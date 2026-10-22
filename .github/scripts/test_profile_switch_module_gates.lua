#!/usr/bin/env lua
--[[
    Regression test: profile switching, module gates and plans leftovers.

      1. Profile switch runs the profile-scoped migrations (theme / font / toast lanes / dead keys) for the
         profile switched to; they used to run at login for the active profile only.
      2. Profile switch / reset re-syncs modules whose enabled state changed: the ModuleManager setter runs
         (PvP event registration etc.) and WN_MODULE_TOGGLED reaches the listeners. Unchanged modules stay quiet.
      3. Config.lua AceConfig module toggles go through the ModuleManager setters (side effects included).
      4. Dead profile.notifications keys (dismissedNotifications, lastVaultCheck) are pruned, defaults dropped.
      5. Weekly / daily reset sweeps leave plan rows alone and send no PLANS_UPDATED while Plans is off.
      6. Recipe plans do not trigger the warband-wide material walk on every completion pass.
      7. Currency events stop only when no consumer module is on; a consumer re-enable rescans once.
      8. PlansManager reset helpers are thin ResetService delegates.

    Loads AceDB-3.0, MigrationService, ModuleManager and CurrencyCacheService under wow_stub.lua; the Core
    profile block, Config's toggle handler and the plans / daily-quest functions are extracted from their files.
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

UnitClass = function() return "Warrior", "WARRIOR" end
UnitRace = function() return "Human", "Human" end
UnitFactionGroup = function() return "Alliance" end
GetLocale = function() return "enUS" end
GetCurrentRegion = function() return 3 end
GetCurrentRegionName = function() return "EU" end
securecallfunction = function(fn, ...) return fn(...) end
InCombatLockdown = function() return false end

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

-- Tiny AceEvent-like message bus: RegisterMessage(selfOrSink, msg, fn) + SendMessage dispatch.
local function NewAddon(ns)
    local addon = { messages = {}, _listeners = {} }
    function addon.RegisterMessage(owner, msg, fn)
        local list = addon._listeners[msg] or {}
        addon._listeners[msg] = list
        list[owner] = fn
    end
    function addon:SendMessage(msg, ...)
        self.messages[#self.messages + 1] = { msg = msg, a = select(1, ...), b = select(2, ...) }
        local list = self._listeners[msg]
        if list then
            for _, fn in pairs(list) do fn(msg, ...) end
        end
    end
    addon.Print = function() end
    ns.WarbandNexus = addon
    ns.DebugPrint = function() end
    ns.DebugVerbosePrint = function() end
    ns.IsDebugModeEnabled = function() return false end
    return addon
end

local function LoadFile(rel, ns)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

-- Pull one top-level `function WarbandNexus:Name(...)` out of a file and install it on `addon`.
local function Extract(rel, name, addon, ns, prelude)
    local body = ReadFile(rel):match("(function WarbandNexus:" .. name .. "%(.-\nend)\n")
    if not body then return false end
    local chunk = assert(loadstring("local WarbandNexus, ns = ...\n" .. (prelude or "") .. "\n" .. body,
        "@" .. rel .. ":" .. name))
    chunk(addon, ns)
    return true
end

-- Real Utilities:IsModuleEnabled / IsAnyModuleEnabled.
local function InstallModuleChecks(ns)
    ns.Utilities = ns.Utilities or {}
    local src = ReadFile("Modules/Utilities.lua")
    local a = assert(src:match("(function Utilities:IsModuleEnabled%(.-\nend)\n"))
    local b = assert(src:match("(function Utilities:IsAnyModuleEnabled%(.-\nend)\n"))
    assert(loadstring("local ns = ...\nlocal Utilities = ns.Utilities\n" .. a .. "\n" .. b))(ns)
end

local function CountMsg(addon, msg, a, b)
    local n = 0
    for i = 1, #addon.messages do
        local m = addon.messages[i]
        if m.msg == msg and (a == nil or m.a == a) and (b == nil or m.b == b) then n = n + 1 end
    end
    return n
end

-- ---------------------------------------------------------------------------
local ns = {}
local WarbandNexus = NewAddon(ns)
LoadFile("libs/LibStub/LibStub.lua", ns)
LoadFile("libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", ns)
LoadFile("libs/AceDB-3.0/AceDB-3.0.lua", ns)
LoadFile("Locales/enUS.lua", ns)
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua", ns)
local E = ns.Constants.EVENTS
LoadFile("Modules/MigrationService.lua", ns)
LoadFile("Modules/ModuleManager.lua", ns)
InstallModuleChecks(ns)
ns.Utilities.GetCanonicalCharacterKey = function(_, k) return k end
ns.Utilities.GetCharacterKey = function() return "Alpha-Kazzak" end
local MS = ns.MigrationService

local pvpToggles, rechargeStops = {}, 0
ns.PvPService = { OnModuleToggled = function(_, enabled) pvpToggles[#pvpToggles + 1] = enabled end }
function WarbandNexus:StopRechargeTimer() rechargeStops = rechargeStops + 1 end
function WarbandNexus:ResetStorageTreeExpandState() end

-- Module toggle helpers live in ModuleManager (loaded above); OnProfileChanged comes from Core.
assert(Extract("Core.lua", "OnProfileChanged", WarbandNexus, ns))

local MODULE_KEYS = { "currencies", "reputations", "items", "storage", "pve", "pvp",
    "plans", "professions", "gear", "collections", "tryCounter" }
local moduleDefaults = {}
for i = 1, #MODULE_KEYS do moduleDefaults[MODULE_KEYS[i]] = true end

WarbandNexusProfileTestDB = {}
local db = LibStub("AceDB-3.0"):New("WarbandNexusProfileTestDB", {
    profile = { modulesEnabled = moduleDefaults, notifications = { enabled = true } },
    global = {},
}, true)
WarbandNexus.db = db
db.global._schemaVersion = 13
MS:RunMigrations(db)
if WarbandNexus.TrackModuleEnabledState then WarbandNexus:TrackModuleEnabledState() end
db.RegisterCallback(WarbandNexus, "OnProfileChanged", "OnProfileChanged")
db.RegisterCallback(WarbandNexus, "OnProfileCopied", "OnProfileChanged")
db.RegisterCallback(WarbandNexus, "OnProfileReset", "OnProfileChanged")

print("Phase 1: switching to an unmigrated profile runs the profile-scoped steps")
db.sv.profiles["Alt"] = {
    lightMode = true,
    modulesEnabled = { pvp = false, collections = false },
    fonts = { scalePreset = "large" },
    notifications = { dismissedNotifications = { 4 }, lastVaultCheck = 77, popupPoint = "LEFT" },
}
db:SetProfile("Alt")
local p = db.profile
assert_eq(p.themeMode, "light", "legacy lightMode migrated to themeMode")
assert_eq(p.themeModeMigratedV1, true, "theme-mode flag stamped on the new profile")
assert_eq(p.uiThemeMigratedV2, true, "ui-theme split ran on the new profile")
assert_eq(p.fonts.scaleCustom, 1.2, "font scale preset resolved on the new profile")
assert_eq(p.notifications.tryCounterToastPoint, "LEFT", "toast lane anchor seeded from the legacy anchor")
assert_eq(p.notifications.dismissedNotifications, nil, "dead key dismissedNotifications pruned")
assert_eq(p.notifications.lastVaultCheck, nil, "dead key lastVaultCheck pruned")

print("Phase 2: switching re-syncs only the modules whose state changed")
assert_eq(#pvpToggles, 1, "PvP setter ran once on the switch")
assert_eq(pvpToggles[1], false, "PvP setter told the module is off")
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED, "pvp", false), 1, "MODULE_TOGGLED(pvp, false)")
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED, "collections", false), 1, "MODULE_TOGGLED(collections, false)")
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED), 2, "no message for unchanged modules")
WarbandNexus.messages = {}
db:SetProfile("Default")
assert_eq(pvpToggles[2], true, "switching back re-enables PvP through its setter")
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED, "collections", true), 1, "MODULE_TOGGLED(collections, true)")
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED), 2, "two modules flipped back, two messages")

