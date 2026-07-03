--[[
    Warband Nexus - Currency Cache Service
    Lean per-character quantity cache; metadata from C_CurrencyInfo on demand.
    Emits WN_CURRENCY_UPDATED and WN_CURRENCY_GAINED after writes.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- Midnight 12.0+: GUIDs from APIs may be secret — never compare or substring without guarding.
local issecretvalue = issecretvalue

local function IsUsableCurrencyName(name)
    if name == nil or name == "" then return false end
    if issecretvalue and issecretvalue(name) then return false end
    return true
end

local function CurrencyNameForLogic(currencyID, nameFallback)
    if IsUsableCurrencyName(nameFallback) then
        return nameFallback
    end
    return ""
end

---Tracker / meta rows in the currency list (not player-facing gains).
local function IsTrackerMetaCurrencyName(nm)
    if not nm or nm == "" then return false end
    if issecretvalue and issecretvalue(nm) then return false end
    if nm:find("Tracker", 1, true)
        or nm:find("EVERGREEN", 1, true)
        or nm:find("Weekly Cap", 1, true)
        or nm:find("Account Rewards", 1, true)
        or nm:match("^Renown%s*%-" ) ~= nil then
        return true
    end
    -- Internal Delves / affix bookkeeping rows (still fire CURRENCY_DISPLAY_UPDATE + look like real currencies)
    local lower = string.lower(nm)
    if lower:find("seasonal affix", 1, true) then
        return true
    end
    if lower:find("events active", 1, true) or lower:find("events maximum", 1, true) then
        if lower:find("delves", 1, true) or lower:find("system", 1, true) then
            return true
        end
    end
    if lower:find("delves", 1, true) and lower:find("system", 1, true) then
        return true
    end
    if nm:find("%d+%.%d+", 1) and nm:find("Delves", 1, true) then
        return true
    end
    -- Scenario / challenge internal scoring rows (CURRENCY_DISPLAY_UPDATE, not Currency panel)
    if nm:match("^Challenge%s*%-") then return true end
    if nm:match("^Sites%s") then return true end
    if nm:match("^Total%s") then return true end
    -- Profession order-book capacity rows (CURRENCY_DISPLAY_UPDATE; not Currency panel)
    if lower:find("public order capacity", 1, true) then return true end
    return false
end

-- Whitelist: currency IDs observed during scans (accumulates across FullScans and sessions).
-- Backed by db.global.currencyData.visibleCurrencyIDs — seeded from GetCurrencyList during FullScan.
-- Event-path chat/DB updates also require panel visibility (ShouldIgnoreCurrencyEvent) after first scan.
local function GetVisibleCurrencyIDs()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    local root = WarbandNexus.db.global.currencyData
    if not root then return nil end
    if not root.visibleCurrencyIDs then
        root.visibleCurrencyIDs = {}
    end
    return root.visibleCurrencyIDs
end

local function MarkCurrencyVisible(currencyID)
    if not currencyID or currencyID == 0 then return end
    local set = GetVisibleCurrencyIDs()
    if set then set[currencyID] = true end
end

local function IsCurrencyVisibleKnown(currencyID)
    local set = GetVisibleCurrencyIDs()
    return set and set[currencyID] == true
end

local function IsVisibleSetEmpty()
    local set = GetVisibleCurrencyIDs()
    if not set then return true end
    return next(set) == nil
end

---Event-path currencies must be player-facing panel rows (FullScan seeds visibleCurrencyIDs from GetCurrencyList).
local function ShouldIgnoreCurrencyEvent(currencyID, currencyData, apiInfo)
    if not currencyID or currencyID == 0 then return true end
    if not apiInfo and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local okInfo, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        apiInfo = okInfo and info or nil
    end
    if apiInfo and apiInfo.isHeader == true then return true end
    local nm = (currencyData and currencyData.name) or ""
    if (nm == "" or nm == ("Currency #" .. tostring(currencyID)))
        and apiInfo and apiInfo.name and not (issecretvalue and issecretvalue(apiInfo.name)) then
        nm = apiInfo.name
    end
    if IsTrackerMetaCurrencyName(nm or "") then return true end
    if apiInfo and apiInfo.name and not (issecretvalue and issecretvalue(apiInfo.name)) then
        if IsTrackerMetaCurrencyName(apiInfo.name) then return true end
    end
    if not IsVisibleSetEmpty() and not IsCurrencyVisibleKnown(currencyID) then return true end
    return false
end

-- Import dependencies
local Constants = ns.Constants
local E = Constants.EVENTS

-- Debug print helper (suppressed unless debugMode + debugVerbose; suppressed when debugTryCounterLoot so loot debug is readable)
local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter(
    "|cff00ffff[CurrencyCache]|r",
    { verboseOnly = true, suppressWhenTryCounterLoot = true }
)) or function() end

-- STATE (Minimal - No RAM cache)

local CurrencyCache = {
    -- Metadata only (no data storage)
    version = Constants.CURRENCY_CACHE_VERSION,
    lastFullScan = 0,
    lastUpdate = 0,
    
    -- Queue: FIFO for currency updates (multi-currency loot can fire many events in one frame).
    updateQueue = {},       -- { currencyID, ... } — use table.remove(1); do not leave nil holes (# is undefined with holes)
    isDraining = false,     -- While true, OnCurrencyUpdate only appends; one drain loop drains until empty
    --- True while a C_Timer.After(0) resume for DrainCurrencyQueue is scheduled (avoids duplicate timers).
    drainResumePending = false,
    --- Successful UpdateSingleCurrency calls in the current drain session (may span budgeted slices).
    _drainBcCount = 0,
    _drainBcSingleId = nil,

    --- Deferred split-currency chat: invalidate stale C_Timer.After when same ID updates again same frame.
    deferGainToken = {},    -- [currencyID] = number
    
    -- Throttle timers
    fullScanThrottle = nil,
    
    -- Flags
    isInitialized = false,
    isScanning = false,
    initScanPending = false,  -- True while waiting for the initial 5s delayed scan; suppresses event-driven FullScans
    -- Login: CURRENCY_DISPLAY_UPDATE spam runs UpdateSingleCurrency before the delayed FullScan seeds SV;
    -- without this, every ID looks like a fresh gain. Cleared after the first successful PerformFullScan (needsScan path).
    suppressCurrencyGainChatUntilScan = false,
    -- Init/Clear already broadcast LOADING_STARTED; skip duplicate when deferred PerformFullScan runs.
    skipNextCurrencyLoadingStartedBroadcast = false,
    --- Merged UI read model (rebuilt from DB + metadata cache; see RebuildMergedCurrenciesUIReadModel).
    mergedUIReadModel = nil,
    mergedUIReadModelGen = -2,
    --- Last CURRENCY_DISPLAY_UPDATE (GetTime); CHAT_MSG_CURRENCY fallback skips when recent.
    _lastCurrencyDisplayEventAt = 0,
    _broadScanTimer = nil,
    _currencyDrainKickTimer = nil,
    pendingPostCombatScan = false,
}

-- Loading state for UI (similar to ReputationLoadingState pattern)
ns.CurrencyLoadingState = ns.CurrencyLoadingState or {
    isLoading = false,
    loadingProgress = 0,
    currentStage = "Preparing...",
}

-- SESSION-ONLY METADATA CACHE (never persisted)

local currencyMetadataCache = {}          -- [currencyID] = { name, icon, ... }
local currencyMetadataCacheOrder = {}     -- Circular buffer eviction order
local currencyMetadataCacheHead = 1       -- Circular buffer head index
local CURRENCY_METADATA_CACHE_MAX = 256

---Normalize API quantity for currencies that expose "total earned" style values.
---Some capped currencies report (max + current); we want display = current on hand.

---Coffer Key Shards: ID drifts by patch — detect by localized name only.
local function IsCofferKeyShardByApiInfo(info)
    if not info or not info.name then return false end
    local nm = info.name
    if issecretvalue and issecretvalue(nm) then return false end
    local n = string.lower(tostring(nm))
    return n:find("coffer", 1, true) ~= nil and n:find("shard", 1, true) ~= nil
end

---Season-style UI: Blizzard marks progress-style currencies with useTotalEarnedForMaxQty.
---No hardcoded currency ID lists — new 12.0.x currencies work when the API sets these flags.
local function IsSeasonProgressSplitCurrency(currencyID, info)
    if not info then return false end
    if info.isHeader then return false end
    if info.useTotalEarnedForMaxQty == true then return true end
    if IsCofferKeyShardByApiInfo(info) then return true end
    if ns.Utilities and ns.Utilities.IsWeeklyCapCurrency and ns.Utilities:IsWeeklyCapCurrency(currencyID, info.name) then
        return true
    end
    return false
end

--- Safe tonumber for C_CurrencyInfo fields (Midnight may return secret values).
local function SafeCurrencyNumber(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

--- Season denominator for "Current / Season Max" + cap coloring (totalEarned vs cap).
--- Prefer maxQuantity when set (Blizzard's season cap for Dawncrests/shards). Some currencies
--- expose only maxWeeklyQuantity for the same cap — if we leave seasonMax nil, UI falls back to
--- weekly branch and treats bag qty 0 as "not capped" → wrong green for capped Coffer Key Shards.
local function SeasonMaxFromSplitCurrencyInfo(currencyID, info)
    if not info or not IsSeasonProgressSplitCurrency(currencyID, info) then return nil end
    local maxQ = SafeCurrencyNumber(info.maxQuantity) or 0
    local maxWeekly = SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
    if maxQ > 0 then
        return maxQ
    end
    if maxWeekly > 0 then
        return maxWeekly
    end
    return nil
end

--- Legacy global (if present): earned-this-week may differ from structured API on some builds.
local function LegacyEarnedThisWeekFromGlobal(currencyID)
    local gf = rawget(_G, "GetCurrencyInfo")
    if type(gf) ~= "function" then return nil end
    -- Legacy order (pre-9.0): name, quantity, texture, earnedThisWeek, weeklyMax, totalMax, ...
    local ok, _n, _q, _tex, earnedThisWeek = pcall(gf, currencyID)
    if not ok then return nil end
    return SafeCurrencyNumber(earnedThisWeek)
end

--- Progress for Season line + cap color.
--- Coffer Key Shards: Blizzard "Weekly Maximum" uses quantityEarnedThisWeek; totalEarned may be 0, wrong, or secret
--- while useTotalEarnedForMaxQty is true — must not stop at totalEarned only.
local function ProgressEarnedFromCurrencyInfo(currencyID, info)
    if not info then return nil end
    local te = SafeCurrencyNumber(info.totalEarned)
    local qew = SafeCurrencyNumber(info.quantityEarnedThisWeek)
    local tracked = SafeCurrencyNumber(info.trackedQuantity)
    local useTotal = info.useTotalEarnedForMaxQty == true

    if IsCofferKeyShardByApiInfo(info)
        or (ns.Utilities and ns.Utilities.IsWeeklyCapCurrency and ns.Utilities:IsWeeklyCapCurrency(currencyID, info.name))
        or (ns.Utilities and ns.Utilities.IsRestoredCofferKeyCurrency and ns.Utilities:IsRestoredCofferKeyCurrency(currencyID, info.name)) then
        -- Do NOT max() across fields: totalEarned can be cumulative (e.g. 1800) while UI cap is weekly/season (600) → bogus "1800/600".
        -- quantityEarnedThisWeek is authoritative for this-week progress, including 0 after weekly reset.
        local maxW = SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
        local maxQ = SafeCurrencyNumber(info.maxQuantity) or 0
        local cap = (maxW > 0) and maxW or maxQ
        local function clampToCap(v)
            if v == nil or cap <= 0 then return v end
            if v > cap then return cap end
            return v
        end
        if qew ~= nil then
            return clampToCap(qew)
        end
        if tracked ~= nil and tracked > 0 then
            return clampToCap(tracked)
        end
        if te ~= nil then
            return clampToCap(te)
        end
        local leg = LegacyEarnedThisWeekFromGlobal(currencyID)
        if leg ~= nil then return clampToCap(leg) end
        return nil
    end

    if useTotal and te ~= nil then
        return te
    end
    if info.canEarnPerWeek and qew ~= nil then
        return qew
    end
    local maxW = SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
    if maxW > 0 and qew ~= nil then
        return qew
    end
    if tracked ~= nil then
        return tracked
    end
    return te
end

---When quantity > maxQuantity we treat as (cap + current) and use quantity - cap.
local function NormalizeQuantity(rawQuantity, maxQuantity, useTotalEarnedForMaxQty)
    local quantity = SafeCurrencyNumber(rawQuantity) or 0
    local cap = SafeCurrencyNumber(maxQuantity) or 0
    if cap > 0 and quantity > cap then
        quantity = quantity - cap
    end
    if quantity < 0 then
        quantity = 0
    end
    return quantity
end

--- Cap for NormalizeQuantity (strip Blizzard "cap + held" encoding when quantity > cap).
--- Coffer Key Shards: bag quantity is literal; maxWeeklyQuantity is weekly earn cap only —
--- using it as normCap turns e.g. 1625 into 1025 when weekly max is 600.
local function NormalizationCapFromCurrencyInfo(currencyID, info)
    if not info then return 0 end
    local maxQ = SafeCurrencyNumber(info.maxQuantity) or 0
    local maxWeekly = SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
    if IsCofferKeyShardByApiInfo(info) or (ns.Utilities and ns.Utilities.IsWeeklyCapCurrency and ns.Utilities:IsWeeklyCapCurrency(currencyID, info.name)) then
        return (maxQ > 0) and maxQ or 0
    end
    local normCap = (maxQ > 0) and maxQ or maxWeekly
    if normCap == 0 and IsSeasonProgressSplitCurrency(currencyID, info) then
        normCap = 200
    end
    return normCap
end

-- DB ACCESS (Direct - No RAM cache)

---Get direct reference to currency DB
local function GetDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    
    -- Initialize structure if needed
    if not WarbandNexus.db.global.currencyData then
        WarbandNexus.db.global.currencyData = {
            version = CurrencyCache.version,
            lastScan = 0,
            currencies = {},
            headers = {},  -- Blizzard currency headers structure
            visibleCurrencyIDs = {},  -- cumulative whitelist for notifications
        }
    end
    if not WarbandNexus.db.global.currencyData.visibleCurrencyIDs then
        WarbandNexus.db.global.currencyData.visibleCurrencyIDs = {}
    end

    return WarbandNexus.db.global.currencyData
end

--- Canonical subsidiary DB key (matches `db.global.characters` / MigrationService GUID keys).
local function CurrencySubsidiaryKey(optionalCharKey)
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey then
        return CS:ResolveSubsidiaryCharacterKey(WarbandNexus, optionalCharKey)
    end
    local k = optionalCharKey
    if not k and ns.Utilities and ns.Utilities.GetCharacterStorageKey then
        k = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    end
    if k and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(k) or k
    end
    return k
end

--- Remove Name-Realm / legacy alias rows after a canonical write (one bucket per character).
local function PruneCurrencyAliasBuckets(db, charKey)
    if not db or not charKey or not ns.VaultCharKeysMatch then return end
    charKey = CurrencySubsidiaryKey(charKey)
    if not charKey then return end
    local function prune(tbl)
        if type(tbl) ~= "table" then return end
        for k in pairs(tbl) do
            if k ~= charKey and ns.VaultCharKeysMatch(k, charKey) then
                tbl[k] = nil
            end
        end
    end
    if db.currencies then prune(db.currencies) end
    if db.totalEarned then prune(db.totalEarned) end
end

-- Memoized alias-bucket resolution for cross-key SV lookups (GUID write key vs
-- Name-Realm roster index). Positive matches are permanent — alias relations do
-- not change within a session; misses expire after 30s so a bucket created later
-- (a character's first write) becomes visible without invalidation plumbing.
-- Without this, the merged read-model rebuild degraded to O(currencies × chars²).
local currencyAliasBuckets = {}  -- [charKey] = { k1, k2, ... } matching bucket keys
local currencyAliasMissAt = {}   -- [charKey] = GetTime() of last full-scan miss

-- Per-currency throttle for the current character's live API refetch in GetCurrencyData.
local currencyLiveFetchAt = {}   -- [currencyID] = GetTime() of last live fetch

local function ResolveCurrencyAliasBuckets(currencies, charKey)
    if ns.Utilities and ns.Utilities.IsGuidOnlySubsidiaryReads and ns.Utilities:IsGuidOnlySubsidiaryReads() then
        return nil
    end
    local hit = currencyAliasBuckets[charKey]
    if hit then return hit end
    local missAt = currencyAliasMissAt[charKey]
    if missAt and (GetTime() - missAt) < 30 then return nil end
    if not ns.VaultCharKeysMatch then return nil end
    local matches = nil
    for k, row in pairs(currencies) do
        if type(row) == "table" and k ~= charKey and ns.VaultCharKeysMatch(k, charKey) then
            matches = matches or {}
            matches[#matches + 1] = k
        end
    end
    if matches then
        currencyAliasBuckets[charKey] = matches
        currencyAliasMissAt[charKey] = nil
        return matches
    end
    currencyAliasMissAt[charKey] = GetTime()
    return nil
end

--- Read stored quantity from SV when keys differ (GUID write vs Name-Realm roster index).
local function LookupStoredCurrencyValue(db, charKey, currencyID)
    if not db or not db.currencies or not charKey or not currencyID then return nil end
    local bucket = db.currencies[charKey]
    if bucket and bucket[currencyID] ~= nil then
        return bucket[currencyID]
    end
    local aliases = ResolveCurrencyAliasBuckets(db.currencies, charKey)
    if aliases then
        for i = 1, #aliases do
            local row = db.currencies[aliases[i]]
            if type(row) == "table" and row[currencyID] ~= nil then
                return row[currencyID]
            end
        end
    end
    return nil
end

--- Weekly-cap PvE currencies (coffer shards, Dundun, restored key): progress resets each week.
--- Dawncrests use season totalEarned — not weekly-persisted here.
local function UsesWeeklyProgressPersistence(currencyID, info)
    if not info and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    end
    if not info then return false end
    if IsCofferKeyShardByApiInfo(info) then return true end
    if ns.Utilities and ns.Utilities.IsWeeklyCapCurrency and ns.Utilities:IsWeeklyCapCurrency(currencyID, info.name) then
        return true
    end
    if ns.Utilities and ns.Utilities.IsRestoredCofferKeyCurrency and ns.Utilities:IsRestoredCofferKeyCurrency(currencyID, info.name) then
        return true
    end
    return false
end

local function GetCharacterLastSeen(charKey)
    if not charKey or not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    local chars = WarbandNexus.db.global.characters
    if not chars then return nil end
    local row = chars[charKey]
    if type(row) == "table" and type(row.lastSeen) == "number" then
        return row.lastSeen
    end
    if ns.VaultCharKeysMatch then
        for k, v in pairs(chars) do
            if type(v) == "table" and ns.VaultCharKeysMatch(k, charKey) and type(v.lastSeen) == "number" then
                return v.lastSeen
            end
        end
    end
    return nil
end

local function IsWeeklyProgressStaleForChar(db, charKey, currencyID)
    if not db or not charKey or not currencyID then return false end
    local currentWeekStart = ns.GetCurrentWeeklyResetStartTime and ns.GetCurrentWeeklyResetStartTime()
    if not currentWeekStart or currentWeekStart <= 0 then return false end

    local weekBucket = db.currencyProgressWeek and db.currencyProgressWeek[charKey]
    local storedWeek = weekBucket and weekBucket[currencyID]
    if type(storedWeek) == "number" and storedWeek > 0 then
        return storedWeek < currentWeekStart
    end

    -- Legacy rows saved before per-week stamps: infer from last time this character was active.
    local lastSeen = GetCharacterLastSeen(charKey)
    if type(lastSeen) == "number" then
        return lastSeen < currentWeekStart
    end
    return true
end

local function RecordCurrencyProgressWeek(db, charKey, currencyID, info)
    if not db or not charKey or not currencyID then return end
    if not UsesWeeklyProgressPersistence(currencyID, info) then return end
    local weekStart = ns.GetCurrentWeeklyResetStartTime and ns.GetCurrentWeeklyResetStartTime()
    if not weekStart or weekStart <= 0 then return end
    if not db.currencyProgressWeek then db.currencyProgressWeek = {} end
    if not db.currencyProgressWeek[charKey] then db.currencyProgressWeek[charKey] = {} end
    db.currencyProgressWeek[charKey][currencyID] = weekStart
end

local function ApplyWeeklyProgressFreshness(db, charKey, currencyID, storedTe)
    if storedTe == nil then return nil end
    if not UsesWeeklyProgressPersistence(currencyID, nil) then
        return storedTe
    end
    if IsWeeklyProgressStaleForChar(db, charKey, currencyID) then
        return 0
    end
    return storedTe
end

--- Clear stale weekly progress in SV (offline alts after weekly reset).
local function PruneStaleWeeklyCurrencyProgress(db)
    if not db or not db.totalEarned then return end
    local currentWeekStart = ns.GetCurrentWeeklyResetStartTime and ns.GetCurrentWeeklyResetStartTime()
    if not currentWeekStart or currentWeekStart <= 0 then return end

    for charKey, row in pairs(db.totalEarned) do
        if type(row) == "table" then
            for currencyID, te in pairs(row) do
                if type(te) == "number" and te > 0 and UsesWeeklyProgressPersistence(currencyID, nil) then
                    if IsWeeklyProgressStaleForChar(db, charKey, currencyID) then
                        row[currencyID] = 0
                        if db.weeklyEarnedThisWeek and db.weeklyEarnedThisWeek[charKey] then
                            db.weeklyEarnedThisWeek[charKey][currencyID] = 0
                        end
                        RecordCurrencyProgressWeek(db, charKey, currencyID, nil)
                    end
                end
            end
        end
    end
end

local function RecordWeeklyEarnedSnapshot(db, charKey, currencyID, info)
    if not db or not charKey or not currencyID or not info then return end
    if not UsesWeeklyProgressPersistence(currencyID, info) then return end
    local qew = SafeCurrencyNumber(info.quantityEarnedThisWeek)
    if qew == nil then return end
    if not db.weeklyEarnedThisWeek then db.weeklyEarnedThisWeek = {} end
    if not db.weeklyEarnedThisWeek[charKey] then db.weeklyEarnedThisWeek[charKey] = {} end
    db.weeklyEarnedThisWeek[charKey][currencyID] = qew
    RecordCurrencyProgressWeek(db, charKey, currencyID, info)
end

--- One-time heal: capped weekly progress without an API weekly snapshot was often stale totalEarned.
local function HealSuspiciousWeeklyCapProgress(db)
    if not db or not db.totalEarned then return end
    if db.weeklyEarnedSnapshotV1 then return end
    for charKey, row in pairs(db.totalEarned) do
        if type(row) == "table" then
            for currencyID, te in pairs(row) do
                if type(te) == "number" and te > 0 and UsesWeeklyProgressPersistence(currencyID, nil) then
                    local snap = db.weeklyEarnedThisWeek
                        and db.weeklyEarnedThisWeek[charKey]
                        and db.weeklyEarnedThisWeek[charKey][currencyID]
                    if snap == nil then
                        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
                        local maxW = info and SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
                        local maxQ = info and SafeCurrencyNumber(info.maxQuantity) or 0
                        local cap = (maxW > 0) and maxW or maxQ
                        if cap > 0 and te >= cap then
                            row[currencyID] = 0
                        end
                    end
                end
            end
        end
    end
    db.weeklyEarnedSnapshotV1 = true
end

local function LookupStoredTotalEarnedRaw(db, charKey, currencyID)
    if not db or not db.totalEarned or not charKey or not currencyID then return nil end
    local bucket = db.totalEarned[charKey]
    if bucket and bucket[currencyID] ~= nil then
        return bucket[currencyID]
    end
    if ns.Utilities and ns.Utilities.IsGuidOnlySubsidiaryReads and ns.Utilities:IsGuidOnlySubsidiaryReads() then
        return nil
    end
    if ns.VaultCharKeysMatch then
        for k, row in pairs(db.totalEarned) do
            if type(row) == "table" and k ~= charKey and ns.VaultCharKeysMatch(k, charKey) and row[currencyID] ~= nil then
                return row[currencyID]
            end
        end
    end
    return nil
end

local function LookupStoredTotalEarned(db, charKey, currencyID)
    if UsesWeeklyProgressPersistence(currencyID, nil) then
        if IsWeeklyProgressStaleForChar(db, charKey, currencyID) then
            return 0
        end
        local weekBucket = db.weeklyEarnedThisWeek and db.weeklyEarnedThisWeek[charKey]
        if weekBucket and weekBucket[currencyID] ~= nil then
            return weekBucket[currencyID]
        end
    end
    local stored = LookupStoredTotalEarnedRaw(db, charKey, currencyID)
    if stored == nil then return nil end
    return ApplyWeeklyProgressFreshness(db, charKey, currencyID, stored)
end

-- ON-DEMAND METADATA RESOLVER (Session RAM only)

---Resolve currency metadata from WoW API (cached in session RAM, never persisted).
local function ResolveCurrencyMetadata(currencyID)
    if not currencyID or currencyID == 0 then return nil end
    
    -- Check RAM cache first
    local cached = currencyMetadataCache[currencyID]
    if cached then return cached end
    
    -- Fetch from WoW API
    if not C_CurrencyInfo then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return nil end

    local maxQ = SafeCurrencyNumber(info.maxQuantity) or 0
    local maxWeekly = SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
    -- Dawncrests / Coffer Key Shards: maxQuantity = season cap, maxWeeklyQuantity = weekly cap.
    -- For display we want the weekly cap; for NormalizeQuantity we need the season cap.
    local effectiveMax
    if IsSeasonProgressSplitCurrency(currencyID, info) and maxWeekly > 0 then
        effectiveMax = maxWeekly
    elseif maxQ > 0 then
        effectiveMax = maxQ
    else
        effectiveMax = maxWeekly
    end
    local safeDisplayName = IsUsableCurrencyName(info.name) and info.name or ("Currency #" .. tostring(currencyID))
    local metadata = {
        currencyID = currencyID,
        name = safeDisplayName,
        icon = info.iconFileID,
        iconFileID = info.iconFileID,
        maxQuantity = effectiveMax,
        seasonMax = SeasonMaxFromSplitCurrencyInfo(currencyID, info),
        maxWeeklyQuantity = maxWeekly,
        useTotalEarnedForMaxQty = info.useTotalEarnedForMaxQty or false,
        isAccountWide = info.isAccountWide or false,
        isAccountTransferable = info.isAccountTransferable or false,
        description = info.description or "",
        quality = info.quality or 1,
    }
    metadata.normalizationCap = NormalizationCapFromCurrencyInfo(currencyID, info)
    metadata.isSeasonProgressSplit = IsSeasonProgressSplitCurrency(currencyID, info)
    metadata.isCofferKeyShard = IsCofferKeyShardByApiInfo(info)

    -- Circular buffer eviction (O(1) instead of O(n) table.remove)
    if #currencyMetadataCacheOrder >= CURRENCY_METADATA_CACHE_MAX then
        local evictID = currencyMetadataCacheOrder[currencyMetadataCacheHead]
        if evictID then
            currencyMetadataCache[evictID] = nil
        end
        currencyMetadataCacheOrder[currencyMetadataCacheHead] = currencyID
        currencyMetadataCacheHead = (currencyMetadataCacheHead % CURRENCY_METADATA_CACHE_MAX) + 1
    else
        currencyMetadataCacheOrder[#currencyMetadataCacheOrder + 1] = currencyID
    end
    
    currencyMetadataCache[currencyID] = metadata
    
    return metadata
end

---Clear session-only currency metadata cache (call on tab leave, etc.)
function WarbandNexus:ClearCurrencyMetadataCache()
    wipe(currencyMetadataCache)
    wipe(currencyMetadataCacheOrder)
    currencyMetadataCacheHead = 1
    ns._currenciesForUICacheInvalidateGen = (ns._currenciesForUICacheInvalidateGen or 0) + 1
end

-- INITIALIZATION

---Initialize currency cache (validates DB structure, does NOT clear data)
function WarbandNexus:InitializeCurrencyCache()
    if CurrencyCache.isInitialized then
        return
    end
    
    local db = GetDB()
    if not db then
        return
    end
    
    -- Load metadata
    CurrencyCache.lastFullScan = db.lastScan or 0

    PruneStaleWeeklyCurrencyProgress(db)
    HealSuspiciousWeeklyCapProgress(db)
    
    -- Get current character subsidiary key (GUID-backed after migration; resolves legacy API key).
    local currentSubsidiaryKey = CurrencySubsidiaryKey(nil)
    
    -- Scan decision only: avoid summing every currency row across all alts (O(total entries)).
    local anyCurrencyData = false
    local currentCharCount = 0
    for charKey, charCurrencies in pairs(db.currencies) do
        if type(charCurrencies) == "table" and next(charCurrencies) ~= nil then
            anyCurrencyData = true
        end
        local canonLoop = charKey
        if ns.Utilities.GetCanonicalCharacterKey then
            canonLoop = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
        end
        local isCurrentChar = (canonLoop == currentSubsidiaryKey)
            or (currentSubsidiaryKey and ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(charKey, currentSubsidiaryKey))
        if isCurrentChar and type(charCurrencies) == "table" then
            local count = 0
            for _ in pairs(charCurrencies) do
                count = count + 1
            end
            currentCharCount = count
        end
    end
    
    -- Determine if scan is needed
    local needsScan = false
    local scanReason = ""
    
    if not anyCurrencyData then
        needsScan = true
        scanReason = "No data in DB"
    elseif currentCharCount == 0 then
        needsScan = true
        scanReason = "Current character (" .. tostring(currentSubsidiaryKey) .. ") has no data"
    else
        -- Check for version mismatch
        local dbVersion = db.version
        if dbVersion ~= CurrencyCache.version then
            needsScan = true
            scanReason = string.format("Version mismatch (DB: %s, Current: %s)", tostring(dbVersion), tostring(CurrencyCache.version))
        else
            local age = time() - CurrencyCache.lastFullScan
            local MAX_CACHE_AGE = 3600  -- 1 hour (event-driven refresh only after warm persist)
            if age > MAX_CACHE_AGE then
                needsScan = true
                scanReason = string.format("Cache is old (%d seconds)", age)
            end
        end
    end

    local DF = ns.DataFreshness
    if needsScan and DF and DF.IsCurrencyWarm and DF.IsCurrencyWarm(db, CurrencyCache.version, currentSubsidiaryKey) then
        needsScan = false
        scanReason = "Persisted warm — event-driven updates only"
    end

    if not needsScan then
        if (db.lastScan or 0) <= 0 then
            db.lastScan = time()
        end
        CurrencyCache.lastFullScan = db.lastScan
        -- Suppress debounced/event FullScans briefly after warm reload (API burst looks like stale cache).
        CurrencyCache.initScanPending = true
        C_Timer.After(12, function()
            if CurrencyCache then
                CurrencyCache.initScanPending = false
            end
        end)
    end
    
    -- Currency data loaded from DB
    
    if needsScan then
        -- Set loading state for UI
        ns.CurrencyLoadingState.isLoading = true
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Waiting for API..."
        
        -- Block WN-Currency chat until FullScan writes current API state (avoids login spam from event burst).
        CurrencyCache.suppressCurrencyGainChatUntilScan = true
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.CURRENCY_LOADING_STARTED)
        end
        CurrencyCache.skipNextCurrencyLoadingStartedBroadcast = true
        
        -- Suppress event-driven FullScans until the init scan completes
        -- (CURRENCY_DISPLAY_UPDATE fires on login with nil/0 currencyType, triggering redundant scans)
        CurrencyCache.initScanPending = true
        
        -- Delay scan to ensure API is ready. 1.5s is sufficient for C_CurrencyInfo
        -- (available almost immediately after PLAYER_LOGIN). Previous 5s delay caused
        -- currency data to appear late on first login (T+7s instead of T+3.5s).
        C_Timer.After(1.5, function()
            if CurrencyCache then
                CurrencyCache.initScanPending = false
                CurrencyCache:PerformFullScan(true)  -- bypass throttle for initial scan
            end
        end)
    else
        -- Fire ready event immediately (data exists and is fresh)
        C_Timer.After(0.1, function()
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage(E.CURRENCY_CACHE_READY)
            end
        end)
    end
    
    -- Register event listeners for real-time updates
    self:RegisterCurrencyCacheEvents()
    
    -- Pre-warm metadata cache: resolve all known currency IDs from SV in background.
    -- C_CurrencyInfo.GetCurrencyInfo is synchronous (~0.01ms/call), so 200 calls = ~2ms.
    -- Done deferred so it doesn't add to login frame budget.
    C_Timer.After(8, function()
        local db2 = GetDB()
        if db2 and db2.currencies then
            local seen = {}
            for _, charCurrencies in pairs(db2.currencies) do
                for currencyID in pairs(charCurrencies) do
                    if not seen[currencyID] then
                        seen[currencyID] = true
                        ResolveCurrencyMetadata(currencyID)
                    end
                end
            end
        end
    end)
    
    if not CurrencyCache.currenciesForUIListeners then
        CurrencyCache.currenciesForUIListeners = true
        ns._currenciesForUICacheInvalidateGen = 0
        CurrencyCache.mergedUIReadModel = nil
        CurrencyCache.mergedUIReadModelGen = -2
        local function bumpCurrenciesForUIMergeCache()
            ns._currenciesForUICacheInvalidateGen = (ns._currenciesForUICacheInvalidateGen or 0) + 1
        end
        if WarbandNexus.RegisterMessage then
            -- Unique listener self: AceEvent allows one handler per (self, message).
            local CCListeners = CurrencyCache._msgListeners or {}
            CurrencyCache._msgListeners = CCListeners
            WarbandNexus.RegisterMessage(CCListeners, E.CURRENCY_UPDATED, bumpCurrenciesForUIMergeCache)
            WarbandNexus.RegisterMessage(CCListeners, E.CURRENCIES_UPDATED, bumpCurrenciesForUIMergeCache)
            WarbandNexus.RegisterMessage(CCListeners, E.CURRENCY_CACHE_CLEARED, bumpCurrenciesForUIMergeCache)
            WarbandNexus.RegisterMessage(CCListeners, E.CHARACTER_UPDATED, bumpCurrenciesForUIMergeCache)
            WarbandNexus.RegisterMessage(CCListeners, E.CHARACTER_TRACKING_CHANGED, bumpCurrenciesForUIMergeCache)
            WarbandNexus.RegisterMessage(CCListeners, E.MONEY_UPDATED, bumpCurrenciesForUIMergeCache)
        end
    end

    CurrencyCache.isInitialized = true
end

-- CURRENCY DATA RETRIEVAL (Direct from API)

---Fetch live currency info from WoW API (used for scans and event processing).
---Returns a lightweight table with quantity + fields needed for internal logic.
---Metadata (name, icon, etc.) is NOT persisted — see ResolveCurrencyMetadata.
local function FetchCurrencyFromAPI(currencyID)
    if not currencyID or currencyID == 0 then return nil end
    if not C_CurrencyInfo then return nil end
    
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return nil end

    local maxQ = SafeCurrencyNumber(info.maxQuantity) or 0
    local maxWeekly = SafeCurrencyNumber(info.maxWeeklyQuantity) or 0
    local normCap = NormalizationCapFromCurrencyInfo(currencyID, info)
    local rawQty = SafeCurrencyNumber(info.quantity)
    if rawQty == nil then rawQty = 0 end
    local normalizedQuantity = NormalizeQuantity(rawQty, normCap, info.useTotalEarnedForMaxQty)
    -- Display cap: weekly cap for Dawncrests / coffer shards (progress), season cap otherwise.
    local displayCap
    if IsSeasonProgressSplitCurrency(currencyID, info) and maxWeekly > 0 then
        displayCap = maxWeekly
    else
        displayCap = normCap
    end
    local sm = SeasonMaxFromSplitCurrencyInfo(currencyID, info)
    local progress = ProgressEarnedFromCurrencyInfo(currencyID, info)
    if type(progress) == "number" and type(sm) == "number" and sm > 0 and progress > sm then
        progress = sm
    end
    local displayName = IsUsableCurrencyName(info.name) and info.name or ("Currency #" .. tostring(currencyID))
    return {
        currencyID = currencyID,
        quantity = normalizedQuantity,
        name = displayName,
        isDiscovered = (info.discovered == true) or (info.isDiscovered == true),
        isAccountWide = info.isAccountWide or false,
        isAccountTransferable = info.isAccountTransferable or false,
        maxQuantity = displayCap,
        seasonMax = sm,
        totalEarned = progress,
        useTotalEarnedForMaxQty = info.useTotalEarnedForMaxQty or false,
    }
end

-- UPDATE OPERATIONS (Direct DB)

--- Dawncrest / useTotalEarnedForMaxQty: Blizzard may fire two updates for one drop (bag qty vs totalEarned).
--- Same gain amount on alternate "quantity" vs "progress" dispatches within this window = one physical gain.
local CROSS_SOURCE_CHAT_DEDUP_SEC = 1.25
local lastCurrencyGainChatByID = {} -- [currencyID] = { t = number, amount = number, source = string }

local function DispatchCurrencyGainChat(currencyID, currencyData, gainAmount, gainSource)
    if not currencyData or gainAmount <= 0 then return false end
    if CurrencyCache.suppressCurrencyGainChatUntilScan then
        return false
    end
    local live = (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) and C_CurrencyInfo.GetCurrencyInfo(currencyID) or nil
    if ShouldIgnoreCurrencyEvent(currencyID, currencyData, live) then return false end
    if live then
        if IsSeasonProgressSplitCurrency(currencyID, live) then
            local prev = lastCurrencyGainChatByID[currencyID]
            local now = GetTime()
            if prev and prev.amount == gainAmount and prev.source ~= gainSource
                and (now - prev.t) <= CROSS_SOURCE_CHAT_DEDUP_SEC then
                return false
            end
        end
    end
    MarkCurrencyVisible(currencyID)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.CURRENCY_GAINED, {
            currencyID = currencyID,
            gainAmount = gainAmount,
            gainSource = gainSource,
        })
        if live and IsSeasonProgressSplitCurrency(currencyID, live) then
            lastCurrencyGainChatByID[currencyID] = {
                t = GetTime(),
                amount = gainAmount,
                source = gainSource,
            }
        end
    end
    return true
end

---Merge API quantity with CURRENCY_DISPLAY_UPDATE payload when the client API is one frame stale
---(multi-currency loot: first ID updates, second still reads old values from GetCurrencyInfo).
local function MergeCurrencyQuantityWithEventHint(oldQuantity, apiQuantity, eventHint)
    local n = SafeCurrencyNumber(apiQuantity) or 0
    if not eventHint then return n, false end
    local evDelta = SafeCurrencyNumber(eventHint.quantityChange)
    local evAbs = SafeCurrencyNumber(eventHint.absQuantity)
    if n ~= oldQuantity then
        return n, false
    end
    if evDelta and evDelta > 0 then
        return oldQuantity + evDelta, true
    end
    if evAbs ~= nil and evAbs ~= oldQuantity then
        return evAbs, true
    end
    return n, false
end

---Update a single currency in DB for current character.
---SV stores only quantity (number). Metadata comes from ResolveCurrencyMetadata on-demand.
local function UpdateSingleCurrency(currencyID, eventHint)
    if not currencyID or currencyID == 0 then return false end
    
    local db = GetDB()
    if not db then return false end
    
    local charKey = CurrencySubsidiaryKey(nil)
    if not charKey then return false end

    -- Initialize character entry if needed
    if not db.currencies[charKey] then
        db.currencies[charKey] = {}
    end
    
    -- Snapshot old value for gain detection (SV stores plain number)
    local oldQuantity = db.currencies[charKey][currencyID] or 0
    -- Stored value may be number or table; extract quantity either way
    if type(oldQuantity) == "table" then oldQuantity = oldQuantity.quantity or 0 end
    
    -- Fetch new data from API
    local currencyData = FetchCurrencyFromAPI(currencyID)
    if not currencyData then
        return false
    end

    local apiInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if ShouldIgnoreCurrencyEvent(currencyID, currencyData, apiInfo) then
        return false
    end
    
    local mergedQty, usedEventHint = MergeCurrencyQuantityWithEventHint(oldQuantity, currencyData.quantity or 0, eventHint)
    local newQuantity = mergedQty
    if usedEventHint then
        currencyData.quantity = newQuantity
    end
    local te = currencyData.totalEarned
    local splitCur = apiInfo and IsSeasonProgressSplitCurrency(currencyID, apiInfo)
    if not db.totalEarned then db.totalEarned = {} end
    if not db.totalEarned[charKey] then db.totalEarned[charKey] = {} end
    local oldTe = db.totalEarned[charKey][currencyID]
    local teChanged = splitCur and te ~= nil and type(te) == "number" and te ~= oldTe
    local qtyChanged = (newQuantity ~= oldQuantity)

    -- Weekly progress (totalEarned) can change without bag quantity changing — must not early-out.
    if not qtyChanged and not teChanged then
        return false
    end

    if qtyChanged then
        db.currencies[charKey][currencyID] = newQuantity
    end

    if splitCur and te ~= nil and type(te) == "number" then
        db.totalEarned[charKey][currencyID] = te
        if apiInfo then
            RecordWeeklyEarnedSnapshot(db, charKey, currencyID, apiInfo)
        else
            RecordCurrencyProgressWeek(db, charKey, currencyID, nil)
        end
    end

    PruneCurrencyAliasBuckets(db, charKey)

    -- Update scan timestamp
    CurrencyCache.lastUpdate = time()
    db.lastScan = CurrencyCache.lastUpdate

    -- Check for gain and fire lean notification event
    local qGain = (newQuantity > oldQuantity) and (newQuantity - oldQuantity) or 0
    local pGain = (splitCur and type(oldTe) == "number" and type(te) == "number" and te > oldTe) and (te - oldTe) or 0

    -- Season-progress rows (Dawncrest tiers, etc.): Blizzard often updates totalEarned and bag quantity on separate ticks.
    -- Same tick with both deltas: one "progress" line (matches currency panel). Quantity-only: defer one frame so te can land → fewer bogus "(20)" totals.
    if splitCur and qGain > 0 and pGain > 0 then
        if not DispatchCurrencyGainChat(currencyID, currencyData, pGain, "progress") then
            return true
        end
    elseif splitCur and qGain > 0 then
        local snapQ = oldQuantity
        local snapTe = (type(oldTe) == "number") and oldTe or nil
        CurrencyCache.deferGainToken[currencyID] = (CurrencyCache.deferGainToken[currencyID] or 0) + 1
        local tok = CurrencyCache.deferGainToken[currencyID]
        C_Timer.After(0, function()
            if CurrencyCache.deferGainToken[currencyID] ~= tok then
                return
            end
            local cd = FetchCurrencyFromAPI(currencyID)
            if not cd then return end
            local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if not info or not IsSeasonProgressSplitCurrency(currencyID, info) then return end
            local teN = cd.totalEarned
            local qN = SafeCurrencyNumber(cd.quantity) or 0
            if type(teN) == "number" and type(snapTe) == "number" and teN > snapTe then
                local g = teN - snapTe
                if g > 0 then
                    DispatchCurrencyGainChat(currencyID, cd, g, "progress")
                end
            elseif qN > snapQ then
                local g = qN - snapQ
                if g > 0 then
                    DispatchCurrencyGainChat(currencyID, cd, g, "quantity")
                end
            end
        end)
    elseif splitCur and pGain > 0 then
        if not DispatchCurrencyGainChat(currencyID, currencyData, pGain, "progress") then
            return true
        end
    elseif qGain > 0 then
        if not DispatchCurrencyGainChat(currencyID, currencyData, qGain, "quantity") then
            return true
        end
    end

    return true
end

-- HIERARCHY DETECTION (Collapse/Expand technique)
-- Blizzard's C_CurrencyInfo API returns a flat list with no depth field.
-- We collapse all headers first, then expand one-at-a-time to discover the
-- parent→child relationships. This produces the REAL hierarchy that matches
-- the Blizzard Currency panel (e.g. Midnight → Season 1 → Crests).

---Recursively scan a header's direct children.
---PRE: header at `headerIndex` is visible and collapsed. All sub-headers
---     within it are collapsed too (from the initial CollapseAll pass).
---POST: header at `headerIndex` is collapsed again.
local function ScanHeaderNode(headerIndex, depth, currencyDataCollector)
    local hInfo = C_CurrencyInfo.GetCurrencyListInfo(headerIndex)
    if not hInfo or not hInfo.isHeader then return nil end

    local node = {
        name = hInfo.name,
        depth = depth,
        currencies = {},
        children = {},
    }

    -- Ensure collapsed, then expand to count DIRECT children
    if hInfo.isHeaderExpanded then
        C_CurrencyInfo.ExpandCurrencyList(headerIndex, false)
    end
    local sizeBefore = C_CurrencyInfo.GetCurrencyListSize()
    C_CurrencyInfo.ExpandCurrencyList(headerIndex, true)

    -- Some sub-headers may have retained an internal "expanded" state.
    -- Collapse them so only DIRECT children are visible.
    local subChanged = true
    local subSafety = 0
    while subChanged and subSafety < 100 do
        subChanged = false
        subSafety = subSafety + 1
        local curSize = C_CurrencyInfo.GetCurrencyListSize()
        for j = headerIndex + 1, curSize do
            local jInfo = C_CurrencyInfo.GetCurrencyListInfo(j)
            if not jInfo then break end
            if jInfo.isHeader and jInfo.isHeaderExpanded then
                C_CurrencyInfo.ExpandCurrencyList(j, false)
                subChanged = true
                break
            end
        end
    end

    local sizeAfter = C_CurrencyInfo.GetCurrencyListSize()
    local childCount = sizeAfter - sizeBefore

    if childCount > 0 then
        local processed = 0
        local j = headerIndex + 1
        while processed < childCount do
            local cInfo = C_CurrencyInfo.GetCurrencyListInfo(j)
            if not cInfo then break end

            if cInfo.isHeader then
                local childNode = ScanHeaderNode(j, depth + 1, currencyDataCollector)
                if childNode then
                    table.insert(node.children, childNode)
                end
            else
                local currencyID = nil
                local link = C_CurrencyInfo.GetCurrencyListLink(j)
                if link and not (issecretvalue and issecretvalue(link)) then
                    currencyID = tonumber(link:match("currency:(%d+)"))
                end
                if not currencyID and cInfo.currencyID then
                    currencyID = cInfo.currencyID
                end
                if currencyID and currencyID > 0 then
                    table.insert(node.currencies, currencyID)
                    MarkCurrencyVisible(currencyID)
                    local data = FetchCurrencyFromAPI(currencyID)
                    if data then
                        table.insert(currencyDataCollector, data)
                    end
                end
            end

            j = j + 1
            processed = processed + 1
        end
    end

    -- Collapse this header (restores list to pre-expand state)
    C_CurrencyInfo.ExpandCurrencyList(headerIndex, false)

    return node
end

---Build the full currency hierarchy from the Blizzard API.
---Uses collapse-all / expand-one-at-a-time to discover parent→child links.
local function BuildHierarchyFromAPI()
    if not C_CurrencyInfo then return {}, {} end

    local currencyDataCollector = {}

    -- Phase 1: Collapse ALL visible headers for a clean slate
    local collapseChanged = true
    local collapseSafety = 0
    while collapseChanged and collapseSafety < 300 do
        collapseChanged = false
        collapseSafety = collapseSafety + 1
        local size = C_CurrencyInfo.GetCurrencyListSize()
        for i = 1, size do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and info.isHeader and info.isHeaderExpanded then
                C_CurrencyInfo.ExpandCurrencyList(i, false)
                collapseChanged = true
                break
            end
        end
    end

    -- Phase 2: Only root-level items are visible now. Scan them.
    local roots = {}
    local rootSize = C_CurrencyInfo.GetCurrencyListSize()
    if rootSize == 0 then return {}, {} end

    local i = 1
    while i <= rootSize do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info then
            if info.isHeader then
                local rootNode = ScanHeaderNode(i, 0, currencyDataCollector)
                if rootNode then
                    table.insert(roots, rootNode)
                end
            else
                local currencyID = nil
                local link = C_CurrencyInfo.GetCurrencyListLink(i)
                if link and not (issecretvalue and issecretvalue(link)) then
                    currencyID = tonumber(link:match("currency:(%d+)"))
                end
                if currencyID and currencyID > 0 then
                    MarkCurrencyVisible(currencyID)
                    local data = FetchCurrencyFromAPI(currencyID)
                    if data then
                        table.insert(currencyDataCollector, data)
                    end
                end
            end
        end
        i = i + 1
    end

    -- Phase 3: Expand all headers back (restore normal WoW UI state)
    local expandChanged = true
    local expandSafety = 0
    while expandChanged and expandSafety < 300 do
        expandChanged = false
        expandSafety = expandSafety + 1
        local size = C_CurrencyInfo.GetCurrencyListSize()
        for k = 1, size do
            local info = C_CurrencyInfo.GetCurrencyListInfo(k)
            if info and info.isHeader and not info.isHeaderExpanded then
                C_CurrencyInfo.ExpandCurrencyList(k, true)
                expandChanged = true
                break
            end
        end
    end

    return roots, currencyDataCollector
end

-- HEADER MERGE (accumulate currency IDs across character scans)

---Build a flat lookup: headerName → set of currency IDs from a header tree
local function BuildOldCurrencyLookup(headers)
    local lookup = {}
    local hdrs = headers or {}
    for i = 1, #hdrs do
        local h = hdrs[i]
        lookup[h.name] = lookup[h.name] or {}
        local hcurrencies = h.currencies or {}
        for j = 1, #hcurrencies do
            local cid = hcurrencies[j]
            lookup[h.name][cid] = true
        end
        if h.children then
            local childLookup = BuildOldCurrencyLookup(h.children)
            for name, ids in pairs(childLookup) do
                lookup[name] = lookup[name] or {}
                for cid in pairs(ids) do
                    lookup[name][cid] = true
                end
            end
        end
    end
    return lookup
end

---Merge old currency IDs into a new header tree (preserves IDs from prior scans)
local function MergeOldCurrencyIDs(newHeaders, oldLookup)
    for i = 1, #newHeaders do
        local h = newHeaders[i]
        local old = oldLookup[h.name]
        if old then
            local newSet = {}
            for j = 1, #h.currencies do
                local cid = h.currencies[j]
                newSet[cid] = true
            end
            for cid in pairs(old) do
                if not newSet[cid] then
                    table.insert(h.currencies, cid)
                end
            end
        end
        if h.children and #h.children > 0 then
            MergeOldCurrencyIDs(h.children, oldLookup)
        end
    end
end

-- FULL SCAN

---Perform full scan of all currencies (Direct DB architecture).
---Builds a proper header tree from Blizzard's API hierarchy (supports Midnight+).
function CurrencyCache:PerformFullScan(bypassThrottle)
    DebugPrint("|cff9370DB[CurrencyCache]|r [Currency Action] FullScan triggered (bypass=" .. tostring(bypassThrottle) .. ")")
    if not bypassThrottle and InCombatLockdown and InCombatLockdown() then
        self.pendingPostCombatScan = true
        DebugPrint("|cff9370DB[CurrencyCache]|r [Currency Action] FullScan deferred (combat)")
        return
    end
    if not C_CurrencyInfo then
        -- Avoid leaving Currency tab stuck on "Loading" (e.g. rare load order / API unavailable).
        ns.CurrencyLoadingState.isLoading = false
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = nil
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.CURRENCY_CACHE_READY)
        end
        return
    end

    if not bypassThrottle and self.initScanPending then
        DebugPrint("|cff9370DB[CurrencyCache]|r [Currency Action] FullScan SKIPPED (init scan pending)")
        return
    end

    if not bypassThrottle then
        local now = time()
        local timeSinceLastScan = now - self.lastFullScan
        local MIN_SCAN_INTERVAL = 5
        if timeSinceLastScan < MIN_SCAN_INTERVAL then
            return
        end
    end

    if self.isScanning then
        return
    end

    if ns._fullScanInProgress then
        DebugPrint("|cff9370DB[CurrencyCache]|r [PERF] Deferring FullScan — another scan in progress")
        C_Timer.After(1.0, function()
            if CurrencyCache then
                CurrencyCache:PerformFullScan(bypassThrottle)
            end
        end)
        return
    end

    self.isScanning = true
    ns._fullScanInProgress = true

    -- Do NOT wipe the visibility whitelist — it accumulates across scans/sessions/characters.
    -- A scan that misses a header (timing / already-expanded quirks) must not drop previously
    -- observed currency IDs (Dawncrests, Untainted Mana-Crystals, Undercoin, etc.).

    ns.CurrencyLoadingState.isLoading = true
    ns.CurrencyLoadingState.loadingProgress = 0
    ns.CurrencyLoadingState.currentStage = "Fetching currency data..."

    local skipLoadingStarted = CurrencyCache.skipNextCurrencyLoadingStartedBroadcast
    CurrencyCache.skipNextCurrencyLoadingStartedBroadcast = false
    if WarbandNexus.SendMessage and not skipLoadingStarted then
        WarbandNexus:SendMessage(E.CURRENCY_LOADING_STARTED)
    end

    -- Quick check: is the API ready?
    local listSize = C_CurrencyInfo.GetCurrencyListSize()
    if listSize == 0 then
        self.isScanning = false
        ns._fullScanInProgress = false
        -- Clear loading so Currency tab can render SV snapshot or empty state; retry in background.
        ns.CurrencyLoadingState.isLoading = false
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Waiting for API... (retrying)"
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.CURRENCY_CACHE_READY)
        end
        C_Timer.After(5, function()
            if CurrencyCache then
                CurrencyCache:PerformFullScan(true)
            end
        end)
        return
    end

    ns.CurrencyLoadingState.loadingProgress = 20
    ns.CurrencyLoadingState.currentStage = string.format("Scanning %d list entries...", listSize)

    -- Build hierarchy from Blizzard API (collapse/expand technique)
    local headerTree, currencyDataArray = BuildHierarchyFromAPI()

    ns.CurrencyLoadingState.loadingProgress = 70
    ns.CurrencyLoadingState.currentStage = string.format("Processed %d currencies", #currencyDataArray)

    -- Merge old currency IDs from prior character scans
    local db = GetDB()
    if db then
        if db.headers and #db.headers > 0 then
            local oldLookup = BuildOldCurrencyLookup(db.headers)
            MergeOldCurrencyIDs(headerTree, oldLookup)
        end
        db.headers = headerTree
    end

    -- Update DB (quantities per character)
    ns.CurrencyLoadingState.loadingProgress = 85
    ns.CurrencyLoadingState.currentStage = "Saving to database..."
    -- Keep suppression active THROUGH UpdateAll on the initial login scan: account-wide
    -- currencies (Dawncrests, Coffer Key Shards, Reservoir Anima, etc.) often differ between
    -- the SV snapshot from last logout and the current API state because other characters'
    -- activity sync'd them while offline. Without this, every login spams the entire delta
    -- as "gains" (see user report: full Dawncrest totals printed on every login).
    -- Subsequent scans (event-driven during play) leave the flag false and emit normally.
    local wasInitialScan = CurrencyCache.suppressCurrencyGainChatUntilScan
    self:UpdateAll(currencyDataArray)
    if wasInitialScan then
        CurrencyCache.suppressCurrencyGainChatUntilScan = false
    end

    -- Complete
    ns.CurrencyLoadingState.isLoading = false
    ns.CurrencyLoadingState.loadingProgress = 100
    ns.CurrencyLoadingState.currentStage = "Complete!"

    self.isScanning = false
    ns._fullScanInProgress = false

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.CURRENCY_CACHE_READY)
        WarbandNexus:SendMessage(E.CURRENCY_UPDATED)
    end
end

---Update all currencies in DB (lean format: only quantity per currency).
function CurrencyCache:UpdateAll(currencyDataArray)
    if not currencyDataArray or #currencyDataArray == 0 then
        return false
    end
    
    local db = GetDB()
    if not db then
        return false
    end
    
    local currentCharKey = CurrencySubsidiaryKey(nil)
    if not currentCharKey then
        return false
    end

    -- Clear ONLY current character's data (preserve other characters)
    if not db.currencies[currentCharKey] then
        db.currencies[currentCharKey] = {}
    else
        wipe(db.currencies[currentCharKey])
    end
    if db.totalEarned and db.totalEarned[currentCharKey] then
        wipe(db.totalEarned[currentCharKey])
    end
    
    -- Write ONLY quantity to SV (lean format)
    local currencyCount = 0
    if not db.totalEarned then db.totalEarned = {} end
    if not db.totalEarned[currentCharKey] then db.totalEarned[currentCharKey] = {} end

    for i = 1, #currencyDataArray do
        local data = currencyDataArray[i]
        if data.currencyID then
            db.currencies[currentCharKey][data.currencyID] = data.quantity or 0
            local teFull = data.totalEarned
            local rowApi = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(data.currencyID)
            if teFull ~= nil and type(teFull) == "number" and rowApi and IsSeasonProgressSplitCurrency(data.currencyID, rowApi) then
                db.totalEarned[currentCharKey][data.currencyID] = teFull
                RecordWeeklyEarnedSnapshot(db, currentCharKey, data.currencyID, rowApi)
            end
            currencyCount = currencyCount + 1
        end
    end

    PruneCurrencyAliasBuckets(db, currentCharKey)

    PruneStaleWeeklyCurrencyProgress(db)

    -- Do NOT emit WN_CURRENCY_GAINED from FullScan reconciliation diffs. That path compares
    -- last SV snapshot to fresh API; after character change / account sync, hundreds of
    -- currencies can differ at once and each looks like a "gain" — flooding chat.
    -- Real-time gains still go through CURRENCY_DISPLAY_UPDATE → UpdateSingleCurrency →
    -- DispatchCurrencyGainChat (and login spam is still suppressed by suppressCurrencyGainChatUntilScan).
    -- (Previously: emit Undercoin etc. if only FullScan updated — rare; tradeoff accepted vs chat spam.)
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    db.lastScan = self.lastFullScan
    db.version = self.version
    
    return true
end

-- EVENT HANDLERS

-- EVENT HANDLERS (Direct DB)

-- CURRENCY UPDATE QUEUE (FIFO, time-budgeted drain)
-- Multi-currency / same-currency bursts enqueue many IDs. Events may fire while we are
-- inside UpdateSingleCurrency or PerformFullScan — those handlers only append. One drain
-- session runs until the queue is empty; each frame processes up to CURRENCY_DRAIN_BUDGET_MS
-- then resumes on the next frame (C_Timer.After(0)) so loot bursts do not monopolize one frame.
-- Never wipe the queue after a pass: that dropped updates appended while isDraining was true.

-- Max CPU per frame for synchronous currency queue drain (loot bursts enqueue many IDs).
local CURRENCY_DRAIN_BUDGET_MS = 4.5
local BROAD_CURRENCY_SCAN_DEBOUNCE_SEC = 1.25
local CURRENCY_CHAT_FALLBACK_QUIET_SEC = 2.0

local DrainCurrencyQueue

local function ScheduleDebouncedBroadCurrencyScan()
    if CurrencyCache.initScanPending then return end
    if InCombatLockdown and InCombatLockdown() then
        CurrencyCache.pendingPostCombatScan = true
        return
    end
    if CurrencyCache._broadScanTimer then return end
    CurrencyCache._broadScanTimer = C_Timer.NewTimer(BROAD_CURRENCY_SCAN_DEBOUNCE_SEC, function()
        CurrencyCache._broadScanTimer = nil
        if InCombatLockdown and InCombatLockdown() then
            CurrencyCache.pendingPostCombatScan = true
            return
        end
        if CurrencyCache and CurrencyCache.PerformFullScan then
            CurrencyCache:PerformFullScan()
        end
    end)
end

---Coalesce CURRENCY_DISPLAY_UPDATE enqueues onto the next frame (loot often fires many per tick).
local function ScheduleCurrencyDrainKick()
    if CurrencyCache.isDraining or CurrencyCache._currencyDrainKickTimer then
        return
    end
    CurrencyCache._currencyDrainKickTimer = C_Timer.NewTimer(0, function()
        CurrencyCache._currencyDrainKickTimer = nil
        DrainCurrencyQueue()
    end)
end

local function registerDrainBroadcastSuccess(currencyID)
    local c = CurrencyCache
    c._drainBcCount = (c._drainBcCount or 0) + 1
    if c._drainBcCount == 1 then
        c._drainBcSingleId = currencyID
    else
        c._drainBcSingleId = nil
    end
end

local function flushDrainBroadcastIfNeeded()
    local c = CurrencyCache
    local n = c._drainBcCount or 0
    if n <= 0 then return end
    if WarbandNexus.SendMessage then
        if n == 1 and c._drainBcSingleId then
            WarbandNexus:SendMessage(E.CURRENCY_UPDATED, c._drainBcSingleId)
        else
            WarbandNexus:SendMessage(E.CURRENCY_UPDATED)
        end
    end
    c._drainBcCount = 0
    c._drainBcSingleId = nil
end

local function scheduleDrainResume()
    if CurrencyCache.drainResumePending then return end
    CurrencyCache.drainResumePending = true
    C_Timer.After(0, function()
        CurrencyCache.drainResumePending = false
        DrainCurrencyQueue()
    end)
end

---Drain the currency queue synchronously until empty or time budget exceeded (then resume next frame).
---Nested DrainCurrencyQueue calls (while isDraining) return immediately; the outer loop
---keeps table.remove(1) until #queue == 0, including items added during processing.
DrainCurrencyQueue = function()
    if CurrencyCache.isDraining then return end
    CurrencyCache.isDraining = true

    local P = ns.Profiler
    local sliceT0 = (P and P.enabled and P.eventTrace) and debugprofilestop() or nil
    local sliceStart = debugprofilestop()
    local processedInSlice = 0
    local budgetExceeded = false

    while #CurrencyCache.updateQueue > 0 do
        if (debugprofilestop() - sliceStart) > CURRENCY_DRAIN_BUDGET_MS then
            budgetExceeded = true
            break
        end
        local entry = table.remove(CurrencyCache.updateQueue, 1)
        processedInSlice = processedInSlice + 1
        if entry == 0 then
            -- Never PerformFullScan inside the budget loop — one call can exceed 100ms and ignores CURRENCY_DRAIN_BUDGET_MS.
            ScheduleDebouncedBroadCurrencyScan()
        elseif type(entry) == "table" and entry.currencyID then
            if UpdateSingleCurrency(entry.currencyID, entry) then
                registerDrainBroadcastSuccess(entry.currencyID)
            end
        elseif type(entry) == "number" and entry > 0 then
            if UpdateSingleCurrency(entry) then
                registerDrainBroadcastSuccess(entry)
            end
        end
    end

    if sliceT0 and P then
        P:TraceInternalHandler("CurrencyDrainSlice", sliceT0,
            string.format("proc=%d rem=%d budgetHit=%s", processedInSlice, #CurrencyCache.updateQueue, budgetExceeded and "1" or "0"))
    end

    if #CurrencyCache.updateQueue > 0 then
        CurrencyCache.isDraining = false
        scheduleDrainResume()
    else
        flushDrainBroadcastIfNeeded()
        CurrencyCache.isDraining = false
    end
end

---Drain currency queue on PLAYER_LOGOUT (no frame budget; skip UI messages).
local function DrainCurrencyQueueOnLogout()
    if CurrencyCache._broadScanTimer then
        CurrencyCache._broadScanTimer:Cancel()
        CurrencyCache._broadScanTimer = nil
    end
    if CurrencyCache._currencyDrainKickTimer then
        CurrencyCache._currencyDrainKickTimer:Cancel()
        CurrencyCache._currencyDrainKickTimer = nil
    end
    CurrencyCache.drainResumePending = false

    local needsBroadScan = false
    while CurrencyCache.isDraining do
        CurrencyCache.isDraining = false
    end
    CurrencyCache.isDraining = true

    while #CurrencyCache.updateQueue > 0 do
        local entry = table.remove(CurrencyCache.updateQueue, 1)
        if entry == 0 then
            needsBroadScan = true
        elseif type(entry) == "table" and entry.currencyID then
            UpdateSingleCurrency(entry.currencyID, entry)
        elseif type(entry) == "number" and entry > 0 then
            UpdateSingleCurrency(entry)
        end
    end

    if needsBroadScan and CurrencyCache.PerformFullScan
        and ns.CharacterService and ns.CharacterService:IsCharacterTracked(WarbandNexus) then
        CurrencyCache:PerformFullScan()
    end

    CurrencyCache._drainBcCount = 0
    CurrencyCache._drainBcSingleId = nil
    CurrencyCache.isDraining = false
end

function WarbandNexus:FlushCurrencyCacheOnLogout()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    DrainCurrencyQueueOnLogout()
end

---Handle CURRENCY_DISPLAY_UPDATE event (FIFO queue + synchronous drain)
---Event payload (Retail): currencyType, quantity, quantityChange, quantityGainSource, destroyReason
---When multiple currencies drop in one moment, GetCurrencyInfo can lag; pass quantity/quantityChange through.
local function OnCurrencyUpdate(currencyType, quantity, quantityChange, quantityGainSource, destroyReason)
    local P = ns.Profiler
    local t0 = (P and P.enabled and P.eventTrace) and debugprofilestop() or nil
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
        return
    end

    if CurrencyCache.initScanPending then
        return
    end

    CurrencyCache._lastCurrencyDisplayEventAt = GetTime()

    if currencyType and currencyType > 0 then
        table.insert(CurrencyCache.updateQueue, {
            currencyID = currencyType,
            absQuantity = SafeCurrencyNumber(quantity),
            quantityChange = SafeCurrencyNumber(quantityChange),
        })
        ScheduleCurrencyDrainKick()
    else
        -- Nil/invalid type during play: debounced broad scan only (never sync PerformFullScan on loot tick).
        ScheduleDebouncedBroadCurrencyScan()
    end
    if t0 and P then
        P:TraceEventHandler("CURRENCY_DISPLAY_UPDATE", t0, currencyType, quantity, quantityChange, quantityGainSource, destroyReason)
    end
end

-- REMOVED: OnMoneyUpdate — never registered; gold tracking is owned by EventManager:OnMoneyChanged.

-- PUBLIC API (Direct DB Access)

---Get currency data for a specific currency.
---Combines SV quantity (per-char) + on-demand metadata from API.
---Current character: always prefers live API quantity so UI never shows stale/dummy SV.
function WarbandNexus:GetCurrencyData(currencyID, charKey)
    if not currencyID or currencyID == 0 then return nil end
    
    local db = GetDB()
    if not db then return nil end
    
    -- Use current character if not specified
    if not charKey then
        charKey = CurrencySubsidiaryKey(nil)
    else
        charKey = CurrencySubsidiaryKey(charKey)
    end
    
    if not charKey then return nil end

    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
    end
    
    local quantity = nil
    local currentKey = CurrencySubsidiaryKey(nil)
    local function norm(k) return (k and k:gsub("%s+", "")) or "" end
    local isCurrentChar = (currentKey and norm(charKey) == norm(currentKey))

    -- Current character: fetch live from API so we never show stale DB/dummy data.
    -- Throttled per currency: CURRENCY_DISPLAY_UPDATE pushes real changes into the SV
    -- cache the moment they happen, so this fetch only guards against a missed event —
    -- without the throttle, every UI iteration paid one API call per currency.
    local liveTotalEarned = nil
    local liveSeasonMax = nil
    local liveUseTotalEarned = nil
    if isCurrentChar and (not currencyLiveFetchAt[currencyID]
        or (GetTime() - currencyLiveFetchAt[currencyID]) >= 5) then
        currencyLiveFetchAt[currencyID] = GetTime()
        local liveData = FetchCurrencyFromAPI(currencyID)
        if liveData and liveData.quantity ~= nil then
            quantity = liveData.quantity
            liveTotalEarned = liveData.totalEarned
            liveSeasonMax = liveData.seasonMax
            liveUseTotalEarned = liveData.useTotalEarnedForMaxQty
            if not db.currencies[charKey] then
                db.currencies[charKey] = {}
            end
            db.currencies[charKey][currencyID] = quantity
            local teSplitInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currencyID)
            if liveTotalEarned ~= nil and type(liveTotalEarned) == "number" and teSplitInfo and IsSeasonProgressSplitCurrency(currencyID, teSplitInfo) then
                if not db.totalEarned then db.totalEarned = {} end
                if not db.totalEarned[charKey] then db.totalEarned[charKey] = {} end
                db.totalEarned[charKey][currencyID] = liveTotalEarned
                RecordWeeklyEarnedSnapshot(db, charKey, currencyID, teSplitInfo)
            end
        end
    end

    -- Non-current char or API failed: use SV
    if quantity == nil then
        local stored = LookupStoredCurrencyValue(db, charKey, currencyID)
        if stored ~= nil then
            if type(stored) == "number" then
                quantity = stored
            elseif type(stored) == "table" then
                quantity = stored.quantity or 0
            end
        end
    end

    -- Last resort for current char: SV (e.g. API not ready yet)
    if quantity == nil and isCurrentChar then
        local stored = LookupStoredCurrencyValue(db, charKey, currencyID)
        if stored ~= nil then
            if type(stored) == "number" then quantity = stored
            elseif type(stored) == "table" then quantity = stored.quantity or 0 end
        end
    end
    
    if quantity == nil then return nil end
    
    -- Resolve metadata from API (session RAM cache)
    local metadata = ResolveCurrencyMetadata(currencyID)
    if not metadata then
        -- API not ready yet; return minimal data
        return {
            currencyID = currencyID,
            quantity = quantity,
            name = "Currency #" .. currencyID,
            icon = nil,
            iconFileID = nil,
            maxQuantity = 0,
            isAccountWide = false,
            isAccountTransferable = false,
            description = "",
            quality = 1,
        }
    end
    
    -- Resolve totalEarned: live value for current char, SV for offline chars
    local totalEarned = liveTotalEarned
    if not totalEarned then
        totalEarned = LookupStoredTotalEarned(db, charKey, currencyID)
    end

    -- Same rule as Dawncrests: follow API useTotalEarnedForMaxQty (do not force shards — caused wrong "current" vs crest columns).
    local useEarned = (liveUseTotalEarned == true) or (metadata.useTotalEarnedForMaxQty == true)

    local seasonMaxOut = liveSeasonMax or metadata.seasonMax
    if type(totalEarned) == "number" and type(seasonMaxOut) == "number" and seasonMaxOut > 0 and totalEarned > seasonMaxOut then
        totalEarned = seasonMaxOut
    end

    -- Combine: SV quantity + RAM metadata
    return {
        currencyID = currencyID,
        quantity = quantity,
        name = metadata.name,
        icon = metadata.icon,
        iconFileID = metadata.iconFileID,
        maxQuantity = metadata.maxQuantity,
        seasonMax = seasonMaxOut,
        totalEarned = totalEarned,
        useTotalEarnedForMaxQty = useEarned,
        isAccountWide = metadata.isAccountWide,
        isAccountTransferable = metadata.isAccountTransferable,
        description = metadata.description,
        quality = metadata.quality,
    }
end

--- Live API: blended season/weekly progress (matches FetchCurrencyFromAPI totalEarned semantics).
function WarbandNexus:GetCurrencyProgressEarnedFromAPI(currencyID)
    if not currencyID or not C_CurrencyInfo then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return nil end
    local progress = ProgressEarnedFromCurrencyInfo(currencyID, info)
    local sm = SeasonMaxFromSplitCurrencyInfo(currencyID, info)
    if type(progress) == "number" and type(sm) == "number" and sm > 0 and progress > sm then
        return sm
    end
    return progress
end

---Normalize any character key representation to a comparable form.
local function NormalizeCharKey(key)
    return (key and tostring(key):gsub("%s+", "")) or ""
end

---Resolve the best matching currency bucket for a character from DB, handling legacy key formats.
local function ResolveCharCurrencyBucket(allCurrencies, rawCharKey, canonicalKey)
    if type(allCurrencies) ~= "table" then return nil end
    if canonicalKey and allCurrencies[canonicalKey] then
        return allCurrencies[canonicalKey]
    end
    if rawCharKey and allCurrencies[rawCharKey] then
        return allCurrencies[rawCharKey]
    end

    local targetCanon = NormalizeCharKey(canonicalKey)
    local targetRaw = NormalizeCharKey(rawCharKey)
    for existingKey, bucket in pairs(allCurrencies) do
        if NormalizeCharKey(existingKey) == targetCanon or NormalizeCharKey(existingKey) == targetRaw then
            return bucket
        end
        if ns.VaultCharKeysMatch and rawCharKey and ns.VaultCharKeysMatch(existingKey, rawCharKey) then
            return bucket
        end
        if ns.VaultCharKeysMatch and canonicalKey and ns.VaultCharKeysMatch(existingKey, canonicalKey) then
            return bucket
        end
    end
    return nil
end

---Get all cached currency data for a character (lean format from SV).
---Returns { [currencyID] = quantity } map.
function WarbandNexus:GetAllCurrencyData(charKey)
    if not charKey then
        charKey = CurrencySubsidiaryKey(nil)
    else
        charKey = CurrencySubsidiaryKey(charKey)
    end
    
    if not charKey then return {} end
    
    local db = GetDB()
    if not db or not db.currencies then return {} end
    
    local bucket = ResolveCharCurrencyBucket(db.currencies, charKey, charKey)
    return bucket or {}
end

---Rebuild merged currency UI read model from AceDB (`db.currencies` / `db.totalEarned`) plus session metadata.
---No C_CurrencyInfo in this path: quantities are whatever writers (PerformFullScan, UpdateSingleCurrency) last persisted.
---Metadata comes from ResolveCurrencyMetadata (one API hit per cold ID, RAM-cached).
local function RebuildMergedCurrenciesUIReadModel()
    local db = GetDB()
    if not db then
        CurrencyCache.mergedUIReadModel = {}
        CurrencyCache.mergedUIReadModelGen = ns._currenciesForUICacheInvalidateGen or 0
        return
    end

    -- 1) Collect all tracked character keys (same list as UI/tooltip)
    local trackedCharacters = {}
    if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters then
        for charKey, charData in pairs(WarbandNexus.db.global.characters) do
            if type(charData) == "table" and charData.isTracked == true then
                local canonicalKey = (ns.Utilities and ns.Utilities.ResolveCharacterRowKey and ns.Utilities:ResolveCharacterRowKey(charData))
                    or charKey
                if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
                    canonicalKey = ns.Utilities:GetCanonicalCharacterKey(canonicalKey) or charKey
                end
                trackedCharacters[#trackedCharacters + 1] = {
                    rawKey = charKey,
                    canonicalKey = canonicalKey,
                }
            end
        end
    end
    if #trackedCharacters == 0 and db.currencies then
        for charKey in pairs(db.currencies) do
            trackedCharacters[#trackedCharacters + 1] = {
                rawKey = charKey,
                canonicalKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ns.Utilities:GetCanonicalCharacterKey(charKey)) or charKey,
            }
        end
    end

    -- Resolve each character's currency bucket ONCE: the resolution is independent of
    -- the currency ID, but the loop below used to redo the alias scan per currency ×
    -- per character (O(currencies × chars²) on mixed GUID/Name-Realm SVs).
    for i = 1, #trackedCharacters do
        local tracked = trackedCharacters[i]
        tracked.bucket = ResolveCharCurrencyBucket(db.currencies, tracked.rawKey, tracked.canonicalKey)
    end

    local currencyIDSet = {}
    if db.currencies then
        for _, currencies in pairs(db.currencies) do
            if type(currencies) == "table" then
                for currencyID in pairs(currencies) do
                    currencyIDSet[currencyID] = true
                end
            end
        end
    end

    local result = {}
    for currencyID in pairs(currencyIDSet) do
        local metadata = ResolveCurrencyMetadata(currencyID)
        local entry = {
            name = metadata and metadata.name or ("Currency #" .. currencyID),
            icon = metadata and metadata.icon or nil,
            maxQuantity = metadata and metadata.maxQuantity or 0,
            isAccountWide = metadata and metadata.isAccountWide or false,
            isAccountTransferable = metadata and metadata.isAccountTransferable or false,
        }
        entry.chars = {}
        local maxQty = 0
        local splitNormCap = nil
        if metadata and metadata.isSeasonProgressSplit and not metadata.isCofferKeyShard then
            local sm = tonumber(metadata.seasonMax) or 0
            local mw = tonumber(metadata.maxWeeklyQuantity) or 0
            splitNormCap = (sm > 0) and sm or ((mw > 0) and mw or nil)
            if not splitNormCap or splitNormCap == 0 then
                splitNormCap = 200
            end
        end

        for i = 1, #trackedCharacters do
            local tracked = trackedCharacters[i]
            local rawKey = tracked.rawKey
            local canonicalKey = tracked.canonicalKey
            local qty = 0
            local currencies = tracked.bucket
            local stored = currencies and currencies[currencyID]
            if type(stored) == "number" then qty = stored
            elseif type(stored) == "table" then qty = stored.quantity or 0 end

            if splitNormCap and qty > splitNormCap then
                qty = qty - splitNormCap
                if qty < 0 then qty = 0 end
            end
            if canonicalKey and canonicalKey ~= "" then
                entry.chars[canonicalKey] = qty
            end
            if rawKey and rawKey ~= "" then
                entry.chars[rawKey] = qty
            end
            if qty > maxQty then maxQty = qty end
        end
        if entry.isAccountWide then entry.value = maxQty else entry.value = nil end
        result[currencyID] = entry
    end

    CurrencyCache.mergedUIReadModel = result
    CurrencyCache.mergedUIReadModelGen = ns._currenciesForUICacheInvalidateGen or 0
end

---Get all currencies in UI format: [currencyID] = { name, icon, maxQuantity, chars = { [key] = qty, ... } }.
---Per-character `chars` may list the same quantity under both SV row key (e.g. GUID) and Name-Realm so UI row keys always resolve.
---Read-only merged view: rebuilt from AceDB when invalidated; metadata from ResolveCurrencyMetadata (session RAM).
function WarbandNexus:GetCurrenciesForUI()
    local db = GetDB()
    if not db then return {} end

    local gen = ns._currenciesForUICacheInvalidateGen or 0
    if CurrencyCache.mergedUIReadModel and CurrencyCache.mergedUIReadModelGen == gen then
        return CurrencyCache.mergedUIReadModel
    end

    RebuildMergedCurrenciesUIReadModel()
    return CurrencyCache.mergedUIReadModel or {}
end

---Bump merge cache used by GetCurrenciesForUI (call after rare SV surgery without a WN_* message).
function WarbandNexus:InvalidateCurrenciesForUICache()
    ns._currenciesForUICacheInvalidateGen = (ns._currenciesForUICacheInvalidateGen or 0) + 1
end

---Manually trigger currency scan
function WarbandNexus:ScanCurrencies()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        CurrencyCache.pendingPostCombatScan = true
        return
    end
    
    CurrencyCache:PerformFullScan(false)
end

--- Flush a currency broad scan queued during combat.
function CurrencyCache:FlushPostCombatScan()
    if not self.pendingPostCombatScan then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self.pendingPostCombatScan = false
    self:PerformFullScan(false)
end

---Clear currency cache for current character
function WarbandNexus:ClearCurrencyCache()
    CurrencyCache:Clear(true)
end

---Clear currency data for current character only
function CurrencyCache:Clear(clearDB)
    if clearDB then
        local db = GetDB()
        if db then
            -- Get current character key
            local currentCharKey = CurrencySubsidiaryKey(nil)
            
            -- Only clear CURRENT character's currency data
            if db.currencies and db.currencies[currentCharKey] then
                wipe(db.currencies[currentCharKey])
            end
            if db.totalEarned and db.totalEarned[currentCharKey] then
                wipe(db.totalEarned[currentCharKey])
            end
            if db.currencyProgressWeek and db.currencyProgressWeek[currentCharKey] then
                wipe(db.currencyProgressWeek[currentCharKey])
            end
            if db.weeklyEarnedThisWeek and db.weeklyEarnedThisWeek[currentCharKey] then
                wipe(db.weeklyEarnedThisWeek[currentCharKey])
            end
            
            -- Reset scan time for current character only
            db.lastScan = 0
        end
    end
    
    -- Reset metadata
    self.lastFullScan = 0
    self.lastUpdate = 0
    self.isScanning = false
    
    -- Fire events
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.CURRENCY_CACHE_CLEARED)
    end
    
    -- Automatically start rescan after clearing
    if clearDB then
        -- Set loading state for UI
        ns.CurrencyLoadingState.isLoading = true
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Preparing..."
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.CURRENCY_LOADING_STARTED)
        end
        CurrencyCache.skipNextCurrencyLoadingStartedBroadcast = true
        
        C_Timer.After(1, function()
            if CurrencyCache then
                CurrencyCache:PerformFullScan(true)  -- bypass throttle since we just cleared
            end
        end)
    else
        -- Clear loading state if not rescanning
        ns.CurrencyLoadingState.isLoading = false
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Preparing..."
    end
