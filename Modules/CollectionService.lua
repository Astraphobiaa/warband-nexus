--[[
    Warband Nexus - Collection Service
    DB-backed mount/pet/toy browse cache + real-time obtain detection.
    collectionStore (SV) + collectionCache.owned (RAM); incremental EnsureCollectionData scans.
    Emits WN_COLLECTIBLE_OBTAINED, WN_COLLECTION_SCAN_COMPLETE, WN_COLLECTION_SCAN_PROGRESS.

    NOTIFICATION FLOW (toast lane; display in NotificationManager):
      NEW_MOUNT_ADDED / NEW_PET_ADDED / NEW_TOY_ADDED / bag scan -> dedup -> WN_COLLECTIBLE_OBTAINED
      ACHIEVEMENT_EARNED + Warband achievement popups ON -> AddAlert hook (ShowAchievementNotification)
        + ScheduleAchievementToastFallback if AddAlert never fires
      ACHIEVEMENT_EARNED + Warband popups OFF -> Blizzard AddAlert only (suppressToast on WN_COLLECTIBLE_OBTAINED)
    Currency/reputation: ChatMessageService only (not WN_COLLECTIBLE_OBTAINED).

    WN_NONUI_UI: `bagScanFrame` (and similar) are background event hosts (`CreateFrame`); Browse UI stays in Modules/UI.
]]

local ADDON_NAME, ns = ...

-- 12.1.5 removed the global item/coin fallbacks; bind the namespaced APIs.
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local tinsert = table.insert
local Utilities = ns.Utilities
local function CmpItemName(a, b)
    return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.name) or "") < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.name) or "")
end

--- Plans/collection browse search: never call :lower() on secret API strings (Midnight 12.0+).
local function NormalizeCollectionSearchText(searchText)
    if issecretvalue and issecretvalue(searchText) then return "" end
    if searchText == nil then return "" end
    if type(searchText) ~= "string" then return "" end
    return searchText:lower()
end

local function CollectionNameMatchesSearch(name, searchText)
    if searchText == "" then return true end
    if type(name) ~= "string" then return false end
    local lower = (Utilities and Utilities.SafeLower and Utilities:SafeLower(name)) or ""
    if lower == "" then return false end
    return lower:find(searchText, 1, true) ~= nil
end

-- Debug print helper (only prints if debug mode + debugVerbose enabled; reduces BAG SCAN spam)
local IsDebugModeEnabled = ns.IsDebugModeEnabled
local DebugChatPrint = ns.DebugChatPrint

local function CollectionUserPrint(self, msg)
    if DebugChatPrint then
        DebugChatPrint(msg)
    elseif IsDebugModeEnabled and IsDebugModeEnabled() and self.Print then
        self:Print(msg)
    end
end

local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter(
    nil,
    { verboseOnly = true, suppressWhenTryCounterLoot = true }
)) or function() end
local IsDebugVerboseEnabled = ns.IsDebugVerboseEnabled
local function DebugPrintf(fmt, ...)
    if IsDebugVerboseEnabled and IsDebugVerboseEnabled() then
        DebugPrint(string.format(fmt, ...))
    end
end

local Notify = ns.CollectionNotify
local Mat = ns.CollectionMaterialize

---V2 direct scan: GetCategoryList() returns leaf categories — pair with GetAchievementInfo(categoryID, index)
---(two args only; includeAll applies to GetCategoryNumAchievements, not GetAchievementInfo per wiki).
local function GetCategoryAchievementListCount(categoryID)
    if not categoryID or not GetCategoryNumAchievements then return 0 end
    local ok, total = pcall(GetCategoryNumAchievements, categoryID)
    if ok and type(total) == "number" then return total end
    return 0
end

-- Achievement scan defer state: CollectionService_Achievements.lua

local function EnsurePlansAchievementLoadingState(isLoading)
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState.achievement then
        ns.PlansLoadingState.achievement = { isLoading = false, loader = nil }
    end
    if isLoading == nil then return end
    ns.PlansLoadingState.achievement.isLoading = isLoading
    if isLoading then
        ns.PlansLoadingState.achievement.loadingProgress = ns.PlansLoadingState.achievement.loadingProgress or 0
        ns.PlansLoadingState.achievement.currentStage = ns.PlansLoadingState.achievement.currentStage
            or ((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...")
    end
end

local function SafeAchievementDisplayName(id, name)
    if not id or (issecretvalue and issecretvalue(id)) then return nil end
    if name and ((issecretvalue and issecretvalue(name)) or name ~= "") then
        if issecretvalue and issecretvalue(name) then
            return "ID:" .. tostring(id)
        end
        return name
    end
    return "ID:" .. tostring(id)
end

local function IsAchievementEarnedByMe(wasEarnedByMe)
    if issecretvalue and issecretvalue(wasEarnedByMe) then return false end
    if wasEarnedByMe == nil then return false end
    return wasEarnedByMe == true
end

---Per-character credit is authoritative on GetAchievementInfo(achievementID) (wiki #13 wasEarnedByMe).
local function GetAchievementEarnedByMeInfo(achievementID, fallbackPoints, fallbackWasEarned, fallbackIsGuild)
    if not achievementID or not GetAchievementInfo then
        return fallbackWasEarned, fallbackIsGuild, fallbackPoints
    end
    if issecretvalue and issecretvalue(achievementID) then
        return false, fallbackIsGuild, fallbackPoints
    end
    local ok, packed = pcall(function()
        return { GetAchievementInfo(achievementID) }
    end)
    if not ok or not packed or not packed[1] then
        return fallbackWasEarned, fallbackIsGuild, fallbackPoints
    end
    return packed[13], packed[12], packed[3] or fallbackPoints
end

---GetAchievementInfo(categoryID, index) — wiki: 15 returns; wasEarnedByMe is index 13.
local function GetAchievementInfoByCategoryIndex(categoryID, achIndex)
    if not GetAchievementInfo or not categoryID or not achIndex then return false end
    local ok, packed = pcall(function()
        return { GetAchievementInfo(categoryID, achIndex) }
    end)
    if not ok or not packed or not packed[1] or (issecretvalue and issecretvalue(packed[1])) then
        return false
    end
    return true, packed[1], packed[2], packed[3], packed[4], packed[5], packed[6], packed[7],
        packed[8], packed[9], packed[10], packed[11], packed[12], packed[13]
end

local _achievementCharacterPointsCache = nil
local _collectionCountsAPICache = nil
local COLLECTION_COUNTS_API_TTL = 60

local function SafeAchievementCountPair()
    if not GetNumCompletedAchievements then return 0, 0 end
    local ok, total, completed = pcall(GetNumCompletedAchievements)
    if not ok then return 0, 0 end
    if total and issecretvalue and issecretvalue(total) then total = 0 end
    if completed and issecretvalue and issecretvalue(completed) then completed = 0 end
    return tonumber(total) or 0, tonumber(completed) or 0
end

local function NeedsCharacterAchievementPointsRecompute(addon)
    if not addon or not addon.db or not addon.db.global then return false end
    local CS = ns.CharacterService
    local charKey = (CS and CS.ResolveCharactersTableKey and CS:ResolveCharactersTableKey(addon))
        or (CS and CS.GetCharactersTablePersistKey and CS:GetCharactersTablePersistKey(addon))
    if not charKey or (issecretvalue and issecretvalue(charKey)) then return false end
    local row = addon.db.global.characters and addon.db.global.characters[charKey]
    local stored = row and row.achievementPointsEarned
    if type(stored) == "number" and stored > 0 then return false end
    if row and row.achievementPointsResolvedAt then return false end
    local accountPts = 0
    if GetTotalAchievementPoints then
        accountPts = tonumber(GetTotalAchievementPoints()) or 0
    end
    local _, completed = SafeAchievementCountPair()
    return completed > 0 and accountPts > 0
end

local function PersistCharacterAchievementPoints(addon, points)
    if not addon or not addon.db or not addon.db.global then return end
    local CS = ns.CharacterService
    local charKey = (CS and CS.GetCharactersTablePersistKey and CS:GetCharactersTablePersistKey(addon))
        or (CS and CS.ResolveCharactersTableKey and CS:ResolveCharactersTableKey(addon))
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
    if not charKey or (issecretvalue and issecretvalue(charKey)) then return end
    local chars = addon.db.global.characters
    if not chars then return end
    if not chars[charKey] and addon.SaveCurrentCharacterData then
        addon:SaveCurrentCharacterData({ lightOnly = true })
        charKey = (CS and CS.ResolveCharactersTableKey and CS:ResolveCharactersTableKey(addon)) or charKey
    end
    local row = chars[charKey]
    if not row then return end
    local n = tonumber(points) or 0
    row.achievementPointsEarned = n
    row.achievementPointsResolvedAt = time()
    _achievementCharacterPointsCache = {
        charKey = charKey,
        points = n,
        timestamp = GetTime(),
    }
    _collectionCountsAPICache = nil
end

local function ResolveCharacterAchievementPoints(addon)
    local CS = ns.CharacterService
    local charKey = (CS and CS.ResolveCharactersTableKey and CS:ResolveCharactersTableKey(addon))
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(addon))
    if charKey and _achievementCharacterPointsCache
        and _achievementCharacterPointsCache.charKey == charKey then
        local age = GetTime() - (_achievementCharacterPointsCache.timestamp or 0)
        if age < COLLECTION_COUNTS_API_TTL then
            return _achievementCharacterPointsCache.points or 0
        end
    end
    if not charKey or not addon.db or not addon.db.global then return 0 end
    local row = addon.db.global.characters and addon.db.global.characters[charKey]
    if row and type(row.achievementPointsEarned) == "number" and row.achievementPointsEarned > 0 then
        return row.achievementPointsEarned
    end
    return 0
end

-- CONSTANTS

local Constants = ns.Constants
local E = Constants.EVENTS
local FRAME_BUDGET_MS = Constants.FRAME_BUDGET_MS
local BATCH_SIZE = Constants.BATCH_SIZE
local CACHE_VERSION = Constants.COLLECTION_CACHE_VERSION

---Reused for COLLECTION_SCAN_PROGRESS only (listeners read fields synchronously).
local collectionScanProgressPayload = {}

local function SendCollectionScanProgress(sender, collectionType, progress, scanned, total)
    if not Constants or not Constants.EVENTS or not sender or not sender.SendMessage then return end
    local ev = Constants.EVENTS.COLLECTION_SCAN_PROGRESS
    if not ev then return end
    collectionScanProgressPayload.category = collectionType
    collectionScanProgressPayload.progress = progress
    collectionScanProgressPayload.scanned = scanned
    collectionScanProgressPayload.total = total
    sender:SendMessage(ev, collectionScanProgressPayload)
end

---Coalesce burst triggers (e.g. many GetUncollected* calls) into a single next-frame EnsureCollectionData.
local ensureCollectionDeferredPending = false
local function ScheduleEnsureCollectionDataDeferred()
    if ensureCollectionDeferredPending then return end
    ensureCollectionDeferredPending = true
    -- Two zero-delay timers: coalesce burst callers and run one tick after first scheduling
    -- so login/UI layout is less likely to share a frame with EnsureCollectionData startup.
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            ensureCollectionDeferredPending = false
            if WarbandNexus.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
                WarbandNexus:EnsureCollectionData()
            end
        end)
    end)
end
ns.ScheduleEnsureCollectionDataDeferred = ScheduleEnsureCollectionDataDeferred

