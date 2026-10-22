#!/usr/bin/env lua
--[[
    Regression test: player-facing chat lines, slash help and Easy Access labels come from ns.L.

    These strings were English literals, so every non-English client saw them untranslated:
      1. PlansManager: "Added plan:" / "Removed plan:" chat lines and the two AddPlan input errors.
      2. Core / DataService: character save error, ESC keybind removal, guild bank scan messages.
      3. CommandService: /wn help ("saved", "keys"), /wn reminder help, syncwq result, /wn keys lines.
      4. Easy Access: vault tracker column defs (Raid / Dungeon / World), tracker and options window
         titles, the options menu checkboxes and the "Columns" label.
      5. Config.lua (AceConfig) lacked the PvP / Gear / Collections / Try Counter module toggles.
      6. The currency module text now says currency data keeps updating while other modules use it.

    Every module is driven with a sentinel locale (each key reads back as "@KEY@"), so a line built from
    the locale shows the sentinel and an English literal does not. Keys the code asked for must exist in
    enUS. Loads the shipped PlansManager / DataService / CommandService / VaultButton_Core / Config under
    wow_stub.lua; the Core.lua handlers are extracted with loadstring. The VaultButton table / options
    windows need the full frame stack, so their label calls are checked in the source.
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

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end

-- Real enUS table: the keys the code asks for must exist there.
local enNs = {}
assert(loadstring(ReadFile("Locales/enUS.lua"), "@Locales/enUS.lua"))("WarbandNexus", enNs)
local enUS = assert(enNs.LOCALES and enNs.LOCALES.enUS, "enUS table")

-- Sentinel locale: "@KEY@" for every key; format keys keep their specifier so arguments still show.
local asked = {}
local SENTINEL_FORMATS = {
    CHARACTER_SAVE_ERROR_FORMAT = "@CHARACTER_SAVE_ERROR_FORMAT@ %s",
    REMINDER_SYNCWQ_SAVED_FORMAT = "@REMINDER_SYNCWQ_SAVED_FORMAT@ %d",
}
local sentinelL = setmetatable({}, { __index = function(_, k)
    asked[k] = true
    return SENTINEL_FORMATS[k] or ("@" .. tostring(k) .. "@")
end })

local printed = {}
local ns = {}
local WarbandNexus = {
    db = { global = { plans = {}, customPlans = {}, characters = {} },
        profile = { modulesEnabled = {} }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function(_, msg) printed[#printed + 1] = msg end,
}
ns.WarbandNexus = WarbandNexus
ns.L = sentinelL
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return "Player-1-00000001" end,
    ResolveCharactersTableKey = function() return "Player-1-00000001" end,
}

local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local function Joined() return table.concat(printed, "\n") end
local function Has(text, needle) return text:find(needle, 1, true) ~= nil end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
ns.Utilities.GetCharacterStorageKey = function() return "Player-1-00000001" end
ns.Utilities.IsModuleEnabled = function() return true end
LoadFile("Modules/PlansManager.lua")
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")
LoadFile("Modules/CommandService.lua")

print("Phase 1: plan add / remove chat lines and AddPlan input errors")
do
    WarbandNexus._ResolveSinglePlan = function() end
    WarbandNexus.RefreshPlanCache = function() end
    WarbandNexus.GetPlanDisplayName = function(_, plan) return plan.name end
    printed = {}
    assert_eq(WarbandNexus:AddPlan(nil), nil, "invalid plan data rejected")
    assert_eq(Has(Joined(), "@PLAN_ERROR_INVALID_DATA@"), true, "invalid plan data error from locale")
    printed = {}
    assert_eq(WarbandNexus:AddPlan({ name = "No type" }), nil, "typeless plan rejected")
    assert_eq(Has(Joined(), "@PLAN_ERROR_TYPE_REQUIRED@"), true, "missing plan type error from locale")
    printed = {}
    local id = WarbandNexus:AddPlan({ type = "custom", name = "Feed the cat" })
    assert_eq(type(id), "number", "custom plan added")
    assert_eq(Has(Joined(), "@PLAN_ADDED_PREFIX@|r Feed the cat"), true, "added line: locale prefix + plan name")
    assert_eq(Has(Joined(), "Added plan"), false, "no English 'Added plan' literal")
    printed = {}
    assert_eq(WarbandNexus:RemovePlan(id), true, "plan removed")
    assert_eq(Has(Joined(), "@PLAN_REMOVED_PREFIX@|r Feed the cat"), true, "removed line: locale prefix + plan name")
    WarbandNexus.db.global.customPlans[1] = { id = 900, type = "custom", name = "Daily herbs" }
    printed = {}
    assert_eq(WarbandNexus:RemovePlan(900), true, "custom plan removed")
    assert_eq(Has(Joined(), "@CUSTOM_PLAN_REMOVED_PREFIX@|r Daily herbs"), true, "custom removed line from locale")
    assert_eq(Has(Joined(), "Removed "), false, "no English 'Removed ...' literal")
end

print("Phase 2: DataService deferred / flushed character save errors")
do
    WarbandNexus.SaveCurrentCharacterData = function() error("db locked", 0) end
    printed = {}
    WarbandNexus:ScheduleDeferredCharacterSave(true)
    stub.Advance(60)
    assert_eq(Has(Joined(), "@CHARACTER_SAVE_ERROR_FORMAT@ db locked"), true, "deferred save error from locale (keeps error text)")
    printed = {}
    WarbandNexus:ScheduleDeferredCharacterSave(true)
    WarbandNexus:FlushDeferredCharacterSave()
    assert_eq(Has(Joined(), "@CHARACTER_SAVE_ERROR_FORMAT@ db locked"), true, "flushed save error from locale")
    assert_eq(Has(Joined(), "Error saving character"), false, "no English save error literal")
end

print("Phase 3: Core.lua keybind, character save and guild bank messages")
do
    local src = ReadFile("Core.lua")
    local function Extract(name, prelude)
        local s = src:find("function WarbandNexus:" .. name .. "(", 1, true)
        local e = s and src:find("\nend\n", s, true)
        assert(s and e, "Core.lua: " .. name .. " not found")
        local chunk = assert(loadstring("local WarbandNexus, ns = ...\n" .. (prelude or "") .. src:sub(s, e + 4),
            "@Core.lua:" .. name))
        chunk(WarbandNexus, ns)
    end
    Extract("ApplyToggleKeybind")
    Extract("SaveCharacter")
    Extract("OnGuildBankOpened", "local IsGuildBankScanConsumerEnabled = function() return true end\n")
    Extract("ThrottledGuildBankScan")

    _G["WarbandNexusToggleButton"] = {}
    ClearOverrideBindings = function() end
    SetOverrideBindingClick = function() end
    WarbandNexus.db.profile.toggleKeybind = "ESCAPE"
    printed = {}
    WarbandNexus:ApplyToggleKeybind()
    assert_eq(WarbandNexus.db.profile.toggleKeybind, nil, "ESC keybind cleared")
    assert_eq(Has(Joined(), "@KEYBIND_ESC_REMOVED@"), true, "ESC keybind notice from locale")

    WarbandNexus.characterSaved = false
    printed = {}
    WarbandNexus:SaveCharacter()
    assert_eq(Has(Joined(), "@CHARACTER_SAVE_ERROR_FORMAT@ db locked"), true, "SaveCharacter error from locale")
    InCombatLockdown = function() return true end
    printed = {}
    WarbandNexus:SaveCharacter()
    InCombatLockdown = function() return false end
    assert_eq(Has(Joined(), "@CHARACTER_SAVE_ERROR_FORMAT@ db locked"), true, "in-combat SaveCharacter error from locale")

    WarbandNexus.ScanGuildBank = function() return false, "not_tracked" end
    printed = {}
    WarbandNexus:OnGuildBankOpened()
    stub.Advance(1)
    assert_eq(Has(Joined(), "[@ITEMS_GUILD_BANK@]|r @GUILD_BANK_SCAN_FAILED@"), true, "guild bank scan failure from locale")
    WarbandNexus.ScanGuildBank = nil
    WarbandNexus.guildBankIsOpen = true
    printed = {}
    WarbandNexus:ThrottledGuildBankScan()
    assert_eq(Has(Joined(), "[@ITEMS_GUILD_BANK@]|r @GUILD_BANK_SCAN_UNAVAILABLE@"), true, "guild bank scan unavailable from locale")
    assert_eq(Has(Joined(), "ScanGuildBank not available"), false, "no English guild bank literal")
end

print("Phase 4: slash help, reminder help and /wn keys lines")
do
    local CS = ns.CommandService
    WarbandNexus.GetArgs = function(_, input, n)
        local out = {}
        for w in tostring(input or ""):gmatch("%S+") do out[#out + 1] = w end
        return unpack(out, 1, n)
    end
    printed = {}
    CS:HandleSlashCommand(WarbandNexus, "help")
    local help = Joined()
    assert_eq(Has(help, "/wn saved|r — @SAVED_INSTANCES_TITLE@"), true, "/wn saved help from locale")
    assert_eq(Has(help, "/wn keys|r — @CMD_KEYS@"), true, "/wn keys help from locale")
    assert_eq(Has(help, "Announce alt keystones"), false, "no English keys help literal")

    printed = {}
    CS:HandleSlashCommand(WarbandNexus, "reminder")
    local rem = Joined()
    assert_eq(Has(rem, "@CMD_REMINDER_STATUS@"), true, "reminder status help from locale")
    assert_eq(Has(rem, "@CMD_REMINDER_TEST@"), true, "reminder test help from locale")
    assert_eq(Has(rem, "@CMD_REMINDER_SYNCWQ@"), true, "reminder syncwq help from locale")

    WarbandNexus.ScanMidnightQuests = function() return { worldQuests = { { questID = 1 }, { questID = 2 } } } end
    ns.ReminderQuestCatalog = { RefreshDiscoveryFromScan = function() end }
    printed = {}
    CS:HandleSlashCommand(WarbandNexus, "reminder syncwq")
    assert_eq(Has(Joined(), "@REMINDER_SYNCWQ_SAVED_FORMAT@ 2"), true, "syncwq result from locale (count kept)")

    WarbandNexus.GetAllCharacters = function() return {} end
    printed = {}
    CS:HandleSlashCommand(WarbandNexus, "keys")
    assert_eq(Has(Joined(), "@KEYS_NONE_FOUND@"), true, "no keystones line from locale")

    RAID_CLASS_COLORS = { MAGE = { r = 1, g = 1, b = 1 } }
    IsInGroup = function() return false end
    IsInRaid = function() return false end
    WarbandNexus.GetAllCharacters = function()
        return { { _key = "Player-1-00000001", name = "Alpha", classFile = "MAGE" } }
    end
    WarbandNexus.GetPvEKeystone = function() return { level = 10, mapID = 503, dungeonName = "Ara-Kara" } end
    printed = {}
    CS:HandleSlashCommand(WarbandNexus, "keys")
    assert_eq(Has(Joined(), "@KEYS_LOCAL_HEADER@"), true, "local keystone header from locale")
    assert_eq(Has(Joined(), "Ara-Kara (+10)"), true, "keystone line still printed")
end

print("Phase 5: Easy Access column defs and window labels")
do
    ns.VaultButton = ns.VaultButton or {}
    ns.UI_GetIconMarkup = ns.UI_GetIconMarkup or function() return "" end
    ns.UI_GetIconAtlas = ns.UI_GetIconAtlas or function() return nil end
    local okLoad, loadErr = pcall(LoadFile, "Modules/VaultButton_Core.lua")
    assert_eq(okLoad, true, "VaultButton_Core.lua loads" .. (okLoad and "" or (": " .. tostring(loadErr))))
    local M = ns.VaultButton
    if okLoad then
        ns.ResolveVaultTrackerColumnWidth = ns.ResolveVaultTrackerColumnWidth or function() return nil end
        WarbandNexus.db.profile.vaultButton = { columns = {} }
        local okDefs, defs = pcall(M.GetEnabledCategoryDefs)
        assert_eq(okDefs, true, "GetEnabledCategoryDefs runs" .. (okDefs and "" or (": " .. tostring(defs))))
        if okDefs then
            local labels = {}
            for i = 1, #defs do labels[defs[i].key] = defs[i].label .. "/" .. defs[i].tooltip end
            assert_eq(labels.raids, "@EA_TOOLTIP_CAT_RAID@/@EA_TOOLTIP_CAT_RAID@", "raid column label + tooltip from locale")
            assert_eq(labels.mythicPlus, "@EA_TOOLTIP_CAT_DUNGEON@/@EA_TOOLTIP_CAT_DUNGEON@", "dungeon column label + tooltip from locale")
            assert_eq(labels.world, "@EA_TOOLTIP_CAT_WORLD@/@EA_TOOLTIP_CAT_WORLD@", "world column label + tooltip from locale")
        end
    end

    -- Window construction needs the whole frame stack; check the label calls in the source instead.
    local tableSrc = ReadFile("Modules/VaultButton_Table.lua")
    local trackerSrc = ReadFile("Modules/VaultButton_TrackerUI.lua")
    assert_eq(Has(tableSrc, 'title:SetText("Vault Tracker")'), false, "table window title not a literal")
    assert_eq(Has(tableSrc, 'title:SetText(EAL("VAULT_BUTTON_MENU_TRACKER"'), true, "table window title from EAL")
    assert_eq(Has(trackerSrc, 'title:SetText(EAL("VAULT_BUTTON_MENU_TRACKER"'), true, "options window title from EAL")
    assert_eq(Has(trackerSrc, 'columnLabel:SetText(EAL("COLUMNS_BUTTON"'), true, "Columns label from EAL")
    assert_eq(trackerSrc:find('CreateMenuCheckbox%(f, "'), nil, "no options checkbox with a literal label")
    assert_eq(trackerSrc:find('\n%s+"[A-Z][^"\n]*%."%)'), nil, "no options checkbox with a literal tooltip")
    for key in (tableSrc .. trackerSrc):gmatch('EAL%("([%w_]+)"') do asked[key] = true end
end

print("Phase 6: Config.lua module toggles match Settings > Modules")
do
    local setCalls = {}
    WarbandNexus.SetModuleEnabled = function(_, key, value) setCalls[#setCalls + 1] = key .. "=" .. tostring(value) end
    local registered
    LibStub = function(name)
        if name == "AceConfig-3.0" then
            return { RegisterOptionsTable = function(_, app, opts) if app == "WarbandNexus" then registered = opts end end }
        end
        return { GetOptionsTable = function() return {} end }
    end
    local okLoad, loadErr = pcall(LoadFile, "Config.lua")
    assert_eq(okLoad, true, "Config.lua loads" .. (okLoad and "" or (": " .. tostring(loadErr))))
    if okLoad then
        WarbandNexus:InitializeConfig()
    end
    local args = registered and registered.args or {}
    local want = {
        { "modulePvP", "pvp", "MODULE_PVP" },
        { "moduleGear", "gear", "MODULE_GEAR" },
        { "moduleCollections", "collections", "MODULE_COLLECTIONS" },
        { "moduleTryCounter", "tryCounter", "MODULE_TRY_COUNTER" },
    }
    for i = 1, #want do
        local field, key, lkey = want[i][1], want[i][2], want[i][3]
        local opt = args[field]
        assert_eq(opt and opt.type, "toggle", field .. " toggle exists")
        if opt then
            assert_eq(opt.name(), "@" .. lkey .. "@", field .. " label from Settings > Modules key")
            assert_eq(opt.desc(), "@" .. lkey .. "_DESC@", field .. " description from Settings > Modules key")
            WarbandNexus.db.profile.modulesEnabled[key] = false
            assert_eq(opt.get(), false, field .. " reads modulesEnabled." .. key)
            setCalls = {}
            opt.set(nil, true)
            assert_eq(setCalls[1], key .. "=true", field .. " goes through SetModuleEnabled")
        end
    end
end

print("Phase 7: every key the code asked for exists in enUS; currency module text is accurate")
do
    local missing = {}
    for k in pairs(asked) do
        if enUS[k] == nil then missing[#missing + 1] = k end
    end
    table.sort(missing)
    assert_eq(table.concat(missing, ", "), "", "no locale key missing from enUS")
    assert_eq(Has(enUS.MODULE_CURRENCIES_DESC or "", "still updates while other modules use it"), true,
        "Settings > Modules currency text: data keeps updating")
    assert_eq(Has(enUS.CONFIG_MOD_CURRENCIES_DESC or "", "still updates while other modules use it"), true,
        "AceConfig currency text: data keeps updating")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("User-visible strings localization suite failed with " .. failed .. " failure(s).")
end
print("User-visible strings localization suite: ALL TESTS PASSED.")
