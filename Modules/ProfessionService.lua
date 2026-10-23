--[[
    Warband Nexus - Profession Service
    Collects concentration/knowledge on TRADE_SKILL_SHOW (APIs require profession window); persists to db.global.characters.

    Data flow: TRADE_SKILL_SHOW → RunAllCollectors → SendMessage(WN_*_UPDATED)
]]

local ADDON_NAME, ns = ...

-- 12.1.5 removed the global item/coin fallbacks; bind the namespaced APIs.
local GetItemInfo = C_Item.GetItemInfo
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local DebugPrint = ns.DebugPrint
local DebugVerbosePrint = ns.DebugVerbosePrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

local issecretvalue = issecretvalue

-- Shared with the ProfessionService_* satellites (separate chunks, loaded right after this file).
-- Helpers they call are exported at the end of this file; the weekly knowledge tables / functions
-- live in ProfessionService_WeeklyKnowledge.lua and are read here as PS.* at call time.
local PS = ns.ProfessionServiceShared or {}
ns.ProfessionServiceShared = PS

local function IsCurrentCharacterTracked()
    return ns.CharacterService and WarbandNexus and ns.CharacterService:IsCharacterTracked(WarbandNexus)
end

--- Index in `db.global.characters` for the logged-in player (GUID when available).
local function ResolveTrackedCharactersTableKey()
    return ns.CharacterService and WarbandNexus and ns.CharacterService.ResolveCharactersTableKey
        and ns.CharacterService:ResolveCharactersTableKey(WarbandNexus)
end

--- Canonical key for WN_* payloads after GUID migration (Name-Realm from APIs resolves to storage slot).
local function CurrentSessionCanonicalCharacterKey()
    local raw = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    if not raw then return nil end
    if ns.Utilities.GetCanonicalCharacterKey then
        local canon = ns.Utilities:GetCanonicalCharacterKey(raw)
        if canon and canon ~= "" then return canon end
        if issecretvalue and issecretvalue(raw) then return nil end
        return raw
    end
    return raw
end

-- STATE

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
    -- Secret check first (2026-10-22): a secret string has type "string"; `not` / `~=` on it error.
    -- Secret value: extract via FontString (SetText accepts secret values, GetText returns plain string)
    if issecretvalue and issecretvalue(value) then
        if not _resolverFS then
            _resolverFS = UIParent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            _resolverFS:Hide()
        end
        _resolverFS:SetText(value)
        local text = _resolverFS:GetText()
        if text and issecretvalue and issecretvalue(text) then
            return nil
        end
        if text and type(text) == "string" and text ~= "" then
            return text
        end
        return nil
    end
    if value == nil then return nil end
    if type(value) == "string" and value ~= "" then return value end
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
        if ok and link and type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
            local parsed = link:match("%[(.-)%]")
            if parsed and parsed ~= "" then return parsed end
        end
    end
    if GetSpellLink then
        local ok, link = pcall(GetSpellLink, spellID)
        if ok and link and type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
            local parsed = link:match("%[(.-)%]")
            if parsed and parsed ~= "" then return parsed end
        end
    end
    return nil
end

-- Safe string extraction from API values — uses ResolveAPIString for secret value support
local function SafeAPIString(value)
    -- Secret check FIRST: comparing a secret (even `value ~= ""`) is itself forbidden.
    if issecretvalue and issecretvalue(value) then
        return ResolveAPIString(value)   -- try FontString extraction
    end
    if type(value) ~= "string" or value == "" then return nil end
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

-- Collector burst: coalesce WN_* emits during RunAllProfessionCollectors / light craft paths.
local collectorBurstDepth = 0
local collectorNotifyPending = {}
local collectorUiNotifySuppressed = false
local lastConcentrationCollectorAt = 0
local CONCENTRATION_HOOK_SKIP_SEC = 1.0
local LIGHT_LIST_COLLECTOR_MIN_INTERVAL = 1.0
local lastLightListCollectorAt = 0

-- Coalesce profession-window open + early TRADE_SKILL_LIST_UPDATE bursts into one collector pass.
local PROFESSION_WINDOW_SYNC_DEBOUNCE = 0.45
local PROFESSION_WINDOW_OPEN_GRACE = 2.5
local professionWindowSyncTimer = nil
local professionWindowOpenAt = 0
-- Set after the debounced open sync runs once; prevents TRADE_SKILL_LIST_UPDATE from
-- re-scheduling full collector passes for the entire grace window (grace anchor is TRADE_SKILL_SHOW only).
local professionWindowInitialSyncComplete = false
local professionWindowRetryUsed = false
local professionWindowSyncedSkillLineID = nil

local function IsProfessionTradeWindowReady()
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady then return false end
    local readyOk, ready = pcall(C_TradeSkillUI.IsTradeSkillReady)
    return readyOk and ready == true
end

local function NotifyCollectorUpdate(notifyKey, messageName, charKey)
    if not notifyKey or not messageName or not charKey then return end
    if collectorBurstDepth > 0 then
        collectorNotifyPending[notifyKey] = charKey
        return
    end
    if WarbandNexus and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(messageName, charKey)
    end
end

local function BeginCollectorBurst()
    collectorBurstDepth = collectorBurstDepth + 1
end

local function EndCollectorBurst(forceProfessionNotify)
    if collectorBurstDepth <= 0 then return end
    collectorBurstDepth = collectorBurstDepth - 1
    if collectorBurstDepth > 0 then return end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey or not WarbandNexus or not WarbandNexus.SendMessage then
        for k in pairs(collectorNotifyPending) do
            collectorNotifyPending[k] = nil
        end
        return
    end

    if forceProfessionNotify then
        collectorNotifyPending.profession = charKey
    end

    if collectorUiNotifySuppressed then
        for k in pairs(collectorNotifyPending) do
            collectorNotifyPending[k] = nil
        end
        return
    end

    local notifyOrder = {
        { "concentration", E.CONCENTRATION_UPDATED },
        { "knowledge", E.KNOWLEDGE_UPDATED },
        { "recipe", E.RECIPE_DATA_UPDATED },
        { "profession", E.PROFESSION_DATA_UPDATED },
        { "cooldowns", E.PROFESSION_COOLDOWNS_UPDATED },
        { "orders", E.CRAFTING_ORDERS_UPDATED },
        { "equipment", E.PROFESSION_EQUIPMENT_UPDATED },
    }
    for i = 1, #notifyOrder do
        local row = notifyOrder[i]
        if collectorNotifyPending[row[1]] then
            WarbandNexus:SendMessage(row[2], charKey)
        end
    end
    for k in pairs(collectorNotifyPending) do
        collectorNotifyPending[k] = nil
    end
end

local function GetOpenTradeSkillChildSkillLineID()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionChildSkillLineID then return nil end
    local slOk, slID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
    if slOk and slID and slID > 0 then
        return slID
    end
    return nil
end

local function ProfessionWindowCollectorsNeedRetry()
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady then return false end
    local readyOk, ready = pcall(C_TradeSkillUI.IsTradeSkillReady)
    if not readyOk or ready ~= true then return false end

    local skillLineID = GetOpenTradeSkillChildSkillLineID()
    if not skillLineID then return true end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey or not WarbandNexus or not WarbandNexus.db then return true end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return true end

    local conc = charData.concentration and charData.concentration[skillLineID]
    if not conc or not conc.max or conc.max <= 0 then return true end

    local rec = charData.recipes and charData.recipes[skillLineID]
    if not rec or not rec.totalCount or rec.totalCount <= 0 then return true end

    local kd = charData.knowledgeData and charData.knowledgeData[skillLineID]
    if not kd then return true end

    return false
end

