#!/usr/bin/env lua
--[[
    Regression test: a brand-new alt must get its reputation login scan.

    DataFreshness.IsReputationWarm returned true whenever db.accountWide had rows. Those rows
    were written by another character, so on a new alt the login init treated the reputation
    cache as warm, skipped the full scan, and the alt never got its own per-character
    reputations. Warm now requires the current character's bucket, as IsCurrencyWarm does.

    Loads the shipped DataFreshness.lua under wow_stub.lua.
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

LoadFile("Modules/DataFreshness.lua")

local DF = ns.DataFreshness
local VERSION = 7

print("Phase 1: New alt on an account with account-wide rows")
do
    local db = {
        version = VERSION,
        accountWide = { [2590] = { s = 3 }, [2594] = { s = 5 } },
        characters = { ["Player-1-MAIN"] = { [72] = { s = 8 } } },
    }
    assert_eq(DF.IsReputationWarm(db, VERSION, "Player-1-NEWALT"), false, "new alt is cold -> login scan runs")
    assert_eq(DF.IsReputationWarm(db, VERSION, "Player-1-MAIN"), true, "scanned character stays warm")
end

print("Phase 2: Same contract as currency")
do
    local db = { version = VERSION, accountWide = {}, characters = { ["Player-1-MAIN"] = {} } }
    assert_eq(DF.IsReputationWarm(db, VERSION, "Player-1-MAIN"), false, "empty own bucket is cold")
    local cdb = { version = VERSION, currencies = { ["Player-1-MAIN"] = { [3008] = 1 } } }
    assert_eq(DF.IsCurrencyWarm(cdb, VERSION, "Player-1-NEWALT"), false, "currency: new alt cold")
    db.characters["Player-1-MAIN"] = { [72] = { s = 8 } }
    assert_eq(DF.IsReputationWarm(db, VERSION + 1, "Player-1-MAIN"), false, "schema mismatch is cold")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Reputation warm suite failed with " .. failed .. " failure(s).")
end
print("Reputation warm suite: ALL TESTS PASSED.")
