--[[
    Warband Nexus - Unified Collection Service
    
    Unified collection system with persistent DB-backed cache
    
    Replaces deprecated modules:
    - CollectionManager.lua (REMOVED)
    - CollectionScanner.lua (REMOVED)
    
    Provides:
    1. Real-time detection when mounts/pets/toys are obtained
    2. Background async scanning for Browse UI (uncollected items)
    3. Persistent DB-backed cache (survives /reload)
    4. Incremental updates (no full rescans)
    5. Event-driven notifications
    
    Events fired:
    - WN_COLLECTIBLE_OBTAINED: Real-time detection
    - WN_COLLECTION_SCAN_COMPLETE: Background scan finished
    - WN_COLLECTION_SCAN_PROGRESS: Scan progress updates
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local FRAME_BUDGET_MS = Constants.FRAME_BUDGET_MS
local BATCH_SIZE = Constants.BATCH_SIZE
local CACHE_VERSION = Constants.COLLECTION_CACHE_VERSION

-- ============================================================================
-- COLLECTION CACHE (PERSISTENT IN DB)
-- ============================================================================
--[[
    Unified cache for both real-time and background scanning:
    - owned: {mountID/speciesID/itemID -> true} - O(1) lookups (RAM only)
    - uncollected: {type -> {id -> {name, icon, source...}}} - Browse UI data (PERSISTED TO DB)
    
    IMPORTANT: uncollected cache is saved to DB (SavedVariables) to avoid re-scanning on every reload.
    Only scan when:
    1. DB cache is empty (first time)
    2. User manually requests refresh
    3. Real-time detection adds/removes items (incremental update)
]]

local collectionCache = {
    owned = {
        mounts = {},
        pets = {},
        toys = {}
    },
    uncollected = {
        mount = {},       -- Singular to match COLLECTION_CONFIGS keys
        pet = {},
        toy = {},
        achievement = {}, -- Achievement cache
        title = {},       -- Title cache
        transmog = {},    -- Transmog cache
        illusion = {}     -- Illusion cache
    },
    version = CACHE_VERSION,
    lastScan = time(),  -- Initialize to current time to avoid huge negative numbers
}

-- Global loading state (accessible from UI modules like PlansUI)
ns.CollectionLoadingState = {
    isLoading = false,
    loadingProgress = 0,  -- 0-100
    currentStage = nil,   -- "Mounts", "Pets", "Toys", "Achievements", etc.
    currentCategory = nil,
    totalItems = 0,
    scannedItems = 0,
}

---Initialize collection cache from DB (load persisted data)
---Called on addon load to restore previous scan results
function WarbandNexus:InitializeCollectionCache()
    print("|cff9370DB[WN CollectionService]|r InitializeCollectionCache called")
    
    -- CRITICAL: Ensure DB is initialized
    if not self.db or not self.db.global then
        print("|cffff0000[WN CollectionService]|r ERROR: DB not initialized yet!")
        -- Retry after 1 second
        C_Timer.After(1, function()
            if self and self.InitializeCollectionCache then
                self:InitializeCollectionCache()
            end
        end)
        return
    end
    
    -- Initialize DB structure if needed
    if not self.db.global.collectionCache then
        self.db.global.collectionCache = {
            uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, transmog = {}, illusion = {} },
            version = CACHE_VERSION,
            lastScan = time()  -- Initialize to current time
        }
        print("|cffffcc00[WN CollectionService]|r Initialized NEW collection cache (empty)")
        return
    end
    
    -- Load from DB
    local dbCache = self.db.global.collectionCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        print("|cffffcc00[WN CollectionService]|r Cache version mismatch (DB: " .. tostring(dbCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
        self.db.global.collectionCache = {
            uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, transmog = {}, illusion = {} },
            version = CACHE_VERSION,
            lastScan = time()  -- Initialize to current time
        }
        return
    end
    
    -- Load uncollected cache from DB to RAM
    collectionCache.uncollected = dbCache.uncollected or { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, transmog = {}, illusion = {} }
    collectionCache.lastScan = dbCache.lastScan or 0
    collectionCache.lastAchievementScan = dbCache.lastAchievementScan or 0  -- Separate timestamp
    
    -- Count loaded items
    local mountCount, petCount, toyCount, achievementCount, titleCount, illusionCount = 0, 0, 0, 0, 0, 0
    for _ in pairs(collectionCache.uncollected.mount or {}) do mountCount = mountCount + 1 end
    for _ in pairs(collectionCache.uncollected.pet or {}) do petCount = petCount + 1 end
    for _ in pairs(collectionCache.uncollected.toy or {}) do toyCount = toyCount + 1 end
    for _ in pairs(collectionCache.uncollected.achievement or {}) do achievementCount = achievementCount + 1 end
    for _ in pairs(collectionCache.uncollected.title or {}) do titleCount = titleCount + 1 end
    for _ in pairs(collectionCache.uncollected.illusion or {}) do illusionCount = illusionCount + 1 end
    
    if achievementCount == 0 then
        print("|cffffcc00[WN CollectionService]|r Achievement cache is EMPTY (scan will be triggered on first view)")
    end
    
    print(string.format("|cff00ff00[WN CollectionService]|r Loaded cache from DB: %d mounts, %d pets, %d toys, %d achievements, %d titles, %d illusions", 
        mountCount, petCount, toyCount, achievementCount, titleCount, illusionCount))
end

---Save collection cache to DB (persist scan results)
---Called after scan completion to avoid re-scanning on reload
function WarbandNexus:SaveCollectionCache()
    if not self.db or not self.db.global then
        print("|cffff0000[WN CollectionService ERROR]|r Cannot save cache: DB not initialized")
        return
    end
    
    -- Save to DB
    self.db.global.collectionCache = {
        uncollected = collectionCache.uncollected,
        version = CACHE_VERSION,
        lastScan = collectionCache.lastScan,
        lastAchievementScan = collectionCache.lastAchievementScan or collectionCache.lastScan,  -- Save achievement-specific timestamp
    }
    
    -- Count saved items
    local mountCount, petCount, toyCount = 0, 0, 0
    for _ in pairs(collectionCache.uncollected.mount or {}) do mountCount = mountCount + 1 end
    for _ in pairs(collectionCache.uncollected.pet or {}) do petCount = petCount + 1 end
    for _ in pairs(collectionCache.uncollected.toy or {}) do toyCount = toyCount + 1 end
    
    print(string.format("|cff00ff00[WN CollectionService]|r Saved cache to DB: %d mounts, %d pets, %d toys", 
        mountCount, petCount, toyCount))
end

---Invalidate collection cache (mark for refresh)
---Called when collection data changes (e.g., new mount obtained)
function WarbandNexus:InvalidateCollectionCache()
    -- Clear RAM caches
    collectionCache.owned.mounts = {}
    collectionCache.owned.pets = {}
    collectionCache.owned.toys = {}
    
    -- Mark lastScan to trigger refresh on next UI open
    collectionCache.lastScan = 0
    
    print("|cffffcc00[WN CollectionService]|r Collection cache invalidated (will refresh on next scan)")
end

---Remove collectible from uncollected cache (incremental update when player obtains it)
---This is called by event handlers when player collects a new mount/pet/toy
---@param collectionType string "mount", "pet", or "toy"
---@param id number mountID, speciesID, or itemID
function WarbandNexus:RemoveFromUncollected(collectionType, id)
    if not collectionCache.uncollected[collectionType] then
        return
    end
    
    if collectionCache.uncollected[collectionType][id] then
        local itemName = collectionCache.uncollected[collectionType][id].name or "Unknown"
        collectionCache.uncollected[collectionType][id] = nil
        
        -- Update owned cache
        if not collectionCache.owned[collectionType .. "s"] then
            collectionCache.owned[collectionType .. "s"] = {}
        end
        collectionCache.owned[collectionType .. "s"][id] = true
        
        -- Persist to DB (incremental update)
        self:SaveCollectionCache()
        
        print(string.format("|cff00ff00[WN CollectionService]|r INCREMENTAL UPDATE: Removed %s from uncollected %ss (now collected)", 
            itemName, collectionType))
    end
end

-- Active coroutines for async scanning
local activeCoroutines = {}

-- ============================================================================
-- REAL-TIME CACHE BUILDING (Fast O(1) Lookup)
-- ============================================================================

---Build or refresh owned collection cache
---Used for real-time detection (fast ownership checks)
function WarbandNexus:BuildCollectionCache()
    print("|cff9370DB[WN CollectionService]|r Building collection cache...")
    local success, err = pcall(function()
        collectionCache.owned = {
            mounts = {},
            pets = {},
            toys = {}
        }
        
        -- Cache all owned mounts
        if C_MountJournal and C_MountJournal.GetMountIDs then
            local mountIDs = C_MountJournal.GetMountIDs()
            for _, mountID in ipairs(mountIDs) do
                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if isCollected then
                    collectionCache.owned.mounts[mountID] = true
                end
            end
        end
        
        -- Cache all owned pets (by speciesID)
        if C_PetJournal and C_PetJournal.GetNumPets then
            local numPets = C_PetJournal.GetNumPets()
            for i = 1, numPets do
                local petID, speciesID, owned = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID and owned then
                    collectionCache.owned.pets[speciesID] = true
                end
            end
        end
        
        -- Cache all owned toys
        if C_ToyBox and C_ToyBox.GetNumToys then
            for i = 1, C_ToyBox.GetNumToys() do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and PlayerHasToy and PlayerHasToy(itemID) then
                    collectionCache.owned.toys[itemID] = true
                end
            end
        end
    end)
    
    if not success then
        print("|cffff4444[WN CollectionService ERROR]|r Cache build failed: " .. tostring(err))
    else
        local total = 0
        for _, cache in pairs(collectionCache.owned) do
            for _ in pairs(cache) do total = total + 1 end
        end
        print("|cff9370DB[WN CollectionService]|r Cache built: " .. total .. " items owned")
    end
end

---Check if player owns a collectible
---@param collectibleType string "mount", "pet", or "toy"
---@param id number mountID, speciesID, or itemID
---@return boolean owned
function WarbandNexus:IsCollectibleOwned(collectibleType, id)
    if not collectionCache.owned[collectibleType] then
        self:BuildCollectionCache()
    end
    
    return collectionCache.owned[collectibleType][id] == true
end

-- ============================================================================
-- REAL-TIME EVENT HANDLERS (NEW_MOUNT_ADDED, NEW_PET_ADDED, NEW_TOY_ADDED)
-- ============================================================================

---Handle NEW_MOUNT_ADDED event
---Fires when player learns a new mount
---@param mountID number The mount ID
function WarbandNexus:OnNewMountAdded(event, mountID)
    if not mountID then return end
    
    local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
    if not name then return end
    
    -- Update owned cache
    collectionCache.owned.mounts[mountID] = true
    
    -- Remove from uncollected cache if present
    self:RemoveFromUncollected("mount", mountID)
    
    -- Fire notification event
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "mount",
        id = mountID,
        name = name,
        icon = icon
    })
    
    print("|cff00ff00[WN CollectionService]|r NEW MOUNT: " .. name)
