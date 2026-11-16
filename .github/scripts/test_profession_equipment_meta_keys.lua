#!/usr/bin/env lua
--[[
    Regression test: the stale-profession sweep keeps the equipment store's bookkeeping rows.

    OnProfessionChanged deleted every professionEquipment key that was not a current profession
    name, which included "_legacy" (the flat-format equipment the UI still falls back to) and
    "_last" (the warm stamp DataFreshness short-circuits on). Only per-profession tables under a
    plain name are judged now.

    Runs the shipped WarbandNexus:OnProfessionChanged body from Modules/ProfessionService.lua.
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
dofile(SCRIPT_DIR .. "/wow_stub.lua")

local KEY = "Player-01"
local WarbandNexus = { db = { global = { characters = {} } } }
local ns = {
    WarbandNexus = WarbandNexus,
    Utilities = { IsModuleEnabled = function() return true end },
}

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
-- The method body only, with its file-local helpers supplied by the prelude.
local src = ReadFile("Modules/ProfessionService.lua")
local body = src:match("(function WarbandNexus:OnProfessionChanged%(.-\nend)\r?\n")
assert(body, "OnProfessionChanged not found")
local chunk = assert(loadstring([[
local WarbandNexus, ns, KEY = ...
local function IsCurrentCharacterTracked() return true end
local function IsProfessionTradeWindowReady() return false end
local function ResolveTrackedCharactersTableKey() return KEY end
local function CollectAllExpansionProfessions() end
]] .. body, "@ProfessionService.lua:OnProfessionChanged"))
chunk(WarbandNexus, ns, KEY)

print("Phase 1: unlearning a profession keeps the equipment store's bookkeeping rows")
do
    local legacy = { tool = { itemID = 1 } }
    WarbandNexus.db.global.characters[KEY] = {
        professions = { [1] = { name = "Mining" }, [2] = { name = "Herbalism" } },
        professionExpansions = { Mining = {}, Herbalism = {}, Alchemy = {} },
        professionEquipment = {
            Mining = { tool = {} },
            Alchemy = { tool = {} },             -- unlearned
            _legacy = legacy,
            _last = { lastUpdate = 123 },
            lastUpdate = 1772060967,
        },
    }
    WarbandNexus:OnProfessionChanged()
    local eq = WarbandNexus.db.global.characters[KEY].professionEquipment
    assert_eq(eq.Alchemy, nil, "an unlearned profession's equipment is removed")
    assert_eq(eq.Mining ~= nil, true, "a current profession's equipment stays")
    assert_eq(eq._legacy, legacy, "_legacy flat-format equipment is kept")
    assert_eq(eq._last and eq._last.lastUpdate, 123, "_last warm stamp is kept")
    assert_eq(eq.lastUpdate, 1772060967, "scalar lastUpdate is not judged as a profession")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profession equipment meta keys suite failed with " .. failed .. " failure(s).")
end
print("Profession equipment meta keys suite: ALL TESTS PASSED.")
