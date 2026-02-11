--[[
    Warband Nexus - Profession Cache Service
    Recipe metadata, cooldowns, and crafting charges per character.
    Requires profession window open for full scan (C_TradeSkillUI).
    Events: TRADE_SKILL_SHOW, TRADE_SKILL_LIST_UPDATE trigger scan.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print(...)
    end
end

-- Reagent type: Basic = 1 (required reagents). We store Basic/required only.
local CRAFTING_REAGENT_TYPE_BASIC = 1

-- Midnight 12.0: Secret values from C_Spell.GetSpellCooldown during restricted context (e.g. instanced combat).
-- Cannot compare or do arithmetic on them. issecretvalue is nil on pre-12.0.
local _issecretvalue = issecretvalue

-- ============================================================================
-- SAFE API WRAPPERS (TWW: C_Spell namespace, returns table not multi-value)
-- ============================================================================

local function SafeGetSpellCooldown(spellID)
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            return info.startTime or 0, info.duration or 0
        end
        return 0, 0
    end
    if GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
    return 0, 0
end

local function SafeGetSpellCharges(spellID)
    if C_Spell and C_Spell.GetSpellCharges then
        local info = C_Spell.GetSpellCharges(spellID)
        if info then
            return info.currentCharges or 0, info.maxCharges or 0, info.cooldownStartTime or 0, info.cooldownDuration or 0
        end
        return 0, 0, 0, 0
    end
    if GetSpellCharges then
        return GetSpellCharges(spellID)
    end
    return 0, 0, 0, 0
end

-- ============================================================================
-- CATEGORY → EXPANSION MAPPING (built per scan for recipe grouping)
-- ============================================================================

--[[
    Build a mapping from every categoryID (and sub-category) to its root
    category name. Root categories correspond to expansion tiers in the
    profession window (e.g. "Khaz Algar", "Classic").
]]
local function BuildCategoryToExpansionMap()
    local map = {}
    if not C_TradeSkillUI or not C_TradeSkillUI.GetCategories then return map end

    -- GetCategories/GetSubCategories return multiple values, NOT a table
    local ok, topCats = pcall(function() return { C_TradeSkillUI.GetCategories() } end)
    if not ok or not topCats or #topCats == 0 then return map end

    local function MapSubTree(catID, rootName)
        map[catID] = rootName
        if C_TradeSkillUI.GetSubCategories then
            local ok2, subs = pcall(function() return { C_TradeSkillUI.GetSubCategories(catID) } end)
            if ok2 and subs then
                for _, subID in ipairs(subs) do
                    if type(subID) == "number" then
                        MapSubTree(subID, rootName)
                    end
                end
            end
        end
    end

    for _, catID in ipairs(topCats) do
        if type(catID) == "number" then
            local nameOk, catName
            if C_TradeSkillUI.GetCategoryInfo then
                nameOk, catName = pcall(function()
                    local info = C_TradeSkillUI.GetCategoryInfo(catID)
                    return info and info.name
                end)
            end
            local name = (nameOk and catName) or ("Category " .. catID)
            MapSubTree(catID, name)
        end
    end

    return map
end

-- ============================================================================
-- SCAN: Recipe list + metadata + cooldowns + charges
-- ============================================================================

--[[
    Scan currently open profession: learned recipes, reagents, cooldowns, charges.
    Also groups recipes by expansion using category hierarchy.
    Call when TRADE_SKILL_SHOW / TRADE_SKILL_LIST_UPDATE (after IsTradeSkillReady).
    @return boolean - true if scan succeeded
]]
function WarbandNexus:ScanCurrentProfessionRecipes()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady() then
        return false
    end

    local success, result = pcall(function()
        local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
        if not baseInfo or not baseInfo.professionID then return false end

        local key = ns.Utilities:GetCharacterKey()
        if not self.db.global.characters[key] or not self.db.global.characters[key].professions then
            return false
        end

        local professions = self.db.global.characters[key].professions
        local targetProf = nil
        local targetProfKey = nil

        for i = 1, 2 do
            if professions[i] and professions[i].skillLine == baseInfo.professionID then
                targetProf = professions[i]
                targetProfKey = i
                break
            end
        end
        if not targetProf then
            if professions.cooking and professions.cooking.skillLine == baseInfo.professionID then
                targetProf = professions.cooking
                targetProfKey = "cooking"
            end
            -- Fishing and Archaeology have no craftable recipes - skip scanning
        end

        if not targetProf then return false end

        if not self.db.global.professionRecipes then
            self.db.global.professionRecipes = {}
        end
        local recipeCache = self.db.global.professionRecipes

        local allRecipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if not allRecipeIDs or #allRecipeIDs == 0 then
            targetProf.knownRecipes = {}
            targetProf.cooldowns = {}
            targetProf.charges = {}
            targetProf.expansionRecipes = {}
            targetProf.lastRecipeScan = time()
            return true
        end

        -- Build category → expansion name mapping for recipe grouping
        local categoryToExpansion = BuildCategoryToExpansionMap()

        -- Contamination safeguard: verify recipes belong to this profession's category tree
        -- If the UI hasn't fully switched, recipe IDs may belong to the previous profession
        if next(categoryToExpansion) and #allRecipeIDs > 0 then
            local sampleInfo = C_TradeSkillUI.GetRecipeInfo(allRecipeIDs[1])
            if sampleInfo and sampleInfo.categoryID then
                if not categoryToExpansion[sampleInfo.categoryID] then
                    DebugPrint("|cffff8800[WN ProfessionCacheService]|r Recipe category mismatch detected - profession UI not ready. Skipping scan.")
                    return false
                end
            end
        end

        local knownRecipes = {}
        local cooldowns = {}
        local charges = {}
        local expansionRecipes = {}

        for _, recipeID in ipairs(allRecipeIDs) do
            local recipeInfo = C_TradeSkillUI.GetRecipeInfo(recipeID)
            if recipeInfo and recipeInfo.learned then
                table.insert(knownRecipes, recipeID)

                -- Group by expansion via category hierarchy
                local expName = (recipeInfo.categoryID and categoryToExpansion[recipeInfo.categoryID]) or "Other"
                if not expansionRecipes[expName] then
                    expansionRecipes[expName] = {}
                end
                table.insert(expansionRecipes[expName], recipeID)

                -- Schematic: recipeSpellID is first arg (often same as recipeID)
                local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
                if schematic then
                    local reagents = {}
                    if schematic.reagentSlotSchematics then
                        for _, slot in ipairs(schematic.reagentSlotSchematics) do
                            local required = (slot.required == true) or (slot.reagentType == CRAFTING_REAGENT_TYPE_BASIC)
                            if required and slot.reagents and #slot.reagents > 0 then
                                -- Capture ALL quality tiers (rank 1/2/3 have different itemIDs)
                                local tiers = {}
                                for _, r in ipairs(slot.reagents) do
                                    if r.itemID then
                                        table.insert(tiers, r.itemID)
                                    end
                                end
                                if #tiers > 0 then
                                    table.insert(reagents, {
                                        itemID = tiers[1],           -- primary (rank 1) for backward compat
                                        quantity = slot.quantityRequired or 1,
                                        qualityTiers = tiers,        -- { rank1ID, rank2ID, rank3ID }
                                    })
                                end
                            end
                        end
                    end
                    recipeCache[recipeID] = {
                        name = schematic.name or recipeInfo.name,
                        icon = schematic.icon or recipeInfo.icon,
                        outputItemID = schematic.outputItemID,
                        skillLineID = baseInfo.professionID,
                        recipeType = schematic.recipeType,
                        reagents = reagents,
                        spellID = recipeID,
                    }
                end

                -- Cooldown (GetTime-based). WoW 12.0: start/duration may be secret values in restricted context.
                local start, duration = SafeGetSpellCooldown(recipeID)
                if start and duration then
                    if _issecretvalue and (_issecretvalue(start) or _issecretvalue(duration)) then
                        -- Skip: secret values during restricted context (instanced combat, etc.)
                    elseif duration > 0 then
                        cooldowns[recipeID] = {
                            startTime = start,
                            duration = duration,
                        }
                    end
                end

                -- Charges
                local currentCharges, maxCharges, cooldownStart, cooldownDuration = SafeGetSpellCharges(recipeID)
                if maxCharges and maxCharges > 0 then
                    charges[recipeID] = {
                        currentCharges = currentCharges or 0,
                        maxCharges = maxCharges,
                        cooldownStart = cooldownStart or 0,
                        cooldownDuration = cooldownDuration or 0,
                    }
                end
            end
        end

        targetProf.knownRecipes = knownRecipes
        targetProf.cooldowns = cooldowns
        targetProf.charges = charges
        targetProf.expansionRecipes = expansionRecipes
        targetProf.lastRecipeScan = time()

        DebugPrint("|cff9370DB[WN ProfessionCacheService]|r Scan complete. Recipes:", #knownRecipes, "Expansion groups:", (function()
            local c = 0; for _ in pairs(expansionRecipes) do c = c + 1 end; return c
        end)())

        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end

        return true
    end)

    if not success then
        DebugPrint("|cffff0000[WN ProfessionCacheService]|r ScanCurrentProfessionRecipes error:", result)
        return false
    end
    return result
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Get enriched recipe list for a character's profession slot.
    @param charKey string
    @param profSlot number|string 1, 2, "cooking", "fishing", "archaeology"
    @return table|nil { { recipeID, name, icon, cooldownRemaining, charges, craftableCount }, ... }
]]
function WarbandNexus:GetRecipesForCharacterProfession(charKey, profSlot)
    if not charKey or not self.db.global.characters[charKey] then return nil end
    local prof = self.db.global.characters[charKey].professions and self.db.global.characters[charKey].professions[profSlot]
    if not prof or not prof.knownRecipes then return nil end

    -- Skip non-crafting professions
    if profSlot == "fishing" or profSlot == "archaeology" then return nil end

    local recipeCache = self.db.global.professionRecipes or {}
    local currentKey = ns.Utilities:GetCharacterKey()
    local isCurrentChar = (charKey == currentKey)
    local profSkillLine = prof.skillLine
    local out = {}

    for _, recipeID in ipairs(prof.knownRecipes) do
        local meta = recipeCache[recipeID]

        -- Cross-profession validation: skip recipes that don't belong to this profession
        local validRecipe = true
        if meta and meta.skillLineID and profSkillLine and meta.skillLineID ~= profSkillLine then
            validRecipe = false
        end

        if validRecipe then
            local cooldownRemaining = self:GetCooldownRemaining(charKey, profSlot, recipeID)
            local chargeInfo = nil
            if prof.charges and prof.charges[recipeID] then
                chargeInfo = prof.charges[recipeID]
                if isCurrentChar then
                    local cur, max, cStart, cDur = SafeGetSpellCharges(recipeID)
                    if max and max > 0 then
                        chargeInfo = {
                            currentCharges = cur or 0,
                            maxCharges = max,
                            cooldownStart = cStart or 0,
                            cooldownDuration = cDur or 0,
                        }
                    end
                end
            end
            local craftableCount = self:GetCraftableCount(charKey, recipeID)
            table.insert(out, {
                recipeID = recipeID,
                name = meta and meta.name or ("Recipe " .. tostring(recipeID)),
                icon = meta and meta.icon,
                outputItemID = meta and meta.outputItemID,
                cooldownRemaining = cooldownRemaining,
                charges = chargeInfo,
                craftableCount = craftableCount,
            })
        end
    end

    return out