end

---Handle NEW_PET_ADDED event
---Fires when player learns a new battle pet
---@param speciesID number The pet species ID
function WarbandNexus:OnNewPetAdded(event, speciesID)
    if not speciesID then return end
    
    local name, icon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if not name then return end
    
    -- Update owned cache
    collectionCache.owned.pets[speciesID] = true
    
    -- Remove from uncollected cache if present
    self:RemoveFromUncollected("pet", speciesID)
    
    -- Fire notification event
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "pet",
        id = speciesID,
        name = name,
        icon = icon
    })
    
    print("|cff00ff00[WN CollectionService]|r NEW PET: " .. name)
end

---Handle NEW_TOY_ADDED event
---Fires when player learns a new toy
---@param itemID number The toy item ID
function WarbandNexus:OnNewToyAdded(event, itemID)
    if not itemID then return end
    
    -- Toy APIs are sometimes delayed, use pcall for safety
    local success, name = pcall(GetItemInfo, itemID)
    if not success or not name then
        -- Retry after a short delay if item data not loaded yet
        C_Timer.After(0.5, function()
            self:OnNewToyAdded(event, itemID)
        end)
        return
    end
    
    local icon = GetItemIcon(itemID)
    
    -- Update owned cache
    collectionCache.owned.toys[itemID] = true
    
    -- Remove from uncollected cache if present
    self:RemoveFromUncollected("toy", itemID)
    
    -- Fire notification event
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "toy",
        id = itemID,
        name = name,
        icon = icon
    })
    
    print("|cff00ff00[WN CollectionService]|r NEW TOY: " .. name)
end

---Handle TRANSMOG_COLLECTION_UPDATED event
---Fires when transmog collection changes (including illusions)
---We need to detect which illusion was added by comparing before/after
function WarbandNexus:OnTransmogCollectionUpdated(event)
    if not C_TransmogCollection or not C_TransmogCollection.GetIllusions then return end
    
    -- Throttle checks to avoid spam (illusions are rare)
    if self._lastIllusionCheck and (GetTime() - self._lastIllusionCheck) < 2 then
        return
    end
    self._lastIllusionCheck = GetTime()
    
    -- Get current illusion state
    local illusions = C_TransmogCollection.GetIllusions()
    if not illusions then return end
    
    -- Build current collected set
    local currentCollected = {}
    for _, illusionInfo in ipairs(illusions) do
        if illusionInfo and illusionInfo.visualID and illusionInfo.isCollected then
            currentCollected[illusionInfo.visualID] = illusionInfo
        end
    end
    
    -- Initialize previous state if not exists
    if not self._previousIllusionState then
        self._previousIllusionState = currentCollected
        return
    end
    
    -- Compare and find newly collected illusions
    for visualID, illusionInfo in pairs(currentCollected) do
        if not self._previousIllusionState[visualID] then
            -- NEW ILLUSION COLLECTED!
            local name = illusionInfo.name
            
            -- Try spell name if no name
            if (not name or name == "") and illusionInfo.spellID then
                local spellName = C_Spell and C_Spell.GetSpellName(illusionInfo.spellID)
                if spellName and spellName ~= "" then
                    name = spellName
                end
            end
            
            -- Fallback to visualID
            if not name or name == "" then
                name = "Illusion " .. visualID
            end
            
            local icon = illusionInfo.icon or 134400
            
            -- Remove from uncollected cache if present
            self:RemoveFromUncollected("illusion", visualID)
            
            -- Fire notification event
            self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                type = "illusion",
                id = visualID,
                name = name,
                icon = icon
            })
            
            print("|cff00ff00[WN CollectionService]|r NEW ILLUSION: " .. name .. " (ID: " .. visualID .. ")")
        end
    end
    
    -- Update previous state
    self._previousIllusionState = currentCollected
