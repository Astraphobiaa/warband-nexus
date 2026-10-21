#!/usr/bin/env lua
--[[
    Regression test: mail items that are crafting reagents must be classified as "reagent".

    ClassifyMailItemKind asked C_Item.IsCraftingReagent, which does not exist in 12.1.5
    (Blizzard_APIDocumentationGenerated 70448, Ketho GlobalAPI dump). The call was feature-detected,
    so reagents outside the Tradegoods item class (e.g. Midnight finishing reagents filed as
    Miscellaneous) were stored as "other".

    Now: isCraftingReagent is read from C_Item.GetItemInfo's documented 17th return; when the item is
    not cached (no returns) the class-based check still runs.

    Loads the shipped MailSnapshotService.lua under wow_stub.lua. Item IDs are illustrative.
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

local REAGENT_MISC = 240001      -- crafting reagent filed under Miscellaneous (classID 15)
local PLAIN_MISC = 240002        -- Miscellaneous, not a reagent
local UNCACHED = 240003          -- GetItemInfo returns nothing yet
local reagentFlag = { [REAGENT_MISC] = true, [PLAIN_MISC] = false }

C_Item.GetItemInfo = function(id)
    if reagentFlag[id] == nil then return end
    -- itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount,
    -- itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expansionID, setID,
    -- isCraftingReagent, itemDescription (12.1.5 API doc)
    return "Item" .. id, "|Hitem:" .. id .. "::::::::::::::::|h[Item" .. id .. "]|h", 1, 90, 0, "Miscellaneous", "Other",
        200, "", 134400, 0, 15, 4, 0, 11, nil, reagentFlag[id], ""
end
-- itemID, itemType, itemSubType, itemEquipLoc, icon, classID
C_Item.GetItemInfoInstant = function(id) return id, "Miscellaneous", "Other", "", 134400, 15 end
C_Item.GetItemQualityByID = function() return 1 end
C_Item.GetDetailedItemLevelInfo = function() return nil end

local ns = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
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

LoadFile("Modules/Constants.lua")
LoadFile("Modules/MailSnapshotService.lua")
local M = ns.MailSnapshot

print("Phase 1: GetItemInfo's isCraftingReagent marks a Miscellaneous item as a reagent")
do
    local it = M.NormalizeMailItem({ itemID = REAGENT_MISC, name = "Item" .. REAGENT_MISC, count = 20 })
    assert_eq(it.kind, "reagent", "reagent flag from the 17th GetItemInfo return")
end

print("Phase 2: Non-reagents and uncached items fall through to the class check")
do
    local plain = M.NormalizeMailItem({ itemID = PLAIN_MISC, name = "Item" .. PLAIN_MISC, count = 1 })
    assert_eq(plain.kind, "other", "isCraftingReagent false is not a reagent")
    local uncached = M.NormalizeMailItem({ itemID = UNCACHED, name = "Item" .. UNCACHED, count = 1 })
    assert_eq(uncached.kind, "other", "uncached item classified without error")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Mail reagent classification suite failed with " .. failed .. " failure(s).")
end
print("Mail reagent classification suite: ALL TESTS PASSED.")