end

--[[
    Helper: sum total available for one itemID across warband.
    @param itemID number
    @return number total, table|nil characters
]]
local function GetItemTotalAcrossWarband(self, itemID)
    local counts = (self.GetDetailedItemCountsFast and self:GetDetailedItemCountsFast(itemID)) or nil
    local total = (counts and counts.warbandBank or 0) + (counts and counts.personalBankTotal or 0)
    if counts and counts.characters then
        for _, c in ipairs(counts.characters) do
            total = total + (c.total or 0)
        end
    end
    return total, counts and counts.characters or {}
end

--[[
    Get reagent availability across warband (bags + bank + warband bank).
    Now returns per-tier (quality rank) availability for each reagent slot.
    Tiers CANNOT be mixed within a single craft.
    @param recipeID number
    @return table { { itemID, quantityRequired, totalAvailable, characters,
                      tierAvailability = { { itemID, tierIndex, totalAvailable, characters }, ... } }, ... }
]]
function WarbandNexus:GetReagentAvailability(recipeID)
    local recipeCache = self.db.global.professionRecipes or {}
    local meta = recipeCache[recipeID]
    if not meta or not meta.reagents or #meta.reagents == 0 then
        return {}
    end

    local results = {}
    for _, r in ipairs(meta.reagents) do
        local tiers = r.qualityTiers or { r.itemID }
        local tierAvailability = {}
        local bestTotal = 0
        local bestCharacters = {}

        for tierIdx, tierItemID in ipairs(tiers) do
            local total, characters = GetItemTotalAcrossWarband(self, tierItemID)
            table.insert(tierAvailability, {
                itemID = tierItemID,
                tierIndex = tierIdx,
                totalAvailable = total,
                characters = characters,
            })
            -- Track best tier (most available) for backward-compatible totalAvailable
            if total > bestTotal then
                bestTotal = total
                bestCharacters = characters
            end
        end

        table.insert(results, {
            itemID = r.itemID,                  -- primary (rank 1) for backward compat
            quantityRequired = r.quantity,
            totalAvailable = bestTotal,          -- best single tier's total
            characters = bestCharacters,
            tierAvailability = tierAvailability,  -- per-tier breakdown
        })
    end
    return results
