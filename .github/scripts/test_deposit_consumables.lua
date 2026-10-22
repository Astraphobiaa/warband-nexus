#!/usr/bin/env lua
--[[
    Regression test: the reagent / warband auto-deposit never moves food, drink, oils or whetstones.

    Player reports (CurseForge, 2026-09-22 .. 2026-10-05): warbound "Hearty" food and Thalassian oil
    were auto-deposited into the Warband bank, even with "Ignore Food & Drinks" on. Fixed in v3.5.16
    (694711a: classify by GetItemInfoInstant class/subclass; finished consumables, item enhancements
    and usable Miscellaneous items are never deposited). This pins that behaviour.

    Loads the shipped Modules/WarbandBankDepositService.lua under wow_stub.lua.
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

-- Item classes (Blizzard ItemConstantsDocumentation): Consumable 0, Gem 3, Reagent 5, Tradegoods 7,
-- ItemEnhancement 8, Miscellaneous 15. Tradegoods subclass 9 = Herb.
Enum.ItemClass = { Consumable = 0, Container = 1, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5,
    Tradegoods = 7, ItemEnhancement = 8, Questitem = 12, Miscellaneous = 15, Profession = 19 }
Enum.ItemConsumableSubclass = { Fooddrink = 5 }
Enum.ItemReagentSubclass = { Reagent = 0 }
Enum.BankType = { Character = 0, Guild = 1, Account = 2 }

local ITEMS = {
    [222728] = { name = "Hearty Champion's Bento (warbound food)", class = 0, sub = 5 },
    [259201] = { name = "Thalassian Mana Oil", class = 15, sub = 4, useSpell = 1236000 },
    [259190] = { name = "Thalassian Whetstone", class = 15, sub = 4, useSpell = 1236001 },
    [212244] = { name = "Weapon enhancement", class = 8, sub = 0 },
    [236761] = { name = "Herb reagent", class = 7, sub = 9 },
}
local bags = { [0] = { 222728, 259201, 259190, 212244, 236761 } }

C_Item.GetItemInfoInstant = function(id)
    local it = ITEMS[id]
    if not it then return nil end
    return id, "", "", "", 0, it.class, it.sub
end
C_Item.GetItemSpell = function(id)
    local it = ITEMS[id]
    if it and it.useSpell then return "Use", it.useSpell end
end
C_Item.GetItemInfo = function() return nil end
C_Container.GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end
C_Container.GetContainerItemInfo = function(bag, slot)
    local id = bags[bag] and bags[bag][slot]
    if id then return { itemID = id, stackCount = 1, isLocked = false } end
end
local moved = {}
C_Container.UseContainerItem = function(bag, slot) moved[#moved + 1] = bags[bag][slot] end
C_Bank = { IsItemAllowedInBankType = function() return true end }
ItemLocation = { CreateFromBagAndSlot = function() return { IsValid = function() return true end } end }

local ns = {}
local WarbandNexus = {
    db = { global = {}, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
    bankIsOpen = true,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end

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
LoadFile("Modules/WarbandBankDepositService.lua")

local function wasMoved(id)
    for i = 1, #moved do if moved[i] == id then return true end end
    return false
end

print("Phase 1: Manual deposit to the Warband bank (default settings)")
do
    WarbandNexus:TriggerReagentDeposit(true)
    stub.Advance(5)
    assert_eq(wasMoved(236761), true, "herb reagent deposited")
    assert_eq(wasMoved(222728), false, "warbound hearty food stays in the bags")
    assert_eq(wasMoved(259201), false, "Thalassian Mana Oil stays in the bags")
    assert_eq(wasMoved(259190), false, "Thalassian Whetstone stays in the bags")
    assert_eq(wasMoved(212244), false, "item enhancement stays in the bags")
end

print("Phase 2: Food stays even with 'Ignore Food & Drinks' turned off")
do
    moved = {}
    WarbandNexus.db.profile.reagentDeposit = { enabled = true, ignoreFood = false, destination = "warband",
        categories = { herbs = true, general = true, warbound = true } }
    stub.Advance(3)                                  -- past the 2s action cooldown
    WarbandNexus:TriggerReagentDeposit(true)
    stub.Advance(5)
    assert_eq(wasMoved(222728), false, "food is a finished consumable: never deposited")
    assert_eq(wasMoved(236761), true, "reagent still deposited")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Deposit consumables suite failed with " .. failed .. " failure(s).")
end
print("Deposit consumables suite: ALL TESTS PASSED.")
