#!/usr/bin/env lua
--[[
    Regression test: equipped-gear scan cost / messages and the storage finder's item filter.

    Loads the shipped Modules/GearService.lua + GearService_StorageFind.lua under wow_stub.lua and checks:
      A1. A rescan that changes nothing (crest / batch CURRENCY_UPDATED, save pass) sends no
          GEAR_UPDATED: an empty slot list made the Gear tab repaint everything. A slot whose link is
          the same but whose ilvl moved is still reported by slot.
      A2. Slots whose link did not change do not re-read their tooltip (C_TooltipInfo.GetInventoryItem);
          the event's slot does; a new link reads its tooltip once, not twice.
      A3. PLAYER_LOGOUT does no live inventory read: a partial teardown read cannot overwrite the row,
          and a pending equip-change scan is cancelled.
      A4. FindGearStorageUpgrades runs the cosmetic API only for equippable items and reads
          GetItemInfoInstant once per itemID; the findings stay the same.
      A5. Stored slot rows carry no `name` and no false hasEnchant / isMissingGem / isEnchantable.
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
table.wipe = table.wipe or wipe

local LIVE = "Player-1-0000000A"

-- ---------- world: equipped items ----------
local UPGRADE_LINE = 99
Enum.TooltipDataLineType = { ItemUpgradeLevel = UPGRADE_LINE }
local function MakeLink(itemID, enchant)
    return "|cffa335ee|Hitem:" .. itemID .. ":" .. (enchant or "") .. "::::::::::::::|h[Item" .. itemID .. "]|h|r"
end
local equipped = {}       -- slotID -> link
local ilvlByLink = {}     -- link -> ilvl
local equipLocByID = {}   -- itemID -> INVTYPE_*
local function Equip(slotID, itemID, ilvl, equipLoc, enchant)
    local link = MakeLink(itemID, enchant)
    equipped[slotID] = link
    ilvlByLink[link] = ilvl
    equipLocByID[itemID] = equipLoc
    return link
end
local SLOT_LOCS = {
    [1] = "INVTYPE_HEAD", [2] = "INVTYPE_NECK", [3] = "INVTYPE_SHOULDER", [15] = "INVTYPE_CLOAK",
    [5] = "INVTYPE_CHEST", [9] = "INVTYPE_WRIST", [10] = "INVTYPE_HAND", [6] = "INVTYPE_WAIST",
    [7] = "INVTYPE_LEGS", [8] = "INVTYPE_FEET", [11] = "INVTYPE_FINGER", [12] = "INVTYPE_FINGER",
    [13] = "INVTYPE_TRINKET", [14] = "INVTYPE_TRINKET", [16] = "INVTYPE_WEAPON", [17] = "INVTYPE_HOLDABLE",
}
for sid, loc in pairs(SLOT_LOCS) do
    Equip(sid, 5000 + sid, 250, loc, sid == 16 and "7000" or nil)
end

local invReads, tipReads, tipReadsBySlot = 0, 0, {}
GetInventoryItemLink = function(_, slotID)
    invReads = invReads + 1
    return equipped[slotID]
end
C_TooltipInfo = {
    GetInventoryItem = function(_, slotID)
        tipReads = tipReads + 1
        tipReadsBySlot[slotID] = (tipReadsBySlot[slotID] or 0) + 1
        return { lines = { { leftText = "Upgrade Level: Hero 3/6", type = UPGRADE_LINE } } }
    end,
}
C_ItemUpgrade = {}
LE_ITEM_CLASS_ARMOR = 4   -- the stub answers every unknown CAPS global with its own name
ItemLocation = { CreateFromEquipmentSlot = function() return { IsValid = function() return true end } end }

local function IDFromLink(v)
    if type(v) == "number" then return v end
    local id = type(v) == "string" and v:match("item:(%d+)")
    return id and tonumber(id) or nil
end
local instantCalls, instantCallsByID = 0, {}
C_Item.GetItemInfoInstant = function(v)
    local id = IDFromLink(v)
    if not id then return nil end
    instantCalls = instantCalls + 1
    instantCallsByID[id] = (instantCallsByID[id] or 0) + 1
    local loc = equipLocByID[id] or ""
    local classID = (loc ~= "" and loc ~= "INVTYPE_NON_EQUIP") and 4 or 0
    return id, "Type", "SubType", loc, 134400, classID, classID == 4 and 1 or 0  -- armor: cloth (mage)
end
GetItemInfoInstant = C_Item.GetItemInfoInstant
C_Item.GetItemInfo = function(v)
    local id = IDFromLink(v)
    local link = type(v) == "string" and v or MakeLink(id)
    return "Item" .. tostring(id), link, 4, ilvlByLink[link] or 0
end
C_Item.GetDetailedItemLevelInfo = function(v) return ilvlByLink[v] or 0 end
C_Item.GetItemStats = function() return { ITEM_MOD_INTELLECT_SHORT = 10 } end
local cosmeticCalls, cosmeticIDs = 0, {}
C_Item.IsCosmeticItem = function(v)
    cosmeticCalls = cosmeticCalls + 1
    return cosmeticIDs[IDFromLink(v)] == true
end
UnitSex = function() return 2 end
UnitRace = function() return "Human", "Human", 1 end
UnitLevel = function() return 90 end
UnitClass = function() return "Mage", "MAGE", 8 end

-- ---------- addon ----------
local sent = {}
local ns = {}
local WarbandNexus = {
    db = { global = { characters = {}, gearData = {}, itemStorage = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) sent[#sent + 1] = { msg = msg, payload = payload } end,
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
    ResolveSubsidiaryCharacterKey = function() return LIVE end,
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
ns.Utilities.IsModuleEnabled = function() return true end
LoadFile("Modules/Data/SeasonData.lua")
LoadFile("Modules/GearService_Slots.lua")
LoadFile("Modules/GearService_UpgradeTracks.lua")
LoadFile("Modules/GearService.lua")
LoadFile("Modules/GearService_StorageFind.lua")

local GEAR_UPDATED = ns.Constants.EVENTS.GEAR_UPDATED
local function GearMessages()
    local out = {}
    for i = 1, #sent do
        if sent[i].msg == GEAR_UPDATED then out[#out + 1] = sent[i].payload end
    end
    return out
end
local function HasSlot(payload, sid)
    local ids = payload and payload.slotIDs or {}
    for i = 1, #ids do
        if ids[i] == sid then return true end
    end
    return false
end
local function ResetCounters()
    sent = {}
    tipReads, tipReadsBySlot, invReads = 0, {}, 0
end
local function Row() return WarbandNexus.db.global.gearData[LIVE] end

print("Phase 1: first scan (no stored row)")
do
    ResetCounters()
    WarbandNexus:ScanEquippedGear()
    local row = Row()
    assert_eq(row and row.slots and row.slots[1] and row.slots[1].upgradeTrack, "Hero", "first scan stored the tooltip track")
    local msgs = GearMessages()
    assert_eq(#msgs, 1, "first scan sends one GEAR_UPDATED")
    assert_eq(HasSlot(msgs[1], 1) and HasSlot(msgs[1], 16), true, "first scan lists the filled slots")
    assert_eq(tipReadsBySlot[1], 1, "A2: a new link reads its tooltip once, not twice")
end

print("Phase 2 (A5): stored row shape")
do
    local s1, s16 = Row().slots[1], Row().slots[16]
    assert_eq(s1.name, nil, "A5: no stored item name (the link carries it)")
    assert_eq(s1.hasEnchant, nil, "A5: hasEnchant=false is not stored")
    assert_eq(s1.isMissingGem, nil, "A5: isMissingGem=false is not stored")
    assert_eq(s16.hasEnchant, true, "A5: hasEnchant=true still stored")
end

print("Phase 3 (A1 + A2): rescan with nothing changed (crest / batch currency path)")
do
    local before = Row()
    ResetCounters()
    WarbandNexus:ScanEquippedGear()
    assert_eq(#GearMessages(), 0, "A1: unchanged rescan sends no GEAR_UPDATED")
    assert_eq(tipReads, 0, "A2: unchanged links re-read no tooltip")
    assert_eq(Row() ~= before and Row().slots[1].upgradeTrack, "Hero", "row still persisted with its track")
end

print("Phase 4 (A1): same link, item level moved")
do
    ilvlByLink[equipped[5]] = 253
    ResetCounters()
    WarbandNexus:ScanEquippedGear()
    local msgs = GearMessages()
    assert_eq(#msgs, 1, "A1: a field-only change still sends GEAR_UPDATED")
    assert_eq(HasSlot(msgs[1], 5), true, "A1: the slot with the new ilvl is listed")
    assert_eq(HasSlot(msgs[1], 1), false, "A1: untouched slots are not listed")
end

print("Phase 5 (A2): equipment event on an unchanged slot, then a real swap")
do
    ResetCounters()
    WarbandNexus:ScanEquippedGear(6)
    local msgs = GearMessages()
    assert_eq(#msgs == 1 and HasSlot(msgs[1], 6), true, "event slot is still reported")
    assert_eq(tipReads, 1, "A2: only the event's slot re-reads its tooltip")
    assert_eq(tipReadsBySlot[6], 1, "A2: that read is for slot 6")

    Equip(1, 6001, 259, "INVTYPE_HEAD")
    ResetCounters()
    WarbandNexus:ScanEquippedGear(1)
    msgs = GearMessages()
    assert_eq(#msgs == 1 and HasSlot(msgs[1], 1), true, "swap reports slot 1")
    assert_eq(tipReads, 1, "A2: swap reads one tooltip, for the new link")
end

print("Phase 6 (A3): PLAYER_LOGOUT does no live read")
do
    local stored = Row()
    local storedNeck = stored.slots[2]
    -- Teardown: the neck reads empty, the rest is still there.
    local savedNeck = equipped[2]
    equipped[2] = nil
    ResetCounters()
    WarbandNexus:OnGearEquipmentChanged(7)
    WarbandNexus:FlushGearCacheOnLogout()
    stub.Advance(5)
    assert_eq(Row(), stored, "A3: logout left the stored row in place")
    assert_eq(Row().slots[2], storedNeck, "A3: partial teardown read did not drop the neck slot")
    assert_eq(#GearMessages(), 0, "A3: the pending equip-change scan was cancelled")
    equipped[2] = savedNeck
end

print("Phase 7 (A4): storage finder filters by equip slot before the cosmetic check")
do
    WarbandNexus.db.global.characters[LIVE] = { name = "Live", classFile = "MAGE", isTracked = true, level = 90 }
    WarbandNexus.IsGearStorageRecommendationsEnabled = function() return true end
    WarbandNexus.GearStoragePanelDebug = function() end
    WarbandNexus.GearStorageTrace = function() end
    local items = {}
    for i = 1, 40 do
        local id = 9000 + (i % 10)          -- 10 distinct non-gear itemIDs, 4 copies each
        items[#items + 1] = { itemID = id, itemLink = MakeLink(id), quality = 1, itemLevel = 0 }
    end
    local cosmeticID, gearID = 8101, 8102
    equipLocByID[cosmeticID] = "INVTYPE_HEAD"
    equipLocByID[gearID] = "INVTYPE_HEAD"
    cosmeticIDs[cosmeticID] = true
    for _, id in ipairs({ cosmeticID, gearID }) do
        local link = MakeLink(id)
        ilvlByLink[link] = 300
        items[#items + 1] = { itemID = id, itemLink = link, quality = 4, itemLevel = 300, isBound = false }
    end
    WarbandNexus.GetWarbandBankData = function() return { items = items } end
    cosmeticCalls, instantCalls, instantCallsByID = 0, 0, {}
    local ok, findings = pcall(WarbandNexus.FindGearStorageUpgrades, WarbandNexus, LIVE)
    assert_eq(ok, true, "FindGearStorageUpgrades ran" .. (ok and "" or (": " .. tostring(findings))))
    findings = ok and findings or {}
    assert_eq(cosmeticCalls, 2, "A4: cosmetic API asked only for the 2 equippable items")
    assert_eq(instantCallsByID[9001], 2, "A4: GetItemInfoInstant read once per itemID and once per link (4 copies)")
    local head = findings[1] or {}
    local hasGear, hasCosmetic = false, false
    for i = 1, #head do
        if head[i].itemID == gearID then hasGear = true end
        if head[i].itemID == cosmeticID then hasCosmetic = true end
    end
    assert_eq(hasGear, true, "A4: the equippable non-cosmetic item is still recommended")
    assert_eq(hasCosmetic, false, "A4: the cosmetic item is still rejected")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")
if #stub.errors > 0 then for i = 1, #stub.errors do print("    err: " .. stub.errors[i]) end end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Gear scan / storage find suite failed with " .. failed .. " failure(s).")
end
print("Gear scan / storage find suite: ALL TESTS PASSED.")
