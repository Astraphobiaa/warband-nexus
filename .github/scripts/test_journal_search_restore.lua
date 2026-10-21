#!/usr/bin/env lua
--[[
    Regression test: toy and mount scans must put the player's journal search back.

    The scans clear the search (C_ToyBox.SetFilterString("") / C_MountJournal.SetSearch("")) so every
    entry is listed, and meant to restore it from C_ToyBox.GetFilterString / C_MountJournal.GetSearch.
    Neither getter exists in 12.1.5 (Ketho GlobalAPI dump, Blizzard_APIDocumentationGenerated 70448),
    so the saved value was always "" and a scan wiped whatever the player had typed.

    Now: the text is read where Blizzard_Collections keeps it (ToyBox.searchString, set by
    ToyBox_OnSearchTextChanged; MountJournal.searchBox:GetText()).

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

-- Journal state: the setters exist, the getters do not.
local toyFilter, mountSearch = "wolf", "drake"
local toyFilterCalls, mountSearchCalls = {}, {}
C_ToyBox = {
    GetToyInfo = function() return nil end,
    GetCollectedShown = function() return true end,
    GetUncollectedShown = function() return false end,
    SetCollectedShown = function() end,
    SetUncollectedShown = function() end,
    SetAllSourceTypeFilters = function() end,
    SetSourceTypeFilter = function() end,
    IsSourceTypeFilterChecked = function() return true end,
    GetNumSourceTypeFilters = function() return 2 end,
    SetFilterString = function(s) toyFilter = s; toyFilterCalls[#toyFilterCalls + 1] = s end,
    ForceToyRefilter = function() end,
    GetNumFilteredToys = function() return 0 end,
    GetToyFromIndex = function() return nil end,
}
C_MountJournal = {
    GetNumDisplayedMounts = function() return 0 end,
    GetDisplayedMountInfo = function() return nil end,
    SetSourceFilter = function() end,
    IsSourceChecked = function() return true end,
    GetNumMountSourceFilters = function() return 2 end,
    SetAllSourceFilters = function() end,
    SetAllTypeFilters = function() end,
    SetCollectedFilterSetting = function() end,
    SetSearch = function(s) mountSearch = s; mountSearchCalls[#mountSearchCalls + 1] = s end,
}
ToyBox = { searchString = "wolf", searchBox = { GetText = function() return "wolf" end } }
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

local function cleared(calls)
    for i = 1, #calls do if calls[i] == "" then return true end end
    return false
end

print("Phase 1: Toy source grouping restores the toy search")
do
    toyFilterCalls = {}
    WarbandNexus:GetToysGroupedBySourceType()
    assert_eq(cleared(toyFilterCalls), true, "scan cleared the toy search")
    assert_eq(toyFilter, "wolf", "toy search restored to the player's text")
end

print("Phase 2: Mount source map restores the mount search")
do
    mountSearchCalls = {}
    ns._mountGroupedFromMapValid = false
    WarbandNexus:EnsureMountSourceIndexMap()
    assert_eq(cleared(mountSearchCalls), true, "scan cleared the mount search")
    assert_eq(mountSearch, "drake", "mount search restored to the player's text")
end

print("Phase 3: Chunked toy materialize restores the toy search")
do
    ns._toyItemIDToSourceIndex = nil
    toyFilterCalls = {}
    local Mat = ns.CollectionMaterialize
    local state
    for _ = 1, 50 do
        state = Mat.ToyBoxBuildMaterializeStep(1000, state, WarbandNexus)
        if state.done then break end
    end
    assert_eq(state and state.done, true, "materialize finished")
    assert_eq(cleared(toyFilterCalls), true, "materialize cleared the toy search")
    assert_eq(toyFilter, "wolf", "toy search restored after materialize")
end

print("Phase 4: Journal not loaded or secret text restores to empty")
do
    local savedToyBox = ToyBox
    ToyBox = nil
    toyFilter = "x"
    WarbandNexus:GetToysGroupedBySourceType()
    assert_eq(toyFilter, "", "no ToyBox frame: empty search")
    ToyBox = savedToyBox
    local secret = "secret-text"
    stub.secrets[secret] = true
    ToyBox.searchString = secret
    WarbandNexus:GetToysGroupedBySourceType()
    assert_eq(toyFilter, "", "secret search text is not passed back")
    stub.secrets[secret] = nil
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Journal search restore suite failed with " .. failed .. " failure(s).")
end
print("Journal search restore suite: ALL TESTS PASSED.")
