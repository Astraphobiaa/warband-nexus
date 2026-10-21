#!/usr/bin/env lua
--[[
    Regression test: PvE / PvP snapshots never replace stored progress with an unready read.

    - UpdateMythicPlusRunHistory wrote {} over this week's runs when GetRunHistory read nil / empty
      (before CHALLENGE_MODE_MAPS_UPDATE at login).
    - SyncVaultDataFromScanner kept dungeonRunCounts / worldTierProgress from last week on a reused
      vault entry, so tooltips showed last week's Heroic/Mythic runs and delve tiers.
    - PvPService:SnapshotRatedInfo's login / pre-match fallbacks wrote the all-zero pre-reply read
      of GetPersonalRatedInfo over stored ratings.
    - Saved-instance boss rows stored a raw (possibly secret) isKilled.
    Loads the shipped PvECacheService.lua and PvPService.lua under wow_stub.lua.
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
local RESET = 1791950400            -- 2026-10-14 04:00:00 UTC
local now = RESET + 2 * 86400
GetServerTime = function() return now end
time = function() return now end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now end }

local ns = {}
local WarbandNexus = {
    db = {
        global = {
            characters = {},
            pveCache = {
                delves = { characters = {}, companion = {} },
                lockouts = { worldBosses = {}, raids = {}, dungeons = {} },
                mythicPlus = {}, greatVault = { activities = {}, rewards = {} },
            },
        },
        profile = {}, char = {},
    },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
}

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
LoadFile("Modules/PvECacheService.lua")
LoadFile("Modules/PvPService.lua")

local KEY = "Player-01"
local mp = WarbandNexus.db.global.pveCache.mythicPlus
ns.CharacterService = ns.CharacterService or {}
ns.CharacterService.IsCharacterTracked = function() return true end

print("Phase 1: An unready run history read keeps this week's runs")
do
    local history = { { mapChallengeModeID = 500, level = 12, completed = true } }
    C_MythicPlus = { GetRunHistory = function() return history end }
    C_ChallengeMode = { GetMapUIInfo = function() return "Halls" end }
    WarbandNexus:UpdateMythicPlusRunHistory(KEY)
    assert_eq(#(mp.runHistory[KEY] or {}), 1, "this week's run stored")
    history = nil
    WarbandNexus:UpdateMythicPlusRunHistory(KEY)
    assert_eq(#(mp.runHistory[KEY] or {}), 1, "nil read keeps this week's runs")
    history = {}
    WarbandNexus:UpdateMythicPlusRunHistory(KEY)
    assert_eq(#(mp.runHistory[KEY] or {}), 1, "empty read keeps this week's runs")
end

print("Phase 2: A reused vault entry drops last week's run counts and delve tiers")
do
    local gv = WarbandNexus.db.global.pveCache.greatVault
    gv.activities[KEY] = {
        raids = {}, mythicPlus = {}, pvp = {}, world = {}, lastUpdate = RESET - 3600,
        weeklyResetTime = RESET,                       -- next reset as of last week's snapshot
        dungeonRunCounts = { heroic = 4, mythic = 8, mythicPlus = 8 },
        worldTierProgress = { { activityTierID = 1, difficulty = 8, numPoints = 3 } },
    }
    Enum = Enum or {}
    Enum.WeeklyRewardChestThresholdType = Enum.WeeklyRewardChestThresholdType or { Raid = 3, Activities = 1, RankedPvP = 2, World = 6 }
    WarbandNexus:SyncVaultDataFromScanner({ { type = 1, index = 1, progress = 0, threshold = 1, level = 0 } })
    local act = gv.activities[KEY]
    assert_eq(act.dungeonRunCounts, nil, "last week's dungeon run counts dropped")
    assert_eq(act.worldTierProgress, nil, "last week's delve tier progress dropped")
end

print("Phase 3: PvP fallbacks do not overwrite stored ratings with an all-zero read")
do
    local live = { 0, 0, 0, 0, 0, 0, 0 }
    GetPersonalRatedInfo = function() return unpack(live) end
    GetCurrentArenaSeason = function() return 0 end
    local store = { brackets = { ["3v3"] = { rating = 1850, seasonBest = 1900, seasonPlayed = 120 } }, honor = {} }
    WarbandNexus.db.global.pvpProgress = { [KEY] = store }
    store.ratedUpdated = RESET - 3600                  -- last week's snapshot
    GetCurrentArenaSeason = function() return 41 end
    ns.PvPService:SnapshotRatedInfo(true)              -- T+5 login / pre-match fallback
    assert_eq(store.brackets["3v3"].rating, 1850, "fallback keeps the stored rating")
    assert_eq(store.ratedUpdated, RESET - 3600, "a pass with every bracket skipped does not refresh the weekly stamp")
    ns.PvPService:SnapshotRatedInfo(nil, true)         -- authoritative server reply
    assert_eq(store.brackets["3v3"].rating, 0, "the server reply may still reset it")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("PvE / PvP snapshot suite failed with " .. failed .. " failure(s).")
end
print("PvE / PvP snapshot suite: ALL TESTS PASSED.")