local function EmitPlansBrowseCollectionEnsure(category)
    if not category then return end
    if E.PLANS_BROWSE_COLLECTION_ENSURE_REQUESTED and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.PLANS_BROWSE_COLLECTION_ENSURE_REQUESTED, { category = category })
        return
    end
    if ns.RequestPlansBrowseCollectionEnsure then
        ns.RequestPlansBrowseCollectionEnsure(category)
        return
    end
    if WarbandNexus.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
        ScheduleEnsureCollectionDataDeferred()
    end
end

-- COLLECTION CACHE (PERSISTENT IN DB)
--[[
    Unified cache for both real-time and background scanning:
    - owned: {mountID/speciesID/itemID -> true} - O(1) lookups (RAM only)
    - uncollected: {type -> {id -> {name, icon, source...}}} - Browse UI data (PERSISTED TO DB)
    
    IMPORTANT: uncollected cache is saved to DB (SavedVariables) to avoid re-scanning on every reload.
    Only scan when:
    1. DB cache is empty (first time)
    2. User manually requests refresh
    3. Real-time detection adds/removes items (incremental update)
    
    Startup order (InitializationService):
    - P0: InitializeCollectionCache (load collectionStore from SV)
    - P1: RunCollectionOwnedCacheWarmup — owned O(1) cache; quiet when store already matches CACHE_VERSION (no extra LoadingTracker row)
    - P5: EnsureFullCollectionData — EnsureCollectionData if any category missing / version mismatch
    
    Persisted in db.global.collectionStore (per row, 2026-10-22): mount id+collected+sourceType, pet id+collected+sourceTypeIndex, achievement id+collected+points, title id+collected; display fields resolve lazily from the API (CollectionService_Store.lua). Toy id+name only (collected from API when needed). Illusions keep their full rows.
    Profiler labels (when /wn profiler on): EnsureBlizzard_CollectionsLoad, BuildFullCollectionData [async], EnsureCollectionData [async], BuildCollectionCache / BuildCollectionCache_quiet [async].
]]

-- SINGLE SOURCE: all collection data in one structure. Collections (full) and Plans (uncollected) read from the same source.
-- The API only kicks in when data is missing or on a version update.
local collectionStore = {
    version = CACHE_VERSION,
    lastBuilt = 0,
    mount = {},
    pet = {},
    toy = {},
    achievement = {},
    title = {},
    illusion = {},
    scanCompleted = {},
}

-- collectionData = collectionStore alias (GetAllMountsData etc. use collectionData)
local collectionData = collectionStore

---Full journal scan should persist thousands of rows; a tiny store means a failed/partial scan.
local ACHIEVEMENT_STORE_MIN_TRUST = 250

local function IsCategoryScanMarkedComplete(category)
    local sc = collectionStore.scanCompleted
    local tbl = collectionStore[category]
    return sc and sc[category] ~= nil and type(tbl) == "table" and next(tbl) ~= nil
end

local function MarkCategoryScanComplete(category)
    if not category then return end
    if not collectionStore.scanCompleted then
        collectionStore.scanCompleted = {}
    end
    collectionStore.scanCompleted[category] = time()
end

local function ClearCategoryScanComplete(category)
    if collectionStore.scanCompleted and category then
        collectionStore.scanCompleted[category] = nil
    end
end

local function CategoryNeedsInitialScan(category)
    local tbl = collectionStore[category]
    local hasRows = tbl and next(tbl) ~= nil
    if hasRows then return false end
    return not IsCategoryScanMarkedComplete(category)
end

local function CountAchievementStoreEntries()
    local store = collectionStore.achievement
    if type(store) ~= "table" then return 0 end
    local n = 0
    for _ in pairs(store) do
        n = n + 1
    end
    return n
end

local function IsAchievementStoreInadequate()
    return CountAchievementStoreEntries() < ACHIEVEMENT_STORE_MIN_TRUST
end

local function SumAchievementJournalPointsMax()
    if IsAchievementStoreInadequate() then return 0 end
    local store = collectionStore.achievement
    if type(store) ~= "table" then return 0 end
    local sum = 0
    for _, record in pairs(store) do
        if type(record) == "table" and record.isGuild ~= true then
            local pt = tonumber(record.points) or 0
            if pt > 0 then sum = sum + pt end
        end
    end
    return sum
end

local function ApplyAchievementSummaryToData(addon, data)
    if not data then return data end
    if GetTotalAchievementPoints then
        data.achievementPoints = GetTotalAchievementPoints() or 0
    end
    data.achievementsTotal, data.achievementsCompleted = SafeAchievementCountPair()
    data.achievementPointsCharacter = ResolveCharacterAchievementPoints(addon)
    data.achievementPointsMax = SumAchievementJournalPointsMax()
    if NeedsCharacterAchievementPointsRecompute(addon)
        and addon.RecomputeCharacterAchievementPointsAsync then
        addon:RecomputeCharacterAchievementPointsAsync()
    end
    return data
end

local function SignalAchievementScanPipelineDone(sender, payload)
    EnsurePlansAchievementLoadingState(false)
    if Constants and Constants.EVENTS and sender and sender.SendMessage then
        sender:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, payload or { category = "achievement" })
    end
end

---True when EnsureCollectionData would return immediately (SV version matches, store has all categories).
---Includes toy/pet count sanity vs journal totals (same rules as EnsureCollectionData).
---@return boolean
local function IsCollectionEnsureDataComplete(self)
    if not self.db or not self.db.global then return false end
    local dbStore = self.db.global.collectionStore
    local versionOk = dbStore and dbStore.version == CACHE_VERSION
    local hasMounts = collectionStore.mount and next(collectionStore.mount) ~= nil
    local hasPets = collectionStore.pet and next(collectionStore.pet) ~= nil
    local hasToys = collectionStore.toy and next(collectionStore.toy) ~= nil
    local hasAchievements = collectionStore.achievement and next(collectionStore.achievement) ~= nil
    local hasTitles = (collectionStore.title and next(collectionStore.title) ~= nil)
        or IsCategoryScanMarkedComplete("title")
    local hasIllusions = (collectionStore.illusion and next(collectionStore.illusion) ~= nil)
        or IsCategoryScanMarkedComplete("illusion")
    local needAchievementIncludeAllRescan = self.db.global and not self.db.global.wnAchievementDirectScanV2
    if not (versionOk and hasMounts and hasPets and hasToys and hasAchievements and hasTitles and hasIllusions and not needAchievementIncludeAllRescan) then
        return false
    end
    if hasAchievements and IsAchievementStoreInadequate() then
        return false
    end
    if hasToys and C_ToyBox and C_ToyBox.GetNumToys then
        local apiTotal = C_ToyBox.GetNumToys() or 0
        if apiTotal and apiTotal > 0 then
            local storeCount = 0
            for _ in pairs(collectionStore.toy) do
                storeCount = storeCount + 1
            end
            if storeCount < (apiTotal * 0.5) then
                return false
            end
        end
    end
    if hasPets and C_PetJournal and C_PetJournal.GetNumPets then
        local apiTotal = C_PetJournal.GetNumPets() or 0
        if apiTotal and apiTotal > 0 then
            local storeCount = 0
            for _ in pairs(collectionStore.pet) do
                storeCount = storeCount + 1
            end
            if storeCount < (apiTotal * 0.5) then
                return false
            end
        end
    end
    return true
end

--- Exposed for UI: true when persisted collectionStore matches code version and all categories are populated.
---@return boolean
function WarbandNexus:IsCollectionEnsureDataComplete()
    return IsCollectionEnsureDataComplete(self)
end

--- Plans browse: true when collectionStore has no rows for mount/pet/toy/illusion/title yet.
---@return boolean
function WarbandNexus:IsPlansBrowseCategoryStoreEmpty(category)
    if not category then return true end
    if category == "achievement" and IsAchievementStoreInadequate() then
        return true
    end
    if (category == "illusion" or category == "title") and IsCategoryScanMarkedComplete(category) then
        return false
    end
    local tbl = collectionStore[category]
    return not tbl or next(tbl) == nil
end

-- collectionCache: deprecated; GetUncollected* now filters from collectionStore. ScanCollection still writes uncollected (transitional).
local collectionCache = {
    owned = { mounts = {}, pets = {}, toys = {} },
    uncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, illusion = {} },
    completed = { achievement = {} },
    lastScan = 0,
    lastAchievementScan = 0,
}

--- True when persisted collectionStore can hydrate RAM owned cache without a journal scan.
---@param self table
---@return boolean
local function CanHydrateOwnedCacheFromStore(self)
    return IsCollectionEnsureDataComplete(self)
end

--- Fill collectionCache.owned from collectionStore.collected flags (fast; no C_MountJournal scan).
---@param self table
---@return number ownedCount approximate entries set
local function HydrateOwnedCacheFromStore(self)
    local owned = collectionCache.owned
    wipe(owned.mounts)
    wipe(owned.pets)
    wipe(owned.toys)
    local count = 0

    local function absorb(store, bucket)
        if type(store) ~= "table" then return end
        for id, data in pairs(store) do
            if type(data) == "table" and data.collected == true then
                bucket[id] = true
                count = count + 1
            end
        end
    end

    absorb(collectionStore.mount, owned.mounts)
    absorb(collectionStore.pet, owned.pets)
    absorb(collectionStore.toy, owned.toys)
    collectionCache.lastScan = time()
    return count
end

local TOY_OWNED_HYDRATE_BUDGET_MS = 4

