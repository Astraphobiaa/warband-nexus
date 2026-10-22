#!/usr/bin/env lua
--[[
    Regression test: re-enabling Professions mid-session runs the login collectors.

    The login collectors (concentration, equipment, Midnight weekly knowledge, expansion professions,
    knowledge) return early while the module is off, and the Core.lua / tracking-confirm timers that
    call them run once per login. SetProfessionModuleEnabled(true) only restarted the recharge timer,
    and ProfessionService had no WN_MODULE_TOGGLED listener, so a character whose module was off at
    login kept empty profession data until the next /reload. ProfessionService_Login.lua now listens
    for MODULE_TOGGLED("professions", true) and runs them once.

    Loads the shipped ProfessionService.lua and its satellites under wow_stub.lua (namespace shape of
    test_split_professionservice.lua) and fires the registered message handler.
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
local addon = {}
ns.WarbandNexus = addon
local modules = { professions = true }
local tracked = true
addon.db = {
    profile = { themeMode = "dark", modulesEnabled = modules },
    global = { characters = {} },
    char = {},
}
local toggleHandlers = {}
addon.RegisterMessage = function(_, msg, fn)
    toggleHandlers[msg] = toggleHandlers[msg] or {}
    local list = toggleHandlers[msg]
    list[#list + 1] = fn
end
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
    IsModuleEnabled = function(_, mod) return modules[mod] == true end,
}
ns.CharacterService = {
    IsCharacterTracked = function() return tracked end,
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

local E = ns.Constants.EVENTS
local COLLECTORS = {
    "CollectConcentrationOnLogin", "CollectEquipmentOnLogin", "CollectMidnightKnowledgeOnLogin",
    "CollectExpansionProfessionsOnLogin", "CollectKnowledgeOnLogin",
}
local calls = {}
for i = 1, #COLLECTORS do
    local name = COLLECTORS[i]
    assert_eq(type(addon[name]), "function", "WarbandNexus:" .. name .. " defined")
    addon[name] = function() calls[name] = (calls[name] or 0) + 1 end
end

local function Toggle(moduleName, enabled)
    for k in pairs(calls) do calls[k] = nil end
    local list = toggleHandlers[E.MODULE_TOGGLED] or {}
    for i = 1, #list do list[i](E.MODULE_TOGGLED, moduleName, enabled) end
    stub.Advance(2)
end

local function CountRan()
    local n = 0
    for i = 1, #COLLECTORS do
        if calls[COLLECTORS[i]] == 1 then n = n + 1 end
    end
    return n
end

print("Phase 1: Re-enabling Professions runs every login collector once")
do
    assert_eq(toggleHandlers[E.MODULE_TOGGLED] ~= nil, true, "a WN_MODULE_TOGGLED listener is registered")
    modules.professions = true
    Toggle("professions", true)
    for i = 1, #COLLECTORS do
        assert_eq(calls[COLLECTORS[i]], 1, COLLECTORS[i] .. " ran once")
    end
end

print("Phase 2: Other toggles and gates run nothing")
do
    Toggle("professions", false)
    assert_eq(CountRan(), 0, "disabling Professions runs no collector")
    Toggle("gear", true)
    assert_eq(CountRan(), 0, "another module's toggle runs no collector")
    modules.professions = false
    Toggle("professions", true)
    assert_eq(CountRan(), 0, "module flipped off again before the deferred run: nothing collected")
    modules.professions = true
    tracked = false
    Toggle("professions", true)
    assert_eq(CountRan(), 0, "untracked character: nothing collected")
    tracked = true
end

print("Phase 3: One failing collector does not stop the rest")
do
    local realConc = addon.CollectConcentrationOnLogin
    addon.CollectConcentrationOnLogin = function() error("concentration API not ready") end
    Toggle("professions", true)
    assert_eq(CountRan(), 4, "the four other collectors still ran")
    addon.CollectConcentrationOnLogin = realConc
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers"
    .. (stub.errors[1] and (" (" .. stub.errors[1] .. ")") or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Profession re-enable collectors suite failed with " .. failed .. " failure(s).")
end
print("Profession re-enable collectors suite: ALL TESTS PASSED.")
