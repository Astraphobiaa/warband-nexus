--[[
    Warband Nexus - SharedWidgets PlansLayout (split from SharedWidgets.lua)
    Plans header actions, card grid metrics, To-Do summary heights, plan points.
    Loaded right after Modules/UI/SharedWidgets.lua (TOC) so every later file still finds these ns.UI_* exports.
]]

local _, ns = ...
assert(ns.UI and ns.UI_ApplyVisuals and ns.UI_CreateCard, "SharedWidgets_PlansLayout: load after SharedWidgets.lua")
local issecretvalue = issecretvalue
local UI_SPACING = ns.UI_SPACING
local IsClassicModeEnabled = ns.UI_IsClassicMode

--- Anchor a header control on the right rail; vertically centers on `iconFrame` when provided.
function ns.UI_PlansAnchorHeaderAction(control, headerFrame, fromRight, width, yOffset, iconFrame)
    if not control or not headerFrame then return end
    width = width or (control.GetWidth and control:GetWidth()) or 24
    fromRight = fromRight or 6
    control:ClearAllPoints()
    control:SetPoint("RIGHT", headerFrame, "RIGHT", -fromRight, yOffset or 0)
    if iconFrame then
        control:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    end
end

--- After header actions are placed, shrink the title to the remaining width (`fromRight` = final rightOffset).
function ns.UI_PlansSyncTitleRightInset(row, fromRight)
    if not row or not row.titleText or not row.headerFrame then return end
    fromRight = fromRight or 6
    local titleText = row.titleText
    local data = row.data
    -- Unified To-Do header: title is chained after icon/type; only shrink the right edge for actions.
    if data and data.todoUnifiedHeader then
        row._todoSummaryRightInset = fromRight
        titleText:ClearAllPoints()
        local titleGap = row._todoTitleGap or 6
        local titleAnchor = row._todoTitleAnchor or row.typeBadge or row.iconFrame
        if row._todoMetaRowCentered and row.iconFrame then
            if titleAnchor then
                titleText:SetPoint("LEFT", titleAnchor, "RIGHT", titleGap, 0)
            else
                titleText:SetPoint("LEFT", row.headerFrame, "LEFT", row._todoIconLeft or 40, 0)
            end
            titleText:SetPoint("TOP", row.iconFrame, "TOP", 0, 0)
            if not row.pointsSubText then
                titleText:SetPoint("BOTTOM", row.iconFrame, "BOTTOM", 0, 0)
            end
            titleText:SetJustifyV("MIDDLE")
        elseif row._todoTitleTopLayout then
            if titleAnchor then
                titleText:SetPoint("TOPLEFT", titleAnchor, "TOPRIGHT", titleGap, 0)
            else
                titleText:SetPoint("TOPLEFT", row.headerFrame, "TOPLEFT", row._todoIconLeft or 40, 0)
            end
        elseif titleAnchor then
            titleText:SetPoint("LEFT", titleAnchor, "RIGHT", titleGap, 0)
            if row.iconFrame then
                titleText:SetPoint("TOP", row.iconFrame, "TOP", 0, 0)
                titleText:SetPoint("BOTTOM", row.iconFrame, "BOTTOM", 0, 0)
            end
        else
            titleText:SetPoint("LEFT", row.headerFrame, "LEFT", row._todoIconLeft or 40, 0)
        end
        if row.metaRightText then
            titleText:SetPoint("RIGHT", row.metaRightText, "LEFT", -titleGap, 0)
        else
            titleText:SetPoint("RIGHT", row.headerFrame, "RIGHT", -fromRight, 0)
        end
        if row.pointsSubText then
            row.pointsSubText:ClearAllPoints()
            row.pointsSubText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
            row.pointsSubText:SetPoint("RIGHT", titleText, "RIGHT", 0, 0)
            if row.iconFrame and row._todoMetaRowCentered then
                titleText:SetPoint("TOP", row.iconFrame, "TOP", 0, 0)
                titleText:SetJustifyV("TOP")
            end
        end
        local summaryAnchor = row._todoSummaryAnchor or row.iconFrame
        local summaryRight = row._todoSummaryRightInset or fromRight
        local nLines = row.summaryTexts and #row.summaryTexts or (row.summaryText and 1 or 0)
        local layout = ns.UI_PlansTodoSummaryLayout and ns.UI_PlansTodoSummaryLayout(
            row.headerFrame and row.headerFrame:GetHeight(),
            nLines,
            row.pointsSubText ~= nil
        )
        local function anchorSummaryLine(fs, slotIndex)
            fs:ClearAllPoints()
            if summaryAnchor then
                fs:SetPoint("LEFT", summaryAnchor, "LEFT", 0, 0)
            elseif row.iconFrame then
                fs:SetPoint("LEFT", row.iconFrame, "LEFT", 0, 0)
            end
            if row.iconFrame and layout then
                local yOff = -(layout.startFromIconBottom + slotIndex * (layout.lineH + layout.lineGap))
                fs:SetPoint("TOPLEFT", row.iconFrame, "BOTTOMLEFT", 0, yOff)
            end
            fs:SetPoint("RIGHT", row.headerFrame, "RIGHT", -summaryRight, 0)
        end
        if row.summaryTexts then
            for si = 1, #row.summaryTexts do
                local st = row.summaryTexts[si]
                if st then
                    anchorSummaryLine(st, si - 1)
                end
            end
        elseif row.summaryText then
            anchorSummaryLine(row.summaryText, 0)
        end
        if row.metaRightText then
            row.metaRightText:ClearAllPoints()
            row.metaRightText:SetPoint("RIGHT", row.headerFrame, "RIGHT", -fromRight, 0)
            if row.iconFrame then
                row.metaRightText:SetPoint("CENTER", row.iconFrame, "CENTER", 0, 0)
            end
        end
        if row._todoActionControls then
            for ai = 1, #row._todoActionControls do
                local ctrl = row._todoActionControls[ai]
                local ro = row._todoActionOffsets and row._todoActionOffsets[ai]
                if ctrl and ro then
                    ns.UI_PlansAnchorHeaderAction(ctrl, row.headerFrame, ro, nil, 0, row.iconFrame)
                end
            end
        end
        if row.expandBtn and row._todoChevronBottomRight then
            local chevIn = (ns.UI_PLANS_CARD_METRICS and ns.UI_PLANS_CARD_METRICS.todoChevronInset) or 6
            row.expandBtn:ClearAllPoints()
            row.expandBtn:SetPoint("BOTTOMRIGHT", row.headerFrame, "BOTTOMRIGHT", -chevIn, chevIn)
        end
        return
    end
    local titleAnchorFrame, titleAnchorGap = 4, 4
    if data and data.score and not data.scoreBelow and row.scoreText then
        titleAnchorFrame = row.scoreText
    elseif row.typeBadge then
        titleAnchorFrame = row.typeBadge
    elseif row.iconFrame then
        titleAnchorFrame = row.iconFrame
    end
    titleText:ClearAllPoints()
    if titleAnchorFrame then
        titleText:SetPoint("LEFT", titleAnchorFrame, "RIGHT", titleAnchorGap, 0)
    else
        titleText:SetPoint("LEFT", row.headerFrame, "LEFT", 40, 0)
    end
    titleText:SetPoint("RIGHT", row.headerFrame, "RIGHT", -fromRight, 0)
    if row.SyncHeaderToTitle then
        row:SyncHeaderToTitle()
    end
