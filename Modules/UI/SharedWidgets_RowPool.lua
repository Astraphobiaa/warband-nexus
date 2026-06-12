--[[
    Warband Nexus - SharedWidgets SharedWidgets_RowPool (ops-028 slice)
    Loaded after Modules/UI/SharedWidgets.lua core exports.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local issecretvalue = issecretvalue

ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

local COLORS = ns.UI_COLORS
local UI_SPACING = ns.UI_SPACING
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING
local GetPixelScale = ns.GetPixelScale
local PixelSnap = ns.PixelSnap
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateButton = ns.UI_CreateButton
local CreateIcon = ns.UI_CreateIcon
local GetColors = function() return ns.UI_COLORS end
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

local function ResolveSurfaceTierColor(tier)
    if ns.UI_ResolveSurfaceTierColor then
        return ns.UI_ResolveSurfaceTierColor(tier)
    end
    local C = COLORS or {}
    if tier == "rowEven" then
        return C.surfaceRowEven or (UI_SPACING and UI_SPACING.ROW_COLOR_EVEN) or { 0.112, 0.112, 0.138, 0.96 }
    elseif tier == "rowOdd" then
        return C.surfaceRowOdd or (UI_SPACING and UI_SPACING.ROW_COLOR_ODD) or { 0.090, 0.090, 0.112, 0.96 }
    end
    return C.bg or { 0.065, 0.065, 0.082, 0.98 }
end

--- Characters tab row: horizontal class tint (Gear model–style: class×0.5, no additive white).
--- @param gradientWidthPx number|nil  Width from row left edge (px). When set, gradient ends at identity text block; else ~17.5% row width fallback.
--- Call after ApplyRowBackground / ApplyOnlineCharacterHighlight so row.bg exists for blend target.
local ROW_CLASS_GRADIENT_WIDTH_FRAC = 0.175
local function ApplyCharacterRowClassGradientAccent(row, classFile, gradientWidthPx)
    if not row then return end
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then
        if row._wnClassGradientTex then
            row._wnClassGradientTex:Hide()
        end
        return
    end

    local r, g, b = cc.r, cc.g, cc.b
    local br, bgc, bb = 0.08, 0.08, 0.10
    if row.bg and row.bg.GetVertexColor then
        br, bgc, bb = row.bg:GetVertexColor()
    end

    local rw = row:GetWidth() or row._wnRowPaintWidth or 200
    local rh = row:GetHeight() or 46
    local w
    if type(gradientWidthPx) == "number" and gradientWidthPx > 1 then
        w = math.max(8, math.min(rw, gradientWidthPx))
    else
        w = math.max(6, rw * ROW_CLASS_GRADIENT_WIDTH_FRAC)
    end

    local tex = row._wnClassGradientTex
    if not tex then
        -- ARTWORK stays visible on pooled Button rows during scroll (BORDER can drop out with highlight).
        tex = row:CreateTexture(nil, "ARTWORK")
        row._wnClassGradientTex = tex
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    tex:SetSize(w, rh)
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetDrawLayer then
        tex:SetDrawLayer("ARTWORK", 0)
    end
    if row.GetFrameLevel and tex.SetFrameLevel then
        tex:SetFrameLevel(row:GetFrameLevel() + 1)
    end

    local ok = false
    if tex.SetGradient and CreateColor then
        -- Class tint: closer to RAID_CLASS_COLORS (readable hue); right stop still alpha 0.
        local tR = math.min(1, r * 0.58)
        local tG = math.min(1, g * 0.58)
        local tB = math.min(1, b * 0.58)
        local cL = CreateColor(tR, tG, tB, 0.42)
        local cR = CreateColor(br, bgc, bb, 0)
        ok = pcall(function()
            tex:SetGradient("HORIZONTAL", cL, cR)
        end)
        if not ok and Enum and Enum.GradientOrientation and Enum.GradientOrientation.Horizontal then
            ok = pcall(function()
                tex:SetGradient(Enum.GradientOrientation.Horizontal, cL, cR)
            end)
        end
    end
    if not ok then
        tex:SetColorTexture(
            math.min(1, r * 0.34 + br * 0.66),
            math.min(1, g * 0.34 + bgc * 0.66),
            math.min(1, b * 0.34 + bb * 0.66),
            0.32
        )
    end
    tex:Show()
end

ns.UI_ApplyCharacterRowClassGradientAccent = ApplyCharacterRowClassGradientAccent

-- STRETCH ROW VIEWPORT RELAYOUT (shared across tabs)
-- Tabs register row lists on scrollChild; LayoutCoordinator live resize calls tab adapters
-- that delegate here. Characters virtual lists use VirtualListModule instead.

--- Refresh `_wnGradientRefresh` on visible rows (Characters / Professions / PvE chrome).
function ns.UI_RefreshRegisteredRowGradients(rows)
    if not rows then return end
    for ri = 1, #rows do
        local row = rows[ri]
        if row and row:IsShown() and row._wnGradientRefresh then
            pcall(row._wnGradientRefresh)
        end
    end
end

--- Re-anchor collapsible section bodies under their headers (full scroll width).
function ns.UI_RelayoutStretchSectionBodies(scrollChild, opts)
    opts = opts or {}
    local sections = opts.sections
    if not sections and scrollChild then
        sections = scrollChild._wnStretchSectionList
    end
    if not sections then return end
    local side = opts.sideMargin
    if side == nil then
        side = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 10
    end
    local anchorKey = opts.anchorKey or "_wnAnchorHeader"
    for si = 1, #sections do
        local cf = sections[si]
        local hdr = cf and cf[anchorKey]
        if cf and hdr then
            cf:ClearAllPoints()
            cf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", -side, 0)
            cf:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", side, 0)
            cf:SetHeight(math.max(0.1, cf._wnSectionFullH or 0.1))
        end
    end
end

--- Stretch TOPLEFT/TOPRIGHT rows to parent width; refresh stripes + class gradients.
--- opts: rows | rowsKey, sections, rowHeight, yOffsetKey, rowLeftPad, rowRightPad, sideMargin, refreshGradients
function ns.UI_RelayoutStretchRows(scrollChild, opts)
    if not scrollChild then return end
    opts = opts or {}
    if opts.sections or scrollChild._wnStretchSectionList then
        ns.UI_RelayoutStretchSectionBodies(scrollChild, opts)
    end
    local rows = opts.rows
    if not rows then
        local key = opts.rowsKey or "_wnStretchRowList"
        rows = scrollChild[key]
    end
    if not rows then return end
    local rowH = opts.rowHeight
    local yKey = opts.yOffsetKey or "_wnYOffset"
    local leftPad = opts.rowLeftPad or 0
    local rightPad = opts.rowRightPad or 0
    local refreshGradients = opts.refreshGradients ~= false
    for ri = 1, #rows do
        local row = rows[ri]
        if row and row:IsShown() then
            local parent = row:GetParent()
            if parent then
                local yOff = row[yKey] or 0
                row:ClearAllPoints()
                if rowH and row.SetHeight then
                    row:SetHeight(rowH)
                end
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad, -yOff)
                row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightPad, -yOff)
                local rowW = row:GetWidth()
                if (not rowW or rowW < 2) and parent.GetWidth then
                    rowW = parent:GetWidth()
                end
                if rowW and rowW >= 2 then
                    row._wnRowPaintWidth = rowW
                end
                if row.bg and row.bg.SetAllPoints then
                    row.bg:SetAllPoints()
                end
                if refreshGradients and row._wnGradientRefresh then
                    if rowW and rowW >= 2 then
                        pcall(row._wnGradientRefresh)
                    elseif C_Timer and C_Timer.After then
                        local rowRef = row
                        C_Timer.After(0, function()
                            if rowRef and rowRef:IsShown() and rowRef._wnGradientRefresh then
                                pcall(row._wnGradientRefresh)
                            end
                        end)
                    end
                end
            end
        end
    end
