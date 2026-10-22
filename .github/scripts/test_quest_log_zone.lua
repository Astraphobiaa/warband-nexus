#!/usr/bin/env lua
--[[
    Regression test: quest-log quests are filed under the zone they belong to, not a route hop.

    QuestInfo has no mapID, so the log scan fell back to C_QuestLog.GetNextWaypoint, whose first
    return is the map of the NEXT WAYPOINT of the route (a portal room, a zone on the way). A quest
    outside Midnight routed through Silvermoon showed up as a Midnight quest, and a Midnight quest
    routed through a portal elsewhere was dropped. The log scan now uses the Midnight zone of the
    quest-log header the quest is listed under (matched by the localized C_Map name); task quests
    still use C_TaskQuest.GetQuestZoneID.

    Loads the shipped Modules/DailyQuestManager.lua under wow_stub.lua.
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

local EVERSONG, SILVERMOON, OUTSIDE = 2395, 2393, 2339   -- 2339 = Dornogal (not a Midnight zone)
local MAP_NAMES = { [EVERSONG] = "Eversong Woods", [SILVERMOON] = "Silvermoon City", [OUTSIDE] = "Dornogal" }
local LOG = {
    { isHeader = true, title = "Eversong Woods" },
    { questID = 91001, title = "Eversong errand", isDaily = true },   -- routed via a portal outside Midnight
    { isHeader = true, title = "Dornogal" },
    { questID = 91002, title = "Dornogal errand", isDaily = true },   -- routed via Silvermoon
}
local WAYPOINT = { [91001] = OUTSIDE, [91002] = SILVERMOON }

C_Map = C_Map or {}
C_Map.GetMapInfo = function(mapID)
    return { mapID = mapID, name = MAP_NAMES[mapID] or ("Map " .. mapID), parentMapID = 2537 }
end
C_QuestLog = {
    GetNumQuestLogEntries = function() return #LOG end,
    GetInfo = function(i) return LOG[i] end,
    GetTitleForQuestID = function(id)
        for i = 1, #LOG do if LOG[i].questID == id then return LOG[i].title end end
    end,
    GetNextWaypoint = function(id) return WAYPOINT[id], 0.5, 0.5 end,
    GetLogIndexForQuestID = function(id)
        for i = 1, #LOG do if LOG[i].questID == id then return i end end
    end,
    IsQuestFlaggedCompleted = function() return false end,
    IsWorldQuest = function() return false end,
    GetQuestObjectives = function() return {} end,
}
C_TaskQuest = { GetQuestZoneID = function() return nil end }

local ns = {}
local WarbandNexus = {
    db = { global = { resets = {}, characters = {} }, profile = {}, char = {} },
    SendMessage = function() end,
    RegisterMessage = function() end,
    RegisterEvent = function() end,
    Print = function() end,
}
ns.WarbandNexus = WarbandNexus
ns.DebugPrint = function() end
ns.DebugVerbosePrint = function() end
ns.IsDebugModeEnabled = function() return false end
ns.Utilities = {
    GetCharacterKey = function() return "Player-01" end,
    GetCharacterStorageKey = function() return "Player-01" end,
    GetCanonicalCharacterKey = function(_, k) return k end,
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
LoadFile("Modules/DailyQuestManager.lua")

local function find(quests, id)
    for _, list in pairs(quests) do
        for i = 1, #list do
            if list[i].questID == id then return list[i] end
        end
    end
end

print("Phase 1: Log quests use their quest-log zone header, not the next waypoint")
do
    local quests = WarbandNexus:ScanMidnightQuests()
    local q1, q2 = find(quests, 91001), find(quests, 91002)
    assert_eq(q1 ~= nil, true, "Midnight quest routed via a non-Midnight portal is listed")
    assert_eq(q1 and q1.mapID, EVERSONG, "it is filed under its header zone")
    assert_eq(q2, nil, "a non-Midnight quest routed through Silvermoon is not listed")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Quest log zone suite failed with " .. failed .. " failure(s).")
end
print("Quest log zone suite: ALL TESTS PASSED.")
