#!/usr/bin/env lua
--[[
    Regression test: deleting a stale same-name character copy must not delete the logged-in character.

    Untracked rows drop their guid, so their canonical key is Name-Realm. DeleteCharacter canonicalized
    the key before looking it up, and Utilities maps the CURRENT player's Name-Realm to the session
    GUID row, so deleting an old untracked copy (deleted-and-recreated character with the same name)
    deleted the live character's row instead.

    Loads the shipped Modules/Utilities.lua and Modules/DatabaseOptimizer.lua under wow_stub.lua.
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

local GUID_LIVE, GUID_OLD = "Player-3674-0000000A", "Player-3674-000000FF"
UnitGUID = function(unit) if unit == "player" then return GUID_LIVE end end
UnitName = function() return "Alpha" end
GetNormalizedRealmName = function() return "Kazzak" end
GetRealmName = function() return "Kazzak" end

local ns = {}
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {}, favoriteCharacters = {} }, profile = { characterOrder = {} }, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
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
LoadFile("Modules/DatabaseOptimizer.lua")

local function roster()
    WarbandNexus.db.global.characters = {
        [GUID_LIVE] = { name = "Alpha", realm = "Kazzak", guid = GUID_LIVE, isTracked = true, gold = 777, _key = GUID_LIVE },
        -- Untracked stale copy of an earlier "Alpha-Kazzak": guid wiped on untrack, row index kept.
        [GUID_OLD] = { name = "Alpha", realm = "Kazzak", isTracked = false, gold = 3, _key = GUID_OLD },
    }
    if ns.Utilities.InvalidateCharacterKeyIndex then ns.Utilities:InvalidateCharacterKeyIndex() end
    return WarbandNexus.db.global.characters
end

print("Phase 1: Deleting the stale copy by its row index keeps the live character")
do
    local chars = roster()
    local ok = WarbandNexus:DeleteCharacter(GUID_OLD)
    assert_eq(ok, true, "delete reports success")
    assert_eq(chars[GUID_OLD], nil, "stale copy deleted")
    assert_eq(chars[GUID_LIVE] and chars[GUID_LIVE].gold, 777, "live character row kept")
end

print("Phase 2: A literal Name-Realm row is deleted as itself, not remapped to the live GUID")
do
    local chars = roster()
    chars[GUID_OLD] = nil
    chars["Alpha-Kazzak"] = { name = "Alpha", realm = "Kazzak", isTracked = false, gold = 3, _key = "Alpha-Kazzak" }
    if ns.Utilities.InvalidateCharacterKeyIndex then ns.Utilities:InvalidateCharacterKeyIndex() end
    WarbandNexus:DeleteCharacter("Alpha-Kazzak")
    assert_eq(chars["Alpha-Kazzak"], nil, "Name-Realm row deleted")
    assert_eq(chars[GUID_LIVE] and chars[GUID_LIVE].gold, 777, "live character row kept")
end

print("Phase 3: An ambiguous Name-Realm key never deletes the live character")
do
    local chars = roster()
    -- What the Characters tab used to pass for the stale copy: its canonical key, Name-Realm.
    local staleUiKey = ns.Utilities:ResolveCharacterRowKey(chars[GUID_OLD])
    WarbandNexus:DeleteCharacter(staleUiKey or "Alpha-Kazzak")
    assert_eq(chars[GUID_LIVE] and chars[GUID_LIVE].gold, 777, "live character row kept on an ambiguous key")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Character delete stale copy suite failed with " .. failed .. " failure(s).")
end
print("Character delete stale copy suite: ALL TESTS PASSED.")
