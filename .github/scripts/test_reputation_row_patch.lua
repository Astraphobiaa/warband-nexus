#!/usr/bin/env lua
--[[
    Regression test: a reputation gain repaints only that faction's row.

    - WN_REPUTATION_UPDATED was sent without a payload, so the Reputation tab re-aggregated every
      faction across every character and rebuilt the whole list on each gain. A full scan now sends
      { changedFactionIDs = { [id] = true }, structural = bool }: value-only changes are structural =
      false; a new / removed faction, a standing or renown level change, an account-wide flip or a
      secret value is structural.
    - The tab re-aggregates just the changed factions and repaints their painted rows; off-screen rows
      get the fresh entry when scrolled in. Structural payloads, an active search, a payload-less
      UPDATED or a faction missing from the painted list still redraw in full.
    - The scan's WN_REPUTATION_LOADING_STARTED repainted the tab as a loading card on every gain;
      with a list already painted it now leaves the rows up.

    Loads the shipped Modules/ReputationCacheService.lua, Modules/UI/ReputationUI.lua and
    Modules/UI/VirtualListModule.lua under wow_stub.lua.
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
    src = src:gsub("^\239\187\191", "")
    local chunk, err = loadstring(src, "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

local KEY = "Player-1-00000001"

-- ================================================================================================
-- Service: the payload a full scan sends
-- ================================================================================================
local svc = {}
do
    local ns = {}
    local sent = {}
    local WN = {
        db = { global = { characters = {} }, profile = {}, char = {} },
        SendMessage = function(_, msg, payload) sent[#sent + 1] = { msg = msg, payload = payload } end,
        RegisterMessage = function() end,
        RegisterEvent = function() end,
        RegisterBucketEvent = function() end,
        Print = function() end,
    }
    ns.WarbandNexus = WN
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
    local scanRows = {}
    ns.ReputationScanner = { FetchAllFactionsAsync = function(_, cb) cb(scanRows) end }
    ns.ReputationProcessor = { Process = function(_, raw) return raw end }
    LoadFile("Modules/Constants.lua", ns)
    LoadFile("Modules/Utilities.lua", ns)
    LoadFile("Modules/DataFreshness.lua", ns)
    LoadFile("Modules/ReputationCacheService.lua", ns)
    local RC = ns.ReputationCache
    RC.BuildSnapshotAsync = function() end
    RC.ProcessPendingChatNotifications = function() end
    RC.PerformSnapshotDiff = function() end
    svc.RC, svc.ns, svc.sent, svc.WN = RC, ns, sent, WN

    -- One full scan returning `rows`; returns the WN_REPUTATION_UPDATED payload it sent.
    function svc.Scan(rows)
        for i = #scanRows, 1, -1 do scanRows[i] = nil end
        for i = 1, #rows do scanRows[i] = rows[i] end
        for i = #sent, 1, -1 do sent[i] = nil end
        RC.isScanning = false
        ns._fullScanInProgress = false
        RC:PerformFullScan(true)
        stub.Advance(0)
        local E = ns.Constants.EVENTS
        for i = 1, #sent do
            if sent[i].msg == E.REPUTATION_UPDATED then return sent[i].payload, true end
        end
        return nil, false
    end
end

local function fac(id, value, opts)
    opts = opts or {}
    return { factionID = id, name = "Faction " .. id, currentValue = value, maxValue = 1000,
        reaction = opts.reaction or 5, isAccountWide = opts.accountWide or false, _scanIndex = id,
        parentFactionName = "Midnight", renown = opts.renown }
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

print("Phase 1: A full scan reports which factions changed and whether the list can move")
do
    local p, sentUpdate = svc.Scan({ fac(100, 50), fac(200, 10) })
    assert_eq(sentUpdate, true, "scan sends WN_REPUTATION_UPDATED")
    assert_eq(type(p) == "table" and p.structural, true, "first scan (new factions) is structural")

    p = svc.Scan({ fac(100, 60), fac(200, 10) })
    assert_eq(type(p) == "table" and p.structural, false, "value-only gain is not structural")
    assert_eq(type(p) == "table" and p.changedFactionIDs and p.changedFactionIDs[100], true,
        "gained faction 100 is listed")
    assert_eq(type(p) == "table" and countKeys(p.changedFactionIDs), 1, "unchanged faction 200 is not listed")

    p = svc.Scan({ fac(100, 60), fac(200, 10) })
    assert_eq(type(p) == "table" and p.structural == false and countKeys(p.changedFactionIDs), 0,
        "a scan that changed nothing sends an empty, non-structural set")

    p = svc.Scan({ fac(100, 5, { reaction = 6 }), fac(200, 10) })
    assert_eq(type(p) == "table" and p.structural, true, "standing tier change is structural")
    assert_eq(type(p) == "table" and p.changedFactionIDs and p.changedFactionIDs[100], true,
        "standing change still names the faction")

    p = svc.Scan({ fac(100, 5, { reaction = 6 }), fac(200, 10), fac(300, 1) })
    assert_eq(type(p) == "table" and p.structural, true, "a new faction is structural")

    p = svc.Scan({ fac(100, 5, { reaction = 6 }), fac(200, 10), fac(300, 1, { accountWide = true }) })
    assert_eq(type(p) == "table" and p.structural, true, "an account-wide flip is structural")

    svc.Scan({ fac(400, 1, { renown = { level = 3, current = 10, max = 2500 } }) })
    p = svc.Scan({ fac(400, 1, { renown = { level = 3, current = 90, max = 2500 } }) })
    assert_eq(type(p) == "table" and p.structural == false and p.changedFactionIDs and p.changedFactionIDs[400], true,
        "renown progress inside a level is value-only")
    p = svc.Scan({ fac(400, 1, { renown = { level = 4, current = 0, max = 2500 } }) })
    assert_eq(type(p) == "table" and p.structural, true, "renown level up is structural")

    local secret = stub.MarkSecret(777777)
    p = svc.Scan({ fac(100, secret, { reaction = 6 }), fac(200, 10), fac(300, 1, { accountWide = true }) })
    assert_eq(type(p) == "table" and p.structural, true, "a secret value is never compared (structural)")
    stub.ClearSecrets()
end

print("Phase 2: Debounced single-faction updates carry the same payload")
do
    local RC = svc.RC
    svc.Scan({ fac(100, 5), fac(200, 10) })
    for i = #svc.sent, 1, -1 do svc.sent[i] = nil end
    RC:UpdateFaction(200, fac(200, 11))
    stub.Advance(1)
    local p
    for i = 1, #svc.sent do
        if svc.sent[i].msg == svc.ns.Constants.EVENTS.REPUTATION_UPDATED then p = svc.sent[i].payload end
    end
    assert_eq(type(p) == "table" and p.structural == false and p.changedFactionIDs and p.changedFactionIDs[200], true,
        "UpdateFaction value change: { [200] = true }, structural = false")
end

-- ================================================================================================
-- UI: the Reputation tab patches rows for value-only payloads
-- ================================================================================================
local Frame = {}
local NOOP = function() return nil end
Frame.__index = function(t, k)
    local m = rawget(Frame, k)
    if m then return m end
    if type(k) == "string" and k:match("^%u") then return NOOP end
    return nil
end
function Frame.new(parent)
    return setmetatable({ _parent = parent, _shown = true, _scripts = {} }, Frame)
end
function Frame:GetParent() return self._parent end
function Frame:SetParent(p) self._parent = p end
function Frame:IsVisible() return not self._hidden end
function Frame:IsShown() return self._shown end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:GetHeight() return 400 end
function Frame:GetWidth() return 600 end
function Frame:GetTop() return 1000 end
function Frame:GetBottom() return 600 end
function Frame:GetLeft() return 0 end
function Frame:GetRight() return 600 end
function Frame:GetVerticalScroll() return self._scroll or 0 end
function Frame:SetVerticalScroll(v) self._scroll = v end
function Frame:GetScrollChild() return self._child end
function Frame:SetScript(n, fn) self._scripts[n] = fn end
function Frame:GetScript(n) return self._scripts[n] end
function Frame:GetChildren() return end
function Frame:GetRegions() return end
function Frame:GetNumChildren() return 0 end
function Frame:GetStringWidth() return 50 end
function Frame:GetFrameLevel() return 1 end
function Frame:CreateTexture() return Frame.new(self) end
function Frame:CreateFontString() return Frame.new(self) end
function Frame:GetText() return self._text end
function Frame:SetText(t) self._text = t end
function Frame:GetObjectType() return "Frame" end

local ui = {}
do
    local Factory = setmetatable({}, { __index = function() return function(_, parent) return Frame.new(parent) end end })
    local ns = { UI = { Factory = Factory } }
    ns.FontManager = Factory
    ns.DebugPrint = function() end
    local rgba = { 0.5, 0.5, 0.5, 1 }
    ns.UI_COLORS = { accent = rgba, bg = rgba, border = rgba, borderLight = rgba, gold = rgba, green = rgba,
        red = rgba, surfaceRowOdd = rgba }
    ns.UI_LAYOUT = { TABLE = { CELL_PAD_X = 4, COL_GAP = 4, ROW_H = { standard = 30 } } }
    ns.UI_TableKit = { ResolveWidths = function(cols, _, w, o) for i = 1, #cols do w[i] = cols[i].width; o[i] = 0 end end }
    ns.UI_FormatNumber = function(n) return tostring(n) end
    ns.UI_SetTextColorRole = function() end
    ns.UI_CreateCollapseExpandControl = function(parent) return Frame.new(parent) end
    ns.UI_CollapseExpandSetState = function() end
    ns.UI_CreateDBVersionBadge = function(parent) return Frame.new(parent) end
    ns.UI_HideEmptyStateCard = function() end
    ns.UI_AcquireReputationRow = function(parent) return Frame.new(parent) end
    ns.UI_ReleaseReputationRow = function() end
    ns.UI_ReleaseReputationRowsFromSubtree = function() end
    ns.UI_ReleaseAllPooledChildren = function() end
    ns.UI_ChainSectionFrameBelow = function() end
    ns.UI_CreateNoticeFrame = function(parent) return Frame.new(parent) end
    ns.UI_CreateCollapsibleHeader = function(parent) local h = Frame.new(parent); return h, nil, Frame.new(h) end
    ns.UI_SyncMainTabScrollChrome = function() end
    ns.UI_GetCharKey = function(c) return c._key end
    ns.UI_GetSubsidiaryCharKey = function() return KEY end
    local bodies = {}
    ns.UI_SectionPool = {
        BeginPass = function() end,
        Discard = function() end,
        Remember = function() end,
        HeaderOpts = function(_, _, opts) return opts end,
        Acquire = function(_, key, parent)
            local f = bodies[key] or Frame.new(parent)
            f._parent = parent
            bodies[key] = f
            return f
        end,
    }
    ui.query = ""
    ns.SearchStateManager = { GetQuery = function() return ui.query end, UpdateResults = function() end }
    ns.SearchResultsRenderer = { PrepareContainer = function() end, RenderEmptyState = function() return 0 end }
    ns.ReputationLoadingState = { isLoading = true }
    _G.C_Reputation = { GetNumFactions = function() return 0 end, IsAccountWideReputation = function() return false end }

    -- Fake reputation store: [factionID] = currentValue (one character, character-based, one header).
    local values = {}
    ui.values = values
    local function hydrate(id)
        return { factionID = id, name = "Faction " .. id, currentValue = values[id], maxValue = 1000,
            standingID = 5, standingName = "Friendly", isAccountWide = false, _characterKey = KEY,
            _scanIndex = id, type = "classic" }
    end
    ui.order = {}
    local handlers = {}
    local WN = {
        db = { global = {}, profile = { reputationExpanded = {
            ["filtered-section-characterbased"] = true, ["filtered-cb-header-Midnight"] = true } } },
        RegisterMessage = function(_, msg, fn) handlers[msg] = fn end,
        Print = function() end,
    }
    function WN:GetAllCharacters()
        return { { name = "Alt", realm = "Realm", classFile = "MAGE", level = 90, isTracked = true, _key = KEY } }
    end
    function WN:GetAllReputations()
        local out = {}
        for i = 1, #ui.order do out[#out + 1] = hydrate(ui.order[i]) end
        return out
    end
    function WN:GetReputationsForFactions(set)
        local out = {}
        for i = 1, #ui.order do
            if set[ui.order[i]] then out[#out + 1] = hydrate(ui.order[i]) end
        end
        return out
    end
    function WN:GetReputationHeaders() return { { name = "Midnight", factions = ui.order } } end
    ns.WarbandNexus = WN
    LoadFile("Modules/Constants.lua", ns)
    LoadFile("Modules/UI/VirtualListModule.lua", ns)
    LoadFile("Modules/UI/ReputationUI.lua", ns)

    local scroll = Frame.new(nil)
    local scrollChild = Frame.new(scroll)
    scroll._child = scrollChild
    local rc = Frame.new(scrollChild)
    scrollChild.resultsContainer = rc
    local mf = Frame.new(nil)
    mf.scroll, mf.scrollChild, mf.currentTab, mf.fixedHeader = scroll, scrollChild, "reputations", Frame.new(nil)
    WN.UI = { mainFrame = mf }

    ui.ns, ui.WN, ui.handlers, ui.bodies, ui.rc, ui.mf, ui.scroll = ns, WN, handlers, bodies, rc, mf, scroll
    ui.E = ns.Constants.EVENTS

    -- Register the listeners (loading fast path), then paint the list.
    WN:DrawReputationTab(scrollChild)
    ns.ReputationLoadingState.isLoading = false

    ui.listDraws, ui.tabDraws = 0, 0
    local realList, realTab = WN.DrawReputationList, WN.DrawReputationTab
    WN.DrawReputationList = function(...) ui.listDraws = ui.listDraws + 1; return realList(...) end
    WN.DrawReputationTab = function(...) ui.tabDraws = ui.tabDraws + 1; return realTab(...) end
end

local function Paint(n)
    for i = #ui.order, 1, -1 do ui.order[i] = nil end
    for id = 1, n do ui.order[id] = id; ui.values[id] = id * 10 end
    ui.WN:DrawReputationList(ui.rc, 600)
    stub.Advance(1)
    ui.listDraws, ui.tabDraws = 0, 0
end

local function Body() return ui.bodies["rep:body:filtered-cb-header-Midnight"] end

local function VisibleRowFor(fid)
    local body = Body()
    local vis = body and body._virtualVisibleFrames or {}
    for j = 1, #vis do
        local it = body._vlm_flatList[vis[j].index]
        if it and it.populateEntry and it.populateEntry.factionID == fid then return vis[j].frame end
    end
    return nil
end

local function Burst(payload, withUpdate)
    ui.handlers[ui.E.REPUTATION_CACHE_READY]()
    if withUpdate ~= false then
        ui.handlers[ui.E.REPUTATION_UPDATED](ui.E.REPUTATION_UPDATED, payload)
    end
    stub.Advance(0)
end

print("Phase 3: A value-only gain repaints the painted row without a list redraw")
do
    Paint(3)
    assert_eq(ui.handlers[ui.E.REPUTATION_UPDATED] ~= nil, true, "listeners registered")
    local row2 = VisibleRowFor(2)
    local row3 = VisibleRowFor(3)
    assert_eq(row2 ~= nil and row2._wnRepData and row2._wnRepData.currentValue, 20, "faction 2 painted with 20")
    local oldData3 = row3 and row3._wnRepData
    ui.values[2] = 25
    Burst({ changedFactionIDs = { [2] = true }, structural = false })
    assert_eq(ui.listDraws, 0, "no full list redraw for a value-only gain")
    assert_eq(VisibleRowFor(2), row2, "faction 2 keeps its row frame (patched in place, not re-windowed)")
    row2 = VisibleRowFor(2)
    assert_eq(row2 and row2._wnRepData and row2._wnRepData.currentValue, 25, "faction 2's row shows the new value")
    assert_eq(VisibleRowFor(3) and VisibleRowFor(3)._wnRepData == oldData3, true, "faction 3's row is untouched")

    Burst({ changedFactionIDs = {}, structural = false })
    assert_eq(ui.listDraws, 0, "a scan with no changed rows repaints nothing")
end

print("Phase 4: An off-screen faction gets the fresh entry when scrolled into view")
do
    Paint(40)
    assert_eq(VisibleRowFor(38), nil, "faction 38 is off-screen")
    ui.values[38] = 999
    Burst({ changedFactionIDs = { [38] = true }, structural = false })
    assert_eq(ui.listDraws, 0, "off-screen gain does not redraw the list")
    ui.scroll:SetVerticalScroll(37 * 34)
    ui.mf._vlmScrollPaint = true
    Body()._virtualUpdater()
    ui.mf._vlmScrollPaint = nil
    local row = VisibleRowFor(38)
    assert_eq(row and row._wnRepData and row._wnRepData.currentValue, 999, "scrolled-in row shows the new value")
    ui.scroll:SetVerticalScroll(0)
end

print("Phase 5: Anything the patch cannot prove redraws in full")
do
    Paint(3)
    Burst({ changedFactionIDs = { [2] = true }, structural = true })
    assert_eq(ui.listDraws, 1, "structural payload redraws the list")

    Paint(3)
    Burst(nil)
    assert_eq(ui.listDraws, 1, "payload-less UPDATED redraws the list")

    Paint(3)
    Burst(nil, false)
    assert_eq(ui.listDraws, 1, "CACHE_READY alone redraws the list")

    Paint(3)
    Burst({ changedFactionIDs = { [77] = true }, structural = false })
    assert_eq(ui.listDraws, 1, "a changed faction with no painted row redraws the list")

    ui.query = "faction"
    Paint(3)
    ui.values[2] = 26
    Burst({ changedFactionIDs = { [2] = true }, structural = false })
    assert_eq(ui.listDraws, 1, "active search redraws the list")
    ui.query = ""

    Paint(3)
    ui.mf.currentTab = "items"
    Burst({ changedFactionIDs = { [2] = true }, structural = false })
    ui.mf.currentTab = "reputations"
    Burst({ changedFactionIDs = { [3] = true }, structural = false })
    assert_eq(ui.listDraws, 1, "an update missed off the tab forces the next one to redraw")
end

print("Phase 6: A background rescan keeps the painted list (no loading-card repaint)")
do
    Paint(3)
    ui.ns.ReputationLoadingState.isLoading = true
    ui.handlers[ui.E.REPUTATION_LOADING_STARTED]()
    assert_eq(ui.tabDraws, 0, "LOADING_STARTED over a painted list does not redraw the tab")
    ui.ns.ReputationLoadingState.isLoading = false
    ui.values[1] = 15
    Burst({ changedFactionIDs = { [1] = true }, structural = false })
    assert_eq(ui.listDraws, 0, "the scan's value-only update then patches the row")
    local row1 = VisibleRowFor(1)
    assert_eq(row1 and row1._wnRepData and row1._wnRepData.currentValue, 15, "faction 1's row shows the new value")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers"
    .. (stub.errors[1] and (" (" .. stub.errors[1] .. ")") or ""))

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Reputation row patch suite failed with " .. failed .. " failure(s).")
end
print("Reputation row patch suite: ALL TESTS PASSED.")