-- CONCENTRATION DATA COLLECTION

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
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("[Concentration] GetConcentrationCurrencyID API not available")
        end
        return
    end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    -- Initialize concentration table if missing
    if not charData.concentration then
        charData.concentration = {}
    end

    -- Use C_TradeSkillUI.GetProfessionChildSkillLineID() to get the
    -- current child skillLineID, then query concentration via
    -- C_TradeSkillUI.GetConcentrationCurrencyID(skillLineID).
    --
    -- ProfessionInfo tables do NOT contain a skillLineID field,
    -- so we must use the dedicated API to retrieve it.

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

    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("[Concentration] childSkillLineID=" .. tostring(skillLineID) .. " baseProfName=" .. tostring(baseProfName))
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
            for li = 1, #lines do
                local sl = lines[li]
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
    local concentrationDirty = false
    for idx = 1, #skillLinesToTry do
        local entry = skillLinesToTry[idx]
        local slID = entry.id
        local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, slID)

        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("[Concentration] Trying skillLineID=" .. tostring(slID) .. " -> currencyID=" .. tostring(currencyID))
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
                    local newCurrent = currInfo.quantity or 0
                    local newMax = currInfo.maxQuantity or 0
                    local prev = charData.concentration[slID]
                    if not prev or prev.current ~= newCurrent or prev.max ~= newMax
                        or prev.currencyID ~= currencyID then
                        concentrationDirty = true
                    end
                    local concEntry = {
                        current        = newCurrent,
                        max            = newMax,
                        currencyID     = currencyID,
                        skillLineID    = slID,
                        professionName = professionName,
                        expansionName  = expansionName,
                        lastUpdate     = time(),
                    }
                    charData.concentration[slID] = concEntry
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
                    if IsDebugModeEnabled and IsDebugModeEnabled() then
                        DebugPrint("[Concentration] Stored: skillLineID=" .. tostring(slID) .. " " .. tostring(professionName) .. " = "
                            .. tostring(currInfo.quantity) .. "/" .. tostring(currInfo.maxQuantity))
                    end
                end
            end
        end
    end

    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("[Concentration] Collection complete, found " .. found .. " concentration currencies")
    end

    -- Rebuild reverse lookup map for real-time currency matching
    if WarbandNexus.RebuildConcentrationCurrencyMap then
        WarbandNexus:RebuildConcentrationCurrencyMap()
    end

    lastConcentrationCollectorAt = GetTime()

    if concentrationDirty then
        NotifyCollectorUpdate("concentration", E.CONCENTRATION_UPDATED, charKey)
    end
end

-- PROFESSION KNOWLEDGE DATA COLLECTION (C_ProfSpecs API)

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

    -- Get the trait config ID
    local configID = nil
    if C_ProfSpecs.GetConfigIDForSkillLine then
        local ok, cid = pcall(C_ProfSpecs.GetConfigIDForSkillLine, skillLineID)
        if ok and cid and cid > 0 then
            configID = cid
        end
    end
    if not configID then return nil end

    -- Get specialization tab IDs (these are also tree IDs)
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

    --- Pool-max uses deduped node IDs across tabs; tab summary counts every node in this tree.
    --- Persisted shape is summary-only (no per-node arrays) — UI reads totals from ProfessionInfoWindow / ProfessionsUI.
    local function ScanKnowledgeTree(treeID, seenNodes)
        if not treeID or treeID <= 0 then return 0, 0, 0, 0, 0 end
        if not C_Traits or not C_Traits.GetTreeNodes or not C_Traits.GetNodeInfo then return 0, 0, 0, 0, 0 end
        local ok, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
        if not ok or not nodeIDs or #nodeIDs == 0 then return 0, 0, 0, 0, 0 end

        local poolMax = 0
        local tabTotalRanks, tabSpentRanks, tabAllocated, tabNodeCount = 0, 0, 0, 0
        for n = 1, #nodeIDs do
            local nodeID = nodeIDs[n]
            local isNewForMax = not seenNodes or not seenNodes[nodeID]
            if seenNodes then
                seenNodes[nodeID] = true
            end
            local nOk, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
            if nOk and nodeInfo then
                local maxRanks = nodeInfo.maxRanks
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

                if type(maxRanks) == "number" and maxRanks > 0 then
                    local currentRank = nodeInfo.currentRank or nodeInfo.activeRank or 0
                    tabNodeCount = tabNodeCount + 1
                    tabTotalRanks = tabTotalRanks + maxRanks
                    tabSpentRanks = tabSpentRanks + currentRank
                    if currentRank > 0 then
                        tabAllocated = tabAllocated + 1
                    end
                    if isNewForMax then
                        poolMax = poolMax + maxRanks
                    end
                end
            end
        end
        return poolMax, tabTotalRanks, tabSpentRanks, tabAllocated, tabNodeCount
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

        local treeMax, tabTotalRanks, tabSpentRanks, tabAllocated, tabNodeCount =
            ScanKnowledgeTree(tabID, seenKnowledgeNodes)

        specTabs[#specTabs + 1] = {
            tabID = tabID,
            name  = tabName,
            state = tabState,
            totalRanks = tabTotalRanks,
            spentRanks = tabSpentRanks,
            allocatedNodes = tabAllocated,
            totalNodes = tabNodeCount,
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
                        for cii = 1, #treeCurrencies do
                            local ci = treeCurrencies[cii]
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

    if IsDebugModeEnabled and IsDebugModeEnabled() and DebugVerbosePrint then
        DebugVerbosePrint("[Knowledge] " .. (profName or "?")
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

    local charKey = ResolveTrackedCharactersTableKey()
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
    local knowledgeDirty = false
    if result then
        local prev = charData.knowledgeData[skillLineID]
        if not prev or prev.unspentPoints ~= (result.unspentPoints or 0)
            or prev.spentPoints ~= (result.spentPoints or 0)
            or prev.maxPoints ~= (result.maxPoints or 0)
            or prev.hasUnspentPoints ~= (result.hasUnspentPoints or false) then
            knowledgeDirty = true
        end
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

    if knowledgeDirty then
        NotifyCollectorUpdate("knowledge", E.KNOWLEDGE_UPDATED, charKey)
    end
end

-- PROFESSION EQUIPMENT DATA COLLECTION

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
    for i = 1, #slotIDs do
        local slotID = slotIDs[i]
        local key = slotKeys[i] or ("slot" .. i)
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemLink = GetInventoryItemLink("player", slotID)
            local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID) or nil
            local itemName = (itemLink and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)))
                and itemLink:match("%[(.-)%]")
                or nil
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
-- Never persist lastUpdate-only stubs (Professions UI treated those as empty-slot warnings).
local function StoreEquipment(charData, profName, equipment)
    local key = NormalizeProfessionNameForEquipment(profName) or profName
    if equipment then
        charData.professionEquipment[key] = equipment
    else
        charData.professionEquipment[key] = nil
    end
end

local EQUIPMENT_SLOT_KEYS = { "tool", "accessory1", "accessory2" }

local function EquipmentSlotsEqual(a, b)
    if not a and not b then return true end
    if not a or not b then return false end
    for i = 1, #EQUIPMENT_SLOT_KEYS do
        local k = EQUIPMENT_SLOT_KEYS[i]
        local ida = a[k] and a[k].itemID
        local idb = b[k] and b[k].itemID
        if ida ~= idb then return false end
    end
    return true
end

-- Persist equipment only when equipped item IDs changed; returns true when stored.
local function StoreEquipmentIfChanged(charData, profName, equipment)
    local key = NormalizeProfessionNameForEquipment(profName) or profName
    local prev = charData.professionEquipment and charData.professionEquipment[key]
    if EquipmentSlotsEqual(prev, equipment) then
        return false
    end
    StoreEquipment(charData, profName, equipment)
    return true
end

