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

-- Debug print helper (only prints if debug mode + debugVerbose enabled; reduces BAG SCAN spam)
local function DebugPrint(...)
    if not (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode) then return end
    if not WarbandNexus.db.profile.debugVerbose then return end
    _G.print(...)  -- Use global print to avoid recursion
end

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

-- MERKEZİ KAYNAK: Tüm collection verileri tek yapıda. Collections (full) ve Plans (uncollected) aynı kaynaktan okur.
-- API sadece veri yoksa veya versiyon güncellemesinde devreye girer.
local collectionStore = {
    version = CACHE_VERSION,
    lastBuilt = 0,
    mount = {},
    pet = {},
    toy = {},
    achievement = {},
    title = {},
    illusion = {},
}

-- collectionData = collectionStore alias (GetAllMountsData vb. collectionData kullanıyor)
local collectionData = collectionStore

-- collectionCache: deprecated; GetUncollected* artık collectionStore'dan filtreler. ScanCollection hâlâ uncollected yazıyor (geçiş).
local collectionCache = {
    owned = { mounts = {}, pets = {}, toys = {} },
    uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, transmog = {}, illusion = {} },
    completed = { achievement = {} },
    lastScan = 0,
    lastAchievementScan = 0,
}

-- Forward declaration: defined later (BACKGROUND SCANNING section); used by BuildFullCollectionData.
local COLLECTION_CONFIGS

-- Global loading state (accessible from UI modules like PlansUI)
ns.CollectionLoadingState = {
    isLoading = false,
    loadingProgress = 0,  -- 0-100
    currentStage = nil,   -- "Mounts", "Pets", "Toys", "Achievements", etc.
    currentCategory = nil,
    totalItems = 0,
    scannedItems = 0,
}

-- Session-only RAM cache for collection metadata (icon, source, description). Cleared on tab leave / reload.
local METADATA_CACHE_MAX = 512
local metadataCache = {}
local metadataCacheOrder = {}   -- Circular buffer
local metadataCacheHead = 1     -- Circular buffer head index

-- ============================================================================
-- DUPLICATE NOTIFICATION PREVENTION (BAG SCAN + COLLECTION EVENTS)
-- ============================================================================
--[[
    Two-layer dedup architecture:
    
    LAYER 1 — Persistent DB (bagDetectedCollectibles):
      Keyed by type_id, 2-hour expiry. Survives /reload.
      Prevents duplicate when bag scan fires BEFORE Blizzard collection event.
    
    LAYER 2 — Session ring buffer (recentNotifications):
      Keyed by string (type_id OR itemName), configurable cooldown per entry.
      O(1) eviction via circular buffer (no O(n) oldest-search).
      Merges the old recentlyNotified (5s, by id) + recentNotificationsByName (2s, by name)
      + bagDetectedPetNames (60s, by name) into a single bounded structure.
]]

---Track previously seen items in bags to detect NEW items
local previousBagContents = {}
local isInitialized = false  -- Track if we've done initial scan

-- ============================================================================
-- RING BUFFER: O(1) bounded dedup cache
-- ============================================================================
-- Fixed-size circular array. When full, the oldest entry is evicted automatically.
-- Supports time-based cooldown checks via the stored timestamp.

---Create a new ring buffer with the given capacity
---@param capacity number Maximum entries before eviction
---@return table ringBuffer
local function CreateRingBuffer(capacity)
    return {
        entries = {},       -- [slot] = { key, timestamp, cooldown }
        lookup = {},        -- [key] = slot (for O(1) existence check)
        capacity = capacity,
        head = 1,           -- Next write position (1-indexed, wraps)
        size = 0,           -- Current number of valid entries
    }
end

---Check if a key exists in the ring buffer and is within its cooldown
---@param rb table Ring buffer
---@param key string Lookup key
---@return boolean isActive True if key was recently added and cooldown hasn't expired
local function RingBufferCheck(rb, key)
    local slot = rb.lookup[key]
    if not slot then return false end
    
    local entry = rb.entries[slot]
    if not entry or entry.key ~= key then
        -- Slot was overwritten by a newer entry; stale lookup
        rb.lookup[key] = nil
        return false
    end
    
    local elapsed = GetTime() - entry.timestamp
    if elapsed < entry.cooldown then
        return true
    end
    
    -- Expired
    return false
end

---Add or refresh a key in the ring buffer
---@param rb table Ring buffer
---@param key string Lookup key
---@param cooldown number Cooldown in seconds
local function RingBufferAdd(rb, key, cooldown)
    -- If key already exists and is in a valid slot, update in-place
    local existingSlot = rb.lookup[key]
    if existingSlot then
        local entry = rb.entries[existingSlot]
        if entry and entry.key == key then
            entry.timestamp = GetTime()
            entry.cooldown = cooldown
            return
        end
        -- Stale lookup, will be overwritten below
    end
    
    -- Evict oldest entry at head position if buffer is full
    local slot = rb.head
    local old = rb.entries[slot]
    if old then
        rb.lookup[old.key] = nil  -- Remove old entry's lookup
    end
    
    -- Write new entry
    rb.entries[slot] = { key = key, timestamp = GetTime(), cooldown = cooldown }
    rb.lookup[key] = slot
    
    -- Advance head
    rb.head = (slot % rb.capacity) + 1
    if rb.size < rb.capacity then
        rb.size = rb.size + 1
    end
end

-- Unified session dedup buffer (replaces 3 separate tables + O(n) cleanups)
-- Capacity 64: more than enough for rapid loot events without memory growth
local recentNotifications = CreateRingBuffer(64)

-- Cooldown constants
local NOTIFICATION_COOLDOWN = 5    -- By type_id: 5 seconds
local NAME_DEBOUNCE_COOLDOWN = 2   -- By item name: 2 seconds
local BAG_PET_NAME_COOLDOWN = 60   -- Pet name fallback: 60 seconds

-- ============================================================================
-- LAYER 0: Persistent DB (notifiedCollectibles) — permanent dedup
-- ============================================================================
-- Records every collectible that was successfully notified. Prevents
-- duplicate notifications across sessions (e.g. WoW re-fires NEW_TOY_ADDED
-- on login for already-owned toys). Keys: "type_id" → true.

---Initialize notifiedCollectibles DB (persistent across reloads)
local function InitializeNotifiedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not WarbandNexus.db.global.notifiedCollectibles then
        WarbandNexus.db.global.notifiedCollectibles = {}
    end
end

---Check if a collectible was already notified in a previous session
---@param collectibleType string "mount", "pet", "toy"
---@param collectibleID number Collectible ID
---@return boolean wasNotified
local function WasAlreadyNotified(collectibleType, collectibleID)
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.notifiedCollectibles then
        return false
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    return WarbandNexus.db.global.notifiedCollectibles[key] == true
end

---Mark a collectible as notified (persistent, survives reload/logout)
---@param collectibleType string "mount", "pet", "toy"
---@param collectibleID number Collectible ID
local function MarkAsPermanentlyNotified(collectibleType, collectibleID)
    InitializeNotifiedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.notifiedCollectibles then
        return
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    WarbandNexus.db.global.notifiedCollectibles[key] = true
end

-- ============================================================================
-- LAYER 1: Persistent DB (bagDetectedCollectibles) — unchanged semantics
-- ============================================================================

---Initialize bag-detected collectibles DB (persistent across reloads)
local function InitializeBagDetectedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not WarbandNexus.db.global.bagDetectedCollectibles then
        WarbandNexus.db.global.bagDetectedCollectibles = {}
    end
end

local BAG_DETECTED_EXPIRY = 7200  -- 2 hours

---Check if collectible was detected in bag scan (time-limited, 2 hour expiry)
---@param collectibleType string Type: "mount", "pet", "toy"
---@param collectibleID number Collectible ID
---@return boolean wasDetected
local function WasDetectedInBag(collectibleType, collectibleID)
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.bagDetectedCollectibles then
        return false
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    local detectedAt = WarbandNexus.db.global.bagDetectedCollectibles[key]
    -- Legacy support: `true` (boolean) from old code → treat as expired
    if detectedAt == true then
        WarbandNexus.db.global.bagDetectedCollectibles[key] = nil
        return false
    end
    if type(detectedAt) == "number" then
        if (time() - detectedAt) < BAG_DETECTED_EXPIRY then
            return true
        end
        WarbandNexus.db.global.bagDetectedCollectibles[key] = nil
    end
    return false
end

---Mark collectible as detected in bag (session-persistent with timestamp)
---@param collectibleType string Type: "mount", "pet", "toy"
---@param collectibleID number Collectible ID
local function MarkAsDetectedInBag(collectibleType, collectibleID)
    InitializeBagDetectedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.bagDetectedCollectibles then
        return
    end
    local key = collectibleType .. "_" .. tostring(collectibleID)
    WarbandNexus.db.global.bagDetectedCollectibles[key] = time()
    DebugPrint(string.format("|cff00ffff[WN DeDupe]|r Marked %s %s as BAG-DETECTED", collectibleType, collectibleID))
end

-- ============================================================================
-- LAYER 2: Session ring buffer — O(1) dedup for all short-term checks
-- ============================================================================

---Check if an item name was recently shown (2s debounce)
---@param itemName string The item/collectible name
---@return boolean
local function WasRecentlyShownByName(itemName)
    if not itemName then return false end
    local blocked = RingBufferCheck(recentNotifications, "name:" .. itemName)
    if blocked then
        DebugPrint(string.format("|cffff8800[WN NameDebounce]|r '%s' → BLOCKED (quick debounce)", itemName))
    end
    return blocked
end

---Mark item name as recently shown (2s debounce)
---@param itemName string
local function MarkAsShownByName(itemName)
    if not itemName then return end
    RingBufferAdd(recentNotifications, "name:" .. itemName, NAME_DEBOUNCE_COOLDOWN)
end

---Check if collectible was recently notified by ID (5s cooldown)
---@param collectibleType string
---@param collectibleID number
---@return boolean
local function WasRecentlyNotified(collectibleType, collectibleID)
    local key = "id:" .. collectibleType .. "_" .. tostring(collectibleID)
    local blocked = RingBufferCheck(recentNotifications, key)
    if blocked then
        DebugPrint(string.format("|cff888888[WN DeDupe]|r %s %s → BLOCKED (id cooldown)", collectibleType, collectibleID))
    end
    return blocked
end

---Mark collectible as notified by ID (5s cooldown)
---@param collectibleType string
---@param collectibleID number
local function MarkAsNotified(collectibleType, collectibleID)
    RingBufferAdd(recentNotifications, "id:" .. collectibleType .. "_" .. tostring(collectibleID), NOTIFICATION_COOLDOWN)
end

-- ============================================================================
-- COLLECTION CACHE INITIALIZATION
-- ============================================================================

---Initialize collection cache from DB (load persisted data)
---Called on addon load to restore previous scan results
function WarbandNexus:InitializeCollectionCache()
    local debugMode = self.db and self.db.profile and self.db.profile.debugMode
    
    if debugMode then
    DebugPrint("|cff9370DB[WN CollectionService]|r InitializeCollectionCache called")
    end
    
    -- CRITICAL: Ensure DB is initialized
    if not self.db or not self.db.global then
        if debugMode then
    DebugPrint("|cffff0000[WN CollectionService]|r ERROR: DB not initialized yet!")
        end
        -- Retry after 1 second
        C_Timer.After(1, function()
            if self and self.InitializeCollectionCache then
                self:InitializeCollectionCache()
            end
        end)
        return
    end
    
    local defaultUncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, transmog = {}, illusion = {} }

    if not self.db.global.collectionCache then
        self.db.global.collectionCache = {
            uncollected = defaultUncollected,
            version = CACHE_VERSION,
            lastScan = time()
        }
        if debugMode then
    DebugPrint("|cffffcc00[WN CollectionService]|r Initialized NEW collection cache (empty)")
        end
        return
    end

    local dbCache = self.db.global.collectionCache

    if dbCache.version ~= CACHE_VERSION then
        if debugMode then
    DebugPrint("|cffffcc00[WN CollectionService]|r Cache version mismatch (DB: " .. tostring(dbCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
        end
        self.db.global.collectionCache = {
            uncollected = defaultUncollected,
            version = CACHE_VERSION,
            lastScan = time()
        }
        return
    end

    collectionCache.uncollected = dbCache.uncollected or defaultUncollected
    collectionCache.completed = dbCache.completed or { achievement = {} }
    if not collectionCache.completed.achievement then
        collectionCache.completed.achievement = {}
    end
    collectionCache.lastScan = dbCache.lastScan or 0
    collectionCache.lastAchievementScan = dbCache.lastAchievementScan or 0

    -- MERKEZİ KAYNAK: collectionStore yükle veya eski DB'den migrate et
    local dbStore = self.db.global.collectionStore
    if dbStore and dbStore.version == CACHE_VERSION then
        collectionStore.mount = dbStore.mount or {}
        collectionStore.pet = dbStore.pet or {}
        local rawToy = dbStore.toy or {}
        collectionStore.toy = {}
        for id, v in pairs(rawToy) do
            if v and v.id then
                collectionStore.toy[id] = { id = v.id, name = (type(v.name) == "string" and v.name ~= "") and v.name or tostring(v.id) }
            end
        end
        collectionStore.achievement = dbStore.achievement or {}
        collectionStore.title = dbStore.title or {}
        collectionStore.illusion = dbStore.illusion or {}
        collectionStore.lastBuilt = dbStore.lastBuilt or 0
        if debugMode then
            local m, p, t, a, ti, il = 0, 0, 0, 0, 0, 0
            for _ in pairs(collectionStore.mount) do m = m + 1 end
            for _ in pairs(collectionStore.pet) do p = p + 1 end
            for _ in pairs(collectionStore.toy) do t = t + 1 end
            for _ in pairs(collectionStore.achievement) do a = a + 1 end
            for _ in pairs(collectionStore.title) do ti = ti + 1 end
            for _ in pairs(collectionStore.illusion) do il = il + 1 end
            DebugPrint(string.format("|cff00ff00[WN CollectionService]|r Loaded collectionStore: %d mounts, %d pets, %d toys, %d achievements, %d titles, %d illusions", m, p, t, a, ti, il))
        end
    else
        -- Migration: collectionData + collectionCache → collectionStore
        if self.db.global.collectionData and self.db.global.collectionData.version == CACHE_VERSION then
            local cd = self.db.global.collectionData
            collectionStore.mount = cd.mount or {}
            collectionStore.pet = cd.pet or {}
            local rawToy = cd.toy or {}
            collectionStore.toy = {}
            for id, v in pairs(rawToy) do
                if v and v.id then
                    collectionStore.toy[id] = { id = v.id, name = (type(v.name) == "string" and v.name ~= "") and v.name or tostring(v.id) }
                end
            end
            collectionStore.lastBuilt = cd.lastBuilt or 0
        end
        -- collectionCache.completed.achievement → collectionStore.achievement (merge)
        if collectionCache.completed and collectionCache.completed.achievement then
            for id, ach in pairs(collectionCache.completed.achievement) do
                if ach and not collectionStore.achievement[id] then
                    collectionStore.achievement[id] = ach
                    if collectionStore.achievement[id].collected == nil then
                        collectionStore.achievement[id].collected = true
                    end
                end
            end
        end
        -- collectionCache.uncollected → collectionStore (id->name → id->{id,name,collected=false}; toy: id+name only)
        for ctype, tbl in pairs(collectionCache.uncollected or {}) do
            if type(tbl) == "table" and (ctype == "mount" or ctype == "pet" or ctype == "toy" or ctype == "achievement" or ctype == "title" or ctype == "illusion") then
                local store = collectionStore[ctype]
                if store then
                    for id, name in pairs(tbl) do
                        if not store[id] then
                            local nameStr = (type(name) == "string") and name or ("ID:" .. tostring(id))
                            if ctype == "toy" then
                                store[id] = { id = id, name = nameStr }
                            else
                                store[id] = { id = id, name = nameStr, collected = false }
                            end
                        end
                    end
                end
            end
        end
        if debugMode then
            DebugPrint("|cffffcc00[WN CollectionService]|r Migrated collectionData/cache → collectionStore")
        end
    end

    -- Count loaded items (debug mode only)
    if debugMode then
        local mountCount, petCount, toyCount, achievementCount, titleCount, illusionCount = 0, 0, 0, 0, 0, 0
        for _ in pairs(collectionCache.uncollected.mount or {}) do mountCount = mountCount + 1 end
        for _ in pairs(collectionCache.uncollected.pet or {}) do petCount = petCount + 1 end
        for _ in pairs(collectionCache.uncollected.toy or {}) do toyCount = toyCount + 1 end
        for _ in pairs(collectionCache.uncollected.achievement or {}) do achievementCount = achievementCount + 1 end
        for _ in pairs(collectionCache.uncollected.title or {}) do titleCount = titleCount + 1 end
        for _ in pairs(collectionCache.uncollected.illusion or {}) do illusionCount = illusionCount + 1 end
        
        if achievementCount == 0 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Achievement cache is EMPTY (scan will be triggered on first view)")
        end
        
    DebugPrint(string.format("|cff00ff00[WN CollectionService]|r Loaded cache from DB: %d mounts, %d pets, %d toys, %d achievements, %d titles, %d illusions", 
            mountCount, petCount, toyCount, achievementCount, titleCount, illusionCount))
    end
    
    -- Initialize bag-detected collectibles DB (for duplicate prevention)
    InitializeBagDetectedDB()
end

---Save collection store to DB (merkezi kaynak — Collections + Plans aynı veriden okur)
---Called after scan completion and real-time updates
function WarbandNexus:SaveCollectionStore()
    if not self.db or not self.db.global then return end
    collectionStore.version = CACHE_VERSION
    collectionStore.lastBuilt = collectionStore.lastBuilt or time()
    local toySave = {}
    for id, v in pairs(collectionStore.toy or {}) do
        if v and v.id then
            toySave[id] = { id = v.id, name = (type(v.name) == "string" and v.name ~= "") and v.name or tostring(v.id) }
        end
    end
    self.db.global.collectionStore = {
        version = collectionStore.version,
        lastBuilt = collectionStore.lastBuilt,
        mount = collectionStore.mount,
        pet = collectionStore.pet,
        toy = toySave,
        achievement = collectionStore.achievement,
        title = collectionStore.title,
        illusion = collectionStore.illusion,
    }
    DebugPrint("|cff00ff00[WN CollectionService]|r Saved collectionStore to DB")
end

---Save collection cache to DB (legacy — syncs collectionCache for backward compat; also saves collectionStore)
---Called after scan completion to avoid re-scanning on reload
function WarbandNexus:SaveCollectionCache()
    if not self.db or not self.db.global then
    DebugPrint("|cffff0000[WN CollectionService ERROR]|r Cannot save cache: DB not initialized")
        return
    end

    self.db.global.collectionCache = {
        uncollected = collectionCache.uncollected,
        completed = collectionCache.completed or { achievement = {} },
        version = CACHE_VERSION,
        lastScan = collectionCache.lastScan,
        lastAchievementScan = collectionCache.lastAchievementScan or collectionCache.lastScan,
    }

    self:SaveCollectionStore()
end

---Invalidate collection cache (mark for refresh)
---Called when collection data changes (e.g., new mount obtained)
---@param category string|nil Optional category to invalidate ("mount","pet","toy","achievement","title","illusion"). nil = mount/pet/toy only (safe default).
function WarbandNexus:InvalidateCollectionCache(category)
    if category then
        if category == "mount" or category == "pet" or category == "toy" then
            local key = category .. "s"
            if collectionCache.owned[key] then collectionCache.owned[key] = {} end
            if collectionCache.uncollected[category] then collectionCache.uncollected[category] = {} end
        elseif collectionCache.uncollected[category] then
            collectionCache.uncollected[category] = {}
        end
        if category == "achievement" then
            collectionCache.lastAchievementScan = 0
        else
            collectionCache.lastScan = 0
        end
        DebugPrint("|cffffcc00[WN CollectionService]|r Collection cache invalidated: " .. category)
    else
        collectionCache.owned.mounts = {}
        collectionCache.owned.pets = {}
        collectionCache.owned.toys = {}
        if collectionCache.uncollected.mount then collectionCache.uncollected.mount = {} end
        if collectionCache.uncollected.pet then collectionCache.uncollected.pet = {} end
        if collectionCache.uncollected.toy then collectionCache.uncollected.toy = {} end
        collectionCache.lastScan = 0
        DebugPrint("|cffffcc00[WN CollectionService]|r Collection cache invalidated: mount/pet/toy (will refresh on next scan)")
    end
end

---Save full collection data to DB (legacy — artık SaveCollectionStore kullan)
function WarbandNexus:SaveCollectionData()
    self:SaveCollectionStore()
end

-- ============================================================================
-- BLIZZARD_COLLECTIONS LOADER (required for full API data) — must be before BuildFullCollectionData
-- ============================================================================
local blizzardCollectionsLoaded = false
local function EnsureBlizzardCollectionsLoaded()
    if blizzardCollectionsLoaded then return end
    if InCombatLockdown() then return end
    blizzardCollectionsLoaded = true
    local function SafeLoadAddOn(addonName)
        local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addonName)
        if isLoaded then return end
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, addonName)
        elseif LoadAddOn then
            pcall(LoadAddOn, addonName)
        end
    end
    SafeLoadAddOn("Blizzard_Collections")
    DebugPrint("|cff00ff00[WN CollectionService]|r Ensured Blizzard_Collections is loaded for API data")
