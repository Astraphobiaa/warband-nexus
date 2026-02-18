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

-- Debug print helper (only prints if debug mode enabled)
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print(...)  -- Use global print to avoid recursion
    end
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

-- uncollected: persisted to DB (minimal id->name after refactor). "all" cache removed (unused).
local collectionCache = {
    owned = {
        mounts = {},
        pets = {},
        toys = {}
    },
    uncollected = {
        mount = {}, pet = {}, toy = {},
        achievement = {}, title = {}, transmog = {}, illusion = {}
    },
    version = CACHE_VERSION,
    lastScan = time(),
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
    collectionCache.lastScan = dbCache.lastScan or 0
    collectionCache.lastAchievementScan = dbCache.lastAchievementScan or 0
    
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

---Save collection cache to DB (persist scan results)
---Called after scan completion to avoid re-scanning on reload
function WarbandNexus:SaveCollectionCache()
    if not self.db or not self.db.global then
    DebugPrint("|cffff0000[WN CollectionService ERROR]|r Cannot save cache: DB not initialized")
        return
    end

    self.db.global.collectionCache = {
        uncollected = collectionCache.uncollected,
        version = CACHE_VERSION,
        lastScan = collectionCache.lastScan,
        lastAchievementScan = collectionCache.lastAchievementScan or collectionCache.lastScan,
    }

    local mountCount, petCount, toyCount = 0, 0, 0
    for _ in pairs(collectionCache.uncollected.mount or {}) do mountCount = mountCount + 1 end
    for _ in pairs(collectionCache.uncollected.pet or {}) do petCount = petCount + 1 end
    for _ in pairs(collectionCache.uncollected.toy or {}) do toyCount = toyCount + 1 end
    DebugPrint(string.format("|cff00ff00[WN CollectionService]|r Saved cache to DB: %d mounts, %d pets, %d toys",
        mountCount, petCount, toyCount))
end

---Invalidate collection cache (mark for refresh)
---Called when collection data changes (e.g., new mount obtained)
function WarbandNexus:InvalidateCollectionCache()
    collectionCache.owned.mounts = {}
    collectionCache.owned.pets = {}
    collectionCache.owned.toys = {}
    for k in pairs(collectionCache.uncollected) do
        if type(collectionCache.uncollected[k]) == "table" then
            collectionCache.uncollected[k] = {}
        end
    end
    collectionCache.lastScan = 0
    DebugPrint("|cffffcc00[WN CollectionService]|r Collection cache invalidated (will refresh on next scan)")
end

---Remove collectible from uncollected cache (incremental update when player obtains it)
---This is called by event handlers when player collects a new mount/pet/toy
---@param collectionType string "mount", "pet", or "toy"
---@param id number mountID, speciesID, or itemID
function WarbandNexus:RemoveFromUncollected(collectionType, id)
    if not collectionCache.uncollected[collectionType] then
        return
    end

    local entry = collectionCache.uncollected[collectionType][id]
    if entry ~= nil then
        local itemName = (type(entry) == "string") and entry or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        collectionCache.uncollected[collectionType][id] = nil

        -- Update owned cache
        if collectionType == "mount" or collectionType == "pet" or collectionType == "toy" then
            local key = collectionType .. "s"
            if not collectionCache.owned[key] then
                collectionCache.owned[key] = {}
            end
            collectionCache.owned[key][id] = true
        end

        -- Persist to DB (incremental update)
        self:SaveCollectionCache()

        DebugPrint(string.format("|cff00ff00[WN CollectionService]|r INCREMENTAL UPDATE: Removed %s from uncollected %ss (now collected)",
                itemName, collectionType))
    end
end

-- Active coroutines for async scanning
local activeCoroutines = {}

-- ============================================================================
-- BLIZZARD_COLLECTIONS LOADER (required for full API data)
-- ============================================================================
-- C_MountJournal, C_PetJournal, C_ToyBox, and C_TransmogCollection depend on
-- Blizzard_Collections being loaded to return complete data (icons, source text).
-- Without it, APIs may return names but nil icons, or toy filters return 0 results.
local blizzardCollectionsLoaded = false

local function EnsureBlizzardCollectionsLoaded()
    if blizzardCollectionsLoaded then return end
    -- TAINT GUARD: LoadAddOn is a protected action; cannot call during combat
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

-- Expose for other modules (PlansManager, PlanCardFactory) via ns
ns.EnsureBlizzardCollectionsLoaded = EnsureBlizzardCollectionsLoaded

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
    
    -- LAYER 0: Persistent dedup — already notified in a previous session?
    if WasAlreadyNotified("mount", mountID) then
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: mount " .. mountID .. " (already notified)")
        return
    end
    
    local name, _, icon = C_MountJournal.GetMountInfoByID(mountID)
    -- Midnight 12.0: return values may be secret during instanced combat
    if issecretvalue then
        if name and issecretvalue(name) then name = nil end
        if icon and issecretvalue(icon) then icon = nil end
    end
    if not name then
        -- Mount data may not be loaded yet (or secret in Midnight) — retry (max 3 attempts)
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
    
    -- LAYER 1: Quick name-based debounce (1-2s)
    if WasRecentlyShownByName(name) then
    DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
        return
    end
    
    -- LAYER 2: Check if this mount was detected in bag scan (permanent block)
    if WasDetectedInBag("mount", mountID) then
    DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: mount " .. name .. " (detected in bag before, permanent block)")
        return
    end
    
    -- LAYER 3: Check short-term cooldown by ID (5s)
    if WasRecentlyNotified("mount", mountID) then
    DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: mount " .. name .. " (notified within 5s)")
        return
    end
    
    -- Update owned cache
    collectionCache.owned.mounts[mountID] = true
    
    -- Remove from uncollected cache if present
    self:RemoveFromUncollected("mount", mountID)
    
    -- Mark as notified (multi-layer)
    MarkAsNotified("mount", mountID)     -- By ID (5s)
    MarkAsShownByName(name)              -- By name (2s)
    MarkAsPermanentlyNotified("mount", mountID)  -- Persistent (survives logout)
    
    -- Fire notification event
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "mount",
        id = mountID,
        name = name,
        icon = icon
    })
    
    -- Invalidate collection cache so next UI open refreshes (owned list changed)
    self:InvalidateCollectionCache()
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW MOUNT: " .. name)
end

