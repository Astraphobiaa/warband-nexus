#!/usr/bin/env lua
--[[
    Regression test: CollectionService.lua split (background scanning / COLLECTION_CONFIGS ->
    CollectionService_JournalScan.lua, metadata + toy source resolve -> CollectionService_Metadata.lua,
    GetUncollected* / GetCollected* -> CollectionService_Queries.lua, achievement scan + reward
    scanner -> CollectionService_Achievements.lua).

    Static: the main file stays under the 4000-line / 120 top-level-local budget, every satellite is
    listed in the TOC after CollectionService.lua (they bind its ns.CollectionServiceRT at load) and
    before PlansManager.lua (first file that calls the moved methods), and each satellite asserts RT
    so a mis-ordered TOC fails loudly.
    Runtime: under wow_stub.lua main + satellites load, every moved public method is on WarbandNexus,
    every `local X = RT.X` alias in a satellite resolves to a non-nil RT field, COLLECTION_CONFIGS and
    ResolveStoreRowDisplay are published on RT, and the results cache the Queries satellite reads is
    the one table the main file wipes.
]]

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
dofile(SCRIPT_DIR .. "/wow_stub.lua")

local function ReadFile(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""):gsub("\r\n", "\n"))
end

local MAIN = "Modules/CollectionService.lua"
local SATELLITES = {
    "Modules/CollectionService_JournalScan.lua",
    "Modules/CollectionService_Metadata.lua",
    "Modules/CollectionService_Queries.lua",
    "Modules/CollectionService_Achievements.lua",
}
local FIRST_CONSUMER = "Modules/PlansManager.lua"

-- ---------- static: size budget ----------
print("Static: size budget, TOC order, RT assert")
local main = ReadFile(MAIN) or ""
local lineCount, topLocals = 0, 0
for line in (main .. "\n"):gmatch("([^\n]*)\n") do
    lineCount = lineCount + 1
    if line:match("^local%s") then topLocals = topLocals + 1 end
end
check(lineCount < 4000, "CollectionService.lua under 4000 lines (" .. lineCount .. ")")
check(topLocals < 120, "CollectionService.lua under 120 top-level locals (" .. topLocals .. ")")

-- ---------- static: TOC order ----------
local toc = ReadFile("WarbandNexus.toc") or ""
local tocIndex, n = {}, 0
for line in toc:gmatch("[^\n]+") do
    n = n + 1
    local rel = line:gsub("\\", "/"):gsub("%s+$", "")
    if not tocIndex[rel] then tocIndex[rel] = n end
end
local mainIdx = tocIndex[MAIN]
local consumerIdx = tocIndex[FIRST_CONSUMER]
for s = 1, #SATELLITES do
    local sat = SATELLITES[s]
    local satIdx = tocIndex[sat]
    check(satIdx ~= nil, sat .. " listed in the TOC")
    check(satIdx and mainIdx and mainIdx < satIdx, sat .. " loads after CollectionService.lua (RT table)")
    check(satIdx and consumerIdx and satIdx < consumerIdx, sat .. " loads before " .. FIRST_CONSUMER)
    local satSrc = ReadFile(sat) or ""
    check(satSrc:find("local RT = assert(ns.CollectionServiceRT,", 1, true) ~= nil,
        sat .. " asserts ns.CollectionServiceRT")
end

-- ---------- runtime: load main + satellites under the stub ----------
print("Runtime: moved methods reachable and wired")
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
    IsModuleEnabled = function() return true end,
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
}

local function LoadFile(rel)
    local src = ReadFile(rel)
    if not src then return false, "missing file: " .. rel end
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then return false, err end
    return pcall(chunk, "WarbandNexus", ns)
end

local files = {
    "Locales/enUS.lua", "Modules/Constants.lua",
    "Modules/CollectionService_Materialize.lua", "Modules/CollectionService_NotifyDedup.lua",
    "Modules/CollectionService_Scan.lua", MAIN, "Modules/CollectionService_Store.lua",
}
for s = 1, #SATELLITES do files[#files + 1] = SATELLITES[s] end
for i = 1, #files do
    local ok, err = LoadFile(files[i])
    check(ok, "loads " .. files[i] .. (ok and "" or (" -- " .. tostring(err))))
    if files[i] == "Locales/enUS.lua" then ns.L = ns.LOCALES and ns.LOCALES.enUS end
