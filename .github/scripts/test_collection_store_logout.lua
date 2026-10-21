#!/usr/bin/env lua
--[[
    Regression test: PLAYER_LOGOUT before the collection store is loaded must not wipe SV.

    collectionStore lives in RAM as empty defaults until InitializeCollectionCache (deferred P0
    init, queued until combat ends) copies db.global.collectionStore in. FlushCollectionStoreOnLogout
    used to call SaveCollectionStore unconditionally, so a /reload or logout in combat (or in the
    first ~0.5s) replaced every saved mount/pet/toy/achievement with empty tables.

    Loads the shipped CollectionService files under wow_stub.lua.
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

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = { modulesEnabled = {} }, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    UnregisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
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

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/CollectionService_Materialize.lua")
LoadFile("Modules/CollectionService_NotifyDedup.lua")
LoadFile("Modules/CollectionService_Scan.lua")
LoadFile("Modules/CollectionService.lua")
LoadFile("Modules/CollectionService_Store.lua")

local CACHE_VERSION = ns.CollectionServiceRT.CACHE_VERSION

local function countRows(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

-- A player's saved store from the previous session.
WarbandNexus.db.global.collectionStore = {
    version = CACHE_VERSION,
    lastBuilt = 1700000000,
    mount = { [6] = { id = 6, name = "Brown Horse", collected = true }, [7] = { id = 7, name = "Gray Wolf", collected = false } },
    pet = { [39] = { id = 39, name = "Mechanical Squirrel", collected = true } },
    toy = { [1973] = { id = 1973, name = "Orb of Deception" } },
    achievement = { [6] = { id = 6, name = "Level 10", collected = true } },
    title = {},
    illusion = {},
    scanCompleted = { mount = 1700000000, pet = 1700000000 },
}

print("Phase 1: Logout before the store is loaded leaves SV untouched")
do
    WarbandNexus:FlushCollectionStoreOnLogout()
    local saved = WarbandNexus.db.global.collectionStore
    assert_eq(countRows(saved.mount), 2, "saved mounts survive an early logout")
    assert_eq(countRows(saved.pet), 1, "saved pets survive an early logout")
    assert_eq(countRows(saved.toy), 1, "saved toys survive an early logout")
    assert_eq(countRows(saved.achievement), 1, "saved achievements survive an early logout")
    assert_eq(saved.scanCompleted and saved.scanCompleted.mount, 1700000000, "scanCompleted stamp survives")
end

print("Phase 2: After the store is loaded, logout persists it as before")
do
    WarbandNexus:InitializeCollectionCache()
    assert_eq(ns.CollectionServiceRT.storeHydrated, true, "store marked hydrated after init")
    ns.CollectionServiceRT.collectionStore.mount[8] = { id = 8, name = "White Stallion", collected = true }
    WarbandNexus:FlushCollectionStoreOnLogout()
    local saved = WarbandNexus.db.global.collectionStore
    assert_eq(countRows(saved.mount), 3, "loaded store plus a new mount is persisted")
    assert_eq(countRows(saved.pet), 1, "pets persisted after hydrate")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Collection store logout suite failed with " .. failed .. " failure(s).")
end
print("Collection store logout suite: ALL TESTS PASSED.")
