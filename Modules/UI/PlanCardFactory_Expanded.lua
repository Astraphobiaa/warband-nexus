--[[
    Warband Nexus - Plan card expanded-content actions.
    Split from PlanCardFactory.lua (ops-041).
    Loaded before Modules/UI/PlanCardFactory.lua.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue

ns.PlanCardFactory = ns.PlanCardFactory or {}
local PlanCardFactory = ns.PlanCardFactory

local FontManager = ns.FontManager
local CardLayoutManager = ns.UI_CardLayoutManager
local FormatTextNumbers = ns.UI_FormatTextNumbers
local NormalizeColonLabelSpacing = ns.UI_NormalizeColonLabelSpacing
local format = string.format

local function PCol(key, fb)
    return ns.UI_GetPlanUIColor and ns.UI_GetPlanUIColor(key, fb) or fb
end

local function PMetricLabel()
    return PCol("metric")
end

local PLAN_CARD_BODY_RIGHT_INSET = 30

local function BuildAchievementProgressLabelText(achievementID)
    local summary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achievementID)
    if not summary or (summary.rawNumCriteria or 0) <= 0 then return nil end
    local headerTxt = ns.UI_FormatAchievementProgressHeader and ns.UI_FormatAchievementProgressHeader(summary)
    if not headerTxt or headerTxt == "" then return nil end
    local P2 = ns.PLAN_UI_COLORS or {}
    local done = (summary.displayMode == "quantity_bar" and summary.totalReqQuantity > 0 and summary.totalQuantity >= summary.totalReqQuantity)
        or (summary.completedCount >= summary.rawNumCriteria)
    local progressColor = done and (P2.progressFull or "|cff00ff00") or PCol("incomplete")
    local label = PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r "
    if summary.displayMode == "quantity_bar" and summary.hasProgressBased then
        local progressFmt = (ns.L and ns.L["PROGRESS_ON_FORMAT"]) or "You are %d / %d on the progress"
        return label .. progressColor .. format(progressFmt, summary.totalQuantity, summary.totalReqQuantity) .. "|r"
    end
    return label .. progressColor .. headerTxt .. "|r"
end

local PLAN_SRC_ICON_LG = (ns.UI_PLAN_SOURCE_ICON_LG) or 18
local PLAN_SRC_ROW_VPAD = 7

local function PlanSourceAdvanceY(y, fontString, useIconFloor)
    local lh = fontString:GetStringHeight() or 14
    local block = useIconFloor and math.max(lh, PLAN_SRC_ICON_LG + 4) or math.max(lh, 16)
    return y - block - PLAN_SRC_ROW_VPAD
end

local function PlanSourceIconMarkup(kind, size)
    if ns.UI_PlanSourceIconMarkup then
        return ns.UI_PlanSourceIconMarkup(kind, size)
    end
    size = size or PLAN_SRC_ICON_LG
    if kind == "loot" then
        return format("|A:Banker:%d:%d|a", size, size)
    elseif kind == "quest" then
        return format("|A:Islands-QuestTurnin:%d:%d|a", size, size)
    elseif kind == "location" then
        return format("|A:poi-islands-table:%d:%d|a", size, size)
    end
    return format("|A:Class:%d:%d|a", size, size)
end

--[[
    Create expandable content frame
]]
function PlanCardFactory:CreateExpandableContent(card, anchorFrame)
    local expandedContent = ns.UI.Factory:CreateContainer(card)
    -- Anchor to BOTTOM of anchorFrame with proper spacing (negative Y = down)
    expandedContent:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -8)
    expandedContent:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
    -- Don't set height here - it will be calculated dynamically based on content
    -- But set a minimum height to ensure frame exists
    expandedContent:SetHeight(1)
    card.expandedContent = expandedContent
    expandedContent:Hide()
    
    return expandedContent
end

--[[
    Create unified expand/collapse button for all card types
    @param card Frame - Card frame
    @param isExpanded boolean - Current expansion state
    @return Button - Expand button frame
]]
function PlanCardFactory:CreateExpandButton(card, isExpanded)
    -- Remove existing expand button if any
    if card._expandButton then
        local bin = ns.UI_RecycleBin
        card._expandButton:Hide()
        if bin then card._expandButton:SetParent(bin) else card._expandButton:SetParent(nil) end
        card._expandButton = nil
    end
    
    -- Create expand button (using Factory pattern, 20x20, same size as delete button)
    local expandButton = ns.UI.Factory:CreateButton(card, 20, 20, true)  -- noBorder=true
    expandButton:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 10)
    expandButton:EnableMouse(true)
    
    -- Create arrow icon texture
    local arrowTexture = expandButton:CreateTexture(nil, "OVERLAY")
    arrowTexture:SetAllPoints(expandButton)
    if isExpanded then
        arrowTexture:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
    else
        arrowTexture:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
    end
    expandButton.arrowTexture = arrowTexture
    
    card._expandButton = expandButton
    return expandButton
