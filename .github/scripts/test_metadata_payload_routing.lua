#!/usr/bin/env lua
--[[
    Regression test: WN_ITEM_METADATA_READY payload filtering and the CRITERIA_UPDATE repaint (2026-10-22).

      K3  WN_ITEM_METADATA_READY means both "Items metadata batch resolved" (no payload, ItemsCacheService)
          and "achievement reward item resolved" (payload = achievementID, CollectionService_Achievements,
          one message per item, not coalesced). The Gear tab and both Items listeners repainted on the
          achievement one too. They now ignore a payload; the Collections achievement consumer is unchanged.
      K4  the router's CRITERIA_UPDATE coalescer announced a repaint as WN_PLANS_UPDATED from the UI layer:
          nothing is written there, and every listener of that data message (daily-quest index rebuild,
          reminder cache, Collections redraw, journal icons) woke ~1/s. It now sends
          WN_UI_MAIN_REFRESH_REQUESTED for the Plans tab and schedules the To-Do tracker's own refresh.

    Loads the shipped Modules/UI/UI_RefreshRouter.lua and Modules/UI/ItemsUI.lua under wow_stub.lua.
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

-- Fake frames: PascalCase methods not defined below are no-ops; data fields stay nil.
local noop = function() end
local Frame = {}
local FrameMT = { __index = function(_, k)
    local v = Frame[k]
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^[A-Z]") then return noop end
    return nil
end }
local function NewFrame()
    return setmetatable({ _children = {}, _shown = true, _w = 100, _scripts = {} }, FrameMT)
end
function Frame:Hide() self._shown = false end
function Frame:Show() self._shown = true end
function Frame:IsShown() return self._shown end
function Frame:GetWidth() return self._w end
function Frame:GetParent() return self._parent end

local function Constants()
    local ns = {}
    LoadFile("Modules/Constants.lua", ns)
    return ns.Constants
end

-- Message capture: every (target, message) handler, in registration order.
local function NewBus()
    local bus = { list = {}, sent = {} }
    function bus.Register(target, msg, fn)
        bus.list[#bus.list + 1] = { target = target, msg = msg, fn = fn }
    end
    function bus.Handlers(msg)
        local out = {}
        for i = 1, #bus.list do
            if bus.list[i].msg == msg then out[#out + 1] = bus.list[i].fn end
        end
        return out
    end
    function bus.Send(_, msg, ...)
        bus.sent[#bus.sent + 1] = { msg = msg, arg = (...) }
        local hs = bus.Handlers(msg)
        for i = 1, #hs do hs[i](msg, ...) end
    end
    function bus.Count(msg)
        local n = 0
        for i = 1, #bus.sent do if bus.sent[i].msg == msg then n = n + 1 end end
        return n
    end
    return bus
end

local ACH_ID = 4242

-- =====================================================================================
print("Phase 1 (K3 / K4): router Gear listener and CRITERIA_UPDATE repaint")
do
    local ns = { Constants = Constants() }
    local E = ns.Constants.EVENTS
    local bus = NewBus()
    local WN = { RegisterMessage = bus.Register, SendMessage = bus.Send, UpdateTabCountBadges = noop }
    local gearIconRefreshes = 0
    WN.TryRefreshAllGearEquipSlotIcons = function() gearIconRefreshes = gearIconRefreshes + 1 end
    local f = NewFrame()
    f.currentTab = "gear"
    ns.UI_GetItemsSubTab = function() return "inventory" end
    local populates, skipPopulates = 0, 0
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

    local meta = bus.Handlers(E.ITEM_METADATA_READY)
    assert_eq(#meta >= 1, true, "router registers a WN_ITEM_METADATA_READY listener")
    for i = 1, #meta do meta[i](E.ITEM_METADATA_READY) end
    assert_eq(gearIconRefreshes, 1, "Gear: Items metadata batch (no payload) refreshes the slot icons")
    for i = 1, #meta do meta[i](E.ITEM_METADATA_READY, ACH_ID) end
    assert_eq(gearIconRefreshes, 1, "Gear: achievement reward item (payload) does not repaint the Gear tab")

    -- K4: CRITERIA_UPDATE with an achievement plan, Plans tab on screen, tracker shown.
    WN.planCache = { achievementIDs = { [ACH_ID] = true } }
    local dirtied = 0
    ns.UI_MarkPlansAchievementCardsDirty = function() dirtied = dirtied + 1 end
    local trackerSchedules, trackerAction = 0, nil
    ns.PlansTrackerWindow = { SchedulePlansUpdatedRefresh = function(p)
        trackerSchedules = trackerSchedules + 1
        trackerAction = p and p.action
    end }
    local tracker = NewFrame()
    _G.WarbandNexus_PlansTracker = tracker
    f.currentTab = "plans"
    bus.sent = {}
    stub.Fire("CRITERIA_UPDATE")
    stub.Fire("CRITERIA_UPDATE")
    stub.Advance(1.5)
    assert_eq(dirtied, 1, "criteria burst coalesced: achievement cards marked dirty once")
    assert_eq(bus.Count(E.PLANS_UPDATED), 0, "no WN_PLANS_UPDATED data message for a repaint")
    assert_eq(bus.Count(E.UI_MAIN_REFRESH_REQUESTED), 1, "one WN_UI_MAIN_REFRESH_REQUESTED instead")
    local req
    for i = 1, #bus.sent do if bus.sent[i].msg == E.UI_MAIN_REFRESH_REQUESTED then req = bus.sent[i].arg end end
    assert_eq(req and req.tab, "plans", "refresh request targets the Plans tab")
    stub.Advance(2)
    assert_eq(populates, 1, "Plans tab: one coalesced (cooldown-respecting) populate")
    assert_eq(skipPopulates, 0, "Plans tab: no cooldown-skipping populate")
    assert_eq(trackerSchedules, 1, "shown To-Do tracker: its coalesced refresh is scheduled")
    assert_eq(trackerAction, "criteria_update", "tracker refresh keeps the neutral criteria_update action")

    tracker:Hide()
    trackerSchedules = 0
    stub.Fire("CRITERIA_UPDATE")
    stub.Advance(1.5)
    assert_eq(trackerSchedules, 0, "hidden tracker: no tracker refresh")
    _G.WarbandNexus_PlansTracker = nil
end

-- =====================================================================================
print("Phase 2 (K3): Items listeners ignore the achievement payload")
do
    local ns = { UI = { Factory = {} }, Constants = Constants() }
    local E = ns.Constants.EVENTS
    local bus = NewBus()
    local WN = { db = { profile = {}, global = {}, char = {} }, RegisterMessage = bus.Register, SendMessage = bus.Send }
    ns.WarbandNexus = WN
    ns.SearchStateManager = { UpdateResults = noop, GetQuery = function() return "" end }
    ns.UI_GetExpandedGroups = function() return {} end
    ns.StorageSectionLayout = {}
    local sub = "inventory"
    ns.UI_GetItemsSubTab = function() return sub end
    ns.Utilities = { IsModuleEnabled = function() return true end }
    ns.CharacterService = { IsCharacterTracked = function() return true end }
    LoadFile("Modules/UI/ItemsUI.lua", ns)

    local mf = NewFrame()
    mf.currentTab = "items"
    local parent = NewFrame()
    mf.scrollChild = parent
    WN.UI = { mainFrame = mf }
    pcall(WN.DrawItemList, WN, parent)   -- registers the listeners first; the draw itself may stop early
    local meta = bus.Handlers(E.ITEM_METADATA_READY)
    assert_eq(#meta, 2, "Items + Storage embed listeners registered")

    -- Bags sub-tab: virtual list repaint.
    local rc = NewFrame()
    rc._parent = parent
    parent.resultsContainer = rc
    local virtualRepaints = 0
    rc._virtualUpdater = function() virtualRepaints = virtualRepaints + 1 end
    for i = 1, #meta do meta[i](E.ITEM_METADATA_READY) end
    assert_eq(virtualRepaints, 1, "Bags: Items metadata batch repaints visible rows")
    for i = 1, #meta do meta[i](E.ITEM_METADATA_READY, ACH_ID) end
    assert_eq(virtualRepaints, 1, "Bags: achievement reward item does not repaint")

    -- Warband sub-tab (Storage tree embed): in-place row refresh.
    sub = "warband"
    local inPlace = 0
    local row = NewFrame()
    row._wnStorageItemRef = { itemID = 1 }
    rc._wnStorageRowRefs = { row }
    rc._wnStorageApplyRowVisual = function() inPlace = inPlace + 1 end
    for i = 1, #meta do meta[i](E.ITEM_METADATA_READY) end
    assert_eq(inPlace, 1, "Warband tree: Items metadata batch refreshes rows in place")
    for i = 1, #meta do meta[i](E.ITEM_METADATA_READY, ACH_ID) end
    assert_eq(inPlace, 1, "Warband tree: achievement reward item does not repaint")
end

-- =====================================================================================
print("Phase 3 (K3): the achievement consumer still gets its payload")
do
    local fh = assert(io.open(ROOT .. "/Modules/CollectionService_Achievements.lua", "rb"))
    local src = fh:read("*a")
    fh:close()
    assert_eq(src:find("SendMessage(E.ITEM_METADATA_READY, achievementID)", 1, true) ~= nil, true,
        "CollectionService_Achievements still sends the achievementID payload")
    fh = assert(io.open(ROOT .. "/Modules/UI/CollectionsUI.lua", "rb"))
    src = fh:read("*a")
    fh:close()
    assert_eq(src:find("metadataReadyName, function(_, achievementID)\n            if not achievementID then return end", 1, true) ~= nil,
        true, "CollectionsUI listener still keys on the achievementID payload")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Metadata payload routing suite failed with " .. failed .. " failure(s).")
end
print("Metadata payload routing suite: ALL TESTS PASSED.")
