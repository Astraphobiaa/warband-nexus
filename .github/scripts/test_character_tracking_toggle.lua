#!/usr/bin/env lua
--[[
    Regression test: toggling tracking on ANOTHER character's row must only change that row.

    ConfirmCharacterTracking resolved its target through GetCharactersTablePersistKey, which returns
    the logged-in player's row whenever one exists. Untracking alt B while logged in on A merged B
    into A, deleted chars[B], and untracked A; the next login's orphan cleanup then purged every
    GUID-keyed bucket B owned. Both the Characters-tab toggle and the right-click menu reach it.

    Loads the shipped Modules/CharacterService.lua under wow_stub.lua.
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

local GUID_A, GUID_B, GUID_OLD = "Player-3674-0000000A", "Player-3674-0000000B", "Player-3674-000000FF"
UnitGUID = function(unit) if unit == "player" then return GUID_A end end
UnitName = function() return "Alpha" end
GetNormalizedRealmName = function() return "Kazzak" end

local ns = {}
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
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
ns.Utilities = {
    GetCharacterKey = function(_, name, realm) return (name or "Alpha") .. "-" .. (realm or "Kazzak") end,
    GetCharacterStorageKey = function() return GUID_A end,
    GetCanonicalCharacterKey = function(_, k)
        -- Mirrors Utilities: the current player's Name-Realm maps to the session GUID.
        if k == "Alpha-Kazzak" then return GUID_A end
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
local CS = ns.CharacterService

local function freshRoster()
    WarbandNexus.db.global.characters = {
        [GUID_A] = { name = "Alpha", realm = "Kazzak", guid = GUID_A, isTracked = true, gold = 100 },
        [GUID_B] = { name = "Bravo", realm = "Kazzak", guid = GUID_B, isTracked = true, gold = 900 },
    }
    messages = {}
    return WarbandNexus.db.global.characters
end

print("Phase 1: Untracking an alt changes only the alt's row")
do
    local chars = freshRoster()
    CS:ConfirmCharacterTracking(WarbandNexus, GUID_B, false)
    stub.Advance(1)
    assert_eq(chars[GUID_B] ~= nil, true, "alt row still exists")
    assert_eq(chars[GUID_B] and chars[GUID_B].isTracked, false, "alt row untracked")
    assert_eq(chars[GUID_B] and chars[GUID_B].gold, 900, "alt row keeps its data")
    assert_eq(chars[GUID_B] and chars[GUID_B].guid, GUID_B, "alt row keeps its GUID")
    assert_eq(chars[GUID_A].isTracked, true, "logged-in character stays tracked")
    assert_eq(chars[GUID_A].gold, 100, "logged-in character data untouched")
    assert_eq(messages[1] and messages[1].payload and messages[1].payload.charKey, GUID_B, "tracking message names the alt")
end

print("Phase 2: Re-tracking the alt works the same way")
do
    local chars = WarbandNexus.db.global.characters
    CS:ConfirmCharacterTracking(WarbandNexus, GUID_B, true)
    stub.Advance(1)
    assert_eq(chars[GUID_B].isTracked, true, "alt row tracked again")
    assert_eq(chars[GUID_A].isTracked, true, "logged-in character unaffected")
end

print("Phase 3: Toggling the logged-in character still uses the self path")
do
    local chars = freshRoster()
    CS:ConfirmCharacterTracking(WarbandNexus, "Alpha-Kazzak", false)
    stub.Advance(1)
    assert_eq(chars[GUID_A].isTracked, false, "own row untracked via Name-Realm key")
    assert_eq(chars[GUID_B].isTracked, true, "alt row unaffected by self toggle")
end

print("Phase 4: A same-name copy with a different GUID is treated as another character")
do
    local chars = freshRoster()
    chars["Alpha-Kazzak"] = { name = "Alpha", realm = "Kazzak", guid = GUID_OLD, isTracked = true, gold = 5 }
    CS:ConfirmCharacterTracking(WarbandNexus, "Alpha-Kazzak", false)
    stub.Advance(1)
    assert_eq(chars["Alpha-Kazzak"] and chars["Alpha-Kazzak"].isTracked, false, "stale copy untracked in place")
    assert_eq(chars[GUID_A].isTracked, true, "logged-in character not untracked by the stale copy")
end

print("Phase 5: Re-tracking a guid-less untracked alt by its Name-Realm key changes only that alt")
do
    local chars = freshRoster()
    chars[GUID_B].isTracked = false
    chars[GUID_B].guid = nil                 -- untrack drops the guid; the row stays GUID-indexed
    CS:ConfirmCharacterTracking(WarbandNexus, "Bravo-Kazzak", true)
    stub.Advance(1)
    assert_eq(chars[GUID_B].isTracked, true, "guid-less alt re-tracked")
    assert_eq(chars[GUID_A].isTracked, true, "logged-in character unchanged")
    assert_eq(chars["Bravo-Kazzak"], nil, "no stray Name-Realm row created")
end

print("Phase 6: The self entry point still runs the self path when the live row does not exist yet")
do
    WarbandNexus.db.global.characters = {
        ["Alpha-Kazzak"] = { name = "Alpha", realm = "Kazzak", guid = GUID_OLD, isTracked = false },
    }
    local chars = WarbandNexus.db.global.characters
    local selfKey = CS:ResolveCharactersTableKey(WarbandNexus)
    CS:ConfirmCharacterTracking(WarbandNexus, selfKey, true)
    stub.Advance(1)
    local live = chars[GUID_A] or chars["Alpha-Kazzak"]
    assert_eq(live and live.isTracked, true, "self dialog tracks the live character")
    assert_eq(live and live.guid, GUID_A, "self path captured the live GUID")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Character tracking toggle suite failed with " .. failed .. " failure(s).")
end
print("Character tracking toggle suite: ALL TESTS PASSED.")
