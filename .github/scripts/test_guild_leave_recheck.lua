#!/usr/bin/env lua
--[[
    Regression test: a single "not in guild" read does not delete the guild-bank cache.

    SyncPlayerGuildMembership runs at PLAYER_ENTERING_WORLD. One IsInGuild() == false read was taken
    as "left the guild": the character's guildName was cleared and, with no other alt in that guild,
    the whole guild-bank cache was deleted. A leave is now confirmed by a second read 8s later.

    Loads the shipped Modules/GuildBankScanner.lua under wow_stub.lua.
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

local inGuild = true
IsInGuild = function() return inGuild end
GetGuildInfo = function() if inGuild then return "Night Watch" end end

local KEY = "Player-3674-0000000A"
local printed = {}
local ns = {}
local WarbandNexus = {
    db = { global = { characters = {}, guildBank = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function(_, msg) printed[#printed + 1] = msg end,
    InvalidateGuildBankScan = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
ns.Utilities = {
    GetCharacterStorageKey = function() return KEY end,
    GetCanonicalCharacterKey = function(_, k) return k end,
    SafeLower = function(_, s) return s and s:lower() end,
    IsModuleEnabled = function() return true end,
}
ns.CharacterService = {
    ResolveCharactersTableKey = function() return KEY end,
    IsCharacterTracked = function() return true end,
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

LoadFile("Modules/Constants.lua")
LoadFile("Modules/GuildBankScanner.lua")

local function setup()
    WarbandNexus.db.global.characters = { [KEY] = { name = "Alpha", realm = "Kazzak", guildName = "Night Watch" } }
    WarbandNexus.db.global.guildBank = { ["Night Watch"] = { tabs = { { items = { "x" } } } } }
end

print("Phase 1: A transient 'not in guild' read keeps the guild and its bank")
do
    setup()
    inGuild = false                        -- unready read at PLAYER_ENTERING_WORLD
    WarbandNexus:SyncPlayerGuildMembership()
    assert_eq(WarbandNexus.db.global.guildBank["Night Watch"] ~= nil, true, "guild bank kept right after the read")
    assert_eq(WarbandNexus.db.global.characters[KEY].guildName, "Night Watch", "guildName kept right after the read")
    inGuild = true                         -- guild data arrives
    stub.Advance(10)
    assert_eq(WarbandNexus.db.global.guildBank["Night Watch"] ~= nil, true, "guild bank kept after the recheck")
    assert_eq(WarbandNexus.db.global.characters[KEY].guildName, "Night Watch", "guildName kept after the recheck")
end

print("Phase 2: A real leave (still not in guild on recheck) is applied")
do
    setup()
    inGuild = false
    WarbandNexus:SyncPlayerGuildMembership()
    stub.Advance(10)
    assert_eq(WarbandNexus.db.global.characters[KEY].guildName, nil, "guildName cleared after a confirmed leave")
    assert_eq(WarbandNexus.db.global.guildBank["Night Watch"], nil, "orphaned guild bank removed after a confirmed leave")
    local told = false
    for i = 1, #printed do if printed[i]:find("no longer in a guild", 1, true) then told = true end end
    assert_eq(told, true, "player told about the confirmed leave")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Guild leave recheck suite failed with " .. failed .. " failure(s).")
end
print("Guild leave recheck suite: ALL TESTS PASSED.")
