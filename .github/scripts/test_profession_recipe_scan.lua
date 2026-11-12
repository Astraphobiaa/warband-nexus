#!/usr/bin/env lua
--[[
    Regression test: the profession recipe scan actually writes to the character row.

    Recipes are only readable while a trade skill window is open, which makes the path easy to get
    wrong and impossible to notice -- the first build stored nothing and the window it feeds simply
    did nothing when clicked, with no error. This loads the shipped
    Modules/CharacterSystemsService.lua under the WoW stub, hands it the exact shape the live
    client returned (GetBaseProfessionInfo -> professionID 186 / Mining / 23 of 75, GetRecipeInfo
    with a `learned` flag), and checks what lands on the row.
]]

local passed, failed = 0, 0
local function check(cond, msg)
    if cond then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print("  FAIL " .. msg)
    end
end
local function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s",
        msg, tostring(expected), tostring(actual)))
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
dofile(SCRIPT_DIR .. "/wow_stub.lua")

-- The live client's shape, verbatim from /wn charprobe.
local RECIPES = {
    [1] = { name = "Smelt Copper", icon = 100, learned = true },
    [2] = { name = "Smelt Tin", icon = 101, learned = false },
    [3] = { name = "Smelt Silver", icon = 102, learned = false },
}
local windowOpen = true
C_TradeSkillUI = {
    GetBaseProfessionInfo = function()
        if not windowOpen then return {} end
        return {
            professionID = 186, professionName = "Mining",
            skillLevel = 23, maxSkillLevel = 75, isPrimaryProfession = true,
        }
    end,
    GetAllRecipeIDs = function()
        if not windowOpen then return {} end
        return { 1, 2, 3 }
    end,
    GetRecipeInfo = function(id) return RECIPES[id] end,
}

local messages = {}
local ns = {}
local WarbandNexus = {
    db = { global = { characters = { ["Player-01"] = { name = "Tester" } } } },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    SupportsFeature = function(_, key) return key ~= "nothing" end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.Constants = { EVENTS = { CHARACTER_SYSTEMS_UPDATED = "WN_CHARACTER_SYSTEMS_UPDATED" } }
ns.Utilities = { GetCharacterStorageKey = function() return "Player-01" end }

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/CharacterSystemsService.lua")

print("Phase 1: a scan with the window open lands on the character row")
do
    check(type(WarbandNexus.ScanProfessionRecipes) == "function", "ScanProfessionRecipes exported")
    local entry = WarbandNexus:ScanProfessionRecipes()
    check(entry ~= nil, "scan returned an entry")
    local row = WarbandNexus.db.global.characters["Player-01"]
    check(row.systems ~= nil, "systems table created on the row")
    local stored = row.systems and row.systems.recipes and row.systems.recipes[186]
    check(stored ~= nil, "stored under the profession id the client reported")
    if stored then
        eq(stored.name, "Mining", "profession name kept")
        eq(stored.skillLevel, 23, "skill level kept")
        eq(stored.maxSkillLevel, 75, "skill cap kept")
        eq(#stored.recipes, 3, "every recipe stored")
        eq(stored.known, 1, "learned recipes counted")
        -- Known first: the window draws them as its first section.
        eq(stored.recipes[1].learned, true, "known recipes sort first")
        eq(stored.recipes[1].name, "Smelt Copper", "known recipe is the learned one")
    end
    eq(#messages, 1, "one update message sent")
    eq(messages[1] and messages[1].msg, "WN_CHARACTER_SYSTEMS_UPDATED", "message name")
end

print("Phase 2: the reader finds it back")
do
    local entry = WarbandNexus:GetProfessionRecipes("Player-01", 186)
    check(entry ~= nil, "GetProfessionRecipes returns the stored entry")
    eq(WarbandNexus:GetProfessionRecipes("Player-01", 999), nil, "unknown profession id answers nil")
end

print("Phase 3: a closed window changes nothing")
do
    windowOpen = false
    local before = WarbandNexus.db.global.characters["Player-01"].systems.recipes[186]
    local entry = WarbandNexus:ScanProfessionRecipes()
    eq(entry, nil, "scan declines when the window is shut")
    eq(WarbandNexus.db.global.characters["Player-01"].systems.recipes[186], before,
        "the stored entry is left alone")
end

print("Phase 4: an empty scan never erases what was already stored")
do
    -- The API goes quiet while the character is dead, and the spellbook and trait tables are not
    -- populated the instant a reload finishes. ScanCharacterSystems used to assign a fresh table,
    -- so those moments wiped the talents, the spellbook AND the recipe cache that costs a trip to
    -- every profession window to rebuild.
    local row = WarbandNexus.db.global.characters["Player-01"]
    row.systems.talents = { tabs = { { index = 1, spent = 5 } } }
    row.systems.spells = { known = 24, lines = {} }
    local recipesBefore = row.systems.recipes
    assert(recipesBefore, "precondition: recipes were stored by the earlier phases")

    -- Both halves answer nothing, the way they do while dead.
    C_SpellBook = nil
    C_Traits = nil
    C_ClassTalents = nil

    WarbandNexus:ScanCharacterSystems()
    local after = row.systems
    check(after ~= nil, "systems table survives the empty scan")
    check(after.talents ~= nil, "talents are kept when the tree reads empty")
    eq(after.talents and after.talents.tabs and after.talents.tabs[1].spent, 5,
        "the kept talents are the previous ones")
    check(after.spells ~= nil, "spellbook is kept when it reads empty")
    eq(after.recipes, recipesBefore, "the recipe cache is carried over, not dropped")
    eq(after.recipes and after.recipes[186] and after.recipes[186].name, "Mining",
        "the carried recipes are still readable")
end


print("Phase 5: a window that is not ready yet is not stored")
do
    -- While the frame is coming up GetBaseProfessionInfo answers professionID 0 with no name,
    -- and GetAllRecipeIDs still holds whatever was loaded last. `not base.professionID` let that
    -- through, because 0 is true in Lua: the row gained a nameless recipes[0] carrying another
    -- profession's list, and the profession actually being opened never got an entry.
    C_TradeSkillUI = {
        GetBaseProfessionInfo = function()
            return { professionID = 0, professionName = "", skillLevel = 0, maxSkillLevel = 0 }
        end,
        GetAllRecipeIDs = function() return { 1, 2, 3 } end,
        GetRecipeInfo = function(id) return RECIPES[id] end,
    }
    local row = WarbandNexus.db.global.characters["Player-01"]
    row.systems.recipes = row.systems.recipes or {}
    row.systems.recipes[0] = { professionID = 0, recipes = { 1, 2 } }   -- what the bug left behind

    local entry = WarbandNexus:ScanProfessionRecipes()
    eq(entry, nil, "a zero profession id is refused")

    -- And a later good scan sweeps the bad row out.
    C_TradeSkillUI.GetBaseProfessionInfo = function()
        return { professionID = 129, professionName = "First Aid", skillLevel = 7, maxSkillLevel = 75 }
    end
    local good = WarbandNexus:ScanProfessionRecipes()
    check(good ~= nil, "the ready window is stored")
    eq(row.systems.recipes[0], nil, "the nameless row is swept out")
    eq(row.systems.recipes[129] and row.systems.recipes[129].name, "First Aid",
        "stored under the profession that was open")
    check(row.systems.recipes[186] ~= nil, "the other profession is left alone")
end


print(string.format("\nTotal: %d checks, %d failed", passed + failed, failed))
if failed > 0 then
    error("Profession recipe scan suite failed with " .. failed .. " failure(s).", 0)
end
print("test_profession_recipe_scan: all checks passed")
