---CollectionManager: Handles mount/pet/toy collection detection and validation
---@class CollectionManager
local addonName, ns = ...
local WarbandNexus = LibStub("AceAddon-3.0"):GetAddon("WarbandNexus")

--[[============================================================================
    COLLECTION CACHE
    Cache player's entire collection for fast lookup
============================================================================]]

---Build collection cache (all owned mounts/pets/toys)
function WarbandNexus:BuildCollectionCache()
    local success, err = pcall(function()
        self.collectionCache = {
            mounts = {},
            pets = {},
            toys = {}
        }
        
        -- Cache all mounts
        if C_MountJournal and C_MountJournal.GetMountIDs then
            local mountIDs = C_MountJournal.GetMountIDs()
            for _, mountID in ipairs(mountIDs) do
                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if isCollected then
                    self.collectionCache.mounts[mountID] = true
                end
            end
        end
        
        -- Cache all pets (by speciesID)
        if C_PetJournal and C_PetJournal.GetNumPets then
            local numPets, numOwned = C_PetJournal.GetNumPets()
            local seenSpecies = {}
            
            for i = 1, numPets do
                local petID, speciesID, owned, customName = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID and not seenSpecies[speciesID] then
                    self.collectionCache.pets[speciesID] = true
                    seenSpecies[speciesID] = true
                end
            end
        end
        
        -- Cache all toys
        if C_ToyBox and C_ToyBox.GetNumToys then
            for i = 1, C_ToyBox.GetNumToys() do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and PlayerHasToy and PlayerHasToy(itemID) then
                    self.collectionCache.toys[itemID] = true
                end
            end
        end
    end)
    
    if not success then
        self:Debug("Error in BuildCollectionCache: " .. tostring(err))
        -- Initialize with empty cache on error
        self.collectionCache = {
            mounts = {},
            pets = {},
            toys = {}
        }
    end
end

---Check if player owns a mount/pet/toy
---@param collectibleType string "mount", "pet", or "toy"
---@param id number mountID, speciesID, or toyItemID
---@return boolean owned
function WarbandNexus:IsCollectibleOwned(collectibleType, id)
    if not self.collectionCache then
        self:BuildCollectionCache()
    end
    
    if collectibleType == "mount" then
        return self.collectionCache.mounts[id] == true
    elseif collectibleType == "pet" then
        return self.collectionCache.pets[id] == true
    elseif collectibleType == "toy" then
        return self.collectionCache.toys[id] == true
    end
    
    return false
end

