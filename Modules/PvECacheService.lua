--[[
    Warband Nexus - PvE Cache Service
    Persistent cache for PvE data: Mythic+, Great Vault, Lockouts, Weekly Rewards
    
    Architecture:
    - Event-driven updates (MYTHIC_PLUS_CURRENT_AFFIX_UPDATE, WEEKLY_REWARDS_UPDATE, etc.)
    - DB-backed persistence (no session-only data)
    - Throttled updates (2s for rare changes)
    - Single source of truth for PvE data
    
    Events fired:
    - WN_PVE_UPDATED: PvE data changed (UI should refresh)
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local DebugPrint = ns.DebugPrint
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities

---Chat-visible diagnostics when Config → Debug Mode is on (SavedVariables-safe summaries only).
local function PvECacheUserDebug(msg, ...)
    local W = rawget(_G, "WarbandNexus") or WarbandNexus
    local db = W and W.db and W.db.profile
    if not db or not db.debugMode then return end
    if not (W and W.Print) then return end
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, msg, ...)
        text = ok and s or tostring(msg)
    else
        text = tostring(msg)
    end
    W:Print("|cff00ccff[PvE Cache]|r " .. text)
end

-- Prevent chat spam for repeated identical diagnostic branches.
local pveCacheDiagLastLogAt = {}
local function ShouldLogPvECacheDiag(key, intervalSec)
    local now = GetTime()
    local last = pveCacheDiagLastLogAt[key] or 0
    local interval = intervalSec or 30
    if (now - last) < interval then
        return false
    end
    pveCacheDiagLastLogAt[key] = now
    return true
end

--- One SavedVariables bucket per logical character: normalize legacy/UI key spellings
--- so imports, migration, and live API paths never split the same toon across multiple keys.
local function CanonicalizePvEKey(charKey)
    if not charKey or charKey == "" then return charKey end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local k = ns.Utilities:GetCanonicalCharacterKey(charKey)
        if k and k ~= "" then return k end
    end
    return charKey
end

---Characters tab reads db.global.characters[].mythicKey; PvE updates must mirror pveCache keystone there.
---@param addon AceAddon WarbandNexus
---@param pveCharKey string
---@param keystoneLevel number|nil
---@param mapID number|nil
---@return boolean changed
local function MirrorKeystoneToCharacterRow(addon, pveCharKey, keystoneLevel, mapID)
    if not addon or not addon.db or not addon.db.global or not addon.db.global.characters then return false end
    local tableKey = pveCharKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local r = ns.CharacterService:ResolveCharactersTableKey(addon)
        if r then tableKey = r end
    end
    local row = addon.db.global.characters[tableKey]
    if not row then return false end
    local old = row.mythicKey
    local lv = tonumber(keystoneLevel)
    local mid = tonumber(mapID)
    if lv and mid and lv > 0 and mid > 0 then
        local oldLevel = old and tonumber(old.level) or nil
        local oldMap = old and tonumber(old.mapID or old.dungeonID) or nil
        if oldLevel == lv and oldMap == mid then
            return false
        end
        local mapName
        if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
            local ok, mn = pcall(C_ChallengeMode.GetMapUIInfo, mid)
            if ok and mn and not (issecretvalue and issecretvalue(mn)) then
                mapName = mn
            end
        end
        row.mythicKey = {
            level = lv,
            dungeonID = mid,
            dungeonName = mapName or "Unknown Dungeon",
            mapID = mid,
            scanTime = time(),
        }
        return true
    else
        if old == nil then
            return false
        end
        row.mythicKey = nil
        return true
    end
end

local function CmpNameSort(a, b)
    return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.name) or "") < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.name) or "")
end

local function SafeSavedInstanceNumber(value)
    if value == nil then return nil end
    if issecretvalue and issecretvalue(value) then return nil end
    return tonumber(value)
end

local function BuildSavedInstanceStorageKey(slotIndex, lockoutID, journalInstanceID, difficultyID)
    if lockoutID ~= nil and not (issecretvalue and issecretvalue(lockoutID)) then
        local numericID = tonumber(lockoutID)
        if numericID then return numericID end
        if type(lockoutID) == "string" and lockoutID ~= "" then return lockoutID end
    end

    local slot = SafeSavedInstanceNumber(slotIndex) or 0
    local instanceID = SafeSavedInstanceNumber(journalInstanceID)
    local difficulty = SafeSavedInstanceNumber(difficultyID)
    if instanceID then
        return table.concat({ "instance", tostring(instanceID), tostring(difficulty or 0), tostring(slot) }, ":")
    end
    return "slot:" .. tostring(slot)
end

---Boss rows for one GetSavedInstances() slot index (Encounter Journal order).
---@param slotIndex number
---@param numEncounters number|nil
---@return table[]
local function BuildSavedInstanceEncounterList(slotIndex, numEncounters)
    local encounters = {}
    numEncounters = SafeSavedInstanceNumber(numEncounters)
    if not numEncounters or numEncounters <= 0 then return encounters end
    for j = 1, numEncounters do
        local bossName, _, isKilled = GetSavedInstanceEncounterInfo(slotIndex, j)
        if issecretvalue and bossName and issecretvalue(bossName) then bossName = nil end
        if bossName then
            encounters[#encounters + 1] = {
                name = bossName,
                killed = isKilled or false,
            }
        end
    end
    return encounters
end

---GetSavedInstanceInfo may return isRaid as boolean or 1/0; it can also be nil in edge builds.
---Use DifficultyID + maxPlayers as fallback so 5-player lockouts still land in dungeons.
---@param raw any
---@param maxPlayers number|nil
---@param difficultyId number|nil
---@return boolean|nil true = raid, false = dungeon / small-group saved instance, nil = unknown
local function CoerceSavedInstanceIsRaid(raw, maxPlayers, difficultyId)
    if issecretvalue and raw ~= nil and issecretvalue(raw) then
        raw = nil
    end
    if raw == true or raw == 1 then return true end
    if raw == false or raw == 0 then return false end

    if type(difficultyId) == "number" and not (issecretvalue and issecretvalue(difficultyId)) then
        -- Raid-style difficulties (see DifficultyID / wow-api-guardian, Midnight 12.0.1)
        if difficultyId == 14 or difficultyId == 15 or difficultyId == 16 or difficultyId == 17
            or difficultyId == 3 or difficultyId == 4 or difficultyId == 5 or difficultyId == 6
            or difficultyId == 9 or difficultyId == 33 or difficultyId == 220 or difficultyId == 241 then
            return true
        end
        -- Party / M+ / timewalking party / delve-ish small group
        if difficultyId == 1 or difficultyId == 2 or difficultyId == 8 or difficultyId == 23
            or difficultyId == 24 or difficultyId == 150 or difficultyId == 205
            or difficultyId == 208 or difficultyId == 236 then
            return false
        end
    end

    if type(maxPlayers) == "number" and maxPlayers > 0
        and not (issecretvalue and issecretvalue(maxPlayers)) then
        if maxPlayers <= 5 then return false end
        if maxPlayers >= 10 then return true end
    end

    return nil
end

---Only lockouts with a known future reset time (resetAt) count as active.
---@param lockout table|nil
---@param nowS number GetServerTime()-style unix seconds
---@return boolean
local function SavedLockoutRowIsActive(lockout, nowS)
    if not lockout or type(nowS) ~= "number" then return false end
    local ra = lockout.resetAt
    if type(ra) ~= "number" then return false end
    if issecretvalue and issecretvalue(ra) then return false end
    return ra > nowS
end

---@param rawMap table|nil [lockoutID] = compact row
---@param isRaidFlag boolean
---@return table[]
local function HydrateSavedLockoutsForChar(rawMap, isRaidFlag)
    local hydrated = {}
    local nowS = (GetServerTime and GetServerTime()) or time()
    for instanceID, lockout in pairs(rawMap or {}) do
        if SavedLockoutRowIsActive(lockout, nowS) then
            local displayInstanceID = lockout.instanceID or instanceID
            local difficultyName
            if lockout.difficulty and GetDifficultyInfo then
                difficultyName = GetDifficultyInfo(lockout.difficulty)
            end
            hydrated[#hydrated + 1] = {
                instanceID = displayInstanceID,
                name = lockout.name or ("Instance #" .. tostring(displayInstanceID)),
                difficulty = lockout.difficulty,
                difficultyName = difficultyName or lockout.difficultyName or "Unknown",
                reset = lockout.reset,
                resetAt = lockout.resetAt,
                extended = lockout.extended or false,
                numEncounters = lockout.numEncounters,
                encounterProgress = lockout.encounterProgress,
                encounters = lockout.encounters or {},
                progress = lockout.encounterProgress or 0,
                total = lockout.numEncounters or 0,
                isRaid = isRaidFlag,
            }
        end
    end
    table.sort(hydrated, CmpNameSort)
    return hydrated
end

local function BuildAffixSignature(pveCache)
    local mp = pveCache and pveCache.mythicPlus
    local aff = mp and mp.currentAffixes
    if type(aff) ~= "table" or #aff == 0 then return "" end
    local ids = {}
    for i = 1, #aff do
        local v = aff[i]
        local id = (type(v) == "table" and v.id) or v
        id = tonumber(id)
        if id and id > 0 then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local parts = {}
    for i = 1, #ids do
        parts[i] = tostring(ids[i])
    end
    return table.concat(parts, ",")
end

