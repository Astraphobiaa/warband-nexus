--[[
    Warband Nexus - Try Counter statistics sync (ops split: TryCounterService_Stats)
    GetStatistic seeding, ENCOUNTER_END miss path, runtime NPC reseed.
    Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local E = ns.Constants and ns.Constants.EVENTS
local Fns = TC.Fns
local RT = TC.Runtime

assert(Fns and RT, 'TryCounterService_Stats: load TryCounterService.lua first')

local issecretvalue = issecretvalue
local IsInInstance = IsInInstance
local InCombatLockdown = InCombatLockdown
local GetStatistic = GetStatistic
local GetTime = GetTime
local debugprofilestop = debugprofilestop
local C_Timer = C_Timer
local wipe = wipe
local next = next
local pairs = pairs
local tonumber = tonumber
local tostring = tostring

function Fns.SumStatisticTotalsFromIds(statIds)
    if not statIds or #statIds == 0 then return 0, false end
    local GetStat = GetStatistic
    if not GetStat then return 0, false end
    local total = 0
    local hadReadable = false
    for i = 1, #statIds do
        local sid = statIds[i]
        local val = GetStat(sid)
        local num
        if val and not (issecretvalue and issecretvalue(val)) then
            local s = string.gsub(tostring(val), "[^%d]", "")
            if s ~= "" then
                hadReadable = true
                num = tonumber(s)
            end
        end
        if num and num > 0 then
            total = total + num
        end
    end
    return total, hadReadable
end

function Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, thisCharTotal, hadReadable)
    if not charSnapshot or not tryKey or not hadReadable then return end
    charSnapshot[tryKey] = thisCharTotal
end

function Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
    if not snapshots or not tryKey then return 0 end
    local globalTotal = 0
    for _, snap in pairs(snapshots) do
        local charVal = snap[tryKey]
        if charVal and charVal > 0 then
            globalTotal = globalTotal + charVal
        end
    end
    return globalTotal
end

function Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable)
    if not tryKey or not tcType or not Fns.EnsureDB() then return false end
    if not hadReadable then return false end
    local WN = WarbandNexus
    local currentCount = WN:GetTryCount(tcType, tryKey) or 0
    local syncDown = WN.db.profile.notifications
        and WN.db.profile.notifications.syncTryCountDownToStatistics == true
    local newCount = currentCount
    if globalTotal > currentCount then
        newCount = globalTotal
    elseif syncDown and globalTotal < currentCount then
        newCount = globalTotal
    end
    if newCount == currentCount then return false end
    WN:SetTryCount(tcType, tryKey, newCount)
    return true
end

function Fns.InvalidateMergedStatisticSeedIndex()
    RT.statState.indexDirty = true
end

function Fns.EnsureMergedStatisticSeedIndex()
    if not RT.statState.indexDirty and #RT.mergedStatSeedGroupList > 0 then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        RT.statState.indexDirty = true
        return
    end
    Fns.RebuildMergedStatisticSeedIndex()
end