end

--- Viewport resize profiles for `UI_RegisterTabViewportResize` (LayoutCoordinator adapters).
ns.UI_VIEWPORT_RESIZE_MODE = {
    STRETCH_ROWS = "stretch_rows",
    RESULTS_CONTAINER = "results",
    CUSTOM = "custom",
}

local function ResolveTabSideMargin(mf, fallback)
    local side = fallback
    if side == nil then
        side = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    end
    if mf and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mf)
        if m and m.sideMargin then
            side = m.sideMargin
        end
    end
    return side
end

--- Results-annex tabs (Currency, Reputation): widen `resultsContainer` on viewport change.
---@return boolean handled
function ns.UI_RelayoutResultsViewport(scrollChild, contentWidth, mf, opts)
    opts = opts or {}
    if not scrollChild or not contentWidth or contentWidth < 1 then
        return false
    end
    local getContainer = opts.getContainer
    local rc = (getContainer and getContainer(scrollChild)) or scrollChild.resultsContainer
    if not rc then
        return false
    end
    local side = ResolveTabSideMargin(mf, opts.sideMargin)
    rc:SetWidth(math.max(1, contentWidth - side * 2))
    if ns.UI_RelayoutResultsContainer then
        ns.UI_RelayoutResultsContainer(rc, scrollChild, side, opts.bottomInset or 8)
    end
    return true
