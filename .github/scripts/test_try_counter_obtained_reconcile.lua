#!/usr/bin/env lua5.1
--[[
    Try Counter obtained-latch reconciliation, driven through the REAL shipped files.

    Regression for github issue #76: the Try Counter kept incrementing Nether-Warped Egg
    attempts forever after the egg had already been obtained.

    Why the latch is the only thing that can stop it: the egg incubates for 7 days, so
    C_MountJournal keeps reporting the Nether-Warped Drake as uncollected the whole time.
    IsCollectibleCollected therefore has nothing to go on except tryCounts.obtained.

    Why the latch went missing: it is written only from the live loot routes. Fast auto-loot
    closes the window before the slot scan, the egg can be looted on another character, or
    looted before the addon was ever installed - and there was no way back. This test pins
    the way back: reconciling the latch against what the player actually holds.

    Runs on its own harness on purpose. The shared fishing test catches the egg in phase 4,
    which freezes the counter by design (v3.5.2), and a frozen counter makes "the count did
    not move" pass for the wrong reason.
]]

local H = dofile(".github/scripts/wow_addon_harness.lua")
local stub, WN, Fns, RT = H.stub, H.WN, H.Fns, H.RT

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local EGG_ITEM_ID = 268730
local DRAKE_MOUNT = 260916
local VOIDSTORM   = 2405
local BOBBER_GUID = "Creature-0-0-0-0-124736-000000000000"
local JUNK        = 6303

local function Count() return WN:GetTryCount("mount", DRAKE_MOUNT) or 0 end

---One fishing cast that pulls up `catch`.
local function Cast(catch)
    stub.Reset()
    stub.world.mapID = VOIDSTORM
    stub.world.isFishingLoot = true
    stub.world.lootSlots = {
        { hasItem = true, link = "|Hitem:" .. catch .. "::::::::::::::::|h[Catch]|h" },
    }
    stub.world.lootSources = { { BOBBER_GUID, 1 } }

    stub.Fire("LOOT_READY", true)
    stub.Fire("LOOT_OPENED", true, false)
    stub.Advance(0.05)   -- ScheduleLootRouteProcessor defers one frame
    stub.Fire("LOOT_CLOSED")
    stub.Advance(5)      -- miss-increment job + increment-announce flush debounce
end

print("phase 1: the egg is registered as a delayed-yield candidate")
check(Fns.delayedYieldItemIDs[EGG_ITEM_ID] == true,
      "IndexDrop collected the egg (it declares yields and is not repeatable)")
check(not Fns.IsItemMarkedObtained(EGG_ITEM_ID),
      "nothing is latched before the player holds anything")

print("phase 2: control - nothing held, the counter still moves")
Cast(JUNK)
check(Count() == 1, "first cast counts (got " .. Count() .. ")")
Cast(JUNK)
check(Count() == 2, "second cast counts (got " .. Count() .. ")")
check(not Fns.IsItemMarkedObtained(EGG_ITEM_ID),
      "an empty inventory latches nothing")

print("phase 3: the egg is in the bags but no loot route ever latched it")
stub.world.bagCounts[EGG_ITEM_ID] = 1
RT.lastObtainedReconcile = 0   -- the sweep is throttled; this is the next allowed window
local before = Count()
Cast(JUNK)
check(Count() == before,
      "the cast no longer counts a miss (was " .. before .. ", got " .. Count() .. ")")
check(Fns.IsItemMarkedObtained(EGG_ITEM_ID),
      "the sweep latched `obtained`")
check(Fns.delayedYieldItemIDs[EGG_ITEM_ID] == nil,
      "a latched item leaves the candidate set, so later checks cost nothing")

print("phase 4: the latch survives the item leaving the bags")
-- Hatched, sold, or moved somewhere GetItemCount cannot see: the latch is what the UI's
-- frozen "tries to obtain" total hangs on, so it must not un-latch.
stub.world.bagCounts[EGG_ITEM_ID] = nil
RT.lastObtainedReconcile = 0
before = Count()
Cast(JUNK)
check(Count() == before, "still no miss after the egg leaves the bags (got " .. Count() .. ")")
check(Fns.IsItemMarkedObtained(EGG_ITEM_ID), "`obtained` is not revoked")

print("phase 5: a manual ClearItemObtained is not undone by the next sweep")
-- RebuildTrackDB refills the candidate set from scratch (custom tracking edits do this), so
-- an opt-out that lived only in the candidate set would be silently reverted on the next sweep.
WN:ClearItemObtained(EGG_ITEM_ID)
check(not Fns.IsItemMarkedObtained(EGG_ITEM_ID), "the manual clear takes effect")
Fns.delayedYieldItemIDs[EGG_ITEM_ID] = true      -- what a RebuildTrackDB would put back
stub.world.bagCounts[EGG_ITEM_ID] = 1            -- and the egg is still sitting in the bags
RT.lastObtainedReconcile = 0
Fns.ReconcileObtainedFromInventory()
check(not Fns.IsItemMarkedObtained(EGG_ITEM_ID),
      "the sweep respects the opt-out instead of re-latching from the bags")
before = Count()
Cast(JUNK)
check(Count() == before + 1, "after the manual clear the cast counts again (got " .. Count() .. ")")
stub.world.bagCounts[EGG_ITEM_ID] = nil

print("phase 6: the sweep is throttled, not run per drop check")
RT.lastObtainedReconcile = 0
Fns.delayedYieldItemIDs[999001] = true          -- a candidate that is never held
stub.world.bagCounts[999001] = nil
Fns.MaybeReconcileObtainedFromInventory()
local stamp = RT.lastObtainedReconcile
check(stamp > 0, "a sweep stamps its run time")
Fns.MaybeReconcileObtainedFromInventory()
check(RT.lastObtainedReconcile == stamp,
      "a second sweep inside the interval is skipped, not repeated")
Fns.delayedYieldItemIDs[999001] = nil

print("phase 7: no errors escaped any handler or timer")
for i = 1, #stub.errors do print("  error: " .. tostring(stub.errors[i])) end
check(#stub.errors == 0, "no runtime errors")

if failures > 0 then
    io.stderr:write(("\ntest_try_counter_obtained_reconcile: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_try_counter_obtained_reconcile: all checks passed")