end

-- Register real-time collection events
-- These fire immediately when player learns a mount/pet/toy
WarbandNexus:RegisterEvent("NEW_MOUNT_ADDED", "OnNewMountAdded")
WarbandNexus:RegisterEvent("NEW_PET_ADDED", "OnNewPetAdded")
WarbandNexus:RegisterEvent("NEW_TOY_ADDED", "OnNewToyAdded")

-- ============================================================================
-- REAL-TIME COLLECTION DETECTION
-- ============================================================================

---Check if an item is a NEW collectible that player doesn't own
---Used for real-time detection (inventory/bank scanning)
---@param itemID number The item ID
---@param hyperlink string|nil Item hyperlink (required for caged pets)
---@return table|nil {type, id, name, icon} or nil if not a new collectible
function WarbandNexus:CheckNewCollectible(itemID, hyperlink)
    if not itemID then return nil end
    print("|cff9370DB[WN CollectionService]|r CheckNewCollectible: itemID=" .. tostring(itemID))
    
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
        
        -- Check if already owned
        local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
        if not name or isCollected then return nil end
        
        print("|cff00ff00[WN CollectionService]|r NEW MOUNT DETECTED: " .. name .. " (ID: " .. mountID .. ")")
        return {
            type = "mount",
            id = mountID,
            name = name,
            icon = icon
        }
    end
    
    -- ========================================
    -- PETS (Battle Pets: classID 17, Companion Pets: classID 15/subclass 2)
    -- ========================================
    if classID == 17 or (classID == 15 and subclassID == 2) then
        if not C_PetJournal then return nil end
        
        local speciesID = nil
        
        -- Try API first
        if C_PetJournal.GetPetInfoByItemID then
            speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        end
        
        -- Extract from hyperlink for caged pets (classID 17)
        if not speciesID and hyperlink and classID == 17 then
            speciesID = tonumber(hyperlink:match("|Hbattlepet:(%d+):"))
        end
        
        if not speciesID then return nil end
        
        -- Check if player owns ANY of this species
        local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
        if numOwned and numOwned > 0 then return nil end
        
        local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        
        return {
            type = "pet",
            id = speciesID,
            name = speciesName or itemName or "Unknown Pet",
            icon = speciesIcon or itemIcon or 134400
        }
    end
    
    -- ========================================
    -- TOY (classID 15, subclass 0)
    -- ========================================
    if classID == 15 and subclassID == 0 then
        if not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
        
        local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
        if not toyName then return nil end
        
        -- Check if already owned
        if PlayerHasToy and PlayerHasToy(itemID) then return nil end
        
        print("|cff00ff00[WN CollectionService]|r NEW TOY DETECTED: " .. toyName .. " (ID: " .. itemID .. ")")
        return {
            type = "toy",
            id = itemID,
            name = toyName,
            icon = toyIcon or itemIcon
        }
    end
    
    return nil
end

-- ============================================================================
-- BACKGROUND SCANNING (Async Coroutine-Based)
-- ============================================================================

-- Runtime cache for illusions (used during scan to avoid API re-calls)
local illusionRuntimeCache = nil
local illusionDebugCount = 0  -- Debug counter for illusion logging

