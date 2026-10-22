#!/usr/bin/env lua
--[[
    Regression test: the collectible bag scan never trusts an ItemsCache bag snapshot older than the
    newest bag change.

    The collectible scan runs ~0.06 s after BAG_UPDATE_DELAYED, but ItemsCache publishes its bag
    snapshot only after the 0.5 s BAG_UPDATE bucket. The scan judged the snapshot by age (0.65 s TTL),
    so a second loot shortly after the previous publish read the old snapshot: the new slot went into
    the baseline unseen and its mount / pet / toy notification was lost until that bag changed again.
    The snapshot now carries the bag generation its slot data was read at and is used only while that
    generation is current. A throttled (deferred) ItemsCache write publishes slot data captured at an
    earlier BAG_UPDATE, so it must carry the capture generation, not the publish-time one.

    Loads the shipped Modules/ItemsCacheService.lua and CollectionService*.lua under wow_stub.lua and
    drives BAG_UPDATE / BAG_UPDATE_DELAYED plus the ItemsCache bucket callback on a fake clock.
]]

local passed, failed = 0, 0
local function check(cond, msg, detail)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg .. (detail and (": " .. tostring(detail)) or ""))
    end
end
local function assert_eq(actual, expected, msg)
    check(actual == expected, msg, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

-- Serializer that fails: ItemsCache takes its documented uncompressed fallback.
local noLib = { Serialize = function() return nil end }
LibStub = setmetatable({ GetLibrary = function() return noLib end }, { __call = function() return noLib end })
C_Item.GetItemCount = function() return 0 end
C_Item.IsItemKeystoneByID = function() return false end

-- ---------- message bus ----------
local sent = {}
local bus = {}
local function RegisterMessage(target, msg, fn)
    if type(fn) == "string" then
        local name = fn
        fn = function(...) return target[name](target, ...) end
    end
    bus[msg] = bus[msg] or {}
    bus[msg][target] = fn
end
local function SendMessage(_, msg, ...)
    sent[#sent + 1] = { msg = msg, arg = (...) }
    local list = bus[msg]
    if not list then return end
    for _, fn in pairs(list) do pcall(fn, msg, ...) end
end

local LIVE = "Player-1-0000000A"
local ns = {}
local WarbandNexus = {
    db = { global = { characters = { [LIVE] = { name = "Live", classFile = "MAGE", isTracked = true } },
                      itemStorage = {} },
           profile = { modulesEnabled = { collections = true } }, char = {} },
    SendMessage = SendMessage,
    RegisterMessage = RegisterMessage,
    UnregisterMessage = function() end,
    RegisterEvent = function() end,
    UnregisterEvent = function() end,
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
string.trim = string.trim or strtrim

-- ---------- bag model: bag 0 only, 8 slots; 9000 = junk (class 7), 9001+ = mount items ----------
local bags = { [0] = { 9000 } }
local liveReads = 0
C_Container.GetContainerNumSlots = function(bagID) return bagID == 0 and 8 or 0 end
C_Container.GetContainerItemInfo = function(bagID, slotID)
    liveReads = liveReads + 1
    local id = bags[bagID] and bags[bagID][slotID]
    if not id then return nil end
    return { itemID = id, hyperlink = "|Hitem:" .. id .. ":|h[Item" .. id .. "]|h", stackCount = 1 }
end
C_Item.GetItemInfoInstant = function(id)
    if id == 9000 then return id, nil, nil, nil, nil, 7, 0 end
    return id, nil, nil, nil, nil, 15, 5
end
C_Item.GetItemIconByID = function(id) return 5000 + id end

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
LoadFile("Modules/Utilities.lua")
ns.Utilities.IsModuleEnabled = function() return true end
ns.Utilities.IsAnyModuleEnabled = function() return true end
ns.Utilities.GetCharacterStorageKey = function() return LIVE end
ns.Utilities.GetCanonicalCharacterKey = function(_, k) return k end
LoadFile("Modules/ItemsCacheService.lua")
LoadFile("Modules/MigrationService.lua")
LoadFile("Modules/CollectionService_Materialize.lua")
LoadFile("Modules/CollectionService_NotifyDedup.lua")
LoadFile("Modules/CollectionService_Scan.lua")
LoadFile("Modules/CollectionService.lua")

local E = ns.Constants.EVENTS
WarbandNexus.CheckNewCollectible = function(_, itemID)
    if itemID ~= 9000 then return { type = "mount", id = itemID + 100, name = "BagMount" .. itemID, icon = 1 } end
    return nil
end
local function Obtained(itemID)
    local n = 0
    for i = 1, #sent do
        if sent[i].msg == E.COLLECTIBLE_OBTAINED and type(sent[i].arg) == "table" and sent[i].arg.id == itemID + 100 then
            n = n + 1
        end
    end
    return n
end
-- The ItemsCache BAG_UPDATE bucket (RegisterBucketEvent is stubbed): what AceBucket calls after 0.5 s.
local function ItemsBucket()
    WarbandNexus:OnBagUpdate({ [0] = true })
end
local function Loot(slot, itemID)
    bags[0][slot] = itemID
    stub.Fire("BAG_UPDATE", 0)
    stub.Fire("BAG_UPDATE_DELAYED")
end
local function Snap()
    return ns.ItemsCacheBagSnapshots and ns.ItemsCacheBagSnapshots[0]
end

-- Login: baseline + first ItemsCache publish.
stub.Fire("PLAYER_ENTERING_WORLD", true, false)
ItemsBucket()
stub.Advance(3)
check(Snap() ~= nil, "setup: ItemsCache published a bag 0 snapshot")

-- ======================================================================
print("1. A second loot shortly after the previous publish is still announced")
-- ======================================================================
sent = {}
Loot(2, 9001)
stub.Advance(0.1)                 -- collectible scan (~0.06 s)
assert_eq(Obtained(9001), 1, "first loot: mount item announced")
stub.Advance(0.4)
ItemsBucket()                     -- bucket at +0.5 s publishes a snapshot that holds 9001
check(Snap() and Snap().slots["0_2"] == 9001, "bucket published the snapshot with the first loot")
stub.Advance(0.05)
Loot(3, 9002)                     -- 0.05 s after that publish
stub.Advance(0.1)
assert_eq(Obtained(9002), 1, "second loot within 0.65 s of the publish: mount item announced")
assert_eq(ns.CollectionScan.previousBagContents["0_3"], 9002, "second loot: baseline holds the new slot")

-- ======================================================================
print("2. A current snapshot still replaces the live container walk")
-- ======================================================================
stub.Advance(0.4)
ItemsBucket()
stub.Advance(0.2)
check(Snap() and Snap().slots["0_3"] == 9002, "snapshot caught up with the second loot")
liveReads = 0
sent = {}
WarbandNexus:OnBagUpdateForCollectibles({ [0] = true })
assert_eq(liveReads, 0, "no bag change since the publish: scan reads the snapshot, no C_Container walk")
assert_eq(#sent, 0, "unchanged bag: nothing announced")

-- ======================================================================
print("3. A deferred ItemsCache write carries the generation its slots were read at")
-- ======================================================================
-- Publish P was 0.3 s ago (past the 0.08 s scan throttle); run a bucket inside the 0.5 s
-- throttle so its slot capture is deferred, then loot again before the deferred write lands.
stub.Advance(0.1)
sent = {}
Loot(4, 9003)
stub.Advance(0.05)
ItemsBucket()                     -- throttled: captures slots (with 9003), flush scheduled
stub.Advance(0.05)                -- collectible scan for 9003
assert_eq(Obtained(9003), 1, "third loot: mount item announced")
stub.Advance(0.06)                -- P+0.46: the scan for the next loot lands after the P+0.5 flush
Loot(5, 9004)                     -- newer change than the deferred capture
stub.Advance(0.3)                 -- deferred flush (P+0.5) publishes the old capture; then the scan runs
check(Snap() and Snap().slots["0_4"] == 9003 and Snap().slots["0_5"] == nil,
    "deferred write published the earlier capture (without the newest loot)")
assert_eq(Obtained(9004), 1, "loot after the deferred capture: mount item announced")
assert_eq(ns.CollectionScan.previousBagContents["0_5"], 9004, "newest loot is in the baseline")

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Bag snapshot generation suite failed with " .. failed .. " failure(s).")
end
print("Bag snapshot generation suite: ALL TESTS PASSED.")
