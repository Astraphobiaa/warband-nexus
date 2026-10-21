#!/usr/bin/env lua
--[[
    Regression test: a full character save never wipes this week's keystone, and the logout flush
    never runs a full (API re-scanning) save.

    ScanMythicKeystone returns nil both for "no key" and for an unready API (login burst), and the
    full save wrote that nil over the stored key. A keystone never disappears mid-week, so a nil read
    with a key stored this week now keeps it. PLAYER_LOGOUT flushed a pending deferred full save,
    re-reading keystone / stats / PvE during client teardown; it now flushes a light save.
    Loads the shipped DataService.lua (+ roster helpers, ResetService) under wow_stub.lua.
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
local WEEK = 7 * 86400
local RESET = 1791950400
local now = RESET + 2 * 86400
GetServerTime = function() return now end
time = function() return now end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now end,
    GetSecondsUntilDailyReset = function() return 3600 end }

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
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/Utilities.lua")
ns.Utilities.GetCharacterStorageKey = function() return KEY end
ns.Utilities.IsModuleEnabled = function() return false end
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")

-- Collaborators the full save calls; their own behaviour is out of scope here.
WarbandNexus.CollectPvEData = function() return nil end
WarbandNexus.CollectProfessionData = function() return {} end
local keystoneScans = 0
WarbandNexus.ScanMythicKeystone = function() keystoneScans = keystoneScans + 1 return nil end
WarbandNexus.UpdatePvEDataV2 = function() end
WarbandNexus.UpdateCurrencyData = function() end

local function row(extra)
    local r = {
        name = "Tester", realm = "TestRealm", classFile = "MAGE", level = 90, guid = KEY,
        isTracked = true, trackingConfirmed = true, lastSeen = 1,
        professions = { [1] = { name = "Tailoring" } },
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    WarbandNexus.db.global.characters[KEY] = r
    return r
end

print("Phase 1: An unready keystone read keeps this week's stored key")
do
    row({ mythicKey = { level = 12, mapID = 500, scanTime = now - 3600 } })
    WarbandNexus:SaveCurrentCharacterData()
    local r = WarbandNexus.db.global.characters[KEY]
    assert_eq(r.lastFullSaveAt ~= nil, true, "full path taken")
    assert_eq(r.mythicKey and r.mythicKey.level, 12, "this week's keystone kept on a nil scan")
end

print("Phase 2: A key stored before the weekly reset is cleared by a nil scan")
do
    row({ mythicKey = { level = 12, mapID = 500, scanTime = RESET - 3600 } })
    WarbandNexus:SaveCurrentCharacterData()
    assert_eq(WarbandNexus.db.global.characters[KEY].mythicKey, nil, "last week's keystone cleared")
end

print("Phase 3: The logout flush of a combat-deferred save does not re-scan APIs")
do
    row({ mythicKey = { level = 9, mapID = 501, scanTime = now - 60 } })
    InCombatLockdown = function() return true end
    WarbandNexus:SaveCurrentCharacterData()          -- deferred: pending full save
    InCombatLockdown = function() return false end
    keystoneScans = 0
    WarbandNexus:FlushDataServiceOnLogout()
    assert_eq(keystoneScans, 0, "no keystone scan during PLAYER_LOGOUT")
    assert_eq(WarbandNexus.db.global.characters[KEY].mythicKey and WarbandNexus.db.global.characters[KEY].mythicKey.level, 9,
        "stored keystone untouched by the logout flush")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Keystone / logout save suite failed with " .. failed .. " failure(s).")
end
print("Keystone / logout save suite: ALL TESTS PASSED.")
