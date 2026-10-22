#!/usr/bin/env lua
--[[
    Regression test: tracking a character collects vault data for every vault consumer.

    After the tracking confirm, CharacterService collected PvE data only when modulesEnabled.pve
    was on, while the login path (Core.lua P2) and UpdatePvEData itself use
    Utilities:IsPvEVaultConsumerEnabled() (PvE tab, Plans, vault button, vault reminder). With the
    PvE tab off but Plans or the vault button on, a newly tracked character had no vault data until
    the next login. The confirm path now uses the same consumer gate.

    Loads the shipped Modules/CharacterService.lua under wow_stub.lua (harness of
    test_character_tracking_toggle.lua).
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

local GUID_A = "Player-3674-0000000A"
UnitGUID = function(unit) if unit == "player" then return GUID_A end end
UnitName = function() return "Alpha" end
GetNormalizedRealmName = function() return "Kazzak" end

local ns = {}
local pveUpdates = 0
local WarbandNexus = {
    db = { global = { characters = {} }, profile = { modulesEnabled = {} }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
function WarbandNexus:UpdatePvEData() pveUpdates = pveUpdates + 1 end
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
-- Consumer gate: same rule as Utilities:IsPvEVaultConsumerEnabled (pve or plans module, or vault button).
local vaultButtonOn = false
ns.Utilities = {
    GetCharacterKey = function(_, name, realm) return (name or "Alpha") .. "-" .. (realm or "Kazzak") end,
    GetCharacterStorageKey = function() return GUID_A end,
    GetCanonicalCharacterKey = function(_, k)
        if k == "Alpha-Kazzak" then return GUID_A end
        return k
    end,
    SafeGuid = function(_, unit) if unit == "player" then return GUID_A end end,
    SplitCharacterKey = function(_, k)
        local n, r = tostring(k or ""):match("^([^-]+)%-(.+)$")
        return n, r
    end,
    InvalidateCharacterKeyIndex = function() end,
    IsModuleEnabled = function(_, m) return WarbandNexus.db.profile.modulesEnabled[m] == true end,
    IsPvEVaultConsumerEnabled = function()
        local me = WarbandNexus.db.profile.modulesEnabled
        return (me.pve == true or me.plans == true or vaultButtonOn) and true or false
    end,
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

local function TrackSelf(modules, vb)
    WarbandNexus.db.global.characters = {
        [GUID_A] = { name = "Alpha", realm = "Kazzak", guid = GUID_A, isTracked = false },
    }
    WarbandNexus.db.profile.modulesEnabled = modules
    vaultButtonOn = vb or false
    pveUpdates = 0
    CS:ConfirmCharacterTracking(WarbandNexus, GUID_A, true)
    stub.Advance(10)
    return pveUpdates
end

print("Phase 1: Every vault consumer gets the post-confirm PvE collection")
do
    assert_eq(TrackSelf({ pve = true }), 1, "PvE tab on: vault data collected")
    assert_eq(TrackSelf({ pve = false, plans = true }), 1, "PvE off, Plans on: vault data collected")
    assert_eq(TrackSelf({ pve = false }, true), 1, "PvE off, vault button on: vault data collected")
end

print("Phase 2: No consumer, no collection")
do
    assert_eq(TrackSelf({ pve = false, plans = false }), 0, "no vault consumer: nothing collected")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers"
    .. (stub.errors[1] and (" (" .. stub.errors[1] .. ")") or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Tracking confirm vault gate suite failed with " .. failed .. " failure(s).")
end
print("Tracking confirm vault gate suite: ALL TESTS PASSED.")
