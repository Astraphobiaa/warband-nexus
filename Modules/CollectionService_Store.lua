--[[ CollectionService persistence + owned cache build (ops split) ]]
local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local RT = assert(ns.CollectionServiceRT, 'CollectionService_Store: load CollectionService.lua first')
local CACHE_VERSION = RT.CACHE_VERSION
local DebugPrint = RT.DebugPrint
local time = RT.time
local issecretvalue = issecretvalue
local C_Timer = C_Timer
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local C_ToyBox = C_ToyBox
local CanHydrateOwnedCacheFromStore = RT.CanHydrateOwnedCacheFromStore
local HydrateOwnedCacheFromStore = RT.HydrateOwnedCacheFromStore

local function getDeferredTimer() return RT.deferredStoreSaveTimer end
local function setDeferredTimer(t) RT.deferredStoreSaveTimer = t end

-- Slim persisted rows (2026-10-22). SV keeps only what cannot be read back from the client:
-- collected flags, achievement points (summed over every row by SumAchievementJournalPointsMax)
-- and the journal-filter source indices (rebuilt only by a filter sweep, not per id).
-- Display metadata (name, icon, source text, ...) lives in RAM: values a scan already produced
-- move into derivedByField, anything else resolves once per id via RT.ResolveStoreRowDisplay.
-- Toys are already id+name; illusions are not slimmed (GetIllusionStrings is not a proven sync read).
local STORE_PERSIST_FIELDS = {
    mount = { id = true, collected = true, sourceType = true },
    pet = { id = true, collected = true, sourceTypeIndex = true },
    achievement = { id = true, collected = true, points = true },
    title = { id = true, collected = true },
}
-- Fields a reader may ask for that the API resolver returns; other missing keys stay nil
-- (e.g. SumAchievementJournalPointsMax probes isGuild, which no writer ever stored).
local STORE_DERIVED_FIELDS = {
    mount = { name = true, icon = true, spellID = true, source = true, description = true, creatureDisplayID = true,
        shouldHideOnChar = true, isFactionSpecific = true, faction = true, isSteadyFlight = true },
    pet = { name = true, icon = true, source = true, description = true, petType = true, creatureDisplayID = true,
        obtainable = true },
    achievement = { name = true, icon = true, description = true, categoryID = true, rewardItemID = true, rewardTitle = true },
    title = { name = true, titleString = true, playerTitle = true, iconAtlas = true, source = true, type = true },
}
ns.CollectionStorePersistFields = STORE_PERSIST_FIELDS

local derivedByField = {}   -- [category][field][id] = value (RAM only)
local derivedResolved = {}  -- [category][id] = true once the API resolver filled this id
local storeRowMeta = {}

local function SetDerived(category, id, key, value, overwrite)
    local byField = derivedByField[category][key]
    if not byField then
        byField = {}
        derivedByField[category][key] = byField
    end
    if overwrite or byField[id] == nil then
        byField[id] = value
    end
end

---Fill the RAM display fields of one id from the API resolver; scan values already there win.
---@return boolean resolved
local function ResolveDerivedRow(category, id)
    local data = RT.ResolveStoreRowDisplay and RT.ResolveStoreRowDisplay(category, id)
    if type(data) ~= "table" then return false end
    local keep = STORE_PERSIST_FIELDS[category]
    for k, v in pairs(data) do
        if not keep[k] then SetDerived(category, id, k, v, false) end
    end
    derivedResolved[category][id] = true
    return true
end

