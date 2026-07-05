--[[
    Warband Nexus - Try Counter comprehensive self-test (/wn tc test).
    Synthetic loot-session probes per source type (object, rare, container, fishing,
    raid boss, world boss, encounter). No real loot required; restores try counts after deltas.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars
local format = string.format
local wipe = wipe
local GetTime = GetTime

assert(Fns and RT and V and WarbandNexus, "TryCounterService_SelfTest: load TryCounterService.lua first")

local FAKE_ITEM_ID = TC.SELF_TEST_FAKE_ITEM_ID or 987654321
local SYLVANAS_NPC_ID = 175732
local SYLVANAS_ENCOUNTER_ID = 2435
local SYLVANAS_CHEST_OBJECT_ID = TC.SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID or 368304

local function fakeDrop()
    return { type = "item", itemID = FAKE_ITEM_ID, repeatable = true, name = "TC Self Test Token" }
end

local function fakeItemLink()
    return "|Hitem:" .. tostring(FAKE_ITEM_ID) .. ":0|h[TC Self Test]|h|r"
end

local function snapshotState()
    return {
        session = Fns.SnapshotLootSessionState(),
        pending = RT.pendingLootSessionFinalize,
        wasFishing = RT.lootReady.wasFishing,
        lootReadyTime = RT.lootReady.time,
        containerID = V.lastContainerItemID,
        containerTime = V.lastContainerItemTime,
        objID = V.lastTrackedObjectInteractID,
        objGUID = V.lastTrackedObjectInteractGUID,
        objTime = V.lastTrackedObjectInteractTime,
        tryKey = V.lastTryCountSourceKey,
        tryTime = V.lastTryCountSourceTime,
    }
end

local function restoreState(s)
    if not s then return end
    Fns.ApplyLootSessionState(s.session)
    Fns.SetDeferredLootSessionSnapshot(s.pending)
    RT.lootReady.wasFishing = s.wasFishing
    RT.lootReady.time = s.lootReadyTime or 0
    V.lastContainerItemID = s.containerID
    V.lastContainerItemTime = s.containerTime or 0
    V.lastTrackedObjectInteractID = s.objID
    V.lastTrackedObjectInteractGUID = s.objGUID
    V.lastTrackedObjectInteractTime = s.objTime or 0
    V.lastTryCountSourceKey = s.tryKey
    V.lastTryCountSourceTime = s.tryTime or 0
end

local function withRestoredState(fn)
    local snap = snapshotState()
    local dedupSnap = Fns.SnapshotTryCounterSelfTestDedupState and Fns.SnapshotTryCounterSelfTestDedupState()
    Fns.ClearDeferredLootSession()
    if Fns.ClearTryCounterTransientKillMarks then
        Fns.ClearTryCounterTransientKillMarks()
    end
    if Fns.ClearTryCounterSelfTestDedupState then
        Fns.ClearTryCounterSelfTestDedupState()
    end
    if Fns.ClearTryCounterGatherCastGuard then
        Fns.ClearTryCounterGatherCastGuard()
    end
    if Fns.SetTryCounterSelfTestSlotOutcomeEnv then
        Fns.SetTryCounterSelfTestSlotOutcomeEnv(nil)
    end
    V.lastTryCountSourceKey = nil
    V.lastTryCountSourceTime = 0
    local ok, err = pcall(fn)
    restoreState(snap)
    if Fns.RestoreTryCounterSelfTestDedupState and dedupSnap then
        Fns.RestoreTryCounterSelfTestDedupState(dedupSnap)
    end
    if Fns.ClearTryCounterTransientKillMarks then
        Fns.ClearTryCounterTransientKillMarks()
    end
    if Fns.ClearTryCounterGatherCastGuard then
        Fns.ClearTryCounterGatherCastGuard()
    end
    if Fns.SetTryCounterSelfTestSlotOutcomeEnv then
        Fns.SetTryCounterSelfTestSlotOutcomeEnv(nil)
    end
    if not ok then error(err) end
end

local function runSelfTestHarness(WN, title, fn)
    local pass, fail, warn = 0, 0, 0
    local failedLabels = {}
    local function linePass(label)
        pass = pass + 1
        WN:Print("|cff00ff00[WN-TC-Test] PASS|r " .. label)
    end
    local function lineFail(label, err)
        fail = fail + 1
        failedLabels[#failedLabels + 1] = { label = label, err = err }
        local tail = err and (": " .. tostring(err)) or ""
        WN:Print("|cffff0000[WN-TC-Test] FAIL|r " .. label .. tail)
    end
    local function lineWarn(label)
        warn = warn + 1
        WN:Print("|cffffcc00[WN-TC-Test] WARN|r " .. label)
    end
    local function section(st)
        WN:Print("|cff9370DB[WN-TC-Test]|r — " .. st)
    end
    local function probe(label, pfn)
        local ok, err = pcall(pfn)
        if ok then linePass(label) else lineFail(label, err) end
    end
    if Fns.ClearTryCounterTransientKillMarks then
        Fns.ClearTryCounterTransientKillMarks()
    end
    if Fns.ClearTryCounterGatherCastGuard then
        Fns.ClearTryCounterGatherCastGuard()
    end
    WN:Print("|cff9370DB[WN-TC-Test]|r " .. title)
    fn(section, probe, lineWarn)
    if fail == 0 then
        WN:Print(format("|cff00ff00[WN-TC-Test] OK|r %d passed, %d warnings.", pass, warn))
    else
        WN:Print("|cffff0000[WN-TC-Test]|r Failed checks (recap):")
        for i = 1, #failedLabels do
            local entry = failedLabels[i]
            local tail = entry.err and (": " .. tostring(entry.err)) or ""
            WN:Print("|cffff0000[WN-TC-Test] FAIL|r " .. entry.label .. tail)
        end
        WN:Print(format("|cffff0000[WN-TC-Test] FAILED|r %d passed, %d failed, %d warnings.", pass, fail, warn))
    end
end

function WarbandNexus:RunTryCounterSelfTest()
    local WN = self
    local pass, fail, warn = 0, 0, 0
    local failedLabels = {}
    local samples = Fns.GetSelfTestSampleIds and Fns.GetSelfTestSampleIds() or {}

    local function linePass(label)
        pass = pass + 1
        WN:Print("|cff00ff00[WN-TC-Test] PASS|r " .. label)
    end
    local function lineFail(label, err)
        fail = fail + 1
        failedLabels[#failedLabels + 1] = { label = label, err = err }
        local tail = err and (": " .. tostring(err)) or ""
        WN:Print("|cffff0000[WN-TC-Test] FAIL|r " .. label .. tail)
    end
    local function lineWarn(label)
        warn = warn + 1
        WN:Print("|cffffcc00[WN-TC-Test] WARN|r " .. label)
    end
    local function section(title)
        WN:Print("|cff9370DB[WN-TC-Test]|r — " .. title)
    end
    local function probe(label, fn)
        local ok, err = pcall(fn)
        if ok then linePass(label) else lineFail(label, err) end
    end
    local function requireFn(name)
        local fn = WN[name]
        if type(fn) ~= "function" and Fns then
            fn = Fns[name]
        end
        if type(fn) == "function" then
            linePass(name .. " registered")
        else
            lineFail(name .. " missing")
        end
    end

    if not Fns.EnsureDB() then
        WN:Print("|cffff0000[WN-TC-Test]|r DB not ready — aborting.")
        return
    end
    if not Fns.EnsureTryCounterRuntimeDbLoaded or not Fns.EnsureTryCounterRuntimeDbLoaded() then
        WN:Print("|cffff0000[WN-TC-Test]|r CollectibleSourceDB not loaded — aborting.")
        return
    end

    if Fns.ClearTryCounterTransientKillMarks then
        Fns.ClearTryCounterTransientKillMarks()
    end
    if Fns.ClearTryCounterGatherCastGuard then
        Fns.ClearTryCounterGatherCastGuard()
    end

    local mechID = samples.mechanicaItemID or 234741
    local savedFakeCount = WN:GetTryCount("item", FAKE_ITEM_ID)
    local savedMechCount = WN:GetTryCount("item", mechID)
    if Fns.SetTryCounterSelfTestSyncMiss then
        Fns.SetTryCounterSelfTestSyncMiss(true)
    end
    if RT.tryCounterSelfTest then
        RT.tryCounterSelfTest.bypassAutoGate = true
    end

    WN:Print("|cff9370DB[WN-TC-Test]|r Full regression (handlers + loot routes)...")

    -- ── Core registration ─────────────────────────────────────────────
    section("Core APIs & handlers")
    requireFn("OnTryCounterNewMountAdded")
    requireFn("OnTryCounterNewPetAdded")
    requireFn("OnTryCounterCollectibleObtained")
    requireFn("GetTryCount")
    requireFn("SetTryCount")
    requireFn("IncrementTryCount")
    requireFn("ResetTryCount")
    requireFn("CheckTargetDrops")
    requireFn("ProcessNPCLoot")
    requireFn("ProcessFishingLoot")
    requireFn("ProcessContainerLoot")
    requireFn("OnTryCounterLootReady")
    requireFn("OnTryCounterLootOpened")
    requireFn("OnTryCounterLootClosed")
    requireFn("OnTryCounterChatMsgLoot")
    requireFn("OnTryCounterEncounterStart")
    requireFn("OnTryCounterEncounterEnd")
    requireFn("OnTryCounterBossKill")
    requireFn("NpcDropEntryContainsAnyItemSet")
    requireFn("ScheduleEncounterLootlessMissFallback")
    requireFn("ForceTryCounterStatisticsSync")
    requireFn("EnsureTryCounterRuntimeDbLoaded")
    requireFn("ApplyEarlyLootAttemptIncrement")
    requireFn("IsLootSessionActiveForIncrementAnnounce")
    requireFn("ScheduleIncrementAnnounceFlushAfterLoot")
    requireFn("ShouldSkipLateLootOpenedRoute")
    requireFn("NotifyLootTryOutcomeCommitted")
    requireFn("CancelEncounterLootlessMissFallback")

    local evList = TC.TRYCOUNTER_EVENTS or {}
    local hasMountEv, hasPetEv, hasLootEv = false, false, false
    for i = 1, #evList do
        local ev = evList[i]
        if ev == "NEW_MOUNT_ADDED" then hasMountEv = true end
        if ev == "NEW_PET_ADDED" then hasPetEv = true end
        if ev == "LOOT_READY" or ev == "LOOT_CLOSED" then hasLootEv = true end
    end
    if hasMountEv then linePass("NEW_MOUNT_ADDED in TRYCOUNTER_EVENTS") else lineFail("NEW_MOUNT_ADDED missing") end
    if hasPetEv then linePass("NEW_PET_ADDED in TRYCOUNTER_EVENTS") else lineFail("NEW_PET_ADDED missing") end
    if hasLootEv then linePass("LOOT_READY/CLOSED in TRYCOUNTER_EVENTS") else lineFail("loot events missing") end

    local notif = WN.db and WN.db.profile and WN.db.profile.notifications
    if notif and notif.autoTryCounter == true then
        linePass("autoTryCounter enabled")
    else
        lineWarn("autoTryCounter off — live loot won't count (Settings > Notifications)")
    end
    if Fns.IsTryCounterModuleEnabled and Fns.IsTryCounterModuleEnabled() then
        linePass("Try Counter module enabled")
    else
        lineWarn("Try Counter module disabled (Settings > Modules)")
    end

    section("Loot pipeline helpers")
    probe("NpcDropEntryContainsAnyItemSet", function()
        local drops = { { type = "item", itemID = FAKE_ITEM_ID } }
        if not Fns.NpcDropEntryContainsAnyItemSet(drops, { [FAKE_ITEM_ID] = true }) then
            error("expected true for matching item")
        end
        if Fns.NpcDropEntryContainsAnyItemSet(drops, { [99999999] = true }) then
            error("expected false for non-matching item")
        end
    end)
    probe("ResolveFromEncounterCache (no crash outside instance)", function()
        local ctx = {}
        Fns.ResolveFromEncounterCache(ctx, false)
        if ctx.drops then error("expected no drops outside instance") end
    end)
    probe("ScheduleEncounterLootlessMissFallback (nil-safe no-op)", function()
        Fns.ScheduleEncounterLootlessMissFallback(nil, nil, nil)
        Fns.ScheduleEncounterLootlessMissFallback(0, 16, "tc_self_test_enc")
    end)

    -- ── Nil / bogus handler tolerance ─────────────────────────────────
    section("Handler nil safety")
    probe("OnTryCounterNewMountAdded(nil)", function() WN:OnTryCounterNewMountAdded(nil) end)
    probe("OnTryCounterNewMountAdded(0)", function() WN:OnTryCounterNewMountAdded(0) end)
    probe("OnTryCounterNewPetAdded(nil)", function() WN:OnTryCounterNewPetAdded(nil) end)
    probe("OnTryCounterNewPetAdded(bogus guid)", function() WN:OnTryCounterNewPetAdded("BattlePet-0-0-0-0") end)
    probe("OnTryCounterCollectibleObtained(nil,nil)", function() WN:OnTryCounterCollectibleObtained(nil, nil) end)
    probe("OnTryCounterCollectibleObtained(invalid type)", function()
        WN:OnTryCounterCollectibleObtained("WN_TEST", { type = "bogus", id = 1 })
    end)
    probe("GetTryCount(nil,nil)", function()
        if WN:GetTryCount(nil, nil) ~= 0 then error("expected 0") end
    end)
    probe("SetTryCount/GetTryCount roundtrip (fake item)", function()
        local old = WN:GetTryCount("item", FAKE_ITEM_ID)
        WN:SetTryCount("item", FAKE_ITEM_ID, 42)
        if WN:GetTryCount("item", FAKE_ITEM_ID) ~= 42 then error("roundtrip failed") end
        WN:SetTryCount("item", FAKE_ITEM_ID, old or 0)
    end)
    probe("CheckTargetDrops(no target)", function() WN:CheckTargetDrops() end)

    section("Statistics-only miss (raid/dungeon gate)")
    probe("ShouldUseStatisticsOnlyMiss false without statisticIds", function()
        if Fns.ShouldUseStatisticsOnlyMiss({ fakeDrop() }, nil) then
            error("expected false without statisticIds")
        end
    end)
    probe("ShouldUseStatisticsOnlyMiss false outside instance (with stat ids)", function()
        if Fns.IsRaidOrDungeonInstance() then return end
        if Fns.ShouldUseStatisticsOnlyMiss({ { type = "mount", itemID = 1 } }, { 15176 }) then
            error("expected false outside raid/dungeon")
        end
    end)
    probe("FilterDropsByDifficulty Mythic in scenario when diff nil", function()
        withRestoredState(function()
            Fns.SetTryCounterSelfTestSlotOutcomeEnv({ instance = { instanceType = "scenario" } })
            local fakeID = TC.SELF_TEST_FAKE_ITEM_ID or 987654321
            local drops = {
                { type = "mount", itemID = fakeID, name = "TC Scenario Mythic", dropDifficulty = "Mythic", repeatable = true },
            }
            local trackable = Fns.FilterDropsByDifficulty(drops, nil)
            if #trackable ~= 1 then
                error("expected 1 trackable Mythic drop in scenario, got " .. tostring(#trackable))
            end
            Fns.SetTryCounterSelfTestSlotOutcomeEnv(nil)
        end)
    end)
    probe("IsRaidOrDungeonInstance true for scenario megadungeon sim", function()
        withRestoredState(function()
            Fns.SetTryCounterSelfTestSlotOutcomeEnv({ instance = { instanceType = "scenario" } })
            if not Fns.IsRaidOrDungeonInstance() then
                error("expected scenario to count as raid/dungeon instance")
            end
            Fns.SetTryCounterSelfTestSlotOutcomeEnv(nil)
        end)
    end)
    probe("ProcessMissedDrops noop for stat-only in raid sim", function()
        withRestoredState(function()
            if Fns.SetTryCounterSelfTestSlotOutcomeEnv then
                Fns.SetTryCounterSelfTestSlotOutcomeEnv({
                    instance = { instanceType = "raid", difficulty = 16 },
                })
            end
            local drop = { type = "mount", itemID = 1, name = "TC Stat Gate" }
            local old = WN:GetTryCount("mount", 1) or 0
            Fns.ProcessMissedDrops({ drop }, { 15176 }, { sync = true })
            if WN:GetTryCount("mount", 1) ~= old then
                error("loot miss must not increment stat-only raid drops")
            end
        end)
    end)
    probe("StageDeferred: no early increment in stat raid sim", function()
        withRestoredState(function()
            if Fns.SetTryCounterSelfTestSlotOutcomeEnv then
                Fns.SetTryCounterSelfTestSlotOutcomeEnv({
                    instance = { instanceType = "raid", difficulty = 16 },
                })
            end
            local drop = { type = "mount", itemID = 1, name = "TC Stat Gate" }
            local old = WN:GetTryCount("mount", 1) or 0
            Fns.StageDeferredLootSession({
                kind = "npc",
                trackable = { drop },
                drops = { statisticIds = { 15176 } },
            })
            if RT.pendingLootSessionFinalize and RT.pendingLootSessionFinalize.earlyMissApplied then
                error("stat raid must not early-increment")
            end
            if (WN:GetTryCount("mount", 1) or 0) ~= old then
                error("stat raid stage must not bump count")
            end
            Fns.ClearDeferredLootSession()
        end)
    end)
    probe("RunStatisticsOnlyMissReseed no manual +1 when stat unchanged", function()
        withRestoredState(function()
            local drop = { type = "item", itemID = FAKE_ITEM_ID, repeatable = true, name = "TC Self Test Token" }
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.RunStatisticsOnlyMissReseed({ drop }, { 99999999 }, { sync = true })
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old then
                error("expected no manual fallback increment")
            end
        end)
    end)

    -- ── Classify-Lock-Process routes ──────────────────────────────────
    section("Loot classify routes")
    probe("Classify: herb GameObject -> skip (gather window)", function()
        withRestoredState(function()
            WN:OnTryCounterSpellcastSent("UNIT_SPELLCAST_SENT", "player", "Test Node", "cast", 12345)
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = { samples.herbGUID or "GameObject-0-0-0-0-999999-000000000000" }
            if Fns.ClassifyLootSession("opened") ~= "skip" then
                error("expected skip for untracked herb GO")
            end
        end)
    end)
    probe("Classify: Overflowing Dumpster -> npc (not skip)", function()
        withRestoredState(function()
            WN:OnTryCounterSpellcastSent("UNIT_SPELLCAST_SENT", "player", "Overflowing Dumpster", "cast", 12345)
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = { samples.dumpsterGUID or "GameObject-0-0-0-0-469857-000000000000" }
            if Fns.ClassifyLootSession("opened") ~= "npc" then
                error("expected npc for tracked dumpster, got " .. tostring(Fns.ClassifyLootSession("opened")))
            end
        end)
    end)
    if samples.containerID then
        probe("Classify: tracked container -> container", function()
            withRestoredState(function()
                V.lastContainerItemID = samples.containerID
                V.lastContainerItemTime = GetTime()
                Fns.ResetLootSession()
                if Fns.ClassifyLootSession("closed") ~= "container" then
                    error("expected container route")
                end
            end)
        end)
    else
        lineWarn("no containerDropDB entry — container classify skipped")
    end
    probe("Classify: LOOT_CLOSED fishing snapshot -> fishing", function()
        withRestoredState(function()
            RT.lootReady.wasFishing = true
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = {}
            if Fns.ClassifyLootSession("closed") ~= "fishing" then
                error("expected fishing route")
            end
        end)
    end)
    probe("LootSourcesLookLikeFishingOnly: known bobber", function()
        local bobberGUID = "Creature-0-0-0-0-124736-000000000000"
        if not Fns.LootSourcesLookLikeFishingOnly({ bobberGUID }) then
            error("expected true for known bobber GUID")
        end
    end)
    probe("LootSourcesLookLikeFishingOnly: unknown mob + GO not fishing", function()
        local mobGUID = "Creature-0-0-0-0-999001-000000000000"
        local goGUID = "GameObject-0-0-0-0-888888-000000000000"
        if Fns.LootSourcesLookLikeFishingOnly({ mobGUID, goGUID }) then
            error("expected false for unknown creature + GameObject")
        end
    end)
    probe("Classify: tracked rare NPC in fishable zone -> npc (not fishing)", function()
        withRestoredState(function()
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = { samples.rareNpcGUID or "Creature-0-0-0-0-230995-000000000000" }
            local route = Fns.ClassifyLootSession("opened")
            if route == "fishing" then
                error("tracked rare mob must not route to fishing")
            end
            if route ~= "npc" then
                error("expected npc route, got " .. tostring(route))
            end
        end)
    end)

    -- ── GUID / DB resolution ──────────────────────────────────────────
    section("Source DB match (object / rare / raid)")
    probe("MatchGuidExact: dumpster objectID", function()
        local drops, npcID, objectID = Fns.MatchGuidExact(samples.dumpsterGUID)
        if not drops or objectID ~= (samples.objectID or 469857) then
            error("dumpster not in objectDropDB")
        end
    end)
    probe("MatchGuidExact: rare NPC (Nitro)", function()
        local drops, npcID = Fns.MatchGuidExact(samples.rareNpcGUID)
        if not drops or npcID ~= (samples.rareNpcID or 230995) then
            error("Nitro rare not in npcDropDB")
        end
    end)
    probe("MatchGuidExact: raid boss NPC (Gallywix)", function()
        local drops, npcID = Fns.MatchGuidExact(samples.raidBossGUID)
        if not drops or npcID ~= (samples.raidBossNpcID or 241526) then
            error("Gallywix not in npcDropDB")
        end
    end)
    probe("LootSessionHasTrackedObjectSource(dumpster)", function()
        if not Fns.LootSessionHasTrackedObjectSource({ samples.dumpsterGUID }) then
            error("expected tracked object")
        end
    end)

    -- ── Deferred session finalize (miss / obtain) ─────────────────────
    section("Deferred loot session outcomes")
    probe("StageDeferred: earlyMissApplied +1 before finalize (npc)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "npc",
                trackable = { drop },
            })
            if not RT.pendingLootSessionFinalize then
                error("expected pending session")
            end
            if not RT.pendingLootSessionFinalize.earlyMissApplied then
                error("expected earlyMissApplied at loot open")
            end
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected +1 at loot open")
            end
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("finalize must not double-increment")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize npc: early miss announces at close (no double chat)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "npc",
                trackable = { drop },
            })
            if not RT.pendingLootSessionFinalize or not RT.pendingLootSessionFinalize.earlyMissApplied then
                error("expected earlyMissApplied before finalize")
            end
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            RT.lootSession.opened = true
            local captured
            local origTryChat = TC.TryChat
            TC.TryChat = function(msg)
                if type(msg) == "string" and msg:find("attempt", 1, true) then
                    captured = msg
                end
            end
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            Fns.FlushDeferredTryCounterIncrementAnnounces()
            TC.TryChat = origTryChat
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected single early increment count")
            end
            if not captured then
                error("expected increment announce after early miss finalize")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize npc: miss +1 (fake item)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "npc",
                trackable = { drop },
                baselineTryCounts = Fns.CaptureTryCountBaselines({ drop }),
            })
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected miss increment")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize container: miss +1 (fake item)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "container",
                trackable = { drop },
                containerItemID = samples.containerID or 0,
                baselineTryCounts = Fns.CaptureTryCountBaselines({ drop }),
            })
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected container miss increment")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize fishing: miss +1 (fake item)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "fishing",
                trackable = { drop },
                baselineTryCounts = Fns.CaptureTryCountBaselines({ drop }),
            })
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected fishing miss increment")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize slot_boss: miss +1 (fake item)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "slot_boss",
                trackable = { drop },
                drops = { drop },
                slotOutcomeSourceKey = "tc_self_test_slot",
                slotBossNpcID = samples.raidBossNpcID or 241526,
                baselineTryCounts = Fns.CaptureTryCountBaselines({ drop }),
            })
            RT.lootSession.numLoot = 1
            RT.lootSession.slotData[1] = { hasItem = true, link = "|Hitem:1:0|h[Junk]|h|r" }
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected slot_boss miss increment")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize slot_boss: miss +1 (hasItem, no link)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            local old = WN:GetTryCount("item", FAKE_ITEM_ID)
            Fns.StageDeferredLootSession({
                kind = "slot_boss",
                trackable = { drop },
                drops = { drop },
                slotOutcomeSourceKey = "tc_self_test_slot_nolink",
                slotBossNpcID = samples.raidBossNpcID or 241526,
                baselineTryCounts = Fns.CaptureTryCountBaselines({ drop }),
            })
            RT.lootSession.numLoot = 1
            RT.lootSession.slotData[1] = { hasItem = true, link = nil }
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                error("expected slot_boss miss increment without readable link")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, old)
        end)
    end)
    probe("Finalize npc: obtain resets repeatable (fake item)", function()
        withRestoredState(function()
            local drop = fakeDrop()
            WN:SetTryCount("item", FAKE_ITEM_ID, 7)
            Fns.StageDeferredLootSession({
                kind = "npc",
                trackable = { drop },
                baselineTryCounts = { ["item\0" .. tostring(FAKE_ITEM_ID)] = 7 },
            })
            RT.lootSession.numLoot = 1
            RT.lootSession.slotData[1] = { hasItem = true, link = fakeItemLink() }
            Fns.FinalizeDeferredLootSessionOutcome(WN)
            if WN:GetTryCount("item", FAKE_ITEM_ID) ~= 0 then
                error("expected reset after obtain")
            end
            if not Fns.IsObtainOutcomeApplied("item", FAKE_ITEM_ID, drop) then
                error("obtain outcome mark missing")
            end
            WN:SetTryCount("item", FAKE_ITEM_ID, 0)
        end)
    end)

    -- ── Live pipeline stubs (NPC rare / container / object) ───────────
    section("ProcessNPCLoot / container / currency fallback")
    probe("ProcessNPCLoot: rare defers until close (Nitro)", function()
        withRestoredState(function()
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = { samples.rareNpcGUID }
            RT.lootSession.numLoot = 0
            WN:ProcessNPCLoot("opened")
            if not RT.pendingLootSessionFinalize then
                error("expected deferred rare session")
            end
            Fns.ClearDeferredLootSession()
        end)
    end)
    probe("ProcessNPCLoot closed: single increment without open defer", function()
        withRestoredState(function()
            -- Cartel rare without lockout_quest; distinct GUID from Nitro opened probe above.
            local npcID = samples.closedRouteRareNpcID or 234480
            local npcGUID = samples.closedRouteRareNpcGUID or "Creature-0-0-0-0-234480-000000000000"
            local drops, matchNpc = Fns.MatchGuidExact(npcGUID)
            if not drops or matchNpc ~= npcID then
                error("closed-route NPC not in runtime npcDropDB")
            end
            local drop = drops[1]
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if not tryKey then return end
            local old = WN:GetTryCount(tcType, tryKey) or 0
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = { npcGUID }
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            RT.lootSession.opened = false
            WN:ProcessNPCLoot("closed")
            if (WN:GetTryCount(tcType, tryKey) or 0) ~= old + 1 then
                error("expected single closed-route increment")
            end
            WN:SetTryCount(tcType, tryKey, old)
        end)
    end)
    probe("Late LOOT_OPENED after closed route: no second increment", function()
        withRestoredState(function()
            local npcID = samples.closedRouteRareNpcID or 234480
            local npcGUID = samples.closedRouteRareNpcGUID or "Creature-0-0-0-0-234480-000000000000"
            local drops, matchNpc = Fns.MatchGuidExact(npcGUID)
            if not drops or matchNpc ~= npcID then
                error("closed-route NPC not in runtime npcDropDB")
            end
            local drop = drops[1]
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if not tryKey then return end
            local old = WN:GetTryCount(tcType, tryKey) or 0
            Fns.ResetLootSession()
            RT.lootSession.sourceGUIDs = { npcGUID }
            RT.lootSession.numLoot = 0
            wipe(RT.lootSession.slotData)
            RT.lootSession.opened = false
            WN:ProcessNPCLoot("closed")
            local afterClosed = WN:GetTryCount(tcType, tryKey) or 0
            if afterClosed ~= old + 1 then
                error("expected closed-route increment")
            end
            if not Fns.ShouldSkipLateLootOpenedRoute(false) then
                error("expected ShouldSkipLateLootOpenedRoute after closed route")
            end
            RT.lootSession.opened = false
            WN:OnTryCounterLootOpened("LOOT_OPENED", true, false)
            if (WN:GetTryCount(tcType, tryKey) or 0) ~= afterClosed then
                error("late LOOT_OPENED must not increment again")
            end
            WN:SetTryCount(tcType, tryKey, old)
        end)
    end)
    if samples.containerID then
        probe("ProcessContainerLoot: defers on opened", function()
            withRestoredState(function()
                V.lastContainerItemID = samples.containerID
                V.lastContainerItemTime = GetTime()
                Fns.ResetLootSession()
                WN:ProcessContainerLoot("opened")
                if not RT.pendingLootSessionFinalize then
                    error("expected deferred container session")
                end
                Fns.ClearDeferredLootSession()
            end)
        end)
    end
    probe("Currency fallback: tracked dumpster miss (fake via mechanica restore)", function()
        withRestoredState(function()
            Fns.ResetLootSession()
            if Fns.ClearTryCounterTransientKillMarks then
                Fns.ClearTryCounterTransientKillMarks()
            end
            local mechID = samples.mechanicaItemID or 234741
            local old = WN:GetTryCount("item", mechID)
            V.lastTrackedObjectInteractID = samples.objectID or 469857
            V.lastTrackedObjectInteractGUID = samples.dumpsterGUID
            V.lastTrackedObjectInteractTime = GetTime()
            V.lastTryCountSourceKey = nil
            V.lastTryCountSourceTime = 0
            Fns.TryProcessTrackedObjectCurrencyFallback(WN)
            if WN:GetTryCount("item", mechID) ~= old + 1 then
                error("expected mechanica miss from currency fallback")
            end
            WN:SetTryCount("item", mechID, old)
        end)
    end)

    -- ── Encounter / world boss bookkeeping ───────────────────────────
    section("Encounter & world boss handlers")
    probe("OnTryCounterEncounterStart(bogus)", function()
        WN:OnTryCounterEncounterStart("ENCOUNTER_START", 0, "Test", 0, 0)
    end)
    probe("OnTryCounterEncounterEnd(bogus)", function()
        WN:OnTryCounterEncounterEnd("ENCOUNTER_END", 0, "Test", 0, 0, 0)
    end)
    probe("OnTryCounterBossKill(bogus)", function()
        WN:OnTryCounterBossKill("BOSS_KILL", 0, "Test")
    end)
    probe("OnTryCounterLootReady/Closed (no loot)", function()
        withRestoredState(function()
            WN:OnTryCounterLootReady(false)
            WN:OnTryCounterLootClosed()
        end)
    end)

    -- ── CHAT_MSG_LOOT guards ──────────────────────────────────────────
    section("CHAT_MSG_LOOT paths")
    probe("CHAT: untracked junk item (early exit)", function()
        WN:OnTryCounterChatMsgLoot("CHAT_MSG_LOOT", "You receive loot: [Junk].", "Player", "")
    end)
    probe("ShouldDeferLootOutcomeUntilClose(opened)", function()
        if Fns.ShouldDeferLootOutcomeUntilClose("opened") ~= true then error("expected true") end
        if Fns.ShouldDeferLootOutcomeUntilClose("closed") ~= false then error("expected false") end
    end)

    -- ── Summary ───────────────────────────────────────────────────────
    if Fns.SetTryCounterSelfTestSyncMiss then
        Fns.SetTryCounterSelfTestSyncMiss(false)
    end
    if RT.tryCounterSelfTest then
        RT.tryCounterSelfTest.bypassAutoGate = false
    end
    if Fns.FlushDeferredTryCounterIncrementAnnounces then
        Fns.FlushDeferredTryCounterIncrementAnnounces()
    end
    WN:SetTryCount("item", FAKE_ITEM_ID, savedFakeCount or 0)
    WN:SetTryCount("item", mechID, savedMechCount or 0)

    if fail == 0 then
        WN:Print(format(
            "|cff00ff00[WN-TC-Test] OK|r %d passed, %d warnings. Routes: object, rare, container, fishing, raid, encounter, chat.",
            pass, warn))
    else
        WN:Print("|cffff0000[WN-TC-Test]|r Failed checks (recap):")
        for i = 1, #failedLabels do
            local entry = failedLabels[i]
            local tail = entry.err and (": " .. tostring(entry.err)) or ""
            WN:Print("|cffff0000[WN-TC-Test] FAIL|r " .. entry.label .. tail)
        end
        WN:Print(format("|cffff0000[WN-TC-Test] FAILED|r %d passed, %d failed, %d warnings.", pass, fail, warn))
    end
