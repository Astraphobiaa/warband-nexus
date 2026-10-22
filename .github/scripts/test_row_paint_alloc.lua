#!/usr/bin/env lua
--[[
    Regression test: row paints do not allocate per-row closures / tables, and repeated paints do not
    redo work whose result cannot have changed.

    - Row scripts (Items, Storage, Currency, Reputation, Characters): every paint set fresh closures
      (OnEnter / OnLeave / OnMouseUp / OnClick, ~15 per Characters row). Now the paint stores its data
      on the row and installs stable shared handlers; the handlers still act on the latest painted data.
    - ApplyRowBackground (Classic theme): a new dimmed color table per row per paint; now one cached
      table per tier, refreshed when the source tier color changes.
    - GetItemDisplayName (caged pets): resolved the pet name through the API on every paint; now
      successes are cached by item ID and a miss is retried only after a delay.
    - Characters row live-resize layout: a fresh `shown` table per row; now a wiped scratch table.
    - VirtualListModule TakeStaleFrameForSig: a linear scan of the previous visible rows per visible
      row; now a per-paint sig -> frame lookup with the same claim order.

    Loads the shipped files under wow_stub.lua with permissive fake frames.
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

local function ReadFile(rel)
    local fh = assert(io.open(ROOT .. "/" .. rel, "rb"), "missing file: " .. rel)
    local src = fh:read("*a")
    fh:close()
    return (src:gsub("^\239\187\191", ""))
end
local function LoadFile(rel, ns)
    local chunk, err = loadstring(ReadFile(rel), "@" .. rel)
    if not chunk then error("load " .. rel .. ": " .. tostring(err), 0) end
    local ok, rerr = pcall(chunk, "WarbandNexus", ns)
    if not ok then error("run " .. rel .. ": " .. tostring(rerr), 0) end
end

-- Permissive frame: unknown Capitalized methods are no-ops; data fields stay nil; scripts recorded.
local Frame = {}
local NOOP = function() return nil end
Frame.__index = function(t, k)
    local m = rawget(Frame, k)
    if m then return m end
    if type(k) == "string" and k:match("^%u") then return NOOP end  -- shared: no allocation per call
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
function Frame:HasScript() return true end
function Frame:GetChildren() return end
function Frame:GetNumChildren() return 0 end
function Frame:GetStringWidth() return 50 end
function Frame:GetFrameLevel() return 1 end
function Frame:CreateTexture() return Frame.new(self) end
function Frame:CreateFontString() return Frame.new(self) end
function Frame:GetText() return self._text end
function Frame:SetText(t) self._text = t end

-- Snapshot every script handler on a set of frames: "frameName.Script" -> function.
local function SnapshotScripts(frames)
    local out = {}
    for name, f in pairs(frames) do
        if f and f._scripts then
            for script, fn in pairs(f._scripts) do out[name .. "." .. script] = fn end
        end
    end
    return out
end
local function CountChangedHandlers(a, b)
    local changed, total = 0, 0
    for k, fn in pairs(a) do
        total = total + 1
        if b[k] ~= fn then changed = changed + 1 end
    end
    for k in pairs(b) do
        if a[k] == nil then changed = changed + 1 end
    end
    return changed, total
end

-- Search a function's upvalues (recursively) for a local function by name.
local function FindUpvalue(fn, name, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if type(fn) ~= "function" or seen[fn] or depth > 4 then return nil end
    seen[fn] = true
    local i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        if n == name and type(v) == "function" then return v end
        i = i + 1
    end
    i = 1
    while true do
        local n, v = debug.getupvalue(fn, i)
        if not n then break end
        if type(v) == "function" then
            local r = FindUpvalue(v, name, depth + 1, seen)
            if r then return r end
        elseif type(v) == "table" then
            for _, tv in pairs(v) do
                if type(tv) == "function" then
                    local r = FindUpvalue(tv, name, depth + 1, seen)
                    if r then return r end
                end
            end
        end
        i = i + 1
    end
    return nil
end

-- ------------------------------------------------------------------------------------------------
print("Phase 1: VirtualListModule claims stale rows by sig without a linear rescan")
do
    -- Frames whose `_vlm_stale` reads are counted (the old per-row scan read it O(n^2) per paint).
    local staleReads = 0
    local CFrame = {}
    local function cframeNew(parent)
        local store = { _parent = parent, _shown = true, _scripts = {} }
        return setmetatable({}, {
            __index = function(_, k)
                if k == "_vlm_stale" then staleReads = staleReads + 1 end
                local v = store[k]
                if v ~= nil then return v end
                return Frame.__index(store, k)
            end,
            __newindex = store,
        })
    end
    local ns = { DebugPrint = function() end, UI_LAYOUT = {} }
    LoadFile("Modules/UI/VirtualListModule.lua", ns)
    local VLM = ns.VirtualListModule

    local mainFrame = Frame.new(nil)
    mainFrame.scroll = Frame.new(mainFrame)
    mainFrame.scrollChild = Frame.new(mainFrame.scroll)
    mainFrame.scroll._child = mainFrame.scrollChild
    local container = Frame.new(mainFrame.scrollChild)

    local flatList = {}
    for i = 1, 60 do
        -- rows 3 and 4 share a sig: claim order must stay the old scan's (first in old visible order)
        local sig = (i == 4) and "row3" or ("row" .. i)
        flatList[i] = { type = "row", yOffset = (i - 1) * 30, height = 30, data = { id = i }, rowReuseSig = sig }
    end
    local created = 0
    VLM.SetupVirtualList(mainFrame, container, 0, flatList, {
        createRowFn = function() created = created + 1; return cframeNew(container) end,
        populateRowFn = function() end,
        incrementalRowReuse = true,
    })
    container._vlm_incrementalRowReuse = true
    mainFrame._virtualScrollUpdate()

    local function frameBySig()
        local map, order = {}, {}
        local vis = container._virtualVisibleFrames
        for j = 1, #vis do
            local f = vis[j].frame
            order[#order + 1] = f
            map[vis[j].index] = f
        end
        return map, order
    end
    local before, beforeOrder = frameBySig()
    local nVisible = #beforeOrder
    assert_eq(nVisible > 10, true, "a page of rows is visible (" .. nVisible .. ")")

    staleReads = 0
    local createdBefore = created
    mainFrame._vlmScrollPaint = true
    mainFrame._virtualScrollUpdate()
    mainFrame._vlmScrollPaint = nil
    local after = frameBySig()
    local same = 0
    for idx, f in pairs(before) do
        if after[idx] == f then same = same + 1 end
    end
    assert_eq(same, nVisible, "every visible row keeps its frame on a repaint (sig match)")
    assert_eq(created, createdBefore, "no row frame created on a repaint")
    assert_eq(after[3] == before[3] and after[4] == before[4], true,
        "rows sharing a sig are claimed in the previous visible order")
    assert_eq(staleReads <= 3 * nVisible, true,
        string.format("stale-flag reads per paint are linear (%d reads for %d rows)", staleReads, nVisible))

    -- Scrolling: rows that stay visible keep their frames; rows that leave are released.
    mainFrame.scroll:SetVerticalScroll(150)
    mainFrame._vlmScrollPaint = true
    mainFrame._virtualScrollUpdate()
    mainFrame._vlmScrollPaint = nil
    local scrolled = frameBySig()
    local kept = 0
    for idx, f in pairs(scrolled) do
        if before[idx] == f then kept = kept + 1 end
    end
    assert_eq(kept > 0 and scrolled[1] == nil, true, "scrolled paint reuses overlapping rows (" .. kept .. ")")
end

-- ------------------------------------------------------------------------------------------------
print("Phase 2: Classic row background reuses one dimmed color per tier")
do
    local srcEven = { 0.5, 0.5, 0.5, 0.9 }
    local srcOdd = { 0.25, 0.25, 0.25, 1 }
    local ns = {
        UI = { Factory = {} },
        FontManager = {},
        UI_ResolveSurfaceTierColor = function(tier) return tier == "rowEven" and srcEven or srcOdd end,
        UI_IsClassicMode = function() return true end,
    }
    ns.WarbandNexus = {}
    LoadFile("Modules/UI/SharedWidgets_RowPool.lua", ns)
    local row = Frame.new(nil)
    local applied
    row.bg = Frame.new(row)
    function row.bg:SetColorTexture(r, g, b, a) applied = { r, g, b, a } end
    ns.UI.Factory:ApplyRowBackground(row, 2)
    local first = row.bgColor
    assert_eq(math.abs(applied[4] - 0.9 * 0.22) < 1e-9 and applied[1] == 0.5, true, "dimmed alpha applied (classic)")
    ns.UI.Factory:ApplyRowBackground(row, 2)
    assert_eq(row.bgColor, first, "second paint of the same tier reuses the cached color table")
    ns.UI.Factory:ApplyRowBackground(row, 1)
    assert_eq(row.bgColor ~= first and math.abs(applied[4] - 0.22) < 1e-9, true, "odd tier has its own dimmed color")
    srcEven[1] = 0.8                                  -- theme refresh rewrote the tier color
    ns.UI.Factory:ApplyRowBackground(row, 2)
    assert_eq(applied[1], 0.8, "a changed source tier color is picked up")
    srcEven = { 0.1, 0.2, 0.3, 1 }                    -- theme refresh swapped the tier table
    ns.UI.Factory:ApplyRowBackground(row, 2)
    assert_eq(applied[3] == 0.3 and math.abs(applied[4] - 0.22) < 1e-9, true, "a swapped source tier table is picked up")
end

-- ------------------------------------------------------------------------------------------------
print("Phase 3: Caged pet display names resolve once, misses retry later")
do
    local ns = {}
    ns.L = {}
    LoadFile("Modules/Utilities.lua", ns)
    local U = ns.Utilities
    local petCalls, tipCalls = 0, 0
    local petNames = { [1001] = "Lil' Tester" }
    _G.C_PetJournal.GetPetInfoByItemID = function(id) petCalls = petCalls + 1; return petNames[id] end
    _G.C_TooltipInfo = { GetItemByID = function() tipCalls = tipCalls + 1; return nil end }

    local n1 = U:GetItemDisplayName(1001, "Pet Cage", 17)
    local n2 = U:GetItemDisplayName(1001, "Pet Cage", 17)
    local n3 = U:GetItemDisplayName(1001, "Pet Cage", 17)
    assert_eq(n1 == "Lil' Tester" and n2 == n1 and n3 == n1, true, "pet name shown on every paint")
    assert_eq(petCalls, 1, "pet API called once for three paints of the same cage")
    assert_eq(U:GetItemDisplayName(1001, "Bread", 0), "Bread", "non-pet items keep their own name")

    petCalls, tipCalls = 0, 0
    assert_eq(U:GetItemDisplayName(2002, "Pet Cage", 17), "Pet Cage", "unresolved cage falls back to the item name")
    U:GetItemDisplayName(2002, "Pet Cage", 17)
    assert_eq(petCalls + tipCalls, 2, "a miss is not re-resolved on the next paint (1 pet + 1 tooltip call)")
    stub.Advance(10)
    petNames[2002] = "Late Loader"
    assert_eq(U:GetItemDisplayName(2002, "Pet Cage", 17), "Late Loader", "a miss is retried later and then resolves")
    petCalls = 0
    U:GetItemDisplayName(2002, "Pet Cage", 17)
    assert_eq(petCalls, 0, "the late success is cached")

    petNames[3003] = stub.MarkSecret("secret pet")
    assert_eq(U:GetItemDisplayName(3003, "Pet Cage", 17), "Pet Cage", "a secret pet name is never shown or cached")
end

-- ------------------------------------------------------------------------------------------------
print("Phase 4: Items rows keep stable scripts that act on the latest painted item")
do
    local ns = { UI = { Factory = {} } }
    local tips, links = {}, {}
    ns.UI_ShowTooltip = function(_, data) tips[#tips + 1] = data end
    ns.UI_HideTooltip = function() end
    ns.UI_NormalizeColonLabelSpacing = function(s) return s end
    ns.UI_FormatNumber = function(n) return tostring(n) end
    ns.UI_GetQualityHex = function() return "ffffff" end
    local WN = { db = { profile = {}, global = {} }, RegisterMessage = function() end }
    ns.WarbandNexus = WN
    LoadFile("Modules/Constants.lua", ns)
    ns.SearchStateManager = { UpdateResults = function() end, GetQuery = function() return "" end }
    ns.UI_GetExpandedGroups = function() return {} end
    ns.StorageSectionLayout = {}
    ns.UI_SectionPool = { BeginPass = function() end }
    ns.UI_SetTextColorRole = function() end
    ns.UI.Factory.ApplyRowBackground = function() end
    local captured
    ns.VirtualListModule = {
        SetupVirtualList = function(_, _, _, _, opts) captured = opts; error("captured", 0) end,
    }
    LoadFile("Modules/UI/ItemsUI.lua", ns)
    WN.GetItemDisplayName = function(_, _, name) return name end
    WN.UI = { mainFrame = Frame.new(nil) }
    WN.itemsExpandAllActive = true
    local items = { { itemID = 11, stackCount = 2, name = "Apple", link = "|Hitem:11|h[Apple]|h", actualBagID = 0, slotIndex = 1 },
                    { itemID = 22, stackCount = 1, name = "Bread", link = "|Hitem:22|h[Bread]|h", actualBagID = 0, slotIndex = 2 } }
    WN.GetInventoryItems = function() return items end
    local parent = Frame.new(Frame.new(nil))
    pcall(WN.DrawItemsResults, WN, parent, 0, 400, "inventory", "")
    assert_eq(type(captured and captured.populateRowFn), "function", "Items draw reached the virtual list setup")
    if captured then
        local row = Frame.new(parent)
        row.qtyText, row.icon, row.nameText, row.locationText = Frame.new(row), Frame.new(row), Frame.new(row), Frame.new(row)
        captured.populateRowFn(row, { data = items[1], rowIdx = 1 }, 1)
        local s1 = SnapshotScripts({ row = row })
        captured.populateRowFn(row, { data = items[2], rowIdx = 2 }, 2)
        local s2 = SnapshotScripts({ row = row })
        local changed, total = CountChangedHandlers(s1, s2)
        assert_eq(total >= 3 and changed == 0, true,
            string.format("repaint keeps the same %d script functions (%d replaced)", total, changed))
        row:GetScript("OnEnter")(row)
        assert_eq(tips[#tips] and tips[#tips].itemID, 22, "tooltip shows the latest painted item")
        _G.IsShiftKeyDown = function() return true end
        _G.ChatEdit_InsertLink = function(l) links[#links + 1] = l end
        row:GetScript("OnMouseUp")(row, "LeftButton")
        assert_eq(links[1], "|Hitem:22|h[Bread]|h", "shift-click links the latest painted item")
        row:GetScript("OnMouseUp")(row, "RightButton")
        assert_eq(#links, 1, "other buttons do not link")
        stub.MarkSecret(items[2].link)
        row:GetScript("OnMouseUp")(row, "LeftButton")
        assert_eq(#links, 1, "a secret link is not inserted")
        stub.ClearSecrets()
        _G.IsShiftKeyDown, _G.ChatEdit_InsertLink = nil, nil
    end

    print("Phase 4b: Storage tree rows keep stable scripts")
    LoadFile("Modules/UI/ItemsUI_StorageDraw.lua", ns)
    local Populate = FindUpvalue(WN.DrawStorageResults, "ItemsUI_PopulateStorageRowDirect")
    assert_eq(type(Populate), "function", "ItemsUI_PopulateStorageRowDirect reachable")
    if Populate then
        local row = Frame.new(parent)
        row.qtyText, row.icon, row.nameText, row.locationText = Frame.new(row), Frame.new(row), Frame.new(row), Frame.new(row)
        local ok1, e1 = pcall(Populate, row, { itemID = 33, name = "Cheese", itemLink = "|Hitem:33|h[Cheese]|h" }, 1, 400, "Bag 1")
        local s1 = SnapshotScripts({ row = row })
        local ok2, e2 = pcall(Populate, row, { itemID = 44, name = "Dates", itemLink = "|Hitem:44|h[Dates]|h" }, 2, 400, "Bag 2")
        local s2 = SnapshotScripts({ row = row })
        assert_eq(ok1 and ok2, true, "storage row paints (" .. tostring(not ok1 and e1 or not ok2 and e2 or "") .. ")")
        local changed, total = CountChangedHandlers(s1, s2)
        assert_eq(total >= 2 and changed == 0, true,
            string.format("repaint keeps the same %d script functions (%d replaced)", total, changed))
        local onEnter = row:GetScript("OnEnter")
        if onEnter then onEnter(row) end
        local t = tips[#tips]
        assert_eq(t and t.itemID == 44 and t.itemLink == "|Hitem:44|h[Dates]|h", true, "tooltip shows the latest painted item")
    end
end

-- Shared ns for the tab modules (Currency / Reputation): enough layout + widget stubs to load and paint.
local function TabNS()
    local tips = {}
    -- Factory: any widget constructor returns a permissive frame.
    local Factory = setmetatable({}, { __index = function() return function(_, parent) return Frame.new(parent) end end })
    local ns = { UI = { Factory = Factory } }
    ns.FontManager = Factory
    ns.WarbandNexus = { db = { profile = {}, global = {} }, RegisterMessage = function() end }
    ns.UI_LIST_ROW_COLUMNS = { currency = { nameLeft = 10, amountRightPad = 8 }, textGap = 6 }
    ns.UI_TableKit = { ResolveWidths = function(cols, _, w, o) for i = 1, #cols do w[i] = cols[i].width; o[i] = 0 end end }
    ns.UI_LAYOUT = { TABLE = { CELL_PAD_X = 4, COL_GAP = 4, ROW_H = { standard = 30 } } }
    ns.UI_FormatNumber = function(n) return tostring(n) end
    local rgba = { 0.5, 0.5, 0.5, 1 }
    ns.UI_COLORS = { accent = rgba, bg = rgba, border = rgba, borderLight = rgba, gold = rgba, green = rgba,
        red = rgba, surfaceRowOdd = rgba }
    ns.UI_ShowTooltip = function(_, data) tips[#tips + 1] = data end
    ns.UI_HideTooltip = function() end
    ns.UI_SetTextColorRole = function() end
    ns.UI_CreateCollapseExpandControl = function(parent) return Frame.new(parent) end
    ns.UI_CollapseExpandSetState = function() end
    ns.UI.Factory.ApplyRowBackground = function() end
    LoadFile("Modules/Constants.lua", ns)
    return ns, tips
end

-- ------------------------------------------------------------------------------------------------
print("Phase 5: Currency rows keep stable scripts")
do
    local ns, tips = TabNS()
    LoadFile("Modules/UI/CurrencyUI.lua", ns)
    local Populate = FindUpvalue(ns.WarbandNexus.DrawCurrencyList, "PopulateCurrencyRowFrame")
    assert_eq(type(Populate), "function", "PopulateCurrencyRowFrame reachable")
    if Populate then
        local row = Frame.new(nil)
        row.nameText, row.amountText, row.icon = Frame.new(row), Frame.new(row), Frame.new(row)
        local ok1, e1 = pcall(Populate, row, { name = "Valor", quantity = 5, maxQuantity = 0, viewCharKey = "A" }, 101, 1, 500, true)
        local s1 = SnapshotScripts({ row = row })
        local ok2, e2 = pcall(Populate, row, { name = "Honor", quantity = 7, maxQuantity = 0, viewCharKey = "B" }, 202, 2, 500, true)
        local s2 = SnapshotScripts({ row = row })
        assert_eq(ok1 and ok2, true, "currency row paints (" .. tostring(not ok1 and e1 or not ok2 and e2 or "") .. ")")
        local changed, total = CountChangedHandlers(s1, s2)
        assert_eq(total >= 2 and changed == 0, true,
            string.format("repaint keeps the same %d script functions (%d replaced)", total, changed))
        local onEnter = row:GetScript("OnEnter")
        if onEnter then onEnter(row) end
        local t = tips[#tips]
        assert_eq(t and t.currencyID == 202 and t.charKey == "B", true, "tooltip shows the latest painted currency")
    end
end

-- ------------------------------------------------------------------------------------------------
print("Phase 6: Reputation rows keep stable scripts")
do
    local ns, tips = TabNS()
    LoadFile("Modules/UI/ReputationUI.lua", ns)
    local Populate = FindUpvalue(ns.WarbandNexus.DrawReputationList, "PopulateReputationRow")
    assert_eq(type(Populate), "function", "PopulateReputationRow reachable")
    if Populate then
        local toggles = {}
        local function entry(id, name)
            return { data = { name = name, standing = { name = "Friendly" } }, factionID = id, rowIdx = 1, rowWidth = 800,
                subfactions = { {} }, IsExpanded = function() return false end,
                ToggleExpand = function(key, expanded) toggles[#toggles + 1] = key .. "=" .. tostring(expanded) end }
        end
        local row = Frame.new(nil)
        local ok1, e1 = pcall(Populate, row, entry(5, "Five"))
        local s1 = SnapshotScripts({ row = row, collapse = row.collapseBtn })
        local ok2, e2 = pcall(Populate, row, entry(6, "Six"))
        local s2 = SnapshotScripts({ row = row, collapse = row.collapseBtn })
        assert_eq(ok1 and ok2, true, "reputation row paints (" .. tostring(not ok1 and e1 or not ok2 and e2 or "") .. ")")
        local changed, total = CountChangedHandlers(s1, s2)
        assert_eq(total >= 4 and changed == 0, true,
            string.format("repaint keeps the same %d script functions (%d replaced)", total, changed))
        local onEnter = row:GetScript("OnEnter")
        if onEnter then onEnter(row) end
        assert_eq(tips[#tips] and tips[#tips].title, "Six", "tooltip shows the latest painted faction")
        local click = row.collapseBtn and row.collapseBtn:GetScript("OnClick")
        if click then click(row.collapseBtn) end
        local rowClick = row:GetScript("OnClick")
        if rowClick then rowClick(row) end
        assert_eq(table.concat(toggles, ","), "rep-subfactions-6=true,rep-subfactions-6=false",
            "collapse button and row click toggle the latest painted faction, sharing one state")
    end
end

-- ------------------------------------------------------------------------------------------------
print("Phase 7: Characters rows keep stable scripts that act on the latest painted character")
do
    local tips, calls = {}, {}
    local rgba = { 0.5, 0.5, 0.5, 1 }
    local Factory = setmetatable({}, { __index = function() return function(_, parent) return Frame.new(parent) end end })
    local col = { width = 30, spacing = 5, total = 30 }
    local cols = setmetatable({}, { __index = function() return col end })
    local flex = { guild = 60, itemLevel = 40, gold = 60, professions = 120, mythicKey = 60 }
    local ns = { UI = { Factory = Factory } }
    local WN = { db = { profile = {}, global = { characters = {} } } }
    function WN:ReorderCharacter(char, list, listKey, dir) calls[#calls + 1] = "reorder:" .. char.name .. ":" .. dir end
    function WN:SendMessage() end
    ns.WarbandNexus = WN
    ns.UI_CHAR_ROW_COLUMNS = cols
    ns.UI_GetColumnOffset = function() return 10 end
    ns.UI_CreateFrame = function(_, _, parent) return Frame.new(parent) end
    ns.UI_CreateFavoriteButton = function(parent) return Frame.new(parent) end
    ns.UI_CreateFactionIcon = function(parent) return Frame.new(parent) end
    ns.UI_CreateRaceIcon = function(parent) return Frame.new(parent) end
    ns.UI_CreateClassIcon = function(parent) return Frame.new(parent) end
    ns.UI_ComputeCharRowFlexColumns = function() return flex end
    ns.UI_SetTextColorRole = function() end
    ns.UI_SetIcon = function() end
    ns.UI_GetMonochromeIconVertex = function() return rgba end
    ns.UI_ApplyCharacterRowClassGradientAccent = function() end
    ns.UI_ShowCharacterRowContextMenu = function(_, key) calls[#calls + 1] = "menu:" .. tostring(key) end
    ns.UI_ShowCharacterSectionAssignMenu = function(_, key) calls[#calls + 1] = "assign:" .. tostring(key) end
    ns.CharacterService = {
        IsFavoriteCharacter = function() return false end,
        ToggleFavoriteCharacter = function(_, _, key) calls[#calls + 1] = "fav:" .. tostring(key); return true end,
        ParseCustomGroupIdFromListKey = function() return nil end,
    }
    ns.Utilities = setmetatable({}, { __index = function() return function() return 0 end end })
    ns.CharactersUI = { _bind = {
        WarbandNexus = WN, E = { UI_MAIN_REFRESH_REQUESTED = "WN_UI_MAIN_REFRESH_REQUESTED" },
        FontManager = Factory, COLORS = { accent = rgba, gold = rgba, green = rgba, red = rgba },
        ShowTooltip = function(_, data) tips[#tips + 1] = data end, HideTooltip = function() end,
        FormatMoney = function() return "0g" end, ThemeTextHex = function() return "|cffffffff" end,
        SemanticGoldHex = function() return "|cffffd100" end, PresentFS = function() end,
        CreateCharacterDeleteDialogButton = function(parent) return Frame.new(parent) end,
        CreateIcon = function(parent) local f = Frame.new(parent); f.texture = Frame.new(f); return f end,
        AcquireCharacterRow = function(parent) return Frame.new(parent) end,
        GetCharKey = function(c) return c.name .. "-Realm" end,
        IsCharLoggedInSession = function() return false end,
        GetLayout = function() return {} end, BuildGuildText = function() return "" end,
    } }
    LoadFile("Modules/UI/CharactersUI_Row.lua", ns)

    local function makeChar(name, tracked)
        return { name = name, realm = "Realm", classFile = "MAGE", level = 80, isTracked = tracked, _key = name,
            lastSeen = os.time() - 7200,
            professions = { { name = name .. "Alchemy", icon = 1, skill = 10, maxSkill = 100 },
                            { name = name .. "Mining", icon = 2, skill = 5, maxSkill = 100 } } }
    end
    local parent = Frame.new(nil)
    local row = Frame.new(parent)
    local function paint(char)
        return pcall(WN.DrawCharacterRow, WN, parent, char, 1, 800, 0, false, true, { char }, "regular", 1, 1, nil, row)
    end
    local function frames()
        local rb = row.reorderButtons or {}
        local pi = row.profIcons or {}
        return { row = row, fav = row.favButton, track = row.trackingBtn, up = rb.up, down = rb.down,
            assign = row.headerAssignBtn, delete = row.deleteBtn, prof1 = pi[1], prof2 = pi[2] }
    end
    local ok1, e1 = paint(makeChar("Alpha", true))
    local s1 = SnapshotScripts(frames())
    local g1 = row._wnGradientRefresh
    local beta = makeChar("Beta", true)
    local ok2, e2 = paint(beta)
    local s2 = SnapshotScripts(frames())
    assert_eq(ok1 and ok2, true, "character row paints (" .. tostring(not ok1 and e1 or not ok2 and e2 or "") .. ")")
    local changed, total = CountChangedHandlers(s1, s2)
    assert_eq(total >= 14 and changed == 0, true,
        string.format("repaint keeps the same %d script functions (%d replaced)", total, changed))
    assert_eq(g1 ~= nil and row._wnGradientRefresh == g1, true, "gradient refresh callback is created once per row")

    local f = frames()
    local function run(fr, script, ...) local fn = fr and fr:GetScript(script); if fn then fn(fr, ...) end end
    run(f.row, "OnMouseUp", "RightButton")
    run(f.fav, "OnClick")
    run(f.up, "OnClick")
    run(f.down, "OnClick")
    run(f.assign, "OnClick")
    assert_eq(table.concat(calls, ","), "menu:Beta-Realm,fav:Beta-Realm,reorder:Beta:-1,reorder:Beta:1,assign:Beta-Realm",
        "row menu / favorite / reorder / section assign act on the latest painted character")
    beta.isTracked = false                            -- tooltip reads tracking state at hover time
    run(f.track, "OnEnter")
    assert_eq(tips[#tips] and tips[#tips].description, "Click to enable tracking.", "tracking tooltip reads the latest character")
    run(f.prof1, "OnEnter")
    assert_eq(tips[#tips] and tips[#tips].title, "BetaAlchemy", "profession tooltip shows the latest painted profession")
    run(f.delete, "OnEnter")
    assert_eq(tips[#tips] and tips[#tips].description, "Remove Beta from tracking", "delete tooltip names the latest character")
    local gradCalls = 0
    ns.UI_ApplyCharacterRowClassGradientAccent = function(_, classFile) gradCalls = gradCalls + 1 end
    row._wnGradientRefresh()
    assert_eq(gradCalls, 1, "gradient refresh still applies the class accent")

    -- Live-resize relayout: no table per row per step (was `local shown = {}`).
    local Layout = ns.CharactersUI.ApplyCharacterRowInteriorLayout
    Layout(row, 820)
    local x1 = row.profIcons[1]
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    for _ = 1, 2000 do Layout(row, 820) end
    local grownKB = collectgarbage("count") - before
    collectgarbage("restart")
    assert_eq(grownKB < 40, true, string.format("2000 relayouts allocate ~nothing (%.1f KB)", grownKB))
end

print("Phase Z: a pooled reputation row without sub-factions drops the previous toggle (static)")
do
    local fh = assert(io.open((os.getenv("WN_ROOT") or ".") .. "/Modules/UI/ReputationUI.lua", "rb"))
    local src = fh:read("*a"):gsub("\r\n", "\n")
    fh:close()
    local elseBlock = src:match('if row%.collapseBtn then row%.collapseBtn:Hide%(%) end(.-)\n    end\n')
    assert_eq(elseBlock and elseBlock:find('row:SetScript("OnClick", nil)', 1, true) ~= nil
        and elseBlock:find("row._wnRepCollapseKey = nil", 1, true) ~= nil, true,
        "no-sub-faction branch clears the stale OnClick / collapse key")
end

assert_eq(#stub.errors, 0, "no errors raised inside stubbed timers/handlers")

print(string.format("\nTotal Checks: %d | Failures: %d", passed + failed, failed))
if failed > 0 then
    error("Row paint allocation suite failed with " .. failed .. " failure(s).")
end
print("Row paint allocation suite: ALL TESTS PASSED.")
