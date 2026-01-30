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
local CACHE_VERSION = "3.0.0"  -- Unified cache version (incremented for illusion/title fixes)

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
        mount = {},  -- Singular to match COLLECTION_CONFIGS keys
        pet = {},
        toy = {},
        achievement = {},  -- NEW: Achievement cache
        title = {}         -- NEW: Title cache
    },
    version = CACHE_VERSION,
    lastScan = 0,
}

---Initialize collection cache from DB (load persisted data)
---Called on addon load to restore previous scan results
function WarbandNexus:InitializeCollectionCache()
    -- Initialize DB structure if needed
    if not self.db.global.collectionCache then
        self.db.global.collectionCache = {
            uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {} },
            version = CACHE_VERSION,
            lastScan = 0
        }
        print("|cff9370DB[WN CollectionService]|r Initialized empty collection cache in DB")
        return
    end
    
    -- Load from DB
    local dbCache = self.db.global.collectionCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        print("|cffffcc00[WN CollectionService]|r Cache version mismatch (DB: " .. tostring(dbCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
        self.db.global.collectionCache = {
            uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {} },
            version = CACHE_VERSION,
            lastScan = 0
        }
        return
    end
    
    -- Load uncollected cache from DB to RAM
    collectionCache.uncollected = dbCache.uncollected or { mount = {}, pet = {}, toy = {}, achievement = {}, title = {} }
    collectionCache.lastScan = dbCache.lastScan or 0
    
    -- Count loaded items
    local mountCount, petCount, toyCount, achievementCount, titleCount = 0, 0, 0, 0, 0
    for _ in pairs(collectionCache.uncollected.mount or {}) do mountCount = mountCount + 1 end
    for _ in pairs(collectionCache.uncollected.pet or {}) do petCount = petCount + 1 end
    for _ in pairs(collectionCache.uncollected.toy or {}) do toyCount = toyCount + 1 end
    for _ in pairs(collectionCache.uncollected.achievement or {}) do achievementCount = achievementCount + 1 end
    for _ in pairs(collectionCache.uncollected.title or {}) do titleCount = titleCount + 1 end
    
    print(string.format("|cff00ff00[WN CollectionService]|r Loaded cache from DB: %d mounts, %d pets, %d toys, %d achievements, %d titles", 
        mountCount, petCount, toyCount, achievementCount, titleCount))
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
        lastScan = collectionCache.lastScan
    }
    
    -- Count saved items
    local mountCount, petCount, toyCount = 0, 0, 0
    for _ in pairs(collectionCache.uncollected.mount or {}) do mountCount = mountCount + 1 end
    for _ in pairs(collectionCache.uncollected.pet or {}) do petCount = petCount + 1 end
    for _ in pairs(collectionCache.uncollected.toy or {}) do toyCount = toyCount + 1 end
    
    print(string.format("|cff00ff00[WN CollectionService]|r Saved cache to DB: %d mounts, %d pets, %d toys", 
        mountCount, petCount, toyCount))
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