end

--[[
    Update expand button icon based on expansion state
    @param card Frame - Card frame
    @param isExpanded boolean - Current expansion state
]]
function PlanCardFactory:UpdateExpandButtonIcon(card, isExpanded)
    if card._expandButton and card._expandButton.arrowTexture then
        if isExpanded then
            card._expandButton.arrowTexture:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
        else
            card._expandButton.arrowTexture:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
        end
    end
end

--[[
    Setup unified card click handler for expand/collapse
    @param card Frame - Card frame
    @param expandCallback function - Callback to execute on expand/collapse
]]
function PlanCardFactory:SetupCardClickHandler(card, expandCallback)
    -- Store original click handler if exists (Midnight: GetScript errors when no script set on Frame)
    local originalOnMouseUp = nil
    do
        local ok, res = pcall(function() return card:GetScript("OnMouseUp") end)
        if ok then originalOnMouseUp = res end
    end
    
    if not card.clickedOnRemoveBtn then
        card.clickedOnRemoveBtn = false
    end
    if not card.clickedOnExpandButton then
        card.clickedOnExpandButton = false
    end
    
    card:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        
        -- Check if click was on remove button
        if self.clickedOnRemoveBtn then
            self.clickedOnRemoveBtn = false
            -- Call original handler for remove button functionality
            if originalOnMouseUp then
                originalOnMouseUp(self, button)
            end
            return
        end
        
        -- Check if click was on expand button
        if self.clickedOnExpandButton then
            self.clickedOnExpandButton = false
            -- Expand button has its own OnClick handler, don't trigger card click
            return
        end
        
        -- If we get here, it's a card click (not remove or expand button)
        -- Trigger expand/collapse on card click
        if expandCallback then
            expandCallback(self)
        end
    end)
end

--[[
    Remeasure achievement card stacked text (word-wrap) and sync frame height with layout manager.
    opts.deferLayout: only ApplyCardGeometry; caller runs RecalculateAllPositions once (resize batch).
]]

--[[
    Setup achievement expand/collapse handler
]]
function PlanCardFactory:SetupAchievementExpandHandler(card, plan)
    -- Create unified expand button (20x20, same size as delete button)
    local expandButton = self:CreateExpandButton(card, card.isExpanded or false)
    
    local factory = self
    
    -- Setup expand callback
    local expandCallback = function(cardFrame)
        local achievementID = cardFrame.planAchievementID or plan.achievementID
        if not achievementID then return end
        
        if cardFrame.isExpanded then
            -- Collapse
            cardFrame.isExpanded = false
            if cardFrame.cardKey then
                ns.expandedCards[cardFrame.cardKey] = false
            end
            if cardFrame.expandedContent then
                cardFrame.expandedContent:Hide()
            end
            if cardFrame.requirementsHeader then
                cardFrame.requirementsHeader:SetText(PMetricLabel() .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r ...")
            end
            
            -- Recalculate progress when collapsed to show same format as expanded
            if achievementID and cardFrame.progressLabel then
                local progressText = BuildAchievementProgressLabelText(achievementID)
                if progressText then
                    cardFrame.progressLabel:SetText(FormatTextNumbers(progressText))
                else
                    cardFrame.progressLabel:SetText(PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r")
                end
            elseif cardFrame.progressLabel then
                cardFrame.progressLabel:SetText(PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["PROGRESS_LABEL"]) or "Progress:") .. "|r")
            end
            
            factory:ReflowAchievementCard(cardFrame)
            -- Update expand button icon
            factory:UpdateExpandButtonIcon(cardFrame, false)
        else
            -- Expand
            cardFrame.isExpanded = true
            if cardFrame.cardKey then
                ns.expandedCards[cardFrame.cardKey] = true
            end
            
            local numCriteria = GetAchievementNumCriteria(achievementID)
            if numCriteria and numCriteria > 0 then
                PlanCardFactory:ExpandAchievementContent(cardFrame, achievementID)
                if cardFrame.expandedContent then
                    cardFrame.expandedContent:Show()
                end
            else
                PlanCardFactory:ExpandAchievementEmpty(cardFrame)
            end
            
            -- Update requirements header text
            if cardFrame.requirementsHeader then
                cardFrame.requirementsHeader:SetText(PMetricLabel() .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r")
            end
            
            -- Update expand button icon
            factory:UpdateExpandButtonIcon(cardFrame, true)
        end
    end
    
    -- Setup card click handler
    self:SetupCardClickHandler(card, expandCallback)
    
    -- Also setup expand button click
    expandButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        expandCallback(card)
    end)
end

