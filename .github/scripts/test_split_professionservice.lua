#!/usr/bin/env lua
--[[
    Warband Nexus - Unit Test: ProfessionService split (2026-10-22)

    ProfessionService.lua was 4415 lines with 121 top-level locals. Weekly knowledge, the login
    collectors and the read API moved verbatim into ProfessionService_WeeklyKnowledge.lua,
    ProfessionService_Login.lua and ProfessionService_Queries.lua; they share state through
    ns.ProfessionServiceShared (PS).

    Validates:
    1. Main file is under 4000 lines and under 120 top-level locals
    2. TOC lists each satellite after ProfessionService.lua (Login after WeeklyKnowledge) and before
       the first later file that uses its public names
    3. Each satellite binds PS and asserts it (mis-ordered TOC fails loudly at load)
    4. Loading main + satellites under wow_stub exposes every moved public function, the PS exports
       both sides need, and the main-file call sites that now read PS.* still run
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

local function ReadFile(rel)
    local fh = io.open(ROOT .. "/" .. rel, "rb")
    if not fh then return nil end
    local src = fh:read("*a")
    fh:close()
    return src
end

local MAIN = "Modules/ProfessionService.lua"
local SATELLITES = {
    "Modules/ProfessionService_WeeklyKnowledge.lua",
    "Modules/ProfessionService_Login.lua",
    "Modules/ProfessionService_Queries.lua",
}

-- Public names each satellite defines (WarbandNexus methods; ns.* noted separately).
local MOVED = {
    ["Modules/ProfessionService_WeeklyKnowledge.lua"] = {
        "HasWeeklyResetOccurredForTimestamp", "SanitizeWeeklyKnowledgeProgress", "GetCharacterWeeklyKnowledge",
    },
    ["Modules/ProfessionService_Login.lua"] = {
        "CollectConcentrationOnLogin", "CollectMidnightKnowledgeOnLogin", "CollectExpansionProfessionsOnLogin",
        "IsExpansionProfessionsPersistedWarm", "IsKnowledgePersistedWarm", "ShouldSkipKnowledgeLoginWarmup",
        "IsConcentrationPersistedWarm", "IsProfessionEquipmentPersistedWarm", "CollectKnowledgeOnLogin",
    },
    ["Modules/ProfessionService_Queries.lua"] = {
        "GetAllConcentrationData", "GetProjectedConcentration", "GetConcentrationExpiringAlerts",
        "GetConcentrationQueue", "GetRecipeCraftCountFromMaterials", "GetCraftersForRecipe",
        "GetProfessionConcentrationEntry", "GetEstimatedConcentration", "GetConcentrationTimeToFull",
        "GetConcentrationTimeToFullDetailed", "GetKnowledgeData", "GetAllKnowledgeDataForProfession",
        "PrintProfessionVerify", "GetRecipeMissingReagents", "FormatShoppingList",
    },
}

print("Phase 1: Main file size and local headroom")
do
    local src = ReadFile(MAIN) or ""
    local lines, locals = 0, 0
    if src ~= "" and src:sub(-1) ~= "\n" then src = src .. "\n" end
    for line in src:gmatch("([^\n]*)\n") do
        lines = lines + 1
        if line:find("^local%s") then locals = locals + 1 end
    end
    assert_true(lines < 4000, "ProfessionService.lua under 4000 lines (" .. lines .. ")")
    assert_true(locals < 120, "ProfessionService.lua under 120 top-level locals (" .. locals .. ")")
end

print("Phase 2: TOC order")
do
    local toc = ReadFile("WarbandNexus.toc") or ""
    local order, index = {}, {}
    for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r$", "")
        if line:find("%.lua$") and not line:find("^#") then
            local rel = line:gsub("\\", "/")
            order[#order + 1] = rel
            index[rel] = #order
        end
    end
    local mainAt = index[MAIN]
    assert_true(mainAt ~= nil, "TOC lists ProfessionService.lua")
    for i = 1, #SATELLITES do
        local sat = SATELLITES[i]
        local at = index[sat]
        assert_true(at ~= nil and mainAt ~= nil and at > mainAt, sat .. " listed after ProfessionService.lua")
        -- First later file (outside the ProfessionService group) that names one of this satellite's functions.
        local firstConsumer
        if mainAt then
            for j = mainAt + 1, #order do
                local rel = order[j]
                if not rel:find("^Modules/ProfessionService") then
                    local src = ReadFile(rel)
                    if src then
                        local names = MOVED[sat]
                        for n = 1, #names do
                            if src:find("%f[%w_]" .. names[n] .. "%f[^%w_]") then firstConsumer = j break end
                        end
                    end
                end
                if firstConsumer then break end
            end
        end
        assert_true(at ~= nil and (not firstConsumer or at < firstConsumer),
            sat .. " listed before its first consumer (" .. tostring(firstConsumer and order[firstConsumer]) .. ")")
    end
    local w, l = index[SATELLITES[1]], index[SATELLITES[2]]
    assert_true(w and l and w < l, "ProfessionService_Login.lua listed after ProfessionService_WeeklyKnowledge.lua")
end

print("Phase 3: Satellites bind and assert the shared table")
do
    for i = 1, #SATELLITES do
        local src = ReadFile(SATELLITES[i]) or ""
        assert_true(src:find("local PS = ns%.ProfessionServiceShared") ~= nil, SATELLITES[i] .. " binds ns.ProfessionServiceShared")
        assert_true(src:find("assert%(PS and PS%.") ~= nil, SATELLITES[i] .. " asserts PS at load")
    end
end

-- Stub environment (same shape as test_profession_weekly_knowledge.lua)
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")
table.wipe = _G.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local function NewNamespace()
    local ns = {}
    local addon = {}
    ns.WarbandNexus = addon
    addon.db = {
        profile = { themeMode = "dark", modulesEnabled = { professions = true } },
        global = { characters = {} },
        char = {},
    }
    addon.RegisterMessage = function() end
    addon.SendMessage = function() end
    addon.RegisterEvent = function() end
    addon.Print = function() end
    addon.Debug = function() end
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
    return ns, addon
end

local function LoadFile(rel, ns)
    local src = ReadFile(rel)
    if not src then return false, "missing file: " .. rel end
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then return false, err end
    return pcall(chunk, "WarbandNexus", ns)
end

print("Phase 4: Mis-ordered load fails at the satellite assert")
do
    local ns = NewNamespace()
    LoadFile("Locales/enUS.lua", ns)
    ns.L = ns.LOCALES and ns.LOCALES.enUS
    LoadFile("Modules/Constants.lua", ns)
    local ok, err = LoadFile(SATELLITES[2], ns)
    assert_eq(ok, false, "ProfessionService_Login.lua refuses to load before the main file")
    assert_true(tostring(err):find("check the TOC") ~= nil, "assert message names the TOC")
end

print("Phase 5: Moved functions reachable after a TOC-order load")
do
    local ns, addon = NewNamespace()
    LoadFile("Locales/enUS.lua", ns)
    ns.L = ns.LOCALES and ns.LOCALES.enUS
    LoadFile("Modules/Constants.lua", ns)
    local ok, err = LoadFile(MAIN, ns)
    assert_eq(ok, true, "ProfessionService.lua loads (" .. tostring(err) .. ")")
    for i = 1, #SATELLITES do
        ok, err = LoadFile(SATELLITES[i], ns)
        assert_eq(ok, true, SATELLITES[i] .. " loads (" .. tostring(err) .. ")")
    end
    for i = 1, #SATELLITES do
        local names = MOVED[SATELLITES[i]]
        for n = 1, #names do
            assert_eq(type(addon[names[n]]), "function", "WarbandNexus:" .. names[n] .. " defined")
        end
    end
    assert_eq(type(ns.GetCharacterWeeklyKnowledge), "function", "ns.GetCharacterWeeklyKnowledge defined")
    assert_eq(type(ns.SanitizeAllStoredScrappedRecipes), "function", "ns.SanitizeAllStoredScrappedRecipes still defined")
    assert_eq(ns.ProfessionService, addon, "ns.ProfessionService still the addon object")

    local PS = ns.ProfessionServiceShared or {}
    local fromMain = {
        "IsCurrentCharacterTracked", "ResolveTrackedCharactersTableKey", "CurrentSessionCanonicalCharacterKey",
        "SafeAPIString", "EnsureSkillLineBucket", "NotifyCollectorUpdate", "CollectKnowledgeForSkillLine",
        "CollectAllExpansionProfessions", "SanitizeAllStoredScrappedRecipes",
    }
    for n = 1, #fromMain do
        assert_eq(type(PS[fromMain[n]]), "function", "PS." .. fromMain[n] .. " exported by the main file")
    end
    assert_eq(type(PS.MIDNIGHT_SKILLLINE_TO_PARENT), "table", "PS.MIDNIGHT_SKILLLINE_TO_PARENT exported by the main file")
    local fromWeekly = {
        MIDNIGHT_WEEKLY_SOURCES = "table", MIDNIGHT_CATCHUP_CURRENCY = "table", catchUpCurrencyToSkillLine = "table",
        RECURRING_WEEKLY_PROGRESS_KEYS = "table", HasWeeklyResetOccurredForTimestamp = "function",
        CollectMidnightKnowledgeProgressForSkillLine = "function", RefreshAllMidnightKnowledgeProgressForCharacter = "function",
    }
    for name, kind in pairs(fromWeekly) do
        assert_eq(type(PS[name]), kind, "PS." .. name .. " exported by ProfessionService_WeeklyKnowledge.lua")
    end
    assert_true(PS.MIDNIGHT_WEEKLY_SOURCES and PS.MIDNIGHT_WEEKLY_SOURCES[2906] ~= nil, "weekly sources carry Midnight Alchemy (2906)")

    -- Main-file call sites that now read PS.* at call time.
    addon.db.global.characters["Player-01"] = { name = "Player", professions = {}, concentration = {} }
    ok, err = pcall(addon.OnProfessionQuestProgressChanged, addon, true)
    assert_eq(ok, true, "OnProfessionQuestProgressChanged runs through PS.RefreshAll... (" .. tostring(err) .. ")")
    ok, err = pcall(addon.RefreshCurrentCharacterKnowledgeProgress, addon, true)
    assert_eq(ok, true, "RefreshCurrentCharacterKnowledgeProgress runs (" .. tostring(err) .. ")")
    ok, err = pcall(addon.OnProfessionProgressCurrencyChanged, addon, 3189)
    assert_eq(ok, true, "OnProfessionProgressCurrencyChanged reads PS.MIDNIGHT_CATCHUP_CURRENCY (" .. tostring(err) .. ")")
    ok, err = pcall(stub.Advance, 1)
    assert_eq(ok, true, "currency refresh timer body runs (" .. tostring(err) .. ")")
    ok, err = pcall(addon.FlushProfessionOnLogout, addon)
    assert_eq(ok, true, "FlushProfessionOnLogout runs (" .. tostring(err) .. ")")
    local entry = { current = 100, max = 1000, lastUpdate = time() - 3600 }
    assert_eq(addon:GetEstimatedConcentration(entry), 110, "Queries satellite: estimated concentration after one hour")
end

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("ProfessionService split suite failed with " .. failed .. " failure(s).")
else
    print("ProfessionService split suite: ALL TESTS PASSED.")
end
