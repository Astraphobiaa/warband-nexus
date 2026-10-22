#!/usr/bin/env lua
--[[
    Regression test: the item-count tooltip does not walk every alt's bags on every hover.

    GetDetailedItemCountsFast (every item tooltip, profession reagent lists) counted the item by
    walking each stored character's bags + bank array and the warband bank array, on every hover:
    with 20 characters that is ~10-15k rows per tooltip. Each array is now indexed once (itemID ->
    stacks) and reused until it is replaced or its length / generation changes, so a second hover
    reads no rows. Counts must stay identical, and a warband save must be picked up.

    Loads the shipped Modules/ItemsCacheService.lua under wow_stub.lua (uncompressed storage).
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

-- Serializer that fails: SaveWarbandBankCompressed takes its documented uncompressed fallback.
local noLib = { Serialize = function() return nil end }
LibStub = setmetatable({ GetLibrary = function() return noLib end }, { __call = function() return noLib end })
C_Item.GetItemCount = function(_, includeBank) return includeBank and 3 or 1 end
C_Item.IsItemKeystoneByID = function() return false end

local LIVE, ALT1, ALT2 = "Player-1-0000000A", "Player-1-0000000B", "Player-1-0000000C"
local reads = 0
local function counted(items)
    local out = {}
    for i = 1, #items do
        local real = items[i]
        out[i] = setmetatable({}, { __index = function(_, k)
            if k == "itemID" then reads = reads + 1 end
            return real[k]
        end })
    end
    return out
end

local ns = {}
local WarbandNexus = {
    db = { global = {
        characters = {
            [LIVE] = { name = "Live", classFile = "MAGE", isTracked = true },
            [ALT1] = { name = "Alt", classFile = "PRIEST", isTracked = true },
            [ALT2] = { name = "Bank", classFile = "ROGUE", isTracked = true },
        },
        itemStorage = {
            [ALT1] = {
                bags = { compressed = false, lastUpdate = 10, data = counted({
                    { itemID = 100, stackCount = 5 }, { itemID = 200, stackCount = 1 }, { itemID = 100, stackCount = 2 } }) },
                bank = { compressed = false, lastUpdate = 10, data = counted({ { itemID = 100, stackCount = 20 } }) },
            },
            [ALT2] = {
                bags = { compressed = false, lastUpdate = 10, data = counted({ { itemID = 300, stackCount = 1 } }) },
                bank = { compressed = false, lastUpdate = 10, data = counted({
                    { itemID = 100, stackCount = 4 }, { itemID = 180653, stackCount = 1, isKeystone = true } }) },
            },
            warbandBank = { compressed = false, lastUpdate = 10, data = counted({
                { itemID = 100, stackCount = 50 }, { itemID = 200, stackCount = 7 } }) },
        },
        guildBank = {},
    }, profile = {}, char = {} },
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
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function(_, _, k) return k or LIVE end,
    ResolveCharactersTableKey = function() return LIVE end,
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
ns.Utilities.GetCharacterStorageKey = function() return LIVE end
ns.Utilities.GetCanonicalCharacterKey = function(_, k) return k end
LoadFile("Modules/ItemsCacheService.lua")

local function rowFor(result, name)
    for i = 1, #result.characters do
        if result.characters[i].charName == name then return result.characters[i] end
    end
end

print("Phase 1: Counts are unchanged")
local first
do
    first = WarbandNexus:GetDetailedItemCountsFast(100)
    assert_eq(first and first.warbandBank, 50, "warband bank count")
    local alt, bank = rowFor(first, "Alt"), rowFor(first, "Bank")
    assert_eq(alt and alt.bagCount, 7, "alt bags summed over stacks")
    assert_eq(alt and alt.bankCount, 20, "alt bank")
    assert_eq(bank and bank.bankCount, 4, "second alt bank (keystone row ignored)")
    assert_eq(rowFor(first, "Live") and rowFor(first, "Live").bagCount, 1, "live character uses the live count")
    assert_eq(first.personalBankTotal, 2 + 20 + 4, "personal bank total")
    assert_eq(first.characters[1].isLiveSession, true, "live character sorted first")
end

print("Phase 2: A second hover reads no stored rows")
do
    reads = 0
    local again = WarbandNexus:GetDetailedItemCountsFast(200)
    local readsSecondItem = reads
    reads = 0
    WarbandNexus:GetDetailedItemCountsFast(100)
    assert_eq(again.warbandBank, 7, "other item counted from the same index")
    assert_eq(rowFor(again, "Alt") and rowFor(again, "Alt").bagCount, 1, "other item alt count")
    assert_eq(readsSecondItem, 0, "hovering another item walks no arrays (index reused)")
    assert_eq(reads, 0, "hovering the same item again walks no arrays")
end

print("Phase 3: A warband bank save is picked up")
do
    -- Same length as before (2 rows), so only the replaced table / generation can invalidate.
    WarbandNexus:SaveWarbandBankCompressed({ { itemID = 100, stackCount = 60 }, { itemID = 200, stackCount = 7 } })
    local r = WarbandNexus:GetDetailedItemCountsFast(100)
    assert_eq(r and r.warbandBank, 60, "new warband count after invalidation")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Tooltip item count suite failed with " .. failed .. " failure(s).")
end
print("Tooltip item count suite: ALL TESTS PASSED.")
