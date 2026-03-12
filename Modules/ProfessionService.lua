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
                local professionName = entry.profName
                local expansionName = nil
                local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slID)
                if piOk and profInfo then
                    professionName = professionName or profInfo.professionName or profInfo.parentProfessionName
                    expansionName = profInfo.professionName or profInfo.parentProfessionName
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

    local profName = nil
    local expansionName = nil
    if C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if ok and profInfo then
            profName = profInfo.professionName or profInfo.parentProfessionName
            expansionName = profInfo.professionName or profInfo.parentProfessionName
        end
    end
    if not profName and C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
        local ok, baseInfo = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
        if ok and baseInfo then profName = baseInfo.professionName end
    end
    profName = profName or ("Profession_" .. skillLineID)

    local result = CollectKnowledgeForSkillLine(skillLineID, profName)
    if result then
        result.professionName = profName
        result.expansionName = expansionName
        charData.knowledgeData[skillLineID] = result
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

-- Mapping from profession name to Enum.Profession value
-- Used to call C_TradeSkillUI.GetProfessionSlots(enumValue)
local PROFESSION_NAME_TO_ENUM = {
    ["First Aid"] = 0,
    ["Blacksmithing"] = 1,
    ["Leatherworking"] = 2,
    ["Alchemy"] = 3,
    ["Herbalism"] = 4,
    ["Cooking"] = 5,
    ["Mining"] = 6,
    ["Tailoring"] = 7,
    ["Engineering"] = 8,
    ["Enchanting"] = 9,
    ["Fishing"] = 10,
    ["Skinning"] = 11,
    ["Jewelcrafting"] = 12,
    ["Inscription"] = 13,
    ["Archaeology"] = 14,
}

-- Fallback slots for when GetProfessionSlots is unavailable
local EQUIPMENT_SLOTS = {
    { slotID = 20, key = "tool" },
    { slotID = 21, key = "accessory1" },
    { slotID = 22, key = "accessory2" },
}

local function CollectEquipmentDataForCurrentProfession()
    if not WarbandNexus or not WarbandNexus.db then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    local profName = GetCurrentProfessionName()
    if not profName or profName == "" then return end

    -- Ensure professionEquipment is keyed by profession (support legacy flat table)
    if not charData.professionEquipment or not rawget(charData.professionEquipment, "tool") then
        if type(charData.professionEquipment) ~= "table" then
            charData.professionEquipment = {}
        end
    else
        -- Migrate old flat table to per-profession; keep as _legacy fallback
        local legacy = charData.professionEquipment
        charData.professionEquipment = { _legacy = legacy }
    end

    local equipment = {
        lastUpdate = time(),
    }

    for _, slot in ipairs(EQUIPMENT_SLOTS) do
        local itemID = GetInventoryItemID("player", slot.slotID)
        if itemID then
            local itemLink = GetInventoryItemLink("player", slot.slotID)
            local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slot.slotID) or nil
            local itemName = nil
            if itemLink then
                itemName = itemLink:match("%[(.-)%]")
            end
            equipment[slot.key] = {
                itemID   = itemID,
                itemLink = itemLink,
                icon     = icon,
                name     = itemName or ("Item " .. itemID),
            }
        end
    end

    charData.professionEquipment[profName] = equipment

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_PROFESSION_EQUIPMENT_UPDATED", charKey)
    end
end

--[[
    Helper: Get equipment slot IDs for a profession using GetProfessionSlots API.
    Returns array of slot IDs, or nil if API unavailable.
    Note: GetProfessionSlots returns 1-indexed slot IDs directly usable with GetInventoryItemID.
]]
local function GetSlotsForProfession(profEnum)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionSlots then return nil end

    local ok, slots = pcall(C_TradeSkillUI.GetProfessionSlots, profEnum)
    if not ok or not slots or #slots == 0 then return nil end

    -- GetProfessionSlots returns slot IDs directly (e.g., 20, 21, 22 for first profession)
    -- No offset needed - these are the actual inventory slot IDs
    return slots
end

--[[
    Helper: Collect equipment from specific slot IDs for a profession.
    Returns equipment table { tool?, accessory1?, accessory2?, lastUpdate }.
]]
local function CollectEquipmentFromSlots(slotIDs)
    if not slotIDs or #slotIDs == 0 then return nil end

    local equipment = { lastUpdate = time() }
    local slotKeys = { "tool", "accessory1", "accessory2" }
    local hasAny = false

    for i, slotID in ipairs(slotIDs) do
        local key = slotKeys[i] or ("slot" .. i)
        local itemID = GetInventoryItemID("player", slotID)
        if itemID then
            local itemLink = GetInventoryItemLink("player", slotID)
            local icon = GetInventoryItemTexture and GetInventoryItemTexture("player", slotID) or nil
            local itemName = nil
            if itemLink then itemName = itemLink:match("%[(.-)%]") end
            equipment[key] = {
                itemID = itemID, itemLink = itemLink, icon = icon,
                name = itemName or ("Item " .. itemID),
            }
            hasAny = true
        end
    end

    return hasAny and equipment or nil