end

--- Register a tab with the standard viewport resize contract (live + commit via LayoutCoordinator).
--- Profile:
---   mode          UI_VIEWPORT_RESIZE_MODE.* (default CUSTOM)
---   tabKey        mf.currentTab value (default tabId)
---   freezeWhileResizing  skip live body work during corner-drag (Items/PvE/Chars pattern)
---   stretch       opts table | fn(scrollChild, contentWidth, mf) -> opts for UI_RelayoutStretchRows
---   results       { getContainer?, sideMargin?, bottomInset? }
---   onLive        fn -> boolean|nil handled (CUSTOM or pre-hook)
---   onLiveAfter   fn after stretch/results live pass
---   onCommit      fn -> boolean|nil; false/nil = allow PopulateContent on commit
---   refreshHeader run UI_RefreshFixedHeaderChrome on commit
function ns.UI_RegisterTabViewportResize(tabId, profile)
    local LC = ns.UI_LayoutCoordinator
    if not LC or not tabId or not profile then
        return
    end
    local mode = profile.mode or ns.UI_VIEWPORT_RESIZE_MODE.CUSTOM
    local tabKey = profile.tabKey or tabId

    local function TabIsActive(mf)
        return mf and mf.currentTab == tabKey
    end

    local function ResolveStretchOpts(scrollChild, contentWidth, mf)
        local stretch = profile.stretch
        if type(stretch) == "function" then
            return stretch(scrollChild, contentWidth, mf)
        end
        return stretch
    end

    local function RunStretchLive(scrollChild, contentWidth, mf)
        if profile.onLive then
            profile.onLive(scrollChild, contentWidth, mf)
        end
        local opts = ResolveStretchOpts(scrollChild, contentWidth, mf)
        if opts then
            ns.UI_RelayoutStretchRows(scrollChild, opts)
        end
        if profile.onLiveAfter then
            profile.onLiveAfter(scrollChild, contentWidth, mf)
        end
        return true
    end

    local function RunResultsLive(scrollChild, contentWidth, mf)
        if profile.onLive then
            profile.onLive(scrollChild, contentWidth, mf)
        end
        local handled = ns.UI_RelayoutResultsViewport(scrollChild, contentWidth, mf, profile.results)
        if profile.onLiveAfter then
            profile.onLiveAfter(scrollChild, contentWidth, mf)
        end
        return handled
    end

    LC:RegisterTabAdapter(tabId, {
        OnViewportWidthChanged = function(scrollChild, contentWidth, mf)
            if not TabIsActive(mf) then
                return false
            end
            if profile.freezeWhileResizing and ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mf) then
                return true
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.STRETCH_ROWS then
                return RunStretchLive(scrollChild, contentWidth, mf)
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.RESULTS_CONTAINER then
                return RunResultsLive(scrollChild, contentWidth, mf)
            end
            if profile.onLive then
                return profile.onLive(scrollChild, contentWidth, mf) == true
            end
            return false
        end,
        OnViewportLayoutCommit = function(scrollChild, contentWidth, mf)
            if not TabIsActive(mf) then
                return false
            end
            if profile.onCommit then
                local commitHandled = profile.onCommit(scrollChild, contentWidth, mf)
                if commitHandled ~= nil then
                    return commitHandled == true
                end
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.RESULTS_CONTAINER then
                return RunResultsLive(scrollChild, contentWidth, mf)
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.STRETCH_ROWS and profile.stretchCommitLive ~= false then
                RunStretchLive(scrollChild, contentWidth, mf)
            end
            if profile.refreshHeader and ns.UI_RefreshFixedHeaderChrome then
                ns.UI_RefreshFixedHeaderChrome(mf)
            end
            return profile.handledCommit == true
        end,
    })
