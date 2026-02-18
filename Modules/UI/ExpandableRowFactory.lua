--[[
    Warband Nexus - Expandable Row Factory
    Creates expandable rows for achievements/collections with expand/collapse functionality
    
    Extracted from SharedWidgets.lua for better modularity
    Used in Plans UI for achievement tracking
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
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
    local leftMargin = 48
    local rightMargin = 16
    local sectionSpacing = 6
    
    -- Information Section (inline: "Description: text...")
    if data.information and data.information ~= "" then
        -- Combined header + text in one line
        local infoText = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
        infoText:SetPoint("TOPLEFT", leftMargin, yOffset)
        infoText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
        infoText:SetJustifyH("LEFT")
        infoText:SetText("|cff88cc88" .. ((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r |cffdddddd" .. data.information .. "|r")
        infoText:SetWordWrap(true)
        infoText:SetSpacing(2)
        
        local textHeight = infoText:GetStringHeight()
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
        
        -- Section header with inline progress
        local reqLabel = (ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:"
        local headerText = "|cffffcc00" .. reqLabel .. "|r"
        if progressLine then
            headerText = headerText .. " " .. progressLine
        end
        
        local criteriaHeader = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
        criteriaHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
        criteriaHeader:SetPoint("TOPRIGHT", -rightMargin, yOffset)
        criteriaHeader:SetJustifyH("LEFT")
        criteriaHeader:SetText(headerText)
        
        yOffset = yOffset - 20
        
        -- Render criteria grid
        if #criteriaItems > 0 then
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
                    local maxLineHeight = 16
                    for colIndex, criteriaItem in ipairs(currentRow) do
                        local xPos = leftMargin + (colIndex - 1) * columnWidth
                        local criteriaText = criteriaItem.text or criteriaItem
                        local linkedID = criteriaItem.linkedAchievementID
                        
                        local isCompleted = criteriaItem.completed
                        if linkedID and ShowAchievementPopup and not isCompleted then
                            -- Interactive: Button frame for incomplete achievement-linked criteria
                            local btn = CreateFrame("Button", nil, detailsFrame)
                            btn:SetPoint("TOPLEFT", xPos, yOffset)
                            btn:SetSize(columnWidth - 8, 16)
                            
                            local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
                            label:SetPoint("LEFT")
                            label:SetWidth(columnWidth - 12)
                            label:SetJustifyH("LEFT")
                            label:SetText(criteriaText)
                            label:SetWordWrap(false)
                            label:SetMaxLines(1)
                            
                            -- Hover: subtle alpha feedback only (popup on click)
                            btn:SetScript("OnEnter", function()
                                label:SetAlpha(0.7)
                            end)
                            btn:SetScript("OnLeave", function()
                                label:SetAlpha(1)
                            end)
                            
                            -- Click: open achievement popup with Track + Add
                            btn:SetScript("OnClick", function(self)
                                ShowAchievementPopup(linkedID, self)
                            end)
                            
                            local textH = label:GetStringHeight() or 16
                            if textH > maxLineHeight then maxLineHeight = textH end
                        else
                            -- Standard: plain FontString for non-achievement criteria
                            local colLabel = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
                            colLabel:SetPoint("TOPLEFT", xPos, yOffset)
                            colLabel:SetWidth(columnWidth - 8)
                            colLabel:SetJustifyH("LEFT")
                            -- Legacy items are plain strings; structured items have .text
                            local displayText = type(criteriaText) == "string" and criteriaText or tostring(criteriaText)
                            colLabel:SetText("|cffeeeeee" .. displayText .. "|r")
                            colLabel:SetWordWrap(true)
                            colLabel:SetNonSpaceWrap(false)
                            colLabel:SetMaxLines(2)
                            local textH = colLabel:GetStringHeight() or 16
                            if textH > maxLineHeight then maxLineHeight = textH end
                        end
                    end
                    
                    yOffset = yOffset - maxLineHeight - 4
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
            
            -- Show details and resize row
            row.detailsFrame:Show()
            local totalHeight = rowHeight + row.detailsFrame:GetHeight()
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
            row:SetHeight(rowHeight)
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
    
    -- Item Icon (after expand button) - WoW-like smaller
    if data.icon then
        local iconFrame = CreateIcon(headerFrame, data.icon, UI_SPACING.HEADER_ICON_SIZE + 4, false, nil, true)
        iconFrame:SetPoint("LEFT", 32, 0)
        iconFrame:Show()  -- CRITICAL: Show the row icon!
        row.iconFrame = iconFrame
    end
    
    -- Score (for achievements) or Type badge - WoW-like compact
    if data.score then
        local scoreText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
        scoreText:SetPoint("LEFT", 68, 0)
        scoreText:SetWidth(60)
        scoreText:SetJustifyH("LEFT")
        scoreText:SetText("|cffffd700" .. data.score .. ((ns.L and ns.L["POINTS_SHORT"]) or " pts") .. "|r")
        row.scoreText = scoreText
    end
    
    -- Title - WoW-like normal font
    local titleText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
    titleText:SetPoint("LEFT", data.score and 134 or 68, 0)
    titleText:SetPoint("RIGHT", -90, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffffff" .. (data.title or (ns.L["UNKNOWN"] or "Unknown")) .. "|r")
    titleText:SetWordWrap(false)
    row.titleText = titleText
    
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
        
        local totalHeight = rowHeight + row.detailsFrame:GetHeight()
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
