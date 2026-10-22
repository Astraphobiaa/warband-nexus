#!/usr/bin/env lua
--[[
    Regression test: tab refreshes do only the work the change needs (2026-10-22 audit).

      A5  a bag / item update on Items > Bags / Bank ran a full PopulateContent of the tab; it now
          refreshes the stats line + results list in place (TryRefreshItemsResultsForBagUpdate), and
          only the Storage-tree sub-tabs (Warband, Guild) keep the full populate.
      A4  every Currency draw walked every currency x every tracked character (AggregateCurrencies)
          even with unchanged data; the aggregate is now cached on the read-model identity.
      C5  every currency row of every collapsed section was built on each draw, each copying the
          whole read-model entry (per-character quantity map included) with pairs; collapsed bodies
          are now built on first expand and the row table carries only the fields the row reads.
      A3  every WN_PLANS_UPDATED (criteria_update ~1/s, try_count_set per kill) rebuilt the To-Do
          tracker's vault / daily cards; messages are coalesced (0.3s) and the cards are re-shown
          when only neutral actions arrived.

    Loads the shipped UI_RefreshRouter.lua, ItemsUI.lua, CurrencyUI.lua (+ SectionPool.lua) and
    PlansTrackerWindow.lua under wow_stub.lua with fake frames.
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
local function NewFrame(parent)
    local f = setmetatable({ _children = {}, _shown = true, _h = 0, _w = 0, _scripts = {} }, FrameMT)
    if parent then f:SetParent(parent) end
    return f
end
function Frame:SetParent(p)
    local old = self._parent
    if old then
        for i = #old._children, 1, -1 do if old._children[i] == self then table.remove(old._children, i) end end
    end
    self._parent = p
    if p then p._children[#p._children + 1] = self end
end
function Frame:GetParent() return self._parent end
function Frame:GetChildren() return unpack(self._children) end
function Frame:GetRegions() return end
function Frame:Hide() self._shown = false end
function Frame:Show() self._shown = true end
function Frame:IsShown() return self._shown end
function Frame:SetHeight(h) self._h = h end
function Frame:GetHeight() return self._h end
function Frame:SetWidth(w) self._w = w end
function Frame:GetWidth() return self._w end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:SetScript(name, fn) self._scripts[name] = fn end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:GetObjectType() return "Frame" end
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:GetTop() return nil end

local function Constants()
    local ns = {}
    LoadFile("Modules/Constants.lua", ns)
    return ns.Constants
end

-- =====================================================================================
print("Phase 1 (A5): router sends Bags / Bank updates to the in-place results refresh")
do
    local ns = { Constants = Constants() }
    local handlers = {}
    local WN = {
        RegisterMessage = function(_, msg, fn) handlers[msg] = fn end,
        SendMessage = noop,
        UpdateTabCountBadges = noop,
    }
    local inPlaceCalls, inPlaceResult = 0, true
    WN.TryRefreshItemsResultsForBagUpdate = function()
        inPlaceCalls = inPlaceCalls + 1
        return inPlaceResult
    end
    local populates, skipPopulates = 0, 0
    local f = NewFrame(nil)
    f.currentTab = "items"
    local sub = "inventory"
    ns.UI_GetItemsSubTab = function() return sub end
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
    local E = ns.Constants.EVENTS
    local bags, items = handlers[E.BAGS_UPDATED], handlers[E.ITEMS_UPDATED]
    assert_eq(type(bags) == "function" and type(items) == "function", true, "BAGS_UPDATED / ITEMS_UPDATED listeners registered")

    bags(E.BAGS_UPDATED); items(E.ITEMS_UPDATED); bags(E.BAGS_UPDATED)
    stub.Advance(0.5)
    assert_eq(inPlaceCalls, 1, "Bags: ITEMS + BAGS burst -> one in-place results refresh")
    assert_eq(populates + skipPopulates, 0, "Bags: no full PopulateContent")

    sub = "personal"
    bags(E.BAGS_UPDATED)
    stub.Advance(0.5)
    assert_eq(inPlaceCalls, 2, "Bank: in-place results refresh")
    assert_eq(populates + skipPopulates, 0, "Bank: no full PopulateContent")

    inPlaceResult = false
    bags(E.BAGS_UPDATED)
    stub.Advance(0.5)
    assert_eq(populates, 1, "in-place path rejected (loading / chrome missing) -> full PopulateContent")

    inPlaceResult = true
    sub = "guild"
    local before = inPlaceCalls
    bags(E.BAGS_UPDATED)
    stub.Advance(0.5)
    assert_eq(inPlaceCalls, before, "Guild (Storage tree): not routed in place")
    assert_eq(populates, 2, "Guild: full PopulateContent kept")

    sub = "warband"
    bags(E.BAGS_UPDATED)
    stub.Advance(0.5)
    assert_eq(skipPopulates, 1, "Warband: full PopulateContent (skip cooldown) kept")
end

-- =====================================================================================
print("Phase 2 (A5): TryRefreshItemsResultsForBagUpdate refreshes stats + results only when safe")
do
    local ns = { UI = { Factory = {} }, Constants = Constants() }
    local WN = { db = { profile = {}, global = {} }, RegisterMessage = noop }
    ns.WarbandNexus = WN
    ns.SearchStateManager = { UpdateResults = noop, GetQuery = function() return "" end }
    ns.UI_GetExpandedGroups = function() return {} end
    ns.StorageSectionLayout = {}
    local sub = "inventory"
    ns.UI_GetItemsSubTab = function() return sub end
    local moduleOn, tracked = true, true
    ns.Utilities = {
        IsModuleEnabled = function() return moduleOn end,
        GetLiveCharacterMoneyCopper = function() return 12345 end,
    }
    ns.CharacterService = { IsCharacterTracked = function() return tracked end }
    ns.UI_FormatMoney = function(c) return "gold:" .. tostring(c) end
    ns.UI_FormatNumber = function(n) return tostring(n) end
    LoadFile("Modules/UI/ItemsUI.lua", ns)

    local redraws = 0
    WN.RedrawItemsResultsOnly = function() redraws = redraws + 1 end
    WN.GetBankStatistics = function() return {} end
    WN.GetInventoryItems = function() return { { itemID = 1 }, { itemID = 2 } } end
    WN.db.char = { bags = { usedSlots = 4, totalSlots = 10, lastScan = 0 } }
    local mf = NewFrame(nil)
    mf.currentTab = "items"
    local sc = NewFrame(mf)
    mf.scrollChild = sc
    local rc = NewFrame(sc)
    sc.resultsContainer = rc
    sc._itemsStatsText = NewFrame(sc)
    sc._itemsGoldDisplay = NewFrame(sc)
    WN.UI = { mainFrame = mf }

    local try = WN.TryRefreshItemsResultsForBagUpdate
    assert_eq(type(try), "function", "WarbandNexus:TryRefreshItemsResultsForBagUpdate exists")
    if type(try) == "function" then
        assert_eq(try(WN), false, "results not painted by DrawItemList yet -> rejected")
        sc._wnItemsResultsPainted = true
        local ok, res = pcall(try, WN)
        assert_eq(ok and res, true, "Bags with painted results -> handled in place" .. (ok and "" or (": " .. tostring(res))))
        assert_eq(redraws, 1, "results list redrawn once")
        assert_eq(sc._itemsStatsText._text ~= nil, true, "stats line rewritten")
        assert_eq(sc._itemsGoldDisplay._text, "gold:12345", "Bags gold line rewritten")

        sub = "guild"
        assert_eq(try(WN), false, "Guild (Storage tree) -> rejected")
        sub = "warband"
        assert_eq(try(WN), false, "Warband (Storage tree) -> rejected")
        sub = "personal"
        ns.ItemsLoadingState = { isLoading = true }
        assert_eq(try(WN), false, "items loading -> rejected")
        ns.ItemsLoadingState = nil
        tracked = false
        assert_eq(try(WN), false, "untracked character (banner) -> rejected")
        tracked = true
        moduleOn = false
        assert_eq(try(WN), false, "Items module disabled -> rejected")
        moduleOn = true
        mf.currentTab = "currency"
        assert_eq(try(WN), false, "other tab -> rejected")
        assert_eq(redraws, 1, "no redraw on any rejected call")
    end
end

-- =====================================================================================
print("Phase 3 (A4 / C5): currency aggregate cache + collapsed sections build no rows")
local currencyDraw
do
    local ns = { UI = {}, Constants = Constants() }
    local WN = { db = { profile = { currencyShowZero = true, currencyExpanded = {} },
                        global = { currencyData = {} } }, RegisterMessage = noop }
    ns.WarbandNexus = WN
    ns.UI_LIST_ROW_COLUMNS = { textGap = 4, currency = { nameLeft = 30, amountRightPad = 8 } }
    ns.UI_LAYOUT = {}
    ns.UI_COLORS = { accent = { 1, 1, 1 }, red = { 1, 0, 0 }, green = { 0, 1, 0 } }
    ns.FontManager = { CreateFontString = function(_, parent) return NewFrame(parent) end }
    ns.SearchStateManager = { GetQuery = function() return "" end, UpdateResults = noop }
    ns.SearchResultsRenderer = { RenderEmptyState = function() return 10 end }
    ns.UI_FormatNumber = function(n) return tostring(n) end
    ns.UI_SetTextColorRole = noop
    ns.UI_GetCharKey = function(c) return c.key end
    ns.UI_GetSubsidiaryCharKey = function() return "A" end
    ns.Utilities = {}
    ns.UI_RecycleBin = NewFrame(nil)
    ns.UI.Factory = {
        CreateContainer = function(_, parent) return NewFrame(parent) end,
        ApplyRowBackground = noop,
    }
    ns.UI_ChainSectionFrameBelow = noop
    ns.UI_HideEmptyStateCard = noop
    ns.UI_ReleaseAllPooledChildren = noop
    local rowsBuilt = 0
    ns.UI_AcquireCurrencyRow = function(parent)
        rowsBuilt = rowsBuilt + 1
        local row = NewFrame(parent)
        row.icon, row.nameText, row.amountText = NewFrame(row), NewFrame(row), NewFrame(row)
        return row
    end
    ns.UI_ReleaseCurrencyRowsFromSubtree = noop
    ns.UI_CreateNoticeFrame = function(parent) return NewFrame(parent) end
    local headers = {}
    ns.UI_CreateCollapsibleHeader = function(wrap, text, key, isExpanded, onToggle, _icon, _atlas, _i, _n, vo)
        local h = (vo and vo.reuseHeader) or NewFrame(wrap)
        h._key, h._onToggle, h._vo = key, onToggle, vo
        headers[key] = h
        return h, nil, nil
    end
    _G.RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 1 } }
    LoadFile("Modules/UI/SectionPool.lua", ns)
    LoadFile("Modules/UI/CurrencyUI.lua", ns)

    -- Read model: chars reads are counted through a proxy (one walk = #currencies x #characters).
    local charsReads = 0
    local function entry(name, qtyA, qtyB, accountWide)
        local qty = { A = qtyA, B = qtyB }
        local chars = setmetatable({}, { __index = function(_, k)
            charsReads = charsReads + 1
            return qty[k]
        end })
        local e = { name = name, icon = 1, maxQuantity = 0, isAccountWide = accountWide,
                    isAccountTransferable = accountWide, chars = chars }
        if accountWide then e.value = qtyA end
        return e
    end
    local model = { [1] = entry("Alpha", 5, 3, false), [2] = entry("Beta", 0, 7, false), [3] = entry("Gamma", 9, 9, true) }
    WN.GetCurrenciesForUI = function() return model end
    WN.db.global.currencyData.headers = {
        { name = "Midnight", depth = 0, currencies = { 1, 2, 3 }, children = {} },
    }
    WN.GetAllCharacters = function()
        return { { key = "A", name = "Ana", realm = "R", classFile = "MAGE" },
                 { key = "B", name = "Bo", realm = "R", classFile = "MAGE" } }
    end
    WN.GetCurrencyData = function() return nil end

    local container = NewFrame(nil)
    local function draw() return WN:DrawCurrencyList(container, 600) end
    currencyDraw = draw

    local ok, err = pcall(draw)
    assert_eq(ok, true, "first draw runs" .. (ok and "" or (": " .. tostring(err))))
    local readsFirst = charsReads
    assert_eq(readsFirst > 0, true, "first draw aggregates (reads per-character quantities)")
    assert_eq(rowsBuilt, 0, "both sections collapsed: no currency row built")

    pcall(draw)
    assert_eq(charsReads, readsFirst, "second draw, unchanged data: aggregate served from cache")
    assert_eq(rowsBuilt, 0, "second draw: still no row built")

    model = { [1] = entry("Alpha", 6, 3, false), [2] = entry("Beta", 0, 7, false), [3] = entry("Gamma", 9, 9, true) }
    local readsBefore = charsReads
    pcall(draw)
    assert_eq(charsReads > readsBefore, true, "new read model (CURRENCY_UPDATED) -> re-aggregated")

    -- Expand the Character-Specific section: its category tree is built now, rows included.
    local sec = headers["currency-char-specific"]
    assert_eq(sec ~= nil, true, "character-specific section header drawn")
    if sec then
        -- SECTION_COLLAPSE_HEADER_HEIGHT falls back to 36 (no UI_LAYOUT override here).
        local wrapH = sec:GetParent() and sec:GetParent():GetHeight()
        assert_eq(wrapH ~= nil and math.abs(wrapH - 36.1) < 1e-6, true, "collapsed section wrap = header height + 0.1")
        local body = sec._vo and sec._vo.animatedContent and sec._vo.animatedContent()
        if body then body:Show() end
        sec._onToggle(true, sec)
        local cat = headers["all-char-Midnight"]
        assert_eq(cat ~= nil, true, "expand: child category header built")
        assert_eq(rowsBuilt, 0, "expand: rows of the still-collapsed category not built")
        if cat then
            local catBody = cat._vo.animatedContent()
            catBody:Show()
            cat._onToggle(true, cat)
            assert_eq(rowsBuilt, 2, "category expand: its 2 rows built")
            local rows = { catBody:GetChildren() }
            local row = rows[1]
            assert_eq(row and row._wnCurrency and row._wnCurrency.chars, nil,
                "row display table does not copy the per-character quantity map")
            assert_eq(row and row._wnCurrency and row._wnCurrency.name ~= nil, true, "row display table has the name")
            cat._onToggle(false, cat)
            cat._onToggle(true, cat)
            assert_eq(rowsBuilt, 2, "re-expand: rows not rebuilt")
        end
    end
end

-- =====================================================================================
print("Phase 4 (A3): tracker coalesces WN_PLANS_UPDATED and re-uses the vault card frame")
do
    local ns = { UI = {}, Constants = Constants() }
    local WN = { db = { profile = {}, global = { plansTracker = { width = 380, height = 420 } } },
                 RegisterMessage = noop }
    ns.WarbandNexus = WN
    ns.FontManager = { CreateFontString = function(_, parent) return NewFrame(parent) end }
    ns.UI_RecycleBin = NewFrame(nil)
    ns.UI.Factory = { CreateContainer = function(_, parent) return NewFrame(parent) end }
    local vaultBuilds = 0
    ns.UI_PlanCardFactory = { CreateWeeklyVaultCard = function() vaultBuilds = vaultBuilds + 1 end }
    ns.UI_MeasureFullWidthPlanCardHeight = function() return 174 end
    local vault = { id = 7, type = "weekly_vault", characterName = "Ana", slots = {} }
    local plans = { vault }
    WN.GetActivePlans = function() return plans end
    WN.IsActivePlanComplete = function() return false end
    LoadFile("Modules/UI/PlansTrackerWindow.lua", ns)

    local frame = NewFrame(nil)
    frame._w, frame._h = 380, 420
    local sc = NewFrame(frame)
    frame.contentScrollChild = sc
    _G.WarbandNexus_PlansTracker = frame
    local PTW = ns.PlansTrackerWindow or {}

    local function paintedVaultCards()
        local n, card = 0, nil
        local kids = { sc:GetChildren() }
        for i = 1, #kids do
            if kids[i]:IsShown() and kids[i] ~= sc._wnTrackerEmptyFrame then n = n + 1; card = kids[i] end
        end
        return n, card
    end

    local ok, err = pcall(PTW.RefreshTheme)
    assert_eq(ok, true, "first paint runs" .. (ok and "" or (": " .. tostring(err))))
    assert_eq(vaultBuilds, 1, "first paint builds the vault card")
    local _, firstCard = paintedVaultCards()

    local schedule = PTW.SchedulePlansUpdatedRefresh
    assert_eq(type(schedule), "function", "WN_PLANS_UPDATED coalescer exposed")
    if type(schedule) ~= "function" then
        -- Pre-fix behaviour: each WN_PLANS_UPDATED ran RefreshTrackerContentImmediate().
        schedule = function() pcall(PTW.RefreshTheme) end
    end
    do
        schedule({ action = "criteria_update" })
        schedule({ action = "try_count_set" })
        schedule({ action = "criteria_update" })
        stub.Advance(0.2)
        assert_eq(vaultBuilds, 1, "burst: nothing painted before the 0.3s window closes")
        stub.Advance(0.2)
        local n, card = paintedVaultCards()
        assert_eq(vaultBuilds, 1, "neutral burst (criteria / try counts) -> vault card not rebuilt")
        assert_eq(n, 1, "one vault card shown")
        assert_eq(card, firstCard, "same vault card frame re-shown")

        schedule({ action = "criteria_update" })
        schedule({ action = "weekly_progress_updated", planID = 7 })
        stub.Advance(0.5)
        n, card = paintedVaultCards()
        assert_eq(vaultBuilds, 2, "vault progress in the window -> card rebuilt once")
        assert_eq(n, 1, "still one vault card shown")
        assert_eq(card ~= firstCard and firstCard:GetParent() == ns.UI_RecycleBin, true, "old card parked")

        plans = {}
        schedule({ action = "removed", planID = 7 })
        stub.Advance(0.5)
        n = paintedVaultCards()
        assert_eq(n, 0, "removed vault plan -> its cached card leaves the list")
    end
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Tab refresh routing suite failed with " .. failed .. " failure(s).")
end
print("Tab refresh routing suite: ALL TESTS PASSED.")