end
--- Apply alternating row background color to any frame.
--- Central helper that replaces inline ROW_COLOR_EVEN/ODD logic across all tabs.
--- Works with both newly created rows and pooled/reused rows.
function ns.UI.Factory:ApplyRowBackground(row, rowIndex)
    if not row then return end
    local tier = (rowIndex % 2 == 0) and "rowEven" or "rowOdd"
    local bgColor = ResolveSurfaceTierColor(tier)
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    row.bgColor = bgColor
end

---Apply (or clear) the online-character highlight on a character row or header.
---Uses the live theme accent color so it respects user customization.
function ns.UI.Factory:ApplyOnlineCharacterHighlight(frame, isOnline)
    if not frame then return end
    local ac = COLORS and COLORS.accent or ns.UI_COLORS and ns.UI_COLORS.accent
    if isOnline and ac then
        -- Background: very dark tint of accent (≈15% brightness so text stays readable)
        local r, g, b = ac[1] * 0.55, ac[2] * 0.55, ac[3] * 0.55
        if not frame.bg then
            frame.bg = frame:CreateTexture(nil, "BACKGROUND")
            frame.bg:SetAllPoints()
        end
        frame.bg:SetColorTexture(r * 0.4, g * 0.4, b * 0.4, 1)
        -- Left accent bar: full accent brightness
        if not frame.onlineAccent then
            frame.onlineAccent = frame:CreateTexture(nil, "BORDER")
            frame.onlineAccent:SetWidth(3)
            frame.onlineAccent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.onlineAccent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        end
        frame.onlineAccent:SetColorTexture(ac[1], ac[2], ac[3], 1)
        frame.onlineAccent:Show()
    else
        if frame.onlineAccent then frame.onlineAccent:Hide() end
        if frame.bg and frame.bgColor then
            local c = frame.bgColor
            frame.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

--- Create a data row with alternating background color.
--- Standard pattern for creating new rows with proper positioning and alternating bg.
--- For pooled/reused rows, use Factory:ApplyRowBackground() instead.
---@return Frame row, number newYOffset
function ns.UI.Factory:CreateDataRow(parent, yOffset, rowIndex, height)
    if not parent then return nil, yOffset end

    local h = height or UI_SPACING.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:Show()

    self:ApplyRowBackground(row, rowIndex)

    return row, yOffset + h
end

