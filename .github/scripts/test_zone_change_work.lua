#!/usr/bin/env lua
--[[
    Regression test: a plain zone change does not redo login-only work.

    PLAYER_ENTERING_WORLD fires on login, /reload AND every loading screen (instance in / out,
    portals). Two handlers ignored its (isInitialLogin, isReloadingUi) arguments:
      - VaultScanner poked the server with C_WeeklyRewards.OnUIInteract on every zone change; each
        reply (WEEKLY_REWARDS_UPDATE) runs three full vault handlers. Zone changes now use the
        throttled RequestWeeklyVaultRefresh; login / reload still poke directly.
      - DailyQuestManager re-ran its login pass (one ScanMidnightQuests per daily plan) on every zone
        change, although QUEST_LOG_UPDATE already refreshes those plans.

    Loads the shipped VaultScanner.lua and DailyQuestManager.lua under wow_stub.lua.
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

local pokes, throttled, dailyLogins = 0, 0, 0
C_WeeklyRewards = {
    OnUIInteract = function() pokes = pokes + 1 end,
    GetActivities = function() return {} end,
}

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {}, plans = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
    RequestWeeklyVaultRefresh = function() throttled = throttled + 1 end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    IsPvEVaultConsumerEnabled = function() return true end,
    IsModuleEnabled = function() return true end,
    GetCharacterKey = function() return "Tester-TestRealm" end,
    GetCharacterStorageKey = function() return "Player-1-00000001" end,
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

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/VaultScanner.lua")
LoadFile("Modules/DailyQuestManager.lua")
WarbandNexus.OnDailyQuestLogin = function() dailyLogins = dailyLogins + 1 end
WarbandNexus:InitializeDailyQuestManager()

print("Phase 1: Login / reload still run the login work")
do
    stub.Fire("PLAYER_ENTERING_WORLD", true, false)
    stub.Advance(1.5)
    assert_eq(pokes, 1, "initial login pokes the vault server")
    assert_eq(dailyLogins, 1, "initial login runs the daily-quest login pass")
    stub.Fire("PLAYER_ENTERING_WORLD", false, true)
    stub.Advance(1.5)
    assert_eq(pokes, 2, "reload pokes the vault server")
    assert_eq(dailyLogins, 2, "reload runs the daily-quest login pass")
end

print("Phase 2: A plain zone change does not")
do
    stub.Fire("PLAYER_ENTERING_WORLD", false, false)
    stub.Advance(1.5)
    assert_eq(pokes, 2, "zone change: no direct vault poke")
    assert_eq(throttled, 1, "zone change: throttled vault refresh instead")
    assert_eq(dailyLogins, 2, "zone change: no daily-quest login pass")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Zone change work suite failed with " .. failed .. " failure(s).")
end
print("Zone change work suite: ALL TESTS PASSED.")