local function CooldownStateFingerprint(entries)
    if not entries then return "" end
    local parts = {}
    for recipeID, entry in pairs(entries) do
        local remaining = 0
        if entry.cooldownEnd and entry.lastUpdate then
            remaining = entry.cooldownEnd - entry.lastUpdate
        end
        parts[#parts + 1] = tostring(recipeID) .. ":"
            .. tostring(entry.charges or 0) .. ":"
            .. tostring(entry.maxCharges or 0) .. ":"
            .. tostring(remaining)
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

--[[
    Collect equipment for the CURRENTLY OPEN profession window.
    Uses C_TradeSkillUI.GetProfessionSlots to get the correct slot IDs from the game.
]]
local function CollectEquipmentDataForCurrentProfession()
    if not WarbandNexus or not WarbandNexus.db then return end
    local charKey = ResolveTrackedCharactersTableKey()
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
        local profIdxTry = { p1, p2, pCook, pFish }
        for ii = 1, #profIdxTry do
            local idx = profIdxTry[ii]
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
    if StoreEquipmentIfChanged(charData, profName, equipment) then
        NotifyCollectorUpdate("equipment", E.PROFESSION_EQUIPMENT_UPDATED, charKey)
    end
end

--[[
    Collect equipment for ALL player professions.
    Uses C_TradeSkillUI.GetProfessionSlots per profession — the game tells us
    which inventory slots belong to which profession. No hardcoded assumptions.
]]
local function CollectEquipmentByDetection()
    if not WarbandNexus or not WarbandNexus.db then return end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    EnsureEquipmentTable(charData)

    local prof1, prof2, _, fish, cook = GetProfessions()
    local profIndicesAll = { prof1, prof2, cook, fish }
    local anyEquipmentChanged = false
    for ii = 1, #profIndicesAll do
        local profIndex = profIndicesAll[ii]
        if profIndex then
            local profName, _, _, _, _, _, skillLine = GetProfessionInfo(profIndex)
            if profName and profName ~= "" then
                local slotIDs = GetProfessionSlotIDs(profName, skillLine)
                if slotIDs then
                    local equipment = CollectEquipmentFromSlots(slotIDs)
                    if StoreEquipmentIfChanged(charData, profName, equipment) then
                        anyEquipmentChanged = true
                    end
                end
            end
        end
    end

    if anyEquipmentChanged then
        NotifyCollectorUpdate("equipment", E.PROFESSION_EQUIPMENT_UPDATED, charKey)
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
    if self.IsProfessionEquipmentPersistedWarm and self:IsProfessionEquipmentPersistedWarm() then
        return
    end
    C_Timer.After(2, function()
        if not WarbandNexus or not IsCurrentCharacterTracked() then return end
        pcall(CollectEquipmentDataForCurrentProfession)
        pcall(CollectEquipmentByDetection)
    end)
end

-- RECIPE SELECTION HOOK

--[[
    Append " (N)" craft count from materials (not schematic.quantityMax) to the recipe detail title.
    Scans SchematicForm regions after Init; deferred one frame so default text is present.
]]
local function ApplyCraftCountToSchematicFormTitle(schematicForm, recipeInfo)
    if not schematicForm or not recipeInfo or not recipeInfo.recipeID then return end
    if not C_TradeSkillUI then return end

    local recipeID = recipeInfo.recipeID
    local craftMax = WarbandNexus.GetRecipeCraftCountFromMaterials
        and WarbandNexus:GetRecipeCraftCountFromMaterials(recipeID)
    if craftMax == nil then return end

    local baseName = recipeInfo.name
    if (not baseName or baseName == "") and C_TradeSkillUI.GetRecipeSchematic then
        local schOk, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
        if schOk and schematic and schematic.name then
            baseName = schematic.name
        end
    end
    if issecretvalue and issecretvalue(baseName) then return end
    if not baseName or baseName == "" then return end

    local function stripColors(s)
        return ns.Utilities:StripFormattingCodes(s)
    end

    local baseStrip = stripColors(baseName)
    local desired = baseName .. " (" .. craftMax .. ")"
    -- Per-call constants, computed once (were recomputed for every region visited).
    local desiredStrip = stripColors(desired)
    local escaped = baseStrip:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    local titlePattern = "^" .. escaped .. "%s*%(%d+)%)$"

    local function isTitleRegion(r)
        if not (r and r.GetText and r.SetText) then return false end
        local t = r:GetText()
        -- Midnight: never tostring/compare secret region text
        if issecretvalue and issecretvalue(t) then return false end
        if t == nil then return false end
        if t == "" then return false end
        local ts = stripColors(t)
        if ts == baseStrip or ts == desiredStrip then return true end
        return ts:match(titlePattern) ~= nil
    end

    -- Cached title fontstring from a previous select: reuse only while it still sits under this
    -- form (within the walk depth) and still holds this recipe's title.
    local cached = schematicForm._wnCraftCountTitleRegion
    if cached then
        local p, depth = cached.GetParent and cached:GetParent(), 0
        while p and p ~= schematicForm and depth <= 13 do
            p = p.GetParent and p:GetParent()
            depth = depth + 1
        end
        if p == schematicForm and isTitleRegion(cached) then
            cached:SetText(desired)
            return
        end
        schematicForm._wnCraftCountTitleRegion = nil
    end

    -- Vararg walkers: no {GetRegions()} / {GetChildren()} table per visited node.
    local visit
    local function scanRegions(...)
        for i = 1, select("#", ...) do
            local r = (select(i, ...))
            if isTitleRegion(r) then
                r:SetText(desired)
                schematicForm._wnCraftCountTitleRegion = r
                return true
            end
        end
        return false
    end
    local function scanChildren(depth, ...)
        for j = 1, select("#", ...) do
            if visit((select(j, ...)), depth) then return true end
        end
        return false
    end
    visit = function(frame, depth)
        if not frame or depth > 12 then return false end
        if scanRegions(frame:GetRegions()) then return true end
        return scanChildren(depth + 1, frame:GetChildren())
    end

    visit(schematicForm, 0)
end

--[[
    Install a secure hook on ProfessionsFrame.CraftingPage.SchematicForm:Init().
    Deferred until TRADE_SKILL_SHOW fires (frame is load-on-demand).
    The hook fires WN_RECIPE_SELECTED with recipeInfo for the companion window.
]]
local customerOrdersHookInstalled = false
local function InstallCustomerOrdersHook()
    if customerOrdersHookInstalled then return end
    if ProfessionsCustomerOrdersFrame and ProfessionsCustomerOrdersFrame.Form and ProfessionsCustomerOrdersFrame.Form.SchematicForm then
        local ok = pcall(hooksecurefunc, ProfessionsCustomerOrdersFrame.Form.SchematicForm, "Init", function(self, recipeInfo)
            if not recipeInfo then return end
            if WarbandNexus and WarbandNexus.SendMessage then
                WarbandNexus:SendMessage(E.RECIPE_SELECTED, recipeInfo)
            end
        end)
        if ok then
            customerOrdersHookInstalled = true
        end
    end
end

local function InstallRecipeHook()
    InstallCustomerOrdersHook()
    if hooksInstalled then return end

    -- ProfessionsFrame is load-on-demand; must exist by now (TRADE_SKILL_SHOW fired)
    if not ProfessionsFrame then return end
    if not ProfessionsFrame.CraftingPage then return end
    if not ProfessionsFrame.CraftingPage.SchematicForm then return end

    local ok, err = pcall(hooksecurefunc, ProfessionsFrame.CraftingPage.SchematicForm, "Init", function(self, recipeInfo)
        if not recipeInfo then return end
        if WarbandNexus and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.RECIPE_SELECTED, recipeInfo)
        end
        C_Timer.After(0, function()
            if not self or not recipeInfo or not recipeInfo.recipeID then return end
            pcall(ApplyCraftCountToSchematicFormTitle, self, recipeInfo)
        end)
    end)

    if ok then
        hooksInstalled = true
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("[ProfessionService] SchematicForm:Init hook installed")
        end
    else
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("[ProfessionService] Hook install failed: " .. tostring(err))
        end
    end