--- Create a collapsible section header with border, arrow, title, hover.
--- Uses ApplyVisuals for consistent border rendering (same as CharactersUI/PlansUI headers).
---@return number newYOffset, Frame header
function ns.UI.Factory:CreateSectionHeader(parent, yOffset, isCollapsed, titleStr, rightStr, onToggle, height, leftIndent)
    if not parent then return yOffset, nil end

    local sp = UI_SPACING
    local h = height or sp.SECTION_COLLAPSE_HEADER_HEIGHT or sp.HEADER_HEIGHT
    local indent = leftIndent or 0
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(h)
    header:SetPoint("TOPLEFT", indent, -yOffset)
    header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    -- Draw above virtual-scroll row frames so nothing shows through behind header
    header:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    header:Show()

    local surf = COLORS.surfaceElevated or COLORS.bgLight
    -- Opaque background (1.0) so row text does not show through behind header
    ApplyVisuals(header, {surf[1], surf[2], surf[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    header._wnSectionHeaderBaseBg = {surf[1], surf[2], surf[3], 1}

    if ns.UI_ApplySectionChromeUnderlay then
        ns.UI_ApplySectionChromeUnderlay(header)
    end

    -- Collapse/expand chevron (same control as tab section headers)
    local collapseBtn = ns.UI_CreateCollapseExpandControl(header, not isCollapsed, { enableMouse = true })
    local chevLeft = sp.SECTION_HEADER_FACTORY_CHEVRON_LEFT or 10
    collapseBtn:SetPoint("LEFT", chevLeft + indent, 0)

    -- Title text
    local title = FontManager:CreateFontString(header, UIFontRole("factorySectionHeaderTitle"), "OVERLAY")
    title:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)

    -- Right-side text (optional)
    if rightStr then
        local rightLabel = FontManager:CreateFontString(header, UIFontRole("factorySectionHeaderRight"), "OVERLAY")
        rightLabel:SetPoint("RIGHT", header, "RIGHT", -sp.SIDE_MARGIN, 0)
        rightLabel:SetJustifyH("RIGHT")
        rightLabel:SetText(rightStr)
        title:SetPoint("RIGHT", rightLabel, "LEFT", -6, 0)
    end

    title:SetText(titleStr)

    -- Click handlers
    header:SetScript("OnClick", onToggle)
    collapseBtn:SetScript("OnClick", onToggle)

    -- Hover highlight (token-driven base from `surfaceElevated`)
    header:SetScript("OnEnter", function()
        if header.SetBackdropColor and header._wnSectionHeaderBaseBg then
            local b = header._wnSectionHeaderBaseBg
            header:SetBackdropColor(
                math.min(1, b[1] * 1.12),
                math.min(1, b[2] * 1.12),
                math.min(1, b[3] * 1.12),
                b[4] or 1
            )
        end
    end)
    header:SetScript("OnLeave", function()
        if header.SetBackdropColor and header._wnSectionHeaderBaseBg then
            local b = header._wnSectionHeaderBaseBg
            header:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
        end
    end)

    return yOffset + h, header
end

local COLLECTION_PLAN_SLOT_SIZE = math.floor(19 * 1.25 + 0.5)

local function SetCollectionPlanSlotTooltip(btn, tip)
    if not btn then return end
    local hasTip = ns.CollectionsUI and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent
        and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent(tip)
    if not hasTip and type(tip) == "string" and tip ~= "" then
        hasTip = true
    end
    if not hasTip then
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        return
    end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 4, 6)
        GameTooltip:ClearLines()
        local wR, wG, wB = 1, 1, 1
        if type(tip) == "table" then
            if tip.title and tip.title ~= "" then
                GameTooltip:SetText(tip.title, wR, wG, wB)
            end
            local lines = tip.lines
            if type(lines) == "table" then
                for i = 1, #lines do
                    local line = lines[i]
                    if line and line ~= "" then
                        GameTooltip:AddLine(line, wR, wG, wB, true)
                    end
                end
            end
        else
            GameTooltip:SetText(tip, wR, wG, wB)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function CreateCollectionPlanSlotButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:Hide()
    b:SetFrameLevel((row:GetFrameLevel() or 0) + 12)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    b._wnIcon = tex
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

local function EnsureCollectionRowPlanSlotButtons(row)
    if not row then return end
    if row.todoSlotBtn and row.trackSlotBtn then return end
    if row.rowTodoIcon then
        row.rowTodoIcon:Hide()
    end
    if row.rowTrackIcon then
        row.rowTrackIcon:Hide()
    end
    row.todoSlotBtn = row.todoSlotBtn or CreateCollectionPlanSlotButton(row)
    row.trackSlotBtn = row.trackSlotBtn or CreateCollectionPlanSlotButton(row)
end

--- Collection list row: status icon (check/cross) + item icon + label. Same layout for Mounts, Pets, Achievements.
--- Caller sets position (virtual scroll). Use ApplyCollectionListRowContent to set content and selection.
---@return Frame row
function ns.UI.Factory:CreateCollectionListRow(parent, height)
    if not parent then return nil end
    local h = height or UI_SPACING.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row:EnableMouse(true)

    local pad = UI_SPACING.SIDE_MARGIN or 10
    local gap = 4
    local collIconScale = 1.25
    local statusSize = math.floor(16 * collIconScale + 0.5)
    local iconSize = math.floor((UI_SPACING.ROW_ICON_SIZE or 20) * collIconScale + 0.5)

    local statusIcon = row:CreateTexture(nil, "ARTWORK")
    statusIcon:SetSize(statusSize, statusSize)
    statusIcon:SetPoint("LEFT", pad, 0)
    row.statusIcon = statusIcon

    row.todoSlotBtn = CreateCollectionPlanSlotButton(row)
    row.trackSlotBtn = CreateCollectionPlanSlotButton(row)

    local iconBorder = self:CreateContainer(row, iconSize, iconSize, true)
    if iconBorder then
        local bg = { 0.12, 0.12, 0.14, 0.95 }
        local bc = COLORS.border or COLORS.accent or { 0.5, 0.4, 0.7 }
        if ApplyVisuals then
            ApplyVisuals(iconBorder, bg, { bc[1], bc[2], bc[3], 0.72 })
        end
        iconBorder:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
        row._iconBorder = iconBorder
    end
    local iconHost = row._iconBorder or row
    local icon = iconHost:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHost, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconHost, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local label = FontManager:CreateFontString(row, UIFontRole("factoryDataRowLabel"), "OVERLAY")
    label:SetPoint("LEFT", iconHost, "RIGHT", gap, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local rightLabel = FontManager:CreateFontString(row, UIFontRole("factoryDataRowRight"), "OVERLAY")
    rightLabel:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
    rightLabel:SetJustifyH("RIGHT")
    rightLabel:SetWordWrap(false)
    rightLabel:Hide()
    row.rightLabel = rightLabel

    return row
end

local COLLECTION_ROW_ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local COLLECTION_ROW_ICON_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function CollectionListRowIconHost(row)
    return row._iconBorder or row.icon
end

local function CollectionRowTextLeftX(row, pad, gap, slotGap)
    local x = pad or 10
    gap = gap or 4
    slotGap = slotGap or 3
    if row.statusIcon and row.statusIcon:IsShown() then
        x = x + (row.statusIcon:GetWidth() or 0) + gap
    end
    if row.todoSlotBtn and row.todoSlotBtn:IsShown() then
        x = x + COLLECTION_PLAN_SLOT_SIZE + slotGap
        if row.trackSlotBtn and row.trackSlotBtn:IsShown() then
            x = x + COLLECTION_PLAN_SLOT_SIZE + slotGap
        end
    end
    local iconHost = CollectionListRowIconHost(row)
    if iconHost and iconHost.GetWidth then
        x = x + (iconHost:GetWidth() or 0) + gap
    end
    return x
end

--- Vertically center label (and optional subtitle) in the row; two-line block height never exceeds item icon.
local function LayoutCollectionListRowText(row, pad, gap, slotGap)
    if not row or not row.label then return end
    pad = pad or 10
    gap = gap or 4
    slotGap = slotGap or 3
    local iconHost = CollectionListRowIconHost(row)
    if not iconHost then return end
    local rowH = row:GetHeight() or (UI_SPACING.ROW_HEIGHT or 32)
    local iconH = iconHost:GetHeight() or 25
    local textX = CollectionRowTextLeftX(row, pad, gap, slotGap)
    local subText = row.subtitle and row.subtitle:GetText()
    local hasSub = row.subtitle and row.subtitle:IsShown()
        and subText and not (issecretvalue and issecretvalue(subText))
        and subText ~= ""
    row.label:ClearAllPoints()
    if hasSub and row.subtitle then
        row.subtitle:ClearAllPoints()
        local lineGap = 2
        local lh = row.label:GetStringHeight() or 12
        local sh = row.subtitle:GetStringHeight() or 10
        local blockH = lh + lineGap + sh
        if blockH > iconH then
            lineGap = 1
            blockH = lh + lineGap + sh
        end
        if blockH > iconH then
            blockH = iconH
            lineGap = math.max(0, blockH - lh - sh)
        end
        local blockTop = (rowH - blockH) * 0.5
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("TOP")
        row.subtitle:SetJustifyH("LEFT")
        row.subtitle:SetJustifyV("TOP")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -blockTop)
        row.subtitle:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -lineGap)
        if row.rightLabel and row.rightLabel:IsShown() then
            row.subtitle:SetPoint("RIGHT", row.rightLabel, "LEFT", -6, 0)
        else
            row.subtitle:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
        end
    else
        local lh = row.label:GetStringHeight() or 12
        local blockTop = (rowH - lh) * 0.5
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("TOP")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -blockTop)
    end
    if row.rightLabel and row.rightLabel:IsShown() then
        row.rightLabel:ClearAllPoints()
        row.rightLabel:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
        row.rightLabel:SetJustifyV("MIDDLE")
        row.label:SetPoint("RIGHT", row.rightLabel, "LEFT", -6, 0)
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
    end
