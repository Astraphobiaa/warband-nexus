#!/usr/bin/env lua
--[[
    Regression test: vault / keystone read paths do the work their callers actually need.

      1. LookupPveCacheSubtable (VaultButton_Data) resolved charKey's canonical key twice per
         subtable row (CharKeysMatch inside the alias walk) and ignored the GUID-only flag, so
         GetPvEData (~11 lookups) and BuildCharList cost O(rows) canonical resolves per call.
         Results must stay identical: newest alias row wins, a claimed row wins over all.
      2. CurrentVaultWeekId floored GetServerTime()+secsUntilReset to the minute; a reset on the
         hour sampled at ...:59:59 then ...:00:00 changed the id and rebuilt the vault snapshot.
      3. WN_CURRENCY_UPDATED ran the full vault refresh (snapshot drop + badge sweep) for every
         currency; only Voidcore / Manaflux feed the vault rows.
      4. Keystone tooltip and /wn keys called the full GetPvEData per roster character to read
         .keystone; the PvE service now has keystone / vault-activity accessors with the same key
         resolution and the callers use them.

    Loads the shipped Constants / ResetService / VaultButton_Data / VaultButton / PvECacheService
    (+ satellites) / CommandService under wow_stub.lua; the tooltip helper is extracted from
    TooltipService_GameTooltip.lua with loadstring.
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

local WEEK = 7 * 86400
local RESET = 1791950400            -- 2026-10-14 04:00:00 UTC (on the hour, like Blizzard resets)
local now = RESET + 2 * 86400
local jitter = 0
local nextReset = RESET + WEEK
GetServerTime = function() return now end
time = function() return now end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return nextReset - now + jitter end }

-- Alias map: Name-Realm -> GUID. Counts every canonical resolve.
local GUID, NAME = "Player-1-0000000A", "Alpha-Realm"
local resolves = 0
local guidOnly = false
local ns = {}
local WarbandNexus = {
    db = { global = { characters = {}, pveCache = {
        mythicPlus = { keystones = {}, bestRuns = {}, dungeonScores = {}, runHistory = {} },
        greatVault = { activities = {}, rewards = {} },
        lockouts = { raids = {}, dungeons = {}, worldBosses = {} },
        delves = { characters = {}, companion = {} },
    } }, profile = {}, char = {} },
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
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.CharacterService = { IsCharacterTracked = function() return true end }
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    IsPvEVaultConsumerEnabled = function() return false end,
    GetCharacterKey = function() return GUID end,
    GetCharacterStorageKey = function() return GUID end,
    GetCanonicalCharacterKey = function(_, k)
        resolves = resolves + 1
        if k == NAME then return GUID end
        return k
    end,
    IsGuidOnlySubsidiaryReads = function() return guidOnly end,
    ResolveKeystoneDungeonName = function(_, ks) return "Dungeon" .. tostring(ks.mapID) end,
}
ns.VaultButton = { state = {} }

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

LoadFile("Modules/Constants.lua")
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/VaultButton_Data.lua")
LoadFile("Modules/VaultButton.lua")
LoadFile("Modules/PvECacheService.lua")
LoadFile("Modules/PvECacheService_MythicPlus.lua")
LoadFile("Modules/PvECacheService_Vault.lua")
LoadFile("Modules/CommandService.lua")

local M = ns.VaultButton
-- Defined in VaultButton_Core.lua (not loaded here).
M.VOIDCORE_ID = 3418
M.MANAFLUX_ID = 3465
M.GetManafluxID = function() return 3465 end
local Lookup = ns.LookupPvECacheSubtable

print("Phase 1: alias lookup keeps its results and stops resolving charKey per row")
do
    -- 30 unrelated rows plus the character under its GUID and its Name-Realm alias.
    local sub = {}
    for i = 1, 30 do sub["Player-1-" .. string.format("%08X", 100 + i)] = { lastUpdate = i } end
    sub[GUID] = { lastUpdate = 50, tag = "guid" }
    sub[NAME] = { lastUpdate = 60, tag = "alias" }
    assert_eq(Lookup(sub, GUID).tag, "alias", "newest alias row wins (mixed keys)")
    assert_eq(Lookup(sub, NAME).tag, "alias", "same answer when asked by Name-Realm")
    sub[GUID].hasAvailableRewards, sub[GUID].claimedAt = false, 10
    assert_eq(Lookup(sub, GUID).tag, "guid", "claimed row still wins over a newer alias")
    sub[GUID].hasAvailableRewards, sub[GUID].claimedAt = nil, nil

    resolves = 0
    Lookup(sub, GUID)
    -- Old code: 1 + 2 per table row (charKey re-resolved inside CharKeysMatch) = 65.
    assert_eq(resolves <= 33, true, "mixed keys: one resolve per row plus one for charKey (got " .. resolves .. ")")

    guidOnly = true
    sub[NAME] = nil
    resolves = 0
    assert_eq(Lookup(sub, GUID).tag, "guid", "GUID-only: direct hit returned")
    assert_eq(resolves <= 1, true, "GUID-only: no alias walk (got " .. resolves .. " resolves)")
    resolves = 0
    assert_eq(Lookup(sub, "Player-1-FFFFFFFF"), nil, "GUID-only: miss returns nil")
    assert_eq(resolves <= 1, true, "GUID-only: a miss does not walk the table either (got " .. resolves .. ")")
    assert_eq(Lookup({ [GUID] = 7 }, GUID), 7, "non-table value returned as before")
    guidOnly = false
end

print("Phase 2: reset-epoch jitter does not rebuild the vault snapshot")
do
    local builds = 0
    M.BuildCharList = function() builds = builds + 1; return {} end
    M.InvalidateVaultSnapshot()
    for _, j in ipairs({ 0, -1, 0, 1, -1 }) do
        jitter = j
        M.GetVaultCharList()
    end
    jitter = 0
    assert_eq(builds, 1, "five reads across +-1s jitter build the snapshot once")
    now, nextReset = now + WEEK, nextReset + WEEK     -- next week: the id must still move
    M.GetVaultCharList()
    assert_eq(builds, 2, "a real weekly reset still rebuilds")
end

print("Phase 3: only vault currencies touch the vault snapshot")
do
    local listeners = {}
    WarbandNexus.RegisterMessage = function(_, msg, fn) listeners[msg] = fn end
    M.HookWNMessages()
    local onCurrency = listeners[ns.Constants.EVENTS.CURRENCY_UPDATED]
    assert_eq(type(onCurrency), "function", "CURRENCY_UPDATED listener registered")

    local builds, badges, tables = 0, 0, 0
    M.BuildCharList = function() builds = builds + 1; return {} end
    M.UpdateBadge = function() badges = badges + 1; M.GetVaultCharList() end
    M.RefreshTable = function() tables = tables + 1 end
    M.InvalidateVaultSnapshot()
    M.GetVaultCharList()
    builds = 0

    onCurrency(nil, 3008)                              -- unrelated single currency
    stub.Advance(0.2)
    M.GetVaultCharList()
    assert_eq(builds, 0, "unrelated currency: snapshot kept")
    assert_eq(badges, 0, "unrelated currency: no badge sweep")

    onCurrency(nil, M.VOIDCORE_ID)                     -- Voidcore, tracker closed
    stub.Advance(0.2)
    assert_eq(badges, 0, "Voidcore with the table closed: no badge sweep")
    M.GetVaultCharList()
    assert_eq(builds, 1, "Voidcore with the table closed: next reader rebuilds once")

    ns.VaultButton.state.tableFrame = { IsShown = function() return true end }
    onCurrency(nil, M.GetManafluxID())                 -- Manaflux, tracker open
    stub.Advance(0.2)
    assert_eq(badges, 1, "Manaflux with the table open: full refresh")
    assert_eq(tables, 1, "Manaflux with the table open: table redrawn")
    onCurrency(nil, nil)                               -- batch update without an ID
    stub.Advance(0.2)
    assert_eq(badges, 2, "batch update (no ID) with the table open: full refresh")
    ns.VaultButton.state.tableFrame = nil
end

print("Phase 4: keystone / vault accessors match GetPvEData")
do
    local pc = WarbandNexus.db.global.pveCache
    pc.mythicPlus.keystones[NAME] = { mapID = 503, level = 12, lastUpdate = 5 }
    pc.greatVault.activities[GUID] = { raids = { { progress = 1, threshold = 2 } }, lastUpdate = 5 }
    local full = WarbandNexus:GetPvEData(GUID)
    local ks = WarbandNexus.GetPvEKeystone and WarbandNexus:GetPvEKeystone(GUID)
    assert_eq(ks and ks.level, full.keystone and full.keystone.level, "GetPvEKeystone level == GetPvEData keystone level")
    assert_eq(ks and ks.name, "Dungeon503", "GetPvEKeystone resolves the dungeon name through the alias row")
    local acts = WarbandNexus.GetPvEVaultActivities and WarbandNexus:GetPvEVaultActivities(NAME)
    assert_eq(acts ~= nil and acts == full.vaultActivities, true, "GetPvEVaultActivities returns the same stored row")
    assert_eq(WarbandNexus.GetPvEKeystone and WarbandNexus:GetPvEKeystone("Player-1-FFFFFFFF"), nil, "no row: nil")
end

-- Roster for the caller phases: three characters, two holding keys.
local roster = {
    { _key = GUID, name = "Alpha", classFile = "MAGE" },
    { _key = "Player-1-0000000B", name = "Bravo", classFile = "PRIEST" },
    { _key = "Player-1-0000000C", name = "Charlie", classFile = "ROGUE" },
}
WarbandNexus.db.global.pveCache.mythicPlus.keystones["Player-1-0000000B"] = { mapID = 504, level = 7, lastUpdate = 5 }
local fullReads = 0
local realGetPvEData = WarbandNexus.GetPvEData
WarbandNexus.GetPvEData = function(self, k) fullReads = fullReads + 1; return realGetPvEData(self, k) end
WarbandNexus.GetAllCharacters = function() return roster end

print("Phase 5: keystone tooltip reads keystones only")
do
    RAID_CLASS_COLORS = { MAGE = { r = 1, g = 1, b = 1 }, PRIEST = { r = 1, g = 1, b = 1 }, ROGUE = { r = 1, g = 1, b = 1 } }
    IsShiftKeyDown = function() return false end
    local src = ReadFile("Modules/TooltipService_GameTooltip.lua")
    local s = src:find("local function AppendWNKeystoneLines(tooltip, hyperlink)", 1, true)
    local e = s and src:find("\nend\n", s, true)
    assert_eq(s ~= nil and e ~= nil, true, "AppendWNKeystoneLines found")
    local chunk = loadstring("local WarbandNexus, Utilities, ns = ...\n" .. src:sub(s, e + 4) .. "return AppendWNKeystoneLines\n",
        "@AppendWNKeystoneLines")
    local Append = chunk(WarbandNexus, ns.Utilities, ns)
    local lines = {}
    local tip = {
        AddLine = function(_, t) lines[#lines + 1] = t end,
        AddDoubleLine = function(_, l, r) lines[#lines + 1] = l .. "=" .. r end,
    }
    fullReads = 0
    assert_eq(Append(tip, nil), true, "tooltip lines added")
    assert_eq(fullReads, 0, "no full GetPvEData per roster row (was one per character)")
    local joined = table.concat(lines, "|")
    assert_eq(joined:find("Alpha=+12 Dungeon503", 1, true) ~= nil, true, "Alpha's +12 listed")
    assert_eq(joined:find("Bravo=+7 Dungeon504", 1, true) ~= nil, true, "Bravo's +7 listed")
    assert_eq(joined:find("Charlie", 1, true), nil, "keyless character not listed")
end

print("Phase 6: /wn keys reads keystones only")
do
    local printed = {}
    WarbandNexus.GetArgs = function() return "keys" end
    WarbandNexus.Print = function(_, t) printed[#printed + 1] = t end
    IsInGroup = function() return false end
    IsInRaid = function() return false end
    fullReads = 0
    ns.CommandService:HandleSlashCommand(WarbandNexus, "keys")
    assert_eq(fullReads, 0, "no full GetPvEData per roster row")
    local joined = table.concat(printed, "|")
    assert_eq(joined:find("Dungeon503 (+12)", 1, true) ~= nil, true, "Alpha's key printed")
    assert_eq(joined:find("Dungeon504 (+7)", 1, true) ~= nil, true, "Bravo's key printed")
end

print("Phase 7: PvE column measurement reads vault activities only")
do
    -- The measurer is a closure deep inside PvEUI's layout pass; check the call it makes.
    local src = ReadFile("Modules/UI/PvEUI.lua")
    local body = src:match('if key == "slot1" or key == "slot2" or key == "slot3" then(.-)local claim = false')
    assert_eq(body ~= nil and body:find("GetPvEVaultActivities", 1, true) ~= nil, true,
        "slot width measurement uses GetPvEVaultActivities")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")
if #stub.errors > 0 then for i = 1, #stub.errors do print("    err: " .. stub.errors[i]) end end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Vault reads and refresh suite failed with " .. failed .. " failure(s).")
end
print("Vault reads and refresh suite: ALL TESTS PASSED.")