end

--[[
    How many times can this recipe be crafted with available reagents.
    For each reagent slot, picks the BEST single quality tier (tiers cannot be mixed).
    The overall craftable count is the minimum across all reagent slots.
    @param charKey string|nil If nil, uses warband-wide availability
    @param recipeID number
    @return number
]]
function WarbandNexus:GetCraftableCount(charKey, recipeID)
    local availability = self:GetReagentAvailability(recipeID)
    if not availability or #availability == 0 then return 0 end

    local minCraftable = nil
    for _, a in ipairs(availability) do
        local need = a.quantityRequired or 1
        if need <= 0 then need = 1 end

        -- Pick the best single quality tier for this reagent slot
        local bestForSlot = 0
        if a.tierAvailability and #a.tierAvailability > 0 then
            for _, tier in ipairs(a.tierAvailability) do
                local n = math.floor((tier.totalAvailable or 0) / need)
                if n > bestForSlot then bestForSlot = n end
            end
        else
            -- Fallback: no tier data (legacy cache entry)
            bestForSlot = math.floor((a.totalAvailable or 0) / need)
        end

        if minCraftable == nil or bestForSlot < minCraftable then
            minCraftable = bestForSlot
        end
    end
    return minCraftable or 0
end

--[[
    Seconds remaining on cooldown for a recipe. Live for current char, cache for others.
    @param charKey string
    @param profSlot number|string
    @param recipeID number
    @return number - 0 if no cooldown
]]
function WarbandNexus:GetCooldownRemaining(charKey, profSlot, recipeID)
    local currentKey = ns.Utilities:GetCharacterKey()
    if charKey == currentKey then
        local start, duration = SafeGetSpellCooldown(recipeID)
        if not start or not duration then return 0 end
        if _issecretvalue and (_issecretvalue(start) or _issecretvalue(duration)) then
            return 0  -- Secret values in restricted context (WoW 12.0)
        end
        if duration <= 0 then return 0 end
        local remaining = start + duration - GetTime()
        return remaining > 0 and remaining or 0
    end

    local prof = self.db.global.characters[charKey] and self.db.global.characters[charKey].professions and self.db.global.characters[charKey].professions[profSlot]
    if not prof or not prof.cooldowns or not prof.cooldowns[recipeID] then return 0 end
    local cd = prof.cooldowns[recipeID]
    local remaining = cd.startTime + cd.duration - GetTime()
    return remaining > 0 and remaining or 0