end

--- Chain header controls right-to-left with uniform gap; each control vertically centered on `headerFrame`.
function ns.UI_PlansChainHeaderActions(headerFrame, controls, opts)
    if not headerFrame or not controls or #controls == 0 then return end
    opts = type(opts) == "table" and opts or {}
    local gap = opts.gap or 8
    local fromRight = opts.fromRight or 6
    local prev
    for ci = 1, #controls do
        local ctrl = controls[ci]
        if ctrl then
            ctrl:ClearAllPoints()
            if prev then
                ctrl:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
            else
                ctrl:SetPoint("RIGHT", headerFrame, "RIGHT", -fromRight, 0)
            end
            prev = ctrl
        end
    end
end

--- Gap between sibling data rows (not headers/sections). See `UI_LAYOUT.dataRowGap`.
function ns.UI_DataRowGap()
    local layout = ns.UI_LAYOUT or {}
    return layout.dataRowGap or 4
end

--- Measured inner width for list chrome (headers/sections) inside a scroll child or results container.
function ns.UI_ResolveListContentWidth(scrollChild, fallbackWidth, extraPad)
    extraPad = extraPad or 0
    local pw = scrollChild and scrollChild.GetWidth and scrollChild:GetWidth()
    if pw and pw > 1 then
        return math.max(80, math.floor(pw - extraPad))
    end
    return fallbackWidth or 260
