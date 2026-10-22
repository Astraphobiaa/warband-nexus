#!/usr/bin/env lua
--[[
    Regression test: crafting-order counts must come from APIs that exist in 12.1.5.

    CollectCraftingOrdersData called C_CraftingOrders.GetNumPersonalOrders / GetNumGuildOrders.
    Neither exists in Blizzard_APIDocumentationGenerated 12.1.5 (70448), and the calls were
    feature-detected, so every stored count was 0.

    Now: the personal count is the open profession's entry in C_CraftingOrders.GetPersonalOrdersInfo()
    (CraftingOrderPersonalOrdersInfo.numPersonalOrders, matched on Enum.Profession). The guild count
    has no getter; it arrives with CRAFTINGORDERS_UPDATE_ORDER_COUNT (orderType, numOrders), which
    Blizzard_ProfessionsCrafterOrderPage uses for its tab titles, and later collections keep it.

    2026-10-22: an unread personal list (pcall error / no table) wrote 0 over the stored count, and the
    logout flush re-read the counts during PLAYER_LOGOUT teardown. Both now keep the stored count.

    Loads the shipped ProfessionService.lua under wow_stub.lua. Skill line / enum values are illustrative.
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
table.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local SKILL_LINE = 2918            -- open child profession (Midnight Tailoring)
local PROF_TAILORING = 8           -- Enum.Profession value reported by GetBaseProfessionInfo
local PROF_OTHER = 3
Enum = Enum or {}
Enum.CraftingOrderType = { Public = 0, Guild = 1, Personal = 2, Npc = 3 }

C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end,
    GetProfessionChildSkillLineID = function() return SKILL_LINE end,
    GetBaseProfessionInfo = function() return { profession = PROF_TAILORING, professionName = "Tailoring" } end,
    GetChildProfessionInfo = function() return { professionID = SKILL_LINE, professionName = "Midnight Tailoring" } end,
    GetConcentrationCurrencyID = function() return 0 end,
    GetProfessionInfoBySkillLineID = function() return nil end,
}
local personalInfos = {
    { profession = PROF_OTHER, numPersonalOrders = 9, professionName = "Blacksmithing" },
    { profession = PROF_TAILORING, numPersonalOrders = 3, professionName = "Tailoring" },
}
C_CraftingOrders = {
    GetPersonalOrdersInfo = function() return personalInfos end,
    GetClaimedOrder = function() return nil end,
}

local ns = {}
local fired = {}
local WarbandNexus = {
    db = { profile = { modulesEnabled = { professions = true } }, global = { characters = {} }, char = {} },
    RegisterMessage = function() end,
    SendMessage = function(_, msg) fired[#fired + 1] = msg end,
    RegisterEvent = function() end,
    Print = function() end,
    Debug = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = { SVC = "svc" }, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    GetCharacterStorageKey = function() return "Player-01" end,
    GetCharacterKey = function() return "Player-01" end,
    IsModuleEnabled = function(_, mod) return mod == "professions" end,
}
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveCharactersTableKey = function() return "Player-01" end,
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
LoadFile("Modules/ProfessionService.lua")
LoadFile("Modules/ProfessionService_WeeklyKnowledge.lua")
LoadFile("Modules/ProfessionService_Login.lua")
LoadFile("Modules/ProfessionService_Queries.lua")

local charData = { name = "Seamstress", professionData = { bySkillLine = {} } }
WarbandNexus.db.global.characters["Player-01"] = charData

local function orders() return charData.craftingOrders and charData.craftingOrders[SKILL_LINE] end
local function openWindow()
    WarbandNexus:OnTradeSkillShow()
    stub.Advance(5)
end

print("Phase 1: Personal order count is read from GetPersonalOrdersInfo for the open profession")
do
    openWindow()
    assert_eq(orders() and orders().personalCount, 3, "personalCount = Tailoring entry's numPersonalOrders")
    assert_eq(orders() and orders().guildCount, 0, "guildCount 0 before any order-count event")
end

print("Phase 2: Guild order count comes from CRAFTINGORDERS_UPDATE_ORDER_COUNT and survives a rescan")
do
    local src = assert(io.open(ROOT .. "/Modules/EventManager.lua", "rb")):read("*a")
    assert_eq(src:find('"CRAFTINGORDERS_UPDATE_ORDER_COUNT"', 1, true) ~= nil, true, "EventManager registers the event")

    local handler = WarbandNexus.OnCraftingOrdersOrderCount
    assert_eq(type(handler), "function", "ProfessionService exposes OnCraftingOrdersOrderCount")
    if handler then
        fired = {}
        WarbandNexus:OnCraftingOrdersOrderCount(Enum.CraftingOrderType.Guild, 4)
        assert_eq(orders() and orders().guildCount, 4, "guild tab count stored")
        local sawOrders = false
        for i = 1, #fired do if fired[i] == "WN_CRAFTING_ORDERS_UPDATED" then sawOrders = true end end
        assert_eq(sawOrders, true, "WN_CRAFTING_ORDERS_UPDATED emitted on change")

        WarbandNexus:OnCraftingOrdersOrderCount(Enum.CraftingOrderType.Public, 57)
        assert_eq(orders() and orders().guildCount, 4, "public tab count does not overwrite the guild count")
    end

    personalInfos[2].numPersonalOrders = 1
    WarbandNexus:OnTradeSkillClose()
    openWindow()
    assert_eq(orders() and orders().personalCount, 1, "personal count refreshed on reopen")
    assert_eq(orders() and orders().guildCount, 4, "guild count kept across a rescan")
end

print("Phase 3: An unread personal-order list keeps the stored count")
do
    C_CraftingOrders.GetPersonalOrdersInfo = function() error("orders not loaded") end
    WarbandNexus:OnTradeSkillClose()
    openWindow()
    assert_eq(orders() and orders().personalCount, 1, "failed read does not write 0")
    C_CraftingOrders.GetPersonalOrdersInfo = function() return personalInfos end
end

print("Phase 4: The logout flush does not re-read order counts during teardown")
do
    WarbandNexus:OnTradeSkillListUpdate()          -- list refresh still owed at logout
    C_CraftingOrders.GetPersonalOrdersInfo = function() return {} end
    WarbandNexus:FlushProfessionOnLogout()
    assert_eq(orders() and orders().personalCount, 1, "teardown read does not zero the personal count")
    assert_eq(orders() and orders().guildCount, 4, "guild count kept")
    C_CraftingOrders.GetPersonalOrdersInfo = function() return personalInfos end
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Crafting order count suite failed with " .. failed .. " failure(s).")
end
print("Crafting order count suite: ALL TESTS PASSED.")
