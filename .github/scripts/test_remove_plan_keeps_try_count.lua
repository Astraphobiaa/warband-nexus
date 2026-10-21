#!/usr/bin/env lua
--[[
    Regression test: removing a plan keeps the collectible's try count.

    Try counts are kept per collectible whether or not it is planned; only an obtain resets them.
    RemovePlan used to call ResetTryCount for mount / pet / toy / illusion plans, so un-planning a
    mount from a Collections list wiped every recorded attempt (user decision 2026-10-22: keep them).

    Loads the shipped Modules/PlansManager.lua under wow_stub.lua.
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
local resetCalls = {}
local tryCounts = { mount = { [1234] = 150 }, pet = { [77] = 12 }, toy = {}, illusion = {} }
local WarbandNexus = {
    db = { global = { plans = {}, customPlans = {}, characters = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
    ResetTryCount = function(_, ct, id)
        resetCalls[#resetCalls + 1] = ct .. ":" .. tostring(id)
        if tryCounts[ct] then tryCounts[ct][id] = 0 end
    end,
    GetTryCount = function(_, ct, id) return tryCounts[ct] and tryCounts[ct][id] or 0 end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    GetCharacterKey = function() return "Alpha-Kazzak" end,
    GetCharacterStorageKey = function() return "Player-3674-0000000A" end,
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

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/PlansManager.lua")

WarbandNexus.db.global.plans = {
    { id = 1, type = "mount", mountID = 1234, name = "Invincible" },
    { id = 2, type = "pet", speciesID = 77, name = "Mr. Bigglesworth" },
}

print("Phase 1: Removing mount and pet plans leaves their try counts alone")
do
    local okMount = WarbandNexus:RemovePlan(1)
    local okPet = WarbandNexus:RemovePlan(2)
    assert_eq(okMount, true, "mount plan removed")
    assert_eq(okPet, true, "pet plan removed")
    assert_eq(#WarbandNexus.db.global.plans, 0, "plan list empty")
    assert_eq(#resetCalls, 0, "ResetTryCount never called on plan removal")
    assert_eq(tryCounts.mount[1234], 150, "mount try count kept (150)")
    assert_eq(tryCounts.pet[77], 12, "pet try count kept (12)")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Remove plan try count suite failed with " .. failed .. " failure(s).")
end
print("Remove plan try count suite: ALL TESTS PASSED.")
