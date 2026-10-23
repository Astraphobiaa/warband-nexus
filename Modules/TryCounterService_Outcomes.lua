--[[
    Warband Nexus - Try Counter loot outcomes (split from TryCounterService.lua, 2026-10-22)
    Early-miss announce, try-count baselines, deferred loot session stage / finalize and the
    per-route outcome appliers (NPC / fishing / container / slot boss).
    Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars

assert(Fns and RT and V and RT.pendingPreResetCounts and RT.mergedLootTryCountedAt and RT.lootReady,
    "TryCounterService_Outcomes: load TryCounterService.lua first")

-- Owned by TryCounterService.lua (separate chunk); shared through the Runtime table.
local pendingPreResetCounts = RT.pendingPreResetCounts
local mergedLootTryCountedAt = RT.mergedLootTryCountedAt
local lootReady = RT.lootReady

local MERGED_LOOT_TRY_DEDUP_TTL = TC.MERGED_LOOT_TRY_DEDUP_TTL or 600

local GetLootSlotLink = GetLootSlotLink
local GetTime = GetTime
local C_Timer = C_Timer
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

local lastLockoutSkipChatKey = nil
local lastLockoutSkipChatTime = 0

local function SendTryCounterCollectibleObtained(self, payload, sourceItemID)
    if not self or not self.SendMessage or not payload then return end
    if not payload.obtainedBy then
        local name = UnitName("player")
        if not (issecretvalue and issecretvalue(name)) and name and name ~= "" then
            payload.obtainedBy = name
        end
    end
    if payload.type and payload.id ~= nil then
        WarbandNexus:RegisterTryCounterLootToastForBagDedupe(payload.type, payload.id, sourceItemID)
    end
    self:SendMessage(E.COLLECTIBLE_OBTAINED, payload)
end

--- LOOT_OPENED early miss uses silentAnnounce; emit the delta at LOOT_CLOSED finalize.
function Fns.EmitEarlyMissIncrementAnnounce(trackable, found, baselineTryCounts)
    if not Fns.IsAutoTryCounterEnabled() then
        Fns.TryCounterAnnounceDebug("early-miss: skipped (auto try counter disabled)")
        return
    end
    if not trackable or not baselineTryCounts then
        Fns.TryCounterAnnounceDebug("early-miss: skipped (trackable=%s baselines=%s)",
            tostring(trackable ~= nil), tostring(baselineTryCounts ~= nil))
        return
    end
    local incrementAnnounce = {}
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop and (not found or not found[drop.itemID])
            and not Fns.ShouldSkipMissIncrementForDrop(drop)
            and (drop.repeatable or not Fns.IsCollectibleCollected(drop)) then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local ck = tcType .. "\0" .. tostring(tryKey)
                local base = Fns.GetTryCountBaseline(baselineTryCounts, drop, tcType, tryKey)
                local now = WarbandNexus:GetTryCount(tcType, tryKey) or 0
                -- gsub returns 2 values; parenthesise so the count never shifts the format args.
                Fns.TryCounterAnnounceDebug("early-miss %s: base=%s now=%d added=%s",
                    (ck:gsub("%z", ":")), tostring(base), now, tostring(base and (now - base)))
                if base == nil then
                    -- We only get here when the early increment already ran, so this drop WAS
                    -- counted. Staying silent is the one wrong answer: report the total instead of
                    -- the delta we can no longer compute.
                    Fns.TryCounterAnnounceDebug("early-miss %s: no baseline - announcing total %d",
                        (ck:gsub("%z", ":")), now)
                    base = (now > 0) and (now - 1) or 0
                end
                local added = now - base
                if added > 0 then
                    incrementAnnounce[ck] = {
                        drop = drop,
                        added = added,
                        finalCount = now,
                    }
                end
            end
        end
    end
    if next(incrementAnnounce) then
        Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce)
    else
        Fns.TryCounterAnnounceDebug("early-miss: nothing to announce")
    end
end

function Fns.RefreshLootSessionSlotLinks(numLoot, slotData)
    if not numLoot or numLoot == 0 or not slotData then return end
    for i = 1, numLoot do
        local entry = slotData[i]
        if entry and entry.hasItem and GetLootSlotLink then
            local link = GetLootSlotLink(i)
            if issecretvalue and issecretvalue(link) then link = nil end
            if link then entry.link = link end
        end
    end
end

function Fns.BuildNpcLootFoundMap(trackable, numLoot, slotData)
    Fns.RefreshLootSessionSlotLinks(numLoot, slotData)
    local found = Fns.ScanLootForItems(trackable, numLoot, slotData)
    for i = 1, #trackable do
        local drop = trackable[i]
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if tryKey and Fns.IsDropObtainedThisKill(tcType, tryKey, drop) then
            found[drop.itemID] = true
        end
    end
    return found
end

--- Silent +1 at LOOT_OPENED (before loot lines): normal kill/rare flow only; stat-backed raid skips.
---@return boolean earlyMissApplied
---Open-world AoE farm: one loot window can merge N corpses of the same drop table, and each corpse
---is one attempt. Encounters, objects and statistic-backed rows always count 1.
function Fns.ComputeFarmCorpseMultiplier(drops, matchedNpcID, matchedEncounterID, lastMatchedObjectID, allSourceGUIDs, missedDrops)
    if not matchedNpcID or matchedEncounterID or lastMatchedObjectID then return 1 end
    if not allSourceGUIDs or #allSourceGUIDs == 0 then return 1 end
    if drops and Fns.NpcEntryHasStatisticIds(drops) then return 1 end
    local tableMult = Fns.CountCorpsesSharingDropTable(allSourceGUIDs, drops)
    local npcMult = Fns.CountUniqueLootSourcesForNpcID(allSourceGUIDs, matchedNpcID)
    local tryItemSet = Fns.BuildItemIdSetFromDropList(missedDrops)
    local candidateList = Fns.BuildNpcIdsEligibleForDropItemSet(tryItemSet)
    local itemMult = Fns.CountCorpsesForMissedDropItems(allSourceGUIDs, tryItemSet, candidateList)
    return math.max(1, tableMult, npcMult, itemMult)
end

function Fns.ApplyEarlyLootAttemptIncrement(ctx)
    if not ctx or not ctx.trackable or #ctx.trackable == 0 then return false end
    if not Fns.IsAutoTryCounterEnabled() or not Fns.EnsureDB() then return false end

    local drops = ctx.drops
    local statIds = drops and drops.statisticIds or nil
    if Fns.ShouldUseStatisticsOnlyMiss(ctx.trackable, statIds) then return false end

    local npcID = ctx.matchedNpcID or ctx.slotBossNpcID
    if npcID and Fns.IsLockoutDuplicate(npcID) then return false end
    -- Already counted by the ENCOUNTER_END lootless fallback; the outcome pass consumes the mark.
    if npcID and Fns.HasLootlessMissForNpc(npcID) then return false end

    local tryCountSourceKey = ctx.slotOutcomeSourceKey
        or Fns.BuildTryCountSourceKey(ctx.matchedEncounterID, ctx.matchedNpcID, ctx.lastMatchedObjectID, ctx.dedupGUID)
    local now = GetTime()
    local encounterDedupTtl = 15
    if tryCountSourceKey and V.lastTryCountSourceKey == tryCountSourceKey
        and (now - (V.lastTryCountSourceTime or 0)) < encounterDedupTtl then
        return false
    end

    local missed = {}
    for i = 1, #ctx.trackable do
        local d = ctx.trackable[i]
        if d and not Fns.ShouldSkipMissIncrementForDrop(d)
            and (d.repeatable or not Fns.IsCollectibleCollected(d)) then
            missed[#missed + 1] = d
        end
    end
    if #missed == 0 then return false end

    local kind = ctx.kind or "npc"
    if kind == "fishing" then
        V.lastTryCountSourceKey = "fishing_open"
        V.lastTryCountSourceTime = now
    elseif kind == "container" and ctx.containerItemID then
        V.lastTryCountSourceKey = "container_" .. tostring(ctx.containerItemID)
        V.lastTryCountSourceTime = now
    else
        if tryCountSourceKey then
            V.lastTryCountSourceKey = tryCountSourceKey
            V.lastTryCountSourceTime = now
            local guid = ctx.dedupGUID or (ctx.allSourceGUIDs and ctx.allSourceGUIDs[1])
            V.lastTryCountLootSourceGUID = guid
        end
    end

    -- The deferred and closed routes always take this early path, so the AoE corpse multiplier has
    -- to apply here too; it used to live only on the rare non-early path (+1 for 3 corpses).
    local attemptTimes = 1
    if kind == "npc" then
        attemptTimes = Fns.ComputeFarmCorpseMultiplier(drops, ctx.matchedNpcID, ctx.matchedEncounterID,
            ctx.lastMatchedObjectID, ctx.allSourceGUIDs, missed)
    end
    Fns.ProcessMissedDrops(missed, statIds, {
        silentAnnounce = true,
        sync = true,
        attemptTimes = attemptTimes,
    })
    local committedKey = tryCountSourceKey
    Fns.NotifyLootTryOutcomeCommitted(committedKey, ctx.matchedNpcID or ctx.slotBossNpcID)
    Fns.MarkLootSourceGuidsProcessed(ctx.dedupGUID, ctx.allSourceGUIDs, nil)
    return true
end

function Fns.StageDeferredLootSession(ctx)
    if not ctx or not ctx.trackable or #ctx.trackable == 0 then return end
    V.pendingLootSessionFinalize = {
        kind = ctx.kind or "npc",
        matchedNpcID = ctx.matchedNpcID,
        matchedEncounterID = ctx.matchedEncounterID,
        lastMatchedObjectID = ctx.lastMatchedObjectID,
        dedupGUID = ctx.dedupGUID,
        drops = ctx.drops,
        trackable = ctx.trackable,
        encounterDiffID = ctx.encounterDiffID,
        allSourceGUIDs = ctx.allSourceGUIDs,
        slotOutcomeSourceKey = ctx.slotOutcomeSourceKey,
        slotBossNpcID = ctx.slotBossNpcID,
        containerItemID = ctx.containerItemID,
        baselineTryCounts = Fns.CaptureTryCountBaselines(ctx.trackable),
        stagedAt = GetTime(),
        lootOpenSerial = RT.lootOpenSerial or 0,
        earlyMissApplied = false,
    }
    if Fns.ApplyEarlyLootAttemptIncrement(ctx) then
        V.pendingLootSessionFinalize.earlyMissApplied = true
    end
    RT.pendingLootSessionFinalize = V.pendingLootSessionFinalize
    if ctx.matchedNpcID then
        Fns.MarkLockoutLootTouched(ctx.matchedNpcID)
        Fns.CancelLockoutQuestFallbackForNpc(ctx.matchedNpcID)
    end
    if ctx.slotBossNpcID then
        Fns.MarkLockoutLootTouched(ctx.slotBossNpcID)
    end
end

function Fns.FinalizeDeferredLootSessionOutcome(self)
    local pending = V.pendingLootSessionFinalize
    if not pending then return end
    V.pendingLootSessionFinalize = nil
    RT.pendingLootSessionFinalize = nil

    local kind = pending.kind or "npc"
    -- Slot data is only evidence for the window the session was staged in. Reading a later window's
    -- slots could mark a drop "found" that was never seen here and wrongly reset its try counter.
    local sameWindow = (pending.lootOpenSerial == nil)
        or (pending.lootOpenSerial == (RT.lootOpenSerial or 0))
    local found
    if sameWindow then
        found = Fns.BuildNpcLootFoundMap(pending.trackable, RT.lootSession.numLoot, RT.lootSession.slotData)
    else
        found = {}
        Fns.TryCounterAnnounceDebug("finalize: stale pending (staged serial=%s, now=%s) - slots ignored",
            tostring(pending.lootOpenSerial), tostring(RT.lootOpenSerial))
    end
    local baseline = pending.baselineTryCounts
    local earlyMissApplied = pending.earlyMissApplied

    if kind == "fishing" then
        Fns.ApplyFishingLootOutcomes(self, {
            trackable = pending.trackable,
            found = found,
            baselineTryCounts = baseline,
            earlyMissApplied = earlyMissApplied,
        })
        return
    end
    if kind == "container" then
        Fns.ApplyContainerLootOutcomes(self, {
            trackable = pending.trackable,
            found = found,
            containerItemID = pending.containerItemID,
            baselineTryCounts = baseline,
            earlyMissApplied = earlyMissApplied,
        })
        return
    end
    if kind == "slot_boss" then
        Fns.ApplySlotBossLootOutcomes(self, {
            trackable = pending.trackable,
            found = found,
            drops = pending.drops,
            slotOutcomeSourceKey = pending.slotOutcomeSourceKey,
            slotBossNpcID = pending.slotBossNpcID,
            allSourceGUIDs = pending.allSourceGUIDs,
            baselineTryCounts = baseline,
            earlyMissApplied = earlyMissApplied,
        })
        return
    end

    local matchedNpcID = pending.matchedNpcID
    -- IsLockoutDuplicate LATCHES: the first observation of a flagged quest marks the period as used
    -- and returns false, every later call returns true. ApplyEarlyLootAttemptIncrement already
    -- consumed that first observation at LOOT_OPENED (that is what earlyMissApplied records), so
    -- asking again here reports a duplicate for the very kill we just counted -- and the isLockoutSkip
    -- branch in ApplyNpcLootOutcomes then printed "Skipped: daily/weekly lockout" INSTEAD of calling
    -- EmitEarlyMissIncrementAnnounce. Every Undermine daily/weekly rare incremented in silence.
    local isLockoutSkip = false
    if not earlyMissApplied and matchedNpcID then
        isLockoutSkip = Fns.IsLockoutDuplicate(matchedNpcID) == true
    end
    Fns.ApplyNpcLootOutcomes(self, {
        trackable = pending.trackable,
        found = found,
        drops = pending.drops,
        matchedNpcID = matchedNpcID,
        matchedEncounterID = pending.matchedEncounterID,
        lastMatchedObjectID = pending.lastMatchedObjectID,
        dedupGUID = pending.dedupGUID,
        allSourceGUIDs = pending.allSourceGUIDs,
        isLockoutSkip = isLockoutSkip,
        baselineTryCounts = baseline,
        earlyMissApplied = earlyMissApplied,
    })
end

function Fns.ApplyNpcLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local drops = opts.drops
    local matchedNpcID = opts.matchedNpcID
    local matchedEncounterID = opts.matchedEncounterID
    local lastMatchedObjectID = opts.lastMatchedObjectID
    local dedupGUID = opts.dedupGUID
    local allSourceGUIDs = opts.allSourceGUIDs or {}
    local isLockoutSkip = opts.isLockoutSkip
    local baselineTryCounts = opts.baselineTryCounts
    local earlyMissApplied = opts.earlyMissApplied

    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local base = Fns.GetTryCountBaseline(baselineTryCounts, drop, tcType, tryKey)
            if base ~= nil then
                return Fns.AdjustPreResetForDelayedReseed(base, tcType, tryKey)
            end
        end
        local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
        return Fns.AdjustPreResetForDelayedReseed(currentCount, tcType, tryKey)
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey and not Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                local didReset = Fns.ShouldResetOnObtain(tcType, tryKey, drop)
                if didReset then
                    WarbandNexus:ResetTryCount(tcType, tryKey)
                end
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat(
                    didReset and "TRYCOUNTER_OBTAINED_RESET" or "TRYCOUNTER_OBTAINED",
                    didReset and "Obtained %s! Try counter reset." or "Obtained %s!",
                    itemLink, preResetCount))
                if drop.type == "item" then
                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                    SendTryCounterCollectibleObtained(WarbandNexus, {
                        type = "item",
                        id = drop.itemID,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    }, drop.itemID)
                end
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey and not Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local currentCount = preResetForDrop(drop)
                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount or 0
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED", "Obtained %s!", itemLink, currentCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = drop.type,
                    id = (drop.type == "item") and drop.itemID or tryKey,
                    name = itemName or drop.name or "Unknown",
                    icon = itemIcon,
                    preResetTryCount = currentCount,
                    fromTryCounter = true,
                }, drop.itemID)
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and drop.type ~= "item" and not found[drop.itemID] then
            local tryKey = Fns.GetTryCountKey(drop)
            if tryKey then
                local currentCount = preResetForDrop(drop)
                local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
            end
        end
    end

    if isLockoutSkip then
        if Fns.ShouldAnnounceLockoutSkip(matchedNpcID) then
            local lockDedupKey = (matchedEncounterID and ("lockskip_enc_" .. tostring(matchedEncounterID)))
                or (matchedNpcID and ("lockskip_npc_" .. tostring(matchedNpcID)))
                or "lockskip_generic"
            local tLock = GetTime()
            if lockDedupKey ~= lastLockoutSkipChatKey or (tLock - lastLockoutSkipChatTime) >= RT.SKIP_CHAT_DEDUP_SEC then
                lastLockoutSkipChatKey = lockDedupKey
                lastLockoutSkipChatTime = tLock
                Fns.TryChat("|cff9370DB[WN-Counter]|r |cff888888" .. ((ns.L and ns.L["TRYCOUNTER_LOCKOUT_SKIP"]) or "Skipped: daily/weekly lockout active for this NPC."))
            end
        end
        return
    end

    if earlyMissApplied then
        Fns.EmitEarlyMissIncrementAnnounce(trackable, found, baselineTryCounts)
        Fns.MarkLootSourceGuidsProcessed(dedupGUID, allSourceGUIDs, nil)
        return
    end

    local dropsToIncrement = {}
    for i = 1, #trackable do
        local d = trackable[i]
        if not found[d.itemID] and not Fns.ShouldSkipMissIncrementForDrop(d) then
            dropsToIncrement[#dropsToIncrement + 1] = d
        end
    end
    -- The lootless fallback already counted this kill; obtain detection above still ran.
    if matchedNpcID and Fns.ConsumeLootlessMissForNpc(matchedNpcID) then
        dropsToIncrement = {}
    end

    local now = GetTime()
    local farmCorpseMult = Fns.ComputeFarmCorpseMultiplier(drops, matchedNpcID, matchedEncounterID,
        lastMatchedObjectID, allSourceGUIDs, dropsToIncrement)

    local tryCountSourceKey = Fns.BuildTryCountSourceKey(matchedEncounterID, matchedNpcID, lastMatchedObjectID, dedupGUID)
    local encounterDedupTtl = 15
    if #dropsToIncrement > 0 and tryCountSourceKey
        and V.lastTryCountSourceKey == tryCountSourceKey and (now - V.lastTryCountSourceTime) < encounterDedupTtl then
        local statBackedOnly = {}
        local statIds = drops and drops.statisticIds
        for i = 1, #dropsToIncrement do
            local drop = dropsToIncrement[i]
            if Fns.ShouldUseStatisticsOnlyMiss({ drop }, statIds) then
                statBackedOnly[#statBackedOnly + 1] = drop
            end
        end
        dropsToIncrement = statBackedOnly
    end

    local mergeFp = nil
    local openWorldFarm = matchedNpcID and not matchedEncounterID and not lastMatchedObjectID
    local statNoStats = not (drops and Fns.NpcEntryHasStatisticIds(drops))
    if openWorldFarm and statNoStats and #dropsToIncrement > 0 and #allSourceGUIDs > 0 then
        mergeFp = tostring(matchedNpcID) .. "\1" .. Fns.BuildSortedSourceFingerprint(allSourceGUIDs)
        local tMerge = mergedLootTryCountedAt[mergeFp]
        if tMerge and (now - tMerge) < MERGED_LOOT_TRY_DEDUP_TTL then
            dropsToIncrement = {}
            farmCorpseMult = 1
            mergeFp = nil
        end
    end

    local willIncrementMisses = #dropsToIncrement > 0

    V.lastTryCountSourceKey = tryCountSourceKey
    V.lastTryCountSourceTime = GetTime()
    if tryCountSourceKey then
        V.lastTryCountLootSourceGUID = (type(dedupGUID) == "string" and dedupGUID) or allSourceGUIDs[1]
    else
        V.lastTryCountLootSourceGUID = nil
    end

    local statIds = drops and drops.statisticIds or nil
    local lootMiss = {}
    for i = 1, #dropsToIncrement do
        local drop = dropsToIncrement[i]
        if not Fns.ShouldUseStatisticsOnlyMiss({ drop }, statIds) then
            lootMiss[#lootMiss + 1] = drop
        end
    end
    dropsToIncrement = lootMiss
    Fns.TryCounterLootDebugDropLines(self, "NPC", dropsToIncrement, farmCorpseMult)
    if #dropsToIncrement > 0 then
        Fns.ProcessMissedDrops(dropsToIncrement, statIds, { attemptTimes = farmCorpseMult })
        Fns.NotifyLootTryOutcomeCommitted(tryCountSourceKey, matchedNpcID)
    end
    if mergeFp and willIncrementMisses then
        mergedLootTryCountedAt[mergeFp] = GetTime()
    end
    Fns.MarkLootSourceGuidsProcessed(dedupGUID, allSourceGUIDs, nil)
end

function Fns.ApplyFishingLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local baselineTryCounts = opts.baselineTryCounts
    local earlyMissApplied = opts.earlyMissApplied

    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local base = Fns.GetTryCountBaseline(baselineTryCounts, drop, tcType, tryKey)
            if base ~= nil then return base end
        end
        return WarbandNexus:GetTryCount(tcType, tryKey) or 0
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if found[drop.itemID] and drop.repeatable then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                local didReset = Fns.ShouldResetOnObtain(tcType, tryKey, drop)
                if didReset then
                    WarbandNexus:ResetTryCount(tcType, tryKey)
                end
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount or 0
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat(
                    didReset and "TRYCOUNTER_CAUGHT_RESET" or "TRYCOUNTER_CAUGHT",
                    didReset and "Caught %s! Try counter reset." or "Caught %s!",
                    itemLink, preResetCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                -- `a and f()` keeps only f's first return; itemIcon (10th) was always nil.
                local itemName, _, _, _, _, _, _, _, _, itemIcon
                if GetItemInfoFn then itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID) end
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType, id = tryKey, name = itemName or drop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount, fromTryCounter = true,
                }, drop.itemID)
            end
        elseif found[drop.itemID] and not drop.repeatable then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                -- One-time catch: the counter freezes at "tries to obtain" (NPC path semantics).
                -- Resetting here wiped that total the moment the item was caught.
                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = preResetCount or 0
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                V.lastTryCountSourceTime = GetTime()
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_CAUGHT", "Caught %s!", itemLink, preResetCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                -- `a and f()` keeps only f's first return; itemIcon (10th) was always nil.
                local itemName, _, _, _, _, _, _, _, _, itemIcon
                if GetItemInfoFn then itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID) end
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType, id = tryKey, name = itemName or drop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount, fromTryCounter = true,
                }, drop.itemID)
            end
        end
    end

    local missed = {}
    for i = 1, #trackable do
        local d = trackable[i]
        if not found[d.itemID] and not Fns.ShouldSkipMissIncrementForDrop(d) then
            missed[#missed + 1] = d
        end
    end
    Fns.TryCounterLootDebugDropLines(self, "Fishing", missed)
    Fns.TryCounterAnnounceDebug("fishing outcomes: missed=%d earlyMissApplied=%s baselines=%s",
        #missed, tostring(earlyMissApplied == true), tostring(baselineTryCounts ~= nil))
    if earlyMissApplied then
        Fns.EmitEarlyMissIncrementAnnounce(trackable, found, baselineTryCounts)
    elseif #missed > 0 then
        V.lastTryCountSourceKey = "fishing_open"
        V.lastTryCountSourceTime = GetTime()
        Fns.ProcessMissedDrops(missed, nil)
    end
end

function Fns.ApplyContainerLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local baselineTryCounts = opts.baselineTryCounts
    local earlyMissApplied = opts.earlyMissApplied
    local containerItemID = opts.containerItemID
    local now = GetTime()
    if containerItemID then
        V.lastTryCountSourceKey = "container_" .. tostring(containerItemID)
        V.lastTryCountSourceTime = now
    end

    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local base = Fns.GetTryCountBaseline(baselineTryCounts, drop, tcType, tryKey)
            if base ~= nil then return base end
        end
        return WarbandNexus:GetTryCount(tcType, tryKey) or 0
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if found[drop.itemID] then
            if not drop.repeatable and drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            -- Same guard as the NPC path: the CHAT_MSG_LOOT container path may already have announced
            -- and reset this obtain, and a second pass would print a contradictory count.
            if tryKey and Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                tryKey = nil
            end
            if tryKey then
                Fns.ResolveCollectibleID(drop)
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                local didReset = Fns.ShouldResetOnObtain(tcType, tryKey, drop)
                if didReset then
                    WarbandNexus:ResetTryCount(tcType, tryKey)
                end
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount or 0
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                local chatKey = didReset and "TRYCOUNTER_CONTAINER_RESET" or "TRYCOUNTER_CONTAINER"
                local chatFallback = didReset and "Obtained %s from container! Try counter reset." or "Obtained %s from container!"
                Fns.TryChat(Fns.BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                -- `a and f()` keeps only f's first return; itemIcon (10th) was always nil.
                local itemName, _, _, _, _, _, _, _, _, itemIcon
                if GetItemInfoFn then itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID) end
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType,
                    id = (drop.type == "item") and drop.itemID or tryKey,
                    name = itemName or drop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount, fromTryCounter = true,
                }, drop.itemID)
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end

    local missed = {}
    for i = 1, #trackable do
        if not found[trackable[i].itemID] then missed[#missed + 1] = trackable[i] end
    end
    if earlyMissApplied then
        Fns.EmitEarlyMissIncrementAnnounce(trackable, found, baselineTryCounts)
    else
        Fns.ProcessMissedDrops(missed, nil, { sync = true })
    end
end

function Fns.ApplySlotBossLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local drops = opts.drops
    local slotOutcomeSourceKey = opts.slotOutcomeSourceKey
    local slotBossNpcID = opts.slotBossNpcID
    local allSourceGUIDs = opts.allSourceGUIDs or {}
    local baselineTryCounts = opts.baselineTryCounts
    local earlyMissApplied = opts.earlyMissApplied
    local now = GetTime()

    local anyFound = false
    for ti = 1, #trackable do
        local d = trackable[ti]
        if d and found[d.itemID] then anyFound = true; break end
    end

    if anyFound then
        Fns.ClearEncounterRecentKillsForNpcId(slotBossNpcID)
        if baselineTryCounts then
            Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops, baselineTryCounts)
        else
            Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops)
        end
        V.lastTryCountSourceKey = slotOutcomeSourceKey
        V.lastTryCountSourceTime = now
        V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
        return
    end

    -- Miss path: personal-loot chest slots may have hasItem=true while links are nil/secret at
    -- LOOT_CLOSED (Midnight / post-cinematic Sylvanas chest). Readable links are not required.
    if not Fns.LootSlotsHaveReadableItemLink(RT.lootSession.slotData, RT.lootSession.numLoot)
        and not Fns.LootSlotsHaveItemsPresent(RT.lootSession.slotData, RT.lootSession.numLoot) then
        return
    end

    local missed = {}
    for mi = 1, #trackable do
        local d = trackable[mi]
        if d and not found[d.itemID] and not Fns.ShouldSkipMissIncrementForDrop(d) then
            missed[#missed + 1] = d
        end
    end
    if #missed == 0 then return end

    if earlyMissApplied then
        Fns.EmitEarlyMissIncrementAnnounce(trackable, found, baselineTryCounts)
        V.lastTryCountSourceKey = slotOutcomeSourceKey
        V.lastTryCountSourceTime = now
        V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
        return
    end

    if Fns.ShouldUseStatisticsOnlyMiss(missed, drops and drops.statisticIds) then
        V.lastTryCountSourceKey = slotOutcomeSourceKey
        V.lastTryCountSourceTime = now
        V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
        return
    end

    if slotOutcomeSourceKey and V.lastTryCountSourceKey == slotOutcomeSourceKey
        and (now - V.lastTryCountSourceTime) < 15 then
        V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
        return
    end

    Fns.ClearEncounterRecentKillsForNpcId(slotBossNpcID)
    Fns.TryCounterLootDebugDropLines(self, "SlotOutcome", missed, 1)
    Fns.ProcessMissedDrops(missed, drops and drops.statisticIds, { attemptTimes = 1 })
    V.lastTryCountSourceKey = slotOutcomeSourceKey
    V.lastTryCountSourceTime = now
    V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
    Fns.NotifyLootTryOutcomeCommitted(slotOutcomeSourceKey, slotBossNpcID)
end

function Fns.IsLootSessionPendingOrRecent(ttlSec)
    if V.pendingLootSessionFinalize then return true end
    if RT.lootSession.opened then return true end
    local ttl = ttlSec or RT.LOOT_SESSION_RECENT_TTL
    if lootReady.time > 0 and (GetTime() - lootReady.time) < ttl then return true end
    return false
end

--- All slot-based try counting defers DB writes until LOOT_CLOSED (LOOT_OPENED may fire early).
function Fns.ShouldDeferLootOutcomeUntilClose(lootRouteSource)
    if lootRouteSource ~= "opened" then return false end
    -- Nothing left to wait for: the window this route belongs to has already closed (see
    -- ScheduleLootRouteProcessor). Apply the outcome now instead of staging an unfinalizable session.
    if V.lootRouteWindowAlreadyClosed then return false end
    return true
end

function Fns.SessionTrackableContainsItemID(trackable, itemID)
    if not trackable or not itemID then return false end
    for i = 1, #trackable do
        local d = trackable[i]
        if d and d.itemID == itemID then return true, d end
        if d and d.questStarters then
            for qi = 1, #d.questStarters do
                if d.questStarters[qi].itemID == itemID then return true, d end
            end
        end
    end
    return false, nil
end

function Fns.TryMarkSessionObtainFromChatItem(itemID)
    if not itemID then return false end
    local pending = V.pendingLootSessionFinalize
    if not pending or not pending.trackable then return false end
    local matched, drop = Fns.SessionTrackableContainsItemID(pending.trackable, itemID)
    if not matched or not drop then return false end
    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
    if not tryKey then return false end
    Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
    return true
end

function Fns.CaptureTryCountBaselines(trackable)
    local baselines = {}
    for i = 1, #trackable do
        local drop = trackable[i]
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if tryKey then
            local count = WarbandNexus:GetTryCount(tcType, tryKey) or 0
            baselines[tcType .. "\0" .. tostring(tryKey)] = count
            -- Second entry keyed by the drop TABLE itself. The composite key is derived from
            -- ResolveCollectibleID, which yields the mountID only while C_MountJournal
            -- .GetMountFromItem is warm and silently falls back to the itemID when it is not -- so a
            -- key captured at LOOT_OPENED can fail to match the one re-derived at LOOT_CLOSED. That
            -- mismatch made the whole attempt line vanish (base=nil -> "nothing to announce") and
            -- also skewed the "after N attempts" number on obtain. The drop table is the same object
            -- at both ends, so this lookup cannot drift. Read it via Fns.GetTryCountBaseline.
            baselines[drop] = count
        end
    end
    return baselines
end

--- Baseline for one drop. Identity first (drift-proof), composite key second (older callers /
--- baselines captured before a drop entry existed). Returns nil when neither is present.
function Fns.GetTryCountBaseline(baselines, drop, tcType, tryKey)
    if not baselines then return nil end
    if drop ~= nil then
        local byDrop = baselines[drop]
        if byDrop ~= nil then return byDrop end
    end
    if tcType and tryKey ~= nil then
        return baselines[tcType .. "\0" .. tostring(tryKey)]
    end
    return nil
end
