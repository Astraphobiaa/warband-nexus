--[[
    Warband Nexus - Profession Service
    Lightweight service for profession-related data collection and persistence.

    WoW RETAIL API LIMITATION (no way around it):
    - Concentration, knowledge are ONLY available while the profession window is open (C_TradeSkillUI context).
    - GetProfessionInfoBySkillLineID(skillLineID) can return skill level without the window
      ONLY after the user has opened that profession at least once per session (data "validation").
    - There is no API to fetch full profession data in the background; OpenTradeSkill() requires
      a hardware event and opens the UI. So we MUST collect on TRADE_SKILL_SHOW and persist.

    Responsibilities:
    - On TRADE_SKILL_SHOW: collect concentration, knowledge, expansion skill levels; persist to db.global.characters[charKey].
    - Provide APIs for UI/tooltip (GetAllConcentrationData, GetKnowledgeData, etc.).
    - Install recipe selection hook for companion window (deferred until ProfessionsFrame exists).

    Data flow:
    TRADE_SKILL_SHOW → RunAllCollectors (0.6s + 1.2s retry) → db.global → SendMessage(WN_*_UPDATED)
    UI reads from same db.global.characters; expansion filter in UI filters skill/concentration/knowledge display.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local function IsCurrentCharacterTracked()
    return ns.CharacterService and WarbandNexus and ns.CharacterService:IsCharacterTracked(WarbandNexus)
end

-- ============================================================================
-- STATE
-- ============================================================================

local hooksInstalled = false          -- Guard: install SchematicForm hook only once
local PROFESSION_SCHEMA_VERSION = 1

-- Forward declaration used by equipment collection
local GetCurrentProfessionName

-- Resolve potentially secret API values into usable strings via FontString extraction
-- In WoW 11.0+ (TWW), many API return values are "secret values" that can be displayed
-- on FontStrings but cannot be read as plain strings by addons. This function extracts
-- the displayed text from a hidden FontString to get a usable string.
local _resolverFS = nil
local function ResolveAPIString(value)
    if not value then return nil end
    if type(value) == "string" and value ~= "" then return value end
    -- Secret value: extract via FontString (SetText accepts secret values, GetText returns plain string)
    if issecretvalue and issecretvalue(value) then
        if not _resolverFS then
            _resolverFS = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            _resolverFS:Hide()
        end
        _resolverFS:SetText(value)
        local text = _resolverFS:GetText()
        if text and type(text) == "string" and text ~= "" then
            return text
        end
        return nil
    end
    -- Non-nil, non-string, non-secret: try tostring
    local s = tostring(value)
    if s and s ~= "" and s ~= "nil" then return s end
    return nil
end

-- Robustly resolve a spell name from spellID, handling secret values and API changes
local function ResolveSpellName(spellID)
    if not spellID or spellID <= 0 then return nil end
    -- Method 1: C_Spell.GetSpellName (TWW 11.0+)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok and name then
            local resolved = ResolveAPIString(name)
            if resolved then return resolved end
        end
    end
    -- Method 2: Legacy GetSpellInfo
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, spellID)
        if ok and name then
            local resolved = ResolveAPIString(name)
            if resolved then return resolved end
        end
    end
    -- Method 3: Parse name from spell link (links are plain strings)
    if C_Spell and C_Spell.GetSpellLink then
        local ok, link = pcall(C_Spell.GetSpellLink, spellID)
        if ok and link and type(link) == "string" then
            local parsed = link:match("%[(.-)%]")
            if parsed and parsed ~= "" then return parsed end
        end
    end
    if GetSpellLink then
        local ok, link = pcall(GetSpellLink, spellID)
        if ok and link and type(link) == "string" then
            local parsed = link:match("%[(.-)%]")
            if parsed and parsed ~= "" then return parsed end
        end
    end
    return nil
end

-- Safe string extraction from API values — uses ResolveAPIString for secret value support
local function SafeAPIString(value)
    if not value then return nil end
    if type(value) == "string" and value ~= "" then return value end
    -- Try to resolve secret values via FontString extraction
    if issecretvalue and issecretvalue(value) then
        return ResolveAPIString(value)
    end
    if type(value) ~= "string" then return nil end
    return value
end

local function EnsureProfessionDataSchema(charData)
    if type(charData.professionData) ~= "table" then
        charData.professionData = {
            schemaVersion = PROFESSION_SCHEMA_VERSION,
            bySkillLine = {},   -- [skillLineID] = bucket
            byProfession = {},  -- [professionName] = { [skillLineID] = true }
            lastUpdate = time(),
        }
    end

    local pd = charData.professionData
    pd.schemaVersion = PROFESSION_SCHEMA_VERSION
    if type(pd.bySkillLine) ~= "table" then pd.bySkillLine = {} end
    if type(pd.byProfession) ~= "table" then pd.byProfession = {} end
    pd.lastUpdate = time()
    return pd
end

local function EnsureSkillLineBucket(charData, skillLineID, professionName, expansionName)
    if not skillLineID or skillLineID <= 0 then return nil, nil end
    local pd = EnsureProfessionDataSchema(charData)

    local bucket = pd.bySkillLine[skillLineID]
    if type(bucket) ~= "table" then
        bucket = {
            skillLineID = skillLineID,
            professionName = nil,
            expansionName = nil,
            lastUpdate = time(),
        }
        pd.bySkillLine[skillLineID] = bucket
    end

    local safeProfessionName = SafeAPIString(professionName)
    local safeExpansionName = SafeAPIString(expansionName)

    if safeProfessionName and safeProfessionName ~= "" then
        bucket.professionName = safeProfessionName
        if type(pd.byProfession[safeProfessionName]) ~= "table" then
            pd.byProfession[safeProfessionName] = {}
        end
        pd.byProfession[safeProfessionName][skillLineID] = true
    end
    if safeExpansionName and safeExpansionName ~= "" then
        bucket.expansionName = safeExpansionName
    end

    bucket.lastUpdate = time()
    return bucket, pd
end

-- ============================================================================
-- CONCENTRATION DATA COLLECTION
-- ============================================================================

--[[
    Collect concentration data for the current character's open profession.
    Called on TRADE_SKILL_SHOW after a short delay to ensure API readiness.
    
    Stores per profession:
    {
        current     = number,   -- Current concentration points
        max         = number,   -- Maximum concentration
        currencyID  = number,   -- Blizzard currency ID
        lastUpdate  = number,   -- time() when recorded
    }
]]
local function CollectConcentrationData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI then return end
    if not C_TradeSkillUI.GetConcentrationCurrencyID then
        if WarbandNexus.Debug then
            WarbandNexus:Debug("[Concentration] GetConcentrationCurrencyID API not available")
        end
        return
    end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    -- Initialize concentration table if missing
    if not charData.concentration then
        charData.concentration = {}
    end

    -- ----------------------------------------------------------------
    -- Use C_TradeSkillUI.GetProfessionChildSkillLineID() to get the
    -- current child skillLineID, then query concentration via
    -- C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID).
    --
    -- ProfessionInfo tables do NOT contain a skillLineID field,
    -- so we must use the dedicated API to retrieve it.
    -- ----------------------------------------------------------------

    -- Get the base profession name (e.g. "Tailoring") for the storage key
    local baseProfName = nil
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local baseOk, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if baseOk and baseInfo then
            baseProfName = baseInfo.professionName
        end
    end

    -- Method 1: GetProfessionChildSkillLineID — returns the currently active child skill line
    local skillLineID = nil
    if C_TradeSkillUI.GetProfessionChildSkillLineID then
        local slOk, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if slOk and slID and slID > 0 then
            skillLineID = slID
        end
    end

    if WarbandNexus.Debug then
        WarbandNexus:Debug("[Concentration] childSkillLineID=" .. tostring(skillLineID) .. " baseProfName=" .. tostring(baseProfName))
    end

    -- Build skill-line-to-try list with per-entry profession tracking.
    -- Each entry: { id = number, profName = string|nil }
    -- Method 1 uses baseProfName (from the open window).
    -- Method 2 entries carry their own profName from discoveredSkillLines.
    local skillLinesToTry = {}
    local skillLineSeen = {}
    if skillLineID then
        skillLinesToTry[1] = { id = skillLineID, profName = baseProfName }
        skillLineSeen[skillLineID] = true
    end
    if charData.discoveredSkillLines then
        for profName, lines in pairs(charData.discoveredSkillLines) do
            for _, sl in ipairs(lines) do
                local id = (type(sl) == "table" and sl.id) or sl
                if id and not skillLineSeen[id] then
                    skillLineSeen[id] = true
                    skillLinesToTry[#skillLinesToTry + 1] = { id = id, profName = profName }
                end
            end
        end
    end

    -- First entry = current open profession window; always update that one.
    -- Later entries = from discoveredSkillLines; only set if not already set (avoid overwriting
    -- with wrong expansion or swapping between professions when opening different windows).
    local found = 0
    for idx, entry in ipairs(skillLinesToTry) do
        local slID = entry.id
        local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, slID)

        if WarbandNexus.Debug then
            WarbandNexus:Debug("[Concentration] Trying skillLineID=" .. tostring(slID) .. " -> currencyID=" .. tostring(currencyID))
        end

        if concOk and currencyID and currencyID > 0 then
            local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                local professionName = SafeAPIString(entry.profName)
                local expansionName = nil
                local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slID)
                if piOk and profInfo then
                    professionName = professionName or SafeAPIString(profInfo.parentProfessionName)
                    expansionName = SafeAPIString(profInfo.professionName)
                end
                professionName = professionName or ("Profession_" .. slID)

                -- Store by skillLineID so content (expansion) is kept separate
                local isCurrentWindow = (idx == 1)
                local alreadyHave = charData.concentration[slID] and charData.concentration[slID].currencyID
                if isCurrentWindow or not alreadyHave then
                    charData.concentration[slID] = {
                        current        = currInfo.quantity or 0,
                        max            = currInfo.maxQuantity or 0,
                        currencyID     = currencyID,
                        skillLineID    = slID,
                        professionName = professionName,
                        expansionName  = expansionName,
                        lastUpdate     = time(),
                    }
                    local bucket = EnsureSkillLineBucket(charData, slID, professionName, expansionName)
                    if bucket then
                        bucket.concentration = {
                            current = currInfo.quantity or 0,
                            max = currInfo.maxQuantity or 0,
                            currencyID = currencyID,
                            lastUpdate = time(),
                        }
                    end
                    found = found + 1
                    if WarbandNexus.Debug then
                        WarbandNexus:Debug("[Concentration] Stored: skillLineID=" .. tostring(slID) .. " " .. tostring(professionName) .. " = "
                            .. tostring(currInfo.quantity) .. "/" .. tostring(currInfo.maxQuantity))
                    end
                end
            end
        end
    end

    if WarbandNexus.Debug then
        WarbandNexus:Debug("[Concentration] Collection complete, found " .. found .. " concentration currencies")
    end

    -- Rebuild reverse lookup map for real-time currency matching
    if WarbandNexus.RebuildConcentrationCurrencyMap then
        WarbandNexus:RebuildConcentrationCurrencyMap()
    end

    -- Fire event for consumers (tooltip, UI)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CONCENTRATION_UPDATED", charKey)
    end
end

-- ============================================================================
-- PROFESSION KNOWLEDGE DATA COLLECTION (C_ProfSpecs API)
-- ============================================================================