end

--- To-Do / Track column beside collected check (Collections + To-Do browse). `planSlotState` nil = hidden (e.g. Recent cards).
--- planSlotState: `onTodo`, `onTrack`, optional `achievementRow`, `achievementCollected`, optional `showTrackSlot`, optional `onTodoClick` / `onTrackClick` (toggle supported by caller), optional `todoTooltip` / `trackTooltip` (hover; non-interactive slots still show tooltip when text set and mouse enabled).
local function ApplyCollectionRowPlanSlotTextures(row, planSlotState, gap, slotGap)
    EnsureCollectionRowPlanSlotButtons(row)
    local todoBtn = row.todoSlotBtn
    local trackBtn = row.trackSlotBtn
    local iconHost = row and CollectionListRowIconHost(row)
    local statusIcon = row and row.statusIcon
    if not todoBtn or not trackBtn or not iconHost or not statusIcon then return end
    gap = gap or 4
    slotGap = slotGap or 3
    if not planSlotState then
        todoBtn:Hide()
        trackBtn:Hide()
        todoBtn:SetScript("OnClick", nil)
        trackBtn:SetScript("OnClick", nil)
        SetCollectionPlanSlotTooltip(todoBtn, nil)
        SetCollectionPlanSlotTooltip(trackBtn, nil)
        todoBtn:EnableMouse(false)
        trackBtn:EnableMouse(false)
        todoBtn:ClearAllPoints()
        trackBtn:ClearAllPoints()
        iconHost:ClearAllPoints()
        iconHost:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
        return
    end
    local onTodo = planSlotState.onTodo == true
    local onTrack = planSlotState.onTrack == true
    local achRow = planSlotState.achievementRow == true
    local achCollected = planSlotState.achievementCollected == true
    local showTrackSlot
    if planSlotState.showTrackSlot == false then
        showTrackSlot = false
    elseif planSlotState.showTrackSlot == true then
        showTrackSlot = true
    else
        showTrackSlot = achRow
    end

    local todoTex = todoBtn._wnIcon
    local trackTex = trackBtn._wnIcon
    if not todoTex or not trackTex then return end

    todoBtn:ClearAllPoints()
    trackBtn:ClearAllPoints()
    todoBtn:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    trackBtn:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    todoBtn:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
    todoBtn:Show()

    local todoDisabled = achCollected == true
    if ns.UI_ApplyWnActionIcon then
        ns.UI_ApplyWnActionIcon(todoTex, "todo", onTodo, todoDisabled)
    else
        ns.UI_SetWnIconTexture(todoTex, "todo", {
            desaturate = todoDisabled,
            vertexColor = ns.UI_WnIconVertexForKey("todo", onTodo, todoDisabled),
        })
    end

    local todoClickable = (type(planSlotState.onTodoClick) == "function") and (onTodo or not achCollected)
    local todoTip = planSlotState.todoTooltip
    local todoHasTip = ns.CollectionsUI and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent
        and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent(todoTip)
    if not todoHasTip and type(todoTip) == "string" and todoTip ~= "" then
        todoHasTip = true
    end
    local todoMouse = todoClickable or todoHasTip
    todoBtn:EnableMouse(todoMouse)
    if todoClickable then
        todoBtn:SetScript("OnClick", function()
            planSlotState.onTodoClick()
        end)
    else
        todoBtn:SetScript("OnClick", nil)
    end
    SetCollectionPlanSlotTooltip(todoBtn, todoMouse and todoHasTip and todoTip or nil)

    iconHost:ClearAllPoints()
    if showTrackSlot then
        trackBtn:SetPoint("LEFT", todoBtn, "RIGHT", slotGap, 0)
        trackBtn:Show()
        local trackDisabled = achCollected == true
        if ns.UI_ApplyWnActionIcon then
            ns.UI_ApplyWnActionIcon(trackTex, "track", onTrack, trackDisabled)
        else
            ns.UI_SetWnIconTexture(trackTex, "track", {
                desaturate = trackDisabled,
                vertexColor = ns.UI_WnIconVertexForKey("track", onTrack, trackDisabled),
            })
        end
        local trackClickable = (type(planSlotState.onTrackClick) == "function") and (not achCollected)
        local trackTip = planSlotState.trackTooltip
        local trackHasTip = ns.CollectionsUI and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent
            and ns.CollectionsUI.CollectionPlanSlotTooltipHasContent(trackTip)
        if not trackHasTip and type(trackTip) == "string" and trackTip ~= "" then
            trackHasTip = true
        end
        local trackMouse = trackClickable or trackHasTip
        trackBtn:EnableMouse(trackMouse)
        if trackClickable then
            trackBtn:SetScript("OnClick", function()
                planSlotState.onTrackClick()
            end)
        else
            trackBtn:SetScript("OnClick", nil)
        end
        SetCollectionPlanSlotTooltip(trackBtn, trackMouse and trackHasTip and trackTip or nil)
        iconHost:SetPoint("LEFT", trackBtn, "RIGHT", gap, 0)
    else
        trackBtn:Hide()
        trackBtn:SetScript("OnClick", nil)
        SetCollectionPlanSlotTooltip(trackBtn, nil)
        trackBtn:EnableMouse(false)
        iconHost:SetPoint("LEFT", todoBtn, "RIGHT", gap, 0)
    end
