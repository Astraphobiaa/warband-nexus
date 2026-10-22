#!/usr/bin/env lua
--[[
    Regression test: frequent game events no longer fan out into redundant WN_* messages / redraws.

    Part 1 drives the shipped DataService.lua under wow_stub.lua:
      - B4  every money change sent CHARACTER_UPDATED{gold} twice (UpdateCharacterGold, then a
            MONEY_UPDATED -> UpdateCharacterCache("gold") listener that rewrote the same values);
      - B8  every XP tick while leveling sent CHARACTER_UPDATED{rested} (currentXP was compared,
            though no UI shows it);
      - B12 UPDATE_PENDING_MAIL sent CHARACTER_UPDATED{mail} even when hasMail did not change.
    Part 2 pins routing decisions that need the whole UI / gear stack to drive (static):
      - A1/A2 a currency drain rebuilt the whole Gear tab and the Characters tab without cooldown;
      - B1  QUEST_LOG_UPDATE re-checked every plan once a second without any daily-quest plan;
      - B2  any single non-crest currency rescanned all 16 equipped slots;
      - B3  the vault badge re-swept the roster on gold / zone / rested / mail updates;
      - B11 TryCounter received UNIT_SPELLCAST_* for every raid / nameplate unit.
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
local xp, money, newMail = 1000, 50000, false
UnitName = function() return "Tester" end
GetNormalizedRealmName = function() return "TestRealm" end
UnitRace = function() return "Human", "Human" end
GetMoney = function() return money end
UnitXP = function() return xp end
UnitXPMax = function() return 100000 end
GetXPExhaustion = function() return 5000 end
GetRestState = function() return 1, "Rested", 2 end
IsResting = function() return false end
HasNewMail = function() return newMail end
GetZoneText = function() return "Silvermoon City" end
GetSubZoneText = function() return "" end

local ns = {}
local listeners, events = {}, {}
local sent = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload)
        sent[#sent + 1] = { msg = msg, payload = payload }
        local l = listeners[msg]
        if l then for i = 1, #l do l[i](msg, payload) end end
    end,
    RegisterMessage = function(_, msg, fn)
        listeners[msg] = listeners[msg] or {}
        listeners[msg][#listeners[msg] + 1] = fn
    end,
    RegisterEvent = function(_, ev, fn) events[ev] = fn end,
    RegisterBucketEvent = function() end,
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
    return (src:gsub("^\239\187\191", ""):gsub("\r\n", "\n"))
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
ns.Utilities.GetCanonicalCharacterKey = function(_, k) return k end
LoadFile("Modules/DataService_RosterHelpers.lua")
LoadFile("Modules/DataService.lua")
local E = ns.Constants.EVENTS
-- RegisterCharacterCacheEvents uses WarbandNexus.RegisterMessage(listenerTable, msg, fn).
WarbandNexus.RegisterMessage = function(_, msg, fn)
    listeners[msg] = listeners[msg] or {}
    listeners[msg][#listeners[msg] + 1] = fn
end
WarbandNexus:RegisterCharacterCacheEvents()

local function countCharUpdated(dataType)
    local n = 0
    for i = 1, #sent do
        local s = sent[i]
        if s.msg == E.CHARACTER_UPDATED and s.payload and s.payload.dataType == dataType then n = n + 1 end
    end
    return n
end

WarbandNexus.db.global.characters[KEY] = { name = "Tester", realm = "TestRealm", isTracked = true, raceFile = "Human" }

print("Phase 1 (B4): one money change sends CHARACTER_UPDATED{gold} once")
do
    sent = {}
    money = 60000
    WarbandNexus:UpdateCharacterGold()
    WarbandNexus:SendMessage(E.MONEY_UPDATED)      -- what EventManager sends right after
    assert_eq(countCharUpdated("gold"), 1, "single gold update message")
    assert_eq(WarbandNexus.db.global.characters[KEY].gold, 6, "gold written")
end

print("Phase 2 (B8): an XP tick that changes nothing shown sends no message")
do
    WarbandNexus:UpdateCharacterCache("rested")      -- seed the snapshot
    sent = {}
    xp = 1500
    WarbandNexus:UpdateCharacterCache("rested")
    assert_eq(countCharUpdated("rested"), 0, "no CHARACTER_UPDATED{rested} for an XP-only change")
    local r = WarbandNexus.db.global.characters[KEY].rested
    assert_eq(r and r.currentXP, 1500, "currentXP still stored")
end

print("Phase 3 (B12): a repeated mail notice with no change sends nothing")
do
    newMail = true
    WarbandNexus:UpdateMailStatus()
    sent = {}
    WarbandNexus:UpdateMailStatus()
    assert_eq(countCharUpdated("mail"), 0, "unchanged hasMail: no message")
    newMail = false
    WarbandNexus:UpdateMailStatus()
    assert_eq(countCharUpdated("mail"), 1, "hasMail flip still sends")
end

print("Phase 4: routing decisions (static)")
do
    local router = ReadFile("Modules/UI/UI_RefreshRouter.lua")
    local cur = router:match("EVENTS%.CURRENCY_UPDATED, function%(%)(.-)\n    end%)")
    assert_eq(cur ~= nil, true, "router CURRENCY_UPDATED handler found")
    local gear = cur and cur:match('currentTab == "gear" then(.-)elseif')
    assert_eq(gear and gear:find("TryRefreshGearUpgradeEconomy", 1, true) ~= nil, true,
        "A1: gear tab tries the narrow economy refresh first")
    local chars = cur and cur:match('currentTab == "chars" then(.-)elseif')
    assert_eq(chars and chars:find("SchedulePopulateContent%(%)") ~= nil and chars:find("SchedulePopulateContent%(true%)") == nil, true,
        "A2: characters tab keeps the populate cooldown")

    local dq = ReadFile("Modules/DailyQuestManager.lua")
    local body = dq:match("function WarbandNexus:OnDailyQuestUpdate%(%)(.-)\nend\n")
    local gateAt = body and body:find("if not dailyList or #dailyList == 0 then", 1, true)
    local sendAt = body and body:find('reason = "QUEST_LOG_UPDATE"', 1, true)
    assert_eq(gateAt ~= nil and sendAt ~= nil and gateAt < sendAt, true,
        "B1: QUEST_LOG_UPDATE sends plan checks only with a daily-quest plan")

    local gs = ReadFile("Modules/GearService.lua")
    local l = gs:match("EVENTS%.CURRENCY_UPDATED, function%(_, currencyID%)(.-)\nend%)")
    assert_eq(l and l:find("UPGRADE_CURRENCY_ID_SET_EARLY%[currencyID%]") ~= nil, true,
        "B2: a single non-crest currency skips the equipped-gear rescan")

    local vb = ReadFile("Modules/VaultButton.lua")
    local v = vb:match("E%.CHARACTER_UPDATED then(.-)\n    end\n")
    assert_eq(v and v:find("gold = true", 1, true) ~= nil and v:find("IGNORED[dt]", 1, true) ~= nil, true,
        "B3: vault badge ignores gold / zone / rested / mail updates")

    local tc = ReadFile("Modules/TryCounterService.lua")
    local reg = tc:match("function Fns%.RegisterTryCounterEvents%(%)(.-)\nend\n")
    assert_eq(reg and reg:find('RegisterUnitEvent, tryCounterFrame, ev, "player"', 1, true) ~= nil, true,
        "B11: UNIT_SPELLCAST_* registered for the player only")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Message storms suite failed with " .. failed .. " failure(s).")
end
print("Message storms suite: ALL TESTS PASSED.")