end
ns.EnsureBlizzardCollectionsLoaded = EnsureBlizzardCollectionsLoaded

---Build full collection data (all mounts, pets, toys with id, name, icon, source, description).
---Runs on login when DB has no data or version changed. Stores result in collectionStore and DB.
---@param onComplete function|nil Callback when done (used by EnsureCollectionData)
function WarbandNexus:BuildFullCollectionData(onComplete)
    EnsureBlizzardCollectionsLoaded()
    local LT = ns.LoadingTracker
    if LT and not onComplete then
        LT:Register("collection_data", (ns.L and ns.L["LT_COLLECTION_DATA"]) or "Collection Data")
    end

    ns.CollectionLoadingState.isLoading = true
    ns.CollectionLoadingState.loadingProgress = 0
    ns.CollectionLoadingState.currentStage = (ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections..."
    ns.CollectionLoadingState.currentCategory = "mount"

    local _issecretvalue = issecretvalue
    local BUDGET_MS = 6
    local configs = { "mount", "pet", "toy" }
    local configIdx = 1
    local itemIdx = 1
    local items = {}
    local currentType = nil
    local config = nil

    local function nextBatch()
        if configIdx > #configs then
            ns.CollectionLoadingState.loadingProgress = 99
            collectionStore.lastBuilt = time()
            self:SaveCollectionStore()
            if onComplete then
                onComplete()
            else
                ns.CollectionLoadingState.isLoading = false
                ns.CollectionLoadingState.loadingProgress = 100
                ns.CollectionLoadingState.currentStage = (ns.L and ns.L["SYNC_COMPLETE"]) or "Complete"
                if LT then LT:Complete("collection_data") end
                if Constants and Constants.EVENTS then
                    self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = "all" })
                end
            end
            DebugPrint("|cff00ff00[WN CollectionService]|r Full collection data built and saved")
            return
        end
        currentType = configs[configIdx]
        config = COLLECTION_CONFIGS[currentType]
        if not config then
            configIdx = configIdx + 1
            C_Timer.After(0, nextBatch)
            return
        end
        if configIdx == 1 and itemIdx == 1 then
            items = config.iterator()
        elseif itemIdx == 1 then
            items = config.iterator()
        end

        local stageName = (currentType == "mount" and ((ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts"))
            or (currentType == "pet" and ((ns.L and ns.L["CATEGORY_PETS"]) or "Pets"))
            or (currentType == "toy" and ((ns.L and ns.L["CATEGORY_TOYS"]) or "Toys"))
            or currentType
        ns.CollectionLoadingState.currentStage = stageName
        ns.CollectionLoadingState.currentCategory = currentType

        local batchStart = debugprofilestop()
        while itemIdx <= #items do
            local id = items[itemIdx]
            local ok, data = pcall(config.extract, id)
            if ok and data and data.id then
                if currentType == "mount" then
                    collectionData.mount[data.id] = data
                elseif currentType == "pet" then
                    collectionData.pet[data.id] = data
                elseif currentType == "toy" then
                    collectionData.toy[data.id] = { id = data.id, name = data.name }
                end
            end
            itemIdx = itemIdx + 1
            if itemIdx % 50 == 0 or itemIdx == #items then
                local progress = #items > 0 and math.floor(((configIdx - 1) * 100 / #configs) + (itemIdx / #items) * (100 / #configs)) or 0
                ns.CollectionLoadingState.loadingProgress = math.min(99, progress)
            end
            if debugprofilestop() - batchStart > BUDGET_MS then
                C_Timer.After(0, nextBatch)
                return
            end
        end
        configIdx = configIdx + 1
        itemIdx = 1
        C_Timer.After(0, nextBatch)
    end

    nextBatch()
end

---Ensure collection data is populated. Core-level init — versiyon değişti veya veri yoksa tam scan.
---Plans/Collections sekmelerinden tetiklenmez; sadece init.
---@param onComplete function|nil Callback when all scans finish
function WarbandNexus:EnsureCollectionData(onComplete)
    if not self.db or not self.db.global then
        if onComplete then onComplete() end
        return
    end

    local dbStore = self.db.global.collectionStore
    local versionOk = dbStore and dbStore.version == CACHE_VERSION
    local hasMounts = collectionStore.mount and next(collectionStore.mount) ~= nil
    local hasPets = collectionStore.pet and next(collectionStore.pet) ~= nil
    local hasToys = collectionStore.toy and next(collectionStore.toy) ~= nil
    local hasAchievements = collectionStore.achievement and next(collectionStore.achievement) ~= nil
    local hasTitles = collectionStore.title and next(collectionStore.title) ~= nil
    local hasIllusions = collectionStore.illusion and next(collectionStore.illusion) ~= nil

    -- Sanity check: if toy store count is far below ToyBox total, force a rebuild
    if hasToys and C_ToyBox and C_ToyBox.GetNumToys then
        local apiTotal = C_ToyBox.GetNumToys() or 0
        if apiTotal and apiTotal > 0 then
            local storeCount = 0
            for _ in pairs(collectionStore.toy) do
                storeCount = storeCount + 1
            end
            -- If we have less than half of the toys in store, consider it stale
            if storeCount < (apiTotal * 0.5) then
                DebugPrint(string.format("|cffffcc00[WN CollectionService]|r Toy store size (%d) << ToyBox total (%d) — forcing full rebuild", storeCount, apiTotal))
                hasMounts = false   -- trigger BuildFullCollectionData (mount/pet/toy) below
                hasPets = false
                hasToys = false
            end
        end
    end

    if versionOk and hasMounts and hasPets and hasToys and hasAchievements and hasTitles and hasIllusions then
        if onComplete then onComplete() end
        return
    end

    local LT = ns.LoadingTracker
    if LT then
        LT:Register("collection_data", (ns.L and ns.L["LT_COLLECTION_DATA"]) or "Collection Data")
    end

    ns.CollectionLoadingState.isLoading = true
    ns.CollectionLoadingState.loadingProgress = 0
    ns.CollectionLoadingState.currentStage = (ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections..."

    EnsureBlizzardCollectionsLoaded()

    local queue = {}
    -- BuildFullCollectionData handles mount+pet+toy together; trigger when any of them is missing/stale
    if not hasMounts or not hasPets or not hasToys then
        queue[#queue + 1] = "build"  -- BuildFullCollectionData (mounts, pets, toys)
    end
    if not hasAchievements then
        queue[#queue + 1] = "achievement"
    end
    if not (collectionStore.title and next(collectionStore.title)) then
        queue[#queue + 1] = "title"
    end
    if not (collectionStore.illusion and next(collectionStore.illusion)) then
        queue[#queue + 1] = "illusion"
    end

    if #queue == 0 then
        ns.CollectionLoadingState.isLoading = false
        ns.CollectionLoadingState.loadingProgress = 100
        if LT then LT:Complete("collection_data") end
        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = "all" })
        end
        if onComplete then onComplete() end
        return
    end

    local idx = 1
    local function RunNext()
        if idx > #queue then
            ns.CollectionLoadingState.isLoading = false
            ns.CollectionLoadingState.loadingProgress = 100
            if LT then LT:Complete("collection_data") end
            self:SaveCollectionStore()
            if Constants and Constants.EVENTS then
                self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = "all" })
            end
            if onComplete then onComplete() end
            return
        end

        local step = queue[idx]
        idx = idx + 1
        local progress = ((idx - 2) / #queue) * 100

        if step == "build" then
            ns.CollectionLoadingState.currentStage = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts"
            self:BuildFullCollectionData(function()
                ns.CollectionLoadingState.loadingProgress = math.min(99, (idx - 1) / #queue * 100)
                C_Timer.After(0.2, RunNext)
            end)
        elseif step == "achievement" then
            ns.CollectionLoadingState.currentStage = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements"
            local msgName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_COMPLETE) or "WN_COLLECTION_SCAN_COMPLETE"
            local handler
            handler = function(_, data)
                if data and data.category == "achievement" then
                    self:UnregisterMessage(msgName, handler)
                    ns.CollectionLoadingState.loadingProgress = math.min(99, (idx - 1) / #queue * 100)
                    C_Timer.After(0.2, RunNext)
                end
            end
            self:RegisterMessage(msgName, handler)
            self:ScanAchievementsAsync()
            return
        elseif step == "title" or step == "illusion" then
            ns.CollectionLoadingState.currentStage = step == "title" and ((ns.L and ns.L["CATEGORY_TITLES"]) or "Titles") or ((ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions")
            self:ScanCollection(step, nil, function()
                ns.CollectionLoadingState.loadingProgress = math.min(99, (idx - 1) / #queue * 100)
                C_Timer.After(0.2, RunNext)
            end)
        end
    end

    RunNext()
end

---Legacy: EnsureFullCollectionData — artık EnsureCollectionData kullan
function WarbandNexus:EnsureFullCollectionData()
    self:EnsureCollectionData()
end

---Get single mount record from global collection data (id, name, icon, source, description, creatureDisplayID, collected).
---@param mountID number
---@return table|nil
function WarbandNexus:GetMountData(mountID)
    if not mountID or not collectionData.mount then return nil end
    return collectionData.mount[mountID]
end

---Get all mount records from global collection data for UI (search uses name; list uses id).
---@return table[] Array of { id, name, icon, source, description, creatureDisplayID, collected }
function WarbandNexus:GetAllMountsData()
    if not collectionData.mount then return {} end
    local out = {}
    for id, d in pairs(collectionData.mount) do
        if d and d.id then
            out[#out + 1] = d
        end
    end
    return out
end

---Get all pet records from global collection data for UI (search uses name; list uses speciesID).
---@return table[] Array of { id, name, icon, source, description, creatureDisplayID, collected }
function WarbandNexus:GetAllPetsData()
    if not collectionData.pet then return {} end
    local out = {}
    for id, d in pairs(collectionData.pet) do
        if d and d.id then
            out[#out + 1] = d
        end
    end
    return out
end

---Get all toy records from store (id, name only in DB). Adds collected from API for compatibility.
---@return table[] Array of { id, name, collected }
function WarbandNexus:GetAllToysData()
    if not collectionStore.toy then return {} end
    local out = {}
    for id, d in pairs(collectionStore.toy) do
        if d and d.id then
            local collected = false
            if PlayerHasToy then
                local raw = PlayerHasToy(d.id)
                if issecretvalue and raw and issecretvalue(raw) then collected = true else collected = raw == true end
            end
            out[#out + 1] = { id = d.id, name = d.name or tostring(d.id), collected = collected }
        end
    end
    return out
end

-- ============================================================================
-- TOY: C_ToyBox source type only. Categories = Blizzard Sources (Drop, Quest, Vendor, ...).
-- ============================================================================
local TOY_SOURCE_TYPE_MAX = 32
-- Blizzard Toy Box Filter > Sources order (fallback when TOY_SOURCE_TYPE_N globals missing or SOURCE_TYPE_OTHER)
local TOY_SOURCE_TYPE_NAMES = {
    [1] = "Drop",
    [2] = "Quest",
    [3] = "Vendor",
    [4] = "Profession",
    [5] = "Pet Battle",
    [6] = "Achievement",
    [7] = "World Event",
    [8] = "Promotion",
    [9] = "In-Game Shop",
    [10] = "Discovery",
    [11] = "Trading Post",
}

---Category label for Blizzard source type index. Prefer game globals/locale; else use Sources filter names (Drop, Quest, Vendor, ...).
function WarbandNexus:GetToySourceTypeName(sourceIndex)
    if not sourceIndex or type(sourceIndex) ~= "number" or sourceIndex < 1 then return "" end
    local key = "TOY_SOURCE_TYPE_" .. sourceIndex
    local L = ns.L
    if L and L[key] and L[key] ~= key and L[key] ~= "SOURCE_TYPE_OTHER" then return L[key] end
    local g = _G[key]
    if type(g) == "string" and g ~= "" and g ~= "SOURCE_TYPE_OTHER" then return g end
    return TOY_SOURCE_TYPE_NAMES[sourceIndex] or ("Category " .. sourceIndex)
end

function WarbandNexus:GetToySourceTypeCount()
    if not C_ToyBox then return 0 end
    EnsureBlizzardCollectionsLoaded()
    if C_ToyBox.GetNumSourceTypeFilters and type(C_ToyBox.GetNumSourceTypeFilters) == "function" then
        local ok, n = pcall(C_ToyBox.GetNumSourceTypeFilters)
        if ok and type(n) == "number" and n >= 1 then return n end
    end
    return math.min(24, TOY_SOURCE_TYPE_MAX)
end

---Group toys by C_ToyBox source type filter. Saves/restores filter state.
function WarbandNexus:GetToysGroupedBySourceType()
    local grouped = {}
    local itemIDToSource = {}
    if not C_ToyBox then return grouped, itemIDToSource end
    EnsureBlizzardCollectionsLoaded()
    if InCombatLockdown() then return grouped, itemIDToSource end
    local origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
    local origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
    local origFilterString = C_ToyBox.GetFilterString and C_ToyBox.GetFilterString() or ""
    local origSourceFilters = {}
    local count = self:GetToySourceTypeCount()
    for i = 1, count do
        if C_ToyBox.IsSourceTypeFilterChecked then
            local ok, checked = pcall(C_ToyBox.IsSourceTypeFilterChecked, i)
            if ok and checked ~= nil then origSourceFilters[i] = checked end
        end
    end
    pcall(function()
        C_ToyBox.SetCollectedShown(true)
        C_ToyBox.SetUncollectedShown(true)
        C_ToyBox.SetFilterString("")
        for sourceIndex = 1, count do
            C_ToyBox.SetAllSourceTypeFilters(false)
            C_ToyBox.SetSourceTypeFilter(sourceIndex, true)
            if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
            local numFiltered = (C_ToyBox.GetNumFilteredToys and C_ToyBox.GetNumFilteredToys()) or 0
            if issecretvalue and numFiltered and issecretvalue(numFiltered) then numFiltered = 0 end
            local itemIDs = {}
            for j = 1, numFiltered do
                local itemID = C_ToyBox.GetToyFromIndex(j)
                if itemID and itemID > 0 and not (issecretvalue and issecretvalue(itemID)) then
                    if not itemIDToSource[itemID] then
                        itemIDToSource[itemID] = sourceIndex
                        itemIDs[#itemIDs + 1] = itemID
                    end
                end
            end
            grouped[sourceIndex] = { name = self:GetToySourceTypeName(sourceIndex), itemIDs = itemIDs }
        end
        C_ToyBox.SetAllSourceTypeFilters(true)
        if origCollected ~= nil then C_ToyBox.SetCollectedShown(origCollected) end
        if origUncollected ~= nil then C_ToyBox.SetUncollectedShown(origUncollected) end
        if origFilterString then C_ToyBox.SetFilterString(origFilterString) end
        for i, checked in pairs(origSourceFilters) do
            if C_ToyBox.SetSourceTypeFilter then C_ToyBox.SetSourceTypeFilter(i, checked) end
        end
        if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
    end)
    return grouped, itemIDToSource
end

---Single source of truth for toy source line: C_ToyBox source type name (Drop, Quest, Vendor, ...). Used by Collections and Plans.
---Caches itemID->sourceIndex from GetToysGroupedBySourceType so repeated lookups are cheap.
function WarbandNexus:GetToySourceTypeNameForItem(itemID)
    if not itemID then return nil end
    if not ns._toyItemIDToSourceIndexCache then ns._toyItemIDToSourceIndexCache = {} end
    local cache = ns._toyItemIDToSourceIndexCache
    if not cache.map then
        local _, itemIDToSource = self:GetToysGroupedBySourceType()
        cache.map = itemIDToSource or {}
    end
    local idx = cache.map[itemID]
    if not idx then return nil end
    return self:GetToySourceTypeName(idx)
end

---Flat list of all toys for UI (no categories). Returns array of { id, name, icon, collected } sorted by name.
function WarbandNexus:GetToysFlatList()
    local out = {}
    if not C_ToyBox or not C_ToyBox.GetToyInfo then return out end
    EnsureBlizzardCollectionsLoaded()
    if InCombatLockdown() then return out end
    local origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
    local origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
    local origFilterString = C_ToyBox.GetFilterString and C_ToyBox.GetFilterString() or ""
    pcall(function()
        C_ToyBox.SetCollectedShown(true)
        C_ToyBox.SetUncollectedShown(true)
        C_ToyBox.SetAllSourceTypeFilters(true)
        C_ToyBox.SetFilterString("")
        if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
        local numToys = (C_ToyBox.GetNumFilteredToys and C_ToyBox.GetNumFilteredToys()) or (C_ToyBox.GetNumToys and C_ToyBox.GetNumToys()) or 0
        if issecretvalue and numToys and issecretvalue(numToys) then numToys = 0 end
        for i = 1, numToys do
            local itemID = C_ToyBox.GetToyFromIndex(i)
            if itemID and itemID > 0 and not (issecretvalue and issecretvalue(itemID)) then
                local _, toyName, icon = C_ToyBox.GetToyInfo(itemID)
                if issecretvalue and toyName and issecretvalue(toyName) then toyName = nil end
                local name = (toyName and toyName ~= "") and toyName or tostring(itemID)
                if not icon and (C_Item and C_Item.GetItemInfo) then
                    local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(itemID)
                    if tex then icon = tex end
                end
                local collected = false
                if PlayerHasToy then
                    local raw = PlayerHasToy(itemID)
                    if issecretvalue and raw and issecretvalue(raw) then collected = true else collected = raw == true end
                end
                out[#out + 1] = { id = itemID, name = name, icon = icon, collected = collected, isCollected = collected }
            end
        end
        if origCollected ~= nil then C_ToyBox.SetCollectedShown(origCollected) end
        if origUncollected ~= nil then C_ToyBox.SetUncollectedShown(origUncollected) end
        if origFilterString then C_ToyBox.SetFilterString(origFilterString) end
        if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
    end)
    table.sort(out, function(a, b) return (a.name or "") < (b.name or "") end)
    return out
end

---Toys grouped by Blizzard source type for UI. Each item: id, name, icon, collected. DB stores only id+name.
function WarbandNexus:GetToysDataGroupedBySourceType()
    EnsureBlizzardCollectionsLoaded()
    local grouped = self:GetToysGroupedBySourceType()
    local result = {}
    if not C_ToyBox or not C_ToyBox.GetToyInfo then return result end
    local _issecretvalue = issecretvalue
    local store = collectionStore.toy
    for sourceIndex, group in pairs(grouped) do
        if group and group.itemIDs and #group.itemIDs > 0 then
            local items = {}
            for i = 1, #group.itemIDs do
                local itemID = group.itemIDs[i]
                local _, toyName, icon = C_ToyBox.GetToyInfo(itemID)
                if _issecretvalue and toyName and _issecretvalue(toyName) then toyName = nil end
                local name = (toyName and toyName ~= "") and toyName or nil
                if not name and store and store[itemID] and (store[itemID].name or "") ~= "" then
                    name = store[itemID].name
                end
                if (not name or name == "") and C_Item and C_Item.GetItemInfo then
                    local itemName = C_Item.GetItemInfo(itemID)
                    if itemName and type(itemName) == "string" and itemName ~= "" then
                        if not _issecretvalue or not _issecretvalue(itemName) then name = itemName end
                    end
                end
                if not name or name == "" then name = tostring(itemID) end
                if not icon and (C_Item and C_Item.GetItemInfo) then
                    local _, _, _, _, _, _, _, _, _, tex = C_Item.GetItemInfo(itemID)
                    if tex then icon = tex end
                end
                local collected = false
                if PlayerHasToy then
                    local raw = PlayerHasToy(itemID)
                    if _issecretvalue and raw and _issecretvalue(raw) then collected = true
                    else collected = raw == true end
                end
                items[#items + 1] = {
                    id = itemID,
                    name = name,
                    icon = icon,
                    collected = collected,
                    isCollected = collected,
                    sourceTypeIndex = sourceIndex,
                    sourceTypeName = group.name,
                }
            end
            table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
            result[sourceIndex] = { name = group.name, items = items }
        end
    end
    return result
end

---Tooltip lines for selected toy (detail panel description only). Source comes from source type, not tooltip.
---Returns { name, icon, lines = string[], isCollected }. Call TooltipUtil.SurfaceArgs before reading lines.
function WarbandNexus:GetToyTooltipForDisplay(itemID)
    if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
    local _, name, icon = C_ToyBox.GetToyInfo(itemID)
    if issecretvalue and name and issecretvalue(name) then name = nil end
    if not name then name = "" end
    if not icon and (C_Item and C_Item.GetItemInfo) then
        local _, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
        if itemTexture then icon = itemTexture end
    end
    local isCollected = false
    if PlayerHasToy then
        local raw = PlayerHasToy(itemID)
        if issecretvalue and raw and issecretvalue(raw) then isCollected = true
        else isCollected = raw == true end
    end
    local tooltipData = nil
    if C_TooltipInfo then
        local ok1, r1 = pcall(C_TooltipInfo.GetToyByItemID, itemID)
        if ok1 and r1 and r1.lines and #r1.lines > 0 then tooltipData = r1 end
        if (not tooltipData or not tooltipData.lines or #tooltipData.lines == 0) and C_TooltipInfo.GetItemByID then
            local ok2, r2 = pcall(C_TooltipInfo.GetItemByID, itemID)
            if ok2 and r2 and r2.lines and #r2.lines > 0 then tooltipData = r2 end
        end
    end
    if tooltipData and tooltipData.lines and TooltipUtil and TooltipUtil.SurfaceArgs then
        pcall(TooltipUtil.SurfaceArgs, tooltipData)
    end
    local _issecretvalue = issecretvalue
    local function safeText(t)
        if not t or type(t) ~= "string" then return nil end
        if _issecretvalue and _issecretvalue(t) then return nil end
        return t
    end
    local function strip(s)
        if not s or type(s) ~= "string" then return "" end
        return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|T.-|t", "")
    end
    local fallback1 = (ns.L and ns.L["FALLBACK_TOY_COLLECTION"]) or "Toy Collection"
    local fallback2 = (ns.L and ns.L["FALLBACK_TOY_BOX"]) or "Toy Box"
    local fallback3 = (ns.L and ns.L["FALLBACK_WARBAND_TOY"]) or "Warband Toy"
    local function skipLine(lineStr)
        if not lineStr or lineStr == "" then return true end
        local t = (lineStr:gsub("^%s+", ""):gsub("%s+$", ""))
        if t == "" or t == fallback1 or t == fallback2 or t == fallback3 then return true end
        return false
    end
    local lines = {}
    if tooltipData and tooltipData.lines then
        for i = 1, #tooltipData.lines do
            local line = tooltipData.lines[i]
            if line then
                local left = safeText(line.leftText)
                local right = safeText(line.rightText)
                local lineText = (left and left ~= "" and left) or (right and right ~= "" and right) or nil
                if lineText then
                    local cleaned = strip(lineText):gsub("^%s+", ""):gsub("%s+$", "")
                    if not skipLine(cleaned) then lines[#lines + 1] = cleaned end
                end
            end
        end
    end
    return { name = name, icon = icon, lines = lines, isCollected = isCollected }
end

-- Canonical collection counts from Blizzard API only (single source for Statistics + Collections).
-- Cache invalidated on WN_COLLECTION_UPDATED / WN_COLLECTIBLE_OBTAINED so both tabs show same numbers.
local _collectionCountsAPICache = nil
local COLLECTION_COUNTS_API_TTL = 60

---Return cached or freshly computed collection counts from Blizzard API only.
---Single source of truth for Statistics and Collections (e.g. mount total 1577 in both).
---@return table { mounts = { collected, total }, pets = { collected, totalSpecies, uniqueSpecies, journalEntries }, toys = { collected, total }, achievementPoints = number }
function WarbandNexus:GetCollectionCountsFromAPI()
    local now = GetTime()
    if _collectionCountsAPICache and (now - _collectionCountsAPICache.timestamp) < COLLECTION_COUNTS_API_TTL then
        return _collectionCountsAPICache.data
    end

    local data = {
        mounts = { collected = 0, total = 0 },
        pets = { collected = 0, totalSpecies = 0, uniqueSpecies = 0, journalEntries = 0 },
        toys = { collected = 0, total = 0 },
        achievementPoints = 0,
    }

    if GetTotalAchievementPoints then
        data.achievementPoints = GetTotalAchievementPoints() or 0
    end

    if C_MountJournal and C_MountJournal.GetMountIDs then
        local mountIDs = C_MountJournal.GetMountIDs()
        if mountIDs then
            data.mounts.total = #mountIDs
            for i = 1, #mountIDs do
                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountIDs[i])
                if issecretvalue and isCollected and issecretvalue(isCollected) then
                    -- treat secret as collected for count
                elseif isCollected == true then
                    data.mounts.collected = data.mounts.collected + 1
                end
            end
        end
    end

    if C_PetJournal then
        if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
        local numJournalEntries, numCollectedPets = 0, 0
        if C_PetJournal.GetNumPets then
            numJournalEntries, numCollectedPets = C_PetJournal.GetNumPets()
            if issecretvalue and numJournalEntries and issecretvalue(numJournalEntries) then numJournalEntries = 0 end
            if issecretvalue and numCollectedPets and issecretvalue(numCollectedPets) then numCollectedPets = 0 end
        end
        data.pets.journalEntries = numJournalEntries or 0
        data.pets.collected = numCollectedPets or 0
        local numUniqueSpecies = 0
        local numTotalSpecies = 0
        if C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetPetInfoTableByPetID then
            local ownedPetIDs = C_PetJournal.GetOwnedPetIDs()
            if ownedPetIDs then
                data.pets.collected = #ownedPetIDs
                local ownedSpecies = {}
                for j = 1, #ownedPetIDs do
                    local info = C_PetJournal.GetPetInfoTableByPetID(ownedPetIDs[j])
                    if info and info.speciesID then
                        ownedSpecies[info.speciesID] = true
                    end
                end
                for _ in pairs(ownedSpecies) do
                    numUniqueSpecies = numUniqueSpecies + 1
                end
            end
        end
        data.pets.uniqueSpecies = numUniqueSpecies
        if C_PetJournal.GetPetInfoByIndex then
            local allSpecies = {}
            for i = 1, numJournalEntries do
                local petID, speciesID = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID then
                    allSpecies[speciesID] = true
                end
            end
            for _ in pairs(allSpecies) do
                numTotalSpecies = numTotalSpecies + 1
            end
            data.pets.totalSpecies = numTotalSpecies
        else
            data.pets.totalSpecies = numJournalEntries
        end
    end

    if C_ToyBox then
        -- Total: filter-independent (GetNumToys). Collected: GetToyFromIndex is filter-dependent, so set "show all" before iterating.
        local numToys = C_ToyBox.GetNumToys() or (C_ToyBox.GetNumTotalDisplayedToys() or 0)
        data.toys.total = numToys
        local collected = 0
        if PlayerHasToy and numToys and numToys > 0 then
            local origCollected, origUncollected, origFilterString
            if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
            if not InCombatLockdown() then
                origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
                origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
                origFilterString = C_ToyBox.GetFilterString and C_ToyBox.GetFilterString() or ""
                pcall(function()
                    C_ToyBox.SetCollectedShown(true)
                    C_ToyBox.SetUncollectedShown(true)
                    if C_ToyBox.SetAllSourceTypeFilters then C_ToyBox.SetAllSourceTypeFilters(true) end
                    if C_ToyBox.SetFilterString then C_ToyBox.SetFilterString("") end
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            for i = 1, numToys do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and (PlayerHasToy(itemID) == true or (issecretvalue and PlayerHasToy(itemID) and issecretvalue(PlayerHasToy(itemID)))) then
                    collected = collected + 1
                end
            end
            if not InCombatLockdown() and (origCollected ~= nil or origUncollected ~= nil or origFilterString) then
                pcall(function()
                    if origCollected ~= nil and C_ToyBox.SetCollectedShown then C_ToyBox.SetCollectedShown(origCollected) end
                    if origUncollected ~= nil and C_ToyBox.SetUncollectedShown then C_ToyBox.SetUncollectedShown(origUncollected) end
                    if origFilterString and C_ToyBox.SetFilterString then C_ToyBox.SetFilterString(origFilterString) end
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
        end
        data.toys.collected = collected
    end

    _collectionCountsAPICache = { timestamp = now, data = data }
    return data
end

---Invalidate the API counts cache so next GetCollectionCountsFromAPI() recomputes (e.g. after collection change).
function WarbandNexus:InvalidateCollectionCountsAPICache()
    _collectionCountsAPICache = nil
end

---Get all achievements (complete + incomplete) for Collections UI. Uses cache from ScanAchievementsAsync.
---@return table[] Array of { id, name, icon, points, description, categoryID, collected }
function WarbandNexus:GetAllAchievementsData()
    local uncollected = self:GetUncollectedAchievements("", 999999) or {}
    local completed = self:GetCompletedAchievements("", 999999) or {}
    local seen = {}
    local out = {}
    for i = 1, #uncollected do
        local a = uncollected[i]
        if a and a.id and not seen[a.id] then
            seen[a.id] = true
            a.collected = false
            a.isCollected = false
            out[#out + 1] = a
        end
    end
    for i = 1, #completed do
        local a = completed[i]
        if a and a.id and not seen[a.id] then
            seen[a.id] = true
            a.collected = true
            a.isCollected = true
            out[#out + 1] = a
        end
    end
    return out
end

---Remove collectible from uncollected cache (incremental update when player obtains it)
---This is called by event handlers when player collects a new mount/pet/toy
---@param collectionType string "mount", "pet", or "toy"
---@param id number mountID, speciesID, or itemID
function WarbandNexus:RemoveFromUncollected(collectionType, id)
    local uncollected = collectionCache.uncollected[collectionType]
    local entry = uncollected and uncollected[id]
    local itemName = (type(entry) == "string") and entry or (entry and entry.name) or (ns.L and ns.L["UNKNOWN"]) or "Unknown"

    if entry ~= nil then
        collectionCache.uncollected[collectionType][id] = nil
    end

    -- Merkezi kaynak: collectionStore güncelle (collected=true)
    local store = collectionStore[collectionType]
    local didUpdate = false
    if store then
        if not store[id] then
            store[id] = { id = id, name = itemName, collected = true }
            didUpdate = true
        elseif store[id].collected ~= true then
            store[id].collected = true
            didUpdate = true
        end
    end

    -- Update owned cache
    if collectionType == "mount" or collectionType == "pet" or collectionType == "toy" then
        local key = collectionType .. "s"
        if not collectionCache.owned[key] then
            collectionCache.owned[key] = {}
        end
        collectionCache.owned[key][id] = true
    end

    if didUpdate and store then
        self:SaveCollectionStore()
        DebugPrint(string.format("|cff00ff00[WN CollectionService]|r INCREMENTAL UPDATE: %s marked collected in %ss",
                itemName, collectionType))
    end
end

-- Active coroutines for async scanning
local activeCoroutines = {}

-- ============================================================================
-- ASYNC SCAN ABORT PROTOCOL (for tab switches)
-- ============================================================================

---Abort all active collection scans (called when switching away from Plans tab)
function WarbandNexus:AbortCollectionScans()
    local abortCount = 0
    for collectionType, co in pairs(activeCoroutines) do
        if co and coroutine.status(co) ~= "dead" then
            -- Coroutines can't be forcibly killed in Lua, but we can mark them as aborted
            -- The scan loop will check and exit gracefully
            activeCoroutines[collectionType] = nil
            abortCount = abortCount + 1
        end
    end
    
    if abortCount > 0 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Aborted " .. abortCount .. " active scans (tab switch)")
    end
end

-- ============================================================================
-- NOTIFICATION SEEDING (must be defined before BuildCollectionCache)
-- ============================================================================

---One-time seed: mark all currently owned collectibles as notified.
---Runs once per account (when notifiedCollectibles DB is first created).
---Prevents false "You got it on your first try!" for already-owned items
---after addon update introduces the persistent dedup layer.
local function SeedNotifiedFromOwned()
    InitializeNotifiedDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local db = WarbandNexus.db.global.notifiedCollectibles
    if not db then return end
    
    -- Only seed once: if DB already has entries, skip
    if db._seeded then return end
    
    local count = 0
    for mountID in pairs(collectionCache.owned.mounts) do
        local key = "mount_" .. tostring(mountID)
        if not db[key] then db[key] = true; count = count + 1 end
    end
    for speciesID in pairs(collectionCache.owned.pets) do
        local key = "pet_" .. tostring(speciesID)
        if not db[key] then db[key] = true; count = count + 1 end
    end
    for itemID in pairs(collectionCache.owned.toys) do
        local key = "toy_" .. tostring(itemID)
        if not db[key] then db[key] = true; count = count + 1 end
    end
    
    db._seeded = true
    DebugPrint(string.format("|cff00ccff[WN CollectionService]|r Seeded notifiedCollectibles: %d entries from owned cache", count))
end

-- ============================================================================
-- REAL-TIME CACHE BUILDING (Fast O(1) Lookup)
-- ============================================================================

---Build or refresh owned collection cache
---Uses time-budgeted batching: each phase (mounts/pets/toys) yields to the next
---frame when the 4ms budget is exceeded, preventing single-frame spikes.
function WarbandNexus:BuildCollectionCache()
    local _issecretvalue = issecretvalue
    local BUDGET_MS = 4
    local P = ns.Profiler
    if P then P:StartAsync("BuildCollectionCache") end
    local LT = ns.LoadingTracker
    if LT then LT:Register("collections", (ns.L and ns.L["LT_COLLECTIONS"]) or "Collections") end
    
    collectionCache.owned = {
        mounts = {},
        pets = {},
        toys = {}
    }
    
    -- Pre-declare all phase functions for forward references
    local MountBatch, StartPetPhase, PetBatch, StartToyPhase, ToyBatch
    
    -- ── Phase 1: Mounts (time-budgeted) ──
    local mountIDs
    local ok1, err1 = pcall(function()
        if C_MountJournal and C_MountJournal.GetMountIDs then
            mountIDs = C_MountJournal.GetMountIDs()
        end
    end)
    if not ok1 then
        DebugPrint("|cffff4444[WN CollectionService ERROR]|r Mount cache init failed: " .. tostring(err1))
    end
    
    local mountIdx = 1
    MountBatch = function()
        if not mountIDs then StartPetPhase() return end
        local batchStart = debugprofilestop()
        local ok, err = pcall(function()
            while mountIdx <= #mountIDs do
                local mountID = mountIDs[mountIdx]
                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                if _issecretvalue and isCollected and _issecretvalue(isCollected) then
                    -- skip
                elseif isCollected then
                    collectionCache.owned.mounts[mountID] = true
                end
                mountIdx = mountIdx + 1
                if debugprofilestop() - batchStart > BUDGET_MS then
                    C_Timer.After(0, MountBatch)
                    return
                end
            end
            StartPetPhase()
        end)
        if not ok then
            DebugPrint("|cffff4444[WN CollectionService ERROR]|r Mount batch failed: " .. tostring(err))
            StartPetPhase()
        end
    end
    
    -- ── Phase 2: Pets (time-budgeted) ──
    local petIdx = 1
    local numPets = 0
    StartPetPhase = function()
        local ok, err = pcall(function()
            if C_PetJournal and C_PetJournal.GetNumPets then
                numPets = C_PetJournal.GetNumPets() or 0
                if _issecretvalue and numPets and _issecretvalue(numPets) then
                    numPets = 0
                end
            end
        end)
        if not ok then
            DebugPrint("|cffff4444[WN CollectionService ERROR]|r Pet init failed: " .. tostring(err))
        end
        C_Timer.After(0, PetBatch)
    end
    
    PetBatch = function()
        local ok, err = pcall(function()
            local batchStart = debugprofilestop()
            while petIdx <= numPets do
                local petID, speciesID, owned = C_PetJournal.GetPetInfoByIndex(petIdx)
                local speciesSecret = _issecretvalue and speciesID and _issecretvalue(speciesID)
                local ownedSecret = _issecretvalue and owned and _issecretvalue(owned)
                if not speciesSecret and not ownedSecret and speciesID and owned then
                    collectionCache.owned.pets[speciesID] = true
                end
                petIdx = petIdx + 1
                if debugprofilestop() - batchStart > BUDGET_MS then
                    C_Timer.After(0, PetBatch)
                    return
                end
            end
            StartToyPhase()
        end)
        if not ok then
            DebugPrint("|cffff4444[WN CollectionService ERROR]|r Pet batch failed: " .. tostring(err))
            StartToyPhase()
        end
    end
    
    -- ── Phase 3: Toys (time-budgeted) ──
    local toyIdx = 1
    local numToys = 0
    StartToyPhase = function()
        local ok, err = pcall(function()
            if C_ToyBox and C_ToyBox.GetNumToys then
                numToys = C_ToyBox.GetNumToys() or 0
                if _issecretvalue and numToys and _issecretvalue(numToys) then
                    numToys = 0
                end
            end
        end)
        if not ok then
            DebugPrint("|cffff4444[WN CollectionService ERROR]|r Toy init failed: " .. tostring(err))
        end
        C_Timer.After(0, ToyBatch)
    end
    
    ToyBatch = function()
        local ok, err = pcall(function()
            local batchStart = debugprofilestop()
            while toyIdx <= numToys do
                local itemID = C_ToyBox.GetToyFromIndex(toyIdx)
                if itemID and not (_issecretvalue and _issecretvalue(itemID)) then
                    local hasToy = PlayerHasToy and PlayerHasToy(itemID)
                    if hasToy and not (_issecretvalue and _issecretvalue(hasToy)) then
                        collectionCache.owned.toys[itemID] = true
                    end
                end
                toyIdx = toyIdx + 1
                if debugprofilestop() - batchStart > BUDGET_MS then
                    C_Timer.After(0, ToyBatch)
                    return
                end
            end
            if P then P:StopAsync("BuildCollectionCache") end
            if LT then LT:Complete("collections") end
            SeedNotifiedFromOwned()
        end)
        if not ok then
            DebugPrint("|cffff4444[WN CollectionService ERROR]|r Toy batch failed: " .. tostring(err))
            if P then P:StopAsync("BuildCollectionCache") end
            if LT then LT:Complete("collections") end
        end
    end
    
    MountBatch()
end

---Check if player owns a collectible
---@param collectibleType string "mount", "pet", or "toy"
---@param id number mountID, speciesID, or itemID
---@return boolean owned
function WarbandNexus:IsCollectibleOwned(collectibleType, id)
    -- Cache uses plural keys (mounts/pets/toys), callers pass singular (mount/pet/toy)
    local key = collectibleType and (collectibleType .. "s") or nil
    if not key then return false end

    if not collectionCache.owned[key] then
        self:BuildCollectionCache()
    end

    local cache = collectionCache.owned[key]
    return cache and cache[id] == true
end

-- ============================================================================
-- REAL-TIME EVENT HANDLERS (NEW_MOUNT_ADDED, NEW_PET_ADDED, NEW_TOY_ADDED)
-- ============================================================================

---Handle NEW_MOUNT_ADDED event
---Fires when player learns a new mount
---@param mountID number The mount ID
---@param retryCount number|nil Internal retry counter
function WarbandNexus:OnNewMount(event, mountID, retryCount)
    if not mountID then return end
    retryCount = retryCount or 0

    local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
    if issecretvalue then
        if name and issecretvalue(name) then name = nil end
        if icon and issecretvalue(icon) then icon = nil end
    end
    if not name then
        if retryCount < 3 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewMount: Data not ready for mountID=" .. mountID .. ", retry " .. (retryCount + 1) .. "/3")
            C_Timer.After(0.5, function()
                self:OnNewMount(event, mountID, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewMount: Data unavailable after 3 retries for mountID=" .. mountID)
        end
        return
    end

    -- ALWAYS update collected status in store (data correctness must not depend on notification dedup)
    collectionCache.owned.mounts[mountID] = true
    self:RemoveFromUncollected("mount", mountID)

    if not collectionStore.mount then collectionStore.mount = {} end
    local m = collectionStore.mount[mountID]
    local storeChanged = false
    if not m then
        local sourceText = ""
        if C_MountJournal.GetMountInfoExtraByID then
            local _, description, src = C_MountJournal.GetMountInfoExtraByID(mountID)
            if src and not (issecretvalue and issecretvalue(src)) then sourceText = src end
        end
        collectionStore.mount[mountID] = {
            id = mountID, name = name, icon = icon, source = sourceText, description = "",
            creatureDisplayID = nil, collected = true,
        }
        storeChanged = true
    elseif m.collected ~= true then
        m.collected = true
        storeChanged = true
    end
    if storeChanged then
        self:SaveCollectionStore()
    end

    -- Dedup layers only gate NOTIFICATIONS — data update above always runs
    local isRepeatable = WarbandNexus.IsRepeatableCollectible and WarbandNexus:IsRepeatableCollectible("mount", mountID)
    local skipNotification = false
    if not isRepeatable and WasAlreadyNotified("mount", mountID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: mount " .. mountID .. " (already notified)")
    elseif WasRecentlyShownByName(name) then
        skipNotification = true
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
    elseif WasDetectedInBag("mount", mountID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: mount " .. name .. " (detected in bag before, permanent block)")
    elseif WasRecentlyNotified("mount", mountID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: mount " .. name .. " (notified within 5s)")
    end

    if not skipNotification then
        MarkAsNotified("mount", mountID)
        MarkAsShownByName(name)
        MarkAsPermanentlyNotified("mount", mountID)

        self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
            type = "mount",
            id = mountID,
            name = name,
            icon = icon
        })
    end

    -- Always fire data-update event so UI refreshes (even when notification is deduped)
    self:InvalidateCollectionCache("mount")
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "mount")
    end

    DebugPrint("|cff00ff00[WN CollectionService]|r NEW MOUNT: " .. name .. (skipNotification and " (notification deduped)" or ""))
end

---Handle NEW_PET_ADDED event
---Fires when player learns a new battle pet
---@param petGUID string The pet GUID (e.g., "BattlePet-0-000013DED8E1")
---@param retryCount number|nil Internal retry counter
function WarbandNexus:OnNewPet(event, petGUID, retryCount)
    if not petGUID then return end
    retryCount = retryCount or 0

    local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon = C_PetJournal.GetPetInfoByPetID(petGUID)
    if issecretvalue then
        if speciesID and issecretvalue(speciesID) then speciesID = nil end
        if name and issecretvalue(name) then name = nil end
        if icon and issecretvalue(icon) then icon = nil end
    end

    if not speciesID or not name then
        -- Pet journal may not be ready immediately when NEW_PET_ADDED fires; retry with backoff (up to 5 tries, 0.8s apart)
        if retryCount < 5 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewPet: Data not ready for petGUID=" .. tostring(petGUID) .. ", retry " .. (retryCount + 1) .. "/5")
            C_Timer.After(0.8, function()
                self:OnNewPet(event, petGUID, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewPet: Data unavailable after 5 retries for petGUID=" .. tostring(petGUID))
        end
        return
    end

    -- ALWAYS update collected status in store (data correctness must not depend on notification dedup)
    collectionCache.owned.pets[speciesID] = true
    self:RemoveFromUncollected("pet", speciesID)

    if not collectionStore.pet then collectionStore.pet = {} end
    local p = collectionStore.pet[speciesID]
    local storeChanged = false
    if not p then
        local sourceText = ""
        if C_PetJournal.GetPetInfoBySpeciesID then
            local _, _, _, _, src = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            if src and not (issecretvalue and issecretvalue(src)) then sourceText = src end
        end
        collectionStore.pet[speciesID] = {
            id = speciesID, name = name, icon = icon, source = sourceText, description = "",
            creatureDisplayID = displayID, collected = true,
        }
        storeChanged = true
    elseif p.collected ~= true then
        p.collected = true
        storeChanged = true
    end
    if storeChanged then
        self:SaveCollectionStore()
    end

    -- Dedup layers only gate NOTIFICATIONS — data update above always runs
    local isRepeatable = WarbandNexus.IsRepeatableCollectible and WarbandNexus:IsRepeatableCollectible("pet", speciesID)
    local skipNotification = false

    -- Duplicate pet species (2/3, 3/3 etc.) — skip notification but data is already updated
    local numOwned, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
    if issecretvalue and numOwned and issecretvalue(numOwned) then numOwned = nil end
    if numOwned and numOwned > 1 then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r SKIP: " .. name .. " (" .. numOwned .. "/" .. (limit or 3) .. " owned) - not first acquisition")
    elseif not isRepeatable and WasAlreadyNotified("pet", speciesID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: pet " .. name .. " (already notified)")
    elseif WasRecentlyShownByName(name) then
        skipNotification = true
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
    elseif WasDetectedInBag("pet", speciesID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. name .. " (detected in bag before, permanent block)")
    elseif RingBufferCheck(recentNotifications, "petname:" .. name) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. name .. " (item-based bag detection)")
    elseif WasRecentlyNotified("pet", speciesID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. name .. " (notified within 5s)")
    end

    if not skipNotification then
        MarkAsNotified("pet", speciesID)
        MarkAsShownByName(name)
        MarkAsPermanentlyNotified("pet", speciesID)

        self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
            type = "pet",
            id = speciesID,
            name = name,
            icon = icon
        })
    end

    -- Always fire data-update event so UI refreshes (even when notification is deduped)
    self:InvalidateCollectionCache("pet")
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "pet")
    end

    DebugPrint("|cff00ff00[WN CollectionService]|r NEW PET: " .. name .. " (speciesID: " .. speciesID .. ")" .. (skipNotification and " (notification deduped)" or ""))
end

---Handle NEW_TOY_ADDED event
---Fires when player learns a new toy
---@param itemID number The toy item ID
---@param _isFavorite any WoW payload (ignored)
---@param _retryCount number|nil Internal retry counter (only set by self-retry)
function WarbandNexus:OnNewToy(event, itemID, _isFavorite, _retryCount)
    if not itemID then return end
    local retryCount = (type(_retryCount) == "number") and _retryCount or 0

    local success, name = pcall(GetItemInfo, itemID)
    if not success or not name then
        if retryCount < 3 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewToy: Data not ready for itemID=" .. itemID .. ", retry " .. (retryCount + 1) .. "/3")
            C_Timer.After(0.5, function()
                self:OnNewToy(event, itemID, nil, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewToy: Data unavailable after 3 retries for itemID=" .. itemID)
        end
        return
    end

    local icon = GetItemIcon(itemID)

    -- ALWAYS update collected status in store (data correctness must not depend on notification dedup)
    collectionCache.owned.toys[itemID] = true
    self:RemoveFromUncollected("toy", itemID)

    if not collectionStore.toy then collectionStore.toy = {} end
    local t = collectionStore.toy[itemID]
    if not t then
        collectionStore.toy[itemID] = { id = itemID, name = name }
        self:SaveCollectionStore()
    end

    -- Dedup layers only gate NOTIFICATIONS — data update above always runs
    local isRepeatable = WarbandNexus.IsRepeatableCollectible and WarbandNexus:IsRepeatableCollectible("toy", itemID)
    local skipNotification = false
    if not isRepeatable and WasAlreadyNotified("toy", itemID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: toy " .. itemID .. " (already notified)")
    elseif WasDetectedInBag("toy", itemID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: toy " .. name .. " (detected in bag before, permanent block)")
    elseif WasRecentlyNotified("toy", itemID) then
        skipNotification = true
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: toy " .. name .. " (notified within 5s)")
    elseif WasRecentlyShownByName(name) then
        skipNotification = true
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
    end

    if not skipNotification then
        MarkAsNotified("toy", itemID)
        MarkAsShownByName(name)
        MarkAsPermanentlyNotified("toy", itemID)

        self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
            type = "toy",
            id = itemID,
            name = name,
            icon = icon
        })
    end

    -- Always fire data-update event so UI refreshes (even when notification is deduped)
    self:InvalidateCollectionCache("toy")
    if ns._toyItemIDToSourceIndexCache then ns._toyItemIDToSourceIndexCache.map = nil end
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "toy")
    end

    DebugPrint("|cff00ff00[WN CollectionService]|r NEW TOY: " .. name .. (skipNotification and " (notification deduped)" or ""))
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
                name = ((ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion") .. " " .. visualID
            end
            
            local icon = illusionInfo.icon or 134400
            
            -- Remove from uncollected cache if present
            self:RemoveFromUncollected("illusion", visualID)
            
            -- Persistent dedup (survives logout)
            MarkAsPermanentlyNotified("illusion", visualID)
            
            -- Fire notification event
            self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                type = "illusion",
                id = visualID,
                name = name,
                icon = icon
            })
            
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW ILLUSION: " .. name .. " (ID: " .. visualID .. ")")
        end
    end
    
    -- Update previous state
    self._previousIllusionState = currentCollected
end

-- Dedicated listener key for CollectionService message handlers.
-- AceEvent allows only ONE handler per (event, self) pair; using WarbandNexus as self
-- would be overwritten by CollectionsUI handlers (or vice versa).
local CSListeners = {}

-- When any module fires WN_COLLECTIBLE_OBTAINED (e.g. TryCounterService, bag scan), keep uncollected cache in sync
-- so completed/obtained items disappear from Browse (Mounts/Pets/Toys) and Plans lists.
local Constants_CS = ns.Constants
if Constants_CS and Constants_CS.EVENTS and Constants_CS.EVENTS.COLLECTIBLE_OBTAINED then
    WarbandNexus.RegisterMessage(CSListeners, Constants_CS.EVENTS.COLLECTIBLE_OBTAINED, function(_, data)
        if not data or not data.type or not data.id then return end
        local t = data.type
        if (t == "mount" or t == "pet" or t == "toy") and data.id then
            WarbandNexus:RemoveFromUncollected(t, data.id)
            if Constants_CS.EVENTS.COLLECTION_UPDATED then
                WarbandNexus:SendMessage(Constants_CS.EVENTS.COLLECTION_UPDATED, t)
            end
        end
    end)
end

-- Register real-time collection events
-- Bag scan handles ALL collectible detection (mount/pet/toy)
-- Real-time collection events: fire when mount/pet/toy is learned (from quests, drops, vendors, etc.)
-- Duplicate prevention: Multi-layer debounce (name, ID, bag-detection) prevents double notifications.
WarbandNexus:RegisterEvent("NEW_MOUNT_ADDED", "OnNewMount")
WarbandNexus:RegisterEvent("NEW_PET_ADDED", "OnNewPet")
WarbandNexus:RegisterEvent("NEW_TOY_ADDED", "OnNewToy")

-- Invalidate API counts cache so Statistics and Collections show same numbers after any collection change
local function InvalidateCollectionCountsCache()
    if WarbandNexus.InvalidateCollectionCountsAPICache then
        WarbandNexus:InvalidateCollectionCountsAPICache()
    end
end
WarbandNexus.RegisterMessage(CSListeners, Constants.EVENTS.COLLECTION_UPDATED, InvalidateCollectionCountsCache)
WarbandNexus.RegisterMessage(CSListeners, Constants.EVENTS.COLLECTIBLE_OBTAINED, InvalidateCollectionCountsCache)

---Handle ACHIEVEMENT_EARNED event
---Removes completed achievement from cache and handles chained achievements
---@param achievementID number The completed achievement ID
function WarbandNexus:OnAchievementEarned(event, achievementID)
    if not achievementID then return end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r Achievement earned: " .. achievementID)
    
    -- Remove completed achievement from cache
    if collectionCache.uncollected.achievement and collectionCache.uncollected.achievement[achievementID] then
        collectionCache.uncollected.achievement[achievementID] = nil
    DebugPrint("|cff9370DB[WN CollectionService]|r Removed completed achievement " .. achievementID .. " from cache")
    end

    -- Mark as collected in store so Collections UI and GetAllAchievementsData show it as completed
    if not collectionStore.achievement then collectionStore.achievement = {} end
    local entry = collectionStore.achievement[achievementID]
    if not entry then
        collectionStore.achievement[achievementID] = { collected = true }
    else
        entry.collected = true
    end
    self:SaveCollectionStore()

    -- Check for chained/superceding achievements (e.g., 5/5 → 0/10)
    -- GetSupercedingAchievements returns the next achievement in the chain
    if C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements then
        local supercedingAchievements = C_AchievementInfo.GetSupercedingAchievements(achievementID)
        if supercedingAchievements and #supercedingAchievements > 0 then
            for _, nextAchievementID in ipairs(supercedingAchievements) do
                -- Get achievement info with pcall protection
                local success, id, name, points, completed, month, day, year, description, flags, icon = pcall(GetAchievementInfo, nextAchievementID)
                
                if success and name and not completed then
    DebugPrint("|cffffcc00[WN CollectionService]|r Found chained achievement: " .. name .. " (ID: " .. nextAchievementID .. ")")
                    
                    -- Get category ID
                    local categoryID = GetAchievementCategory(nextAchievementID)
                    
                    -- Get reward info (with pcall)
                    local rewardItemID, rewardTitle
                    local rewardSuccess, item, title = pcall(GetAchievementReward, nextAchievementID)
                    if rewardSuccess then
                        if type(item) == "number" then
                            rewardItemID = item
                        end
                        if type(title) == "string" and title ~= "" then
                            rewardTitle = title
                        elseif type(item) == "string" and item ~= "" then
                            rewardTitle = item
                        end
                    end
                    
                    -- Add new chained achievement to cache directly (no full re-scan needed!)
                    if not collectionCache.uncollected.achievement then
                        collectionCache.uncollected.achievement = {}
                    end
                    
                    collectionCache.uncollected.achievement[nextAchievementID] = {
                        id = nextAchievementID,
                        name = name,
                        points = points,
                        description = description,
                        icon = icon,
                        type = "achievement",
                        rewardItemID = rewardItemID,
                        rewardTitle = rewardTitle,
                        categoryID = categoryID
                    }
                    
    DebugPrint("|cff00ff00[WN CollectionService]|r Added chained achievement to cache: " .. name)
                    
                    -- Trigger UI refresh (no cache invalidation needed!)
                    if self.SendMessage then
                        self:SendMessage("WN_COLLECTION_UPDATED", "achievement")
                    end
                    
                    break -- Only need to process one chained achievement
                end
            end
        end
    end
    
    -- Notify UI so Collections tab updates immediately (achievement earned).
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "achievement")
    end
    -- When "Replace Achievement Popup" is OFF: we don't hook AddAlert, so send WN_COLLECTIBLE_OBTAINED here so Plans/TryCounter/cache get the event. When ON: hook sends it via ShowAchievementNotification.
    local hideBlizzard = self.db and self.db.profile and self.db.profile.notifications and self.db.profile.notifications.hideBlizzardAchievementAlert
    if not hideBlizzard then
        local ok, _, achName, _, _, _, _, _, _, _, achIcon = pcall(GetAchievementInfo, achievementID)
        if not ok then achName = nil; achIcon = nil end
        if issecretvalue then
            if achName and issecretvalue(achName) then achName = nil end
            if achIcon and issecretvalue(achIcon) then achIcon = nil end
        end
        local displayName = achName or ((ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement")
        local displayIcon = achIcon
        MarkAsPermanentlyNotified("achievement", achievementID)
        self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
            type = "achievement",
            id = achievementID,
            name = displayName,
            icon = displayIcon
        })
    end
end

---Called from AddAlert hook when "Replace Achievement Popup" is on. Builds payload, marks notified, sends WN_COLLECTIBLE_OBTAINED. If we don't show (e.g. notifications off), Blizzard popup is shown as fallback by the hook.
---@param achievementID number
function WarbandNexus:ShowAchievementNotification(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return end
    if issecretvalue and issecretvalue(achievementID) then return end
    local ok, _, achName, _, _, _, _, _, _, _, achIcon = pcall(GetAchievementInfo, achievementID)
    if not ok then achName = nil; achIcon = nil end
    if issecretvalue then
        if achName and issecretvalue(achName) then achName = nil end
        if achIcon and issecretvalue(achIcon) then achIcon = nil end
    end
    local displayName = achName
    local displayIcon = achIcon
    if not displayName or displayName == "" then
        displayName = (ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement"
        displayIcon = nil
    end
    MarkAsPermanentlyNotified("achievement", achievementID)
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "achievement",
        id = achievementID,
        name = displayName,
        icon = displayIcon
    })
end

-- Register achievement earned event for cache invalidation
-- CRITICAL: Must be AFTER function definition
WarbandNexus:RegisterEvent("ACHIEVEMENT_EARNED", "OnAchievementEarned")

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
    
    -- FAST PATH: Use GetItemInfoInstant first (non-blocking, cache-only) to get classID/subclassID.
    -- This avoids calling the potentially blocking GetItemInfo for non-collectible items.
    -- Collectibles can be classID 0 (Consumable - vendor toys/elixirs),
    -- 15 (Miscellaneous - most mounts/toys), or 17 (Battle Pet).
    local _, _, _, _, _, instantClassID, instantSubclassID = GetItemInfoInstant(itemID)
    if instantClassID and instantClassID ~= 0 and instantClassID ~= 15 and instantClassID ~= 17 then
        return nil  -- Definitely not a collectible (weapon, armor, reagent, etc.)
    end
    
    -- Get full item info (may block briefly if not cached, but we've narrowed the set)
    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
    local itemName, _, _, _, _, _, _, _, _, itemIcon, _, classID, subclassID = GetItemInfoFn(itemID)
    if not classID then
        -- Fallback: use instant values if GetItemInfo hasn't cached yet
        if instantClassID then
            classID = instantClassID
            subclassID = instantSubclassID
        else
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemID)
            end
            return nil
        end
    end
    
    -- Log for known collectible classes to aid debugging
    -- classID 0: Consumable (some vendor toys), classID 15: Misc (mounts/toys/pets), classID 17: Battle Pet
    if classID == 0 or classID == 17 or (classID == 15 and (subclassID == 0 or subclassID == 2 or subclassID == 5)) then
        DebugPrint("|cff00ccff[WN CollectionService]|r CheckNewCollectible: itemID=" .. itemID .. " classID=" .. tostring(classID) .. " subclassID=" .. tostring(subclassID) .. " name=" .. tostring(itemName))
    end
    
    -- ========================================
    -- MOUNT (classID 15, subclass 5)
    -- ========================================
    if classID == 15 and subclassID == 5 then
        local result = self:_DetectMount(itemID, itemName, itemIcon)
        if result then return result end
    end
    
    -- ========================================
    -- PETS (Battle Pets: classID 17, Companion Pets: classID 15/subclass 2)
    -- ========================================
    if classID == 17 or (classID == 15 and subclassID == 2) then
        local result = self:_DetectPet(itemID, hyperlink, itemName, itemIcon, classID, subclassID)
        if result then return result end
    end
    
    -- ========================================
    -- TOY (classID 15/subclass 0, or classID 0 - Consumable-type toys like vendor elixirs)
    -- ========================================
    if (classID == 15 and subclassID == 0) or classID == 0 then
        local result = self:_DetectToy(itemID, itemName, itemIcon)
        if result then return result end
    end
    
    -- ========================================
    -- FALLBACK: classID 15/0 items that didn't match specific branches
    -- Some vendor pets/mounts have unexpected subclassIDs (e.g., subclass 4 "Other")
    -- Only check items that have a "Use:" spell (skips junk like Spare Parts, Pet Charms)
    -- ========================================
    if (classID == 15 or classID == 0) and subclassID ~= 5 and subclassID ~= 2 then
        -- Only try fallback if the item is DIRECTLY convertible to a collectible
        -- Check if any collection API recognizes this item (skip generic "Use:" items)
        local isMountItem = C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(itemID)
        local isToyItem = C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID)
        
        if isMountItem or isToyItem then
            DebugPrint("|cffffcc00[WN CollectionService]|r Fallback detection for classID=15, subclassID=" .. tostring(subclassID) .. " itemID=" .. itemID)
            
            if isMountItem then
                local mountResult = self:_DetectMount(itemID, itemName, itemIcon)
                if mountResult then return mountResult end
            end
            
            if isToyItem then
                local toyResult = self:_DetectToy(itemID, itemName, itemIcon)
                if toyResult then return toyResult end
            end
            
            -- Try pet detection as last resort
            local petResult = self:_DetectPet(itemID, hyperlink, itemName, itemIcon, classID, subclassID)
            if petResult then return petResult end
        end
    end
    
    -- ========================================
    -- FALLBACK 2: classID 15 subclass 2 where GetPetInfoByItemID failed
    -- Try hyperlink-based detection as alternative
    -- ========================================
    if classID == 15 and subclassID == 2 and hyperlink then
        -- GetPetInfoByItemID failed in the pet branch above
        -- Try tooltip-based detection via C_TooltipInfo
        local speciesID = self:_DetectPetFromTooltip(itemID)
        if speciesID then
            local result = self:_BuildPetResult(speciesID, itemName, itemIcon)
            if result then return result end
        end
    end
    
    return nil
end

-- ============================================================================
-- DETECTION HELPERS (DRY extraction from CheckNewCollectible)
-- ============================================================================

---Try to detect a mount from itemID
---@param itemID number
---@param itemName string|nil
---@param itemIcon number|string|nil
---@return table|nil
function WarbandNexus:_DetectMount(itemID, itemName, itemIcon)
    if not C_MountJournal or not C_MountJournal.GetMountFromItem then
        return nil
    end
    
    local mountID = C_MountJournal.GetMountFromItem(itemID)
    if not mountID then return nil end
    
    -- Check if already owned
    local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
    if not name or isCollected then return nil end
    
    -- DUPLICATE PREVENTION
    if WasDetectedInBag("mount", mountID) then return nil end
    if WasRecentlyShownByName(name) then return nil end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW MOUNT DETECTED: " .. name .. " (ID: " .. mountID .. ")")
    return {
        type = "mount",
        id = mountID,
        name = name,
        icon = icon
    }
end

---Try to detect a pet from itemID/hyperlink using multiple methods
---@param itemID number
---@param hyperlink string|nil
---@param itemName string|nil
---@param itemIcon number|string|nil
---@param classID number
---@param subclassID number
---@return table|nil
function WarbandNexus:_DetectPet(itemID, hyperlink, itemName, itemIcon, classID, subclassID)
    if not C_PetJournal then return nil end
    
    local speciesID = nil
    local speciesName = nil
    local speciesIcon = nil
    
    -- Method 1: Battle Pet Cage (classID 17) - extract speciesID from hyperlink
    if classID == 17 and hyperlink then
        speciesID = tonumber(hyperlink:match("|Hbattlepet:(%d+):"))
        if speciesID then
            speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        end
    end
    
    -- Method 2: Companion Pet Item - use C_PetJournal.GetPetInfoByItemID
    -- IMPORTANT: Return signature is (name, icon, petType, creatureID, sourceText, description,
    --   isWild, canBattle, tradeable, unique, obtainable, displayID, speciesID)
    -- speciesID is the 13th return value, NOT the 1st!
    if not speciesID and C_PetJournal.GetPetInfoByItemID then
        local pName, pIcon, _, _, _, _, _, _, _, _, _, _, pSpeciesID = C_PetJournal.GetPetInfoByItemID(itemID)
        if pSpeciesID and type(pSpeciesID) == "number" then
            speciesID = pSpeciesID
            speciesName = pName
            speciesIcon = pIcon
        end
    end
    
    -- Method 3: Try tooltip-based detection if above methods failed
    if not speciesID or type(speciesID) ~= "number" then
        speciesID = self:_DetectPetFromTooltip(itemID)
        if speciesID then
            speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        end
    end
    
    -- If speciesID found, use full species-aware detection
    if speciesID and type(speciesID) == "number" then
        return self:_BuildPetResult(speciesID, speciesName or itemName, speciesIcon or itemIcon)
    end
    
    -- ========================================
    -- Method 4: ITEM-BASED FALLBACK
    -- C_PetJournal.GetPetInfoByItemID doesn't support all items (API limitation).
    -- For confirmed companion pet items (classID=15, subclass=2), verify via GetItemSpell
    -- and use item info (name/icon) for the notification instead of species info.
    -- The NEW_PET_ADDED event will handle the authoritative collection detection when learned.
    -- ========================================
    if classID == 15 and subclassID == 2 then
        local spellName, spellID = GetItemSpell(itemID)
        if spellName and spellID then
    DebugPrint("|cffffcc00[WN CollectionService]|r Pet item fallback: GetPetInfoByItemID failed, using item info. spell=" .. tostring(spellName) .. " spellID=" .. tostring(spellID))
            
            local petName = itemName or ((ns.L and ns.L["FALLBACK_UNKNOWN_PET"]) or "Unknown Pet")
            
            -- DUPLICATE PREVENTION (use item-based key since we don't have speciesID)
            if WasDetectedInBag("pet_item", itemID) then return nil end
            if WasRecentlyShownByName(petName) then return nil end
            
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW PET DETECTED (item fallback): " .. petName .. " (itemID: " .. itemID .. ")")
            return {
                type = "pet",
                id = itemID,  -- Use itemID since speciesID unavailable
                name = petName,
                icon = itemIcon or 134400
            }
        end
    end
    
    return nil
end

---Build pet result after speciesID is confirmed
---@param speciesID number
---@param fallbackName string|nil
---@param fallbackIcon number|string|nil
---@return table|nil
function WarbandNexus:_BuildPetResult(speciesID, fallbackName, fallbackIcon)
    if not C_PetJournal then return nil end
    
    -- Get species info if not already available
    local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    local petName = speciesName or fallbackName or ((ns.L and ns.L["FALLBACK_UNKNOWN_PET"]) or "Unknown Pet")
    local petIcon = speciesIcon or fallbackIcon or 134400
    
    -- Check if player already owns this species (only notify for 0/3 → first acquisition)
    local numOwned = C_PetJournal.GetNumCollectedInfo(speciesID)
    if numOwned and numOwned > 0 then
        return nil  -- Already collected
    end
    
    -- DUPLICATE PREVENTION
    if WasDetectedInBag("pet", speciesID) then return nil end
    if WasRecentlyShownByName(petName) then return nil end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW PET DETECTED: " .. petName .. " (speciesID: " .. speciesID .. ")")
    return {
        type = "pet",
        id = speciesID,
        name = petName,
        icon = petIcon
    }
end

---Try to extract speciesID from item tooltip data
---Uses C_TooltipInfo API to check for battle pet markers in tooltip
---@param itemID number
---@return number|nil speciesID
function WarbandNexus:_DetectPetFromTooltip(itemID)
    -- Method: C_TooltipInfo.GetItemByID returns structured tooltip data
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then
        return nil
    end
    
    local success, tooltipData = pcall(C_TooltipInfo.GetItemByID, itemID)
    if not success or not tooltipData or not tooltipData.lines then
        return nil
    end
    
    -- Look for battlepet hyperlink in tooltip lines
    for i = 1, #tooltipData.lines do
        local line = tooltipData.lines[i]
        if line and line.leftText then
            -- Some items embed battlepet:speciesID in tooltip
            local speciesID = tonumber(line.leftText:match("battlepet:(%d+)"))
            if speciesID then
    DebugPrint("|cff00ccff[WN CollectionService]|r Tooltip detection found speciesID: " .. speciesID .. " for itemID: " .. itemID)
                return speciesID
            end
        end
    end
    
    return nil
end

---Try to detect a toy from itemID
---@param itemID number
---@param itemName string|nil
---@param itemIcon number|string|nil
---@return table|nil
function WarbandNexus:_DetectToy(itemID, itemName, itemIcon)
    if not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end

    local _, toyName, toyIcon, _, _, itemQuality = C_ToyBox.GetToyInfo(itemID)
    if not toyName then return nil end
    -- Midnight 12.0: API returns may be secret; do not use for display or logic
    if issecretvalue and issecretvalue(toyName) then return nil end

    -- Check if already owned (guard secret return)
    if PlayerHasToy then
        local has = PlayerHasToy(itemID)
        if issecretvalue and has and issecretvalue(has) then return nil end
        if has == true then return nil end
    end
    
    -- DUPLICATE PREVENTION
    if WasDetectedInBag("toy", itemID) then return nil end
    if WasRecentlyShownByName(toyName) then return nil end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW TOY DETECTED: " .. toyName .. " (ID: " .. itemID .. ")")
    return {
        type = "toy",
        id = itemID,
        name = toyName,
        icon = toyIcon or itemIcon,
        itemQuality = itemQuality,
    }
end

-- ============================================================================
-- BACKGROUND SCANNING (Async Coroutine-Based)
-- ============================================================================

-- Runtime cache for illusions (used during scan to avoid API re-calls)
local illusionRuntimeCache = nil
local illusionDebugCount = 0  -- Debug counter for illusion logging

---Unified collection configuration for background scanning
COLLECTION_CONFIGS = {
    mount = {
        name = "Mounts",
        iterator = function()
            EnsureBlizzardCollectionsLoaded()
            if not C_MountJournal or not C_MountJournal.GetMountIDs then return {} end
            return C_MountJournal.GetMountIDs() or {}
        end,
        extract = function(mountID)
            local name, spellID, icon, _, _, sourceType, _, isFactionSpecific, faction, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if not name then return nil end
            -- Midnight 12.0: isCollected may be a secret value; never assign it directly
            local collected = false
            if issecretvalue and isCollected and issecretvalue(isCollected) then
                collected = true
            elseif isCollected == true then
                collected = true
            end

            local creatureDisplayID, description, source = C_MountJournal.GetMountInfoExtraByID(mountID)

            return {
                id = mountID,
                name = name,
                icon = icon,
                spellID = spellID,
                source = source or ((ns.L and ns.L["FALLBACK_UNKNOWN_SOURCE"]) or UNKNOWN or "Unknown"),
                sourceType = sourceType,
                description = description,
                creatureDisplayID = creatureDisplayID,
                collected = collected,
                shouldHideOnChar = shouldHideOnChar,
                isFactionSpecific = isFactionSpecific,
                faction = faction,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected or data.shouldHideOnChar then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableMount(data) then
                return false
            end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data or data.shouldHideOnChar then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableMount(data) then
                return false
            end
            return true
        end,
    },
    
    pet = {
        name = "Pets",
        iterator = function()
            if not C_PetJournal then return {} end
            
            -- CRITICAL: Pet journal filter functions require Blizzard_Collections to be loaded
            EnsureBlizzardCollectionsLoaded()
            
            -- Save original filter state
            local origSearch = C_PetJournal.GetSearchFilter and C_PetJournal.GetSearchFilter() or ""
            
            -- Reset filters to show ALL pets for accurate scanning
            -- TAINT GUARD: Filter manipulation taints PetJournal; skip during combat to prevent blocked actions
            if not InCombatLockdown() then
                pcall(function()
                    if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
                    -- Show both collected and uncollected
                    if C_PetJournal.SetFilterChecked then
                        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
                    end
                    -- Show all pet types
                    if C_PetJournal.SetPetTypeFilter then
                        for i = 1, C_PetJournal.GetNumPetTypes() do
                            C_PetJournal.SetPetTypeFilter(i, true)
                        end
                    end
                    -- Show all sources
                    if C_PetJournal.SetPetSourceChecked then
                        for i = 1, C_PetJournal.GetNumPetSources() do
                            C_PetJournal.SetPetSourceChecked(i, true)
                        end
                    end
                end)
            end
            
            local numPets = C_PetJournal.GetNumPets() or 0
            
            -- CRITICAL: Resolve speciesIDs NOW while "show all" filters are active
            -- GetPetInfoByIndex depends on current filter state
            local pets = {}
            local seen = {}
            for i = 1, numPets do
                local _, speciesID = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID and not seen[speciesID] then
                    seen[speciesID] = true
                    table.insert(pets, speciesID)
                end
            end
            
            -- Restore original filter state
            -- TAINT GUARD: Same guard as above - skip restore if in combat
            if not InCombatLockdown() then
                pcall(function()
                    if origSearch and origSearch ~= "" and C_PetJournal.SetSearchFilter then
                        C_PetJournal.SetSearchFilter(origSearch)
                    end
                end)
            end
            
            return pets
        end,
        extract = function(speciesID)
            -- speciesID is now passed directly from iterator (not an index)
            if not speciesID then return nil end
            
            local speciesName, icon, petType, _, source, description = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
            if not speciesName then return nil end
            
            -- Check if player owns this species
            local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
            local owned = numCollected and numCollected > 0
            
            local creatureDisplayID = nil
            if C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
                local numDisplays = C_PetJournal.GetNumDisplays(speciesID) or 0
                if numDisplays > 0 then
                    creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(speciesID, 1)
                end
            end
            
            return {
                id = speciesID,
                name = speciesName,
                icon = icon,
                source = source or ((ns.L and ns.L["FALLBACK_PET_COLLECTION"]) or "Pet Collection"),
                description = description,
                collected = owned,
                petType = petType,
                creatureDisplayID = creatureDisplayID,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainablePet(data) then
                return false
            end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainablePet(data) then
                return false
            end
            return true
        end,
    },

    toy = {
        name = "Toys",
        iterator = function()
            if not C_ToyBox then return {} end
            
            -- CRITICAL: C_ToyBox filter functions require Blizzard_Collections to be loaded.
            -- Without it, GetNumFilteredToys() returns 0 and filter manipulation has no effect.
            EnsureBlizzardCollectionsLoaded()
            
            -- Save original filter state to restore after scan
            local origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
            local origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
            local origFilterString = C_ToyBox.GetFilterString and C_ToyBox.GetFilterString() or ""
            
            -- Ensure all toys are visible for scanning (GetToyFromIndex uses filtered list)
            -- TAINT GUARD: ToyBox filter manipulation is protected; skip during combat
            if not InCombatLockdown() then
                pcall(function()
                    C_ToyBox.SetCollectedShown(true)
                    C_ToyBox.SetUncollectedShown(true)
                    C_ToyBox.SetAllSourceTypeFilters(true)
                    C_ToyBox.SetFilterString("")
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            
            -- Try GetNumFilteredToys first; fall back to GetNumTotalDisplayedToys or GetNumToys
            local numToys = 0
            if C_ToyBox.GetNumFilteredToys then
                numToys = C_ToyBox.GetNumFilteredToys() or 0
            end
            -- If filtered count is 0, the filter may not have applied yet; try total count
            if numToys == 0 and C_ToyBox.GetNumTotalDisplayedToys then
                numToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
            end
            if numToys == 0 and C_ToyBox.GetNumToys then
                numToys = C_ToyBox.GetNumToys() or 0
            end
            
            -- CRITICAL: Resolve itemIDs NOW while "show all" filters are active.
            -- GetToyFromIndex uses the current filter state, so we must capture
            -- actual itemIDs before restoring original filters.
            local toys = {}
            for i = 1, numToys do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and itemID > 0 then
                    table.insert(toys, itemID)
                end
            end
            
            -- Restore original filter state to avoid side effects on player ToyBox UI
            -- TAINT GUARD: Same guard as above - skip restore if in combat
            if not InCombatLockdown() then
                pcall(function()
                    if origCollected ~= nil then C_ToyBox.SetCollectedShown(origCollected) end
                    if origUncollected ~= nil then C_ToyBox.SetUncollectedShown(origUncollected) end
                    if origFilterString then C_ToyBox.SetFilterString(origFilterString) end
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            
            return toys
        end,
        extract = function(itemID)
            if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
            local _, toyName = C_ToyBox.GetToyInfo(itemID)
            if issecretvalue and toyName and issecretvalue(toyName) then toyName = nil end
            local name = (toyName and toyName ~= "") and toyName or tostring(itemID)
            local collected = false
            if PlayerHasToy then
                local raw = PlayerHasToy(itemID)
                if issecretvalue and raw and issecretvalue(raw) then collected = true
                else collected = raw == true end
            end
            return { id = itemID, name = name, collected = collected }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableToy(data) then
                return false
            end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableToy(data) then
                return false
            end
            return true
        end,
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
                source = description or ((ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement"),
                collected = completed,
                rewardItemID = rewardItemID,
                rewardTitle = rewardTitle,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            return data ~= nil
        end,
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
                source = description or ((ns.L and ns.L["FALLBACK_PLAYER_TITLE"]) or "Title Reward"),
                collected = completed,
                rewardText = rewardTitle,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            return data ~= nil
        end,
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
            local sourceText = sourceInfo.sourceText or ((ns.L and ns.L["FALLBACK_TRANSMOG_COLLECTION"]) or "Transmog Collection")
            
            -- Get item info (C_Item namespace for Midnight 12.0+)
            local itemName, _, _, _, icon
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
            if itemID then
                itemName, _, _, _, _, _, _, _, _, icon = GetItemInfoFn(itemID)
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
        name = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
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
                local illusionType = (ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion"
                name = ((ns.L and ns.L["FALLBACK_ILLUSION_FORMAT"]) and string.format(ns.L["FALLBACK_ILLUSION_FORMAT"], sourceID)) or (illusionType .. " " .. sourceID)
            end
            
            -- Clean up sourceText
            if not sourceText or sourceText == "" then
                sourceText = illusionInfo.sourceText or ((ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source")
            end
            
            local icon = illusionInfo.icon or 134400  -- Default icon
            local isCollected = illusionInfo.isCollected
            
            -- DEBUG: Log source info for first few illusions
            if not isCollected then
                if illusionDebugCount < 5 then
    DebugPrint(string.format("|cff00ffff[WN DEBUG Illusion #%d]|r sourceID: %d, visualID: %d", 
                        illusionDebugCount + 1, sourceID, illusionInfo.visualID or 0))
    DebugPrint("  GetIllusionStrings(" .. sourceID .. ") returned:")
    DebugPrint("    name:", tostring(name))
    DebugPrint("    hyperlink:", tostring(hyperlink))
    DebugPrint("    sourceText:", tostring(sourceText))
                    
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
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableIllusion(data) then
                return false
            end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            if ns.CollectionRules and ns.CollectionRules.UnobtainableFilters and
               ns.CollectionRules.UnobtainableFilters:IsUnobtainableIllusion(data) then
                return false
            end
            return true
        end,
    },

    title = {
        name = "Titles",
        iterator = function()
            if not GetNumTitles or not GetTitleName or not IsTitleKnown then return {} end
            
            local numTitles = GetNumTitles()
            if not numTitles or numTitles == 0 then return {} end
            
            local titleList = {}
            for titleMaskID = 1, numTitles do
                table.insert(titleList, titleMaskID)
            end
            
            return titleList
        end,
        extract = function(titleMaskID)
            -- Get title info
            local titleString, playerTitle = GetTitleName(titleMaskID)
            if not titleString or titleString == "" then return nil end
            
            -- Check if player knows this title
            local isKnown = IsTitleKnown(titleMaskID)
            
            -- Format title name (remove %s placeholder)
            local displayName = titleString:gsub("%%s", ""):trim()
            
            return {
                id = titleMaskID,
                name = displayName,
                titleString = titleString,  -- Original format with %s
                playerTitle = playerTitle,  -- Boolean: true = suffix (name Title), false = prefix (Title name)
                collected = isKnown,
                iconAtlas = "poi-legendsoftheharanir",  -- Atlas icon for titles (matches TYPE_ICONS.title)
                icon = nil,  -- No texture icon, use atlas only
                source = (ns.L and ns.L["FALLBACK_PLAYER_TITLE"]) or "Player Title",
                type = "title",
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            return data ~= nil
        end,
    },
}

---Scan a collection type asynchronously (coroutine-based with duplicate protection)
---@param collectionType string "mount", "pet", "toy", "achievement", "title", "transmog", "illusion"
---@param onProgress function|nil Progress callback (current, total, itemData)
---@param onComplete function|nil Completion callback (results)
function WarbandNexus:ScanCollection(collectionType, onProgress, onComplete)
    DebugPrint("|cff9370DB[WN CollectionService]|r ScanCollection called for: " .. tostring(collectionType))
    
    -- Ensure Blizzard_Collections is loaded (required for icons, source text, toy filters)
    EnsureBlizzardCollectionsLoaded()
    
    local config = COLLECTION_CONFIGS[collectionType]
    if not config then
    DebugPrint("|cffff4444[WN CollectionService ERROR]|r Invalid collection type: " .. tostring(collectionType))
        return
    end
    
    -- CRITICAL: Prevent duplicate scans (already scanning)
    if activeCoroutines[collectionType] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Scan already in progress for: " .. tostring(collectionType) .. ", skipping")
        return
    end
    
    -- CRITICAL: Check if scan is needed (collectionStore veya collectionCache dolu ve güncel)
    local storeHasData = collectionStore[collectionType] and next(collectionStore[collectionType]) ~= nil
    local cacheHasData = collectionCache.uncollected[collectionType] and next(collectionCache.uncollected[collectionType]) ~= nil
    local cacheExists = storeHasData or cacheHasData
    if cacheExists then
        local lastScan = collectionCache.lastScan or 0
        local timeSinceLastScan = time() - lastScan
        
        -- If cache exists and scan was recent (< 5 minutes), skip
        if timeSinceLastScan < 300 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Cache exists and recent for " .. tostring(collectionType) .. " (scanned " .. timeSinceLastScan .. "s ago), skipping scan")
            -- CRITICAL: EnsureCollectionData relies on onComplete to advance the queue; always invoke when skipping
            if onComplete then onComplete(collectionStore[collectionType] or {}) end
            return
        end
    end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r Starting background scan: " .. tostring(collectionType))
    
    -- Initialize loading state for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState[collectionType] then
        ns.PlansLoadingState[collectionType] = { isLoading = false, loader = nil }
    end
    
    -- Set loading state to true
    ns.PlansLoadingState[collectionType].isLoading = true
    ns.PlansLoadingState[collectionType].loadingProgress = 0
    ns.PlansLoadingState[collectionType].currentStage = "Preparing..."
    
    local co = coroutine.create(function()
        local startTime = debugprofilestop()
        local results = {}
        local items = config.iterator()
        local total = #items
        local Constants = ns.Constants

        -- Handle empty collection (nothing to scan)
        if total == 0 then
            -- For toy scans, 0 results likely means filters didn't apply yet; schedule retry instead of caching empty
            if collectionType == "toy" then
                local retryKey = "__toyRetryCount"
                local retryCount = ns[retryKey] or 0
                if retryCount < 3 then
                    ns[retryKey] = retryCount + 1
                    ns.PlansLoadingState[collectionType].isLoading = false
                    ns.PlansLoadingState[collectionType].currentStage = "Retrying..."
                    DebugPrint("|cffffcc00[WN CollectionService]|r Toy scan returned 0 results, scheduling retry " .. (retryCount + 1) .. "/3")
                    C_Timer.After(0.5, function()
                        if self and self.ScanCollection then self:ScanCollection("toy") end
                    end)
                    return
                end
                -- After 3 retries, give up and cache empty
                ns[retryKey] = nil
            end
            if collectionStore[collectionType] ~= nil then
                collectionStore[collectionType] = results
            end
            collectionCache.uncollected[collectionType] = results
            ns.PlansLoadingState[collectionType].isLoading = false
            ns.PlansLoadingState[collectionType].loadingProgress = 100
            ns.PlansLoadingState[collectionType].currentStage = "Complete!"
            if Constants and Constants.EVENTS then
                self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
                    category = collectionType,
                    progress = 100,
                    scanned = 0,
                    total = 0,
                })
            end
            -- CRITICAL: EnsureCollectionData queue advances only when onComplete is called (e.g. illusion/title empty scan)
            if onComplete then onComplete(results) end
            if Constants and Constants.EVENTS then
                self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = collectionType, results = results, elapsed = 0 })
            end
            return
        end

        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_PROGRESS, {
                category = collectionType,
                progress = 0,
                scanned = 0,
                total = total,
            })
        end

        local shouldIncludeFn = config.shouldIncludeInAll or config.shouldInclude
        for i, item in ipairs(items) do
            local data = config.extract(item)

            if data and data.id and shouldIncludeFn and shouldIncludeFn(data) then
                results[data.id] = data
            end

            -- PROGRESSIVE UPDATE: Update loading state every 50 items
            if i % 50 == 0 or i == total then
                local progress = math.min(99, math.floor((i / total) * 100))
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
                -- Check if scan was aborted (tab switch)
                if not activeCoroutines[collectionType] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Scan aborted for: " .. collectionType)
                    ns.PlansLoadingState[collectionType].isLoading = false
                    return  -- Exit coroutine gracefully
                end
                coroutine.yield()
            end
        end
        
        -- Merkezi kaynak: collectionStore'a tam veri yaz (mount, pet, toy, achievement, title, illusion)
        if collectionStore[collectionType] ~= nil then
            collectionStore[collectionType] = results
        end
        -- collectionCache.uncollected: Plans/GetUncollectedItems için id->name (sadece uncollected)
        local uncollectedMap = {}
        for id, d in pairs(results) do
            if d and (d.collected == false or d.collected == nil) then
                uncollectedMap[id] = (d.name and d.name ~= "") and d.name or ("ID:" .. tostring(id))
            end
        end
        collectionCache.uncollected[collectionType] = uncollectedMap
        collectionCache.lastScan = time()
        collectionStore.lastBuilt = time()

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
    DebugPrint(string.format("|cff00ff00[WN CollectionService]|r Scan complete: %s - %d total, %d uncollected, %.2fms",
            config.name, total, uncollectedCount, elapsed))
        
        -- CRITICAL DEBUG: Verify cache write
    DebugPrint("|cff00ccff[WN CollectionService DEBUG]|r Cache written to key: '" .. collectionType .. "'")
    DebugPrint("|cff00ccff[WN CollectionService DEBUG]|r Cache now has keys:")
        for key, value in pairs(collectionCache.uncollected) do
            local itemCount = 0
            for _ in pairs(value) do itemCount = itemCount + 1 end
    DebugPrint("|cff00ccff[WN CollectionService]|r   - '" .. key .. "' = " .. itemCount .. " items")
        end
        
        -- PERSIST TO DB (avoid re-scanning on reload)
        self:SaveCollectionCache()
        
        -- Clean up runtime caches (illusion, transmog, etc.)
        if collectionType == "illusion" and illusionRuntimeCache then
            illusionRuntimeCache = nil
    DebugPrint("|cff9370DB[WN CollectionService]|r Cleared runtime cache for illusions")
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
        
        -- UI refreshes via WN_COLLECTION_SCAN_COMPLETE listener in UI.lua (event-driven).
        
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
            -- Reset loading state so UI doesn't stay stuck
            if ns.PlansLoadingState and ns.PlansLoadingState[collectionType] then
                ns.PlansLoadingState[collectionType].isLoading = false
                ns.PlansLoadingState[collectionType].loadingProgress = 0
                ns.PlansLoadingState[collectionType].currentStage = "Error"
            end
        end
    end)
end

---Get uncollected items from cache (for Browse UI). Raw id->name map (minimal format).
---@param collectionType string "mount", "pet", "toy", "achievement", "title", "illusion"
---@return table|nil Uncollected items {id -> name string}
function WarbandNexus:GetUncollectedItems(collectionType)
    return collectionCache.uncollected[collectionType]
end

---Session-only metadata cache: circular buffer eviction (O(1) instead of O(n) table.remove).
local function metadataCacheSet(cacheKey, meta)
    if #metadataCacheOrder >= METADATA_CACHE_MAX then
        local oldKey = metadataCacheOrder[metadataCacheHead]
        if oldKey then metadataCache[oldKey] = nil end
        metadataCacheOrder[metadataCacheHead] = cacheKey
        metadataCacheHead = (metadataCacheHead % METADATA_CACHE_MAX) + 1
    else
        metadataCacheOrder[#metadataCacheOrder + 1] = cacheKey
    end
    metadataCache[cacheKey] = meta
end

local function GetToyFallbackSources()
    local fallback1 = (ns.L and ns.L["FALLBACK_TOY_COLLECTION"]) or "Toy Collection"
    local fallback2 = (ns.L and ns.L["FALLBACK_TOY_BOX"]) or "Toy Box"
    local fallback3 = (ns.L and ns.L["FALLBACK_WARBAND_TOY"]) or "Warband Toy"
    return fallback1, fallback2, fallback3
end

local function IsToySourceGeneric(sourceText)
    local fallback1, fallback2, fallback3 = GetToyFallbackSources()
    return not sourceText or sourceText == "" or sourceText == fallback1 or sourceText == fallback2 or sourceText == fallback3
end

local function TrimText(text)
    if type(text) ~= "string" then return "" end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

---Validate that toy source text is source-like (not random tooltip garbage).
---@param sourceText string|nil
---@return boolean
function WarbandNexus:IsReliableToySource(sourceText)
    if type(sourceText) ~= "string" then return false end
    local s = TrimText(sourceText)
    if s == "" or IsToySourceGeneric(s) then return false end

    if s:find("|c", 1, true) or s:find("|r", 1, true) or s:find("|T", 1, true) or s:find("|H", 1, true) then
        return false
    end

    local L = ns.L
    local sourceLabel = ((L and L["SOURCE_LABEL"]) or "Source:"):gsub("[:%s]+$", "")
    local keywords = {
        BATTLE_PET_SOURCE_1 or "Drop",
        BATTLE_PET_SOURCE_2 or "Quest",
        BATTLE_PET_SOURCE_3 or "Vendor",
        BATTLE_PET_SOURCE_4 or "Profession",
        BATTLE_PET_SOURCE_5 or "Pet Battle",
        BATTLE_PET_SOURCE_6 or "Achievement",
        BATTLE_PET_SOURCE_7 or "World Event",
        BATTLE_PET_SOURCE_8 or "Promotion",
        (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",
        (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",
        (L and L["PARSE_SOLD_BY"]) or "Sold by",
        (L and L["PARSE_CONTAINED_IN"]) or "Contained in",
        (L and L["PARSE_ZONE"]) or ZONE or "Zone",
        (L and L["PARSE_COST"]) or "Cost",
        (L and L["PARSE_AMOUNT"]) or "Amount",
        (L and L["ZONE_DROP"]) or "Zone drop",
        (L and L["FISHING"]) or "Fishing",
        sourceLabel,
    }

    for i = 1, #keywords do
        local kw = keywords[i]
        if type(kw) == "string" and kw ~= "" then
            local escaped = kw:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            if s:match("^%s*" .. escaped .. "%s*:") or s:match("^%s*" .. escaped .. "%s") then
                return true
            end
        end
    end

    return false
end

---Single place for toy metadata: C_ToyBox.GetToyInfo (name, icon, itemQuality) + tooltip (source, description) + CollectibleSourceDB when tooltip is fallback.
---API note: GetToyInfo returns itemID, toyName, icon, isFavorite, hasFanfare, itemQuality — no sourceText; source comes from tooltip/DB.
---@param itemID number Toy item ID (C_ToyBox uses item ID)
---@return table|nil { name, icon, source, description, itemQuality } or nil
function WarbandNexus:GetToySourceInfo(itemID)
    if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
    -- Session cache: reuse only when source already validated as meaningful.
    local cache = WarbandNexus.toySourceInfoCache
    if cache and cache[itemID] then
        local c = cache[itemID]
        if self:IsReliableToySource(c.source) then
            return c
        end
    end

    local _, name, icon, _, _, itemQuality = C_ToyBox.GetToyInfo(itemID)
    if not name then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    if not icon and (C_Item and C_Item.GetItemInfo) then
        local _, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
        if itemTexture then icon = itemTexture end
    end

    local sourceText = ""
    local descriptionText = ""
    -- Prefer GetToyByItemID: toy tooltip often has "Source:"; GetItemByID returns item tooltip (e.g. weapon stats) with no source line
    local tooltipData = nil
    if C_TooltipInfo then
        if C_TooltipInfo.GetToyByItemID then
            tooltipData = C_TooltipInfo.GetToyByItemID(itemID)
        end
        if (not tooltipData or not tooltipData.lines or #tooltipData.lines == 0) and C_TooltipInfo.GetItemByID then
            tooltipData = C_TooltipInfo.GetItemByID(itemID)
        end
    end
    local _issecretvalue = issecretvalue
    local function safeText(t)
        if not t or type(t) ~= "string" then return nil end
        if _issecretvalue and _issecretvalue(t) then return nil end
        return t
    end
    local function stripColorCodes(s)
        if not s or type(s) ~= "string" then return s end
        return s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|c%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")
    end
    local sourceKeywords = {
        BATTLE_PET_SOURCE_1 or "Drop",
        BATTLE_PET_SOURCE_3 or "Vendor",
        BATTLE_PET_SOURCE_2 or "Quest",
        BATTLE_PET_SOURCE_4 or "Profession",
        BATTLE_PET_SOURCE_7 or "World Event",
        BATTLE_PET_SOURCE_8 or "Promotion",
        (ns.L and ns.L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",
        (ns.L and ns.L["SOURCE_TYPE_TREASURE"]) or "Treasure",
        (ns.L and ns.L["PARSE_ZONE"]) or ZONE or "Zone",
    }
    local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
    local sourceLabelClean = sourceLabel:gsub("[:%s]+$", "")

    local function isSourceLine(line)
        if not line then return false end
        if line.type == 2 or line.type == 25 then return true end
        local left = safeText(line.leftText)
        local right = safeText(line.rightText)
        if left and sourceLabelClean ~= "" and left:find(sourceLabelClean, 1, true) then return true end
        if right and sourceLabelClean ~= "" and right:find(sourceLabelClean, 1, true) then return true end
        -- Only treat as source if line starts with "Keyword:" so description text containing "drop" etc. is not misclassified
        for _, kw in ipairs(sourceKeywords) do
            local escaped = kw:gsub("%%", "%%%%")
            if (left and left:match("^%s*" .. escaped .. "%s*:")) or (right and right:match("^%s*" .. escaped .. "%s*:")) then
                return true
            end
        end
        return false
    end

    if tooltipData and tooltipData.lines then
        local sourceParts = {}
        local descParts = {}
        for idx, line in ipairs(tooltipData.lines) do
            local left = safeText(line.leftText)
            local right = safeText(line.rightText)
            local lineText = (left and left ~= "" and left) or (right and right ~= "" and right) or nil
            if not lineText then
            elseif isSourceLine(line) then
                -- If line is "Source:" + right-side payload, prefer right-side text.
                if left and right and sourceLabelClean ~= "" and left:find(sourceLabelClean, 1, true) then
                    sourceParts[#sourceParts + 1] = right
                else
                    sourceParts[#sourceParts + 1] = lineText
                end
            elseif idx > 1 then
                descParts[#descParts + 1] = lineText
            end
        end
        if #sourceParts > 0 then
            sourceText = table.concat(sourceParts, "\n")
        end
        if #descParts > 0 then
            descriptionText = table.concat(descParts, "\n")
        end
    end
    local fallback1 = GetToyFallbackSources()
    if IsToySourceGeneric(sourceText) then
        local dbSource = ns.CollectibleSourceDB and ns.CollectibleSourceDB.GetSourceStringForToy and ns.CollectibleSourceDB.GetSourceStringForToy(itemID)
        if dbSource and dbSource ~= "" then
            sourceText = dbSource
        end
    end
    sourceText = stripColorCodes(sourceText)
    descriptionText = stripColorCodes(descriptionText)
    if not self:IsReliableToySource(sourceText) then
        sourceText = fallback1
    end
    -- Ensure space before and after every colon in source (e.g. "Vendor:Orix" -> "Vendor : Orix")
    sourceText = sourceText:gsub("([^%s]):([^%s])", "%1 : %2")
    local result = {
        name = name,
        icon = icon,
        source = sourceText,
        description = descriptionText,
        itemQuality = itemQuality,
    }
    -- Session cache (no invalidation; name/source/icon do not change on collect)
    if not WarbandNexus.toySourceInfoCache then WarbandNexus.toySourceInfoCache = {} end
    WarbandNexus.toySourceInfoCache[itemID] = result
    return result
end

---Resolve icon/source/description for a collection entry on demand. Uses session RAM cache; cleared on tab leave.
---Prefers db.global.collectionData when available (no API calls).
---@param collectionType string "mount", "pet", "toy", "achievement", "title", "illusion"
---@param id number
---@return table|nil { name, icon, source, description, ... } or nil if API fails
function WarbandNexus:ResolveCollectionMetadata(collectionType, id)
    if not id or not collectionType then return nil end
    local cacheKey = collectionType .. ":" .. tostring(id)
    if metadataCache[cacheKey] then
        return metadataCache[cacheKey]
    end

    -- Prefer full collection data from DB (no API calls)
    if collectionType == "mount" and collectionData.mount and collectionData.mount[id] then
        local d = collectionData.mount[id]
        local meta = {
            name = d.name,
            icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
            source = d.source or "",
            description = d.description or "",
            creatureDisplayID = d.creatureDisplayID,
            isCollected = d.collected,
        }
        metadataCache[cacheKey] = meta
        return meta
    end
    if collectionType == "pet" and collectionData.pet and collectionData.pet[id] then
        local d = collectionData.pet[id]
        local meta = {
            name = d.name,
            icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
            source = d.source or "",
            description = d.description or "",
            isCollected = d.collected,
            creatureDisplayID = d.creatureDisplayID,
        }
        metadataCache[cacheKey] = meta
        return meta
    end
    if collectionType == "toy" and collectionData.toy and collectionData.toy[id] then
        local d = collectionData.toy[id]
        local source = self:GetToySourceTypeNameForItem(id) or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
        if source == "SOURCE_UNKNOWN" then source = "Unknown" end
        local description = d.description or ""
        if description == "" then
            local info = self:GetToySourceInfo(id)
            if info and info.description and info.description ~= "" then description = info.description end
        end
        -- Resolve icon from API when not stored (toys only store id+name in DB)
        local icon = d.icon
        if not icon or icon == "" then
            EnsureBlizzardCollectionsLoaded()
            if C_ToyBox and C_ToyBox.GetToyInfo then
                local _, _, apiIcon = C_ToyBox.GetToyInfo(id)
                if apiIcon and apiIcon ~= 0 then icon = apiIcon end
            end
            if not icon or icon == "" then
                local info = self:GetToySourceInfo(id)
                if info and info.icon and info.icon ~= "" then icon = info.icon end
            end
        end
        local meta = {
            name = d.name,
            icon = icon or "Interface\\Icons\\INV_Misc_Toy_07",
            source = source,
            description = description,
            isCollected = d.collected,
        }
        metadataCache[cacheKey] = meta
        return meta
    end

    -- Ensure Blizzard_Collections is loaded (required for icons, source text)
    EnsureBlizzardCollectionsLoaded()

    local meta = nil
    -- Helper: treat 0 and nil as invalid icon (0 is truthy in Lua but invalid fileID)
    local function validIcon(icon)
        if icon and icon ~= 0 then return icon end
        return nil
    end

    -- Track whether we got a real icon from API or used fallback
    local usedFallbackIcon = false
    
    -- CRITICAL: Do NOT use `X and X.func()` pattern for multi-return APIs!
    -- In Lua 5.1, `X and func()` truncates to 1 return value because `and` is a
    -- binary expression, not a function call. Only raw function calls at the tail
    -- of an expression list preserve multiple returns.

    if collectionType == "mount" then
        if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return nil end
        local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
        if name then
            icon = validIcon(icon)
            -- Fallback: spell texture
            if not icon and spellID then
                if C_Spell and C_Spell.GetSpellTexture then
                    icon = validIcon(C_Spell.GetSpellTexture(spellID))
                elseif GetSpellTexture then
                    icon = validIcon(GetSpellTexture(spellID))
                end
            end
            if not icon then usedFallbackIcon = true end
            local _, description, source = C_MountJournal.GetMountInfoExtraByID(id)
            meta = { name = name, icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse", source = source or "", description = description or "" }
            -- Current collected state (Midnight: isCollected may be secret)
            if issecretvalue and isCollected and issecretvalue(isCollected) then
                meta.isCollected = true
            else
                meta.isCollected = isCollected == true
            end
        end
    elseif collectionType == "pet" then
        if not C_PetJournal or not C_PetJournal.GetPetInfoBySpeciesID then return nil end
        -- API: speciesName, speciesIcon, petType, companionID, tooltipSource, tooltipDescription
        local name, icon, _, _, source, description = C_PetJournal.GetPetInfoBySpeciesID(id)
        if name then
            icon = validIcon(icon)
            if not icon then usedFallbackIcon = true end
            local creatureDisplayID = nil
            if C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
                local numDisplays = C_PetJournal.GetNumDisplays(id) or 0
                if numDisplays > 0 then
                    creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(id, 1)
                end
            end
            local numCollected = C_PetJournal.GetNumCollectedInfo and C_PetJournal.GetNumCollectedInfo(id)
            local isCollected = numCollected and numCollected > 0
            meta = { name = name, icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01", source = source or "", description = description or "", creatureDisplayID = creatureDisplayID, isCollected = isCollected }
        end
    elseif collectionType == "toy" then
        local info = self:GetToySourceInfo(id)
        if info then
            local icon = validIcon(info.icon)
            if not icon then usedFallbackIcon = true end
            local isCollected
            if PlayerHasToy then
                local isCollectedRaw = PlayerHasToy(id)
                if issecretvalue and isCollectedRaw and issecretvalue(isCollectedRaw) then
                    isCollected = true
                else
                    isCollected = isCollectedRaw == true
                end
            end
            local sourceLine = self:GetToySourceTypeNameForItem(id) or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
            if sourceLine == "SOURCE_UNKNOWN" then sourceLine = "Unknown" end
            meta = {
                name = info.name,
                icon = icon or "Interface\\Icons\\INV_Misc_Toy_07",
                source = sourceLine,
                description = info.description or "",
                itemQuality = info.itemQuality,
                isCollected = isCollected,
            }
        end
    elseif collectionType == "achievement" then
        local ok, _, achName, points, _, _, _, _, description, _, achIcon = pcall(GetAchievementInfo, id)
        if ok and achName then
            achIcon = validIcon(achIcon)
            local categoryID = GetAchievementCategory and GetAchievementCategory(id) or nil
            meta = { name = achName, icon = achIcon or "Interface\\Icons\\Achievement_General", points = points or 0, description = description or "", source = description or "", categoryID = categoryID }
        end
    elseif collectionType == "illusion" then
        if not C_TransmogCollection or not C_TransmogCollection.GetIllusionStrings then return nil end
        local name, _, sourceText = C_TransmogCollection.GetIllusionStrings(id)
        if name then
            local illusionIcon = nil
            local illusionSourceFallback = nil
            if C_TransmogCollection.GetIllusionInfo then
                local illusionInfo = C_TransmogCollection.GetIllusionInfo(id)
                if illusionInfo then
                    illusionIcon = validIcon(illusionInfo.icon)
                    -- Secondary source fallback from illusionInfo
                    if (not sourceText or sourceText == "") and illusionInfo.sourceText then
                        illusionSourceFallback = illusionInfo.sourceText
                    end
                end
            end
            local resolvedSource = sourceText
            if not resolvedSource or resolvedSource == "" then
                resolvedSource = illusionSourceFallback or ((ns.L and ns.L["SOURCE_ENCHANTING"]) or "Enchanting")
            end
            meta = { name = name, icon = illusionIcon or "Interface\\Icons\\INV_Enchant_Disenchant", source = resolvedSource, description = "" }
        end
    elseif collectionType == "title" then
        if not GetTitleName then return nil end
        local titleString = GetTitleName(id)
        if titleString then
            meta = { name = titleString, icon = "Interface\\Icons\\INV_Scroll_11", source = "", description = "" }
        end
    end

    if meta then
        meta.id = id
        meta.type = collectionType
        meta.collected = meta.isCollected or false
        if meta.isCollected == nil then
            meta.isCollected = false
        end
        -- Only permanently cache metadata with real API icons.
        -- If fallback icon was used (API returned 0/nil), DON'T cache — allow re-query
        -- on next access so the real icon can be resolved once the data is available.
        if not usedFallbackIcon then
            metadataCacheSet(cacheKey, meta)
        end
    end
    return meta
end

---Clear session-only metadata cache (call when user leaves Plans tab to free RAM).
function WarbandNexus:ClearCollectionMetadataCache()
    wipe(metadataCache)
    wipe(metadataCacheOrder)
    metadataCacheHead = 1
    if ns._toyItemIDToSourceIndexCache then ns._toyItemIDToSourceIndexCache.map = nil end
end

---Get uncollected mounts (UNIFIED: collectionStore-first, scan if empty). Plans sadece uncollected gösterir.
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected mounts {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedMounts(searchText, limit)
    searchText = (searchText or ""):lower()

    local store = collectionStore.mount
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for mountID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(mountID))
                if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                    local meta
                    if d.icon or d.source then
                        meta = { id = mountID, name = d.name, icon = d.icon, source = d.source, description = d.description, creatureDisplayID = d.creatureDisplayID, isCollected = false }
                    else
                        meta = self:ResolveCollectionMetadata("mount", mountID)
                        if meta then meta.isCollected = false end
                    end
                    if meta then
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then return results end
                    end
                end
            end
        end
        return results
    end

    return {}
end

---Get uncollected pets (UNIFIED: collectionStore-first). Plans sadece uncollected gösterir.
function WarbandNexus:GetUncollectedPets(searchText, limit)
    searchText = (searchText or ""):lower()
    local store = collectionStore.pet
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for petID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(petID))
                if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                    local meta
                    if d.icon or d.source then
                        meta = { id = petID, name = d.name, icon = d.icon, source = d.source, description = d.description, creatureDisplayID = d.creatureDisplayID, isCollected = false }
                    else
                        meta = self:ResolveCollectionMetadata("pet", petID)
                        if meta then meta.isCollected = false end
                    end
                    if meta then
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then return results end
                    end
                end
            end
        end
        return results
    end

    return {}
end

---Get uncollected toys (UNIFIED: collectionStore-first). Plans sadece uncollected gösterir.
---When store has fallback source ("Toy Collection"/"Toy Box"), re-resolves from tooltip so Plans shows correct source.
function WarbandNexus:GetUncollectedToys(searchText, limit)
    searchText = (searchText or ""):lower()
    local store = collectionStore.toy
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for toyID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(toyID))
                if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                    local meta
                    local sourceOk = self:IsReliableToySource(d.source)
                    if (d.icon or d.source) and sourceOk then
                        meta = { id = toyID, name = d.name, icon = d.icon, source = d.source, description = d.description, isCollected = false }
                    else
                        meta = self:ResolveCollectionMetadata("toy", toyID)
                        if meta then
                            meta.isCollected = false
                            meta.id = toyID
                        end
                    end
                    if meta then
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then return results end
                    end
                end
            end
        end
        return results
    end

    return {}
end


---Async achievement scanner (background scanning with coroutine)
---Scans all achievements and populates achievement cache
---NOTE: Titles are now scanned separately via Title API
function WarbandNexus:ScanAchievementsAsync()
    -- Prevent duplicate scans
    if activeCoroutines["achievements"] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Achievement scan already in progress")
        return
    end
    
    -- CRITICAL FIX: Use separate lastScan timestamp for achievements
    -- Don't share with mount/pet/toy (they update global lastScan)
    local lastAchievementScan = collectionCache.lastAchievementScan or 0
    local timeSinceLastScan = time() - lastAchievementScan
    
    -- Validate timestamp (prevent negative values from corrupted data)
    if timeSinceLastScan < 0 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Invalid lastAchievementScan timestamp detected, forcing scan")
        timeSinceLastScan = math.huge  -- Force scan
    end
    
    -- Check cooldown (5 minutes)
    if timeSinceLastScan < 300 then
    DebugPrint(string.format("|cffffcc00[WN CollectionService]|r Achievement scan skipped (last scan %.0f seconds ago)", timeSinceLastScan))
        return
    end
    
    DebugPrint("|cff9370DB[WN CollectionService]|r Starting async achievement scan...")
    
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
    local scannedCount = 0
    local totalEstimated = 5000  -- Rough estimate for progress bar
    local lastProgressUpdate = 0  -- Throttle progress events
    local lastYield = debugprofilestop()  -- Track time since last yield
    
    local function scanCoroutine()
        collectionCache.uncollected.achievement = {}
        collectionCache.completed = collectionCache.completed or {}
        collectionCache.completed.achievement = {}

        local categoryList = GetCategoryList()
        if not categoryList or #categoryList == 0 then
    DebugPrint("|cffff0000[WN CollectionService]|r GetCategoryList() returned no categories")
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
                            
                            -- CRITICAL: Also update PlansLoadingState for UI (achievement uses PlansLoadingState)
                            if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
                                ns.PlansLoadingState.achievement.loadingProgress = progress
                                ns.PlansLoadingState.achievement.currentStage = string.format("Scanning Achievements... (%d/%d)", scannedCount, totalEstimated)
                            end
                            
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
                    
                    if not success or not id or not name then
                        -- Yield and continue
                    else
                        local rewardItemID, rewardTitle
                        local rewardSuccess, item, title = pcall(GetAchievementReward, id)
                        if rewardSuccess then
                            if type(item) == "number" then rewardItemID = item end
                            if type(title) == "string" and title ~= "" then
                                rewardTitle = title
                            elseif type(item) == "string" and item ~= "" then
                                rewardTitle = item
                            end
                        end

                        local displayName = (name and name ~= "") and name or ("ID:" .. tostring(id))
                        local record = {
                            id = id,
                            name = displayName,
                            icon = icon,
                            points = points,
                            description = description,
                            collected = completed,
                            categoryID = categoryID,
                            rewardItemID = rewardItemID,
                            rewardTitle = rewardTitle,
                        }
                        collectionStore.achievement[id] = record
                        if completed then
                            collectionCache.completed.achievement[id] = displayName
                        else
                            collectionCache.uncollected.achievement[id] = displayName
                            totalAchievements = totalAchievements + 1
                        end
                    end
                    
                    -- OPTIMIZATION: Yield every 100 achievements (improved from 20)
                    -- Check frame budget (don't exceed 8ms per frame)
                    if scannedCount % 100 == 0 then
                        -- Check if scan was aborted (tab switch)
                        if not activeCoroutines["achievements"] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Achievement scan aborted")
                            if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
                                ns.PlansLoadingState.achievement.isLoading = false
                            end
                            return  -- Exit coroutine gracefully
                        end
                        
                        local timeSinceYield = debugprofilestop() - lastYield
                        -- If we've used more than 8ms, yield immediately
                        if timeSinceYield >= 8 then
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
        
        -- CRITICAL: Update PlansLoadingState for UI (achievement uses PlansLoadingState, not CollectionLoadingState)
        if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
            ns.PlansLoadingState.achievement.isLoading = false
            ns.PlansLoadingState.achievement.loadingProgress = 100
            ns.PlansLoadingState.achievement.currentStage = "Complete!"
        end
        
    DebugPrint(string.format("|cff00ff00[WN CollectionService]|r Achievement scan complete: %d achievements (%.2fs)", 
            totalAchievements, elapsed))
        
        -- Fire completion event
        self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, {
            category = "achievement",
            totalAchievements = totalAchievements,
            elapsed = elapsed,
        })
        
        -- UI refreshes via WN_COLLECTION_SCAN_COMPLETE listener in UI.lua (event-driven).
        
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
    DebugPrint("|cffff0000[WN CollectionService ERROR]|r Achievement scan failed: " .. tostring(err))
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

---Get uncollected achievements (UNIFIED: collectionStore-first). Plans sadece uncollected gösterir.
function WarbandNexus:GetUncollectedAchievements(searchText, limit)
    searchText = (searchText or ""):lower()
    local store = collectionStore.achievement
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for achID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(achID))
                if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                    local meta
                    if d.icon or d.points then
                        meta = { id = achID, name = d.name, icon = d.icon, points = d.points, description = d.description, isCollected = false, categoryID = d.categoryID }
                    else
                        meta = self:ResolveCollectionMetadata("achievement", achID)
                        if meta then meta.id = achID; meta.isCollected = false end
                    end
                    if meta and not meta.categoryID and GetAchievementCategory then
                        meta.categoryID = GetAchievementCategory(achID)
                    end
                    if meta then
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then return results end
                    end
                end
            end
        end
        return results
    end

    return {}
end

---Get completed achievements (UNIFIED: collectionStore-first). Collections sadece collected gösterir.
function WarbandNexus:GetCompletedAchievements(searchText, limit)
    searchText = (searchText or ""):lower()
    local store = collectionStore.achievement
    local hasData = store and next(store) ~= nil

    if not hasData then
        if collectionCache.uncollected.achievement and next(collectionCache.uncollected.achievement) then
            return {}
        end
        return self:GetUncollectedAchievements(searchText, 0)
    end

    local results = {}
    local count = 0
    for achID, d in pairs(store) do
        if d and d.collected == true then
            local name = d.name or ("ID:" .. tostring(achID))
            if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                local meta
                if d.icon or d.points then
                    meta = { id = achID, name = d.name, icon = d.icon, points = d.points, description = d.description, isCollected = true, categoryID = d.categoryID }
                else
                    meta = self:ResolveCollectionMetadata("achievement", achID)
                    if meta then meta.id = achID; meta.isCollected = true end
                end
                if meta and not meta.categoryID and GetAchievementCategory then
                    meta.categoryID = GetAchievementCategory(achID)
                end
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then return results end
                end
            end
        end
    end
    return results
end

---Get uncollected illusions (UNIFIED: collectionStore-first). Plans sadece uncollected gösterir.
function WarbandNexus:GetUncollectedIllusions(searchText, limit)
    searchText = (searchText or ""):lower()
    local store = collectionStore.illusion
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for illusionID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(illusionID))
                if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                    local meta = (d.icon or d.source) and d or self:ResolveCollectionMetadata("illusion", illusionID)
                    if meta then
                        meta = { id = illusionID, name = meta.name or name, icon = meta.icon, source = meta.source, isCollected = false }
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then return results end
                    end
                end
            end
        end
        return results
    end

    return {}
end


---Get uncollected titles (UNIFIED: collectionStore-first). Plans sadece uncollected gösterir.
function WarbandNexus:GetUncollectedTitles(searchText, limit)
    searchText = (searchText or ""):lower()
    local store = collectionStore.title
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for titleID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or d.rewardText or ("ID:" .. tostring(titleID))
                if searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true)) then
                    local meta = (d.icon or d.rewardText) and d or self:ResolveCollectionMetadata("title", titleID)
                    if meta then
                        meta = { id = titleID, name = meta.name or meta.rewardText or name, icon = meta.icon, rewardText = meta.rewardText, isCollected = false }
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then return results end
                    end
                end
            end
        end
        return results
    end

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
        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(rewardItemID)
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
        local fromAchLabel = (ns.L and ns.L["PARSE_FROM_ACHIEVEMENT"]) or "From Achievement"
        itemData.description = (itemData.description or "") .. "\n\n|cff00ff00" .. fromAchLabel .. ":|r " .. achievementName
    end
    
    return itemData
end

-- ============================================================================
-- BAG SCAN SYSTEM (BAG_UPDATE_DELAYED LOOT DETECTION)
-- ============================================================================
-- Note: Helper functions (WasRecentlyNotified, MarkAsNotified) defined at top of file

-- Pending items: items detected in bag but GetItemInfo returned nil (data not loaded yet)
-- These are retried on the next scan to avoid losing notifications
local pendingRetryItems = {}  -- { [slotKey] = { itemID=n, hyperlink=s, retries=n } }

---Scan bags for new uncollected collectibles (mount/pet/toy items)
---@param specificBagIDs table|nil Optional set of bag IDs to scan {[bagID]=true}. nil = scan all 0-4.
---@return table|nil New collectible info {type, itemID, itemLink, itemName, icon}
local function ScanBagsForNewCollectibles(specificBagIDs)
    local currentBagContents = {}
    local newCollectibles = {}
    
    -- OPTIMIZATION: On first scan, populate previousBagContents without notifications
    if not isInitialized then
        for bagID = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots then
                for slotID = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if itemInfo and itemInfo.itemID then
                        local slotKey = bagID .. "_" .. slotID
                        currentBagContents[slotKey] = itemInfo.itemID
                    end
                end
            end
        end
        
        previousBagContents = currentBagContents
        isInitialized = true
        
        -- Count items (can't use # operator on dictionary)
        local itemCount = 0
        for _ in pairs(currentBagContents) do itemCount = itemCount + 1 end
        
    DebugPrint("|cff9370DB[WN CollectionService]|r Bag scan initialized (tracking " .. itemCount .. " items, no notifications)")
        return nil  -- No notifications on first scan
    end
    
    -- NORMAL SCAN: Detect NEW items only
    local scanAll = (specificBagIDs == nil)
    if scanAll then
    DebugPrint("|cff00ccff[WN BAG SCAN]|r Scanning ALL bags for NEW items...")
    else
        local bagList = {}
        for bagID in pairs(specificBagIDs) do bagList[#bagList + 1] = tostring(bagID) end
    DebugPrint("|cff00ccff[WN BAG SCAN]|r Scanning bags [" .. table.concat(bagList, ",") .. "] for NEW items...")
    end
    
    -- RETRY PENDING ITEMS: Items from previous scan where GetItemInfo returned nil
    for slotKey, pending in pairs(pendingRetryItems) do
        local collectibleInfo = WarbandNexus:CheckNewCollectible(pending.itemID, pending.hyperlink)
        if collectibleInfo then
    DebugPrint("|cff00ff00[WN BAG SCAN]|r ✓ RETRY SUCCESS: " .. collectibleInfo.type .. " - " .. collectibleInfo.name)
            table.insert(newCollectibles, {
                type = collectibleInfo.type,
                itemID = pending.itemID,
                collectibleID = collectibleInfo.id,
                itemLink = pending.hyperlink,
                itemName = collectibleInfo.name,
                icon = collectibleInfo.icon
            })
            pendingRetryItems[slotKey] = nil
        else
            pending.retries = (pending.retries or 0) + 1
            if pending.retries >= 5 then
                -- Give up after 5 retries (item is likely not a collectible)
    DebugPrint("|cff888888[WN BAG SCAN]|r Retry limit reached for itemID " .. pending.itemID .. ", giving up")
                pendingRetryItems[slotKey] = nil
            end
        end
    end
    
    -- Scan inventory bags: only changed bags if specificBagIDs provided, otherwise all 0-4
    for bagID = 0, 4 do
        if scanAll or specificBagIDs[bagID] then
            -- SCAN this bag: iterate all slots, detect new items
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots then
                for slotID = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if itemInfo and itemInfo.itemID then
                        local itemID = itemInfo.itemID
                        local slotKey = bagID .. "_" .. slotID
                        
                        currentBagContents[slotKey] = itemID
                        
                        if not previousBagContents[slotKey] or previousBagContents[slotKey] ~= itemID then
                            -- PRE-FILTER: GetItemInfoInstant is non-blocking, cache-only.
                            -- Collectibles can be classID 0 (Consumable - vendor toys/elixirs),
                            -- 15 (Miscellaneous - most mounts/toys), or 17 (Battle Pet).
                            local _, _, _, _, _, preClassID = GetItemInfoInstant(itemID)
                            
                            if preClassID and preClassID ~= 0 and preClassID ~= 15 and preClassID ~= 17 then
                                -- Not a collectible (weapon, armor, reagent, etc.) — skip
                            elseif not preClassID then
    DebugPrint("|cffffcc00[WN BAG SCAN]|r Item data not loaded for itemID " .. itemID .. " - queuing for retry")
                                if not pendingRetryItems[slotKey] then
                                    pendingRetryItems[slotKey] = {
                                        itemID = itemID,
                                        hyperlink = itemInfo.hyperlink,
                                        retries = 0
                                    }
                                end
                            else
    DebugPrint("|cff00ccff[WN BAG SCAN]|r NEW ITEM detected at " .. slotKey .. " - itemID: " .. itemID)
                                local collectibleInfo = WarbandNexus:CheckNewCollectible(itemID, itemInfo.hyperlink)
                                
                                if collectibleInfo then
    DebugPrint("|cff00ff00[WN BAG SCAN]|r ✓ Collectible detected: " .. collectibleInfo.type .. " - " .. collectibleInfo.name)
                                    
                                    table.insert(newCollectibles, {
                                        type = collectibleInfo.type,
                                        itemID = itemID,
                                        collectibleID = collectibleInfo.id,
                                        itemLink = itemInfo.hyperlink,
                                        itemName = collectibleInfo.name,
                                        icon = collectibleInfo.icon
                                    })
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Carry forward unchanged bags from previousBagContents
    -- (only needed when scanning specific bags, not all)
    if not scanAll then
        for slotKey, itemID in pairs(previousBagContents) do
            local bagID = tonumber(slotKey:match("^(%d+)"))
            if bagID and not specificBagIDs[bagID] then
                currentBagContents[slotKey] = itemID
            end
        end
    end
    
    -- Update previous state
    previousBagContents = currentBagContents
    
    local itemCount = 0
    for _ in pairs(currentBagContents) do itemCount = itemCount + 1 end
    local pendingCount = 0
    for _ in pairs(pendingRetryItems) do pendingCount = pendingCount + 1 end
    DebugPrint("|cff00ccff[WN BAG SCAN]|r Scan complete. Tracking " .. itemCount .. " items, found " .. #newCollectibles .. " collectibles, " .. pendingCount .. " pending retry")
    
    -- If there are pending items, schedule a retry after a reasonable delay
    if pendingCount > 0 then
        C_Timer.After(2.0, function()
            if WarbandNexus.OnBagUpdateForCollectibles then
                WarbandNexus:OnBagUpdateForCollectibles()
            end
        end)
    end
    
    return #newCollectibles > 0 and newCollectibles or nil
end

---Handle BAG_UPDATE_DELAYED event (detects new collectible items in bags)
---Throttled: safety net against rapid calls (debounce in raw frame handles coalescing)
local lastCollectibleScanTime = 0
local COLLECTIBLE_SCAN_THROTTLE = 0.3

function WarbandNexus:OnBagUpdateForCollectibles(specificBagIDs)
    local now = GetTime()
    if (now - lastCollectibleScanTime) < COLLECTIBLE_SCAN_THROTTLE then
        return  -- Skip: too soon since last scan
    end
    lastCollectibleScanTime = now
    
    DebugPrint("|cff00ccff[WN BAG SCAN]|r OnBagUpdateForCollectibles triggered")
    local newCollectibles = ScanBagsForNewCollectibles(specificBagIDs)
    
    if newCollectibles then
    DebugPrint("|cff00ccff[WN BAG SCAN]|r Found " .. #newCollectibles .. " new collectible(s)")
        for _, collectible in ipairs(newCollectibles) do
            -- LAYER 1: Quick name-based debounce (1-2s) - Prevents rapid-fire duplicates
            if not WasRecentlyShownByName(collectible.itemName) then
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW " .. string.upper(collectible.type) .. " IN BAG: " .. collectible.itemName)
                
                -- LAYER 2: Mark as bag-detected (PERMANENT - survives reload)
                MarkAsDetectedInBag(collectible.type, collectible.collectibleID)
                
                -- LAYER 3: Mark with short-term cooldown (5s, for same-session duplicates)
                MarkAsNotified(collectible.type, collectible.collectibleID)
                
                -- LAYER 4: Mark by name (2s, prevents same-name duplicates)
                MarkAsShownByName(collectible.itemName)
                
                -- LAYER 5: For item-based pet fallback (no speciesID), mark name with longer window
                -- This prevents double notification when NEW_PET_ADDED fires later on right-click
                if collectible.type == "pet" and collectible.itemID == collectible.collectibleID then
                    RingBufferAdd(recentNotifications, "petname:" .. collectible.itemName, BAG_PET_NAME_COOLDOWN)
                end
                
                -- LAYER 6: Persistent dedup (survives logout) — prevents re-notification on future logins
                MarkAsPermanentlyNotified(collectible.type, collectible.collectibleID)
                
                -- Fire WN_COLLECTIBLE_OBTAINED event
                if self.SendMessage then
                    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = collectible.type,
                        id = collectible.collectibleID,
                        name = collectible.itemName,
                        icon = collectible.icon
                    })
                end
            else
    DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. collectible.itemName)
            end
        end
    else
    DebugPrint("|cff888888[WN BAG SCAN]|r No new collectibles found")
    end
end

-- ============================================================================
-- INDEPENDENT BAG SCAN EVENT LISTENER (Self-Contained)
-- ============================================================================
--[[
    CollectionService owns its own BAG_UPDATE_DELAYED listener via a raw frame.
    This decouples collectible detection from ItemsCacheService, ensuring:
    
    1. Bag scan runs regardless of items module enabled/disabled
    2. Bag scan runs regardless of character tracking state
    3. No AceEvent single-handler conflicts (raw frame = independent event stream)
    4. Self-contained system: CollectionService is the SOLE owner of bag-based
       collectible detection. No other module needs to call OnBagUpdateForCollectibles.
    
    ARCHITECTURE: Two-path collectible detection system:
    
      Path 1 — BAG SCAN (this listener):
        Trigger: BAG_UPDATE tracks changed bagIDs → BAG_UPDATE_DELAYED → 0.3s debounce
                 → ScanBagsForNewCollectibles(changedBagIDs)
        Detects: Uncollected mount/pet/toy items when they land in bags
        Sources: Vendor purchase, trade, loot, mail, quest reward (item-based)
        Optimization: Only scans bags that actually changed, not all 0-4
    
      Path 2 — BLIZZARD COLLECTION EVENTS (registered above at file scope):
        Trigger: NEW_MOUNT_ADDED / NEW_PET_ADDED / NEW_TOY_ADDED
        Detects: Collectibles when they are learned (added to collection)
        Sources: Achievement rewards, quest rewards (auto-learn), right-click use
    
      Multi-layer dedup prevents double notifications when both paths fire
      for the same collectible (e.g., item lands in bag → user right-clicks to learn).
]]
do
    local bagScanFrame = CreateFrame("Frame")
    local bagScanTimer = nil
    local BAG_SCAN_DEBOUNCE = 0.3  -- 300ms debounce: BAG_UPDATE_DELAYED is already WoW's "settled" signal
    local baselineInitialized = false
    local changedBagIDs = {}       -- Tracks which bags changed since last scan {[bagID]=true}
    local suppressUntil = 0        -- Suppress BAG_UPDATE_DELAYED until this GetTime() value
    
    bagScanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bagScanFrame:RegisterEvent("BAG_UPDATE")           -- Track which specific bags changed
    bagScanFrame:RegisterEvent("BAG_UPDATE_DELAYED")   -- "Settled" signal: trigger scan
    
    bagScanFrame:SetScript("OnEvent", function(self, event, arg1)
        if event == "PLAYER_ENTERING_WORLD" then
            -- Initialize bag baseline on first world entry.
            -- The first call to ScanBagsForNewCollectibles populates previousBagContents
            -- without generating notifications (isInitialized = false guard inside).
            if not baselineInitialized then
                baselineInitialized = true
                if WarbandNexus and WarbandNexus.OnBagUpdateForCollectibles then
                    WarbandNexus:OnBagUpdateForCollectibles()  -- nil = scan all (baseline)
                end
                -- Suppress the next BAG_UPDATE_DELAYED for 2 seconds after baseline.
                -- Login always fires BAG_UPDATE_DELAYED shortly after PLAYER_ENTERING_WORLD,
                -- which would re-scan all 116+ slots and find 0 changes (waste).
                suppressUntil = GetTime() + 2.0
                DebugPrint("|cff9370DB[WN CollectionService]|r Bag scan baseline initialized (PLAYER_ENTERING_WORLD)")
            end
            return
        end
        
        if event == "BAG_UPDATE" then
            -- Track which bag changed. arg1 = bagID.
            -- Only care about inventory bags (0-4) for collectible detection.
            local bagID = arg1
            if bagID and bagID >= 0 and bagID <= 4 then
                changedBagIDs[bagID] = true
            end
            return
        end
        
        -- BAG_UPDATE_DELAYED: Debounce rapid fires into a single scan.
        if not baselineInitialized then return end
        
        -- Suppress post-baseline duplicate scan
        if GetTime() < suppressUntil then
            wipe(changedBagIDs)
            return
        end
        
        -- Skip if no inventory bags have changed since last scan.
        -- changedBagIDs may also accumulate between now and timer callback,
        -- so check again inside the callback.
        local hasInventoryChange = false
        for _ in pairs(changedBagIDs) do
            hasInventoryChange = true
            break
        end
        
        if not hasInventoryChange then
            return  -- No inventory bags changed (bank-only update, etc.)
        end
        
        if bagScanTimer then
            bagScanTimer:Cancel()
        end
        
        -- Snapshot at TIMER FIRE time (not now). This lets BAG_UPDATE events
        -- that arrive between BAG_UPDATE_DELAYED and the timer callback
        -- accumulate into the same scan batch. Without this, multi-item loots
        -- (rare kills, junk opens) cause 2-3 separate scans instead of 1.
        bagScanTimer = C_Timer.NewTimer(BAG_SCAN_DEBOUNCE, function()
            bagScanTimer = nil
            -- Snapshot and clear at callback time
            local bagsToScan = {}
            local hasBags = false
            for bagID in pairs(changedBagIDs) do
                bagsToScan[bagID] = true
                hasBags = true
            end
            wipe(changedBagIDs)
            
            if hasBags and WarbandNexus and WarbandNexus.OnBagUpdateForCollectibles then
                WarbandNexus:OnBagUpdateForCollectibles(bagsToScan)
            end
        end)
    end)
end

-- ============================================================================
-- UNIFIED LOGIN-TIME COLLECTION SCAN
-- ============================================================================
--[[
    Single entry point for scanning all collection types at login.
    Runs sequentially (mount → pet → toy) with time-budgeted batching.
    Integrates with LoadingTracker for sync state display.
    Stores IDs + names in DB for search bar functionality.
]]

---Legacy: ScanAllCollectionsOnLogin — artık EnsureCollectionData kullan (core init'te tetiklenir)
function WarbandNexus:ScanAllCollectionsOnLogin()
    self:EnsureCollectionData()
end

-- Expose CollectionService reference for external modules
ns.CollectionService = ns.CollectionService or {}
ns.CollectionService.collectionCache = collectionCache

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Module loaded - verbose logging removed for normal users