end

--- Flush section header to wrap edges (no extra side inset — parent scroll/results already has tab margin).
function ns.UI_AnchorSectionHeaderInWrap(header, wrap, stackW)
    if not header or not wrap then return end
    local w = stackW
    if not w or w < 1 then
        w = wrap.GetWidth and wrap:GetWidth()
    end
    w = math.max(1, w or 1)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
    if header.SetWidth then
        header:SetWidth(w)
    end
end

--- Clamp virtual-list row paint width so TOPRIGHT anchors stay inside the list body.
function ns.UI_ClampRowPaintWidth(rowParent, xOffset, requestedWidth, rightPad)
    local pw = rowParent and rowParent.GetWidth and rowParent:GetWidth()
    if not pw or pw < 1 then
        return requestedWidth
    end
    return math.max(1, math.min(requestedWidth or pw, pw - (xOffset or 0) - (rightPad or 4)))
end


-- PLANS TAB (To-Do List expandable rows + Browse grid cards): single source of truth
local PLANS_GRID_SPACING = UI_SPACING.CARD_GAP or 8

--- @class PlansCardMetrics
local PLANS_ICON_SCALE = 1.25
local function PlansMetric(n)
    return math.max(1, math.floor((n or 0) * PLANS_ICON_SCALE + 0.5))
end

--- Header action buttons (delete / reminder / track) on plan cards and To-Do rows — single size source.
function ns.UI_PlansHeaderActionSize()
    local PCM = ns.UI_PLANS_CARD_METRICS or {}
    return PCM.todoTypeBadgeSize or PlansMetric(24) or 24
end

ns.UI_PLANS_CARD_METRICS = {
    gridSpacing = PLANS_GRID_SPACING,
    --- CreateExpandableRow rowData (main To-Do tab + tracker): keep in sync with PlansUI rowData
    todoIconSize = PlansMetric(41),
    todoTypeBadgeSize = PlansMetric(24),
    todoExpandableMinHeight = PlansMetric(63),
    todoExpandableHeightCap = PlansMetric(71),
    --- Fixed collapsed header: [icon][type atlas][title][tries]; summary under item icon.
    --- Matches UI_PlansTodoFixedCollapsedHeight(true) — 2 summary slots + points row reserve.
    todoUnifiedHeaderHeight = 123,
    todoUnifiedSlotLines = 2,
    todoUnifiedIconSize = 40,
    todoTypeBadgeSize = 28,
    todoIconRowTop = 8,
    todoMetaGap = 8,
    todoTitleGap = 8,
    todoSummaryGap = 4,
    todoSummaryBandTopGap = 12,
    todoSummaryBandBottomPad = 14,
    todoSummaryRowH = 16,
    todoSummaryLineGap = 3,
    todoPointsRowH = 14,
    todoBottomPad = 12,
    todoMetaRightReserve = 88,
    todoChevronInset = 6,
    --- Classic To-Do: dialog insets shift icon/action alignment vs modern accent cards.
    classicTodoIconLeft = 14,
    classicTodoIconRowTop = 10,
    classicTodoIconTexInset = 3,
    classicTodoActionRightInset = 10,
    --- Browse mounts/pets/etc. grid: same icon/badge feel as To-Do; fixed card height for two-column grid
    browseCardHeight = PlansMetric(126),
    --- Vertical gap between To-Do List cards (Currency/Reputation row-gap parity).
    todoListCardGap = 10,
    browseCardPadH = (UI_SPACING and UI_SPACING.PAGE_STACK and UI_SPACING.PAGE_STACK.SIDE) or 12,
    plansActionIconInset = 3,
    browseIconTopInset = PlansMetric(10),
    browseIconLeftInset = PlansMetric(10),
    browseIconContainerSize = PlansMetric(45),
    browseRightRailW = PlansMetric(52),
    plansChevronSize = PlansMetric(18),
}