end

-- EXPANSION SUB-PROFESSION COLLECTION

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
            local skillLineID = info.professionID

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

local MIDNIGHT_SKILLLINE_TO_PARENT = {
    [2906] = 171, -- Alchemy
    [2907] = 164, -- Blacksmithing
    [2909] = 333, -- Enchanting
    [2910] = 202, -- Engineering
    [2912] = 182, -- Herbalism
    [2913] = 773, -- Inscription
    [2914] = 755, -- Jewelcrafting
    [2915] = 165, -- Leatherworking
    [2916] = 186, -- Mining
    [2917] = 393, -- Skinning
    [2918] = 197, -- Tailoring
}

-- Base profession skillLine -> Midnight child skillLine (inverse of the table above).
local MIDNIGHT_PARENT_TO_SKILLLINE = {}
for childID, parentID in pairs(MIDNIGHT_SKILLLINE_TO_PARENT) do
    MIDNIGHT_PARENT_TO_SKILLLINE[parentID] = childID
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

    local charKey = ResolveTrackedCharactersTableKey()
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
            for ei = 1, #expansions do
                local exp = expansions[ei]
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

    -- Seed the Midnight skill line for primary professions that were never opened in the
    -- profession window on this character; otherwise the expansion skill is never tracked.
    if GetProfessions and GetProfessionInfo then
        local p1, p2 = GetProfessions()
        local primaries = { p1, p2 }
        for pi = 1, 2 do
            local idx = primaries[pi]
            if idx then
                local okInfo, baseName, _, _, _, _, _, baseSkillLine = pcall(GetProfessionInfo, idx)
                local safeName = okInfo and SafeAPIString(baseName) or nil
                local childID = okInfo and baseSkillLine and MIDNIGHT_PARENT_TO_SKILLLINE[baseSkillLine]
                if safeName and childID then
                    local list = charData.discoveredSkillLines[safeName]
                    local known = false
                    if type(list) == "table" then
                        for li = 1, #list do
                            if list[li] and list[li].id == childID then known = true break end
                        end
                    else
                        list = {}
                        charData.discoveredSkillLines[safeName] = list
                    end
                    if not known then
                        list[#list + 1] = { id = childID }
                    end
                end
            end
        end
    end

    for profName, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            local expansions = {}
            local hasValidSkill = false
            local existingData = charData.professionExpansions[profName]
            for sli = 1, #skillLines do
                local sl = skillLines[sli]
                local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sl.id)
                -- Per-line guard (login burst, PLAYER_LOGOUT teardown): a line that reads 0/0 or not at
                -- all keeps its previous entry. The whole-list guard below only catches the case where
                -- EVERY line is unready; one valid line used to publish the others as 0/0 or drop them.
                local prevLine
                if (not profOk or not profInfo or (tonumber(profInfo.maxSkillLevel) or 0) <= 0)
                    and type(existingData) == "table" then
                    for ei = 1, #existingData do
                        local e = existingData[ei]
                        if e and e.skillLineID == sl.id and (tonumber(e.maxSkillLevel) or 0) > 0 then
                            prevLine = e
                            break
                        end
                    end
                end
                if prevLine then
                    expansions[#expansions + 1] = prevLine
                elseif profOk and profInfo then
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
                    -- 0/0 means the profession system is not loaded yet; keep the stored skill.
                    if bucket and (maxSkillLevel > 0 or not bucket.skill) then
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
            if #expansions > 0 and (hasValidSkill or not existingData) then
                charData.professionExpansions[profName] = expansions
            end
        end
    end
end

-- HELPERS

--[[
    Get the parent profession name for the currently open trade skill.
    Returns nil if profession frame is not open or API unavailable.
]]
-- Normalize to base profession name so equipment is keyed consistently (Alchemy, Tailoring, etc.).
NormalizeProfessionNameForEquipment = function(name)
    local safe = SafeAPIString(name)
    if not safe or safe == "" then return nil end
    local s = safe:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", ""):gsub("^Shadowlands ", "")
    return (s ~= "" and s) or safe
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
    local safe = raw and SafeAPIString(raw) or nil
    return safe and NormalizeProfessionNameForEquipment(safe) or nil
end

-- RECIPE SUMMARY DATA COLLECTION

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

-- Known unobtainable / scrapped recipes from PTR that did not make it to live
local SCRAPPED_UNOBTAINABLE_RECIPE_NAMES = {
    ["odious alloy"] = true,
    ["alliage odieux"] = true,
    ["gehässige legierung"] = true,
    ["gehaessige legierung"] = true,
    ["aleación odiosa"] = true,
    ["aleacion odiosa"] = true,
    ["lega odiosa"] = true,
    ["liga odiosa"] = true,
    ["гнусный сплав"] = true,
    ["отвратительный сплав"] = true,
    ["可憎合金"] = true,
    ["令人憎恶的合金"] = true,
    ["令人憎惡的合金"] = true,
    ["불쾌한 합금"] = true,
    ["역겨운 합금"] = true,
}

local function IsScrappedOrUnobtainableRecipe(recipeID, recipeInfo, nameOverride)
    if recipeInfo and recipeInfo.learned == true then
        return false
    end
    -- Check Blizzard internal flags if present on recipeInfo
    if recipeInfo and (recipeInfo.isInternal or recipeInfo.isTest or recipeInfo.isDummy) then
        return true
    end

    local name = nameOverride or (recipeInfo and recipeInfo.name)
    if not name or (issecretvalue and issecretvalue(name)) then
        return false
    end
    local lower = (ns.Utilities and ns.Utilities.SafeLower and ns.Utilities:SafeLower(name)) or (type(name) == "string" and name:lower()) or ""
    if SCRAPPED_UNOBTAINABLE_RECIPE_NAMES[lower] then
        return true
    end
    if lower:find("odious alloy", 1, true) then
        return true
    end

    -- Universal Blizzard internal/placeholder tags across all professions ([DNT], [PH], [TEST], (Deprecated), etc.)
    if lower:find("%[dnt%]")
        or lower:find("%[ph%]")
        or lower:find("%[test%]")
        or lower:find("%(test%)")
        or lower:find("%(deprecated%)")
        or lower:find("%(unused%)")
        or lower:find("%(internal%)")
        or lower:find("qa test")
    then
        return true
    end

    return false
end
ns.IsScrappedOrUnobtainableRecipe = IsScrappedOrUnobtainableRecipe

local function SanitizeScrappedRecipesForCharacter(charData)
    if not charData or type(charData) ~= "table" then return false end
    if not charData.recipes or type(charData.recipes) ~= "table" then return false end

    local anyModified = false
    for slID, rd in pairs(charData.recipes) do
        if type(rd) == "table" and rd.recipeList and type(rd.recipeList) == "table" then
            local modified = false
            local newList = {}
            local removedCount = 0
            for ri = 1, #rd.recipeList do
                local r = rd.recipeList[ri]
                if r and not r.learned and IsScrappedOrUnobtainableRecipe(r.recipeID, nil, r.name) then
                    modified = true
                    removedCount = removedCount + 1
                else
                    newList[#newList + 1] = r
                end
            end
            if modified then
                anyModified = true
                rd.recipeList = newList
                rd.totalCount = math.max(0, (rd.totalCount or 0) - removedCount)
                local bucket = charData.professionData and charData.professionData.bySkillLine and charData.professionData.bySkillLine[slID]
                if bucket and bucket.recipes and bucket.recipes.totalCount then
                    bucket.recipes.totalCount = math.max(0, (bucket.recipes.totalCount or 0) - removedCount)
                end
            end
        end
    end
    return anyModified
end

local function SanitizeAllStoredScrappedRecipes()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.characters then return end
    for charKey, charData in pairs(WarbandNexus.db.global.characters) do
        SanitizeScrappedRecipesForCharacter(charData)
    end
end
ns.SanitizeAllStoredScrappedRecipes = SanitizeAllStoredScrappedRecipes

local function CollectRecipeSummaryData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI then return end
    if not C_TradeSkillUI.GetAllRecipeIDs or not C_TradeSkillUI.GetRecipeInfo then return end

    local charKey = ResolveTrackedCharactersTableKey()
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
    if not PS.MIDNIGHT_WEEKLY_SOURCES[skillLineID] or type(PS.MIDNIGHT_WEEKLY_SOURCES[skillLineID]) ~= "table" then
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
    local recipeList = {}
    local rawRecipeCount = #recipeIDs
    local categoryCache = {}

    for i = 1, #recipeIDs do
        local recipeID = recipeIDs[i]
        local riOk, recipeInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if riOk and recipeInfo then
            -- Filter to Midnight categories only (strict content isolation).
            local categoryID = recipeInfo.categoryID
            -- Locale-independent first: IsRecipeInSkillLine (12.1.5 API doc) asks by ID whether the
            -- recipe belongs to this Midnight child skill line. The category-name test below matches
            -- the English word "Midnight" and fails where the client translates the expansion name.
            local inSkillLine
            if C_TradeSkillUI.IsRecipeInSkillLine then
                local okSl, isIn = pcall(C_TradeSkillUI.IsRecipeInSkillLine, recipeID, skillLineID)
                if okSl and not (issecretvalue and issecretvalue(isIn)) and type(isIn) == "boolean" then
                    inSkillLine = isIn
                end
            end
            if inSkillLine == nil then
                inSkillLine = IsMidnightRecipeCategory(categoryID, categoryCache)
            end
            if inSkillLine then
                if not IsScrappedOrUnobtainableRecipe(recipeID, recipeInfo) then
                    totalCount = totalCount + 1

                    if recipeInfo.learned == true then
                        knownCount = knownCount + 1
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
    end

    local prevRecipe = charData.recipes and charData.recipes[skillLineID]
    -- 0 Midnight recipes while a populated summary exists = category data not ready (or teardown);
    -- persisting it zeroed known/first-craft counts and the weekly firstCraft progress.
    if totalCount == 0 and prevRecipe and (tonumber(prevRecipe.totalCount) or 0) > 0 then
        return
    end
    local recipeDirty = not prevRecipe
        or prevRecipe.totalCount ~= totalCount
        or prevRecipe.knownCount ~= knownCount
        or prevRecipe.firstCraftDoneCount ~= firstCraftDoneCount
        or prevRecipe.skillUpCount ~= skillUpCount

    charData.recipes[skillLineID] = {
        skillLineID = skillLineID,
        professionName = professionName,
        expansionName = expansionName,
        totalCount = totalCount,
        knownCount = knownCount,
        firstCraftDoneCount = firstCraftDoneCount,
        firstCraftTotalCount = firstCraftTotalCount,
        firstCraftAvailableCount = firstCraftAvailableCount,
        skillUpCount = skillUpCount,
        recipeList = recipeList,
        lastScan = time(),
    }

    -- 2026-10-22: no stored duplicates. knownRecipes was recipeList's learned rows again (readers
    -- derive it: ProfessionService_Queries RecipeRowKnowsRecipe), firstCraftCount repeated
    -- firstCraftDoneCount, and bucket.recipes repeated these counters with no reader.
    local bucket = EnsureSkillLineBucket(charData, skillLineID, professionName, expansionName)
    if bucket then
        bucket.recipes = nil
    end
    -- Keep weekly knowledge counters in sync after recipe scans.
    if PS.CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, professionName, expansionName) then
        NotifyCollectorUpdate("profession", E.PROFESSION_DATA_UPDATED, charKey)
    end

    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("[Recipes] source=GetAllRecipeIDs raw=" .. tostring(rawRecipeCount)
            .. " filteredMidnight=" .. tostring(totalCount)
            .. " prof=" .. tostring(professionName) .. " slID=" .. tostring(skillLineID)
            .. " known/total=" .. tostring(knownCount) .. "/" .. tostring(totalCount)
            .. " firstCraft(done/total)=" .. tostring(firstCraftDoneCount) .. "/" .. tostring(firstCraftTotalCount)
            .. " available=" .. tostring(firstCraftAvailableCount)
            .. " skillUp=" .. tostring(skillUpCount))
        if DebugVerbosePrint then
            DebugVerbosePrint("[ProfDebug] " .. tostring(professionName)
                .. " (slID " .. tostring(skillLineID) .. ")"
                .. " raw=" .. tostring(rawRecipeCount)
                .. ", midnight=" .. tostring(totalCount)
                .. ", learned=" .. tostring(knownCount)
                .. ", firstCraft=" .. tostring(firstCraftDoneCount) .. "/" .. tostring(firstCraftTotalCount))
        end
    end

    if recipeDirty then
        NotifyCollectorUpdate("recipe", E.RECIPE_DATA_UPDATED, charKey)
    end
