#!/usr/bin/env lua
--[[
    Regression test (2026-10-22): reputation chat lines refresh only the named faction.

    G1  Every rep chat line (CHAT_MSG_COMBAT_FACTION_CHANGE, at most every 1.5 s, throttle bypassed)
        ran a full ~250-faction scan, UpdateAll + BuildHeaders, a full snapshot diff and an async
        snapshot rebuild. A line (or MAJOR_FACTION_RENOWN_LEVEL_CHANGED) whose faction is known now
        re-reads just that faction and writes it through UpdateFaction. Unattributable sources
        (unparsed / secret line, unknown name, new faction, account-wide flip) keep the full scan.
        The row written must be identical to what the full scan writes for the same API state.
    G2  Per-character rows persisted constant false flags (hasParagon, _isAccountWide, _isHeader,
        _isHeaderWithRep). They are stored only when true; readers treat nil as false.

    Loads the shipped ReputationScanner / ReputationProcessor / ReputationCacheService under wow_stub.lua.
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
table.wipe = _G.wipe

-- ---------- fake reputation API ----------
local KEY = "Player-1-00000001"
local calls = { index = 0, byID = 0 }
local factions = {
    { factionID = 9000, name = "Midnight", isHeader = true, isHeaderWithRep = false, reaction = 0,
      currentStanding = 0, currentReactionThreshold = 0, nextReactionThreshold = 0 },
    { factionID = 100, name = "Faction A", reaction = 5, currentStanding = 3500,
      currentReactionThreshold = 3000, nextReactionThreshold = 9000, isChild = false },
    { factionID = 200, name = "Faction R", reaction = 5, currentStanding = 500,
      currentReactionThreshold = 0, nextReactionThreshold = 2500 },
    { factionID = 300, name = "Faction F", reaction = 5, currentStanding = 1200,
      currentReactionThreshold = 1000, nextReactionThreshold = 2000 },
}
local byID = {}
for i = 1, #factions do byID[factions[i].factionID] = factions[i] end
local accountWide = { [200] = true }
local major = { [200] = { factionID = 200, name = "Faction R", renownLevel = 3,
    renownReputationEarned = 500, renownLevelThreshold = 2500 } }
local friends = { [300] = { friendshipFactionID = 300, standing = 1200, maxRep = 42000, name = "Faction F",
    text = "Buddy", reactionThreshold = 1000, nextThreshold = 2000 } }
local friendRanks = { [300] = { currentLevel = 2, maxLevel = 5 } }

local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end

C_Reputation = {
    GetNumFactions = function() return #factions end,
    GetFactionDataByIndex = function(i) calls.index = calls.index + 1; return copy(factions[i]) end,
    GetFactionDataByID = function(id) calls.byID = calls.byID + 1; return copy(byID[id]) end,
    ExpandAllFactionHeaders = function() end,
    IsMajorFaction = function(id) return major[id] ~= nil end,
    IsAccountWideReputation = function(id) return accountWide[id] == true end,
    IsFactionParagon = function() return false end,
    GetFactionParagonInfo = function() return nil end,
}
C_MajorFactions = {
    GetMajorFactionData = function(id) return copy(major[id]) end,
    GetCurrentRenownLevel = function(id) return major[id] and major[id].renownLevel end,
    HasMaximumRenown = function() return false end,
}
C_GossipInfo = {
    GetFriendshipReputation = function(id) return copy(friends[id]) or { friendshipFactionID = 0 } end,
    GetFriendshipReputationRanks = function(id) return copy(friendRanks[id]) end,
}
GetGuildInfo = function() return nil end
UnitName = function() return "Tester" end
GetRealmName = function() return "TestRealm" end
FACTION_STANDING_INCREASED = "Reputation with %s increased by %d."
FACTION_STANDING_DECREASED = "Reputation with %s decreased by %d."

-- ---------- load shipped files ----------
local messages = {}
local WarbandNexus = {
    db = { global = { characters = {} }, profile = {}, char = {} },
    SendMessage = function(_, msg, payload) messages[#messages + 1] = { msg = msg, payload = payload } end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    RegisterBucketEvent = function() end,
    Print = function() end,
}
local ns = { WarbandNexus = WarbandNexus }
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end,
    StartAsync = function() end, StopAsync = function() end, SliceLabel = function() return "" end }
ns.CharacterService = {
    IsCharacterTracked = function() return true end,
    ResolveSubsidiaryCharacterKey = function() return KEY end,
    ResolveCharactersTableKey = function() return KEY end,
}

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a"):gsub("^\239\187\191", "")
    fh:close()
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

LoadFile("Modules/Constants.lua")
LoadFile("Modules/Utilities.lua")
LoadFile("Modules/DataFreshness.lua")
LoadFile("Modules/ReputationScanner.lua")
LoadFile("Modules/ReputationProcessor.lua")
LoadFile("Modules/ReputationCacheService.lua")
local RC = ns.ReputationCache
local EV = ns.Constants.EVENTS

local fullScans = 0
local realFullScan = RC.PerformFullScan
RC.PerformFullScan = function(self, bypass)
    fullScans = fullScans + 1
    return realFullScan(self, bypass)
end
RC:RegisterEventListeners()

local function rdb() return WarbandNexus.db.global.reputationData end
local function charRow(id) return rdb().characters[KEY][id] end
local function reset()
    stub.Advance(5)   -- clear the 1.5 s chat-scan spacing and any pending UI debounce
    fullScans, calls.index, calls.byID = 0, 0, 0
    for i = #messages, 1, -1 do messages[i] = nil end
end
local function lastPayload(msgName)
    for i = #messages, 1, -1 do
        if messages[i].msg == msgName then return messages[i].payload end
    end
    return nil
end
local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end
-- Deep equality ignoring _scanTime (the scan clock).
local function sameRow(a, b, path)
    if type(a) ~= "table" or type(b) ~= "table" then
        if a == b then return true end
        return false, (path or "row") .. ": " .. tostring(a) .. " vs " .. tostring(b)
    end
    for k, v in pairs(a) do
        if k ~= "_scanTime" then
            local ok, why = sameRow(v, b[k], (path or "row") .. "." .. tostring(k))
            if not ok then return false, why end
        end
    end
    for k in pairs(b) do
        if k ~= "_scanTime" and a[k] == nil then return false, (path or "row") .. "." .. tostring(k) .. " only in full-scan row" end
    end
    return true
end
local function chat(line)
    stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", line)
    stub.Advance(3)
end
local function assertParity(id, bucket, label)
    local rowBefore = copy(bucket == "aw" and rdb().accountWide[id] or charRow(id))
    local fiBefore = copy(rdb().factionInfo[id])
    RC:PerformFullScan(true)
    stub.Advance(1)
    local rowAfter = bucket == "aw" and rdb().accountWide[id] or charRow(id)
    local ok, why = sameRow(rowBefore, rowAfter)
    assert_eq(ok, true, label .. ": incremental row == full-scan row" .. (why and (" (" .. why .. ")") or ""))
    assert_eq((sameRow(fiBefore, rdb().factionInfo[id])), true, label .. ": factionInfo unchanged by full scan")
end

print("Setup: initial full scan")
do
    RC:PerformFullScan(true)
    stub.Advance(1)
    assert_eq(charRow(100) ~= nil, true, "Faction A stored per character")
    assert_eq(rdb().accountWide[200] ~= nil, true, "Faction R stored account-wide")
    assert_eq(charRow(300) ~= nil, true, "Faction F stored per character")
    assert_eq(RC._snapshotReady, true, "snapshot built")
    assert_eq(RC._nameToID["Faction A"], 100, "name map has Faction A")
end

print("G2: constant false flags are not persisted; readers still see false")
do
    local row = charRow(100)
    assert_eq(rawget(row, "hasParagon"), nil, "hasParagon=false not stored")
    assert_eq(rawget(row, "_isAccountWide"), nil, "_isAccountWide=false not stored")
    assert_eq(rawget(row, "_isHeader"), nil, "_isHeader=false not stored")
    assert_eq(rawget(row, "_isHeaderWithRep"), nil, "_isHeaderWithRep=false not stored")
    assert_eq(rdb().accountWide[200]._isAccountWide, true, "true flag still stored")
    local h = WarbandNexus:GetFactionByID(100)
    assert_eq(h and h.isAccountWide, false, "hydrated isAccountWide reads false")
    assert_eq(h and h.isHeader, false, "hydrated isHeader reads false")
    assert_eq(h and h.isHeaderWithRep, false, "hydrated isHeaderWithRep reads false")
    assert_eq(h and h.hasParagon, false, "hydrated hasParagon reads false")
    -- A row saved by the old code (explicit false) must not read as a structural change.
    row.hasParagon, row._isAccountWide, row._isHeader, row._isHeaderWithRep = false, false, false, false
    reset()
    RC:PerformFullScan(true)
    stub.Advance(1)
    local p = lastPayload(EV.REPUTATION_UPDATED)
    assert_eq(p and p.structural, false, "old false-flag row vs new nil-flag row: not structural")
    assert_eq(p and p.changedFactionIDs[100], nil, "old false-flag row vs new nil-flag row: unchanged")
end

print("G1: a parsed chat line for a known faction refreshes only that faction")
do
    reset()
    byID[100].currentStanding = 3600
    chat("Reputation with Faction A increased by 100.")
    assert_eq(fullScans, 0, "no full scan")
    assert_eq(calls.index, 0, "no GetFactionDataByIndex walk")
    assert_eq(calls.byID <= 6, true, "a handful of by-ID reads (" .. calls.byID .. ")")
    assert_eq(charRow(100).currentValue, 600, "stored progress updated")
    local p = lastPayload(EV.REPUTATION_UPDATED)
    assert_eq(p and p.changedFactionIDs[100], true, "REPUTATION_UPDATED names faction 100")
    assert_eq(p and countKeys(p.changedFactionIDs), 1, "REPUTATION_UPDATED names only faction 100")
    assert_eq(p and p.structural, false, "value-only change")
    local g = lastPayload(EV.REPUTATION_GAINED)
    assert_eq(g and g.factionID, 100, "WN_REPUTATION_GAINED fired for faction 100")
    assert_eq(g and g.gainAmount, 100, "gain amount from the chat line")
    assert_eq(RC._snapshot[100] and RC._snapshot[100].barValue, 3600, "snapshot entry refreshed")
    assertParity(100, "char", "classic per-character")
end

print("G1: friendship faction through the chat line")
do
    reset()
    friends[300].standing = 1250
    byID[300].currentStanding = 1250
    chat("Reputation with Faction F increased by 50.")
    assert_eq(fullScans, 0, "no full scan")
    assert_eq(calls.index, 0, "no index walk")
    assertParity(300, "char", "friendship per-character")
end

print("G1: MAJOR_FACTION_RENOWN_LEVEL_CHANGED refreshes the account-wide renown faction by ID")
do
    reset()
    major[200].renownLevel = 4
    major[200].renownReputationEarned = 100
    byID[200].currentStanding = 100
    stub.Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 200, 4, 3)
    stub.Advance(3)
    assert_eq(fullScans, 0, "no full scan")
    assert_eq(calls.index, 0, "no index walk")
    assert_eq(rdb().accountWide[200].renown and rdb().accountWide[200].renown.level, 4, "renown level stored")
    local p = lastPayload(EV.REPUTATION_UPDATED)
    assert_eq(p and p.changedFactionIDs[200], true, "payload names faction 200")
    assert_eq(p and p.structural, true, "renown level change is structural")
    local g = lastPayload(EV.REPUTATION_GAINED)
    assert_eq(g and g.isRenownLevelUp, true, "renown level-up notification")
    assertParity(200, "aw", "renown account-wide")
end

print("G1: unattributable sources keep the full scan")
do
    reset()
    chat("Reputation with Nobody Known increased by 5.")
    assert_eq(fullScans, 1, "unknown faction name: full scan")

    reset()
    chat(stub.MarkSecret("Reputation with Faction A increased by 7 (secret copy)."))
    assert_eq(fullScans, 1, "secret chat text: full scan")

    reset()
    chat("unparsable rep line")
    assert_eq(fullScans, 1, "unparsed line: full scan")

    reset()
    RC._nameToID["Faction N"] = 400
    byID[400] = { factionID = 400, name = "Faction N", reaction = 4, currentStanding = 10,
        currentReactionThreshold = 0, nextReactionThreshold = 3000 }
    chat("Reputation with Faction N increased by 10.")
    assert_eq(fullScans, 1, "named faction with no stored row: full scan")

    reset()
    accountWide[100] = true
    byID[100].currentStanding = 3700
    chat("Reputation with Faction A increased by 100.")
    assert_eq(fullScans, 1, "per-character faction now reading account-wide: full scan")
    assert_eq(rdb().accountWide[100] ~= nil, true, "full scan moved it to account-wide")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers" .. (stub.errors[1] and (": " .. stub.errors[1]) or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Reputation incremental chat suite failed with " .. failed .. " failure(s).")
end
print("Reputation incremental chat suite: ALL TESTS PASSED.")