print("Phase 2b: a mid-session toggle is tracked, so a profile reset re-syncs it")
-- Settings > Modules path for gear: write the flag, send the message.
db.profile.modulesEnabled.gear = false
WarbandNexus:SendMessage(E.MODULE_TOGGLED, "gear", false)
WarbandNexus.messages = {}
db:ResetProfile()
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED, "gear", true), 1, "reset re-enables gear for its listeners")
assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED), 1, "only gear changed")

print("Phase 3: Config.lua AceConfig toggles go through the ModuleManager setters")
do
    local src = ReadFile("Config.lua")
    local body = assert(src:match("(local function CreateModuleToggleHandler%(moduleName%).-\nend)\n"))
    local make = assert(loadstring("local WarbandNexus, E = ...\n" .. body .. "\nreturn CreateModuleToggleHandler",
        "@Config.lua:CreateModuleToggleHandler"))(WarbandNexus, E)
    WarbandNexus.messages = {}
    local before = rechargeStops
    make("professions")(nil, false)
    assert_eq(db.profile.modulesEnabled.professions, false, "flag written")
    assert_eq(rechargeStops, before + 1, "professions setter side effect ran (recharge timer stopped)")
    assert_eq(CountMsg(WarbandNexus, E.MODULE_TOGGLED, "professions", false), 1, "MODULE_TOGGLED sent once")
    make("professions")(nil, true)