--[[
    Collect profession specialization knowledge data using the C_Traits API chain.
    
    Blizzard's own approach (from Blizzard_ProfessionsSpecializations.lua):
    1. C_ProfSpecs.GetConfigIDForSkillLine(skillLineID)    → configID
    2. C_ProfSpecs.GetSpecTabIDsForSkillLine(skillLineID)  → tab/tree IDs
    3. C_ProfSpecs.GetTabInfo(tabID).rootNodeID             → rootNodeID
    4. C_ProfSpecs.GetSpendCurrencyForPath(rootNodeID)      → traitCurrencyID
    5. C_Traits.GetTreeCurrencyInfo(configID, treeID, false) → { traitCurrencyID, quantity, spent, maxQuantity }
    6. C_Traits.GetTraitCurrencyInfo(traitCurrencyID)       → (_, _, currencyTypesID) for display
    
    quantity = UNSPENT points, spent = already spent, maxQuantity = max earnable.
    
    @param skillLineID number - Expansion-specific skill line (e.g. "Khaz Algar Tailoring")
    @param profName string - Profession name for storage key
    @return table|nil - Knowledge data table or nil
]]
local function CollectKnowledgeForSkillLine(skillLineID, profName)
    if not C_ProfSpecs or not C_Traits then return nil end
    if not skillLineID or skillLineID <= 0 then return nil end

    -- Step 1: Get the trait config ID
    local configID = nil
    if C_ProfSpecs.GetConfigIDForSkillLine then
        local ok, cid = pcall(C_ProfSpecs.GetConfigIDForSkillLine, skillLineID)
        if ok and cid and cid > 0 then
            configID = cid
        end
    end
    if not configID then return nil end

    -- Step 2: Get specialization tab IDs (these are also tree IDs)
    local tabIDs = nil
    if C_ProfSpecs.GetSpecTabIDsForSkillLine then
        local ok, ids = pcall(C_ProfSpecs.GetSpecTabIDsForSkillLine, skillLineID)
        if ok and ids and #ids > 0 then
            tabIDs = ids
        end
    end
    if not tabIDs then return nil end

    -- Step 3-6: For each tab, get knowledge currency via C_Traits
    local unspentTotal = 0
    local spentTotal = 0
    local maxTotal = 0
    local estimatedMaxTotal = 0
    local currencyName = ""
    local currencyIcon = nil
    local specTabs = {}
    local foundCurrency = false

    local function EstimateTreeMaxFromNodes(treeID, seenNodes)
        if not treeID or treeID <= 0 then return 0, {} end
        if not C_Traits or not C_Traits.GetTreeNodes or not C_Traits.GetNodeInfo then return 0, {} end
        local ok, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if not ok or not nodeIDs or #nodeIDs == 0 then return 0, {} end

        local total = 0
        local nodeDetails = {}
        for n = 1, #nodeIDs do
            local nodeID = nodeIDs[n]
            local isNewForMax = not seenNodes or not seenNodes[nodeID]
            if seenNodes then
                seenNodes[nodeID] = true
            end
            local nOk, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
            if nOk and nodeInfo then
                local maxRanks = nodeInfo.maxRanks
                if (not maxRanks or maxRanks <= 0) and nodeInfo.activeEntry and type(nodeInfo.activeEntry.maxRanks) == "number" then
                    maxRanks = nodeInfo.activeEntry.maxRanks
                end
                if (not maxRanks or maxRanks <= 0) and nodeInfo.entryIDs and C_Traits.GetEntryInfo then
                    local best = 0
                    for e = 1, #nodeInfo.entryIDs do
                        local entryID = nodeInfo.entryIDs[e]
                        local eOk, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
                        if eOk and entryInfo and type(entryInfo.maxRanks) == "number" and entryInfo.maxRanks > best then
                            best = entryInfo.maxRanks
                        end
                    end
                    maxRanks = best
                end

                -- Resolve node name via definition chain: entryID -> definitionID -> overrideName / spellID
                -- Uses ResolveAPIString to handle Blizzard secret values (TWW 11.0+)
                -- Try all entryIDs (active first, then rest) — Midnight API may return name from alternate entry
                local nodeName = nil
                local entryIDsToTry = {}
                if nodeInfo.activeEntry and nodeInfo.activeEntry.entryID then
                    entryIDsToTry[#entryIDsToTry + 1] = nodeInfo.activeEntry.entryID
                end
                if nodeInfo.entryIDs then
                    for e = 1, #nodeInfo.entryIDs do
                        local eid = nodeInfo.entryIDs[e]
                        if eid and (not nodeInfo.activeEntry or eid ~= nodeInfo.activeEntry.entryID) then
                            entryIDsToTry[#entryIDsToTry + 1] = eid
                        end
                    end
                end
                for ei = 1, #entryIDsToTry do
                    if nodeName then break end
                    local resolveEntryID = entryIDsToTry[ei]
                    if resolveEntryID and C_Traits.GetEntryInfo and C_Traits.GetDefinitionInfo then
                        local eOk2, entryInf = pcall(C_Traits.GetEntryInfo, configID, resolveEntryID)
                        if eOk2 and entryInf and entryInf.definitionID then
                            -- Entry-level name can exist for some profession trees
                            if entryInf.name then
                                nodeName = ResolveAPIString(entryInf.name)
                            end
                            local dOk, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInf.definitionID)
                            if dOk and defInfo then
                                if not nodeName then
                                    nodeName = ResolveAPIString(defInfo.overrideName)
                                end
                                if not nodeName and defInfo.name then
                                    nodeName = ResolveAPIString(defInfo.name)
                                end
                                if not nodeName and defInfo.spellID then
                                    nodeName = ResolveSpellName(defInfo.spellID)
                                end
                                -- overriddenSpellID can hold the display spell for some profession nodes
                                if not nodeName and defInfo.overriddenSpellID and defInfo.overriddenSpellID > 0 then
                                    nodeName = ResolveSpellName(defInfo.overriddenSpellID)
                                end
                            end
                        end
                    end
                end
                -- Additional fallback path for client variants exposing nodeInfo.name directly.
                if not nodeName and nodeInfo.name then
                    nodeName = ResolveAPIString(nodeInfo.name)
                end

                local currentRank = nodeInfo.currentRank or nodeInfo.activeRank or 0

                -- Collect edge targets for tree layout
                local edgeTargets = nil
                if nodeInfo.visibleEdges and #nodeInfo.visibleEdges > 0 then
                    edgeTargets = {}
                    for e = 1, #nodeInfo.visibleEdges do
                        local edge = nodeInfo.visibleEdges[e]
                        if edge and edge.targetNode then
                            edgeTargets[#edgeTargets + 1] = edge.targetNode
                        end
                    end
                    if #edgeTargets == 0 then edgeTargets = nil end
                end

                if isNewForMax and type(maxRanks) == "number" and maxRanks > 0 then
                    total = total + maxRanks
                end

                -- Store node detail with position data for tree layout
                if type(maxRanks) == "number" and maxRanks > 0 then
                    local hasName = (nodeName ~= nil)
                    nodeDetails[#nodeDetails + 1] = {
                        name = nodeName or (currentRank > 0 and "Unknown Node" or nil),
                        hasRealName = hasName,
                        currentRank = currentRank,
                        maxRanks = maxRanks,
                        nodeID = nodeID,
                        posX = nodeInfo.posX or 0,
                        posY = nodeInfo.posY or 0,
                        edges = edgeTargets,
                    }
                end
            end
        end
        return total, nodeDetails
    end

    local seenKnowledgeNodes = {}
    for i = 1, #tabIDs do
        local tabID = tabIDs[i]
        local tabName = ""
        local tabState = ""
        local rootNodeID = nil

        -- Get tab info (name + rootNodeID)
        if C_ProfSpecs.GetTabInfo then
            local tiOk, tabInfo = pcall(C_ProfSpecs.GetTabInfo, tabID)
            if tiOk and tabInfo then
                tabName = tabInfo.name or ""
                rootNodeID = tabInfo.rootNodeID
            end
        end

        -- Get tab state
        if C_ProfSpecs.GetStateForTab then
            local stOk, state = pcall(C_ProfSpecs.GetStateForTab, tabID, configID)
            if stOk and state then
                tabState = tostring(state)
            end
        end

        local treeMax, treeNodeDetails = EstimateTreeMaxFromNodes(tabID, seenKnowledgeNodes)

        specTabs[#specTabs + 1] = {
            tabID = tabID,
            name  = tabName,
            state = tabState,
            nodes = treeNodeDetails,
        }

        if treeMax and treeMax > 0 then
            estimatedMaxTotal = estimatedMaxTotal + treeMax
        end

        -- Get the spend currency for this tab's root path
        if rootNodeID and C_ProfSpecs.GetSpendCurrencyForPath then
            local scOk, spendCurrency = pcall(C_ProfSpecs.GetSpendCurrencyForPath, rootNodeID)
            if scOk and spendCurrency then
                -- Get tree currency info from C_Traits
                if C_Traits.GetTreeCurrencyInfo then
                    local tcOk, treeCurrencies = pcall(C_Traits.GetTreeCurrencyInfo, configID, tabID, false)
                    if tcOk and treeCurrencies then
                        for _, ci in ipairs(treeCurrencies) do
                            if ci.traitCurrencyID == spendCurrency then
                                -- Only count from the FIRST tab that has this currency
                                -- (all tabs share the same knowledge pool)
                                if not foundCurrency then
                                    unspentTotal = ci.quantity or 0
                                    spentTotal = ci.spent or 0
                                    maxTotal = ci.maxQuantity or 0
                                    foundCurrency = true

                                    -- Get display info (name, icon) via currencyTypesID
                                    if C_Traits.GetTraitCurrencyInfo then
                                        local ctOk, _, _, currencyTypesID = pcall(C_Traits.GetTraitCurrencyInfo, spendCurrency)
                                        if ctOk and currencyTypesID and currencyTypesID > 0 then
                                            local ciOk, cInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyTypesID)
                                            if ciOk and cInfo then
                                                currencyName = cInfo.name or ""
                                                currencyIcon = cInfo.iconFileID
                                            end
                                        end
                                    end
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    if not foundCurrency then return nil end

    -- If API returns 0 max, fall back to node-based max and finally to (spent+unspent).
    -- Keep max at least current progress to avoid "Current > Max" displays.
    local effectiveMax = maxTotal
    if (not effectiveMax or effectiveMax <= 0) and estimatedMaxTotal > 0 then
        effectiveMax = estimatedMaxTotal
    end
    if (not effectiveMax or effectiveMax <= 0) and (unspentTotal + spentTotal) > 0 then
        effectiveMax = unspentTotal + spentTotal
    end
    if effectiveMax and effectiveMax > 0 and effectiveMax < (unspentTotal + spentTotal) then
        effectiveMax = unspentTotal + spentTotal
    end

    local result = {
        skillLineID      = skillLineID,
        hasUnspentPoints = (unspentTotal > 0),
        unspentPoints    = unspentTotal,
        spentPoints      = spentTotal,
        maxPoints        = effectiveMax,
        currencyName     = currencyName,
        currencyIcon     = currencyIcon,
        specTabs         = specTabs,
        lastUpdate       = time(),
    }

    if WarbandNexus and WarbandNexus.Debug then
        WarbandNexus:Debug("[Knowledge] " .. (profName or "?")
            .. ": unspent=" .. unspentTotal
            .. ", spent=" .. spentTotal
            .. ", max=" .. maxTotal
            .. ", name=" .. currencyName)
    end

    return result
end

--[[
    Collect knowledge data for the currently open profession.
    Called on TRADE_SKILL_SHOW alongside other collectors.
]]
local function CollectKnowledgeData()
    if not WarbandNexus or not WarbandNexus.db then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    if not charData.knowledgeData then
        charData.knowledgeData = {}
    end

    -- Get the active child skillLineID
    local skillLineID = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID then
        local ok, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if ok and slID and slID > 0 then
            skillLineID = slID
        end
    end
    if not skillLineID then return end

    local profName = nil
    local expansionName = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and profInfo then
            profName = SafeAPIString(profInfo.parentProfessionName) or SafeAPIString(profInfo.professionName)
            expansionName = SafeAPIString(profInfo.professionName)
        end
    end
    if not profName and C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then profName = SafeAPIString(baseInfo.professionName) end
    end
    profName = profName or ("Profession_" .. skillLineID)

    local result = CollectKnowledgeForSkillLine(skillLineID, profName)
    if result then
        result.professionName = profName
        result.expansionName = expansionName
        charData.knowledgeData[skillLineID] = result
        -- Clean up legacy profName-keyed entry to prevent stale data
        if profName and charData.knowledgeData[profName] then
            charData.knowledgeData[profName] = nil
        end
        local bucket = EnsureSkillLineBucket(charData, skillLineID, profName, expansionName)
        if bucket then
            bucket.knowledge = {
                hasUnspentPoints = result.hasUnspentPoints or false,
                unspentPoints = result.unspentPoints or 0,
                spentPoints = result.spentPoints or 0,
                maxPoints = result.maxPoints or 0,
                currencyName = SafeAPIString(result.currencyName) or "",
                currencyIcon = result.currencyIcon,
                specTabs = result.specTabs,
                lastUpdate = result.lastUpdate or time(),
            }
        end
    end

    -- Fire event for consumers
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_KNOWLEDGE_UPDATED", charKey)
    end
end

-- ============================================================================
-- PROFESSION EQUIPMENT DATA COLLECTION
-- ============================================================================

--[[
    Collect profession equipment data from equipped items.
    Each profession has its own dedicated equipment slots returned by C_TradeSkillUI.GetProfessionSlots(Enum.Profession).

    Storage: charData.professionEquipment[professionName] = { tool?, accessory1?, accessory2?, lastUpdate }
    Legacy:  if professionEquipment has .tool (flat table), UI treats it as fallback for any profession.
]]

local NormalizeProfessionNameForEquipment

-- Profession name → Enum.Profession value (used by C_TradeSkillUI.GetProfessionSlots).
local PROFESSION_ENUM = {
    ["Blacksmithing"] = 1,  ["Leatherworking"] = 2, ["Alchemy"]     = 3,
    ["Herbalism"]     = 4,  ["Cooking"]        = 5, ["Mining"]       = 6,
    ["Tailoring"]     = 7,  ["Engineering"]    = 8, ["Enchanting"]   = 9,
    ["Fishing"]       = 10, ["Skinning"]       = 11,["Jewelcrafting"] = 12,
    ["Inscription"]   = 13,
}

-- Base skillLine → Enum.Profession (locale-independent).
local SKILLLINE_TO_ENUM = {
    [164] = 1, [165] = 2, [171] = 3, [182] = 4, [185] = 5,
    [186] = 6, [197] = 7, [202] = 8, [333] = 9, [356] = 10,
    [393] = 11,[755] = 12,[773] = 13,
}

-- Ask the game for the actual equipment slot IDs for a profession.
-- Returns a plain array like {20,21,22} or {23,24,25} — game decides the mapping.
local function GetProfessionSlotIDs(profName, skillLine)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionSlots then return nil end

    local normalized = NormalizeProfessionNameForEquipment(profName)
    local profEnum = (skillLine and SKILLLINE_TO_ENUM[skillLine])
                  or (normalized and PROFESSION_ENUM[normalized])
    if not profEnum then return nil end

    local ok, slotIDs = pcall(C_TradeSkillUI.GetProfessionSlots, profEnum)
    if ok and slotIDs and #slotIDs > 0 then return slotIDs end
    return nil
end

-- Collect equipment from an array of inventory slot IDs.
-- Returns { tool?, accessory1?, accessory2?, lastUpdate } or nil if all slots empty.
local function CollectEquipmentFromSlots(slotIDs)
    if not slotIDs or #slotIDs == 0 then return nil end
    local slotKeys = { "tool", "accessory1", "accessory2" }
    local equipment = { lastUpdate = time() }
    local hasAny = false
    for i, slotID in ipairs(slotIDs) do
        local key = slotKeys[i] or ("slot" .. i)
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemLink = GetInventoryItemLink("player", slotID)
            local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID) or nil
            local itemName = itemLink and itemLink:match("%[(.-)%]")
            equipment[key] = {
                itemID = itemID, itemLink = itemLink, icon = icon,
                name = itemName or ("Item " .. itemID),
            }
            hasAny = true
        end
    end
    return hasAny and equipment or nil
