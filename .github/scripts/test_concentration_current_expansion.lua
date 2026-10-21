#!/usr/bin/env lua
--[[
    Regression test: the Characters row must show the current expansion's concentration.

    ProfessionService also stored each concentration entry under the profession NAME, but only
    when that key was missing, so charData.concentration["Tailoring"] stayed tied to the first
    expansion ever recorded. CharactersUI_Row read exactly that key, so after Midnight launched the
    tooltip kept showing the old expansion's concentration. After a reload the name row is also a
    separate table, and live CURRENCY_DISPLAY_UPDATE refreshes could land on it instead of the
    skillLineID row.

    Now: resolve the highest skillLineID entry for the profession (GetProfessionConcentrationEntry,
    used by the Characters row), stop writing name keys, and route live updates to skillLineID rows.

    Loads the shipped ProfessionService.lua under wow_stub.lua. 2918 is Midnight Tailoring
    (MIDNIGHT_MOXIE_CURRENCY in ProfessionsUI.lua); 2883 and the currency IDs are illustrative.
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

local MIDNIGHT_TAILORING = 2918
local OLD_TAILORING = 2883
local MIDNIGHT_CONC_CURRENCY = 9001
local OLD_CONC_CURRENCY = 9000
local live = { [MIDNIGHT_CONC_CURRENCY] = { quantity = 200, maxQuantity = 1000 } }
C_CurrencyInfo = { GetCurrencyInfo = function(id) return live[id] end }
C_TradeSkillUI = {
    GetConcentrationCurrencyID = function(sl)
        if sl == MIDNIGHT_TAILORING then return MIDNIGHT_CONC_CURRENCY end
        return 0
    end,
    GetProfessionInfoBySkillLineID = function() return nil end,
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

local function entry(sl, cid, cur, max)
    return { current = cur, max = max, currencyID = cid, skillLineID = sl, professionName = "Tailoring", lastUpdate = os.time() }
end

print("Phase 1: Characters row resolves the Midnight entry, not the pinned name key")
do
    local char = { concentration = {
        Tailoring = entry(OLD_TAILORING, OLD_CONC_CURRENCY, 100, 1000),   -- legacy, pinned to the old expansion
        [OLD_TAILORING] = entry(OLD_TAILORING, OLD_CONC_CURRENCY, 100, 1000),
        [MIDNIGHT_TAILORING] = entry(MIDNIGHT_TAILORING, MIDNIGHT_CONC_CURRENCY, 500, 1000),
    } }
    local got = WarbandNexus.GetProfessionConcentrationEntry
        and WarbandNexus:GetProfessionConcentrationEntry(char, "Tailoring")
    assert_eq(got and got.skillLineID, MIDNIGHT_TAILORING, "current expansion skillLineID wins")

    local src = assert(io.open(ROOT .. "/Modules/UI/CharactersUI_Row.lua", "rb")):read("*a")
    assert_eq(src:find("concentration%[profName%]") == nil, true, "CharactersUI_Row no longer reads concentration[profName]")
    assert_eq(src:find("GetProfessionConcentrationEntry", 1, true) ~= nil, true, "CharactersUI_Row uses the resolver")

    local legacyOnly = { concentration = { Tailoring = entry(OLD_TAILORING, OLD_CONC_CURRENCY, 100, 1000) } }
    got = WarbandNexus.GetProfessionConcentrationEntry and WarbandNexus:GetProfessionConcentrationEntry(legacyOnly, "Tailoring")
    assert_eq(got and got.current, 100, "legacy name-only row still resolves")
end

print("Phase 2: Login discovery writes the skillLineID key only")
do
    local charData = {
        name = "Seamstress",
        discoveredSkillLines = { Tailoring = { MIDNIGHT_TAILORING } },
        concentration = {},
        professionData = { bySkillLine = {} },
    }
    WarbandNexus.db.global.characters["Player-01"] = charData
    WarbandNexus:CollectConcentrationOnLogin()
    assert_eq(charData.concentration[MIDNIGHT_TAILORING] and charData.concentration[MIDNIGHT_TAILORING].current, 200,
        "skillLineID entry written")
    assert_eq(charData.concentration.Tailoring, nil, "no profession-name key written")
end

print("Phase 3: Live currency update lands on the skillLineID row")
do
    local charData = WarbandNexus.db.global.characters["Player-01"]
    -- After a reload the legacy name row is its own table with the same currencyID.
    charData.concentration.Tailoring = entry(MIDNIGHT_TAILORING, MIDNIGHT_CONC_CURRENCY, 200, 1000)
    WarbandNexus:RebuildConcentrationCurrencyMap()
    stub.Advance(5)                                    -- past the collector's hook-skip window
    live[MIDNIGHT_CONC_CURRENCY] = { quantity = 750, maxQuantity = 1000 }
    WarbandNexus:OnConcentrationCurrencyChanged(MIDNIGHT_CONC_CURRENCY)
    assert_eq(charData.concentration[MIDNIGHT_TAILORING].current, 750, "skillLineID row refreshed")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Concentration current expansion suite failed with " .. failed .. " failure(s).")
end
print("Concentration current expansion suite: ALL TESTS PASSED.")
