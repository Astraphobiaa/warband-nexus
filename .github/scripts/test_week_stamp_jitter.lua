#!/usr/bin/env lua
--[[
    Regression test: weekly-reset stamp jitter must not read as "previous week".

    `GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()` samples two clocks at two
    instants, so the same reset was stored as ...:59:58, ...:59:59 or ...:00:00 (seen in a live
    SavedVariables file). Comparing a STORED week start against a freshly computed one with
    `<` / `~=` then flipped to "stale" mid-week and wiped weekly progress:
      - CurrencyCacheService: every alt's weekly-cap progress
      - DailyQuestManager: recorded warband weeklies on a plan (exact ~= compare)
      - VaultButton_Data / PvECacheService: "rewards claimed this week" -> false
      - ResetService: a spurious WN_WEEKLY_RESET_OCCURRED

    Loads the shipped files under wow_stub.lua and drives the clock directly.
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

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local WEEK = 7 * 86400
local RESET = 1791950400            -- 2026-10-14 04:00:00 UTC (EU weekly reset)
local now = RESET + 3 * 86400 + 1234
local jitter = 0                    -- seconds the reset countdown is off from GetServerTime()

GetServerTime = function() return now end
time = function() return now end
GetCurrentRegion = function() return 3 end
C_DateAndTime = {
    GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now + jitter end,
    GetSecondsUntilDailyReset = function() return 3600 + jitter end,
}

local ns = {}
local fired = {}
local WarbandNexus = {
    db = { global = { resets = {}, currencyData = {}, characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) fired[#fired + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
}
ns.VaultButton = {}

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/VaultButton_Data.lua")
LoadFile("Modules/CurrencyCacheService.lua")
LoadFile("Modules/DailyQuestManager.lua")

local function countFired(msg)
    local n = 0
    for i = 1, #fired do if fired[i].msg == msg then n = n + 1 end end
    return n
end

print("Phase 1: Reset epochs are canonical under clock jitter")
do
    local RS = ns.ResetService
    for _, off in ipairs({ -2, -1, 0, 1, 2 }) do
        assert_eq(RS.NormalizeResetEpoch(RESET + off), RESET, "NormalizeResetEpoch(RESET" .. string.format("%+d", off) .. ") == RESET")
    end
    local starts = {}
    for _, j in ipairs({ -1, 0, 1 }) do
        jitter = j
        starts[#starts + 1] = RS.GetCurrentWeeklyResetStartTime()
    end
    jitter = 0
    assert_eq(starts[1], RESET, "week start with -1s jitter")
    assert_eq(starts[2], RESET, "week start with no jitter")
    assert_eq(starts[3], RESET, "week start with +1s jitter")
end

print("Phase 2: Stored jittered epoch does not fire a spurious weekly reset")
do
    local resets = WarbandNexus.db.global.resets
    resets.lastWeeklyResetEpoch = RESET - 1          -- written by an older build
    resets.lastDailyResetEpoch = ns.ResetService.GetCurrentDailyResetStartTime() - 1
    fired = {}
    ns.ResetService:CheckAndTriggerResets("test")
    assert_eq(countFired("WN_WEEKLY_RESET_OCCURRED"), 0, "no WN_WEEKLY_RESET_OCCURRED mid-week")
    assert_eq(countFired("WN_DAILY_RESET_OCCURRED"), 0, "no WN_DAILY_RESET_OCCURRED mid-day")

    local saved = now
    now = RESET + WEEK + 5                           -- a real reset has passed
    fired = {}
    ns.ResetService:CheckAndTriggerResets("test")
    assert_eq(countFired("WN_WEEKLY_RESET_OCCURRED"), 1, "real weekly reset still fires once")
    now = saved
    WarbandNexus.db.global.resets = { lastWeeklyResetEpoch = RESET, lastDailyResetEpoch = 0 }
end

print("Phase 3: Vault claim stamped last session still counts as this week")
do
    assert_eq(ns.VaultRewardsClaimedForCurrentWeek({ claimedResetTime = RESET - 1 }), true,
        "claimedResetTime one second early = claimed this week")
    assert_eq(ns.VaultRewardsClaimedForCurrentWeek({ claimedResetTime = RESET - WEEK }), false,
        "claim from last week is not this week's")
end

print("Phase 4: Currency weekly progress is not stale on a jittered stamp")
do
    local isStale = ns.CurrencyCache.IsWeeklyProgressStaleForChar
    local db = { currencyProgressWeek = { ["Player-02"] = { [3310] = RESET - 1, [3311] = RESET - WEEK } } }
    jitter = 1
    assert_eq(isStale(db, "Player-02", 3310), false, "stamp written one second early is this week")
    jitter = 0
    assert_eq(isStale(db, "Player-02", 3311), true, "stamp from last week is stale")
end

print("Phase 5: Plan weekly record survives jitter, clears on a real reset")
do
    local PW = ns.DailyQuestManagerPlanWeekly
    local plan = { charWeeklyProgress = { weekStart = RESET - 1, questIDs = { [91001] = true } } }
    for _, j in ipairs({ 1, 0, -1 }) do
        jitter = j
        PW.EnsurePlanCharWeeklyProgress(plan)
    end
    jitter = 0
    assert_eq(plan.charWeeklyProgress.questIDs[91001], true, "recorded warband weekly kept mid-week")
    assert_eq(plan.charWeeklyProgress.weekStart, RESET, "stored week start normalized")

    plan.charWeeklyProgress.weekStart = RESET - WEEK
    PW.EnsurePlanCharWeeklyProgress(plan)
    assert_eq(plan.charWeeklyProgress.questIDs[91001], nil, "record from last week is wiped")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Week stamp jitter suite failed with " .. failed .. " failure(s).")
end
print("Week stamp jitter suite: ALL TESTS PASSED.")
