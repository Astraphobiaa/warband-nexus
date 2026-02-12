--[[
    Warband Nexus - Profession Service
    Lightweight service for profession-related data collection and persistence.
    
    Responsibilities:
    - Collect concentration data when profession window opens (TRADE_SKILL_SHOW)
    - Persist concentration per character in db.global.characters[charKey].concentration
    - Provide GetAllConcentrationData() API for tooltip/UI consumers
    - Install recipe selection hook (deferred until ProfessionsFrame exists)
    
    Data flow:
    TRADE_SKILL_SHOW → CollectConcentrationData() → db.global → SendMessage(WN_CONCENTRATION_UPDATED)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- STATE
-- ============================================================================

local hooksInstalled = false          -- Guard: install SchematicForm hook only once

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

    -- Method 2: If Method 1 fails, try all stored discoveredSkillLines
    local skillLinesToTry = {}
    if skillLineID then
        skillLinesToTry[1] = skillLineID
    end
    -- Also add discovered skill lines for this profession from DB
    if charData.discoveredSkillLines then
        for profName, lines in pairs(charData.discoveredSkillLines) do
            for _, slID in ipairs(lines) do
                -- Avoid duplicates
                local isDup = false
                for _, existing in ipairs(skillLinesToTry) do
                    if existing == slID then isDup = true; break end
                end
                if not isDup then
                    skillLinesToTry[#skillLinesToTry + 1] = slID
                end
            end
        end
    end

    local found = 0
    for _, slID in ipairs(skillLinesToTry) do
        local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, slID)

        if WarbandNexus.Debug then
            WarbandNexus:Debug("[Concentration] Trying skillLineID=" .. slID .. " -> currencyID=" .. tostring(currencyID))
        end

        if concOk and currencyID and currencyID > 0 then
            local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
            if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                -- Determine the profession name for this skill line
                local profKey = baseProfName
                if not profKey then
                    local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slID)
                    if piOk and profInfo then
                        profKey = profInfo.professionName or profInfo.parentProfessionName
                    end
                end
                profKey = profKey or ("Profession_" .. slID)

                charData.concentration[profKey] = {
                    current      = currInfo.quantity or 0,
                    max          = currInfo.maxQuantity or 0,
                    currencyID   = currencyID,
                    skillLineID  = slID,
                    lastUpdate   = time(),
                }
                found = found + 1
                if WarbandNexus.Debug then
                    WarbandNexus:Debug("[Concentration] Stored: " .. profKey .. " = "
                        .. tostring(currInfo.quantity) .. "/" .. tostring(currInfo.maxQuantity)
                        .. " (currencyID=" .. currencyID .. ", skillLine=" .. slID .. ")")
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
    local currencyName = ""
    local currencyIcon = nil
    local specTabs = {}
    local foundCurrency = false

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

        specTabs[#specTabs + 1] = {
            tabID = tabID,
            name  = tabName,
            state = tabState,
        }

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

    local result = {
        skillLineID      = skillLineID,
        hasUnspentPoints = (unspentTotal > 0),
        unspentPoints    = unspentTotal,
        spentPoints      = spentTotal,
        maxPoints        = maxTotal,
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

    -- Get base profession name for storage key
    local profName = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then
            profName = baseInfo.professionName
        end
    end
    profName = profName or ("Profession_" .. skillLineID)

    local result = CollectKnowledgeForSkillLine(skillLineID, profName)
    if result then
        charData.knowledgeData[profName] = result
    end

    -- Fire event for consumers
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_KNOWLEDGE_UPDATED", charKey)
    end
end

-- ============================================================================
-- RECIPE KNOWLEDGE COLLECTION
-- ============================================================================

--[[
    Collect known recipes for the current character's open profession.
    Called on TRADE_SKILL_SHOW after a delay to ensure API readiness.
    
    Stores per profession (keyed by skillLineID):
    {
        professionName  = string,
        skillLevel      = number,
        maxSkillLevel   = number,
        knownRecipes    = { [recipeID] = true, ... },
        lastScan        = number (timestamp),
    }
]]
local function CollectRecipeData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    if not charData.recipes then
        charData.recipes = {}
    end

    -- Determine the profession identity for the currently open trade skill
    local professionName = nil
    local skillLineID = nil
    local skillLevel, maxSkillLevel = 0, 0

    -- Try GetChildProfessionInfos (expansion-specific sub-professions)
    if C_TradeSkillUI.GetChildProfessionInfos then
        local ok, childInfos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
        if ok and childInfos and #childInfos > 0 then
            for i = 1, #childInfos do
                local info = childInfos[i]
                if info and info.skillLineID and not skillLineID then
                    skillLineID = info.skillLineID
                    professionName = info.parentProfessionName or info.professionName
                end
            end
        end
    end

    -- Fallback: GetBaseProfessionInfo
    if not skillLineID and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then
            skillLineID = baseInfo.professionID or baseInfo.skillLineID
            professionName = professionName or baseInfo.professionName
        end
    end

    -- Get skill level
    if skillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if profOk and profInfo then
            skillLevel = profInfo.skillLevel or 0
            maxSkillLevel = profInfo.maxSkillLevel or 0
            if not professionName or professionName == "" then
                professionName = profInfo.professionName or profInfo.parentProfessionName
            end
        end
    end

    -- Get all recipe IDs
    if not C_TradeSkillUI.GetAllRecipeIDs then return end

    local recipeOk, allRecipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs)
    if not recipeOk or not allRecipeIDs or #allRecipeIDs == 0 then return end

    local knownRecipes = {}
    local recipeCount = 0

    for ri = 1, #allRecipeIDs do
        local recipeID = allRecipeIDs[ri]
        local isKnown = true

        if C_TradeSkillUI.GetRecipeInfo then
            local riOk, recipeInfo = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
            if riOk and recipeInfo and recipeInfo.learned == false then
                isKnown = false
            end
        end

        if isKnown then
            knownRecipes[recipeID] = true
            recipeCount = recipeCount + 1
        end
    end

    local storeKey = skillLineID or professionName or "unknown"
    professionName = professionName or "Unknown Profession"

    charData.recipes[storeKey] = {
        professionName = professionName,
        skillLevel     = skillLevel,
        maxSkillLevel  = maxSkillLevel,
        knownRecipes   = knownRecipes,
        lastScan       = time(),
    }

    -- Fire event for consumers
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_RECIPE_DATA_UPDATED", charKey)
    end
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
        if baseOk and baseInfo and baseInfo.professionName and baseInfo.professionName ~= "" then
            parentName = baseInfo.professionName
        end
    end
    if not parentName and childInfos[1] then
        parentName = childInfos[1].parentProfessionName
    end

    local expansions = {}
    for i = 1, #childInfos do
        local info = childInfos[i]
        if info then
            local skillLevel = info.skillLevel or 0
            local maxSkillLevel = info.maxSkillLevel or 0
            local expansionName = info.professionName or ("Expansion " .. i)
            local skillLineID = info.skillLineID or info.professionID

            -- Get detailed skill info if skillLineID is available
            if skillLineID and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
                local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
                if profOk and profInfo then
                    skillLevel = profInfo.skillLevel or skillLevel
                    maxSkillLevel = profInfo.maxSkillLevel or maxSkillLevel
                    if profInfo.professionName and profInfo.professionName ~= "" then
                        expansionName = profInfo.professionName
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

            -- Persist discovered skillLineIDs for future login refreshes
            local discovered = {}
            for _, exp in ipairs(expansions) do
                if exp.skillLineID then
                    discovered[#discovered + 1] = {
                        id   = exp.skillLineID,
                        name = exp.name,
                    }
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
            for _, sl in ipairs(skillLines) do
                local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sl.id)
                if profOk and profInfo then
                    expansions[#expansions + 1] = {
                        name          = profInfo.professionName or sl.name,
                        skillLevel    = profInfo.skillLevel or 0,
                        maxSkillLevel = profInfo.maxSkillLevel or 0,
                        skillLineID   = sl.id,
                    }
                end
            end

            if #expansions > 0 then
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
local function GetCurrentProfessionName()
    if not C_TradeSkillUI then return nil end
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo and baseInfo.professionName and baseInfo.professionName ~= "" then
            return baseInfo.professionName
        end
    end
    if C_TradeSkillUI.GetChildProfessionInfos then
        local ok, childInfos = pcall(C_TradeSkillUI.GetChildProfessionInfos)
        if ok and childInfos and #childInfos > 0 and childInfos[1] then
            return childInfos[1].parentProfessionName or childInfos[1].professionName
        end
    end
    return nil