end

-- COOLDOWN DATA COLLECTION

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

    local charKey = ResolveTrackedCharactersTableKey()
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
    local prevCooldownFingerprint = CooldownStateFingerprint(cooldownEntries)
    local knownCooldownIDs = {}
    local found = 0

    for ri = 1, #recipeIDsToCheck do
        local recipeID = recipeIDsToCheck[ri]
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
                            recipeName = SafeAPIString(recipeInfo.name)
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
                        recipeName  = recipeName
                            or (cooldownEntries[recipeID] and cooldownEntries[recipeID].recipeName)
                            or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
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
        for vi = 1, #recipeIDsToCheck do
            validSet[recipeIDsToCheck[vi]] = true
        end
        for recipeID in pairs(cooldownEntries) do
            if not validSet[recipeID] then
                cooldownEntries[recipeID] = nil
            end
        end
    end

    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("[Cooldowns] Collected " .. found .. " cooldown(s) for skillLineID=" .. tostring(skillLineID) .. " (fullScan=" .. tostring(needFullScan) .. ")")
    end

    local bucket = EnsureSkillLineBucket(charData, skillLineID, baseProfName, nil)
    if bucket then
        bucket.cooldowns = cooldownEntries
        bucket.lastUpdate = now
    end

    if CooldownStateFingerprint(cooldownEntries) ~= prevCooldownFingerprint then
        NotifyCollectorUpdate("cooldowns", E.PROFESSION_COOLDOWNS_UPDATED, charKey)
    end
end

