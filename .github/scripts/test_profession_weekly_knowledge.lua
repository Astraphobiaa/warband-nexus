#!/usr/bin/env lua
--[[
    Warband Nexus - Unit Test: Profession Weekly Knowledge & Treatise Matrix
    Target: Midnight 12.1.0 (## Interface: 120100)

    Validates:
    1. CharacterHasMidnightSkillLine correctly resolves for alts having only charData.professions
    2. Consuming an Inscription/Alchemy/Engineering treatise updates weekly knowledge to 1 / 1
    3. QUEST_LOG_UPDATE and TRAIT_TREE_CURRENCY_INFO_UPDATED event triggers refresh knowledge
    4. Logout flush persists weekly knowledge without delay
    5. PUI.GetSkillLineIDForFilter resolves Midnight skill lines with or without professionExpansions
    6. Recurring keys reset on weekly reset while one-time uniques persist
]]

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        print(string.format("  FAIL %s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, msg)
    assert_eq(not not cond, true, msg)
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."

-- Load stub environment
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")
table.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local ns = {}
local WarbandNexus = {}
ns.WarbandNexus = WarbandNexus

-- Mock AceDB
WarbandNexus.db = {
    profile = {
        themeMode = "dark",
        modulesEnabled = { professions = true },
    },
    global = {
        characters = {},
    },
    char = {},
}

local emittedMessages = {}
WarbandNexus.RegisterMessage = function(self, tbl, msg, handler) end
WarbandNexus.SendMessage = function(self, msg, ...)
    table.insert(emittedMessages, { msg = msg, args = { ... } })
end
WarbandNexus.RegisterEvent = function(...) end
WarbandNexus.Print = function(...) end
WarbandNexus.Debug = function(...) end

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
LoadFile("Modules/UI/ProfessionsUI.lua")

print("Phase 1: Alt Character Profession Recognition Without Open Window")
do
    local charKey = "Player-01"
    local charData = {
        name = "AltHero",
        professions = {
            [1] = { name = "Alchemy", skillLine = 171, rank = 100, maxRank = 100 },
            [2] = { name = "Inscription", skillLine = 773, rank = 100, maxRank = 100 },
        },
        professionData = { bySkillLine = {} },
        discoveredSkillLines = {},
    }
    WarbandNexus.db.global.characters[charKey] = charData

    -- Refresh knowledge progress
    local refreshed = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(refreshed, nil, "initial knowledge is unpopulated before scan")

    -- Call refresh
    WarbandNexus:RefreshCurrentCharacterKnowledgeProgress()

    local alchKnowledge = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_true(type(alchKnowledge) == "table", "Alchemy 2906 knowledge bucket initialized")
    assert_eq(alchKnowledge.treatise and alchKnowledge.treatise.total, 1, "Alchemy treatise total is 1")
    assert_eq(alchKnowledge.treatise and alchKnowledge.treatise.current, 0, "Alchemy treatise initially 0")

    local inscKnowledge = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2913)
    assert_true(type(inscKnowledge) == "table", "Inscription 2913 knowledge bucket initialized")
    assert_eq(inscKnowledge.treatise and inscKnowledge.treatise.total, 1, "Inscription treatise total is 1")
    assert_eq(inscKnowledge.treatise and inscKnowledge.treatise.current, 0, "Inscription treatise initially 0")

    -- Tailoring (2918) should NOT be initialized for this character
    local tailKnowledge = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2918)
    assert_eq(tailKnowledge, nil, "Tailoring 2918 not initialized for non-tailor")
end

print("Phase 2: Consuming a Treatise (Tratado) Updates to 1 / 1")
do
    local charKey = "Player-01"
    local charData = WarbandNexus.db.global.characters[charKey]

    -- Simulate using Thalassian Treatise on Inscription (Quest 95131)
    if stub.SetQuestCompleted then
        stub.SetQuestCompleted(95131, true)
    else
        _G.C_QuestLog.completedQuests[95131] = true
    end

    -- Trigger progress change immediately
    WarbandNexus:OnProfessionQuestProgressChanged(true)

    local inscKnowledge = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2913)
    assert_eq(inscKnowledge.treatise.current, 1, "Inscription treatise updated to 1 / 1 after use")
    assert_eq(inscKnowledge.treatise.total, 1, "Inscription treatise total remains 1")

    -- Alchemy treatise was NOT used, must stay 0 / 1
    local alchKnowledge = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(alchKnowledge.treatise.current, 0, "Alchemy treatise unaffected (stays 0 / 1)")

    -- Check message emission
    assert_true(#emittedMessages > 0, "E.PROFESSION_DATA_UPDATED emitted on treatise completion")
end

print("Phase 3: Logout Flush Persists In-Flight Treatise Completion")
do
    local charKey = "Player-01"
    local charData = WarbandNexus.db.global.characters[charKey]

    -- Now use Alchemy treatise (Quest 95127) right before logout
    if stub.SetQuestCompleted then
        stub.SetQuestCompleted(95127, true)
    else
        _G.C_QuestLog.completedQuests[95127] = true
    end

    -- Call FlushProfessionOnLogout directly
    WarbandNexus:FlushProfessionOnLogout()

    local alchKnowledge = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(alchKnowledge.treatise.current, 1, "Alchemy treatise saved synchronously on logout flush (1 / 1)")
end

print("Phase 4: ProfessionsUI SkillLine Resolution with Missing Expansions")
do
    local PUI = ns.ProfessionsUI
    local char = {
        professions = {
            [1] = { name = "Alchemy", skillLine = 171 },
            [2] = { name = "Inscription", skillLine = 773 },
        },
        professionExpansions = nil, -- empty / unpopulated expansions
    }

    local alchSlID = PUI.GetSkillLineIDForFilter(char, "Alchemy")
    assert_eq(alchSlID, 2906, "PUI resolves Alchemy to Midnight 2906 via base skillLine fallback")

    local inscSlID = PUI.GetSkillLineIDForFilter(char, "Inscription")
    assert_eq(inscSlID, 2913, "PUI resolves Inscription to Midnight 2913 via base skillLine fallback")
end

print("Phase 5: Weekly Reset Sanitization")
do
    local charKey = "Player-01"
    local charData = WarbandNexus.db.global.characters[charKey]

    -- Artificially age the lastUpdate timestamp beyond 7 days
    local wk = charData.professionWeeklyKnowledge[2913]
    wk.lastUpdate = time() - (8 * 86400)
    wk.uniques = { current = 4, total = 8, source = "hardcoded_quest" }

    local sanitized = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2913)
    assert_eq(sanitized.treatise.current, 0, "Treatise (recurring) reset to 0 after weekly reset")
    assert_eq(sanitized.uniques.current, 4, "Uniques (one-time) preserved across weekly reset")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profession weekly knowledge suite failed with " .. failed .. " failure(s).")
else
    print("Profession weekly knowledge suite: ALL TESTS PASSED.")
end