end

--- Mythic Sylvanas chest path only (/wn tc test sylvanas). No raid required.
function WarbandNexus:RunTryCounterSylvanasSelfTest()
    local WN = self
    if not Fns.EnsureDB() then
        WN:Print("|cffff0000[WN-TC-Test]|r DB not ready — aborting.")
        return
    end
    if not Fns.EnsureTryCounterRuntimeDbLoaded or not Fns.EnsureTryCounterRuntimeDbLoaded() then
        WN:Print("|cffff0000[WN-TC-Test]|r CollectibleSourceDB not loaded — aborting.")
        return
    end
    local savedFake = WN:GetTryCount("item", FAKE_ITEM_ID)
    if Fns.SetTryCounterSelfTestSyncMiss then
        Fns.SetTryCounterSelfTestSyncMiss(true)
    end

    runSelfTestHarness(WN, "Sylvanas Mythic chest probes (post-cinematic slot-first + pending replay)...", function(section, probe)
        section("Encounter bookkeeping")
        probe("ENCOUNTER_END seeds recentKill for Sylvanas (2435)", function()
            withRestoredState(function()
                WN:OnTryCounterEncounterEnd("ENCOUNTER_END", SYLVANAS_ENCOUNTER_ID, "Sylvanas Windrunner", 16, 20, 1)
                local _, kd = Fns.GetFreshEncounterKillForNpc(SYLVANAS_NPC_ID)
                if not kd or kd.npcID ~= SYLVANAS_NPC_ID then
                    error("recentKill missing for npc " .. tostring(SYLVANAS_NPC_ID))
                end
            end)
        end)

        section("Slot-first miss (chest after cinematic)")
        probe("slot_boss miss: hasItem, no link (Sylvanas npc 175732)", function()
            withRestoredState(function()
                local drop = fakeDrop()
                local old = WN:GetTryCount("item", FAKE_ITEM_ID)
                WN:OnTryCounterEncounterEnd("ENCOUNTER_END", SYLVANAS_ENCOUNTER_ID, "Sylvanas Windrunner", 16, 20, 1)
                Fns.StageDeferredLootSession({
                    kind = "slot_boss",
                    trackable = { drop },
                    drops = { drop },
                    slotOutcomeSourceKey = "encounter_" .. tostring(SYLVANAS_ENCOUNTER_ID),
                    slotBossNpcID = SYLVANAS_NPC_ID,
                    baselineTryCounts = Fns.CaptureTryCountBaselines({ drop }),
                })
                RT.lootSession.numLoot = 1
                RT.lootSession.slotData[1] = { hasItem = true, link = nil }
                Fns.FinalizeDeferredLootSessionOutcome(WN)
                if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                    error("expected miss increment after cinematic-style chest")
                end
                WN:SetTryCount("item", FAKE_ITEM_ID, old)
            end)
        end)

        section("Chest before ENCOUNTER_END (pending replay)")
        probe("TryReplayPendingEncounterLoot after ENCOUNTER_END", function()
            withRestoredState(function()
                local drop = fakeDrop()
                local old = WN:GetTryCount("item", FAKE_ITEM_ID)
                if Fns.SetTryCounterSelfTestSlotOutcomeEnv then
                    Fns.SetTryCounterSelfTestSlotOutcomeEnv({
                        instance = { instanceType = "raid", difficulty = 16, templateInstanceID = 1193 },
                        bossTrackable = { [SYLVANAS_NPC_ID] = { drop } },
                    })
                end
                Fns.ResetLootSession()
                RT.lootSession.numLoot = 1
                RT.lootSession.slotData[1] = { hasItem = true, link = nil }
                RT.lootSession.sourceGUIDs = { "GameObject-0-0-0-0-" .. tostring(SYLVANAS_CHEST_OBJECT_ID) .. "-000000000001" }
                RT.pendingEncounterLootSnapshot = Fns.SnapshotLootSessionState()
                WN._pendingEncounterLoot = true
                WN:OnTryCounterEncounterEnd("ENCOUNTER_END", SYLVANAS_ENCOUNTER_ID, "Sylvanas Windrunner", 16, 20, 1)
                if not Fns.TryReplayPendingEncounterLoot then
                    error("TryReplayPendingEncounterLoot missing")
                end
                Fns.TryReplayPendingEncounterLoot(WN)
                if Fns.SetTryCounterSelfTestSlotOutcomeEnv then
                    Fns.SetTryCounterSelfTestSlotOutcomeEnv(nil)
                end
                if WN:GetTryCount("item", FAKE_ITEM_ID) ~= old + 1 then
                    error("expected replay miss increment")
                end
                WN:SetTryCount("item", FAKE_ITEM_ID, old)
            end)
        end)
    end)

    if Fns.SetTryCounterSelfTestSyncMiss then
        Fns.SetTryCounterSelfTestSyncMiss(false)
    end
    if Fns.FlushDeferredTryCounterIncrementAnnounces then
        Fns.FlushDeferredTryCounterIncrementAnnounces()
    end
    WN:SetTryCount("item", FAKE_ITEM_ID, savedFake or 0)
end
