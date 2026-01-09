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
        -- Iterate through all pets to build initial cache of owned species
        -- Note: We use GetNumPets and iterate to ensure we get all unique species
        -- For a more complete cache, we might need a different approach if this only shows journal list
        -- But for "owned" check, this is usually sufficient for loaded journal
        for i = 1, numPets do
             local petID, speciesID, owned, customName, _, _, _, _, _, _, _, _, _, _, isTradeable, isUnique = C_PetJournal.GetPetInfoByIndex(i)
             if speciesID and owned then
                 self.collectionCache.pets[speciesID] = true
             end
        end
    end
    
    -- Cache all toys
    if C_ToyBox and C_ToyBox.GetNumToys then
        -- C_ToyBox.GetNumToys returns total available toys, we need to check ownership
        -- We iterate by index which corresponds to the filtered list usually, 
        -- but for a true snapshot we should ideally check "all" toys.
        -- However, iterating known toys is safer. 
        -- Optimization: We rely on C_ToyBox.PlayerHasToy for checks, 
        -- but we populate cache for diffing.
        -- Since GetNumToys depends on filters, this might be incomplete.
        -- Better approach for snapshot: Use C_ToyBox.GetToyInfo on demand or accept filter limitations?
        -- The plan suggests: "C_ToyBox taranır."
        -- Let's stick to iterating what we can see or rely on events for new additions.
        -- To be safe against filter bugs, we primarily rely on PlayerHasToy in checks.
        -- But for the cache diff, we'll try to populate what we can.
        for i = 1, C_ToyBox.GetNumToys() do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and PlayerHasToy and PlayerHasToy(itemID) then
                self.collectionCache.toys[itemID] = true
            end
        end
    end
    end)
    
    if not success then
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
        
        -- Check API directly for ownership (most reliable)
        local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not name then return nil end
        
        -- Already collected - skip
        if isCollected then
            return nil
        end
        
        return {
            type = "mount",
            id = mountID,
            name = name,
            icon = icon
        }
    end
    
    -- ========================================
    -- PET (classID 17 - Battle Pets / Caged Pets)
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
        
        -- Check collection count - only notify if player has 0 of this species
        local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
        if numOwned and numOwned > 0 then
            return nil -- Already own at least one
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
    -- COMPANION PETS (classID 15, subclass 2)
    -- ========================================
    if classID == 15 and subclassID == 2 then
        if not C_PetJournal then return nil end
        
        local speciesID = nil
        local speciesName = nil
        local speciesIcon = nil
        
        -- GetPetInfoByItemID returns: speciesName, speciesIcon, petType, companionID, ...
        -- companionID (4th return) is the speciesID
        if C_PetJournal.GetPetInfoByItemID then
            local petName, petIcon, petType, companionID = C_PetJournal.GetPetInfoByItemID(itemID)
            if companionID and type(companionID) == "number" then
                speciesID = companionID
                speciesName = petName
                speciesIcon = petIcon
            end
        end

        if speciesID then
            -- Check collection count - only notify if player has 0 of this species
            local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
            if numOwned and numOwned > 0 then
                return nil -- Already own at least one
            end
            
            -- Use already captured name/icon or fetch from speciesID
            if not speciesName then
                speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            end
            
             return {
                type = "pet",
                id = speciesID,
                name = speciesName or itemName or "Unknown Pet",
                icon = speciesIcon or itemIcon or 134400
            }
        end
    end
    
    -- ========================================
    -- UNIVERSAL FALLBACK (For Items with weird ClassIDs)
    -- ========================================
    -- Some items (like Void-Scarred Egg) are Consumables (Class 0) but teach Mounts or Pets.
    -- We perform a check here if previous specific checks failed.
    
    -- 1. Check for MOUNT (using API isCollected)
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local mountID = C_MountJournal.GetMountFromItem(itemID)
        if mountID then
            local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if name then
                if isCollected then
                    return nil -- Already owned
                end
                    return {
                        type = "mount",
                        id = mountID,
                        name = name,
                        icon = icon
                    }
            end
        end
    end

    -- 2. Check for PET (using API numOwned)
    if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        if speciesID then
            -- Check collection count - only show if 0 owned
            local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
            if numOwned and numOwned > 0 then
                return nil -- Already own at least one
            end
                local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                 return {
                    type = "pet",
                    id = speciesID,
                    name = speciesName or itemName or "Unknown Pet",
                    icon = speciesIcon or itemIcon or 134400
                }
        end
    end
    
    -- 3. Check for TOY (using PlayerHasToy API)
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local toyInfo = C_ToyBox.GetToyInfo(itemID)
        
        -- Only proceed if this is a collectible toy
        if toyInfo then
            -- Check ownership using PlayerHasToy (most reliable)
            if PlayerHasToy and PlayerHasToy(itemID) then
                return nil -- Already owned
            end
            
            return {
                type = "toy",
                id = itemID,
                name = itemName or "Unknown Toy",
                icon = itemIcon or 134400
            }
        end
    end
    
    -- Not a collectible
    return nil
