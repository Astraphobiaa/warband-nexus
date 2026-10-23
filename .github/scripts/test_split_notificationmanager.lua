#!/usr/bin/env lua
--[[
    Regression test: NotificationManager.lua split (test / QA commands -> NotificationManager_Tests.lua).

    Static: the main file stays under the 4000-line / 120 top-level-local budget, the satellite is
    listed in the TOC right after NotificationManager.lua (it reuses the main file's test helpers)
    and asserts the shared table it reads.
    Runtime: under wow_stub.lua the satellite loads after the main file, every moved public command is
    on WarbandNexus, and the moved code reaches the helpers / tables the main file still owns.
]]

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then passed = passed + 1; print("  ok   " .. msg)
    else failed = failed + 1; print("  FAIL " .. msg) end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

local function ReadFile(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""):gsub("\r\n", "\n"))
end

-- ---------- static: size budget ----------
print("Static: size budget and TOC order")
local main = ReadFile("Modules/NotificationManager.lua") or ""
local lineCount, topLocals = 0, 0
for line in (main .. "\n"):gmatch("([^\n]*)\n") do
    lineCount = lineCount + 1
    if line:match("^local%s") then topLocals = topLocals + 1 end
end
check(lineCount < 4000, "NotificationManager.lua under 4000 lines (" .. lineCount .. ")")
check(topLocals < 120, "NotificationManager.lua under 120 top-level locals (" .. topLocals .. ")")

-- ---------- static: TOC order ----------
local toc = ReadFile("WarbandNexus.toc") or ""
local tocIndex, n = {}, 0
for line in toc:gmatch("[^\n]+") do
    n = n + 1
    local rel = line:gsub("\\", "/"):gsub("%s+$", "")
    if not tocIndex[rel] then tocIndex[rel] = n end
end
local satIdx = tocIndex["Modules/NotificationManager_Tests.lua"]
local mainIdx = tocIndex["Modules/NotificationManager.lua"]
check(satIdx ~= nil, "NotificationManager_Tests.lua listed in the TOC")
check(satIdx and mainIdx and satIdx == mainIdx + 1, "NotificationManager_Tests.lua loads right after NotificationManager.lua")
local needs = { "Modules/Constants.lua", "Modules/NotificationManager_Presentation.lua",
    "Modules/NotificationManager_ToastChrome.lua", "Modules/NotificationManager_AlertStack.lua" }
for i = 1, #needs do
    local idx = tocIndex[needs[i]]
    check(satIdx and idx and idx < satIdx, "NotificationManager_Tests.lua loads after " .. needs[i])
end

-- ---------- static: satellite asserts its shared table ----------
local sat = ReadFile("Modules/NotificationManager_Tests.lua") or ""
check(sat:find('assert(Hooks and Hooks.TestLootFireAchievementAddAlert, "NotificationManager_Tests: load NotificationManager.lua first")', 1, true) ~= nil,
    "satellite asserts ns.NotificationManagerHooks")

