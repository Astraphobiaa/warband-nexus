#!/usr/bin/env lua
--[[
    Regression test: field-only WN_CHARACTER_UPDATED keeps the roster cache and the key index.

    DataService dropped the GetAllCharacters roster cache and the Utilities guid / Name-Realm key index
    on every WN_CHARACTER_UPDATED, so each gold / zone / XP / mail tick made the next roster read rebuild
    the merged view (BuildGuidByNameRealmIndex) and the next key lookup rebuild the index. Field-only
    payloads cannot add, drop, re-key or rename a row; structural or unknown payloads still invalidate.

    Loads the shipped Modules/Utilities.lua, DataService_RosterHelpers.lua and DataService.lua under
    wow_stub.lua and drives the registered CHARACTER_UPDATED listener.
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
GetNormalizedRealmName = function() return "TestRealm" end
GetMoney = function() return 0 end

local ns = {}
local msgHandlers = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function(_, msg, fn) msgHandlers[msg] = fn end,
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
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")

local indexDrops = 0
local realInvalidate = ns.Utilities.InvalidateCharacterKeyIndex
ns.Utilities.InvalidateCharacterKeyIndex = function(self, ...)
    indexDrops = indexDrops + 1
    return realInvalidate(self, ...)
end

WarbandNexus.db.global.characters[KEY] = { name = "Tester", realm = "TestRealm", guid = KEY, isTracked = true,
    level = 90, lastSeen = 100 }
WarbandNexus:RegisterCharacterCacheEvents()
local E = ns.Constants.EVENTS
local onUpdated = msgHandlers[E.CHARACTER_UPDATED]
assert_eq(type(onUpdated), "function", "CHARACTER_UPDATED listener registered")
local Roster = ns.DataServiceRoster
local cache = Roster and Roster.cache

local function Fire(payload)
    WarbandNexus:GetAllCharacters()              -- warm the roster cache
    indexDrops = 0
    onUpdated(E.CHARACTER_UPDATED, payload)
    return cache and cache.list ~= nil, indexDrops
end

print("Phase 1: Field-only updates keep the roster cache and the key index")
do
    local fieldOnly = { "gold", "zone", "rested", "level", "itemLevel", "spec", "mail", "guild", "favorite",
        "customSection", "customSections", "vaultClaim", "mythicKey" }
    for i = 1, #fieldOnly do
        local kept, drops = Fire({ charKey = KEY, dataType = fieldOnly[i] })
        assert_eq(kept and drops == 0, true, "dataType = " .. fieldOnly[i] .. " keeps the roster cache and key index")
    end
end

print("Phase 2: Structural or unknown payloads still invalidate")
do
    local cases = {
        { "no payload", nil },
        { "charKey only (tracking confirm / played time)", { charKey = KEY } },
        { "isNew (full save)", { charKey = KEY, isNew = true } },
        { "isDeleted", { charKey = KEY, isDeleted = true } },
        { "isTracked = false", { charKey = KEY, isTracked = false } },
        { "rosterPrune", { dataType = "rosterPrune", removed = 2 } },
        { "professions (roster build heals professions)", { charKey = KEY, dataType = "professions" } },
        { "unknown dataType", { charKey = KEY, dataType = "somethingNew" } },
        { "field-only dataType with isDeleted", { charKey = KEY, dataType = "gold", isDeleted = true } },
        { "plain string payload", KEY },
    }
    for i = 1, #cases do
        local kept, drops = Fire(cases[i][2])
        assert_eq(not kept and drops == 1, true, cases[i][1] .. " drops the roster cache and key index")
    end
end

print("Phase 3: A kept roster still reflects the live row")
do
    local row = WarbandNexus.db.global.characters[KEY]
    WarbandNexus:GetAllCharacters()
    row.copper = 12345
    onUpdated(E.CHARACTER_UPDATED, { charKey = KEY, dataType = "gold" })
    local list = WarbandNexus:GetAllCharacters()
    assert_eq(list[1] and list[1].copper, 12345, "cached roster row is the live row (gold visible)")
    row.level = 91
    row.lastSeen = 200
    onUpdated(E.CHARACTER_UPDATED, { charKey = KEY, dataType = "level" })
    list = WarbandNexus:GetAllCharacters()
    assert_eq(list[1] and list[1].level, 91, "level change rebuilds through the roster signature")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers"
    .. (stub.errors[1] and (" (" .. stub.errors[1] .. ")") or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("CHARACTER_UPDATED roster cache suite failed with " .. failed .. " failure(s).")
end
print("CHARACTER_UPDATED roster cache suite: ALL TESTS PASSED.")