for category, keep in pairs(STORE_PERSIST_FIELDS) do
    derivedByField[category] = {}
    derivedResolved[category] = {}
    local derived = STORE_DERIVED_FIELDS[category]
    storeRowMeta[category] = {
        __index = function(row, key)
            if keep[key] then return nil end
            local id = rawget(row, "id")
            if id == nil then return nil end
            local byField = derivedByField[category][key]
            local value = byField and byField[id]
            if value ~= nil or not derived[key] or derivedResolved[category][id] then
                return value
            end
            if ResolveDerivedRow(category, id) then
                byField = derivedByField[category][key]
                value = byField and byField[id]
            end
            -- Unresolved (API not ready / secret): same placeholder the list readers print; retried next read.
            if value == nil and key == "name" and not derivedResolved[category][id] then
                return "ID:" .. tostring(id)
            end
            return value
        end,
        -- Writers that set display fields on a slim row keep them in RAM, never in SV.
        __newindex = function(row, key, value)
            local id = rawget(row, "id")
            if keep[key] or id == nil then
                rawset(row, key, value)
            else
                SetDerived(category, id, key, value, true)
            end
        end,
    }
end

---Move non-persisted fields of every row into RAM and attach the lazy row metatable.
---Rows already carrying the metatable are slim (its __newindex keeps them so) and are skipped.
---@param category string
---@param map table|nil id -> row
function RT.SlimCollectionStoreRows(category, map)
    local keep = STORE_PERSIST_FIELDS[category]
    local meta = storeRowMeta[category]
    if not keep or type(map) ~= "table" then return end
    for id, row in pairs(map) do
        if type(row) == "table" and getmetatable(row) ~= meta then
            if rawget(row, "id") == nil then rawset(row, "id", id) end
            local rowID = rawget(row, "id")
            -- A row without the metatable is a fresh scan/event result for this id: it replaces
            -- what RAM held, so fields it leaves out resolve again instead of keeping old values.
            for field, byField in pairs(derivedByField[category]) do
                if rawget(row, field) == nil then byField[rowID] = nil end
            end
            derivedResolved[category][rowID] = nil
            for k, v in pairs(row) do
                if not keep[k] then
                    SetDerived(category, rowID, k, v, true)
                    rawset(row, k, nil)
                end
            end
            setmetatable(row, meta)
        end
    end
end

-- Display-field warm-up (2026-10-22). Slim rows resolve display fields on first read, so the first
-- achievement list query read ~12k names in one frame (three API calls each). After the store loads,
-- resolve rows ahead in time-budgeted slices; a query that comes first still resolves on demand.
local WARM_BUDGET_MS = 2
local WARM_COMBAT_RETRY_SEC = 5
local warmGen = 0

