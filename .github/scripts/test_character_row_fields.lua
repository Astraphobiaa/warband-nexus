#!/usr/bin/env lua
--[[
    Regression test: character-row fields are not overwritten by stale or unread values.

    - isResting: the full save wrote `fullLoc.isResting or existing`, so once true it stayed true
      after the character left the inn (a fresh false read fell back to the stored true).
    - zoneName: an unknown zone was stored as "" (CollectPlayerLocation and the zone update),
      replacing the stored name with an empty one.
    - Money: GetMoney() returning nil wrote 0 gold over the stored balance (only a secret value fell
      back to the stored one).

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
local mapID, mapName, zoneText, money, resting = 2393, "Silvermoon City", "Silvermoon City", 1234567, false
UnitName = function() return "Tester" end
GetNormalizedRealmName = function() return "TestRealm" end
UnitClass = function() return "Mage", "MAGE", 8 end
UnitLevel = function() return 90 end
UnitFactionGroup = function() return "Horde" end
UnitRace = function() return "Blood Elf", "BloodElf" end
UnitSex = function() return 3 end
C_PlayerInfo = {}
GetMoney = function() return money end
GetAverageItemLevel = function() return 280, 280 end
HasNewMail = function() return false end
IsInGuild = function() return false end
IsResting = function() return resting end
GetZoneText = function() return zoneText end
GetSubZoneText = function() return "Court of the Sun" end
UnitStat = function() return 0, 0 end
UnitXP = function() return 0 end
UnitXPMax = function() return 0 end
GetXPExhaustion = function() return nil end
GetRestState = function() return nil end
C_Item.GetDetailedItemLevelInfo = function() return nil end
C_Map = {
    GetBestMapForUnit = function() return mapID end,
    GetMapInfo = function() return mapName and { mapID = mapID, name = mapName } or nil end,
}

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

local G = WarbandNexus.db.global
local function seed()
    G.characters[KEY] = {
        name = "Tester", realm = "TestRealm", classFile = "MAGE", level = 90, guid = KEY,
        isTracked = true, trackingConfirmed = true, lastSeen = 1,
        professions = { [1] = { name = "Tailoring" } },
        gold = 123, silver = 45, copper = 67, zoneName = "Silvermoon City", isResting = true,
    }
    return G.characters[KEY]
end

print("Phase 1: A fresh 'not resting' read clears a stored isResting = true (full save)")
do
    seed()
    resting = false
    WarbandNexus:SaveCurrentCharacterData()
    local row = G.characters[KEY]
    assert_eq(row.lastFullSaveAt ~= nil, true, "full path was taken")
    assert_eq(row.isResting, false, "isResting follows the fresh read")
end

print("Phase 2: An unknown zone keeps the stored zone name")
do
    seed()
    mapName, zoneText = nil, ""
    WarbandNexus:SaveCurrentCharacterData()
    assert_eq(G.characters[KEY].zoneName, "Silvermoon City", "full save keeps the zone when the read is empty")
    WarbandNexus:UpdateCharacterCache("zone")
    assert_eq(G.characters[KEY].zoneName, "Silvermoon City", "zone update keeps the zone when GetZoneText is empty")
    mapName, zoneText = "Eversong Woods", "Eversong Woods"
    WarbandNexus:UpdateCharacterCache("zone")
    assert_eq(G.characters[KEY].zoneName, "Eversong Woods", "a real zone still updates")
end

print("Phase 3: An unread balance (GetMoney nil) keeps the stored gold")
do
    seed()
    money = nil
    WarbandNexus:UpdateCharacterCache("gold")
    local row = G.characters[KEY]
    assert_eq(row.gold, 123, "gold kept")
    assert_eq(row.silver, 45, "silver kept")
    assert_eq(row.copper, 67, "copper kept")
    money = 50000
    WarbandNexus:UpdateCharacterCache("gold")
    assert_eq(G.characters[KEY].gold, 5, "a real balance still updates")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Character row fields suite failed with " .. failed .. " failure(s).")
end
print("Character row fields suite: ALL TESTS PASSED.")