end

print("Phase 4: dead notification keys pruned on a fast-path login; defaults dropped")
do
    local ddb = { global = { _schemaVersion = 13, _wnMigrationFastPathRev = 7, characters = {} },
        profile = { notifications = { dismissedNotifications = {}, lastVaultCheck = 5, keep = 1 } }, char = {}, sv = {} }
    MS:RunMigrations(ddb)
    assert_eq(ddb.profile.notifications.dismissedNotifications, nil, "dismissedNotifications removed")
    assert_eq(ddb.profile.notifications.lastVaultCheck, nil, "lastVaultCheck removed")
    assert_eq(ddb.profile.notifications.keep, 1, "other notification keys kept")
    local defaultsBlock = ReadFile("Core.lua"):match("local defaults = {.-\n}\n") or ""
    assert_eq(defaultsBlock:find("dismissedNotifications", 1, true), nil, "no dismissedNotifications default")
    assert_eq(defaultsBlock:find("lastVaultCheck", 1, true), nil, "no lastVaultCheck default")
end

print("Phase 5: reset sweeps do nothing to plans while the Plans module is off")
do
    local planCalls = { prune = 0, reset = 0 }
    function WarbandNexus:HasDailyResetOccurredSince() return true end
    function WarbandNexus:HasWeeklyResetOccurredSince() return true end
    function WarbandNexus:GetWeeklyResetTime() return 10 * 86400 end
    function WarbandNexus:PruneAllPvEWeeklyData() planCalls.prune = planCalls.prune + 1 end
    function WarbandNexus:ResetWeeklyPlans() planCalls.reset = planCalls.reset + 1 end
    assert(Extract("Modules/PlansManager.lua", "CheckRecurringPlanResets", WarbandNexus, ns,
        "local E = ns.Constants.EVENTS"))
    assert(Extract("Modules/PlansManager_Vault.lua", "CheckWeeklyReset", WarbandNexus, ns,
        "local PLAN_TYPES = { WEEKLY_VAULT = 'weekly_vault' }"))
    local dqPrelude = "local E = ns.Constants.EVENTS\nlocal function GetDailyQuestPlansForCharKey() return nil end"
    assert(Extract("Modules/DailyQuestManager.lua", "UpdateDailyQuestWeeklyReset", WarbandNexus, ns, dqPrelude))
    assert(Extract("Modules/DailyQuestManager.lua", "RefreshDailyQuestsOnDailyReset", WarbandNexus, ns, dqPrelude))

    local plan = { completed = true, resetCycle = { enabled = true, resetType = "daily", lastResetTime = 1, infiniteRepeat = true } }
    db.global.customPlans = { plan }
    db.global.plans = {}
    WarbandNexus._weeklyVaultPlansList = { { type = "weekly_vault", lastReset = 0 } }

    db.profile.modulesEnabled.plans = false
    WarbandNexus.messages = {}
    WarbandNexus:CheckRecurringPlanResets()
    WarbandNexus:CheckWeeklyReset()
    WarbandNexus:UpdateDailyQuestWeeklyReset()
    WarbandNexus:RefreshDailyQuestsOnDailyReset()
    assert_eq(plan.completed, true, "recurring plan not reopened while Plans is off")
    assert_eq(planCalls.reset, 0, "vault plans not reset while Plans is off")
    assert_eq(planCalls.prune, 1, "PvE weekly prune still runs (not a plans write)")
    assert_eq(CountMsg(WarbandNexus, E.PLANS_UPDATED), 0, "no PLANS_UPDATED while Plans is off")

    db.profile.modulesEnabled.plans = true
    WarbandNexus:CheckRecurringPlanResets()
    WarbandNexus:CheckWeeklyReset()
    WarbandNexus:UpdateDailyQuestWeeklyReset()
    WarbandNexus:RefreshDailyQuestsOnDailyReset()
    assert_eq(plan.completed, false, "recurring plan reopened with Plans on")
    assert_eq(planCalls.reset, 1, "stale vault plans reset with Plans on")
    assert_eq(CountMsg(WarbandNexus, E.PLANS_UPDATED), 3, "recurring + weekly + daily PLANS_UPDATED with Plans on")

    -- Re-enable rescan covers the recurring reset that was skipped while off.
    local pmSrc = ReadFile("Modules/PlansManager.lua")
    local toggleBlock = pmSrc:match("E%.MODULE_TOGGLED, function%(_, moduleName, enabled%)(.-)\n    end%)") or ""
    assert_eq(toggleBlock:find("CheckRecurringPlanResets", 1, true) ~= nil, true,
        "Plans re-enable reruns CheckRecurringPlanResets")
