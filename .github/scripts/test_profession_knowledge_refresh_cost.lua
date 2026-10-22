#!/usr/bin/env lua
--[[
    Regression test: the weekly-knowledge refresh reads only what can still change (2026-10-22).

    RefreshAllMidnightKnowledgeProgressForCharacter runs on QUEST_LOG_UPDATE / bag / trait-currency
    bursts (at most every 3 s). It treated any stored trace of a skill line (bucket, recipes,
    concentration, legacy mirror) as "owned", so a dropped profession's ~20 quest flags were read
    every time, and each unowned line called GetProfessions() again. Now only the stored profession
    list + live primaries count, GetProfessions() runs once per refresh, and a counter already at its
    cap (uniques ever, recurring ones inside the week) is not re-read: the no-drop clamp would keep it
    there anyway, so the stored progress is identical.

    Loads the shipped ProfessionService*.lua files under wow_stub.lua; quest reads are counted through
    C_QuestLog.IsQuestFlaggedCompleted.
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

local ns = {}
local WarbandNexus = {}
ns.WarbandNexus = WarbandNexus
WarbandNexus.db = {
    profile = { themeMode = "dark", modulesEnabled = { professions = true } },
    global = { characters = {} },
    char = {},
}
WarbandNexus.RegisterMessage = function() end
WarbandNexus.SendMessage = function() end
WarbandNexus.RegisterEvent = function() end
WarbandNexus.Print = function() end
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

-- Counted quest reads, per quest ID.
local reads = {}
local function ReadsOf(list)
    local n = 0
    for i = 1, #list do n = n + (reads[list[i]] or 0) end
    return n
end
local flagged = C_QuestLog.IsQuestFlaggedCompleted
C_QuestLog.IsQuestFlaggedCompleted = function(qid)
    reads[qid] = (reads[qid] or 0) + 1
    return flagged(qid)
end
-- Live primaries: GetProfessionInfo 7th return = base skill line.
local livePrimaries = {}
local getProfessionsCalls = 0
_G.GetProfessions = function()
    getProfessionsCalls = getProfessionsCalls + 1
    return livePrimaries[1], livePrimaries[2]
end
_G.GetProfessionInfo = function(idx)
    return "Prof" .. idx, 1, 1, 1, 0, 0, idx
end

local ALCH_UNIQUES = { 89115, 89117, 89114, 89116, 89113, 89112, 89111, 89118, 93794 }
local ALCH_TREATISE = { 95127 }
local TAILOR_ALL = { 89078, 89079, 89080, 89081, 89082, 89083, 89084, 89085, 93201, 95137, 93696, 93542, 93543 }

-- Alchemy (171) owned; Tailoring dropped, but its old bucket / recipes / concentration remain.
local charData = {
    name = "Alt",
    professions = { [1] = { name = "Alchemy", skillLine = 171 } },
    professionData = { bySkillLine = {
        [2918] = { weeklyKnowledge = { uniques = { current = 1, total = 9 }, lastUpdate = time() } },
    } },
    recipes = { [2918] = { firstCraftDoneCount = 1, firstCraftTotalCount = 5 } },
    concentration = { [2918] = { current = 1, max = 1000 } },
    discoveredSkillLines = {},
}
WarbandNexus.db.global.characters["Player-01"] = charData
local Refresh = function() WarbandNexus:RefreshCurrentCharacterKnowledgeProgress(true) end

print("1. Only owned skill lines are read; GetProfessions once per refresh")
do
    reads, getProfessionsCalls = {}, 0
    Refresh()
    assert_eq(ReadsOf(TAILOR_ALL), 0, "dropped profession (stale bucket / recipes / concentration): no quest reads")
    assert_eq(ReadsOf(ALCH_UNIQUES) > 0, true, "owned profession (stored list): quests read")
    assert_eq(getProfessionsCalls <= 1, true, "GetProfessions() at most once per refresh (was once per unowned line)")
    local alch = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(alch and alch.uniques and alch.uniques.total, 9, "Alchemy progress collected")
    assert_eq(charData.professionData.bySkillLine[2918].weeklyKnowledge.uniques.current, 1, "dropped line's stored data untouched")

    livePrimaries[1] = 197                       -- Tailoring learned again (live primaries)
    reads = {}
    Refresh()
    assert_eq(ReadsOf(TAILOR_ALL) > 0, true, "live primary profession is refreshed without a stored entry")
    livePrimaries[1] = nil
end

print("2. A counter at its cap is not re-read, and the stored result is unchanged")
do
    for i = 1, #ALCH_UNIQUES do stub.SetQuestCompleted(ALCH_UNIQUES[i], true) end
    stub.SetQuestCompleted(ALCH_TREATISE[1], true)
    Refresh()
    local alch = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(alch.uniques.current, 9, "uniques 9 / 9")
    assert_eq(alch.treatise.current, 1, "treatise 1 / 1")
    reads = {}
    Refresh()
    assert_eq(ReadsOf(ALCH_UNIQUES), 0, "uniques at cap: not re-read")
    assert_eq(ReadsOf(ALCH_TREATISE), 0, "treatise at cap (same week): not re-read")
    alch = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(alch.uniques.current, 9, "uniques still 9 / 9")
    assert_eq(alch.treatise.current, 1, "treatise still 1 / 1")
end

print("3. The skip never hides a real change")
do
    -- Weekly reset since the stored value: the recurring counter is read again and drops.
    local wk = charData.professionData.bySkillLine[2906].weeklyKnowledge
    wk.lastUpdate = time() - 8 * 86400
    stub.SetQuestCompleted(ALCH_TREATISE[1], false)
    reads = {}
    Refresh()
    local alch = WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906)
    assert_eq(ReadsOf(ALCH_TREATISE) > 0, true, "after the weekly reset the treatise is read again")
    assert_eq(alch.treatise.current, 0, "treatise drops to 0 / 1 in the new week")
    assert_eq(alch.uniques.current, 9, "uniques keep 9 / 9 across the reset")
    -- A changed quest list (different total) is a new baseline: read again.
    alch.uniques = { current = 8, total = 8, source = "hardcoded_quest" }
    reads = {}
    Refresh()
    assert_eq(ReadsOf(ALCH_UNIQUES) > 0, true, "stored total differs from the quest list: uniques read again")
    assert_eq(WarbandNexus:GetCharacterWeeklyKnowledge(charData, 2906).uniques.total, 9, "uniques total follows the list")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profession knowledge refresh cost suite failed with " .. failed .. " failure(s).")
end
print("Profession knowledge refresh cost suite: ALL TESTS PASSED.")
