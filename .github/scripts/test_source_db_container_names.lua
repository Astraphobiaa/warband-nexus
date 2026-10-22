#!/usr/bin/env lua
--[[
    Regression test: "Contained in : <container>" source labels recover once the container item loads.

    GetSourceStringForToy / GetSourceStringForMount build a lazy index once per session. The container
    name came from GetItemInfo(containerItemID), which is nil until the client has the item cached, so a
    cold cache stored the bare "Contained in" for the rest of the session (2026-10-22).

    Now an unresolved name requests the item load while the index is built and is retried on lookup.

    Loads the shipped Modules/CollectibleSourceDB.lua under wow_stub.lua.
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

local CONTAINER_TOY, TOY = 990001, 990002
local CONTAINER_MOUNT, MOUNT_ITEM, MOUNT_ID = 990003, 990004, 77001
local cachedNames = {}
local loadRequests = {}
-- The shipped file binds C_Item.GetItemInfo at load: install the controllable version first.
C_Item.GetItemInfo = function(id) return cachedNames[id] end
C_Item.RequestLoadItemDataByID = function(id) loadRequests[id] = (loadRequests[id] or 0) + 1 end
C_MountJournal.GetMountFromItem = function(itemID)
    if itemID == MOUNT_ITEM then return MOUNT_ID end
    return nil
end

local ns = {}
ns.WarbandNexus = { db = { global = {}, profile = {}, char = {} } }
ns.DebugPrint = function() end
local fh = assert(io.open(ROOT .. "/Modules/CollectibleSourceDB.lua", "rb"))
local src = fh:read("*a"):gsub("^\239\187\191", "")
fh:close()
local chunk = assert(loadstring(src, "@Modules/CollectibleSourceDB.lua"))
chunk("WarbandNexus", ns)
local db = assert(ns.CollectibleSourceDB, "CollectibleSourceDB not exported")

db.containers = db.containers or {}
db.containers[CONTAINER_TOY] = { drops = { { type = "toy", itemID = TOY } } }
db.containers[CONTAINER_MOUNT] = { drops = { { type = "mount", itemID = MOUNT_ITEM } } }
db._toySourceByItemID = nil
db._mountSourceByMountID = nil

print("Phase 1: cold item cache")
do
    assert_eq(db.GetSourceStringForToy(TOY), "Contained in", "toy: bare label while the container is uncached")
    assert_eq(db.GetSourceStringForMount(MOUNT_ID), "Contained in", "mount: bare label while the container is uncached")
    assert_eq((loadRequests[CONTAINER_TOY] or 0) > 0, true, "toy container load requested")
    assert_eq((loadRequests[CONTAINER_MOUNT] or 0) > 0, true, "mount container load requested")
end

print("Phase 2: the container loads; the next lookup shows its name")
do
    cachedNames[CONTAINER_TOY] = "Box of Toys"
    cachedNames[CONTAINER_MOUNT] = "Crate of Reins"
    assert_eq(db.GetSourceStringForToy(TOY), "Contained in : Box of Toys", "toy: label picks up the loaded name")
    assert_eq(db.GetSourceStringForMount(MOUNT_ID), "Contained in : Crate of Reins", "mount: label picks up the loaded name")
    cachedNames[CONTAINER_TOY] = nil
    assert_eq(db.GetSourceStringForToy(TOY), "Contained in : Box of Toys", "toy: resolved label is kept")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Source DB container name suite failed with " .. failed .. " failure(s).")
end
print("Source DB container name suite: ALL TESTS PASSED.")