end

print("Phase 6: recipe plans skip the material walk in CheckPlansForCompletion")
do
    local walks = 0
    function WarbandNexus:CheckMaterialsAcrossWarband() walks = walks + 1; return {} end
    function WarbandNexus:ShowPlanCompletedNotification() end
    function WarbandNexus:RebuildIncompleteTodoPlansList() end
    C_MountJournal = { GetMountInfoByID = function() return "Mount", nil, nil, nil, nil, nil, nil, nil, nil, nil, true end }
    local prelude = "local E = ns.Constants.EVENTS\nlocal PLAN_TYPES = { MOUNT = 'mount', PET = 'pet', TOY = 'toy', "
        .. "RECIPE = 'recipe', ACHIEVEMENT = 'achievement', ILLUSION = 'illusion', TITLE = 'title', WEEKLY_VAULT = 'weekly_vault' }"
    assert(Extract("Modules/PlansManager.lua", "CheckPlanProgress", WarbandNexus, ns, prelude))
    assert(Extract("Modules/PlansManager.lua", "CheckPlansForCompletion", WarbandNexus, ns, prelude))
    local mount = { id = 2, type = "mount", mountID = 5 }
    db.global.plans = { { id = 1, type = "recipe", reagents = { { itemID = 1, quantity = 1 } } }, mount }
    WarbandNexus._incompleteTodoPlansList = nil
    WarbandNexus:CheckPlansForCompletion()
    WarbandNexus:CheckPlansForCompletion()
    assert_eq(walks, 0, "no warband material walk for a recipe plan")
    assert_eq(mount.completed, true, "other plans are still checked")
end