-- CRAFTING ORDERS DATA COLLECTION

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

    Personal: C_CraftingOrders.GetPersonalOrdersInfo() (one entry per profession).
    Guild: no synchronous getter exists (12.1.5 API doc); the count arrives with
    CRAFTINGORDERS_UPDATE_ORDER_COUNT, passed in as guildCountFromEvent, else the last one seen is kept.
]]
local function CollectCraftingOrdersData(guildCountFromEvent)
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_CraftingOrders then return end

    local charKey = ResolveTrackedCharactersTableKey()
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
    local baseProfEnum = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then
            baseProfName = SafeAPIString(baseInfo.professionName)
            if type(baseInfo.profession) == "number" then baseProfEnum = baseInfo.profession end
        end
    end

    local prevOrders = charData.craftingOrders[skillLineID]
    -- An unread personal list (pcall error / no table) keeps the stored count instead of writing 0.
    local personalCount = (prevOrders and prevOrders.personalCount) or 0
    local guildCount = guildCountFromEvent or (prevOrders and prevOrders.guildCount) or 0
    local publicCount = 0

    -- Personal orders: CraftingOrderPersonalOrdersInfo { profession (Enum.Profession), numPersonalOrders, professionName }
    if baseProfEnum and C_CraftingOrders.GetPersonalOrdersInfo then
        local ok, infos = pcall(C_CraftingOrders.GetPersonalOrdersInfo)
        if ok and type(infos) == "table" then
            personalCount = 0
            for i = 1, #infos do
                local info = infos[i]
                if type(info) == "table" and info.profession == baseProfEnum then
                    if type(info.numPersonalOrders) == "number" then personalCount = info.numPersonalOrders end
                    break
                end
            end
        end
    end

    -- Claimed order (adds to personal context)
    if C_CraftingOrders.GetClaimedOrder then
        local ok, order = pcall(C_CraftingOrders.GetClaimedOrder)
        if ok and order then
            -- Claimed order exists — count is already included in personal
        end
    end

    local ordersDirty = not prevOrders
        or prevOrders.personalCount ~= personalCount
        or prevOrders.guildCount ~= guildCount
        or prevOrders.publicCount ~= publicCount

    charData.craftingOrders[skillLineID] = {
        personalCount = personalCount,
        guildCount    = guildCount,
        publicCount   = publicCount,
        lastUpdate    = time(),
    }

    local bucket = EnsureSkillLineBucket(charData, skillLineID, baseProfName, nil)
    if bucket then
        bucket.orders = charData.craftingOrders[skillLineID]
    end

    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("[Orders] Collected for skillLineID=" .. tostring(skillLineID) .. " personal=" .. personalCount .. " guild=" .. guildCount)
    end

    if ordersDirty then
        NotifyCollectorUpdate("orders", E.CRAFTING_ORDERS_UPDATED, charKey)
    end
end

-- EVENT HANDLERS

-- TRADE_SKILL_LIST_UPDATE can fire several times per craft; full GetAllRecipeIDs scans are expensive.
local RECIPE_SUMMARY_SCAN_MIN_INTERVAL = 2.0
local lastRecipeSummaryScanAt = 0
local recipeSummaryScanPending = false
local recipeSummaryScanScheduled = false
local lastTradeSkillListSkillLineID = nil
local tradeSkillListUpdateNeedsReschedule = false

local tradeSkillListUpdatePending = false

local function RunRecipeSummaryScanAndKnowledge()
    recipeSummaryScanPending = false
    recipeSummaryScanScheduled = false
    lastRecipeSummaryScanAt = GetTime()
    BeginCollectorBurst()
    pcall(CollectRecipeSummaryData)
    EndCollectorBurst(false)
end

local function ScheduleThrottledRecipeSummaryScan(forceImmediate)
    recipeSummaryScanPending = true
    if recipeSummaryScanScheduled then return end

    local delay = 0.1
    if not forceImmediate then
        local elapsed = GetTime() - lastRecipeSummaryScanAt
        if elapsed < RECIPE_SUMMARY_SCAN_MIN_INTERVAL then
            delay = RECIPE_SUMMARY_SCAN_MIN_INTERVAL - elapsed
        end
    end

    recipeSummaryScanScheduled = true
    C_Timer.After(delay, function()
        if not recipeSummaryScanPending then
            recipeSummaryScanScheduled = false
            return
        end
        if not WarbandNexus or not IsCurrentCharacterTracked() then
            recipeSummaryScanPending = false
            recipeSummaryScanScheduled = false
            return
        end
        RunRecipeSummaryScanAndKnowledge()
    end)
end

local function RunLightTradeSkillListCollectors()
    local now = GetTime()
    if (now - lastLightListCollectorAt) < LIGHT_LIST_COLLECTOR_MIN_INTERVAL then
        tradeSkillListUpdateNeedsReschedule = true
        return
    end
    lastLightListCollectorAt = now

    BeginCollectorBurst()
    pcall(CollectConcentrationData)
    pcall(CollectAllExpansionProfessions, true)
    EndCollectorBurst(false)
    ScheduleThrottledRecipeSummaryScan(false)
end

local function RunAllProfessionCollectors(silentUiNotify, atLogout)
    recipeSummaryScanPending = false
    recipeSummaryScanScheduled = false
    lastRecipeSummaryScanAt = GetTime()
    if not WarbandNexus then return end
    local prevSuppress = collectorUiNotifySuppressed
    if silentUiNotify then
        collectorUiNotifySuppressed = true
    end
    BeginCollectorBurst()
    pcall(CollectConcentrationData)
    pcall(CollectKnowledgeData)
    pcall(CollectAllExpansionProfessions, true)
    pcall(CollectRecipeSummaryData)
    pcall(CollectCooldownData)
    -- Order counts are not re-read during PLAYER_LOGOUT teardown; the order events kept them current.
    if not atLogout then pcall(CollectCraftingOrdersData) end
    pcall(CollectEquipmentDataForCurrentProfession)
    pcall(CollectEquipmentByDetection)
    -- Only WN_* when a collector marked dirty — never force PROFESSION_DATA_UPDATED every open.
    EndCollectorBurst(false)
    collectorUiNotifySuppressed = prevSuppress
end

local function RunProfessionWindowSyncCollectors()
    professionWindowSyncTimer = nil
    professionWindowInitialSyncComplete = true
    if not WarbandNexus or not IsCurrentCharacterTracked() then return end
    if WarbandNexus.UpdateProfessionData then
        pcall(WarbandNexus.UpdateProfessionData, WarbandNexus)
    end
    RunAllProfessionCollectors()
    professionWindowSyncedSkillLineID = GetOpenTradeSkillChildSkillLineID()
    if ProfessionWindowCollectorsNeedRetry() and not professionWindowRetryUsed then
        professionWindowRetryUsed = true
        C_Timer.After(0.55, function()
            if not WarbandNexus or not IsCurrentCharacterTracked() then return end
            if not IsProfessionTradeWindowReady() then return end
            if ProfessionWindowCollectorsNeedRetry() then
                RunAllProfessionCollectors(true)
            end
        end)
    end
end

local function ScheduleProfessionWindowSync()
    if professionWindowSyncTimer and professionWindowSyncTimer.Cancel then
        professionWindowSyncTimer:Cancel()
    end
    professionWindowSyncTimer = C_Timer.NewTimer(PROFESSION_WINDOW_SYNC_DEBOUNCE, RunProfessionWindowSyncCollectors)
end

local function IsProfessionWindowOpenGrace()
    return professionWindowOpenAt > 0
        and (GetTime() - professionWindowOpenAt) < PROFESSION_WINDOW_OPEN_GRACE
end

--- True while the Blizzard profession window is open or in the post-open grace window.
--- UI layers use this to coalesce professions-tab PopulateContent bursts.
function WarbandNexus:IsProfessionTradeWindowUiCoalesce()
    if IsProfessionWindowOpenGrace() then return true end
    return IsProfessionTradeWindowReady()
end

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

    -- Grace anchor: TRADE_SKILL_SHOW only (list updates must not extend grace or UI refresh storms).
    professionWindowOpenAt = GetTime()
    professionWindowInitialSyncComplete = false
    professionWindowRetryUsed = false
    professionWindowSyncedSkillLineID = nil

    -- Trailing debounce: one collector pass after API settles (replaces fixed 0.6s + 1.2s double run).
    ScheduleProfessionWindowSync()

    -- Notify companion window
    if self.SendMessage then
        self:SendMessage(E.PROFESSION_WINDOW_OPENED)
    end
end

--[[
    Called on TRADE_SKILL_DATA_SOURCE_CHANGED (switched profession while window is open).
    Resets sync state and schedules a full collector pass for the newly active profession.
]]
function WarbandNexus:OnTradeSkillDataSourceChanged()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end

    professionWindowOpenAt = GetTime()
    professionWindowInitialSyncComplete = false
    professionWindowRetryUsed = false
    professionWindowSyncedSkillLineID = nil

    ScheduleProfessionWindowSync()