---Count table entries (helper for debug)
---@param tbl table
---@return number
function WarbandNexus:TableCount(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

--[[============================================================================
    COLLECTION DETECTION LOGIC
============================================================================]]

---Check if an item is a NEW collectible (mount/pet/toy) that player doesn't have
---@param itemID number The item ID
---@param hyperlink string|nil Item hyperlink (required for caged pets)
---@return table|nil collectibleData {type, id, name, icon} or nil
function WarbandNexus:CheckNewCollectible(itemID, hyperlink)
    if not itemID then return nil end
    
    -- Get basic item info
    local itemName, _, _, _, _, _, _, _, _, itemIcon, _, classID, subclassID = GetItemInfo(itemID)
    if not classID then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil
    end
    
    -- ========================================
    -- MOUNT (classID 15, subclass 5)
    -- ========================================
    if classID == 15 and subclassID == 5 then
        if not C_MountJournal or not C_MountJournal.GetMountFromItem then
            return nil
        end
        
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if not mountID then return nil end
        
        -- Check cache: do we already own this?
        if self:IsCollectibleOwned("mount", mountID) then
            return nil
        end
        
        local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
        if not name then return nil end
        
        return {
            type = "mount",
            id = mountID,
            name = name,
            icon = icon
        }
    end
    
    -- ========================================
    -- PET (classID 17)
    -- ========================================
    if classID == 17 then
        if not C_PetJournal then return nil end
        
        local speciesID = nil
        
        -- Try API first (works for non-caged pets)
        if C_PetJournal.GetPetInfoByItemID then
            speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        end
        
        -- For caged pets, extract speciesID from hyperlink
        if not speciesID and hyperlink then
            speciesID = tonumber(hyperlink:match("|Hbattlepet:(%d+):"))
        end
        
        if not speciesID then return nil end
        
        -- Check cache: already collected?
        if self:IsCollectibleOwned("pet", speciesID) then
            return nil
        end
        
        -- Get display info
        local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        
        return {
            type = "pet",
            id = speciesID,
            name = speciesName or itemName or "Unknown Pet",
            icon = speciesIcon or itemIcon or 134400
        }
    end
    
    -- ========================================
    -- TOY (only collectible toys in ToyBox)
    -- ========================================
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local toyInfo = C_ToyBox.GetToyInfo(itemID)
        
        -- Only proceed if this is a collectible toy
        if toyInfo then
            -- Check cache: do we already own this?
            if self:IsCollectibleOwned("toy", itemID) then
                return nil
            end
            
            return {
                type = "toy",
                id = itemID,
                name = itemName or "Unknown Toy",
                icon = itemIcon or 134400
            }
        end
        return nil
    end
    
    -- Not a collectible
    return nil
end

--[[============================================================================
    EVENT HANDLING
============================================================================]]

---Initialize collection tracking system
function WarbandNexus:InitializeCollectionTracking()
    self:BuildCollectionCache()
    self.notifiedCollectibles = {}
    self.lastBagSnapshot = self:UpdateBagSnapshot()
    
    self:RegisterBucketEvent("BAG_UPDATE_DELAYED", 0.2, "OnBagUpdateForCollections")
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnCollectionUpdated")
    self:RegisterEvent("NEW_PET_ADDED", "OnCollectionUpdated")
    self:RegisterEvent("NEW_TOY_ADDED", "OnCollectionUpdated")
end

---Handle collection update events (add new collectible to cache)
---@param event string Event name
---@param ... any Event parameters
function WarbandNexus:OnCollectionUpdated(event, ...)
    if not self.collectionCache then
        self:BuildCollectionCache()
        return
    end
    
    if event == "NEW_MOUNT_ADDED" then
        local mountID = ...
        if mountID then
            self.collectionCache.mounts[mountID] = true
        end
    
    elseif event == "NEW_PET_ADDED" then
        local petID = ...
        if petID and C_PetJournal then
            local speciesID = C_PetJournal.GetPetInfoByPetID(petID)
            if speciesID then
                self.collectionCache.pets[speciesID] = true
            end
        end
    
    elseif event == "NEW_TOY_ADDED" then
        local itemID, new = ...
        if itemID and new then
            self.collectionCache.toys[itemID] = true
        end
    end
end

---Update bag snapshot
function WarbandNexus:UpdateBagSnapshot()
    local snapshot = {}
    
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                if itemInfo and itemInfo.itemID then
                    local key = itemInfo.itemID
                    if itemInfo.hyperlink and itemInfo.hyperlink:match("|Hbattlepet:") then
                        key = itemInfo.hyperlink
                    end
                    snapshot[key] = true
                end
            end
        end
    end
    
    return snapshot
end

---Handle BAG_UPDATE_DELAYED - detect new loot
function WarbandNexus:OnBagUpdateForCollections()
    if not self.db or not self.db.profile or not self.db.profile.notifications then
        return
    end

    if not self.db.profile.notifications.showLootNotifications then
        return
    end

    if not self.notifiedCollectibles then
        self.notifiedCollectibles = {}
    end
    
    if not self.lastBagSnapshot then
        self.lastBagSnapshot = {}
    end

    local currentSnapshot = self:UpdateBagSnapshot()

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local itemInfo = C_Container.GetContainerItemInfo(bag, slot)
                if itemInfo and itemInfo.itemID then
                    local key = itemInfo.itemID
                    if itemInfo.hyperlink and itemInfo.hyperlink:match("|Hbattlepet:") then
                        key = itemInfo.hyperlink
                    end
                    
                    if not self.lastBagSnapshot[key] then
                        local collectibleData = self:CheckNewCollectible(itemInfo.itemID, itemInfo.hyperlink)
                        
                        if collectibleData then
                            local trackingKey = collectibleData.type .. "_" .. collectibleData.id
                            
                            if not self.notifiedCollectibles[trackingKey] then
                                self:ShowCollectibleToast(collectibleData)
                                self.notifiedCollectibles[trackingKey] = true
                            end
                        end
                    end
                end
            end
        end
    end
    
    self.lastBagSnapshot = currentSnapshot
end