end

---Fallback when CHAT_MSG_CURRENCY fires without a recent CURRENCY_DISPLAY_UPDATE (ChatIntegrationService).
function CurrencyCache:OnCurrencyChatSignal()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
        return
    end
    local lastDisplay = self._lastCurrencyDisplayEventAt or 0
    if (GetTime() - lastDisplay) < CURRENCY_CHAT_FALLBACK_QUIET_SEC then
        return
    end
    ScheduleDebouncedBroadCurrencyScan()
end

-- EVENT REGISTRATION

---Register currency cache events
function WarbandNexus:RegisterCurrencyCacheEvents()
    -- Guard: prevent double/triple registration
    if CurrencyCache.eventsRegistered then
        return
    end
    
    if not self.RegisterEvent then
        return
    end
    
    CurrencyCache.eventsRegistered = true
    
    -- CHAT_MSG_CURRENCY filter + debounced scan: ChatIntegrationService.lua (single hook owner).
    
    -- Register WoW events (may not fire in TWW)
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", function(event, currencyType, quantity, quantityChange, quantityGainSource, destroyReason)
        OnCurrencyUpdate(currencyType, quantity, quantityChange, quantityGainSource, destroyReason)
    end)
    
    self:RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", function()
        ns.DebugPrint("EVENT: ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
        if CurrencyCache.syncTimer then
            CurrencyCache.syncTimer:Cancel()
            CurrencyCache.syncTimer = nil
        end
        if CurrencyCache.PerformActualSync then
            CurrencyCache:PerformActualSync()
        end
    end)
    
    -- TERTIARY: Hook Warband transfers to update offline character immediately
    -- Since the hook event sometimes triggers before the local client knows the true DB amount 
    -- or if the user hasn't logged into the character yet, we sync ALL known currencies.
    if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyFromAccountCharacter then
        hooksecurefunc(C_CurrencyInfo, "RequestCurrencyFromAccountCharacter", function(sourceCharacterGUID, currencyID, quantity)
            if not currencyID or not sourceCharacterGUID or not quantity then return end
            if issecretvalue and issecretvalue(sourceCharacterGUID) then return end
            
            -- LOCAL PREDICTION: Immediately deduct from our local DB for the source character
            -- The API is heavily delayed/throttled for offline characters.
            local db = GetDB()
            local wDB = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
            if db and db.currencies and wDB and wDB.characters then
                for charKey, charData in pairs(wDB.characters) do
                    -- Match by GUID only. A name-based fallback existed here, but GUID
                    -- strings ("Player-####-XXXXXXXX") never contain character names,
                    -- so it could not match; rows without a stored guid are skipped.
                    local guidMatch = false
                    if charData.guid and sourceCharacterGUID then
                        local cg = charData.guid
                        if not ((issecretvalue and issecretvalue(cg)) or (issecretvalue and issecretvalue(sourceCharacterGUID))) then
                            guidMatch = (cg == sourceCharacterGUID)
                        end
                    end
                    if guidMatch then
                        local storageKey = CurrencySubsidiaryKey(charKey)
                        if db.currencies[storageKey] and db.currencies[storageKey][currencyID] then
                            local oldQty = db.currencies[storageKey][currencyID]
                            local newQty = math.max(0, oldQty - quantity)
                            db.currencies[storageKey][currencyID] = newQty
                            
                            -- Mark this currency as recently transferred to protect against stale API overwrites
                            CurrencyCache.recentTransfers = CurrencyCache.recentTransfers or {}
                            CurrencyCache.recentTransfers[storageKey] = CurrencyCache.recentTransfers[storageKey] or {}
                            CurrencyCache.recentTransfers[storageKey][currencyID] = GetTime()
                            
                            if IsDebugModeEnabled and IsDebugModeEnabled() then
                                ns.DebugPrint(string.format("[WN Hook] Deducted %d of currency %d from %s (%d -> %d)", quantity, currencyID, storageKey, oldQty, newQty))
                            end
                            
                            if WarbandNexus.SendMessage then
                                WarbandNexus:SendMessage(E.CURRENCY_UPDATED)
                            end
                        end
                        break
                    end
                end
            end
            
            -- Ask for a server sync for good measure after a delay
            C_Timer.After(1.5, function()
                if CurrencyCache and CurrencyCache.SyncAccountCurrencies then
                    CurrencyCache:SyncAccountCurrencies(currencyID)
                end
            end)
        end)
    end
    
    -- PLAYER_MONEY: owned by Core.lua / EventManager (OnMoneyChanged)
    -- Do NOT register here — prevents duplicate gold processing
    
