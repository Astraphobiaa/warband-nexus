#!/usr/bin/env lua
--[[
    Message hygiene and service layering (2026-10-22). Loads the shipped files under wow_stub.lua.

      1  TooltipService:Show / :Hide no longer send WN_TOOLTIP_SHOW / WN_TOOLTIP_HIDE (nobody listens;
         Show ran once per hovered row).
      2  DataService no longer redefines WarbandNexus:HasWeeklyResetOccurred with its own fallback:
         the ResetService shim stays the single source.
      3  ResetService:CheckAndTriggerResets sends both reset messages.
      4  The PvECache weekly-reset listener emits WN_PVE_UPDATED after it clears the weekly rows.
      5  CharacterService tracking prompts only send CHARACTER_TRACKING_DIALOG_REQUESTED; never call
         ns.CharacterTrackingDialog directly.
      6  A full SaveCurrentCharacterData refreshes pveCache once, without the GetPvEData read-back and
         ImportLegacyPvEData re-write.
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

local function LoadFile(ns, rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local function NewNS()
    local sent = {}
    local WN = {
        db = { global = { characters = {} }, profile = {}, char = {} },
        Print = function() end,
        RegisterEvent = function() end,
        RegisterBucketEvent = function() end,
        RegisterMessage = function() end,
    }
    function WN:SendMessage(ev, payload) sent[#sent + 1] = { ev = ev, payload = payload } end
    local ns = { WarbandNexus = WN }
    ns.DebugPrint = function() end
    ns.DebugVerbosePrint = function() end
    ns.IsDebugModeEnabled = function() return false end
    ns.L = setmetatable({}, { __index = function(_, k) return k end })
    return ns, WN, sent
end

local function CountSent(sent, ev)
    local n = 0
    for i = 1, #sent do if sent[i].ev == ev then n = n + 1 end end
    return n
end

print("Phase 1: tooltip Show / Hide send no unheard messages")
do
    local ns, WN, sent = NewNS()
    LoadFile(ns, "Modules/Constants.lua")
    ns.TooltipGameTooltip = { Install = function() end }
    GetScreenWidth = GetScreenWidth or function() return 1920 end
    GetScreenHeight = GetScreenHeight or function() return 1080 end
    local frame = setmetatable({ shown = false }, { __index = function() return function() return 0 end end })
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    ns.UI = { TooltipFactory = { CreateTooltipFrame = function() return frame end } }
    LoadFile(ns, "Modules/TooltipService.lua")
    local TS = ns.TooltipService
    local owner = setmetatable({}, { __index = function() return function() return 0 end end })
    TS:Show(owner, { type = "custom", lines = {} })
    assert_eq(frame.shown, true, "Show reached the end (frame shown)")
    TS:Hide()
    assert_eq(frame.shown, false, "Hide ran (frame hidden)")
    assert_eq(CountSent(sent, "WN_TOOLTIP_SHOW"), 0, "no WN_TOOLTIP_SHOW per tooltip")
    assert_eq(CountSent(sent, "WN_TOOLTIP_HIDE"), 0, "no WN_TOOLTIP_HIDE per tooltip")
end

-- ResetService keeps its WN_UI_MAIN_REFRESH_REQUESTED: a reset changes every time-derived label (countdowns,
-- weekly done marks) on whatever tab is open, which is the UI-only redraw that message is for.
print("Phase 3: ResetService sends both reset messages")
local rsNs, rsWN, rsSent = NewNS()
do
    rsWN.db.global.resets = { lastDailyResetEpoch = 0, lastWeeklyResetEpoch = 0 }
    LoadFile(rsNs, "Modules/Constants.lua")
    LoadFile(rsNs, "Modules/ResetService.lua")
    rsNs.ResetService:CheckAndTriggerResets("test")
    assert_eq(CountSent(rsSent, "WN_DAILY_RESET_OCCURRED"), 1, "daily reset message sent")
    assert_eq(CountSent(rsSent, "WN_WEEKLY_RESET_OCCURRED"), 1, "weekly reset message sent")
end

print("Phase 4: PvECache weekly-reset listener emits WN_PVE_UPDATED after clearing")
do
    local ns, WN, sent = NewNS()
    local handlers = {}
    function WN:RegisterMessage(ev, fn) handlers[ev] = fn end
    function WN:SavePvECache() end
    function WN:GetWeeklyResetTime() return 0 end
    LoadFile(ns, "Modules/Constants.lua")
    ns.CharacterService = { IsCharacterTracked = function() return true end }
    ns.Utilities = { IsPvEVaultConsumerEnabled = function() return false end, IsModuleEnabled = function() return false end }
    LoadFile(ns, "Modules/PvECacheService.lua")
    LoadFile(ns, "Modules/PvECacheService_MythicPlus.lua")
    LoadFile(ns, "Modules/PvECacheService_Vault.lua")
    WN:InitializePvECache()
    WN.db.global.pveCache.mythicPlus.currentAffixes = { 1, 2 }
    WN:RegisterPvECacheEvents()
    local h = handlers["WN_WEEKLY_RESET_OCCURRED"]
    assert_eq(type(h), "function", "weekly reset listener registered")
    if h then h() end
    assert_eq(next(WN.db.global.pveCache.mythicPlus.currentAffixes), nil, "weekly affixes cleared")
    assert_eq(CountSent(sent, "WN_PVE_UPDATED"), 1, "WN_PVE_UPDATED emitted after the weekly clear")
end

print("Phase 5: CharacterService tracking prompts never call the dialog view")
do
    local ns = NewNS()
    LoadFile(ns, "Modules/Constants.lua")
    LoadFile(ns, "Modules/Utilities.lua")
    LoadFile(ns, "Modules/CharacterService.lua")
    local CS = ns.CharacterService
    local uiCalls = 0
    ns.CharacterTrackingDialog = {
        ShowInitial = function() uiCalls = uiCalls + 1 end,
        ShowChange = function() uiCalls = uiCalls + 1 end,
    }
    local got = {}
    local addon = { SendMessage = function(_, ev, payload) got[#got + 1] = { ev = ev, payload = payload } end }
    CS:ShowCharacterTrackingConfirmation(addon, "A-Realm")
    CS:ShowTrackingChangeConfirmation(addon, "A-Realm", "A", true)
    assert_eq(#got, 2, "both prompts sent CHARACTER_TRACKING_DIALOG_REQUESTED")
    assert_eq(got[1] and got[1].ev, "WN_CHARACTER_TRACKING_DIALOG_REQUESTED", "initial prompt message name")
    assert_eq(got[2] and got[2].payload and got[2].payload.mode, "change", "change prompt payload mode")
    -- An addon object without AceEvent used to fall through to the view.
    local bare = {}
    CS:ShowCharacterTrackingConfirmation(bare, "A-Realm")
    CS:ShowTrackingChangeConfirmation(bare, "A-Realm", "A", false)
    assert_eq(uiCalls, 0, "service never called ns.CharacterTrackingDialog")
end

print("Phase 2 + 6: DataService (reset shim single source, full-save PvE round trip)")
do
    local KEY = "Player-1-00000001"
    UnitName = function() return "Tester" end
    GetNormalizedRealmName = function() return "TestRealm" end
    UnitClass = function() return "Mage", "MAGE", 8 end
    UnitLevel = function() return 90 end
    UnitFactionGroup = function() return "Horde" end
    UnitRace = function() return "Blood Elf", "BloodElf" end
    UnitSex = function() return 3 end
    C_PlayerInfo = {}
    GetMoney = function() return 1234567 end
    GetAverageItemLevel = function() return 280, 280 end
    HasNewMail = function() return false end
    IsInGuild = function() return false end
    IsResting = function() return false end
    GetZoneText = function() return "Silvermoon City" end
    GetSubZoneText = function() return "Court of the Sun" end
    UnitStat = function() return 0, 0 end
    UnitXP = function() return 0 end
    UnitXPMax = function() return 0 end
    GetXPExhaustion = function() return nil end
    GetRestState = function() return nil end
    C_Item.GetDetailedItemLevelInfo = function() return nil end

    local ns, WN = NewNS()
    ns.CharacterService = {
        IsCharacterTracked = function() return true end,
        ResolveSubsidiaryCharacterKey = function() return KEY end,
        ResolveCharactersTableKey = function() return KEY end,
    }
    LoadFile(ns, "Modules/Constants.lua")
    LoadFile(ns, "Modules/Utilities.lua")
    ns.Utilities.GetCharacterStorageKey = function() return KEY end
    ns.Utilities.IsModuleEnabled = function(_, name) return name == "pve" end
    LoadFile(ns, "Modules/ResetService.lua")
    local shim = WN.HasWeeklyResetOccurred
    LoadFile(ns, "Modules/DataService_RosterHelpers.lua")
    LoadFile(ns, "Modules/DataService.lua")
    assert_eq(rawequal(WN.HasWeeklyResetOccurred, shim), true,
        "HasWeeklyResetOccurred is still the ResetService shim after DataService loads")

    local calls = { update = 0, get = 0, import = 0 }
    WN.UpdatePvEData = function() calls.update = calls.update + 1 end
    WN.GetPvEData = function() calls.get = calls.get + 1; return { greatVault = {}, lockouts = {}, mythicPlus = {} } end
    WN.ImportLegacyPvEData = function() calls.import = calls.import + 1 end
    WN.CollectProfessionData = function() return {} end
    WN.ScanMythicKeystone = function() return nil end
    WN.UpdateCurrencyData = function() end

    WN.db.global.characters[KEY] = {
        name = "Tester", realm = "TestRealm", classFile = "MAGE", level = 90, guid = KEY,
        isTracked = true, trackingConfirmed = true, lastSeen = 1,
        professions = { [1] = { name = "Tailoring" }, [2] = { name = "Enchanting" } },
    }
    local ok = WN:SaveCurrentCharacterData()
    assert_eq(ok, true, "full save ran")
    assert_eq(WN.db.global.characters[KEY].lastFullSaveAt ~= nil, true, "full path taken")
    assert_eq(calls.update, 1, "pveCache refreshed from the API once")
    assert_eq(calls.get, 0, "no GetPvEData read-back during the save")
    assert_eq(calls.import, 0, "no ImportLegacyPvEData re-write of the just-written data")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Message layering suite failed with " .. failed .. " failure(s).")
end
print("Message layering suite: ALL TESTS PASSED.")