end

-- ============================================================================
-- TIER GROUP MAP: reverse-maps any tier itemID → full tier group
-- ============================================================================

--[[
    Build a reverse map from any quality-tier itemID to its full tier group.
    Allows WN Search to show all tiers when hovering any single tier.
    Lazily cached, invalidated after 15s.
    @return table { [itemID] = { tiers = {id1,id2,id3}, quantity = N, baseName = "..." } }
]]
local tierGroupCache = nil
function WarbandNexus:GetTierGroupForItem(itemID)
    if not itemID then return nil end

    -- Lazy build
    if not tierGroupCache then
        tierGroupCache = {}
        local recipeCache = self.db.global.professionRecipes or {}
        for _, meta in pairs(recipeCache) do
            if meta.reagents then
                for _, r in ipairs(meta.reagents) do
                    if r.qualityTiers and #r.qualityTiers > 1 then
                        local group = {
                            tiers = r.qualityTiers,
                            quantity = r.quantity or 1,
                            baseItemID = r.itemID,
                        }
                        for _, tid in ipairs(r.qualityTiers) do
                            tierGroupCache[tid] = group
                        end
                    end
                end
            end
        end
        -- Auto-invalidate so new scans are picked up
        C_Timer.After(15, function() tierGroupCache = nil end)
    end

    return tierGroupCache[itemID]