end

--[[
    Called on TRADE_SKILL_CLOSE (profession window closed).
    Notifies companion window.
]]
function WarbandNexus:OnTradeSkillClose()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end

    lastTradeSkillListSkillLineID = nil
    professionWindowOpenAt = 0
    professionWindowInitialSyncComplete = false
    professionWindowRetryUsed = false
    professionWindowSyncedSkillLineID = nil
    if professionWindowSyncTimer and professionWindowSyncTimer.Cancel then
        professionWindowSyncTimer:Cancel()
        professionWindowSyncTimer = nil
    end
    
    if self.SendMessage then
        self:SendMessage(E.PROFESSION_WINDOW_CLOSED)
    end
end

--[[
    Called on TRADE_SKILL_LIST_UPDATE (recipe list changed, expansion tab switched, or after crafting).
    Refreshes concentration so the current expansion's concentration is stored.
    Without this, switching e.g. Dragon Isles → Khaz Algar keeps showing the previous expansion's
    value (e.g. 1000/1000) while the game shows the current one (e.g. 479/1000).
]]
function WarbandNexus:OnTradeSkillListUpdate()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    
    -- Only process if profession frame is open
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end
    
    if tradeSkillListUpdatePending then
        tradeSkillListUpdateNeedsReschedule = true
        return
    end
    tradeSkillListUpdatePending = true
    
    C_Timer.After(0.5, function()
        tradeSkillListUpdatePending = false
        if not WarbandNexus or not IsCurrentCharacterTracked() then return end

        local skillLineID = GetOpenTradeSkillChildSkillLineID()
        local expansionSwitched = lastTradeSkillListSkillLineID ~= nil
            and skillLineID ~= nil
            and skillLineID ~= lastTradeSkillListSkillLineID
        if skillLineID then
            lastTradeSkillListSkillLineID = skillLineID
        end

        if expansionSwitched then
            -- Open debouncer already ran full collectors for this skill line; avoid a second full pass.
            if skillLineID and professionWindowSyncedSkillLineID
                and skillLineID == professionWindowSyncedSkillLineID then
                RunLightTradeSkillListCollectors()
            elseif IsProfessionWindowOpenGrace() and not professionWindowInitialSyncComplete then
                ScheduleProfessionWindowSync()
            else
                RunAllProfessionCollectors()
                professionWindowSyncedSkillLineID = skillLineID
            end
        elseif IsProfessionWindowOpenGrace() then
            -- Initial profession open: coalesce early list bursts into the open debouncer once.
            if not professionWindowInitialSyncComplete then
                ScheduleProfessionWindowSync()
            end
        else
            -- Post-craft bursts: avoid full recipe/cooldown/order rescans every list tick.
            RunLightTradeSkillListCollectors()
        end

        if tradeSkillListUpdateNeedsReschedule then
            tradeSkillListUpdateNeedsReschedule = false
            if WarbandNexus.OnTradeSkillListUpdate then
                WarbandNexus:OnTradeSkillListUpdate()
            end
        end
    end)
end

--[[
    Called on CRAFTINGORDERS_UPDATE_ORDER_COUNT (orderType, numOrders): the crafter order page
    publishes its per-type tab counts here. The only source of the guild order count.
]]
function WarbandNexus:OnCraftingOrdersOrderCount(orderType, numOrders)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if type(orderType) ~= "number" or type(numOrders) ~= "number" then return end
    local guildType = Enum and Enum.CraftingOrderType and Enum.CraftingOrderType.Guild
    pcall(CollectCraftingOrdersData, (guildType and orderType == guildType) and numOrders or nil)
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
        ScheduleThrottledRecipeSummaryScan(false)
    end)
end

local professionQuestProgressDebounceTimer, professionQuestProgressLastRunAt = nil, nil
-- Throttle, not debounce (2026-10-22): QUEST_LOG_UPDATE / bag / trait-currency fire every few
-- hundred ms while questing, and the old 0.35s trailing timer was recreated on each one, re-running
-- every quest-flag list per profession each time the stream paused. Now: first trigger runs after
-- the 0.35s settle delay, later triggers fold into one run at most every MIN_INTERVAL; that run
-- reads live state, so the final state is never lost.
local PROFESSION_QUEST_PROGRESS_SETTLE, PROFESSION_QUEST_PROGRESS_MIN_INTERVAL = 0.35, 3.0

local function RunProfessionQuestProgressRefresh()
    if professionQuestProgressDebounceTimer then
        professionQuestProgressDebounceTimer:Cancel()
        professionQuestProgressDebounceTimer = nil
    end
    professionQuestProgressLastRunAt = GetTime()
    if not WarbandNexus or not IsCurrentCharacterTracked() then return end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end
    local charData = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end
    if PS.RefreshAllMidnightKnowledgeProgressForCharacter(charData) > 0 then
        NotifyCollectorUpdate("profession", E.PROFESSION_DATA_UPDATED, charKey)
    end
end

function WarbandNexus:OnProfessionQuestProgressChanged(immediate)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end

    if immediate or not (C_Timer and C_Timer.NewTimer) then
        RunProfessionQuestProgressRefresh()
        return
    end
    -- A run is already owed; it reads live state when it fires.
    if professionQuestProgressDebounceTimer then return end
    local delay = PROFESSION_QUEST_PROGRESS_SETTLE
    local lastRunAt = professionQuestProgressLastRunAt
    if lastRunAt then
        local remaining = (lastRunAt + PROFESSION_QUEST_PROGRESS_MIN_INTERVAL) - GetTime()
        if remaining > delay then
            delay = remaining
        end
    end
    professionQuestProgressDebounceTimer = C_Timer.NewTimer(delay, RunProfessionQuestProgressRefresh)
end

function WarbandNexus:RefreshCurrentCharacterKnowledgeProgress(suppressNotify)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end
    if PS.RefreshAllMidnightKnowledgeProgressForCharacter(charData) > 0 then
        if not suppressNotify then
            NotifyCollectorUpdate("profession", E.PROFESSION_DATA_UPDATED, charKey)
        end
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
    -- Open-window sync collectors already refresh expansion + profession buckets.
    if IsProfessionTradeWindowReady() then return end
    
    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    -- Refresh basic profession data (names, icons, skill levels)
    if self.UpdateProfessionData then
        self:UpdateProfessionData()
    end

    -- Compare current professions to detect profession changes
    local currentProfs = {}
    local currentPrimaryCount = 0
    if charData.professions then
        for k, prof in pairs(charData.professions) do
            if prof and prof.name then
                currentProfs[prof.name] = true
                if prof.name ~= "Cooking" and prof.name ~= "Fishing" then
                    currentPrimaryCount = currentPrimaryCount + 1
                end
            end
        end
    end

    -- Clear stale data for unlearned professions.
    -- ONLY clear stale data if currentPrimaryCount >= 2, or if previously known primary
    -- professions count was <= 1 and currentPrimaryCount >= 1.
    -- If GetProfessions() returns only 1 profession while the character previously had 2,
    -- it is a partial/lagged scan: NEVER purge the other primary profession!
    local existingPrimaryCount = 0
    if charData.professionExpansions then
        for profName in pairs(charData.professionExpansions) do
            if profName ~= "Cooking" and profName ~= "Fishing" then
                existingPrimaryCount = existingPrimaryCount + 1
            end
        end
    end
    local canClearStale = (currentPrimaryCount >= 2) or (existingPrimaryCount <= 1 and currentPrimaryCount >= 1)
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

-- REAL-TIME UPDATE SYSTEM

