--[[
    Warband Nexus - SharedWidgets TabLayout (split from SharedWidgets.lua)
    Sub-tab bar, main tab layout metrics, tab chrome stack, scroll bar column sync.
    Loaded right after Modules/UI/SharedWidgets.lua (TOC) so every later file still finds these ns.UI_* exports.
]]

local _, ns = ...
assert(ns.UI and ns.UI_ApplyVisuals and ns.UI_CreateCard, "SharedWidgets_TabLayout: load after SharedWidgets.lua")
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local FontManager = ns.FontManager
local ThemeAPI = ns.UITheme.ThemeAPI
local COLORS = ns.UITheme.COLORS
local UI_SPACING = ns.UI_SPACING
local IsLightModeEnabled = ns.UI_IsLightMode
local IsClassicModeEnabled = ns.UI_IsClassicMode
local ApplyVisuals = ns.UI_ApplyVisuals

--- Shared horizontal sub-tab strip metrics (Collections, To-Do, Items bank).
local function GetSubTabLayout()
    local layout = ns.UI_LAYOUT or {}
    local st = layout.SUB_TAB or {}
    return {
        btnHeight = st.BTN_HEIGHT or 40,
        btnSpacing = st.BTN_SPACING or 8,
        iconSize = st.ICON_SIZE or 28,
        iconLeft = st.ICON_LEFT or 10,
        iconTextGap = st.ICON_TEXT_GAP or 8,
        textRight = st.TEXT_RIGHT or 10,
        defaultWidth = st.DEFAULT_WIDTH or 150,
        activeBarHeight = st.ACTIVE_BAR_HEIGHT or 3,
        activeBarInset = st.ACTIVE_BAR_INSET or 8,
        activeBarBottom = st.ACTIVE_BAR_BOTTOM or 4,
    }
end
ns.UI_GetSubTabLayout = GetSubTabLayout

local function SubTabIdleBackdrop()
    if ns.UI_GetNavTabInactiveBackdrop then
        return ns.UI_GetNavTabInactiveBackdrop()
    end
    local row = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
    return { row[1], row[2], row[3], row[4] or 1 }
end

local function SubTabHoverBackdrop()
    if ns.UI_GetControlChromeHoverBackdrop then
        return ns.UI_GetControlChromeHoverBackdrop()
    end
    return SubTabIdleBackdrop()
end

--- Apply idle/active chrome for horizontal sub-tab buttons (theme-aware light/dark/classic).
function ns.UI_ApplySubTabButtonVisuals(btn, isActive, accent)
    if not btn then return end
    local acc = accent or COLORS.accent or { 0.40, 0.20, 0.58 }
    if btn._wnBlizzardButton then
        if ns.UI_NormalizeBlizzardButtonChrome then
            ns.UI_NormalizeBlizzardButtonChrome(btn)
        elseif ns.UI_ApplyClassicNavTabActiveState then
            ns.UI_ApplyClassicNavTabActiveState(btn, isActive)
        end
        if btn.activeBar and btn.activeBar.Hide then
            btn.activeBar:Hide()
        end
        if btn._text then
            if isActive then
                if ns.UI_GetSemanticGoldColor then
                    local gr, gg, gb = ns.UI_GetSemanticGoldColor()
                    btn._text:SetTextColor(gr, gg, gb)
                else
                    ns.UI_SetTextColorRole(btn._text, "Bright")
                end
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(btn._text, true)
                end
            elseif btn.IsEnabled and btn:IsEnabled() then
                ns.UI_SetTextColorRole(btn._text, "Muted")
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(btn._text, false)
                end
            else
                ns.UI_SetTextColorRole(btn._text, "Dim")
            end
        end
        return
    end
    local canCustom = not ns.UI_CanApplyCustomChrome or ns.UI_CanApplyCustomChrome(btn)
    local updateBorder = ns.UI_UpdateBorderColor
    if isActive then
        local ar, ag, ab, aa
        if ThemeAPI.GetSubTabActiveBackdropRGBA then
            ar, ag, ab, aa = ThemeAPI.GetSubTabActiveBackdropRGBA(acc)
        else
            ar, ag, ab, aa = acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1
        end
        if canCustom and ApplyVisuals then
            ApplyVisuals(btn, { ar, ag, ab, aa }, { acc[1], acc[2], acc[3], 1 })
        end
        if btn._text then
            ns.UI_SetTextColorRole(btn._text, "Bright")
            if ns.UI_SetNavLabelFontStyle then
                ns.UI_SetNavLabelFontStyle(btn._text, true)
            end
        end
        if canCustom then
            if updateBorder then updateBorder(btn, { acc[1], acc[2], acc[3], 1 }) end
            if btn.SetBackdropColor then btn:SetBackdropColor(ar, ag, ab, aa) end
        end
    else
        local idle = SubTabIdleBackdrop()
        local br, bgr, bbb, bba
        if ThemeAPI.GetSubTabInactiveBorderRGBA then
            br, bgr, bbb, bba = ThemeAPI.GetSubTabInactiveBorderRGBA(acc)
        else
            br, bgr, bbb, bba = acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 0.6
        end
        if canCustom and ApplyVisuals then
            ApplyVisuals(btn, idle, { br, bgr, bbb, bba })
        end
        if btn._text then
            if btn.IsEnabled and btn:IsEnabled() then
                ns.UI_SetTextColorRole(btn._text, "Muted")
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(btn._text, false)
                end
            else
                ns.UI_SetTextColorRole(btn._text, "Dim")
            end
        end
        if canCustom then
            if updateBorder then updateBorder(btn, { br, bgr, bbb, bba }) end
            if btn.SetBackdropColor then btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 1) end
        end
    end
