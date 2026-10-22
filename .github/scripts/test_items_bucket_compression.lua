#!/usr/bin/env lua
--[[
    Regression test: item buckets end up compressed in SavedVariables.

    During play a dirty bag is first written uncompressed by the fast persist (~15 s after the last
    change) with its content signature. The logout / leaving-world flush then called
    SaveItemsCompressedImmediate, which returned early whenever the stored signature matched,
    without looking at the compressed flag. Every bag that sat still after its fast write stayed
    uncompressed for good: on a real account 10 of 16 buckets, ~518 KB instead of ~24 KB.

    Loads the shipped Modules/ItemsCacheService.lua under wow_stub.lua with a fake serializer /
    deflate pair (round-trips through a lookup table) and checks:
      1. fast persist -> sync flush leaves the current character's bucket compressed;
      2. buckets another session left uncompressed (other characters) are packed by the sync flush;
      3. packed data still decodes to the same rows; a compressed bucket with the same content is
         not re-packed.
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

-- Fake AceSerializer + LibDeflate: payloads are kept in a table, the stored value is a token string.
local payloads, packs = {}, 0
local fakeLib = {
    Serialize = function(_, data) payloads[#payloads + 1] = data; return "ser:" .. #payloads end,
    Deserialize = function(_, s) local i = tonumber(s:match("^ser:(%d+)$")); return i ~= nil, payloads[i] end,
    CompressDeflate = function(_, s) packs = packs + 1; return "z:" .. s end,
    DecompressDeflate = function(_, s) return (s:gsub("^z:", "")) end,
    EncodeForPrint = function(_, s) return "p:" .. s end,
    DecodeForPrint = function(_, s) return (s:gsub("^p:", "")) end,
}
LibStub = setmetatable({ GetLibrary = function() return fakeLib end }, { __call = function() return fakeLib end })
C_Item.GetItemCount = function() return 0 end
C_Item.IsItemKeystoneByID = function() return false end

local LIVE, ALT = "Player-1-0000000A", "Player-1-0000000B"
local altRows = { { itemID = 300, stackCount = 2, slot = 1, bagID = 0 }, { itemID = 301, stackCount = 1, slot = 2, bagID = 0 } }

local ns = {}
local WarbandNexus = {
    db = { global = {
        characters = {
            [LIVE] = { name = "Live", classFile = "MAGE", isTracked = true },
            [ALT] = { name = "Alt", classFile = "PRIEST", isTracked = true },
        },
        itemStorage = {
            -- Left by an earlier session's fast persist.
            [ALT] = { bags = { compressed = false, lastUpdate = 10, data = altRows, slotCount = 2, stackTotal = 3, contentSig = "old" } },
            warbandBank = { compressed = true, lastUpdate = 10, data = "p:z:ser:0" },
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

local storage = WarbandNexus.db.global.itemStorage
local liveRows = { { itemID = 100, stackCount = 5, slot = 1, bagID = 0 }, { itemID = 200, stackCount = 1, slot = 2, bagID = 0 } }

print("Phase 1: fast persist, then the leaving-world flush")
do
    WarbandNexus:SaveItemsCompressed(LIVE, "bags", liveRows)
    stub.Advance(60)
    local b = storage[LIVE] and storage[LIVE].bags
    assert_eq(b and b.compressed, false, "fast persist wrote the bucket uncompressed")
    WarbandNexus:FlushItemsCacheOnLeavingWorld()
    b = storage[LIVE] and storage[LIVE].bags
    assert_eq(b and b.compressed, true, "sync flush compressed the bucket with an unchanged signature")
    assert_eq(b and type(b.data), "string", "compressed bucket stores a string")
end

print("Phase 2: buckets another session left uncompressed")
do
    local b = storage[ALT].bags
    assert_eq(b.compressed, true, "other character's uncompressed bucket packed by the sync flush")
    assert_eq(type(b.data), "string", "packed bucket stores a string")
    assert_eq(b.slotCount, 2, "bucket metadata kept")
    local ok, rows = fakeLib:Deserialize(fakeLib:DecompressDeflate(fakeLib:DecodeForPrint(b.data)))
    assert_eq(ok and rows and rows[1] and rows[1].itemID, 300, "packed data decodes to the same rows")
    assert_eq(storage.warbandBank.data, "p:z:ser:0", "warband bank bucket left alone")
end

print("Phase 3: an already compressed bucket with the same content is not re-packed")
do
    local before = packs
    WarbandNexus:SaveItemsCompressedImmediate(LIVE, "bags", liveRows)
    assert_eq(packs, before, "same content, already compressed: no compress call")
    WarbandNexus:FlushItemsCacheOnLeavingWorld()
    assert_eq(packs, before, "second flush finds nothing left to pack")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")
if #stub.errors > 0 then for i = 1, #stub.errors do print("    err: " .. stub.errors[i]) end end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Items bucket compression suite failed with " .. failed .. " failure(s).")
end
print("Items bucket compression suite: ALL TESTS PASSED.")
