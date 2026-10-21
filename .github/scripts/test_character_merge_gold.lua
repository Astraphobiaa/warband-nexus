#!/usr/bin/env lua
--[[
    Regression test: collapsing duplicate character rows must keep the NEWER row's gold.

    MergeCharacterRowPreserveWinner copied the loser's gold whenever it held more copper than
    the winner. Gold is a balance, so a stale duplicate (an old Name-Realm row, a login-race row)
    resurrected gold the character had since spent. The row with the newer lastSeen is right.

    Loads the shipped MigrationService.lua under wow_stub.lua.
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
LoadFile("Modules/MigrationService.lua")

local MS = ns.MigrationService
local function copper(row) return ns.Utilities:GetCharTotalCopper(row) end

print("Phase 1: Winner is newer and spent gold -- stale richer loser does not win")
do
    local winner = { lastSeen = 2000, gold = 100, silver = 0, copper = 0 }
    local loser = { lastSeen = 1000, gold = 5000, silver = 12, copper = 34 }
    MS:MergeCharacterRowPreserveWinner(winner, loser)
    assert_eq(copper(winner), 100 * 10000, "winner keeps its own (newer, lower) gold")
end

print("Phase 2: Loser is newer -- its gold is current")
do
    local winner = { lastSeen = 1000, gold = 5000, silver = 0, copper = 0 }
    local loser = { lastSeen = 2000, gold = 40, silver = 5, copper = 6 }
    MS:MergeCharacterRowPreserveWinner(winner, loser)
    assert_eq(copper(winner), 40 * 10000 + 5 * 100 + 6, "newer loser's gold copied")
end

print("Phase 3: Winner never recorded money -- loser fills it in")
do
    local winner = { lastSeen = 3000 }
    local loser = { lastSeen = 1000, gold = 7, silver = 0, copper = 0 }
    MS:MergeCharacterRowPreserveWinner(winner, loser)
    assert_eq(copper(winner), 7 * 10000, "missing money filled from loser")
end

print("Phase 4: Loser has no money -- winner untouched")
do
    local winner = { lastSeen = 1000, gold = 9, silver = 0, copper = 0 }
    local loser = { lastSeen = 2000 }
    MS:MergeCharacterRowPreserveWinner(winner, loser)
    assert_eq(copper(winner), 9 * 10000, "winner's money not wiped by an empty newer row")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Character merge gold suite failed with " .. failed .. " failure(s).")
end
print("Character merge gold suite: ALL TESTS PASSED.")