---@param categories string[] slim categories, warmed in this order
function RT.WarmStoreRowDisplay(categories)
    warmGen = warmGen + 1
    local gen = warmGen
    local queue = {}
    for i = 1, #categories do
        local category = categories[i]
        local map = RT.collectionStore[category]
        if STORE_PERSIST_FIELDS[category] and type(map) == "table" then
            for id in pairs(map) do
                queue[#queue + 1] = category
                queue[#queue + 1] = id
            end
        end
    end
    local pos = 1
    local function step()
        if gen ~= warmGen then return end
        if InCombatLockdown and InCombatLockdown() then
            C_Timer.After(WARM_COMBAT_RETRY_SEC, step)
            return
        end
        local start = debugprofilestop()
        while pos < #queue do
            local category, id = queue[pos], queue[pos + 1]
            pos = pos + 2
            if not derivedResolved[category][id] then ResolveDerivedRow(category, id) end
            if debugprofilestop() - start > WARM_BUDGET_MS then
                C_Timer.After(0, step)
                return
            end
        end
    end
    C_Timer.After(0, step)
end

function RT.ScheduleDeferredCollectionStoreSave()
    if getDeferredTimer() then return end
    setDeferredTimer(C_Timer.NewTimer(2, function()
        setDeferredTimer(nil)
        if WarbandNexus and WarbandNexus.SaveCollectionStore then
            WarbandNexus:SaveCollectionStore()
        end
    end))
end

---Save collection store to DB (single source — Collections + Plans read from the same data)
---Called after scan completion and real-time updates
function WarbandNexus:SaveCollectionStore()
    if not self.db or not self.db.global then return end
    -- Never persist before InitializeCollectionCache loaded SV into RAM: the RAM store still holds
    -- the empty file-load defaults, and writing them replaces every saved mount/pet/toy/achievement.
    -- Happens when PLAYER_LOGOUT (or a collection event) lands before the deferred P0 init ran:
    -- /reload or logout in combat (SafeInit queues until combat ends) or within the first ~0.5s.
    if not RT.storeHydrated then
        DebugPrint("|cffffcc00[WN CollectionService]|r SaveCollectionStore skipped: store not loaded from SV yet")
        return
    end
    RT.collectionStore.version = CACHE_VERSION
    RT.collectionStore.lastBuilt = RT.collectionStore.lastBuilt or time()
    local toySave = {}
    for id, v in pairs(RT.collectionStore.toy or {}) do
        if v and v.id then
            toySave[id] = { id = v.id, name = (type(v.name) == "string" and v.name ~= "") and v.name or tostring(v.id) }
        end
    end
    for category in pairs(STORE_PERSIST_FIELDS) do
        RT.SlimCollectionStoreRows(category, RT.collectionStore[category])
    end
    self.db.global.collectionStore = {
        version = RT.collectionStore.version,
        lastBuilt = RT.collectionStore.lastBuilt,
        mount = RT.collectionStore.mount,
        pet = RT.collectionStore.pet,
        toy = toySave,
        achievement = RT.collectionStore.achievement,
        title = RT.collectionStore.title,
        illusion = RT.collectionStore.illusion,
        scanCompleted = RT.collectionStore.scanCompleted or {},
    }
    DebugPrint("|cff00ff00[WN CollectionService]|r Saved collectionStore to DB")
end

---Cancel deferred collectionStore save and persist immediately on PLAYER_LOGOUT.
function WarbandNexus:FlushCollectionStoreOnLogout()
    local timer = getDeferredTimer()
    if timer then
        timer:Cancel()
        setDeferredTimer(nil)
    end
    self:SaveCollectionStore()
end

---Save collection cache to DB (legacy — syncs collectionCache for backward compat; also saves collectionStore)
---Called after scan completion to avoid re-scanning on reload
function WarbandNexus:SaveCollectionCache()
    if not self.db or not self.db.global then
    DebugPrint("|cffff0000[WN CollectionService ERROR]|r Cannot save cache: DB not initialized")
        return
    end

    self.db.global.collectionCache = {
        uncollected = RT.collectionCache.uncollected,
        completed = RT.collectionCache.completed or { achievement = {} },
        version = CACHE_VERSION,
        lastScan = RT.collectionCache.lastScan,
        lastAchievementScan = RT.collectionCache.lastAchievementScan or RT.collectionCache.lastScan,
    }

    self:SaveCollectionStore()
end

---Invalidate collection cache (mark for refresh)
---Called when collection data changes (e.g., new mount obtained)
function WarbandNexus:InvalidateCollectionCache(category)
    if category then
        if category == "mount" or category == "pet" or category == "toy" then
            local key = category .. "s"
            if RT.collectionCache.owned[key] then RT.collectionCache.owned[key] = {} end
            if RT.collectionCache.uncollected[category] then RT.collectionCache.uncollected[category] = {} end
        elseif RT.collectionCache.uncollected[category] then
            RT.collectionCache.uncollected[category] = {}
        end
        if category == "achievement" then
            RT.collectionCache.lastAchievementScan = 0
        else
            RT.collectionCache.lastScan = 0
        end
    else
        RT.collectionCache.owned.mounts = {}
        RT.collectionCache.owned.pets = {}
        RT.collectionCache.owned.toys = {}
        if RT.collectionCache.uncollected.mount then RT.collectionCache.uncollected.mount = {} end
        if RT.collectionCache.uncollected.pet then RT.collectionCache.uncollected.pet = {} end
        if RT.collectionCache.uncollected.toy then RT.collectionCache.uncollected.toy = {} end
        RT.collectionCache.lastScan = 0
    end
end

function WarbandNexus:BuildCollectionCache(opts)
    opts = opts or {}
    local quiet = opts.quiet == true
    if not opts.forceJournalScan and CanHydrateOwnedCacheFromStore(self) then
        HydrateOwnedCacheFromStore(self)
        self:ScheduleLazyOwnedToyHydrate()
        return
    end
    -- Re-entrant calls (e.g. IsCollectibleOwned while pets/toys phases still empty) used to
    -- wipe owned cache and stack parallel timer chains, leaving LoadingTracker "collections" stuck.
    if self._buildingCollectionCache then return end
    self._buildingCollectionCache = true

    if self._collectionCacheSafetyTimer then
        self._collectionCacheSafetyTimer:Cancel()
        self._collectionCacheSafetyTimer = nil
    end

    local _issecretvalue = issecretvalue
    local BUDGET_MS = 4
    local P = ns.Profiler
    if P then P:StartAsync(quiet and "BuildCollectionCache_quiet" or "BuildCollectionCache") end
    local LT = ns.LoadingTracker
    if LT and not quiet then LT:Register("collections", (ns.L and ns.L["LT_COLLECTIONS"]) or "Collections") end

    local addonSelf = self
    self._collectionCacheSafetyTimer = C_Timer.NewTimer(60, function()
        addonSelf._collectionCacheSafetyTimer = nil
        if not addonSelf._buildingCollectionCache then return end
        addonSelf._buildingCollectionCache = nil
        if P then pcall(function() P:StopAsync(quiet and "BuildCollectionCache_quiet" or "BuildCollectionCache") end) end
        local lt = ns.LoadingTracker
        if lt and not quiet then lt:Complete("collections") end
        DebugPrint("|cffffcc00[WN CollectionService]|r BuildCollectionCache safety timeout — released LoadingTracker (collections)")
    end)

    RT.collectionCache.owned = {
        mounts = {},
        pets = {},
        toys = {}
    }
    
    -- Pre-declare all phase functions for forward references
    local MountBatch, StartPetPhase, PetBatch, StartToyPhase, ToyBatch

    local function onOwnedCacheBuildDone()
        if addonSelf._collectionCacheSafetyTimer then
            addonSelf._collectionCacheSafetyTimer:Cancel()
            addonSelf._collectionCacheSafetyTimer = nil
        end
        addonSelf._buildingCollectionCache = nil
        if P then pcall(function() P:StopAsync(quiet and "BuildCollectionCache_quiet" or "BuildCollectionCache") end) end
        if LT and not quiet then LT:Complete("collections") end
    end

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
                    RT.collectionCache.owned.mounts[mountID] = true
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
                    RT.collectionCache.owned.pets[speciesID] = true
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
                        RT.collectionCache.owned.toys[itemID] = true
                    end
                end
                toyIdx = toyIdx + 1
                if debugprofilestop() - batchStart > BUDGET_MS then
                    C_Timer.After(0, ToyBatch)
                    return
                end
            end
            onOwnedCacheBuildDone()
            RT.SeedNotifiedFromOwned()
        end)
        if not ok then
            DebugPrint("|cffff4444[WN CollectionService ERROR]|r Toy batch failed: " .. tostring(err))
            onOwnedCacheBuildDone()
        end
    end
    
    MountBatch()
end

---Check if player owns a collectible
---@return boolean owned
function WarbandNexus:IsCollectibleOwned(collectibleType, id)
    local key = collectibleType and (collectibleType .. "s") or nil
    if not key then return false end

    local cache = RT.collectionCache.owned[key]
    if not cache or next(cache) == nil then
        if CanHydrateOwnedCacheFromStore(self) then
            HydrateOwnedCacheFromStore(self)
            cache = RT.collectionCache.owned[key]
            if cache and cache[id] == true then
                return true
            end
        end
        self:BuildCollectionCache({ forceJournalScan = true })
        cache = RT.collectionCache.owned[key]
    end

    return cache and cache[id] == true
end