end

--- Atlas or file icon for sub-tab buttons (`icon`, `iconAtlas`, optional `iconFallback`).
function ns.UI_ApplySubTabIcon(tex, tabInfo, iconSize)
    if not tex or not tabInfo then return end
    local L = GetSubTabLayout()
    local sz = (iconSize or L.iconSize) - 2
    tex:SetTexture(nil)
    if tabInfo.iconAtlas then
        local ok = pcall(function()
            tex:SetAtlas(tabInfo.iconAtlas, false)
        end)
        if ok then
            tex:SetSize(sz, sz)
            tex:SetSnapToPixelGrid(false)
            tex:SetTexelSnappingBias(0)
            return
        end
    end
    tex:SetTexture(tabInfo.icon or tabInfo.iconFallback or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetSize(sz, sz)
end

--- Horizontal sub-tab bar shared by Collections, To-Do, and Items bank strips.
--- opts: `{ tabs, activeKey, onSelect, maxWidth, wrapRows, rightReserve, accent,
---          btnHeight, btnSpacing, iconLeft, textRight, activeBarInset, activeBarBottom }`
--- tabs[]: `{ key, label|name, icon?, iconAtlas?, iconFallback?, disabled?, hideIcon? }`
function ns.UI_CreateSubTabBar(parent, opts)
    opts = type(opts) == "table" and opts or {}
    local tabs = opts.tabs or {}
    local L = GetSubTabLayout()
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateContainer or not Factory.CreateButton then return nil end

    local accent = opts.accent or COLORS.accent or { 0.40, 0.20, 0.58 }
    local btnHeight = opts.btnHeight or L.btnHeight
    local btnSpacing = opts.btnSpacing or L.btnSpacing
    local iconLeft = opts.iconLeft or L.iconLeft
    local textRight = opts.textRight or L.textRight
    local activeBarInset = opts.activeBarInset or L.activeBarInset
    local activeBarBottom = opts.activeBarBottom or L.activeBarBottom
    local bar = Factory:CreateContainer(parent, 400, btnHeight, false)
    if not bar then return nil end

    local barHost = bar
    local rightReserve = opts.rightReserve or 0
    if rightReserve > 0 then
        local btnArea = Factory:CreateContainer(bar, 200, btnHeight, false)
        if btnArea then
            btnArea:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
            btnArea:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -rightReserve, 0)
            barHost = btnArea
        end
    end

    local btnWidths = {}
    for i = 1, #tabs do
        local tabInfo = tabs[i]
        local label = tabInfo.label or tabInfo.name or tabInfo.key or ""
        local tempFs = FontManager:CreateFontString(bar, "body", "OVERLAY")
        tempFs:SetText(label)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local hideIcon = tabInfo.hideIcon
        local needed = hideIcon
            and (iconLeft + textW + textRight)
            or (iconLeft + L.iconSize + L.iconTextGap + textW + textRight)
        btnWidths[i] = hideIcon and needed or math.max(needed, L.defaultWidth)
    end

    local maxWidth = opts.maxWidth
    local wrapRows = opts.wrapRows
    local buttons = {}
    local xPos = 0
    local currentRow = 0

    for i = 1, #tabs do
        local tabInfo = tabs[i]
        local tabKey = tabInfo.key
        local label = tabInfo.label or tabInfo.name or tabKey
        local btnWidth = btnWidths[i]
        local isActive = (tabKey == opts.activeKey)

        if wrapRows and maxWidth and xPos + btnWidth > maxWidth and xPos > 0 then
            xPos = 0
            currentRow = currentRow + 1
        end

        local btn
        if IsClassicModeEnabled() then
            btn = CreateFrame("Button", nil, barHost, "UIPanelButtonTemplate")
            btn:SetSize(btnWidth, btnHeight)
            btn._wnBlizzardButton = true
            if ns.UI_NormalizeBlizzardButtonChrome then
                ns.UI_NormalizeBlizzardButtonChrome(btn)
            end
        else
            btn = Factory:CreateButton(barHost, btnWidth, btnHeight)
        end
        if not btn then return nil end
        btn:SetPoint("TOPLEFT", barHost, "TOPLEFT", xPos, -(currentRow * (btnHeight + btnSpacing)))
        btn._tabKey = tabKey

        if not btn._wnBlizzardButton and Factory.ApplyHighlight then
            Factory:ApplyHighlight(btn)
        end

        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(L.activeBarHeight)
        activeBar:SetPoint("BOTTOMLEFT", activeBarInset, activeBarBottom)
        activeBar:SetPoint("BOTTOMRIGHT", -activeBarInset, activeBarBottom)
        activeBar:SetColorTexture(accent[1], accent[2], accent[3], 1)
        activeBar:SetAlpha(isActive and 1 or 0)
        btn.activeBar = activeBar
        if btn._wnBlizzardButton then
            activeBar:Hide()
        end

        local btnIcon = btn:CreateTexture(nil, "ARTWORK")
        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText._wnNavLabel = true
        if tabInfo.hideIcon then
            btnIcon:Hide()
            btnText:SetPoint("LEFT", btn, "LEFT", iconLeft, 0)
        else
            ns.UI_ApplySubTabIcon(btnIcon, tabInfo)
            btnIcon:SetPoint("LEFT", iconLeft, 0)
            btnText:SetPoint("LEFT", btnIcon, "RIGHT", L.iconTextGap, 0)
        end
        btnText:SetPoint("RIGHT", btn, "RIGHT", -textRight, 0)
        btnText:SetText(label)
        btnText:SetJustifyH("LEFT")
        btnText:SetWordWrap(false)
        btn._text = btnText

        btn._active = isActive
        ns.UI_ApplySubTabButtonVisuals(btn, isActive, accent)

        btn:SetScript("OnClick", function()
            if opts.onSelect then opts.onSelect(tabKey) end
        end)

        if not btn._wnBlizzardButton then
            local updateBorder = ns.UI_UpdateBorderColor
            if updateBorder then
                btn:SetScript("OnEnter", function(self)
                    if self._active then return end
                    updateBorder(self, { accent[1] * 1.2, accent[2] * 1.2, accent[3] * 1.2, 0.9 })
                end)
                btn:SetScript("OnLeave", function(self)
                    if self._active then return end
                    local br, bgr, bbb, bba = ThemeAPI.GetSubTabInactiveBorderRGBA(accent)
                    updateBorder(self, { br, bgr, bbb, bba })
                end)
            else
                btn:SetScript("OnEnter", function(self)
                    if self._active then return end
                    if self.SetBackdropColor then
                        local hover = SubTabHoverBackdrop()
                        self:SetBackdropColor(hover[1], hover[2], hover[3], hover[4] or 0.95)
                    end
                end)
                btn:SetScript("OnLeave", function(self)
                    if self._active then return end
                    if self.SetBackdropColor then
                        local idle = SubTabIdleBackdrop()
                        self:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 1)
                    end
                end)
            end
        end

        if tabInfo.disabled then
            btn:Disable()
            btn:SetAlpha(0.5)
            ns.UI_ApplySubTabButtonVisuals(btn, false, accent)
        end

        buttons[tabKey] = btn
        xPos = xPos + btnWidth + btnSpacing
    end

    local totalHeight = wrapRows
        and ((currentRow + 1) * btnHeight + currentRow * btnSpacing)
        or btnHeight
    bar:SetHeight(totalHeight)
    bar.buttons = buttons

    function bar:SetActiveTab(key)
        for k, btn in pairs(buttons) do
            local active = (k == key)
            btn._active = active
            if btn.activeBar then
                if btn._wnBlizzardButton then
                    btn.activeBar:Hide()
                else
                    btn.activeBar:SetAlpha(active and 1 or 0)
                end
            end
            ns.UI_ApplySubTabButtonVisuals(btn, active, accent)
        end
    end

    return bar