end

--[[
    Collect equipment for all player professions using GetProfessionSlots API.
    Each profession has its own dedicated equipment slots.
]]
local function CollectEquipmentByDetection()
    if not WarbandNexus or not WarbandNexus.db then return end

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    -- Ensure table (migrate legacy flat to { _legacy = old } if needed)
    if not charData.professionEquipment or type(charData.professionEquipment) ~= "table" then
        charData.professionEquipment = {}
    elseif rawget(charData.professionEquipment, "tool") then
        charData.professionEquipment = { _legacy = charData.professionEquipment }
    end

    -- Get player's professions (prof1, prof2, archaeology, fishing, cooking)
    local prof1, prof2, arch, fish, cook = GetProfessions()
    local profIndices = { prof1, prof2, arch, fish, cook }
    local collectedAny = false

    for _, profIndex in ipairs(profIndices) do
        if profIndex then
            local profName = GetProfessionInfo(profIndex)
            if profName and profName ~= "" then
                local profEnum = PROFESSION_NAME_TO_ENUM[profName]
                if profEnum then
                    local slots = GetSlotsForProfession(profEnum)
                    if slots and #slots > 0 then
                        local equipment = CollectEquipmentFromSlots(slots)
                        if equipment then
                            charData.professionEquipment[profName] = equipment
                            collectedAny = true
                        end
                    end
                end
            end
        end
    end

    -- Debug: if GetProfessionSlots failed or returned nothing, log it
    if not collectedAny and WarbandNexus.Debug then
        WarbandNexus:Debug("[ProfEquip] No equipment collected via GetProfessionSlots - API may require profession window")
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
    if slot and (slot == 20 or slot == 21 or slot == 22) then
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
    C_Timer.After(2, function()
        if not WarbandNexus then return end
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
            local hasValidSkill = false
            for _, sl in ipairs(skillLines) do
                local profOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, sl.id)
                if profOk and profInfo then
                    local skillLevel    = profInfo.skillLevel or 0
                    local maxSkillLevel = profInfo.maxSkillLevel or 0
                    expansions[#expansions + 1] = {
                        name          = profInfo.professionName or sl.name,
                        skillLevel    = skillLevel,
                        maxSkillLevel = maxSkillLevel,
                        skillLineID   = sl.id,
                    }
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
        if ok and baseInfo then baseProfName = baseInfo.professionName end
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
    
    -- Install hooks (once, deferred until frame exists)
    InstallRecipeHook()

    -- Run all collectors; C_TradeSkillUI can be not ready immediately after TRADE_SKILL_SHOW
    local function RunAllCollectors()
        if not WarbandNexus then return end
        pcall(CollectConcentrationData)
        pcall(CollectKnowledgeData)
        pcall(CollectAllExpansionProfessions, true)
        pcall(CollectEquipmentDataForCurrentProfession)
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
    
    -- Only process if profession frame is open
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady or not C_TradeSkillUI.IsTradeSkillReady() then
        return
    end
    
    if tradeSkillListUpdatePending then return end
    tradeSkillListUpdatePending = true
    
    C_Timer.After(0.5, function()
        tradeSkillListUpdatePending = false
        if not WarbandNexus then return end
        -- Re-collect all tab-specific data when the expansion tab changes.
        -- Each data type is keyed by skillLineID so switching tabs writes to the correct bucket.
        pcall(CollectConcentrationData)
        pcall(CollectKnowledgeData)
        pcall(CollectAllExpansionProfessions, true)
    end)
end

--[[
    Called on SKILL_LINES_CHANGED (profession learned/dropped/skill level changed).
    Refreshes expansion data and detects profession changes.
]]
function WarbandNexus:OnProfessionChanged()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
    
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

    -- Guard: Only clear stale data if we have valid current professions to compare against.
    -- SKILL_LINES_CHANGED fires on login before GetProfessions() is ready, so currentProfs
    -- can be empty even though the character has professions. Clearing stale data against an
    -- empty list would destroy ALL saved expansion and knowledge data.
    if next(currentProfs) then
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
                    concData.current    = currInfo.quantity or concData.current
                    concData.max        = currInfo.maxQuantity or concData.max
                    concData.lastUpdate = time()
                end
            end
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
        entry.current    = currInfo.quantity or entry.current
        entry.max        = currInfo.maxQuantity or entry.max
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

--[[
    Called when TRAIT_NODE_CHANGED or TRAIT_CONFIG_UPDATED fires.
    Refreshes knowledge data for all professions of the current character.
    Throttled to avoid excessive API calls during rapid spec changes.
]]
local knowledgeRefreshPending = false

function WarbandNexus:OnKnowledgeChanged()
    -- Guard: skip when professions module is disabled
    if not ns.Utilities:IsModuleEnabled("professions") then return end
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