local function BuildRunsSignature(runHistory)
    if type(runHistory) ~= "table" or #runHistory == 0 then return "" end
    local parts = {}
    for i = 1, #runHistory do
        local r = runHistory[i]
        if r then
            parts[#parts + 1] = tostring(r.level or 0) .. ":" .. tostring(r.dungeon or "") .. ":" .. ((r.timed and "1") or "0")
        end
    end
    return table.concat(parts, "|")
end

---Build a compact change signature for current character PvE UI payload.
---@param pveCache table|nil
---@param charKey string
---@return string
local function BuildPvESignature(pveCache, charKey)
    local mp = pveCache and pveCache.mythicPlus
    local gv = pveCache and pveCache.greatVault
    local lo = pveCache and pveCache.lockouts
    local delves = pveCache and pveCache.delves

    local key = mp and mp.keystones and mp.keystones[charKey]
    local keySig = tostring(key and key.level or 0) .. ":" .. tostring(key and key.mapID or 0)

    local ds = mp and mp.dungeonScores and mp.dungeonScores[charKey]
    local overall = ds and tonumber(ds.overallScore) or 0
    local dungeonCount = 0
    local dungeonSum = 0
    if ds and type(ds.dungeons) == "table" then
        for _, row in pairs(ds.dungeons) do
            dungeonCount = dungeonCount + 1
            dungeonSum = dungeonSum + tonumber((row and row.score) or 0) + tonumber((row and row.bestLevel) or 0)
        end
    end

    local rewards = gv and gv.rewards and gv.rewards[charKey]
    local rewardSig = rewards and rewards.hasAvailableRewards and "1" or "0"

    local acts = gv and gv.activities and gv.activities[charKey]
    local raidN = acts and acts.raids and #acts.raids or 0
    local mPlusN = acts and acts.mythicPlus and #acts.mythicPlus or 0
    local pvpN = acts and acts.pvp and #acts.pvp or 0
    local worldN = acts and acts.world and #acts.world or 0

    local runSig = BuildRunsSignature(mp and mp.runHistory and mp.runHistory[charKey])
    local affSig = BuildAffixSignature(pveCache)

    local lockN = 0
    if lo and lo.raids and type(lo.raids[charKey]) == "table" then
        for _ in pairs(lo.raids[charKey]) do lockN = lockN + 1 end
    end

    local wbN = 0
    if lo and lo.worldBosses and type(lo.worldBosses[charKey]) == "table" then
        for _ in pairs(lo.worldBosses[charKey]) do wbN = wbN + 1 end
    end

    local delveChar = delves and delves.characters and delves.characters[charKey]
    local delveSig = tostring(delves and delves.season or 0)
        .. ":" .. ((delveChar and delveChar.bountifulComplete) and "1" or "0")
        .. ":" .. ((delveChar and delveChar.crackedKeystoneComplete) and "1" or "0")
        .. ":" .. tostring(delveChar and delveChar.gildedStashes or -1)
        .. ":" .. tostring(delves and delves.companion and delves.companion.renownLevel or 0)

    return table.concat({
        keySig,
        tostring(overall),
        tostring(dungeonCount),
        tostring(dungeonSum),
        rewardSig,
        tostring(raidN), tostring(mPlusN), tostring(pvpN), tostring(worldN),
        tostring(lockN), tostring(wbN),
        delveSig,
        affSig,
        runSig,
    }, ";")
end

local WEEK_SECONDS = 7 * 86400

---Best-effort weekly reset start timestamp (epoch seconds).
---@return number|nil
local function GetCurrentWeeklyResetStartTime()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and GetServerTime then
        local secsUntil = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if secsUntil ~= nil and secsUntil >= 0 then
            return GetServerTime() + secsUntil - WEEK_SECONDS
        end
    end
    if WarbandNexus and WarbandNexus.GetWeeklyResetTime then
        local nextReset = WarbandNexus:GetWeeklyResetTime()
        if nextReset and nextReset > 0 then
            return nextReset - WEEK_SECONDS
        end
    end
    return nil
end

---Prune keystones that belong to a previous weekly cycle.
---Runs on init/update so stale keys never survive a weekly reset.
local function PruneExpiredKeystonesForWeeklyReset()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return 0
    end
    local mp = WarbandNexus.db.global.pveCache.mythicPlus
    if not mp then return 0 end
    if not mp.keystones then
        mp.keystones = {}
        return 0
    end

    local resetStart = GetCurrentWeeklyResetStartTime()
    local removed = 0
    for key, data in pairs(mp.keystones) do
        local stamp = type(data) == "table" and data.lastUpdate or nil
        local stale = false
        if resetStart and resetStart > 0 then
            stale = type(stamp) ~= "number" or stamp < resetStart
        elseif WarbandNexus.HasWeeklyResetOccurred then
            stale = type(stamp) ~= "number" or WarbandNexus:HasWeeklyResetOccurred(stamp)
        end
        if stale then
            mp.keystones[key] = nil
            removed = removed + 1
        end
    end

    if resetStart and resetStart > 0 then
        mp.lastKeystoneWeeklyReset = resetStart
    end
    return removed
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local CACHE_VERSION = Constants.PVE_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.SHARED_RARE
local GreatVaultActivityHasCompletedRows

---Midnight-safe quest completion check (pcall + secret guard).
---@param questID number
---@return boolean
local function SafeIsQuestFlaggedCompleted(questID)
    if not questID or type(questID) ~= "number" then return false end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if not ok or done == nil then return false end
    if issecretvalue and issecretvalue(done) then return false end
    return done == true
end

--- Read Gilded Stash weekly progress from the live UI widget (when available).
local function GetGildedStashCounts()
    local current, weeklyMax = -1, 4
    if C_UIWidgetManager and C_UIWidgetManager.GetSpellDisplayVisualizationInfo then
        local widget = C_UIWidgetManager.GetSpellDisplayVisualizationInfo(7591)
        local tooltip = widget and widget.spellInfo and widget.spellInfo.tooltip
        if tooltip then
            local cur, max = tooltip:match("(%d+)%s*/%s*(%d+)")
            if cur then current = tonumber(cur) or current end
            if max then weeklyMax = tonumber(max) or weeklyMax end
        end
    end
    return current, weeklyMax
end

-- ============================================================================
-- NO LOCAL CACHE - DIRECT DB ACCESS ONLY
-- ============================================================================
-- Architecture: API > DB > UI (same as Reputation and Currency)
-- All data operations go directly to self.db.global.pveCache
-- No local variables, no RAM cache, no sync issues!

-- Throttle timers
local lastUpdateTime = 0
local pendingUpdate = false
local keystoneRetryPending = {}
local keystoneRetryCount = {}
local keystoneZeroSeenAt = {}
-- Track last observed (level, mapID) per char so repeated identical API results
-- (very common: UPDATE_INSTANCE_INFO + CHALLENGE_MODE_MAPS_UPDATE bursts during
-- reload/zone all read the same values) become no-ops instead of re-running the
-- write/log path. Stored as "level|mapID" strings; nil API → "nil|nil".
local keystoneLastSeen = {}

local KEYSTONE_ZERO_CONFIRM_SECONDS = 2
local KEYSTONE_RETRY_MAX = 3

---Schedule one delayed keystone re-read for API warmup races.
---Capped at KEYSTONE_RETRY_MAX attempts per session per char so a character that
---genuinely owns no keystone (API returns nil rather than 0 in some warmup paths)
---doesn't trigger an infinite retry loop and chat-spam.
---@param charKey string
local function ScheduleKeystoneRetry(charKey)
    if not charKey or keystoneRetryPending[charKey] then
        return
    end
    if not C_Timer or not C_Timer.After then
        return
    end
    local attempts = (keystoneRetryCount[charKey] or 0)
    if attempts >= KEYSTONE_RETRY_MAX then
        return
    end
    keystoneRetryCount[charKey] = attempts + 1
    keystoneRetryPending[charKey] = true
    C_Timer.After(1.2, function()
        keystoneRetryPending[charKey] = nil
        if not WarbandNexus or not WarbandNexus.UpdateCharacterKeystone then
            return
        end
        WarbandNexus:UpdateCharacterKeystone(charKey)
        if WarbandNexus.SavePvECache then
            WarbandNexus:SavePvECache()
        end
        local events = ns.Constants and ns.Constants.EVENTS
        if WarbandNexus.SendMessage and events and events.PVE_UPDATED then
            WarbandNexus:SendMessage(events.PVE_UPDATED)
        end
    end)
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize PvE cache from DB
---Called on addon load to restore previous scan results
function WarbandNexus:InitializePvECache()
    if not self.db.global.pveCache then
        self.db.global.pveCache = {
            mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, dungeons = {}, worldBosses = {} },
            delves = { companion = {}, season = 0 },
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        return
    end
    
    -- Non-destructive version migration.
    -- Bumping CACHE_VERSION must NOT wipe per-character Great Vault / keystone data,
    -- otherwise alts show empty until each one is logged into and re-scanned.
    -- The current character's data is refreshed on PLAYER_LOGIN regardless; for alts
    -- we keep whatever is already stored and just ensure the expected sub-tables exist.
    local cache = self.db.global.pveCache
    cache.mythicPlus = cache.mythicPlus or { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} }
    cache.mythicPlus.currentAffixes = cache.mythicPlus.currentAffixes or {}
    cache.mythicPlus.keystones      = cache.mythicPlus.keystones      or {}
    cache.mythicPlus.bestRuns       = cache.mythicPlus.bestRuns       or {}
    cache.mythicPlus.dungeonScores  = cache.mythicPlus.dungeonScores  or {}

    cache.greatVault = cache.greatVault or { activities = {}, rewards = {} }
    cache.greatVault.activities = cache.greatVault.activities or {}
    cache.greatVault.rewards    = cache.greatVault.rewards    or {}

    cache.lockouts = cache.lockouts or { raids = {}, dungeons = {}, worldBosses = {} }
    cache.lockouts.raids       = cache.lockouts.raids       or {}
    cache.lockouts.dungeons    = cache.lockouts.dungeons    or {}
    cache.lockouts.worldBosses = cache.lockouts.worldBosses or {}

    cache.delves = cache.delves or { companion = {}, season = 0 }
    cache.delves.companion = cache.delves.companion or {}
    cache.delves.season    = cache.delves.season    or 0

    cache.version = CACHE_VERSION
    cache.lastUpdate = cache.lastUpdate or 0

    -- Weekly hygiene: do not keep stale pre-reset keystones across sessions.
    PruneExpiredKeystonesForWeeklyReset()
    
    -- CRITICAL: Validate and clear corrupted vault data
    -- Each character should have max 3 activities per type (raids, mythicPlus, pvp, world)
    if self.db.global.pveCache.greatVault and self.db.global.pveCache.greatVault.activities then
        for charKey, charData in pairs(self.db.global.pveCache.greatVault.activities) do
            if charData.raids and #charData.raids > 9 then
                self.db.global.pveCache.greatVault.activities[charKey] = nil
            elseif charData.mythicPlus and #charData.mythicPlus > 9 then
                self.db.global.pveCache.greatVault.activities[charKey] = nil
            elseif charData.world and #charData.world > 9 then
                self.db.global.pveCache.greatVault.activities[charKey] = nil
            end
        end
    end
    
end

---Save PvE cache to DB
function WarbandNexus:SavePvECache()
    if not self.db or not self.db.global or not self.db.global.pveCache then
        return
    end
    
    -- Update metadata (data is already in DB from direct writes)
    self.db.global.pveCache.version = CACHE_VERSION
    self.db.global.pveCache.lastUpdate = time()
    
end

-- ============================================================================
-- MYTHIC+ DATA
-- ============================================================================

---Update current week's Mythic+ affixes (lean: only IDs stored in SV).
---Metadata (name, description, icon) resolved on-demand from C_ChallengeMode.GetAffixInfo().
function WarbandNexus:UpdateMythicPlusAffixes()
    if not C_MythicPlus or not C_ChallengeMode or not self.db.global.pveCache then return end
    
    -- CRITICAL: C_MythicPlus.GetCurrentAffixes() returns affixID list OR struct array
    local affixes = C_MythicPlus.GetCurrentAffixes()
    
    if affixes and #affixes > 0 then
        self.db.global.pveCache.mythicPlus.currentAffixes = {}
        for i = 1, #affixes do
            local affixData = affixes[i]
            local affixID = type(affixData) == "table" and affixData.id or affixData
            
            if affixID and type(affixID) == "number" then
                -- Store only the ID (lean format). Metadata resolved on-demand.
                table.insert(self.db.global.pveCache.mythicPlus.currentAffixes, affixID)
            end
        end
    end
end

