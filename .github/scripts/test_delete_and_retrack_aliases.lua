#!/usr/bin/env lua
--[[
    Regression test: deleting or re-tracking a character leaves no orphaned alias data.

    1. DeleteCharacter removed favorites / order entries / section assignments by exact key only. A
       "Name-Realm" favorite or assignment of a GUID-keyed row survived the delete (and kept the
       Favorites block / custom section non-empty). Section locks were never removed.
    2. While a character is untracked its row has no guid, and the orphan / alias migrations moved its
       subsidiary buckets (currencies, PvE, gear, ...) to its Name-Realm key. When it was tracked again
       the readers used the row key and the Name-Realm buckets were never read or purged.

    Loads the shipped CharacterService, MigrationService and DatabaseOptimizer under wow_stub.lua.
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

local GUID_A, GUID_B = "Player-3674-0000000A", "Player-3674-0000000B"
UnitGUID = function(unit) if unit == "player" then return GUID_A end end
UnitName = function() return "Alpha" end
GetNormalizedRealmName = function() return "Kazzak" end

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
local chars
ns.Utilities = {
    GetCharacterKey = function(_, name, realm) return (name or "Alpha") .. "-" .. (realm or "Kazzak") end,
    GetCharacterStorageKey = function() return GUID_A end,
    GetCanonicalCharacterKey = function(_, k)
        -- Mirrors the roster index: a Name-Realm key resolves to the row that owns that name.
        for key, row in pairs(chars or {}) do
            if type(row) == "table" and row.name and (row.name .. "-" .. row.realm) == k and key ~= k then return key end
        end
        return k
    end,
    SafeGuid = function(_, unit) if unit == "player" then return GUID_A end end,
    SplitCharacterKey = function(_, k)
        local n, r = tostring(k or ""):match("^([^-]+)%-(.+)$")
        return n, r
    end,
    InvalidateCharacterKeyIndex = function() end,
    IsModuleEnabled = function() return true end,
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

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/CharacterService.lua")
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/DatabaseOptimizer.lua")
local CS = ns.CharacterService
local G, P = WarbandNexus.db.global, WarbandNexus.db.profile

print("Phase 1: Deleting a GUID row removes its Name-Realm favorite, assignment, lock and order entries")
do
    G.characters = {
        [GUID_A] = { name = "Alpha", realm = "Kazzak", guid = GUID_A, isTracked = true },
        [GUID_B] = { name = "Bravo", realm = "Kazzak", guid = GUID_B, isTracked = true },
    }
    chars = G.characters
    G.favoriteCharacters = { "Bravo-Kazzak", GUID_A }
    P.characterGroupAssignments = { ["Bravo-Kazzak"] = "group_1", [GUID_B] = "group_1", [GUID_A] = "group_2" }
    P.characterLockedAssignments = { ["Bravo-Kazzak"] = true, [GUID_A] = true }
    P.characterOrder = { regular = { GUID_A, "Bravo-Kazzak" }, group_1 = { GUID_B } }

    assert_eq(WarbandNexus:DeleteCharacter(GUID_B), true, "delete succeeds")
    assert_eq(#G.favoriteCharacters, 1, "Name-Realm favorite of the deleted row removed")
    assert_eq(G.favoriteCharacters[1], GUID_A, "other favorite kept")
    assert_eq(P.characterGroupAssignments["Bravo-Kazzak"], nil, "Name-Realm assignment removed")
    assert_eq(P.characterGroupAssignments[GUID_B], nil, "GUID assignment removed")
    assert_eq(P.characterGroupAssignments[GUID_A], "group_2", "other assignment kept")
    assert_eq(P.characterLockedAssignments["Bravo-Kazzak"], nil, "section lock removed")
    assert_eq(P.characterLockedAssignments[GUID_A], true, "other lock kept")
    assert_eq(#P.characterOrder.regular, 1, "Name-Realm order entry removed")
    assert_eq(#P.characterOrder.group_1, 0, "GUID order entry removed")
end

print("Phase 2: Re-tracking the logged-in character folds its Name-Realm buckets back")
do
    G.characters = {
        [GUID_A] = { name = "Alpha", realm = "Kazzak", isTracked = false, trackingConfirmed = true },  -- untrack dropped the guid
    }
    chars = G.characters
    G.gearData = { ["Alpha-Kazzak"] = { slots = { [1] = { itemID = 1 } } } }
    G.pveProgress = { ["Alpha-Kazzak"] = { weekly = 3 } }
    G.currencyData = { currencies = { ["Alpha-Kazzak"] = { [3008] = 120 } }, totalEarned = {} }
    CS:ConfirmCharacterTracking(WarbandNexus, GUID_A, true)
    stub.Advance(1)
    assert_eq(G.characters[GUID_A].isTracked, true, "tracked again")
    assert_eq(G.pveProgress[GUID_A] and G.pveProgress[GUID_A].weekly, 3, "PvE bucket moved to the row key")
    assert_eq(G.pveProgress["Alpha-Kazzak"], nil, "no Name-Realm PvE orphan left")
    assert_eq(G.currencyData.currencies[GUID_A] and G.currencyData.currencies[GUID_A][3008], 120, "currency bucket moved")
    assert_eq(G.currencyData.currencies["Alpha-Kazzak"], nil, "no Name-Realm currency orphan left")
    assert_eq(G.gearData["Alpha-Kazzak"], nil, "no Name-Realm gear orphan left")
end

print("Phase 3: Re-tracking an alt from the Characters tab folds its buckets too")
do
    G.characters = {
        [GUID_A] = { name = "Alpha", realm = "Kazzak", guid = GUID_A, isTracked = true },
        [GUID_B] = { name = "Bravo", realm = "Kazzak", isTracked = false, trackingConfirmed = true },
    }
    chars = G.characters
    G.pveProgress = { ["Bravo-Kazzak"] = { weekly = 7 } }
    CS:ConfirmCharacterTracking(WarbandNexus, GUID_B, true)
    stub.Advance(1)
    assert_eq(G.pveProgress[GUID_B] and G.pveProgress[GUID_B].weekly, 7, "alt PvE bucket moved to its row key")
    assert_eq(G.pveProgress["Bravo-Kazzak"], nil, "no Name-Realm orphan left")
end

print("Phase 4: A separate row that owns the Name-Realm key keeps its buckets")
do
    G.characters = {
        [GUID_A] = { name = "Alpha", realm = "Kazzak", isTracked = false, trackingConfirmed = true },
        ["Alpha-Kazzak"] = { name = "Alpha", realm = "Kazzak", isTracked = false },
    }
    chars = G.characters
    G.pveProgress = { ["Alpha-Kazzak"] = { weekly = 1 } }
    assert_eq(ns.MigrationService:FoldLegacySubsidiaryBuckets(WarbandNexus.db, "Alpha-Kazzak", GUID_A), 0,
        "fold refuses while a roster row owns the legacy key")
    assert_eq(G.pveProgress["Alpha-Kazzak"] and G.pveProgress["Alpha-Kazzak"].weekly, 1, "that row's bucket untouched")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Delete and re-track aliases suite failed with " .. failed .. " failure(s).")
end
print("Delete and re-track aliases suite: ALL TESTS PASSED.")
