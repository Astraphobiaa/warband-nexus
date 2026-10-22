#!/usr/bin/env lua
--[[
    Regression test: reset-period checks reuse the current period start within one server second.

    HasDailyResetOccurred / HasWeeklyResetOccurred did a pcall + C_DateAndTime read (plus
    GetServerTime) on every call; login sweeps call them per character x skill line and the UI per
    row. The current daily / weekly start is now memoized while GetServerTime() is unchanged.
    Answers must be identical to a fresh read, jitter normalization must still apply, and a new
    server second (or a reset crossing) must read the API again.

    Loads the shipped Modules/ResetService.lua.
]]

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local ROOT = os.getenv("WN_ROOT") or "."

local DAY, WEEK = 86400, 7 * 86400
local WEEK_START = 1728450000 - (1728450000 % 3600)   -- a whole-hour reset instant
local now = WEEK_START + 3 * DAY + 1234
local jitter = 0
local dailyCalls, weeklyCalls = 0, 0
GetServerTime = function() return now end
GetCurrentRegion = function() return 3 end
C_DateAndTime = {
    GetSecondsUntilDailyReset = function()
        dailyCalls = dailyCalls + 1
        return DAY - ((now - WEEK_START) % DAY) + jitter
    end,
    GetSecondsUntilWeeklyReset = function()
        weeklyCalls = weeklyCalls + 1
        return WEEK - ((now - WEEK_START) % WEEK) + jitter
    end,
}

local ns = { Constants = { EVENTS = {} } }
ns.WarbandNexus = { db = { global = {} }, SendMessage = function() end }

local fh = assert(io.open(ROOT .. "/Modules/ResetService.lua", "rb"), "missing Modules/ResetService.lua")
local src = fh:read("*a")
fh:close()
local chunk = assert(loadstring((src:gsub("^\239\187\191", "")), "@Modules/ResetService.lua"))
chunk("WarbandNexus", ns)
local RS = ns.ResetService

print("Phase 1: Many checks in one server second read the reset API once")
do
    dailyCalls, weeklyCalls = 0, 0
    local w1 = RS.HasWeeklyResetOccurred(WEEK_START - 10)
    for _ = 1, 200 do RS.HasWeeklyResetOccurred(WEEK_START + 5) end
    local w2 = RS.HasWeeklyResetOccurred(WEEK_START + 5)
    for _ = 1, 200 do RS.HasDailyResetOccurred(now - 10) end
    assert_eq(w1, true, "stamp before the week start: reset occurred")
    assert_eq(w2, false, "stamp after the week start: no reset")
    assert_eq(weeklyCalls, 1, "202 weekly checks -> one GetSecondsUntilWeeklyReset")
    assert_eq(dailyCalls, 1, "200 daily checks -> one GetSecondsUntilDailyReset")
end

print("Phase 2: Memoized answers equal a fresh read, normalization kept")
do
    assert_eq(RS.GetCurrentWeeklyResetStartTime(), WEEK_START, "weekly start is the whole-hour reset")
    assert_eq(RS.GetCurrentDailyResetStartTime(), WEEK_START + 3 * DAY, "daily start is the whole-hour reset")
    now = now + 1
    jitter = -2                                   -- countdown sampled 2 s early (seen live)
    assert_eq(RS.GetCurrentWeeklyResetStartTime(), WEEK_START, "jittered read still normalizes to the reset")
    assert_eq(RS.HasWeeklyResetOccurred(WEEK_START), false, "stamp equal to the start: no reset")
    jitter = 0
end

print("Phase 3: A new server second reads again; a reset crossing is seen at once")
do
    weeklyCalls = 0
    now = now + 1
    RS.HasWeeklyResetOccurred(WEEK_START + 5)
    assert_eq(weeklyCalls, 1, "next second re-reads the API")
    local stamp = WEEK_START + 100
    assert_eq(RS.HasWeeklyResetOccurred(stamp), false, "mid-week stamp: no reset yet")
    now = WEEK_START + WEEK + 1                   -- one second past the next weekly reset
    assert_eq(RS.HasWeeklyResetOccurred(stamp), true, "after the reset the same stamp reports a reset")
    assert_eq(RS.GetCurrentWeeklyResetStartTime(), WEEK_START + WEEK, "week start moved to the new reset")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Reset period memo suite failed with " .. failed .. " failure(s).")
end
print("Reset period memo suite: ALL TESTS PASSED.")