---Unified collection configuration for background scanning
local COLLECTION_CONFIGS = {
    mount = {
        name = "Mounts",
        iterator = function()
            if not C_MountJournal then return {} end
            return C_MountJournal.GetMountIDs() or {}
        end,
        extract = function(mountID)
            local name, spellID, icon, _, _, sourceType, _, isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if not name then return nil end
            
            local _, description, source = C_MountJournal.GetMountInfoExtraByID(mountID)
            
            return {
                id = mountID,
                name = name,
                icon = icon,
                spellID = spellID,
                source = source or "Unknown",
                sourceType = sourceType,
                description = description,
                collected = isCollected,
                shouldHideOnChar = shouldHideOnChar,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected or data.shouldHideOnChar then return false end
            
            -- Use centralized filter
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and 
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableMount(data) then
                return false
            end
            
            return true
        end
    },
    
    pet = {
        name = "Pets",
        iterator = function()
            if not C_PetJournal then return {} end
            
            local numPets = C_PetJournal.GetNumPets()
            local pets = {}
            for i = 1, numPets do
                table.insert(pets, i)
            end
            return pets
        end,
        extract = function(index)
            local _, speciesID, owned, _, _, _, _, speciesName, icon, petType, _, _, description = C_PetJournal.GetPetInfoByIndex(index)
            if not speciesName then return nil end
            
            local _, _, _, _, source = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            
            return {
                id = speciesID,
                name = speciesName,
                icon = icon,
                source = source or "Pet Collection",
                description = description,
                collected = owned,
                petType = petType,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and 
               ns.CollectionRules.UnobtainableFilters:IsUnobtainablePet(data) then
                return false
            end
            
            return true
        end
    },
    
    toy = {
        name = "Toys",
        iterator = function()
            if not C_ToyBox then return {} end
            
            local numToys = C_ToyBox.GetNumToys() or 0
            local toys = {}
            for i = 1, numToys do
                table.insert(toys, i)
            end
            return toys
        end,
        extract = function(index)
            local itemID = C_ToyBox.GetToyFromIndex(index)
            if not itemID then return nil end
            
            local _, name, icon = C_ToyBox.GetToyInfo(itemID)
            if not name then return nil end
            
            local hasToy = PlayerHasToy(itemID)
            local sourceText = "Toy Collection"  -- Simplified for now
            
            return {
                id = itemID,
                name = name,
                icon = icon,
                source = sourceText,
                collected = hasToy,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and 
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableToy(data) then
                return false
            end
            
            return true
        end
    },
    
    achievement = {
        name = "Achievements",
        iterator = function()
            if not GetCategoryList then return {} end
            
            local categoryList = GetCategoryList() or {}
            local allAchievements = {}
            
            for _, categoryID in ipairs(categoryList) do
                if categoryID then
                    local numAchievements = GetCategoryNumAchievements(categoryID)
                    for achIndex = 1, numAchievements do
                        table.insert(allAchievements, {categoryID = categoryID, achIndex = achIndex})
                    end
                end
            end
            
            return allAchievements
        end,
        extract = function(item)
            local success, id, name, points, completed, month, day, year, description, flags, icon = pcall(GetAchievementInfo, item.categoryID, item.achIndex)
            if not success or not id or not name then return nil end
            
            -- Get reward info
            local rewardItemID, rewardTitle
            local rewardSuccess, rewardItem, title = pcall(GetAchievementReward, id)
            if rewardSuccess then
                if type(rewardItem) == "number" then
                    rewardItemID = rewardItem
                end
                if type(title) == "string" and title ~= "" then
                    rewardTitle = title
                elseif type(rewardItem) == "string" and rewardItem ~= "" then
                    rewardTitle = rewardItem
                end
            end
            
            return {
                id = id,
                name = name,
                icon = icon,
                points = points,
                description = description,
                source = description or "Achievement",
                collected = completed,
                rewardItemID = rewardItemID,
                rewardTitle = rewardTitle,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end
    },
    
    title = {
        name = "Titles",
        iterator = function()
            if not GetCategoryList then return {} end
            
            local categoryList = GetCategoryList() or {}
            local allTitles = {}
            
            for _, categoryID in ipairs(categoryList) do
                if categoryID then
                    local numAchievements = GetCategoryNumAchievements(categoryID)
                    for achIndex = 1, numAchievements do
                        table.insert(allTitles, {categoryID = categoryID, achIndex = achIndex})
                    end
                end
            end
            
            return allTitles
        end,
        extract = function(item)
            local success, id, name, points, completed, month, day, year, description, flags, icon = pcall(GetAchievementInfo, item.categoryID, item.achIndex)
            if not success or not id or not name then return nil end
            
            -- Get reward info (titles only)
            local rewardTitle
            local rewardSuccess, rewardItem, title = pcall(GetAchievementReward, id)
            if rewardSuccess then
                if type(title) == "string" and title ~= "" then
                    rewardTitle = title
                elseif type(rewardItem) == "string" and rewardItem ~= "" then
                    rewardTitle = rewardItem
                end
            end
            
            -- Only include if has title reward
            if not rewardTitle then return nil end
            
            return {
                id = id,
                name = name,
                icon = icon,
                points = points,
                description = description,
                source = description or "Title Reward",
                collected = completed,
                rewardText = rewardTitle,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end
    },
    
    transmog = {
        name = "Transmog",
        iterator = function()
            if not C_TransmogCollection or not C_TransmogCollection.GetAllAppearanceSources then
                return {}
            end
            
            -- Get all appearance sources (efficient built-in API)
            local allSources = C_TransmogCollection.GetAllAppearanceSources()
            if not allSources then return {} end
            
            local sourceList = {}
            for sourceID, _ in pairs(allSources) do
                table.insert(sourceList, sourceID)
            end
            
            return sourceList
        end,
        extract = function(sourceID)
            if not C_TransmogCollection then return nil end
            
            local sourceInfo = C_TransmogCollection.GetSourceInfo(sourceID)
            if not sourceInfo then return nil end
            
            local itemID = sourceInfo.itemID
            local visualID = sourceInfo.visualID
            local isCollected = sourceInfo.isCollected
            local sourceText = sourceInfo.sourceText or "Transmog Collection"
            
            -- Get item info
            local itemName, _, _, _, icon
            if itemID then
                itemName, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemID)
            end
            
            return {
                id = sourceID,
                name = itemName or ("Transmog Source " .. sourceID),
                icon = icon or 134400,
                sourceText = sourceText,
                source = sourceText,
                collected = isCollected,
                itemID = itemID,
                visualID = visualID,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end
    },
    
    illusion = {
        name = "Illusions",
        iterator = function()
            if not C_TransmogCollection or not C_TransmogCollection.GetIllusions then return {} end
            
            -- Reset debug counter for new scan
            illusionDebugCount = 0
            
            local illusions = C_TransmogCollection.GetIllusions()
            if not illusions then return {} end
            
            -- Cache the full illusion table for extract() to use
            -- This avoids calling GetIllusions() hundreds of times in extract()
            illusionRuntimeCache = {}
            
            local illusionList = {}
            for _, illusionInfo in ipairs(illusions) do
                if illusionInfo and illusionInfo.sourceID then
                    -- CRITICAL: Use sourceID (not visualID!) - GetIllusionStrings needs sourceID
                    illusionRuntimeCache[illusionInfo.sourceID] = illusionInfo
                    table.insert(illusionList, illusionInfo.sourceID)
                end
            end
            
            return illusionList
        end,
        extract = function(sourceID)
            if not C_TransmogCollection then return nil end
            
            -- Use cached illusion data for isCollected check
            local illusionInfo = illusionRuntimeCache and illusionRuntimeCache[sourceID]
            if not illusionInfo then return nil end
            
            -- CORRECT API: GetIllusionStrings(sourceID) - NOT visualID!
            local name, hyperlink, sourceText = C_TransmogCollection.GetIllusionStrings(sourceID)
            
            -- Fallback 1: Try basic illusion info if API returns nil
            if not name or name == "" then
                name = illusionInfo.name
            end
            
            -- Fallback 2: Try spell name from spellID if still empty
            if (not name or name == "") and illusionInfo.spellID then
                local spellName = C_Spell and C_Spell.GetSpellName(illusionInfo.spellID)
                if spellName and spellName ~= "" then
                    name = spellName
                end
            end
            
            -- Fallback 3: Use sourceID as last resort
            if not name or name == "" then
                name = "Illusion " .. sourceID
            end
            
            -- Clean up sourceText
            if not sourceText or sourceText == "" then
                sourceText = illusionInfo.sourceText or "Unknown source"
            end
            
            local icon = illusionInfo.icon or 134400  -- Default icon
            local isCollected = illusionInfo.isCollected
            
            -- DEBUG: Log source info for first few illusions
            if not isCollected then
                if illusionDebugCount < 5 then
                    print(string.format("|cff00ffff[WN DEBUG Illusion #%d]|r sourceID: %d, visualID: %d", 
                        illusionDebugCount + 1, sourceID, illusionInfo.visualID or 0))
                    print("  GetIllusionStrings(" .. sourceID .. ") returned:")
                    print("    name:", tostring(name))
                    print("    hyperlink:", tostring(hyperlink))
                    print("    sourceText:", tostring(sourceText))
                    
                    illusionDebugCount = illusionDebugCount + 1
                end
            end
            
            return {
                id = sourceID,  -- Use sourceID as ID
                name = name,
                icon = icon,
                sourceText = sourceText,
                source = sourceText,
                collected = isCollected,
                visualID = illusionInfo.visualID,  -- Keep for reference
                hyperlink = hyperlink,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            
            -- Filter unobtainable illusions (retired, removed, etc.)
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and 
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableIllusion(data) then
                return false
            end
            
            return true
        end,
    },
}

---Scan a collection type asynchronously (coroutine-based with duplicate protection)
---@param collectionType string "mount", "pet", "toy", "achievement", "title", "transmog", "illusion"
---@param onProgress function|nil Progress callback (current, total, itemData)
---@param onComplete function|nil Completion callback (results)
function WarbandNexus:ScanCollection(collectionType, onProgress, onComplete)
    print("|cff9370DB[WN CollectionService]|r ScanCollection called for: " .. tostring(collectionType))
    
    local config = COLLECTION_CONFIGS[collectionType]
    if not config then
        print("|cffff4444[WN CollectionService ERROR]|r Invalid collection type: " .. tostring(collectionType))
        return
    end
    
    -- CRITICAL: Prevent duplicate scans (already scanning)
    if activeCoroutines[collectionType] then
        print("|cffffcc00[WN CollectionService]|r Scan already in progress for: " .. tostring(collectionType) .. ", skipping")
        return
    end
    
    -- CRITICAL: Check if scan is needed (cache exists and recent)
    local cacheExists = collectionCache.uncollected[collectionType] and next(collectionCache.uncollected[collectionType]) ~= nil
    if cacheExists then
        local lastScan = collectionCache.lastScan or 0
        local timeSinceLastScan = time() - lastScan
        
        -- If cache exists and scan was recent (< 5 minutes), skip
        if timeSinceLastScan < 300 then
            print("|cffffcc00[WN CollectionService]|r Cache exists and recent for " .. tostring(collectionType) .. " (scanned " .. timeSinceLastScan .. "s ago), skipping scan")
            return
        end
    end
    
    print("|cff00ff00[WN CollectionService]|r Starting background scan: " .. tostring(collectionType))
    
    -- Initialize loading state for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState[collectionType] then
        ns.PlansLoadingState[collectionType] = { isLoading = false, loader = nil }
    end
    
    -- Set loading state to true
    ns.PlansLoadingState[collectionType].isLoading = true
    ns.PlansLoadingState[collectionType].loadingProgress = 0
    ns.PlansLoadingState[collectionType].currentStage = "Preparing..."
    
    -- Create coroutine for async scanning
    local co = coroutine.create(function()
        local startTime = debugprofilestop()
        local results = {}
        local items = config.iterator()
        local total = #items
        
        -- Send initial progress event (0%)
        local Constants = ns.Constants
        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
                category = collectionType,
                progress = 0,
                scanned = 0,
                total = total,
            })
        end
        
        for i, item in ipairs(items) do
            -- Extract item data
            local data = config.extract(item)
            
            -- Apply filters
            if data and config.shouldInclude(data) then
                results[data.id] = data
            end
            
            -- PROGRESSIVE UPDATE: Update loading state every 50 items
            if i % 50 == 0 then
                local progress = math.min(100, math.floor((i / total) * 100))
                ns.PlansLoadingState[collectionType].loadingProgress = progress
                ns.PlansLoadingState[collectionType].currentStage = string.format("Scanning %s... (%d/%d)", config.name, i, total)
                
                -- Fire progress event for UI refresh
                if Constants and Constants.EVENTS then
                    self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
                        category = collectionType,
                        progress = progress,
                        scanned = i,
                        total = total,
                    })
                end
            end
            
            -- Progress callback (legacy)
            if onProgress and i % BATCH_SIZE == 0 then
                onProgress(i, total, data)
            end
            
            -- Yield every BATCH_SIZE items (frame budget management)
            if i % BATCH_SIZE == 0 then
                coroutine.yield()
            end
        end
        
        -- Store results in cache
        collectionCache.uncollected[collectionType] = results
        collectionCache.lastScan = time()
        
        -- FINAL PROGRESS: Set to 100%
        ns.PlansLoadingState[collectionType].loadingProgress = 100
        ns.PlansLoadingState[collectionType].currentStage = "Complete!"
        
        -- Fire final progress event (100%)
        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
                category = collectionType,
                progress = 100,
                scanned = total,
                total = total,
            })
        end
        
        local elapsed = debugprofilestop() - startTime
        local uncollectedCount = 0
        for _ in pairs(results) do uncollectedCount = uncollectedCount + 1 end
        print(string.format("|cff00ff00[WN CollectionService]|r Scan complete: %s - %d total, %d uncollected, %.2fms",
            config.name, total, uncollectedCount, elapsed))
        
        -- CRITICAL DEBUG: Verify cache write
        print("|cff00ccff[WN CollectionService DEBUG]|r Cache written to key: '" .. collectionType .. "'")
        print("|cff00ccff[WN CollectionService DEBUG]|r Cache now has keys:")
        for key, value in pairs(collectionCache.uncollected) do
            local itemCount = 0
            for _ in pairs(value) do itemCount = itemCount + 1 end
            print("|cff00ccff[WN CollectionService]|r   - '" .. key .. "' = " .. itemCount .. " items")
        end
        
        -- PERSIST TO DB (avoid re-scanning on reload)
        self:SaveCollectionCache()
        
        -- Clean up runtime caches (illusion, transmog, etc.)
        if collectionType == "illusion" and illusionRuntimeCache then
            illusionRuntimeCache = nil
            print("|cff9370DB[WN CollectionService]|r Cleared runtime cache for illusions")
        end
        
        -- Set loading state to false (scan complete)
        ns.PlansLoadingState[collectionType].isLoading = false
        
        -- Completion callback
        if onComplete then
            onComplete(results)
        end
        
        -- Fire completion event
        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, {
                category = collectionType,
                results = results,
                elapsed = elapsed,
            })
        end
        
        -- Auto-refresh UI after scan complete (like achievement scan)
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
                local mainFrame = WarbandNexus.UI.mainFrame
                if mainFrame:IsShown() and mainFrame.currentTab == "plans" then
                    print("|cff00ccff[WN CollectionService]|r Auto-refreshing UI after " .. collectionType .. " scan complete...")
                    WarbandNexus:RefreshUI()
                end
            end
        end)
    end)
    
    -- Store coroutine
    activeCoroutines[collectionType] = co
    
    -- Start ticker to resume coroutine
    local ticker
    ticker = C_Timer.NewTicker(0.1, function()
        if coroutine.status(co) == "dead" then
            ticker:Cancel()
            activeCoroutines[collectionType] = nil
            return
        end
        
        local success, err = coroutine.resume(co)
        if not success then
            self:Debug("CollectionService: Scan error - " .. tostring(err))
            ticker:Cancel()
            activeCoroutines[collectionType] = nil
        end
    end)
