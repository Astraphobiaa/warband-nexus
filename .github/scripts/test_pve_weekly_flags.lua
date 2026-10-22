#!/usr/bin/env lua
--[[
    Regression test: per-character PvE weekly flags never drop inside one reset period.

    UpdateDelvesData / UpdateWorldBossKills rewrote every weekly flag from a live quest read.
    SafeIsQuestFlaggedCompleted reports "unknown" (unready login read, secret value, pcall error)
    as false, so one bad read turned a completed weekly (Bountiful, Cracked Keystone, Nightmare
    Task, Purging the Vaults, Delve Nemesis, world boss) back into "not done" on that character's
    row for the rest of the week. Same class as the profession logout wipe.

    Loads the shipped Modules/PvECacheService.lua under wow_stub.lua.
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
LoadFile("Modules/PvECacheService_MythicPlus.lua")
LoadFile("Modules/PvECacheService_Vault.lua")

local C = ns.Constants
local WEEKLY = {
    crackedKeystoneComplete = C.PVE_CRACKED_KEYSTONE_WEEKLY_QUEST_ID,
    nightmareTaskComplete = C.PVE_NIGHTMARE_TASK_WEEKLY_QUEST_ID,
    purgingVaultsComplete = C.PVE_PURGING_VAULTS_WEEKLY_QUEST_ID,
    delveNemesisComplete = C.PVE_DELVE_NEMESIS_WEEKLY_QUEST_ID,
}
local WORLD_BOSS_QUEST = 93913
local KEY = "Player-01"

local function setAllDone(done)
    for _, qid in pairs(WEEKLY) do stub.SetQuestCompleted(qid, done) end
    stub.SetQuestCompleted(WORLD_BOSS_QUEST, done)
end

print("Phase 1: Live completion is recorded")
do
    setAllDone(true)
    WarbandNexus:UpdateDelvesData(KEY)
    WarbandNexus:UpdateWorldBossKills(KEY)
    local dc = WarbandNexus.db.global.pveCache.delves.characters[KEY]
    for field in pairs(WEEKLY) do
        assert_eq(dc[field], true, field .. " recorded as done")
    end
    assert_eq(WarbandNexus.db.global.pveCache.lockouts.worldBosses[KEY][WORLD_BOSS_QUEST], true, "world boss kill recorded")
end

print("Phase 2: An unready read later the same week does not undo it")
do
    now = now + 3600
    setAllDone(false)                     -- quest API not ready / secret -> reads false
    WarbandNexus:UpdateDelvesData(KEY)
    WarbandNexus:UpdateWorldBossKills(KEY)
    local dc = WarbandNexus.db.global.pveCache.delves.characters[KEY]
    for field in pairs(WEEKLY) do
        assert_eq(dc[field], true, field .. " kept done after a false read")
    end
    assert_eq(WarbandNexus.db.global.pveCache.lockouts.worldBosses[KEY][WORLD_BOSS_QUEST], true, "world boss kill kept after a false read")
end

print("Phase 3: After the weekly reset the flags clear again")
do
    now = RESET + WEEK + 3600             -- next week
    WarbandNexus:UpdateDelvesData(KEY)
    WarbandNexus:UpdateWorldBossKills(KEY)
    local dc = WarbandNexus.db.global.pveCache.delves.characters[KEY]
    for field in pairs(WEEKLY) do
        assert_eq(dc[field], false, field .. " cleared for the new week")
    end
    assert_eq(WarbandNexus.db.global.pveCache.lockouts.worldBosses[KEY][WORLD_BOSS_QUEST], nil, "world boss kill cleared for the new week")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("PvE weekly flags suite failed with " .. failed .. " failure(s).")
end
print("PvE weekly flags suite: ALL TESTS PASSED.")
