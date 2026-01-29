--[[
    Warband Nexus - Unified Collection Service
    
    Combines functionality from:
    - CollectionManager.lua: Real-time collection detection
    - CollectionScanner.lua: Background scanning for Browse UI
    
    Provides:
    1. Real-time detection when mounts/pets/toys are obtained
    2. Background async scanning for Browse UI (uncollected items)
    3. Single unified cache for both use cases
    4. Event-driven notifications
    
    Events fired:
    - WARBAND_COLLECTIBLE_OBTAINED: Real-time detection
    - WARBAND_COLLECTION_SCAN_COMPLETE: Background scan finished
    - WARBAND_COLLECTION_SCAN_PROGRESS: Scan progress updates
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local FRAME_BUDGET_MS = 5      -- 5ms per frame for background scanning
local BATCH_SIZE = 10          -- Yield every 10 items
local CACHE_VERSION = "2.0.0"  -- Unified cache version

-- ============================================================================
-- COLLECTION CACHE
-- ============================================================================
--[[
    Unified cache for both real-time and background scanning:
    - owned: {mountID/speciesID/itemID -> true} - O(1) lookups
    - uncollected: {type -> {id -> {name, icon, source...}}} - Browse UI data
]]

local collectionCache = {
    owned = {
        mounts = {},
        pets = {},
        toys = {}
    },
    uncollected = {
        mounts = {},
        pets = {},
        toys = {}
    },
    version = CACHE_VERSION,
    lastScan = 0,
}

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
    -- PET (classID 17 - Battle Pets)
    -- ========================================
    if classID == 17 then
        if not C_PetJournal then return nil end
        
        local speciesID = nil
        
        -- Try API first
        if C_PetJournal.GetPetInfoByItemID then
            speciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        end
        
        -- Extract from hyperlink for caged pets
        if not speciesID and hyperlink then
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
    -- COMPANION PETS (classID 15, subclass 2)
    -- ========================================
    if classID == 15 and subclassID == 2 then
        if not C_PetJournal then return nil end
        
        local speciesID = C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetPetInfoByItemID(itemID)
        if not speciesID then return nil end
        
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
}

---Scan a collection type asynchronously (coroutine-based)
---@param collectionType string "mount", "pet", or "toy"
---@param onProgress function|nil Progress callback (current, total, itemData)
---@param onComplete function|nil Completion callback (results)
function WarbandNexus:ScanCollection(collectionType, onProgress, onComplete)
    print("|cff9370DB[WN CollectionService]|r Starting background scan: " .. tostring(collectionType))
    local config = COLLECTION_CONFIGS[collectionType]
    if not config then
        print("|cffff4444[WN CollectionService ERROR]|r Invalid collection type: " .. tostring(collectionType))
        return
    end
    
    -- Create coroutine for async scanning
    local co = coroutine.create(function()
        local startTime = debugprofilestop()
        local results = {}
        local items = config.iterator()
        local total = #items
        
        for i, item in ipairs(items) do
            -- Extract item data
            local data = config.extract(item)
            
            -- Apply filters
            if data and config.shouldInclude(data) then
                results[data.id] = data
            end
            
            -- Progress callback
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
        
        local elapsed = debugprofilestop() - startTime
        local uncollectedCount = 0
        for _ in pairs(results) do uncollectedCount = uncollectedCount + 1 end
        print(string.format("|cff00ff00[WN CollectionService]|r Scan complete: %s - %d total, %d uncollected, %.2fms",
            config.name, total, uncollectedCount, elapsed))
        
        -- Completion callback
        if onComplete then
            onComplete(results)
        end
        
        -- Fire event
        self:SendMessage(ns.Events.COLLECTION_SCAN_COMPLETE, collectionType, results)
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
            self:PrintDebug("CollectionService: Scan error - " .. tostring(err))
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

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Count table entries
---@param tbl table
---@return number
function WarbandNexus:TableCount(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

---Debug print helper
---@param message string
function WarbandNexus:PrintDebug(message)
    if self.db and self.db.profile and self.db.profile.debugMode then
        print("|cff9370DB[WN Debug]|r " .. message)
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

print("|cff00ff00[WN CollectionService]|r Loaded successfully")
print("|cff9370DB[WN CollectionService]|r Features: Real-time detection + Background scanning")
print("|cff9370DB[WN CollectionService]|r Cache version: " .. CACHE_VERSION)
