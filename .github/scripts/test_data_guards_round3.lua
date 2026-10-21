#!/usr/bin/env lua
--[[
    Regression test: smaller data-safety fixes from the 2026-10-22 audit round.

    1. Cache backups stored a REFERENCE to the live cache (SavedVariables wrote it twice; restore put
       back the same, already-reset table). Now only version / lastScan are kept, and restore reverts
       an invalidation. MigrateSlimCacheBackupsV2 strips old `data` copies.
    2. EnforceCharacterLimit removed rows without a roster message or cache invalidation.
    3. CheckWeeklyReset reset EVERY vault plan when any one was stale (wiping this week's progress and
       manual slot overrides on the others).
    4. The mail snapshot was rescanned with forceInbox after MAIL_CLOSED, when the inbox API is not a
       reliable source; a pending forced scan now runs at the close event instead.
    5. UpdateProfessionData kept a dropped profession forever (slot merge on every read).
    6. The money-log and PvP-statistics reset buttons now confirm first (static check: UI buttons).

    Loads the shipped modules under wow_stub.lua.
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

local KEY = "Player-1-00000001"
local WEEK = 7 * 86400
local RESET = 1791950400
local now = RESET + 2 * 86400
GetServerTime = function() return now end
time = function() return now end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now end,
    GetSecondsUntilDailyReset = function() return 3600 end }
GetNormalizedRealmName = function() return "TestRealm" end
UnitName = function() return "Tester" end

local ns = {}
local handlers = {}
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {}, plans = {}, customPlans = {} }, profile = { characterOrder = {} }, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function(_, ev, fn) handlers[ev] = fn end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return KEY end,
    ResolveCharactersTableKey = function() return KEY end,
    BuildFavoriteKeySet = function() return {} end,
    IsFavoriteFromKeySet = function() return false end,
}

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/Utilities.lua")
ns.Utilities.GetCharacterStorageKey = function() return KEY end
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/DatabaseOptimizer.lua")
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")
LoadFile("Modules/PlansManager.lua")
LoadFile("Modules/PlansManager_Vault.lua")
LoadFile("Modules/MailSnapshotService.lua")
local G = WarbandNexus.db.global

print("Phase 1: Cache backups keep only what invalidation changes, and restore reverts it")
do
    G.reputationData = { version = 7, lastScan = 1234, characters = { [KEY] = { [1] = {} } } }
    WarbandNexus:InvalidateCache("reputation", "test")
    assert_eq(G.reputationData.version, nil, "invalidation reset the version")
    assert_eq(G.cacheBackups.reputation.data, nil, "backup holds no copy of the live table")
    assert_eq(G.cacheBackups.reputation.version, 7, "backup keeps the previous version")
    assert_eq(WarbandNexus:RestoreCacheBackup("reputation"), true, "restore succeeds")
    assert_eq(G.reputationData.version, 7, "restore reverts the invalidation")
    assert_eq(G.reputationData.lastScan, 1234, "restore reverts lastScan")
    G.cacheBackups.pve = { savedAt = 1, data = { lastScan = 55, big = { 1, 2, 3 } } }
    assert_eq(type(ns.MigrationService.MigrateSlimCacheBackupsV2), "function", "backup slimming migration exists")
    if ns.MigrationService.MigrateSlimCacheBackupsV2 then ns.MigrationService:MigrateSlimCacheBackupsV2(WarbandNexus.db) end
    assert_eq(G.cacheBackups.pve.data, nil, "migration strips the old data copy")
    assert_eq(G.cacheBackups.pve.lastScan, 55, "migration keeps the restorable lastScan")
end

print("Phase 2: The character-limit prune tells listeners")
do
    G.characters = {}
    for i = 1, 4 do
        G.characters["Player-1-" .. i] = { name = "Alt" .. i, isTracked = false, lastSeen = 100 + i }
    end
    messages = {}
    local removed = WarbandNexus:EnforceCharacterLimit(2)
    assert_eq(removed, 2, "two oldest untracked rows removed")
    local told = false
    for i = 1, #messages do
        if messages[i].msg == "WN_CHARACTER_UPDATED" and messages[i].payload and messages[i].payload.dataType == "rosterPrune" then told = true end
    end
    assert_eq(told, true, "WN_CHARACTER_UPDATED rosterPrune sent")
end

print("Phase 3: The weekly check resets only the stale vault plan")
do
    local function vaultPlan(id, lastReset)
        return { id = id, type = "weekly_vault", lastReset = lastReset, completed = true,
            slots = { dungeon = { { completed = true, manualOverride = true } }, raid = {}, world = {} },
            progress = { dungeonCount = 4, raidBossCount = 0, worldActivityCount = 0 } }
    end
    local stale, fresh = vaultPlan(1, RESET - 3 * 86400), vaultPlan(2, RESET + 3600)
    G.plans = { stale, fresh }
    WarbandNexus._weeklyVaultPlansList = nil
    WarbandNexus:CheckWeeklyReset()
    assert_eq(stale.progress.dungeonCount, 0, "stale plan reset")
    assert_eq(fresh.progress.dungeonCount, 4, "this week's plan keeps its progress")
    assert_eq(fresh.slots.dungeon[1].manualOverride, true, "this week's manual override kept")
end

print("Phase 4: The mail snapshot is not rescanned from the inbox after the mailbox closed")
do
    G.characters[KEY] = { name = "Tester", isTracked = true, hasMail = true,
        mailSnapshot = { count = 3, messages = { { sender = "A" }, { sender = "B" }, { sender = "C" } } } }
    WarbandNexus:InitializeMailSnapshotService()
    local inboxItems = 0
    GetInboxNumItems = function() return inboxItems, inboxItems end
    HasNewMail = function() return true end
    handlers.MAIL_CLOSED()                         -- closed with nothing pending
    stub.Advance(1)
    local snap = G.characters[KEY].mailSnapshot
    assert_eq(snap and snap.count, 3, "snapshot kept after MAIL_CLOSED (no inbox re-read)")
end

print("Phase 5: A dropped profession leaves the stored professions")
do
    G.characters[KEY] = { name = "Tester", isTracked = true,
        professions = { [1] = { name = "Tailoring", skillLine = 197 }, [2] = { name = "Mining", skillLine = 186 } } }
    WarbandNexus.CollectProfessionData = function() return { [1] = { name = "Tailoring", skillLine = 197 } } end
    WarbandNexus:UpdateProfessionData()
    local profs = G.characters[KEY].professions
    assert_eq(profs[1] and profs[1].name, "Tailoring", "kept profession stays")
    assert_eq(profs[2], nil, "dropped profession removed")
    WarbandNexus.CollectProfessionData = function() return { cooking = { name = "Cooking" } } end
    WarbandNexus:UpdateProfessionData()
    assert_eq(G.characters[KEY].professions[1] and G.characters[KEY].professions[1].name, "Tailoring",
        "a read without primaries (still loading) keeps the stored primaries")
end

print("Phase 6: Irreversible reset buttons confirm first")
do
    local money = ReadFile("Modules/UI/CharacterBankMoneyLogPopup.lua")
    local pvp = ReadFile("Modules/UI/PvPUI_Draw.lua")
    assert_eq(money:find("UI_ShowConfirmDialog", 1, true) ~= nil, true, "money-log reset goes through the confirm dialog")
    assert_eq(pvp:find("UI_ShowConfirmDialog", 1, true) ~= nil, true, "PvP statistics reset goes through the confirm dialog")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Data guards round 3 suite failed with " .. failed .. " failure(s).")
end
print("Data guards round 3 suite: ALL TESTS PASSED.")