print("Phase 7: currency events stop only when no consumer module is on")
do
    local cns = {}
    local CW = NewAddon(cns)
    CW.db = { global = { characters = {} }, profile = { modulesEnabled = {} }, char = {} }
    local handlers = {}
    function CW:RegisterEvent(ev, fn) handlers[ev] = fn end
    cns.Utilities = {
        GetCharacterKey = function() return "Alpha-Kazzak" end,
        GetCharacterStorageKey = function() return "Alpha-Kazzak" end,
        GetCanonicalCharacterKey = function(_, k) return k end,
    }
    InstallModuleChecks(cns)
    cns.CharacterService = { IsCharacterTracked = function() return true end }
    C_CurrencyInfo = { GetCurrencyInfo = function() return nil end }
    LoadFile("Modules/Constants.lua", cns)
    LoadFile("Modules/CurrencyCacheService.lua", cns)
    local CC = cns.CurrencyCache
    local fullScans, syncs = 0, 0
    CC.PerformFullScan = function() fullScans = fullScans + 1 end
    CC.PerformActualSync = function() syncs = syncs + 1 end
    CW:RegisterCurrencyCacheEvents()

    local m = CW.db.profile.modulesEnabled
    m.currencies, m.gear, m.professions, m.pvp, m.pve = false, false, false, false, false
    CC.updateQueue = {}
    handlers["CURRENCY_DISPLAY_UPDATE"]("CURRENCY_DISPLAY_UPDATE", 3008, 10, 1)
    handlers["ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED"]("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
    assert_eq(#CC.updateQueue, 0, "no queued update with every consumer off")
    assert_eq(syncs, 0, "no account sync with every consumer off")

    m.pve = true
    handlers["CURRENCY_DISPLAY_UPDATE"]("CURRENCY_DISPLAY_UPDATE", 3008, 11, 1)
    assert_eq(#CC.updateQueue, 1, "PvE tab alone keeps currency updates flowing")
    m.pve = false
    CW.db.profile.vaultButton = { enabled = true }
    handlers["CURRENCY_DISPLAY_UPDATE"]("CURRENCY_DISPLAY_UPDATE", 3008, 12, 1)
    assert_eq(#CC.updateQueue, 2, "Vault button alone keeps currency updates flowing")
    CW.db.profile.vaultButton = nil

    -- Re-enable after a dropped event: one catch-up scan.
    CC.updateQueue = {}
    m.currencies = true
    CW:SendMessage(cns.Constants.EVENTS.MODULE_TOGGLED, "currencies", true)
    CW:SendMessage(cns.Constants.EVENTS.MODULE_TOGGLED, "gear", true)
    stub.Advance(1)
    assert_eq(fullScans, 1, "one catch-up scan after the first consumer re-enable")
end

print("Phase 8: PlansManager reset helpers are thin ResetService delegates")
do
    local T = {}
    local tns = { ResetService = {
        HasDailyResetOccurred = function(ts) return "daily:" .. tostring(ts) end,
        HasWeeklyResetOccurred = function(ts) return "weekly:" .. tostring(ts) end,
        GetNextWeeklyResetTime = function() return 4242 end,
    } }
    assert(Extract("Modules/PlansManager.lua", "HasDailyResetOccurredSince", T, tns))
    assert(Extract("Modules/PlansManager.lua", "HasWeeklyResetOccurredSince", T, tns))
    assert(Extract("Modules/PlansManager_Vault.lua", "GetWeeklyResetTime", T, tns))
    assert_eq(T:HasDailyResetOccurredSince(7), "daily:7", "daily helper delegates")
    assert_eq(T:HasWeeklyResetOccurredSince(8), "weekly:8", "weekly helper delegates")
    assert_eq(T:GetWeeklyResetTime(), 4242, "weekly reset time delegates")
    local pm, pv = ReadFile("Modules/PlansManager.lua"), ReadFile("Modules/PlansManager_Vault.lua")
    local bodies = (pm:match("(function WarbandNexus:HasDailyResetOccurredSince%(.-\nend)\n") or "")
        .. (pm:match("(function WarbandNexus:HasWeeklyResetOccurredSince%(.-\nend)\n") or "")
        .. (pv:match("(function WarbandNexus:GetWeeklyResetTime%(.-\nend)\n") or "")
    assert_eq(bodies:find("C_DateAndTime", 1, true), nil, "no divergent C_DateAndTime fallback left")
end

assert_eq(#stub.errors, 0, "no errors inside timers / handlers")
for i = 1, #stub.errors do print("  error: " .. stub.errors[i]) end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profile switch / module gates suite failed with " .. failed .. " failure(s).")
end
print("Profile switch / module gates suite: ALL TESTS PASSED.")