end

--- Compact rail width for main shell body (below header): ratio of inner width, clamped.
---@return number railWidth
function ns.UI_ComputeGoldenRailWidth(innerBodyWidth, shell)
    shell = shell or (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local ratio = shell.NAV_RAIL_WIDTH_RATIO or 0.17
    local minW = shell.NAV_RAIL_WIDTH_MIN or 148
    local maxW = shell.NAV_RAIL_WIDTH_MAX or 192
    local usable = math.max(360, tonumber(innerBodyWidth) or 800)
    local railW = math.floor(usable * ratio + 0.5)
    if railW < minW then railW = minW end
    if railW > maxW then railW = maxW end
    return railW
end

--- Unified scroll-area metrics for tab painters (header, results, cards).
---@return table|nil metrics { contentWidth, sideMargin, topMargin, sectionGap }
function ns.UI_GetMainTabLayoutMetrics(mainFrame)
    if not mainFrame then return nil end
    local layout = ns.UI_LAYOUT or {}
    local shell = layout.MAIN_SHELL or {}
    local scroll = layout.MAIN_SCROLL or {}
    local side = shell.CONTENT_PAD_X or scroll.CONTENT_PAD_X or layout.SIDE_MARGIN or 12
    local titleTopGap = shell.TAB_CHROME_TITLE_TOP_GAP or layout.TAB_CHROME_TITLE_TOP_GAP or 0
    local top = (shell.CONTENT_PAD_TOP or scroll.CONTENT_PAD_TOP or layout.topMargin or 0) + titleTopGap
    local gap = shell.CONTENT_SECTION_GAP or layout.SECTION_SPACING or 10
    local contentW = (ns.UI_GetMainScrollContentWidth and ns.UI_GetMainScrollContentWidth(mainFrame)) or 600
    local titleH = layout.TITLE_CARD_DEFAULT_HEIGHT or 64
    local blockGap = layout.TAB_CHROME_BLOCK_GAP or 8
    local scrollTop = layout.TAB_CHROME_SCROLL_TOP or 8
    local bottomPad = layout.TAB_CHROME_CONTENT_BOTTOM_PAD or 12
    return {
        contentWidth = contentW,
        bodyWidth = math.max(200, contentW - side * 2),
        sideMargin = side,
        topMargin = top,
        sectionGap = gap,
        cardGap = layout.CARD_GAP or 10,
        titleCardHeight = titleH,
        blockGap = blockGap,
        scrollTop = scrollTop,
        contentBottomPad = bottomPad,
        goldenRatio = shell.GOLDEN_RATIO or 1.6180339887,
    }
end

--- Top inset inside Items resultsContainer before list or empty card (parity across Bags / Warband / Guild).
---@return number
function ns.UI_ItemsResultsTopGap(baseYOffset)
    local layout = ns.UI_LAYOUT or {}
    return (baseYOffset or 0) + (layout.SECTION_SPACING or 8)
end

--- Symmetric horizontal inset for tab body (MAIN_SHELL.CONTENT_PAD_X / SIDE_MARGIN).
---@return number
function ns.UI_GetTabSideMargin()
    local layout = ns.UI_LAYOUT or {}
    local shell = layout.MAIN_SHELL or {}
    local scroll = layout.MAIN_SCROLL or {}
    return shell.CONTENT_PAD_X or scroll.CONTENT_PAD_X or layout.SIDE_MARGIN or layout.sideMargin or 12
end

--- Scroll viewport width (between scroll chrome). Replaces legacy full-width guesses.
---@return number contentWidth
---@return table|nil metrics
function ns.UI_ResolveMainTabContentWidth(mainFrame, parent)
    if mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.contentWidth and m.contentWidth > 0 then
            return m.contentWidth, m
        end
    end
    if mainFrame and ns.UI_GetMainScrollContentWidth then
        local vw = ns.UI_GetMainScrollContentWidth(mainFrame)
        if vw and vw > 0 then
            return vw, nil
        end
    end
    if parent and parent.GetWidth then
        local pw = parent:GetWidth()
        if pw and pw > 0 then
            return pw, nil
        end
    end
    return 600, nil
end

--- Inner body width after symmetric side insets (`bodyWidth` in metrics). Replaces `parent:GetWidth() - 20`.
---@return number bodyWidth
---@return table|nil metrics
function ns.UI_ResolveMainTabBodyWidth(mainFrame, parent)
    if mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.bodyWidth and m.bodyWidth > 0 then
            return m.bodyWidth, m
        end
        if m and m.contentWidth and m.contentWidth > 0 then
            local side = m.sideMargin or ns.UI_GetTabSideMargin()
            return math.max(200, m.contentWidth - side * 2), m
        end
    end
    local side = ns.UI_GetTabSideMargin()
    local contentW = (ns.UI_ResolveMainTabContentWidth(mainFrame, parent))
    return math.max(200, contentW - side * 2), nil
end

--- List paint width inside `resultsContainer` (incremental redraw / Draw*List).
---@return number
function ns.UI_ResolveResultsContainerPaintWidth(mainFrame, resultsContainer)
    if resultsContainer and resultsContainer.GetWidth then
        local rw = resultsContainer:GetWidth()
        if rw and rw > 1 then
            return rw
        end
    end
    local scrollChild = mainFrame and mainFrame.scrollChild
    return ns.UI_ResolveMainTabBodyWidth(mainFrame, scrollChild)
end

--- Begin fixedHeader layout pass for a tab (unified top inset + side margins).
---@return table|nil chrome { mainFrame, headerParent, metrics, yOffset, side }
function ns.UI_BeginTabChromeLayout(mainFrame)
    if not mainFrame then return nil end
    local headerParent = mainFrame.fixedHeader
    if not headerParent then return nil end
    local metrics = ns.UI_GetMainTabLayoutMetrics(mainFrame)
    if not metrics then return nil end
    return {
        mainFrame = mainFrame,
        headerParent = headerParent,
        metrics = metrics,
        yOffset = metrics.topMargin or 0,
        side = metrics.sideMargin or 12,
    }
end

--- Anchor a title card on the fixedHeader chrome row.
function ns.UI_AnchorTabTitleCard(titleCard, chrome)
    if not titleCard or not chrome or not chrome.headerParent then return end
    local y = chrome.yOffset or 0
    local side = chrome.side or 12
    titleCard:ClearAllPoints()
    titleCard:SetPoint("TOPLEFT", chrome.headerParent, "TOPLEFT", side, -y)
    titleCard:SetPoint("TOPRIGHT", chrome.headerParent, "TOPRIGHT", -side, -y)
end

--- Advance chrome Y after a fixedHeader block (title card, sub-tab bar, search row, …).
---@return number
function ns.UI_AdvanceTabChromeYOffset(yOffset, blockHeight, gapAfter)
    local sp = UI_SPACING or {}
    gapAfter = gapAfter or sp.TAB_CHROME_BLOCK_GAP or 8
    return (yOffset or 0) + (blockHeight or 0) + gapAfter
end

--- Commit fixedHeader height after laying out chrome blocks.
---@return number
function ns.UI_CommitTabFixedHeader(mainFrame, yOffset)
    if mainFrame and mainFrame.fixedHeader then
        mainFrame.fixedHeader:SetHeight(math.max(1, yOffset or 1))
        local fh = mainFrame.fixedHeader
        if fh._wnHairlinebottom and fh._wnHairlinebottom.Hide then
            fh._wnHairlinebottom:Hide()
        end
    end
    return yOffset or 0
end

--- PAGE STACK helpers (see UI_LAYOUT.PAGE_STACK). Create paths and Reposition* paths must both
--- place chrome through these so a cached repaint can never drift from the first paint.

---Place a fixedHeader block (title card, sub-tab bar, search box, stats line) at the current
---chrome Y with symmetric +/-side anchors, then advance by height + gap.
---@param chrome table from UI_BeginTabChromeLayout
---@param frame Frame
---@param height number|nil block height (nil = frame:GetHeight())
---@param gapKey string|nil PAGE_STACK key for the gap after the block (default "BLOCK_GAP")
---@return number newYOffset
function ns.UI_PageStack_Place(chrome, frame, height, gapKey)
    if not chrome or not frame or not chrome.headerParent then
        return chrome and chrome.yOffset or 0
    end
    local ps = (UI_SPACING and UI_SPACING.PAGE_STACK) or {}
    local y = chrome.yOffset or 0
    local side = chrome.side or ps.SIDE or 12
    if frame:GetParent() ~= chrome.headerParent then
        frame:SetParent(chrome.headerParent)
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", chrome.headerParent, "TOPLEFT", side, -y)
    frame:SetPoint("TOPRIGHT", chrome.headerParent, "TOPRIGHT", -side, -y)
    if height then frame:SetHeight(height) end
    local h = height or frame:GetHeight() or 0
    local gap = ps[gapKey or "BLOCK_GAP"]
    if gap == nil then gap = ps.BLOCK_GAP or 8 end
    chrome.yOffset = y + h + gap
    return chrome.yOffset
end

---Anchor a top-level body block (results container, content frame, empty-state host) inside the
---scroll child with symmetric +/-side anchors at the same Y. Returns the body width.
---@param parent Frame scroll child (or another full-width body host)
---@param frame Frame
---@param y number top offset (positive, downward); default PAGE_STACK.BODY_TOP
---@return number bodyWidth
function ns.UI_PageStack_AnchorBody(parent, frame, y)
    if not parent or not frame then return 0 end
    local ps = (UI_SPACING and UI_SPACING.PAGE_STACK) or {}
    local side = ps.SIDE or 12
    y = y or ps.BODY_TOP or 8
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", side, -y)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -side, -y)
    return math.max(1, (parent:GetWidth() or 0) - side * 2)
end

--- Debug tint overlays for scroll viewport / bar column (toggle: `/wn debug on`).
---@param scrollFrame ScrollFrame|nil
---@param barColumn Frame|nil
---@param viewportBorder Frame|nil optional main-shell viewport rim
function ns.UI_ApplyScrollLayoutDebugChrome(scrollFrame, barColumn, viewportBorder)
    local enabled = ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()
    local function ensureBg(frame, key, r, g, b, a)
        if not frame then return end
        local tex = frame[key]
        if not enabled then
            if tex and tex.Hide then tex:Hide() end
            return
        end
        if not tex then
            tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
            tex:SetAllPoints(frame)
            frame[key] = tex
        end
        tex:SetColorTexture(r, g, b, a)
        tex:Show()
    end
    ensureBg(viewportBorder, "_wnDebugViewportRimBg", 0.95, 0.45, 0.08, 0.12)
    ensureBg(scrollFrame, "_wnDebugScrollViewportBg", 0.12, 0.38, 0.92, 0.20)
    ensureBg(barColumn, "_wnDebugBarColumnBg", 0.12, 0.78, 0.28, 0.38)
end

--- Re-anchor main-window scrollbar lanes (matches CreateMainWindow in Modules/UI.lua).
function ns.UI_SyncMainScrollBarColumns(mainFrame)
    if not mainFrame or not mainFrame.scroll then return end
    local content = mainFrame.content
    local col = mainFrame.scrollBarColumn
    if not content or not col then return end

    local layout = ns.UI_LAYOUT or {}
    local ms = layout.MAIN_SCROLL or {}
    local hints = ns.UI_GetMainScrollLayoutHints and ns.UI_GetMainScrollLayoutHints() or {}
    local colW = (col.GetWidth and col:GetWidth()) or hints.scrollbarColumnWidth or 26
    local scrollGap = hints.scrollGap or ms.SCROLL_GAP or 2
    local scrollInsetLeft = hints.scrollInsetLeft or ms.SCROLL_INSET_LEFT or 4
    local scrollInsetRight = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
        or (colW + scrollGap)
    local hBarBottom = hints.horizontalLaneBottomOffset or ms.H_BAR_BOTTOM_OFFSET or 6
    local hRowH = colW

    if ns.UI.Factory and ns.UI.Factory.EnsureScrollBarColumnSync then
        ns.UI.Factory:EnsureScrollBarColumnSync(mainFrame.scroll, col, { width = colW, gap = scrollGap })
    elseif ns.UI.Factory and ns.UI.Factory.SyncScrollBarColumnToViewport then
        ns.UI.Factory:SyncScrollBarColumnToViewport(mainFrame.scroll, col, { width = colW, gap = scrollGap })
    end

    local hCont = mainFrame.hScrollContainer
    if hCont then
        hCont:ClearAllPoints()
        hCont:SetPoint("LEFT", content, "LEFT", scrollInsetLeft, 0)
        hCont:SetPoint("RIGHT", content, "RIGHT", -scrollInsetRight, 0)
        hCont:SetPoint("BOTTOM", content, "BOTTOM", 0, hBarBottom)
        hCont:SetHeight(hRowH)
        if mainFrame.hScroll and mainFrame.hScroll.PositionInContainer then
            mainFrame.hScroll:PositionInContainer(hCont, 0)
        end
    end

    if ns.UI.Factory and ns.UI.Factory.DeferScrollBarVisibility and mainFrame.scroll then
        ns.UI.Factory:DeferScrollBarVisibility(mainFrame.scroll)
    end
    if ns.UI_ApplyScrollLayoutDebugChrome then
        ns.UI_ApplyScrollLayoutDebugChrome(mainFrame.scroll, col, mainFrame.viewportBorder)
    end
end

--- Canonical: bar column outside scroll viewport (Button | track | Button full viewport height).
function ns.UI_SyncScrollBarColumnToViewport(scrollFrame, barColumn, opts)
    if ns.UI.Factory and ns.UI.Factory.SyncScrollBarColumnToViewport then
        ns.UI.Factory:SyncScrollBarColumnToViewport(scrollFrame, barColumn, opts)
    end
end

--- Sync bar column to scroll viewport and install OnSizeChanged resize hook (chains prior handler).
function ns.UI_EnsureScrollBarColumnSync(scrollFrame, barColumn, opts)
    if ns.UI.Factory and ns.UI.Factory.EnsureScrollBarColumnSync then
        ns.UI.Factory:EnsureScrollBarColumnSync(scrollFrame, barColumn, opts)
    end
end

--- First Y offset inside scrollChild for tab body content (below fixedHeader).
---@return number
function ns.UI_GetTabScrollContentStartY()
    local sp = UI_SPACING or {}
    return sp.TAB_CHROME_SCROLL_TOP or 8
end

--- Y inside scrollChild when a column-header strip sits flush under the title card (PvE / Professions).
---@return number
function ns.UI_GetTabColumnHeaderScrollTop()
    return 0
end

--- Scroll child bottom padding (PopulateContent post-layout).
---@return number
function ns.UI_GetTabScrollContentBottomPad()
    local sp = UI_SPACING or {}
    return sp.TAB_CHROME_CONTENT_BOTTOM_PAD or 12
end

--- Scroll body height between fixedHeader and footer (viewport minus top/bottom chrome insets).
---@return number
function ns.UI_GetMainTabScrollBodyHeight(mainFrame)
    if not mainFrame or not mainFrame.scroll then return 0 end
    local viewportH = mainFrame.scroll:GetHeight() or 0
    if viewportH < 2 and mainFrame.fixedHeader then
        local fhBot = mainFrame.fixedHeader:GetBottom()
        local sb = mainFrame.scroll:GetBottom()
        if fhBot and sb and fhBot > sb then
            viewportH = fhBot - sb
        end
    end
    local scrollTop = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    local bottomPad = (ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12
    return math.max(0, viewportH - scrollTop - bottomPad)
end

--- Rail tab active / idle visuals (subtle outer glow on selected tab).
function ns.UI_ApplyRailTabActiveVisuals(btn, isActive, accentColor)
    if not btn or not btn._wnRailTextMode then return end
    if btn._wnBlizzardButton then return end
    local ac = accentColor or (COLORS and COLORS.accent) or { 0.6, 0.4, 1 }
    local glow = btn._wnRailActiveGlow
    local glowInner = btn._wnRailActiveGlowInner
    if glow then glow:Hide() end
    if glowInner then glowInner:Hide() end
    if isActive then
        if not btn._wnRailActiveStripe then
            btn._wnRailActiveStripe = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        local stripe = btn._wnRailActiveStripe
        stripe:SetWidth(3)
        stripe:ClearAllPoints()
        stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -2)
        stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 2)
        local sa = IsLightModeEnabled() and 0.98 or 0.92
        stripe:SetColorTexture(ac[1], ac[2], ac[3], sa)
        stripe:Show()
        if ns.UI_RegisterAccentStripe then
            ns.UI_RegisterAccentStripe(stripe)
        end
    elseif btn._wnRailActiveStripe then
        btn._wnRailActiveStripe:Hide()
    end