---Handle NEW_PET_ADDED event
---Fires when player learns a new battle pet
---@param petGUID string The pet GUID (e.g., "BattlePet-0-000013DED8E1")
---@param retryCount number|nil Internal retry counter
function WarbandNexus:OnNewPet(event, petGUID, retryCount)
    if not petGUID then return end
    retryCount = retryCount or 0
    
    -- NEW_PET_ADDED returns petGUID (string), not speciesID!
    -- Use C_PetJournal.GetPetInfoByPetID to convert petGUID -> speciesID
    local speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon = C_PetJournal.GetPetInfoByPetID(petGUID)
    -- Midnight 12.0: return values may be secret during instanced combat
    if issecretvalue then
        if speciesID and issecretvalue(speciesID) then speciesID = nil end
        if name and issecretvalue(name) then name = nil end
        if icon and issecretvalue(icon) then icon = nil end
    end
    
    if not speciesID or not name then
        -- Pet data may not be loaded yet (or secret in Midnight) — retry (max 3 attempts)
        if retryCount < 3 then
            DebugPrint("|cffffcc00[WN CollectionService]|r OnNewPet: Data not ready for petGUID=" .. tostring(petGUID) .. ", retry " .. (retryCount + 1) .. "/3")
            C_Timer.After(0.5, function()
                self:OnNewPet(event, petGUID, retryCount + 1)
            end)
        else
            DebugPrint("|cffff0000[WN CollectionService]|r OnNewPet: Data unavailable after 3 retries for petGUID=" .. tostring(petGUID))
        end
        return
    end
    
    -- LAYER 0: Persistent dedup — already notified in a previous session?
    if WasAlreadyNotified("pet", speciesID) then
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: pet " .. name .. " (already notified)")
        return
    end
    
    -- LAYER 1: Quick name-based debounce (1-2s) - Prevents rapid-fire duplicates from multiple events
    if WasRecentlyShownByName(name) then
    DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
        return
    end
    
    -- LAYER 2: Only notify if this is the FIRST pet of this species (0 → 1)
    -- Do NOT notify for 1/3 → 2/3 or any other duplicates
    local numOwned, limit = C_PetJournal.GetNumCollectedInfo(speciesID)
    -- Midnight 12.0: numOwned may be secret during instanced combat
    if issecretvalue and numOwned and issecretvalue(numOwned) then numOwned = nil end
    if numOwned and numOwned > 1 then
    DebugPrint("|cff888888[WN CollectionService]|r SKIP: " .. name .. " (" .. numOwned .. "/" .. (limit or 3) .. " owned) - not first acquisition")
        return
    end
    
    -- LAYER 3: Check if this pet was detected in bag scan (permanent block)
    if WasDetectedInBag("pet", speciesID) then
    DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. name .. " (detected in bag before, permanent block)")
        return
    end
    
    -- LAYER 3b: Check item-based bag detection (60s window)
    -- When GetPetInfoByItemID fails, bag scan uses item info and stores pet name here
    -- This prevents double notification when the pet is learned via right-click
    if RingBufferCheck(recentNotifications, "petname:" .. name) then
    DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. name .. " (item-based bag detection)")
        return
    end
    
    -- LAYER 4: Check short-term cooldown by ID (5s)
    if WasRecentlyNotified("pet", speciesID) then
    DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: pet " .. name .. " (notified within 5s)")
        return
    end
    
    -- Update owned cache
    collectionCache.owned.pets[speciesID] = true
    
    -- Remove from uncollected cache if present
    self:RemoveFromUncollected("pet", speciesID)
    
    -- Mark as notified (multi-layer)
    MarkAsNotified("pet", speciesID)        -- By ID (5s)
    MarkAsShownByName(name)                  -- By name (2s)
    MarkAsPermanentlyNotified("pet", speciesID)  -- Persistent (survives logout)
    
    -- Fire notification event
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "pet",
        id = speciesID,
        name = name,
        icon = icon
    })
    
    -- Invalidate collection cache so next UI open refreshes (owned list changed)
    self:InvalidateCollectionCache()
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW PET: " .. name .. " (speciesID: " .. speciesID .. ")")
end

