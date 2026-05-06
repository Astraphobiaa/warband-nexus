--[[
    Warband Nexus - Expandable Row Factory
    Creates expandable rows for achievements/collections with expand/collapse functionality
    
    Extracted from SharedWidgets.lua for better modularity
    Used in Plans UI for achievement tracking
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local DebugPrint = ns.DebugPrint
-- Import dependencies from SharedWidgets (with safety checks)
local UI_SPACING = ns.UI_SPACING  -- Standardized spacing constants
local COLORS = ns.UI_COLORS  -- Use COLORS table instead of GetColors function
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateIcon = ns.UI_CreateIcon
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
    local bgColor = options.bgColor or {row.bgColor[1] * 0.7, row.bgColor[2] * 0.7, row.bgColor[3] * 0.7, 1}
    local borderColor = options.borderColor or {
        COLORS.accent[1] * 0.4,
        COLORS.accent[2] * 0.4,
        COLORS.accent[3] * 0.4,
        0.6
    }
    
    local detailsFrame = CreateFrame("Frame", nil, parentFrame)
    detailsFrame:SetPoint("TOPLEFT", row.headerFrame, "BOTTOMLEFT", 0, -1)
    detailsFrame:SetPoint("TOPRIGHT", row.headerFrame, "BOTTOMRIGHT", 0, -1)
    
    -- Background and border for expanded section
    if ApplyVisuals then
        ApplyVisuals(detailsFrame, bgColor, borderColor)
    else
        if detailsFrame.SetBackdrop then
            detailsFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            detailsFrame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
            detailsFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
    end
    
    -- Divider line between header and details
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
        
        -- Section header with inline progress (left-anchored, same margin as Description)
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
        
        -- Render criteria grid (fixed line height for even two-column alignment, no wrap to avoid "0 / \n1)")
        if #criteriaItems > 0 then
            local CRITERIA_LINE_HEIGHT = 16
            local availableWidth = row:GetWidth() - leftMargin - rightMargin
            local columnsPerRow = data.criteriaColumns or 2
            if #criteriaItems <= 2 then
                columnsPerRow = 1
            end
            columnsPerRow = math.min(columnsPerRow, 2)
            local columnWidth = availableWidth / columnsPerRow
            local currentRow = {}
            
            local ShowAchievementPopup = ns.UI_ShowAchievementPopup
            
            for i, item in ipairs(criteriaItems) do
                table.insert(currentRow, item)
                
                if #currentRow == columnsPerRow or i == #criteriaItems then
                    for colIndex, criteriaItem in ipairs(currentRow) do
                        local xPos = leftMargin + (colIndex - 1) * columnWidth
                        local criteriaText = criteriaItem.text or criteriaItem
                        local linkedID = criteriaItem.linkedAchievementID
                        
                        local isCompleted = criteriaItem.completed
                        if linkedID and ShowAchievementPopup and not isCompleted then
                            -- Interactive: Button frame for incomplete achievement-linked criteria
                            local btn = CreateFrame("Button", nil, detailsFrame)
                            btn:SetPoint("TOPLEFT", xPos, yOffset)
                            btn:SetSize(columnWidth - 8, CRITERIA_LINE_HEIGHT)
                            
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
                    currentRow = {}
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
    
    if not parent then return nil end
    
    rowHeight = rowHeight or UI_SPACING.CHAR_ROW_HEIGHT  -- Use standardized character row height
    
    -- Main container (will grow/shrink but header stays at top)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)
    row:SetHeight(rowHeight) -- Initial height
    
    -- Store state
    row.isExpanded = isExpanded or false
    row.data = data
    row.rowHeight = rowHeight
    row.onToggle = onToggle
    
    -- Alternating row color (set by caller based on index)
    row.bgColor = {0.08, 0.08, 0.10, 1}
    
    -- Header frame (FIXED HEIGHT, always visible at top) - Button for hover support
    local headerFrame = CreateFrame("Button", nil, row)
    headerFrame:SetPoint("TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", 0, 0)
    headerFrame:SetHeight(rowHeight)
    row.headerFrame = headerFrame
    
    -- Apply background and gradient border to header
    if ApplyVisuals then
        -- Gradient border: brighter at top, darker at bottom
        local borderColor = {
            COLORS.accent[1] * 0.8,
            COLORS.accent[2] * 0.8,
            COLORS.accent[3] * 0.8,
            0.4
        }
        ApplyVisuals(headerFrame, row.bgColor, borderColor)
    end
    
    -- Apply highlight effect
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(headerFrame)
    else
        -- Fallback: simple border
        if headerFrame.SetBackdrop then
            headerFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                tileSize = 1,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            headerFrame:SetBackdropColor(row.bgColor[1], row.bgColor[2], row.bgColor[3], row.bgColor[4])
            headerFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.5)
        end
    end
    
    -- Toggle function (header stays fixed, only details expand below)
    local function ToggleExpand()
        row.isExpanded = not row.isExpanded
        
        if row.isExpanded then
            -- Use atlas for up arrow (collapse)
            if row.expandBtnNormalTex then
                row.expandBtnNormalTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
            end
            if row.expandBtnHighlightTex then
                row.expandBtnHighlightTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
            end
            
            -- Create details frame if not exists (positioned BELOW header)
            -- Phase 4.7: Use shared function to avoid code duplication
            if not row.detailsFrame then
                row.detailsFrame = CreateDetailsFrame(row, row, { data = data })
            end
            
            -- Show details and resize row (header may be taller than rowHeight when title wraps)
            row.detailsFrame:Show()
            local totalHeight = headerFrame:GetHeight() + row.detailsFrame:GetHeight()
            row:SetHeight(totalHeight)
        else
            -- Use atlas for down arrow (expand)
            if row.expandBtnNormalTex then
                row.expandBtnNormalTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
            end
            if row.expandBtnHighlightTex then
                row.expandBtnHighlightTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
            end
            
            -- Hide details and collapse row
            if row.detailsFrame then
                row.detailsFrame:Hide()
            end
            row:SetHeight(headerFrame:GetHeight())
        end
        
        -- Callback
        if row.onToggle then
            row.onToggle(row.isExpanded)
        end
    end
    
    -- Expand/Collapse button (inside header) - Using atlas arrows
    local expandBtn = CreateFrame("Button", nil, headerFrame)
    expandBtn:SetSize(20, 20)
    expandBtn:SetPoint("LEFT", 6, 0)
    
    -- Create textures and set atlas
    local normalTex = expandBtn:CreateTexture(nil, "ARTWORK")
    normalTex:SetAllPoints()
    if isExpanded then
        normalTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
    else
        normalTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
    end
    expandBtn:SetNormalTexture(normalTex)
    
    local highlightTex = expandBtn:CreateTexture(nil, "HIGHLIGHT")
    highlightTex:SetAllPoints()
    if isExpanded then
        highlightTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
    else
        highlightTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
    end
    highlightTex:SetAlpha(0.3)
    expandBtn:SetHighlightTexture(highlightTex)
    
    -- Store texture references for toggle updates
    row.expandBtnNormalTex = normalTex
    row.expandBtnHighlightTex = highlightTex
    
    expandBtn:SetScript("OnClick", function()
        ToggleExpand()
    end)
    row.expandBtn = expandBtn
    
    -- Make entire header clickable for expand/collapse
    headerFrame:EnableMouse(true)
    headerFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            ToggleExpand()
        end
    end)
    
    -- Item Icon (after expand button) - WoW-like smaller. Supports atlas icons via data.iconIsAtlas.
    if data.icon then
        local iconFrame = CreateIcon(headerFrame, data.icon, UI_SPACING.HEADER_ICON_SIZE + 4, data.iconIsAtlas == true, nil, true)
        iconFrame:SetPoint("LEFT", 32, 0)
        iconFrame:Show()  -- CRITICAL: Show the row icon!
        row.iconFrame = iconFrame
    end

    -- Optional small TYPE atlas badge rendered immediately to the LEFT of the title
    -- (e.g. shield atlas for achievements, dragon-rostrum for mounts). Uses data.typeAtlas.
    local TYPE_BADGE_SIZE = 14
    local TYPE_BADGE_GAP = 4
    local typeBadgeXOffset = 0
    if data.typeAtlas then
        local typeBadge = CreateFrame("Frame", nil, headerFrame)
        typeBadge:SetSize(TYPE_BADGE_SIZE, TYPE_BADGE_SIZE)
        typeBadge:SetPoint("LEFT", headerFrame, "LEFT", 64, 0)
        local typeTex = typeBadge:CreateTexture(nil, "OVERLAY")
        typeTex:SetAllPoints()
        local ok = pcall(function() typeTex:SetAtlas(data.typeAtlas, false) end)
        if ok then
            typeBadge:Show()
            typeBadgeXOffset = TYPE_BADGE_SIZE + TYPE_BADGE_GAP
            row.typeBadge = typeBadge
        else
            typeBadge:Hide()
        end
    end

    -- Score: either inline (legacy) or below the title (data.scoreBelow = true).
    if data.score and not data.scoreBelow then
        local scoreText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
        scoreText:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 68, -6)
        scoreText:SetWidth(60)
        scoreText:SetJustifyH("LEFT")
        scoreText:SetJustifyV("TOP")
        scoreText:SetWordWrap(false)
        scoreText:SetText("|cffffd700" .. data.score .. ((ns.L and ns.L["POINTS_SHORT"]) or " pts") .. "|r")
        row.scoreText = scoreText
    end

    -- Title: allow 2 lines so long achievement names do not overlap the Track button area
    local titleText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
    local titleLeft
    if data.scoreBelow then
        -- Title sits next to the type badge (or icon when no badge); score moves under it.
        titleLeft = 64 + typeBadgeXOffset
    elseif data.score then
        -- Legacy layout: inline score occupies 68..128, title starts after.
        titleLeft = 134
    else
        titleLeft = 64 + typeBadgeXOffset
    end
    titleText:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", titleLeft, -6)
    titleText:SetPoint("RIGHT", headerFrame, "RIGHT", -90, 0)
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
    
    -- Expanded details container (created on demand)
    row.detailsFrame = nil
    
    -- Initialize expanded state (without triggering callbacks - CRITICAL for preventing infinite loops)
    if isExpanded then
        row.isExpanded = true
        -- Update textures to expanded state (up arrow)
        if row.expandBtnNormalTex then
            row.expandBtnNormalTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
        end
        if row.expandBtnHighlightTex then
            row.expandBtnHighlightTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
        end
        
        -- Manually create and show details without calling ToggleExpand
        -- (to avoid triggering onToggle callback during initialization)
        -- Phase 4.7: Use shared function to avoid code duplication
        row.detailsFrame = CreateDetailsFrame(row, row, { data = data })
        row.detailsFrame:Show()
        
        local totalHeight = headerFrame:GetHeight() + row.detailsFrame:GetHeight()
        row:SetHeight(totalHeight)
    end
    
    return row
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export to namespace
ns.UI_CreateExpandableRow = CreateExpandableRow

-- Module loaded - verbose logging hidden (debug mode only)