---Update character's keystone data
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateCharacterKeystone(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_MythicPlus or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    local keystoneInfo = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    local ksStore = self.db.global.pveCache.mythicPlus and self.db.global.pveCache.mythicPlus.keystones
    local existing = ksStore and ksStore[charKey] or nil

    -- Skip when API returned the SAME (level, mapID) as the previous call for this
    -- character. Without this guard, every event in a reload/zone burst retraces
    -- the entire keystone path (and re-emits the debug log) for unchanged values.
    local seenKey = tostring(keystoneLevel) .. "|" .. tostring(keystoneInfo)
    if keystoneLastSeen[charKey] == seenKey then
        return
    end
    keystoneLastSeen[charKey] = seenKey

    local didChange = false
    if keystoneInfo and keystoneLevel and keystoneLevel > 0 then
        if not self.db.global.pveCache.mythicPlus.keystones then
            self.db.global.pveCache.mythicPlus.keystones = {}
        end
        local oldLevel = existing and tonumber(existing.level) or nil
        local oldMap = existing and tonumber(existing.mapID) or nil
        local newLevel = tonumber(keystoneLevel)
        local newMap = tonumber(keystoneInfo)
        if oldLevel ~= newLevel or oldMap ~= newMap then
            self.db.global.pveCache.mythicPlus.keystones[charKey] = {
                mapID = keystoneInfo,
                level = keystoneLevel,
                lastUpdate = time(),
            }
            didChange = true
            PvECacheUserDebug("keystone: STORED key=%s mapID=%s level=%s", tostring(charKey), tostring(keystoneInfo), tostring(keystoneLevel))
        end
        keystoneZeroSeenAt[charKey] = nil
        keystoneRetryCount[charKey] = nil
        if MirrorKeystoneToCharacterRow(self, charKey, keystoneLevel, keystoneInfo) then
            didChange = true
        end
    else
        -- Only clear when API reports "no key" (level 0). Nil map+level often means APIs not ready yet —
        -- do not wipe a good cached key (fixes login / affix race losing alt keys).
        if keystoneLevel == 0 then
            if existing and existing.level and existing.level > 0 then
                local firstSeen = keystoneZeroSeenAt[charKey]
                if not firstSeen then
                    keystoneZeroSeenAt[charKey] = time()
                    PvECacheUserDebug(
                        "keystone: API level 0 (first sight) — keep existing cache key=%s mapID=%s level=%s",
                        tostring(charKey), tostring(existing.mapID), tostring(existing.level))
                    return
                end
                if (time() - firstSeen) < KEYSTONE_ZERO_CONFIRM_SECONDS then
                    PvECacheUserDebug(
                        "keystone: API level 0 (await confirm) — keep existing cache key=%s age=%ss",
                        tostring(charKey), tostring(time() - firstSeen))
                    return
                end
            end

            if self.db.global.pveCache.mythicPlus.keystones then
                self.db.global.pveCache.mythicPlus.keystones[charKey] = nil
            end
            didChange = existing ~= nil
            keystoneZeroSeenAt[charKey] = nil
            PvECacheUserDebug("keystone: API level 0 — cleared cache entry key=%s", tostring(charKey))
            if MirrorKeystoneToCharacterRow(self, charKey, nil, nil) then
                didChange = true
            end
        else
            -- API warmup race: keep existing key and schedule one delayed re-read.
            -- Only log/request when no retry is already in-flight; without this guard,
            -- bursty events (zoning, login, refresh) repaint the same warning dozens
            -- of times per second while the API is still warming up.
            if not keystoneRetryPending[charKey] then
                if C_MythicPlus.RequestMapInfo then
                    pcall(C_MythicPlus.RequestMapInfo)
                end
                ScheduleKeystoneRetry(charKey)
                PvECacheUserDebug(
                    "keystone: no write (API not ready: level=%s mapID=%s) key=%s — existing cache kept",
                    tostring(keystoneLevel), tostring(keystoneInfo), tostring(charKey))
            end
        end
    end
    if didChange and self.SendMessage and Constants and Constants.EVENTS and Constants.EVENTS.CHARACTER_UPDATED then
        self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, { charKey = charKey, dataType = "mythicKey" })
    end
end