---Handle NEW_TOY_ADDED event
---Fires when player learns a new toy
---@param itemID number The toy item ID
---@param _isFavorite any WoW payload (ignored)
---@param _retryCount number|nil Internal retry counter (only set by self-retry)
function WarbandNexus:OnNewToy(event, itemID, _isFavorite, _retryCount)
    if not itemID then return end
    -- _isFavorite comes from WoW's NEW_TOY_ADDED payload; _retryCount is only set by self-retry
    local retryCount = (type(_retryCount) == "number") and _retryCount or 0
    
    -- LAYER 0: Persistent dedup — already notified in a previous session?
    if WasAlreadyNotified("toy", itemID) then
        DebugPrint("|cff888888[WN CollectionService]|r ✓ PERMANENT DEDUP: toy " .. itemID .. " (already notified)")
        return
    end
    
    -- LAYER 1: Check if this toy was detected in bag scan (permanent block)
    if WasDetectedInBag("toy", itemID) then
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: toy " .. itemID .. " (detected in bag before, permanent block)")
        return
    end
    
    -- LAYER 2: Check short-term cooldown by ID (5s)
    if WasRecentlyNotified("toy", itemID) then
        DebugPrint("|cff888888[WN CollectionService]|r ✓ DUPLICATE BLOCKED: toy " .. itemID .. " (notified within 5s)")
        return
    end
    
    -- Toy APIs are sometimes delayed, use pcall for safety
    local success, name = pcall(GetItemInfo, itemID)
    if not success or not name then
        -- Retry after a short delay if item data not loaded yet (max 3 attempts)
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
    
    -- LAYER 3: Quick name-based debounce (1-2s) - Check AFTER getting name
    if WasRecentlyShownByName(name) then
        DebugPrint("|cffff8800[WN CollectionService]|r SKIP (name debounce): " .. name)
        return
    end
    
    local icon = GetItemIcon(itemID)
    
    -- Update owned cache
    collectionCache.owned.toys[itemID] = true
    
    -- Remove from uncollected cache if present
    self:RemoveFromUncollected("toy", itemID)
    
    -- Mark as notified (multi-layer)
    MarkAsNotified("toy", itemID)        -- By ID (5s)
    MarkAsShownByName(name)              -- By name (2s)
    MarkAsPermanentlyNotified("toy", itemID)  -- Persistent (survives logout)
    
    -- Fire notification event
    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
        type = "toy",
        id = itemID,
        name = name,
        icon = icon
    })
    
    -- Invalidate collection cache so next UI open refreshes (owned list changed)
    self:InvalidateCollectionCache()
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW TOY: " .. name)
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