--[[
    Build a reverse lookup: concentrationCurrencyID → professionName
    Used by OnConcentrationCurrencyChanged to quickly identify which
    profession's concentration was affected by a CURRENCY_DISPLAY_UPDATE.
    
    @return table { [currencyID] = profName, ... }
]]
local function BuildConcentrationCurrencyMap()
    local map = {}
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return map end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return map end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData or not charData.concentration then return map end

    for key, concData in pairs(charData.concentration) do
        if type(concData) == "table" and concData.currencyID and concData.currencyID > 0 then
            -- Legacy profession-name rows share a currencyID with their skillLineID row (separate
            -- tables after a reload); live updates must land on the skillLineID row.
            if type(key) == "number" or map[concData.currencyID] == nil then
                map[concData.currencyID] = key
            end
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
    if (GetTime() - lastConcentrationCollectorAt) < CONCENTRATION_HOOK_SKIP_SEC then
        return
    end
    
    -- Rebuild map if empty (first call or after reload)
    if not next(concentrationCurrencyMap) then
        concentrationCurrencyMap = BuildConcentrationCurrencyMap()
    end
    
    local key = concentrationCurrencyMap[currencyID]
    if not key then return end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end

    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData or not charData.concentration or not charData.concentration[key] then return end

    local ok, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if ok and currInfo then
        local entry = charData.concentration[key]
        entry.current    = currInfo.quantity or entry.current or 0
        entry.max        = currInfo.maxQuantity or entry.max or 0
        entry.lastUpdate = time()
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("[Concentration] Real-time update: key=" .. tostring(key) .. " = " .. tostring(entry.current) .. "/" .. tostring(entry.max))
        end
        
        -- Notify consumers (tooltip, UI)
        if self.SendMessage then
            self:SendMessage(E.CONCENTRATION_UPDATED, charKey)
        end
    end
end

local progressCurrencyRefreshPending = false
local pendingProgressCurrencySkillLineID = nil

function WarbandNexus:OnProfessionProgressCurrencyChanged(currencyID)
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end
    if not currencyID or not PS.MIDNIGHT_CATCHUP_CURRENCY[currencyID] then return end

    local skillLineID = PS.catchUpCurrencyToSkillLine[currencyID]
    if skillLineID then
        pendingProgressCurrencySkillLineID = skillLineID
    end
    if progressCurrencyRefreshPending then return end
    progressCurrencyRefreshPending = true

    C_Timer.After(0.75, function()
        progressCurrencyRefreshPending = false
        if not WarbandNexus or not IsCurrentCharacterTracked() then return end
        local charKey = ResolveTrackedCharactersTableKey()
        if not charKey then return end
        local charData = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
            and WarbandNexus.db.global.characters[charKey]
        if not charData then return end

        local refreshed = 0
        local targetSkillLineID = pendingProgressCurrencySkillLineID
        pendingProgressCurrencySkillLineID = nil
        if targetSkillLineID then
            if PS.CollectMidnightKnowledgeProgressForSkillLine(charData, targetSkillLineID, nil, "Midnight") then
                refreshed = 1
            end
        else
            refreshed = PS.RefreshAllMidnightKnowledgeProgressForCharacter(charData)
        end

        if refreshed > 0 then
            NotifyCollectorUpdate("profession", E.PROFESSION_DATA_UPDATED, charKey)
        end
    end)
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
            WarbandNexus:CollectKnowledgeOnLogin({ reason = "event" })
        end)
        
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("[Knowledge] Real-time refresh triggered by spec change")
        end
    end)
end

---Flush debounced profession writes on PLAYER_LOGOUT (sync; no new C_Timer).
function WarbandNexus:FlushProfessionOnLogout()
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if not IsCurrentCharacterTracked() then return end

    if professionQuestProgressDebounceTimer then
        professionQuestProgressDebounceTimer:Cancel()
        professionQuestProgressDebounceTimer = nil
    end

    -- On logout teardown, GetProfessions() returns nil, so we do NOT call UpdateProfessionData.
    -- Live saves during gameplay already persisted latest skill levels.
    pcall(CollectAllExpansionProfessions, false)

    local charKey = ResolveTrackedCharactersTableKey()
    local charData = charKey and self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if charData and IsCurrentCharacterTracked() then
        PS.RefreshAllMidnightKnowledgeProgressForCharacter(charData)
    end

    local windowOpen = false
    if C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady then
        local ok, ready = pcall(C_TradeSkillUI.IsTradeSkillReady)
        windowOpen = ok and ready == true
    end

    local listPending = tradeSkillListUpdatePending
    local knowledgePending = knowledgeRefreshPending
    if not windowOpen and not listPending and not knowledgePending then return end

    tradeSkillListUpdatePending = false
    knowledgeRefreshPending = false

    -- Only flush work a debounce still owed. An open window alone is no reason to re-read every
    -- C_TradeSkillUI collector during PLAYER_LOGOUT teardown; live events already persisted it.
    if windowOpen and listPending then
        RunAllProfessionCollectors(nil, true)
    end

    if knowledgePending then
        pcall(function()
            WarbandNexus:CollectKnowledgeOnLogin({ reason = "event" })
        end)
    end
end

--[[
    Rebuild the concentration currency map.
    Called after any concentration collection to keep the map current.
]]
function WarbandNexus:RebuildConcentrationCurrencyMap()
    concentrationCurrencyMap = BuildConcentrationCurrencyMap()
end

-- PERIODIC RECHARGE TIMER (1-minute tick)

--[[
    Start a 1-minute repeating ticker that refreshes the logged-in profession row estimate.
    View-only: no WN_CONCENTRATION_UPDATED (DB unchanged; avoids PopulateContent storms while idle).
]]
local rechargeTickerHandle = nil

function WarbandNexus:StartRechargeTimer()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    if rechargeTickerHandle then return end  -- Already running
    
    rechargeTickerHandle = C_Timer.NewTicker(60, function()
        if not WarbandNexus then return end
        -- Guard each tick: stop if module was disabled mid-session
        if not ns.Utilities:IsModuleEnabled("professions") then return end
        
        local charKey = ResolveTrackedCharactersTableKey()
        if not charKey then return end
        if WarbandNexus.TryRefreshProfessionsLoggedInRow then
            WarbandNexus:TryRefreshProfessionsLoggedInRow(charKey, true)
        end
    end)
    
    if IsDebugModeEnabled and IsDebugModeEnabled() and DebugVerbosePrint then
        DebugVerbosePrint("[Recharge Timer] Started (60s interval)")
    end
end

function WarbandNexus:StopRechargeTimer()
    if rechargeTickerHandle then
        rechargeTickerHandle:Cancel()
        rechargeTickerHandle = nil
        
        if IsDebugModeEnabled and IsDebugModeEnabled() and DebugVerbosePrint then
            DebugVerbosePrint("[Recharge Timer] Stopped")
        end
    end
end

-- SATELLITE EXPORTS (ProfessionService_WeeklyKnowledge / _Login / _Queries bind these at load)

PS.IsCurrentCharacterTracked = IsCurrentCharacterTracked
PS.ResolveTrackedCharactersTableKey = ResolveTrackedCharactersTableKey
PS.CurrentSessionCanonicalCharacterKey = CurrentSessionCanonicalCharacterKey
PS.SafeAPIString = SafeAPIString
PS.EnsureSkillLineBucket = EnsureSkillLineBucket
PS.NotifyCollectorUpdate = NotifyCollectorUpdate
PS.CollectKnowledgeForSkillLine = CollectKnowledgeForSkillLine
PS.CollectAllExpansionProfessions = CollectAllExpansionProfessions
PS.MIDNIGHT_SKILLLINE_TO_PARENT = MIDNIGHT_SKILLLINE_TO_PARENT
PS.SanitizeAllStoredScrappedRecipes = SanitizeAllStoredScrappedRecipes

-- EXPORT

ns.ProfessionService = WarbandNexus
