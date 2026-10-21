#!/usr/bin/env lua
--[[
    Regression test: a character-key rename carries the per-character WEEK STAMPS with their data.

    ApplyCharacterKeyedStorageRenames moved mythicPlus.runHistory but not runHistoryWeek, and moved
    currencyData.totalEarned but not currencyProgressWeek / weeklyEarnedThisWeek. The weekly prune
    deletes any runHistory row without a week stamp, so a Name-Realm -> GUID rekey wiped that
    character's M+ runs; the currency maps stayed behind under the old key.

    Loads the shipped Modules/MigrationService.lua under wow_stub.lua.
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

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    InvalidateCharacterKeyIndex = function() end,
    GetCanonicalCharacterKey = function(_, k) return k end,
    GetCharacterKey = function(_, n, r) return n and r and (n .. "-" .. r) or nil end,
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
LoadFile("Modules/MigrationService.lua")
local MS = ns.MigrationService

local OLD, NEW = "Alpha-Kazzak", "Player-3674-0000000A"
local WEEK_STAMP = 1791950400

local db = { global = {
    characters = {},
    pveCache = { mythicPlus = {
        runHistory = { [OLD] = { { mapChallengeModeID = 500, level = 12, completed = true } } },
        runHistoryWeek = { [OLD] = WEEK_STAMP },
        keystones = {}, bestRuns = {}, dungeonScores = {},
    }, greatVault = { activities = {}, rewards = {} }, lockouts = {} },
    currencyData = {
        currencies = { [OLD] = { [3310] = 40 } },
        totalEarned = { [OLD] = { [3310] = 40 } },
        currencyProgressWeek = { [OLD] = { [3310] = WEEK_STAMP } },
        weeklyEarnedThisWeek = { [OLD] = { [3310] = 40 } },
    },
} }

print("Phase 1: Rekey moves run history together with its week stamp")
do
    MS:ApplyCharacterKeyedStorageRenames(db, { [OLD] = NEW })
    local mp = db.global.pveCache.mythicPlus
    assert_eq(mp.runHistory[NEW] ~= nil, true, "run history moved to the new key")
    assert_eq(mp.runHistoryWeek[NEW], WEEK_STAMP, "run history week stamp moved to the new key")
    assert_eq(mp.runHistoryWeek[OLD], nil, "old week stamp removed")
end

print("Phase 2: Rekey moves currency weekly maps together with totalEarned")
do
    local cd = db.global.currencyData
    assert_eq(cd.totalEarned[NEW] and cd.totalEarned[NEW][3310], 40, "totalEarned moved")
    assert_eq(cd.currencyProgressWeek[NEW] and cd.currencyProgressWeek[NEW][3310], WEEK_STAMP, "currencyProgressWeek moved")
    assert_eq(cd.weeklyEarnedThisWeek[NEW] and cd.weeklyEarnedThisWeek[NEW][3310], 40, "weeklyEarnedThisWeek moved")
    assert_eq(cd.currencyProgressWeek[OLD], nil, "old currencyProgressWeek key removed")
    assert_eq(cd.weeklyEarnedThisWeek[OLD], nil, "old weeklyEarnedThisWeek key removed")
end

print("Phase 3: Alias merge keeps each currency's week stamp and amount together")
do
    local THIS_WEEK, LAST_WEEK = WEEK_STAMP, WEEK_STAMP - 7 * 86400
    local db2 = { global = {
        charactersGuidKeyedV1 = true,
        characters = { [NEW] = { name = "Alpha", realm = "Kazzak", guid = NEW } },
        currencyData = {
            currencies = { [OLD] = { [3310] = 1 }, [NEW] = { [3310] = 1 } },
            totalEarned = { [OLD] = { [3310] = 90 }, [NEW] = { [3310] = 10 } },
            -- Alias row: last week's stamp with a large amount; GUID row: this week's stamp, small amount.
            currencyProgressWeek = { [OLD] = { [3310] = LAST_WEEK }, [NEW] = { [3310] = THIS_WEEK } },
            weeklyEarnedThisWeek = { [OLD] = { [3310] = 90 }, [NEW] = { [3310] = 10 } },
        },
        pveCache = { mythicPlus = {}, greatVault = {}, lockouts = {} },
    }, profile = {} }
    MS:MigrateSubsidiaryAliasBucketsV1(db2)
    local cd = db2.global.currencyData
    assert_eq(cd.currencyProgressWeek[NEW] and cd.currencyProgressWeek[NEW][3310], THIS_WEEK, "newer week stamp kept")
    assert_eq(cd.weeklyEarnedThisWeek[NEW] and cd.weeklyEarnedThisWeek[NEW][3310], 10, "amount paired with the newer stamp")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Rekey week stamps suite failed with " .. failed .. " failure(s).")
end
print("Rekey week stamps suite: ALL TESTS PASSED.")
