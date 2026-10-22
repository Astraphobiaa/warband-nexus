#!/usr/bin/env lua
--[[
    Regression test: an uncached reagent name asks the client to load the item.

    GetRecipeMissingReagents (ProfessionService_Queries) and the Recipe Companion's FetchReagentData fell
    back to "Item <id>" when C_Item.GetItemNameByID / GetItemInfo had no name yet, and never asked for the
    item, so the label stayed "Item <id>" on every later rebuild until something else loaded the item.
    Since 2026-10-22 the fallback also calls C_Item.RequestLoadItemDataByID, so the next build has the name.

    Loads the shipped ProfessionService files under wow_stub.lua; FetchReagentData is a local of
    Modules/UI/RecipeCompanionWindow.lua and is extracted with loadstring.
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

local REAGENT, RECIPE = 424242, 5150
local names, requests = {}, {}
C_Item.GetItemInfo = function(id) return names[id] end
C_Item.GetItemNameByID = function(id) return names[id] end
C_Item.RequestLoadItemDataByID = function(id) requests[id] = (requests[id] or 0) + 1 end
C_TradeSkillUI = {
    GetRecipeSchematic = function()
        return { reagentSlotSchematics = { { reagentType = 1, required = true, quantityRequired = 2,
            reagents = { { itemID = REAGENT } } } } }
    end,
    GetRecipeInfo = function() return { name = "Test Recipe" } end,
    IsTradeSkillReady = function() return false end,
}

local ns = {}
local WarbandNexus = {
    db = { profile = { modulesEnabled = { professions = true } }, global = { characters = {} }, char = {} },
    RegisterMessage = function() end,
    SendMessage = function() end,
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

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
local function LoadFile(rel)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
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
WarbandNexus.GetDetailedItemCountsFast = function() return nil end

print("Phase 1: missing-reagent list requests the uncached reagent")
do
    local res = WarbandNexus:GetRecipeMissingReagents(RECIPE, 1, false)
    local entry = res and res.missingReagents and res.missingReagents[1]
    assert_eq(entry and entry.name, "Item " .. REAGENT, "placeholder name while uncached")
    assert_eq((requests[REAGENT] or 0) > 0, true, "item load requested for the placeholder")
    names[REAGENT] = "Shimmering Thread"
    res = WarbandNexus:GetRecipeMissingReagents(RECIPE, 1, false)
    entry = res and res.missingReagents and res.missingReagents[1]
    assert_eq(entry and entry.name, "Shimmering Thread", "next query shows the loaded name")
end

print("Phase 2: Recipe Companion reagent data requests the uncached reagent")
do
    names[REAGENT], requests = nil, {}
    local body = ReadFile("Modules/UI/RecipeCompanionWindow.lua"):match("\nlocal function FetchReagentData%(recipeID%)(.-)\nend\n")
    assert_eq(body ~= nil, true, "FetchReagentData found")
    local fetch = assert(loadstring("local GetItemInfo, WarbandNexus = ...\nreturn function(recipeID)" .. (body or "") .. "\nend",
        "@FetchReagentData"))(C_Item.GetItemInfo, WarbandNexus)
    local data = fetch(RECIPE)
    local reagent = data and data[1] and data[1].reagents[1]
    assert_eq(reagent and reagent.name, "Item " .. REAGENT, "placeholder name while uncached")
    assert_eq((requests[REAGENT] or 0) > 0, true, "item load requested for the placeholder")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Reagent name load request suite failed with " .. failed .. " failure(s).")
end
print("Reagent name load request suite: ALL TESTS PASSED.")