end

-- Ensure the professionEquipment table exists and is per-profession keyed.
local function EnsureEquipmentTable(charData)
    if not charData.professionEquipment or type(charData.professionEquipment) ~= "table" then
        charData.professionEquipment = {}
    elseif rawget(charData.professionEquipment, "tool") then
        charData.professionEquipment = { _legacy = charData.professionEquipment }
    end
end

-- Store equipment under the normalized profession name.
local function StoreEquipment(charData, profName, equipment)
    local key = NormalizeProfessionNameForEquipment(profName) or profName
    charData.professionEquipment[key] = equipment or { lastUpdate = time() }
end

--[[
    Collect equipment for the CURRENTLY OPEN profession window.
    Uses C_TradeSkillUI.GetProfessionSlots to get the correct slot IDs from the game.
]]
local function CollectEquipmentDataForCurrentProfession()
    if not WarbandNexus or not WarbandNexus.db then return end
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    local profName = GetCurrentProfessionName()
    if not profName or profName == "" then return end

    EnsureEquipmentTable(charData)

    -- Get slot IDs for the currently open profession via its enum
    local slotIDs = GetProfessionSlotIDs(profName)

    -- If API unavailable, try to get skillLine from GetProfessions for a second attempt
    if not slotIDs then
        local p1, p2, _, pFish, pCook = GetProfessions()
        local normalized = NormalizeProfessionNameForEquipment(profName)
        for _, idx in ipairs({ p1, p2, pCook, pFish }) do
            if idx then
                local n, _, _, _, _, _, sl = GetProfessionInfo(idx)
                if n and NormalizeProfessionNameForEquipment(n) == normalized then
                    slotIDs = GetProfessionSlotIDs(n, sl)
                    break
                end
            end
        end
    end
    if not slotIDs then return end

    local equipment = CollectEquipmentFromSlots(slotIDs)
    StoreEquipment(charData, profName, equipment)

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_PROFESSION_EQUIPMENT_UPDATED", charKey)
    end
end

--[[
    Collect equipment for ALL player professions.
    Uses C_TradeSkillUI.GetProfessionSlots per profession — the game tells us
    which inventory slots belong to which profession. No hardcoded assumptions.
]]
local function CollectEquipmentByDetection()
    if not WarbandNexus or not WarbandNexus.db then return end
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    EnsureEquipmentTable(charData)

    local prof1, prof2, _, fish, cook = GetProfessions()
    for _, profIndex in ipairs({ prof1, prof2, cook, fish }) do
        if profIndex then
            local profName, _, _, _, _, _, skillLine = GetProfessionInfo(profIndex)
            if profName and profName ~= "" then
                local slotIDs = GetProfessionSlotIDs(profName, skillLine)
                if slotIDs then
                    local equipment = CollectEquipmentFromSlots(slotIDs)
                    StoreEquipment(charData, profName, equipment)
                end
            end
        end
    end

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_PROFESSION_EQUIPMENT_UPDATED", charKey)
    end
end

--[[
    Event handler for PLAYER_EQUIPMENT_CHANGED.
    Updates current profession if window is open; detects profession from equipped items.
]]
function WarbandNexus:OnEquipmentChanged(slot)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if slot and slot >= 20 and slot <= 30 then
        C_Timer.After(0.2, function()
            if not WarbandNexus then return end
            pcall(CollectEquipmentDataForCurrentProfession)
            pcall(CollectEquipmentByDetection)
        end)
    end
end

--[[
    On login: detect profession equipment using GetSkillLineForGear API.
    Stores equipment per-profession without needing to open the profession window.
]]
function WarbandNexus:CollectEquipmentOnLogin()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    C_Timer.After(2, function()
        if not WarbandNexus or not IsCurrentCharacterTracked() then return end
        pcall(CollectEquipmentDataForCurrentProfession)
        pcall(CollectEquipmentByDetection)
    end)
end

-- ============================================================================
-- RECIPE SELECTION HOOK
-- ============================================================================

--[[
    Install a secure hook on ProfessionsFrame.CraftingPage.SchematicForm:Init().
    Deferred until TRADE_SKILL_SHOW fires (frame is load-on-demand).
    The hook fires WN_RECIPE_SELECTED with recipeInfo for the companion window.
]]
local function InstallRecipeHook()
    if hooksInstalled then return end

    -- ProfessionsFrame is load-on-demand; must exist by now (TRADE_SKILL_SHOW fired)
    if not ProfessionsFrame then return end
    if not ProfessionsFrame.CraftingPage then return end
    if not ProfessionsFrame.CraftingPage.SchematicForm then return end

    local ok, err = pcall(hooksecurefunc, ProfessionsFrame.CraftingPage.SchematicForm, "Init", function(self, recipeInfo)
        if not recipeInfo then return end
        if WarbandNexus and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_RECIPE_SELECTED", recipeInfo)
        end
    end)

    if ok then
        hooksInstalled = true
        if WarbandNexus.Debug then
            WarbandNexus:Debug("[ProfessionService] SchematicForm:Init hook installed")
        end
    else
        if WarbandNexus.Debug then
            WarbandNexus:Debug("[ProfessionService] Hook install failed: " .. tostring(err))
        end
    end
end

-- ============================================================================
-- EXPANSION SUB-PROFESSION COLLECTION
-- ============================================================================

--[[
    Collect expansion sub-profession data for the CURRENTLY OPEN profession.
    Uses GetChildProfessionInfos (only works when profession frame is open).
    Called on TRADE_SKILL_SHOW. This is the AUTHORITATIVE source — returns
    all expansion child skill lines with real skill line IDs.
]]
local function CollectExpansionFromOpenProfession()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetChildProfessionInfos then return nil, nil end

    local ok, childInfos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
    if not ok or not childInfos or #childInfos == 0 then return nil, nil end

    -- Get parent profession name
    local parentName = nil
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local baseOk, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        local baseName = baseOk and baseInfo and SafeAPIString(baseInfo.professionName) or nil
        if baseName and baseName ~= "" then
            parentName = baseName
        end
    end
    if not parentName and childInfos[1] then
        parentName = SafeAPIString(childInfos[1].parentProfessionName)
    end

    local expansions = {}
    for i = 1, #childInfos do
        local info = childInfos[i]
        if info then
            local skillLevel = info.skillLevel or 0
            local maxSkillLevel = info.maxSkillLevel or 0
            local expansionName = SafeAPIString(info.professionName) or ("Expansion " .. i)
            local skillLineID = info.skillLineID or info.professionID

            -- Get detailed skill info if skillLineID is available
            if skillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
                if profOk and profInfo then
                    skillLevel = profInfo.skillLevel or skillLevel
                    maxSkillLevel = profInfo.maxSkillLevel or maxSkillLevel
                    local safeExpName = SafeAPIString(profInfo.professionName)
                    if safeExpName and safeExpName ~= "" then
                        expansionName = safeExpName
                    end
                end
            end

            expansions[#expansions + 1] = {
                name          = expansionName,
                skillLevel    = skillLevel,
                maxSkillLevel = maxSkillLevel,
                skillLineID   = skillLineID,
            }
        end
    end

    return parentName, expansions
end

--[[
    Collect expansion sub-profession data.
    
    Strategy:
    1. When called from TRADE_SKILL_SHOW: use GetChildProfessionInfos for the
       currently open profession (authoritative, returns all expansions).
    2. On login: refresh skill levels for ALL previously discovered skillLineIDs
       using GetProfessionInfoBySkillLineID (works without profession frame open).
    
    Data is stored in charData.professionExpansions[professionName] and
    discovered skillLineIDs persist across sessions in charData.discoveredSkillLines.
]]
local function CollectAllExpansionProfessions(fromTradeSkillShow)
    if not WarbandNexus or not WarbandNexus.db then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    if not charData.professionExpansions then
        charData.professionExpansions = {}
    end
    if not charData.discoveredSkillLines then
        charData.discoveredSkillLines = {}  -- { [profName] = { { id=N, name=S }, ... } }
    end

    -- === PHASE 1: If profession frame is open, collect authoritative data ===
    if fromTradeSkillShow then
        local parentName, expansions = CollectExpansionFromOpenProfession()
        if parentName and expansions and #expansions > 0 then
            charData.professionExpansions[parentName] = expansions
            EnsureProfessionDataSchema(charData)

            -- Persist discovered skillLineIDs for future login refreshes
            local discovered = {}
            for _, exp in ipairs(expansions) do
                if exp.skillLineID then
                    discovered[#discovered + 1] = {
                        id   = exp.skillLineID,
                        name = exp.name,
                    }
                    local bucket = EnsureSkillLineBucket(charData, exp.skillLineID, parentName, exp.name)
                    if bucket then
                        bucket.skill = {
                            current = exp.skillLevel or 0,
                            max = exp.maxSkillLevel or 0,
                            lastUpdate = time(),
                        }
                    end
                end
            end
            if #discovered > 0 then
                charData.discoveredSkillLines[parentName] = discovered
            end
        end
    end

    -- === PHASE 2: Refresh ALL previously discovered skillLineIDs ===
    -- This works on login without the profession frame being open
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionInfoBySkillLineID then return end

    for profName, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            local expansions = {}
            local hasValidSkill = false
            for _, sl in ipairs(skillLines) do
                local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sl.id)
                if profOk and profInfo then
                    local skillLevel    = profInfo.skillLevel or 0
                    local maxSkillLevel = profInfo.maxSkillLevel or 0
                    local updatedName = SafeAPIString(profInfo.professionName) or sl.name
                    expansions[#expansions + 1] = {
                        name          = updatedName,
                        skillLevel    = skillLevel,
                        maxSkillLevel = maxSkillLevel,
                        skillLineID   = sl.id,
                    }
                    local bucket = EnsureSkillLineBucket(charData, sl.id, profName, updatedName)
                    if bucket then
                        bucket.skill = {
                            current = skillLevel,
                            max = maxSkillLevel,
                            lastUpdate = time(),
                        }
                    end
                    -- Track if at least one expansion returned real skill data
                    if maxSkillLevel > 0 then
                        hasValidSkill = true
                    end
                end
            end

            -- Only overwrite if we got entries AND at least one has real skill data.
            -- On login the API can return profInfo with 0/0 skill levels before the
            -- profession system is fully loaded, which would replace good saved data.
            -- If existing data already exists and new data has no valid skills, keep the old data.
            local existingData = charData.professionExpansions[profName]
            if #expansions > 0 and (hasValidSkill or not existingData) then
                charData.professionExpansions[profName] = expansions
            end
        end
    end
