#!/usr/bin/env lua
--[[
    Regression test: login no longer force-loads Blizzard load-on-demand addons.

    Part 1 drives the shipped NotificationManager.lua under wow_stub.lua. Every
    ApplyBlizzardAchievementAlertSuppression() pass (login, retries, PLAYER_ENTERING_WORLD,
    settings toggles, the production Blizzard fallback) used to call
    LoadAddOn on six names -- Blizzard_AchievementUI plus four addons that do not exist in
    12.1.5 -- whether or not Warband achievement popups were on. AchievementAlertSystem,
    CriteriaAlertSystem and MonthlyActivityAlertSystem are defined in the always-loaded
    Blizzard_FrameXML/Mainline/AlertFrameSystems.lua (wow-ui-source live 12.1.5.70448), so the
    stub defines them up front exactly like the base UI does. Suppression now unregisters the
    matching AlertFrame events (no AddAlert swap, no taint) and must never load an addon.

    Part 2 drives the shipped AchievementFrameIntegration.lua: PLAYER_LOGIN used to load
    Blizzard_AchievementUI to warm the journal hooks. The hooks now attach when the player first
    opens the journal; the first open must still decorate the rows already on screen.
]]

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg)
    end
end
local function assert_eq(actual, expected, msg)
    check(actual == expected, string.format("%s (expected %s, got %s)", msg, tostring(expected), tostring(actual)))
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

-- ---------- load-on-demand model ----------
-- LoadAddOn on a real LoD addon marks it loaded, runs its "file body" and fires ADDON_LOADED;
-- unknown names answer like the client does for a missing addon (false, "MISSING").
local loaded, loadCalls, loadNames = {}, 0, {}
local onLoadBody = {}
local continueQueue = {}
local LOD_ADDONS = { Blizzard_AchievementUI = true }
local function SimulateAddOnLoaded(name)
    loaded[name] = true
    if onLoadBody[name] then onLoadBody[name]() end
    stub.Fire("ADDON_LOADED", name)
    local q = continueQueue[name]
    continueQueue[name] = nil
    if q then for i = 1, #q do q[i]() end end
end
C_AddOns = {
    IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end,
    GetAddOnMetadata = function() return nil end,
    LoadAddOn = function(name)
        loadCalls = loadCalls + 1
        loadNames[#loadNames + 1] = name
        if not LOD_ADDONS[name] then return false, "MISSING" end
        if not loaded[name] then SimulateAddOnLoaded(name) end
        return true
    end,
}
-- Blizzard_SharedXML/EventUtil.lua (live 12.1.5): runs now when loaded, else once on ADDON_LOADED.
EventUtil = {
    ContinueOnAddOnLoaded = function(name, cb)
        if loaded[name] then cb(); return end
        continueQueue[name] = continueQueue[name] or {}
        table.insert(continueQueue[name], cb)
    end,
}
-- hooksecurefunc([tbl,] name, post): real post-hook so hooks installed by the addon actually run.
local hooked = {}
hooksecurefunc = function(a, b, c)
    local tbl, name, post = _G, a, b
    if type(a) == "table" then tbl, name, post = a, b, c end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig(...) }
        post(...)
        return unpack(r)
    end
    hooked[name] = (hooked[name] or 0) + 1
end
MAX_ACHIEVEMENT_ALERTS = 4
local categoryIDs = {}
for i = 1, 100 do categoryIDs[i] = 1000 + i end
GetCategoryList = function() return categoryIDs end
GetCategoryInfo = function() return "Category", -1 end
GetAchievementInfo = function(id) return id, "Ach", 10, false end
PlaySound = function() end

