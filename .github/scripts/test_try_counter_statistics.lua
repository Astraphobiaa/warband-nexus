#!/usr/bin/env lua5.1
--[[
    Try Counter statistics path, driven through the REAL shipped files.

    This path was completely unexercised before: GetStatistic answered nil unconditionally in the
    stub, so every suite made ZERO calls to it while 57 statistic-backed counter buckets existed.
    That is also the code v3.5.2 changed most (the "already warm" shortcut was removed, the runtime
    reseed stopped being instance-only, and a repeatable early-return was added), so it shipped in
    3.5.3 with no automated coverage at all.

    Raid and dungeon boss attempts come from here, not from loot: GetStatistic carries the lifetime
    kill count, and the counter is seeded from it so attempts made before the addon was installed
    still show up.

    GetStatistic(category) returns a STRING or nil (warcraft.wiki.gg/wiki/API_GetStatistic).
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

-- Antoran Charhound (Felhounds of Sargeras, npc 126916): four kill statistics feed one mount.
local STAT_IDS = { 11957, 11958, 11959, 12118 }
local MOUNT = 152816

local function Seed()
    Fns.InvalidateMergedStatisticSeedIndex()
    Fns.EnsureMergedStatisticSeedIndex()
    local ok, err = pcall(Fns.SeedFromStatistics, { pruneOrphans = false })
    stub.Advance(40)
    return ok, err
end

print("phase 1: the statistics path is actually reachable")
check(Fns.IsTryCounterReady and Fns.IsTryCounterReady(), "try counter reports ready")
check(#(RT.mergedStatSeedGroupList or {}) > 0,
      ("statistic seed index built (%d buckets)"):format(#(RT.mergedStatSeedGroupList or {})))

stub.ClearStatistics()
local ok = Seed()
check(ok, "seed runs with no statistics available")
check(stub.statCalls > 0, ("GetStatistic is consulted (%d calls)"):format(stub.statCalls))

print("phase 2: readable statistics seed the counter")
stub.ClearStatistics()
WN:SetTryCount("mount", MOUNT, 0)
stub.SetStatistic(11957, 7)
stub.SetStatistic(12118, 5)
check(Seed(), "seed runs with statistics present")
check((WN:GetTryCount("mount", MOUNT) or 0) == 12,
      ("kill statistics sum onto the counter: 7 + 5 = 12 (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

print("phase 3: the value is read as a string, the way the API returns it")
stub.ClearStatistics()
WN:SetTryCount("mount", MOUNT, 0)
stub.SetStatistic(11957, "1,234")   -- in-game display formatting
check(Seed(), "seed runs with a formatted value")
check((WN:GetTryCount("mount", MOUNT) or 0) == 1234,
      ("thousands separator is stripped, not truncated (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

print("phase 4: statistics never lower a local count")
-- The overlay takes the max. A local count earned from loot must survive a smaller statistic,
-- otherwise a fresh character's zero would wipe the account total.
stub.ClearStatistics()
WN:SetTryCount("mount", MOUNT, 40)
stub.SetStatistic(11957, 3)
check(Seed(), "seed runs")
check((WN:GetTryCount("mount", MOUNT) or 0) == 40,
      ("a smaller statistic does not lower the counter (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

print("phase 5: an unreadable statistic does not zero anything")
-- GetStatistic can return nil or a non-numeric placeholder. Neither may be treated as "0 kills".
stub.ClearStatistics()
WN:SetTryCount("mount", MOUNT, 25)
check(Seed(), "seed runs with every statistic unreadable")
check((WN:GetTryCount("mount", MOUNT) or 0) == 25,
      ("nil statistics leave the counter alone (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

stub.ClearStatistics()
stub.SetStatistic(11957, "--")
check(Seed(), "seed runs with a placeholder value")
check((WN:GetTryCount("mount", MOUNT) or 0) == 25,
      ("a non-numeric placeholder leaves the counter alone (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

print("phase 6: a secret statistic value is refused, not coerced")
-- Midnight can hand back secret values; tonumber() on one is a hard error, so the guard must hold.
stub.ClearStatistics()
WN:SetTryCount("mount", MOUNT, 25)
stub.SetStatistic(11957, stub.MarkSecret("999"))
local okSecret = Seed()
check(okSecret, "seed survives a secret statistic value")
check((WN:GetTryCount("mount", MOUNT) or 0) == 25,
      ("a secret value is not applied (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))
check(#stub.errors == 0, "no error raised handling a secret statistic")
stub.ClearSecrets()

print("phase 7: ApplyTryCountFromStatisticTotals honours the v3.5.2 guards")
-- hadReadable=false must be a no-op: that is what stops a failed read from writing anything.
WN:SetTryCount("mount", MOUNT, 30)
check(Fns.ApplyTryCountFromStatisticTotals("mount", MOUNT, 500, false) == false,
      "hadReadable=false applies nothing")
check((WN:GetTryCount("mount", MOUNT) or 0) == 30, "counter untouched when the read failed")
check(Fns.ApplyTryCountFromStatisticTotals("mount", MOUNT, 500, true) == true,
      "hadReadable=true with a higher total applies")
check((WN:GetTryCount("mount", MOUNT) or 0) == 500, "counter raised to the statistic total")

-- Repeatable drops reset to 0 on obtain while the statistic keeps its lifetime total, so applying
-- it would resurrect the count the reset just cleared (the v3.5.2 early-return).
local repeatableKey, repeatableType
for _, b in ipairs(RT.mergedStatSeedGroupList or {}) do
    if WN:IsRepeatableCollectible(b.tcType, b.tryKey) then
        repeatableType, repeatableKey = b.tcType, b.tryKey
        break
    end
end
if repeatableKey then
    WN:SetTryCount(repeatableType, repeatableKey, 0)
    check(Fns.ApplyTryCountFromStatisticTotals(repeatableType, repeatableKey, 900, true) == false,
          "a repeatable collectible refuses the statistic overlay")
    check((WN:GetTryCount(repeatableType, repeatableKey) or 0) == 0,
          "the repeatable counter stays at the value the reset left")
else
    print("  info no shipped drop is both repeatable and statistic-backed - guard not exercised")
end

print("phase 8: the runtime reseed (v3.5.2, no longer instance-only) applies the delta once")
-- v3.5.2 dropped the IsRaidOrDungeonInstance() gate here so an open-world rare's kill statistic
-- lands immediately instead of waiting for the next login pass. The risk that change carries is
-- double counting: the loot path already added +1 manually. Statistics are absolute, and the
-- overlay takes the max, so a reseed must converge on the statistic rather than stack on top.
local NPC = 126916
stub.ClearStatistics()
stub.ClearSecrets()
WN:SetTryCount("mount", MOUNT, 0)

stub.SetStatistic(11957, 10)
Fns.MarkNpcForRuntimeStatReseed(NPC, nil)
local didReseed = Fns.ReseedStatisticsForPendingRuntimeNpcs({ immediateAnnounce = true })
stub.Advance(5)
check(didReseed ~= false or (WN:GetTryCount("mount", MOUNT) or 0) == 10,
      "an open-world reseed runs outside an instance at all")
check((WN:GetTryCount("mount", MOUNT) or 0) == 10,
      ("reseed applies the statistic total (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

-- Reseed again with the statistic unchanged: must be idempotent, not +10 again.
Fns.MarkNpcForRuntimeStatReseed(NPC, nil)
Fns.ReseedStatisticsForPendingRuntimeNpcs({ immediateAnnounce = true })
stub.Advance(5)
check((WN:GetTryCount("mount", MOUNT) or 0) == 10,
      ("a repeat reseed does not stack (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

-- A manual loot +1 followed by a reseed must not end up at 12: the statistic is the truth.
WN:AddTryCountDelta("mount", MOUNT, 1)
check((WN:GetTryCount("mount", MOUNT) or 0) == 11, "loot path adds its manual +1")
stub.SetStatistic(11957, 11)
Fns.MarkNpcForRuntimeStatReseed(NPC, nil)
Fns.ReseedStatisticsForPendingRuntimeNpcs({ immediateAnnounce = true })
stub.Advance(5)
check((WN:GetTryCount("mount", MOUNT) or 0) == 11,
      ("manual +1 then reseed converges on the statistic, not 12 (got %d)"):format(WN:GetTryCount("mount", MOUNT) or 0))

print("phase 9: no errors escaped any handler or timer")
for i = 1, #stub.errors do print("  error: " .. tostring(stub.errors[i])) end
check(#stub.errors == 0, "no runtime errors")

if failures > 0 then
    io.stderr:write(("\ntest_try_counter_statistics: %d failure(s)\n"):format(failures))
    os.exit(1)
end
print("\ntest_try_counter_statistics: all checks passed")
