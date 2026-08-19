#!/usr/bin/env lua5.1
--[[
    Season rollover contract (Midnight 12.1 / Season 2).

    Two things break silently when a season flips, so both are pinned here against the shipped
    files rather than a re-implementation:

    1. Mythic+ scores are season-scoped. C_MythicPlus.GetSeasonBestForMap only reports runs from
       the running season, so on a flip every map reads back empty -- and UpdateDungeonScores
       deliberately refuses to overwrite a populated row with an all-zero snapshot (login / API
       races). Without a season stamp last season's rating stays frozen on screen.
    2. The world-quest zone list is index-addressed. ReminderWorldQuestIndex.ZONES and
       ReminderWorldQuestCatalog.ZONE_KEY_BY_INDEX must stay in lockstep, or a saved reminder
       silently points at the wrong zone after a new zone is inserted.
]]

local ADDON_NAME = "WarbandNexus"
dofile(".github/scripts/wow_stub.lua")   -- run from the repo root, like the other test_*.lua

local failures = 0
local function check(cond, msg)
    if cond then
        print("  ok   " .. msg)
    else
        failures = failures + 1
        print("  FAIL " .. msg)
    end
end

local function NewNS()
    local WN = { db = { global = {}, profile = {}, char = {} } }
    function WN:SendMessage() end
    function WN:RegisterEvent() end
    function WN:RegisterBucketEvent() end
    function WN:SavePvECache() end
    function WN:InvalidateGetAllCharactersCache() end
    function WN:GetWeeklyResetTime() return 0 end
    local ns = { WarbandNexus = WN, LOCALES = {} }
    ns.L = setmetatable({}, { __index = function(_, k) return k end })
    return ns, WN
end

