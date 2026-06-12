--[[
    Warband Nexus - Collection Rules
    Per-type collection status and character eligibility (transmog, mounts, pets, etc.).
]]

local ADDON_NAME, ns = ...

-- Illusion cache: built once per session, maps visualID and sourceID to illusionInfo
local illusionCache = nil
local function GetIllusionCache()
    if illusionCache then return illusionCache end
    if not C_TransmogCollection or not C_TransmogCollection.GetIllusions then return nil end
    local illusions = C_TransmogCollection.GetIllusions()
    if not illusions then return nil end
    illusionCache = {}
    for ii = 1, #illusions do
        local info = illusions[ii]
        if info.visualID then illusionCache[info.visualID] = info end
        if info.sourceID then illusionCache[info.sourceID] = info end
    end
    return illusionCache
end

-- Debug print helper
local DebugPrint = ns.DebugPrint
local WarbandNexus = ns.WarbandNexus

local CollectionRules = {}

CollectionRules.TRANSMOG = {
    CheckIfItemID = function(itemID)
        if not itemID or not C_TransmogCollection then
            return false
        end
        
        local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
        if not classID then
            return false
        end
        
        -- Transmog items are: Weapons (2), Armor (4)
        return classID == 2 or classID == 4
    end,
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
    GetCharacterEligibility = function(sourceID)
        if not sourceID or not C_TransmogCollection then
            return {
                canUse = false,
                reason = (ns.L and ns.L["COLLECTION_RULE_API_NOT_AVAILABLE"]) or "API not available",
                isCollected = false
            }
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

CollectionRules.MOUNT = {
    CheckIfItemID = function(itemID)
        if not itemID or not C_MountJournal then
            return false
        end

        -- Get the spell this item teaches
        local _, itemSpellID = C_Item.GetItemSpell(itemID)
        if not itemSpellID then
            return false
        end

        -- Cross-reference against mount journal: find if any mount's spell matches
        local mountIDs = C_MountJournal.GetMountIDs()
        if not mountIDs then return false end
        for mi = 1, #mountIDs do
            local mountID = mountIDs[mi]
            local _, spellID = C_MountJournal.GetMountInfoByID(mountID)
            if spellID and spellID == itemSpellID then
                return true
            end
        end
        return false
    end,
    GetStatus = function(mountID)
        if not mountID or not C_MountJournal then
            return "UNKNOWN"
        end
        
        -- 12.0.5: isCollected is return value #11 (not #5)
        local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if issecretvalue and isCollected and issecretvalue(isCollected) then
            return "KNOWN"  -- Secret = treat as collected
        end
        return isCollected and "KNOWN" or "UNKNOWN"
    end,
    GetCharacterEligibility = function(mountID)
        if not mountID or not C_MountJournal then
            return {
                canUse = false,
                reason = (ns.L and ns.L["COLLECTION_RULE_API_NOT_AVAILABLE"]) or "API not available",
                isCollected = false
            }
        end
        
        -- 12.0.5: 13 return values; isUsable=#5, isCollected=#11
        local name, _, _, _, isUsable, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        
        if not name then
            return {
                canUse = false,
                reason = (ns.L and ns.L["COLLECTION_RULE_INVALID_MOUNT"]) or "Invalid mount",
                isCollected = false
            }
        end
        
        -- Guard secret values (Midnight 12.0+)
        local collected = false
        if issecretvalue and isCollected and issecretvalue(isCollected) then
            collected = true
        elseif isCollected == true then
            collected = true
        end
        
        local result = {
            isCollected = collected,
            canUse = isUsable or false,
            reason = ""
        }
        
        if not result.canUse and not result.isCollected then
            result.reason = (ns.L and ns.L["COLLECTION_RULE_FACTION_CLASS_RESTRICTED"]) or "Faction or class restricted"
        end
        
        return result
    end
}

CollectionRules.PET = {
    CheckIfItemID = function(itemID)
        if not itemID or not C_PetJournal then
            return false
        end
        
        -- Check if item class is Battle Pet (17)
        local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(itemID)
        return classID == 17
    end,
    GetStatus = function(speciesID)
        if not speciesID or not C_PetJournal then
            return "UNKNOWN"
        end
        
        local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
        return (numOwned and numOwned > 0) and "KNOWN" or "UNKNOWN"
    end,
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

CollectionRules.TOY = {
    CheckIfItemID = function(itemID)
        if not itemID or not C_ToyBox then
            return false
        end
        
        -- Direct API check
        return C_ToyBox.GetToyInfo(itemID) ~= nil
    end,
    GetStatus = function(itemID)
        if not itemID then
            return "UNKNOWN"
        end
        
        local isCollected = PlayerHasToy(itemID)
        return isCollected and "KNOWN" or "UNKNOWN"
    end,
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

CollectionRules.ILLUSION = {
    CheckIfItemID = function(itemID)
        if not itemID or not C_TransmogCollection then
            return false
        end
        
        -- Illusions are weapon enchant visuals
        -- This is a heuristic; better to use illusion ID directly
        return false -- Illusions use illusionID, not itemID
    end,
    GetStatus = function(illusionID)
        if not illusionID or not C_TransmogCollection then
            return "UNKNOWN"
        end

        local cache = GetIllusionCache()
        if not cache then return "UNKNOWN" end

        local info = cache[illusionID]
        if info then
            return info.isCollected and "KNOWN" or "UNKNOWN"
        end

        return "UNKNOWN"
    end,
    GetCharacterEligibility = function(illusionID)
        if not illusionID or not C_TransmogCollection then
            return {canUse = true, reason = "", isCollected = false}
        end

        local cache = GetIllusionCache()
        if not cache then
            return {canUse = true, reason = "", isCollected = false}
        end

        local info = cache[illusionID]
        if info then
            return {
                isCollected = info.isCollected or false,
                canUse = true,
                reason = ""
            }
        end

        return {canUse = true, reason = "", isCollected = false}
    end
}

CollectionRules.ACHIEVEMENT = {
    CheckIfItemID = function(itemID)
        return false -- Achievements use achievementID, not itemID
    end,
    GetStatus = function(achievementID)
        if not achievementID then
            return "UNKNOWN"
        end
        
        local _, _, _, completed = GetAchievementInfo(achievementID)
        return completed and "KNOWN" or "UNKNOWN"
    end,
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

CollectionRules.TITLE = {
    CheckIfItemID = function(itemID)
        return false -- Titles use titleID, not itemID
    end,
    GetStatus = function(titleID)
        if not titleID then
            return "UNKNOWN"
        end
        
        local isKnown = IsTitleKnown(titleID)
        return isKnown and "KNOWN" or "UNKNOWN"
    end,
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

-- PUBLIC API
function WarbandNexus:GetCollectionRule(collectionType)
    return CollectionRules[collectionType]
end
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
function WarbandNexus:GetCollectionStatus(collectionType, id)
    local rule = CollectionRules[collectionType]
    if not rule then
        return "UNKNOWN"
    end
    
    return rule.GetStatus(id)
end
function WarbandNexus:GetCollectionEligibility(collectionType, id)
    local rule = CollectionRules[collectionType]
    if not rule then
        return {canUse = false, reason = "Invalid collection type", isCollected = false}
    end
    
    return rule.GetCharacterEligibility(id)
end

-- UNOBTAINABLE FILTERS (API-only — Pure API approach, no keyword/blocklist logic)
--[[
    "Unobtainable" / "hidden" determination is delegated to the WoW API:
      - Mount: shouldHideOnChar unless isFactionSpecific (cross-faction catalog stays visible)
      - Pet:   obtainable (11th return of C_PetJournal.GetPetInfoBySpeciesID)
      - Toy:   C_ToyBox.GetToyInfo() returning nil for hidden/internal entries
      - Mount/Pet/Toy category: journal source filter index (SetSourceFilter sweep when API sourceType is 0)

    The IsUnobtainable* methods below are kept as no-op stubs so external callers
    that still reference UnobtainableFilters do not break, but they always return
    false (i.e. nothing is filtered out by name/keyword heuristics anymore).
    Filtering happens in CollectionService.COLLECTION_CONFIGS via the API checks
    listed above.
]]

CollectionRules.UnobtainableFilters = {}

function CollectionRules.UnobtainableFilters:IsUnobtainableMount(_)
    return false
end

function CollectionRules.UnobtainableFilters:IsUnobtainablePet(_)
    return false
end

function CollectionRules.UnobtainableFilters:IsUnobtainableToy(_)
    return false
end

function CollectionRules.UnobtainableFilters:IsUnobtainableIllusion(_)
    return false
end

-- EXPORT TO NAMESPACE

ns.CollectionRules = CollectionRules

-- Backwards compatibility: Keep WarbandNexus.UnobtainableFilters reference
if WarbandNexus then
    WarbandNexus.UnobtainableFilters = CollectionRules.UnobtainableFilters
end

-- Load message
-- Module loaded - verbose logging removed

