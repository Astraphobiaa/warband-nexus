#!/usr/bin/env lua
--[[
    Regression test: the mount source-map scan gives the player back every Mount Journal filter it touched.

    EnsureMountSourceIndexMap widens the journal to see every mount per source: SetAllTypeFilters(true)
    and SetCollectedFilterSetting(1..3, true). It restored only the source filters and the search, so a
    player's Collected / Not collected / Unusable and mount-type choices were silently reset after the
    scan (2026-10-22). It also restored inside the scan pcall, so an error mid-scan restored nothing.

    Now the collected (GetCollectedFilterSetting) and type (IsTypeChecked over 1..Enum.MountTypeMeta.NumValues,
    as Blizzard_MountCollection iterates them) settings are saved first and put back after the pcall.

    Loads the shipped CollectionService files under wow_stub.lua.
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

-- Journal filter state as the player left it.
local collected, types, sources, search
local scanError = false
local function ResetJournal()
    collected = { [1] = true, [2] = false, [3] = false }      -- Collected only, no Not collected / Unusable
    types = { [1] = true, [2] = false, [3] = true, [4] = false, [5] = true }
    sources = {}
    for i = 1, 4 do sources[i] = (i ~= 2) end
    search = "drake"
end
ResetJournal()
Enum.MountTypeMeta = { NumValues = 5 }
C_MountJournal = {
    GetNumDisplayedMounts = function()
        if scanError then error("journal not ready") end
        return 0
    end,
    GetDisplayedMountInfo = function() return nil end,
    IsSourceChecked = function(i) return sources[i] end,
    SetSourceFilter = function(i, v) sources[i] = v end,
    SetAllSourceFilters = function(v) for i = 1, 4 do sources[i] = v end end,
    GetCollectedFilterSetting = function(i) return collected[i] end,
    SetCollectedFilterSetting = function(i, v) collected[i] = v end,
    IsTypeChecked = function(i) return types[i] end,
    SetTypeFilter = function(i, v) types[i] = v end,
    SetAllTypeFilters = function(v) for i = 1, 5 do types[i] = v end end,
    SetSearch = function(s) search = s end,
}
ToyBox = { searchString = "", searchBox = { GetText = function() return "" end } }
MountJournal = { searchBox = { GetText = function() return "drake" end } }

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = { modulesEnabled = {} }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    UnregisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    SafeLoadAddOn = function() return true end,
    IsModuleEnabled = function() return true end,
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
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
LoadFile("Modules/CollectionService_Materialize.lua")
LoadFile("Modules/CollectionService_NotifyDedup.lua")
LoadFile("Modules/CollectionService_Scan.lua")
LoadFile("Modules/CollectionService.lua")
LoadFile("Modules/CollectionService_Store.lua")

local function Snapshot()
    return string.format("c=%s,%s,%s t=%s,%s,%s,%s,%s s=%s,%s,%s,%s q=%s",
        tostring(collected[1]), tostring(collected[2]), tostring(collected[3]),
        tostring(types[1]), tostring(types[2]), tostring(types[3]), tostring(types[4]), tostring(types[5]),
        tostring(sources[1]), tostring(sources[2]), tostring(sources[3]), tostring(sources[4]), tostring(search))
end

print("Phase 1: a normal scan restores collected, type, source filters and search")
do
    local before = Snapshot()
    ns._mountGroupedFromMapValid = false
    WarbandNexus:EnsureMountSourceIndexMap()
    assert_eq(collected[2], false, "Not collected filter is back off")
    assert_eq(collected[3], false, "Unusable filter is back off")
    assert_eq(types[2], false, "type filter 2 is back off")
    assert_eq(types[4], false, "type filter 4 is back off")
    assert_eq(Snapshot(), before, "whole journal filter state equals the player's")
end

print("Phase 2: an error mid-scan still restores the filters")
do
    ResetJournal()
    local before = Snapshot()
    scanError = true
    ns._mountGroupedFromMapValid = false
    WarbandNexus:EnsureMountSourceIndexMap()
    scanError = false
    assert_eq(Snapshot(), before, "filter state restored after a failing scan")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Mount journal filter restore suite failed with " .. failed .. " failure(s).")
end
print("Mount journal filter restore suite: ALL TESTS PASSED.")
