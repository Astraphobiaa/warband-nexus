--[[
    Warband Nexus - Collection Rules
    Modular collection logic for all collection types
    
    This module provides a unified interface for checking collection status
    and character eligibility across all WoW collection systems (Transmog, Mounts, Pets, etc.)
    
    Key Features:
    - Warband-wide collection status (isCollected)
    - Character eligibility checks (canDisplayOnPlayer, playerCanCollect)
    - Unified API for tooltip and UI integration
    - TWW 11.0+ compatibility with backward compatibility fallbacks
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- COLLECTION RULES REGISTRY
-- ============================================================================

local CollectionRules = {}

--[[
    Rule Interface:
    Each rule must implement:
    - CheckIfItemID(itemID): Returns true if itemID belongs to this collection type
    - GetStatus(itemID): Returns "KNOWN" or "UNKNOWN"
    - GetCharacterEligibility(itemID): Returns eligibility info table
]]

-- ============================================================================
-- TRANSMOG RULES
-- ============================================================================

CollectionRules.TRANSMOG = {
    --[[
        Check if itemID is a transmog source
        @param itemID number - Item ID to check
        @return boolean - True if item is a transmog source
    ]]
    CheckIfItemID = function(itemID)
        if not itemID or not C_TransmogCollection then
            return false
        end
        
        -- Check if item has transmog source info
        local sourceInfo = C_Item.GetItemInfo(itemID)
        if not sourceInfo then
            return false
        end
        
        -- Check item class/subclass (armor, weapons)
        local _, _, _, _, _, _, _, _, itemEquipLoc, _, _, classID = C_Item.GetItemInfo(itemID)
        if not classID then
            return false
        end
        
        -- Transmog items are: Weapons (2), Armor (4)
        return classID == 2 or classID == 4
    end,
    
    --[[
        Get collection status for a transmog source
        @param sourceID number - Transmog source ID (not itemID!)
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(sourceID)
        if not sourceID or not C_TransmogCollection then
            return "UNKNOWN"
        end
        
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if not sourceInfo then
            return "UNKNOWN"
        end
        
        return sourceInfo.isCollected and "KNOWN" or "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for a transmog source
        @param sourceID number - Transmog source ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(sourceID)
        if not sourceID or not C_TransmogCollection then
            return {canUse = false, reason = "API not available", isCollected = false}
        end
        
        local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
        if not sourceInfo then
            return {canUse = false, reason = "Invalid source", isCollected = false}
        end
        
        local result = {
            isCollected = sourceInfo.isCollected or false,
            canUse = false,
            reason = ""
        }
        
        -- TWW 11.0+ field (backward compatible)
        if sourceInfo.canDisplayOnPlayer ~= nil then
            result.canUse = sourceInfo.canDisplayOnPlayer
            if not result.canUse then
                result.reason = "Wrong armor class"
            end
        else
            -- Fallback: use isUsable (pre-11.0)
            result.canUse = sourceInfo.isUsable or false
            if not result.canUse then
                result.reason = "Not usable by character"
            end
        end
        
        -- Check playerCanCollect (TWW 11.0+)
        if sourceInfo.playerCanCollect ~= nil and not sourceInfo.playerCanCollect then
            result.canUse = false
            result.reason = "Restricted item"
        end
        
        return result
    end
}

-- ============================================================================
-- MOUNT RULES
-- ============================================================================

CollectionRules.MOUNT = {
    --[[
        Check if itemID is a mount
        @param itemID number - Item ID to check
        @return boolean - True if item teaches a mount
    ]]
    CheckIfItemID = function(itemID)
        if not itemID or not C_MountJournal then
            return false
        end
        
        -- Check item spell effect for mount teaching
        local itemSpell = C_Item.GetItemSpell(itemID)
        if not itemSpell then
            return false
        end
        
        -- Mount items typically have "Teaches you how to summon" in tooltip
        -- This is a heuristic check; better to use mount journal directly
        return true -- Simplified for now
    end,
    
    --[[
        Get collection status for a mount
        @param mountID number - Mount ID
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(mountID)
        if not mountID or not C_MountJournal then
            return "UNKNOWN"
        end
        
        local _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        return isCollected and "KNOWN" or "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for a mount
        @param mountID number - Mount ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(mountID)
        if not mountID or not C_MountJournal then
            return {canUse = false, reason = "API not available", isCollected = false}
        end
        
        local name, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        
        if not name then
            return {canUse = false, reason = "Invalid mount", isCollected = false}
        end
        
        local result = {
            isCollected = isCollected or false,
            canUse = isUsable or false,
            reason = ""
        }
        
        if not result.canUse and not result.isCollected then
            result.reason = "Faction or class restricted"
        end
        
        return result
    end
}

-- ============================================================================
-- PET RULES
-- ============================================================================

CollectionRules.PET = {
    --[[
        Check if itemID is a battle pet
        @param itemID number - Item ID to check
        @return boolean - True if item is a pet cage/item
    ]]
    CheckIfItemID = function(itemID)
        if not itemID or not C_PetJournal then
            return false
        end
        
        -- Check if item class is Battle Pet (17)
        local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
        return classID == 17
    end,
    
    --[[
        Get collection status for a pet
        @param speciesID number - Pet species ID
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(speciesID)
        if not speciesID or not C_PetJournal then
            return "UNKNOWN"
        end
        
        local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
        return (numOwned and numOwned > 0) and "KNOWN" or "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for a pet
        @param speciesID number - Pet species ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(speciesID)
        if not speciesID or not C_PetJournal then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
        local isCollected = numOwned and numOwned > 0
        
        -- Pets are account-wide and usable by all characters
        return {
            isCollected = isCollected,
            canUse = true,
            reason = ""
        }
    end
}

-- ============================================================================
-- TOY RULES
-- ============================================================================

CollectionRules.TOY = {
    --[[
        Check if itemID is a toy
        @param itemID number - Item ID to check
        @return boolean - True if item is a toy
    ]]
    CheckIfItemID = function(itemID)
        if not itemID or not C_ToyBox then
            return false
        end
        
        -- Direct API check
        return C_ToyBox.GetToyInfo(itemID) ~= nil
    end,
    
    --[[
        Get collection status for a toy
        @param itemID number - Toy item ID
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(itemID)
        if not itemID then
            return "UNKNOWN"
        end
        
        local isCollected = PlayerHasToy(itemID)
        return isCollected and "KNOWN" or "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for a toy
        @param itemID number - Toy item ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(itemID)
        if not itemID then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        local isCollected = PlayerHasToy(itemID)
        
        -- Toys are account-wide (Warband compatible)
        return {
            isCollected = isCollected,
            canUse = true,
            reason = ""
        }
    end
}

-- ============================================================================
-- ILLUSION RULES
-- ============================================================================

CollectionRules.ILLUSION = {
    --[[
        Check if itemID is an illusion
        @param itemID number - Item ID to check
        @return boolean - True if item provides an illusion
    ]]
    CheckIfItemID = function(itemID)
        if not itemID or not C_TransmogCollection then
            return false
        end
        
        -- Illusions are weapon enchant visuals
        -- This is a heuristic; better to use illusion ID directly
        return false -- Illusions use illusionID, not itemID
    end,
    
    --[[
        Get collection status for an illusion
        @param illusionID number - Illusion ID
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(illusionID)
        if not illusionID or not C_TransmogCollection then
            return "UNKNOWN"
        end
        
        local illusions = C_TransmogCollection.GetIllusions()
        if not illusions then
            return "UNKNOWN"
        end
        
        for _, illusionInfo in ipairs(illusions) do
            if illusionInfo.visualID == illusionID or illusionInfo.sourceID == illusionID then
                return illusionInfo.isCollected and "KNOWN" or "UNKNOWN"
            end
        end
        
        return "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for an illusion
        @param illusionID number - Illusion ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(illusionID)
        if not illusionID or not C_TransmogCollection then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        local illusions = C_TransmogCollection.GetIllusions()
        if not illusions then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        for _, illusionInfo in ipairs(illusions) do
            if illusionInfo.visualID == illusionID or illusionInfo.sourceID == illusionID then
                return {
                    isCollected = illusionInfo.isCollected or false,
                    canUse = true, -- Illusions are account-wide
                    reason = ""
                }
            end
        end
        
        return {canUse = true, reason = "", isCollected = false}
    end
}

-- ============================================================================
-- ACHIEVEMENT RULES
-- ============================================================================

CollectionRules.ACHIEVEMENT = {
    --[[
        Check if itemID relates to an achievement
        @param itemID number - Item ID to check
        @return boolean - Always false (achievements don't have itemIDs)
    ]]
    CheckIfItemID = function(itemID)
        return false -- Achievements use achievementID, not itemID
    end,
    
    --[[
        Get collection status for an achievement
        @param achievementID number - Achievement ID
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(achievementID)
        if not achievementID then
            return "UNKNOWN"
        end
        
        local _, _, _, completed = GetAchievementInfo(achievementID)
        return completed and "KNOWN" or "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for an achievement
        @param achievementID number - Achievement ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(achievementID)
        if not achievementID then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        local _, _, _, completed = GetAchievementInfo(achievementID)
        
        -- Achievements are account-wide in TWW
        return {
            isCollected = completed or false,
            canUse = true,
            reason = ""
        }
    end
}

-- ============================================================================
-- TITLE RULES
-- ============================================================================

CollectionRules.TITLE = {
    --[[
        Check if itemID relates to a title
        @param itemID number - Item ID to check
        @return boolean - Always false (titles don't have itemIDs)
    ]]
    CheckIfItemID = function(itemID)
        return false -- Titles use titleID, not itemID
    end,
    
    --[[
        Get collection status for a title
        @param titleID number - Title ID
        @return string - "KNOWN" or "UNKNOWN"
    ]]
    GetStatus = function(titleID)
        if not titleID then
            return "UNKNOWN"
        end
        
        local isKnown = IsTitleKnown(titleID)
        return isKnown and "KNOWN" or "UNKNOWN"
    end,
    
    --[[
        Get character eligibility for a title
        @param titleID number - Title ID
        @return table - {canUse: boolean, reason: string, isCollected: boolean}
    ]]
    GetCharacterEligibility = function(titleID)
        if not titleID then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        local isKnown = IsTitleKnown(titleID)
        
        -- Titles are account-wide in TWW
        return {
            isCollected = isKnown or false,
            canUse = true,
            reason = ""
        }
    end
}

-- ============================================================================
-- PUBLIC API
-- ============================================================================

--[[
    Get collection rule by type
    @param collectionType string - Type of collection (e.g., "TRANSMOG", "MOUNT")
    @return table|nil - Rule object or nil
]]
function WarbandNexus:GetCollectionRule(collectionType)
    return CollectionRules[collectionType]
end

--[[
    Check if item is part of any collection
    @param itemID number - Item ID to check
    @return string|nil - Collection type or nil
]]
function WarbandNexus:GetItemCollectionType(itemID)
    if not itemID then
        return nil
    end
    
    -- Check each collection type
    for collectionType, rule in pairs(CollectionRules) do
        if rule.CheckIfItemID(itemID) then
            return collectionType
        end
    end
    
    return nil
end

--[[
    Get collection status for any collection type
    @param collectionType string - Type of collection
    @param id number - Collection ID (sourceID, mountID, speciesID, etc.)
    @return string - "KNOWN" or "UNKNOWN"
]]
function WarbandNexus:GetCollectionStatus(collectionType, id)
    local rule = CollectionRules[collectionType]
    if not rule then
        return "UNKNOWN"
    end
    
    return rule.GetStatus(id)
end

--[[
    Get character eligibility for any collection type
    @param collectionType string - Type of collection
    @param id number - Collection ID
    @return table - {canUse: boolean, reason: string, isCollected: boolean}
]]
function WarbandNexus:GetCollectionEligibility(collectionType, id)
    local rule = CollectionRules[collectionType]
    if not rule then
        return {canUse = false, reason = "Invalid collection type", isCollected = false}
    end
    
    return rule.GetCharacterEligibility(id)
end

-- ============================================================================
-- UNOBTAINABLE FILTERS (Merged from UnobtainableFilters.lua)
-- ============================================================================
--[[
    Centralized filter system to exclude genuinely unobtainable items.
    Research-backed blocklists and keyword detection for mounts, pets, toys.
]]

-- Mount Blocklists
local ARENA_MOUNT_NAMES = {
    -- TBC-Shadowlands Arena Mounts (30+ mounts)
    ["Swift Nether Drake"] = true, ["Merciless Nether Drake"] = true,
    ["Vengeful Nether Drake"] = true, ["Brutal Nether Drake"] = true,
    ["Deadly Gladiator's Frost Wyrm"] = true, ["Furious Gladiator's Frost Wyrm"] = true,
    ["Relentless Gladiator's Frost Wyrm"] = true, ["Wrathful Gladiator's Frost Wyrm"] = true,
    ["Vicious Gladiator's Twilight Drake"] = true, ["Ruthless Gladiator's Twilight Drake"] = true,
    ["Cataclysmic Gladiator's Twilight Drake"] = true,
    ["Tyrannical Gladiator's Cloud Serpent"] = true, ["Grievous Gladiator's Cloud Serpent"] = true,
    ["Prideful Gladiator's Cloud Serpent"] = true,
    ["Primal Gladiator's Felblood Gronnling"] = true, ["Wild Gladiator's Felblood Gronnling"] = true,
    ["Warmongering Gladiator's Felblood Gronnling"] = true,
    ["Vindictive Gladiator's Storm Dragon"] = true, ["Fearless Gladiator's Storm Dragon"] = true,
    ["Cruel Gladiator's Storm Dragon"] = true, ["Ferocious Gladiator's Storm Dragon"] = true,
    ["Dread Gladiator's Proto-Drake"] = true, ["Sinister Gladiator's Proto-Drake"] = true,
    ["Notorious Gladiator's Proto-Drake"] = true, ["Corrupted Gladiator's Proto-Drake"] = true,
    ["Sinful Gladiator's Soul Eater"] = true, ["Unchained Gladiator's Soul Eater"] = true,
    ["Cosmic Gladiator's Soul Eater"] = true, ["Eternal Gladiator's Soul Eater"] = true,
}

local CHALLENGE_MODE_MOUNTS = {
    ["Ashen Pandaren Phoenix"] = true, ["Crimson Pandaren Phoenix"] = true,
    ["Emerald Pandaren Phoenix"] = true, ["Violet Pandaren Phoenix"] = true,
    ["Ironside Warwolf"] = true, ["Challenger's War Yeti"] = true,
}

local EVENT_EXCLUSIVE_MOUNTS = {
    ["Black Qiraji Battle Tank"] = true, ["Black Qiraji Resonating Crystal"] = true,
}

local PLACEHOLDER_MOUNTS = {
    ["Tiger"] = true, ["White Stallion"] = true, ["Palomino"] = true,
    ["Fluorescent Green Mechanostrider"] = true, ["Unpainted Mechanostrider"] = true,
}

-- Unobtainable Keywords
local UNOBTAINABLE_SOURCE_KEYWORDS = {
    "GLADIATOR", "ELITE", "SEASON %d", "ARENA SEASON", "RATED",
    "TCG", "TRADING CARD", "LOOT CARD", "BLIZZCON",
    "COLLECTOR'S EDITION", "PROMOTION", "PROMOTIONAL",
    "CHALLENGE MODE", "NO LONGER OBTAINABLE", "RETIRED", "REMOVED", "UNOBTAINABLE", "LEGACY",
}

local UNOBTAINABLE_SOURCE_TYPES = {
    [6] = true,  -- Promotion
    [9] = true,  -- TCG
}

local function HasUnobtainableKeyword(source)
    if not source or source == "" then return false end
    local sourceUpper = source:upper()
    for _, keyword in ipairs(UNOBTAINABLE_SOURCE_KEYWORDS) do
        if sourceUpper:find(keyword) then return true end
    end
    return false
end

-- Filters
CollectionRules.UnobtainableFilters = {}

function CollectionRules.UnobtainableFilters:IsUnobtainableMount(data)
    if not data then return true end
    
    -- Log filter check
    local filtered = false
    local reason = ""
    
    if ARENA_MOUNT_NAMES[data.name] or CHALLENGE_MODE_MOUNTS[data.name] or
       EVENT_EXCLUSIVE_MOUNTS[data.name] or PLACEHOLDER_MOUNTS[data.name] then
        filtered = true
        reason = "Blocklist"
    elseif data.sourceType and UNOBTAINABLE_SOURCE_TYPES[data.sourceType] then
        filtered = true
        reason = "SourceType:" .. data.sourceType
    elseif data.source and HasUnobtainableKeyword(data.source) then
        filtered = true
        reason = "Keyword"
    end
    
    if filtered then
        DebugPrint("|cffff9900[WN UnobtainableFilter]|r Filtered mount: " .. (data.name or "Unknown") .. " (" .. reason .. ")")
    end
    
    return filtered
end

function CollectionRules.UnobtainableFilters:IsUnobtainablePet(data)
    if not data then return true end
    if data.source and HasUnobtainableKeyword(data.source) then return true end
    return false
end

function CollectionRules.UnobtainableFilters:IsUnobtainableToy(data)
    if not data then return true end
    if data.source and HasUnobtainableKeyword(data.source) then return true end
    return false
end

function CollectionRules.UnobtainableFilters:IsUnobtainableIllusion(data)
    if not data then return true end
    if data.source and HasUnobtainableKeyword(data.source) then return true end
    return false
end

-- ============================================================================
-- EXPORT TO NAMESPACE
-- ============================================================================

ns.CollectionRules = CollectionRules

-- Backwards compatibility: Keep WarbandNexus.UnobtainableFilters reference
if WarbandNexus then
    WarbandNexus.UnobtainableFilters = CollectionRules.UnobtainableFilters
end

-- Load message
-- Module loaded - verbose logging removed