end

-- ============================================================================
-- HELPERS
-- ============================================================================

--[[
    Get the parent profession name for the currently open trade skill.
    Returns nil if profession frame is not open or API unavailable.
]]
-- Normalize to base profession name so equipment is keyed consistently (Alchemy, Tailoring, etc.).
NormalizeProfessionNameForEquipment = function(name)
    if not name or name == "" then return name end
    local s = name:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", ""):gsub("^Shadowlands ", "")
    return (s ~= "" and s) or name
end

GetCurrentProfessionName = function()
    if not C_TradeSkillUI then return nil end
    local raw
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo and baseInfo.professionName and baseInfo.professionName ~= "" then
            raw = baseInfo.professionName
        end
    end
    if not raw and C_TradeSkillUI.GetChildProfessionInfos then
        local ok, childInfos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
        if ok and childInfos and #childInfos > 0 and childInfos[1] then
            raw = childInfos[1].parentProfessionName or childInfos[1].professionName
        end
    end
    return raw and NormalizeProfessionNameForEquipment(raw) or nil
end

-- ============================================================================
-- RECIPE SUMMARY DATA COLLECTION
-- ============================================================================

local function IsRecipeFlagTrue(recipeInfo, key1, key2, key3, key4)
    if not recipeInfo then return false end
    local v1 = key1 and recipeInfo[key1]
    local v2 = key2 and recipeInfo[key2]
    local v3 = key3 and recipeInfo[key3]
    local v4 = key4 and recipeInfo[key4]
    if v1 == true or v2 == true or v3 == true or v4 == true then return true end
    if type(v1) == "number" and v1 > 0 then return true end
    if type(v2) == "number" and v2 > 0 then return true end
    if type(v3) == "number" and v3 > 0 then return true end
    if type(v4) == "number" and v4 > 0 then return true end
    return false
end

-- Check whether a recipe category belongs to Midnight by walking parent categories.
-- This keeps recipe counts strictly scoped to Midnight child-skillline content.
local function IsMidnightRecipeCategory(categoryID, cache)
    if not categoryID or categoryID <= 0 then return false end
    cache = cache or {}
    if cache[categoryID] ~= nil then
        return cache[categoryID]
    end
    if not C_TradeSkillUI or not C_TradeSkillUI.GetCategoryInfo then
        cache[categoryID] = false
        return false
    end

    local seen = {}
    local cur = categoryID
    while cur and cur > 0 and not seen[cur] do
        seen[cur] = true
        local ok, catInfo = pcall(C_TradeSkillUI.GetCategoryInfo, cur)
        if not ok or not catInfo then
            break
        end
        local catName = SafeAPIString(catInfo.name)
        if catName and catName:find("Midnight", 1, true) then
            cache[categoryID] = true
            return true
        end
        cur = catInfo.parentCategoryID
    end

    cache[categoryID] = false
    return false
end

-- Midnight weekly profession knowledge (MIDNIGHT_WEEKLY_SOURCES)
-- -----------------------------------------------------------------------------
-- Detection: QuestProgressComplete() = flagged OR in-log complete OR ready for turn-in
--   OR GetInfo(logIndex).isComplete (quest still in journal).
-- Uniques / treasure: quest IDs match wow-professions.com "Treasure Check Macro" per profession
--   (891xx), plus extra one-time/patch IDs where listed (e.g. 93794 Alchemy).
-- Treatise (95127–95138): hidden weekly "consumed treatise" quests. Verified via WeeklyKnowledge addon.
--   Engineering intentionally uses 95138 (not sequential); 95132 unused.
-- Weekly trainer: 93690 Alch, 93691 BS, {93698,93699} Ench, 93692 Eng, 93693 Insc, 93694 JC,
--   93695 LW, 93696 Tailor. Enchanting has two variants (93698 + 93699) instead of "Services Requested".
-- Gathering (weekly drop caps): Enchanting (95048–95053), Herbalism (81425–81430),
--   Mining (88673–88678), Skinning (88534/88549/88537/88536/88530/88529). Verified via WeeklyKnowledge addon.
-- Source model: hardcoded quest IDs + catch-up currency (API).
local MIDNIGHT_WEEKLY_SOURCES = {
    [2906] = {
        catchUpCurrencyID = 3189,
        uniques = {89115, 89117, 89114, 89116, 89113, 89112, 89111, 89118, 93794},
        treatise = {95127},
        weeklyQuest = {93690}, weeklyQuestLimit = 1,
        treasure = {93528, 93529},
    },
    [2907] = {
        catchUpCurrencyID = 3199,
        uniques = {89177, 89178, 89179, 89180, 89181, 89182, 89183, 89184, 93795},
        treatise = {95128},
        weeklyQuest = {93691}, weeklyQuestLimit = 1,
        treasure = {93530, 93531},
    },
    -- Enchanting weekly: two variants — 93698 and 93699 ("A Ray of Sunlight" / Dawn Crystal turn-in to Dolothos).
    -- Unlike other crafting professions, Enchanting has NO "Services Requested" crafting-order weekly.
    -- Gathering: 5x Swirling Arcane Essence (95048-95052, 1 KP each) + 1x Brimming Mana Shard (95053, 4 KP).
    [2909] = {
        catchUpCurrencyID = 3198,
        uniques = {89100, 89101, 89102, 89103, 89104, 89105, 89106, 89107, 92374, 92186},
        treatise = {95129},
        weeklyQuest = {93698, 93699}, weeklyQuestLimit = 1,
        treasure = {93532, 93533},
        gathering = {95048, 95049, 95050, 95051, 95052, 95053},
    },
    [2910] = {
        catchUpCurrencyID = 3197,
        uniques = {89133, 89134, 89135, 89136, 89137, 89138, 89139, 89140, 93796},
        treatise = {95138},
        weeklyQuest = {93692}, weeklyQuestLimit = 1,
        treasure = {93534, 93535},
    },
    -- Herbalism gathering: 5x Thalassian Phoenix Plume (81425-81429, 1 KP each) + 1x Thalassian Phoenix Tail (81430, 4 KP).
    [2912] = {
        catchUpCurrencyID = 3196,
        uniques = {89162, 89161, 89160, 89159, 89158, 89157, 89156, 89155, 93411, 92174},
        treatise = {95130},
        weeklyQuest = {93700, 93702, 93703, 93704}, weeklyQuestLimit = 1,
        gathering = {81425, 81426, 81427, 81428, 81429, 81430},
    },
    [2913] = {
        catchUpCurrencyID = 3195,
        uniques = {89067, 89068, 89069, 89070, 89071, 89072, 89073, 89074, 93412},
        treatise = {95131},
        weeklyQuest = {93693}, weeklyQuestLimit = 1,
        treasure = {93536, 93537},
    },
    [2914] = {
        catchUpCurrencyID = 3194,
        uniques = {89122, 89123, 89124, 89125, 89126, 89127, 89128, 89129, 93222},
        treatise = {95133},
        weeklyQuest = {93694}, weeklyQuestLimit = 1,
        treasure = {93539, 93538},
    },
    [2915] = {
        catchUpCurrencyID = 3193,
        uniques = {89089, 89090, 89091, 89092, 89093, 89094, 89095, 89096, 92371},
        treatise = {95134},
        weeklyQuest = {93695}, weeklyQuestLimit = 1,
        treasure = {93540, 93541},
    },
    -- Mining gathering: 5x Igneous Rock Specimen (88673-88677, 1 KP each) + 1x Septarian Nodule (88678, 3 KP).
    [2916] = {
        catchUpCurrencyID = 3192,
        uniques = {89144, 89145, 89146, 89147, 89148, 89149, 89150, 89151, 92372, 92187},
        treatise = {95135},
        weeklyQuest = {93705, 93706, 93708, 93709}, weeklyQuestLimit = 1,
        gathering = {88673, 88674, 88675, 88676, 88677, 88678},
    },
    -- Skinning gathering: 5x Fine Void-Tempered Hide (88534/88549/88537/88536/88530, 1 KP each) + 1x Mana-Infused Bone (88529, 3 KP).
    [2917] = {
        catchUpCurrencyID = 3191,
        uniques = {89166, 89167, 89168, 89169, 89170, 89171, 89172, 89173, 92373, 92188},
        treatise = {95136},
        weeklyQuest = {93710, 93711, 93712, 93714}, weeklyQuestLimit = 1,
        gathering = {88534, 88549, 88537, 88536, 88530, 88529},
    },
    [2918] = {
        catchUpCurrencyID = 3190,
        uniques = {89078, 89079, 89080, 89081, 89082, 89083, 89084, 89085, 93201},
        treatise = {95137},
        weeklyQuest = {93696}, weeklyQuestLimit = 1,
        treasure = {93542, 93543},
    },
}

local MIDNIGHT_CATCHUP_CURRENCY = {
    [3189] = true, [3199] = true, [3198] = true, [3197] = true, [3196] = true, [3195] = true,
    [3194] = true, [3193] = true, [3192] = true, [3191] = true, [3190] = true,
}

--- True if the quest counts as "done" for UI: flagged complete, in-log complete, or ready to turn in.
--- Matches DailyQuestManager so weekly profession rows update before the flag bit catches up.
local function QuestProgressComplete(questID)
    if not questID or not C_QuestLog then return false end
    if C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done == true then return true end
    end
    if C_QuestLog.IsComplete then
        local ok, done = pcall(C_QuestLog.IsComplete, questID)
        if ok and done == true then return true end
    end
    if C_QuestLog.ReadyForTurnIn then
        local ok, done = pcall(C_QuestLog.ReadyForTurnIn, questID)
        if ok and done == true then return true end
    end
    -- Still in quest log and all objectives done (flag may lag after instance/combat).
    if C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetInfo then
        local ok, logIndex = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
        if ok and logIndex and logIndex > 0 then
            local ok2, info = pcall(C_QuestLog.GetInfo, logIndex)
            if ok2 and type(info) == "table" and info.isComplete then
                return true
            end
        end
    end
    return false
end

local function CountCompletedQuests(questIDs, limit)
    if type(questIDs) ~= "table" or #questIDs == 0 then
        return 0, 0
    end
    local completed = 0
    for i = 1, #questIDs do
        local questID = questIDs[i]
        if questID and QuestProgressComplete(questID) then
            completed = completed + 1
        end
    end
    if limit and limit > 0 then
        return (completed >= limit) and limit or completed, limit
    end
    return completed, #questIDs
end

local function BuildProgressEntry(current, total, source)
    if not total or total <= 0 then
        return { current = 0, total = 0, source = source }
    end
    if not current or current < 0 then current = 0 end
    if current > total then current = total end
    return { current = current, total = total, source = source }
end

