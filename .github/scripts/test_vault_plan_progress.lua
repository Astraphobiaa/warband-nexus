#!/usr/bin/env lua
--[[
    Regression test: an empty Great Vault read at login must not reset a weekly vault plan.

    GetWeeklyVaultProgress returned an all-zero table when C_WeeklyRewards.GetActivities() was
    nil or empty (vault data not streamed in yet). UpdateWeeklyPlanProgress stored those zeros,
    un-completing every slot (silently: first sync of the session), and when the real data
    landed the slots "completed" again -- duplicate WN_VAULT_SLOT_COMPLETED /
    WN_VAULT_CHECKPOINT_COMPLETED / WN_VAULT_PLAN_COMPLETED toasts for progress made days ago.
    Now: no data -> nil (plan untouched), and progress never drops within the same week.

    Loads the shipped ResetService.lua + PlansManager_Vault.lua under wow_stub.lua.
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

local WEEK = 7 * 86400
local RESET = 1791950400            -- 2026-10-14 04:00:00 UTC (EU weekly reset)
local now = RESET + 2 * 86400
GetServerTime = function() return now end
time = function() return now end
GetCurrentRegion = function() return 3 end
C_DateAndTime = {
    GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now end,
    GetSecondsUntilDailyReset = function() return 3600 end,
}

-- Enum.WeeklyRewardChestThresholdType values per warcraft.wiki.gg (Activities = 1, Raid = 3, World = 6).
Enum.WeeklyRewardChestThresholdType = { Activities = 1, Raid = 3, World = 6 }
local activities = nil
C_WeeklyRewards = { GetActivities = function() return activities end }
local function vaultRows(dungeonRuns, raidKills, worldRuns)
    local rows = {}
    for _, t in ipairs({ 1, 4, 8 }) do rows[#rows + 1] = { type = 1, threshold = t, progress = dungeonRuns } end
    for _, t in ipairs({ 2, 4, 6 }) do rows[#rows + 1] = { type = 3, threshold = t, progress = raidKills } end
    for _, t in ipairs({ 2, 4, 8 }) do rows[#rows + 1] = { type = 6, threshold = t, progress = worldRuns } end
    return rows
end

local ns = {}
local fired = {}
local WarbandNexus = {
    db = { global = { plans = {}, resets = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) fired[#fired + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
    Debug = function() end,
    RefreshPlanCache = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    GetCharacterKey = function() return "Tester-TestRealm" end,
    GetCharacterStorageKey = function() return "Player-01" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
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

LoadFile("Modules/Constants.lua")
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/PlansManager_Vault.lua")

local function vaultToasts()
    local n = 0
    for i = 1, #fired do
        local m = fired[i].msg
        if m == "WN_VAULT_SLOT_COMPLETED" or m == "WN_VAULT_CHECKPOINT_COMPLETED" or m == "WN_VAULT_PLAN_COMPLETED" then
            n = n + 1
        end
    end
    return n
end

local function newPlan(dungeon, raid, world, lastReset)
    local function slots(ths, count)
        local out = {}
        for i = 1, #ths do out[i] = { threshold = ths[i], completed = count >= ths[i], manualOverride = false } end
        return out
    end
    return {
        id = 1, type = "weekly_vault", characterName = "Tester", characterRealm = "TestRealm",
        lastReset = lastReset, trackedSlots = { dungeon = true, raid = true, world = true },
        slots = {
            dungeon = slots({ 1, 4, 8 }, dungeon), raid = slots({ 2, 4, 6 }, raid),
            world = slots({ 2, 4, 8 }, world),
            specialAssignment = slots({ 1, 2 }, 0),
        },
        progress = { dungeonCount = dungeon, raidBossCount = raid, worldActivityCount = world,
            specialAssignmentCount = 0, specialAssignmentTotal = 2 },
    }
end

print("Phase 1: No vault data yet -> nil, plan untouched")
do
    activities = nil
    assert_eq(WarbandNexus:GetWeeklyVaultProgress("Tester", "TestRealm"), nil, "GetActivities() nil -> nil")
    activities = {}
    assert_eq(WarbandNexus:GetWeeklyVaultProgress("Tester", "TestRealm"), nil, "GetActivities() {} -> nil")

    local plan = newPlan(4, 2, 2, RESET + 3600)
    WarbandNexus:OnVaultPlanSessionReset()
    fired = {}
    WarbandNexus:UpdateWeeklyPlanProgress(plan)            -- login sync, data not there yet
    assert_eq(plan.progress.dungeonCount, 4, "dungeon progress kept")
    assert_eq(plan.slots.dungeon[2].completed, true, "dungeon slot 2 still completed")

    activities = vaultRows(4, 2, 2)                        -- real data lands
    WarbandNexus:UpdateWeeklyPlanProgress(plan)
    WarbandNexus:UpdateWeeklyPlanProgress(plan)
    assert_eq(vaultToasts(), 0, "no duplicate vault toasts for progress made earlier")
end

print("Phase 2: Partial lower read mid-week does not lower progress")
do
    local plan = newPlan(4, 2, 2, RESET + 3600)
    WarbandNexus:OnVaultPlanSessionReset()
    activities = vaultRows(4, 2, 2)
    WarbandNexus:UpdateWeeklyPlanProgress(plan)            -- first sync (silent)
    fired = {}
    activities = vaultRows(1, 0, 0)                        -- partial read
    WarbandNexus:UpdateWeeklyPlanProgress(plan)
    assert_eq(plan.progress.dungeonCount, 4, "dungeon count not lowered")
    assert_eq(plan.progress.raidBossCount, 2, "raid count not lowered")
    activities = vaultRows(4, 2, 2)
    WarbandNexus:UpdateWeeklyPlanProgress(plan)
    assert_eq(vaultToasts(), 0, "no toasts when the real data returns")
    activities = vaultRows(5, 2, 2)
    WarbandNexus:UpdateWeeklyPlanProgress(plan)
    assert_eq(vaultToasts(), 1, "a real gain still toasts once")
end

print("Phase 3: Plan from last week (reset not applied) accepts lower counts")
do
    local plan = newPlan(8, 6, 8, RESET - WEEK + 3600)
    WarbandNexus:OnVaultPlanSessionReset()
    activities = vaultRows(1, 0, 0)
    WarbandNexus:UpdateWeeklyPlanProgress(plan)
    assert_eq(plan.progress.dungeonCount, 1, "new week's lower count stored")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Vault plan progress suite failed with " .. failed .. " failure(s).")
end
print("Vault plan progress suite: ALL TESTS PASSED.")