end

--[[============================================================================
    EVENT HANDLING
============================================================================]]

---Update local cache with new item
function WarbandNexus:UpdateCollectionCache(type, id)
    if not self.collectionCache then self:BuildCollectionCache() end
    
    if type == "mount" then
        self.collectionCache.mounts[id] = true
    elseif type == "pet" then
        self.collectionCache.pets[id] = true
    elseif type == "toy" then
        self.collectionCache.toys[id] = true
    end
end

---Handle ACHIEVEMENT_EARNED event
function WarbandNexus:OnAchievementEarned(event, achievementID)
    self:HandleAchievement(achievementID)
end

---Process achievement rewards
---@param achievementID number
function WarbandNexus:HandleAchievement(achievementID)
    if not achievementID then return end
    
    -- First, check if the achievement itself is a plan
    local achievementName, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
    if achievementName then
        local completedPlan = self:CheckAchievementPlanCompletion(achievementID)
        
        if completedPlan then
            -- Show achievement plan completion notification
            if self.ShowToastNotification then
                self:ShowToastNotification({
                    icon = icon or "Interface\\Icons\\Achievement_General",
                    title = "Plan Completed!",
                    subtitle = "Achievement Earned",
                    message = achievementName,
                    category = "ACHIEVEMENT",
                    planType = "achievement",
                    autoDismiss = 8,
                    playSound = true,
                })
            end
        end
    end
    
    -- Then check for achievement rewards (mounts/pets/toys)
    local rewardItemID = C_AchievementInfo.GetRewardItemID(achievementID)
    if not rewardItemID or rewardItemID == 0 then return end
    
    -- Load item data if needed (async mixin)
    local item = Item:CreateFromItemID(rewardItemID)
    item:ContinueOnItemLoad(function()
        local collectibleData = self:CheckNewCollectible(rewardItemID)
        
        if collectibleData then
            local trackingKey = collectibleData.type .. "_" .. collectibleData.id
            
            -- Unified deduplication check (30 second window)
            if self:WasRecentlyNotified(trackingKey) then
                return
            end
            
            -- Update Cache, mark as notified, show toast
            self:UpdateCollectionCache(collectibleData.type, collectibleData.id)
            self:MarkAsNotified(trackingKey, "achievement")
            self:ShowCollectibleToast(collectibleData)
        end
    end)
end

---Initialize collection tracking system
function WarbandNexus:InitializeCollectionTracking()
    self:BuildCollectionCache()
    
    -- Unified deduplication table: { ["mount_12345"] = { time = GetTime(), source = "loot" } }
    self.recentlyNotified = {}
    self.lastBagSnapshot = self:UpdateBagSnapshot()
    
    self:RegisterBucketEvent("BAG_UPDATE_DELAYED", 0.2, "OnBagUpdateForCollections")
    
    -- Event-based tracking (Standard)
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnCollectionUpdated")
    self:RegisterEvent("NEW_PET_ADDED", "OnCollectionUpdated")
    self:RegisterEvent("NEW_TOY_ADDED", "OnCollectionUpdated")
    
    -- Achievement-based tracking (Direct Injection)
    self:RegisterEvent("ACHIEVEMENT_EARNED", "OnAchievementEarned")
    
    -- Ensure cache is built on login
    if IsLoggedIn() then
        self:BuildCollectionCache()
    else
        self:RegisterEvent("PLAYER_LOGIN", "BuildCollectionCache")
    end
end

---Check if a collectible was recently notified (within 30 seconds)
---@param trackingKey string The tracking key (e.g., "mount_12345")
---@return boolean True if recently notified
function WarbandNexus:WasRecentlyNotified(trackingKey)
    if not self.recentlyNotified then return false end
    local recent = self.recentlyNotified[trackingKey]
    if recent and (GetTime() - recent.time) < 30 then
        return true
    end
    return false
end

---Mark a collectible as notified
---@param trackingKey string The tracking key
---@param source string The notification source (e.g., "loot", "learned", "achievement")
function WarbandNexus:MarkAsNotified(trackingKey, source)
    if not self.recentlyNotified then self.recentlyNotified = {} end
    self.recentlyNotified[trackingKey] = { time = GetTime(), source = source }
end

