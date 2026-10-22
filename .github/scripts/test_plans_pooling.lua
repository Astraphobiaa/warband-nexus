#!/usr/bin/env lua
--[[
    Regression test: Plans Weekly Progress chrome / rows and the browse grid re-bind instead of rebuild.

    1. DrawDailyTasksView rebuilt every character wrap, collapsible header, section body, stats strip,
       category wrap / header / body and every quest row (status icon, title, objective icons and
       texts) on each paint, and the Plans teardown parked all of it in the recycle bin. The view now
       pools section chrome through SectionPool ("pln:" keys) and rows per section body; the teardown
       keeps pooled frames in place and still discards real garbage. A repaint with unchanged data
       must create no frame, texture or FontString and paint exactly what a fresh build paints.
    2. The browse grid filled its card pool by visible slot, so scrolling by one row re-rendered every
       visible card, and each render allocated row data / context / action tables and closures. Cards
       are now keyed by result index and own their per-card tables; header clicks use one handler.

    Loads the shipped Modules/UI/SectionPool.lua, PlansUI_Browse.lua and PlansUI.lua under wow_stub.lua
    with fake frames that count every CreateFrame / CreateTexture / CreateFontString.
]]

local passed, failed = 0, 0
local function assert_eq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
        print("  ok   " .. msg)
    else
        failed = failed + 1
        local a, e = tostring(actual), tostring(expected)
        if #a > 200 or #e > 200 then
            local at = 1
            while at <= #a and a:sub(at, at) == e:sub(at, at) do at = at + 1 end
            a, e = "..." .. a:sub(math.max(1, at - 60), at + 60), "..." .. e:sub(math.max(1, at - 60), at + 60)
        end
        print(string.format("  FAIL %s: expected %s, got %s", msg, e, a))
    end
end

local SCRIPT_DIR = ".github/scripts"
local ROOT = os.getenv("WN_ROOT") or "."
local stub = dofile(SCRIPT_DIR .. "/wow_stub.lua")

-- ---------- fake widgets ----------
local counts = { frames = 0, textures = 0, fontstrings = 0 }
local Obj = {}
-- PascalCase names are widget methods: unknown ones are no-ops. Anything else is a plain field (nil).
local ObjMT = { __index = function(_, k)
    local v = Obj[k]
    if v ~= nil then return v end
    if type(k) == "string" and k:match("^[A-Z]") then return function() end end
    return nil
end }