--[[
    Expand achievement content with criteria
]]
function PlanCardFactory:ExpandAchievementContent(card, achievementID)
    local expandedContent = card.expandedContent
    if not expandedContent then 
        return 
    end
    local Factory = ns.UI and ns.UI.Factory

    -- Re-anchor expandedContent to requirementsHeader to ensure correct positioning
    local anchorFrame = card.requirementsHeader
    if anchorFrame then
        -- Clear all points and re-anchor to ensure correct position
        expandedContent:ClearAllPoints()
        expandedContent:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -8)
        expandedContent:SetPoint("RIGHT", card, "RIGHT", -PLAN_CARD_BODY_RIGHT_INSET, 0)
    end
    
    -- Clear previous content
    local bin = ns.UI_RecycleBin
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end
    
    local criteriaDetails = {}
    local achSummary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achievementID)
    local formatRowSuffix = ns.UI_FormatCriterionRowSuffix
    if achSummary and achSummary.criteria then
        for ci = 1, #achSummary.criteria do
            local row = achSummary.criteria[ci]
            if row.hasName and row.name then
                local progressText = formatRowSuffix and formatRowSuffix(row, achSummary) or ""
                if progressText ~= "" and not (issecretvalue and issecretvalue(progressText)) then
                    local trimmed = progressText:match("^%s*(.*)")
                    if trimmed and not (issecretvalue and issecretvalue(trimmed)) then
                        progressText = " " .. PCol("body") .. trimmed .. "|r"
                    end
                end
                local linkedAchievementID = row.linkedAchievementID
                local textColor
                if linkedAchievementID then
                    textColor = row.completed and "|cff44ddff" or "|cff44bbff"
                else
                    local P3 = ns.PLAN_UI_COLORS or {}
                    textColor = row.completed and (P3.completed or "|cff44ff44") or (P3.incomplete or PCol("incomplete"))
                end
                local formattedCriteriaName = FormatTextNumbers(row.name)
                local plannedSuffix = ""
                if linkedAchievementID then
                    local WarbandNexus = ns.WarbandNexus
                    if WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(linkedAchievementID) then
                        local plannedWord = (ns.L and ns.L["PLANNED"]) or "Planned"
                        plannedSuffix = " |cffffcc00(" .. plannedWord .. ")|r"
                    end
                end
                criteriaDetails[#criteriaDetails + 1] = {
                    completed = row.completed,
                    text = textColor .. formattedCriteriaName .. "|r" .. progressText .. plannedSuffix,
                    linkedAchievementID = linkedAchievementID,
                }
            end
        end
    end
    
    if card.progressLabel then
        local progressText = BuildAchievementProgressLabelText(achievementID)
        if progressText then
            card.progressLabel:SetText(FormatTextNumbers(progressText))
        end
    end
    
    -- Information text is now updated in card.infoText directly (not in expandedContent)
    local contentY = 0
    
    -- Criteria grid: max 2 columns when wide, 1 column when narrow
    local availableWidth = expandedContent:GetWidth()
    if availableWidth <= 0 then
        availableWidth = (card:GetWidth() or 200) - 40
    end
    local criteriaY = contentY - 8
    local numCols = (availableWidth >= 360) and 2 or 1
    local colWidth = availableWidth / numCols
    local ICON_COL_WIDTH = 18
    local currentRow = {}
    
    local ShowAchievementPopup = ns.UI_ShowAchievementPopup
    
    for i = 1, #criteriaDetails do
        local criteriaData = criteriaDetails[i]
        table.insert(currentRow, criteriaData)
        
        if #currentRow == numCols or i == #criteriaDetails then
            for colIdx = 1, #currentRow do
                local data = currentRow[colIdx]
                local xPos = (colIdx - 1) * colWidth
                local linkedID = data.linkedAchievementID
                
                -- Icon column (fixed width for consistent alignment)
                local iconLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                iconLabel:SetPoint("TOPLEFT", xPos, criteriaY)
                iconLabel:SetWidth(ICON_COL_WIDTH)
                iconLabel:SetJustifyH("CENTER")
                if data.completed then
                    iconLabel:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t")
                else
                    iconLabel:SetText("|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t")
                end
                
                if linkedID and ShowAchievementPopup and not data.completed then
                    -- Interactive: Button frame for incomplete achievement-linked criteria
                    local btnW = math.max(8, colWidth - ICON_COL_WIDTH - 4)
                    local btn = Factory and Factory.CreateButton and Factory:CreateButton(expandedContent, btnW, 16, true)
                    if not btn then
                        btn = CreateFrame("Button", nil, expandedContent)
                        btn:SetSize(btnW, 16)
                    end
                    btn:SetPoint("TOPLEFT", xPos + ICON_COL_WIDTH, criteriaY)
                    
                    local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
                    label:SetPoint("LEFT")
                    label:SetWidth(colWidth - ICON_COL_WIDTH - 8)
                    label:SetJustifyH("LEFT")
                    label:SetText(data.text)
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
                    -- Standard: plain FontString for non-achievement criteria
                    local colLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    colLabel:SetPoint("TOPLEFT", xPos + ICON_COL_WIDTH, criteriaY)
                    colLabel:SetWidth(colWidth - ICON_COL_WIDTH - 4)
                    colLabel:SetJustifyH("LEFT")
                    colLabel:SetText(data.text)
                    colLabel:SetWordWrap(false)
                    colLabel:SetNonSpaceWrap(false)
                    colLabel:SetMaxLines(1)
                end
            end
            criteriaY = criteriaY - 16
            currentRow = {}
        end
    end
    
    local ecPadding = 10
    expandedContent:SetHeight(math.max(ecPadding, math.abs(criteriaY) + ecPadding))
    expandedContent:Show()
    if card.requirementsHeader then
        card.requirementsHeader:SetText(PMetricLabel() .. NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENTS_LABEL"]) or "Requirements:") .. "|r")
        card.requirementsHeader:Show()
    end

    PlanCardFactory:ReflowAchievementCard(card)
end

--[[
    Expand achievement with no criteria â€” Criteria yoksa hiÃ§bir yerde gÃ¶sterme (header + bÃ¶lÃ¼m gizli)
]]
function PlanCardFactory:ExpandAchievementEmpty(card)
    local expandedContent = card.expandedContent
    if not expandedContent then return end

    local bin = ns.UI_RecycleBin
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end

    if card.requirementsHeader then
        card.requirementsHeader:Hide()
    end
    expandedContent:Hide()
    PlanCardFactory:ReflowAchievementCard(card)
end

--[[
    Create mount card
]]

--[[
    Setup description expand handler for custom cards (similar to SetupSourceExpandHandler)
]]
function PlanCardFactory:SetupDescriptionExpandHandler(card, plan)
    -- Create expand button
    local expandButton = self:CreateExpandButton(card, card._isDescriptionExpanded or false)
    card._expandButton = expandButton
    card._sourceExpandButton = expandButton
    
    local factory = self
    local expandCallback = function(cardFrame)
        -- Toggle expansion state
        local wasExpanded = cardFrame._isDescriptionExpanded or false
        cardFrame._isDescriptionExpanded = not wasExpanded
        
        -- Save state to persistent storage
        if cardFrame.cardKey then
            local descExpandKey = cardFrame.cardKey .. "_description"
            if not ns.expandedCards then
                ns.expandedCards = {}
            end
            ns.expandedCards[descExpandKey] = cardFrame._isDescriptionExpanded
        end
        
        -- Ensure state is boolean
        if type(cardFrame._isDescriptionExpanded) ~= "boolean" then
            cardFrame._isDescriptionExpanded = false
        end
        
        -- Update description text
        if cardFrame.fullDescription then
            -- Clear old elements
            local bin = ns.UI_RecycleBin
            if cardFrame.descriptionText then
                cardFrame.descriptionText:Hide()
                if bin then cardFrame.descriptionText:SetParent(bin) else cardFrame.descriptionText:SetParent(nil) end
                cardFrame.descriptionText = nil
            end
            if cardFrame.descriptionTextRest then
                cardFrame.descriptionTextRest:Hide()
                if bin then cardFrame.descriptionTextRest:SetParent(bin) else cardFrame.descriptionTextRest:SetParent(nil) end
                cardFrame.descriptionTextRest = nil
            end
            if cardFrame.descriptionLabel then
                cardFrame.descriptionLabel:Hide()
                if bin then cardFrame.descriptionLabel:SetParent(bin) else cardFrame.descriptionLabel:SetParent(nil) end
                cardFrame.descriptionLabel = nil
            end
            
            -- Calculate truncated description
            local cardWidth = cardFrame:GetWidth() or 200
            local collapsedAvailableWidth = cardWidth - 110
            local expandedAvailableWidth = cardWidth - 40
            local charsPerLineCollapsed = math.floor(collapsedAvailableWidth / 6)
            local charsPerLineExpanded = math.floor(expandedAvailableWidth / 6)
            local maxChars = math.min(charsPerLineCollapsed * 2, 80)
            
            local truncatedDescription = cardFrame.fullDescription
            if #cardFrame.fullDescription > maxChars then
                truncatedDescription = cardFrame.fullDescription:sub(1, maxChars - 3) .. "..."
            end
            
            local descY = -60
            
            -- Create label
            local descLabel = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
            descLabel:SetPoint("TOPLEFT", 10, descY)
            descLabel:SetText(PMetricLabel() .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
            cardFrame.descriptionLabel = descLabel
            
            local labelWidth = descLabel:GetStringWidth()
            
            if not cardFrame._isDescriptionExpanded then
                -- Collapsed: First line text only
                local descText = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
                descText:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
                descText:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
                descText:SetJustifyH("LEFT")
                descText:SetWordWrap(false)
                descText:SetMaxLines(1)
                descText:SetText(FormatTextNumbers(truncatedDescription))
                cardFrame.descriptionText = descText
            else
                -- Expanded: Manual text breaking
                local cardWidth = cardFrame:GetWidth() or 200
                local firstLineWidth = cardWidth - (10 + labelWidth + 5 + 30)
                local subsequentLineWidth = cardWidth - 40
                
                local charsPerFirstLine = math.floor(firstLineWidth / 6)
                local charsPerSubsequentLine = math.floor(subsequentLineWidth / 6)
                
                -- Store for height calculation
                cardFrame._charsPerFirstLine = charsPerFirstLine
                cardFrame._charsPerSubsequentLine = charsPerSubsequentLine
                
                -- Break text
                local firstLineText = cardFrame.fullDescription:sub(1, math.min(charsPerFirstLine, #cardFrame.fullDescription))
                local remainingText = #cardFrame.fullDescription > charsPerFirstLine and cardFrame.fullDescription:sub(charsPerFirstLine + 1) or ""
                
                -- First line
                local firstLineFS = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
                firstLineFS:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
                firstLineFS:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
                firstLineFS:SetJustifyH("LEFT")
                firstLineFS:SetWordWrap(false)
                firstLineFS:SetMaxLines(1)
                firstLineFS:SetText(firstLineText)
                cardFrame.descriptionText = firstLineFS
                
                -- Subsequent lines
                if #remainingText > 0 then
                    local restText = FontManager:CreateFontString(cardFrame, "body", "OVERLAY")
                    restText:SetPoint("TOPLEFT", 10, descY - 14)
                    restText:SetPoint("RIGHT", cardFrame, "RIGHT", -30, 0)
                    restText:SetJustifyH("LEFT")
                    restText:SetJustifyV("TOP")
                    restText:SetWordWrap(true)
                    restText:SetMaxLines(0)
                    restText:SetNonSpaceWrap(true)
                    restText:SetText(remainingText)
                    cardFrame.descriptionTextRest = restText
                end
            end
            
            -- Calculate new card height based on expansion state
            local originalHeight = cardFrame.originalHeight or 130
            local newHeight = originalHeight
            
            if cardFrame._isDescriptionExpanded then
                -- Wait for text to render, then calculate accurate height.
                -- Reuse a single hidden frame to avoid frame accumulation.
                local updateFrame = ns._planDescUpdateFrame
                if not updateFrame then
                    local updateFactory = ns.UI and ns.UI.Factory
                    if updateFactory and updateFactory.CreateContainer then
                        updateFrame = updateFactory:CreateContainer(UIParent, 1, 1, false)
                    else
                        updateFrame = CreateFrame("Frame", nil, UIParent)
                        updateFrame:SetSize(1, 1)
                    end
                    updateFrame:Hide()
                    ns._planDescUpdateFrame = updateFrame
                end
                updateFrame._targetCard = cardFrame
                updateFrame._origHeight = originalHeight
                updateFrame._count = 0
                updateFrame:SetScript("OnUpdate", function(self, elapsed)
                    self._count = self._count + 1
                    if self._count >= 2 then
                        local cf = self._targetCard
                        local restTextHeight = 0
                        if cf and cf.descriptionTextRest then
                            restTextHeight = cf.descriptionTextRest:GetStringHeight()
                        end
                        local collapsedHeight = 14
                        local labelAndFirstLineHeight = 14
                        local calculatedHeight = (self._origHeight or 130) - collapsedHeight + labelAndFirstLineHeight + restTextHeight
                        if cf then
                            cf:SetHeight(calculatedHeight)
                            if CardLayoutManager and cf._layoutManager then
                                CardLayoutManager:UpdateCardHeight(cf, calculatedHeight)
                            end
                        end
                        self:SetScript("OnUpdate", nil)
                    end
                end)
                updateFrame:Show()
                
                -- Set estimated height immediately
                local remainingTextLen = math.max(0, string.len(cardFrame.fullDescription) - (cardFrame._charsPerFirstLine or 0))
                local estimatedRestLines = math.ceil(remainingTextLen / (cardFrame._charsPerSubsequentLine or 1))
                local estimatedRestHeight = estimatedRestLines * 14
                newHeight = originalHeight + estimatedRestHeight
            end
            
            -- Update card height
            cardFrame:SetHeight(newHeight)
            
            -- Update expand button icon
            factory:UpdateExpandButtonIcon(cardFrame, cardFrame._isDescriptionExpanded)
            
            -- Update layout
            if CardLayoutManager and cardFrame._layoutManager then
                CardLayoutManager:UpdateCardHeight(cardFrame, newHeight)
            end
        end
    end
    
    -- Setup card click handler
    self:SetupCardClickHandler(card, expandCallback)
    
    -- Setup expand button click
    expandButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        expandCallback(card)
    end)
    
    -- Prevent expand button click from triggering card click
    expandButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            card.clickedOnExpandButton = true
        end
    end)
end

--[[
    Setup source expand handler for mount/pet/toy/illusion/title cards
    Expands to show all sources (without Details label)
]]
function PlanCardFactory:SetupSourceExpandHandler(card, plan, planType, anchorFrame)
    if not card._sources or #card._sources == 0 then
        return
    end

    -- One structured source: full text wraps inside the card (dynamic height via ReflowSourcePlanCard).
    if #card._sources <= 1 then
        return
    end

    card._needsExpand = true
    
    -- Create unified expand button (20x20, same size as delete button)
    local expandButton = self:CreateExpandButton(card, card._isSourceExpanded or false)
    
    local factory = self
    -- Setup expand callback (mimicking achievement system exactly)
    local expandCallback = function(cardFrame)
        -- Toggle source expansion state FIRST
        local wasExpanded = cardFrame._isSourceExpanded or false
        cardFrame._isSourceExpanded = not wasExpanded
        
        -- Save state to persistent storage (like achievement cards)
        if cardFrame.cardKey then
            local sourceExpandKey = cardFrame.cardKey .. "_source"
            if not ns.expandedCards then
                ns.expandedCards = {}
            end
            ns.expandedCards[sourceExpandKey] = cardFrame._isSourceExpanded
        end
        
        -- Ensure _needsExpand is set if expand button exists
        if cardFrame._sourceExpandButton then
            cardFrame._needsExpand = true
        end
        
        -- Ensure state is boolean, not nil
        if cardFrame._isSourceExpanded == nil then
            cardFrame._isSourceExpanded = false
        end
        
        if cardFrame._isSourceExpanded then
            factory:CreateSourceInfo(cardFrame, plan, -PLAN_CARD_CONTENT_TOP)
        else
            factory:CreateSourceInfo(cardFrame, plan, -PLAN_CARD_CONTENT_TOP)
        end
        
        factory:ReflowSourcePlanCard(cardFrame)
        factory:UpdateExpandButtonIcon(cardFrame, cardFrame._isSourceExpanded)
    end
    
    -- Setup card click handler
    self:SetupCardClickHandler(card, expandCallback)
    
    -- Also setup expand button click (prevent card click handler from firing)
    expandButton:SetScript("OnClick", function(self, button)
        if button ~= "LeftButton" then return end
        -- Prevent event bubbling to card
        expandCallback(card)
    end)
    
    -- Prevent expand button click from triggering card click
    expandButton:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            -- Mark that click was on expand button to prevent card handler
            if card then
                card.clickedOnExpandButton = true
            end
        end
    end)
    
    card._sourceExpandButton = expandButton
end

function PlanCardFactory:ExpandCardContent(card, planType)
    local expandedContent = card.expandedContent
    if not expandedContent then return end
    
    -- Clear previous content
    local bin = ns.UI_RecycleBin
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end
    
    local plan = card.plan
    local contentHeight = 0
    
    -- Type-specific expanded content
    -- Only Achievement cards have expand functionality
    if planType == "achievement" then
        -- Achievement expansion is handled in SetupAchievementExpandHandler
        -- This function is only called for achievement cards
        contentHeight = 0  -- Achievement has its own expansion logic
    elseif planType == "mount" then
        contentHeight = 0  -- No expand for mount
    elseif planType == "pet" then
        contentHeight = 0  -- No expand for pet
    elseif planType == "toy" then
        contentHeight = 0  -- No expand for toy
    elseif planType == "illusion" then
        contentHeight = 0  -- No expand for illusion
    elseif planType == "title" then
        contentHeight = 0  -- No expand for title
    end
    
    -- Update card height
    local expandedHeight = card.originalHeight + contentHeight + 8
    card:SetHeight(expandedHeight)
    expandedContent:Show()
    card.expandHeader:SetText(PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["DETAILS_LABEL"]) or "Details:") .. "|r")
    
    -- Update layout
    if CardLayoutManager and card._layoutManager then
        CardLayoutManager:UpdateCardHeight(card, expandedHeight)
    end
