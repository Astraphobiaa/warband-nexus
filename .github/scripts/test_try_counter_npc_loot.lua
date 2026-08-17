#!/usr/bin/env lua5.1
--[[
    Try Counter NPC-loot regression, driven through the REAL shipped files.

    The bug this pins down: ShouldSkipLateLootOpenedRoute suppressed a LOOT_OPENED route on
    "npc_<id> committed within 10s" alone, with no corpse identity. Farming one rare meant every
    kill that showed a loot window inside that window was dropped -- and since LOOT_OPENED had
    already set lootSession.opened, the LOOT_CLOSED fallback route did not run either, so the
    attempt disappeared silently. Roughly half of a back-to-back farm was lost.

    The guard still has a real job (fast auto-loot can run the closed route BEFORE LOOT_OPENED for
    the same corpse, and that late LOOT_OPENED must not count twice), so both directions are
    asserted here: distinct corpses always count, the same corpse never counts twice.
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

-- Goldenmane's Reins: repeatable world-rare farm mount, no lockout quest, no statisticIds,
-- so it is eligible for the plain loot-window path (BuildTryCounterNpcEligible).
local NPC, ITEM = 137202, 163573

check(RT.npcDropDB[NPC] ~= nil, "test NPC is in npcDropDB")
check(RT.tryCounterNpcEligible[NPC] == true, "test NPC is loot-path eligible")

local function Count()
    local drops = RT.npcDropDB[NPC]
    for i = 1, #drops do
        if drops[i].itemID == ITEM then
            local t, k = Fns.GetTryCountTypeAndKey(drops[i])
            return WN:GetTryCount(t, k) or 0
        end
    end
    return -1
end

local corpseSeq = 0
local function NewCorpse()
    corpseSeq = corpseSeq + 1
    return ("Creature-0-0-0-0-%d-%012d"):format(NPC, corpseSeq)
end

---Loot one corpse. `openedRoute` shows a loot window; otherwise fast auto-loot.
---Returns the delta this loot produced.
local function Loot(guid, openedRoute, gap)
    stub.Advance(gap or 0)
    stub.Reset()
    stub.world.mapID = 1527
    stub.world.isFishingLoot = false
    stub.world.lootSlots = { { hasItem = true, link = "|Hitem:2589::::::::::::::::|h[Linen]|h" } }
    stub.world.lootSources = { { guid, 1 } }
    local before = Count()
    stub.Fire("LOOT_READY", true)
    if openedRoute then
        stub.Fire("LOOT_OPENED", true, false)
        stub.Advance(0.05)
    end
    stub.Fire("LOOT_CLOSED")
    stub.Advance(3)
    return Count() - before
end

print("phase 1: a single kill counts once")
check(Loot(NewCorpse(), true) == 1, "loot window: +1")
check(Loot(NewCorpse(), false, 15) == 1, "fast auto-loot: +1")

print("phase 2: farming one rare inside the 10s window loses nothing")
-- Every corpse is distinct; only the npcID and the timing repeat. This is the regression.
local lost = 0
for i = 1, 6 do
    local viaWindow = (i % 2 == 0)   -- alternate the two loot shapes
    if Loot(NewCorpse(), viaWindow, 3) ~= 1 then lost = lost + 1 end
end
check(lost == 0, ("6 back-to-back kills 3s apart all counted (%d lost)"):format(lost))

lost = 0
for i = 1, 4 do
    if Loot(NewCorpse(), true, 2) ~= 1 then lost = lost + 1 end
end
check(lost == 0, ("4 consecutive loot-window kills 2s apart all counted (%d lost)"):format(lost))

print("phase 3: the same corpse still never counts twice")
-- Fast auto-loot can run the closed route before LOOT_OPENED arrives for that same corpse.
local sameCorpse = NewCorpse()
stub.Advance(15)
check(Loot(sameCorpse, false) == 1, "first pass over the corpse counts")

stub.Reset()
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:2589::::::::::::::::|h[Linen]|h" } }
stub.world.lootSources = { { sameCorpse, 1 } }
local before = Count()
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)   -- late LOOT_OPENED for the corpse just committed
stub.Advance(0.05)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)
check(Count() - before == 0, "late LOOT_OPENED on the SAME corpse does not double count")

-- Reopening the same corpse later (partial loot, close, reopen) must also stay at one attempt.
check(Loot(sameCorpse, true, 15) == 0, "reopening the same corpse after the window does not recount")

print("phase 4: a secret corpse GUID falls back to suppressing, never to double counting")
-- Midnight can hand back secret GUIDs, and then the corpse identities cannot be compared at all.
-- The fix must fail CLOSED there (suppress a possible duplicate) rather than fail open and count
-- twice. Without a controllable issecretvalue stub this branch never ran in any suite.
stub.Advance(15)
local secretCorpse = NewCorpse()
check(Loot(secretCorpse, false) == 1, "baseline: the kill counts while GUIDs are readable")

stub.Reset()
stub.world.lootSlots = { { hasItem = true, link = "|Hitem:2589::::::::::::::::|h[Linen]|h" } }
stub.world.lootSources = { { stub.MarkSecret(NewCorpse()), 1 } }
local beforeSecret = Count()
stub.Fire("LOOT_READY", true)
stub.Fire("LOOT_OPENED", true, false)
stub.Advance(0.05)
stub.Fire("LOOT_CLOSED")
stub.Advance(3)
check(Count() - beforeSecret == 0,
      "an unreadable (secret) corpse GUID inside the window is suppressed, not counted twice")
check(#stub.errors == 0, "no error raised while handling a secret GUID")
stub.ClearSecrets()

-- Outside the window the secret case must not block a legitimate kill forever.
stub.Advance(20)
check(Loot(NewCorpse(), false) == 1, "after the window, counting resumes normally")

print("phase 5: no errors escaped any handler or timer")
for i = 1, #stub.errors do print("  error: " .. tostring(stub.errors[i])) end
check(#stub.errors == 0, "no runtime errors")

if failures > 0 then
    io.stderr:write(("\ntest_try_counter_npc_loot: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_try_counter_npc_loot: all checks passed")