---Handle collection update events (add new collectible to cache)
---@param event string Event name
---@param ... any Event parameters
function WarbandNexus:OnCollectionUpdated(event, ...)
    if not self.collectionCache then
        self:BuildCollectionCache()
        return
    end
    
    local type, id, name, icon
    
    if event == "NEW_MOUNT_ADDED" then
        local mountID = ...
        if not mountID then return end
        
        -- Snapshot Diff Check
        if self.collectionCache.mounts[mountID] then return end
        
        type = "mount"
        id = mountID
        local mName, _, mIcon = C_MountJournal.GetMountInfoByID(mountID)
        name = mName
        icon = mIcon
    
    elseif event == "NEW_PET_ADDED" then
        local petID = ...
        if petID and C_PetJournal then
            local speciesID = C_PetJournal.GetPetInfoByPetID(petID)
            if speciesID then
                -- Check duplicates (0 -> 1 is new)
                local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
                if numOwned and numOwned > 1 then return end -- Duplicate
                
                if self.collectionCache.pets[speciesID] then return end
                
                type = "pet"
                id = speciesID
                local sName, sIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                name = sName
                icon = sIcon
            end
        end
    
    elseif event == "NEW_TOY_ADDED" then
        local itemID, new = ...
        if not itemID or not new then return end
        
        if self.collectionCache.toys[itemID] then return end
        
        type = "toy"
        id = itemID
        local _, tName, _, _, _, _, _, _, _, tIcon = GetItemInfo(itemID)
        
        if not tName then
            C_Item.RequestLoadItemDataByID(itemID)
            name = "New Toy"
            icon = 134400
        else
            name = tName
            icon = tIcon
        end
    end
    
    if type and id and name then
        local trackingKey = type .. "_" .. id
        
        -- Unified deduplication check (30 second window) - CHECK FIRST
        if self:WasRecentlyNotified(trackingKey) then
            return
        end
        
        -- Mark as notified IMMEDIATELY to prevent duplicates
        self:MarkAsNotified(trackingKey, "learned")
        
        -- Update cache
        self:UpdateCollectionCache(type, id)
        
        -- Check if this completes a plan
        local completedPlan = self:CheckPlanCompletion(type, id)
        
        if completedPlan then
            -- Show plan completion notification
            if self.ShowToastNotification then
                -- Map type to category display
                local categoryMap = {
                    mount = "MOUNT",
                    pet = "PET",
                    toy = "TOY",
                    recipe = "RECIPE",
                }
                
                self:ShowToastNotification({
                    icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
                    title = "Plan Completed!",
                    subtitle = "Added to Collection",
                    message = name,
                    category = categoryMap[type] or "PLAN",
                    planType = type,
                    autoDismiss = 8,
                    playSound = true,
                })
            end
        else
            -- Show regular collectible toast
            self:ShowCollectibleToast({
                type = type,
                id = id,
                name = name,
                icon = icon
            })
        end
    end
end

---Check if a collected item completes an active plan
---@param itemType string - "mount", "pet", or "toy"
---@param itemId number - The ID of the collected item
---@return table|nil - The completed plan or nil
function WarbandNexus:CheckPlanCompletion(itemType, itemId)
    if not self.db or not self.db.global or not self.db.global.plans then
        return nil
    end
    
    -- Map item type to plan type
    local planTypeMap = {
        mount = "mount",
        pet = "pet",
        toy = "toy",
    }
    
    local planType = planTypeMap[itemType]
    if not planType then return nil end
    
    -- Check all active plans
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == planType then
            -- Check if IDs match
            if planType == "mount" and plan.mountID == itemId then
                return plan
            elseif planType == "pet" and plan.speciesID == itemId then
                return plan
            elseif planType == "toy" and plan.itemID == itemId then
                return plan
            end
        end
    end
    
    return nil
end

---Check if an earned achievement completes an active plan
---@param achievementID number - The ID of the earned achievement
---@return table|nil - The completed plan or nil
function WarbandNexus:CheckAchievementPlanCompletion(achievementID)
    if not self.db or not self.db.global or not self.db.global.plans then
        return nil
    end
    
    -- Check all active plans for matching achievement
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "achievement" and plan.achievementID == achievementID then
            return plan
        end
    end
    
    return nil
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
                    
                    -- Use speciesID for battle pets if possible to differentiate
                    if itemInfo.hyperlink and itemInfo.hyperlink:match("|Hbattlepet:") then
                        local speciesID = tonumber(itemInfo.hyperlink:match("|Hbattlepet:(%d+):"))
                        if speciesID then
                             key = "pet:" .. speciesID
                        else
                             key = itemInfo.hyperlink
                        end
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
                        local speciesID = tonumber(itemInfo.hyperlink:match("|Hbattlepet:(%d+):"))
                        if speciesID then
                             key = "pet:" .. speciesID
                        else
                             key = itemInfo.hyperlink
                        end
                    end
                    
                    if not self.lastBagSnapshot[key] then
                        -- Found a new item in bag
                        local item = Item:CreateFromItemID(itemInfo.itemID)
                        item:ContinueOnItemLoad(function()
                            local collectibleData = self:CheckNewCollectible(itemInfo.itemID, itemInfo.hyperlink)
                            
                            if collectibleData then
                                local trackingKey = collectibleData.type .. "_" .. collectibleData.id
                                
                                -- Unified deduplication check (30 second window)
                                if self:WasRecentlyNotified(trackingKey) then
                                    return
                                end
                                
                                -- Mark as notified and show toast
                                self:MarkAsNotified(trackingKey, "loot")
                                self:ShowCollectibleToast(collectibleData)
                            end
                        end)
                    end
                end
            end
        end
    end
    
    self.lastBagSnapshot = currentSnapshot
end




