#!/usr/bin/env lua
--[[
    Regression test: one character stored twice (GUID row + legacy Name-Realm row) behaves as one.

    The roster merged the two rows for display only, so per-row actions and raw-row readers saw
    two characters: untracking flipped one row and the merge ("tracked wins") put the other's back,
    the character limit counted both, and a manual order entry under the old key never matched.
    Duplicates are now collapsed in the DB before those actions, and order entries are matched by
    canonical identity.

    Loads the shipped Utilities, CharacterService, MigrationService, DataService_RosterHelpers and
    DatabaseOptimizer under wow_stub.lua, plus DataService's CollapseCharacterRosterDuplicates.
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

local LIVE, ALT = "Player-3674-0000000A", "Player-3674-000000B1"
UnitGUID = function(unit) if unit == "player" then return LIVE end end
UnitName = function() return "Alpha" end
GetNormalizedRealmName = function() return "Kazzak" end
GetRealmName = function() return "Kazzak" end

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {}, favoriteCharacters = {} }, profile = { characterOrder = {} }, char = {} },
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

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
local function Extract(rel, name)
    local body = ReadFile(rel):match("(function WarbandNexus:" .. name .. "%(.-\nend)\r?\n")
    assert(body, "function not found: " .. name)
    local chunk = assert(loadstring("local WarbandNexus, ns = ...\n" .. body, "@" .. rel .. ":" .. name))
    chunk(WarbandNexus, ns)
end

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/CharacterService.lua")
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DatabaseOptimizer.lua")
Extract("Modules/DataService.lua", "CollapseCharacterRosterDuplicates")
WarbandNexus.InvalidateGetAllCharactersCache = function() end

local chars
local function roster(altTracked, legacyTracked)
    WarbandNexus.db.global.characters = {
        [LIVE] = { name = "Alpha", realm = "Kazzak", guid = LIVE, isTracked = true, lastSeen = 300 },
        [ALT] = { name = "Renzak", realm = "Kazzak", guid = ALT, isTracked = altTracked, lastSeen = 200 },
        ["Renzak-Kazzak"] = { name = "Renzak", realm = "Kazzak", isTracked = legacyTracked, lastSeen = 100 },
    }
    chars = WarbandNexus.db.global.characters
    ns.Utilities:InvalidateCharacterKeyIndex()
    return chars
end
local function rowsNamed(name)
    local n = 0
    for _, row in pairs(chars) do if type(row) == "table" and row.name == name then n = n + 1 end end
    return n
end
local function displayed(name)
    local seen = ns.DataServiceRoster.BuildMergedCharacterRosterView(chars)
    for _, row in pairs(seen) do if row.name == name then return row end end
end

print("Phase 1: untracking a character stored twice sticks")
do
    roster(true, true)
    ns.CharacterService:ConfirmCharacterTracking(WarbandNexus, ALT, false)
    assert_eq(rowsNamed("Renzak"), 1, "the two rows were collapsed into one")
    local shown = displayed("Renzak")
    assert_eq(shown and shown.isTracked, false, "the roster shows the character untracked")
end

print("Phase 2: the character limit counts characters, not rows")
do
    roster(true, nil)
    chars["Player-3674-000000C1"] = { name = "Old", realm = "Kazzak", guid = "Player-3674-000000C1",
        isTracked = false, lastSeen = 50 }
    -- Three characters, four rows: a limit of 3 must not prune the untracked one.
    WarbandNexus:EnforceCharacterLimit(3)
    assert_eq(chars["Player-3674-000000C1"] ~= nil, true, "a real untracked character is not pruned")
    assert_eq(rowsNamed("Renzak"), 1, "the duplicate itself was collapsed")
end

print("Phase 3: a manual order entry under an older key still places the character")
do
    roster(true, nil)
    WarbandNexus:CollapseCharacterRosterDuplicates()
    local profile = { characterOrder = { regular = { "Renzak-Kazzak", LIVE } } }
    profile.charactersSortKey = "manual"
    local list = { chars[LIVE], chars[ALT] }
    ns.CharacterService:SortCharacterRosterList(list, profile, "regular", {
        sortKey = "manual",
        getCharKeyFn = function(c) return ns.Utilities:ResolveCharacterRowKey(c) end,
    })
    assert_eq(list[1] and list[1].name, "Renzak", "the old-key entry still sorts first")
    assert_eq(profile.characterOrder.regular[1], ALT, "the entry is rewritten to the current row key")
    assert_eq(#profile.characterOrder.regular, 2, "no second entry for the same character")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Character duplicate rows suite failed with " .. failed .. " failure(s).")
end
print("Character duplicate rows suite: ALL TESTS PASSED.")
