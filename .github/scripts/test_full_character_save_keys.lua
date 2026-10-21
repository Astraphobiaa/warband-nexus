#!/usr/bin/env lua
--[[
    Regression test: the full character save must not drop fields owned by other writers.

    SaveCurrentCharacterData (full path) replaced the whole db.global.characters row with a new
    table literal, so every key it does not list vanished on each login / reload:
      - achievementPointsEarned / achievementPointsResolvedAt (CollectionService)
      - subZoneName (the zone debounce in DataService)
    The light path patches the row in place and was never affected.

    Loads the shipped DataService.lua (+ roster helpers) under wow_stub.lua.
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
UnitName = function() return "Tester" end
GetNormalizedRealmName = function() return "TestRealm" end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitLevel = function() return 90 end
UnitFactionGroup = function() return "Horde" end
UnitRace = function() return "Blood Elf", "BloodElf" end
UnitSex = function() return 3 end
C_PlayerInfo = {}
GetMoney = function() return 1234567 end
GetAverageItemLevel = function() return 280, 280 end
HasNewMail = function() return false end
IsInGuild = function() return false end
IsResting = function() return false end
GetZoneText = function() return "Silvermoon City" end
GetSubZoneText = function() return "Court of the Sun" end
UnitStat = function() return 0, 0 end
UnitXP = function() return 0 end
UnitXPMax = function() return 0 end
GetXPExhaustion = function() return nil end
GetRestState = function() return nil end
C_Item.GetDetailedItemLevelInfo = function() return nil end

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
ns.Utilities.GetCharacterStorageKey = function() return KEY end
ns.Utilities.IsModuleEnabled = function() return false end
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")

-- Collaborators the full save calls; their own behaviour is out of scope here.
WarbandNexus.CollectPvEData = function() return nil end
WarbandNexus.CollectProfessionData = function() return {} end
WarbandNexus.ScanMythicKeystone = function() return nil end
WarbandNexus.UpdatePvEDataV2 = function() end
WarbandNexus.UpdateCurrencyData = function() end

print("Phase 1: Full save keeps keys written by other services")
do
    WarbandNexus.db.global.characters[KEY] = {
        name = "Tester", realm = "TestRealm", classFile = "MAGE", level = 90, guid = KEY,
        isTracked = true, trackingConfirmed = true, lastSeen = 1,
        professions = { [1] = { name = "Tailoring" }, [2] = { name = "Enchanting" } },
        achievementPointsEarned = 21450,
        achievementPointsResolvedAt = 1791950400,
        subZoneName = "Court of the Sun",
        mythicKey = { level = 12 },
    }
    local ok = WarbandNexus:SaveCurrentCharacterData()
    local row = WarbandNexus.db.global.characters[KEY]
    assert_eq(ok, true, "full save ran")
    assert_eq(row.lastFullSaveAt ~= nil, true, "full path (not the light patch) was taken")
    assert_eq(row.achievementPointsEarned, 21450, "achievementPointsEarned survives")
    assert_eq(row.achievementPointsResolvedAt, 1791950400, "achievementPointsResolvedAt survives")
    assert_eq(row.subZoneName, "Court of the Sun", "subZoneName survives")
    assert_eq(row.mythicKey, nil, "an owned key the save cleared stays cleared (keystone used)")
    assert_eq(row.level, 90, "owned keys still rebuilt from the API")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Full character save keys suite failed with " .. failed .. " failure(s).")
end
print("Full character save keys suite: ALL TESTS PASSED.")