---Update character's best M+ runs
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateMythicPlusBestRuns(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_MythicPlus or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    -- Get best run level for each dungeon
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable()
    if not maps then return end
    
    if not self.db.global.pveCache.mythicPlus.bestRuns then
        self.db.global.pveCache.mythicPlus.bestRuns = {}
    end
    
    if not self.db.global.pveCache.mythicPlus.bestRuns[charKey] then
        self.db.global.pveCache.mythicPlus.bestRuns[charKey] = {}
    end
    
    -- Get overall M+ rating/score if available
    local overallScore = 0
    local scoreSource = "NONE"
    
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
        scoreSource = "GetOverallDungeonScore"
    elseif C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        if summary and summary.currentSeasonScore then
            overallScore = summary.currentSeasonScore
            scoreSource = "GetPlayerMythicPlusRatingSummary"
        end
    end
    
    local bestRunsBucket = self.db.global.pveCache.mythicPlus.bestRuns[charKey]
    local prevOverall = bestRunsBucket.overallScore or 0
    local prevSource = bestRunsBucket.scoreSource or "NONE"
    bestRunsBucket.overallScore = overallScore
    bestRunsBucket.scoreSource = scoreSource
    local overallChanged = (prevOverall ~= overallScore) or (prevSource ~= scoreSource)
    local updatedRuns = 0
    
    -- Store best runs for each dungeon
    for i = 1, #maps do
        local mapID = maps[i]
        local _, level, _, onTime = C_MythicPlus.GetWeeklyBestForMap and C_MythicPlus.GetWeeklyBestForMap(mapID)
        if level and level > 0 then
            local old = bestRunsBucket[mapID]
            local oldLevel = old and old.level or 0
            local oldOnTime = old and old.onTime or false
            bestRunsBucket[mapID] = {
                level = level,
                onTime = onTime or false,
                lastUpdate = time(),
            }
            if oldLevel ~= level or oldOnTime ~= (onTime or false) then
                updatedRuns = updatedRuns + 1
            end
        end
    end
    
    if overallChanged or updatedRuns > 0 then
        PvECacheUserDebug(
            "bestRuns: key=%s overall=%s source=%s updatedRuns=%d",
            tostring(charKey), tostring(overallScore), tostring(scoreSource), updatedRuns
        )
    end
end

---True if a dungeonScores bucket has any non-zero progress (used to avoid wiping API race zeros).
local function DungeonScoresBucketHasProgress(scoreEntry)
    if not scoreEntry then return false end
    if type(scoreEntry.overallScore) == "number" and scoreEntry.overallScore > 0 then return true end
    local dungeons = scoreEntry.dungeons
    if type(dungeons) ~= "table" then return false end
    for _, row in pairs(dungeons) do
        if row then
            if (type(row.score) == "number" and row.score > 0) or (type(row.bestLevel) == "number" and row.bestLevel > 0) then
                return true
            end
        end
    end
    return false
end

---Update character's dungeon scores (overall + per-dungeon breakdown)
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateDungeonScores(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_ChallengeMode or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    -- Initialize cache
    if not self.db.global.pveCache.mythicPlus.dungeonScores then
        self.db.global.pveCache.mythicPlus.dungeonScores = {}
    end
    
    if not self.db.global.pveCache.mythicPlus.dungeonScores[charKey] then
        self.db.global.pveCache.mythicPlus.dungeonScores[charKey] = {
            overallScore = 0,
            dungeons = {},
            lastUpdate = 0,
        }
    end
    
    local scoreData = self.db.global.pveCache.mythicPlus.dungeonScores[charKey]
    local prevStoredOverall = scoreData.overallScore or 0
    local existingDungeons = scoreData.dungeons or {}
    
    local newOverall = 0
    if C_ChallengeMode.GetOverallDungeonScore then
        newOverall = C_ChallengeMode.GetOverallDungeonScore() or 0
    end
    
    local maps = C_ChallengeMode.GetMapTable()
    local anyIncomingDungeon = false
    local mergedDungeons = {}
    local preservedFromSV = 0
    local changedRows = 0
    
    if maps then
        for i = 1, #maps do
            local mapID = maps[i]
            local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
            
            local dungeonScore = 0
            local bestLevel = 0
            
            if intimeInfo and intimeInfo.level then
                dungeonScore = math.max(dungeonScore, intimeInfo.dungeonScore or 0)
                bestLevel = math.max(bestLevel, intimeInfo.level)
            end
            if overtimeInfo and overtimeInfo.level then
                dungeonScore = math.max(dungeonScore, overtimeInfo.dungeonScore or 0)
                bestLevel = math.max(bestLevel, overtimeInfo.level)
            end
            
            if dungeonScore > 0 or bestLevel > 0 then
                anyIncomingDungeon = true
            end
            
            local old = existingDungeons[mapID]
            -- Never replace a good cached row with an all-zero snapshot (login / affix / API race).
            if dungeonScore == 0 and bestLevel == 0 and old and ((old.score or 0) > 0 or (old.bestLevel or 0) > 0) then
                mergedDungeons[mapID] = { score = old.score or 0, bestLevel = old.bestLevel or 0 }
                preservedFromSV = preservedFromSV + 1
            else
                mergedDungeons[mapID] = { score = dungeonScore, bestLevel = bestLevel }
                local oldScore = old and old.score or 0
                local oldBestLevel = old and old.bestLevel or 0
                if oldScore ~= dungeonScore or oldBestLevel ~= bestLevel then
                    changedRows = changedRows + 1
                end
            end
        end
    end
    
    -- API often returns all zeros before M+ data hydrates; do not wipe a good SavedVariables snapshot.
    if newOverall == 0 and not anyIncomingDungeon and DungeonScoresBucketHasProgress(scoreData) then
        if ShouldLogPvECacheDiag("dungeonScores-skip-" .. tostring(charKey), 45) then
            PvECacheUserDebug(
                "dungeonScores: SKIP write (API overall=0, no per-map data, SV has progress) key=%s prevOverall=%s",
                tostring(charKey), tostring(scoreData.overallScore or 0))
        end
        return
    end
    
    -- GetMapTable() missing (rare): keep per-map SV; still allow overall score when the API returns it.
    if not maps or #maps == 0 then
        if newOverall > 0 then
            scoreData.overallScore = newOverall
            scoreData.lastUpdate = time()
            if prevStoredOverall ~= scoreData.overallScore then
                PvECacheUserDebug("dungeonScores: maps missing; updated overall only=%s key=%s", tostring(newOverall), tostring(charKey))
            end
        else
            if ShouldLogPvECacheDiag("dungeonScores-maps-missing-" .. tostring(charKey), 60) then
                PvECacheUserDebug("dungeonScores: maps missing; no write key=%s apiOverall=0", tostring(charKey))
            end
        end
        return
    end
    
    -- Overall: only overwrite with 0 when we never had a score (or API gave a non-zero update).
    if newOverall > 0 then
        scoreData.overallScore = newOverall
    elseif (scoreData.overallScore or 0) == 0 then
        scoreData.overallScore = 0
    end
    
    scoreData.dungeons = mergedDungeons
    scoreData.lastUpdate = time()
    if changedRows > 0 or prevStoredOverall ~= (scoreData.overallScore or 0) then
        PvECacheUserDebug(
            "dungeonScores: SAVED key=%s apiOverall=%s storedOverall=%s changedRows=%d maps=%d incomingAny=%s preservedRows=%d",
            tostring(charKey),
            tostring(newOverall),
            tostring(scoreData.overallScore or 0),
            changedRows,
            #maps,
            anyIncomingDungeon and "yes" or "no",
            preservedFromSV)
    end
end

-- ============================================================================
-- GREAT VAULT DATA
-- ============================================================================

---Update Great Vault activities for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateGreatVaultActivities(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey then return end
    charKey = CanonicalizePvEKey(charKey)
    
    -- SYNCHRONOUS: Process vault data already cached by WoW client (from previous OnUIInteract).
    -- ProcessGreatVaultActivities guards against empty data (returns early if GetActivities is nil/empty).
    self:ProcessGreatVaultActivities(charKey)
    
    -- NOTE: OnUIInteract() is NOT called here to avoid excessive server requests.
    -- VaultScanner handles the initial request on PLAYER_ENTERING_WORLD.
    -- PvECacheService event handlers (CHALLENGE_MODE_COMPLETED, etc.) call OnUIInteract as needed.
end

---Process Great Vault activities after server responds
---@param charKey string Character key (name-realm)
function WarbandNexus:ProcessGreatVaultActivities(charKey)
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities or #activities == 0 then 
        -- CRITICAL: Do NOT create empty arrays when API returns nil/empty.
        -- Server may not have responded to OnUIInteract() yet.
        -- Overwriting with empty data would wipe VaultScanner's persisted data.
        PvECacheUserDebug(
            "greatVault: GetActivities empty/nil — NOT overwriting cache (key=%s). Open Great Vault or wait for server.",
            tostring(charKey))
        return 
    end
    
    if not self.db.global.pveCache.greatVault.activities then
        self.db.global.pveCache.greatVault.activities = {}
    end

    local rewardData = self.db.global.pveCache.greatVault.rewards
        and self.db.global.pveCache.greatVault.rewards[charKey]
    local rewardClaimedResetTime = rewardData and tonumber(rewardData.claimedResetTime) or nil
    local previousActivities = self.db.global.pveCache.greatVault.activities[charKey]
    local hadCompletedVaultRows = GreatVaultActivityHasCompletedRows(previousActivities)
    local previousResetTime = GetCurrentWeeklyResetStartTime()
    local rewardClaimedThisReset = rewardClaimedResetTime and previousResetTime and rewardClaimedResetTime >= previousResetTime
    local storedBeforeReset = previousResetTime and previousActivities and (tonumber(previousActivities.lastUpdate) or 0) < previousResetTime
    local incomingCompletedRows = false
    for i = 1, #activities do
        local activity = activities[i]
        local progress = activity and tonumber(activity.progress) or 0
        local threshold = activity and tonumber(activity.threshold) or 0
        if threshold > 0 and progress >= threshold then
            incomingCompletedRows = true
            break
        end
    end
    if hadCompletedVaultRows and storedBeforeReset and not rewardClaimedThisReset and not incomingCompletedRows then
        PvECacheUserDebug(
            "greatVault: preserve pre-reset completed rows key=%s incomingComplete=no",
            tostring(charKey))
        return
    end
    
    -- Calculate weekly reset time for metadata
    local weeklyResetTime = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and (GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0
    
    -- Create fresh arrays only when we have real data (prevent stale duplicates)
    self.db.global.pveCache.greatVault.activities[charKey] = {
        raids = {},
        mythicPlus = {},
        pvp = {},
        world = {},
        lastUpdate = time(),
        weeklyResetTime = weeklyResetTime,
    }
    
    local charData = self.db.global.pveCache.greatVault.activities[charKey]
    
    for i = 1, #activities do
        local activity = activities[i]
        if activity then
            local data = {
                type = activity.type,
                index = activity.index,
                progress = activity.progress,
                threshold = activity.threshold,
                level = activity.level,
                id = activity.id,
                activityTierID = activity.activityTierID,
                raidString = activity.raidString,
                rewards = activity.rewards or nil,
            }
            
            -- Extract reward item level using GetExampleRewardItemHyperlinks
            if activity.id and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
                local currentLink, upgradeLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
                if currentLink then
                    local effectiveILvl, _, baseILvl = C_Item.GetDetailedItemLevelInfo(currentLink)
                    data.rewardItemLevel = effectiveILvl or baseILvl or 0
                end
            end
            
            -- Capture encounter info for raid slots (Blizzard's GetActivityEncounterInfo)
            if activity.type == Enum.WeeklyRewardChestThresholdType.Raid
                and C_WeeklyRewards.GetActivityEncounterInfo then
                local encounters = C_WeeklyRewards.GetActivityEncounterInfo(activity.type, activity.index)
                    if encounters and #encounters > 0 then
                        -- EJ APIs require Blizzard_EncounterJournal to be loaded
                        if not EJ_GetEncounterInfo and not InCombatLockdown() and Utilities and Utilities.SafeLoadAddOn then
                            Utilities:SafeLoadAddOn("Blizzard_EncounterJournal")
                        end
                    data.encounters = {}
                    for ei = 1, #encounters do
                        local enc = encounters[ei]
                        local encName, instanceID
                        if EJ_GetEncounterInfo then
                            local name, _, _, _, _, instID = EJ_GetEncounterInfo(enc.encounterID)
                            encName = name
                            instanceID = instID
                        end
                        local instanceName
                        if instanceID and EJ_GetInstanceInfo then
                            instanceName = EJ_GetInstanceInfo(instanceID)
                        end
                        local diffName
                        if enc.bestDifficulty and enc.bestDifficulty > 0 then
                            if DifficultyUtil and DifficultyUtil.GetDifficultyName then
                                diffName = DifficultyUtil.GetDifficultyName(enc.bestDifficulty)
                            elseif GetDifficultyInfo then
                                diffName = GetDifficultyInfo(enc.bestDifficulty)
                            end
                        end
                        -- Guard secret values
                        if issecretvalue and encName and issecretvalue(encName) then encName = nil end
                        if issecretvalue and instanceName and issecretvalue(instanceName) then instanceName = nil end
                        if issecretvalue and diffName and issecretvalue(diffName) then diffName = nil end
                        data.encounters[ei] = {
                            encounterID = enc.encounterID,
                            bestDifficulty = enc.bestDifficulty,
                            uiOrder = enc.uiOrder,
                            instanceID = enc.instanceID or instanceID,
                            name = encName,
                            instanceName = instanceName,
                            difficultyName = diffName,
                        }
                    end
                end
            end
            
            -- Categorize by activity type
            if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
                table.insert(charData.raids, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
                table.insert(charData.mythicPlus, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                table.insert(charData.pvp, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
                table.insert(charData.world, data)
            end
        end
    end
    
    -- Capture dungeon run counts (Heroic/Mythic/M+ separately)
    if C_WeeklyRewards.GetNumCompletedDungeonRuns then
        local numHeroic, numMythic, numMythicPlus = C_WeeklyRewards.GetNumCompletedDungeonRuns()
        charData.dungeonRunCounts = {
            heroic = numHeroic or 0,
            mythic = numMythic or 0,
            mythicPlus = numMythicPlus or 0,
        }
    end
    
    -- Capture sorted world/delve tier progress
    if C_WeeklyRewards.GetSortedProgressForActivity and Enum.WeeklyRewardChestThresholdType.World then
        local ok, worldProgress = pcall(C_WeeklyRewards.GetSortedProgressForActivity,
            Enum.WeeklyRewardChestThresholdType.World, true)
        if ok and worldProgress and #worldProgress > 0 then
            charData.worldTierProgress = {}
            for wi = 1, #worldProgress do
                charData.worldTierProgress[wi] = {
                    activityTierID = worldProgress[wi].activityTierID,
                    difficulty = worldProgress[wi].difficulty,
                    numPoints = worldProgress[wi].numPoints,
                }
            end
        end
    end
    
    PvECacheUserDebug(
        "greatVault: SAVED key=%s activities=%d raidSlots=%d mPlusSlots=%d worldSlots=%d pvpSlots=%d apiZeroSkipped=no",
        tostring(charKey),
        #activities,
        #(charData.raids or {}),
        #(charData.mythicPlus or {}),
        #(charData.world or {}),
        #(charData.pvp or {}))
        
    -- CRITICAL: Save to DB after data is populated
    WarbandNexus:SavePvECache()
    
    -- NOTE: PVE_UPDATED is NOT fired here. Both callers (UpdatePvEData and
    -- OnVaultDataReceived) fire PVE_UPDATED after this function returns.
    -- Firing here caused a DOUBLE event within milliseconds, and the UI's
    -- 800ms cooldown silently dropped the second (important) one.
end

---Update Great Vault reward availability
---Only sets hasAvailableRewards when rewards are for current period and claimable
---(uses AreRewardsForCurrentRewardPeriod/CanClaimRewards when available; avoids post-season stale true).
---@param charKey string Character key (name-realm)
---@param allowClaimTransition boolean|nil Allow a true -> false reward change after an explicit vault item event
function WarbandNexus:UpdateGreatVaultRewards(charKey, allowClaimTransition)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    local hasAvailable = false
    if C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards() then
        local periodCurrent = true
        if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod then
            periodCurrent = C_WeeklyRewards.AreRewardsForCurrentRewardPeriod() == true
        end

        local canClaim = true
        if C_WeeklyRewards.CanClaimRewards then
            canClaim = C_WeeklyRewards.CanClaimRewards() == true
        end

        if periodCurrent and canClaim then
            -- Midnight+: current-period + can-claim checks are authoritative.
            if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and C_WeeklyRewards.CanClaimRewards then
                hasAvailable = true
            else
                -- Legacy fallback when one/both newer APIs are unavailable.
                local activities = C_WeeklyRewards.GetActivities and C_WeeklyRewards.GetActivities() or nil
                hasAvailable = activities ~= nil and #activities > 0
            end
        end
    end
    
    if not self.db.global.pveCache.greatVault.rewards then
        self.db.global.pveCache.greatVault.rewards = {}
    end

    local previousRewardData = self.db.global.pveCache.greatVault.rewards[charKey]
    local previousResetTime = GetCurrentWeeklyResetStartTime()
    local claimedResetTime = previousRewardData and tonumber(previousRewardData.claimedResetTime) or nil
    local claimedAt = previousRewardData and tonumber(previousRewardData.claimedAt) or nil
    if previousRewardData and previousRewardData.hasAvailableRewards == true and hasAvailable == false then
        local vaultFrameShown = WeeklyRewardsFrame and WeeklyRewardsFrame.IsShown and WeeklyRewardsFrame:IsShown()
        if vaultFrameShown or allowClaimTransition == true then
            claimedResetTime = previousResetTime
            claimedAt = time()
        else
            hasAvailable = true
        end
    end

    self.db.global.pveCache.greatVault.rewards[charKey] = {
        hasAvailableRewards = hasAvailable,
        lastUpdate = time(),
        claimedAt = claimedAt,
        claimedResetTime = claimedResetTime,
    }
end

-- ============================================================================
-- LOCKOUT DATA
-- ============================================================================

---Update saved instance lockouts (raids + dungeons) for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateRaidLockouts(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    if not self.db.global.pveCache.lockouts.raids then
        self.db.global.pveCache.lockouts.raids = {}
    end
    if not self.db.global.pveCache.lockouts.dungeons then
        self.db.global.pveCache.lockouts.dungeons = {}
    end

    local numSavedInstances = GetNumSavedInstances()
    if not numSavedInstances or numSavedInstances == 0 then
        self.db.global.pveCache.lockouts.raids[charKey] = {}
        self.db.global.pveCache.lockouts.dungeons[charKey] = {}
        return
    end

    self.db.global.pveCache.lockouts.raids[charKey] = {}
    self.db.global.pveCache.lockouts.dungeons[charKey] = {}

    local nowServer = (GetServerTime and GetServerTime()) or time()

    for i = 1, numSavedInstances do
        -- 13=extendDisabled, 14=instanceId (10.0.5+); keep full tail so encounter fields stay aligned.
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, _extDis, _instId = GetSavedInstanceInfo(i)

        if issecretvalue and name and issecretvalue(name) then name = nil end
        if issecretvalue and difficulty and issecretvalue(difficulty) then difficulty = nil end
        if issecretvalue and difficultyName and issecretvalue(difficultyName) then difficultyName = nil end
        if issecretvalue and locked ~= nil and issecretvalue(locked) then locked = nil end
        if issecretvalue and extended ~= nil and issecretvalue(extended) then extended = nil end

        local difficultyID = SafeSavedInstanceNumber(difficulty)
        local journalInstanceID = SafeSavedInstanceNumber(_instId)
        local numEncountersSafe = SafeSavedInstanceNumber(numEncounters)
        local encProg = SafeSavedInstanceNumber(encounterProgress)
        local hasBossProgress = encProg and encProg > 0
        -- Some 5-player rows report locked=false while still on the saved list; boss progress implies a real lock.
        local lockedFlag = locked == true or locked == 1
        local extendedFlag = extended == true or extended == 1
        local activeLock = lockedFlag or extendedFlag or hasBossProgress
        if not name or not activeLock then
            -- Nothing to track for this row.
        else
            local resetSec = SafeSavedInstanceNumber(reset)
            -- Do not persist expired lockouts (GetSavedInstanceInfo reset is seconds until weekly reset).
            if not resetSec or resetSec <= 0 then
                -- Skip: already reset or no countdown.
            else
                local raidFlag = CoerceSavedInstanceIsRaid(isRaid, maxPlayers, difficultyID)
                local storageKey = BuildSavedInstanceStorageKey(i, id, journalInstanceID, difficultyID)
                local encounters = BuildSavedInstanceEncounterList(i, numEncountersSafe)
                local row = {
                    name = name,
                    instanceID = journalInstanceID,
                    difficulty = difficultyID,
                    difficultyName = difficultyName,
                    reset = resetSec,
                    resetAt = nowServer + resetSec,
                    extended = extendedFlag,
                    numEncounters = numEncountersSafe,
                    encounterProgress = encProg,
                    encounters = encounters,
                }
                if raidFlag == true then
                    self.db.global.pveCache.lockouts.raids[charKey][storageKey] = row
                elseif raidFlag == false then
                    self.db.global.pveCache.lockouts.dungeons[charKey][storageKey] = row
                end
                -- raidFlag nil: could not classify safely; skip.
            end
        end
    end
end

---Update world boss kills for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateWorldBossKills(charKey)
    if not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    -- World boss kills tracked via quest completion
    -- Midnight 12.0.5 world boss quest IDs
    local worldBossQuests = {
        93913, -- Midnight: World Boss (Quel'Thalas weekly world boss)
    }
    
    if not self.db.global.pveCache.lockouts.worldBosses then
        self.db.global.pveCache.lockouts.worldBosses = {}
    end
    
    self.db.global.pveCache.lockouts.worldBosses[charKey] = {}
    
    for i = 1, #worldBossQuests do
        local questID = worldBossQuests[i]
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then
            self.db.global.pveCache.lockouts.worldBosses[charKey][questID] = true
        end
    end
end

---Collect M+ run history for current character (this week only)
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateMythicPlusRunHistory(charKey)
    if not charKey or not self.db.global.pveCache then return end
    if not C_MythicPlus or not C_MythicPlus.GetRunHistory then return end
    charKey = CanonicalizePvEKey(charKey)

    if not self.db.global.pveCache.mythicPlus.runHistory then
        self.db.global.pveCache.mythicPlus.runHistory = {}
    end

    local runs = C_MythicPlus.GetRunHistory(false, false)
    if not runs then
        self.db.global.pveCache.mythicPlus.runHistory[charKey] = {}
        return
    end

    local history = {}
    for i = 1, #runs do
        local run = runs[i]
        if run and run.mapChallengeModeID and run.level then
            local dungeonName
            if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                dungeonName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
                if issecretvalue and dungeonName and issecretvalue(dungeonName) then
                    dungeonName = nil
                end
            end
            history[#history + 1] = {
                dungeon = dungeonName or ("Map " .. run.mapChallengeModeID),
                level = run.level,
                timed = run.completed or false,
            }
        end
    end

    table.sort(history, function(a, b) return a.level > b.level end)

    self.db.global.pveCache.mythicPlus.runHistory[charKey] = history
end

-- ============================================================================
-- DELVES DATA
-- ============================================================================

---True if any configured Bountiful / Trovehunter weekly quest is flagged complete for the **current** client session.
---Call only while the relevant character is logged in; PvE UI uses per-char cache from UpdateDelvesData for other rows.
---@return boolean
function WarbandNexus:IsBountifulDelveWeeklyDone()
    local ids = Constants.PVE_BOUNTIFUL_WEEKLY_QUEST_IDS
    if not ids or #ids == 0 then return false end
    for i = 1, #ids do
        local qid = ids[i]
        if qid and SafeIsQuestFlaggedCompleted(qid) then
            return true
        end
    end
    return false
end

---Update Delves companion data (account-wide) and per-character delve progress.
---Uses C_DelvesUI APIs (Midnight 12.0+) for companion info and season tracking.
function WarbandNexus:UpdateDelvesData(charKey)
    if not self.db.global.pveCache or not self.db.global.pveCache.delves then return end
    if charKey and charKey ~= "" then
        charKey = CanonicalizePvEKey(charKey)
    end
    
    local delves = self.db.global.pveCache.delves
    
    -- Season number (account-wide)
    if C_DelvesUI and C_DelvesUI.GetCurrentDelvesSeasonNumber then
        local seasonNum = C_DelvesUI.GetCurrentDelvesSeasonNumber()
        if seasonNum and type(seasonNum) == "number" then
            delves.season = seasonNum
        end
    end
    
    -- Companion info (account-wide — same companion for all characters)
    if C_DelvesUI and C_DelvesUI.GetCompanionInfoForActivePlayer then
        local companionInfoID = C_DelvesUI.GetCompanionInfoForActivePlayer()
        if companionInfoID and not (issecretvalue and issecretvalue(companionInfoID)) then
            delves.companion.infoID = companionInfoID
        end
        
        -- Companion faction (for renown/level tracking)
        if C_DelvesUI.GetFactionForCompanion then
            local factionID = C_DelvesUI.GetFactionForCompanion()
            if factionID and type(factionID) == "number" then
                delves.companion.factionID = factionID
                
                -- Resolve companion renown level from reputation API
                if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                    local factionData = C_MajorFactions.GetMajorFactionData(factionID)
                    if factionData then
                        delves.companion.renownLevel = factionData.renownLevel or 0
                        delves.companion.name = factionData.name
                    end
                end
            end
        end
        
        -- Companion role info
        if C_DelvesUI.GetRoleNodeForCompanion then
            local roleNodeID = C_DelvesUI.GetRoleNodeForCompanion()
            if roleNodeID and not (issecretvalue and issecretvalue(roleNodeID)) then
                delves.companion.roleNodeID = roleNodeID
            end
        end
    end
    
    delves.companion.lastUpdate = time()
    
    -- Per-character: bountiful delve quest completion
    if charKey then
        if not delves.characters then delves.characters = {} end
        if not delves.characters[charKey] then delves.characters[charKey] = {} end
        
        -- Bountiful / Trovehunter weeklies — snapshot for this character when they are logged in (quest API is session-local).
        delves.characters[charKey].bountifulComplete = self.IsBountifulDelveWeeklyDone and self:IsBountifulDelveWeeklyDone() or false
        local gildedStashes, gildedStashesMax = GetGildedStashCounts()
        local priorGildedStashes = tonumber(delves.characters[charKey].gildedStashes)
        if gildedStashes >= 0 or priorGildedStashes == nil then
            delves.characters[charKey].gildedStashes = gildedStashes
        end
        delves.characters[charKey].gildedStashesMax = gildedStashesMax
        local crackedID = Constants.PVE_CRACKED_KEYSTONE_WEEKLY_QUEST_ID or 92600
        delves.characters[charKey].crackedKeystoneComplete = SafeIsQuestFlaggedCompleted(crackedID)
        delves.characters[charKey].lastUpdate = time()
    end
end

-- ============================================================================
-- UPDATE ORCHESTRATION
-- ============================================================================

---Update all PvE data for current character (throttled)
function WarbandNexus:UpdatePvEData()
    DebugPrint("|cff9370DB[PvECache]|r [PvE Action] UpdatePvEData triggered")
    -- Align with CollectPvEData / UI: no writes when PvE module disabled
    if ns.Utilities and ns.Utilities.IsModuleEnabled and not ns.Utilities:IsModuleEnabled("pve") then
        return
    end
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Ensure DB is initialized
    if not self.db or not self.db.global or not self.db.global.pveCache then
        self:InitializePvECache()
    end
    
    -- Throttle check
    local currentTime = GetTime()
    if currentTime - lastUpdateTime < UPDATE_THROTTLE then
        pendingUpdate = true
        return
    end
    
    lastUpdateTime = currentTime
    pendingUpdate = false
    
    -- Get current character key (canonical = one pveCache bucket per character)
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    charKey = CanonicalizePvEKey(charKey)
    if not charKey then return end

    local beforeSig = BuildPvESignature(self.db.global.pveCache, charKey)

    -- Ensure weekly reset stale keys are pruned even if affix event did not fire this session.
    PruneExpiredKeystonesForWeeklyReset()

    -- Update all PvE data (API > DB)
    self:UpdateMythicPlusAffixes()
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateDungeonScores(charKey)
    self:UpdateGreatVaultRewards(charKey)
    self:UpdateRaidLockouts(charKey)
    self:UpdateWorldBossKills(charKey)
    self:UpdateMythicPlusRunHistory(charKey)
    self:UpdateDelvesData(charKey)
    
    -- FALLBACK: Populate vault activities from C_WeeklyRewards.GetActivities() only if
    -- VaultScanner hasn't already provided richer data for this character.
    -- VaultScanner is the primary source (PLAYER_ENTERING_WORLD → SyncVaultDataFromScanner)
    -- but may fail on fresh installs, timing issues, or empty API responses.
    local hasVaultData = self.db.global.pveCache
        and self.db.global.pveCache.greatVault
        and self.db.global.pveCache.greatVault.activities
        and self.db.global.pveCache.greatVault.activities[charKey]
        and (next(self.db.global.pveCache.greatVault.activities[charKey].raids or {})
            or next(self.db.global.pveCache.greatVault.activities[charKey].mythicPlus or {})
            or next(self.db.global.pveCache.greatVault.activities[charKey].world or {}))
    if not hasVaultData then
        self:UpdateGreatVaultActivities(charKey)
    end
    
    -- Update timestamp (data already in DB)
    self:SavePvECache()
    
    local afterSig = BuildPvESignature(self.db.global.pveCache, charKey)
    if beforeSig ~= afterSig then
        -- Fire event only when API→DB produced a real data change.
        self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    end
    
end

---Schedule throttled update (called by pending update timer)
function WarbandNexus:ProcessPendingPvEUpdate()
    if pendingUpdate then
        self:UpdatePvEData()
    end
end

-- ============================================================================
-- PUBLIC API (FOR UI AND DATASERVICE)
-- ============================================================================

---Get PvE data for a specific character or all characters
---@param charKey string|nil Character key (nil = return all)
---@return table PvE data
function WarbandNexus:GetPvEData(charKey)
    -- CRITICAL: Always read directly from DB (no cache)
    local dbCache = self.db and self.db.global and self.db.global.pveCache or {}
    
    if charKey then
        charKey = CanonicalizePvEKey(charKey)
        local bestRuns = dbCache.mythicPlus and dbCache.mythicPlus.bestRuns and dbCache.mythicPlus.bestRuns[charKey] or {}
        local dungeonScoresData = dbCache.mythicPlus and dbCache.mythicPlus.dungeonScores and dbCache.mythicPlus.dungeonScores[charKey]
        
        -- Get overall score from dungeonScores (primary) or bestRuns (fallback)
        local overallScore = 0
        if dungeonScoresData and dungeonScoresData.overallScore then
            overallScore = dungeonScoresData.overallScore
        else
            overallScore = bestRuns.overallScore or 0
        end
        
        -- Build dungeon list from dungeonScores (for UI rendering)
        local dungeons = {}
        
        if C_ChallengeMode then
            local maps = C_ChallengeMode.GetMapTable()
            if maps then
                for i = 1, #maps do
                    local mapID = maps[i]
                    local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    if issecretvalue and mapName and issecretvalue(mapName) then mapName = nil end
                    
                    local dungeonScore = 0
                    local bestLevel = 0
                    
                    if dungeonScoresData and dungeonScoresData.dungeons and dungeonScoresData.dungeons[mapID] then
                        local dungeonData = dungeonScoresData.dungeons[mapID]
                        dungeonScore = dungeonData.score or 0
                        bestLevel = dungeonData.bestLevel or 0
                    end
                    
                    -- Fallback to bestRuns if dungeonScores doesn't have bestLevel
                    if bestLevel == 0 then
                        local runData = bestRuns[mapID]
                        bestLevel = runData and runData.level or 0
                    end
                    
                    table.insert(dungeons, {
                        mapID = mapID,
                        name = mapName or ("Dungeon " .. mapID),
                        texture = texture,
                        bestLevel = bestLevel,  -- From dungeonScores or bestRuns
                        score = dungeonScore,  -- From dungeonScores cache
                    })
                end
                
                -- Sort by name
                table.sort(dungeons, CmpNameSort)
            end
        end
        
        -- Hydrate lockouts: raids vs dungeons (Instance Tracker merges both; PvE raid panel uses raids only).
        local rawRaids = dbCache.lockouts and dbCache.lockouts.raids and dbCache.lockouts.raids[charKey] or {}
        local rawDungeons = dbCache.lockouts and dbCache.lockouts.dungeons and dbCache.lockouts.dungeons[charKey] or {}
        local raidLockouts = HydrateSavedLockoutsForChar(rawRaids, true)
        local dungeonLockouts = HydrateSavedLockoutsForChar(rawDungeons, false)
        local combinedLockouts = {}
        for i = 1, #raidLockouts do combinedLockouts[#combinedLockouts + 1] = raidLockouts[i] end
        for i = 1, #dungeonLockouts do combinedLockouts[#combinedLockouts + 1] = dungeonLockouts[i] end
        table.sort(combinedLockouts, CmpNameSort)

        -- Return data for specific character
        local vaultActivities = dbCache.greatVault and dbCache.greatVault.activities and dbCache.greatVault.activities[charKey]
        local returnData = {
            keystone = dbCache.mythicPlus and dbCache.mythicPlus.keystones and dbCache.mythicPlus.keystones[charKey],
            bestRuns = bestRuns,
            dungeonScores = dungeonScoresData,
            vaultActivities = vaultActivities,
            vaultRewards = dbCache.greatVault and dbCache.greatVault.rewards and dbCache.greatVault.rewards[charKey],
            greatVault = vaultActivities or {},  -- Alias for legacy consumers
            raidLockouts = raidLockouts,
            dungeonLockouts = dungeonLockouts,
            lockouts = combinedLockouts,  -- Raids + dungeons for DataService / debug
            worldBosses = dbCache.lockouts and dbCache.lockouts.worldBosses and dbCache.lockouts.worldBosses[charKey],
            -- Delves data (companion is account-wide, per-char quest status)
            delves = {
                companion = dbCache.delves and dbCache.delves.companion or {},
                season = dbCache.delves and dbCache.delves.season or 0,
                character = dbCache.delves and dbCache.delves.characters and dbCache.delves.characters[charKey] or {},
            },
            -- Add legacy-compatible mythicPlus structure
            mythicPlus = {
                overallScore = overallScore,
                dungeons = dungeons,
                bestRuns = bestRuns,
                dungeonScores = dungeonScoresData,
                runHistory = dbCache.mythicPlus and dbCache.mythicPlus.runHistory and dbCache.mythicPlus.runHistory[charKey] or {},
            },
        }
        
        return returnData
    else
        -- Return all data (for global queries like currentAffixes)
        -- Hydrate affixes: SV stores only IDs, resolve name/description/icon on-demand
        local rawAffixes = dbCache.mythicPlus and dbCache.mythicPlus.currentAffixes or {}
        local hydratedAffixes = {}
        for i = 1, #rawAffixes do
            local affixEntry = rawAffixes[i]
            local affixID = type(affixEntry) == "number" and affixEntry or (type(affixEntry) == "table" and affixEntry.id)
            if affixID and C_ChallengeMode then
                local name, description, filedataid = C_ChallengeMode.GetAffixInfo(affixID)
                if name then
                    table.insert(hydratedAffixes, {
                        id = affixID,
                        name = name,
                        description = description or "",
                        icon = filedataid,
                    })
                end
            end
        end
        
        return {
            mythicPlus = dbCache.mythicPlus or {},
            greatVault = dbCache.greatVault or {},
            lockouts = dbCache.lockouts or {},
            delves = dbCache.delves or {},
            currentAffixes = hydratedAffixes,
        }
    end
end

---True if CollectPvEData produced real M+ rows (not an error/empty pre-hydration snapshot).
local function LegacyMythicSnapshotHasData(mp)
    if not mp or type(mp) ~= "table" then return false end
    if mp.keystone and type(mp.keystone.level) == "number" and mp.keystone.level > 0 and mp.keystone.mapID then
        return true
    end
    if type(mp.overallScore) == "number" and mp.overallScore > 0 then return true end
    if mp.dungeons then
        for i = 1, #mp.dungeons do
            local d = mp.dungeons[i]
            if d and ((type(d.score) == "number" and d.score > 0) or (type(d.bestLevel) == "number" and d.bestLevel > 0)) then
                return true
            end
        end
    end
    if mp.dungeonProgress then
        for _, data in pairs(mp.dungeonProgress) do
            if data and ((type(data.score) == "number" and data.score > 0) or (type(data.bestLevel) == "number" and data.bestLevel > 0)) then
                return true
            end
        end
    end
    return false
end

local function GreatVaultActivityHasRows(bucket)
    if not bucket or type(bucket) ~= "table" then return false end
    if bucket.raids and #bucket.raids > 0 then return true end
    if bucket.mythicPlus and #bucket.mythicPlus > 0 then return true end
    if bucket.world and #bucket.world > 0 then return true end
    if bucket.pvp and #bucket.pvp > 0 then return true end
    return false
end

GreatVaultActivityHasCompletedRows = function(bucket)
    if not bucket or type(bucket) ~= "table" then return false end
    for _, category in ipairs({ "raids", "mythicPlus", "world", "pvp" }) do
        local rows = bucket[category]
        if type(rows) == "table" then
            for i = 1, #rows do
                local row = rows[i]
                local progress = row and tonumber(row.progress) or 0
                local threshold = row and tonumber(row.threshold) or 0
                if threshold > 0 and progress >= threshold then
                    return true
                end
            end
        end
    end
    return false
end

---Import legacy PvE data for a specific character into pveCache.
---Used by DatabaseOptimizer migration and UpdatePvEDataV2 fallback.
---Maps the old DataService progress format → PvECacheService structure.
---@param charKey string Character key (name-realm)
---@param legacyData table Legacy pveProgress entry or CollectPvEData result
function WarbandNexus:ImportLegacyPvEData(charKey, legacyData)
    if not charKey or not legacyData then return end
    charKey = CanonicalizePvEKey(charKey)
    if not charKey or charKey == "" then return end
    
    PvECacheUserDebug(
        "import: START key=%s has.mythicPlus=%s has.greatVault=%s has.lockouts=%s",
        tostring(charKey),
        legacyData.mythicPlus and "yes" or "no",
        legacyData.greatVault and ("yes len=" .. tostring(#legacyData.greatVault)) or "no",
        legacyData.lockouts and ("yes len=" .. tostring(#legacyData.lockouts)) or "no")
    
    -- Ensure DB is initialized
    if not self.db or not self.db.global or not self.db.global.pveCache then
        self:InitializePvECache()
    end
    if not self.db.global.pveCache then return end
    
    local pc = self.db.global.pveCache
    
    -- ── M+ Data ──
    if legacyData.mythicPlus then
        local mp = legacyData.mythicPlus
        local existingScores = pc.mythicPlus.dungeonScores and pc.mythicPlus.dungeonScores[charKey]
        local hadCachedMythic = DungeonScoresBucketHasProgress(existingScores)
            or (pc.mythicPlus.keystones and pc.mythicPlus.keystones[charKey] and pc.mythicPlus.keystones[charKey].level and pc.mythicPlus.keystones[charKey].level > 0)
        -- SaveCharacter can run before Challenge Mode APIs hydrate; do not replace good SV with zeros.
        if hadCachedMythic and not LegacyMythicSnapshotHasData(mp) then
            local prevOverall = existingScores and type(existingScores.overallScore) == "number" and existingScores.overallScore or 0
            DebugPrint(string.format("|cff9370DB[PvECache]|r ImportLegacyPvEData: skip mythic for %s (stale/empty snapshot)", charKey))
            PvECacheUserDebug(
                "import: SKIP mythic (empty snapshot, cache kept) key=%s prevOverall=%s snapshotOverall=%s nonzero=%s",
                tostring(charKey), tostring(prevOverall), tostring(mp and mp.overallScore or 0),
                (prevOverall > 0) and "yes" or "no")
        else
        
        -- Keystone: challenge mapID + level (reject legacy CollectPvEData bag scans that stored itemID as mapID).
        if mp.keystone and mp.keystone.level and mp.keystone.level > 0 and mp.keystone.mapID then
            local mid = mp.keystone.mapID
            if type(mid) == "number" and mid > 0 then
                local accept = false
                if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                    local mapName = C_ChallengeMode.GetMapUIInfo(mid)
                    if mapName and not (issecretvalue and issecretvalue(mapName)) and mapName ~= "" then
                        accept = true
                    end
                end
                if not accept and mid < 100000 then
                    accept = true
                end
                if accept then
                    pc.mythicPlus.keystones = pc.mythicPlus.keystones or {}
                    pc.mythicPlus.keystones[charKey] = {
                        mapID = mid,
                        level = mp.keystone.level,
                        lastUpdate = mp.keystone.lastUpdate or time(),
                    }
                end
            end
        end
        
        -- Overall score → dungeonScores
        pc.mythicPlus.dungeonScores = pc.mythicPlus.dungeonScores or {}
        pc.mythicPlus.dungeonScores[charKey] = pc.mythicPlus.dungeonScores[charKey] or {}
        pc.mythicPlus.dungeonScores[charKey].overallScore = mp.overallScore or 0
        
        -- Dungeon progress → bestRuns + dungeonScores.dungeons
        if mp.dungeonProgress then
            pc.mythicPlus.bestRuns = pc.mythicPlus.bestRuns or {}
            pc.mythicPlus.bestRuns[charKey] = pc.mythicPlus.bestRuns[charKey] or {}
            pc.mythicPlus.bestRuns[charKey].overallScore = mp.overallScore or 0
            
            pc.mythicPlus.dungeonScores[charKey].dungeons = pc.mythicPlus.dungeonScores[charKey].dungeons or {}
            
            for mapID, data in pairs(mp.dungeonProgress) do
                pc.mythicPlus.bestRuns[charKey][mapID] = {
                    level = data.bestLevel or 0,
                    score = data.score or 0,
                }
                pc.mythicPlus.dungeonScores[charKey].dungeons[mapID] = {
                    score = data.score or 0,
                    bestLevel = data.bestLevel or 0,
                }
            end
        end
        
        -- Legacy format: dungeons as array (from CollectPvEData)
        if mp.dungeons then
            pc.mythicPlus.bestRuns = pc.mythicPlus.bestRuns or {}
            pc.mythicPlus.bestRuns[charKey] = pc.mythicPlus.bestRuns[charKey] or {}
            pc.mythicPlus.bestRuns[charKey].overallScore = mp.overallScore or 0
            
            pc.mythicPlus.dungeonScores[charKey].dungeons = pc.mythicPlus.dungeonScores[charKey].dungeons or {}
            
            for i = 1, #mp.dungeons do
                local dungeon = mp.dungeons[i]
                if dungeon.mapID then
                    pc.mythicPlus.bestRuns[charKey][dungeon.mapID] = {
                        level = dungeon.bestLevel or 0,
                        score = dungeon.score or 0,
                    }
                    pc.mythicPlus.dungeonScores[charKey].dungeons[dungeon.mapID] = {
                        score = dungeon.score or 0,
                        bestLevel = dungeon.bestLevel or 0,
                    }
                end
            end
        end
        local appliedOverall = pc.mythicPlus.dungeonScores[charKey] and pc.mythicPlus.dungeonScores[charKey].overallScore or 0
        PvECacheUserDebug(
            "import: mythic APPLIED key=%s storedOverall=%s nonzero=%s",
            tostring(charKey), tostring(appliedOverall), (appliedOverall > 0) and "yes" or "no")
        end
    end
    
    -- ── Great Vault ──
    if legacyData.greatVault then
        local prevVault = pc.greatVault.activities and pc.greatVault.activities[charKey]
        if #legacyData.greatVault == 0 and GreatVaultActivityHasRows(prevVault) then
            DebugPrint(string.format("|cff9370DB[PvECache]|r ImportLegacyPvEData: skip empty greatVault for %s (keeping cache)", charKey))
            PvECacheUserDebug(
                "import: SKIP greatVault (legacy [] but cache had rows) key=%s — vault preserved",
                tostring(charKey))
        else
        pc.greatVault.activities = pc.greatVault.activities or {}
        local vaultData = { raids = {}, mythicPlus = {}, pvp = {}, world = {}, lastUpdate = time() }
        
        for i = 1, #legacyData.greatVault do
            local activity = legacyData.greatVault[i]
            local entry = {
                progress = activity.progress or 0,
                threshold = activity.threshold or 0,
                level = activity.level or 0,
                rewardItemLevel = activity.rewardItemLevel,
            }
            
            local actType = activity.type
            if actType == 1 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid) then
                table.insert(vaultData.raids, entry)
            elseif actType == 2 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities) then
                table.insert(vaultData.mythicPlus, entry)
            elseif actType == 3 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.RankedPvP) then
                table.insert(vaultData.pvp, entry)
            elseif actType == 4 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World) then
                table.insert(vaultData.world, entry)
            end
        end
        
        pc.greatVault.activities[charKey] = vaultData
        
        -- Unclaimed rewards
        if legacyData.hasUnclaimedRewards then
            pc.greatVault.rewards = pc.greatVault.rewards or {}
            pc.greatVault.rewards[charKey] = {
                hasAvailableRewards = true,
                lastUpdate = time(),
            }
        end
        PvECacheUserDebug(
            "import: greatVault APPLIED key=%s raid=%d mPlus=%d world=%d pvp=%d unclaimed=%s",
            tostring(charKey),
            #vaultData.raids, #vaultData.mythicPlus, #vaultData.world, #vaultData.pvp,
            legacyData.hasUnclaimedRewards and "yes" or "no")
        end
    end
    
    -- ── Saved instance lockouts (raids + dungeons) ──
    if legacyData.lockouts then
        local prevRaids = pc.lockouts.raids and pc.lockouts.raids[charKey]
        local prevDungeons = pc.lockouts.dungeons and pc.lockouts.dungeons[charKey]
        local hadPrevLockouts = (type(prevRaids) == "table" and next(prevRaids))
            or (type(prevDungeons) == "table" and next(prevDungeons))
        if legacyData.lockouts and #legacyData.lockouts == 0 and hadPrevLockouts then
            DebugPrint(string.format("|cff9370DB[PvECache]|r ImportLegacyPvEData: skip empty lockouts for %s (keeping cache)", charKey))
            PvECacheUserDebug(
                "import: SKIP lockouts (legacy [] but cache had rows) key=%s",
                tostring(charKey))
        else
        pc.lockouts.raids = pc.lockouts.raids or {}
        pc.lockouts.dungeons = pc.lockouts.dungeons or {}
        pc.lockouts.raids[charKey] = {}
        pc.lockouts.dungeons[charKey] = {}

        local nowImp = (GetServerTime and GetServerTime()) or time()
        for i = 1, #legacyData.lockouts do
            local lockout = legacyData.lockouts[i]
            local id = lockout.instanceID or lockout.id
            if id then
                local rRaw = lockout.reset
                local resetSec = nil
                if rRaw ~= nil and not (issecretvalue and issecretvalue(rRaw)) then
                    resetSec = tonumber(rRaw)
                end
                if resetSec and resetSec > 0 then
                    local row = {
                        name = lockout.name,
                        difficulty = lockout.difficulty or lockout.difficultyID,
                        reset = rRaw,
                        resetAt = nowImp + resetSec,
                        extended = lockout.extended or false,
                        numEncounters = lockout.total or lockout.numEncounters,
                        encounterProgress = lockout.progress or lockout.encounterProgress,
                    }
                    if lockout.isRaid == true then
                        pc.lockouts.raids[charKey][id] = row
                    elseif lockout.isRaid == false then
                        pc.lockouts.dungeons[charKey][id] = row
                    else
                        pc.lockouts.raids[charKey][id] = row
                    end
                end
            end
        end
        local nRaid, nDung = 0, 0
        if pc.lockouts.raids[charKey] then
            for _ in pairs(pc.lockouts.raids[charKey]) do nRaid = nRaid + 1 end
        end
        if pc.lockouts.dungeons[charKey] then
            for _ in pairs(pc.lockouts.dungeons[charKey]) do nDung = nDung + 1 end
        end
        PvECacheUserDebug(
            "import: lockouts APPLIED key=%s raids=%d dungeons=%d nonzero=%s",
            tostring(charKey), nRaid, nDung, ((nRaid + nDung) > 0) and "yes" or "no")
        end
    end
    
    self:SavePvECache()
    DebugPrint(string.format("|cff9370DB[PvECache]|r Imported legacy PvE data for %s", charKey))
    PvECacheUserDebug("import: DONE key=%s (SavedVariables write)", tostring(charKey))
end

---Clear PvE cache (force refresh)
function WarbandNexus:ClearPvECache()
    if not self.db or not self.db.global or not self.db.global.pveCache then return end
    
    self.db.global.pveCache.mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} }
    self.db.global.pveCache.greatVault = { activities = {}, rewards = {} }
    self.db.global.pveCache.lockouts = { raids = {}, dungeons = {}, worldBosses = {} }
    self.db.global.pveCache.delves = { companion = {}, season = 0 }
    self.db.global.pveCache.lastUpdate = 0
    
    self:SavePvECache()
end

-- ============================================================================
-- EVENT REGISTRATION (Auto-register on module load)
-- ============================================================================

---Register PvE event listeners
function WarbandNexus:RegisterPvECacheEvents()
    if not self.RegisterEvent then
        return
    end
    
    -- Prime C_MythicPlus API cache on login (deferred to ensure API readiness)
    C_Timer.After(3, function()
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestCurrentAffixes()
        end
    end)
    
    -- Vault warm-up: VaultScanner fires OnUIInteract at T+1s, server responds ~T+2-4s.
    -- Re-collect vault data at T+5s to catch any iLvl that arrived after initial scan.
    C_Timer.After(5, function()
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
        local charKey = CanonicalizePvEKey(ns.Utilities:GetCharacterKey())
        if charKey then
            WarbandNexus:ProcessGreatVaultActivities(charKey)
            WarbandNexus:SavePvECache()
        end
    end)
    
    -- Throttle timer for PvE updates
    local pveUpdateTimer = nil
    local function ThrottledPvEUpdate()
        -- GUARD: Only process if character is tracked
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        
        -- Cancel pending update
        if pveUpdateTimer then
            pveUpdateTimer:Cancel()
        end
        
        -- Wait 1.0s before updating (API needs time to update)
        pveUpdateTimer = C_Timer.NewTimer(1.0, function()
            WarbandNexus:UpdatePvEData()
            pveUpdateTimer = nil
        end)
    end

    local function RefreshVaultRewardsAfterItemChange(delay)
        C_Timer.After(delay or 0.5, function()
            if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
                return
            end

            local charKey = CanonicalizePvEKey(ns.Utilities:GetCharacterKey())
            if not charKey then
                return
            end

            local beforeSig = BuildPvESignature(WarbandNexus.db.global and WarbandNexus.db.global.pveCache, charKey)
            WarbandNexus:UpdateGreatVaultRewards(charKey, true)
            WarbandNexus:SavePvECache()

            local afterSig = BuildPvESignature(WarbandNexus.db.global and WarbandNexus.db.global.pveCache, charKey)
            if beforeSig ~= afterSig then
                WarbandNexus:SendMessage(Constants.EVENTS.PVE_UPDATED)
            end
        end)
    end
    
    -- Mythic+ events
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHALLENGE_MODE_COMPLETED triggered")
        
        -- Request fresh data from Blizzard APIs
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestRewards()
        end
        if C_WeeklyRewards then
            C_WeeklyRewards.OnUIInteract()
        end
        
        ThrottledPvEUpdate()
    end)
    
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] MYTHIC_PLUS_NEW_WEEKLY_RECORD triggered")
        ThrottledPvEUpdate()
    end)
    
    -- CHALLENGE_MODE_MAPS_UPDATE: fires when M+ map/keystone data is refreshed by the server
    -- This is the proper event for keystone detection (instead of bag scanning)
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHALLENGE_MODE_MAPS_UPDATE triggered")
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
        ThrottledPvEUpdate()
    end)
    
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] MYTHIC_PLUS_CURRENT_AFFIX_UPDATE triggered (weekly reset)")
        
        -- Affix refresh: clear affix IDs, then prune stale keystones for the new weekly cycle.
        if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache then
            if WarbandNexus.db.global.pveCache.mythicPlus then
                WarbandNexus.db.global.pveCache.mythicPlus.currentAffixes = {}
                PruneExpiredKeystonesForWeeklyReset()
            end
            
            WarbandNexus:SavePvECache()
        end
        
        -- Then update with new data
        ThrottledPvEUpdate()
        
        -- Also refresh keystone detection (new weekly key may be in bags)
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
    end)
    
    -- Weekly Vault events
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WEEKLY_REWARDS_UPDATE triggered")
        WarbandNexus:OnVaultDataReceived()
    end)
    
    self:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WEEKLY_REWARDS_ITEM_CHANGED triggered")
        RefreshVaultRewardsAfterItemChange(0.3)
        RefreshVaultRewardsAfterItemChange(1.5)
        ThrottledPvEUpdate()
    end)
    
    -- Raid lockout events
    self:RegisterEvent("UPDATE_INSTANCE_INFO", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] UPDATE_INSTANCE_INFO triggered")
        ThrottledPvEUpdate()
    end)
    
    -- Delves events (Midnight 12.0+)
    pcall(function()
        self:RegisterEvent("DELVES_ACCOUNT_DATA_ELEMENT_CHANGED", function()
            DebugPrint("|cff9370DB[PvECache]|r [PvE Event] DELVES_ACCOUNT_DATA_ELEMENT_CHANGED triggered")
            ThrottledPvEUpdate()
        end)
    end)
    
end

-- ============================================================================
-- EVENT HANDLERS (Called by registered events above)
-- ============================================================================

-- REMOVED: OnMythicPlusAffixUpdate — never registered; PvECacheService handles affix updates inline.

---Handle WEEKLY_REWARDS_UPDATE event (vault data received from server)
---NOTE: Named OnVaultDataReceived to avoid collision with PlansManager:OnPvEUpdateCheckPlans
---ARCHITECTURE: Vault activities are processed by VaultScanner → SyncVaultDataFromScanner.
---This handler only updates NON-vault data (keystone, best runs, rewards) to avoid
---overwriting VaultScanner's richer data (nextLevelIlvl, maxIlvl, nextKeyLevel).
function WarbandNexus:OnVaultDataReceived()
    local charKey = CanonicalizePvEKey(ns.Utilities:GetCharacterKey())
    if not charKey then return end
    local beforeSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    
    -- DO NOT call ProcessGreatVaultActivities here!
    -- VaultScanner handles vault activities via SyncVaultDataFromScanner (richer data).
    -- Calling it here would overwrite VaultScanner's enhanced data with basic data.
    
    -- Update non-vault PvE data
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateGreatVaultRewards(charKey)
    
    -- Update timestamp (data already in DB)
    self:SavePvECache()
    
    local afterSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    if beforeSig ~= afterSig then
        self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    end
end

---Sync vault data from VaultScanner to PvECacheService
---@param vaultSlots table Array of vault slot data from VaultScanner
function WarbandNexus:SyncVaultDataFromScanner(vaultSlots)
    if not vaultSlots or type(vaultSlots) ~= "table" then
        return
    end
    -- Never sync an empty slot list into SavedVariables: callers should use
    -- VaultScanner only after GetActivities() returned data. An empty table
    -- would clear per-character vault rows without replacing them.
    if #vaultSlots == 0 then
        return
    end
    
    -- LAZY INIT: VaultScanner fires on PLAYER_ENTERING_WORLD (T+1s),
    -- but InitializePvECache runs at T+2s. On first install, pveCache
    -- doesn't exist yet. Initialize it here so vault data isn't lost.
    if not self.db or not self.db.global then return end
    if not self.db.global.pveCache then
        self:InitializePvECache()
    end
    if not self.db.global.pveCache then return end
    
    -- Must match PvEUI / GetPvEData: one bucket per character after realm normalization.
    local charKey = CanonicalizePvEKey(ns.Utilities:GetCharacterKey())
    if not charKey then return end
    local beforeSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    
    if not self.db.global.pveCache.greatVault.activities then
        self.db.global.pveCache.greatVault.activities = {}
    end
    
    if not self.db.global.pveCache.greatVault.activities[charKey] then
        self.db.global.pveCache.greatVault.activities[charKey] = {
            raids = {},
            mythicPlus = {},
            pvp = {},
            world = {},
            lastUpdate = time(),
            weeklyResetTime = (GetServerTime() + (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset() or 0)),
        }
    end
    
    -- PRESERVE existing iLvl data before clearing.
    -- GetExampleRewardItemHyperlinks() may return nil momentarily after a slot
    -- transitions to complete (server computing rewards). Build a lookup by
    -- activityID so known-good values survive a re-scan that returns 0.
    local activities = self.db.global.pveCache.greatVault.activities[charKey]
    local preservedILvl = {}
    local vaultCategories = {"raids", "mythicPlus", "pvp", "world"}
    for ci = 1, #vaultCategories do
        local category = vaultCategories[ci]
        if activities[category] then
            local catList = activities[category]
            for ai = 1, #catList do
                local a = catList[ai]
                if a.id and a.rewardItemLevel and a.rewardItemLevel > 0 then
                    preservedILvl[a.id] = {
                        rewardItemLevel = a.rewardItemLevel,
                        nextLevelIlvl = a.nextLevelIlvl or 0,
                        maxIlvl = a.maxIlvl or 0,
                    }
                end
            end
        end
    end
    
    -- Keep references so we can roll back if the scanner payload maps to zero
    -- recognized categories (e.g. unexpected typeName) — otherwise we would wipe
    -- good SavedVariables data and show "No vault data" for that character.
    local backupRaids = activities.raids
    local backupMythicPlus = activities.mythicPlus
    local backupPvp = activities.pvp
    local backupWorld = activities.world
    local hadStoredVaultRows = (backupRaids and #backupRaids > 0)
        or (backupMythicPlus and #backupMythicPlus > 0)
        or (backupPvp and #backupPvp > 0)
        or (backupWorld and #backupWorld > 0)
    local hadCompletedVaultRows = GreatVaultActivityHasCompletedRows(activities)
    local previousResetTime = GetCurrentWeeklyResetStartTime()
    local rewardData = self.db.global.pveCache.greatVault.rewards
        and self.db.global.pveCache.greatVault.rewards[charKey]
    local rewardClaimedResetTime = rewardData and tonumber(rewardData.claimedResetTime) or nil
    local rewardClaimedThisReset = rewardClaimedResetTime and previousResetTime and rewardClaimedResetTime >= previousResetTime
    local storedBeforeReset = previousResetTime and (tonumber(activities.lastUpdate) or 0) < previousResetTime
    local incomingCompletedRows = false
    for i = 1, #vaultSlots do
        local slot = vaultSlots[i]
        local progress = slot and tonumber(slot.progress) or 0
        local threshold = slot and tonumber(slot.threshold) or 0
        if threshold > 0 and progress >= threshold then
            incomingCompletedRows = true
            break
        end
    end
    if hadCompletedVaultRows and storedBeforeReset and not rewardClaimedThisReset and not incomingCompletedRows then
        PvECacheUserDebug(
            "scanner: preserve pre-reset completed vault rows key=%s incomingComplete=no",
            tostring(charKey))
        return
    end
    
    -- Clear and re-populate from VaultScanner
    activities.raids = {}
    activities.mythicPlus = {}
    activities.pvp = {}
    activities.world = {}
    
    -- Convert VaultScanner format to PvECacheService format
    for i = 1, #vaultSlots do
        local slot = vaultSlots[i]
        local newILvl = slot.currentILvl or 0
        local newNextILvl = slot.nextILvl or 0
        local newMaxILvl = slot.maxILvl or 0
        
        -- Restore preserved iLvl if new scan returned 0 (server not ready)
        if newILvl == 0 and slot.activityID and preservedILvl[slot.activityID] then
            local saved = preservedILvl[slot.activityID]
            newILvl = saved.rewardItemLevel
            newNextILvl = (newNextILvl > 0) and newNextILvl or saved.nextLevelIlvl
            newMaxILvl = (newMaxILvl > 0) and newMaxILvl or saved.maxIlvl
        end
        
        local activity = {
            type = nil,  -- Will be set based on typeName
            index = slot.index,
            progress = slot.progress,
            threshold = slot.threshold,
            level = slot.level,
            id = slot.activityID,
            rewardItemLevel = newILvl,
            nextLevelIlvl = newNextILvl,
            maxIlvl = newMaxILvl,
        }
        
        -- Map typeName to Enum.WeeklyRewardChestThresholdType
        if slot.typeName == "Raid" then
            activity.type = Enum.WeeklyRewardChestThresholdType.Raid
            table.insert(activities.raids, activity)
        elseif slot.typeName == "M+" then
            activity.type = Enum.WeeklyRewardChestThresholdType.Activities
            table.insert(activities.mythicPlus, activity)
        elseif slot.typeName == "World" then
            activity.type = Enum.WeeklyRewardChestThresholdType.World
            table.insert(activities.world, activity)
        elseif slot.typeName == "PvP" then
            activity.type = Enum.WeeklyRewardChestThresholdType.RankedPvP
            table.insert(activities.pvp, activity)
        end
    end
    
    local insertedCount = #activities.raids + #activities.mythicPlus + #activities.pvp + #activities.world
    if insertedCount == 0 and hadStoredVaultRows then
        activities.raids = backupRaids or {}
        activities.mythicPlus = backupMythicPlus or {}
        activities.pvp = backupPvp or {}
        activities.world = backupWorld or {}
        return
    end
    
    -- Update timestamp
    activities.lastUpdate = time()
    
    -- Save to DB
    self:SavePvECache()
    
    local afterSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    if beforeSig ~= afterSig then
        -- Fire event to refresh UI only when scanner payload changed persisted state.
        self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    end
end

---Handle UPDATE_INSTANCE_INFO event
function WarbandNexus:OnInstanceInfoUpdate()
    self:UpdatePvEData()
end

---Handle CHALLENGE_MODE_COMPLETED event
function WarbandNexus:OnChallengeModeCompleted()
    self:UpdatePvEData()
end

-- ============================================================================
-- PLAYER_LOGOUT: persist PvE cache (no API refresh)
-- ============================================================================
-- Do NOT call UpdatePvEData() here. During logout/teardown, Mythic+ and Weekly
-- Rewards APIs often return empty/zero; a full refresh overwrites pveCache with
-- bogus data for the logging-out character (missing vault, Overall Score 0).

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
    
    pendingUpdate = false
    
    -- Final save (ensures all direct DB writes are persisted)
    WarbandNexus:SavePvECache()
end)

-- ============================================================================
-- LOAD MESSAGE
-- ============================================================================

-- Module loaded (silent)
-- Module loaded - verbose logging hidden (debug mode only)
