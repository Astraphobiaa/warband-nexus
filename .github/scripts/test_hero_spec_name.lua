#!/usr/bin/env lua
--[[
    Regression test: the hero talent spec name must be resolved through an API that exists.

    DataService read the name from C_ClassTalents.GetHeroTalentSpecInfo(heroSpecID), which is not in
    Blizzard_APIDocumentationGenerated 12.1.5 (70448). The call was feature-detected, so heroSpecID was
    stored but heroSpecName never was (both the full save and the "spec" cache update).

    Now: heroSpecID is a trait SubTreeID, so the name is
    C_Traits.GetSubTreeInfo(C_ClassTalents.GetActiveConfigID(), heroSpecID).name.

    Loads the shipped DataService.lua under wow_stub.lua. SubTree / config IDs are illustrative.
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

local CONFIG_ID = 4242
local activeHero = 39
local subTrees = { [39] = "Sunfury", [40] = "Spellslinger" }
C_ClassTalents = {
    GetActiveHeroTalentSpec = function() return activeHero end,
    GetActiveConfigID = function() return CONFIG_ID end,
}
C_Traits = {
    GetSubTreeInfo = function(configID, subTreeID)
        if configID ~= CONFIG_ID or not subTrees[subTreeID] then return nil end
        return { ID = subTreeID, name = subTrees[subTreeID], isActive = subTreeID == activeHero }
    end,
}

print("Phase 1: Full save stores the hero spec name")
do
    WarbandNexus.db.global.characters[KEY] = {
        name = "Tester", realm = "TestRealm", classFile = "MAGE", level = 90, guid = KEY,
        isTracked = true, trackingConfirmed = true, lastSeen = 1,
    }
    local ok = WarbandNexus:SaveCurrentCharacterData()
    local row = WarbandNexus.db.global.characters[KEY]
    assert_eq(ok, true, "full save ran")
    assert_eq(row.heroSpecID, 39, "heroSpecID stored")
    assert_eq(row.heroSpecName, "Sunfury", "heroSpecName = GetSubTreeInfo(activeConfigID, heroSpecID).name")
end

print("Phase 2: Spec cache update follows a hero spec switch")
do
    activeHero = 40
    WarbandNexus:UpdateCharacterCache("spec")
    local row = WarbandNexus.db.global.characters[KEY]
    assert_eq(row.heroSpecID, 40, "heroSpecID updated")
    assert_eq(row.heroSpecName, "Spellslinger", "heroSpecName updated")

    -- No active config yet (talents still loading): keep the stored name.
    C_ClassTalents.GetActiveConfigID = function() return nil end
    WarbandNexus:UpdateCharacterCache("spec")
    assert_eq(row.heroSpecName, "Spellslinger", "unresolvable name keeps the stored one")

    WarbandNexus:SaveCurrentCharacterData()
    row = WarbandNexus.db.global.characters[KEY]
    assert_eq(row.heroSpecName, "Spellslinger", "full save before the config loads keeps the stored name")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Hero spec name suite failed with " .. failed .. " failure(s).")
end
print("Hero spec name suite: ALL TESTS PASSED.")
