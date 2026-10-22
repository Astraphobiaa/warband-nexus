#!/usr/bin/env lua
--[[
    Regression test: PvECacheService.lua split (keystones / Mythic+ -> PvECacheService_MythicPlus.lua,
    Great Vault rewards / claim state / vault event handlers -> PvECacheService_Vault.lua).

    Static: the main file stays under the 4000-line / 120 top-level-local budget, both satellites are
    listed in the TOC right after PvECacheService.lua (they alias its ns.PvECacheService._bind at load)
    and before PvECacheService_VaultSelfTest.lua (first consumer of the moved vault methods), and each
    satellite asserts the bind table so a mis-ordered TOC fails loudly.
    Runtime: under wow_stub.lua main + satellites load, every moved public method is on WarbandNexus,
    every `local X = B.X` alias in a satellite resolves to a non-nil bind field, and the vault session
    flag is one shared table (the satellite reads what the main file's table holds).
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

local MAIN = "Modules/PvECacheService.lua"
local SATELLITES = {
    "Modules/PvECacheService_MythicPlus.lua",
    "Modules/PvECacheService_Vault.lua",
}
local FIRST_CONSUMER = "Modules/PvECacheService_VaultSelfTest.lua"

-- ---------- static: size budget ----------
print("Static: size budget, TOC order, bind assert")
local main = ReadFile(MAIN) or ""
local lineCount, topLocals = 0, 0
for line in (main .. "\n"):gmatch("([^\n]*)\n") do
    lineCount = lineCount + 1
    if line:match("^local%s") then topLocals = topLocals + 1 end
end
check(lineCount < 4000, "PvECacheService.lua under 4000 lines (" .. lineCount .. ")")
check(topLocals < 120, "PvECacheService.lua under 120 top-level locals (" .. topLocals .. ")")
check(main:find("ns.PvECacheService._bind = {", 1, true) ~= nil, "PvECacheService.lua publishes ns.PvECacheService._bind")

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
    check(satIdx and mainIdx and mainIdx < satIdx, sat .. " loads after PvECacheService.lua (bind table)")
    check(satIdx and consumerIdx and satIdx < consumerIdx, sat .. " loads before " .. FIRST_CONSUMER)
    local satSrc = ReadFile(sat) or ""
    check(satSrc:find("local B = assert(ns.PvECacheService and ns.PvECacheService._bind,", 1, true) ~= nil,
        sat .. " asserts ns.PvECacheService._bind")
end

-- ---------- runtime: load main + satellites under the stub ----------
print("Runtime: moved methods reachable and wired")
local ns = {}
local printed = {}
local WarbandNexus = {
    db = {
        global = {
            characters = {},
            pveCache = {
                mythicPlus = {}, greatVault = { activities = {}, rewards = {} },
                lockouts = { worldBosses = {}, raids = {}, dungeons = {} },
                delves = { characters = {}, companion = {} },
            },
        },
        profile = {}, char = {},
    },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function(_, msg) printed[#printed + 1] = msg end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
}

local function LoadFile(rel)
    local src = ReadFile(rel)
    if not src then return false, "missing file: " .. rel end
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then return false, err end
    return pcall(chunk, "WarbandNexus", ns)
end

local files = { "Modules/Constants.lua", "Modules/ResetService.lua", MAIN }
for s = 1, #SATELLITES do files[#files + 1] = SATELLITES[s] end
for i = 1, #files do
    local ok, err = LoadFile(files[i])
    check(ok, "loads " .. files[i] .. (ok and "" or (" -- " .. tostring(err))))
end

local moved = {
    -- PvECacheService_MythicPlus.lua
    "RequestKeystoneRefresh", "UpdateMythicPlusAffixes", "UpdateCharacterKeystone", "UpdateMythicPlusBestRuns",
    "UpdateDungeonScores", "UpdateMythicPlusRunHistory", "GetKeystoneSynergyMatrix", "GetKeystoneRerollRecommendations",
    -- PvECacheService_Vault.lua
    "UpdateGreatVaultActivities", "ProcessGreatVaultActivities", "UpdateGreatVaultRewards", "GetVaultDeadRunAnalysis",
    "RequestWeeklyVaultRefresh", "NotifyVaultEasyAccessRefresh", "HealStaleVaultRewardsCache", "PrintVaultDiagnostics",
    "RefreshVaultClaimState", "SchedulePostClaimVaultHeal", "EnsureWeeklyRewardsFrameHooks", "OnVaultDataReceived",
    "_OnVaultDataReceivedBody", "SyncVaultDataFromScanner",
}
for i = 1, #moved do
    check(type(WarbandNexus[moved[i]]) == "function", "WarbandNexus:" .. moved[i] .. " reachable")
end
check(type(WarbandNexus.UpdatePvEData) == "function" and type(WarbandNexus.RegisterPvECacheEvents) == "function",
    "PvECacheService.lua keeps UpdatePvEData / RegisterPvECacheEvents")

-- Every `local X = B.X` alias in a satellite must resolve: a missing bind field is a silent nil call later.
local B = ns.PvECacheService and ns.PvECacheService._bind
check(type(B) == "table", "ns.PvECacheService._bind built at load")
for s = 1, #SATELLITES do
    local satSrc = ReadFile(SATELLITES[s]) or ""
    local aliases, missing = 0, {}
    for name, field in satSrc:gmatch("\nlocal (%w[%w_]*) = B%.(%w[%w_]*)") do
        aliases = aliases + 1
        if name ~= field or not B or B[field] == nil then missing[#missing + 1] = field end
    end
    check(aliases > 0 and #missing == 0, SATELLITES[s] .. ": " .. aliases .. " bind aliases resolve"
        .. (#missing > 0 and (" (missing: " .. table.concat(missing, ", ") .. ")") or ""))
end

-- One copy of the vault session flag: the Vault satellite reads the main file's table.
if B and type(B.vaultState) == "table" and type(WarbandNexus.PrintVaultDiagnostics) == "function" then
    B.vaultState.vaultDataFreshThisSession = true
    pcall(WarbandNexus.PrintVaultDiagnostics, WarbandNexus)
    check(printed[1] and printed[1]:find("dataFresh=true", 1, true) ~= nil,
        "PrintVaultDiagnostics (Vault satellite) reads vaultState written through the main file's table")
else
    check(false, "vaultState shared table and PrintVaultDiagnostics present")
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
