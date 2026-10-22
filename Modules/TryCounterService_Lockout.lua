--[[
    Warband Nexus - Try Counter lockout quests (split from TryCounterService.lua, 2026-10-22)
    Daily / weekly rare kill gating (lockout duplicate check, quest fallback, quest-log snapshot)
    and lockout-quest auto-discovery. Loaded after TryCounterService.lua; uses
    ns.TryCounter.Runtime + TC.Fns. lockoutQuestsDB is reassigned by LoadRuntimeSourceTables, so it
    is read as RT.lockoutQuestsDB at the use site.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars

assert(Fns and RT and V and RT.lockoutAttempted, "TryCounterService_Lockout: load TryCounterService.lua first")

-- Owned by TryCounterService.lua (separate chunk); shared through the Runtime table.
local lockoutAttempted = RT.lockoutAttempted

local GetTime = GetTime
local pairs = pairs
local format = string.format
local C_Timer = C_Timer
local C_QuestLog = C_QuestLog

local lockoutQuestSnapshot = {} -- [questID] = true : completed lockout quests at last snapshot (QUEST_LOG_UPDATE diff)
local lockoutPreCompletedAtLogin = {} -- [questID] = true : quest was already complete at last SyncLockoutState (pre-kill skip chat only)
local lockoutQuestFallbackTimers = {} -- [questID] = C_Timer handle : deferred count when ground loot is delayed (phase rares)
local lockoutLootTouchedNpc = {} -- [npcID] = GetTime() : corpse loot opened for lockout rare (quest fallback must not pre-count)
local LOCKOUT_QUEST_LOOT_DEFER_SEC = 60 -- long glide / parachute before quest-only fallback when corpse loot never opens

-- LOCKOUT QUEST CHECK (daily/weekly rare kill gating)

function Fns.IsLockoutDuplicate(npcID)
    if not npcID then return false end

    local questData = RT.lockoutQuestsDB[npcID]
    if not questData then return false end  -- No lockout quest registered for this NPC

    -- Normalize to array
    local questIDs = type(questData) == "table" and questData or { questData }

    -- Check if ANY of the lockout quests are flagged completed
    local flaggedQuestID = nil
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        for i = 1, #questIDs do
            if C_QuestLog.IsQuestFlaggedCompleted(questIDs[i]) then
                flaggedQuestID = questIDs[i]
                break
            end
        end
    end

    if not flaggedQuestID then
        -- No quest flagged → lockout has reset since last attempt
        -- Clear all related quest trackers
        for i = 1, #questIDs do
            lockoutAttempted[questIDs[i]] = nil
        end
        return false  -- Allow counting
    end

    -- Quest IS flagged. Did THIS kill flag it, or was it already flagged?
    if lockoutAttempted[flaggedQuestID] then
        -- We already counted one attempt for this lockout period → skip
        return true
    end

    -- First time seeing this quest flagged → THIS kill triggered it → count it
    lockoutAttempted[flaggedQuestID] = true
    return false  -- Allow counting
end

function Fns.SyncLockoutState()
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end

    -- Phase 1: Clean stale entries (quest has reset since last session)
    for questID, _ in pairs(lockoutAttempted) do
        if not C_QuestLog.IsQuestFlaggedCompleted(questID) then
            lockoutAttempted[questID] = nil
            lockoutPreCompletedAtLogin[questID] = nil
        end
    end

    -- Phase 2: Pre-populate from currently flagged quests.
    -- If a lockout quest is already flagged on login/reload, the player used their
    -- attempt in a prior session. Mark it so IsLockoutDuplicate() correctly skips.
    for _, questData in pairs(RT.lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                if not lockoutAttempted[qid] then
                    lockoutAttempted[qid] = true
                end
                lockoutPreCompletedAtLogin[qid] = true
            end
        end
    end

    Fns.RefreshLockoutQuestSnapshot()
end

function Fns.CancelLockoutQuestFallbackForNpc(npcID)
    if not npcID then return end
    local questData = RT.lockoutQuestsDB[npcID]
    if not questData then return end
    local questIDs = type(questData) == "table" and questData or { questData }
    for i = 1, #questIDs do
        local qid = questIDs[i]
        local handle = lockoutQuestFallbackTimers[qid]
        if handle and handle.Cancel then
            handle:Cancel()
        end
        lockoutQuestFallbackTimers[qid] = nil
    end
end

function Fns.ScheduleLockoutQuestFallback(npcID, questID)
    if not npcID or not questID or lockoutAttempted[questID] then return end
    local existing = lockoutQuestFallbackTimers[questID]
    if existing and existing.Cancel then
        existing:Cancel()
    end
    -- NewTimer: C_Timer.After returns no handle, so `existing:Cancel()` above never ran (2026-10-22).
    lockoutQuestFallbackTimers[questID] = C_Timer.NewTimer(LOCKOUT_QUEST_LOOT_DEFER_SEC, function()
        lockoutQuestFallbackTimers[questID] = nil
        if not Fns.IsAutoTryCounterEnabled() then return end
        if lockoutAttempted[questID] then return end
        if V.pendingLootSessionFinalize then return end
        if Fns.IsLootSessionPendingOrRecent(RT.LOOT_SESSION_RECENT_TTL) then return end
        if Fns.WasLockoutLootTouchedRecently(npcID, 180) then return end
        if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
        local ok, stillComplete = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if not ok or not stillComplete then return end
        Fns.ProcessLockoutQuestTryCount(npcID, questID)
    end)
end

function Fns.ShouldAnnounceLockoutSkip(npcID)
    if not npcID then return false end
    local questData = RT.lockoutQuestsDB[npcID]
    if not questData then return false end
    local questIDs = type(questData) == "table" and questData or { questData }
    for i = 1, #questIDs do
        if lockoutPreCompletedAtLogin[questIDs[i]] then
            return true
        end
    end
    return false
end

function Fns.RefreshLockoutQuestSnapshot()
    wipe(lockoutQuestSnapshot)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
    for _, questData in pairs(RT.lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
            if ok and result then
                lockoutQuestSnapshot[qid] = true
            end
        end
    end
end

--- Weekly/daily rare fallback: when the hidden lockout quest flips, count the attempt even if
--- LOOT_OPENED could not resolve a corpse GUID (phase rares, secret GUIDs, parachute delay).
function Fns.ProcessLockoutQuestTryCount(npcID, questID)
    if not npcID or not questID then return end
    if not RT.tryCounterNpcEligible[npcID] or not RT.npcDropDB[npcID] then return end

    local tryCountSourceKey = "lockout_quest_" .. tostring(questID)
    local now = GetTime()
    if V.lastTryCountSourceKey == tryCountSourceKey and (now - V.lastTryCountSourceTime) < 15 then
        return
    end

    local drops = RT.npcDropDB[npcID]
    local trackable = Fns.FilterDropsByDifficulty(drops, nil)
    if #trackable == 0 then return end

    local dropsToIncrement = {}
    for i = 1, #trackable do
        local d = trackable[i]
        if not Fns.ShouldSkipMissIncrementForDrop(d)
            and (d.repeatable or not Fns.IsCollectibleCollected(d)) then
            dropsToIncrement[#dropsToIncrement + 1] = d
        end
    end
    if #dropsToIncrement == 0 then return end

    if V.pendingLootSessionFinalize then return end
    if Fns.IsLootSessionPendingOrRecent(RT.LOOT_SESSION_RECENT_TTL) then return end
    if Fns.WasLockoutLootTouchedRecently(npcID, 180) then return end

    lockoutAttempted[questID] = true
    V.lastTryCountSourceKey = tryCountSourceKey
    V.lastTryCountSourceTime = now
    Fns.TryCounterLootDebugDropLines(WarbandNexus, "LockoutQuest", dropsToIncrement, 1)
    Fns.ProcessMissedDrops(dropsToIncrement, drops.statisticIds, { attemptTimes = 1 })
end

function Fns.MarkLockoutLootTouched(npcID)
    if not npcID then return end
    lockoutLootTouchedNpc[npcID] = GetTime()
end

function Fns.WasLockoutLootTouchedRecently(npcID, ttlSec)
    if not npcID then return false end
    local t = lockoutLootTouchedNpc[npcID]
    if not t then return false end
    return (GetTime() - t) < (ttlSec or 120)
end

function Fns.TryCancelLockoutFallbackFromSourceGUIDs(sourceGUIDs)
    if not sourceGUIDs then return end
    for i = 1, #sourceGUIDs do
        local nid = Fns.GetNPCIDFromGUID(sourceGUIDs[i])
        if nid and RT.lockoutQuestsDB[nid] then
            Fns.MarkLockoutLootTouched(nid)
            Fns.CancelLockoutQuestFallbackForNpc(nid)
        end
    end
end

function Fns.ProcessKnownLockoutQuestCompletions()
    if not Fns.IsAutoTryCounterEnabled() then return end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end

    for npcID, questData in pairs(RT.lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            if not lockoutQuestSnapshot[qid] then
                local ok, nowComplete = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
                if ok and nowComplete then
                    lockoutQuestSnapshot[qid] = true
                    -- Defer so ground-corpse LOOT_OPENED runs first (same as other weekly rares).
                    -- Phase rares (Sthaarbs/Shartabb) flag the quest on kill but loot lands seconds later.
                    if not lockoutAttempted[qid] then
                        Fns.ScheduleLockoutQuestFallback(npcID, qid)
                    end
                end
            end
        end
    end
end

-- LOCKOUT QUEST AUTO-DISCOVERY
-- When an NPC in our drop DB has no lockout quest, detect the hidden
-- tracking quest that flipped by comparing pre-kill and post-kill quest
-- flags.  Approach: maintain a running snapshot of completed quest IDs
-- in the Midnight range; on QUEST_LOG_UPDATE, diff to find new
-- completions.  If a loot event for an unknown-lockout NPC happened
-- recently, associate the newly-completed quest with that NPC.
-- Persisted to db.global.discoveredLockoutQuests so it survives reload.

local DISCOVERY_QUEST_RANGES = {
    { 89560, 89590 },   -- Zul'Aman rares
    { 90790, 90810 },   -- Sundereth the Caller area + Zul'Aman treasures
    { 91040, 91340 },   -- Various zone rares (Eruundi, Tremora, etc.)
    { 91620, 91850 },   -- Harandar rares + misc
    { 92020, 92200 },   -- Harandar / Eversong rares + world bosses (Thorm'belan 92034, Cragpine 92123)
    { 92350, 92650 },   -- Eversong rares + world bosses (Lu'ashal 92560, Predaxas 92636)
    { 93440, 93980 },   -- Newer rares (Voidstorm, Duskburn, Dame Bloodshed, etc.)
    { 94440, 94480 },   -- Arcantina rares (Orivane, Many-Broken, Abysslick, Nullspiral, Blackcore, Steellock)
    { 95005, 95020 },   -- Isle of Quel'Danas rares (Tarhu, Dripping Shadow)
}

local discoverySnapshot = {}           -- [questID] = true for quest IDs completed at snapshot time
local DISCOVERY_PENDING_TTL = 8        -- seconds to wait for QUEST_LOG_UPDATE after loot

function Fns.GetClaimedQuestIDs()
    local claimed = {}
    for _, questData in pairs(RT.lockoutQuestsDB) do
        local qids = type(questData) == "table" and questData or { questData }
        for i = 1, #qids do claimed[qids[i]] = true end
    end
    return claimed
end

function Fns.TakeDiscoverySnapshot()
    wipe(discoverySnapshot)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
    for ri = 1, #DISCOVERY_QUEST_RANGES do
        local lo, hi = DISCOVERY_QUEST_RANGES[ri][1], DISCOVERY_QUEST_RANGES[ri][2]
        for qid = lo, hi do
            local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
            if ok and result then
                discoverySnapshot[qid] = true
            end
        end
    end
end

---Refresh the discovery baseline while a tracked rare with no known lockout quest is targeted,
---i.e. before it dies. Otherwise the baseline dates from login or the last discovery, and the hidden
---quest of any rare killed in between would become the lone candidate and be persisted as this
---NPC's lockout, after which every kill of it reads as a lockout duplicate and stops counting.
function Fns.MaybeRefreshDiscoverySnapshotForNpc(npcID)
    if not npcID or RT.lockoutQuestsDB[npcID] or V.discoveryPendingNpcID then return end
    local now = GetTime()
    if now - (V.discoverySnapshotTime or 0) < 30 then return end   -- one ~1.6k-quest scan per 30s
    V.discoverySnapshotTime = now
    Fns.TakeDiscoverySnapshot()
end

Fns.TryDiscoverLockoutQuest = function()
    if not V.discoveryPendingNpcID then return end
    if GetTime() - V.discoveryPendingTime > DISCOVERY_PENDING_TTL then
        V.discoveryPendingNpcID = nil
        Fns.TakeDiscoverySnapshot()
        return
    end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        V.discoveryPendingNpcID = nil
        return
    end

    local claimed = Fns.GetClaimedQuestIDs()
    local candidates = {}
    for ri = 1, #DISCOVERY_QUEST_RANGES do
        local lo, hi = DISCOVERY_QUEST_RANGES[ri][1], DISCOVERY_QUEST_RANGES[ri][2]
        for qid = lo, hi do
            if not discoverySnapshot[qid] and not claimed[qid] then
                local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
                if ok and result then
                    candidates[#candidates + 1] = qid
                end
            end
        end
    end

    if #candidates == 1 then
        local questID = candidates[1]
        local npcID = V.discoveryPendingNpcID

        RT.lockoutQuestsDB[npcID] = questID
        lockoutAttempted[questID] = true

        if WarbandNexus.db and WarbandNexus.db.global then
            if not WarbandNexus.db.global.discoveredLockoutQuests then
                WarbandNexus.db.global.discoveredLockoutQuests = {}
            end
            WarbandNexus.db.global.discoveredLockoutQuests[npcID] = questID
        end

        if ns.DebugPrint then
            ns.DebugPrint(format("|cff00ff00[LockoutDiscovery]|r NPC %d → quest %d", npcID, questID))
        end
    elseif #candidates > 1 and ns.DebugPrint then
        ns.DebugPrint(format("|cffff9900[LockoutDiscovery]|r NPC %d: %d candidates, skipping (ambiguous)", V.discoveryPendingNpcID, #candidates))
    end

    V.discoveryPendingNpcID = nil
    Fns.TakeDiscoverySnapshot()
end