-- Base-UI alert systems (Blizzard_FrameXML/Mainline/AlertFrameSystems.lua:419/432/1451).
local blizzShown = {}
local function MakeSystem(label)
    local sys = {}
    sys.AddAlert = function(_, ...) blizzShown[#blizzShown + 1] = label end
    return sys, sys.AddAlert
end
local origAch, origCrit, origMonthly
AchievementAlertSystem, origAch = MakeSystem("achievement")
CriteriaAlertSystem, origCrit = MakeSystem("criteria")
MonthlyActivityAlertSystem, origMonthly = MakeSystem("monthly")
-- Blizzard_FrameXML AlertFrame: suppression unregisters its events (C call, no Lua taint).
local alertEvents = { ACHIEVEMENT_EARNED = true, CRITERIA_EARNED = true, PERKS_ACTIVITY_COMPLETED = true }
AlertFrame = {
    UnregisterEvent = function(_, ev) alertEvents[ev] = false end,
    RegisterEvent = function(_, ev) alertEvents[ev] = true end,
}

-- ---------- addon shell ----------
local ns = {}
local notifDb = { enabled = true, hideBlizzardAchievementAlert = false, showCriteriaProgressNotifications = true }
local WarbandNexus = {
    db = { global = { characters = {}, plans = {} }, profile = { notifications = notifDb }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.L = setmetatable({}, { __index = function(_, k) return k end })
-- Satellites NotificationManager.lua asserts on; their contents are not exercised here.
ns.NotificationToastFx = {}
ns.NotificationToastChrome = {}
ns.NotificationAlertStack = {}
ns.NotificationChangelog = {}
ns.CHANGELOG = {}

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""):gsub("\r\n", "\n"))
end
local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/NotificationManager_Presentation.lua")
LoadFile("Modules/NotificationManager.lua")

-- ---------- Part 1: alert suppression ----------
print("Part 1: alert suppression attaches without load-on-demand addons")

-- Warband popups OFF at login.
WarbandNexus:InitializeNotificationListeners()
stub.Advance(0.6)
stub.Fire("PLAYER_ENTERING_WORLD")
stub.Advance(6)
assert_eq(loadCalls, 0, "setting off: login + PLAYER_ENTERING_WORLD call LoadAddOn zero times")
check(not loaded.Blizzard_AchievementUI, "setting off: Blizzard_AchievementUI stays unloaded")
check(alertEvents.ACHIEVEMENT_EARNED and alertEvents.CRITERIA_EARNED and alertEvents.PERKS_ACTIVITY_COMPLETED,
    "setting off: Blizzard AlertFrame keeps all its alert events")

-- Player turns Warband achievement popups ON later (SettingsUI setter: write db, re-apply).
notifDb.hideBlizzardAchievementAlert = true
WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
stub.Advance(3)
assert_eq(loadCalls, 0, "turned on later: still zero LoadAddOn calls")
check(alertEvents.ACHIEVEMENT_EARNED == false, "turned on later: ACHIEVEMENT_EARNED unregistered on AlertFrame")
check(alertEvents.CRITERIA_EARNED == false, "turned on later: CRITERIA_EARNED unregistered on AlertFrame")
check(alertEvents.PERKS_ACTIVITY_COMPLETED == false, "turned on later: PERKS_ACTIVITY_COMPLETED unregistered on AlertFrame")
-- The taint-free design never swaps Blizzard's AddAlert functions.
check(AchievementAlertSystem.AddAlert == origAch, "turned on later: AchievementAlertSystem.AddAlert untouched")
check(CriteriaAlertSystem.AddAlert == origCrit, "turned on later: CriteriaAlertSystem.AddAlert untouched")
check(MonthlyActivityAlertSystem.AddAlert == origMonthly, "turned on later: MonthlyActivityAlertSystem.AddAlert untouched")

-- Journal opened later by the player: suppression state is unaffected.
SimulateAddOnLoaded("Blizzard_AchievementUI")
stub.Advance(6)
check(alertEvents.ACHIEVEMENT_EARNED == false, "after Blizzard_AchievementUI loads: still unregistered")

-- Criteria toast toggled off: Blizzard keeps criteria + Traveler's Log alerts, WN keeps the earned lane.
notifDb.showCriteriaProgressNotifications = false
WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
check(alertEvents.CRITERIA_EARNED and alertEvents.PERKS_ACTIVITY_COMPLETED, "criteria lane off: Blizzard criteria/progress events re-registered")
check(alertEvents.ACHIEVEMENT_EARNED == false, "criteria lane off: earned lane still WN")
notifDb.showCriteriaProgressNotifications = true

-- Turned back OFF: every event we unregistered is registered again.
notifDb.hideBlizzardAchievementAlert = false
WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
check(alertEvents.ACHIEVEMENT_EARNED and alertEvents.CRITERIA_EARNED and alertEvents.PERKS_ACTIVITY_COMPLETED,
    "turned off: all Blizzard alert events registered again")
assert_eq(loadCalls, 0, "part 1: zero LoadAddOn calls overall")
assert_eq(#stub.errors, 0, "part 1: no errors in timers / event handlers" .. (stub.errors[1] and (" -- " .. stub.errors[1]) or ""))

-- ---------- Part 2: achievement journal integration ----------
print("Part 2: journal integration attaches when the player opens it")
loaded.Blizzard_AchievementUI = nil
loadCalls, loadNames = 0, {}
stub.Reset()

local invalidations = 0
ns.UI_InvalidateAchievementCategoryCaches = function() invalidations = invalidations + 1 end
local rowSweeps = 0
-- Blizzard_AchievementUI_Bootstrap.lua is always loaded: ToggleAchievementFrame -> LoadUI -> toggle.
AchievementFrame_LoadUI = function() return C_AddOns.LoadAddOn("Blizzard_AchievementUI") end
ToggleAchievementFrame = function()
    if AchievementFrame_LoadUI() then AchievementFrame_ToggleAchievementFrame() end
end
onLoadBody.Blizzard_AchievementUI = function()
    AchievementTemplateMixin = { Init = function() end }
    AchievementFrame = { IsShown = function() return true end }
    AchievementFrameAchievements = {
        ScrollBox = { ForEachFrame = function() rowSweeps = rowSweeps + 1 end },
    }
    AchievementFrame_ToggleAchievementFrame = function() end
end

LoadFile("Modules/AchievementFrameIntegration.lua")
stub.Fire("PLAYER_LOGIN")
stub.Advance(10)
assert_eq(loadCalls, 0, "PLAYER_LOGIN warmup calls LoadAddOn zero times")
check(not loaded.Blizzard_AchievementUI, "PLAYER_LOGIN warmup leaves Blizzard_AchievementUI unloaded")
check(invalidations >= 1, "PLAYER_LOGIN warmup still drops WN achievement category caches")

-- First open by the player.
ToggleAchievementFrame()
stub.Advance(1)
check(loaded.Blizzard_AchievementUI, "first open loads Blizzard_AchievementUI (Blizzard's own path)")
check((hooked.Init or 0) >= 1, "first open: AchievementTemplateMixin.Init row hook installed")
check(rowSweeps >= 1, "first open: rows already on screen are swept for the WN button")
assert_eq(#stub.errors, 0, "part 2: no errors in timers / event handlers" .. (stub.errors[1] and (" -- " .. stub.errors[1]) or ""))

print(string.format("Total: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