-- Register real-time collection events
-- Bag scan handles ALL collectible detection (mount/pet/toy)
-- Real-time collection events: fire when mount/pet/toy is learned (from quests, drops, vendors, etc.)
-- Duplicate prevention: Multi-layer debounce (name, ID, bag-detection) prevents double notifications.
WarbandNexus:RegisterEvent("NEW_MOUNT_ADDED", "OnNewMount")
WarbandNexus:RegisterEvent("NEW_PET_ADDED", "OnNewPet")
WarbandNexus:RegisterEvent("NEW_TOY_ADDED", "OnNewToy")

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
    
    -- Fire collectible obtained notification for the completed achievement
    -- This shows a toast notification (gated by showLootNotifications in NotificationManager)
    local ok, _, achName, _, _, _, _, _, _, _, achIcon = pcall(GetAchievementInfo, achievementID)
    if not ok then achName = nil; achIcon = nil end
    -- Midnight 12.0: return values may be secret during instanced combat
    if issecretvalue then
        if achName and issecretvalue(achName) then achName = nil end
        if achIcon and issecretvalue(achIcon) then achIcon = nil end
    end
    if achName then
        MarkAsPermanentlyNotified("achievement", achievementID)
        self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
            type = "achievement",
            id = achievementID,
            name = achName,
            icon = achIcon
        })
    end
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
    
    local _, toyName, toyIcon = C_ToyBox.GetToyInfo(itemID)
    if not toyName then return nil end
    
    -- Check if already owned
    if PlayerHasToy and PlayerHasToy(itemID) then return nil end
    
    -- DUPLICATE PREVENTION
    if WasDetectedInBag("toy", itemID) then return nil end
    if WasRecentlyShownByName(toyName) then return nil end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW TOY DETECTED: " .. toyName .. " (ID: " .. itemID .. ")")
    return {
        type = "toy",
        id = itemID,
        name = toyName,
        icon = toyIcon or itemIcon
    }
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
                source = source or ((ns.L and ns.L["FALLBACK_UNKNOWN_SOURCE"]) or UNKNOWN or "Unknown"),
                sourceType = sourceType,
                description = description,
                collected = isCollected,
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
            
            return {
                id = speciesID,
                name = speciesName,
                icon = icon,
                source = source or ((ns.L and ns.L["FALLBACK_PET_COLLECTION"]) or "Pet Collection"),
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
            -- itemID is now passed directly from iterator (not an index)
            if not itemID then return nil end
            
            local _, name, icon = C_ToyBox.GetToyInfo(itemID)
            if not name then return nil end
            
            local hasToy = PlayerHasToy(itemID)
            
            -- Try to get source from tooltip (Toys don't have a dedicated source API)
            local sourceText = (ns.L and ns.L["FALLBACK_UNKNOWN_SOURCE"]) or UNKNOWN or "Unknown"
            if C_TooltipInfo and C_TooltipInfo.GetToyByItemID then
                local tooltipData = C_TooltipInfo.GetToyByItemID(itemID)
                if tooltipData and tooltipData.lines then
                    -- Search for source line in tooltip (Blizzard's Enum.TooltipDataLineType)
                    -- Line type 0 is the header, type 2 is typically source info
                    for _, line in ipairs(tooltipData.lines) do
                        if line.leftText and line.type == 2 then
                            sourceText = line.leftText
                            break
                        end
                    end
                    -- Fallback: Search by matching localized "Source:" pattern from locale
                    if sourceText == ((ns.L and ns.L["FALLBACK_UNKNOWN_SOURCE"]) or UNKNOWN or "Unknown") then
                        local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
                        local sourceLabelClean = sourceLabel:gsub("[:%s]+$", "")
                        for _, line in ipairs(tooltipData.lines) do
                            if line.leftText then
                                local text = line.leftText
                                if text:find(sourceLabelClean, 1, true) then
                                    sourceText = text:gsub("^" .. sourceLabelClean .. "[:%s]*", "")
                                    break
                                end
                            end
                        end
                    end
                end
            end
            
            -- Fallback: Use localized default
            if sourceText == ((ns.L and ns.L["FALLBACK_UNKNOWN_SOURCE"]) or UNKNOWN or "Unknown") then
                sourceText = (ns.L and ns.L["FALLBACK_TOY_COLLECTION"]) or "Toy Collection"
            end
            
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
    
    -- CRITICAL: Check if scan is needed (cache exists and recent)
    local cacheExists = collectionCache.uncollected[collectionType] and next(collectionCache.uncollected[collectionType]) ~= nil
    if cacheExists then
        local lastScan = collectionCache.lastScan or 0
        local timeSinceLastScan = time() - lastScan
        
        -- If cache exists and scan was recent (< 5 minutes), skip
        if timeSinceLastScan < 300 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Cache exists and recent for " .. tostring(collectionType) .. " (scanned " .. timeSinceLastScan .. "s ago), skipping scan")
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

        for i, item in ipairs(items) do
            local data = config.extract(item)

            if data and config.shouldInclude(data) then
                results[data.id] = (data.name and data.name ~= "") and data.name or ("ID:" .. tostring(data.id))
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
        
        -- Auto-refresh UI after scan complete (like achievement scan)
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
                local mainFrame = WarbandNexus.UI.mainFrame
                if mainFrame:IsShown() and mainFrame.currentTab == "plans" and WarbandNexus:IsStillOnTab("plans") then
    DebugPrint("|cff00ccff[WN CollectionService]|r Auto-refreshing UI after " .. collectionType .. " scan complete...")
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

---Resolve icon/source/description for a collection entry on demand. Uses session RAM cache; cleared on tab leave.
---@param collectionType string "mount", "pet", "toy", "achievement", "title", "illusion"
---@param id number
---@return table|nil { name, icon, source, description, ... } or nil if API fails
function WarbandNexus:ResolveCollectionMetadata(collectionType, id)
    if not id or not collectionType then return nil end
    local cacheKey = collectionType .. ":" .. tostring(id)
    if metadataCache[cacheKey] then
        return metadataCache[cacheKey]
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
        local name, spellID, icon = C_MountJournal.GetMountInfoByID(id)
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
        end
    elseif collectionType == "pet" then
        if not C_PetJournal or not C_PetJournal.GetPetInfoBySpeciesID then return nil end
        -- API: speciesName, speciesIcon, petType, companionID, tooltipSource, tooltipDescription
        local name, icon, _, _, source, description = C_PetJournal.GetPetInfoBySpeciesID(id)
        if name then
            icon = validIcon(icon)
            if not icon then usedFallbackIcon = true end
            meta = { name = name, icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01", source = source or "", description = description or "" }
        end
    elseif collectionType == "toy" then
        if not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
        -- API: itemID, toyName, icon, isFavorite, hasFanfare, itemQuality
        local _, name, icon = C_ToyBox.GetToyInfo(id)
        if name then
            icon = validIcon(icon)
            -- Fallback: item icon via C_Item.GetItemInfo
            if not icon then
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
                local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfoFn(id)
                icon = validIcon(itemTexture)
            end
            if not icon then usedFallbackIcon = true end
            -- Try to get source from tooltip (Toys have no dedicated source API)
            local sourceText = ""
            local tooltipData = nil
            -- Try toy-specific tooltip first, then generic item tooltip
            if C_TooltipInfo then
                if C_TooltipInfo.GetToyByItemID then
                    tooltipData = C_TooltipInfo.GetToyByItemID(id)
                end
                if (not tooltipData or not tooltipData.lines) and C_TooltipInfo.GetItemByID then
                    tooltipData = C_TooltipInfo.GetItemByID(id)
                end
            end
            if tooltipData and tooltipData.lines then
                -- Step 1: Search for source line by Blizzard type 2 (TooltipDataLineType)
                for _, line in ipairs(tooltipData.lines) do
                    if line.leftText and line.type == 2 then
                        sourceText = line.leftText
                        break
                    end
                end
                -- Step 2: Search for localized "Source:" pattern in any tooltip line
                if sourceText == "" then
                    local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
                    local sourceLabelClean = sourceLabel:gsub("[:%s]+$", "")
                    for _, line in ipairs(tooltipData.lines) do
                        if line.leftText and line.leftText:find(sourceLabelClean, 1, true) then
                            sourceText = line.leftText:gsub("^" .. sourceLabelClean .. "[:%s]*", "")
                            break
                        end
                    end
                end
                -- Step 3: Search for known source-type keywords in any tooltip line
                -- (many toys have "Drop:", "Vendor:", "Quest:" etc. without type==2 flag)
                if sourceText == "" then
                    local sourceKeywords = {
                        BATTLE_PET_SOURCE_1 or "Drop",
                        BATTLE_PET_SOURCE_3 or "Vendor",
                        BATTLE_PET_SOURCE_2 or "Quest",
                        BATTLE_PET_SOURCE_4 or "Profession",
                        BATTLE_PET_SOURCE_7 or "World Event",
                        BATTLE_PET_SOURCE_8 or "Promotion",
                        (ns.L and ns.L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",
                        (ns.L and ns.L["SOURCE_TYPE_TREASURE"]) or "Treasure",
                    }
                    for _, line in ipairs(tooltipData.lines) do
                        if line.leftText and line.leftText ~= "" then
                            for _, keyword in ipairs(sourceKeywords) do
                                if line.leftText:find(keyword, 1, true) then
                                    sourceText = line.leftText
                                    break
                                end
                            end
                            if sourceText ~= "" then break end
                        end
                    end
                end
            end
            -- Step 4: Final fallback
            if sourceText == "" then
                sourceText = (ns.L and ns.L["FALLBACK_TOY_COLLECTION"]) or "Toy Box"
            end
            meta = { name = name, icon = icon or "Interface\\Icons\\INV_Misc_Toy_07", source = sourceText, description = "" }
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
        meta.collected = false
        meta.isCollected = false
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
end

---Get uncollected mounts (UNIFIED: cache-first, scan if empty). Filters by name from SV; resolves metadata on demand.
---@param searchText string|nil Optional search filter
---@param limit number|nil Optional result limit
---@return table Array of uncollected mounts {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedMounts(searchText, limit)
    searchText = (searchText or ""):lower()

    local cache = collectionCache.uncollected.mount
    local cacheExists = cache and next(cache) ~= nil

    if cacheExists then
        local cachedResults = {}
        local count = 0
        for mountID, name in pairs(cache) do
            if name and (searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true))) then
                local meta = self:ResolveCollectionMetadata("mount", mountID)
                if meta then
                    table.insert(cachedResults, meta)
                    count = count + 1
                    if limit and count >= limit then
                        return cachedResults
                    end
                end
            end
        end
        -- Cache exists: return results even if empty (don't re-scan)
        return cachedResults
    end

    -- NO CACHE: Trigger unified background scan (ONCE)
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.mount then
        ns.PlansLoadingState.mount = { isLoading = false, loader = nil }
    end
    ns.PlansLoadingState.mount.isLoading = true
    ns.PlansLoadingState.mount.loadingProgress = 0
    ns.PlansLoadingState.mount.currentStage = "Preparing..."
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then
            self:ScanCollection("mount")
        end
    end)
    return {}
end

---Get uncollected pets (UNIFIED: cache-first, scan if empty). Filters by name; resolves metadata on demand.
function WarbandNexus:GetUncollectedPets(searchText, limit)
    searchText = (searchText or ""):lower()
    local cache = collectionCache.uncollected.pet
    local cacheExists = cache and next(cache) ~= nil

    if cacheExists then
        local cachedResults = {}
        local count = 0
        for petID, name in pairs(cache) do
            if name and (searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true))) then
                local meta = self:ResolveCollectionMetadata("pet", petID)
                if meta then
                    table.insert(cachedResults, meta)
                    count = count + 1
                    if limit and count >= limit then return cachedResults end
                end
            end
        end
        -- Cache exists: return results even if empty (don't re-scan)
        return cachedResults
    end

    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.pet then ns.PlansLoadingState.pet = { isLoading = false, loader = nil } end
    ns.PlansLoadingState.pet.isLoading = true
    ns.PlansLoadingState.pet.loadingProgress = 0
    ns.PlansLoadingState.pet.currentStage = "Preparing..."
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then self:ScanCollection("pet") end
    end)
    return {}
end

---Get uncollected toys (UNIFIED: cache-first, scan if empty). Filters by name; resolves metadata on demand.
function WarbandNexus:GetUncollectedToys(searchText, limit)
    searchText = (searchText or ""):lower()
    local cache = collectionCache.uncollected.toy
    local cacheExists = cache and next(cache) ~= nil

    if cacheExists then
        local cachedResults = {}
        local count = 0
        for toyID, name in pairs(cache) do
            if name and (searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true))) then
                local meta = self:ResolveCollectionMetadata("toy", toyID)
                if meta then
                    table.insert(cachedResults, meta)
                    count = count + 1
                    if limit and count >= limit then return cachedResults end
                end
            end
        end
        -- Cache exists: return results even if empty (don't re-scan)
        return cachedResults
    end

    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.toy then ns.PlansLoadingState.toy = { isLoading = false, loader = nil } end
    ns.PlansLoadingState.toy.isLoading = true
    ns.PlansLoadingState.toy.loadingProgress = 0
    ns.PlansLoadingState.toy.currentStage = "Preparing..."
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then self:ScanCollection("toy") end
    end)
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

                        if not completed then
                            collectionCache.uncollected.achievement[id] = (name and name ~= "") and name or ("ID:" .. tostring(id))
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
        
        -- Force UI refresh after short delay (ensure UI is updated)
        C_Timer.After(0.5, function()
            if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
                local mainFrame = WarbandNexus.UI.mainFrame
                if mainFrame:IsShown() and mainFrame.currentTab == "plans" and WarbandNexus:IsStillOnTab("plans") then
    DebugPrint("|cff00ccff[WN CollectionService]|r Auto-refreshing UI after scan complete...")
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

---Get uncollected achievements with search and limit. Filters by name; resolves metadata on demand.
function WarbandNexus:GetUncollectedAchievements(searchText, limit)
    searchText = (searchText or ""):lower()
    local cache = collectionCache.uncollected.achievement
    local cacheExists = cache and next(cache) ~= nil

    if cacheExists then
        local cachedResults = {}
        local count = 0
        for achievementID, name in pairs(cache) do
            if name and (searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true))) then
                local meta = self:ResolveCollectionMetadata("achievement", achievementID)
                if meta then
                    table.insert(cachedResults, meta)
                    count = count + 1
                    if limit and count >= limit then return cachedResults end
                end
            end
        end
        return cachedResults
    end

    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.achievement then ns.PlansLoadingState.achievement = { isLoading = false, loader = nil } end
    ns.PlansLoadingState.achievement.isLoading = true
    ns.PlansLoadingState.achievement.loadingProgress = 0
    ns.PlansLoadingState.achievement.currentStage = "Preparing..."
    C_Timer.After(0.1, function()
        if self and self.ScanAchievementsAsync then self:ScanAchievementsAsync() end
    end)
    return {}