end

--[[
    Check if the current character already has data for a given profession.
    @param dataKey string - "recipes", "professionExpansions", or "concentration"
    @param profName string|nil - Profession name to check (nil = check table exists at all)
    @return boolean
]]
local function HasDataForProfession(dataKey, profName)
    if not WarbandNexus or not WarbandNexus.db then return false end
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return false end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return false end

    local tbl = charData[dataKey]
    if not tbl then return false end

    -- If no specific profession, just check table is non-empty
    if not profName then
        return next(tbl) ~= nil
    end

    -- Check if profName key exists in table
    if tbl[profName] then return true end

    -- For recipes: keys may be skillLineIDs, check professionName field inside
    if dataKey == "recipes" then
        for _, profData in pairs(tbl) do
            if profData.professionName == profName then
                return true
            end
        end
    end

    return false
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
    -- Install hooks (once, deferred until frame exists)
    InstallRecipeHook()

    -- Short delay for API readiness, then check what data we need
    C_Timer.After(0.3, function()
        if not WarbandNexus then return end

        -- Concentration: always refresh (values change over time)
        pcall(CollectConcentrationData)

        -- Knowledge data: always refresh (points can be spent/earned)
        pcall(CollectKnowledgeData)

        local profName = GetCurrentProfessionName()

        -- Expansion data: collect only if missing for this profession
        if not HasDataForProfession("professionExpansions", profName) then
            pcall(CollectAllExpansionProfessions, true)
        end

        -- Recipe data: collect only if missing for this profession
        if not HasDataForProfession("recipes", profName) then
            pcall(CollectRecipeData)
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
    if self.SendMessage then
        self:SendMessage("WN_PROFESSION_WINDOW_CLOSED")
    end
end

--[[
    Called on NEW_RECIPE_LEARNED.
    Re-collects recipe data for the current profession (incremental update).
]]
function WarbandNexus:OnNewRecipeLearned()
    -- Only collect if profession frame is open (API requires it)
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end
    C_Timer.After(0.3, function()
        if not WarbandNexus then return end
        pcall(CollectRecipeData)
    end)
end

--[[
    Called on SKILL_LINES_CHANGED (profession learned/dropped/skill level changed).
    Refreshes expansion data and detects profession changes.
]]
function WarbandNexus:OnProfessionChanged()
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    -- Refresh basic profession data (names, icons, skill levels)
    if self.UpdateProfessionData then
        self:UpdateProfessionData()
    end

    -- Compare current professions with stored recipes to detect profession changes
    local currentProfs = {}
    if charData.professions then
        for k, prof in pairs(charData.professions) do
            if prof and prof.name then
                currentProfs[prof.name] = true
            end
        end
    end

    -- Clear stale recipe data for professions the character no longer has
    if charData.recipes then
        local staleKeys = {}
        for storeKey, profData in pairs(charData.recipes) do
            if profData.professionName and not currentProfs[profData.professionName] then
                staleKeys[#staleKeys + 1] = storeKey
            end
        end
        for _, key in ipairs(staleKeys) do
            charData.recipes[key] = nil
        end
    end

    -- Clear stale expansion data
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

            for profName, concData in pairs(charData.concentration) do
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
                    -- Found a crafter — gather concentration data
                    local concEntry = nil
                    if charData.concentration and profData.professionName then
                        concEntry = charData.concentration[profData.professionName]
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
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
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
    if entry.current >= entry.max then return entry.max end

    local elapsed = time() - (entry.lastUpdate or time())
    if elapsed < 0 then elapsed = 0 end

    local estimated = entry.current + (elapsed * CONCENTRATION_PER_SECOND)
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

    -- Format time
    local days = math.floor(secondsToFull / 86400)
    local hours = math.floor((secondsToFull % 86400) / 3600)
    local minutes = math.floor((secondsToFull % 3600) / 60)

    if days > 0 then
        return string.format("%dd %dh %dm", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", math.max(1, minutes))
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

    return charData.knowledgeData[profName]
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
        if charData.knowledgeData and charData.knowledgeData[profName] then
            local kd = charData.knowledgeData[profName]
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

    -- Sort by charName for consistency
    table.sort(result, function(a, b) return a.charName < b.charName end)

    return result
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
    if not self.db or not self.db.global then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = self.db.global.characters and self.db.global.characters[charKey]
    if not charData then return end

    -- Phase 1: Refresh existing stored data from known currency IDs
    if charData.concentration then
        for profName, concData in pairs(charData.concentration) do
            if concData.currencyID and concData.currencyID > 0 then
                local ok, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, concData.currencyID)
                if ok and currInfo then
                    concData.current    = currInfo.quantity or concData.current
                    concData.max        = currInfo.maxQuantity or concData.max
                    concData.lastUpdate = time()
                end
            end
        end
    end

    -- Phase 2: Try to discover concentration via GetConcentrationCurrencyID
    -- using stored discoveredSkillLines (collected when professions were opened)
    if C_TradeSkillUI and C_TradeSkillUI.GetConcentrationCurrencyID
        and charData.discoveredSkillLines then

        if not charData.concentration then
            charData.concentration = {}
        end

        for profName, skillLines in pairs(charData.discoveredSkillLines) do
            -- Only process if we don't already have concentration data for this profession
            if not charData.concentration[profName] then
                for _, slID in ipairs(skillLines) do
                    local concOk, currencyID = pcall(C_TradeSkillUI.GetConcentrationCurrencyID, slID)
                    if concOk and currencyID and currencyID > 0 then
                        local currOk, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                        if currOk and currInfo and currInfo.maxQuantity and currInfo.maxQuantity > 0 then
                            charData.concentration[profName] = {
                                current      = currInfo.quantity or 0,
                                max          = currInfo.maxQuantity or 0,
                                currencyID   = currencyID,
                                skillLineID  = slID,
                                lastUpdate   = time(),
                            }
                            break
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

                local result = CollectKnowledgeForSkillLine(slID, profName)
                if result then
                    charData.knowledgeData[profName] = result
                    break -- Found valid data for this profession
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
    
    for profName, concData in pairs(charData.concentration) do
        if concData.currencyID and concData.currencyID > 0 then
            map[concData.currencyID] = profName
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
    if not currencyID or currencyID == 0 then return end
    
    -- Rebuild map if empty (first call or after reload)
    if not next(concentrationCurrencyMap) then
        concentrationCurrencyMap = BuildConcentrationCurrencyMap()
    end
    
    local profName = concentrationCurrencyMap[currencyID]
    if not profName then return end  -- Not a concentration currency
    
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end
    
    local charData = self.db and self.db.global and self.db.global.characters and self.db.global.characters[charKey]
    if not charData or not charData.concentration or not charData.concentration[profName] then return end
    
    -- Refresh from API
    local ok, currInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if ok and currInfo then
        local entry = charData.concentration[profName]
        entry.current    = currInfo.quantity or entry.current
        entry.max        = currInfo.maxQuantity or entry.max
        entry.lastUpdate = time()
        
        if self.Debug then
            self:Debug("[Concentration] Real-time update: " .. profName .. " = " .. tostring(entry.current) .. "/" .. tostring(entry.max))
        end
        
        -- Notify consumers (tooltip, UI)
        if self.SendMessage then
            self:SendMessage("WN_CONCENTRATION_UPDATED", charKey)
        end
    end
end

--[[
    Called when TRAIT_NODE_CHANGED or TRAIT_CONFIG_UPDATED fires.
    Refreshes knowledge data for all professions of the current character.
    Throttled to avoid excessive API calls during rapid spec changes.
]]
local knowledgeRefreshPending = false

function WarbandNexus:OnKnowledgeChanged()
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
    if rechargeTickerHandle then return end  -- Already running
    
    rechargeTickerHandle = C_Timer.NewTicker(60, function()
        if not WarbandNexus or not WarbandNexus.SendMessage then return end
        
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