-- ---------- runtime: load main + satellite under the stub ----------
print("Runtime: moved commands reachable and wired")
local addAlertCalls = {}
AchievementAlertSystem = { AddAlert = function(_, ...) addAlertCalls[#addAlertCalls + 1] = { ... } end }
GetAchievementInfo = function(id) return id, "Ach", 10, false end
GetAchievementNumCriteria = function() return 3 end
PlaySound = function() end
strlower = strlower or string.lower -- WoW global (FrameXML string alias)

local ns = {}
local notifDb = { enabled = true, hideBlizzardAchievementAlert = false, showCriteriaProgressNotifications = true }
local printed = {}
local WarbandNexus = {
    db = { global = { characters = {}, plans = {} }, profile = { notifications = notifDb }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function(_, msg) printed[#printed + 1] = msg end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return true end
ns.L = setmetatable({}, { __index = function(_, k) return k end })
-- Satellites NotificationManager.lua asserts on; their contents are not exercised here.
ns.NotificationToastFx = {}
ns.NotificationToastChrome = {}
ns.NotificationAlertStack = {}
ns.NotificationChangelog = {}
ns.CHANGELOG = {}

local function LoadFile(rel)
    local src = ReadFile(rel)
    if not src then return false, "missing file: " .. rel end
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then return false, err end
    return pcall(chunk, "WarbandNexus", ns)
end

local loadedAll = true
local files = { "Modules/Constants.lua", "Modules/Utilities.lua", "Modules/NotificationManager_Presentation.lua",
    "Modules/NotificationManager.lua", "Modules/NotificationManager_Tests.lua" }
for i = 1, #files do
    local ok, err = LoadFile(files[i])
    check(ok, "loads " .. files[i] .. (ok and "" or (" -- " .. tostring(err))))
    if not ok then loadedAll = false end
end

local moved = {
    "PrintNotificationTestHelp", "TestAchievementAlertEarn", "TestAchievementAlertProgress",
    "TestAchievementEarnedEvent", "RunNotificationSlashCommand", "TestAlertTest", "TestNotificationStack",
    "TestProgressAlert", "TestAchievementAlertHierarchy", "TestLootNotification", "TestNotificationEvents",
    "TestNotificationEffects", "TestVaultCheck",
}
for i = 1, #moved do
    check(type(WarbandNexus[moved[i]]) == "function", "WarbandNexus:" .. moved[i] .. " reachable")
end
local kept = { "OnPerksActivityCompleted", "ApplyBlizzardAchievementAlertSuppression",
    "ShowModalNotification", "OnVaultSlotCompleted" }
for i = 1, #kept do
    check(type(WarbandNexus[kept[i]]) == "function", "WarbandNexus:" .. kept[i] .. " still in the main file")
end

if loadedAll then
    -- Earn test never calls Blizzard's AddAlert (taint); with Warband popups ON it drives the WN handler.
    addAlertCalls = {}
    WarbandNexus:TestAchievementAlertEarn(6)
    check(#addAlertCalls == 0, "/wn notif earn (popups off) does not call AchievementAlertSystem:AddAlert")
    local shownID
    local prevShow = WarbandNexus.ShowAchievementNotification
    WarbandNexus.ShowAchievementNotification = function(_, id) shownID = id; return true end
    notifDb.hideBlizzardAchievementAlert = true
    WarbandNexus:TestAchievementAlertEarn(6)
    notifDb.hideBlizzardAchievementAlert = false
    WarbandNexus.ShowAchievementNotification = prevShow
    check(#addAlertCalls == 0 and shownID == 6, "/wn notif earn (popups on) reaches ShowAchievementNotification(6)")

    -- Traveler's Log test reaches the WN toast with the main file's icon atlas.
    local progressPayload
    WarbandNexus.ShowGenericProgressNotification = function(_, payload) progressPayload = payload; return true end
    WarbandNexus:TestProgressAlert()
    check(progressPayload and progressPayload.iconAtlas == "activities-toast-icon", "/wn notif traveler uses the Traveler's Log atlas")

    -- Vault progress sample reads the main file's VAULT_CATEGORIES.
    local shown
    local realShow = WarbandNexus.ShowModalNotification
    WarbandNexus.ShowModalNotification = function(_, config) shown = config; return true end
    WarbandNexus:TestLootNotification("vaultprogress")
    WarbandNexus.ShowModalNotification = realShow
    check(shown and shown.itemName == "DUNGEON_CAT" and shown.iconAtlas == "questlog-questtypeicon-heroic",
        "/wn testloot vaultprogress uses VAULT_CATEGORIES.dungeon")
    stub.Advance(1)
    check(#stub.errors == 0, "no errors in timers" .. (stub.errors[1] and (" -- " .. stub.errors[1]) or ""))
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("NotificationManager split suite failed with " .. failed .. " failure(s).")
end
print("NotificationManager split suite: ALL TESTS PASSED.")