end

---Get uncollected illusions. Filters by name; resolves metadata on demand.
function WarbandNexus:GetUncollectedIllusions(searchText, limit)
    searchText = (searchText or ""):lower()
    local cache = collectionCache.uncollected.illusion
    local cacheExists = cache and next(cache) ~= nil

    if cacheExists then
        local cachedResults = {}
        local count = 0
        for illusionID, name in pairs(cache) do
            if name and (searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true))) then
                local meta = self:ResolveCollectionMetadata("illusion", illusionID)
                if meta then
                    table.insert(cachedResults, meta)
                    count = count + 1
                    if limit and count >= limit then return cachedResults end
                end
            end
        end
        if #cachedResults > 0 then return cachedResults end
    end

    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.illusion then ns.PlansLoadingState.illusion = { isLoading = false, loader = nil } end
    ns.PlansLoadingState.illusion.isLoading = true
    ns.PlansLoadingState.illusion.loadingProgress = 0
    ns.PlansLoadingState.illusion.currentStage = "Preparing..."
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then self:ScanCollection("illusion") end
    end)
    return {}
end


---Get uncollected titles. Filters by name; resolves metadata on demand.
function WarbandNexus:GetUncollectedTitles(searchText, limit)
    searchText = (searchText or ""):lower()
    local cache = collectionCache.uncollected.title
    local cacheExists = cache and next(cache) ~= nil

    if cacheExists then
        local cachedResults = {}
        local count = 0
        for titleID, name in pairs(cache) do
            if name and (searchText == "" or (type(name) == "string" and name:lower():find(searchText, 1, true))) then
                local meta = self:ResolveCollectionMetadata("title", titleID)
                if meta then
                    table.insert(cachedResults, meta)
                    count = count + 1
                    if limit and count >= limit then return cachedResults end
                end
            end
        end
        if #cachedResults > 0 then return cachedResults end
    end

    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.title then ns.PlansLoadingState.title = { isLoading = false, loader = nil } end
    ns.PlansLoadingState.title.isLoading = true
    ns.PlansLoadingState.title.loadingProgress = 0
    ns.PlansLoadingState.title.currentStage = "Preparing..."
    C_Timer.After(0.1, function()
        if self and self.ScanCollection then self:ScanCollection("title") end
    end)
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
-- INITIALIZATION
-- ============================================================================

-- Module loaded - verbose logging removed for normal users