end

--- Scroll viewport width for active main tab (after golden rail + insets).
---@return number
--- Shell / content / scroll canvas background (unified panel tone).
---@return table {r,g,b,a}
function ns.UI_GetMainPanelBackgroundColor()
    local C = COLORS or ns.UI_COLORS
    return (C and (C.surfaceViewport or C.bg)) or { 0.130, 0.130, 0.155, 0.98 }
end

--- Live viewport width for responsive tab layout (scroll frame, not frozen scrollChild).
--- Prefer over `scrollChild:GetWidth()` during corner-drag resize sessions.
function ns.UI_GetMainTabViewportWidth(mainFrame)
    return (ns.UI_GetMainScrollContentWidth and ns.UI_GetMainScrollContentWidth(mainFrame)) or 0
end

function ns.UI_GetMainScrollContentWidth(mainFrame)
    if not mainFrame then return 0 end
    if mainFrame.scroll and mainFrame.scroll.GetWidth then
        local w = mainFrame.scroll:GetWidth()
        if w and w > 0 then return w end
    end
    if mainFrame.scrollChild and mainFrame.scrollChild.GetWidth then
        local w = mainFrame.scrollChild:GetWidth()
        if w and w > 0 then return w end
    end
    if mainFrame.content and mainFrame.content.GetWidth then
        local layout = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
        local gap = layout.NAV_RAIL_CONTENT_GAP or 10
        local reserve = 32 + gap
        return math.max(200, (mainFrame.content:GetWidth() or 0) - reserve)
    end
    return 600
end

assert(ns.UI_CreateSubTabBar and ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainScrollContentWidth, "SharedWidgets_TabLayout: exports missing")
