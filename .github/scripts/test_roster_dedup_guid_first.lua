#!/usr/bin/env lua
--[[
    Regression test: roster dedup keeps the GUID row (and its buckets) over a Name-Realm duplicate.

    CollectCharacterDuplicateRenames picked the newest lastSeen as survivor. A login-race Name-Realm
    row is always the newest, and ApplyCharacterKeyedStorageRenames drops the loser's bucket whenever
    the survivor already has one, so the GUID row's stored bags/bank were replaced by the race row's
    near-empty snapshot.

    Loads the shipped DataService_RosterHelpers.lua and MigrationService.lua under wow_stub.lua.
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
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/DataService_RosterHelpers.lua")

local GUID, NR = "Player-3674-0000000A", "Alpha-Kazzak"
local db = { global = {
    characters = {
        [GUID] = { name = "Alpha", realm = "Kazzak", guid = GUID, isTracked = true, lastSeen = 1000, gold = 50 },
        -- Login race: GUID not resolvable yet, a fresh row lands under Name-Realm (newest lastSeen).
        [NR] = { name = "Alpha", realm = "Kazzak", guid = GUID, isTracked = true, lastSeen = 2000 },
    },
    itemStorage = {
        [GUID] = { bags = { "full-bags" }, bank = { "full-bank" } },
        [NR] = { bags = {} },
    },
}, profile = {} }

print("Phase 1: Dedup keeps the GUID row and its stored items")
do
    local n = ns.DataServiceRoster.ApplyCharacterRosterDeduplication(db, ns.MigrationService)
    local chars = db.global.characters
    assert_eq(n, 1, "one duplicate collapsed")
    assert_eq(chars[GUID] ~= nil, true, "GUID row survives")
    assert_eq(chars[NR], nil, "Name-Realm duplicate removed")
    local store = db.global.itemStorage[GUID]
    assert_eq(store and store.bank and store.bank[1], "full-bank", "GUID row's stored bank kept")
    assert_eq(store and store.bags and store.bags[1], "full-bags", "GUID row's stored bags kept")
    assert_eq(chars[GUID] and chars[GUID].lastSeen, 2000, "survivor takes the newer row's lastSeen")
end

print("Phase 2: The surviving GUID row takes the newer duplicate's scalar fields")
do
    local db2 = { global = {
        characters = {
            [GUID] = { name = "Alpha", realm = "Kazzak", guid = GUID, isTracked = true, lastSeen = 1000, level = 88, guildName = "Old Guild" },
            [NR] = { name = "Alpha", realm = "Kazzak", guid = GUID, isTracked = true, lastSeen = 2000, level = 90, guildName = "New Guild", itemLevel = 0 },
        },
    }, profile = {} }
    db2.global.characters[GUID].itemLevel = 280
    ns.DataServiceRoster.ApplyCharacterRosterDeduplication(db2, ns.MigrationService)
    local row = db2.global.characters[GUID]
    assert_eq(row and row.level, 90, "newer level taken")
    assert_eq(row and row.guildName, "New Guild", "newer guild taken")
    assert_eq(row and row.itemLevel, 280, "a 0 from the newer row does not overwrite the real item level")
    assert_eq(row and row.guid, GUID, "survivor keeps its GUID")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Roster dedup GUID-first suite failed with " .. failed .. " failure(s).")
end
print("Roster dedup GUID-first suite: ALL TESTS PASSED.")
