#!/usr/bin/env lua
--[[
    Regression test: GetProfessions' holes must not swallow a profession.

    The function returns five values and leaves gaps -- a character with one primary gets
    prof2 = nil. Classifying them with `ipairs{ r1, r2, r3, r4, r5 }` stops at the first gap, and
    that is exactly what happened: Mining in slot one came through, First Aid in slot three
    vanished, and the roster drew two icons instead of four.

    Loads the shipped Modules/DataService.lua under the WoW stub and drives CollectProfessionData
    with the real return shape measured on the live client.
]]

local passed, failed = 0, 0
local function eq(actual, expected, msg)
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
dofile(SCRIPT_DIR .. "/wow_stub.lua")

-- Measured on WoW Forever: three professions, two gaps, First Aid in the third slot.
-- Tab index -> name, skill line.
local TABS = {
    [5] = { "First Aid", 129 },
    [6] = { "Cooking", 185 },
    [7] = { "Mining", 186 },
}
local RETURNS = { 7, nil, 5, nil, 6 }   -- prof1, prof2, firstAid, fishing, cooking

function GetProfessions() return RETURNS[1], RETURNS[2], RETURNS[3], RETURNS[4], RETURNS[5] end
function GetProfessionInfo(index)
    local row = TABS[index]
    if not row then return nil end
    -- name, icon, rank, maxRank, numSpells, spellOffset, skillLine
    return row[1], 1, 10, 75, 1, 0, row[2]
end

local ns = {}
local supports = { firstAidProfession = true }
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
    SupportsFeature = function(_, key) return supports[key] ~= false end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end,
    SliceLabel = function() return "" end }
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return "Player-01" end,
    ResolveCharactersTableKey = function() return "Player-01" end,
}
ns.Utilities = {
    IsModuleEnabled = function() return true end,
    GetCharacterStorageKey = function() return "Player-01" end,
}

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/DataService.lua")

print("Phase 1: Forever classifies past the gaps, by skill line")
do
    local profs = WarbandNexus:CollectProfessionData()
    eq(type(profs), "table", "profession data collected")
    if type(profs) == "table" then
        eq(profs[1] and profs[1].name, "Mining", "the one primary lands in slot 1")
        eq(profs[2], nil, "no second primary is invented")
        eq(profs.firstAid and profs.firstAid.name, "First Aid", "First Aid survives the gap before it")
        eq(profs.cooking and profs.cooking.name, "Cooking", "Cooking survives two gaps")
        eq(profs.fishing, nil, "Fishing is absent because it is not learned")
    end
end

print("Phase 2: retail keeps the documented positional read")
do
    supports.firstAidProfession = false
    local profs = WarbandNexus:CollectProfessionData()
    eq(type(profs), "table", "profession data collected")
    if type(profs) == "table" then
        eq(profs[1] and profs[1].name, "Mining", "prof1 by position")
        eq(profs.cooking and profs.cooking.name, "Cooking", "cooking by position")
        -- Slot three is Archaeology on retail and deliberately dropped.
        eq(profs.firstAid, nil, "no First Aid where the client has none")
    end
    supports.firstAidProfession = true
end

print("Phase 3: a secondary is never promoted into a primary slot")
do
    -- HealCharacterProfessions fills an empty primary slot from whatever the row mentions, and
    -- its skip list was written for retail: Cooking, Fishing, Archaeology. First Aid is not on it
    -- because retail has none -- so on WoW Forever the heal found "First Aid" in
    -- professionExpansions and put it in slot 2, where the roster drew it as a second primary.
    local charData = {
        professions = {
            [1] = { name = "Mining", skillLine = 186 },
            firstAid = { name = "First Aid", skillLine = 129 },
            cooking = { name = "Cooking", skillLine = 185 },
        },
        professionExpansions = {
            ["Mining"] = {}, ["First Aid"] = {}, ["Cooking"] = {},
        },
    }
    WarbandNexus:HealCharacterProfessions(charData)
    eq(charData.professions[2], nil, "First Aid is not promoted to the second primary")
    eq(charData.professions.firstAid and charData.professions.firstAid.name, "First Aid",
        "it stays in its own slot")
    eq(charData.professions[1] and charData.professions[1].name, "Mining",
        "the real primary is untouched")
end

print("Phase 4: a slot the bug already filled is cleared out")
do
    local charData = {
        professions = {
            [1] = { name = "Mining", skillLine = 186 },
            [2] = { name = "First Aid", skillLine = 2942 },   -- what the heal wrote
            firstAid = { name = "First Aid", skillLine = 129 },
        },
        professionExpansions = { ["Mining"] = {}, ["First Aid"] = {} },
    }
    WarbandNexus:HealCharacterProfessions(charData)
    eq(charData.professions[2], nil, "the promoted copy is removed")
    eq(charData.professions.firstAid and charData.professions.firstAid.skillLine, 129,
        "the real entry keeps its own skill line")
end


print(string.format("\nTotal: %d checks, %d failed", passed + failed, failed))
if failed > 0 then
    error("Profession slot suite failed with " .. failed .. " failure(s).", 0)
end
print("test_profession_slots: all checks passed")