local function LoadFile(ns, rel)
    local fh = assert(io.open(rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    -- Several shipped files carry a UTF-8 BOM. WoW tolerates it and luajit skips it, but
    -- reference Lua 5.1 -- what CI runs -- does not, so strip it before compiling.
    -- Same treatment as wow_addon_harness.lua.
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    chunk(ADDON_NAME, ns)
end

-- MYTHIC+ SEASON STAMP

print("phase 1: Mythic+ score buckets follow the season stamp")

local ns, WN = NewNS()
LoadFile(ns, "Modules/Constants.lua")
ns.CharacterService = { IsCharacterTracked = function() return true end }
LoadFile(ns, "Modules/PvECacheService.lua")

_G.C_MythicPlus = _G.C_MythicPlus or {}
_G.C_ChallengeMode = _G.C_ChallengeMode or {}
_G.C_ChallengeMode.GetMapTable = function() return {} end
_G.C_ChallengeMode.GetOverallDungeonScore = function() return 0 end

WN:InitializePvECache()
local mp = WN.db.global.pveCache.mythicPlus
check(mp.season == 0, "fresh cache starts unstamped (got " .. tostring(mp.season) .. ")")

-- An unstamped cache cannot be attributed to any season, and the stamp shipped in the same build
-- Season 2 opened in, so it must be treated as stale rather than trusted.
mp.dungeonScores["Char-Realm"] = { overallScore = 3000, dungeons = { [123] = { score = 300, bestLevel = 12 } }, lastUpdate = 1 }
mp.bestRuns["Char-Realm"] = { overallScore = 3000 }
_G.C_MythicPlus.GetCurrentSeason = function() return 18 end   -- live value, Midnight Season 2
WN:UpdateDungeonScores("Char-Realm")
check(mp.season == 18, "first read stamps the running season (got " .. tostring(mp.season) .. ")")
local firstStamp = mp.dungeonScores["Char-Realm"]
check(firstStamp == nil or (firstStamp.overallScore or 0) == 0,
    "unstamped cache is treated as stale (got " .. tostring(firstStamp and firstStamp.overallScore) .. ")")
check(mp.bestRuns["Char-Realm"] == nil, "unstamped best runs dropped too")

-- A real flip invalidates every character, offline alts included.
mp.season = 17
mp.dungeonScores["Char-Realm"] = { overallScore = 3000, dungeons = { [123] = { score = 300, bestLevel = 12 } }, lastUpdate = 1 }
mp.dungeonScores["Alt-Realm"] = { overallScore = 2500, dungeons = {}, lastUpdate = 1 }
mp.bestRuns["Char-Realm"] = { overallScore = 3000 }
WN:UpdateDungeonScores("Char-Realm")
check(mp.season == 18, "stamp advances 17 -> 18 (got " .. tostring(mp.season) .. ")")
check(mp.bestRuns["Char-Realm"] == nil, "previous season's best runs dropped")
local cur = mp.dungeonScores["Char-Realm"]
check(cur == nil or (cur.overallScore or 0) == 0,
    "previous season's score gone for the current character (got " .. tostring(cur and cur.overallScore) .. ")")
check(mp.dungeonScores["Alt-Realm"] == nil, "previous season's score gone for offline alts")

-- Within one season the zero-snapshot guard must still protect live data.
mp.dungeonScores["Char-Realm"] = { overallScore = 500, dungeons = {}, lastUpdate = 1 }
WN:UpdateDungeonScores("Char-Realm")
check(mp.dungeonScores["Char-Realm"] and mp.dungeonScores["Char-Realm"].overallScore == 500,
    "same-season rescan does not clear this season's scores")

-- GetCurrentSeason returns -1 until RequestMapInfo has run, and 0 with no season active
-- (warcraft.wiki.gg/wiki/API_C_MythicPlus.GetCurrentSeason). Neither may destroy anything.
mp.dungeonScores["Char-Realm"] = { overallScore = 777, dungeons = {}, lastUpdate = 1 }
for _, unknown in ipairs({ -1, 0 }) do
    _G.C_MythicPlus.GetCurrentSeason = function() return unknown end
    WN:UpdateDungeonScores("Char-Realm")
    check(mp.season == 18 and mp.dungeonScores["Char-Realm"].overallScore == 777,
        "season " .. unknown .. " (not known yet) changes nothing")
end

_G.C_MythicPlus.GetCurrentSeason = nil
WN:UpdateDungeonScores("Char-Realm")
check(mp.season == 18, "missing GetCurrentSeason is survivable")

-- WORLD QUEST ZONE INDEX

print("phase 2: world-quest zone tables stay in lockstep")

local ns2 = NewNS()
LoadFile(ns2, "Locales/enUS.lua")
LoadFile(ns2, "Modules/Constants.lua")
LoadFile(ns2, "Modules/Data/ReminderContentIndex.lua")
LoadFile(ns2, "Modules/Data/ReminderMidnightWorldQuestData.lua")
LoadFile(ns2, "Modules/Data/ReminderMidnightFactionEmissaryData.lua")
LoadFile(ns2, "Modules/Data/ReminderWorldQuestCatalog.lua")
LoadFile(ns2, "Modules/Data/ReminderWorldQuestIndex.lua")

local WQC, IDX = ns2.ReminderWorldQuestCatalog, ns2.ReminderWorldQuestIndex
check(WQC ~= nil and IDX ~= nil, "world quest catalog + index loaded")
check(#IDX.ZONES == #WQC.ZONE_KEYS,
    "ZONES and ZONE_KEYS have the same length (" .. #IDX.ZONES .. " vs " .. #WQC.ZONE_KEYS .. ")")
for i = 1, #IDX.ZONES do
    local key = WQC.ZONE_KEY_BY_INDEX[i]
    check(key ~= nil and WQC.ZONE_INDEX_BY_KEY[key] == i,
        "zone " .. i .. " (" .. tostring(IDX.ZONES[i].defaultLabel) .. ") round-trips through key " .. tostring(key))
end

-- Every zone row must carry a locale key that actually exists, or the picker shows a raw key.
local enUS = ns2.LOCALES and ns2.LOCALES.enUS
check(type(enUS) == "table", "enUS locale table built")
for i = 1, #IDX.ZONES do
    local z = IDX.ZONES[i]
    check(z.localeKey and enUS[z.localeKey] ~= nil,
        "zone " .. i .. " locale key present: " .. tostring(z.localeKey))
end

-- Midnight 12.1: the Coiled Isle and the levels beneath it must all reach the isle's zone.
print("phase 3: Midnight 12.1 Coiled Isle maps reach their zone")
local coiledIndex = WQC.ZONE_INDEX_BY_KEY.coiled_isle
check(coiledIndex ~= nil, "coiled_isle zone key exists")
for _, mapID in ipairs({ 2512, 2509, 2613, 2642 }) do
    local zi = IDX.ResolveZoneIndexForMap and IDX.ResolveZoneIndexForMap(mapID)
    check(zi == coiledIndex, "map " .. mapID .. " resolves to the Coiled Isle (got " .. tostring(zi) .. ")")
end

-- The Coiled Isle is not Isle of Quel'Danas; the pre-12.1 zones must not have shifted.
for mapID, wantKey in pairs({ [2393] = "silvermoon", [2395] = "eversong", [2424] = "isle",
                              [2413] = "harandar", [2437] = "zulaman", [2405] = "voidstorm" }) do
    local zi = IDX.ResolveZoneIndexForMap(mapID)
    check(WQC.ZONE_KEY_BY_INDEX[zi or -1] == wantKey,
        "map " .. mapID .. " still maps to " .. wantKey .. " (got " .. tostring(WQC.ZONE_KEY_BY_INDEX[zi or -1]) .. ")")
end

-- Reminder zone_enter matching normalizes the sub-levels onto the isle's picker row.
print("phase 4: sub-levels normalize onto the isle's picker row")
local RCI = ns2.ReminderContentIndex
if RCI and RCI.Validate then
    local ok = RCI.Validate()
    check(ok ~= false, "ReminderContentIndex.Validate() passes")
end
for _, mapID in ipairs({ 2509, 2613, 2642 }) do
    local canon = RCI.NormalizeToCanonicalPickerMap and RCI.NormalizeToCanonicalPickerMap(mapID)
    check(canon == 2512, "map " .. mapID .. " normalizes to 2512 (got " .. tostring(canon) .. ")")
end
check(RCI.NormalizeToCanonicalPickerMap(2512) == 2512, "2512 normalizes to itself")

print("")
if failures > 0 then
    print("test_season_rollover: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("test_season_rollover: all checks passed")