end

--[[
    Expand mount content - Show full source information with all details
]]
function PlanCardFactory:ExpandMountContent(expandedContent, plan)
    local yOffset = 0
    
    -- Parse multiple sources to get structured data (vendor, zone, cost, etc.)
    local planSourceSafe = plan.source and type(plan.source) == "string" and not (issecretvalue and issecretvalue(plan.source))
    if planSourceSafe and WarbandNexus and WarbandNexus.ParseMultipleSources then
        local success, sources = pcall(function()
            return WarbandNexus:ParseMultipleSources(plan.source)
        end)
        
        if success and sources and #sources > 0 then
            -- Show each source with full details
            for i = 1, #sources do
                local source = sources[i]
                -- Vendor or Drop
                if source.vendor then
                    local vendorText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    vendorText:SetPoint("TOPLEFT", 0, yOffset)
                    vendorText:SetPoint("RIGHT", 0, 0)
                    vendorText:SetText(PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:") .. "|r " .. PCol("body") .. source.vendor .. "|r")
                    vendorText:SetJustifyH("LEFT")
                    vendorText:SetWordWrap(true)
                    vendorText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, vendorText, false)
                elseif source.npc then
                    local npcColor = "ffffffff"
                    local sourceDB = ns.CollectibleSourceDB
                    if sourceDB and sourceDB.lockoutNpcNames and sourceDB.lockoutQuests then
                        local npcID = sourceDB.lockoutNpcNames[source.npc]
                        if npcID then
                            local questData = sourceDB.lockoutQuests[npcID]
                            if questData then
                                local questIDs = type(questData) == "table" and questData or { questData }
                                for qi = 1, #questIDs do
                                    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questIDs[qi]) then
                                        npcColor = "ff666666"
                                        break
                                    end
                                end
                            end
                        end
                    end
                    local dropText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    dropText:SetPoint("TOPLEFT", 0, yOffset)
                    dropText:SetPoint("RIGHT", 0, 0)
                    dropText:SetText(PlanSourceIconMarkup("loot") .. " " .. PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["DROP_LABEL"]) or "Drop:") .. "|r |c" .. npcColor .. " " .. source.npc .. "|r")
                    dropText:SetJustifyH("LEFT")
                    dropText:SetWordWrap(true)
                    dropText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, dropText, true)
                elseif source.quest then
                    local P = ns.PLAN_UI_COLORS or {}
                    local questLabel = NormalizeColonLabelSpacing((ns.L and ns.L["QUEST_LABEL"]) or "Quest:")
                    local questText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    questText:SetPoint("TOPLEFT", 0, yOffset)
                    questText:SetPoint("RIGHT", 0, 0)
                    questText:SetText(PlanSourceIconMarkup("quest") .. " " .. PCol("label") .. questLabel .. "|r" .. PCol("body") .. source.quest .. "|r")
                    questText:SetJustifyH("LEFT")
                    questText:SetWordWrap(true)
                    questText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, questText, true)
                end
                
                -- Location (Zone) â€” append difficulty label for mounts (consistent white; avoid duplication)
                if source.zone then
                    local zoneDiffLabel = ""
                    if plan and plan.type == "mount" and WarbandNexus and WarbandNexus.GetDropDifficulty then
                        local mountID = plan.mountID
                        if mountID then
                            local diff = WarbandNexus:GetDropDifficulty("mount", mountID)
                            local z = source.zone
                            local zSafe = z and type(z) == "string" and not (issecretvalue and issecretvalue(z))
                            local dSafe = diff and not (issecretvalue and issecretvalue(diff))
                            if dSafe and zSafe then
                                if not z:find("(" .. diff .. ")", 1, true) then
                                    local P = ns.PLAN_UI_COLORS or {}
                                    local bodyColor = PCol("body")
                                    zoneDiffLabel = " " .. bodyColor .. "(" .. diff .. ")|r"
                                end
                            end
                        end
                    end
                    local locationText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    locationText:SetPoint("TOPLEFT", 0, yOffset)
                    locationText:SetPoint("RIGHT", 0, 0)
                    locationText:SetText(PlanSourceIconMarkup("location") .. " " .. PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["LOCATION_LABEL"]) or "Location:") .. "|r " .. PCol("body") .. source.zone .. "|r" .. zoneDiffLabel)
                    locationText:SetJustifyH("LEFT")
                    locationText:SetWordWrap(true)
                    locationText:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, locationText, true)
                end
                
                -- Cost (if available)
                if source.cost then
                    local costText = source.cost
                    if type(costText) ~= "string" or (issecretvalue and issecretvalue(costText)) then
                        costText = nil
                    end
                    local currencyName = nil
                    
                    -- Try to identify currency from source text
                    if costText and plan.source and type(plan.source) == "string" and not (issecretvalue and issecretvalue(plan.source)) then
                        for textureID in plan.source:gmatch("|T(%d+)[:|]") do
                            local texID = tonumber(textureID)
                            if texID then
                                local textureMap = {
                                    [3743738] = 1767,   [3726260] = 1885,   [4638724] = 2003,
                                    [5453417] = 2803,   [5915096] = 3056,    [463446] = 515,
                                    [236396] = 241,     [1357486] = 1166,
                                }
                                local currencyID = textureMap[texID]
                                if currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                                    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                                    if info and info.name and not (issecretvalue and issecretvalue(info.name)) then
                                        currencyName = info.name
                                        break
                                    end
                                end
                            end
                        end
                    end
                    
                    if costText and costText:match("[Gg]old") then
                        currencyName = (ns.L and ns.L["GOLD_LABEL"]) or "Gold"
                    end
                    
                    if costText and currencyName and not (issecretvalue and issecretvalue(currencyName))
                        and currencyName ~= "Gold" then
                        costText = costText:gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        costText = costText .. " (" .. currencyName .. ")"
                    end
                    
                    if costText then
                        local costLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                        costLabel:SetPoint("TOPLEFT", 0, yOffset)
                        costLabel:SetPoint("RIGHT", 0, 0)
                        costLabel:SetText(PlanSourceIconMarkup("class") .. " " .. PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["COST_LABEL"]) or "Cost:") .. "|r " .. PCol("body") .. costText .. "|r")
                        costLabel:SetJustifyH("LEFT")
                        costLabel:SetWordWrap(true)
                        costLabel:SetNonSpaceWrap(false)
                        yOffset = PlanSourceAdvanceY(yOffset, costLabel, true)
                    end
                end
                
                -- Faction (if available)
                if source.faction then
                    local factionText = PlanSourceIconMarkup("class") .. " " .. PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["FACTION_LABEL"]) or "Faction:") .. "|r " .. PCol("body") .. source.faction .. "|r"
                    if source.renown then
                        local repType = source.isFriendship and ((ns.L and ns.L["FRIENDSHIP_LABEL"]) or "Friendship") or ((ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown")
                        factionText = factionText .. " |cffffcc00(" .. repType .. " " .. source.renown .. ")|r"
                    end
                    local factionLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    factionLabel:SetPoint("TOPLEFT", 0, yOffset)
                    factionLabel:SetPoint("RIGHT", 0, 0)
                    factionLabel:SetText(factionText)
                    factionLabel:SetJustifyH("LEFT")
                    factionLabel:SetWordWrap(true)
                    factionLabel:SetNonSpaceWrap(false)
                    yOffset = PlanSourceAdvanceY(yOffset, factionLabel, true)
                end
                
                -- Add spacing between sources
                if i < #sources then
                    yOffset = yOffset - 4
                end
            end
        else
            -- Fallback: Show raw source text if parsing fails
            local cleanSource = plan.source
            if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
                cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
            elseif WarbandNexus.CleanSourceText then
                cleanSource = WarbandNexus:CleanSourceText(cleanSource)
                if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
                    cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
                end
            end
            local sourceText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
            sourceText:SetPoint("TOPLEFT", 0, yOffset)
            sourceText:SetPoint("RIGHT", 0, 0)
            sourceText:SetText(PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r " .. PCol("body") .. cleanSource .. "|r")
            sourceText:SetJustifyH("LEFT")
            sourceText:SetWordWrap(true)
            -- Ensure text is rendered before measuring height (use GetStringHeight after SetText)
            local textHeight = sourceText:GetStringHeight() or 20
            yOffset = yOffset - textHeight - 8
        end
    elseif plan.source then
        -- No ParseMultipleSources available, show raw text
        local cleanSource = plan.source
        if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
            cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        elseif WarbandNexus.CleanSourceText then
            cleanSource = WarbandNexus:CleanSourceText(cleanSource)
            if type(cleanSource) ~= "string" or (issecretvalue and issecretvalue(cleanSource)) then
                cleanSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
            end
        end
        local sourceText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
        sourceText:SetPoint("TOPLEFT", 0, yOffset)
        sourceText:SetPoint("RIGHT", 0, 0)
        sourceText:SetText(PCol("label") .. NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:") .. "|r " .. PCol("body") .. cleanSource .. "|r")
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(true)
        -- Use timer to ensure text is rendered before measuring height
        local textHeight = sourceText:GetStringHeight() or 20
        if textHeight < 14 then
            C_Timer.After(0, function()
                local measuredHeight = sourceText:GetStringHeight() or 20
                if measuredHeight > textHeight then
                    textHeight = measuredHeight
                end
            end)
        end
        yOffset = yOffset - textHeight - 8
    end
    
    return math.abs(yOffset)
end

--[[
    Expand pet content
]]
function PlanCardFactory:ExpandPetContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Expand toy content
]]
function PlanCardFactory:ExpandToyContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Expand illusion content
]]
function PlanCardFactory:ExpandIllusionContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--[[
    Expand title content
]]
function PlanCardFactory:ExpandTitleContent(expandedContent, plan)
    return self:ExpandMountContent(expandedContent, plan)  -- Same structure for now
end

--- Milestone thresholds for quest-count style slots (Daily Quest Tracker categories).
assert(PlanCardFactory.CreateExpandableContent, "PlanCardFactory_Expanded: load before PlanCardFactory.lua")