local function NewObj(kind, parent)
    local o = setmetatable({ _kind = kind, _children = {}, _regions = {}, _shown = true, _scripts = {},
        _points = {}, _h = 0, _w = 0 }, ObjMT)
    if kind == "frame" then
        counts.frames = counts.frames + 1
        if parent then o:SetParent(parent) end
    else
        o._parent = parent
        if parent then parent._regions[#parent._regions + 1] = o end
    end
    return o
end
function Obj:SetParent(p)
    local old = self._parent
    self._setParentCalls = (self._setParentCalls or 0) + 1
    if old then
        for i = #old._children, 1, -1 do if old._children[i] == self then table.remove(old._children, i) end end
    end
    self._parent = p
    if p then p._children[#p._children + 1] = self end
end
function Obj:GetParent() return self._parent end
function Obj:GetChildren() return unpack(self._children) end
function Obj:Show() self._shown = true end
function Obj:Hide() self._shown = false end
function Obj:IsShown() return self._shown end
function Obj:SetHeight(h) self._h = h end
function Obj:GetHeight() return self._h end
function Obj:SetWidth(w) self._w = w end
function Obj:GetWidth() return self._w end
function Obj:SetSize(w, h) self._w, self._h = w, h end
function Obj:SetScript(name, fn) self._scripts[name] = fn end
function Obj:GetScript(name) return self._scripts[name] end
function Obj:GetFrameLevel() return 1 end
function Obj:ClearAllPoints() self._points = {} end
-- Like WoW: setting an anchor point that is already set replaces it.
function Obj:SetPoint(a, b, c, d, e)
    local parts = {}
    for _, v in ipairs({ a, b, c, d, e }) do
        if type(v) == "table" then parts[#parts + 1] = "<frame>" else parts[#parts + 1] = tostring(v) end
    end
    local entry = table.concat(parts, ",")
    for i = 1, #self._points do
        if self._points[i]:match("^[^,]+") == a then
            self._points[i] = entry
            return
        end
    end
    self._points[#self._points + 1] = entry
end
function Obj:SetText(t) self._text = t end
function Obj:GetText() return self._text end
function Obj:GetStringWidth() return #(self._text or "") end
function Obj:SetAtlas(a) self._atlas = a end
function Obj:SetVertexColor(r, g, b, a) self._vertex = string.format("%.2f,%.2f,%.2f,%.2f", r, g, b, a or 1) end
function Obj:CreateTexture()
    counts.textures = counts.textures + 1
    return NewObj("texture", self)
end
local function NewFontString(parent, role)
    counts.fontstrings = counts.fontstrings + 1
    local fs = NewObj("fontstring", parent)
    fs._role = role
    return fs
end
_G.CreateFrame = function(_, _, parent) return NewObj("frame", parent) end
_G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 } }

-- Effective-visibility signature of a frame tree (order-insensitive; anchors / sizes / texts / icons).
local function Sig(o)
    if not o._shown then return nil end
    local own = { o._kind, tostring(o._text), tostring(o._atlas), tostring(o._vertex), tostring(o._role),
        table.concat(o._points, ";"), tostring(o._h), tostring(o._rowIndex),
        o._scripts.OnMouseDown and "click" or "-", o._scripts.OnEnter and "tip" or "-" }
    local parts = {}
    for i = 1, #o._regions do
        local s = Sig(o._regions[i])
        if s then parts[#parts + 1] = s end
    end
    for i = 1, #o._children do
        local s = Sig(o._children[i])
        if s then parts[#parts + 1] = s end
    end
    table.sort(parts)
    return "{" .. table.concat(own, "|") .. "[" .. table.concat(parts, "") .. "]}"
end

-- ---------- ns ----------
local ns = {}
local WN = { db = { profile = { modulesEnabled = {} }, global = { plans = {} } }, RegisterMessage = function() end }
ns.WarbandNexus = WN
ns.UI_RecycleBin = NewObj("frame", nil)
ns.UI_LAYOUT = { rowHeight = 26, SECTION_COLLAPSE_HEADER_HEIGHT = 36, SECTION_SPACING = 8,
    PAGE_STACK = { SIDE = 12, BODY_TOP = 8, BOTTOM_PAD = 10 } }
ns.UI_COLORS = { bgCard = { 0.1, 0.1, 0.1, 1 }, accent = { 0.5, 0.4, 0.9 } }
ns.UI_FormatTextNumbers = function(s) return s end
local tooltipShown
ns.TooltipService = { Show = function(_, owner, data) tooltipShown = { owner = owner, title = data.title } end,
    Hide = function() tooltipShown = nil end }
ns.FontManager = { CreateFontString = function(_, parent, role) return NewFontString(parent, role) end }
ns.Utilities = { FormatTimeCompact = function(_, s) return tostring(s) .. "s" end,
    FormatRealmName = function(_, r) return r end }
ns.UI_SetIcon = function(tex, key, opts)
    tex._atlas = "icon:" .. key
    local vc = opts and opts.vertexColor
    if vc then tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4]) else tex:SetVertexColor(1, 1, 1, (opts and opts.alpha) or 1) end
    return true
end
ns.UI_SetTextColorRole = function(fs, role) fs._colorRole = role end
local expanded = {}
ns.UI_GetExpandedGroups = function() return expanded end
ns.UI_CreateCard = function(parent, h) local f = NewObj("frame", parent); f._h = h; return f end
ns.UI_ChainSectionFrameBelow = function(_, frame, prev, left, gap, fallbackY)
    frame:ClearAllPoints()
    if prev then frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -(gap or 8))
    else frame:SetPoint("TOPLEFT", nil, "TOPLEFT", left, -(fallbackY or 0)) end
end
ns.UI_BuildCollapsibleSectionOpts = function(config)
    return { animatedContent = config.bodyGetter, persistToggle = config.persistFn }
end
-- Same reuse contract as SharedWidgets_Collapsible: visualOpts.reuseHeader is re-bound, not recreated.
ns.UI_CreateCollapsibleHeader = function(parent, text, key, isExpanded, onToggle, icon, isAtlas, indent, noIcon, opts)
    local h = opts and opts.reuseHeader
    if h and h._wnCollExpandIcon then
        if h:GetParent() ~= parent then h:SetParent(parent) end
        h._wnCollHeaderText:SetText(text)
        h._wnCollExpanded = isExpanded
        h._wnCollVisualOpts = opts
        h:Show()
        return h, h._wnCollExpandIcon, h._wnCollCategoryIcon, h._wnCollHeaderText
    end
    h = NewObj("frame", parent)
    h._wnCollExpandIcon = NewObj("frame", h)
    h._wnCollExpandIcon._wnCollapseTex = h._wnCollExpandIcon:CreateTexture()
    if not noIcon then h._wnCollCategoryIcon = h:CreateTexture() end
    h._wnCollHeaderText = NewFontString(h, "sectionCollapsibleTitle")
    h._wnCollHeaderText:SetText(text)
    h._wnCollExpanded = isExpanded
    h._wnCollVisualOpts = opts
    return h, h._wnCollExpandIcon, h._wnCollCategoryIcon, h._wnCollHeaderText
end
ns.UI = {}
ns.UI.Factory = {
    CreateContainer = function(_, parent, w, h) local f = NewObj("frame", parent); f:SetSize(w, h); return f end,
    CreateButton = function(_, parent, w, h) local f = NewObj("frame", parent); f:SetSize(w, h); return f end,
    ApplyRowBackground = function(_, row, rowIndex)
        if not row.bg then row.bg = row:CreateTexture() end
        row._rowIndex = rowIndex
    end,
}
-- Mirrors SharedWidgets_RowPool.lua Factory:CreateDataRow (new frame, positioned, alternating bg).
function ns.UI.Factory:CreateDataRow(parent, yOffset, rowIndex, height)
    local row = NewObj("frame", parent)
    row:SetHeight(height)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:Show()
    self:ApplyRowBackground(row, rowIndex)
    return row, yOffset + height
end
ns.QUEST_CATEGORIES = { { key = "weekly" }, { key = "daily" }, { key = "events" } }
ns.CATEGORY_DISPLAY = {
    weekly = { name = function() return "Weekly" end, color = { 1, 0.5, 0 }, atlas = "a-weekly" },
    daily = { name = function() return "Daily" end, color = { 0.2, 0.8, 1 }, atlas = "a-daily" },
    events = { name = function() return "Events" end, color = { 0.8, 0.2, 1 } },
}

local function LoadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring((src:gsub("^\239\187\191", "")), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end
LoadFile("Modules/Constants.lua")
LoadFile("Modules/UI/SectionPool.lua")
LoadFile("Modules/UI/PlansUI_Browse.lua")
LoadFile("Modules/UI/PlansUI.lua")

-- ---------- Weekly Progress driver ----------
local removed, configured = {}, {}
WN.IsActivePlanComplete = function() return false end
WN.RemovePlan = function(_, id) removed[#removed + 1] = id end
WN.ShowWeeklyProgressPlanDialog = function(_, plan) configured[#configured + 1] = plan end

local function Quest(id, title, extra)
    local q = { questID = id, title = title, zone = "Zone" .. tostring(id) }
    for k, v in pairs(extra or {}) do q[k] = v end
    return q
end
local function PlanData(id, name, weeklyQuests)
    return { id = id, type = "daily_quests", contentType = "midnight", characterName = name,
        characterRealm = "Realm", characterClass = "MAGE",
        questTypes = { weekly = true, daily = true, events = true },
        quests = { weekly = weeklyQuests, daily = { Quest(301, "Daily A", { timeLeft = 90 }) }, events = {} } }
end
local function FullWeekly()
    return {
        Quest(101, "Weekly A", { objectives = {
            { text = "Kill", finished = true, numFulfilled = 5, numRequired = 5 },
            { text = "Loot", finished = false, numFulfilled = 1, numRequired = 3 } } }),
        Quest(102, "Weekly B", { isComplete = true }),
        Quest(103, "Weekly C", { isSubQuest = true, isLocked = true }),
    }
end

local function NewMainFrame()
    local sc = NewObj("frame", nil)
    return { scrollChild = sc, currentTab = "plans", _plansCategoryBar = {}, _plansContentWidth = 600,
        _plansScrollBodyStartY = 8, IsShown = function() return true end }
end
ns._sessionPlansCategory = "daily_tasks"
for _, plan in ipairs({ "weekly_char_11", "weekly_char_12", "dq_11_weekly", "dq_11_daily", "dq_11_events", "dq_12_weekly" }) do
    expanded[plan] = true
end

local function Paint(mf)
    WN.UI = { mainFrame = mf }
    return WN:RefreshPlansCategoryBodyOnly()
end
local function Snapshot() return counts.frames, counts.textures, counts.fontstrings end

print("Phase 1: An unchanged repaint creates no frame, texture or FontString")
local mf = NewMainFrame()
local sc = mf.scrollChild
WN.db.global.plans = { PlanData(11, "Alpha", FullWeekly()), PlanData(12, "Beta", FullWeekly()) }
assert_eq(Paint(mf), true, "first paint runs")
local firstSig = Sig(sc)
local charWrap1
for i = 1, #sc._children do
    local c = sc._children[i]
    if c._shown and c._wnSectionPooled == true and not charWrap1 then charWrap1 = c end
end
assert_eq(charWrap1 ~= nil, true, "character wrap is a pooled section frame")
local stray = NewObj("frame", sc)          -- real garbage left on the scroll child by someone else
local f0, t0, s0 = Snapshot()
local parentCalls = charWrap1 and charWrap1._setParentCalls or 0
Paint(mf)
local f1, t1, s1 = Snapshot()
assert_eq(f1 - f0, 0, "repaint creates no frames")
assert_eq(t1 - t0, 0, "repaint creates no textures")
assert_eq(s1 - s0, 0, "repaint creates no FontStrings")
assert_eq(Sig(sc), firstSig, "repaint paints the same tree")
assert_eq(charWrap1 and charWrap1._setParentCalls or -1, parentCalls, "teardown keeps the pooled wrap in place (never parked)")
assert_eq(charWrap1 and charWrap1:GetParent() == sc and charWrap1._shown, true, "pooled wrap re-bound and shown")
assert_eq(stray._wnDiscarded, true, "teardown still discards real garbage")
assert_eq(stray:GetParent(), ns.UI_RecycleBin, "garbage parked in the recycle bin")

print("Phase 2: A changed shape re-binds rows and matches a fresh build")
local function ShrunkWeekly()
    return {
        Quest(102, "Weekly B2", { objectives = { { text = "Only", finished = false, numFulfilled = 0, numRequired = 1 } } }),
        Quest(nil, "No ID quest"),
    }
end
WN.db.global.plans = { PlanData(11, "Alpha", ShrunkWeekly()), PlanData(12, "Beta", {}) }
Paint(mf)
local reusedSig = Sig(sc)
local freshMf = NewMainFrame()
Paint(freshMf)
assert_eq(reusedSig, Sig(freshMf.scrollChild), "re-bound paint equals a fresh paint (rows, objectives, empty rows)")
WN.UI = { mainFrame = mf }

-- Find quest rows of plan 11 / weekly via the pooled section body.
local pool = sc._wnSectionPool
local weeklyBody = pool and pool.frames["pln:cbody:11:weekly"]
local rows = weeklyBody and weeklyBody._wnPlnRows or {}
local visibleRows = 0
for i = 1, #rows do if rows[i]._shown then visibleRows = visibleRows + 1 end end
assert_eq(visibleRows, 2, "rows beyond the quest count are hidden")
assert_eq(rows[2] and rows[2]._scripts.OnMouseDown, nil, "row re-bound to a quest without ID drops the Wowhead click")
if rows[1] then
    rows[1]._scripts.OnEnter(rows[1])
    assert_eq(tooltipShown and tooltipShown.title, "Weekly B2", "tooltip shows the quest bound this paint")
end

print("Phase 3: Header controls act on the plan bound this paint")
local hdr = pool and pool.frames["pln:hdr:12"]
if hdr then
    local removeBtn = hdr._wnPlnRemoveBtn
    local configBtn = hdr._wnPlnConfigBtn
    if removeBtn then removeBtn._scripts.OnClick(removeBtn) end
    if configBtn then configBtn._scripts.OnClick(configBtn) end
end
assert_eq(removed[#removed], 12, "remove button removes plan 12")
assert_eq(configured[#configured] and configured[#configured].id, 12, "configure button opens plan 12")
local catHdr = pool and pool.frames["pln:chdr:11:daily"]
if catHdr then catHdr._wnCollVisualOpts.persistToggle(false) end
assert_eq(expanded["dq_11_daily"], false, "category collapse persists in expandedGroups")

-- ---------- Browse grid (C8) ----------
print("Phase 4: Scrolling binds only the cards entering the window")
local renders = 0
local realRender = WN.RenderPlansBrowseUnifiedRow
WN.RenderPlansBrowseUnifiedRow = function(_, host, card, item, category, i)
    renders = renders + 1
    card = card or NewObj("frame", host)
    card._boundItem = item
    return card
end
ns.PlansUI_GetCurrentCategory = function() return "mount" end
local host = NewObj("frame", nil)
local scrollPos = 0
local gridMf = { scrollChild = NewObj("frame", nil), currentTab = "plans", IsShown = function() return true end,
    scroll = { GetVerticalScroll = function() return scrollPos end, GetHeight = function() return 300 end } }
WN.UI = { mainFrame = gridMf }
local results = {}
for i = 1, 40 do results[i] = { id = i, name = "Item" .. i } end
local st = ns._wnBrowseGridState
st.host, st.results, st.count, st.cols, st.cardWidth, st.colStride = host, results, 40, 2, 200, 210
st.stride, st.totalRows, st.top, st.category, st.active = 100, 20, 0, "mount", true
st._firstRow, st._lastRow = nil, nil

local function CheckWindow(label)
    local seen, ok = {}, true
    for _, card in ipairs(ns._wnBrowseRowPool) do
        if card._shown then
            local item = card._boundItem
            if not item or seen[item] then ok = false end
            if item then seen[item] = true end
        end
    end
    local first = (st._firstRow or 0) * 2 + 1
    local last = math.min(40, ((st._lastRow or 0) + 1) * 2)
    for i = first, last do if not seen[results[i]] then ok = false end end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    assert_eq(ok and n == last - first + 1, true, label .. ": every visible index shows its own item once")
end

ns.UI_UpdateBrowseGridVisibleRange(true)
assert_eq(renders, 12, "forced first pass binds the 12 visible cards")
CheckWindow("initial window")
renders = 0
scrollPos = 100
ns.UI_UpdateBrowseGridVisibleRange(false)
assert_eq(renders, 2, "scrolling one row binds only the entering row")
CheckWindow("after one-row scroll")
renders = 0
scrollPos = 500
ns.UI_UpdateBrowseGridVisibleRange(false)
assert_eq(renders, 8, "scrolling four rows binds only the four entering rows")
CheckWindow("after four-row scroll")
renders = 0
ns.UI_UpdateBrowseGridVisibleRange(true)
assert_eq(renders, 16, "forced pass (planned-state flip) rebinds every visible card")

print("Phase 5: A card rebind reuses its tables and one header handler")
WN.RenderPlansBrowseUnifiedRow = realRender
WN.IsMountPlanned = function() return false end
WN.ParseMultipleSources = function() return {} end
WN.ShouldShowTryCountInUI = function() return true end
WN.GetTryCount = function() return 3 end
local popups = {}
ns.UI_ShowTryCountPopup = function(cat, id, name) popups[#popups + 1] = cat .. ":" .. id .. ":" .. name end
ns.UI_PlanCardFactory = { CreateAddButton = function(parent) return NewObj("frame", parent) end }
ns.UI_ApplyVisuals = nil
ns.UI_RebindTodoBrowseRow = function(row, _, data) row.data = data end
ns.UI_CreateExpandableRow = function(parent, _, _, data)
    local row = NewObj("frame", parent)
    row.headerFrame = NewObj("frame", row)
    row.data = data
    return row
end
local tryTypes = { mount = true }
local itemA = { id = 1, name = "Alpha Mount" }
local itemB = { id = 2, name = "Beta Mount" }
local card = WN:RenderPlansBrowseUnifiedRow(host, nil, itemA, "mount", 1, 200, 80, nil, {}, tryTypes)
local data1, ctx1, ctrl1 = card and card.data, card and card._browseCtx, card and card._todoActionControls
local handler1 = card and card.headerFrame._scripts.OnMouseDown
WN:RenderPlansBrowseUnifiedRow(host, card, itemB, "mount", 2, 200, 80, nil, {}, tryTypes)
assert_eq(card and card.data == data1, true, "row data table reused across rebinds")
assert_eq(card and card._browseCtx == ctx1, true, "context table reused across rebinds")
assert_eq(card and card._todoActionControls == ctrl1, true, "action control list reused across rebinds")
assert_eq(card and card.data.title, "Beta Mount", "row data carries the new item")
local card2 = WN:RenderPlansBrowseUnifiedRow(host, nil, itemA, "mount", 1, 200, 80, nil, {}, tryTypes)
local handler = card and card.headerFrame._scripts.OnMouseDown
assert_eq(handler ~= nil and handler == handler1 and handler == (card2 and card2.headerFrame._scripts.OnMouseDown), true,
    "one shared header click handler for every card")
if handler then handler(card.headerFrame, "RightButton") end
assert_eq(popups[#popups], "mount:2:Beta Mount", "right-click opens the try popup of the item bound now")

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Plans pooling suite failed with " .. failed .. " failure(s).")
end
print("Plans pooling suite: ALL TESTS PASSED.")