end

-- ============================================================================
-- SHARED TOOLTIP INJECTOR (DRY: used by WN Search + Recipe tooltip)
-- ============================================================================

-- Chat-optimized quality tier icons (designed for inline text, proper font-size rendering)
local TIER_ATLAS = {
    "Professions-ChatIcon-Quality-Tier1",
    "Professions-ChatIcon-Quality-Tier2",
    "Professions-ChatIcon-Quality-Tier3",
}

-- Inline tier icon via CreateAtlasMarkup (0,0 = natural size, scales with font)
local function TierTag(tierIdx)
    local atlas = TIER_ATLAS[tierIdx]
    if not atlas then return "" end
    if CreateAtlasMarkup then
        return CreateAtlasMarkup(atlas, 0, 0)
    end
    return "|A:" .. atlas .. ":0:0|a"
end

-- Colored amount based on context
local function AmountColor(amount, threshold)
    if threshold then
        return amount >= threshold and "44ff44" or "ff4444"
    end
    return amount > 0 and "ffffff" or "555555"
end

-- Class-colored character name
local function ClassColoredName(charName, classFile)
    local cc = classFile and RAID_CLASS_COLORS[classFile]
    if cc then
        return string.format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, charName)
    end
    return "|cff999999" .. charName .. "|r"
end

-- Expose tier formatting for companion panel tooltip
ns.TierTag = TierTag
ns.AmountColor = AmountColor
ns.ClassColoredName = ClassColoredName

local function TruncName(name, maxLen)
    if not name then return "?" end
    if #name <= maxLen then return name end
    return name:sub(1, maxLen - 2) .. ".."
end