---Backwards compatibility wrapper: Get uncollected mounts
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected mounts {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedMounts(searchText, limit)
    print("|cff00ccff[WN CollectionService DEBUG]|r GetUncollectedMounts called with searchText='" .. tostring(searchText) .. "', limit=" .. tostring(limit))
    
    -- Check if collectionCache exists
    if not collectionCache then
        print("|cffff0000[WN CollectionService ERROR]|r collectionCache is nil!")
        return {}
    end
    
    -- Check if uncollected table exists
    if not collectionCache.uncollected then
        print("|cffff0000[WN CollectionService ERROR]|r collectionCache.uncollected is nil!")
        return {}
    end
    
    -- Get mount cache
    local uncollected = collectionCache.uncollected["mount"]
    
    if not uncollected then
        print("|cffffcc00[WN CollectionService WARNING]|r collectionCache.uncollected['mount'] is nil! Available keys:")
        for key, _ in pairs(collectionCache.uncollected) do
            print("|cffffcc00[WN CollectionService]|r   - '" .. tostring(key) .. "'")
        end
        return {}
    end
    
    local results = {}
    local count = 0
    
    searchText = searchText and searchText:lower() or ""
    
    -- Debug: Cache size
    local cacheSize = 0
    for _ in pairs(uncollected) do cacheSize = cacheSize + 1 end
    print("|cff9370DB[WN CollectionService]|r Cache size: " .. cacheSize .. " mounts")
    
    -- Iterate and build results
    for id, data in pairs(uncollected) do
        if searchText == "" or (data.name and data.name:lower():find(searchText, 1, true)) then
            table.insert(results, data)
            count = count + 1
            if limit and count >= limit then break end
        end
    end
    
    print("|cff00ff00[WN CollectionService]|r Returning " .. count .. " results (limit: " .. tostring(limit) .. ")")
    
    -- Debug: Show first 3 results
    if count > 0 then
        for i = 1, math.min(3, count) do
            print("|cff9370DB[WN CollectionService]|r Result #" .. i .. ": " .. tostring(results[i].name) .. " (ID: " .. tostring(results[i].id) .. ")")
        end
    else
        print("|cffffcc00[WN CollectionService WARNING]|r No results found! Cache has " .. cacheSize .. " items but none matched criteria.")
    end
    
    return results
end

---Backwards compatibility wrapper: Get uncollected pets
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected pets {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedPets(searchText, limit)
    print("|cff00ccff[WN CollectionService DEBUG]|r GetUncollectedPets called with searchText='" .. tostring(searchText) .. "', limit=" .. tostring(limit))
    
    local uncollected = collectionCache.uncollected["pet"]
    
    if not uncollected then
        print("|cffffcc00[WN CollectionService WARNING]|r collectionCache.uncollected['pet'] is nil!")
        return {}
    end
    
    local results = {}
    local count = 0
    
    searchText = searchText and searchText:lower() or ""
    
    -- Debug: Cache size
    local cacheSize = 0
    for _ in pairs(uncollected) do cacheSize = cacheSize + 1 end
    print("|cff9370DB[WN CollectionService]|r Cache size: " .. cacheSize .. " pets")
    
    for id, data in pairs(uncollected) do
        if searchText == "" or (data.name and data.name:lower():find(searchText, 1, true)) then
            table.insert(results, data)
            count = count + 1
            if limit and count >= limit then break end
        end
    end
    
    print("|cff00ff00[WN CollectionService]|r Returning " .. count .. " results (limit: " .. tostring(limit) .. ")")
    
    return results
end

---Backwards compatibility wrapper: Get uncollected toys
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected toys {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedToys(searchText, limit)
    print("|cff00ccff[WN CollectionService DEBUG]|r GetUncollectedToys called with searchText='" .. tostring(searchText) .. "', limit=" .. tostring(limit))
    
    local uncollected = collectionCache.uncollected["toy"]
    
    if not uncollected then
        print("|cffffcc00[WN CollectionService WARNING]|r collectionCache.uncollected['toy'] is nil!")
        return {}
    end
    
    local results = {}
    local count = 0
    
    searchText = searchText and searchText:lower() or ""
    
    -- Debug: Cache size
    local cacheSize = 0
    for _ in pairs(uncollected) do cacheSize = cacheSize + 1 end
    print("|cff9370DB[WN CollectionService]|r Cache size: " .. cacheSize .. " toys")
    
    for id, data in pairs(uncollected) do
        if searchText == "" or (data.name and data.name:lower():find(searchText, 1, true)) then
            table.insert(results, data)
            count = count + 1
            if limit and count >= limit then break end
        end
    end
    
    print("|cff00ff00[WN CollectionService]|r Returning " .. count .. " results (limit: " .. tostring(limit) .. ")")
    
    return results
end


---Async achievement scanner (background scanning with coroutine)
---Scans all achievements and populates both achievement and title caches
function WarbandNexus:ScanAchievementsAsync()
    -- Prevent duplicate scans
    if activeCoroutines["achievements"] then
        print("|cffffcc00[WN CollectionService]|r Achievement scan already in progress")
        return
    end
    
    -- Check if scan was recent (within last 5 minutes)
    local timeSinceLastScan = GetTime() - (collectionCache.lastScan or 0)
    if timeSinceLastScan < 300 then -- 5 minutes
        print(string.format("|cffffcc00[WN CollectionService]|r Achievement scan skipped (last scan %.0f seconds ago)", timeSinceLastScan))
        return
    end
    
    print("|cff9370DB[WN CollectionService]|r Starting async achievement scan...")
    
    local startTime = GetTime()
    local totalAchievements = 0
    local totalTitles = 0
    
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
                    
                    -- Yield every 50 achievements to prevent lag
                    if totalAchievements % 50 == 0 then
                        coroutine.yield()
                    end
                end
            end
        end
        
        -- Update last scan time
        collectionCache.lastScan = GetTime()
        
        -- Save to DB
        self:SaveCollectionCache()
        
        local elapsed = GetTime() - startTime
        print(string.format("|cff00ff00[WN CollectionService]|r Achievement scan complete: %d achievements, %d titles (%.2fs)", 
            totalAchievements, totalTitles, elapsed))
        
        -- Fire event to refresh UI
        if self.Fire then
            self:Fire("WARBAND_COLLECTION_SCAN_COMPLETE", "achievement")
        end
        
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
        
        local budget = FRAME_BUDGET_MS / 1000
        local startTime = GetTime()
        
        while GetTime() - startTime < budget do
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
---Uses DB cache if available, otherwise scans from API
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected achievements {id, name, type, icon, rewards}
function WarbandNexus:GetUncollectedAchievements(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Try loading from DB cache
    if collectionCache.uncollected.achievement then
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
    
    -- NO CACHE: Scan from API (this should trigger async scan instead)
    print("|cffffcc00[WN CollectionService]|r Achievement cache empty, triggering background scan...")
    
    -- Trigger async scan in background
    C_Timer.After(0.1, function()
        self:ScanAchievementsAsync()
    end)
    
    -- Return empty for now (UI will refresh after scan completes)
    return {}
end

---Get uncollected illusions (weapon enchant appearances) with search and limit support
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected illusions {id, name, icon, sourceText, type}
function WarbandNexus:GetUncollectedIllusions(searchText, limit)
    local results = {}
    local count = 0
    searchText = (searchText or ""):lower()
    
    -- Check if illusion API is available
    if not C_TransmogCollection or not C_TransmogCollection.GetIllusions then
        return results
    end
    
    -- Get all illusions
    local illusions = C_TransmogCollection.GetIllusions()
    if not illusions then return results end
    
    -- Filter uncollected illusions
    for _, illusionInfo in ipairs(illusions) do
        if illusionInfo and not illusionInfo.isCollected then
            -- Get illusion details
            local visualID = illusionInfo.visualID
            local icon = illusionInfo.icon
            local sourceText = illusionInfo.sourceText or "Unknown source"
            
            -- DEBUG: Log ALL fields to understand API structure
            if count < 5 then
                print("|cff00ffff[WN DEBUG Illusion #" .. count .. "]|r ===== FULL API DUMP =====")
                print("  visualID:", tostring(visualID))
                print("  name:", tostring(illusionInfo.name))
                print("  spellID:", tostring(illusionInfo.spellID))
                print("  sourceText:", tostring(illusionInfo.sourceText))
                print("  icon:", tostring(icon))
                print("  isCollected:", tostring(illusionInfo.isCollected))
                
                -- Try alternate fields
                print("  itemID:", tostring(illusionInfo.itemID))
                print("  enchantID:", tostring(illusionInfo.enchantID))
                print("  hyperlink:", tostring(illusionInfo.hyperlink))
                
                -- Dump ALL fields
                for k, v in pairs(illusionInfo) do
                    if type(v) ~= "function" then
                        print("    [" .. tostring(k) .. "] = " .. tostring(v))
                    end
                end
            end
            
            -- Get illusion name with multiple fallback strategies
            local name = "Unknown Illusion"
            
            -- Strategy 1: Use illusionInfo.name if available
            if illusionInfo.name and illusionInfo.name ~= "" then
                name = illusionInfo.name
                if count < 3 then
                    print("|cff00ff00[WN DEBUG]|r Strategy 1 SUCCESS: name =", name)
                end
            -- Strategy 2: Try spell name from spellID
            elseif illusionInfo.spellID and illusionInfo.spellID > 0 then
                local success, spellName = pcall(GetSpellInfo, illusionInfo.spellID)
                if success and spellName and spellName ~= "" then
                    name = spellName
                    if count < 3 then
                        print("|cff00ff00[WN DEBUG]|r Strategy 2 SUCCESS: spellName =", name)
                    end
                elseif count < 3 then
                    print("|cffff0000[WN DEBUG]|r Strategy 2 FAILED: spellID =", illusionInfo.spellID)
                end
            -- Strategy 3: Try to get source item name (last resort)
            elseif visualID then
                -- Use visualID as fallback name
                name = "Illusion #" .. tostring(visualID)
                if count < 3 then
                    print("|cffffcc00[WN DEBUG]|r Strategy 3 FALLBACK: using visualID")
                end
            end
            
            if searchText == "" or name:lower():find(searchText, 1, true) then
                table.insert(results, {
                    id = visualID,
                    name = name,
                    icon = icon,
                    sourceText = sourceText,
                    type = "illusion",
                    spellID = illusionInfo.spellID
                })
                count = count + 1
                if limit and count >= limit then break end
            end
        end
    end
    
    print("|cff9370DB[WN CollectionService]|r GetUncollectedIllusions: Found " .. count .. " uncollected illusions")
    
    return results
end

---Get uncollected titles with search and limit support
---Uses DB cache if available, otherwise scans from API
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected titles {id, name, type}
---NOTE: Titles are achievement-based, limited to known title-granting achievements
function WarbandNexus:GetUncollectedTitles(searchText, limit)
    searchText = (searchText or ""):lower()
    
    -- CACHE-FIRST: Try loading from DB cache
    if collectionCache.uncollected.title then
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
    
    -- NO CACHE: Scan from API (trigger async scan)
    print("|cffffcc00[WN CollectionService]|r Title cache empty, triggering background scan...")
    
    -- Trigger async scan (will also populate achievements)
    C_Timer.After(0.1, function()
        self:ScanAchievementsAsync()
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