--- To-Do row icon anchor overrides (Classic dialog chrome needs tighter inset).
---@return number iconLeft, number iconTopNeg
function ns.UI_PlansTodoIconAnchors()
    local PCM = ns.UI_PLANS_CARD_METRICS or {}
    if IsClassicModeEnabled() then
        return PCM.classicTodoIconLeft or 10, -(PCM.classicTodoIconRowTop or 6)
    end
    return 8, -(PCM.todoIconRowTop or 8)
end

--- Horizontal inset for To-Do tab search bar and card grids (must match).
function ns.UI_PlansContentPadH()
    local PCM = ns.UI_PLANS_CARD_METRICS
    if PCM and PCM.browseCardPadH then
        return PCM.browseCardPadH
    end
    local L = ns.UI_LAYOUT
    return (L and (L.SIDE_MARGIN or L.sideMargin)) or 10
end

--- Plans / Collections browse grid: card width, spacing, horizontal pad (clamp-safe).
function ns.UI_PlansCardGridLayout(contentInnerWidth, columns, opts)
    columns = columns or 2
    opts = opts or {}
    local PCM = ns.UI_PLANS_CARD_METRICS
    local padH = opts.padH
    if padH == nil then
        padH = ns.UI_PlansContentPadH and ns.UI_PlansContentPadH() or ((PCM and PCM.browseCardPadH) or 10)
    end
    local sp = (PCM and PCM.todoListCardGap) or (PCM and PCM.gridSpacing) or PLANS_GRID_SPACING
    local w = math.max(200, (contentInnerWidth or 400) - 2 * padH)
    local cardW = math.max(100, (w - (columns - 1) * sp) / columns)
    return cardW, sp, padH
end

--- Half-width column for Plans 2-column grids (`width` = scroll body inner width; use `UI_ResolveMainTabBodyWidth`).
function ns.UI_PlansCardGridColumnWidth(contentInnerWidth)
    local cardW = ns.UI_PlansCardGridLayout(contentInnerWidth, 2)
    return cardW
end

--- Collapsed unified To-Do / browse card height from summary line count (0–2 typical).
function ns.UI_PlansTodoCollapsedHeight(summaryLineCount)
    local m = ns.UI_PLANS_CARD_METRICS or {}
    summaryLineCount = tonumber(summaryLineCount) or 0
    if summaryLineCount < 0 then summaryLineCount = 0 end
    local top = m.todoIconRowTop or 8
    local icon = m.todoUnifiedIconSize or 40
    local bandGap = m.todoSummaryBandTopGap or 12
    local lineH = m.todoSummaryRowH or 16
    local lineGap = m.todoSummaryLineGap or 3
    local pad = m.todoSummaryBandBottomPad or m.todoBottomPad or 10
    if summaryLineCount == 0 then
        return top + icon + pad
    end
    local summaryH = summaryLineCount * lineH + (summaryLineCount - 1) * lineGap
    return top + icon + bandGap + summaryH + pad
end

--- Safe achievement/collectible points label (locale format + secret guard).
function ns.UI_FormatPlanPoints(points)
    if issecretvalue and issecretvalue(points) then return nil end
    if points == nil then return nil end
    local pts = tonumber(points)
    if not pts or pts <= 0 then return nil end
    local ptsFmt = (ns.L and ns.L["POINTS_FORMAT"]) or "%d Points"
    if type(ptsFmt) ~= "string" or ptsFmt == "" or ptsFmt == "POINTS_FORMAT" then
        ptsFmt = "%d Points"
    end
    local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffd700"
    local ok, out = pcall(format, goldHex .. ptsFmt .. "|r", pts)
    if ok and out and out ~= "" then return out end
    return goldHex .. tostring(pts) .. " " .. ((ns.L and ns.L["POINTS_LABEL"]) or "Points") .. "|r"
