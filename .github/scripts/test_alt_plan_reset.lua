#!/usr/bin/env lua
--[[
    Regression test: an alt's Weekly Progress (daily_quests) plan does not keep last week's
    completions. Only the logged-in character's plan is ever rescanned, so an alt's plan kept last
    week's weeklies and yesterday's dailies ticked -- even reading as fully complete -- until that
    alt logged in. DailyQuestManager now expires them by the plan's own lastUpdate stamp.

    Loads the shipped Constants.lua, ResetService.lua and DailyQuestManager.lua under wow_stub.lua.
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
LoadFile("Modules/DailyQuestManager.lua")

print("Phase 1: an alt's Weekly Progress plan does not keep last week's completions")
do
    -- Only the logged-in character's plan is ever rescanned, so an alt's plan kept last week's
    -- weeklies and yesterday's dailies ticked until that alt logged in.
    ns.Utilities.IsModuleEnabled = function() return true end
    local getKey = ns.Utilities.GetCharacterKey
    ns.Utilities.GetCharacterKey = function(_, n, r)
        if n then return n .. "-" .. r end
        return "Player-01"
    end
    local function plan(lastUpdate)
        return {
            type = "daily_quests", characterName = "Alt", characterRealm = "Kazzak",
            lastUpdate = lastUpdate,
            quests = {
                weeklyQuests = { { questID = 91001, isComplete = true } },
                worldQuests = { { questID = 82001, isComplete = true }, { questID = 82002, isComplete = false } },
                dailyQuests = { { questID = 83001, isComplete = true, isDaily = true } },
                events = {},
            },
            charWeeklyProgress = { weekStart = RESET - WEEK, questIDs = { [91001] = true } },
        }
    end
    now = RESET + 3 * 86400 + 1234
    jitter = 0
    local old, fresh = plan(RESET - 2 * 86400), plan(now - 60)
    WarbandNexus.db.global.plans = { old, fresh }
    WarbandNexus:UpdateDailyQuestWeeklyReset()
    assert_eq(old.quests.weeklyQuests[1].isComplete, false, "alt: last week's weekly reopens")
    assert_eq(#old.quests.worldQuests, 1, "alt: completed world quest from last week is dropped")
    assert_eq(old.quests.worldQuests[1].questID, 82002, "alt: an open world quest stays listed")
    assert_eq(#old.quests.dailyQuests, 0, "alt: yesterday's daily is dropped")
    assert_eq(old.charWeeklyProgress.questIDs[91001], nil, "alt: recorded warband weekly is wiped")
    assert_eq(fresh.quests.weeklyQuests[1].isComplete, true, "a plan updated this week is untouched")
    ns.Utilities.GetCharacterKey = getKey
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Alt plan reset suite failed with " .. failed .. " failure(s).")
end
print("Alt plan reset suite: ALL TESTS PASSED.")
