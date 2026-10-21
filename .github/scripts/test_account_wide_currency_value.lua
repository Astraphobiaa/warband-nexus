#!/usr/bin/env lua
--[[
    Regression test: an account-wide currency must show its current quantity, not the
    highest amount any character ever stored.

    Every tracked character keeps its own snapshot of an account-wide currency, written when it
    last scanned. RebuildMergedCurrenciesUIReadModel took the max across those rows, so after the
    live character spent some, the Currency tab kept showing the pre-spend amount from an alt.
    The live character's row is current; otherwise the most recently seen character's.

    Loads the shipped CurrencyCacheService.lua under wow_stub.lua.
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

local ACCOUNT_WIDE = 3008   -- account-wide currency
local PER_CHAR = 3028       -- per-character currency

C_CurrencyInfo = {
    GetCurrencyInfo = function(id)
        if id == ACCOUNT_WIDE then
            return { name = "Shared Coin", iconFileID = 1, quantity = 0, maxQuantity = 0, isAccountWide = true }
        elseif id == PER_CHAR then
            return { name = "Own Coin", iconFileID = 2, quantity = 0, maxQuantity = 0, isAccountWide = false }
        end
    end,
}

local liveKey = "Player-1-LIVE"
local ns = {}
local WarbandNexus = {
    db = { global = { characters = {}, currencyData = nil }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    GetCharacterKey = function() return liveKey end,
    GetCharacterStorageKey = function() return liveKey end,
    GetCanonicalCharacterKey = function(_, k) return k end,
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
LoadFile("Modules/CurrencyCacheService.lua")

local chars = WarbandNexus.db.global.characters
chars["Player-1-LIVE"] = { isTracked = true, lastSeen = 5000 }
chars["Player-1-ALTA"] = { isTracked = true, lastSeen = 4000 }
chars["Player-1-ALTB"] = { isTracked = true, lastSeen = 3000 }

local function seed(rows)
    local cd = WarbandNexus.db.global.currencyData or {}
    WarbandNexus.db.global.currencyData = cd
    cd.currencies = rows
    cd.headers = cd.headers or {}
    cd.visibleCurrencyIDs = cd.visibleCurrencyIDs or {}
    WarbandNexus:InvalidateCurrenciesForUICache()
    return WarbandNexus:GetCurrenciesForUI()
end

print("Phase 1: Live character spent an account-wide currency")
do
    local ui = seed({
        ["Player-1-LIVE"] = { [ACCOUNT_WIDE] = 120, [PER_CHAR] = 5 },
        ["Player-1-ALTA"] = { [ACCOUNT_WIDE] = 900, [PER_CHAR] = 7 },
        ["Player-1-ALTB"] = { [ACCOUNT_WIDE] = 400 },
    })
    assert_eq(ui[ACCOUNT_WIDE].value, 120, "account-wide value is the live character's row")
    assert_eq(ui[PER_CHAR].value, nil, "per-character currency has no shared value")
    assert_eq(ui[PER_CHAR].chars["Player-1-ALTA"], 7, "per-character rows unchanged")
end

print("Phase 2: Live character has no row yet -- newest-seen alt wins")
do
    local ui = seed({
        ["Player-1-ALTA"] = { [ACCOUNT_WIDE] = 300 },
        ["Player-1-ALTB"] = { [ACCOUNT_WIDE] = 900 },
    })
    assert_eq(ui[ACCOUNT_WIDE].value, 300, "most recently seen character's snapshot")
end

print("Phase 3: No lastSeen anywhere -- old max behaviour")
do
    chars["Player-1-ALTA"].lastSeen = nil
    chars["Player-1-ALTB"].lastSeen = nil
    local ui = seed({
        ["Player-1-ALTA"] = { [ACCOUNT_WIDE] = 300 },
        ["Player-1-ALTB"] = { [ACCOUNT_WIDE] = 900 },
    })
    assert_eq(ui[ACCOUNT_WIDE].value, 900, "ties fall back to the larger snapshot")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Account-wide currency value suite failed with " .. failed .. " failure(s).")
end
print("Account-wide currency value suite: ALL TESTS PASSED.")