end

--- Resolve live achievement points when plan row has none cached.
function ns.UI_ResolveAchievementPlanPoints(plan, cachedEntry)
    local pts = plan and tonumber(plan.points) or 0
    if pts > 0 then return pts end
    if cachedEntry then
        pts = tonumber(cachedEntry.points) or 0
        if pts > 0 then return pts end
    end
    if plan and plan.achievementID and GetAchievementInfo then
        local ok, _, _, ap = pcall(GetAchievementInfo, plan.achievementID)
        if ok and not (issecretvalue and issecretvalue(ap)) and ap ~= nil then
            pts = tonumber(ap) or 0
        end
    end
    return pts > 0 and pts or 0
end

--- Vertical layout for Drop/Location/Requirements lines in the band below the portrait icon.
function ns.UI_PlansTodoSummaryLayout(rowHeight, lineCount, hasPointsRow)
    local m = ns.UI_PLANS_CARD_METRICS or {}
    lineCount = tonumber(lineCount) or 0
    if lineCount < 1 then return nil end
    if not rowHeight then
        rowHeight = ns.UI_PlansTodoFixedCollapsedHeight(hasPointsRow)
    end
    local iconTop = m.todoIconRowTop or 8
    local iconSz = m.todoUnifiedIconSize or 40
    local lineH = m.todoSummaryRowH or 16
    local lineGap = m.todoSummaryLineGap or 3
    local bottomPad = m.todoSummaryBandBottomPad or m.todoBottomPad or 10
    local bandMinGap = m.todoSummaryBandTopGap or 12
    local iconBottom = iconTop + iconSz
    local blockH = lineCount * lineH + (lineCount - 1) * lineGap
    local bandTop = iconBottom + bandMinGap
    local bandBottom = rowHeight - bottomPad
    local bandH = math.max(blockH, bandBottom - bandTop)
    return {
        startFromIconBottom = bandMinGap + (bandH - blockH) * 0.5,
        lineH = lineH,
        lineGap = lineGap,
    }
end

--- All unified To-Do / browse cards share one collapsed height (title + optional points row + summary slots).
function ns.UI_PlansTodoFixedCollapsedHeight(hasPointsRow)
    local m = ns.UI_PLANS_CARD_METRICS or {}
    local slots = m.todoUnifiedSlotLines or 2
    local base = ns.UI_PlansTodoCollapsedHeight(slots)
    if hasPointsRow then
        local gap = m.todoSummaryGap or 4
        local ptsH = m.todoPointsRowH or 14
        return base + ptsH + gap
    end
    return base
end

--- Collapsed expandable header height (To-Do List + tracker rows).
--- Unified layout uses a fixed height so mount/achievement cards align in the grid.
function ns.UI_PlansTodoExpandableHeaderHeight(panelWidth, summaryLineCount)
    if summaryLineCount ~= nil then
        return ns.UI_PlansTodoCollapsedHeight(summaryLineCount)
    end
    if ns.UI_PlansTodoFixedCollapsedHeight then
        return ns.UI_PlansTodoFixedCollapsedHeight(true)
    end
    local m = ns.UI_PLANS_CARD_METRICS
    if m and m.todoUnifiedHeaderHeight then
        return m.todoUnifiedHeaderHeight
    end
    local minH = m and m.todoExpandableMinHeight or 60
    local cap = m and m.todoExpandableHeightCap or 68
    local w = panelWidth or 400
    return math.max(minH, math.min(cap, math.floor(w * 0.10)))
end

assert(ns.UI_PlansAnchorHeaderAction and ns.UI_PLANS_CARD_METRICS and ns.UI_PlansTodoExpandableHeaderHeight, "SharedWidgets_PlansLayout: exports missing")
