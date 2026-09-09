#!/usr/bin/env lua
--[[
    Warband Nexus - Unit Test: RoadmapService
    Target: Midnight 12.1.0 (## Interface: 120100)
]]

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, msg)
    assert_eq(not not cond, true, msg)
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."

-- Load stub environment
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")
table.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local ns = {}
local WarbandNexus = {}
ns.WarbandNexus = WarbandNexus

-- Load Constants
local constChunk = loadfile(ROOT .. "/Modules/Constants.lua")
if constChunk then constChunk("WarbandNexus", ns) end

-- Mock AceDB
WarbandNexus.db = {
    profile = { themeMode = "dark" },
    global = {
        characters = {
            ["Player-01"] = {
                name = "TestHunter",
                class = "HUNTER",
                level = 80,
                currencies = {
                    [3089] = { quantity = 5 },
                    [3465] = { quantity = 4, maxQuantity = 8, totalEarned = 4 },
                    [3509] = { quantity = 2 },
                },
            },
        },
        pveCache = {
            greatVault = {
                activities = {
                    ["Player-01"] = {
                        raid = { { threshold = 2, progress = 2, itemLevel = 310 } },
                        dungeon = { { threshold = 1, progress = 4, itemLevel = 315 }, { threshold = 4, progress = 4, itemLevel = 310 } },
                        world = { { threshold = 2, progress = 2, itemLevel = 305 } },
                    },
                },
                rewards = {
                    ["Player-01"] = { hasAvailableRewards = true },
                },
            },
            delves = {
                characters = {
                    ["Player-01"] = {
                        bountifulComplete = true,
                        gildedStashes = 2,
                        gildedStashesMax = 3,
                        nightmareTaskComplete = true,
                        purgingVaultsComplete = false,
                    },
                },
            },
            mythicPlus = {
                keystones = {
                    ["Player-01"] = {
                        level = 10,
                        challengeMapID = 501,
                    },
                },
            },
            lockouts = {
                raids = {
                    ["Player-01"] = {
                        ["inst-1"] = {
                            name = "The Venomous Abyss",
                            difficultyName = "Heroic",
                            numEncounters = 8,
                            encounterProgress = 6,
                            locked = true,
                            resetAt = os.time() + 86400,
                        },
                        ["inst-expired"] = {
                            name = "Old Expired Raid",
                            difficultyName = "Normal",
                            numEncounters = 8,
                            encounterProgress = 8,
                            locked = true,
                            resetAt = os.time() - 3600,
                        },
                    },
                },
            },
        },
    },
    char = {},
}

-- Mock C_AreaPoiInfo for Bountiful Delves
_G.C_AreaPoiInfo = {
    GetAreaPOIForMap = function(mapID)
        if mapID == 2512 then
            return { 7001, 7002 }
        end
        return {}
    end,
    GetAreaPOIInfo = function(mapID, poiID)
        if poiID == 7001 then
            return {
                name = "Venomfall Deeps",
                description = "Tier 8 Nemesis Delve",
                atlasName = "delves-bountiful",
                position = { x = 0.45, y = 0.60 },
            }
        elseif poiID == 7002 then
            return {
                name = "Gnarldor Isle",
                description = "Delve",
                atlasName = "delves-regular",
                position = { x = 0.30, y = 0.40 },
            }
        end
        return nil
    end,
}

_G.C_DateAndTime = {
    GetSecondsUntilWeeklyReset = function() return 172800 end, -- 2 days
}

_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(questID)
        if questID == 93942 then return true end -- Spark of Tides completed
        return false
    end,
}

-- Load RoadmapService
local svcChunk, err = loadfile(ROOT .. "/Modules/RoadmapService.lua")
if not svcChunk then
    print("FATAL: Failed to load RoadmapService.lua: " .. tostring(err))
    os.exit(1)
end
svcChunk("WarbandNexus", ns)

local RS = ns.RoadmapService
assert_true(RS ~= nil, "RoadmapService is registered on ns")

-- Test 1: Reset seconds
local resetSec = RS:GetWeeklyResetTimeRemaining()
assert_eq(resetSec, 172800, "Weekly reset returns 172800 seconds")

-- Test 2: Bountiful Delves query
local delves = RS:GetBountifulDelves()
assert_eq(#delves, 1, "Detected 1 Bountiful Delve from mock POIs")
assert_eq(delves[1].name, "Venomfall Deeps", "Bountiful delve name matches")
assert_eq(delves[1].isNemesis, true, "Nemesis delve flagged correctly")

-- Test 3: GetCharacterPvERoadmap for Player-01
local roadmap = RS:GetCharacterPvERoadmap("Player-01")
assert_true(roadmap ~= nil, "Roadmap returned valid table")
assert_eq(roadmap.vault.hasUnclaimedReward, true, "Unclaimed Great Vault reward detected")
assert_eq(#roadmap.vault.dungeonSlots, 2, "2 Dungeon vault slots parsed")
assert_eq(roadmap.delves.cofferKeys, 5, "Coffer keys parsed (5)")
assert_eq(roadmap.delves.bountifulCompletedToday, true, "Bountiful today marked completed")
assert_eq(roadmap.seasonalPower.manafluxHeld, 4, "Manaflux held parsed (4)")
assert_eq(roadmap.seasonalPower.keystoneLevel, 10, "Keystone level parsed from mythicPlus.keystones (+10)")

-- Test 4: Weeklies check
assert_true(#roadmap.weeklies >= 9, "At least 9 core weeklies populated")
local nightmareQ
for i = 1, #roadmap.weeklies do
    if roadmap.weeklies[i].key == "nightmare" then nightmareQ = roadmap.weeklies[i] end
end
assert_true(nightmareQ ~= nil, "Nightmare Task found in weeklies")

-- Test 5: Raid lockouts check (expired lockouts filtered)
assert_eq(#roadmap.raidLockouts, 1, "Only 1 active raid lockout (expired lockout filtered out)")
assert_eq(roadmap.raidLockouts[1].name, "The Venomous Abyss", "Active raid lockout instance name matches")
assert_eq(roadmap.raidLockouts[1].encounterProgress, 6, "Raid encounter progress parsed (6/8)")

-- Test 6: ScanAndPersistCurrentCharacter writes to pveCache.weeklyQuests
local scanOk = RS:ScanAndPersistCurrentCharacter("Player-01")
assert_true(scanOk, "ScanAndPersistCurrentCharacter succeeded")
local savedQuests = WarbandNexus.db.global.pveCache.weeklyQuests["Player-01"]
assert_true(savedQuests ~= nil, "pveCache.weeklyQuests['Player-01'] was written")
assert_true(savedQuests.resetAt > os.time(), "resetAt timestamp is in the future")
assert_eq(savedQuests.quests[93942], true, "Quest 93942 (Spark of Tides) flagged complete in DB")

-- Test 7: Weekly reset expiration on cached quests
savedQuests.resetAt = os.time() - 3600 -- Simulate reset occurred
local roadmapReset = RS:GetCharacterPvERoadmap("Player-01")
local sparkQReset
for i = 1, #roadmapReset.weeklies do
    if roadmapReset.weeklies[i].questID == 93942 then sparkQReset = roadmapReset.weeklies[i] end
end
assert_true(sparkQReset ~= nil, "Spark quest present in roadmap")
assert_eq(sparkQReset.completed, false, "Expired weekly quest correctly resets to incomplete")

print(string.format("\ntest_roadmap_service: %d checks passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end