end

--- Apply content and selection to a collection list row (from CreateCollectionListRow). Use for virtual scroll.
function ns.UI.Factory:ApplyCollectionListRowContent(row, rowIndex, iconPath, labelText, isCollected, isSelected, onClick, rightAlignedText, subtitleText, planSlotState)
    if not row then return end
    local pad = UI_SPACING.SIDE_MARGIN or 10
    local gap = 4
    local slotGap = 3
    self:ApplyRowBackground(row, rowIndex or 1)
    if row.statusIcon then
        row.statusIcon:SetTexture(isCollected and COLLECTION_ROW_ICON_READY or COLLECTION_ROW_ICON_NOT_READY)
        row.statusIcon:Show()
    end
    if planSlotState and rawget(planSlotState, "achievementCollected") == nil then
        planSlotState.achievementCollected = isCollected == true
    end
    ApplyCollectionRowPlanSlotTextures(row, planSlotState, gap, slotGap)
    if row.icon then
        local iconTex = (iconPath and iconPath ~= "") and iconPath or "Interface\\Icons\\Achievement_General"
        row.icon:SetTexture(iconTex)
        row.icon:Show()
    end
    local hasSub = subtitleText and subtitleText ~= ""
    if row.label then
        row.label:SetText(labelText or "")
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("MIDDLE")
        row.label:SetWordWrap(false)
    end
    if hasSub then
        if not row.subtitle then
            row.subtitle = FontManager:CreateFontString(row, UIFontRole("small"), "OVERLAY")
            row.subtitle:SetJustifyH("LEFT")
            row.subtitle:SetJustifyV("MIDDLE")
            row.subtitle:SetWordWrap(false)
            row.subtitle:SetTextColor(1, 1, 1, 1)
        end
        row.subtitle:SetText(subtitleText)
        row.subtitle:Show()
    elseif row.subtitle then
        row.subtitle:SetText("")
        row.subtitle:Hide()
    end
    if row.rightLabel and rightAlignedText and rightAlignedText ~= "" then
        row.rightLabel:SetText(rightAlignedText)
        row.rightLabel:SetJustifyV("MIDDLE")
        row.rightLabel:Show()
    else
        if row.rightLabel then
            row.rightLabel:SetText("")
            row.rightLabel:Hide()
        end
    end
    if row.label and CollectionListRowIconHost(row) then
        LayoutCollectionListRowText(row, pad, gap, slotGap)
    end
    row:SetScript("OnMouseDown", onClick)
    if not row.selBg then
        row.selBg = row:CreateTexture(nil, "BORDER")
        row.selBg:SetAllPoints()
    end
    if isSelected then
        local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        row.selBg:SetColorTexture(r, g, b, 0.25)
        row.selBg:Show()
    else
        row.selBg:Hide()
    end
end

assert(ns.UI_ApplyCharacterRowClassGradientAccent and ns.UI.Factory.ApplyRowBackground, "SharedWidgets_RowPool: exports missing")