function Fns.RebuildMergedStatisticSeedIndex()
    local P = ns.Profiler
    if P and P.enabled and P.StartSlice then P:StartSlice(P.CAT.SVC, "TC_RebuildMergedStatIndex") end
    wipe(RT.mergedStatSeedByTypeKey)
    wipe(RT.mergedStatSeedGroupList)
    wipe(RT.statSeedTryKeyPending)
    if not RT.npcDropDB then
        RT.statState.indexDirty = false
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_RebuildMergedStatIndex") end
        return
    end
    for _, npcData in pairs(RT.npcDropDB) do
        local npcStatIds = npcData.statisticIds
        for idx = 1, #npcData do
            local drop = npcData[idx]
            if type(drop) == "table" and drop.type and drop.itemID and not drop.guaranteed then
                local sids = Fns.ResolveReseedStatIdsForDrop(drop, npcStatIds)
                if sids and #sids > 0 then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tcType and tryKey then
                        local mk = tcType .. "\0" .. tostring(tryKey)
                        local bucket = RT.mergedStatSeedByTypeKey[mk]
                        if not bucket then
                            bucket = {
                                tcType = tcType,
                                tryKey = tryKey,
                                idSet = {},
                                drops = {},
                            }
                            RT.mergedStatSeedByTypeKey[mk] = bucket
                            RT.mergedStatSeedGroupList[#RT.mergedStatSeedGroupList + 1] = bucket
                        end
                        for j = 1, #sids do
                            bucket.idSet[sids[j]] = true
                        end
                        bucket.drops[#bucket.drops + 1] = drop
                    else
                        RT.statSeedTryKeyPending[#RT.statSeedTryKeyPending + 1] = {
                            drop = drop,
                            npcStatIds = npcStatIds,
                        }
                    end
                end
            end
        end
    end
    for b = 1, #RT.mergedStatSeedGroupList do
        local bucket = RT.mergedStatSeedGroupList[b]
        local arr = {}
        for sid in pairs(bucket.idSet) do
            arr[#arr + 1] = sid
        end
        table.sort(arr)
        bucket.statIds = arr
        bucket.idSet = nil
    end
    RT.statState.indexDirty = false
    if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_RebuildMergedStatIndex") end
end

function Fns.ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
    if tcType and tryKey then
        local mk = tcType .. "\0" .. tostring(tryKey)
        local bucket = RT.mergedStatSeedByTypeKey[mk]
        if bucket and bucket.statIds and #bucket.statIds > 0 then
            return bucket.statIds
        end
    end
    if resolvedDropStatIds and #resolvedDropStatIds > 0 then
        return resolvedDropStatIds
    end
    return nil
end

function Fns.PruneStatisticSnapshotsOrphanKeys()
    local P = ns.Profiler
    if P and P.enabled and P.StartSlice then P:StartSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
    if not Fns.EnsureDB() then
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
        return
    end
    local db = WarbandNexus.db.global
    local snaps = db.statisticSnapshots
    local chars = db.characters
    if not snaps or not chars or type(snaps) ~= "table" or type(chars) ~= "table" then
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
        return
    end
    local nChar = 0
    for _ in pairs(chars) do
        nChar = nChar + 1
    end
    if nChar == 0 then
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
        return
    end

    local CS = ns.CharacterService
    local removed = 0
    for ck in pairs(snaps) do
        local owned = false
        if CS and CS.CharacterOwnsSubsidiaryKey then
            owned = CS:CharacterOwnsSubsidiaryKey(WarbandNexus, ck)
        else
            owned = chars[ck] ~= nil
        end
        if not owned then
            snaps[ck] = nil
            if type(db.tryCounterStatSeedAt) == "table" then
                db.tryCounterStatSeedAt[ck] = nil
            end
            removed = removed + 1
        end
    end
    if removed > 0 then
        WarbandNexus:Debug("TryCounter: Pruned %d orphan statisticSnapshots (no roster match)", removed)
    end
    if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
end

function Fns.ReseedStatisticsForDrops(drops, resolvedDropStatIds)
    local P = ns.Profiler
    if P and P.enabled and P.StartSlice then P:StartSlice(P.CAT.SVC, "TC_ReseedStatisticsForDrops") end
    local function finish()
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_ReseedStatisticsForDrops") end
    end
    if not drops or #drops == 0 then finish() return end
    if not Fns.EnsureDB() then finish() return end
    if not GetStatistic then finish() return end

    Fns.EnsureMergedStatisticSeedIndex()

    local charKey = Fns.StatisticSnapshotStorageKey()
    if not charKey then finish() return end

    local snapshots = WarbandNexus.db.global.statisticSnapshots
    if not snapshots then
        WarbandNexus.db.global.statisticSnapshots = {}
        snapshots = WarbandNexus.db.global.statisticSnapshots
    end
    if not snapshots[charKey] then
        snapshots[charKey] = {}
    end
    local charSnapshot = snapshots[charKey]

    local function ProcessSeedDrop(drop, statListOverride)
        if drop and not drop.guaranteed then
            local skipStatSeed = (drop.type == "mount" or drop.type == "pet" or drop.type == "toy")
                and Fns.IsCollectibleCollected(drop)
            if not skipStatSeed then
                local statList = statListOverride or Fns.ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
                if statList and #statList > 0 then
                    local thisCharTotal, hadReadable = Fns.SumStatisticTotalsFromIds(statList)
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey and tcType then
                        Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, thisCharTotal, hadReadable)
                        local globalTotal = Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
                        Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable)
                        local newCount = WarbandNexus:GetTryCount(tcType, tryKey) or 0

                        if drop.type == "item" and drop.questStarters then
                            for i = 1, #drop.questStarters do
                                local qs = drop.questStarters[i]
                                if qs.type == "mount" and qs.itemID and not Fns.IsCollectibleCollected(qs) then
                                    local mountKey1 = Fns.ResolveCollectibleID(qs)
                                    local mountKey2 = qs.itemID
                                    local mk = mountKey1 or mountKey2
                                    WarbandNexus:SetTryCount("mount", mk, math.max(newCount, WarbandNexus:GetTryCount("mount", mk) or 0))
                                    if mountKey1 and mountKey1 ~= mountKey2 then
                                        WarbandNexus:SetTryCount("mount", mountKey2, math.max(newCount, WarbandNexus:GetTryCount("mount", mountKey2) or 0))
                                    end
                                    Fns.RegisterQuestStarterMountKey(mk, drop.itemID)
                                    if mountKey1 and mountKey1 ~= mountKey2 then
                                        Fns.RegisterQuestStarterMountKey(mountKey2, drop.itemID)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if drop and drop.questStarters then
            for i = 1, #drop.questStarters do
                local qs = drop.questStarters[i]
                ProcessSeedDrop(qs, nil)
            end
        end
    end

    for i = 1, #drops do
        ProcessSeedDrop(drops[i], nil)
    end

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_reseeded" })
    end
    finish()
end

function Fns.DropsHaveStatBackedReseed(drops, npcStatIds)
    for i = 1, #drops do
        local sids = Fns.ResolveReseedStatIdsForDrop(drops[i], npcStatIds)
        if sids and #sids > 0 then return true end
    end
    return false
end

--- Instance type for try-counter gating (party / raid / scenario megadungeons). Self-test: slotInstance.instanceType.
function Fns.GetTryCounterInstanceType()
    if RT.tryCounterSelfTest.slotInstance and RT.tryCounterSelfTest.slotInstance.instanceType then
        return true, RT.tryCounterSelfTest.slotInstance.instanceType
    end
    if not IsInInstance then return false end
    local inInst, typ = IsInInstance()
    if issecretvalue and inInst and issecretvalue(inInst) then return false end
    if not inInst then return false end
    if issecretvalue and typ and issecretvalue(typ) then return false end
    return true, typ
end

--- True when inside party, raid, or Mythic megadungeon scenario (Operation: Mechagon, Dawn of the Infinite).
function Fns.IsRaidOrDungeonInstance()
    local inInst, typ = Fns.GetTryCounterInstanceType()
    if not inInst then return false end
    return typ == "party" or typ == "raid" or typ == "scenario"
end

--- Raid/dungeon miss try count: authoritative Statistics only (no loot +1).
function Fns.ShouldUseStatisticsOnlyMiss(drops, npcStatIds)
    if not Fns.IsRaidOrDungeonInstance() then return false end
    return Fns.DropsHaveStatBackedReseed(drops, npcStatIds)
end

--- Reseed try counts from Statistics and announce increments (no manual +1 fallback).
function Fns.RunStatisticsOnlyMissReseed(drops, statIds, options)
    if not drops or #drops == 0 then return end
    if not Fns.EnsureDB() then return end
    local WN = WarbandNexus
    local announceTry = Fns.IsAutoTryCounterEnabled()
    local immediateAnnounce = options and options.immediateAnnounce
    local incrementAnnounce = {}
    for i = 1, #drops do
        local drop = drops[i]
        local sids = Fns.ResolveReseedStatIdsForDrop(drop, statIds)
        if sids and #sids > 0 then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            local prevCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
            Fns.ReseedStatisticsForDrops({ drop }, sids)
            local newCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
            if tryKey and newCount > prevCount then
                Fns.MarkDropReseeded(tcType, tryKey)
                if announceTry then
                    local mergeKey = tcType .. "\0" .. tostring(tryKey)
                    incrementAnnounce[mergeKey] = { drop = drop, finalCount = newCount }
                end
            end
        end
    end
    if announceTry and next(incrementAnnounce) then
        Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce, immediateAnnounce)
    end
    if options and options.sync then
        Fns.SchedulePlansTryCountUIUpdate()
    end
