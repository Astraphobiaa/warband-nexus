#!/usr/bin/env lua
--[[
    Regression test: login PvE collect, vault-handler bag deferral and item-scan re-enable.

      1. RegisterPvECacheEvents ran UpdatePvEData at login T+3s with no warm gate, so a character
         with a persisted PvE row paid a full collect that Core's gated T+5.5s call already skips.
      2. _OnVaultDataReceivedBody set ns._pveVaultHandlerActive and cleared it only on a normal
         return: one error in the WEEKLY_REWARDS_UPDATE body left OnBagUpdate deferring every bag
         batch for the rest of the session. OnBagUpdate also kept AceBucket's `received` table,
         which AceBucket wipes right after the callback, so the deferred replay arrived empty.
      3. While every item-scan consumer module was off, bag batches returned before the hash
         check; re-enabling the module left those bags stale until their own next BAG_UPDATE.

    Loads the shipped Constants / Utilities / ResetService / PvECacheService (+ satellites) /
    ItemsCacheService under wow_stub.lua.
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
local RESET = 1791950400
local now = RESET + 2 * 86400
GetServerTime = function() return now end
time = function() return now end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return (RESET + WEEK) - now end }

local fakeLib = {
    Serialize = function() return "ser" end,
    Deserialize = function() return true, {} end,
    CompressDeflate = function(_, s) return s end,
    DecompressDeflate = function(_, s) return s end,
    EncodeForPrint = function(_, s) return s end,
    DecodeForPrint = function(_, s) return s end,
}
LibStub = setmetatable({ GetLibrary = function() return fakeLib end }, { __call = function() return fakeLib end })
C_Item.GetItemCount = function() return 0 end
C_Item.IsItemKeystoneByID = function() return false end

local caught = {}
geterrorhandler = function() return function(e) caught[#caught + 1] = tostring(e) end end

local KEY = "Player-1-0000000A"
local ns = {}
local listeners = {}
local WarbandNexus = {
    db = { global = {
        characters = { [KEY] = { name = "Live", classFile = "MAGE", isTracked = true } },
        itemStorage = {}, guildBank = {},
        pveCache = {
            mythicPlus = { keystones = {}, bestRuns = {}, dungeonScores = {}, runHistory = {} },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, dungeons = {}, worldBosses = {} },
            delves = { characters = {}, companion = {} },
        },
    }, profile = { modulesEnabled = {} }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function(_, msg, fn)
        listeners[msg] = listeners[msg] or {}
        table.insert(listeners[msg], fn)
    end,
    RegisterEvent = function() end,
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
    ResolveSubsidiaryCharacterKey = function(_, _, k) return k or KEY end,
    ResolveCharactersTableKey = function() return KEY end,
}

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
ns.Utilities.GetCharacterStorageKey = function() return KEY end
ns.Utilities.GetCanonicalCharacterKey = function(_, k) return k end
LoadFile("Modules/ResetService.lua")
LoadFile("Modules/PvECacheService.lua")
LoadFile("Modules/PvECacheService_MythicPlus.lua")
LoadFile("Modules/PvECacheService_Vault.lua")
LoadFile("Modules/ItemsCacheService.lua")

local function fire(msg, ...)
    local list = listeners[msg] or {}
    for i = 1, #list do list[i](nil, ...) end
end

print("Phase 1: login T+3s PvE collect honours the warm gate")
do
    local updates, warm = 0, true
    WarbandNexus.UpdatePvEData = function() updates = updates + 1 end
    WarbandNexus.IsPvERowPersistedWarm = function() return warm end
    WarbandNexus.ProcessGreatVaultActivities = function() end
    WarbandNexus:RegisterPvECacheEvents()
    stub.Advance(3.5)
    assert_eq(updates, 0, "warm row: no T+3s UpdatePvEData")
    warm = false
    WarbandNexus:RegisterPvECacheEvents()
    stub.Advance(3.5)
    assert_eq(updates, 1, "cold row: T+3s UpdatePvEData still runs")
    stub.Advance(5)
end

-- Spy on OnBagUpdate: record how many bag IDs each call carried.
local realOnBagUpdate = WarbandNexus.OnBagUpdate
local bagCalls = {}
WarbandNexus.OnBagUpdate = function(self, bagIDs)
    local n = 0
    for _ in pairs(bagIDs or {}) do n = n + 1 end
    bagCalls[#bagCalls + 1] = n
    return realOnBagUpdate(self, bagIDs)
end

print("Phase 2: a deferred bag batch survives AceBucket wiping its table")
do
    ns._pveVaultHandlerActive = true
    local received = { [0] = true, [2] = true }
    WarbandNexus:OnBagUpdate(received)
    for k in pairs(received) do received[k] = nil end      -- what AceBucket does after the callback
    local pending, n = ns._pendingBagUpdateAfterVault, 0
    for _ in pairs(pending or {}) do n = n + 1 end
    assert_eq(n, 2, "both bag IDs kept for the replay")
    ns._pveVaultHandlerActive, ns._pendingBagUpdateAfterVault = nil, nil
end

print("Phase 3: an error in the vault handler releases the bag defer")
do
    bagCalls = {}
    local realKeystone = WarbandNexus.UpdateCharacterKeystone
    WarbandNexus.UpdateCharacterKeystone = function(self)
        WarbandNexus.UpdateCharacterKeystone = realKeystone  -- one shot (bag replay re-reads the key)
        local received = { [0] = true, [2] = true }
        self:OnBagUpdate(received)                           -- bag batch while the handler runs
        for k in pairs(received) do received[k] = nil end
        error("boom")
    end
    local ok = pcall(WarbandNexus._OnVaultDataReceivedBody, WarbandNexus)
    assert_eq(ok, true, "error handed to geterrorhandler instead of escaping")
    assert_eq(#caught == 1 and caught[1]:find("boom", 1, true) ~= nil, true, "the error is reported")
    assert_eq(ns._pveVaultHandlerActive, nil, "handler flag cleared after the error")
    stub.Advance(0.1)
    assert_eq(#bagCalls, 2, "deferred batch replayed")
    assert_eq(bagCalls[2], 2, "replay carries both bag IDs")
    ns._pendingBagUpdateAfterVault = nil
    WarbandNexus:OnBagUpdate({ [1] = true })
    assert_eq(ns._pendingBagUpdateAfterVault, nil, "later bag batches are processed, not deferred")
end

print("Phase 4: re-enabling an item-scan consumer rescans bags skipped while it was off")
do
    local mods = WarbandNexus.db.profile.modulesEnabled
    mods.items, mods.storage, mods.gear, mods.plans, mods.professions = false, false, false, false, false
    WarbandNexus.db.profile.showItemCount = false
    local refreshes = 0
    WarbandNexus.RefreshAllBags = function() refreshes = refreshes + 1 end
    WarbandNexus:InitializeItemsCache()
    stub.Advance(1)
    WarbandNexus:OnBagUpdate({ [0] = true })               -- dropped by the module gate
    fire(ns.Constants.EVENTS.MODULE_TOGGLED, "reputations", true)
    assert_eq(refreshes, 0, "unrelated module: no rescan")
    mods.items = true
    fire(ns.Constants.EVENTS.MODULE_TOGGLED, "items", true)
    assert_eq(refreshes, 1, "items re-enabled after a skipped batch: one rescan")
    fire(ns.Constants.EVENTS.MODULE_TOGGLED, "storage", true)
    assert_eq(refreshes, 1, "nothing skipped since: no second rescan")
    fire(ns.Constants.EVENTS.MODULE_TOGGLED, "items", false)
    assert_eq(refreshes, 1, "disable does not rescan")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")
if #stub.errors > 0 then for i = 1, #stub.errors do print("    err: " .. stub.errors[i]) end end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Vault bag defer suite failed with " .. failed .. " failure(s).")
end
print("Vault bag defer suite: ALL TESTS PASSED.")
