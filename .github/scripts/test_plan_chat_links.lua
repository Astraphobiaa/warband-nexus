#!/usr/bin/env lua
--[[
    Regression test: plan cards must produce chat links through APIs that exist in 12.1.5.

    GetPlanChatLink used C_Item.GetItemLinkByID (toy / recipe / illusion) and C_PetJournal.GetPetLink
    (pet). Neither exists (Blizzard_APIDocumentationGenerated 70448, Ketho GlobalAPI dump), so the
    "link" button always printed "not available". InsertPlanChatLink then inserted through
    ChatEdit_InsertLink / ChatFrame_OpenChat, which only exist when the loadDeprecationFallbacks
    CVar is on (Blizzard_DeprecatedChatInfo).

    Now: toys use C_ToyBox.GetToyLink, other items C_Item.GetItemInfo's 2nd return (requesting the
    item when it is not cached), pets C_PetJournal.GetBattlePetLink on an owned pet's GUID (there is
    no species-level link API, so an unowned species stays unlinkable), and insertion goes through
    ChatFrameUtil.InsertLink / ChatFrameUtil.OpenChat. Also checks MailDetailsPopup's tooltip link.

    Signatures not in the generated docs (GetToyLink, FindPetIDByName, GetBattlePetLink,
    GetPetInfoBySpeciesID) come from Ketho vscode-wow-api Data/Wiki.lua; warcraft.wiki.gg was
    unreachable (403) on 2026-10-22.

    Loads the shipped PlansManager.lua under wow_stub.lua. IDs are illustrative.
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

local TOY_ID, RECIPE_ID, ILLUSION_ITEM, UNCACHED_ID = 1973, 191500, 138787, 999001
local OWNED_SPECIES, UNOWNED_SPECIES = 39, 4242
local function itemLink(id) return "|cffffffff|Hitem:" .. id .. "::::::::::::::::|h[Item" .. id .. "]|h|r" end
local requested = {}

C_Item.GetItemIconByID = function() return 134400 end
C_Item.GetItemInfo = function(id)
    if id == UNCACHED_ID then return end
    return "Item" .. id, itemLink(id)
end
C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
C_ToyBox = {
    GetToyInfo = function() return nil end,
    GetToyLink = function(id) return id == TOY_ID and ("|cff0070dd|Hitem:" .. id .. "::::::::::::::::|h[Orb of Deception]|h|r") or nil end,
}
C_PetJournal = {
    GetPetInfoBySpeciesID = function(sid)
        if sid == OWNED_SPECIES then return "Mechanical Squirrel" end
        if sid == UNOWNED_SPECIES then return "Unowned Critter" end
    end,
    FindPetIDByName = function(name)
        if name == "Mechanical Squirrel" then return OWNED_SPECIES, "BattlePet-0-000000000001" end
        return nil
    end,
    GetBattlePetLink = function(guid) return "|cff0070dd|Hbattlepet:39:1:3:150:10:10:" .. guid .. "|h[Mechanical Squirrel]|h|r" end,
}
local inserted, opened = {}, {}
ChatFrameUtil = {
    InsertLink = function(text) inserted[#inserted + 1] = text; return false end,   -- no edit box open
    OpenChat = function(text) opened[#opened + 1] = text end,
}

local ns = {}
local WarbandNexus = {
    db = { global = { plans = {}, characters = {} }, profile = {}, char = {} },
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

LoadFile("Locales/enUS.lua")
ns.L = ns.LOCALES and ns.LOCALES.enUS
LoadFile("Modules/Constants.lua")
LoadFile("Modules/PlansManager.lua")

print("Phase 1: Toy, recipe and illusion plans link through existing APIs")
do
    local toy = WarbandNexus:GetPlanChatLink({ type = "toy", itemID = TOY_ID })
    assert_eq(toy and toy:find("[Orb of Deception]", 1, true) ~= nil, true, "toy link from C_ToyBox.GetToyLink")
    assert_eq(WarbandNexus:GetPlanChatLink({ type = "recipe", itemID = RECIPE_ID }), itemLink(RECIPE_ID),
        "recipe link = GetItemInfo 2nd return")
    assert_eq(WarbandNexus:GetPlanChatLink({ type = "illusion", itemID = ILLUSION_ITEM }), itemLink(ILLUSION_ITEM),
        "illusion link = GetItemInfo 2nd return")
    assert_eq(WarbandNexus:GetPlanChatLink({ type = "recipe", itemID = UNCACHED_ID }), nil, "uncached item: no link yet")
    assert_eq(requested[UNCACHED_ID], true, "uncached item data requested")
end

print("Phase 2: Pet plans link only through an owned pet")
do
    local pet = WarbandNexus:GetPlanChatLink({ type = "pet", speciesID = OWNED_SPECIES })
    assert_eq(pet and pet:find("battlepet:", 1, true) ~= nil, true, "owned species links via GetBattlePetLink")
    assert_eq(WarbandNexus:GetPlanChatLink({ type = "pet", speciesID = UNOWNED_SPECIES }), nil, "unowned species has no link")
end

print("Phase 3: Insertion goes through ChatFrameUtil")
do
    WarbandNexus:InsertPlanChatLink({ type = "recipe", itemID = RECIPE_ID })
    assert_eq(inserted[1], itemLink(RECIPE_ID), "ChatFrameUtil.InsertLink tried first")
    assert_eq(opened[1], itemLink(RECIPE_ID), "ChatFrameUtil.OpenChat when no edit box took it")
    ChatFrameUtil.InsertLink = function(text) inserted[#inserted + 1] = text; return true end
    opened = {}
    WarbandNexus:InsertPlanChatLink({ type = "toy", itemID = TOY_ID })
    assert_eq(#opened, 0, "no OpenChat once the link was inserted")
end

print("Phase 4: Mail details tooltip no longer depends on C_Item.GetItemLinkByID")
do
    local fh = assert(io.open(ROOT .. "/Modules/UI/MailDetailsPopup.lua", "rb"))
    local src = fh:read("*a")
    fh:close()
    assert_eq(src:find("pcall(C_Item.GetItemLinkByID", 1, true) == nil, true, "no call to the missing GetItemLinkByID")
    assert_eq(src:find("local ok, _, resolved = pcall(C_Item.GetItemInfo, itemID)", 1, true) ~= nil, true,
        "MailDetailsPopup resolves the link from GetItemInfo's 2nd return")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Plan chat link suite failed with " .. failed .. " failure(s).")
end
print("Plan chat link suite: ALL TESTS PASSED.")