end

-- ACCOUNT WIDE SYNCHRONIZATION

---Synchronize a specific currency or all known currencies across all characters using the C_CurrencyInfo API.
---This function sets up the asynchronous fetch from the server.
function CurrencyCache:SyncAccountCurrencies(specificCurrencyID)
    ns.DebugPrint("SyncAccountCurrencies requesting data from server...")
    
    if not C_CurrencyInfo or not C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then
        return
    end

    -- Save requested ID so the event handler knows what to sync
    CurrencyCache.pendingSyncCurrencyID = specificCurrencyID
    CurrencyCache.isAwaitingAccountCurrencyData = true
    
    -- Ask server for fresh account wide currency data
    C_CurrencyInfo.RequestCurrencyDataForAccountCharacters()
    
    -- Fallback timer: The WoW API silently drops/throttles these requests sometimes without firing the event.
    if CurrencyCache.syncTimer then CurrencyCache.syncTimer:Cancel() end
    CurrencyCache.syncTimer = C_Timer.NewTimer(0.5, function()
        ns.DebugPrint("Fallback timer to PerformActualSync triggered.")
        CurrencyCache.syncTimer = nil
        if CurrencyCache.PerformActualSync then
            CurrencyCache:PerformActualSync(specificCurrencyID, 1)
        end
    end)
