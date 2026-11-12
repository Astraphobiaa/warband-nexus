#!/usr/bin/env lua
--[[
    Regression test: equipped item level persistence from equipment events.

    OnItemLevelChanged used a leading-edge throttle with no zero guard:
      - the first event of a burst (PLAYER_EQUIPMENT_CHANGED, before GetAverageItemLevel settles)
        was stored and the settled PLAYER_AVG_ITEM_LEVEL_UPDATE reading 0.1s later was dropped;
      - a 0 reading (gear not streamed in yet) overwrote the stored item level.
    Both left a stale or 0 ilvl on the Characters / PvE rows until the next gear change.

    Loads the shipped Modules/EventManager.lua under wow_stub.lua.
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

local liveIlvl = 0
GetAverageItemLevel = function() return liveIlvl, liveIlvl end

local ns = {}
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
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
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return "Player-01" end,
    ResolveCharactersTableKey = function() return "Player-01" end,
}
-- The real Utilities, because EventManager now reads the equipped average through
-- Utilities:GetEquippedItemLevel rather than calling GetAverageItemLevel itself. Loading the
-- shipped module keeps this test covering the actual path instead of a stub that agrees with it.

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
if not ns.Utilities then
    error("Utilities did not register on ns", 0)
end
-- No capability module here, so SupportsFeature is absent and the helper trusts the API -- which
-- is the retail path, and the one this suite is about.
LoadFile("Modules/EventManager.lua")

local row = { name = "Gearhound", itemLevel = 280.5 }
WarbandNexus.db.global.characters["Player-01"] = row

print("Phase 1: Settled reading of a gear-swap burst is the one stored")
do
    liveIlvl = 280.5                       -- PLAYER_EQUIPMENT_CHANGED: average not recomputed yet
    WarbandNexus:OnItemLevelChanged()
    stub.Advance(0.1)
    liveIlvl = 284.25                      -- PLAYER_AVG_ITEM_LEVEL_UPDATE: settled value
    WarbandNexus:OnItemLevelChanged()
    stub.Advance(1)
    assert_eq(row.itemLevel, 284.25, "settled item level persisted after the burst")
end

print("Phase 2: A 0 reading never overwrites the stored item level")
do
    liveIlvl = 0                           -- gear not streamed in yet (login / zoning)
    WarbandNexus:OnItemLevelChanged()
    stub.Advance(1)
    assert_eq(row.itemLevel, 284.25, "stored item level kept when the API reads 0")
end

print("Phase 3: where the API misreports, the average comes from the equipped pieces")
do
    -- WoW Forever answers a constant 1.75 from GetAverageItemLevel while the equipped gear scans
    -- as item levels 1..10. With the averageItemLevel capability off, Utilities must ignore the
    -- API and average the pieces itself.
    local equipped = { [1] = 10, [3] = 8, [4] = 1, [5] = 7, [16] = 12, [19] = 2 }
    GetInventoryItemLink = function(_, slot)
        return equipped[slot] and ("|Hitem:" .. slot .. "|h") or nil
    end
    C_Item = C_Item or {}
    C_Item.GetDetailedItemLevelInfo = function(link)
        local slot = tonumber(link:match("|Hitem:(%d+)|h"))
        return equipped[slot]
    end
    liveIlvl = 1.75
    WarbandNexus.SupportsFeature = function(_, key)
        if key == "averageItemLevel" then return false end
        return true
    end

    -- Shirt (4) and tabard (19) are excluded, so the average is over slots 1, 3, 5 and 16.
    local expected = (10 + 8 + 7 + 12) / 4
    assert_eq(ns.Utilities:GetEquippedItemLevel(), expected, "computed from equipped pieces, not the API")

    local _, count = ns.Utilities:ComputeEquippedItemLevel()
    assert_eq(count, 4, "shirt and tabard are left out of the count")

    WarbandNexus.SupportsFeature = function() return true end
    assert_eq(ns.Utilities:GetEquippedItemLevel(), 1.75, "with the capability on, the API wins again")
    WarbandNexus.SupportsFeature = nil
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Item level event suite failed with " .. failed .. " failure(s).")
end
print("Item level event suite: ALL TESTS PASSED.")
