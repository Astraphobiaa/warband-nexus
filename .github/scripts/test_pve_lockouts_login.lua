#!/usr/bin/env lua
--[[
    Regression test: a login read of 0 saved instances must not wipe stored lockouts.

    UpdateRaidLockouts replaced this character's raid and dungeon lockouts with {} whenever
    GetNumSavedInstances() returned 0. Until RequestRaidInfo's answer arrives
    (UPDATE_INSTANCE_INFO, warcraft.wiki.gg) that count can be 0 for a saved character, and
    the PvE service never asked for it -- so a login scan could erase the week's lockouts.
    Now the empty write waits for UPDATE_INSTANCE_INFO this session, and the service requests it.

    Loads the shipped ResetService.lua + PvECacheService.lua under wow_stub.lua.
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

local savedInstances = {}
local raidInfoRequests = 0
GetNumSavedInstances = function() return #savedInstances end
GetSavedInstanceInfo = function(i)
    local r = savedInstances[i]
    if not r then return end
    -- name, lockoutId, reset, difficultyId, locked, extended, instanceIDMostSig, isRaid, maxPlayers,
    -- difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId
    return r.name, 1, r.reset, 16, true, false, 0, true, 20, "Mythic", 8, 3, false, r.instanceId
end
GetSavedInstanceEncounterInfo = function() return nil end
RequestRaidInfo = function() raidInfoRequests = raidInfoRequests + 1 end

local KEY = "Player-01"
local ns = {}
local handlers = {}
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
    RegisterEvent = function(_, ev, fn) handlers[ev] = fn end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.CharacterService = { IsCharacterTracked = function() return true end }
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    IsPvEVaultConsumerEnabled = function() return false end,   -- keep the event handler's refresh path out
    GetCharacterKey = function() return KEY end,
    GetCharacterStorageKey = function() return KEY end,
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

local lockouts = WarbandNexus.db.global.pveCache.lockouts
local function countRows(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

WarbandNexus:RegisterPvECacheEvents()

print("Phase 1: Login read of 0 before UPDATE_INSTANCE_INFO keeps stored lockouts")
do
    assert_eq(raidInfoRequests >= 1, true, "PvE service requests raid info on registration")
    lockouts.raids[KEY] = { ["raid:1"] = { name = "March on Quel'Danas", resetAt = RESET + WEEK } }
    lockouts.dungeons[KEY] = { ["dng:1"] = { name = "Windrunner Spire", resetAt = RESET + WEEK } }
    savedInstances = {}
    WarbandNexus:UpdateRaidLockouts(KEY)
    assert_eq(countRows(lockouts.raids[KEY]), 1, "raid lockout kept")
    assert_eq(countRows(lockouts.dungeons[KEY]), 1, "dungeon lockout kept")
end

print("Phase 2: After UPDATE_INSTANCE_INFO the API is authoritative")
do
    assert_eq(type(handlers.UPDATE_INSTANCE_INFO), "function", "UPDATE_INSTANCE_INFO registered")
    handlers.UPDATE_INSTANCE_INFO("UPDATE_INSTANCE_INFO")
    savedInstances = { { name = "March on Quel'Danas", reset = 3600, instanceId = 2913 } }
    WarbandNexus:UpdateRaidLockouts(KEY)
    assert_eq(countRows(lockouts.raids[KEY]), 1, "live lockout written")
    savedInstances = {}
    WarbandNexus:UpdateRaidLockouts(KEY)
    assert_eq(countRows(lockouts.raids[KEY]), 0, "a real 0 (data loaded) clears raids")
    assert_eq(countRows(lockouts.dungeons[KEY]), 0, "a real 0 (data loaded) clears dungeons")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("PvE lockout login suite failed with " .. failed .. " failure(s).")
end
print("PvE lockout login suite: ALL TESTS PASSED.")
