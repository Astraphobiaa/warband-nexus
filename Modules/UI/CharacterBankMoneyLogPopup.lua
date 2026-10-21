--[[
    Warband Nexus - Character Bank Money Logs Popup
    Tabbed view: All / Deposit / Withdraw (transaction log) + Contributions (per-character summary).

    WN_FACTORY: Tabs, scroll hosts, rows, footers prefer `Factory` methods; scroll uses
    CreateScrollBarColumn + PositionScrollBarInContainer + UpdateScrollBarVisibility (MailDetails pattern).
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateExternalWindow = ns.UI_CreateExternalWindow
local Factory = ns.UI.Factory
local TK = ns.UI_TableKit
assert(TK, "SharedWidgets_TableKit.lua must load before CharacterBankMoneyLogPopup.lua")
local TABLE = ns.UI_LAYOUT.TABLE

local issecretvalue = issecretvalue

local function ControlChromeBg()
    if ns.UI_GetControlChromeBackdrop then
        return ns.UI_GetControlChromeBackdrop()
    end
    return COLORS and COLORS.bgCard or { 0.12, 0.12, 0.15, 1 }
end

local function ControlChromeHoverBg()
    if ns.UI_GetControlChromeHoverBackdrop then
        return ns.UI_GetControlChromeHoverBackdrop()
    end
    return COLORS and COLORS.surfaceRowEven or { 0.18, 0.18, 0.22, 1 }
end

local function HeaderRowBg()
    local c = COLORS
    return c and (c.surfaceHeaderChrome or c.bgCard) or { 0.08, 0.08, 0.10, 1 }
end

local function SemanticGoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    return 1, 0.9, 0.2, 1
end

local function SemanticGreenRGB()
    if ns.UI_GetSemanticGreenColor then
        return ns.UI_GetSemanticGreenColor()
    end
    return 0.35, 0.9, 0.45, 1
end

local function SemanticOrangeRGB()
    if ns.UI_GetSemanticOrangeColor then
        return ns.UI_GetSemanticOrangeColor()
    end
    return 1, 0.65, 0.25, 1
end

local SCROLLBAR_COL_W = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
local SCROLLBAR_LANE = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()) or 28
local SCROLL_GAP = 2
local PADDING = 12

-- TableKit column model (SharedWidgets_TableKit.lua): one header strip + pooled rows per tab.
-- Labels are filled at open time (ApplyMoneyLogColumnLabels); widths resolve once below.
local MONEY_COL_W = 200  -- one money cell: "2.000.000" gold + silver + copper with 12px coins
local CHAR_COL_W = 240

-- Transaction log (All / Deposit / Withdraw): To/From is the flex description column.
local LOG_COLS = {
    { key = "time",   labelKey = "MONEY_LOGS_COLUMN_TIME",      fallback = "Time",      width = 90,          align = "CENTER" },
    { key = "char",   labelKey = "MONEY_LOGS_COLUMN_CHARACTER", fallback = "Character", width = CHAR_COL_W,  align = "LEFT" },
    { key = "type",   labelKey = "MONEY_LOGS_COLUMN_TYPE",      fallback = "Type",      width = 90,          align = "CENTER" },
    { key = "tofrom", labelKey = "MONEY_LOGS_COLUMN_TOFROM",    fallback = "To / From", width = 200,         align = "LEFT", flex = 1 },
    { key = "amount", labelKey = "MONEY_LOGS_COLUMN_AMOUNT",    fallback = "Amount",    width = MONEY_COL_W, align = "RIGHT", cell = "money" },
}

-- Contributions: Character (flex) | Deposit | Withdraw | Net. Net = kit signedMoney cell (sign + green / red ink).
local SUM_COLS = {
    { key = "char",     labelKey = "MONEY_LOGS_COLUMN_CHARACTER", fallback = "Character", width = CHAR_COL_W,  align = "LEFT", flex = 1 },
    { key = "deposit",  labelKey = "MONEY_LOGS_DEPOSIT",          fallback = "Deposit",   width = MONEY_COL_W, align = "RIGHT", cell = "money" },
    { key = "withdraw", labelKey = "MONEY_LOGS_WITHDRAW",         fallback = "Withdraw",  width = MONEY_COL_W, align = "RIGHT", cell = "money" },
    { key = "net",      labelKey = "MONEY_LOGS_COLUMN_NET",       fallback = "Net",       width = MONEY_COL_W, align = "RIGHT", cell = "signedMoney" },
}

-- Resolved once: both tabs share one content width (widest natural span), flex columns absorb the rest.
local LOG_WIDTHS, LOG_OFFSETS = {}, {}
local SUM_WIDTHS, SUM_OFFSETS = {}, {}
local TABLE_CONTENT_W = math.max(
    TK.ResolveWidths(LOG_COLS, nil, LOG_WIDTHS, LOG_OFFSETS, 0),
    TK.ResolveWidths(SUM_COLS, nil, SUM_WIDTHS, SUM_OFFSETS, 0))
TK.ResolveWidths(LOG_COLS, TABLE_CONTENT_W, LOG_WIDTHS, LOG_OFFSETS, 0)
TK.ResolveWidths(SUM_COLS, TABLE_CONTENT_W, SUM_WIDTHS, SUM_OFFSETS, 0)

-- Natural table + side padding + scrollbar lane + viewport gap: the narrowest window that never clips a column.
local WINDOW_W = math.max(800, TABLE_CONTENT_W + (PADDING * 2) + SCROLLBAR_LANE + SCROLL_GAP)
local WINDOW_H = 520
local TAB_BAR_H = 30
local TAB_BTN_H = 26

local function FormatTime(timestamp)
    if not timestamp or timestamp <= 0 then return "-" end
    return date("%d.%m %H:%M", timestamp)
end

local function GetToFromText(entryType)
    if entryType == "deposit" then
        return (ns.L and ns.L["MONEY_LOGS_TO_WARBAND_BANK"]) or "Warband Bank"
    end
    return (ns.L and ns.L["MONEY_LOGS_FROM_WARBAND_BANK"]) or "From Warband Bank"
end

local function LookupCharacterRow(storageKey)
    if not storageKey or storageKey == "" then return nil end
    if issecretvalue and issecretvalue(storageKey) then return nil end
    local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    if not chars then return nil end
    local charData = chars[storageKey]
    if charData then return charData end
    if type(storageKey) == "string" and storageKey:sub(1, 7) == "Player-" then
        for _, row in pairs(chars) do
            if type(row) == "table" and row.guid == storageKey then
                return row
            end
        end
    end
    local keySafe = type(storageKey) == "string" and not (issecretvalue and issecretvalue(storageKey))
    if keySafe and storageKey:find("-") and ns.Utilities and ns.Utilities.GetCharacterKey then
        local name, realm = storageKey:match("^([^%-]+)%-(.*)$")
        if name and realm then
            local legacy = ns.Utilities:GetCharacterKey(name, realm)
            if legacy and chars[legacy] then
                return chars[legacy]
            end
        end
    end
    return nil
end

local function ResolveMoneyLogCharacterLabel(entry)
    if entry and entry.characterName and entry.characterName ~= "" then
        if not (issecretvalue and issecretvalue(entry.characterName)) then
            return entry.characterName
        end
    end
    local storageKey = entry and entry.character
    if not storageKey or storageKey == "" then return "-" end
    if issecretvalue and issecretvalue(storageKey) then return "-" end
    if type(storageKey) == "string" and storageKey:sub(1, 7) ~= "Player-" then
        local name, realm = storageKey:match("^([^%-]+)%-(.+)$")
        if name and realm and ns.Utilities and ns.Utilities.FormatRealmName then
            return name .. "-" .. ns.Utilities:FormatRealmName(realm)
        end
        return storageKey
    end
    local charData = LookupCharacterRow(storageKey)
    if charData and charData.name and charData.name ~= "" then
        local name = charData.name
        local realm = charData.realm
        if realm and realm ~= "" then
            local pretty = ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(realm) or realm
            return name .. "-" .. pretty
        end
        return name
    end
    return storageKey
end

local function GetClassColorForEntry(entry, charKey)
    local classFile = entry.classFile
    if not classFile then
        local key = entry.character or charKey
        local charData = LookupCharacterRow(key)
        classFile = charData and (charData.classFile or charData.class)
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b, 1
    end
    local c = COLORS and COLORS.textNormal
    if c then return c[1], c[2], c[3], c[4] or 1 end
    return 0.85, 0.85, 0.9, 1
end

-- ---------------------------------------------------------------------------
-- TableKit row paint: one valueFn per tab (no per-row closures).
-- valueFn returns value, role[, r, g, b, a]: the kit inks text cells (class / semantic colors).
-- ---------------------------------------------------------------------------

local moneyLogCharKey      -- class-color fallback key (set per open)
local CONTRIB_ENTRY = {}   -- scratch entry for contributions label / class color

-- Header labels: accent ink, body font (pre-kit look). Accent re-read on theme refresh.
local function HeaderLabelInk()
    if ns.UI_GetAccentTextRGBA then
        return ns.UI_GetAccentTextRGBA()
    end
    local ac = COLORS and COLORS.accent
    if ac then return ac[1], ac[2], ac[3], 1 end
    return nil
end

local function ApplyMoneyLogColumnLabels(cols)
    local L = ns.L
    for i = 1, #cols do
        local col = cols[i]
        col.label = (L and L[col.labelKey]) or col.fallback
    end
end

local function LogCellValue(col, entry)
    local key = col.key
    if key == "time" then
        return FormatTime(entry.timestamp), nil, SemanticGoldRGB()
    elseif key == "char" then
        return ResolveMoneyLogCharacterLabel(entry), nil, GetClassColorForEntry(entry, moneyLogCharKey)
    elseif key == "type" then
        if entry.type == "deposit" then
            return (ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit", nil, SemanticGreenRGB()
        end
        return (ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw", nil, SemanticOrangeRGB()
    elseif key == "tofrom" then
        return GetToFromText(entry.type), "Normal"
    elseif key == "amount" then
        return entry.amount or 0
    end
    return nil
end

local function ContribEntry(s)
    CONTRIB_ENTRY.character = s.charKey
    CONTRIB_ENTRY.classFile = s.classFile
    return CONTRIB_ENTRY
end

local function ContribCellValue(col, s)
    local key = col.key
    if key == "char" then
        local entry = ContribEntry(s)
        return ResolveMoneyLogCharacterLabel(entry), nil, GetClassColorForEntry(entry, moneyLogCharKey)
    elseif key == "deposit" then
        return s.deposit or 0
    elseif key == "withdraw" then
        return s.withdraw or 0
    elseif key == "net" then
        return s.net or 0
    end
    return nil
end

-- Header strips: one shared opts table (kit copies the fields at create time).
local HEADER_STRIP_OPTS = {
    mode = "text",
    height = TABLE.HEADER_H.text,
    labelFont = "body",
    labelColorFn = HeaderLabelInk,
}

function WarbandNexus:ShowCharacterBankMoneyLogPopup()
    local dialog, contentFrame = CreateExternalWindow({
        name = "CharacterBankMoneyLogPopup",
        title = (ns.L and ns.L["MONEY_LOGS_TITLE"]) or "Money Logs",
        icon = "Interface\\Icons\\INV_Misc_Coin_01",
        width = WINDOW_W,
        height = WINDOW_H,
        preventDuplicates = true,
    })

    if not dialog then return end

    if dialog.SetSize then
        dialog:SetSize(WINDOW_W, WINDOW_H)
    end

    local children = { contentFrame:GetChildren() }
    local bin = ns.UI_RecycleBin
    for i = 1, #children do
        children[i]:Hide()
        if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
    end

    local charKey = (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and WarbandNexus
        and ns.CharacterService:ResolveSubsidiaryCharacterKey(WarbandNexus, nil))
        or (ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
        or nil
    local headerHeight = TABLE.HEADER_H.text
    local rowHeight = TABLE.ROW_H.compact
    local rowSpacing = 2
    moneyLogCharKey = charKey
    ApplyMoneyLogColumnLabels(LOG_COLS)
    ApplyMoneyLogColumnLabels(SUM_COLS)
    -- Pools live per open: the scroll children are rebuilt with the dialog content.
    local logRowPool = TK.CreateRowPool(rowHeight)
    local contribRowPool = TK.CreateRowPool(rowHeight)

    dialog._moneyLogTab = dialog._moneyLogTab or "all"

    -- DATA HELPERS
    local function getFilteredEntries(filter)
        if not WarbandNexus.GetCharacterBankMoneyLogs or type(WarbandNexus.GetCharacterBankMoneyLogs) ~= "function" then
            return {}
        end
        local raw = WarbandNexus:GetCharacterBankMoneyLogs() or {}
        if type(raw) ~= "table" then return {} end
        if filter == "all" then return raw end
        local out = {}
        for i = 1, #raw do
            if raw[i] and raw[i].type == filter then
                out[#out + 1] = raw[i]
            end
        end
        return out
    end

    local function getSummary()
        if not WarbandNexus.GetCharacterBankMoneyLogSummary or type(WarbandNexus.GetCharacterBankMoneyLogSummary) ~= "function" then
            return {}
        end
        return WarbandNexus:GetCharacterBankMoneyLogSummary()
    end

    -- TAB BAR
    local TAB_DEFS = {
        { key = "all",           label = (ns.L and ns.L["MONEY_LOGS_FILTER_ALL"]) or "All" },
        { key = "deposit",       label = (ns.L and ns.L["MONEY_LOGS_DEPOSIT"]) or "Deposit" },
        { key = "withdraw",      label = (ns.L and ns.L["MONEY_LOGS_WITHDRAW"]) or "Withdraw" },
        { key = "contributions", label = (ns.L and ns.L["MONEY_LOGS_SUMMARY_TITLE"]) or "Contributions" },
    }

    -- Tab bar width matches table header (scrollbar lane sits below, not under tabs).
    local TAB_GAP = 4
    local TAB_COUNT = #TAB_DEFS
    local TAB_BAR_W = TABLE_CONTENT_W
    local TAB_BTN_W = math.max(72, math.floor((TAB_BAR_W - (TAB_GAP * (TAB_COUNT - 1))) / TAB_COUNT))

    local tabBar = Factory and Factory.CreateContainer and Factory:CreateContainer(contentFrame, TAB_BAR_W, TAB_BAR_H, false)
    if not tabBar then
        tabBar = CreateFrame("Frame", nil, contentFrame)
        tabBar:SetSize(TAB_BAR_W, TAB_BAR_H)
    end
    tabBar:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PADDING, -8)
    tabBar:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -(PADDING + SCROLLBAR_LANE + SCROLL_GAP), -8)

    local tabButtons = {}
    local function setTabVisuals(btn, selected)
        if not btn then return end
        if btn._wnBlizzardButton then
            if ns.UI_ApplyClassicNavTabActiveState then
                ns.UI_ApplyClassicNavTabActiveState(btn, selected)
            end
            return
        end
        if not ApplyVisuals then return end
        if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(btn) then return end
        if selected then
            ApplyVisuals(btn, ControlChromeHoverBg(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
        else
            ApplyVisuals(btn, ControlChromeBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.5 })
        end
    end

    for idx = 1, TAB_COUNT do
        local def = TAB_DEFS[idx]
        local btnW = TAB_BTN_W
        if idx == TAB_COUNT then
            btnW = TAB_BAR_W - ((TAB_BTN_W + TAB_GAP) * (TAB_COUNT - 1))
        end
        local btn = Factory and Factory.CreateButton and Factory:CreateButton(tabBar, btnW, TAB_BTN_H)
        if not btn then
            btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
            btn:SetSize(btnW, TAB_BTN_H)
        end
        btn:SetSize(btnW, TAB_BTN_H)
        if idx == 1 then
            btn:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            btn:SetPoint("LEFT", tabButtons[idx - 1], "RIGHT", TAB_GAP, 0)
        end
        if Factory and Factory.ApplyHighlight then
            Factory:ApplyHighlight(btn)
        end
        local lbl = FontManager:CreateFontString(btn, "body", "OVERLAY")
        lbl:SetPoint("LEFT", 4, 0)
        lbl:SetPoint("RIGHT", -4, 0)
        lbl:SetText(def.label)
        ns.UI_SetTextColorRole(lbl, "Bright")
        lbl:SetJustifyH("CENTER")
        lbl:SetWordWrap(false)
        if lbl.SetNonSpaceWrap then lbl:SetNonSpaceWrap(false) end
        tabButtons[idx] = btn
    end
    -- Equal-width tabs across the live bar width (same right edge as the table header).
    tabBar:HookScript("OnSizeChanged", function(_, w)
        w = tonumber(w) or 0
        if w <= 0 then return end
        local bw = math.max(72, math.floor((w - (TAB_GAP * (TAB_COUNT - 1))) / TAB_COUNT))
        for idx = 1, TAB_COUNT do
            local tb = tabButtons[idx]
            if idx == TAB_COUNT then
                tb:SetWidth(math.max(72, w - ((bw + TAB_GAP) * (TAB_COUNT - 1))))
            else
                tb:SetWidth(bw)
            end
        end
    end)

    local function AcquireStretchPanel(parent)
        if Factory and Factory.CreateContainer then
            local p = Factory:CreateContainer(parent, 1, 1, false)
            if p then return p end
        end
        return CreateFrame("Frame", nil, parent)
    end

    local function AcquireScrollChildHost(scroll)
        if Factory and Factory.CreateContainer then
            local c = Factory:CreateContainer(scroll, 1, 1, false)
            if c then return c end
        end
        local f = CreateFrame("Frame", nil, scroll)
        f:SetSize(1, 1)
        return f
    end

    local LOG_FOOTER_H = 36
    local SCROLL_HEADER_GAP = 4

    -- Shared bar column synced to whichever tab scroll is active (list | bar | table pattern).
    local scrollBarColumn = Factory and Factory.CreateBareScrollBarColumn and Factory:CreateBareScrollBarColumn(contentFrame, SCROLLBAR_COL_W)
        or (Factory and Factory.CreateContainer and Factory:CreateContainer(contentFrame, SCROLLBAR_COL_W, 1, false))
    if scrollBarColumn then
        scrollBarColumn:SetFrameLevel((contentFrame:GetFrameLevel() or 0) + 8)
    end

    local activeMoneyLogScroll

    local function SyncMoneyLogScrollBar(scroll)
        if not scrollBarColumn or not scroll then return end
        activeMoneyLogScroll = scroll
        if Factory.EnsureScrollBarColumnSync then
            Factory:EnsureScrollBarColumnSync(scroll, scrollBarColumn, { width = SCROLLBAR_COL_W, gap = SCROLL_GAP })
        elseif Factory.SyncScrollBarColumnToViewport then
            Factory:SyncScrollBarColumnToViewport(scroll, scrollBarColumn, { width = SCROLLBAR_COL_W, gap = SCROLL_GAP })
            if scroll.ScrollBar and Factory.PositionScrollBarInContainer then
                Factory:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
            end
        end
        scrollBarColumn:Show()
    end

    local function RefreshMoneyLogScrollChrome(scroll)
        scroll = scroll or activeMoneyLogScroll
        if not scroll then return end
        SyncMoneyLogScrollBar(scroll)
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scroll)
        end
    end

    local function SetupFactoryScroll(panel, headerRow, bottomFrame, childW)
        if not Factory or not Factory.CreateScrollFrame or not bottomFrame then
            return nil, nil
        end
        childW = childW or TABLE_CONTENT_W

        local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
        if not scroll then
            return nil, nil
        end

        -- Right edge = header right edge (bottomFrame already ends at the scrollbar lane + gap).
        scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -SCROLL_HEADER_GAP)
        scroll:SetPoint("BOTTOMRIGHT", bottomFrame, "TOPRIGHT", 0, 0)
        if scroll.SetClipsChildren then
            scroll:SetClipsChildren(true)
        end
        if ns.UI_EnableStandardScrollWheel then
            ns.UI_EnableStandardScrollWheel(scroll)
        end

        local scrollChild = scroll:GetScrollChild()
        if not scrollChild then
            scrollChild = AcquireScrollChildHost(scroll)
            scroll:SetScrollChild(scrollChild)
        end
        scrollChild:SetWidth(childW)
        if scrollChild.EnableMouseWheel then
            scrollChild:EnableMouseWheel(true)
        end

        return scroll, scrollChild
    end

    local function SetupContribScroll(panel, headerRow, childW)
        if not Factory or not Factory.CreateScrollFrame then
            return nil, nil
        end
        childW = childW or TABLE_CONTENT_W

        local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
        if not scroll then
            return nil, nil
        end

        scroll:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -SCROLL_HEADER_GAP)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(SCROLLBAR_LANE + SCROLL_GAP), 0)
        if scroll.SetClipsChildren then
            scroll:SetClipsChildren(true)
        end
        if ns.UI_EnableStandardScrollWheel then
            ns.UI_EnableStandardScrollWheel(scroll)
        end

        local scrollChild = scroll:GetScrollChild()
        if not scrollChild then
            scrollChild = AcquireScrollChildHost(scroll)
            scroll:SetScrollChild(scrollChild)
        end
        scrollChild:SetWidth(childW)
        if scrollChild.EnableMouseWheel then
            scrollChild:EnableMouseWheel(true)
        end

        return scroll, scrollChild
    end

    -- Live table width = scroll viewport width (resolved in ApplyTableWidth; 0 forces the first resolve).
    local tableW = 0

    local logPanel = AcquireStretchPanel(contentFrame)
    logPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PADDING, -(8 + TAB_BAR_H + 8))
    logPanel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PADDING, 10)

    local logHeaderRow = ns.UI.Factory:CreateContainer(logPanel, 1, headerHeight, false)
    logHeaderRow:SetPoint("TOPLEFT", logPanel, "TOPLEFT", 0, 0)
    logHeaderRow:SetPoint("TOPRIGHT", logPanel, "TOPRIGHT", -(SCROLLBAR_LANE + SCROLL_GAP), 0)
    logHeaderRow:SetHeight(headerHeight)
    if ApplyVisuals then
        ApplyVisuals(logHeaderRow, HeaderRowBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8 })
    end

    -- Filled header chrome stays on logHeaderRow; the kit strip draws the column labels on top.
    local logHeaderStrip = TK.CreateHeaderStrip(logHeaderRow, HEADER_STRIP_OPTS)
    logHeaderStrip:SetPoint("TOPLEFT", logHeaderRow, "TOPLEFT", 0, 0)
    logHeaderStrip:SetSize(TABLE_CONTENT_W, headerHeight)
    logHeaderStrip:SetColumns(LOG_COLS, LOG_WIDTHS, LOG_OFFSETS)

    local logFooter = ns.UI.Factory:CreateContainer(logPanel, 1, LOG_FOOTER_H)
    logFooter:SetPoint("BOTTOMLEFT", logPanel, "BOTTOMLEFT", 0, 0)
    logFooter:SetPoint("BOTTOMRIGHT", logPanel, "BOTTOMRIGHT", -(SCROLLBAR_LANE + SCROLL_GAP), 0)

    local logScroll, logScrollChild = SetupFactoryScroll(logPanel, logHeaderRow, logFooter, TABLE_CONTENT_W)

    local resetBtn = ns.UI.Factory:CreateButton(logFooter, 100, 28)
    resetBtn:SetPoint("RIGHT", logFooter, "RIGHT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(resetBtn, ControlChromeBg(), { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    if ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(resetBtn)
    end
    local resetLabel = FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetLabel:SetPoint("CENTER")
    resetLabel:SetText((ns.L and ns.L["MONEY_LOGS_RESET"]) or "Reset")
    ns.UI_SetTextColorRole(resetLabel, "Bright")

    local function clearScrollHost(scroll, scrollChild, rowPool)
        if not scrollChild then return end
        TK.ReleaseRowsFrom(rowPool, 1)
        if scrollChild._wnEmptyText then
            scrollChild._wnEmptyText:Hide()
        end
        scrollChild:SetHeight(1)
        if scroll then
            if scroll.SetVerticalScroll then
                scroll:SetVerticalScroll(0)
            end
            if scroll.UpdateScrollChildRect then
                scroll:UpdateScrollChildRect()
            end
        end
    end

    local function showEmptyText(scrollChild)
        local emptyText = scrollChild._wnEmptyText
        if not emptyText then
            emptyText = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", TABLE.CELL_PAD_X, -10)
            scrollChild._wnEmptyText = emptyText
        end
        emptyText:SetText((ns.L and ns.L["MONEY_LOGS_EMPTY"]) or "No money transactions recorded yet.")
        ns.UI_SetTextColorRole(emptyText, "Muted")
        emptyText:Show()
        scrollChild:SetHeight(rowHeight + 8)
    end

    local function populateLogScroll(filter)
        if not logScroll or not logScrollChild then return end
        clearScrollHost(logScroll, logScrollChild, logRowPool)

        local entries = getFilteredEntries(filter)
        if #entries == 0 then
            showEmptyText(logScrollChild)
            RefreshMoneyLogScrollChrome(logScroll)
            return
        end

        local nCols = #LOG_COLS
        local rowY = 0
        local rowIndex = 0
        for i = #entries, 1, -1 do
            local entry = entries[i]
            rowIndex = rowIndex + 1
            local row = TK.AcquireRow(logRowPool, logScrollChild, rowIndex, tableW, rowHeight)
            row:SetPoint("TOPLEFT", logScrollChild, "TOPLEFT", 0, -rowY)
            TK.PaintRowCells(row, LOG_COLS, LOG_WIDTHS, LOG_OFFSETS, nCols, entry, LogCellValue)
            rowY = rowY + rowHeight + rowSpacing
        end
        logScrollChild:SetHeight(math.max(rowY + 8, 1))
        RefreshMoneyLogScrollChrome(logScroll)
    end

    -- CONTRIBUTIONS PANEL
    local contribPanel = AcquireStretchPanel(contentFrame)
    contribPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", PADDING, -(8 + TAB_BAR_H + 8))
    contribPanel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -PADDING, 10)

    local contribHeaderRow = ns.UI.Factory:CreateContainer(contribPanel, 1, headerHeight, false)
    contribHeaderRow:SetPoint("TOPLEFT", contribPanel, "TOPLEFT", 0, 0)
    contribHeaderRow:SetPoint("TOPRIGHT", contribPanel, "TOPRIGHT", -(SCROLLBAR_LANE + SCROLL_GAP), 0)
    contribHeaderRow:SetHeight(headerHeight)
    if ApplyVisuals then
        ApplyVisuals(contribHeaderRow, HeaderRowBg(), { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8 })
    end

    local contribHeaderStrip = TK.CreateHeaderStrip(contribHeaderRow, HEADER_STRIP_OPTS)
    contribHeaderStrip:SetPoint("TOPLEFT", contribHeaderRow, "TOPLEFT", 0, 0)
    contribHeaderStrip:SetSize(TABLE_CONTENT_W, headerHeight)
    contribHeaderStrip:SetColumns(SUM_COLS, SUM_WIDTHS, SUM_OFFSETS)

    local contribScroll, contribScrollChild = SetupContribScroll(contribPanel, contribHeaderRow, TABLE_CONTENT_W)

    local function populateContribScroll()
        if not contribScroll or not contribScrollChild then return end
        clearScrollHost(contribScroll, contribScrollChild, contribRowPool)

        local summaryData = getSummary()
        if #summaryData == 0 then
            showEmptyText(contribScrollChild)
            RefreshMoneyLogScrollChrome(contribScroll)
            return
        end

        local nCols = #SUM_COLS
        local rowY = 0
        for i = 1, #summaryData do
            local s = summaryData[i]
            local row = TK.AcquireRow(contribRowPool, contribScrollChild, i, tableW, rowHeight)
            row:SetPoint("TOPLEFT", contribScrollChild, "TOPLEFT", 0, -rowY)
            TK.PaintRowCells(row, SUM_COLS, SUM_WIDTHS, SUM_OFFSETS, nCols, s, ContribCellValue)
            rowY = rowY + rowHeight + rowSpacing
        end
        contribScrollChild:SetHeight(math.max(rowY + 8, 1))
        RefreshMoneyLogScrollChrome(contribScroll)
    end

    -- TAB SWITCHING
    local function switchTab(tabKey)
        dialog._moneyLogTab = tabKey
        for idx = 1, #TAB_DEFS do
            setTabVisuals(tabButtons[idx], TAB_DEFS[idx].key == tabKey)
        end
        local isContrib = (tabKey == "contributions")
        if isContrib then
            clearScrollHost(logScroll, logScrollChild, logRowPool)
            logPanel:Hide()
            contribPanel:Show()
            if contribPanel.SetFrameLevel and logPanel.GetFrameLevel then
                contribPanel:SetFrameLevel(logPanel:GetFrameLevel() + 2)
            end
            populateContribScroll()
            SyncMoneyLogScrollBar(contribScroll)
            RefreshMoneyLogScrollChrome(contribScroll)
        else
            clearScrollHost(contribScroll, contribScrollChild, contribRowPool)
            contribPanel:Hide()
            logPanel:Show()
            if logPanel.SetFrameLevel and contribPanel.GetFrameLevel then
                logPanel:SetFrameLevel(contribPanel:GetFrameLevel() + 2)
            end
            populateLogScroll(tabKey)
            SyncMoneyLogScrollBar(logScroll)
            RefreshMoneyLogScrollChrome(logScroll)
        end
    end

    -- Columns span the full viewport: flex columns (To/From, Character) absorb the extra width,
    -- so header, rows and the right-aligned money column always reach the scrollbar lane.
    local function ApplyTableWidth(w)
        w = math.floor((tonumber(w) or 0) + 0.5)
        if w < TABLE_CONTENT_W then w = TABLE_CONTENT_W end
        if w == tableW then return end
        -- Recycled content from a previous open keeps its hook; only the live panel resolves.
        if logPanel:GetParent() ~= contentFrame then return end
        tableW = w
        TK.ResolveWidths(LOG_COLS, tableW, LOG_WIDTHS, LOG_OFFSETS, 0)
        TK.ResolveWidths(SUM_COLS, tableW, SUM_WIDTHS, SUM_OFFSETS, 0)
        logHeaderStrip:SetSize(tableW, headerHeight)
        logHeaderStrip:SetColumns(LOG_COLS, LOG_WIDTHS, LOG_OFFSETS)
        contribHeaderStrip:SetSize(tableW, headerHeight)
        contribHeaderStrip:SetColumns(SUM_COLS, SUM_WIDTHS, SUM_OFFSETS)
        if logScrollChild then logScrollChild:SetWidth(tableW) end
        if contribScrollChild then contribScrollChild:SetWidth(tableW) end
        if dialog:IsShown() then
            switchTab(dialog._moneyLogTab or "all")
        end
    end
    if logScroll then
        logScroll:HookScript("OnSizeChanged", function(_, w) ApplyTableWidth(w) end)
    end
    if contribScroll then
        contribScroll:HookScript("OnSizeChanged", function(_, w) ApplyTableWidth(w) end)
    end
    ApplyTableWidth(logScroll and logScroll:GetWidth() or TABLE_CONTENT_W)

    for idx = 1, #TAB_DEFS do
        local def = TAB_DEFS[idx]
        tabButtons[idx]:SetScript("OnClick", function()
            switchTab(def.key)
        end)
    end

    resetBtn:SetScript("OnClick", function()
        if not WarbandNexus.ClearCharacterBankMoneyLogs then return end
        -- Clearing the money log is irreversible: confirm first (it used to run on a single click).
        local function doReset()
            resetBtn:Disable()
            WarbandNexus:ClearCharacterBankMoneyLogs(nil)
            C_Timer.After(0.25, function()
                if resetBtn and resetBtn.Enable then resetBtn:Enable() end
            end)
        end
        if ns.UI_ShowConfirmDialog then
            ns.UI_ShowConfirmDialog({
                name = "WnConfirmMoneyLogReset",
                title = (ns.L and ns.L["MONEY_LOGS_RESET"]) or "Reset",
                onConfirm = doReset,
            })
        else
            doReset()
        end
    end)

    local function refreshCurrentTab()
        switchTab(dialog._moneyLogTab or "all")
        C_Timer.After(0, function()
            if not dialog or not dialog.IsShown or not dialog:IsShown() then return end
            local isContrib = dialog._moneyLogTab == "contributions"
            SyncMoneyLogScrollBar(isContrib and contribScroll or logScroll)
            RefreshMoneyLogScrollChrome(isContrib and contribScroll or logScroll)
        end)
    end

    dialog:SetScript("OnShow", refreshCurrentTab)
    -- Theme refresh hooks (ns.CharacterBankMoneyLogPopup.RefreshTheme): header ink + row ink repaint.
    dialog._wnMoneyLogHeaderStrips = { logHeaderStrip, contribHeaderStrip }
    dialog._wnMoneyLogRefresh = refreshCurrentTab

    WarbandNexus.UnregisterMessage(dialog, E.CHARACTER_BANK_MONEY_LOG_UPDATED)
    WarbandNexus.RegisterMessage(dialog, E.CHARACTER_BANK_MONEY_LOG_UPDATED, function()
        if dialog:IsShown() then
            refreshCurrentTab()
        end
    end)
    local oldOnHide = dialog:GetScript("OnHide")
    dialog:SetScript("OnHide", function()
        if oldOnHide then oldOnHide() end
        WarbandNexus.UnregisterMessage(dialog, E.CHARACTER_BANK_MONEY_LOG_UPDATED)
    end)

    switchTab(dialog._moneyLogTab or "all")
    dialog:Show()
end

ns.CharacterBankMoneyLogPopup = ns.CharacterBankMoneyLogPopup or {}
function ns.CharacterBankMoneyLogPopup.RefreshTheme()
    local d = _G.WarbandNexus_CharacterBankMoneyLogPopup
    if not (d and d:IsShown()) then return end
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(d)
    end
    local strips = d._wnMoneyLogHeaderStrips
    if strips then
        for i = 1, #strips do strips[i]:RefreshTheme() end
    end
    if d._wnMoneyLogRefresh then d._wnMoneyLogRefresh() end
end

-- (Popup opens through WarbandNexus:ShowCharacterBankMoneyLogPopup — see ItemsUI.)