end

---Get uncollected items from cache (for Browse UI)
---@param collectionType string "mount", "pet", or "toy"
---@return table|nil Uncollected items {id -> data}
function WarbandNexus:GetUncollectedItems(collectionType)
    return collectionCache.uncollected[collectionType]
end

---Get uncollected mounts (UNIFIED: cache-first, scan if empty)
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected mounts {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedMounts(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Check if cache exists and has data
    local cacheExists = collectionCache.uncollected.mount and next(collectionCache.uncollected.mount) ~= nil
    
    if cacheExists then
        local cachedResults = {}
        local count = 0
        
        for mountID, mountData in pairs(collectionCache.uncollected.mount) do
            if mountData and mountData.name then
                if searchText == "" or mountData.name:lower():find(searchText, 1, true) then
                    table.insert(cachedResults, mountData)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        
        -- If we have cached data, return it
        if #cachedResults > 0 then
            print("|cff9370DB[WN CollectionService]|r Returning " .. #cachedResults .. " mounts from cache")
            return cachedResults
        end
    end
    
    -- NO CACHE: Trigger unified background scan (ONCE)
    print("|cffffcc00[WN CollectionService]|r Mount cache empty, triggering unified scan...")
    
    -- Set PlansLoadingState for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.mount then
        ns.PlansLoadingState.mount = { isLoading = false, loader = nil }
    end
    
    -- Set loading state BEFORE triggering scan
    ns.PlansLoadingState.mount.isLoading = true
    ns.PlansLoadingState.mount.loadingProgress = 0
    ns.PlansLoadingState.mount.currentStage = "Preparing..."
    
    -- Trigger unified scan in background (ONCE - ScanCollection has duplicate protection)
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("mount")
        end
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end

---Get uncollected pets (UNIFIED: cache-first, scan if empty)
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected pets {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedPets(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Check if cache exists and has data
    local cacheExists = collectionCache.uncollected.pet and next(collectionCache.uncollected.pet) ~= nil
    
    if cacheExists then
        local cachedResults = {}
        local count = 0
        
        for petID, petData in pairs(collectionCache.uncollected.pet) do
            if petData and petData.name then
                if searchText == "" or petData.name:lower():find(searchText, 1, true) then
                    table.insert(cachedResults, petData)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        
        -- If we have cached data, return it
        if #cachedResults > 0 then
            print("|cff9370DB[WN CollectionService]|r Returning " .. #cachedResults .. " pets from cache")
            return cachedResults
        end
    end
    
    -- NO CACHE: Trigger unified background scan (ONCE)
    print("|cffffcc00[WN CollectionService]|r Pet cache empty, triggering unified scan...")
    
    -- Set PlansLoadingState for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.pet then
        ns.PlansLoadingState.pet = { isLoading = false, loader = nil }
    end
    
    -- Set loading state BEFORE triggering scan
    ns.PlansLoadingState.pet.isLoading = true
    ns.PlansLoadingState.pet.loadingProgress = 0
    ns.PlansLoadingState.pet.currentStage = "Preparing..."
    
    -- Trigger unified scan in background (ONCE - ScanCollection has duplicate protection)
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("pet")
        end
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end

---Get uncollected toys (UNIFIED: cache-first, scan if empty)
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected toys {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedToys(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Check if cache exists and has data
    local cacheExists = collectionCache.uncollected.toy and next(collectionCache.uncollected.toy) ~= nil
    
    if cacheExists then
        local cachedResults = {}
        local count = 0
        
        for toyID, toyData in pairs(collectionCache.uncollected.toy) do
            if toyData and toyData.name then
                if searchText == "" or toyData.name:lower():find(searchText, 1, true) then
                    table.insert(cachedResults, toyData)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        
        -- If we have cached data, return it
        if #cachedResults > 0 then
            print("|cff9370DB[WN CollectionService]|r Returning " .. #cachedResults .. " toys from cache")
            return cachedResults
        end
    end
    
    -- NO CACHE: Trigger unified background scan (ONCE)
    print("|cffffcc00[WN CollectionService]|r Toy cache empty, triggering unified scan...")
    
    -- Set PlansLoadingState for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.toy then
        ns.PlansLoadingState.toy = { isLoading = false, loader = nil }
    end
    
    -- Set loading state BEFORE triggering scan
    ns.PlansLoadingState.toy.isLoading = true
    ns.PlansLoadingState.toy.loadingProgress = 0
    ns.PlansLoadingState.toy.currentStage = "Preparing..."
    
    -- Trigger unified scan in background (ONCE - ScanCollection has duplicate protection)
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("toy")
        end
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end


---Async achievement scanner (background scanning with coroutine)
---Scans all achievements and populates both achievement and title caches
function WarbandNexus:ScanAchievementsAsync()
    -- Prevent duplicate scans
    if activeCoroutines["achievements"] then
        print("|cffffcc00[WN CollectionService]|r Achievement scan already in progress")
        return
    end
    
    -- CRITICAL FIX: Use separate lastScan timestamp for achievements
    -- Don't share with mount/pet/toy (they update global lastScan)
    local lastAchievementScan = collectionCache.lastAchievementScan or 0
    local timeSinceLastScan = time() - lastAchievementScan
    
    -- Validate timestamp (prevent negative values from corrupted data)
    if timeSinceLastScan < 0 then
        print("|cffffcc00[WN CollectionService]|r Invalid lastAchievementScan timestamp detected, forcing scan")
        timeSinceLastScan = math.huge  -- Force scan
    end
    
    -- Check cooldown (5 minutes)
    if timeSinceLastScan < 300 then
        print(string.format("|cffffcc00[WN CollectionService]|r Achievement scan skipped (last scan %.0f seconds ago)", timeSinceLastScan))
        return
    end
    
    print("|cff9370DB[WN CollectionService]|r Starting async achievement scan...")
    
    -- Update loading state (may already be set by GetUncollectedAchievements)
    ns.CollectionLoadingState.isLoading = true
    ns.CollectionLoadingState.loadingProgress = 0
    ns.CollectionLoadingState.currentStage = "Achievements"
    ns.CollectionLoadingState.currentCategory = "achievement"
    ns.CollectionLoadingState.scannedItems = 0
    ns.CollectionLoadingState.totalItems = 0
    
    -- Fire initial progress event to trigger UI update
    self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
        category = "achievement",
        progress = 0,
        scanned = 0,
        total = 0,
    })
    
    local startTime = debugprofilestop()  -- Use debugprofilestop for elapsed time measurement
    local totalAchievements = 0
    local totalTitles = 0
    local scannedCount = 0
    local totalEstimated = 5000  -- Rough estimate for progress bar
    local lastProgressUpdate = 0  -- Throttle progress events
    local lastYield = debugprofilestop()  -- Track time since last yield
    
    local function scanCoroutine()
        -- Clear existing caches
        collectionCache.uncollected.achievement = {}
        collectionCache.uncollected.title = {}
        
        -- Get all achievement categories
        local categoryList = GetCategoryList()
        if not categoryList or #categoryList == 0 then
            print("|cffff0000[WN CollectionService]|r GetCategoryList() returned no categories")
            coroutine.yield()
            return
        end
        
        for _, categoryID in ipairs(categoryList) do
            if categoryID then
                local numAchievements = GetCategoryNumAchievements(categoryID)
                
                for achIndex = 1, numAchievements do
                    -- GetAchievementInfo with pcall protection
                    local success, id, name, points, completed, month, day, year, description, flags, icon = pcall(GetAchievementInfo, categoryID, achIndex)
                    
                    -- Update progress (throttled to reduce event spam)
                    scannedCount = scannedCount + 1
                    
                    -- OPTIMIZATION: Only fire progress event every 250 achievements (not 100)
                    -- This reduces UI refresh spam and improves FPS
                    if scannedCount % 250 == 0 then
                        local progress = math.min(100, math.floor((scannedCount / totalEstimated) * 100))
                        local timeSinceLastUpdate = debugprofilestop() - lastProgressUpdate
                        
                        -- Only update if at least 100ms passed (throttle UI updates)
                        if timeSinceLastUpdate >= 100 then
                            ns.CollectionLoadingState.loadingProgress = progress
                            ns.CollectionLoadingState.scannedItems = scannedCount
                            lastProgressUpdate = debugprofilestop()
                            
                            -- Fire progress event (UI will throttle refreshes)
                            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
                                category = "achievement",
                                progress = progress,
                                scanned = scannedCount,
                                total = totalEstimated,
                            })
                        end
                    end
                    
                    -- Skip if API call failed or achievement is completed
                    if success and id and name and not completed then
                        -- CRITICAL: GetAchievementReward with pcall protection
                        local rewardItemID, rewardTitle
                        local rewardSuccess, item, title = pcall(GetAchievementReward, id)
                        
                        if rewardSuccess then
                            -- Item ID is number, title is string
                            if type(item) == "number" then
                                rewardItemID = item
                            end
                            if type(title) == "string" and title ~= "" then
                                rewardTitle = title
                            elseif type(item) == "string" and item ~= "" then
                                -- Some achievements return title as first value
                                rewardTitle = item
                            end
                        end
                        
                        -- Store achievement
                        collectionCache.uncollected.achievement[id] = {
                            id = id,
                            name = name,
                            type = "achievement",
                            icon = icon or 134400,
                            points = points or 0,
                            description = description or "",
                            rewardItemID = rewardItemID,
                            rewardTitle = rewardTitle,
                            categoryID = categoryID
                        }
                        totalAchievements = totalAchievements + 1
                        
                        -- If this achievement grants a title, also store it separately
                        if rewardTitle then
                            collectionCache.uncollected.title[id] = {
                                id = id,
                                name = rewardTitle, -- The actual title text
                                achievementName = name, -- The achievement name
                                type = "title",
                                icon = icon or 134400,
                                points = points or 0,
                                description = description or "",
                                sourceAchievement = id
                            }
                            totalTitles = totalTitles + 1
                        end
                    end
                    
                    -- OPTIMIZATION: Yield more frequently (every 20 achievements instead of 50)
                    -- AND check frame budget (don't exceed 5ms per frame)
                    if totalAchievements % 20 == 0 then
                        local timeSinceYield = debugprofilestop() - lastYield
                        -- If we've used more than 5ms, yield immediately
                        if timeSinceYield >= 5 then
                            lastYield = debugprofilestop()
                            coroutine.yield()
                        end
                    end
                end
            end
        end
        
        -- Update last scan times
        collectionCache.lastScan = time()  -- General last scan (for other collection types)
        collectionCache.lastAchievementScan = time()  -- Achievement-specific timestamp
        
        -- Save to DB
        self:SaveCollectionCache()
        
        local elapsed = (debugprofilestop() - startTime) / 1000  -- Convert ms to seconds
        
        -- Update loading state
        ns.CollectionLoadingState.isLoading = false
        ns.CollectionLoadingState.loadingProgress = 100
        ns.CollectionLoadingState.scannedItems = scannedCount
        
        print(string.format("|cff00ff00[WN CollectionService]|r Achievement scan complete: %d achievements, %d titles (%.2fs)", 
            totalAchievements, totalTitles, elapsed))
        
        -- Fire completion event
        self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, {
            category = "achievement",
            totalAchievements = totalAchievements,
            totalTitles = totalTitles,
            elapsed = elapsed,
        })
        
        -- Force UI refresh after short delay (ensure UI is updated)
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
                local mainFrame = WarbandNexus.UI.mainFrame
                if mainFrame:IsShown() and mainFrame.currentTab == "plans" then
                    print("|cff00ccff[WN CollectionService]|r Auto-refreshing UI after scan complete...")
                    WarbandNexus:RefreshUI()
                end
            end
        end)
        
        -- Cleanup
        activeCoroutines["achievements"] = nil
    end
    
    -- Start coroutine
    local co = coroutine.create(scanCoroutine)
    activeCoroutines["achievements"] = co
    
    -- Run coroutine with frame budget
    local function resumeCoroutine()
        local co = activeCoroutines["achievements"]
        if not co then return end
        
        local budget = FRAME_BUDGET_MS
        local startTime = debugprofilestop()
        
        while (debugprofilestop() - startTime) < budget do
            local status, err = coroutine.resume(co)
            if not status then
                print("|cffff0000[WN CollectionService ERROR]|r Achievement scan failed: " .. tostring(err))
                activeCoroutines["achievements"] = nil
                return
            end
            
            -- Check if coroutine finished
            if coroutine.status(co) == "dead" then
                activeCoroutines["achievements"] = nil
                return
            end
        end
        
        -- Continue next frame
        C_Timer.After(0, resumeCoroutine)
    end
    
    resumeCoroutine()
end

---Get uncollected achievements with search and limit support
---Uses DB cache if available, otherwise triggers unified scan (ONCE)
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected achievements {id, name, type, icon, rewards}
function WarbandNexus:GetUncollectedAchievements(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Check if cache exists and has data
    local cacheExists = collectionCache.uncollected.achievement and next(collectionCache.uncollected.achievement) ~= nil
    
    if cacheExists then
        local cachedResults = {}
        local count = 0
        
        for achievementID, achievementData in pairs(collectionCache.uncollected.achievement) do
            if achievementData and achievementData.name then
                if searchText == "" or achievementData.name:lower():find(searchText, 1, true) then
                    table.insert(cachedResults, achievementData)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        
        -- If we have cached data, return it
        if #cachedResults > 0 then
            print("|cff9370DB[WN CollectionService]|r Returning " .. #cachedResults .. " achievements from cache")
            return cachedResults
        end
    end
    
    -- NO CACHE: Trigger unified background scan (ONCE)
    print("|cffffcc00[WN CollectionService]|r Achievement cache empty, triggering unified scan...")
    
    -- Set PlansLoadingState for UI (not CollectionLoadingState)
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.achievement then
        ns.PlansLoadingState.achievement = { isLoading = false, loader = nil }
    end
    
    -- IMPORTANT: Set loading state BEFORE triggering scan
    ns.PlansLoadingState.achievement.isLoading = true
    ns.PlansLoadingState.achievement.loadingProgress = 0
    ns.PlansLoadingState.achievement.currentStage = "Preparing..."
    
    -- Trigger unified scan in background (ONCE - ScanCollection has duplicate protection)
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("achievement")
        end
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end

---Get uncollected illusions with search and limit support
---Uses DB cache if available, otherwise triggers unified scan
---Get uncollected illusions (UNIFIED: cache-first, scan if empty)
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected illusions {id, name, icon, sourceText, type}
function WarbandNexus:GetUncollectedIllusions(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Check if cache exists and has data
    local cacheExists = collectionCache.uncollected.illusion and next(collectionCache.uncollected.illusion) ~= nil
    
    if cacheExists then
        local cachedResults = {}
        local count = 0
        
        for illusionID, illusionData in pairs(collectionCache.uncollected.illusion) do
            if illusionData and illusionData.name then
                if searchText == "" or illusionData.name:lower():find(searchText, 1, true) then
                    table.insert(cachedResults, illusionData)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        
        -- If we have cached data, return it
        if #cachedResults > 0 then
            print("|cff9370DB[WN CollectionService]|r Returning " .. #cachedResults .. " illusions from cache")
            return cachedResults
        end
    end
    
    -- NO CACHE: Trigger unified background scan (ONCE)
    print("|cffffcc00[WN CollectionService]|r Illusion cache empty, triggering unified scan...")
    
    -- Set PlansLoadingState for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.illusion then
        ns.PlansLoadingState.illusion = { isLoading = false, loader = nil }
    end
    
    -- Set loading state BEFORE triggering scan
    ns.PlansLoadingState.illusion.isLoading = true
    ns.PlansLoadingState.illusion.loadingProgress = 0
    ns.PlansLoadingState.illusion.currentStage = "Preparing..."
    
    -- Trigger unified scan in background (ONCE - ScanCollection has duplicate protection)
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("illusion")
        end
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end


---Get uncollected titles with search and limit support
---Uses DB cache if available, otherwise triggers unified scan
---@param searchText string|nil Optional search filter
---Get uncollected titles (UNIFIED: cache-first, scan if empty)
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected titles {id, name, type}
---NOTE: Titles are achievement-based, scanned from title-granting achievements
function WarbandNexus:GetUncollectedTitles(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Check if cache exists and has data
    local cacheExists = collectionCache.uncollected.title and next(collectionCache.uncollected.title) ~= nil
    
    if cacheExists then
        local cachedResults = {}
        local count = 0
        
        for titleID, titleData in pairs(collectionCache.uncollected.title) do
            if titleData and titleData.name then
                if searchText == "" or 
                   titleData.name:lower():find(searchText, 1, true) or
                   (titleData.achievementName and titleData.achievementName:lower():find(searchText, 1, true)) then
                    table.insert(cachedResults, titleData)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        
        -- If we have cached data, return it
        if #cachedResults > 0 then
            print("|cff9370DB[WN CollectionService]|r Returning " .. #cachedResults .. " titles from cache")
            return cachedResults
        end
    end
    
    -- NO CACHE: Trigger unified background scan (ONCE)
    print("|cffffcc00[WN CollectionService]|r Title cache empty, triggering unified scan...")
    
    -- Set PlansLoadingState for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.title then
        ns.PlansLoadingState.title = { isLoading = false, loader = nil }
    end
    
    -- Set loading state BEFORE triggering scan
    ns.PlansLoadingState.title.isLoading = true
    ns.PlansLoadingState.title.loadingProgress = 0
    ns.PlansLoadingState.title.currentStage = "Preparing..."
    
    -- Trigger unified scan in background (ONCE - ScanCollection has duplicate protection)
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("title")
        end
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end

-- ============================================================================
-- ACHIEVEMENT REWARD SCANNER
-- ============================================================================

---Scan achievement rewards and categorize them (mount, pet, toy, transmog, etc.)
---@param achievementID number Achievement ID
---@return table|nil Reward info {type, itemID, itemName, icon}
function WarbandNexus:GetAchievementRewardInfo(achievementID)
    if not achievementID then return nil end
    
    -- Use legacy API for achievement rewards (reliable across all WoW versions)
    local rewardItemID, rewardTitle
    local success, itemID, titleName = pcall(GetAchievementReward, achievementID)
    if success then
        rewardItemID = itemID
        rewardTitle = titleName
    end
    
    -- Title reward
    if rewardTitle and rewardTitle ~= "" then
        local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
        return {
            type = "title",
            title = rewardTitle,
            achievementName = name,
            achievementID = achievementID,
            icon = icon or 134400
        }
    end
    
    -- Item reward (mount, pet, toy, transmog)
    if rewardItemID then
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(rewardItemID)
        if not itemName then
            -- Item not in cache, try to load it
            local item = Item:CreateFromItemID(rewardItemID)
            if item then
                item:ContinueOnItemLoad(function()
                    return WarbandNexus:GetAchievementRewardInfo(achievementID)
                end)
            end
            return nil
        end
        
        -- Determine item type
        local rewardType = "item"
        if C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(rewardItemID) then
            rewardType = "mount"
        elseif C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetPetInfoByItemID(rewardItemID) then
            rewardType = "pet"
        elseif C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(rewardItemID) then
            rewardType = "toy"
        elseif C_TransmogCollection and C_TransmogCollection.GetItemInfo and C_TransmogCollection.GetItemInfo(rewardItemID) then
            rewardType = "transmog"
        end
        
        return {
            type = rewardType,
            itemID = rewardItemID,
            itemName = itemName,
            icon = itemIcon,
            achievementID = achievementID
        }
    end
    
    return nil
end

---Add achievement link to item description
---@param itemData table Item data {id, name, icon, ...}
---@param achievementID number Achievement ID that grants this item
---@return table Enhanced item data with achievement link
function WarbandNexus:EnhanceItemWithAchievement(itemData, achievementID)
    if not itemData or not achievementID then return itemData end
    
    local _, achievementName, _, _, _, _, _, _, _, achievementIcon = GetAchievementInfo(achievementID)
    if achievementName then
        itemData.sourceAchievement = achievementID
        itemData.sourceAchievementName = achievementName
        itemData.sourceAchievementIcon = achievementIcon
        itemData.description = (itemData.description or "") .. "\n\n|cff00ff00From Achievement:|r " .. achievementName
    end
    
    return itemData
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

--[[
    [REMOVED] TableCount moved to DataService.lua (line 3011)
    Use DataService:TableCount() instead.
]]

--[[
    [REMOVED] PrintDebug removed - Use WarbandNexus:Debug() instead
    All PrintDebug() calls have been replaced with self:Debug()
]]

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

print("|cff00ff00[WN CollectionService]|r Loaded successfully")
print("|cff9370DB[WN CollectionService]|r Features: Real-time detection + Background scanning")
print("|cff9370DB[WN CollectionService]|r Cache version: " .. CACHE_VERSION)