end

-- STATISTICS SEEDING (WoW Achievement Statistics API)

local SEED_BUDGET_MS = 3  -- max milliseconds per batch frame

function Fns.ScheduleDeferredRarityMountMaxSync(delaySec)
    local syncSerial = RT.statState.perCharStatSyncSerial
    delaySec = tonumber(delaySec) or 2
    C_Timer.After(delaySec, function()
        if syncSerial ~= RT.statState.perCharStatSyncSerial then return end
        if not (Fns.IsTryCounterReady and Fns.IsTryCounterReady()) or not Fns.EnsureDB() then return end
        if WarbandNexus.SyncRarityMountAttemptsMax then
            WarbandNexus:SyncRarityMountAttemptsMax()
        end
    end)
end

function Fns.SeedFromStatistics(opts)
    opts = opts or {}
    if not Fns.EnsureDB() then return end
    if not GetStatistic then return end

    if opts.pruneOrphans then
        Fns.PruneStatisticSnapshotsOrphanKeys()
    end
    Fns.EnsureMergedStatisticSeedIndex()

    local charKey = Fns.StatisticSnapshotStorageKey()
    if not charKey then return end

    local P = ns.Profiler
    local seedLabel = P and P.SliceLabel and P:SliceLabel(P.CAT.SVC, "TC_SeedFromStatistics")
    if P and seedLabel then P:StartAsync(seedLabel) end
    local LT = ns.LoadingTracker
    if LT then LT:Register("trycounts", (ns.L and ns.L["TRYCOUNTER_TRY_COUNTS"]) or "Try Counts") end
    local snapshots = WarbandNexus.db.global.statisticSnapshots
    if not snapshots then
        WarbandNexus.db.global.statisticSnapshots = {}
        snapshots = WarbandNexus.db.global.statisticSnapshots
    end
    if not snapshots[charKey] then
        snapshots[charKey] = {}
    end
    local charSnapshot = snapshots[charKey]

    -- Merged buckets: one seed per (type, tryKey) with union of all difficulty/NPC statistic columns.
    -- Plus pending rows where tryKey was nil (journal cold) — same per-drop stat list as before.
    wipe(RT.statSeedWorkQueue)
    local seedQueue = RT.statSeedWorkQueue
    local seedQueueLen = 0
    for i = 1, #RT.mergedStatSeedGroupList do
        seedQueueLen = seedQueueLen + 1
        seedQueue[seedQueueLen] = { bucket = RT.mergedStatSeedGroupList[i] }
    end
    for p = 1, #RT.statSeedTryKeyPending do
        local pend = RT.statSeedTryKeyPending[p]
        local sids = Fns.ResolveReseedStatIdsForDrop(pend.drop, pend.npcStatIds)
        if sids and #sids > 0 then
            seedQueueLen = seedQueueLen + 1
            seedQueue[seedQueueLen] = {
                drop = pend.drop,
                statIds = sids,
                npcStatIds = pend.npcStatIds,
            }
        end
    end
    for i = seedQueueLen + 1, #seedQueue do
        seedQueue[i] = nil
    end

    local queueIdx = 1
    local seeded = 0
    local anyReadable = false
    local unresolvedDrops = {}

    local function ProcessBatch()
        if not Fns.EnsureDB() then return end
        local batchStart = debugprofilestop()

        while queueIdx <= #seedQueue do
            local entry = seedQueue[queueIdx]

            local function ProcessBatchDrop(drop, thisCharTotal, hadReadable, npcStatIdsForUnresolved)
                if not drop.guaranteed then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey then
                        Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, thisCharTotal, hadReadable)
                        local globalTotal = Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
                        if Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable) then
                            if drop.type == "item" and drop.questStarters then
                                for j = 1, #drop.questStarters do
                                    local qs = drop.questStarters[j]
                                    if qs and qs.type == "mount" and qs.itemID then
                                        local k1 = Fns.ResolveCollectibleID(qs)
                                        local k2 = qs.itemID
                                        Fns.RegisterQuestStarterMountKey(k1 or k2, drop.itemID)
                                        if k1 and k1 ~= k2 then Fns.RegisterQuestStarterMountKey(k2, drop.itemID) end
                                    end
                                end
                            end
                            seeded = seeded + 1
                        end
                    else
                        unresolvedDrops[#unresolvedDrops + 1] = {
                            drop = drop,
                            npcStatIds = npcStatIdsForUnresolved,
                        }
                    end
                end
                if drop and drop.questStarters then
                    for j = 1, #drop.questStarters do
                        local qs = drop.questStarters[j]
                        ProcessBatchDrop(qs, thisCharTotal, hadReadable, npcStatIdsForUnresolved)
                    end
                end
            end

            if entry.bucket then
                local b = entry.bucket
                local thisCharTotal, hadReadable = Fns.SumStatisticTotalsFromIds(b.statIds)
                if hadReadable then anyReadable = true end
                for di = 1, #b.drops do
                    ProcessBatchDrop(b.drops[di], thisCharTotal, hadReadable, nil)
                end
            else
                local thisCharTotal, hadReadable = Fns.SumStatisticTotalsFromIds(entry.statIds)
                if hadReadable then anyReadable = true end
                ProcessBatchDrop(entry.drop, thisCharTotal, hadReadable, entry.npcStatIds)
            end

            queueIdx = queueIdx + 1

            if debugprofilestop() - batchStart > SEED_BUDGET_MS then
                C_Timer.After(0, ProcessBatch)
                return
            end
        end

        if P and seedLabel then P:StopAsync(seedLabel) end
        if LT then LT:Complete("trycounts") end
        -- Stamp the successful read so DF.IsTryCounterStatisticsWarm can expire it (self-healing seed).
        -- Only when at least one statistic was actually readable: GetStatistic can return secret or
        -- "--" values, and stamping a failed pass would lock the character out of retries for a day.
        -- seeded == 0 is NOT failure (a repeat pass that changed nothing is a healthy read).
        local dbG = anyReadable and WarbandNexus.db and WarbandNexus.db.global
        if dbG then
            dbG.tryCounterStatSeedAt = dbG.tryCounterStatSeedAt or {}
            dbG.tryCounterStatSeedAt[charKey] = (time and time()) or 0
        end
        if seeded > 0 then
            WarbandNexus:Debug("TryCounter: Seeded %d entries from WoW Statistics (char: %s)", seeded, charKey)
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
            end
        end

        -- Rarity may load after this batch; two passes catch late `groups.mounts` availability (max never lowers WN).
        Fns.ScheduleDeferredRarityMountMaxSync(2)
        Fns.ScheduleDeferredRarityMountMaxSync(10)

        if #unresolvedDrops > 0 then
            WarbandNexus:Debug("TryCounter: %d drops unresolved, retrying in 10s...", #unresolvedDrops)
            C_Timer.After(10, function()
                if not Fns.EnsureDB() then return end
                Fns.EnsureMergedStatisticSeedIndex()
                local retrySeeded = 0
                local stillUnresolved = {}
                for i = 1, #unresolvedDrops do
                    local uEntry = unresolvedDrops[i]
                    local drop = uEntry.drop
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey then
                        local statList = Fns.ResolveMergedStatisticIdsForDrop(drop, Fns.ResolveReseedStatIdsForDrop(drop, uEntry.npcStatIds))
                        local t, hadReadable = Fns.SumStatisticTotalsFromIds(statList)
                        Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, t, hadReadable)
                        local globalTotal = Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
                        if Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable) then
                            retrySeeded = retrySeeded + 1
                        end
                    else
                        stillUnresolved[#stillUnresolved + 1] = uEntry
                    end
                end
                if retrySeeded > 0 then
                    WarbandNexus:Debug("TryCounter: Retry resolved %d / %d entries", retrySeeded, #unresolvedDrops)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
                    end
                end
                Fns.ScheduleDeferredRarityMountMaxSync(2)

                if #stillUnresolved > 0 then
                    WarbandNexus:Debug("TryCounter: %d still unresolved, final retry in 30s...", #stillUnresolved)
                    C_Timer.After(30, function()
                        if not Fns.EnsureDB() then return end
                        Fns.EnsureMergedStatisticSeedIndex()
                        local finalSeeded = 0
                        local snaps = WarbandNexus.db.global.statisticSnapshots
                        for j = 1, #stillUnresolved do
                            local fEntry = stillUnresolved[j]
                            local drop = fEntry.drop
                            local tcType, finalKey = Fns.GetTryCountTypeAndKey(drop)
                            if finalKey and snaps then
                                local statList = Fns.ResolveMergedStatisticIdsForDrop(drop, Fns.ResolveReseedStatIdsForDrop(drop, fEntry.npcStatIds))
                                local t, hadReadable = Fns.SumStatisticTotalsFromIds(statList)
                                if snaps[charKey] then
                                    Fns.WriteStatisticSnapshotIfReadable(snaps[charKey], finalKey, t, hadReadable)
                                end
                                local total = Fns.SumStatisticSnapshotsGlobal(snaps, finalKey)
                                if Fns.ApplyTryCountFromStatisticTotals(tcType, finalKey, total, hadReadable) then
                                    finalSeeded = finalSeeded + 1
                                end
                            end
                        end
                        if finalSeeded > 0 then
                            WarbandNexus:Debug("TryCounter: Final retry resolved %d / %d entries", finalSeeded, #stillUnresolved)
                            if WarbandNexus.SendMessage then
                                WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
                            end
                        end
                        Fns.ScheduleDeferredRarityMountMaxSync(2)
                    end)
                end
            end)
        end
    end

    ProcessBatch()
end

function Fns.PurgeStaleRuntimeStatReseedNpcs()
    local now = GetTime()
    for npcID, entry in pairs(RT.pendingRuntimeStatNpcIds) do
        local markedAt = type(entry) == "table" and entry.at or entry
        if not markedAt or (now - markedAt) > RT.RUNTIME_STAT_NPC_TTL then
            RT.pendingRuntimeStatNpcIds[npcID] = nil
        end
    end
end

function Fns.MarkNpcForRuntimeStatReseed(npcID, difficultyID)
    npcID = tonumber(npcID)
    if not npcID then return end
    local safeDiff = difficultyID
    if issecretvalue and safeDiff and issecretvalue(safeDiff) then safeDiff = nil end
    RT.pendingRuntimeStatNpcIds[npcID] = {
        at = GetTime(),
        difficultyID = safeDiff,
    }
end

local ENCOUNTER_LOOTLESS_MISS_DELAYS = { 4, 10 }

--- Invalidate pending ENCOUNTER_END lootless miss timers (loot path already counted this boss).
function Fns.CancelEncounterLootlessMissFallback()
    RT.statState.encounterLootlessMissSerial = (RT.statState.encounterLootlessMissSerial or 0) + 1
end

--- Bosses without statisticIds (e.g. HK-8 Mythic mount): personal loot often skips LOOT_OPENED and
--- CHAT_MSG_LOOT lines are gear, not the mount item — schedule a lootless miss if nothing else counted.
function Fns.ScheduleEncounterLootlessMissFallback(npcID, difficultyID, encounterKey)
    npcID = tonumber(npcID)
    if not npcID or not encounterKey or not Fns.IsRaidOrDungeonInstance() then return end
    local drops = RT.npcDropDB and RT.npcDropDB[npcID]
    if not drops or Fns.NpcEntryHasStatisticIds(drops) then return end

    local safeDiff = difficultyID
    if issecretvalue and safeDiff and issecretvalue(safeDiff) then safeDiff = nil end

    local serial = (RT.statState.encounterLootlessMissSerial or 0) + 1
    RT.statState.encounterLootlessMissSerial = serial

    local function tryOnce()
        if serial ~= RT.statState.encounterLootlessMissSerial then return true end
        if not Fns.IsAutoTryCounterEnabled() or not Fns.EnsureDB() then return true end
        local V = RT.vars
        if V and encounterKey and V.lastTryCountSourceKey == encounterKey
            and (GetTime() - (V.lastTryCountSourceTime or 0)) < 120 then
            return true
        end
        if Fns.IsLootSessionPendingOrRecent and Fns.IsLootSessionPendingOrRecent(12) then
            return false
        end
        local _, killData = Fns.GetFreshEncounterKillForNpc(npcID)
        if not killData then return true end
        local inInst = IsInInstance()
        if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
        local encDiff = Fns.ResolveEncounterDifficultyForLootGating(inInst, killData.difficultyID or safeDiff, nil)
        local trackable = Fns.FilterDropsByDifficulty(drops, encDiff)
        if #trackable == 0 then return true end
        local missed = {}
        for i = 1, #trackable do
            local drop = trackable[i]
            if drop and not Fns.ShouldSkipMissIncrementForDrop(drop)
                and (drop.repeatable or not Fns.IsCollectibleCollected(drop)) then
                missed[#missed + 1] = drop
            end
        end
        if #missed == 0 then return true end
        if V then
            V.lastTryCountSourceKey = encounterKey
            V.lastTryCountSourceTime = GetTime()
        end
        Fns.TryCounterLootDebugDropLines(WarbandNexus, "EncounterLootless", missed, 1)
        Fns.ProcessMissedDrops(missed, drops.statisticIds, { attemptTimes = 1 })
        if Fns.ClearEncounterRecentKillsForNpcId then
            Fns.ClearEncounterRecentKillsForNpcId(npcID)
        end
        return true
    end

    for i = 1, #ENCOUNTER_LOOTLESS_MISS_DELAYS do
        local delay = ENCOUNTER_LOOTLESS_MISS_DELAYS[i]
        C_Timer.After(delay, function()
            if serial ~= RT.statState.encounterLootlessMissSerial then return end
            if tryOnce() ~= false then return end
            -- Loot window still open on first pass — second delay retries.
        end)
    end
end

--- Staggered stat reads after ENCOUNTER_END (boss death); does not wait for loot.
function Fns.ScheduleEncounterStatisticsRefresh()
    if not next(RT.pendingRuntimeStatNpcIds) then return end
    RT.statState.encounterStatRetrySerial = RT.statState.encounterStatRetrySerial + 1
    local token = RT.statState.encounterStatRetrySerial
    for i = 1, #RT.ENCOUNTER_STAT_RETRY_DELAYS do
        local delay = RT.ENCOUNTER_STAT_RETRY_DELAYS[i]
        C_Timer.After(delay, function()
            if token ~= RT.statState.encounterStatRetrySerial then return end
            if not (Fns.IsTryCounterReady and Fns.IsTryCounterReady()) or not Fns.EnsureDB() then return end
            if not next(RT.pendingRuntimeStatNpcIds) then return end
            Fns.ReseedStatisticsForPendingRuntimeNpcs({ immediateAnnounce = true })
        end)
    end
end

--- Reseed Statistics for recently killed NPCs only (not the full CollectibleSourceDB scan).
---@param options table|nil { immediateAnnounce = boolean }
---@return boolean didWork
function Fns.ReseedStatisticsForPendingRuntimeNpcs(options)
    Fns.PurgeStaleRuntimeStatReseedNpcs()
    if not next(RT.pendingRuntimeStatNpcIds) then return false end
    if not Fns.IsRaidOrDungeonInstance() then return false end
    if not GetStatistic or not Fns.EnsureDB() then return false end

    local immediateAnnounce = options and options.immediateAnnounce

    Fns.EnsureMergedStatisticSeedIndex()

    local WN = WarbandNexus
    wipe(RT.runtimeStatReseedDropScratch)
    local drops = RT.runtimeStatReseedDropScratch
    local dropCount = 0
    local prevByNpc = {}

    -- ENCOUNTER_END may hand us a secret difficultyID with a cold ENCOUNTER_START cache, leaving
    -- entry.difficultyID nil. FilterDropsByDifficulty fails closed on nil, so a Mythic-gated drop
    -- (Sylvanas) would silently count nothing. Resolve live, same as ScheduleEncounterLootlessMissFallback.
    local liveDiffResolved, liveDiff = false, nil
    local function EncounterDifficultyForEntry(entry)
        local d = type(entry) == "table" and entry.difficultyID or nil
        if d then return d end
        if not liveDiffResolved then
            liveDiffResolved = true
            local inInst = IsInInstance()
            if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
            liveDiff = Fns.ResolveEncounterDifficultyForLootGating(inInst, nil, nil)
        end
        return liveDiff
    end

    for npcID, entry in pairs(RT.pendingRuntimeStatNpcIds) do
        local npcData = RT.npcDropDB and RT.npcDropDB[npcID]
        if npcData and Fns.NpcEntryHasStatisticIds(npcData) then
            local encDiff = EncounterDifficultyForEntry(entry)
            local trackable = Fns.FilterDropsByDifficulty(npcData, encDiff)
            local maxPrev = 0
            for idx = 1, #trackable do
                local drop = trackable[idx]
                if type(drop) == "table" and drop.type and drop.itemID and not drop.guaranteed then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey then
                        local c = WN:GetTryCount(tcType, tryKey) or 0
                        if c > maxPrev then maxPrev = c end
                    end
                    dropCount = dropCount + 1
                    drops[dropCount] = drop
                end
            end
            prevByNpc[npcID] = maxPrev
        else
            RT.pendingRuntimeStatNpcIds[npcID] = nil
        end
    end
    for i = dropCount + 1, #drops do
        drops[i] = nil
    end
    if dropCount == 0 then
        return false
    end

    local prevByDropKey = {}
    for i = 1, dropCount do
        local drop = drops[i]
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if tryKey then
            prevByDropKey[tcType .. "\0" .. tostring(tryKey)] = WN:GetTryCount(tcType, tryKey) or 0
        end
    end

    Fns.ReseedStatisticsForDrops(drops, nil)

    local incrementAnnounce = {}
    local announceTry = Fns.IsAutoTryCounterEnabled()
    for i = 1, dropCount do
        local drop = drops[i]
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if tryKey then
            local mk = tcType .. "\0" .. tostring(tryKey)
            local prevCount = prevByDropKey[mk] or 0
            local newCount = WN:GetTryCount(tcType, tryKey) or 0
            if newCount > prevCount then
                Fns.MarkDropReseeded(tcType, tryKey)
                if announceTry then
                    incrementAnnounce[mk] = { drop = drop, finalCount = newCount }
                end
            end
        end
    end
    if announceTry and next(incrementAnnounce) then
        Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce, immediateAnnounce)
    end

    for npcID, prevMax in pairs(prevByNpc) do
        local npcData = RT.npcDropDB and RT.npcDropDB[npcID]
        -- Same resolution as the collect loop above, or the two trackable lists diverge and the
        -- pending-NPC clear below stops matching what was actually counted.
        local encDiff = EncounterDifficultyForEntry(RT.pendingRuntimeStatNpcIds[npcID])
        local trackable = npcData and Fns.FilterDropsByDifficulty(npcData, encDiff) or {}
        local maxNew = 0
        for idx = 1, #trackable do
            local drop = trackable[idx]
            if type(drop) == "table" and drop.type and drop.itemID and not drop.guaranteed then
                local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                if tryKey then
                    local c = WN:GetTryCount(tcType, tryKey) or 0
                    if c > maxNew then maxNew = c end
                end
            end
        end
        if maxNew > prevMax then
            RT.pendingRuntimeStatNpcIds[npcID] = nil
        end
    end

    Fns.ScheduleDeferredRarityMountMaxSync(2)
    return true
end

function Fns.RequestTryCounterStatisticsIncrementalRefresh()
    if not GetStatistic then return end
    Fns.PurgeStaleRuntimeStatReseedNpcs()
    if not next(RT.pendingRuntimeStatNpcIds) then return end
    RT.statState.statIncrementalDebounceSerial = RT.statState.statIncrementalDebounceSerial + 1
    local token = RT.statState.statIncrementalDebounceSerial
    C_Timer.After(RT.STAT_INCREMENTAL_DEBOUNCE_SEC, function()
        if token ~= RT.statState.statIncrementalDebounceSerial then return end
        if not (Fns.IsTryCounterReady and Fns.IsTryCounterReady()) or not Fns.EnsureDB() then return end
        local now = GetTime()
        if (now - RT.statState.lastStatIncrementalReseedAt) < RT.STAT_INCREMENTAL_MIN_INTERVAL_SEC then return end
        RT.statState.lastStatIncrementalReseedAt = now
        Fns.ReseedStatisticsForPendingRuntimeNpcs()
        Fns.ScheduleDeferredRarityMountMaxSync(2)
    end)
end

--- Legacy name: CRITERIA_UPDATE / regen retry for pending encounter stat NPCs.
function Fns.RequestTryCounterStatisticsRuntimeRefresh()
    Fns.RequestTryCounterStatisticsIncrementalRefresh()
end

local function HasPersistedTryCountEntries()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return false end
    local tc = WarbandNexus.db.global.tryCounts
    if type(tc) ~= "table" then return false end
    for _, bucket in pairs({ "mount", "pet", "item", "toy" }) do
        local tbl = tc[bucket]
        if type(tbl) == "table" and next(tbl) ~= nil then
            return true
        end
    end
    return false
end

function Fns.SchedulePerCharacterStatisticsAndRaritySync()
    local dbGlobal = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local charKey = Fns.StatisticSnapshotStorageKey()
    local DF = ns.DataFreshness
    if DF and DF.IsTryCounterStatisticsWarm and dbGlobal and charKey
        and DF.IsTryCounterStatisticsWarm(dbGlobal, charKey) then
        return
    end
    RT.statState.perCharStatSyncSerial = RT.statState.perCharStatSyncSerial + 1
    local serial = RT.statState.perCharStatSyncSerial
    local function runSeed(pruneOrphans)
        if serial ~= RT.statState.perCharStatSyncSerial then return end
        if not (Fns.IsTryCounterReady and Fns.IsTryCounterReady()) or not Fns.EnsureDB() then return end
        Fns.InvalidateMergedStatisticSeedIndex()
        Fns.SeedFromStatistics({ pruneOrphans = pruneOrphans == true })
    end
    local skipQuick = ns._wnPlayerReloading == true and HasPersistedTryCountEntries()
    if not skipQuick then
        C_Timer.After(RT.PER_CHAR_STAT_SYNC_QUICK_SEC, function() runSeed(false) end)
    end
    C_Timer.After(RT.PER_CHAR_STAT_SYNC_FULL_SEC, function() runSeed(true) end)
    C_Timer.After(RT.PER_CHAR_STAT_RARITY_SEC, function()
        if serial ~= RT.statState.perCharStatSyncSerial then return end
        if WarbandNexus.SyncRarityMountAttemptsMax then
            WarbandNexus:SyncRarityMountAttemptsMax()
        end
    end)
end

--- Force Statistics re-read for the logged-in character (slash / alt refresh).
function WarbandNexus:ForceTryCounterStatisticsSync()
    if not (Fns.IsTryCounterReady and Fns.IsTryCounterReady()) then
        if self.Print then
            self:Print("|cffff6600[WN]|r Try counter not ready yet.")
        end
        return
    end
    if not Fns.EnsureDB() then return end
    Fns.InvalidateMergedStatisticSeedIndex()
    Fns.SeedFromStatistics({ pruneOrphans = true })
    Fns.ScheduleDeferredRarityMountMaxSync(2)
    if self.Print then
        self:Print("|cff9370DB[WN]|r Statistics sync started for this character.")
    end
end