end

local moved = {
    -- CollectionService_JournalScan.lua
    "ScanCollection",
    -- CollectionService_Metadata.lua
    "IsReliableToySource", "GetToySourceInfo", "ResolveCollectionMetadata", "ClearCollectionMetadataCache",
    -- CollectionService_Queries.lua
    "GetUncollectedMounts", "GetUncollectedPets", "GetUncollectedToys", "GetCollectedMounts", "GetCollectedPets",
    "GetCollectedToys", "GetCollectedIllusions", "GetCollectedTitles", "GetUncollectedAchievements",
    "GetCompletedAchievements", "GetUncollectedIllusions", "GetUncollectedTitles",
    -- CollectionService_Achievements.lua
    "ScanAchievementsAsync", "RecomputeCharacterAchievementPointsAsync", "GetAchievementRewardInfo",
    "EnhanceItemWithAchievement",
}
for i = 1, #moved do
    check(type(WarbandNexus[moved[i]]) == "function", "WarbandNexus:" .. moved[i] .. " reachable")
end
check(type(WarbandNexus.BuildFullCollectionData) == "function" and type(WarbandNexus.AbortCollectionScans) == "function",
    "CollectionService.lua keeps BuildFullCollectionData / AbortCollectionScans")

-- Every `local X = RT.X` alias in a satellite must resolve: a missing RT field is a silent nil call later.
local RT = ns.CollectionServiceRT
check(type(RT) == "table", "ns.CollectionServiceRT built at load")
for s = 1, #SATELLITES do
    local satSrc = ReadFile(SATELLITES[s]) or ""
    local aliases, missing = 0, {}
    for name, field in satSrc:gmatch("\nlocal (%w[%w_]*) = RT%.(%w[%w_]*)") do
        aliases = aliases + 1
        if name ~= field or not RT or RT[field] == nil then missing[#missing + 1] = field end
    end
    check(aliases > 0 and #missing == 0, SATELLITES[s] .. ": " .. aliases .. " RT aliases resolve"
        .. (#missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""))
end

-- BuildFullCollectionData (main) reads the configs the JournalScan satellite publishes.
local cfg = RT and RT.COLLECTION_CONFIGS
check(type(cfg) == "table" and type(cfg.mount) == "table" and type(cfg.mount.iterator) == "function",
    "RT.COLLECTION_CONFIGS published with mount.iterator")
check(RT and type(RT.ResolveStoreRowDisplay) == "function", "RT.ResolveStoreRowDisplay published")
-- The read-path save wrapper must not shadow Store's implementation on RT (that would recurse).
check(RT and type(RT.ScheduleDeferredCollectionStoreSave) == "function"
    and not (ReadFile(MAIN) or ""):find("RT.ScheduleDeferredCollectionStoreSave =", 1, true),
    "RT.ScheduleDeferredCollectionStoreSave stays Store's implementation")

-- One results cache: Queries serves what is in it, main's wipe (via Metadata's clear) empties it.
if RT and type(RT.uncollectedResultsCache) == "table" and WarbandNexus.GetUncollectedMounts
    and WarbandNexus.ClearCollectionMetadataCache then
    local sentinel = {}
    RT.uncollectedResultsCache["mount::nil"] = { r = sentinel, t = GetTime() }
    check(WarbandNexus:GetUncollectedMounts(nil) == sentinel, "Queries reads the main file's results cache")
    WarbandNexus:ClearCollectionMetadataCache()
    check(next(RT.uncollectedResultsCache) == nil, "main file's wipe empties the cache Queries reads")
else
    check(false, "results cache shared between main and Queries")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    print("CollectionService split suite: FAILED.")
    os.exit(1)
end
print("CollectionService split suite: ALL TESTS PASSED.")