local function CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, professionName, expansionName)
    local source = MIDNIGHT_WEEKLY_SOURCES[skillLineID]
    if not source then return false end

    local bucket = EnsureSkillLineBucket(charData, skillLineID, professionName, expansionName or "Midnight")
    if not bucket then return false end

    local recipes = charData.recipes and charData.recipes[skillLineID]
    local firstCraftCurrent = recipes and recipes.firstCraftDoneCount or 0
    local firstCraftTotal = recipes and recipes.firstCraftTotalCount or 0
    -- Legacy fallback: old schema stored "firstCraftCount" against all recipes.
    -- That value mapped to "available first-craft bonus", not done-count.
    if firstCraftTotal <= 0 and recipes and recipes.firstCraftCount and recipes.firstCraftCount > 0 then
        firstCraftCurrent = 0
        firstCraftTotal = recipes.firstCraftCount
    end

    local uniquesCur, uniquesTotal = CountCompletedQuests(source.uniques)
    local treatiseCur, treatiseTotal = CountCompletedQuests(source.treatise)
    local weeklyCur, weeklyTotal = CountCompletedQuests(source.weeklyQuest, source.weeklyQuestLimit or 1)
    local treasureCur, treasureTotal = CountCompletedQuests(source.treasure)
    local gatheringCur, gatheringTotal = CountCompletedQuests(source.gathering)

    local catchUpCurrent, catchUpTotal = 0, 0
    if source.catchUpCurrencyID and source.catchUpCurrencyID > 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, currencyInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, source.catchUpCurrencyID)
        if ok and currencyInfo then
            catchUpCurrent = currencyInfo.quantity or 0
            catchUpTotal = currencyInfo.maxQuantity or 0
        end
    end

    local progress = {
        firstCraft  = BuildProgressEntry(firstCraftCurrent, firstCraftTotal, "api_recipe"),
        uniques     = BuildProgressEntry(uniquesCur, uniquesTotal, "hardcoded_quest"),
        treatise    = BuildProgressEntry(treatiseCur, treatiseTotal, "hardcoded_quest"),
        weeklyQuest = BuildProgressEntry(weeklyCur, weeklyTotal, "hardcoded_quest"),
        treasure    = BuildProgressEntry(treasureCur, treasureTotal, "hardcoded_quest"),
        gathering   = BuildProgressEntry(gatheringCur, gatheringTotal, "hardcoded_quest"),
        catchUp     = BuildProgressEntry(catchUpCurrent, catchUpTotal, "api_currency"),
        lastUpdate = time(),
    }

    bucket.weeklyKnowledge = progress

    -- Legacy compatibility mirror
    charData.professionWeeklyKnowledge = charData.professionWeeklyKnowledge or {}
    charData.professionWeeklyKnowledge[skillLineID] = progress
    return true
end

local function RefreshAllMidnightKnowledgeProgressForCharacter(charData)
    if not charData then return 0 end
    local refreshed = 0
    for skillLineID in pairs(MIDNIGHT_WEEKLY_SOURCES) do
        local hasData = (charData.professionData and charData.professionData.bySkillLine and charData.professionData.bySkillLine[skillLineID])
            or (charData.recipes and charData.recipes[skillLineID])
            or (charData.knowledgeData and charData.knowledgeData[skillLineID])
            or (charData.concentration and charData.concentration[skillLineID])
        if hasData and CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, nil, "Midnight") then
            refreshed = refreshed + 1
        end
    end
    return refreshed
end

local function CollectMidnightKnowledgeProgressData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionChildSkillLineID then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    local slOk, skillLineID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
    if not slOk or not skillLineID or not MIDNIGHT_WEEKLY_SOURCES[skillLineID] then return end

    local professionName, expansionName
    if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if piOk and profInfo then
            professionName = SafeAPIString(profInfo.parentProfessionName) or SafeAPIString(profInfo.professionName)
            expansionName = SafeAPIString(profInfo.professionName)
        end
    end

    if CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, professionName, expansionName) and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_PROFESSION_DATA_UPDATED", charKey)
    end
end

local function CollectRecipeSummaryData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI then return end
    if not C_TradeSkillUI.GetAllRecipeIDs or not C_TradeSkillUI.GetRecipeInfo then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    local skillLineID = nil
    if C_TradeSkillUI.GetProfessionChildSkillLineID then
        local slOk, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if slOk and slID and slID > 0 then
            skillLineID = slID
        end
    end
    if not skillLineID then return end
    -- Only collect and persist recipe summary for Midnight profession tabs (no TWW/DF data).
    if not MIDNIGHT_WEEKLY_SOURCES[skillLineID] or type(MIDNIGHT_WEEKLY_SOURCES[skillLineID]) ~= "table" then
        return
    end

    local allIDsOk, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not allIDsOk or not recipeIDs or #recipeIDs == 0 then return end

    local professionName = nil
    local expansionName = nil
    if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if piOk and profInfo then
            professionName = SafeAPIString(profInfo.parentProfessionName) or SafeAPIString(profInfo.professionName)
            expansionName = SafeAPIString(profInfo.professionName)
        end
    end
    if not professionName and C_TradeSkillUI.GetBaseProfessionInfo then
        local baseOk, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if baseOk and baseInfo then
            professionName = SafeAPIString(baseInfo.professionName)
        end
    end
    professionName = professionName or ("Profession_" .. skillLineID)

    if not charData.recipes then
        charData.recipes = {}
    end

    local totalCount = 0
    local knownCount = 0
    local firstCraftDoneCount = 0
    local firstCraftTotalCount = 0
    local firstCraftAvailableCount = 0
    local skillUpCount = 0
    local knownRecipes = {}
    local recipeList = {}
    local rawRecipeCount = #recipeIDs
    local categoryCache = {}

    for i = 1, #recipeIDs do
        local recipeID = recipeIDs[i]
        local riOk, recipeInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if riOk and recipeInfo then
            -- Filter to Midnight categories only (strict content isolation).
            local categoryID = recipeInfo.categoryID
            if IsMidnightRecipeCategory(categoryID, categoryCache) then
                totalCount = totalCount + 1

                if recipeInfo.learned == true then
                    knownCount = knownCount + 1
                    knownRecipes[recipeID] = true
                end

                -- Store recipe detail for Info window display
                recipeList[#recipeList + 1] = {
                    recipeID = recipeID,
                    name = SafeAPIString(recipeInfo.name) or ("Recipe " .. recipeID),
                    icon = recipeInfo.icon,
                    learned = recipeInfo.learned == true,
                }

                -- First Craft (Current / Total): total = only recipes that actually have a first-craft bonus (matches other addons e.g. 72 not 88).
                -- firstCraft == false on unlearned often means "no bonus", so only count: firstCraft==true (available) or learned+firstCraft==false (consumed).
                if type(recipeInfo.firstCraft) == "boolean" then
                    local hasBonus = (recipeInfo.firstCraft == true) or (recipeInfo.learned == true and recipeInfo.firstCraft == false)
                    if hasBonus then
                        firstCraftTotalCount = firstCraftTotalCount + 1
                        if recipeInfo.learned == true then
                            if recipeInfo.firstCraft == false then
                                firstCraftDoneCount = firstCraftDoneCount + 1
                            else
                                firstCraftAvailableCount = firstCraftAvailableCount + 1
                            end
                        end
                    end
                end
                if IsRecipeFlagTrue(recipeInfo, "canSkillUp", "hasSkillUp", "isSkillUpRecipe", "isRecipePotentiallyDiscoverable") then
                    skillUpCount = skillUpCount + 1
                end
            end
        end
    end

    charData.recipes[skillLineID] = {
        skillLineID = skillLineID,
        professionName = professionName,
        expansionName = expansionName,
        totalCount = totalCount,
        knownCount = knownCount,
        firstCraftCount = firstCraftDoneCount, -- legacy key (now stores done count)
        firstCraftDoneCount = firstCraftDoneCount,
        firstCraftTotalCount = firstCraftTotalCount,
        firstCraftAvailableCount = firstCraftAvailableCount,
        skillUpCount = skillUpCount,
        knownRecipes = knownRecipes,
        recipeList = recipeList,
        lastScan = time(),
    }

    local bucket = EnsureSkillLineBucket(charData, skillLineID, professionName, expansionName)
    if bucket then
        bucket.recipes = {
            totalCount = totalCount,
            knownCount = knownCount,
            firstCraftCount = firstCraftDoneCount, -- legacy key (now stores done count)
            firstCraftDoneCount = firstCraftDoneCount,
            firstCraftTotalCount = firstCraftTotalCount,
            firstCraftAvailableCount = firstCraftAvailableCount,
            skillUpCount = skillUpCount,
            lastUpdate = time(),
        }
    end
    -- Keep weekly knowledge counters in sync after recipe scans.
    CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, professionName, expansionName)

    if WarbandNexus.Debug then
        WarbandNexus:Debug("[Recipes] source=GetAllRecipeIDs raw=" .. tostring(rawRecipeCount)
            .. " filteredMidnight=" .. tostring(totalCount)
            .. " prof=" .. tostring(professionName) .. " slID=" .. tostring(skillLineID)
            .. " known/total=" .. tostring(knownCount) .. "/" .. tostring(totalCount)
            .. " firstCraft(done/total)=" .. tostring(firstCraftDoneCount) .. "/" .. tostring(firstCraftTotalCount)
            .. " available=" .. tostring(firstCraftAvailableCount)
            .. " skillUp=" .. tostring(skillUpCount))
    end
    if WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode and WarbandNexus.Print then
        WarbandNexus:Print("[ProfDebug] " .. tostring(professionName)
            .. " (slID " .. tostring(skillLineID) .. ")"
            .. " raw=" .. tostring(rawRecipeCount)
            .. ", midnight=" .. tostring(totalCount)
            .. ", learned=" .. tostring(knownCount)
            .. ", firstCraft=" .. tostring(firstCraftDoneCount) .. "/" .. tostring(firstCraftTotalCount))
    end

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_RECIPE_DATA_UPDATED", charKey)
    end
end

-- ============================================================================
-- COOLDOWN DATA COLLECTION
-- ============================================================================

--[[
    Collect recipe cooldown data for the currently open profession.
    Called on TRADE_SKILL_SHOW after a delay to ensure API readiness.

    Dynamically scans all known recipes for cooldowns (no hardcoded list).
    Stores per expansion (keyed by skillLineID):
    {
        [recipeID] = {
            recipeName   = string,
            recipeIcon   = number,
            cooldownEnd  = number,   -- time() + remaining cooldown (0 = ready)
            duration     = number,   -- Full cooldown duration in seconds
            charges      = number,   -- Current charges
            maxCharges   = number,   -- Max charges
            lastUpdate   = number,
        },
    }

    Optimization: After first full scan, stores cooldownRecipeIDs[skillLineID]
    so subsequent opens only check known-cooldown recipes + periodic full rescan.
]]
local FULL_COOLDOWN_RESCAN_INTERVAL = 3600  -- Full rescan every 1 hour
local lastFullCooldownScan = {}             -- [skillLineID] = time()

