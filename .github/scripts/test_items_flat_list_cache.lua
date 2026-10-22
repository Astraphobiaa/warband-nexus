#!/usr/bin/env lua
--[[
    Regression test: the Items flat-list cache never serves a list for different item contents.

    BuildItemsVirtualFlatList cached its result under subtab + search + #items + expanded groups.
    With the same item count but different contents (an item swapped for another, a stack size
    change, a name that finished loading) it returned the previous flat list, whose rows point at the
    previous item tables: stale rows until the count changed. The key now includes each item's ID,
    stack, location and pending / name state; unchanged contents still hit the cache.

    Loads the shipped Modules/UI/ItemsUI.lua under wow_stub.lua.
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

local ns = { UI = { Factory = {} } }
local WN = { db = { profile = {}, global = {} }, RegisterMessage = function() end }
ns.WarbandNexus = WN
local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
LoadFile("Modules/Constants.lua")
ns.SearchStateManager = { UpdateResults = function() end, GetQuery = function() return "" end }
ns.UI_GetExpandedGroups = function() return {} end
ns.StorageSectionLayout = {}
LoadFile("Modules/UI/ItemsUI.lua")

local current
WN.GetInventoryItems = function() return current end
WN.UI = { mainFrame = {} }
WN.itemsExpandAllActive = true

local function rowItemIDs(fl)
    local ids = {}
    for i = 1, #(fl or {}) do
        if fl[i].type == "row" and fl[i].data then ids[#ids + 1] = fl[i].data.itemID end
    end
    return table.concat(ids, ",")
end
local function build() return WN:BuildItemsVirtualFlatList(400, "inventory", "", 0) end

print("Phase 1: Unchanged contents hit the cache")
local first
do
    current = { { itemID = 1, stackCount = 5, name = "Apple", actualBagID = 0, slotIndex = 1 },
                { itemID = 2, stackCount = 1, name = "Bread", actualBagID = 0, slotIndex = 2 } }
    first = build()
    assert_eq(rowItemIDs(first), "1,2", "rows built")
    current = { { itemID = 1, stackCount = 5, name = "Apple", actualBagID = 0, slotIndex = 1 },
                { itemID = 2, stackCount = 1, name = "Bread", actualBagID = 0, slotIndex = 2 } }
    assert_eq(build(), first, "same contents (fresh tables): cached flat list reused")
end

print("Phase 2: Same count, different contents rebuilds")
do
    current = { { itemID = 1, stackCount = 5, name = "Apple", actualBagID = 0, slotIndex = 1 },
                { itemID = 3, stackCount = 1, name = "Cheese", actualBagID = 0, slotIndex = 2 } }
    local fl = build()
    assert_eq(fl ~= first, true, "swapped item: not the cached list")
    assert_eq(rowItemIDs(fl), "1,3", "swapped item shown")

    current = { { itemID = 1, stackCount = 9, name = "Apple", actualBagID = 0, slotIndex = 1 },
                { itemID = 3, stackCount = 1, name = "Cheese", actualBagID = 0, slotIndex = 2 } }
    local byStack = build()
    assert_eq(byStack ~= fl, true, "stack size change: rebuilt")
    local row1
    for i = 1, #byStack do if byStack[i].type == "row" and byStack[i].data.itemID == 1 then row1 = byStack[i] end end
    assert_eq(row1 and row1.data.stackCount, 9, "new stack size in the row data")

    current = { { itemID = 1, stackCount = 9, name = "Apple", actualBagID = 0, slotIndex = 1 },
                { itemID = 3, stackCount = 1, pending = true, actualBagID = 0, slotIndex = 2 } }
    local pend = build()
    current = { { itemID = 1, stackCount = 9, name = "Apple", actualBagID = 0, slotIndex = 1 },
                { itemID = 3, stackCount = 1, name = "Cheese", actualBagID = 0, slotIndex = 2 } }
    assert_eq(build() ~= pend, true, "a name that finished loading rebuilds")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Items flat list cache suite failed with " .. failed .. " failure(s).")
end
print("Items flat list cache suite: ALL TESTS PASSED.")
