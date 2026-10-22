#!/usr/bin/env lua
--[[
    Regression test: debounce timers must hold a real handle.

    C_Timer.After returns nothing (warcraft.wiki.gg/wiki/API_C_Timer.After), so
    `handle = C_Timer.After(...)` stored nil: the "already scheduled" coalesce never coalesced,
    :Cancel() was a silent no-op, and DataService's PLAYER_LOGOUT flush never saw a pending
    zone change (it only flushes when zoneUpdateTimer is set), so the last zone was lost.

    Part 1 drives the shipped DataService.lua under wow_stub.lua (whose C_Timer.After also returns
    nothing). Part 2 checks that the other debounce sites keep using C_Timer.NewTimer.
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

local KEY = "Player-1-00000001"
local liveZone, liveSubZone = "Silvermoon City", "Court of the Sun"
GetZoneText = function() return liveZone end
GetSubZoneText = function() return liveSubZone end
IsResting = function() return false end
GetNormalizedRealmName = function() return "TestRealm" end
GetMoney = function() return 0 end
C_Item.GetDetailedItemLevelInfo = function() return nil end

local ns = {}
local handlers = {}
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function(_, ev, fn) handlers[ev] = fn end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return KEY end,
    ResolveCharactersTableKey = function() return KEY end,
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

LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
ns.Utilities.GetCharacterStorageKey = function() return KEY end
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")

local row = { name = "Tester", realm = "TestRealm", guid = KEY, isTracked = true, zoneName = "Eversong Woods" }
WarbandNexus.db.global.characters[KEY] = row
WarbandNexus:RegisterCharacterCacheEvents()

local function countZoneUpdates()
    local n = 0
    for i = 1, #messages do
        local p = messages[i].payload
        if messages[i].msg == "WN_CHARACTER_UPDATED" and type(p) == "table" and p.dataType == "zone" then n = n + 1 end
    end
    return n
end

print("Phase 1: Zone change pending at logout is flushed")
do
    liveZone = "Silvermoon City"
    handlers.ZONE_CHANGED_NEW_AREA("ZONE_CHANGED_NEW_AREA")
    stub.Advance(0.5)                                  -- logout inside the 2s debounce
    WarbandNexus:FlushDataServiceOnLogout()
    assert_eq(row.zoneName, "Silvermoon City", "logout flush persisted the pending zone")
    assert_eq(countZoneUpdates(), 1, "one zone write")
    stub.Advance(5)
    assert_eq(countZoneUpdates(), 1, "cancelled debounce does not write again later")
end

print("Phase 2: Zone event burst coalesces into one write")
do
    messages = {}
    for _ = 1, 4 do
        handlers.ZONE_CHANGED("ZONE_CHANGED")
        stub.Advance(0.2)
    end
    stub.Advance(5)
    assert_eq(countZoneUpdates(), 1, "four ZONE_CHANGED within 2s -> one write")
end

print("Phase 3: Flushed character save cancels its debounce timer")
do
    local saves = 0
    WarbandNexus.IsCharacterRowPersistedWarm = function() return false end
    WarbandNexus.SaveCurrentCharacterData = function() saves = saves + 1; return true end
    WarbandNexus:ScheduleDeferredCharacterSave(true)   -- timer A due in 0.75s
    stub.Advance(0.1)
    WarbandNexus:FlushDeferredCharacterSave()          -- post-combat / logout flush: save now
    assert_eq(saves, 1, "flush saved once")
    stub.Advance(0.4)
    WarbandNexus:ScheduleDeferredCharacterSave(true)   -- timer B due 0.75s from now
    stub.Advance(0.3)                                  -- past A's original deadline
    assert_eq(saves, 1, "cancelled timer A does not fire a save early")
    stub.Advance(1)
    assert_eq(saves, 2, "timer B saves once")
end

print("Phase 4: Other debounce sites keep a cancellable handle")
do
    local sites = {
        { "Modules/ItemsCacheService.lua", "deferredThrottleTimer" },
        { "Modules/PvECacheService.lua", "pvePendingUpdateTimer" },
        { "Modules/ProfessionService.lua", "professionWindowSyncTimer" },
        { "Modules/UI/RecipeCompanionWindow.lua", "companionRefreshTimer" },
        { "Modules/DataService.lua", "zoneUpdateTimer" },
        { "Modules/DataService.lua", "characterSaveDebounceTimer" },
    }
    for i = 1, #sites do
        local rel, handle = sites[i][1], sites[i][2]
        local src = ReadFile(rel):gsub("%-%-[^\n]*", "")
        local bad = src:find(handle .. "%s*=%s*C_Timer%.After%(")
        local good = src:find(handle .. "%s*=%s*C_Timer%.NewTimer%(")
        assert_eq(bad == nil and good ~= nil, true, rel .. ": " .. handle .. " = C_Timer.NewTimer(...)")
    end
end

print("Phase 5: No handle is stored from C_Timer.After anywhere in Modules/ (2026-10-22)")
do
    -- Found again in ProfessionsUI (scroll relayout debounce) and TryCounterService (lockout
    -- fallback). The only allowed capture is UI_MainShell's, which checks the type and falls back
    -- to a generation guard.
    local p = io.popen('find "' .. ROOT .. '/Modules" -name "*.lua" 2>/dev/null')
    local offenders = {}
    for path in p:lines() do
        local rel = path:gsub("^" .. ROOT:gsub("%p", "%%%0") .. "/", "")
        local src = ReadFile(rel):gsub("%-%-[^\n]*", "")
        local ln = 0
        for line in (src .. "\n"):gmatch("([^\n]*)\n") do
            ln = ln + 1
            if line:find("[%w_%]]%s*=%s*C_Timer%.After%(") and not line:find("local afterHandle = C_Timer.After(", 1, true) then
                offenders[#offenders + 1] = rel .. ":" .. ln
            end
        end
    end
    p:close()
    assert_eq(#offenders, 0, "no `x = C_Timer.After(...)` handle captures" .. (#offenders > 0 and (" (" .. table.concat(offenders, ", ") .. ")") or ""))
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Timer handle suite failed with " .. failed .. " failure(s).")
end
print("Timer handle suite: ALL TESTS PASSED.")