local function CollectCooldownData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    -- Get the currently active child skillLineID
    local skillLineID = nil
    if C_TradeSkillUI.GetProfessionChildSkillLineID then
        local ok, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if ok and slID and slID > 0 then
            skillLineID = slID
        end
    end
    if not skillLineID then return end

    -- Get base profession name
    local baseProfName = nil
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then baseProfName = SafeAPIString(baseInfo.professionName) end
    end

    -- Initialize tables
    if not charData.professionCooldowns then charData.professionCooldowns = {} end
    if not charData.cooldownRecipeIDs then charData.cooldownRecipeIDs = {} end
    if not charData.professionCooldowns[skillLineID] then charData.professionCooldowns[skillLineID] = {} end

    -- Decide: full scan vs targeted scan of known cooldown recipes
    local now = time()
    local needFullScan = not charData.cooldownRecipeIDs[skillLineID]
        or not lastFullCooldownScan[skillLineID]
        or (now - lastFullCooldownScan[skillLineID]) >= FULL_COOLDOWN_RESCAN_INTERVAL

    local recipeIDsToCheck = {}

    if needFullScan then
        -- Full scan: get all recipe IDs from the open profession window
        if C_TradeSkillUI.GetAllRecipeIDs then
            local ok, allIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
            if ok and allIDs then
                recipeIDsToCheck = allIDs
            end
        end
        lastFullCooldownScan[skillLineID] = now
    else
        -- Targeted scan: only check known cooldown recipes
        recipeIDsToCheck = charData.cooldownRecipeIDs[skillLineID] or {}
    end

    if #recipeIDsToCheck == 0 then return end

    local cooldownEntries = charData.professionCooldowns[skillLineID]
    local knownCooldownIDs = {}
    local found = 0

    for _, recipeID in ipairs(recipeIDsToCheck) do
        if C_TradeSkillUI.GetRecipeCooldown then
            local cdOk, cooldown, isDayCooldown, charges, maxCharges = pcall(C_TradeSkillUI.GetRecipeCooldown, recipeID)
            if cdOk then
                local hasCooldown = (cooldown and cooldown > 0) or (maxCharges and maxCharges > 0 and charges and charges < maxCharges)
                local wasKnown = cooldownEntries[recipeID] ~= nil

                if hasCooldown or wasKnown then
                    -- Get recipe info for name/icon
                    local recipeName, recipeIcon
                    if C_TradeSkillUI.GetRecipeInfo then
                        local riOk, recipeInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
                        if riOk and recipeInfo then
                            recipeName = recipeInfo.name
                            recipeIcon = recipeInfo.icon
                        end
                    end

                    local cooldownEnd = 0
                    local duration = 0
                    if cooldown and cooldown > 0 then
                        cooldownEnd = now + cooldown
                        duration = isDayCooldown and 86400 or cooldown
                    end

                    cooldownEntries[recipeID] = {
                        recipeName  = recipeName or (cooldownEntries[recipeID] and cooldownEntries[recipeID].recipeName) or "Unknown",
                        recipeIcon  = recipeIcon or (cooldownEntries[recipeID] and cooldownEntries[recipeID].recipeIcon) or 134400,
                        cooldownEnd = cooldownEnd,
                        duration    = duration,
                        charges     = charges or 0,
                        maxCharges  = maxCharges or 1,
                        lastUpdate  = now,
                    }
                    knownCooldownIDs[#knownCooldownIDs + 1] = recipeID
                    found = found + 1
                end
            end
        end
    end

    -- Update known cooldown recipe IDs for targeted future scans
    if needFullScan and #knownCooldownIDs > 0 then
        charData.cooldownRecipeIDs[skillLineID] = knownCooldownIDs
    end

    -- Clean up expired entries that are no longer in the recipe list (profession dropped, etc.)
    -- Only on full scan to avoid accidentally removing recipes during targeted scan
    if needFullScan then
        local validSet = {}
        for _, id in ipairs(recipeIDsToCheck) do validSet[id] = true end
        for recipeID in pairs(cooldownEntries) do
            if not validSet[recipeID] then
                cooldownEntries[recipeID] = nil
            end
        end
    end

    if WarbandNexus.Debug then
        WarbandNexus:Debug("[Cooldowns] Collected " .. found .. " cooldown(s) for skillLineID=" .. tostring(skillLineID) .. " (fullScan=" .. tostring(needFullScan) .. ")")
    end

    local bucket = EnsureSkillLineBucket(charData, skillLineID, baseProfName, nil)
    if bucket then
        bucket.cooldowns = cooldownEntries
        bucket.lastUpdate = now
    end

    if found > 0 and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_PROFESSION_COOLDOWNS_UPDATED", charKey)
    end
end

-- ============================================================================
-- CRAFTING ORDERS DATA COLLECTION
-- ============================================================================

--[[
    Collect crafting orders count for the currently open profession.
    Called on TRADE_SKILL_SHOW after a delay.

    Stores per expansion (keyed by skillLineID):
    {
        personalCount = number,
        guildCount    = number,
        publicCount   = number,
        lastUpdate    = number,
    }

    Note: C_CraftingOrders APIs are async and require profession context.
    We use the simplest available methods for an MVP count.
]]
local function CollectCraftingOrdersData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_CraftingOrders then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    -- Get the currently active child skillLineID
    local skillLineID = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID then
        local ok, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if ok and slID and slID > 0 then
            skillLineID = slID
        end
    end
    if not skillLineID then return end

    -- Initialize
    if not charData.craftingOrders then charData.craftingOrders = {} end
    local baseProfName = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then baseProfName = SafeAPIString(baseInfo.professionName) end
    end

    local personalCount = 0
    local guildCount = 0
    local publicCount = 0

    -- Personal orders count
    if C_CraftingOrders.GetNumPersonalOrders then
        local ok, count = pcall(C_CraftingOrders.GetNumPersonalOrders)
        if ok and count then personalCount = count end
    end

    -- Claimed order (adds to personal context)
    if C_CraftingOrders.GetClaimedOrder then
        local ok, order = pcall(C_CraftingOrders.GetClaimedOrder)
        if ok and order then
            -- Claimed order exists — count is already included in personal
        end
    end

    -- Guild orders — try synchronous count if available
    if C_CraftingOrders.GetNumGuildOrders then
        local ok, count = pcall(C_CraftingOrders.GetNumGuildOrders)
        if ok and count then guildCount = count end
    end

    charData.craftingOrders[skillLineID] = {
        personalCount = personalCount,
        guildCount    = guildCount,
        publicCount   = publicCount,
        lastUpdate    = time(),
    }
    local bucket = EnsureSkillLineBucket(charData, skillLineID, baseProfName, nil)
    if bucket then
        bucket.orders = {
            personalCount = personalCount,
            guildCount = guildCount,
            publicCount = publicCount,
            lastUpdate = time(),
        }
    end

    if WarbandNexus.Debug then
        WarbandNexus:Debug("[Orders] Collected for skillLineID=" .. tostring(skillLineID) .. " personal=" .. personalCount .. " guild=" .. guildCount)
    end

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CRAFTING_ORDERS_UPDATED", charKey)
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

--[[
    Called on TRADE_SKILL_SHOW (profession window opened).
    - Installs recipe hook (once)
    - Collects data ONLY if missing for the current profession
    - Concentration: always refresh (currency values change)
    - Fires WN_PROFESSION_WINDOW_OPENED for companion window
]]
function WarbandNexus:OnTradeSkillShow()
    -- Guard: skip data collection when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    
    -- Install hooks (once, deferred until frame exists)
    InstallRecipeHook()

    -- Run all collectors; C_TradeSkillUI can be not ready immediately after TRADE_SKILL_SHOW
    local function RunAllCollectors()
        if not WarbandNexus then return end
        pcall(CollectConcentrationData)
        pcall(CollectKnowledgeData)
        pcall(CollectAllExpansionProfessions, true)
        pcall(CollectRecipeSummaryData)
        pcall(CollectMidnightKnowledgeProgressData)
        pcall(CollectCooldownData)
        pcall(CollectCraftingOrdersData)
        pcall(CollectEquipmentDataForCurrentProfession)
        pcall(CollectEquipmentByDetection)
    end

    -- First pass: 0.6s delay so IsTradeSkillReady / GetProfessionChildSkillLineID are ready
    C_Timer.After(0.6, function()
        RunAllCollectors()
        if WarbandNexus and WarbandNexus.SendMessage then
            local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
            if charKey then
                WarbandNexus:SendMessage("WN_PROFESSION_DATA_UPDATED", charKey)
            end
        end
    end)

    -- Retry pass: 1.2s so UI/list is fully populated (Concentration, Knowledge, etc. then refresh)
    C_Timer.After(1.2, function()
        if not WarbandNexus then return end
        RunAllCollectors()
        if WarbandNexus.SendMessage then
            local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
            if charKey then
                WarbandNexus:SendMessage("WN_PROFESSION_DATA_UPDATED", charKey)
            end
        end
    end)

    -- Notify companion window
    if self.SendMessage then
        self:SendMessage("WN_PROFESSION_WINDOW_OPENED")
    end
end

--[[
    Called on TRADE_SKILL_CLOSE (profession window closed).
    Notifies companion window.
]]
function WarbandNexus:OnTradeSkillClose()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    
    if self.SendMessage then
        self:SendMessage("WN_PROFESSION_WINDOW_CLOSED")
    end
end

--[[
    Called on TRADE_SKILL_LIST_UPDATE (recipe list changed, expansion tab switched, or after crafting).
    Refreshes concentration so the current expansion's concentration is stored.
    Without this, switching e.g. Dragon Isles → Khaz Algar keeps showing the previous expansion's
    value (e.g. 1000/1000) while the game shows the current one (e.g. 479/1000).
]]
local tradeSkillListUpdatePending = false

function WarbandNexus:OnTradeSkillListUpdate()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    
    -- Only process if profession frame is open
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end
    
    if tradeSkillListUpdatePending then return end
    tradeSkillListUpdatePending = true
    
    C_Timer.After(0.5, function()
        tradeSkillListUpdatePending = false
        if not WarbandNexus or not IsCurrentCharacterTracked() then return end
        -- Re-collect all tab-specific data when the expansion tab changes.
        -- Each data type is keyed by skillLineID so switching tabs writes to the correct bucket.
        pcall(CollectConcentrationData)
        pcall(CollectKnowledgeData)
        pcall(CollectAllExpansionProfessions, true)
        pcall(CollectRecipeSummaryData)
        pcall(CollectMidnightKnowledgeProgressData)
        pcall(CollectCooldownData)
        pcall(CollectCraftingOrdersData)
        pcall(CollectEquipmentDataForCurrentProfession)
        pcall(CollectEquipmentByDetection)
    end)
end

--[[
    Called on NEW_RECIPE_LEARNED.
    Refresh recipe summary for the current profession context.
]]
function WarbandNexus:OnNewRecipeLearned()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    C_Timer.After(0.3, function()
        if not WarbandNexus or not IsCurrentCharacterTracked() then return end
        pcall(CollectRecipeSummaryData)
        pcall(CollectMidnightKnowledgeProgressData)
    end)
end

function WarbandNexus:OnProfessionQuestProgressChanged()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end
    if RefreshAllMidnightKnowledgeProgressForCharacter(charData) > 0 and self.SendMessage then
        self:SendMessage("WN_PROFESSION_DATA_UPDATED", charKey)
    end
end

--[[
    Called on SKILL_LINES_CHANGED (profession learned/dropped/skill level changed).
    Refreshes expansion data and detects profession changes.
]]
function WarbandNexus:OnProfessionChanged()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    -- Refresh basic profession data (names, icons, skill levels)
    if self.UpdateProfessionData then
        self:UpdateProfessionData()
    end

    -- Compare current professions to detect profession changes
    local currentProfs = {}
    if charData.professions then
        for k, prof in pairs(charData.professions) do
            if prof and prof.name then
                currentProfs[prof.name] = true
            end
        end
    end

    -- Clear stale data for unlearned professions.
    -- Only trust empty currentProfs after the first successful collection
    -- (ns._professionDataReady set by UpdateProfessionData), otherwise
    -- SKILL_LINES_CHANGED on login would wipe all data.
    local canClearStale = next(currentProfs) or ns._professionDataReady
    if canClearStale then
        if charData.professionExpansions then
            for profName in pairs(charData.professionExpansions) do
                if not currentProfs[profName] then
                    charData.professionExpansions[profName] = nil
                    if charData.discoveredSkillLines then
                        charData.discoveredSkillLines[profName] = nil
                    end
                end
            end
        end

        -- Also clear related data stores for unlearned professions
        if charData.concentration then
            for key, concEntry in pairs(charData.concentration) do
                if type(key) == "string" and not currentProfs[key] then
                    charData.concentration[key] = nil
                end
            end
        end
        if charData.knowledgeData then
            for key in pairs(charData.knowledgeData) do
                if type(key) == "string" and not currentProfs[key] then
                    charData.knowledgeData[key] = nil
                end
            end
        end
        if charData.professionEquipment then
            for profName in pairs(charData.professionEquipment) do
                if not currentProfs[profName] then
                    charData.professionEquipment[profName] = nil
                end
            end
        end
    end

    -- Refresh expansion data from stored skillLineIDs
    pcall(CollectAllExpansionProfessions, false)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Get concentration data for all characters, grouped by profession.
    
    @return table {
        [professionName] = {
            { charKey = string, charName = string, classFile = string,
              current = number, max = number, lastUpdate = number },
            ...
        }
    }
]]
function WarbandNexus:GetAllConcentrationData()
    local result = {}

    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end

    for charKey, charData in pairs(self.db.global.characters) do
        if charData.concentration then
            local charName = charData.name or charKey
            local classFile = charData.classFile or "PRIEST"

            for key, concData in pairs(charData.concentration) do
                local profName = (type(key) == "number" and concData.professionName) or (type(key) == "string" and key) or "Profession"
                if not result[profName] then
                    result[profName] = {}
                end
                local entry = {
                    charKey    = charKey,
                    charName   = charName,
                    classFile  = classFile,
                    current    = concData.current or 0,
                    max        = concData.max or 0,
                    lastUpdate = concData.lastUpdate or 0,
                    currencyID = concData.currencyID,
                }
                result[profName][#result[profName] + 1] = entry
            end
        end
    end

    -- Sort each profession's entries by charName for consistent display
    for _, entries in pairs(result) do
        table.sort(entries, function(a, b) return a.charName < b.charName end)
    end

    return result
end

--[[
    Get all characters that know a specific recipe, with their skill and concentration data.
    
    @param recipeID number - The recipe spell ID
    @return table - Array of crafter entries, sorted by skill level (descending):
    {
        {
            charKey        = string,
            charName       = string,
            classFile      = string,
            professionName = string,
            skillLevel     = number,
            maxSkillLevel  = number,
            concentration  = { current, max, lastUpdate, currencyID } or nil,
            lastScan       = number,
        },
        ...
    }
]]
function WarbandNexus:GetCraftersForRecipe(recipeID)
    local result = {}

    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end
    if not recipeID then return result end

    for charKey, charData in pairs(self.db.global.characters) do
        if charData.recipes then
            for skillLineID, profData in pairs(charData.recipes) do
                if profData.knownRecipes and profData.knownRecipes[recipeID] then
                    -- Concentration keyed by skillLineID (same as recipes); fallback legacy by professionName
                    local concEntry = nil
                    if charData.concentration then
                        concEntry = charData.concentration[skillLineID] or (profData.professionName and charData.concentration[profData.professionName])
                    end

                    -- Look up overall profession skill from charData.professions
                    -- (not the expansion-specific skill stored in profData)
                    local overallSkill, overallMaxSkill = 0, 0
                    if charData.professions then
                        for k, prof in pairs(charData.professions) do
                            if prof and prof.name == profData.professionName then
                                overallSkill = prof.skill or prof.rank or 0
                                overallMaxSkill = prof.maxSkill or prof.maxRank or 0
                                break
                            end
                        end
                    end

                    result[#result + 1] = {
                        charKey        = charKey,
                        charName       = charData.name or charKey,
                        classFile      = charData.classFile or "PRIEST",
                        professionName = profData.professionName or "",
                        skillLevel     = overallSkill,
                        maxSkillLevel  = overallMaxSkill,
                        concentration  = concEntry,
                        lastScan       = profData.lastScan or 0,
                    }
                    break -- A recipe belongs to one profession per character
                end
            end
        end
    end

    -- Sort: highest skill first; on tie, current online character first; then alphabetical
    local currentCharKey = ns.Utilities:GetCharacterKey()
    table.sort(result, function(a, b)
        if a.skillLevel ~= b.skillLevel then
            return a.skillLevel > b.skillLevel
        end
        -- Same skill: prioritize the currently online character
        local aOnline = (a.charKey == currentCharKey)
        local bOnline = (b.charKey == currentCharKey)
        if aOnline ~= bOnline then
            return aOnline
        end
        return a.charName < b.charName
    end)

    return result
end

-- TWW concentration recharge: 10 per hour, 1000 max, 100 hours full recharge
-- Rate is fixed and applies passively (server-side, online and offline)
local CONCENTRATION_PER_SECOND = 10 / 3600  -- 10 per hour → per second

--[[
    Estimate the current concentration for a stored entry, accounting for
    passive regeneration since the snapshot was taken.
    
    @param entry table - { current, max, lastUpdate }
    @return number - Estimated current concentration (floored integer)
]]
function WarbandNexus:GetEstimatedConcentration(entry)
    if not entry or not entry.max or entry.max <= 0 then return 0 end
    local current = entry.current or 0
    if current >= entry.max then return entry.max end

    local elapsed = time() - (entry.lastUpdate or time())
    if elapsed < 0 then elapsed = 0 end

    local estimated = current + (elapsed * CONCENTRATION_PER_SECOND)
    return math.min(math.floor(estimated), entry.max)
end

--[[
    Estimate time until concentration is full for a given entry.
    
    @param entry table - Single concentration entry from GetAllConcentrationData()
    @return string - Formatted time string ("Full", "2h 13m", "1d 4h", etc.)
]]
function WarbandNexus:GetConcentrationTimeToFull(entry)
    if not entry or not entry.max or entry.max <= 0 then return "" end

    local estimated = self:GetEstimatedConcentration(entry)
    if estimated >= entry.max then return "Full" end

    local remainingDeficit = entry.max - estimated
    local secondsToFull = remainingDeficit / CONCENTRATION_PER_SECOND

    local totalHours = math.floor(secondsToFull / 3600)
    local totalMinutes = math.floor(secondsToFull / 60)

    if totalHours >= 1 then
        return string.format("%d Hours", totalHours)
    else
        return string.format("%d Min", math.max(1, totalMinutes))
    end
end

--[[
    Detailed time-to-full breakdown for tooltip display.
    Returns "X Days Y Hours Z Minutes" format.

    @param entry table - Single concentration entry from GetAllConcentrationData()
    @return string - Detailed time string ("2 Days 5 Hours 13 Minutes", etc.)
]]
function WarbandNexus:GetConcentrationTimeToFullDetailed(entry)
    if not entry or not entry.max or entry.max <= 0 then return "" end

    local estimated = self:GetEstimatedConcentration(entry)
    if estimated >= entry.max then return "Full" end

    local remainingDeficit = entry.max - estimated
    local secondsToFull = remainingDeficit / CONCENTRATION_PER_SECOND

    local days = math.floor(secondsToFull / 86400)
    local hours = math.floor((secondsToFull % 86400) / 3600)
    local minutes = math.floor((secondsToFull % 3600) / 60)

    if days > 0 then
        return string.format("%d Days %d Hours %d Min", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%d Hours %d Min", hours, minutes)
    else
        return string.format("%d Min", math.max(1, minutes))
    end
end

-- ============================================================================
-- PUBLIC API: KNOWLEDGE DATA
-- ============================================================================

--[[
    Get knowledge data for a specific character and profession.
    
    @param charKey string - Character key (e.g. "Mert-Silvermoon")
    @param profName string - Profession name (e.g. "Tailoring")
    @return table|nil - Knowledge data entry or nil:
    {
        skillLineID      = number,
        hasUnspentPoints = boolean,
        unspentPoints    = number,
        spentPoints      = number,
        maxPoints        = number,
        currencyName     = string,
        currencyIcon     = number,
        specTabs         = { { tabID, name, state }, ... },
        lastUpdate       = number,
    }
]]
function WarbandNexus:GetKnowledgeData(charKey, profName)
    if not self.db or not self.db.global or not self.db.global.characters then
        return nil
    end
    if not charKey or not profName then return nil end

    local charData = self.db.global.characters[charKey]
    if not charData or not charData.knowledgeData then return nil end

    -- Direct profName lookup (legacy data)
    if charData.knowledgeData[profName] then
        return charData.knowledgeData[profName]
    end
    -- Search skillLineID-keyed entries that match professionName
    for key, kd in pairs(charData.knowledgeData) do
        if type(key) == "number" and type(kd) == "table" and kd.professionName == profName then
            return kd
        end
    end
    return nil
end

--[[
    Get knowledge data for ALL characters for a specific profession.
    
    @param profName string - Profession name (e.g. "Tailoring")
    @return table - Array of entries
]]
function WarbandNexus:GetAllKnowledgeDataForProfession(profName)
    local result = {}

    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end
    if not profName then return result end

    for charKey, charData in pairs(self.db.global.characters) do
        if charData.knowledgeData then
            -- Find knowledge entry matching professionName (entries may be keyed by skillLineID or profName)
            local kd = charData.knowledgeData[profName]
            if not kd then
                for key, entry in pairs(charData.knowledgeData) do
                    if type(key) == "number" and type(entry) == "table" and entry.professionName == profName then
                        kd = entry
                        break
                    end
                end
            end
            if kd then
                result[#result + 1] = {
                    charKey          = charKey,
                    charName         = charData.name or charKey,
                    classFile        = charData.classFile or "PRIEST",
                    hasUnspentPoints = kd.hasUnspentPoints or false,
                    unspentPoints    = kd.unspentPoints or 0,
                    spentPoints      = kd.spentPoints or 0,
                    maxPoints        = kd.maxPoints or 0,
                    currencyName     = kd.currencyName or "",
                    specTabs         = kd.specTabs or {},
                    lastUpdate       = kd.lastUpdate or 0,
                }
            end
        end
    end

    -- Sort by charName for consistency
    table.sort(result, function(a, b) return a.charName < b.charName end)

    return result
end

--[[
    Print current profession stats to chat for verification.
    Call with profession window OPEN (K) to see live API-derived values and DB snapshot.
    Use: /wn profverify
]]
function WarbandNexus:PrintProfessionVerify()
    if not self.Print then return end
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then
        self:Print("|cffff6600[WN Prof Verify]|r No character key.")
        return
    end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then
        self:Print("|cffff6600[WN Prof Verify]|r No character data.")
        return
    end

    local skillLineID
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionChildSkillLineID then
        local ok, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
        if ok and slID and slID > 0 then skillLineID = slID end
    end

    if not skillLineID then
        self:Print("|cff00ccff[WN Prof Verify]|r Open profession window (K) first, then run |cffffcc00/wn profverify|r again.")
        if charData.knowledgeData or charData.recipes then
            self:Print("|cff888888 Stored data for this character (Midnight only):|r")
            if charData.knowledgeData then
                for k, v in pairs(charData.knowledgeData) do
                    local expName = type(v) == "table" and v.expansionName
                    if type(v) == "table" and v.professionName and expName and (not issecretvalue or not issecretvalue(expName)) and expName:find("Midnight", 1, true) then
                        local sp = v.spentPoints or 0
                        local mx = v.maxPoints or 0
                        self:Print("  Knowledge " .. tostring(v.professionName) .. ": " .. sp .. " / " .. (mx > 0 and mx or "--"))
                    end
                end
            end
            if charData.recipes then
                for sl, r in pairs(charData.recipes) do
                    local rExp = type(r) == "table" and r.expansionName
                    if type(r) == "table" and r.professionName and rExp and (not issecretvalue or not issecretvalue(rExp)) and rExp:find("Midnight", 1, true) then
                        self:Print("  Recipes " .. tostring(r.professionName) .. ": " .. tostring(r.knownCount or 0) .. " / " .. tostring(r.totalCount or 0) .. "  First craft: " .. tostring(r.firstCraftDoneCount or 0) .. " / " .. tostring(r.firstCraftTotalCount or 0))
                    end
                end
            end
        end
        if charData.professionEquipment then
            local keys = {}
            for k in pairs(charData.professionEquipment) do if k ~= "_legacy" then keys[#keys + 1] = tostring(k) end end
            if #keys > 0 then
                self:Print("  Equipment keys: " .. table.concat(keys, ", "))
            end
        end
        return
    end

    local profName = "?"
    local expansionName = ""
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and info then
            profName = SafeAPIString(info.parentProfessionName) or SafeAPIString(info.professionName) or "?"
            expansionName = SafeAPIString(info.professionName) or ""
        end
    end

    self:Print("|cff00ff00[WN Prof Verify]|r " .. profName .. " (" .. expansionName .. ") | skillLineID=" .. tostring(skillLineID))

    local kd = charData.knowledgeData and charData.knowledgeData[skillLineID]
    if kd then
        local cur = (kd.spentPoints or 0) + (kd.unspentPoints or 0)
        local max = kd.maxPoints or 0
        self:Print("  Knowledge: " .. cur .. " / " .. (max > 0 and max or "--") .. "  (spent=" .. tostring(kd.spentPoints or 0) .. ", unspent=" .. tostring(kd.unspentPoints or 0) .. ")")
    else
        self:Print("  Knowledge: no data (open this profession tab to refresh)")
    end

    local rec = charData.recipes and charData.recipes[skillLineID]
    if rec then
        self:Print("  Recipes: " .. tostring(rec.knownCount or 0) .. " / " .. tostring(rec.totalCount or 0))
        self:Print("  First craft: " .. tostring(rec.firstCraftDoneCount or 0) .. " / " .. tostring(rec.firstCraftTotalCount or 0))
    else
        self:Print("  Recipes / First craft: no data (open this profession tab to refresh)")
    end

    local eqByProf = charData.professionEquipment
    local eqKey = profName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
    local eqData = eqByProf and (eqByProf[profName] or eqByProf[expansionName] or eqByProf[eqKey]) or nil
    if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
        local parts = {}
        if eqData.tool and eqData.tool.name then parts[#parts + 1] = "Tool: " .. eqData.tool.name end
        if eqData.accessory1 and eqData.accessory1.name then parts[#parts + 1] = "Acc1: " .. eqData.accessory1.name end
        if eqData.accessory2 and eqData.accessory2.name then parts[#parts + 1] = "Acc2: " .. eqData.accessory2.name end
        self:Print("  Equipment: " .. (table.concat(parts, "  ") or "ok"))
    else
        self:Print("  Equipment: none stored (open profession (K) on this char to scan)")
    end

    self:Print("|cff888888 Compare with in-game UI to verify numbers.|r")
end

-- ============================================================================
-- LOGIN-TIME CONCENTRATION COLLECTION
-- ============================================================================

--[[
    Collect concentration data on login/reload.
    First tries to refresh existing data from stored currency IDs.
    Then also runs a full currency list scan to discover new concentration
    currencies (e.g. if the player learned a new profession since last login).
    Called on PLAYER_ENTERING_WORLD with a delay.
]]
function WarbandNexus:CollectConcentrationOnLogin()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not self.db or not self.db.global then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    -- Phase 1: Refresh existing stored data from known currency IDs
    if charData.concentration then
        for slKey, concData in pairs(charData.concentration) do
            if concData.currencyID and concData.currencyID > 0 then
                local ok, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, concData.currencyID)
                if ok and currInfo then
                    concData.current    = currInfo.quantity or concData.current or 0
                    concData.max        = currInfo.maxQuantity or concData.max or 0
                    concData.lastUpdate = time()
                end
            end
            if concData.current == nil then concData.current = 0 end
            if concData.max == nil then concData.max = 0 end
        end
    end

    -- Phase 2: Try to discover concentration via GetConcentrationCurrencyID
    -- using stored discoveredSkillLines (collected when professions were opened)
    if C_TradeSkillUI and C_TradeSkillUI.GetConcentrationCurrencyID then
        if not charData.concentration then
            charData.concentration = {}
        end

        if charData.discoveredSkillLines then
            for profName, skillLines in pairs(charData.discoveredSkillLines) do
                for _, sl in ipairs(skillLines) do
                    local slID = (type(sl) == "table" and sl.id) or sl
                    if slID and not charData.concentration[slID] then
                        local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, slID)
                        if concOk and currencyID and currencyID > 0 then
                            local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                            if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                                local expansionName = nil
                                if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                                    local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slID)
                                    if piOk and profInfo then
                                        expansionName = profInfo.professionName or profInfo.parentProfessionName
                                    end
                                end
                                charData.concentration[slID] = {
                                    current        = currInfo.quantity or 0,
                                    max            = currInfo.maxQuantity or 0,
                                    currencyID     = currencyID,
                                    skillLineID    = slID,
                                    professionName = profName,
                                    expansionName  = expansionName,
                                    lastUpdate     = time(),
                                }
                                local bucket = EnsureSkillLineBucket(charData, slID, profName, expansionName)
                                if bucket then
                                    bucket.concentration = {
                                        current = currInfo.quantity or 0,
                                        max = currInfo.maxQuantity or 0,
                                        currencyID = currencyID,
                                        lastUpdate = time(),
                                    }
                                end
                                break
                            end
                        end
                    end
                end
            end
        end

        -- Phase 2b: Fallback via GetProfessions + GetProfessionInfo (base profession skill line)
        local prof1, prof2 = GetProfessions and GetProfessions()
        for _, index in ipairs({ prof1, prof2 }) do
            if index then
                local ok, name, _, _, _, _, skillLine = pcall(GetProfessionInfo, index)
                if ok and name and name ~= "" and skillLine and skillLine > 0 and not charData.concentration[skillLine] then
                    local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, skillLine)
                    if concOk and currencyID and currencyID > 0 then
                        local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                        if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                            charData.concentration[skillLine] = {
                                current        = currInfo.quantity or 0,
                                max            = currInfo.maxQuantity or 0,
                                currencyID     = currencyID,
                                skillLineID    = skillLine,
                                professionName = name,
                                expansionName  = nil,
                                lastUpdate     = time(),
                            }
                            local bucket = EnsureSkillLineBucket(charData, skillLine, name, nil)
                            if bucket then
                                bucket.concentration = {
                                    current = currInfo.quantity or 0,
                                    max = currInfo.maxQuantity or 0,
                                    currencyID = currencyID,
                                    lastUpdate = time(),
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    -- Rebuild reverse lookup map for real-time currency matching
    if self.RebuildConcentrationCurrencyMap then
        self:RebuildConcentrationCurrencyMap()
    end

    if self.SendMessage then
        self:SendMessage("WN_CONCENTRATION_UPDATED", charKey)
    end
end

--[[
    Refresh expansion sub-profession data on login from stored skillLineIDs.
    Called from Core.lua on PLAYER_ENTERING_WORLD with a delay.
]]
function WarbandNexus:CollectExpansionProfessionsOnLogin()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    pcall(CollectAllExpansionProfessions, false)
end

-- ============================================================================
-- LOGIN-TIME KNOWLEDGE COLLECTION
-- ============================================================================

--[[
    Collect knowledge data on login/reload for all discovered professions.
    Uses stored discoveredSkillLines + C_Traits API chain (same as Blizzard's own code).
    Called from Core.lua on PLAYER_ENTERING_WORLD with a delay.
]]
function WarbandNexus:CollectKnowledgeOnLogin()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not self.db or not self.db.global then return end
    if not C_ProfSpecs or not C_Traits then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    if not charData.knowledgeData then
        charData.knowledgeData = {}
    end

    if not charData.discoveredSkillLines then return end

    for profName, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            for _, sl in ipairs(skillLines) do
                local slID = sl.id or sl
                local expansionName = (type(sl) == "table" and sl.name) or nil

                local result = CollectKnowledgeForSkillLine(slID, profName)
                if result then
                    result.professionName = profName
                    result.expansionName = expansionName
                    charData.knowledgeData[slID] = result
                    local bucket = EnsureSkillLineBucket(charData, slID, profName, expansionName)
                    if bucket then
                        bucket.knowledge = {
                            hasUnspentPoints = result.hasUnspentPoints or false,
                            unspentPoints = result.unspentPoints or 0,
                            spentPoints = result.spentPoints or 0,
                            maxPoints = result.maxPoints or 0,
                            currencyName = SafeAPIString(result.currencyName) or "",
                            currencyIcon = result.currencyIcon,
                            specTabs = result.specTabs,
                            lastUpdate = result.lastUpdate or time(),
                        }
                    end
                    -- Continue: collect ALL expansion skill lines, not just the first
                end
            end
        end
    end

    if self.SendMessage then
        self:SendMessage("WN_KNOWLEDGE_UPDATED", charKey)
    end
end

-- ============================================================================
-- REAL-TIME UPDATE SYSTEM
-- ============================================================================

--[[
    Build a reverse lookup: concentrationCurrencyID → professionName
    Used by OnConcentrationCurrencyChanged to quickly identify which
    profession's concentration was affected by a CURRENCY_DISPLAY_UPDATE.
    
    @return table { [currencyID] = profName, ... }
]]
local function BuildConcentrationCurrencyMap()
    local map = {}
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return map end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return map end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData or not charData.concentration then return map end

    for key, concData in pairs(charData.concentration) do
        if concData.currencyID and concData.currencyID > 0 then
            map[concData.currencyID] = key
        end
    end
    
    return map
end

-- Cache the map; rebuilt when concentration data is collected
local concentrationCurrencyMap = {}

--[[
    Called when CURRENCY_DISPLAY_UPDATE fires.
    Checks if the updated currency is a concentration currency.
    If so, refreshes that specific entry from the API.
    
    @param currencyID number - The currency that changed
]]
function WarbandNexus:OnConcentrationCurrencyChanged(currencyID)
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not currencyID or currencyID == 0 then return end
    
    -- Rebuild map if empty (first call or after reload)
    if not next(concentrationCurrencyMap) then
        concentrationCurrencyMap = BuildConcentrationCurrencyMap()
    end
    
    local key = concentrationCurrencyMap[currencyID]
    if not key then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData or not charData.concentration or not charData.concentration[key] then return end

    local ok, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if ok and currInfo then
        local entry = charData.concentration[key]
        entry.current    = currInfo.quantity or entry.current or 0
        entry.max        = currInfo.maxQuantity or entry.max or 0
        entry.lastUpdate = time()
        if self.Debug then
            self:Debug("[Concentration] Real-time update: key=" .. tostring(key) .. " = " .. tostring(entry.current) .. "/" .. tostring(entry.max))
        end
        
        -- Notify consumers (tooltip, UI)
        if self.SendMessage then
            self:SendMessage("WN_CONCENTRATION_UPDATED", charKey)
        end
    end
end

function WarbandNexus:OnProfessionProgressCurrencyChanged(currencyID)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not currencyID or not MIDNIGHT_CATCHUP_CURRENCY[currencyID] then return end
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end
    if RefreshAllMidnightKnowledgeProgressForCharacter(charData) > 0 and self.SendMessage then
        self:SendMessage("WN_PROFESSION_DATA_UPDATED", charKey)
    end
end

--[[
    Called when TRAIT_NODE_CHANGED or TRAIT_CONFIG_UPDATED fires.
    Refreshes knowledge data for all professions of the current character.
    Throttled to avoid excessive API calls during rapid spec changes.
]]
local knowledgeRefreshPending = false

function WarbandNexus:OnKnowledgeChanged()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if knowledgeRefreshPending then return end  -- Debounce
    knowledgeRefreshPending = true
    
    C_Timer.After(0.5, function()
        knowledgeRefreshPending = false
        if not WarbandNexus or not WarbandNexus.db then return end
        
        -- Re-collect knowledge for all professions
        pcall(function()
            WarbandNexus:CollectKnowledgeOnLogin()
        end)
        
        if WarbandNexus.Debug then
            WarbandNexus:Debug("[Knowledge] Real-time refresh triggered by spec change")
        end
    end)
end

--[[
    Rebuild the concentration currency map.
    Called after any concentration collection to keep the map current.
]]
function WarbandNexus:RebuildConcentrationCurrencyMap()
    concentrationCurrencyMap = BuildConcentrationCurrencyMap()
end

-- ============================================================================
-- PERIODIC RECHARGE TIMER (1-minute tick)
-- ============================================================================

--[[
    Start a 1-minute repeating ticker that fires WN_CONCENTRATION_UPDATED.
    This ensures any visible UI (tooltips, companion window) recalculates
    the estimated concentration and recharge time without stale data.
    
    The ticker is lightweight: no API calls, just fires the message event
    so consumers re-read from DB and recalculate with GetEstimatedConcentration().
]]
local rechargeTickerHandle = nil

function WarbandNexus:StartRechargeTimer()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if rechargeTickerHandle then return end  -- Already running
    
    rechargeTickerHandle = C_Timer.NewTicker(60, function()
        if not WarbandNexus or not WarbandNexus.SendMessage then return end
        -- Guard each tick: stop sending if module was disabled mid-session
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        
        local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
        if charKey then
            WarbandNexus:SendMessage("WN_CONCENTRATION_UPDATED", charKey)
        end
    end)
    
    if self.Debug then
        self:Debug("[Recharge Timer] Started (60s interval)")
    end
end

function WarbandNexus:StopRechargeTimer()
    if rechargeTickerHandle then
        rechargeTickerHandle:Cancel()
        rechargeTickerHandle = nil
        
        if self.Debug then
            self:Debug("[Recharge Timer] Stopped")
        end
    end
end

-- ============================================================================
-- EXPORT
-- ============================================================================

ns.ProfessionService = WarbandNexus