end

--- Normalized Name-Realm key for a roster row (never name-only — duplicate names on different realms stay distinct).
local function RosterNameRealmKey(charData, charKey)
    if type(charData) ~= "table" then return nil end
    local U = ns.Utilities
    if not U or not U.GetCharacterKey then return nil end
    local name, realm = charData.name, charData.realm
    if (not name or name == "") or (not realm or realm == "") then
        if charKey and type(charKey) == "string" and U.SplitCharacterKey then
            name, realm = U:SplitCharacterKey(charKey)
        end
    end
    if not name or not realm
        or (issecretvalue and (issecretvalue(name) or issecretvalue(realm))) then
        return nil
    end
    return U:GetCharacterKey(name, realm)
end

--- Build normalized Name-Realm key from FetchCurrencyDataFromAccountCharacters entry (11.0.2+ fullCharacterName preferred).
local function ResolveApiEntryRosterKey(fullCharacterName, characterName)
    local U = ns.Utilities
    if not U or not U.GetCharacterKey or not U.SplitCharacterKey then return nil end
    local candidates = { fullCharacterName, characterName }
    for i = 1, #candidates do
        local raw = candidates[i]
        if raw and raw ~= "" and not (issecretvalue and issecretvalue(raw)) then
            local n, r = U:SplitCharacterKey(raw)
            if n and r then
                local key = U:GetCharacterKey(n, r)
                if key then return key end
            end
        end
    end
    return nil
