#!/usr/bin/env lua
--[[
    Regression test: logout flush order, migration fast path, migration isolation and SV maintenance.

      1. Logout flush: AceDB's PLAYER_LOGOUT frame is registered before the addon's, fires
         OnDatabaseShutdown and then strips defaults. The flush must run from OnDatabaseShutdown
         (profile defaults still readable) and only once when PLAYER_LOGOUT reaches the addon too.
      2. Fast path: an install already stamped with the current fast-path revision must still re-seed
         the world-quest catalog when CATALOG_VERSION moves.
      3. Isolation: one failing migration step must not abort RunMigrations; later steps still run and
         the fast-path stamp stays unset so the next login retries.
      4. db.global.debugPixelProbe (unused dev dump) is removed, also on installs that already ran V1.
      5. World-quest rows not seen for 90 days are pruned (shipped rows and undated rows stay).
      6. The login currency rebuild only fires when currencyData.version really differs from
         Constants.CURRENCY_CACHE_VERSION.
      7. Pet cage/release invalidates the collection cache and emits COLLECTION_UPDATED("pet") whichever
         tab is open.

    Loads AceDB-3.0, MigrationService, the reminder catalogs and DatabaseOptimizer under wow_stub.lua;
    OnPlayerLogout / OnPetListChanged and the logout registrations are extracted from Core.lua.
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
-- CallbackHandler dispatches through it (localized at load).
securecallfunction = function(fn, ...) return fn(...) end

local ns = {}
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
local function LoadFile(rel, ...)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, ...)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
-- Pull one `function WarbandNexus:Name(...)` out of a file and install it on the test addon.
local function Extract(rel, name, prelude)
    local src = ReadFile(rel)
    local body = src:match("(function WarbandNexus:" .. name .. "%(.-\nend)\n")
    assert(body, "function not found: " .. name)
    local chunk = assert(loadstring((prelude or "") .. "\nlocal WarbandNexus = ...\n" .. body, "@" .. rel .. ":" .. name))
    chunk(WarbandNexus, ns)
end

LoadFile("libs/LibStub/LibStub.lua")
LoadFile("libs/CallbackHandler-1.0/CallbackHandler-1.0.lua")
LoadFile("libs/AceDB-3.0/AceDB-3.0.lua")
LoadFile("Locales/enUS.lua", "WarbandNexus", ns)
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua", "WarbandNexus", ns)
LoadFile("Modules/MigrationService.lua", "WarbandNexus", ns)
-- Shipped catalog rows under test control (GetShippedEntries reads them at load).
local SHIPPED_QID, EMISSARY_QID = 90001, 90002
ns.ReminderMidnightWorldQuestData = { ENTRIES = { { questID = SHIPPED_QID, zoneKey = "eversong", title = "Shipped" } } }
ns.ReminderMidnightFactionEmissaryData = { ENTRIES = { { questID = EMISSARY_QID, zoneKey = "zulaman", title = "Emissary" } } }
LoadFile("Modules/Data/ReminderWorldQuestCatalog.lua", "WarbandNexus", ns)
LoadFile("Modules/Data/ReminderQuestCatalog.lua", "WarbandNexus", ns)
LoadFile("Modules/DatabaseOptimizer.lua", "WarbandNexus", ns)

local MS = ns.MigrationService
local WQC = ns.ReminderWorldQuestCatalog
local DAY = 24 * 60 * 60

-- ---------------------------------------------------------------------------
print("Phase 1: logout flush runs before AceDB strips defaults, once")
-- AceEvent's frame exists after AceDB's (library load order), so PLAYER_LOGOUT reaches it second.
local addonEventFrame = CreateFrame("Frame")
local eventMethods = {}
addonEventFrame:SetScript("OnEvent", function(_, event, ...)
    local m = eventMethods[event]
    if m then WarbandNexus[m](WarbandNexus, event, ...) end
end)
function WarbandNexus:RegisterEvent(event, method)
    eventMethods[event] = method
    addonEventFrame:RegisterEvent(event)
end
function WarbandNexus:ResetStorageTreeExpandState() end
local flushCalls, seenModules, seenCurrencies = 0, nil, nil
function WarbandNexus:FlushCurrencyCacheOnLogout()
    flushCalls = flushCalls + 1
    seenModules = self.db.profile.modulesEnabled
    seenCurrencies = type(seenModules) == "table" and seenModules.currencies
end

WarbandNexusTestDB = {}
local realDb = LibStub("AceDB-3.0"):New("WarbandNexusTestDB", { profile = { modulesEnabled = { currencies = true } } }, true)
WarbandNexus.db = realDb
Extract("Core.lua", "OnPlayerLogout", "local _, ns = nil, select(2, ...)")
-- Run Core.lua's own logout registrations (OnInitialize) against the test addon.
local coreSrc = ReadFile("Core.lua")
local regLines = {}
for line in coreSrc:gmatch("[^\n]+") do
    if line:find('RegisterCallback(self, "OnDatabaseShutdown"', 1, true)
        or line:find('RegisterEvent("PLAYER_LOGOUT"', 1, true) then
        regLines[#regLines + 1] = line
    end
end
assert(#regLines > 0, "no logout registration found in Core.lua")
for i = 1, #regLines do
    assert(loadstring("local self = ...\n" .. regLines[i], "@Core.lua:logoutreg"))(WarbandNexus)
end

stub.Fire("PLAYER_LOGOUT")
assert_eq(#stub.errors, 0, "no errors during PLAYER_LOGOUT")
assert_eq(rawget(realDb.profile, "modulesEnabled"), nil, "AceDB stripped defaults afterwards")
assert_eq(type(seenModules), "table", "flush reads profile.modulesEnabled with defaults still applied")
assert_eq(seenCurrencies, true, "flush sees the default module flag")
assert_eq(flushCalls, 1, "flush runs once when both OnDatabaseShutdown and PLAYER_LOGOUT fire")
WarbandNexus:OnPlayerLogout()
assert_eq(flushCalls, 1, "a later OnPlayerLogout call does not flush again")
stub.Reset()

-- ---------------------------------------------------------------------------
local function NewDb()
    return { global = { _schemaVersion = 13, characters = {} }, profile = {}, char = {}, sv = {} }
end

print("Phase 2: catalog version bump re-seeds on a fast-path install")
local db = NewDb()
WarbandNexus.db = db
MS:RunMigrations(db)
local rev = db.global._wnMigrationFastPathRev
assert_eq(type(rev), "number", "full path stamps the fast-path revision")
assert_eq(db.global.reminderQuestCatalog and db.global.reminderQuestCatalog.version, WQC.CATALOG_VERSION, "first login seeds the catalog")
-- Simulate a release that bumps CATALOG_VERSION without touching the fast-path revision.
db.global.reminderQuestCatalog.version = WQC.CATALOG_VERSION - 1
db.global.reminderQuestCatalog.worldQuests[SHIPPED_QID] = nil
MS:RunMigrations(db)
assert_eq(db.global._wnMigrationFastPathRev, rev, "still on the fast path")
assert_eq(db.global.reminderQuestCatalog.version, WQC.CATALOG_VERSION, "catalog re-seeded to the code version")
assert_eq(db.global.reminderQuestCatalog.worldQuests[SHIPPED_QID] ~= nil, true, "shipped row seeded again")

print("Phase 3: one failing step does not abort the rest")
db = NewDb()
WarbandNexus.db = db
db.global.debugPixelProbe = { physH = 1 }
local realThemeColors = MS.MigrateThemeColors
MS.MigrateThemeColors = function() error("boom") end
local ok = pcall(MS.RunMigrations, MS, db)
MS.MigrateThemeColors = realThemeColors
assert_eq(ok, true, "RunMigrations does not raise")
assert_eq(db.global.reminderQuestCatalog and db.global.reminderQuestCatalog.version, WQC.CATALOG_VERSION, "a later step still ran")
assert_eq(db.global._wnMigrationFastPathRev, nil, "fast-path stamp left unset after a failure")
local reported = false
for i = 1, #stub.errors do
    if stub.errors[i]:find("MigrateThemeColors", 1, true) then reported = true end
end
assert_eq(reported, true, "failure reported to the error handler with the step name")
stub.Reset()

print("Phase 4: debugPixelProbe removed on an install that already ran V1")
db = NewDb()
WarbandNexus.db = db
db.global.pruneOrphanSvKeysV1 = true
db.global._wnMigrationFastPathRev = 6
db.global.debugPixelProbe = { physH = 1080, targets = {} }
db.global.keepMe = { 1 }
MS:RunMigrations(db)
assert_eq(db.global.debugPixelProbe, nil, "debugPixelProbe removed")
assert_eq(db.global.keepMe and db.global.keepMe[1], 1, "other global keys untouched")

print("Phase 5: world-quest rows unseen for 90 days are pruned at login")
local now = time()
db = NewDb()
WarbandNexus.db = db
db.global._wnMigrationFastPathRev = rev   -- an install already on the fast path
db.global.reminderQuestCatalog = { version = WQC.CATALOG_VERSION, worldQuests = {
    [SHIPPED_QID] = { zoneKey = "eversong" },
    [EMISSARY_QID] = { zoneKey = "zulaman" },
} }
local wq = db.global.reminderQuestCatalog.worldQuests
wq[70001] = { zoneKey = "eversong", updatedAt = now - 100 * DAY }
wq[70002] = { zoneKey = "eversong", updatedAt = now - 10 * DAY }
wq[70003] = { zoneKey = "eversong" }
wq[SHIPPED_QID].updatedAt = now - 200 * DAY
wq[EMISSARY_QID].updatedAt = now - 200 * DAY
db.global.reminderQuestDiscovery = { worldQuests = {
    [70001] = { title = "Old", lastSeen = now - 91 * DAY },
    [70002] = { title = "New", lastSeen = now - 1 * DAY },
} }
MS:RunMigrations(db)
assert_eq(wq[70001], nil, "stale saved row pruned")
assert_eq(wq[70002] ~= nil, true, "recent saved row kept")
assert_eq(wq[70003] ~= nil, true, "undated saved row kept")
assert_eq(wq[SHIPPED_QID] ~= nil, true, "shipped row kept regardless of age")
assert_eq(wq[EMISSARY_QID] ~= nil, true, "emissary row kept regardless of age")
assert_eq(db.global.reminderQuestDiscovery.worldQuests[70001], nil, "stale discovered row pruned")
assert_eq(db.global.reminderQuestDiscovery.worldQuests[70002] ~= nil, true, "recent discovered row kept")

-- ---------------------------------------------------------------------------
print("Phase 6: login currency rebuild only on a real version mismatch")
local currencyRebuilds = 0
function WarbandNexus:EnforceCharacterLimit() end
function WarbandNexus:CleanupOrphanedData() end
function WarbandNexus:CheckAutoOptimization() end
function WarbandNexus:ScanReputations() end
function WarbandNexus:UpdateCurrencyData() currencyRebuilds = currencyRebuilds + 1 end
local function RunOptimizerWithCurrencyVersion(version)
    WarbandNexus.db = {
        profile = { autoOptimize = true },
        char = {},
        global = {
            characters = {},
            reputationData = { characters = { a = {} } },
            currencyData = { version = version, currencies = { [3008] = {} } },
        },
    }
    currencyRebuilds = 0
    WarbandNexus:InitializeDatabaseOptimizer()
    stub.Advance(10)
    return currencyRebuilds
end
assert_eq(RunOptimizerWithCurrencyVersion(ns.Constants.CURRENCY_CACHE_VERSION), 0, "current currency schema: no rebuild")
assert_eq(RunOptimizerWithCurrencyVersion("0.9.0"), 1, "older currency schema: one rebuild")
assert_eq(#stub.errors, 0, "no timer errors")
stub.Reset()

-- ---------------------------------------------------------------------------
print("Phase 7: pet cage/release on another tab refreshes the pet collection")
local CHAR = "Player-3674-0000000A"
WarbandNexus.db = { global = { characters = { [CHAR] = {} } }, profile = {}, char = {} }
ns.CharacterService = { ResolveCharactersTableKey = function() return CHAR end }
ns.Utilities = ns.Utilities or {}
local invalidations = 0
function WarbandNexus:InvalidateCollectionCache() invalidations = invalidations + 1 end
WarbandNexus.UI = { mainFrame = { IsShown = function() return true end, currentTab = "items" } }
local numOwned = 100
C_PetJournal.GetNumPets = function() return numOwned, numOwned end
Extract("Core.lua", "OnPetListChanged", "local _, ns = nil, select(2, ...)")
for i = #messages, 1, -1 do messages[i] = nil end
WarbandNexus:OnPetListChanged()        -- baseline
numOwned = 99
WarbandNexus:OnPetListChanged()        -- caged one
numOwned = 98
WarbandNexus:OnPetListChanged()        -- caged another inside the throttle window
stub.Advance(1)
assert_eq(invalidations, 1, "collection cache invalidated once for a burst")
local petMsgs, payload = 0, nil
for i = 1, #messages do
    if messages[i].msg == ns.Constants.EVENTS.COLLECTION_UPDATED then
        petMsgs = petMsgs + 1
        payload = messages[i].payload
    end
end
assert_eq(petMsgs, 1, "one COLLECTION_UPDATED for the burst")
assert_eq(payload, "pet", "payload is the collection type")
assert_eq(#stub.errors, 0, "no timer errors")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Core / migrations maintenance suite failed with " .. failed .. " failure(s).")
end
print("Core / migrations maintenance suite: ALL TESTS PASSED.")