--[[
    Inject standardized reagent availability lines into a GameTooltip.
    All lines are left-aligned via AddLine with inline color codes.

    Format (multi-tier):
        ReagentName    R1 4  R2 5  R3 0  /2
          CharName     R1 4  R2 5  R3 0
          Warband Bank R1 2  R2 0  R3 0

    Format (single-tier):
        ReagentName    4/2
          CharName     4

    @param tooltip GameTooltip
    @param reagentSlots table|nil - array of slot data (nil = auto-fetch via recipeID)
    @param recipeID number|nil
]]
function WarbandNexus:InjectReagentTooltipLines(tooltip, reagentSlots, recipeID)
    -- Auto-fetch from recipe if slots not provided
    if not reagentSlots and recipeID then
        reagentSlots = self:GetReagentAvailability(recipeID)
    end
    if not reagentSlots or #reagentSlots == 0 then return end

    tooltip:AddLine(" ")
    tooltip:AddLine("Warband Nexus - Reagents", 0.4, 0.8, 1)

    for _, slot in ipairs(reagentSlots) do
        local need = slot.quantityRequired or 1
        local baseName = TruncName(GetItemInfo(slot.itemID) or ("Item " .. slot.itemID), 22)

        if slot.tierAvailability and #slot.tierAvailability > 1 then
            -- Multi-tier: reagent name (left) | R1 total  R2 total  R3 total  /need (right)
            local parts = {}
            for _, tier in ipairs(slot.tierAvailability) do
                local have = tier.totalAvailable or 0
                local col = AmountColor(have, need)
                table.insert(parts, TierTag(tier.tierIndex) .. "|cff" .. col .. have .. "|r")
            end
            tooltip:AddDoubleLine(
                "|cffdadada" .. baseName .. "|r",
                table.concat(parts, " ") .. " |cffaaaaaa/" .. need .. "|r",
                1, 1, 1, 1, 1, 1
            )

            -- Per-character breakdown (aggregate tiers per character)
            local charMap = {}
            local charOrder = {}
            for _, tier in ipairs(slot.tierAvailability) do
                if tier.characters then
                    for _, ch in ipairs(tier.characters) do
                        if ch.total and ch.total > 0 then
                            local key = ch.charName or "?"
                            if not charMap[key] then
                                charMap[key] = { classFile = ch.classFile, counts = {} }
                                table.insert(charOrder, key)
                            end
                            charMap[key].counts[tier.tierIndex] = (charMap[key].counts[tier.tierIndex] or 0) + ch.total
                        end
                    end
                end
            end

            for _, charName in ipairs(charOrder) do
                local info = charMap[charName]
                local charParts = {}
                for _, tier in ipairs(slot.tierAvailability) do
                    local count = info.counts[tier.tierIndex] or 0
                    local col = count > 0 and "ffffff" or "555555"
                    table.insert(charParts, TierTag(tier.tierIndex) .. "|cff" .. col .. count .. "|r")
                end
                tooltip:AddDoubleLine(
                    ClassColoredName(charName, info.classFile),
                    table.concat(charParts, " "),
                    1, 1, 1, 1, 1, 1
                )
            end

            -- Warband bank row (if any tier has stock)
            local wbParts = {}
            local hasWarband = false
            for _, tier in ipairs(slot.tierAvailability) do
                local wbCount = 0
                local counts = (self.GetDetailedItemCountsFast and self:GetDetailedItemCountsFast(tier.itemID)) or nil
                if counts then wbCount = counts.warbandBank or 0 end
                if wbCount > 0 then hasWarband = true end
                local col = wbCount > 0 and "ffffff" or "555555"
                table.insert(wbParts, TierTag(tier.tierIndex) .. "|cff" .. col .. wbCount .. "|r")
            end
            if hasWarband then
                tooltip:AddDoubleLine(
                    "|cffddaa44Warband Bank|r",
                    table.concat(wbParts, " "),
                    1, 1, 1, 1, 1, 1
                )
            end
        else
            -- Single-tier: reagent name (left) | have/need (right)
            local have = slot.totalAvailable or 0
            local col = AmountColor(have, need)
            tooltip:AddDoubleLine(
                "|cffdadada" .. baseName .. "|r",
                "|cff" .. col .. have .. "/" .. need .. "|r",
                1, 1, 1, 1, 1, 1
            )

            -- Per-character
            if slot.characters then
                for _, ch in ipairs(slot.characters) do
                    if ch.total and ch.total > 0 then
                        tooltip:AddDoubleLine(
                            ClassColoredName(ch.charName or "?", ch.classFile),
                            "|cffffffff" .. ch.total .. "|r",
                            1, 1, 1, 1, 1, 1
                        )
                    end
                end
            end
        end
    end
end

--[[
    Inject reagent tooltip for a single item (WN Search context).
    Detects if item is part of a tier group and shows all tiers.
    @param tooltip GameTooltip
    @param itemID number
]]
function WarbandNexus:InjectItemReagentTooltipLines(tooltip, itemID)
    local group = self:GetTierGroupForItem(itemID)
    if not group then return false end

    -- Build availability data for this single reagent slot
    local tierAvailability = {}
    for tierIdx, tierItemID in ipairs(group.tiers) do
        local total, characters = GetItemTotalAcrossWarband(self, tierItemID)
        table.insert(tierAvailability, {
            itemID = tierItemID,
            tierIndex = tierIdx,
            totalAvailable = total,
            characters = characters,
        })
    end

    local slot = {
        itemID = group.baseItemID,
        quantityRequired = group.quantity,
        totalAvailable = 0,
        tierAvailability = tierAvailability,
    }

    self:InjectReagentTooltipLines(tooltip, { slot })
    return true
end

-- Expose for UI/events
ns.ProfessionCacheService = true