end

--- Match one API account-currency row to a tracked roster character (GUID, then Name-Realm only).
local function AccountCurrencyEntryMatchesRosterRow(apiChar, charData, charKey)
    if charData.guid and apiChar.guid
        and not (issecretvalue and issecretvalue(charData.guid))
        and not (issecretvalue and issecretvalue(apiChar.guid))
        and charData.guid == apiChar.guid then
        return true
    end
    local wantKey = RosterNameRealmKey(charData, charKey)
    local apiKey = apiChar.rosterKey
    if wantKey and apiKey and wantKey == apiKey then
        if apiChar.guid and not charData.guid and not (issecretvalue and issecretvalue(apiChar.guid)) then
            charData.guid = apiChar.guid
        end
        return true
    end
    return false
end

---Actually performs the update using the fetched data (called from Event).
function CurrencyCache:PerformActualSync(specificCurrencyID, retryCount)
    specificCurrencyID = specificCurrencyID or CurrencyCache.pendingSyncCurrencyID
    retryCount = retryCount or 0
    
    if C_CurrencyInfo.IsAccountCharacterCurrencyDataReady and not C_CurrencyInfo.IsAccountCharacterCurrencyDataReady() then
        if retryCount < 10 then
            ns.DebugPrint("Data not ready. Retrying in 0.5s (Attempt " .. (retryCount + 1) .. ")")
            C_Timer.After(0.5, function()
                if CurrencyCache.PerformActualSync then
                    CurrencyCache:PerformActualSync(specificCurrencyID, retryCount + 1)
                end
            end)
            return
        else
            ns.DebugPrint("Polling timed out after 5 seconds. Aborting sync.")
            CurrencyCache.pendingSyncCurrencyID = nil
            return
        end
    end
    
    -- Clear the pending ID and proceed
    CurrencyCache.pendingSyncCurrencyID = nil
    
    ns.DebugPrint("PerformActualSync triggered.")
    
    if not C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters then
        return
    end
    
    local db = GetDB()
    if not db then
        return
    end
    if not db.currencies then
        return
    end
    
    local wDB = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    if not wDB then
        return
    end
    if not wDB.characters then
        return
    end
    
    -- Collect the currencies to sync
    local currenciesToSync = {}
    if specificCurrencyID then
        currenciesToSync[1] = specificCurrencyID
    else
        -- If no specific ID, sync all known currencies from the DB
        -- (To optimize, we gather a unique list of all currency IDs known to any character)
        local uniqueIDs = {}
        for charKey, charCurrencies in pairs(db.currencies) do
            for cID, _ in pairs(charCurrencies) do
                if not uniqueIDs[cID] then
                    uniqueIDs[cID] = true
                    table.insert(currenciesToSync, cID)
                end
            end
        end
    end
    
    local updatedAny = false
    
    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint(string.format("SyncAccountCurrencies started for %d currencies.", #currenciesToSync))
    end
    
    -- Process each currency
    for i = 1, #currenciesToSync do
        local currencyID = currenciesToSync[i]
        local accountCharacters = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(currencyID)
        
        -- Create a list of characters that the API reported having this currency
        local apiChars = {}
        
        if accountCharacters and type(accountCharacters) == "table" then
            for j = 1, #accountCharacters do
                local info = accountCharacters[j]
                local qty = SafeCurrencyNumber(info.quantity)
                if qty ~= nil then
                    local cName = info.characterName
                    if not cName or (issecretvalue and issecretvalue(cName)) then
                        cName = nil
                    end
                    local cFull = info.fullCharacterName
                    if not cFull or (issecretvalue and issecretvalue(cFull)) then
                        cFull = nil
                    end
                    local cGuid = info.characterGUID
                    if cGuid and (issecretvalue and issecretvalue(cGuid)) then
                        cGuid = nil
                    end
                    local rosterKey = ResolveApiEntryRosterKey(cFull, cName)
                    if cName or cGuid or rosterKey then
                        table.insert(apiChars, {
                            name = cName,
                            fullName = cFull,
                            rosterKey = rosterKey,
                            guid = cGuid,
                            quantity = qty,
                        })
                    end
                end
            end
        end
        
        -- Now iterate over our TRACKED characters and update their DB entry
        local currentPlayerGUID = UnitGUID("player")
        if issecretvalue and currentPlayerGUID and issecretvalue(currentPlayerGUID) then
            currentPlayerGUID = nil
        end
        local currentPlayerKey = CurrencySubsidiaryKey(nil)
        local currentPlayerCanon = currentPlayerKey
        if currentPlayerKey and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            currentPlayerCanon = ns.Utilities:GetCanonicalCharacterKey(currentPlayerKey) or currentPlayerKey
        end
        for charKey, charData in pairs(wDB.characters) do
            if charData.isTracked then
                -- SKIP CURRENT LOGIN CHARACTER! Their data is always fresh locally and might not be in the API response.
                local guidEqual = false
                if charData.guid and currentPlayerGUID then
                    local cg = charData.guid
                    if not ((issecretvalue and issecretvalue(cg)) or (issecretvalue and issecretvalue(currentPlayerGUID))) then
                        guidEqual = (cg == currentPlayerGUID)
                    end
                end
                local rowCanon = charKey
                if ns.Utilities and ns.Utilities.ResolveCharacterRowKey and type(charData) == "table" then
                    rowCanon = ns.Utilities:ResolveCharacterRowKey(charData) or charKey
                end
                if rowCanon and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
                    rowCanon = ns.Utilities:GetCanonicalCharacterKey(rowCanon) or rowCanon
                end
                local isCurrentPlayer = guidEqual
                    or (currentPlayerKey and charKey == currentPlayerKey)
                    or (currentPlayerCanon and rowCanon and currentPlayerCanon == rowCanon)
                
                if not isCurrentPlayer then
                    local newQuantity = 0

                    for k = 1, #apiChars do
                        local apiChar = apiChars[k]
                        if AccountCurrencyEntryMatchesRosterRow(apiChar, charData, charKey) then
                            newQuantity = apiChar.quantity
                            if apiChar.guid and not charData.guid
                                and not (issecretvalue and issecretvalue(apiChar.guid)) then
                                charData.guid = apiChar.guid
                            end
                            break
                        end
                    end
                    local metadata = ResolveCurrencyMetadata(currencyID)
                    local useTotal = metadata and metadata.useTotalEarnedForMaxQty or false
                    local okNi, apiNi = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
                    local normCapSync = (okNi and apiNi) and NormalizationCapFromCurrencyInfo(currencyID, apiNi)
                        or (metadata and metadata.maxQuantity or 0)
                    newQuantity = NormalizeQuantity(newQuantity, normCapSync, useTotal)
                    
                    local storageKey = CurrencySubsidiaryKey(charKey)
                    -- ONLY update if the quantity differs from what we have
                    local oldQuantity = db.currencies[storageKey] and db.currencies[storageKey][currencyID] or 0
                    if oldQuantity ~= newQuantity then
                        -- Protection against stale API data: if we recently locally deducted this currency,
                        -- ignore the API update if it is trying to revert the deduction (i.e. API value > local value)
                        local recentlyTransferred = CurrencyCache.recentTransfers and CurrencyCache.recentTransfers[storageKey] and CurrencyCache.recentTransfers[storageKey][currencyID]
                        local isStaleRevert = recentlyTransferred and (GetTime() - recentlyTransferred < 30) and (newQuantity > oldQuantity)
                        
                        if not isStaleRevert then
                            if not db.currencies[storageKey] then db.currencies[storageKey] = {} end
                            db.currencies[storageKey][currencyID] = newQuantity
                            PruneCurrencyAliasBuckets(db, storageKey)
                            updatedAny = true
                            if ns.DebugVerbosePrint then
                                ns.DebugVerbosePrint(string.format("|cff9370DB[CurrencyCache]|r Sync: Updated %s for %s (%d -> %d)", tostring(currencyID), storageKey, oldQuantity, newQuantity))
                            end
                        else
                            if ns.DebugVerbosePrint then
                                ns.DebugVerbosePrint(string.format("|cff9370DB[CurrencyCache]|r Sync: Ignored stale API data for %s %s (%d -> %d)", charKey, tostring(currencyID), oldQuantity, newQuantity))
                            end
                        end
                    end
                end
            end
        end
    end
    
    if updatedAny and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.CURRENCY_UPDATED)
    end
end

-- Export to namespace for UI and other modules
ns.CurrencyCache = CurrencyCache
