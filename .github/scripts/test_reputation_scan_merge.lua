#!/usr/bin/env lua
--[[
    Regression test: reputation scans never delete progress they did not re-read.

    - db.accountWide entries were never removed. A faction seen once as account-wide stayed there, and
      every scan then purged that faction from ALL character buckets (including the row just written).
    - UpdateAll wiped the current character's bucket and wrote only what this scan returned, so a
      partial walk (faction data not loaded yet, secret names skipped) deleted the missing factions.
    - FlushReputationCacheOnLogout only cancelled UI timers: a throttled / trailing scan still owed
      was dropped, and the warm login check skipped the rescan. It now marks a rescan for next login.

    Loads the shipped Modules/ReputationCacheService.lua under wow_stub.lua.
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

local KEY = "Player-1-00000001"
local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
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
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return KEY end,
    ResolveCharactersTableKey = function() return KEY end,
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
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/DataFreshness.lua")
LoadFile("Modules/ReputationCacheService.lua")
local RC = ns.ReputationCache
RC.BuildHeaders = function() end   -- header tree is out of scope

local function fac(id, value, accountWide)
    return { factionID = id, name = "Faction " .. id, currentValue = value, maxValue = 1000, reaction = 5,
        isAccountWide = accountWide or false }
end
local function rdb() return WarbandNexus.db.global.reputationData end

print("Phase 1: A faction that turns per-character leaves db.accountWide")
do
    RC:UpdateAll({ fac(100, 50, true), fac(200, 10) })
    assert_eq(rdb().accountWide[100] ~= nil, true, "faction 100 stored account-wide")
    RC:UpdateAll({ fac(100, 60, false), fac(200, 11) })
    assert_eq(rdb().accountWide[100], nil, "faction 100 removed from accountWide once per-character")
    assert_eq(rdb().characters[KEY][100] and rdb().characters[KEY][100].currentValue, 60, "per-character row kept, not purged")
end

print("Phase 2: A partial scan keeps the factions it did not return")
do
    RC:UpdateAll({ fac(100, 61), fac(200, 12), fac(300, 400) })
    RC:UpdateAll({ fac(100, 62) })                 -- partial walk: 200 and 300 missing
    local bucket = rdb().characters[KEY]
    assert_eq(bucket[100] and bucket[100].currentValue, 62, "re-read faction updated")
    assert_eq(bucket[200] and bucket[200].currentValue, 12, "missing faction 200 carried over")
    assert_eq(bucket[300] and bucket[300].currentValue, 400, "missing faction 300 carried over")
end

print("Phase 3: A scan still owed at logout is marked for the next login")
do
    RC.updateThrottle = C_Timer.NewTimer(1.0, function() end)
    WarbandNexus:FlushReputationCacheOnLogout()
    assert_eq(rdb().pendingRescanKey, KEY, "owed rescan recorded for this character")
    assert_eq(RC.updateThrottle, nil, "throttle cancelled")
    RC:UpdateAll({ fac(100, 63) })
    assert_eq(rdb().pendingRescanKey, nil, "the next full scan clears the owed marker")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Reputation scan merge suite failed with " .. failed .. " failure(s).")
end
print("Reputation scan merge suite: ALL TESTS PASSED.")
