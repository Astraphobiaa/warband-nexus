--[[
    Warband Nexus - Collection Rules
    Per-type collection status and character eligibility (mounts, pets, toys, illusions, etc.).
]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

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
        
        if issecretvalue and name and issecretvalue(name) then
            return {
                canUse = false,
                reason = (ns.L and ns.L["COLLECTION_RULE_INVALID_MOUNT"]) or "Invalid mount",
                isCollected = false
            }
        end
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
        
        local canUse = false
        if issecretvalue and isUsable and issecretvalue(isUsable) then
            canUse = false
        elseif isUsable == true then
            canUse = true
        end
        
        local result = {
            isCollected = collected,
            canUse = canUse,
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
        if issecretvalue and numOwned and issecretvalue(numOwned) then
            return "KNOWN"
        end
        return (numOwned and numOwned > 0) and "KNOWN" or "UNKNOWN"
    end,
    GetCharacterEligibility = function(speciesID)
        if not speciesID or not C_PetJournal then
            return {canUse = true, reason = "", isCollected = false}
        end
        
        local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
        local isCollected = false
        if issecretvalue and numOwned and issecretvalue(numOwned) then
            isCollected = true
        elseif numOwned and numOwned > 0 then
            isCollected = true
        end
        
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

-- UnobtainableFilters: no-op stubs; filtering uses journal APIs in CollectionService.

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

ns.CollectionRules = CollectionRules

-- Backwards compatibility: Keep WarbandNexus.UnobtainableFilters reference
if WarbandNexus then
    WarbandNexus.UnobtainableFilters = CollectionRules.UnobtainableFilters
end