--- Time-budgeted PlayerHasToy pass for toys (store rows lack collected flag in SV).
function WarbandNexus:ScheduleLazyOwnedToyHydrate()
    if self._lazyToyHydrateRunning then return end
    local store = collectionStore.toy
    if type(store) ~= "table" or next(store) == nil then return end
    self._lazyToyHydrateRunning = true
    local toyIds = {}
    for id in pairs(store) do
        toyIds[#toyIds + 1] = id
    end
    local idx = 1
    local _sv = issecretvalue
    local function batch()
        if not self._lazyToyHydrateRunning then return end
        local batchStart = debugprofilestop()
        while idx <= #toyIds do
            local id = toyIds[idx]
            idx = idx + 1
            if PlayerHasToy then
                local raw = PlayerHasToy(id)
                local collected = false
                if _sv and raw and _sv(raw) then
                    collected = true
                elseif raw == true then
                    collected = true
                end
                if collected then
                    collectionCache.owned.toys[id] = true
                end
            end
            if debugprofilestop() - batchStart > TOY_OWNED_HYDRATE_BUDGET_MS then
                C_Timer.After(0, batch)
                return
            end
        end
        self._lazyToyHydrateRunning = false
    end
    C_Timer.After(0.5, batch)
end

---P1 warmup: when persisted collectionStore is already complete, hydrate owned RAM cache (skip journal scan).
function WarbandNexus:RunCollectionOwnedCacheWarmup()
    if CanHydrateOwnedCacheFromStore(self) then
        local n = HydrateOwnedCacheFromStore(self)
        DebugPrint(string.format(
            "|cff00ccff[WN CollectionService]|r Owned cache hydrated from store (%d entries, no journal scan)",
            n))
        self:ScheduleLazyOwnedToyHydrate()
        return
    end
    self:BuildCollectionCache()
end

---Coalesced EnsureCollectionData (slash / other callers). Does not wipe SV; use DebugForceCollectionRebuild for that.
function WarbandNexus:RequestCollectionDataRefresh()
    if ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading then
        CollectionUserPrint(self, "|cffff8800[WN]|r Collection pipeline already running; skipped. |cff00ccff/wn collection status|r for stage.|r")
        return
    end
    if IsCollectionEnsureDataComplete(self) then
        CollectionUserPrint(self, "|cff888888[WN]|r Collection store already matches code version and categories; nothing to rescan. (|cff00ccff/wn collection rebuild|r to force, or bump cache version in a release.)|r")
        return
    end
    ScheduleEnsureCollectionDataDeferred()
    CollectionUserPrint(self, "|cff00ccff[WN]|r Collection refresh scheduled (EnsureCollectionData next frames).|r")
end

---Debug: print collectionStore counts, SV version, and CollectionLoadingState snapshot.
function WarbandNexus:PrintCollectionDataStatus()
    local dbStore = self.db and self.db.global and self.db.global.collectionStore
    local svVer = dbStore and dbStore.version or "?"
    local nm, np, nt, na, nti, nIll = 0, 0, 0, 0, 0, 0
    for _ in pairs(collectionStore.mount or {}) do nm = nm + 1 end
    for _ in pairs(collectionStore.pet or {}) do np = np + 1 end
    for _ in pairs(collectionStore.toy or {}) do nt = nt + 1 end
    for _ in pairs(collectionStore.achievement or {}) do na = na + 1 end
    for _ in pairs(collectionStore.title or {}) do nti = nti + 1 end
    for _ in pairs(collectionStore.illusion or {}) do nIll = nIll + 1 end
    local load = ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading
    local stage = (ns.CollectionLoadingState and ns.CollectionLoadingState.currentStage) or "-"
    CollectionUserPrint(self, string.format(
        "|cff00ccff[WN Collection]|r SV.version=%s loading=%s stage=%s | store m/p/t/a/ti/il=%d/%d/%d/%d/%d/%d|r",
        tostring(svVer), tostring(load), tostring(stage), nm, np, nt, na, nti, nIll))
end

-- Global loading state (accessible from UI modules like PlansUI)
ns.CollectionLoadingState = {
    isLoading = false,
    loadingProgress = 0,  -- 0-100
    currentStage = nil,   -- "Mounts", "Pets", "Toys", "Achievements", etc.
    currentCategory = nil,
    totalItems = 0,
    scannedItems = 0,
}

-- Session metadata cache: CollectionService_Metadata.lua

-- Short-lived results cache for GetUncollected* functions.
-- Prevents expensive store re-iteration on rapid UI redraws (category switches, toggle clicks).
-- Invalidated by collection events (scan complete, collectible obtained) — those wipes,
-- not this TTL, are what keep results fresh, so the TTL can comfortably outlive redraw cadence.
local RESULTS_CACHE_TTL = 10 -- seconds
local uncollectedResultsCache = {}
--- Merged achievement list for GetAllAchievementsData; cleared with uncollectedResultsCache.
local _allAchievementsMergedCache = nil

local function ClearAchievementMergedListCache()
    _allAchievementsMergedCache = nil
end

local function WipeUncollectedResultsCacheAndMergedAchievements()
    wipe(uncollectedResultsCache)
    ClearAchievementMergedListCache()
end

-- DUPLICATE NOTIFICATION PREVENTION (BAG SCAN + COLLECTION EVENTS)
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

-- Bag scan: CollectionService_Scan.lua (ns.CollectionScan)

-- Notification dedup: CollectionService_NotifyDedup.lua (ns.CollectionNotify)

-- COLLECTION CACHE INITIALIZATION

---Initialize collection cache from DB (load persisted data)
---Called on addon load to restore previous scan results
function WarbandNexus:InitializeCollectionCache()
    local debugMode = self.db and self.db.profile and self.db.profile.debugMode
    
    if debugMode then
    DebugPrint("|cff9370DB[WN CollectionService]|r InitializeCollectionCache called")
    end
    
    -- Ensure DB is initialized
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
    
    local defaultUncollected = { mount = {}, pet = {}, toy = {}, achievement = {}, title = {}, illusion = {} }

    -- Reset the legacy cache when missing or version-mismatched, but DO NOT return
    -- early: the collectionStore load below must still run. The cache and the store
    -- are written by different paths and their SV versions can diverge — bailing out
    -- here used to discard a perfectly valid persisted store for the whole session.
    if not self.db.global.collectionCache then
        self.db.global.collectionCache = {
            uncollected = defaultUncollected,
            version = CACHE_VERSION,
            lastScan = time()
        }
        if debugMode then
    DebugPrint("|cffffcc00[WN CollectionService]|r Initialized NEW collection cache (empty)")
        end
    elseif self.db.global.collectionCache.version ~= CACHE_VERSION then
        if debugMode then
    DebugPrint("|cffffcc00[WN CollectionService]|r Cache version mismatch (DB: " .. tostring(self.db.global.collectionCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
        end
        self.db.global.collectionCache = {
            uncollected = defaultUncollected,
            version = CACHE_VERSION,
            lastScan = time()
        }
    end

    local dbCache = self.db.global.collectionCache

    collectionCache.uncollected = dbCache.uncollected or defaultUncollected
    collectionCache.completed = dbCache.completed or { achievement = {} }
    if not collectionCache.completed.achievement then
        collectionCache.completed.achievement = {}
    end
    collectionCache.lastScan = dbCache.lastScan or 0
    collectionCache.lastAchievementScan = dbCache.lastAchievementScan or 0

    if IsAchievementStoreInadequate() then
        collectionCache.lastAchievementScan = 0
    end

    -- One-shot: force a fresh achievement scan when switching from includeAll=true to includeAll=false.
    -- includeAll=false is correct because GetCategoryList() returns all subcategories, and each
    -- category should only scan its direct achievements. V2 flag triggers rescan for all users.
    if self.db.global and not self.db.global.wnAchievementDirectScanV2 then
        collectionCache.lastAchievementScan = 0
    end
    -- One-shot: re-sum wasEarnedByMe points after character score persistence shipped.
    if self.db.global and not self.db.global.wnAchievementCharPointsBackfillV1 then
        self.db.global.wnAchievementCharPointsBackfillV1 = true
        collectionCache.lastAchievementScan = 0
    end
    -- One-shot: clear stale persisted 0 (failed scan) so ID-based recompute can run.
    if self.db.global and not self.db.global.wnAchievementCharPointsRecomputeV2 then
        self.db.global.wnAchievementCharPointsRecomputeV2 = true
        local chars = self.db.global.characters
        if type(chars) == "table" then
            for _, row in pairs(chars) do
                if type(row) == "table" and row.achievementPointsEarned == 0 then
                    row.achievementPointsEarned = nil
                    row.achievementPointsResolvedAt = nil
                end
            end
        end
    end

    -- SINGLE SOURCE: load collectionStore or migrate from the old DB
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
        collectionStore.scanCompleted = dbStore.scanCompleted or {}
        collectionStore.lastBuilt = dbStore.lastBuilt or 0
        -- SV rows are slim (CollectionService_Store.lua): attach the lazy display-field resolver.
        local slimRows = ns.CollectionServiceRT and ns.CollectionServiceRT.SlimCollectionStoreRows
        if slimRows then
            slimRows("mount", collectionStore.mount)
            slimRows("pet", collectionStore.pet)
            slimRows("achievement", collectionStore.achievement)
            slimRows("title", collectionStore.title)
            -- Resolve display fields before the first list query asks for all of them at once.
            C_Timer.After(10, function()
                local warm = ns.CollectionServiceRT.WarmStoreRowDisplay
                if warm then warm({ "achievement", "mount", "pet", "title" }) end
            end)
        end
        if debugMode then
            local m, p, t, a, ti, il = 0, 0, 0, 0, 0, 0
            for _ in pairs(collectionStore.mount) do m = m + 1 end
            for _ in pairs(collectionStore.pet) do p = p + 1 end
            for _ in pairs(collectionStore.toy) do t = t + 1 end
            for _ in pairs(collectionStore.achievement) do a = a + 1 end
            for _ in pairs(collectionStore.title) do ti = ti + 1 end
            for _ in pairs(collectionStore.illusion) do il = il + 1 end
            DebugPrintf("|cff00ff00[WN CollectionService]|r Loaded collectionStore: %d mounts, %d pets, %d toys, %d achievements, %d titles, %d illusions", m, p, t, a, ti, il)
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
        -- collectionCache.completed.achievement → collectionStore.achievement (merge).
        -- The completed cache stores plain display-name STRINGS (see ScanAchievementsAsync);
        -- older versions stored record tables. Handle both — assigning a field on a string
        -- raises and would abort P0 init.
        if collectionCache.completed and collectionCache.completed.achievement then
            for id, ach in pairs(collectionCache.completed.achievement) do
                if ach and not collectionStore.achievement[id] then
                    if type(ach) == "table" then
                        collectionStore.achievement[id] = ach
                        if collectionStore.achievement[id].collected == nil then
                            collectionStore.achievement[id].collected = true
                        end
                    else
                        collectionStore.achievement[id] = { id = id, name = tostring(ach), collected = true }
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

    -- The in-memory store now mirrors SV (or the migration). Until this point it holds the empty
    -- file-load defaults, and SaveCollectionStore refuses to write them (see storeHydrated there).
    if ns.CollectionServiceRT then
        ns.CollectionServiceRT.storeHydrated = true
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
        
    DebugPrintf("|cff00ff00[WN CollectionService]|r Loaded cache from DB: %d mounts, %d pets, %d toys, %d achievements, %d titles, %d illusions",
        mountCount, petCount, toyCount, achievementCount, titleCount, illusionCount)
    end
    
    -- Initialize bag-detected collectibles DB (for duplicate prevention)
    if Notify and Notify.InitializeBagDetectedDB then
        Notify.InitializeBagDetectedDB()
    end
end

-- Coalesce store persists triggered from READ paths (GetUncollected* drift sync):
-- serializing the whole store inside a getter on every cache miss is wasteful, and
-- the synced collected-flags are re-derived from the API anyway if a save is missed.
local deferredStoreSaveTimer

local CSListeners = {}

ns.CollectionServiceRT = {
    collectionStore = collectionStore,
    collectionCache = collectionCache,
    CACHE_VERSION = CACHE_VERSION,
    DebugPrint = DebugPrint,
    time = time,
    deferredStoreSaveTimer = nil,
    CSListeners = CSListeners,
    -- InvalidateCollectionCountsCache is owned by CollectionService_Events.lua and written back onto RT there.
    WipeUncollectedResultsCacheAndMergedAchievements = WipeUncollectedResultsCacheAndMergedAchievements,
    CanHydrateOwnedCacheFromStore = CanHydrateOwnedCacheFromStore,
    HydrateOwnedCacheFromStore = HydrateOwnedCacheFromStore,
}
-- Store/cache persist: CollectionService_Store.lua
-- Read-path save coalescing wrapper (ScheduleDeferredCollectionStoreSave): CollectionService_Queries.lua

-- Blizzard materialize: CollectionService_Materialize.lua (ns.CollectionMaterialize)

---Build full collection data (all mounts, pets, toys with id, name, icon, source, description).
---Runs on login when DB has no data or version changed. Stores result in collectionStore and DB.
function WarbandNexus:BuildFullCollectionData(onComplete)
    -- Prevent re-entrant calls while already building
    if self._buildingCollectionData then
        if onComplete then onComplete() end
        return
    end
    self._buildingCollectionData = true

    collectionCache.owned = { mounts = {}, pets = {}, toys = {} }

    local Pbf = ns.Profiler
    local profBuildState = { started = false }
    if Pbf and Pbf.enabled then
        Pbf:StartAsync("BuildFullCollectionData")
        profBuildState.started = true
    end
    local function stopBuildProf()
        if profBuildState.started and Pbf then
            pcall(function() Pbf:StopAsync("BuildFullCollectionData") end)
            profBuildState.started = false
        end
    end

    Mat.EnsureBlizzardCollectionsLoaded()
    local LT = ns.LoadingTracker
    if LT and not onComplete then
        LT:Register("collection_data", (ns.L and ns.L["LT_COLLECTION_DATA"]) or "Collection Data")
    end

    ns.CollectionLoadingState.isLoading = true
    ns.CollectionLoadingState.loadingProgress = 0
    ns.CollectionLoadingState.currentStage = (ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections..."
    ns.CollectionLoadingState.currentCategory = "mount"

    local _issecretvalue = issecretvalue
    local BUDGET_MS = FRAME_BUDGET_MS
    local configs = { "mount", "pet", "toy" }
    local configIdx = 1
    local itemIdx = 1
    local items = {}
    local currentType = nil
    local config = nil

    local petMatState, toyMatState = nil, nil

    local function nextBatch()
        if configIdx > #configs then
            self._buildingCollectionData = nil
            stopBuildProf()
            ns.CollectionLoadingState.loadingProgress = 99
            collectionStore.lastBuilt = time()
            -- When called from EnsureCollectionData, the pipeline saves once at the end
            -- to avoid two full db.global.collectionStore writes (large SV hitch).
            if not onComplete then
                self:SaveCollectionStore()
            end
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
        config = ns.CollectionServiceRT.COLLECTION_CONFIGS[currentType]
        if not config then
            configIdx = configIdx + 1
            C_Timer.After(0, nextBatch)
            return
        end
        if itemIdx == 1 then
            if currentType == "mount" then
                petMatState, toyMatState = nil, nil
                if self.EnsureMountSourceIndexMap then self:EnsureMountSourceIndexMap() end
                items = ns.CollectionServiceRT.COLLECTION_CONFIGS.mount.iterator()
            elseif currentType == "pet" then
                toyMatState = nil
                petMatState = Mat.PetJournalBuildMaterializeStep(BUDGET_MS, petMatState)
                if not petMatState.done then
                    C_Timer.After(0, nextBatch)
                    return
                end
                items = petMatState.items
                ns._petSpeciesToSourceIndex = petMatState.speciesToSource
                petMatState = nil
            elseif currentType == "toy" then
                toyMatState = Mat.ToyBoxBuildMaterializeStep(BUDGET_MS, toyMatState, self)
                if not toyMatState.done then
                    C_Timer.After(0, nextBatch)
                    return
                end
                items = toyMatState.items
                ns._toyItemIDToSourceIndex = toyMatState.toyToSource
                if ns._toyItemIDToSourceIndexCache then
                    ns._toyItemIDToSourceIndexCache.map = toyMatState.toyToSource
                end
                toyMatState = nil
            else
                items = config.iterator()
            end
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
                local include = true
                if config.shouldIncludeInAll then
                    include = config.shouldIncludeInAll(data)
                end
                if include then
                    if currentType == "mount" then
                        collectionData.mount[data.id] = data
                    elseif currentType == "pet" then
                        collectionData.pet[data.id] = data
                    elseif currentType == "toy" then
                        collectionData.toy[data.id] = {
                            id = data.id,
                            name = data.name,
                            sourceTypeIndex = data.sourceTypeIndex,
                        }
                    end
                    if data.collected == true then
                        if currentType == "mount" then
                            collectionCache.owned.mounts[data.id] = true
                        elseif currentType == "pet" then
                            collectionCache.owned.pets[data.id] = true
                        elseif currentType == "toy" then
                            collectionCache.owned.toys[data.id] = true
                        end
                    end
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

---Ensure collection data is populated. Core-level init — full scan when the version changed or data is missing.
---Plans/Collections sekmelerinden tetiklenmez; sadece init.
function WarbandNexus:EnsureCollectionData(onComplete)
    if not self.db or not self.db.global then
        if onComplete then onComplete() end
        return
    end

    if IsCollectionEnsureDataComplete(self) then
        if onComplete then onComplete() end
        return
    end

    local hasMounts = collectionStore.mount and next(collectionStore.mount) ~= nil
    local hasPets = collectionStore.pet and next(collectionStore.pet) ~= nil
    local hasToys = collectionStore.toy and next(collectionStore.toy) ~= nil
    local hasAchievements = collectionStore.achievement and next(collectionStore.achievement) ~= nil
    local hasTitles = collectionStore.title and next(collectionStore.title) ~= nil
    local hasIllusions = collectionStore.illusion and next(collectionStore.illusion) ~= nil
    local needAchievementIncludeAllRescan = self.db.global and not self.db.global.wnAchievementDirectScanV2

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
                DebugPrintf("|cffffcc00[WN CollectionService]|r Toy store size (%d) << ToyBox total (%d) — forcing full rebuild", storeCount, apiTotal)
                hasMounts = false   -- trigger BuildFullCollectionData (mount/pet/toy) below
                hasPets = false
                hasToys = false
            end
        end
    end

    -- Same net for pets: an in-combat materialize cannot reset journal filters and
    -- can persist a truncated pet store; toys had this check, pets did not.
    if hasPets and C_PetJournal and C_PetJournal.GetNumPets then
        local apiTotal = C_PetJournal.GetNumPets() or 0
        if apiTotal and apiTotal > 0 then
            local storeCount = 0
            for _ in pairs(collectionStore.pet) do
                storeCount = storeCount + 1
            end
            if storeCount < (apiTotal * 0.5) then
                DebugPrintf("|cffffcc00[WN CollectionService]|r Pet store size (%d) << journal total (%d) — forcing full rebuild", storeCount, apiTotal)
                hasMounts = false
                hasPets = false
                hasToys = false
            end
        end
    end

    local LT = ns.LoadingTracker
    if LT then
        LT:Register("collection_data", (ns.L and ns.L["LT_COLLECTION_DATA"]) or "Collection Data")
    end

    ns.CollectionLoadingState.isLoading = true
    ns.CollectionLoadingState.loadingProgress = 0
    ns.CollectionLoadingState.currentStage = (ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections..."

    Mat.EnsureBlizzardCollectionsLoaded()

    local queue = {}
    -- BuildFullCollectionData handles mount+pet+toy together; trigger when any of them is missing/stale
    if not hasMounts or not hasPets or not hasToys then
        queue[#queue + 1] = "build"  -- BuildFullCollectionData (mounts, pets, toys)
    end
    if (not hasAchievements) or needAchievementIncludeAllRescan or IsAchievementStoreInadequate() then
        queue[#queue + 1] = "achievement"
    end
    if CategoryNeedsInitialScan("title") then
        queue[#queue + 1] = "title"
    end
    if CategoryNeedsInitialScan("illusion") then
        queue[#queue + 1] = "illusion"
    end

    local P = ns.Profiler
    local profEnsureState = { started = false }
    local function stopEnsureProf()
        if profEnsureState.started and P then
            pcall(function() P:StopAsync("EnsureCollectionData") end)
            profEnsureState.started = false
        end
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

    if P and P.enabled then
        P:StartAsync("EnsureCollectionData")
        profEnsureState.started = true
    end

    local idx = 1
    -- 2026-10-22: per-run generation so an older run's 60 s safety timeout cannot force-clear a newer
    -- run; the timeout also drops this run's achievement-step listener (it outlived the run before).
    local runGen = (ns.CollectionLoadingState.ensureRunGen or 0) + 1
    ns.CollectionLoadingState.ensureRunGen = runGen
    local achievementStepWaiting = false
    local function RunNext()
        -- Defer entire pipeline step while in combat (PetJournal / mount APIs may skip or error mid-phase).
        if InCombatLockdown and InCombatLockdown() then
            C_Timer.After(0, RunNext)
            return
        end
        if idx > #queue then
            stopEnsureProf()
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
            local msgName = E.COLLECTION_SCAN_COMPLETE
            local handler
            handler = function(_, data)
                if data and data.category == "achievement" then
                    self:UnregisterMessage(msgName)
                    achievementStepWaiting = false
                    ns.CollectionLoadingState.loadingProgress = math.min(99, (idx - 1) / #queue * 100)
                    C_Timer.After(0.2, RunNext)
                end
            end
            achievementStepWaiting = true
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

    -- Safety timeout: if the pipeline hasn't completed within 60s, force-clear loading state
    -- to prevent the UI from being permanently stuck on the loading overlay
    C_Timer.After(60, function()
        if ns.CollectionLoadingState.ensureRunGen ~= runGen then return end
        if ns.CollectionLoadingState.isLoading then
            -- A later achievement scan must not resume this run's title/illusion/save chain.
            if achievementStepWaiting then
                achievementStepWaiting = false
                WarbandNexus:UnregisterMessage(E.COLLECTION_SCAN_COMPLETE)
            end
            stopEnsureProf()
            ns.CollectionLoadingState.isLoading = false
            ns.CollectionLoadingState.loadingProgress = 100
            if ns.PlansLoadingState then
                for cat, st in pairs(ns.PlansLoadingState) do
                    if type(st) == "table" and st.isLoading then
                        st.isLoading = false
                        st.loadingProgress = 100
                    end
                end
            end
            if LT then LT:Complete("collection_data") end
            if WarbandNexus.SaveCollectionStore then
                WarbandNexus:SaveCollectionStore()
            end
            if Constants and Constants.EVENTS and WarbandNexus.SendMessage then
                WarbandNexus:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = "all", timedOut = true })
            end
            DebugPrint("|cffff4444[WN CollectionService]|r EnsureCollectionData safety timeout — force-cleared loading state")
        end
    end)
end

---Legacy: EnsureFullCollectionData — use EnsureCollectionData instead
function WarbandNexus:EnsureFullCollectionData()
    self:EnsureCollectionData()
end

---Get single mount record from global collection data (id, name, icon, source, description, creatureDisplayID, collected).
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
            out[#out + 1] = {
                id = d.id,
                name = d.name or tostring(d.id),
                collected = collected,
                sourceTypeIndex = d.sourceTypeIndex,
            }
        end
    end
    return out
end

-- TOY: C_ToyBox source type only. Categories = Blizzard Sources (Drop, Quest, Vendor, ...).
local TOY_SOURCE_TYPE_MAX = 32
-- Blizzard Toy Box Filter > Sources order (fallback when TOY_SOURCE_TYPE_N globals missing or SOURCE_TYPE_OTHER)
local TOY_SOURCE_TYPE_NAMES = {
    [1] = (ns.L and ns.L["SOURCE_TYPE_DROP"]) or BATTLE_PET_SOURCE_1 or "Drop",
    [2] = (ns.L and ns.L["SOURCE_TYPE_QUEST"]) or BATTLE_PET_SOURCE_2 or "Quest",
    [3] = (ns.L and ns.L["SOURCE_TYPE_VENDOR"]) or BATTLE_PET_SOURCE_3 or "Vendor",
    [4] = (ns.L and ns.L["SOURCE_TYPE_PROFESSION"]) or BATTLE_PET_SOURCE_4 or "Profession",
    [5] = (ns.L and ns.L["SOURCE_TYPE_PET_BATTLE"]) or BATTLE_PET_SOURCE_5 or "Pet Battle",
    [6] = (ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement",
    [7] = (ns.L and ns.L["SOURCE_TYPE_WORLD_EVENT"]) or BATTLE_PET_SOURCE_7 or "World Event",
    [8] = (ns.L and ns.L["SOURCE_TYPE_PROMOTION"]) or BATTLE_PET_SOURCE_8 or "Promotion",
    [9] = (ns.L and ns.L["SOURCE_TYPE_TRADING_CARD"]) or BATTLE_PET_SOURCE_9 or "Trading Card Game",
    [10] = (ns.L and ns.L["SOURCE_TYPE_IN_GAME_SHOP"]) or BATTLE_PET_SOURCE_10 or "In-Game Shop",
    [11] = (ns.L and ns.L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",
    [12] = (ns.L and ns.L["SOURCE_TYPE_PVP"]) or "PvP",
}

---Build grouped toy tables from session itemID->sourceIndex map (no ToyBox filter sweep).
---@return table grouped same shape as GetToysGroupedBySourceType
local function BuildToyGroupedTablesFromMap(addon, itemIDToSource)
    local grouped = {}
    for itemID, srcIdx in pairs(itemIDToSource) do
        if type(itemID) == "number" and itemID > 0 and type(srcIdx) == "number" and srcIdx > 0 then
            local g = grouped[srcIdx]
            if not g then
                g = { name = addon:GetToySourceTypeName(srcIdx), itemIDs = {} }
                grouped[srcIdx] = g
            end
            tinsert(g.itemIDs, itemID)
        end
    end
    return grouped
end

---Category label for Blizzard source type index. Prefer game globals/locale; else use Sources filter names (Drop, Quest, Vendor, ...).
function WarbandNexus:GetToySourceTypeName(sourceIndex)
    if not sourceIndex or type(sourceIndex) ~= "number" or sourceIndex < 1 then return "" end
    local key = "TOY_SOURCE_TYPE_" .. sourceIndex
    local L = ns.L
    if L and L[key] and L[key] ~= key and L[key] ~= "SOURCE_TYPE_OTHER" then return L[key] end
    local g = _G[key]
    if type(g) == "string" and g ~= "" and g ~= "SOURCE_TYPE_OTHER" then return g end
    return TOY_SOURCE_TYPE_NAMES[sourceIndex] or string.format((L and L["SOURCE_TYPE_CATEGORY_FORMAT"]) or "Category %d", sourceIndex)
end

function WarbandNexus:GetToySourceTypeCount()
    if not C_ToyBox then return 0 end
    Mat.EnsureBlizzardCollectionsLoaded()
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
    Mat.EnsureBlizzardCollectionsLoaded()
    if InCombatLockdown() then return grouped, itemIDToSource end
    if ns._toyGroupedFromMapValid and ns._toyItemIDToSourceIndex and next(ns._toyItemIDToSourceIndex) then
        local map = ns._toyItemIDToSourceIndex
        return BuildToyGroupedTablesFromMap(self, map), map
    end
    local origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
    local origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
    local origFilterString = Mat.GetToyBoxSearchText()
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
    ns._toyItemIDToSourceIndex = itemIDToSource
    ns._toyGroupedFromMapValid = next(itemIDToSource) ~= nil
    return grouped, itemIDToSource
end

---Single source of truth for toy source line: C_ToyBox source type name (Drop, Quest, Vendor, ...). Used by Collections and Plans.
---Caches itemID->sourceIndex from GetToysGroupedBySourceType so repeated lookups are cheap.
function WarbandNexus:GetToySourceTypeNameForItem(itemID)
    if not itemID then return nil end
    local idx = self:GetToySourceTypeIndexForItem(itemID)
    if not idx then return nil end
    return self:GetToySourceTypeName(idx)
end

---Pure-API toy source classifier: returns the BattlePetSources filter index (1-based).
---Mirrors GetToySourceTypeNameForItem but exposes the raw integer for UI categorization.
---@return number|nil sourceIndex (1=Drop, 2=Quest, 3=Vendor, ...) or nil if untracked
function WarbandNexus:GetToySourceTypeIndexForItem(itemID)
    if not itemID then return nil end
    if ns._toyGroupedFromMapValid and ns._toyItemIDToSourceIndex then
        local fastIdx = ns._toyItemIDToSourceIndex[itemID]
        if fastIdx ~= nil then return fastIdx end
    end
    if not ns._toyItemIDToSourceIndexCache then ns._toyItemIDToSourceIndexCache = {} end
    local cache = ns._toyItemIDToSourceIndexCache
    if not cache.map then
        local _, itemIDToSource = self:GetToysGroupedBySourceType()
        cache.map = itemIDToSource or {}
    end
    return cache.map[itemID]
end

-- MOUNT: C_MountJournal source filter map (mirrors pet/toy SetSourceFilter sweep).
-- GetMountInfoByID().sourceType is often 0 ("Other") while the journal source tab is correct.

local MOUNT_SOURCE_FILTER_MAX = 24

---@return boolean|nil
local function SafeJournalBool(val)
    if issecretvalue and issecretvalue(val) then return nil end
    if val == nil then return nil end
    if val == true then return true end
    if val == false then return false end
    return nil
end

function WarbandNexus:GetMountSourceFilterCount()
    if not C_MountJournal then return 0 end
    Mat.EnsureBlizzardCollectionsLoaded()
    if C_MountJournal.IsSourceChecked then
        local maxIdx = 0
        for i = 1, MOUNT_SOURCE_FILTER_MAX do
            local ok, checked = pcall(C_MountJournal.IsSourceChecked, i)
            if ok and checked ~= nil then
                maxIdx = i
            else
                break
            end
        end
        if maxIdx > 0 then return maxIdx end
    end
    return 11
end

---Build mountID -> journal source filter index (1=Drop, 10=Shop, ...). Persists in ns._mountIDToSourceIndex.
function WarbandNexus:EnsureMountSourceIndexMap()
    if ns._mountGroupedFromMapValid and ns._mountIDToSourceIndex and next(ns._mountIDToSourceIndex) then
        return ns._mountIDToSourceIndex
    end
    local mountIDToSource = {}
    if not C_MountJournal or not C_MountJournal.SetSourceFilter or not C_MountJournal.GetDisplayedMountInfo then
        ns._mountIDToSourceIndex = mountIDToSource
        ns._mountGroupedFromMapValid = false
        return mountIDToSource
    end
    if InCombatLockdown() then
        return ns._mountIDToSourceIndex or mountIDToSource
    end
    Mat.EnsureBlizzardCollectionsLoaded()
    local count = self:GetMountSourceFilterCount()
    local origSourceFilters = {}
    for i = 1, count do
        if C_MountJournal.IsSourceChecked then
            local ok, checked = pcall(C_MountJournal.IsSourceChecked, i)
            if ok and checked ~= nil then origSourceFilters[i] = checked end
        end
    end
    local origSearch = Mat.GetMountJournalSearchText()
    -- The scan widens the collected (1-3) and type filters too; save them so the player's Mount Journal
    -- comes back as it was (2026-10-22: only source filters and search were restored).
    -- Type filter range as Blizzard_MountCollection: 1..Enum.MountTypeMeta.NumValues.
    local origCollected, origTypes = {}, {}
    if C_MountJournal.GetCollectedFilterSetting then
        for i = 1, 3 do
            local ok, checked = pcall(C_MountJournal.GetCollectedFilterSetting, i)
            if ok and not (issecretvalue and issecretvalue(checked)) and type(checked) == "boolean" then origCollected[i] = checked end
        end
    end
    local typeCount = Enum and Enum.MountTypeMeta and Enum.MountTypeMeta.NumValues
    if C_MountJournal.IsTypeChecked and type(typeCount) == "number" then
        for i = 1, typeCount do
            local ok, checked = pcall(C_MountJournal.IsTypeChecked, i)
            if ok and not (issecretvalue and issecretvalue(checked)) and type(checked) == "boolean" then origTypes[i] = checked end
        end
    end
    pcall(function()
        if C_MountJournal.SetSearch then C_MountJournal.SetSearch("") end
        if C_MountJournal.SetAllSourceFilters then C_MountJournal.SetAllSourceFilters(false) end
        if C_MountJournal.SetAllTypeFilters then C_MountJournal.SetAllTypeFilters(true) end
        if C_MountJournal.SetCollectedFilterSetting then
            C_MountJournal.SetCollectedFilterSetting(1, true)
            C_MountJournal.SetCollectedFilterSetting(2, true)
            C_MountJournal.SetCollectedFilterSetting(3, true)
        end
        for sourceIndex = 1, count do
            if C_MountJournal.SetAllSourceFilters then C_MountJournal.SetAllSourceFilters(false) end
            C_MountJournal.SetSourceFilter(sourceIndex, true)
            local numDisplayed = (C_MountJournal.GetNumDisplayedMounts and C_MountJournal.GetNumDisplayedMounts()) or 0
            if issecretvalue and numDisplayed and issecretvalue(numDisplayed) then numDisplayed = 0 end
            for j = 1, numDisplayed do
                local _, _, _, _, _, _, _, _, _, _, _, mountID = C_MountJournal.GetDisplayedMountInfo(j)
                if mountID and mountID > 0 and not (issecretvalue and issecretvalue(mountID)) then
                    if not mountIDToSource[mountID] then
                        mountIDToSource[mountID] = sourceIndex
                    end
                end
            end
        end
    end)
    -- Restore outside the scan pcall so an error mid-scan still gives the player their filters back.
    if C_MountJournal.SetAllSourceFilters then pcall(C_MountJournal.SetAllSourceFilters, true) end
    if origSearch ~= "" and C_MountJournal.SetSearch then pcall(C_MountJournal.SetSearch, origSearch) end
    for i, checked in pairs(origSourceFilters) do
        pcall(C_MountJournal.SetSourceFilter, i, checked)
    end
    if C_MountJournal.SetCollectedFilterSetting then
        for i, checked in pairs(origCollected) do
            pcall(C_MountJournal.SetCollectedFilterSetting, i, checked)
        end
    end
    if C_MountJournal.SetTypeFilter then
        for i, checked in pairs(origTypes) do
            pcall(C_MountJournal.SetTypeFilter, i, checked)
        end
    end
    ns._mountIDToSourceIndex = mountIDToSource
    ns._mountGroupedFromMapValid = next(mountIDToSource) ~= nil
    return mountIDToSource
end

---Resolve mount browse category integer: live sourceType when >0, else journal filter map.
---@return number|nil
function WarbandNexus:GetMountBrowseSourceType(mountID)
    if not mountID then return nil end
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        local _, _, _, _, _, sourceType = C_MountJournal.GetMountInfoByID(mountID)
        if sourceType and not (issecretvalue and issecretvalue(sourceType)) and sourceType > 0 then
            return sourceType
        end
    end
    self:EnsureMountSourceIndexMap()
    local fromMap = ns._mountIDToSourceIndex and ns._mountIDToSourceIndex[mountID]
    if fromMap and fromMap > 0 then return fromMap end
    return nil
end

---Hide journal-internal mounts (Soar, class placeholders). Keep cross-faction mounts visible.
---@return boolean true when the mount should be excluded from Collections / To-Do browse
function WarbandNexus:ShouldExcludeMountFromCollectionBrowse(mountID)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoByID then return true end
    local name, _, _, _, _, _, _, isFactionSpecific, _, shouldHideOnChar = C_MountJournal.GetMountInfoByID(mountID)
    if not name or (issecretvalue and issecretvalue(name)) then return true end
    local hide = SafeJournalBool(shouldHideOnChar)
    if hide ~= true then return false end
    local factionSpec = SafeJournalBool(isFactionSpecific)
    if factionSpec == true then
        return false
    end
    return true
end

---Pet species source filter index (1=Drop). Lazy-builds journal map when SV rows lack sourceTypeIndex.
---@return number|nil
function WarbandNexus:GetPetSourceTypeIndexForSpecies(speciesID)
    if not speciesID then return nil end
    local row = collectionStore.pet and collectionStore.pet[speciesID]
    if row and row.sourceTypeIndex and row.sourceTypeIndex > 0 then
        return row.sourceTypeIndex
    end
    if ns._petSpeciesToSourceIndex and ns._petSpeciesToSourceIndex[speciesID] then
        return ns._petSpeciesToSourceIndex[speciesID]
    end
    if InCombatLockdown() or not C_PetJournal then return nil end
    if ns._petSpeciesToSourceIndex and next(ns._petSpeciesToSourceIndex) then
        return ns._petSpeciesToSourceIndex[speciesID]
    end
    local st = Mat.PetJournalBuildMaterializeStep(FRAME_BUDGET_MS * 4, nil)
    while st and not st.done do
        st = Mat.PetJournalBuildMaterializeStep(FRAME_BUDGET_MS * 4, st)
    end
    if st and st.speciesToSource then
        ns._petSpeciesToSourceIndex = st.speciesToSource
    end
    return ns._petSpeciesToSourceIndex and ns._petSpeciesToSourceIndex[speciesID]
end

---Toys grouped by Blizzard source type for UI. Each item: id, name, icon, collected. DB stores only id+name.
function WarbandNexus:GetToysDataGroupedBySourceType()
    Mat.EnsureBlizzardCollectionsLoaded()
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
                    if itemName and type(itemName) == "string" and not (_issecretvalue and _issecretvalue(itemName))
                        and itemName ~= "" then
                        name = itemName
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
            table.sort(items, CmpItemName)
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

---Return cached or freshly computed collection counts from Blizzard API only.
---Single source of truth for Statistics and Collections (e.g. mount total 1577 in both).
---@return table|nil { mounts = { collected, total }, pets = { collected, totalSpecies, uniqueSpecies, journalEntries }, toys = { collected, total }, achievementPoints = number }
function WarbandNexus:GetCollectionCountsFromStore()
    if not IsCollectionEnsureDataComplete(self) then
        return nil
    end

    local data = {
        mounts = { collected = 0, total = 0 },
        pets = { collected = 0, totalSpecies = 0, uniqueSpecies = 0, journalEntries = 0 },
        toys = { collected = 0, total = 0 },
        achievementPoints = 0,
    }

    ApplyAchievementSummaryToData(self, data)

    local mountStore = collectionStore.mount
    if type(mountStore) == "table" then
        for _, row in pairs(mountStore) do
            data.mounts.total = data.mounts.total + 1
            if type(row) == "table" and row.collected == true then
                data.mounts.collected = data.mounts.collected + 1
            end
        end
    end

    local petStore = collectionStore.pet
    if type(petStore) == "table" then
        local uniqueCollected = 0
        for _, row in pairs(petStore) do
            data.pets.totalSpecies = data.pets.totalSpecies + 1
            if type(row) == "table" and row.collected == true then
                data.pets.collected = data.pets.collected + 1
                uniqueCollected = uniqueCollected + 1
            end
        end
        data.pets.uniqueSpecies = uniqueCollected
        data.pets.journalEntries = data.pets.collected
    end

    local toyStore = collectionStore.toy
    if type(toyStore) == "table" then
        for _ in pairs(toyStore) do
            data.toys.total = data.toys.total + 1
        end
        local ownedToys = collectionCache.owned and collectionCache.owned.toys
        if type(ownedToys) == "table" then
            for _ in pairs(ownedToys) do
                data.toys.collected = data.toys.collected + 1
            end
        end
    end

    return data
end

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

    ApplyAchievementSummaryToData(self, data)

    if C_MountJournal and C_MountJournal.GetMountIDs then
        local mountIDs = C_MountJournal.GetMountIDs()
        if mountIDs then
            local totalVisible = 0
            local collectedCount = 0
            for i = 1, #mountIDs do
                local _, _, _, _, _, _, _, isFactionSpecific, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(mountIDs[i])
                local hidden = false
                local hide = SafeJournalBool(shouldHideOnChar)
                if hide == true then
                    local factionSpec = SafeJournalBool(isFactionSpecific)
                    if factionSpec ~= true then
                        hidden = true
                    end
                end
                if not hidden then
                    totalVisible = totalVisible + 1
                    if issecretvalue and isCollected and issecretvalue(isCollected) then
                        collectedCount = collectedCount + 1
                    elseif isCollected == true then
                        collectedCount = collectedCount + 1
                    end
                end
            end
            data.mounts.total = totalVisible
            data.mounts.collected = collectedCount
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
                origFilterString = Mat.GetToyBoxSearchText()
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

---Invalidate the API counts cache so next GetCollectionCountsFromAPI() recomputes.
---For a confirmed mount/pet/toy OBTAIN the cached counters adjust in place instead:
---during farm sessions every obtain wiped the cache, so the next UI access paid the
---full O(journals) API pass again. Totals can drift by at most one until the 60s TTL
---recomputes (only when a journal entry is added in the same window — patch days).
function WarbandNexus:InvalidateCollectionCountsAPICache(obtainedType)
    local c = _collectionCountsAPICache
    if c and c.data then
        if obtainedType == "mount" and c.data.mounts then
            c.data.mounts.collected = (c.data.mounts.collected or 0) + 1
            return
        elseif obtainedType == "toy" and c.data.toys then
            c.data.toys.collected = (c.data.toys.collected or 0) + 1
            return
        elseif obtainedType == "pet" and c.data.pets then
            c.data.pets.collected = (c.data.pets.collected or 0) + 1
            c.data.pets.uniqueSpecies = (c.data.pets.uniqueSpecies or 0) + 1
            c.data.pets.journalEntries = (c.data.pets.journalEntries or 0) + 1
            return
        end
    end
    _collectionCountsAPICache = nil
end

---Get all achievements (complete + incomplete) for Collections UI. Uses cache from ScanAchievementsAsync.
---@return table[] Array of { id, name, icon, points, description, categoryID, collected }
function WarbandNexus:GetAllAchievementsData()
    if _allAchievementsMergedCache and not IsAchievementStoreInadequate() then
        return _allAchievementsMergedCache
    end
    ClearAchievementMergedListCache()
    if IsAchievementStoreInadequate() and self.ScanAchievementsAsync then
        self:ScanAchievementsAsync()
    end
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
    local achTotal = #out
    local achCollected = 0
    for j = 1, achTotal do
        local e = out[j]
        if e and (e.isCollected or e.collected) then
            achCollected = achCollected + 1
        end
    end
    out._wnAchCollected = achCollected
    out._wnAchTotal = achTotal
    _allAchievementsMergedCache = out
    return out
end

---Remove collectible from uncollected cache (incremental update when player obtains it)
---This is called by event handlers when player collects a new mount/pet/toy
function WarbandNexus:RemoveFromUncollected(collectionType, id)
    local uncollected = collectionCache.uncollected[collectionType]
    local entry = uncollected and uncollected[id]
    local itemName = (type(entry) == "string") and entry or (entry and entry.name) or (ns.L and ns.L["UNKNOWN"]) or "Unknown"

    if entry ~= nil then
        collectionCache.uncollected[collectionType][id] = nil
    end

    -- Single source: update collectionStore (collected=true)
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
        DebugPrintf("|cff00ff00[WN CollectionService]|r INCREMENTAL UPDATE: %s marked collected in %ss",
            itemName, collectionType)
    end
end

-- Active coroutines for async scanning
local activeCoroutines = {}
local scanCompleteCallbacks = {}

local function InvokeScanCompleteCallback(collectionType, results)
    local cb = scanCompleteCallbacks[collectionType]
    scanCompleteCallbacks[collectionType] = nil
    if cb then cb(results or {}) end
end

-- ASYNC SCAN ABORT PROTOCOL (for tab switches)

---Abort all active collection scans (called when switching away from Plans tab)
function WarbandNexus:AbortCollectionScans()
    local abortCount = 0
    for collectionType, co in pairs(activeCoroutines) do
        if co and coroutine.status(co) ~= "dead" then
            activeCoroutines[collectionType] = nil
            abortCount = abortCount + 1
            if ns.PlansLoadingState and ns.PlansLoadingState[collectionType] then
                ns.PlansLoadingState[collectionType].isLoading = false
            end
            InvokeScanCompleteCallback(collectionType, collectionStore[collectionType] or {})
        end
    end
    
    if abortCount > 0 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Aborted " .. abortCount .. " active scans (tab switch)")
    end
end

-- NOTIFICATION SEEDING (must be defined before BuildCollectionCache)

---One-time seed: mark all currently owned collectibles as notified.
---Runs once per account (when notifiedCollectibles DB is first created).
---Prevents false "You got it on your first try!" for already-owned items
---after addon update introduces the persistent dedup layer.
local function SeedNotifiedFromOwned()
    if Notify and Notify.InitializeNotifiedDB then
        Notify.InitializeNotifiedDB()
    end
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
    DebugPrintf("|cff00ccff[WN CollectionService]|r Seeded notifiedCollectibles: %d entries from owned cache", count)
end
-- Defined after the RT table constructor above, so CollectionService_Store.lua gets it here.
ns.CollectionServiceRT.SeedNotifiedFromOwned = SeedNotifiedFromOwned

-- REAL-TIME CACHE BUILDING (Fast O(1) Lookup)

---Build or refresh owned collection cache (mount/pet/toy O(1) ownership for notifications and try-counter).
---Uses time-budgeted batching: each phase yields when the 4ms budget is exceeded.
-- BuildCollectionCache: CollectionService_Store.lua


-- NEW_* handlers: CollectionService_Events.lua

---Force mount/pet/toy refetch without debug mode (lighter than rebuild full). Clears those SV maps and schedules EnsureCollectionData.
function WarbandNexus:RequestCollectionDataRefreshForce()
    if ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading then
        CollectionUserPrint(self, "|cffff8800[WN]|r Collection pipeline already running; skipped. |cff00ccff/wn collection status|r for stage.|r")
        return
    end
    if not self.db or not self.db.global then
        CollectionUserPrint(self, "|cffff6600[WN Collection]|r DB not ready.|r")
        return
    end
    local function wipeMap(t)
        if not t then return end
        for k in pairs(t) do
            t[k] = nil
        end
    end
    wipeMap(collectionStore.mount)
    wipeMap(collectionStore.pet)
    wipeMap(collectionStore.toy)
    local dbStore = self.db.global.collectionStore
    if dbStore then
        dbStore.version = "__WN_FORCE_RESYNC__"
        wipeMap(dbStore.mount)
        wipeMap(dbStore.pet)
        wipeMap(dbStore.toy)
    end
    self:InvalidateCollectionCache(nil)
    if ns.CollectionServiceRT.InvalidateCollectionCountsCache then
        ns.CollectionServiceRT.InvalidateCollectionCountsCache(nil, nil)
    end
    if ns.ScheduleEnsureCollectionDataDeferred then
        ns.ScheduleEnsureCollectionDataDeferred()
    elseif self.EnsureCollectionData then
        self:EnsureCollectionData()
    end
    CollectionUserPrint(self, "|cff00ccff[WN]|r Collection rescan scheduled (mounts, pets, toys).|r")
end

--- DEBUG ONLY (gated by CommandService + IsDebugModeEnabled): simulate a collectionStore version bump and re-fetch mount/pet/toy for profiler runs.
function WarbandNexus:DebugForceCollectionRebuild(full)
    full = full == true
    if not self.db or not self.db.global then
        CollectionUserPrint(self, "|cffff6600[WN Collection]|r DB not ready.|r")
        return
    end
    local function wipeMap(t)
        if not t then return end
        for k in pairs(t) do
            t[k] = nil
        end
    end
    wipeMap(collectionStore.mount)
    wipeMap(collectionStore.pet)
    wipeMap(collectionStore.toy)
    if full then
        wipeMap(collectionStore.achievement)
        wipeMap(collectionStore.title)
        wipeMap(collectionStore.illusion)
    end
    local dbStore = self.db.global.collectionStore
    if dbStore then
        dbStore.version = "__WN_DEBUG_FORCE_REBUILD__"
        wipeMap(dbStore.mount)
        wipeMap(dbStore.pet)
        wipeMap(dbStore.toy)
        if full then
            wipeMap(dbStore.achievement)
            wipeMap(dbStore.title)
            wipeMap(dbStore.illusion)
        end
    end
    self:InvalidateCollectionCache(nil)
    if ns.CollectionServiceRT.InvalidateCollectionCountsCache then
        ns.CollectionServiceRT.InvalidateCollectionCountsCache(nil, nil)
    end
    CollectionUserPrint(self, "|cff00ccff[WN Collection]|r Debug rebuild started (mount/pet/toy" ..
        (full and " + achievements/titles/illusions" or "") ..
        "). Use |cff00ccff/wn profiler on|r then open Collections.|r")
    self:EnsureCollectionData(function()
        CollectionUserPrint(self, "|cff00ff00[WN Collection]|r Debug rebuild finished.|r")
    end)
end

---Handle ACHIEVEMENT_EARNED event
---Removes completed achievement from cache and handles chained achievements
function WarbandNexus:OnAchievementEarned(event, achievementID)
    if not achievementID then return end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r Achievement earned: " .. achievementID)

    -- Module gate: store/cache writes only while Collections or Plans consume them.
    -- Character achievement points (Characters tab) and the toast below always run.
    local storeOn = ns.Utilities and ns.Utilities:IsAnyModuleEnabled("collections", "plans") or false
    local prevAchEntry = collectionStore.achievement and collectionStore.achievement[achievementID]
    local priorAchievementCollected = prevAchEntry and prevAchEntry.collected == true

    if storeOn then
        -- Remove completed achievement from cache
        if collectionCache.uncollected.achievement and collectionCache.uncollected.achievement[achievementID] then
            collectionCache.uncollected.achievement[achievementID] = nil
        DebugPrint("|cff9370DB[WN CollectionService]|r Removed completed achievement " .. achievementID .. " from cache")
        end

        -- Mark as collected in store so Collections UI and GetAllAchievementsData show it as completed
        if not collectionStore.achievement then collectionStore.achievement = {} end
        if not prevAchEntry then
            collectionStore.achievement[achievementID] = { id = achievementID, collected = true }
        else
            prevAchEntry.collected = true
        end
        self:SaveCollectionStore()
    end

    if not priorAchievementCollected and GetAchievementInfo then
        -- GetAchievementInfo: points(3) ... rewardText(11), isGuild(12), wasEarnedByMe(13)
        local okPts, _, _, pts, _, _, _, _, _, _, _, _, isGuild, wasEarnedByMe = pcall(GetAchievementInfo, achievementID)
        if okPts and IsAchievementEarnedByMe(wasEarnedByMe) and isGuild ~= true then
            local pt = tonumber(pts) or 0
            if pt > 0 then
                local charKey = (ns.CharacterService and ns.CharacterService.GetCharactersTablePersistKey
                    and ns.CharacterService:GetCharactersTablePersistKey(self))
                    or (ns.Utilities and ns.Utilities.GetCharacterStorageKey
                    and ns.Utilities:GetCharacterStorageKey(self))
                if charKey and not (issecretvalue and issecretvalue(charKey)) then
                    local chars = self.db and self.db.global and self.db.global.characters
                    local row = chars and chars[charKey]
                    if not row and self.SaveCurrentCharacterData then
                        self:SaveCurrentCharacterData({ lightOnly = true })
                        row = chars and chars[charKey]
                    end
                    if row then
                        local prev = tonumber(row.achievementPointsEarned) or 0
                        row.achievementPointsEarned = prev + pt
                        row.achievementPointsResolvedAt = time()
                        _achievementCharacterPointsCache = {
                            charKey = charKey,
                            points = row.achievementPointsEarned,
                            timestamp = GetTime(),
                        }
                        _collectionCountsAPICache = nil
                    end
                end
            end
        end
    end

    -- Check for chained/superceding achievements (e.g., 5/5 → 0/10)
    -- GetSupercedingAchievements returns the next achievement in the chain (store/cache write: gated)
    if storeOn and C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements then
        if not (issecretvalue and achievementID and issecretvalue(achievementID)) then
            local okSup, supercedingAchievements = pcall(C_AchievementInfo.GetSupercedingAchievements, achievementID)
            if okSup and supercedingAchievements and type(supercedingAchievements) == "table" and #supercedingAchievements > 0 then
                for i = 1, #supercedingAchievements do
                    local nextAchievementID = supercedingAchievements[i]
                    if nextAchievementID and not (issecretvalue and issecretvalue(nextAchievementID)) then
                        -- Get achievement info with pcall protection
                        local success, id, name, points, completed, month, day, year, description, flags, icon = pcall(GetAchievementInfo, nextAchievementID)
                        local completedIsSecret = completed and issecretvalue and issecretvalue(completed)
                        if success and name and not (issecretvalue and issecretvalue(name))
                            and not completedIsSecret and completed ~= true then
    DebugPrint("|cffffcc00[WN CollectionService]|r Found chained achievement: " .. tostring(name) .. " (ID: " .. tostring(nextAchievementID) .. ")")
                    
                    -- Get category ID
                    local categoryID
                    if GetAchievementCategory then
                        local okCat, cat = pcall(GetAchievementCategory, nextAchievementID)
                        if okCat and cat and not (issecretvalue and issecretvalue(cat)) then
                            categoryID = cat
                        end
                    end
                    
                    -- Get reward info (with pcall)
                    local rewardItemID, rewardTitle
                    local rewardSuccess, item, title = pcall(GetAchievementReward, nextAchievementID)
                    if rewardSuccess then
                        if type(item) == "number" and not (issecretvalue and issecretvalue(item)) then
                            rewardItemID = item
                        end
                        if type(title) == "string" and not (issecretvalue and issecretvalue(title)) and title ~= "" then
                            rewardTitle = title
                        elseif type(item) == "string" and not (issecretvalue and issecretvalue(item)) and item ~= "" then
                            rewardTitle = item
                        end
                    end
                    
                    local safeDesc = description
                    if safeDesc and issecretvalue and issecretvalue(safeDesc) then safeDesc = nil end
                    
                    -- Add new chained achievement to cache directly (no full re-scan needed!)
                    if not collectionCache.uncollected.achievement then
                        collectionCache.uncollected.achievement = {}
                    end
                    
                    local safePoints = points
                    if safePoints and issecretvalue and issecretvalue(safePoints) then safePoints = nil end
                    local safeIcon = (icon and not (issecretvalue and issecretvalue(icon))) and icon or nil
                    collectionCache.uncollected.achievement[nextAchievementID] = {
                        id = nextAchievementID,
                        name = name,
                        points = safePoints,
                        description = safeDesc,
                        icon = safeIcon,
                        type = "achievement",
                        rewardItemID = rewardItemID,
                        rewardTitle = rewardTitle,
                        categoryID = categoryID
                    }

                    -- Store-driven Plans/Collections read collectionStore, not the legacy
                    -- cache; without this record the chained achievement stays invisible
                    -- until the next full achievement scan.
                    if not collectionStore.achievement[nextAchievementID] then
                        collectionStore.achievement[nextAchievementID] = {
                            id = nextAchievementID,
                            name = name,
                            icon = safeIcon,
                            points = safePoints,
                            description = safeDesc,
                            collected = false,
                            categoryID = categoryID,
                            rewardItemID = rewardItemID,
                            rewardTitle = rewardTitle,
                        }
                        self:SaveCollectionStore()
                    end

    DebugPrint("|cff00ff00[WN CollectionService]|r Added chained achievement to cache: " .. tostring(name))
                    
                    -- Trigger UI refresh (no cache invalidation needed!)
                    if self.SendMessage then
                        self:SendMessage(E.COLLECTION_UPDATED, "achievement")
                    end
                    
                    break -- Only need to process one chained achievement
                end
                    end
                end
            end
        end
    end
    
    -- Notify UI so Collections tab updates immediately (achievement earned).
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
        self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "achievement")
    end
    -- Emit collectible toast only for a genuinely new completion (store already had .collected skips spam).
    -- AddAlert hook may still run; MarkAsNotified here prevents duplicate toast when priorCollected.
    -- Toast: Warband achievement popups ON uses AddAlert replacement; OFF uses Blizzard AddAlert only.
    local useWarbandPopups = ns.NotificationPresentation
        and ns.NotificationPresentation.UseWarbandAchievementPopups()
    if priorAchievementCollected then
        Notify.MarkAsNotified("achievement", achievementID)
        Notify.MarkAsPermanentlyNotified("achievement", achievementID)
        DebugPrint("|cff888888[WN CollectionService]|r Skip achievement toast (already completed in collection store)")
    elseif useWarbandPopups then
        -- Defer toast to NotificationManager's AddAlert hook (ShowAchievementNotification).
        -- Do NOT MarkAsNotified here: ACHIEVEMENT_EARNED often fires before AddAlert; pre-marking
        -- makes ShowAchievementNotification return true (handled) without showing, while the hook
        -- swallows Blizzard's frame — user sees no popup at all.
        DebugPrint("|cff888888[WN CollectionService]|r Defer achievement toast to AddAlert replacement")
        if Notify.ScheduleAchievementToastFallback then
            Notify.ScheduleAchievementToastFallback(achievementID)
        end
    elseif not Notify.WasRecentlyNotified("achievement", achievementID) then
        Notify.MarkAsNotified("achievement", achievementID)
        local ok, _aid, achName, achPoints, _c, _m, _d, _y, _desc, _flags, achIcon = pcall(GetAchievementInfo, achievementID)
        if not ok then achName = nil; achIcon = nil; achPoints = nil end
        if issecretvalue then
            if achName and issecretvalue(achName) then achName = nil end
            if achIcon and issecretvalue(achIcon) then achIcon = nil end
            if achPoints and issecretvalue(achPoints) then achPoints = nil end
        end
        local displayName = achName or ((ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement")
        local displayIcon = achIcon
        Notify.MarkAsPermanentlyNotified("achievement", achievementID)
        -- Classic mode (Warband popups OFF): Blizzard's own popup is the visible alert; the
        -- message still feeds try-counter/recent-ring/caches but must not ALSO toast
        -- (it double-popped). suppressToast skips only the popup in NotificationManager.
        self:SendMessage(E.COLLECTIBLE_OBTAINED, {
            type = "achievement",
            id = achievementID,
            name = displayName,
            icon = displayIcon,
            achievementPoints = (type(achPoints) == "number" and achPoints > 0) and achPoints or nil,
            obtainedBy = Notify.CollectiblePayloadObtainedBy(),
            accountFirstEarn = true,
            suppressToast = true,
        })
    end
end

---Called from AddAlert hook when Warband achievement popups are ON.
---@return boolean shown false when the WN toast will NOT appear — the AddAlert hook then falls back to the Blizzard popup
function WarbandNexus:ShowAchievementNotification(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return false end
    if issecretvalue and issecretvalue(achievementID) then return false end
    local NP = ns.NotificationPresentation
    if not NP or not NP.CanShowWarbandAchievementEarnedToast() then return false end
    -- Session dedup: only report handled when toast was displayed or permanently recorded.
    if Notify.WasRecentlyNotified("achievement", achievementID) then
        if Notify.WasAchievementToastDisplayed(achievementID)
            or Notify.WasAlreadyNotified("achievement", achievementID) then
            return true
        end
        -- Stale session mark without a displayed toast — allow retry / fallback.
    end
    local ok, _aid, achName, achPoints, _c, _m, _d, _y, _desc, _flags, achIcon = pcall(GetAchievementInfo, achievementID)
    if not ok then achName = nil; achIcon = nil; achPoints = nil end
    if issecretvalue then
        if achName and issecretvalue(achName) then achName = nil end
        if achIcon and issecretvalue(achIcon) then achIcon = nil end
        if achPoints and issecretvalue(achPoints) then achPoints = nil end
    end
    local displayName = achName
    local displayIcon = achIcon
    if not displayName or displayName == "" then
        displayName = (ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement"
        displayIcon = nil
    end
    local accountFirstEarn = true
    -- wasEarnedByMe is GetAchievementInfo's 13th return (12th = isGuild)
    local okEarn, _, _, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = pcall(GetAchievementInfo, achievementID)
    if okEarn and completed == true and wasEarnedByMe == false then
        accountFirstEarn = false
    end
    self:SendMessage(E.COLLECTIBLE_OBTAINED, {
        type = "achievement",
        id = achievementID,
        name = displayName,
        icon = displayIcon,
        achievementPoints = (type(achPoints) == "number" and achPoints > 0) and achPoints or nil,
        obtainedBy = Notify.CollectiblePayloadObtainedBy(),
        accountFirstEarn = accountFirstEarn,
    })
    return Notify.WasAchievementToastDisplayed and Notify.WasAchievementToastDisplayed(achievementID) or false
end

-- Register achievement earned event for cache invalidation
-- Must be AFTER function definition
WarbandNexus:RegisterEvent("ACHIEVEMENT_EARNED", "OnAchievementEarned")

-- REAL-TIME COLLECTION DETECTION

---Check if an item is a NEW collectible that player doesn't own
---Used for real-time detection (inventory/bank scanning)
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
    
    -- MOUNT (classID 15, subclass 5)
    if classID == 15 and subclassID == 5 then
        local result = self:_DetectMount(itemID, itemName, itemIcon)
        if result then return result end
    end
    
    -- PETS (Battle Pets: classID 17, Companion Pets: classID 15/subclass 2)
    if classID == 17 or (classID == 15 and subclassID == 2) then
        local result = self:_DetectPet(itemID, hyperlink, itemName, itemIcon, classID, subclassID)
        if result then return result end
    end
    
    -- TOY (classID 15/subclass 0, or classID 0 - Consumable-type toys like vendor elixirs)
    if (classID == 15 and subclassID == 0) or classID == 0 then
        local result = self:_DetectToy(itemID, itemName, itemIcon)
        if result then return result end
    end
    
    -- FALLBACK: classID 15/0 items that didn't match specific branches
    -- Some vendor pets/mounts have unexpected subclassIDs (e.g., subclass 4 "Other")
    -- Only check items that have a "Use:" spell (skips junk like Spare Parts, Pet Charms)
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
    
    -- FALLBACK 2: classID 15 subclass 2 where GetPetInfoByItemID failed
    -- Try hyperlink-based detection as alternative
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

-- DETECTION HELPERS (DRY extraction from CheckNewCollectible)

---Try to detect a mount from itemID
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
    if Notify.WasDetectedInBag("mount", mountID) then return nil end
    if Notify.WasRecentlyShownByName(name) then return nil end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW MOUNT DETECTED: " .. name .. " (ID: " .. mountID .. ")")
    return {
        type = "mount",
        id = mountID,
        name = name,
        icon = icon
    }
end

---Try to detect a pet from itemID/hyperlink using multiple methods
---@return table|nil
function WarbandNexus:_DetectPet(itemID, hyperlink, itemName, itemIcon, classID, subclassID)
    if not C_PetJournal then return nil end
    
    local speciesID = nil
    local speciesName = nil
    local speciesIcon = nil
    
    -- Method 1: Battle Pet Cage (classID 17) - extract speciesID from hyperlink
    if classID == 17 and hyperlink and type(hyperlink) == "string" and not (issecretvalue and issecretvalue(hyperlink)) then
        speciesID = tonumber(hyperlink:match("|Hbattlepet:(%d+):"))
        if speciesID then
            speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        end
    end
    
    -- Method 2: Companion Pet Item - use C_PetJournal.GetPetInfoByItemID
    -- Return signature is (name, icon, petType, creatureID, sourceText, description,
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
    
    -- Method 4: ITEM-BASED FALLBACK
    -- C_PetJournal.GetPetInfoByItemID doesn't support all items (API limitation).
    -- For confirmed companion pet items (classID=15, subclass=2), verify via GetItemSpell
    -- and use item info (name/icon) for the notification instead of species info.
    -- The NEW_PET_ADDED event will handle the authoritative collection detection when learned.
    if classID == 15 and subclassID == 2 then
        local getItemSpell = C_Item and C_Item.GetItemSpell
        local spellName, spellID = nil, nil
        if getItemSpell then
            spellName, spellID = getItemSpell(itemID)
        end
        if spellName and spellID then
    DebugPrint("|cffffcc00[WN CollectionService]|r Pet item fallback: GetPetInfoByItemID failed, using item info. spell=" .. tostring(spellName) .. " spellID=" .. tostring(spellID))
            
            local petName = itemName or ((ns.L and ns.L["FALLBACK_UNKNOWN_PET"]) or "Unknown Pet")
            
            -- DUPLICATE PREVENTION (use item-based key since we don't have speciesID)
            if Notify.WasDetectedInBag("pet_item", itemID) then return nil end
            if Notify.WasRecentlyShownByName(petName) then return nil end
            
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
    if Notify.WasDetectedInBag("pet", speciesID) then return nil end
    if Notify.WasRecentlyShownByName(petName) then return nil end
    
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
            local lineText = line.leftText
            if issecretvalue and issecretvalue(lineText) then
                lineText = nil
            end
            -- Some items embed battlepet:speciesID in tooltip
            if lineText then
                local speciesID = tonumber(lineText:match("battlepet:(%d+)"))
                if speciesID then
    DebugPrint("|cff00ccff[WN CollectionService]|r Tooltip detection found speciesID: " .. speciesID .. " for itemID: " .. itemID)
                    return speciesID
                end
            end
        end
    end
    
    return nil
end

---Try to detect a toy from itemID
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
    if Notify.WasDetectedInBag("toy", itemID) then return nil end
    if Notify.WasRecentlyShownByName(toyName) then return nil end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r NEW TOY DETECTED: " .. toyName .. " (ID: " .. itemID .. ")")
    return {
        type = "toy",
        id = itemID,
        name = toyName,
        icon = toyIcon or itemIcon,
        itemQuality = itemQuality,
    }
end

-- Background scanning (COLLECTION_CONFIGS, ScanCollection): CollectionService_JournalScan.lua

-- Collection metadata + toy source resolve: CollectionService_Metadata.lua

-- GetUncollected* / GetCollected* queries: CollectionService_Queries.lua

-- Achievement scan + character points recompute: CollectionService_Achievements.lua

-- Achievement reward scanner: CollectionService_Achievements.lua

-- Shared with the satellites loaded after this file, which bind these from RT at load:
-- CollectionService_JournalScan.lua, _Metadata.lua, _Queries.lua, _Achievements.lua.
do
    local RT = ns.CollectionServiceRT
    RT.DebugPrintf = DebugPrintf
    RT.GetCategoryAchievementListCount = GetCategoryAchievementListCount
    RT.EnsurePlansAchievementLoadingState = EnsurePlansAchievementLoadingState
    RT.SafeAchievementDisplayName = SafeAchievementDisplayName
    RT.IsAchievementEarnedByMe = IsAchievementEarnedByMe
    RT.GetAchievementEarnedByMeInfo = GetAchievementEarnedByMeInfo
    RT.GetAchievementInfoByCategoryIndex = GetAchievementInfoByCategoryIndex
    RT.NeedsCharacterAchievementPointsRecompute = NeedsCharacterAchievementPointsRecompute
    RT.PersistCharacterAchievementPoints = PersistCharacterAchievementPoints
    RT.NormalizeCollectionSearchText = NormalizeCollectionSearchText
    RT.CollectionNameMatchesSearch = CollectionNameMatchesSearch
    RT.SendCollectionScanProgress = SendCollectionScanProgress
    RT.ScheduleEnsureCollectionDataDeferred = ScheduleEnsureCollectionDataDeferred
    RT.EmitPlansBrowseCollectionEnsure = EmitPlansBrowseCollectionEnsure
    RT.ACHIEVEMENT_STORE_MIN_TRUST = ACHIEVEMENT_STORE_MIN_TRUST
    RT.MarkCategoryScanComplete = MarkCategoryScanComplete
    RT.ClearCategoryScanComplete = ClearCategoryScanComplete
    RT.CountAchievementStoreEntries = CountAchievementStoreEntries
    RT.IsAchievementStoreInadequate = IsAchievementStoreInadequate
    RT.SignalAchievementScanPipelineDone = SignalAchievementScanPipelineDone
    RT.RESULTS_CACHE_TTL = RESULTS_CACHE_TTL
    RT.uncollectedResultsCache = uncollectedResultsCache
    RT.activeCoroutines = activeCoroutines
    RT.scanCompleteCallbacks = scanCompleteCallbacks
    RT.InvokeScanCompleteCallback = InvokeScanCompleteCallback
end

-- Bag scan satellite: CollectionService_Scan.lua (OnBagUpdateForCollectibles + event host)
local CollectionScan = ns.CollectionScan
assert(CollectionScan and CollectionScan.InstallBagScanListener, "CollectionService: load CollectionService_Scan.lua first")
CollectionScan.InstallBagScanListener()

-- Expose CollectionService reference for external modules
ns.CollectionService = ns.CollectionService or {}
ns.CollectionService.collectionCache = collectionCache

-- INITIALIZATION

-- Module loaded - verbose logging removed for normal users
