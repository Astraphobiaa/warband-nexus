#!/usr/bin/env lua5.1
--[[
    Try Counter fishing regression, driven through the REAL shipped files.

    Covers the three ways a fishing cast reaches the counter, plus the two book-keeping
    bugs that made counts and chat lines go missing:

      1. A cast with fishing evidence must produce exactly one attempt and one chat line,
         under a normal loot window AND under fast auto-loot (no LOOT_OPENED).
      2. tryCountReflectsTo must land the count on the collectible that owns it
         (Nether-Warped Egg tries -> the drake's mount key, not the item key).
      3. A one-time catch must NOT reset its counter (v3.5.2) - the frozen
         "tries to obtain" total is the number the UI exists to show.
      4. RT.pendingIncrementAnnounces must stay the live queue across a flush.
      5. A bobber creature id confirmed by IsFishingLoot() must persist to SavedVariables,
         so the structural (no-API) route recognises it after a reload.

    Each phase runs in its own harness section; state that must not bleed is asserted, not assumed.
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, WN, Fns, RT, TC = H.stub, H.WN, H.Fns, H.RT, H.TC

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

-- Nether-Warped Egg (fished in Midnight zones) reflects its try count onto the drake.
local EGG_ITEM_ID  = 268730
local DRAKE_MOUNT  = 260916
local VOIDSTORM    = 2405
local BOBBER_GUID  = "Creature-0-0-0-0-124736-000000000000"   -- shipped known bobber

local function Count() return WN:GetTryCount("mount", DRAKE_MOUNT) or 0 end

---One fishing cast. `catch` is the itemID pulled up; `fastAutoLoot` skips LOOT_OPENED.
local function Cast(catch, fastAutoLoot)
    stub.Reset()
    stub.world.mapID = VOIDSTORM
    stub.world.isFishingLoot = true
    stub.world.lootSlots = {
        { hasItem = true, link = "|Hitem:" .. catch .. "::::::::::::::::|h[Catch]|h" },
    }
    stub.world.lootSources = { { BOBBER_GUID, 1 } }

    stub.Fire("LOOT_READY", true)
    if not fastAutoLoot then
        stub.Fire("LOOT_OPENED", true, false)
        stub.Advance(0.05)   -- ScheduleLootRouteProcessor defers one frame
    end
    stub.Fire("LOOT_CLOSED")
    stub.Advance(5)          -- miss-increment job + increment-announce flush debounce
    return #stub.chat, table.concat(stub.chat, "\n")
end

local JUNK = 6303

print("phase 1: zone is trackable and the drop is wired")
check(Fns.IsInTrackableFishingZone(), "Voidstorm (2405) is a trackable fishing zone")
check(#Fns.CollectFishingDropsForZone() > 0, "zone yields at least one fishing drop")

print("phase 2: misses count and announce, window and fast-auto-loot alike")
local n1 = Cast(JUNK, false)
check(Count() == 1, "normal loot window: count 0 -> 1 (got " .. Count() .. ")")
check(n1 == 1, "normal loot window: exactly one chat line (got " .. n1 .. ")")

local n2 = Cast(JUNK, true)
check(Count() == 2, "fast auto-loot: count 1 -> 2 (got " .. Count() .. ")")
check(n2 == 1, "fast auto-loot: exactly one chat line (got " .. n2 .. ")")

Cast(JUNK, false)
check(Count() == 3, "third cast: count 3 (got " .. Count() .. ")")

print("phase 3: tryCountReflectsTo keys the count on the owning collectible")
check((WN.db.global.tryCounts.mount or {})[DRAKE_MOUNT] == 3,
      "tries persisted under tryCounts.mount[" .. DRAKE_MOUNT .. "]")
check((WN:GetTryCount("item", EGG_ITEM_ID) or 0) == 0,
      "no stray count under the source item key")

print("phase 4: a one-time catch keeps its total (v3.5.2)")
local nCatch, catchText = Cast(EGG_ITEM_ID, false)
check(nCatch == 1, "catch announces exactly one line (got " .. nCatch .. ")")
check(catchText:find("4 attempts", 1, true) ~= nil,
      "catch line reports the 4th attempt")
check(Count() == 4, "one-time catch does NOT zero the counter (got " .. Count() .. ")")
check(catchText:find("counter reset", 1, true) == nil,
      "catch line does not claim a reset that did not happen")

print("phase 5: RT.pendingIncrementAnnounces stays the live queue across a flush")
local queueBefore = RT.pendingIncrementAnnounces
RT.lootSession.opened = true
Fns.RunOrDeferTryCounterIncrementAnnounce(function() end)
check(#RT.pendingIncrementAnnounces == 1, "queued line is visible through RT")
RT.lootSession.opened = false
Fns.FlushDeferredTryCounterIncrementAnnounces()
check(#RT.pendingIncrementAnnounces == 0, "RT sees the queue drained after flush")
check(RT.pendingIncrementAnnounces == queueBefore, "RT alias still points at the live table")
RT.lootSession.opened = true
Fns.RunOrDeferTryCounterIncrementAnnounce(function() end)
check(#RT.pendingIncrementAnnounces == 1, "RT sees lines queued after a flush")
RT.lootSession.opened = false
Fns.FlushDeferredTryCounterIncrementAnnounces()

print("phase 6: a confirmed bobber id persists across a reload")
local NEW_BOBBER = 999001   -- deliberately outside the shipped 3-entry allowlist
local NEW_GUID = "Creature-0-0-0-0-" .. NEW_BOBBER .. "-000000000000"
check(not Fns.IsFishingBobberNpcId(NEW_BOBBER), "unknown bobber starts unknown")

stub.Reset()
stub.world.isFishingLoot = true
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:" .. JUNK .. "::::::::::::::::|h[Junk]|h" } }
stub.world.lootSources = { { NEW_GUID, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(0.05)
stub.Fire("LOOT_CLOSED")
stub.Advance(5)

check(Fns.IsFishingBobberNpcId(NEW_BOBBER), "IsFishingLoot()-confirmed cast learns the bobber id")
check((WN.db.global.discoveredFishingBobbers or {})[NEW_BOBBER] == true,
      "learned bobber id is written to SavedVariables")

-- Reload: runtime allowlist back to shipped state, then re-merge from the DB.
for k in pairs(TC.FISHING_BOBBER_NPC_IDS) do TC.FISHING_BOBBER_NPC_IDS[k] = nil end
TC.FISHING_BOBBER_NPC_IDS[124736] = true
TC.FISHING_BOBBER_NPC_IDS[35591] = true
TC.FISHING_BOBBER_NPC_IDS[216204] = true
check(not Fns.IsFishingBobberNpcId(NEW_BOBBER), "reload clears the runtime allowlist")
Fns.MergeDiscoveredFishingBobbers()
check(Fns.IsFishingBobberNpcId(NEW_BOBBER), "reload merge restores the learned bobber id")
check(Fns.LootSourcesLookLikeFishingOnly({ NEW_GUID }),
      "structural route now classifies that bobber without IsFishingLoot()")

-- Persisting the allowlist makes a wrong entry permanent, so a tracked rare must never get in:
-- learning one would break that rare's own try counting across every future reload.
local TRACKED_RARE = 137202   -- Goldenmane: in npcDropDB and loot-path eligible
Fns.RememberFishingBobberNpcId(TRACKED_RARE)
check(not Fns.IsFishingBobberNpcId(TRACKED_RARE), "a tracked rare is refused as a bobber")
check((WN.db.global.discoveredFishingBobbers or {})[TRACKED_RARE] == nil,
      "a tracked rare is never persisted as a bobber")

print("phase 6b: the GameObject bobber is learned, persisted and then recognised")
-- The live bobber is GAMEOBJECT_TYPE_FISHINGNODE (17), so GetLootSourceInfo reports fishing loot as
-- a GameObject GUID. The learn loop used to scan only "^Creature", so nothing was ever learned and
-- LootSourcesLookLikeFishingOnly rejected every real fishing session (GameObject-only => false).
local NODE_OBJ = 888001
local NODE_GUID = "GameObject-0-0-0-0-" .. NODE_OBJ .. "-000000000000"
check(not Fns.IsFishingBobberObjectId(NODE_OBJ), "fishing-node object starts unknown")
check(not Fns.LootSourcesLookLikeFishingOnly({ NODE_GUID }),
      "unknown GameObject alone is NOT treated as fishing (herb/ore stay safe)")

stub.Reset()
stub.world.mapID = VOIDSTORM
stub.world.isFishingLoot = true
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:" .. JUNK .. "::::::::::::::::|h[Junk]|h" } }
stub.world.lootSources = { { NODE_GUID, 1 } }
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(0.05)
stub.Fire("LOOT_CLOSED")
stub.Advance(5)

check(Fns.IsFishingBobberObjectId(NODE_OBJ), "confirmed cast learns the GameObject bobber id")
check((WN.db.global.discoveredFishingBobberObjects or {})[NODE_OBJ] == true,
      "learned fishing-node object id is written to SavedVariables")

stub.world.isFishingLoot = false
check(Fns.LootSourcesLookLikeFishingOnly({ NODE_GUID }),
      "once learned, the GameObject bobber classifies without IsFishingLoot()")

-- Same poisoning guard as the creature side: a tracked object owns its own route.
local TRACKED_OBJ = 469857   -- Overflowing Dumpster
Fns.RememberFishingBobberObjectId(TRACKED_OBJ)
check(not Fns.IsFishingBobberObjectId(TRACKED_OBJ), "a tracked object is refused as a bobber")

print("phase 6c: the fishing spell icon probe matches the live icon id")
-- SpellMisc.SpellIconFileDataID on 12.1.0.69299: spells 7620 / 131474 / 1281823 all report 4620674.
-- The probe used to compare against 136245 only, so any fishing spell outside the hardcoded list
-- was cached as NOT fishing forever and never armed the cast context.
check(TC.FISHING_SPELL_ICON_IDS[4620674] == true, "live 12.1 fishing icon id is accepted")
check(TC.FISHING_SPELL_ICON_IDS[136245] == true, "legacy icon id still accepted for older clients")

print("phase 7: every Midnight fishing sub-zone resolves to the drop")
-- Parent chains are the real UiMap.db2 ones (see wow_stub.M.uiMapParents). A zone that stops
-- resolving here goes completely silent in game: no count, no chat, no error.
local function ZoneResolves(mapID)
    stub.world.mapID = mapID
    return Fns.IsInTrackableFishingZone() and #Fns.CollectFishingDropsForZone() > 0
end
for _, z in ipairs({
    { 2395, "Eversong Woods" },   { 2405, "Voidstorm" },
    { 2413, "Harandar" },         { 2437, "Zul'Aman" },
    { 2444, "Slayer's Rise" },    { 2393, "Silvermoon City (sub)" },
    { 2424, "Isle of Quel'Danas (parent is 2537)" },
    { 2541, "Arcantina (parent is 2537)" },
    { 2536, "Atal'Aman (sub)" },  { 2576, "The Den (sub)" },
}) do
    check(ZoneResolves(z[1]), ("map %d %s is trackable"):format(z[1], z[2]))
end
-- Coiled Isle is intentionally out: 12.1 fishing rewards there are vendor/questline, not RNG drops.
check(not ZoneResolves(2512), "The Coiled Isle (2512) stays untracked until an RNG drop is confirmed")
stub.world.mapID = VOIDSTORM

print("phase 8: cast context alone classifies as fishing, but a corpse still wins")
local function ClassifyWithCast(sources, mouseoverCorpse)
    Fns.ResetLootSession()
    RT.fishingCtx.active = true
    RT.fishingCtx.castTime = _G.GetTime()
    RT.lootSession.sourceGUIDs = sources
    RT.lootSession.mouseoverGUID = mouseoverCorpse
    stub.world.isFishingLoot = false
    return Fns.ClassifyLootSession("opened")
end
check(ClassifyWithCast({}, nil) == "fishing",
      "cast + fishable zone + NO loot sources -> fishing (was silent before)")
check(ClassifyWithCast({}, "Creature-0-0-0-0-246332-000000000000") == "npc",
      "a tracked mob corpse on mouseover still routes to npc, not fishing")
-- The trigger is restricted to empty sources on purpose: with a corpse in the source list the cast
-- context must not win, or fishing near mobs starts counting kills as casts.
check(ClassifyWithCast({ "Creature-0-0-0-0-777777-000000000000" }, nil) ~= "fishing",
      "cast context does not claim a session that has a creature source")
RT.fishingCtx.active = false

print("phase 9: no errors escaped any handler or timer")
for i = 1, #stub.errors do print("  error: " .. tostring(stub.errors[i])) end
check(#stub.errors == 0, "no runtime errors")

if failures > 0 then
    io.stderr:write(("\ntest_try_counter_fishing: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_try_counter_fishing: all checks passed")
