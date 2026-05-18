--[[
    Warband Nexus - Expandable Row Factory
    Creates expandable rows for achievements/collections with expand/collapse functionality
    
    Extracted from SharedWidgets.lua for better modularity
    Used in Plans UI for achievement tracking
]]

local ADDON_NAME, ns = ...

local wipe = wipe
local criteriaRowScratch = {}

-- Debug print helper
local DebugPrint = ns.DebugPrint
-- Import dependencies from SharedWidgets (with safety checks)
local UI_SPACING = ns.UI_SPACING  -- Standardized spacing constants
local COLORS = ns.UI_COLORS  -- Use COLORS table instead of GetColors function
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateIcon = ns.UI_CreateIcon
local CreateButton = ns.UI_CreateButton
local FontManager = ns.FontManager

-- Dependencies will be loaded lazily on first use (deferred loading)

--============================================================================
-- EXPANDABLE ROW FACTORY
--============================================================================

-- Phase 4.7: Extract duplicate details-frame creation code into shared function
--[[
    Create details frame for expandable row
    @param row - The expandable row frame
    @param parentFrame - Parent frame (usually the row itself)
    @param options - Options table { data, bgColor, borderColor }
    @return detailsFrame - Created details frame
]]
local function CreateDetailsFrame(row, parentFrame, options)
    local data = options.data

    local Factory = ns.UI and ns.UI.Factory
    local detailsW = math.max(50, row:GetWidth() or parentFrame:GetWidth() or 380)
    local detailsFrame = Factory and Factory.CreateContainer and Factory:CreateContainer(parentFrame, detailsW, 1, false)
        or CreateFrame("Frame", nil, parentFrame)
    detailsFrame:SetPoint("TOPLEFT", row.headerFrame, "BOTTOMLEFT", 0, 0)
    detailsFrame:SetPoint("TOPRIGHT", row.headerFrame, "BOTTOMRIGHT", 0, 0)

    -- Single-border layout: the row owns the backdrop, so the details panel inherits the
    -- same frame and only paints a thin divider line at the seam between header and body.
    local divider = detailsFrame:CreateTexture(nil, "OVERLAY")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 0, 0)
    divider:SetPoint("TOPRIGHT", 0, 0)
    divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
    
    local yOffset = -8
    local leftMargin = 12   -- Left-anchored for Description/Requirements to maximize space
    local rightMargin = 16
    local sectionSpacing = 6
    
    -- Information Section (inline: "Description: text...")
    if data.information and data.information ~= "" then
        -- Combined header + text in one line, left-anchored
        local infoText = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
        infoText:SetPoint("TOPLEFT", leftMargin, yOffset)
        infoText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
        infoText:SetJustifyH("LEFT")
        local P = ns.PLAN_UI_COLORS or {}
        infoText:SetText((P.infoLabel or "|cff88ff88") .. ((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r " .. data.information)
        infoText:SetWordWrap(true)
        infoText:SetNonSpaceWrap(false)
        infoText:SetSpacing(2)

        -- Force explicit width so GetStringHeight() returns the wrapped height in the same frame
        -- (anchor-derived width is lazy and would yield a single-line height, causing the next
        -- section to overlap until something triggers a re-layout — observed during scroll).
        local rowW = (row and row:GetWidth()) or (parentFrame and parentFrame:GetWidth()) or 380
        infoText:SetWidth(math.max(60, rowW - leftMargin - rightMargin))

        local textHeight = infoText:GetStringHeight()
        if not textHeight or textHeight < 14 then textHeight = 14 end
        yOffset = yOffset - textHeight - sectionSpacing - 4
    end
    
    -- Criteria Section (supports structured criteriaData with interactive achievement links)
    local hasCriteriaData = data.criteriaData and type(data.criteriaData) == "table" and #data.criteriaData > 0
    local hasCriteriaText = data.criteria and data.criteria ~= ""
    
    if hasCriteriaData or hasCriteriaText then
        -- Build criteria items: prefer structured data, fallback to legacy text
        local criteriaItems = {}  -- { text, linkedAchievementID?, completed? }
        local progressLine = nil

        if hasCriteriaData then
            criteriaItems = data.criteriaData
            -- Extract progress line from legacy text (first line)
            if hasCriteriaText then
                progressLine = string.match(data.criteria, "^([^\n]+)")
            end
        else
            -- Legacy path: split text into lines
            local firstLine = true
            for line in string.gmatch(data.criteria, "[^\n]+") do
                if firstLine then
                    progressLine = line
                    firstLine = false
                else
                    table.insert(criteriaItems, { text = line })
                end
            end
        end

        -- Section header with inline progress. Callers that don't have a true requirement
        -- (e.g. collectible Drop/Location rows) pass criteriaShowHeader = false to keep the
        -- expanded body clean and avoid a misleading "Requirements:" label.
        if data.criteriaShowHeader ~= false then
            local P = ns.PLAN_UI_COLORS or {}
            local reqLabel = (ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:"
            local headerText = (P.progressLabel or "|cffffcc00") .. reqLabel .. "|r"
            if progressLine then
                headerText = headerText .. " " .. progressLine
            end

            local criteriaHeader = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
            criteriaHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
            criteriaHeader:SetPoint("TOPRIGHT", -rightMargin, yOffset)
            criteriaHeader:SetJustifyH("LEFT")
            criteriaHeader:SetWordWrap(true)
            criteriaHeader:SetNonSpaceWrap(false)
            criteriaHeader:SetText(headerText)

            local crowW = (row and row:GetWidth()) or (parentFrame and parentFrame:GetWidth()) or 380
            criteriaHeader:SetWidth(math.max(60, crowW - leftMargin - rightMargin))
            local headerH = criteriaHeader:GetStringHeight()
            if not headerH or headerH < 16 then headerH = 16 end
            yOffset = yOffset - headerH - 4
        end
        
        -- Render criteria grid (fixed line height for even two-column alignment, no wrap to avoid "0 / \n1)")
        if #criteriaItems > 0 then
            local CRITERIA_LINE_HEIGHT = 16
            local rowW = (row and row:GetWidth()) or (parentFrame and parentFrame:GetWidth()) or 380
            local availableWidth = math.max(60, rowW - leftMargin - rightMargin)
            local columnsPerRow = data.criteriaColumns or 2
            if #criteriaItems <= 2 then
                columnsPerRow = 1
            end
            columnsPerRow = math.min(columnsPerRow, 2)
            local columnWidth = availableWidth / columnsPerRow
            wipe(criteriaRowScratch)
            local crn = 0
            
            local ShowAchievementPopup = ns.UI_ShowAchievementPopup
            
            for i = 1, #criteriaItems do
                local item = criteriaItems[i]
                crn = crn + 1
                criteriaRowScratch[crn] = item
                
                if crn == columnsPerRow or i == #criteriaItems then
                    for colIndex = 1, crn do
                        local criteriaItem = criteriaRowScratch[colIndex]
                        local xPos = leftMargin + (colIndex - 1) * columnWidth
                        local criteriaText = criteriaItem.text or criteriaItem
                        local linkedID = criteriaItem.linkedAchievementID
                        
                        local isCompleted = criteriaItem.completed
                        if linkedID and ShowAchievementPopup and not isCompleted then
                            -- Interactive: clickable row (achievement popup); invisible chrome via CreateButton(noBorder).
                            local btn = CreateButton(detailsFrame, math.max(8, columnWidth - 8), CRITERIA_LINE_HEIGHT, nil, nil, true)
                            if not btn then
                                btn = CreateFrame("Button", nil, detailsFrame)
                                btn:SetSize(columnWidth - 8, CRITERIA_LINE_HEIGHT)
                            end
                            btn:SetPoint("TOPLEFT", xPos, yOffset)
                            
                            local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
                            label:SetPoint("LEFT")
                            label:SetWidth(columnWidth - 12)
                            label:SetJustifyH("LEFT")
                            label:SetText(criteriaText)
                            label:SetWordWrap(false)
                            label:SetMaxLines(1)
                            
                            btn:SetScript("OnEnter", function()
                                label:SetAlpha(0.7)
                            end)
                            btn:SetScript("OnLeave", function()
                                label:SetAlpha(1)
                            end)
                            btn:SetScript("OnClick", function(self)
                                ShowAchievementPopup(linkedID, self)
                            end)
                        else
                            -- Standard: one line, no wrap (avoids "0 / 1)" splitting); fixed height for alignment
                            local colLabel = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
                            colLabel:SetPoint("TOPLEFT", xPos, yOffset)
                            colLabel:SetWidth(columnWidth - 8)
                            colLabel:SetJustifyH("LEFT")
                            colLabel:SetWordWrap(false)
                            colLabel:SetMaxLines(1)
                            local displayText = type(criteriaText) == "string" and criteriaText or tostring(criteriaText)
                            colLabel:SetText("|cffeeeeee" .. displayText .. "|r")
                        end
                    end
                    
                    yOffset = yOffset - CRITERIA_LINE_HEIGHT - 4
                    crn = 0
                end
            end
            
            yOffset = yOffset - sectionSpacing
        end
    end
    
    -- Set height based on content (WoW-like: tight)
    local detailsHeight = math.abs(yOffset) + 8
    detailsFrame:SetHeight(detailsHeight)
    
    return detailsFrame
end

--- Bottom extent of painted content (guards lazy GetStringHeight / anchor width drift).
local function MeasureDetailsContentHeight(detailsFrame)
    if not detailsFrame then return 8 end
    local top = detailsFrame:GetTop()
    if not top then
        return math.max(8, detailsFrame:GetHeight() or 8)
    end
    local maxExtent = 8
    local numRegions = detailsFrame:GetNumRegions()
    for ri = 1, numRegions do
        local r = select(ri, detailsFrame:GetRegions())
        if r and r.IsShown and r:IsShown() then
            local bottom = r:GetBottom()
            if bottom then
                maxExtent = math.max(maxExtent, top - bottom)
            end
        end
    end
    local numChildren = detailsFrame:GetNumChildren()
    for ci = 1, numChildren do
        local ch = select(ci, detailsFrame:GetChildren())
        if ch and ch.IsShown and ch:IsShown() then
            local bottom = ch:GetBottom()
            if bottom then
                maxExtent = math.max(maxExtent, top - bottom)
            end
        end
    end
    return maxExtent + 4
end

local function DestroyRowDetailsFrame(row)
    if row.detailsFrame then
        row.detailsFrame:Hide()
        row.detailsFrame:SetParent(nil)
        row.detailsFrame = nil
    end
    row._fullDetailsH = nil
end

local function SafeOnExpandPopulate(data, row)
    local fn = data and data.onExpandPopulate
    if type(fn) == "function" then
        fn(data, row)
    end
end

local function BuildRowDetailsFrame(row)
    local data = row.data
    if not data then return 0 end
    DestroyRowDetailsFrame(row)
    SafeOnExpandPopulate(data, row)
    row.detailsFrame = CreateDetailsFrame(row, row, { data = data })
    if not row.detailsFrame then
        row._fullDetailsH = 0
        return 0
    end
    local layoutH = row.detailsFrame:GetHeight() or 8
    local paintedH = MeasureDetailsContentHeight(row.detailsFrame)
    row._fullDetailsH = math.max(layoutH, paintedH)
    row.detailsFrame:SetHeight(row._fullDetailsH)
    return row._fullDetailsH
end

local function ApplyRowExpandedGeometry(row, detailsH)
    if not row or not row.headerFrame then return end
    detailsH = detailsH or 0
    local headerH = row.headerFrame:GetHeight() or row.rowHeight or 32
    if row.isExpanded and row.detailsFrame and detailsH > 0 then
        row.detailsFrame:SetAlpha(1)
        row.detailsFrame:Show()
        row.detailsFrame:SetHeight(math.max(0.1, detailsH))
        row:SetHeight(headerH + detailsH)
    else
        if row.detailsFrame then
            row.detailsFrame:Hide()
        end
        row:SetHeight(headerH)
    end
    local data = row.data
    if data and data.onSectionResize then
        data.onSectionResize(row, row:GetHeight())
    end
end

local function ApplyTypeAtlasTexture(tex, parent, atlas, size)
    size = size or 24
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", parent, "CENTER", 0, 0)
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    return pcall(function() tex:SetAtlas(atlas, false) end)
end

local function CreateSquareTypeBadge(parent, atlas, badgeSize, FactEr)
    badgeSize = badgeSize or 24
    local frame = FactEr and FactEr:CreateContainer(parent, badgeSize, badgeSize, false)
    if not frame then
        frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(badgeSize, badgeSize)
    end
    local tex = frame:CreateTexture(nil, "ARTWORK")
    if ApplyTypeAtlasTexture(tex, frame, atlas, badgeSize) then
        frame:Show()
        return frame
    end
    frame:Hide()
    return nil
end

--- Fixed To-Do header: title (large), points under title (achievements), summaries under icon.
local function ApplyTodoUnifiedHeader(row, headerFrame, data, rowHeight)
    local PCM = ns.UI_PLANS_CARD_METRICS or {}
    local ICON_LEFT = 8
    local ICON_SIZE = tonumber(data.iconSize) or PCM.todoUnifiedIconSize or PCM.todoIconSize or 40
    local titleInset = data.titleRightInset or 90
    local FactEr = ns.UI and ns.UI.Factory
    local TYPE_BADGE_SIZE = data.typeBadgeSize or PCM.todoTypeBadgeSize or 24
    local iconTop = -(tonumber(PCM.todoIconRowTop) or 8)
    local metaGap = tonumber(PCM.todoMetaGap) or 6
    local titleGap = tonumber(PCM.todoTitleGap) or 6
    local summaryGap = tonumber(PCM.todoSummaryGap) or 4
    local summaryLineGap = tonumber(PCM.todoSummaryLineGap) or 3
    local chevronSz = tonumber(data.chevronSize) or tonumber(PCM.plansChevronSize) or 18
    local hasPoints = data.achievementPoints and tonumber(data.achievementPoints) and tonumber(data.achievementPoints) > 0
    local summaryRight = titleInset
    if data.canExpand ~= false then
        summaryRight = summaryRight + chevronSz + 4
    end

    row._todoIconLeft = ICON_LEFT
    row._todoTitleGap = titleGap
    row._todoSummaryGap = summaryGap
    row._todoMetaRowCentered = true
    row._todoSummaryAnchor = nil
    row._todoSummaryBandTopGap = tonumber(PCM.todoSummaryBandTopGap) or 6
    row._todoSummaryRightInset = summaryRight

    local iconFrame
    if data.icon then
        iconFrame = CreateIcon(headerFrame, data.icon, ICON_SIZE, data.iconIsAtlas == true, nil, false)
        iconFrame:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", ICON_LEFT, iconTop)
        iconFrame:Show()
        row.iconFrame = iconFrame
    end
    row._todoSummaryAnchor = iconFrame or headerFrame

    local function AnchorBadgeOnIcon(badge, icon)
        if not badge or not icon then return end
        badge:SetPoint("LEFT", icon, "RIGHT", metaGap, 0)
        badge:SetPoint("CENTER", icon, "CENTER", 0, 0)
    end

    local titleAnchor = iconFrame or headerFrame
    if hasPoints and iconFrame then
        local shieldFrame = CreateSquareTypeBadge(headerFrame, "UI-Achievement-Shield-NoPoints", TYPE_BADGE_SIZE, FactEr)
        if shieldFrame then
            AnchorBadgeOnIcon(shieldFrame, iconFrame)
            row.typeBadge = shieldFrame
            titleAnchor = shieldFrame
        end
    elseif data.typeAtlas and iconFrame then
        local typeBadgeFrame = CreateSquareTypeBadge(headerFrame, data.typeAtlas, TYPE_BADGE_SIZE, FactEr)
        if typeBadgeFrame then
            AnchorBadgeOnIcon(typeBadgeFrame, iconFrame)
            row.typeBadge = typeBadgeFrame
            titleAnchor = typeBadgeFrame
        end
    end
    row._todoTitleAnchor = titleAnchor

    local metaRightText
    if data.metaRightText and data.metaRightText ~= "" then
        metaRightText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
        metaRightText:SetJustifyH("RIGHT")
        metaRightText:SetWordWrap(false)
        metaRightText:SetMaxLines(1)
        metaRightText:SetText(data.metaRightText)
        row.metaRightText = metaRightText
    end

    local titleText = FontManager:CreateFontString(headerFrame, "title", "OVERLAY")
    titleText:SetPoint("LEFT", titleAnchor, "RIGHT", titleGap, 0)
    if metaRightText then
        metaRightText:SetPoint("RIGHT", headerFrame, "RIGHT", -titleInset, 0)
        if iconFrame then
            metaRightText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
        end
        titleText:SetPoint("RIGHT", metaRightText, "LEFT", -titleGap, 0)
    else
        titleText:SetPoint("RIGHT", headerFrame, "RIGHT", -titleInset, 0)
    end
    if iconFrame then
        titleText:SetPoint("TOP", iconFrame, "TOP", 0, 0)
        if not hasPoints then
            titleText:SetPoint("BOTTOM", iconFrame, "BOTTOM", 0, 0)
            titleText:SetJustifyV("MIDDLE")
        else
            titleText:SetJustifyV("TOP")
        end
    end
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    titleText:SetMaxLines(1)
    titleText:SetNonSpaceWrap(false)
    titleText:SetText("|cffffffff" .. (data.title or (ns.L and ns.L["UNKNOWN"]) or "Unknown") .. "|r")
    row.titleText = titleText

    if hasPoints then
        local pts = data.achievementPoints
        local pointsText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
        pointsText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
        pointsText:SetPoint("RIGHT", titleText, "RIGHT", 0, 0)
        pointsText:SetJustifyH("LEFT")
        pointsText:SetWordWrap(false)
        pointsText:SetMaxLines(1)
        local ptsStr = ns.UI_FormatPlanPoints and ns.UI_FormatPlanPoints(pts)
        if ptsStr then
            pointsText:SetText(ptsStr)
        else
            pointsText:SetText("|cffffd700" .. tostring(tonumber(pts) or 0) .. " " .. ((ns.L and ns.L["POINTS_LABEL"]) or "Points") .. "|r")
        end
        row.pointsSubText = pointsText
    end
    row._todoSummaryTopRef = iconFrame

    local summaryLines = data.summaryLines
    if (not summaryLines or #summaryLines == 0) and data.summaryLine and data.summaryLine ~= "" then
        summaryLines = { data.summaryLine }
    end
    if summaryLines and #summaryLines > 0 and iconFrame then
        row.summaryTexts = {}
        local layout = ns.UI_PlansTodoSummaryLayout and ns.UI_PlansTodoSummaryLayout(rowHeight, #summaryLines, hasPoints)
        for li = 1, #summaryLines do
            local line = summaryLines[li]
            if line and line ~= "" then
                local summaryText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
                summaryText:SetJustifyH("LEFT")
                summaryText:SetJustifyV("MIDDLE")
                summaryText:SetWordWrap(false)
                summaryText:SetMaxLines(1)
                summaryText:SetNonSpaceWrap(false)
                summaryText:SetText(line)
                summaryText:SetPoint("LEFT", row._todoSummaryAnchor, "LEFT", 0, 0)
                if layout then
                    local slotY = -(layout.startFromIconBottom + (li - 1) * (layout.lineH + layout.lineGap))
                    summaryText:SetPoint("TOPLEFT", iconFrame, "BOTTOMLEFT", 0, slotY)
                    summaryText:SetHeight(layout.lineH)
                end
                summaryText:SetPoint("RIGHT", headerFrame, "RIGHT", -summaryRight, 0)
                row.summaryTexts[#row.summaryTexts + 1] = summaryText
                if li == 1 then
                    row.summaryText = summaryText
                end
            end
        end
    end

    headerFrame:SetHeight(rowHeight)
    row:SetHeight(rowHeight)
    row.SyncHeaderToTitle = function() end
end

--[[
    Create an expandable row for achievements/collections
    @param parent - Parent frame
    @param width - Row width
    @param rowHeight - Collapsed row height (default 32)
    @param data - Row data { icon, score, title, information, criteria }
    @param isExpanded - Initial expanded state
    @param onToggle - Callback function(isExpanded)
    @return row - Created expandable row frame
]]
local function CreateExpandableRow(parent, width, rowHeight, data, isExpanded, onToggle)
    -- Validate dependencies on first use (fail gracefully if not loaded)
    if not COLORS or not ApplyVisuals or not CreateIcon or not FontManager then
        DebugPrint("|cffff0000[ExpandableRowFactory] CRITICAL: Missing dependencies! SharedWidgets must load before ExpandableRowFactory.|r")
        return nil
    end
    
    if not parent or not data then return nil end
    
    local PCM0 = ns.UI_PLANS_CARD_METRICS or {}
    if data and data.todoUnifiedHeader then
        if data.collapsedHeight then
            rowHeight = data.collapsedHeight
        elseif ns.UI_PlansTodoFixedCollapsedHeight then
            local hasPts = data.achievementPoints and tonumber(data.achievementPoints) and tonumber(data.achievementPoints) > 0
            rowHeight = ns.UI_PlansTodoFixedCollapsedHeight(hasPts)
        else
            rowHeight = rowHeight or PCM0.todoUnifiedHeaderHeight
        end
    else
        rowHeight = rowHeight or UI_SPACING.CHAR_ROW_HEIGHT
    end
    local FactEr = ns.UI and ns.UI.Factory
    local wRow = math.max(50, width or 120)
    
    -- Main container (will grow/shrink but header stays at top)
    local row = FactEr and FactEr:CreateContainer(parent, wRow, rowHeight, false)
    if not row then
        row = CreateFrame("Frame", nil, parent)
    end
    row:SetWidth(width)
    row:SetHeight(rowHeight) -- Initial height
    if row.SetClipsChildren then
        row:SetClipsChildren(false)
    end

    -- Store state
    row.isExpanded = isExpanded or false
    row.data = data
    row.rowHeight = rowHeight
    row.onToggle = onToggle
    
    -- Alternating row color (set by caller based on index)
    row.bgColor = COLORS.bgCard
    
    -- Header frame (FIXED HEIGHT, always visible at top) - Button for hover support
    local headerFrame = FactEr and FactEr.CreateButton and FactEr:CreateButton(row, wRow, rowHeight, true)
    if not headerFrame then
        headerFrame = CreateFrame("Button", nil, row)
        headerFrame:SetHeight(rowHeight)
    end
    headerFrame:SetPoint("TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", 0, 0)
    headerFrame:SetHeight(rowHeight)
    row.headerFrame = headerFrame
    
    -- Single unified backdrop on the row itself, not on header/details separately. This way the
    -- collapsed and expanded states share one continuous border (no double-line at the seam).
    if ApplyVisuals then
        local borderColor = {
            COLORS.accent[1] * 0.8,
            COLORS.accent[2] * 0.8,
            COLORS.accent[3] * 0.8,
            0.4
        }
        ApplyVisuals(row, row.bgColor, borderColor)
    end

    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(headerFrame)
    end
    
    -- Single-step height apply: onToggle runs when geometry + layout are committed.
    local function ToggleExpand()
        if data.canExpand == false then return end
        local newExpanded = not row.isExpanded
        row.isExpanded = newExpanded
        if ns.UI_CollapseExpandSetState and row.expandBtn then
            ns.UI_CollapseExpandSetState(row.expandBtn, newExpanded)
        end

        if newExpanded then
            local fullDetailsH = BuildRowDetailsFrame(row)
            ApplyRowExpandedGeometry(row, fullDetailsH)
            if row.onToggle then row.onToggle(true) end
        else
            ApplyRowExpandedGeometry(row, 0)
            if row.onToggle then row.onToggle(false) end
        end
    end
    
    local PCM = ns.UI_PLANS_CARD_METRICS or {}
    local rowNudgeY = tonumber(PCM.rowIconNudgeY) or 0
    local chevronSz = tonumber(data.chevronSize) or tonumber(PCM.plansChevronSize) or 18
    local canExpandRow = data.canExpand ~= false
    local chevronInteractive = canExpandRow and (not data.todoUnifiedHeader or canExpandRow)
    local expandBtn = (ns.UI_CreateCollapseExpandControl and ns.UI_CreateCollapseExpandControl(headerFrame, isExpanded, {
        enableMouse = chevronInteractive,
        size = chevronSz,
    })) or CreateFrame("Button", nil, headerFrame)
    if expandBtn and not expandBtn._wnCollapseTex then
        expandBtn:SetSize(chevronSz, chevronSz)
    end
    if data.todoUnifiedHeader then
        if not canExpandRow then
            expandBtn:Hide()
        end
    else
        expandBtn:SetPoint("LEFT", 6, rowNudgeY)
        if not canExpandRow then
            expandBtn:Hide()
        elseif chevronInteractive then
            expandBtn:RegisterForClicks("LeftButtonUp")
            expandBtn:SetScript("OnClick", function(_, button)
                if button ~= "LeftButton" then return end
                ToggleExpand()
            end)
        end
    end
    row.expandBtn = expandBtn

    if canExpandRow then
        headerFrame:EnableMouse(true)
        headerFrame:RegisterForClicks("LeftButtonUp")
        headerFrame:SetScript("OnClick", function(_, button)
            if button ~= "LeftButton" then return end
            ToggleExpand()
        end)
    else
        headerFrame:SetScript("OnClick", nil)
    end

    if data.todoUnifiedHeader then
        ApplyTodoUnifiedHeader(row, headerFrame, data, rowHeight)
        if canExpandRow and row.expandBtn then
            row._todoChevronBottomRight = true
            local chevIn = tonumber(PCM.todoChevronInset) or 6
            row.expandBtn:ClearAllPoints()
            row.expandBtn:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", -chevIn, chevIn)
            row.expandBtn:Show()
            row.expandBtn:EnableMouse(true)
            if row.expandBtn.RegisterForClicks then
                row.expandBtn:RegisterForClicks("LeftButtonUp")
            end
            row.expandBtn:SetScript("OnClick", function(_, button)
                if button ~= "LeftButton" then return end
                ToggleExpand()
            end)
            row.expandBtn:Raise()
        end
    else
    -- Item Icon (after expand button). data.iconSize overrides the default for callers that
    -- want a chunkier portrait. Title and type badge anchor to this frame so they stay aligned
    -- regardless of icon size. Supports atlas icons via data.iconIsAtlas.
    local ICON_SIZE = data.iconSize or (PCM.todoIconSize or (UI_SPACING.HEADER_ICON_SIZE + 4))
    local ICON_LEFT = 6 + chevronSz + 4
    local iconFrame
    if data.icon then
        -- Show the same pixel border as Plan cards (CreateIcon noBorder=false) so To-Do rows match grid cards.
        iconFrame = CreateIcon(headerFrame, data.icon, ICON_SIZE, data.iconIsAtlas == true, nil, false)
        iconFrame:SetPoint("LEFT", ICON_LEFT, rowNudgeY)
        iconFrame:Show()  -- CRITICAL: Show the row icon!
        row.iconFrame = iconFrame
    end

    -- Optional small TYPE atlas badge rendered immediately to the RIGHT of the icon
    -- (e.g. shield atlas for achievements, dragon-rostrum for mounts). Uses data.typeAtlas.
    local TYPE_BADGE_SIZE = data.typeBadgeSize or PCM.rowTypeBadgeSize or 20
    local TYPE_BADGE_GAP = 4
    local typeBadgeFrame
    if data.typeAtlas then
        typeBadgeFrame = FactEr and FactEr:CreateContainer(headerFrame, TYPE_BADGE_SIZE, TYPE_BADGE_SIZE, false)
        if not typeBadgeFrame then
            typeBadgeFrame = CreateFrame("Frame", nil, headerFrame)
        end
        typeBadgeFrame:SetSize(TYPE_BADGE_SIZE, TYPE_BADGE_SIZE)
        if iconFrame then
            typeBadgeFrame:SetPoint("LEFT", iconFrame, "RIGHT", TYPE_BADGE_GAP, rowNudgeY)
        else
            typeBadgeFrame:SetPoint("LEFT", headerFrame, "LEFT", ICON_LEFT + ICON_SIZE + TYPE_BADGE_GAP, rowNudgeY)
        end
        local typeTex = typeBadgeFrame:CreateTexture(nil, "OVERLAY")
        local inset = tonumber(PCM.rowTypeBadgeInset) or math.max(1, math.floor(TYPE_BADGE_SIZE * 0.10 + 0.5))
        typeTex:SetPoint("TOPLEFT", typeBadgeFrame, "TOPLEFT", inset, -inset)
        typeTex:SetPoint("BOTTOMRIGHT", typeBadgeFrame, "BOTTOMRIGHT", -inset, inset)
        local ok = pcall(function() typeTex:SetAtlas(data.typeAtlas, false) end)
        if ok then
            typeBadgeFrame:Show()
            row.typeBadge = typeBadgeFrame
        else
            typeBadgeFrame:Hide()
            typeBadgeFrame = nil
        end
    end

    -- Score: either inline (legacy) or below the title (data.scoreBelow = true).
    if data.score and not data.scoreBelow then
        local scoreText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
        scoreText:SetPoint("LEFT", iconFrame or headerFrame, iconFrame and "RIGHT" or "LEFT", iconFrame and (TYPE_BADGE_GAP + 2) or (ICON_LEFT + ICON_SIZE + TYPE_BADGE_GAP + 2), 6)
        scoreText:SetWidth(60)
        scoreText:SetJustifyH("LEFT")
        scoreText:SetJustifyV("TOP")
        scoreText:SetWordWrap(false)
        scoreText:SetText("|cffffd700" .. data.score .. ((ns.L and ns.L["POINTS_SHORT"]) or " pts") .. "|r")
        row.scoreText = scoreText
    end

    -- Title: anchored to the right of icon (or type badge if present) so it always lines up.
    local titleText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
    local titleAnchorFrame, titleAnchorGap
    if data.score and not data.scoreBelow then
        titleAnchorFrame = row.scoreText
        titleAnchorGap = 4
    elseif typeBadgeFrame then
        titleAnchorFrame = typeBadgeFrame
        titleAnchorGap = TYPE_BADGE_GAP
    elseif iconFrame then
        titleAnchorFrame = iconFrame
        titleAnchorGap = TYPE_BADGE_GAP
    end
    -- Title shares the icon's vertical center (so single-line titles sit on the icon mid-line),
    -- and grows downward when wrapped. LEFT anchors to icon/badge RIGHT for horizontal lock-step.
    if titleAnchorFrame then
        titleText:SetPoint("LEFT", titleAnchorFrame, "RIGHT", titleAnchorGap, 0)
    else
        titleText:SetPoint("LEFT", headerFrame, "LEFT", ICON_LEFT + ICON_SIZE + TYPE_BADGE_GAP, 0)
    end
    titleText:SetPoint("RIGHT", headerFrame, "RIGHT", -(data.titleRightInset or 90), 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetJustifyV("TOP")
    titleText:SetWordWrap(true)
    titleText:SetMaxLines(2)
    titleText:SetNonSpaceWrap(false)
    titleText:SetText("|cffffffff" .. (data.title or (ns.L["UNKNOWN"] or "Unknown")) .. "|r")
    row.titleText = titleText

    -- Score-below layout: render points under the title, sharing the title's left margin.
    if data.score and data.scoreBelow then
        local scoreText = FontManager:CreateFontString(headerFrame, "small", "OVERLAY")
        scoreText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
        scoreText:SetJustifyH("LEFT")
        scoreText:SetWordWrap(false)
        scoreText:SetText("|cffffd700" .. data.score .. ((ns.L and ns.L["POINTS_SHORT"]) or " pts") .. "|r")
        row.scoreText = scoreText
    end

    local function SyncHeaderToTitle()
        local th = titleText:GetStringHeight() or 14
        local minHeader = rowHeight
        local extraScoreH = 0
        if data.score and data.scoreBelow and row.scoreText then
            extraScoreH = (row.scoreText:GetStringHeight() or 12) + 4
        elseif data.score and row.scoreText then
            minHeader = math.max(minHeader, row.scoreText:GetStringHeight() + 12)
        end
        local newH = math.max(minHeader, th + extraScoreH + 12)
        headerFrame:SetHeight(newH)
        if row.detailsFrame and row.detailsFrame:IsShown() then
            row:SetHeight(headerFrame:GetHeight() + row.detailsFrame:GetHeight())
        else
            row:SetHeight(headerFrame:GetHeight())
        end
    end
    row.SyncHeaderToTitle = SyncHeaderToTitle
    SyncHeaderToTitle()
    end

    row.detailsFrame = nil

    -- Initialize expanded state (without row.onToggle — avoids populate loops)
    if isExpanded then
        row.isExpanded = true
        if ns.UI_CollapseExpandSetState and row.expandBtn then
            ns.UI_CollapseExpandSetState(row.expandBtn, true)
        end
        local fullDetailsH = BuildRowDetailsFrame(row)
        ApplyRowExpandedGeometry(row, fullDetailsH)
    end

    row.RebuildDetails = function()
        if not row.isExpanded then return end
        local fullDetailsH = BuildRowDetailsFrame(row)
        ApplyRowExpandedGeometry(row, fullDetailsH)
    end

    return row
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export to namespace
ns.UI_CreateExpandableRow = CreateExpandableRow

--- Remeasure expanded body + reflow masonry (Plans To-Do rows; no card.plan).
function ns.UI_ReflowExpandableTodoRow(row, opts)
    if not row or not row.data then return end
    if row.isExpanded then
        local fullDetailsH = BuildRowDetailsFrame(row)
        ApplyRowExpandedGeometry(row, fullDetailsH)
    else
        ApplyRowExpandedGeometry(row, 0)
    end
    if opts and opts.deferLayout then
        return
    end
    local lm = row._layoutManager
    local CLM = ns.UI_CardLayoutManager
    if lm and CLM then
        CLM:RecalculateAllPositions(lm)
    end
end

-- Module loaded - verbose logging hidden (debug mode only)
