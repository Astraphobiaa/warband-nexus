#!/usr/bin/env lua
--[[
    Regression test: hero talent spec fields are removed and stay removed.

    heroSpecID / heroSpecName were written to every character row but nothing displayed them (their
    only reader, GetWeeklyDashboard, had no caller). They were dropped on 2026-10-22: the writers are
    gone, and MigrateRemoveHeroSpecV1 clears the stored values once.

    Loads the shipped Modules/MigrationService.lua under wow_stub.lua and scans the shipped files.
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
ns.WarbandNexus = { db = { global = {}, profile = {}, char = {} }, SendMessage = function() end, RegisterMessage = function() end }
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = { InvalidateCharacterKeyIndex = function() end }

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
LoadFile("Modules/MigrationService.lua")

print("Phase 1: The one-shot migration clears stored hero spec fields")
do
    local db = { global = { characters = {
        A = { name = "Alpha", heroSpecID = 31, heroSpecName = "Dark Ranger", level = 90 },
        B = { name = "Bravo", heroSpecID = 12 },
    } }, profile = {} }
    ns.MigrationService:MigrateRemoveHeroSpecV1(db)
    assert_eq(db.global.characters.A.heroSpecID, nil, "heroSpecID cleared")
    assert_eq(db.global.characters.A.heroSpecName, nil, "heroSpecName cleared")
    assert_eq(db.global.characters.B.heroSpecID, nil, "second row cleared")
    assert_eq(db.global.characters.A.level, 90, "other fields untouched")
    assert_eq(db.global.heroSpecRemovedV1, true, "migration flag set")
end

print("Phase 2: No shipped file writes or reads hero spec fields any more")
do
    local hits = 0
    local p = io.popen('grep -rn "heroSpec" "' .. ROOT .. '/Modules" "' .. ROOT .. '/Core.lua" 2>/dev/null')
    for line in p:lines() do
        -- The cleanup migration itself is the only allowed mention.
        if not line:find("MigrateRemoveHeroSpecV1", 1, true) and not line:find("heroSpecRemovedV1", 1, true)
            and not line:find("row.heroSpec", 1, true) and not line:find("%-%-%-") then
            hits = hits + 1
            print("    " .. line)
        end
    end
    p:close()
    assert_eq(hits, 0, "no hero spec writers or readers outside the cleanup migration")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Remove hero spec suite failed with " .. failed .. " failure(s).")
end
print("Remove hero spec suite: ALL TESTS PASSED.")
