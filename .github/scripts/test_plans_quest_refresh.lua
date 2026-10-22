#!/usr/bin/env lua
--[[
    Regression test: plan completion, daily-quest rescans and the refresh router do no double work
    (2026-10-22 audit, package B).

      B1  CheckPlansForCompletion completed a title plan twice: its WN_COLLECTIBLE_OBTAINED dispatch
          runs OnPlanCollectionUpdated synchronously, which already completes the plan (toast + chat),
          then processPlan toasted again. The completion also rebuilt _incompleteTodoPlansList in place
          while it was being iterated, so the next plan was skipped.
      B2  every QUEST_LOG_UPDATE wave with a daily plan on the character ran a full ScanMidnightQuests
          and sent WN_PLANS_UPDATED{daily_plan_updated} with no diff; the router then repainted Plans
          with skipCooldown. Unchanged quest log -> no scan; unchanged rows -> no message; the router
          coalesces daily_plan_updated when the delta path declines.
      B3  with the Stats tab open every WN_CHARACTER_UPDATED (zone, rested, mail, ilvl, favorite...)
          repainted the tab; only roster / played-time (no dataType) and rosterPrune do now.
      B4  WN_PLAN_COMPLETED carried no planID, so the PlansUI card cache rebuilt every card.

    Loads the shipped PlansManager.lua, DailyQuestManager.lua (+ _Tracking) and UI_RefreshRouter.lua
    under wow_stub.lua.
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

local function LoadFile(rel, ns)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local function BaseNs()
    local ns = {}
    LoadFile("Locales/enUS.lua", ns)
    ns.L = ns.LOCALES and ns.LOCALES.enUS
    LoadFile("Modules/Constants.lua", ns)
    ns.DebugPrint = function() end
    ns.DebugVerbosePrint = function() end
    ns.IsDebugModeEnabled = function() return false end
    ns.Profiler = { enabled = false, CAT = {}, Start = function() end, Stop = function() end, SliceLabel = function() return "" end }
    ns.Utilities = {
        GetCharacterKey = function() return "Alpha-Kazzak" end,
        GetCharacterStorageKey = function() return "Player-3674-0000000A" end,
        GetCanonicalCharacterKey = function(_, k) return k end,
        IsModuleEnabled = function() return true end,
    }
    return ns
end

-- =====================================================================================
print("Phase 1 (B1, B4): one completion per plan, none skipped, planID on WN_PLAN_COMPLETED")
do
    local ns = BaseNs()
    local E = ns.Constants.EVENTS
    local completedMsgs, prints = {}, 0
    local WN
    WN = {
        db = { global = { plans = {}, customPlans = {}, characters = {} }, profile = {}, char = {} },
        RegisterMessage = function() end,
        RegisterEvent = function() end,
        Print = function(_, text)
            if type(text) == "string" and text:find("Plan completed", 1, true) then prints = prints + 1 end
        end,
        SendMessage = function(self, msg, payload)
            if msg == E.PLAN_COMPLETED then
                completedMsgs[#completedMsgs + 1] = payload
            elseif msg == E.COLLECTIBLE_OBTAINED then
                -- NotificationManager's dispatch calls OnPlanCollectionUpdated synchronously.
                self:OnPlanCollectionUpdated(msg, payload)
            end
        end,
    }
    ns.WarbandNexus = WN
    LoadFile("Modules/PlansManager.lua", ns)
    WN.CheckPlanProgress = function() return { collected = true } end
    WN.GetPlanDisplayName = function(_, plan) return plan.name end
    WN.GetPlanDisplayIcon = function() return "icon" end

    WN.db.global.plans = {
        { id = 11, type = "title", titleID = 501, name = "the Patient" },
        { id = 12, type = "mount", mountID = 1234, name = "Invincible" },
        { id = 13, type = "mount", mountID = 1235, name = "Mimiron's Head" },
    }
    WN.planCache = {}
    WN:RefreshPlanCache()
    assert_eq(#(WN._incompleteTodoPlansList or {}), 3, "three incomplete To-Do plans indexed")

    WN:CheckPlansForCompletion()
    local perPlan = {}
    for i = 1, #completedMsgs do
        local pid = completedMsgs[i].planID
        perPlan[tostring(pid)] = (perPlan[tostring(pid)] or 0) + 1
    end
    assert_eq(#completedMsgs, 3, "one WN_PLAN_COMPLETED per plan after a single check")
    assert_eq(prints, 3, "one 'Plan completed' chat line per plan")
    assert_eq(perPlan["11"], 1, "title plan toasted once (B4: payload carries planID)")
    assert_eq(perPlan["12"], 1, "plan after the title plan is not skipped")
    assert_eq(perPlan["13"], 1, "last plan completed")
    local plans = WN.db.global.plans
    assert_eq(plans[1].completed and plans[2].completed and plans[3].completed, true, "all three plans marked completed")
    assert_eq(#WN._incompleteTodoPlansList, 0, "incomplete list empty afterwards")

    stub.Advance(1)   -- the debounced re-check scheduled by the title dispatch
    assert_eq(#completedMsgs, 3, "debounced re-check adds no second toast")
end

-- =====================================================================================
print("Phase 2 (B2): QUEST_LOG_UPDATE scans only on log change, sends only on row change")
do
    local ns = BaseNs()
    local E = ns.Constants.EVENTS
    local EVERSONG = 2395
    local objectives = { [91001] = { { numFulfilled = 1, numRequired = 4, finished = false, text = "Boars" } } }
    local LOG = {
        { isHeader = true, title = "Eversong Woods" },
        { questID = 91001, title = "Eversong errand", isDaily = true },
    }
    local mapCalls = 0
    local completeIDs = {}
    C_Map = C_Map or {}
    C_Map.GetMapInfo = function(mapID) return { mapID = mapID, name = (mapID == EVERSONG) and "Eversong Woods" or ("Map " .. mapID), parentMapID = 2537 } end
    C_QuestLog = {
        GetNumQuestLogEntries = function() return #LOG end,
        GetInfo = function(i) return LOG[i] end,
        GetTitleForQuestID = function(id)
            for i = 1, #LOG do if LOG[i].questID == id then return LOG[i].title end end
        end,
        GetNextWaypoint = function() return nil end,
        GetLogIndexForQuestID = function(id)
            for i = 1, #LOG do if LOG[i].questID == id then return i end end
        end,
        IsQuestFlaggedCompleted = function() return false end,
        IsWorldQuest = function() return false end,
        GetQuestObjectives = function(id) return objectives[id] or {} end,
        IsComplete = function(id) return completeIDs[id] == true end,
        GetQuestsOnMap = function()
            mapCalls = mapCalls + 1
            return {}
        end,
    }
    C_TaskQuest = { GetQuestZoneID = function() return nil end }

    local plansMsgs = 0
    local WN = {
        db = { global = { plans = {}, characters = {} }, profile = {}, char = {} },
        RegisterMessage = function() end,
        RegisterEvent = function() end,
        Print = function() end,
        SendMessage = function(_, msg, payload)
            if msg == E.PLANS_UPDATED and payload and payload.action == "daily_plan_updated" then
                plansMsgs = plansMsgs + 1
            end
        end,
    }
    ns.WarbandNexus = WN
    LoadFile("Modules/DailyQuestManager.lua", ns)
    LoadFile("Modules/DailyQuestManager_Tracking.lua", ns)
    local plan = {
        id = 21, type = "daily_quests", characterName = "Alpha", characterRealm = "Kazzak",
        questTypes = { dailyQuests = true, weeklyQuests = true, worldQuests = true, assignments = true, events = true },
        lastUpdate = time(),
    }
    WN.db.global.plans = { plan }
    WN:InitializeDailyQuestManager()

    local function Wave()
        WN:OnDailyQuestUpdate()
        stub.Advance(1.1)
    end

    Wave()
    assert_eq(mapCalls > 0, true, "first wave: full scan")
    assert_eq(plansMsgs, 1, "first wave: rows built -> one daily_plan_updated")

    local before = mapCalls
    Wave()
    assert_eq(mapCalls, before, "unchanged quest log: no ScanMidnightQuests")
    assert_eq(plansMsgs, 1, "unchanged quest log: no daily_plan_updated")

    objectives[91001][1].numFulfilled = 2
    Wave()
    assert_eq(mapCalls > before, true, "objective progress changed: rescan")
    assert_eq(plansMsgs, 2, "objective progress changed: one daily_plan_updated")

    stub.Advance(61)
    before = mapCalls
    Wave()
    assert_eq(mapCalls > before, true, "last scan older than the max age: rescan (map-only data)")
    assert_eq(plansMsgs, 2, "rescan with identical rows: no daily_plan_updated")

    objectives[91001][1].numFulfilled = stub.MarkSecret(7777)
    before = mapCalls
    Wave()
    assert_eq(mapCalls > before, true, "secret objective value: fingerprint unreadable -> rescan")
    local before2 = mapCalls
    Wave()
    assert_eq(mapCalls > before2, true, "secret value keeps forcing the scan path")
    stub.ClearSecrets()

    -- Objective-less quest turns ready-for-turn-in: no objective changed, the log state did.
    Wave()
    before = mapCalls
    completeIDs[91001] = true
    Wave()
    assert_eq(mapCalls > before, true, "quest became complete without objective change: rescan")

    -- A scan that errors must not mark the log as seen: the next wave retries.
    objectives[91001][1].numFulfilled = 3
    local realUpdate = WN.UpdateDailyPlanProgress
    WN.UpdateDailyPlanProgress = function() error("scan failed") end
    Wave()
    WN.UpdateDailyPlanProgress = realUpdate
    stub.Reset()   -- the deliberate error above is not a test failure
    before = mapCalls
    Wave()
    assert_eq(mapCalls > before, true, "failed scan left the fingerprint unstored: next wave rescans")

    local sentBefore = plansMsgs
    WN:UpdateDailyPlanProgress(plan, true)
    assert_eq(plansMsgs, sentBefore + 1, "explicit refresh (turn-in / tracking / reset) still always sends")
end

-- =====================================================================================
print("Phase 3 (B2, B3): router coalesces daily_plan_updated and filters Stats updates")
do
    local noop = function() end
    local ns = { Constants = BaseNs().Constants }
    local E = ns.Constants.EVENTS
    local handlers = {}
    local WN = {
        RegisterMessage = function(_, msg, fn) handlers[msg] = fn end,
        SendMessage = noop,
        UpdateTabCountBadges = noop,
    }
    local shown = true
    local f = { currentTab = "plans", IsShown = function() return shown end }
    local populates, skipPopulates = 0, 0
    local deltaResult = false
    ns.PlansUI_ApplyPlanDelta = function() return deltaResult end
    LoadFile("Modules/UI/UI_RefreshRouter.lua", ns)
    ns.UI_RefreshRouter.RegisterMainShellListeners({
        addon = WN, frame = f, eventsSelf = {}, constants = ns.Constants, state = {},
        schedulePopulate = function(skip)
            if skip then skipPopulates = skipPopulates + 1 else populates = populates + 1 end
        end,
        scheduleGearInvNarrow = noop, throttledGearAsyncRepaint = noop,
        isGearTabQuiet = function() return false end, updateTabVisibility = noop,
        scrollNavEnsureTabVisible = noop, updateTabButtonStates = noop,
    })
    local plansH, charH = handlers[E.PLANS_UPDATED], handlers[E.CHARACTER_UPDATED]
    assert_eq(type(plansH) == "function" and type(charH) == "function", true, "PLANS_UPDATED / CHARACTER_UPDATED listeners registered")

    plansH(E.PLANS_UPDATED, { action = "daily_plan_updated", planID = 21, planType = "daily_quests" })
    assert_eq(skipPopulates, 0, "daily_plan_updated (delta declined): no cooldown-skipping repaint")
    assert_eq(populates, 1, "daily_plan_updated (delta declined): coalesced repaint")
    plansH(E.PLANS_UPDATED, { action = "added", planID = 22 })
    assert_eq(skipPopulates, 1, "user add (delta declined): immediate repaint kept")
    deltaResult = true
    plansH(E.PLANS_UPDATED, { action = "daily_plan_updated", planID = 21 })
    assert_eq(populates + skipPopulates, 2, "daily_plan_updated absorbed by the delta path: no repaint")

    f.currentTab = "stats"
    populates, skipPopulates = 0, 0
    local ignored = { "zone", "rested", "mail", "itemLevel", "favorite", "guild", "professions", "gold" }
    for i = 1, #ignored do
        charH(E.CHARACTER_UPDATED, { charKey = "Alpha-Kazzak", dataType = ignored[i] })
    end
    assert_eq(populates + skipPopulates, 0, "Stats: zone / rested / mail / ilvl / favorite / gold(own listener) do not repaint")
    charH(E.CHARACTER_UPDATED, { charKey = "Alpha-Kazzak" })
    assert_eq(skipPopulates, 1, "Stats: roster / played-time update (no dataType) repaints")
    charH(E.CHARACTER_UPDATED, { dataType = "rosterPrune", removed = 1 })
    assert_eq(skipPopulates, 2, "Stats: rosterPrune repaints")
    charH(E.CHARACTER_UPDATED, { charKey = "Gone-Kazzak", isDeleted = true })
    assert_eq(skipPopulates, 3, "Stats: deleted character repaints")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Plans quest refresh suite failed with " .. failed .. " failure(s).")
end
print("Plans quest refresh suite: ALL TESTS PASSED.")
