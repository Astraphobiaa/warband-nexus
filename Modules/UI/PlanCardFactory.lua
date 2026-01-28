--[[
    Warband Nexus - Plan Card Factory
    Centralized factory for creating plan cards with unified structure
    Supports all plan types: Achievement, Mount, Pet, Toy, Illusion, Title, Weekly Vault, Daily Quest
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local CreateCard = ns.UI_CreateCard
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
local CardLayoutManager = ns.UI_CardLayoutManager
local FontManager = ns.FontManager  -- Centralized font management
local FormatTextNumbers = ns.UI_FormatTextNumbers

local PlanCardFactory = {}

-- Type colors
local TYPE_COLORS = {
    mount = {0.6, 0.8, 1},
    pet = {0.5, 1, 0.5},
    toy = {1, 0.9, 0.2},
    recipe = {0.8, 0.8, 0.5},
    achievement = {1, 0.8, 0.2},
    transmog = {0.8, 0.5, 1},
    custom = {1, 0.2, 0.2},  -- Will use COLORS.accent in actual usage
    weekly_vault = {1, 0.2, 0.2},  -- Will use COLORS.accent
    illusion = {0.8, 0.5, 1},
    title = {0.6, 0.6, 0.6},
}

-- Type names
local TYPE_NAMES = {
    mount = "Mount",
    pet = "Pet",
    toy = "Toy",
    recipe = "Recipe",
    illusion = "Illusion",
    title = "Title",
    custom = "Custom",
    transmog = "Transmog",
}

-- Type icon atlas mapping
local TYPE_ICONS = {
    mount = "dragon-rostrum",
    pet = "WildBattlePetCapturable",
    toy = "CreationCatalyst-32x32",
    illusion = "UpgradeItem-32x32",
    title = "poi-legendsoftheharanir",
    transmog = "poi-transmogrifier",
}

--[[
    Create base card structure
    @param parent Frame - Parent container
    @param plan table - Plan data
    @param progress table - Plan progress data
    @param layoutManager table - CardLayoutManager instance
    @param col number - Column index (0-based)
    @param cardHeight number - Base card height
    @param cardWidth number - Card width
    @return Frame - Created card frame
]]
function PlanCardFactory:CreateBaseCard(parent, plan, progress, layoutManager, col, cardHeight, cardWidth)
    if not parent or not plan then
        return nil, nil, nil
    end
    
    local card = CreateCard(parent, cardHeight)
    if not card then
        return nil, nil, nil
    end
    
    if cardWidth then
        card:SetWidth(cardWidth)
    end
    card:EnableMouse(true)
    
    -- Add to layout manager
    if layoutManager then
        CardLayoutManager:AddCard(layoutManager, card, col, cardHeight)
    end
    
    -- Store original height for expand/collapse
    card.originalHeight = cardHeight
    card.plan = plan
    card.progress = progress
    
    -- Initialize expanded state
    local cardKey = "plan_" .. plan.id
    card.cardKey = cardKey
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    card.isExpanded = ns.expandedCards[cardKey] or false
    card.expandedContent = nil
    
    -- Apply visuals
    local COLORS = ns.UI_COLORS
    if ApplyVisuals then
        local borderColor = {0.30, 0.90, 0.30, 0.8}  -- Green border for all plans
        ApplyVisuals(card, {0.08, 0.08, 0.10, 1}, borderColor)
    end
    
    -- Apply highlight effect (safe check for Factory)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(card)
    end
    
    -- Icon border frame for positioning reference (used for checkmark and nameText)
    local iconBorder = CreateFrame("Frame", nil, card)
    iconBorder:SetSize(46, 46)
    iconBorder:SetPoint("TOPLEFT", 10, -10)
    iconBorder:EnableMouse(false)
    
    -- Create icon (centered in iconBorder, like old code)
    -- Custom plans use atlas, others use texture
    local iconTexture = plan.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    local iconIsAtlas = plan.iconIsAtlas or false
    if plan.type == "custom" and plan.icon then
        iconIsAtlas = true  -- Custom plans always use atlas
    end
    
    local iconFrameObj = CreateIcon(card, iconTexture, 42, iconIsAtlas, nil, false)
    if iconFrameObj then
        iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
        iconFrameObj:EnableMouse(false)
    end
    
    -- Collected checkmark
    if progress and progress.collected then
        local check = card:CreateTexture(nil, "OVERLAY")
        check:SetSize(18, 18)
        check:SetPoint("TOPRIGHT", iconBorder, "TOPRIGHT", 3, 3)
        check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    end
    
    -- Name text (use larger font for all cards)
    local nameText = FontManager:CreateFontString(card, "title", "OVERLAY")
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
    nameText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
    local nameColor = (progress and progress.collected) and "|cff44ff44" or "|cffffffff"
    
    -- Use FULL plan name (no truncation) - let overflow system handle it
    local displayName = FormatTextNumbers(plan.name or "Unknown")
    
    nameText:SetText(nameColor .. displayName .. "|r")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetNonSpaceWrap(false)
    nameText:SetMaxLines(1)
    nameText:EnableMouse(false)
    card.nameText = nameText
    card.planNameText = nameText  -- Store reference for overflow checking
    
    -- Show icon and card after full setup (prevents flickering)
    if iconFrameObj then
        iconFrameObj:Show()
    end
    card:Show()
    
    return card, iconBorder, nameText
end

--[[
    Create type badge (for non-achievement cards)
    @param card Frame - Card frame
    @param plan table - Plan data
    @param nameText Frame - Name text frame to anchor below
    @return Frame - Type badge text frame
]]
function PlanCardFactory:CreateTypeBadge(card, plan, nameText)
    if not card or not plan then
        return nil
    end
    
    -- Use nameText if provided, otherwise use card.nameText
    local anchorFrame = nameText or card.nameText
    if not anchorFrame then
        -- Fallback: use fixed position
        anchorFrame = card
    end
    
    local typeName = TYPE_NAMES[plan.type] or "Unknown"
    local COLORS = ns.UI_COLORS
    local typeColor = TYPE_COLORS[plan.type] or {0.6, 0.6, 0.6}
    -- Use accent color for custom and weekly_vault
    if plan.type == "custom" or plan.type == "weekly_vault" then
        typeColor = COLORS and COLORS.accent or {1, 0.2, 0.2}
    end
    local typeIconAtlas = TYPE_ICONS[plan.type]
    
    -- Create icon frame if available
    local iconFrame = nil
    if typeIconAtlas then
        iconFrame = CreateFrame("Frame", nil, card)
        iconFrame:SetSize(20, 20)
        if anchorFrame == card then
            iconFrame:SetPoint("TOPLEFT", 10, -60)
        else
            iconFrame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
        end
        iconFrame:EnableMouse(false)
        
        local iconTexture = iconFrame:CreateTexture(nil, "OVERLAY")
        iconTexture:SetAllPoints()
        local iconSuccess = pcall(function()
            iconTexture:SetAtlas(typeIconAtlas, false)
        end)
        if not iconSuccess then
            iconFrame:Hide()
            iconFrame = nil
        else
            iconTexture:SetSnapToPixelGrid(false)
            iconTexture:SetTexelSnappingBias(0)
            iconFrame:Show()  -- Show after setup
        end
    end
    
    -- Create type badge text (ALWAYS create, even if anchor is card)
    local typeBadge = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    if iconFrame then
        typeBadge:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
    else
        if anchorFrame == card then
            typeBadge:SetPoint("TOPLEFT", 10, -60)
        else
            typeBadge:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
        end
    end
    typeBadge:SetPoint("RIGHT", card, "RIGHT", -10, 0)  -- Prevent overflow
    typeBadge:SetJustifyH("LEFT")
    typeBadge:SetWordWrap(false)
    typeBadge:SetMaxLines(1)
    typeBadge:SetText(string.format("|cff%02x%02x%02x%s|r", 
        typeColor[1]*255, typeColor[2]*255, typeColor[3]*255,
        typeName))
    typeBadge:EnableMouse(false)
    
    return typeBadge
end

--[[
    Create achievement points badge
    @param card Frame - Card frame
    @param plan table - Plan data
    @param nameText Frame - Name text frame to anchor below
    @return Frame - Points text frame
]]
function PlanCardFactory:CreateAchievementPointsBadge(card, plan, nameText)
    local typeColor = TYPE_COLORS.achievement
    
    local shieldFrame = CreateFrame("Frame", nil, card)
    shieldFrame:SetSize(20, 20)
    shieldFrame:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -2)
    shieldFrame:EnableMouse(false)
    
    local shieldIcon = shieldFrame:CreateTexture(nil, "OVERLAY")
    shieldIcon:SetAllPoints()
    local shieldSuccess = pcall(function()
        shieldIcon:SetAtlas("UI-Achievement-Shield-NoPoints", false)
    end)
    if not shieldSuccess then
        shieldIcon:Hide()
    end
    shieldIcon:SetSnapToPixelGrid(false)
    shieldIcon:SetTexelSnappingBias(0)
    
    local pointsText = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    pointsText:SetPoint("LEFT", shieldFrame, "RIGHT", 4, 0)
    pointsText:SetPoint("RIGHT", card, "RIGHT", -10, 0)  -- Prevent overflow
    pointsText:SetJustifyH("LEFT")
    pointsText:SetWordWrap(false)
    pointsText:SetMaxLines(1)
    if plan.points then
        pointsText:SetText(string.format("|cff%02x%02x%02x%d Points|r", 
            typeColor[1]*255, typeColor[2]*255, typeColor[3]*255,
            plan.points))
    end
    pointsText:EnableMouse(false)
    
    return pointsText
end

--[[
    Create source information display
    @param card Frame - Card frame
    @param plan table - Plan data
    @param line3Y number - Y offset for line 3
    @return Frame - Last text element created
]]
function PlanCardFactory:CreateSourceInfo(card, plan, line3Y)
    local sources = {}
    
    -- Safely parse source
    if plan.source and type(plan.source) == "string" and plan.source ~= "" then
        if WarbandNexus and WarbandNexus.ParseMultipleSources then
            local success, result = pcall(function()
                return WarbandNexus:ParseMultipleSources(plan.source)
            end)
            if success and result and #result > 0 then
                sources = result
            end
        end
    end
    
    local lastTextElement = nil
    local currentY = line3Y
    
    -- Show sources (collapsed: only first source, expanded: all sources)
    -- Store sources in card for expand functionality
    card._sources = sources
    
    -- CRITICAL: Restore source expansion state from persistent storage (like achievement cards)
    if not card.cardKey then
        card.cardKey = "plan_" .. (plan.id or "unknown")
    end
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    -- Use separate key for source expansion state (non-achievement cards)
    local sourceExpandKey = card.cardKey .. "_source"
    if card._isSourceExpanded == nil then
        -- Restore from persistent storage
        card._isSourceExpanded = ns.expandedCards[sourceExpandKey] or false
    end
    -- CRITICAL: Ensure state is boolean (not nil) before using it
    if type(card._isSourceExpanded) ~= "boolean" then
        card._isSourceExpanded = false
    end
    
    -- Calculate if content exceeds card height
    local originalHeight = card.originalHeight or 130
    local maxContentHeight = originalHeight - 60  -- Reserve space for icon, name, etc.
    local estimatedContentHeight = 0
    
    if #sources > 0 then
        -- Estimate height needed for all sources
        for i, source in ipairs(sources) do
            if source.vendor or source.npc then
                estimatedContentHeight = estimatedContentHeight + 18
            end
            if source.zone then
                estimatedContentHeight = estimatedContentHeight + 18
            end
            if i < #sources then
                estimatedContentHeight = estimatedContentHeight + 4  -- Spacing
            end
        end
        
        -- If content exceeds card height, enable expand/collapse
        local needsExpand = estimatedContentHeight > maxContentHeight
        
        -- CRITICAL: If expand button exists, content definitely exceeds card height
        -- Set _needsExpand flag if expand button exists
        if card._sourceExpandButton then
            card._needsExpand = true
        elseif card._needsExpand == nil then
            -- Store needsExpand flag for later use (set by SetupSourceExpandHandler)
            card._needsExpand = needsExpand
        end
        
        -- In collapsed view, show only first source if content exceeds card height
        -- CRITICAL: Use _needsExpand flag or expand button existence to determine collapse state
        local sourcesToShow
        
        -- Determine if we should collapse (show only first source)
        -- CRITICAL: If expand button exists, we ALWAYS need to respect expansion state
        -- Priority: 1) If expand button exists, ALWAYS use expansion state (most reliable)
        --           2) Otherwise, use _needsExpand flag or calculated needsExpand
        local shouldCollapse = false
        
        -- CRITICAL: Ensure _isSourceExpanded is boolean before checking
        local isExpanded = (card._isSourceExpanded == true)
        
        -- CRITICAL: If expand button exists, content definitely exceeds card height
        -- We MUST respect the expansion state - if collapsed, show only first source
        -- This is the MOST RELIABLE check - if button exists, we know content exceeds
        if card._sourceExpandButton then
            -- Expand button exists = content definitely exceeds card height
            -- Collapse if not expanded (show only first source)
            shouldCollapse = not isExpanded
        elseif card._needsExpand == true then
            -- _needsExpand flag is explicitly set to true (from SetupSourceExpandHandler)
            shouldCollapse = not isExpanded
        elseif needsExpand then
            -- Calculated needsExpand (first time CreateSourceInfo is called, before SetupSourceExpandHandler)
            shouldCollapse = not isExpanded
        end
        
        
        -- CRITICAL: Always respect shouldCollapse if expand button exists
        -- This ensures that after expand->collapse, we show only first source
        -- FORCE collapse if expand button exists and not expanded
        if card._sourceExpandButton and not isExpanded then
            -- Expand button exists and collapsed - MUST show only first source
            sourcesToShow = {sources[1]}
        elseif shouldCollapse and #sources > 0 then
            -- Content exceeds card height and collapsed - show only first source
            sourcesToShow = {sources[1]}
        else
            -- Expanded or content fits - show all sources
            sourcesToShow = sources
        end
        
        
        -- Create source container frame (similar to achievement's expandedContent)
        -- CRITICAL: Destroy and recreate container to ensure clean state
        -- This is more reliable than trying to clear all children
        if card._sourceContainer then
            -- Destroy old container completely
            local oldContainer = card._sourceContainer
            -- Clear all children first
            for i = oldContainer:GetNumChildren(), 1, -1 do
                local child = select(i, oldContainer:GetChildren())
                if child then
                    child:Hide()
                    child:ClearAllPoints()
                    child:SetParent(nil)
                end
            end
            oldContainer:Hide()
            oldContainer:ClearAllPoints()
            oldContainer:SetParent(nil)
            card._sourceContainer = nil
        end
        
        -- Create fresh container
        local sourceContainer = CreateFrame("Frame", nil, card)
        sourceContainer:SetPoint("TOPLEFT", 10, line3Y)
        sourceContainer:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        sourceContainer:SetHeight(1)  -- Will be calculated dynamically
        card._sourceContainer = sourceContainer
        
        
        -- Create source elements inside container
        -- CRITICAL: Ensure container is visible before creating elements
        card._sourceContainer:Show()
        local containerY = 0
        
        
        for i, source in ipairs(sourcesToShow) do
            -- Vendor or Drop
            if source.vendor then
                local vendorText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                vendorText._isSourceElement = true
                vendorText:SetPoint("TOPLEFT", 0, containerY)
                vendorText:SetPoint("RIGHT", 0, 0)
                vendorText:SetText("|A:Class:16:16|a |cff99ccffVendor:|r |cffffffff" .. source.vendor .. "|r")
                vendorText:SetJustifyH("LEFT")
                vendorText:SetWordWrap(true)
                vendorText:SetNonSpaceWrap(false)
                -- Truncate only in collapsed view
                if not card._isSourceExpanded then
                    vendorText:SetMaxLines(1)
                else
                    vendorText:SetMaxLines(2)  -- Max 2 lines even when expanded
                end
                lastTextElement = vendorText
                containerY = containerY - 18
            elseif source.npc then
                local dropText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                dropText._isSourceElement = true
                dropText:SetPoint("TOPLEFT", 0, containerY)
                dropText:SetPoint("RIGHT", 0, 0)
                dropText:SetText("|A:Class:16:16|a |cff99ccffDrop:|r |cffffffff" .. source.npc .. "|r")
                dropText:SetJustifyH("LEFT")
                dropText:SetWordWrap(true)
                dropText:SetNonSpaceWrap(false)
                -- Truncate only in collapsed view
                if not card._isSourceExpanded then
                    dropText:SetMaxLines(1)
                else
                    dropText:SetMaxLines(2)  -- Max 2 lines even when expanded
                end
                lastTextElement = dropText
                containerY = containerY - 18
            end
            
            -- Location (Zone)
            if source.zone then
                local locationText = FontManager:CreateFontString(card._sourceContainer, "body", "OVERLAY")
                locationText._isSourceElement = true
                locationText:SetPoint("TOPLEFT", 0, containerY)
                locationText:SetPoint("RIGHT", 0, 0)
                locationText:SetText("|A:Class:16:16|a |cff99ccffLocation:|r |cffffffff" .. source.zone .. "|r")
                locationText:SetJustifyH("LEFT")
                locationText:SetWordWrap(true)
                locationText:SetNonSpaceWrap(false)
                -- Truncate only in collapsed view
                if not card._isSourceExpanded then
                    locationText:SetMaxLines(1)
                else
                    locationText:SetMaxLines(2)  -- Max 2 lines even when expanded
                end
                lastTextElement = locationText
                containerY = containerY - 18
            end
            
            -- Add spacing between sources
            if i < #sourcesToShow then
                containerY = containerY - 4
            end
        end
        
        -- Update container height and visibility based on expansion state
        if card._sourceContainer then
            card._sourceContainer:SetHeight(math.abs(containerY))
            -- Container is always visible, content (sourcesToShow) changes based on expansion state
            -- This mimics achievement's expandedContent behavior
        end
        
        -- Return container as lastTextElement for anchoring purposes
        if card._sourceContainer and lastTextElement then
            lastTextElement = card._sourceContainer
        end
        
        -- Expand indicator is handled by SetupSourceExpandHandler
        -- Don't create it here, it will be created as a button
    end
    
    -- Fallback: If no structured sources found, show raw source text
    if #sources == 0 and not lastTextElement then
        local rawText = plan.source or ""
        
        -- Clean source text if function exists
        if WarbandNexus and WarbandNexus.CleanSourceText then
            local success, cleaned = pcall(function()
                return WarbandNexus:CleanSourceText(rawText)
            end)
            if success and cleaned then
                rawText = cleaned
            end
        end
        
        -- Normalize whitespace
        rawText = rawText:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        
        -- If still empty or "Unknown", show a meaningful message
        if rawText == "" or rawText == "Unknown" or rawText == "Unknown source" then
            rawText = "Source information not available"
        end
        
        local sourceText = FontManager:CreateFontString(card, "body", "OVERLAY")
        sourceText:SetPoint("TOPLEFT", 10, currentY)
        sourceText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        
        -- Check if text already has a source type prefix
        local sourceType, sourceDetail = rawText:match("^([^:]+:%s*)(.*)$")
        
        if sourceType and sourceDetail and sourceDetail ~= "" then
            -- Text already has source type prefix
            sourceText:SetText("|A:Class:16:16|a |cff99ccff" .. sourceType .. "|r|cffffffff" .. sourceDetail .. "|r")
        else
            -- No source type prefix, add "Source:" label
            sourceText:SetText("|A:Class:16:16|a |cff99ccffSource:|r |cffffffff" .. rawText .. "|r")
        end
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(true)
        sourceText:SetMaxLines(2)
        sourceText:SetNonSpaceWrap(false)
        lastTextElement = sourceText
    end
    
    
    -- ALWAYS return a text element (even if nil, so SetupExpandHandler can work)
    -- If nothing was created, create a placeholder
    if not lastTextElement then
        local placeholderText = FontManager:CreateFontString(card, "body", "OVERLAY")
        placeholderText:SetPoint("TOPLEFT", 10, line3Y)
        placeholderText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        placeholderText:SetText("|A:Class:16:16|a |cff99ccffSource:|r |cffffffffUnknown source|r")
        placeholderText:SetJustifyH("LEFT")
        placeholderText:SetWordWrap(true)
        placeholderText:SetMaxLines(2)
        placeholderText:SetNonSpaceWrap(false)
        lastTextElement = placeholderText
    end
    
    return lastTextElement
end

--[[
    Create expandable content frame
    @param card Frame - Card frame
    @param anchorFrame Frame - Frame to anchor below
    @return Frame - Expanded content frame
]]
function PlanCardFactory:CreateExpandableContent(card, anchorFrame)
    local expandedContent = CreateFrame("Frame", nil, card)
    -- Anchor to BOTTOM of anchorFrame with proper spacing (negative Y = down)
    expandedContent:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -8)
    expandedContent:SetPoint("RIGHT", card, "RIGHT", -30, 0)
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
        card._expandButton:Hide()
        card._expandButton:SetParent(nil)
        card._expandButton = nil
    end
    
    -- Create expand button (20x20, same size as delete button)
    local expandButton = CreateFrame("Button", nil, card)
    expandButton:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 10)
    expandButton:SetSize(20, 20)
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
    -- Store original click handler if exists
    local originalOnMouseUp = card:GetScript("OnMouseUp")
    
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
    Main factory method - creates a plan card based on type
    @param parent Frame - Parent container
    @param plan table - Plan data
    @param progress table - Plan progress data
    @param layoutManager table - CardLayoutManager instance
    @param col number - Column index (0-based)
    @param cardHeight number - Base card height
    @param cardWidth number - Card width (optional)
    @return Frame - Created card frame
]]
function PlanCardFactory:CreateCard(parent, plan, progress, layoutManager, col, cardHeight, cardWidth)
    if not plan or not plan.type then
        return nil
    end
    
    -- Ensure progress is a table (not nil)
    if not progress then
        progress = {}
    end
    
    -- Create base card
    local card, iconBorder, nameText = self:CreateBaseCard(parent, plan, progress, layoutManager, col, cardHeight, cardWidth)
    
    if not card then
        return nil
    end
    
    -- Create type-specific content
    if plan.type == "achievement" then
        local success, err = pcall(function()
            self:CreateAchievementCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create achievement card: " .. tostring(err))
        end
    elseif plan.type == "mount" then
        local success, err = pcall(function()
            self:CreateMountCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create mount card: " .. tostring(err))
        end
    elseif plan.type == "pet" then
        local success, err = pcall(function()
            self:CreatePetCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create pet card: " .. tostring(err))
        end
    elseif plan.type == "toy" then
        local success, err = pcall(function()
            self:CreateToyCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create toy card: " .. tostring(err))
        end
    elseif plan.type == "illusion" then
        local success, err = pcall(function()
            self:CreateIllusionCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create illusion card: " .. tostring(err))
        end
    elseif plan.type == "title" then
        local success, err = pcall(function()
            self:CreateTitleCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create title card: " .. tostring(err))
        end
    elseif plan.type == "weekly_vault" then
        local success, err = pcall(function()
            self:CreateWeeklyVaultCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create weekly vault card: " .. tostring(err))
        end
    elseif plan.type == "daily_quests" then
        -- Daily quests handled separately in PlansUI
        -- Just return base card
    else
        -- Default card for other types
        local success, err = pcall(function()
            self:CreateDefaultCard(card, plan, progress, nameText)
        end)
        if not success then
            WarbandNexus:Print("|cffff0000[PlanCardFactory Error]|r Failed to create default card: " .. tostring(err))
        end
    end
    
    return card
end

--[[
    Create achievement card with expand functionality
]]
function PlanCardFactory:CreateAchievementCard(card, plan, progress, nameText)
    -- Create points badge
    if plan.points then
        self:CreateAchievementPointsBadge(card, plan, nameText)
    end
    
    -- Parse source for achievement-specific display
    local rawText = plan.source or ""
    if WarbandNexus.CleanSourceText then
        rawText = WarbandNexus:CleanSourceText(rawText)
    end
    
    local description, progressText = rawText:match("^(.-)%s*(Progress:%s*.+)$")
    
    -- Fallback: If description not found in source, try to get it from achievement API
    if (not description or description == "") and plan.achievementID then
        local success, achievementInfo = pcall(GetAchievementInfo, plan.achievementID)
        if success and achievementInfo then
            local _, _, _, _, _, _, _, achievementDescription = GetAchievementInfo(plan.achievementID)
            if achievementDescription and achievementDescription ~= "" then
                description = achievementDescription
            end
        end
    end
    
    -- Additional fallback: Check if plan has description field
    if (not description or description == "") and plan.description then
        description = plan.description
    end
    
    local currentY = -60
    local lastTextElement = nil
    
    -- Information (show truncated version when collapsed, full text when expanded)
    if description and description ~= "" then
        -- Clean up description (remove extra whitespace, newlines)
        description = description:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        
        -- Store full description for expand
        card.fullDescription = description
        
        -- Show truncated version (max 2 lines, ~80 chars to prevent overflow)
        -- Calculate based on card width to ensure it fits
        local cardWidth = card:GetWidth() or 200
        local availableWidth = cardWidth - 40  -- 10px left + 30px right margin
        local charsPerLine = math.floor(availableWidth / 6)  -- ~6 pixels per char
        local maxChars = charsPerLine * 2  -- 2 lines max
        maxChars = math.min(maxChars, 80)  -- Cap at 80 chars for safety
        
        local truncatedDescription = description
        if #description > maxChars then
            truncatedDescription = description:sub(1, maxChars - 3) .. "..."
        end
        
        local infoText = FontManager:CreateFontString(card, "body", "OVERLAY")
        infoText:SetPoint("TOPLEFT", 10, currentY)
        infoText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        -- Show truncated version when collapsed, full when expanded
        local displayText = (card.isExpanded and description) or truncatedDescription
        infoText:SetText("|cff88ff88Information:|r |cffffffff" .. displayText .. "|r")
        infoText:SetJustifyH("LEFT")
        infoText:SetWordWrap(true)
        -- Truncate only in collapsed view
        if not card.isExpanded then
            infoText:SetMaxLines(2)
        else
            infoText:SetMaxLines(0)  -- No limit when expanded
        end
        infoText:SetNonSpaceWrap(false)
        -- Force text to fit within bounds (prevent overflow)
        infoText:SetWidth(card:GetWidth() - 40)  -- 10px left + 30px right margin
        card.infoText = infoText  -- Store for reference
        lastTextElement = infoText
    end
    
    -- Progress (calculate actual progress from achievement criteria)
    local progressLabel = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    if lastTextElement then
        progressLabel:SetPoint("TOPLEFT", lastTextElement, "BOTTOMLEFT", 0, -12)
    else
        progressLabel:SetPoint("TOPLEFT", 10, currentY)
    end
    progressLabel:SetPoint("RIGHT", card, "RIGHT", -30, 0)
    progressLabel:SetJustifyH("LEFT")
    progressLabel:SetWordWrap(false)
    card.progressLabel = progressLabel  -- Store for later update
    card.planAchievementID = plan.achievementID  -- Store for progress calculation
    
    -- Calculate progress on initial creation
    local achievementID = plan.achievementID
    if achievementID then
        local numCriteria = GetAchievementNumCriteria(achievementID)
        if numCriteria and numCriteria > 0 then
            local completedCount = 0
            local totalQuantity = 0
            local totalReqQuantity = 0
            local hasProgressBased = false
            
            for criteriaIndex = 1, numCriteria do
                local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
                if criteriaName and criteriaName ~= "" then
                    if completed then
                        completedCount = completedCount + 1
                    end
                    if quantity and reqQuantity and reqQuantity > 0 then
                        totalQuantity = totalQuantity + (quantity or 0)
                        totalReqQuantity = totalReqQuantity + (reqQuantity or 0)
                        hasProgressBased = true
                    end
                end
            end
            
            local progressColor = (completedCount == numCriteria) and "|cff00ff00" or "|cffffffff"
            if hasProgressBased and totalReqQuantity > 0 then
                -- Progress-based: "You are X/Y on the progress"
                progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou are %d/%d on the progress|r", progressColor, totalQuantity, totalReqQuantity))
            else
                -- Criteria-based: "You completed X of Y total requirements"
                progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou completed %d of %d total requirements|r", progressColor, completedCount, numCriteria))
            end
        else
            progressLabel:SetText("|cffffcc00Progress:|r")
        end
    else
        progressLabel:SetText("|cffffcc00Progress:|r")
    end
    
    lastTextElement = progressLabel
    
    -- Reward
    if plan.rewardText and plan.rewardText ~= "" then
        local rewardText = FontManager:CreateFontString(card, "small", "OVERLAY")
        if lastTextElement then
            rewardText:SetPoint("TOPLEFT", lastTextElement, "BOTTOMLEFT", 0, -12)
        else
            rewardText:SetPoint("TOPLEFT", 10, currentY)
        end
        rewardText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        rewardText:SetText("|cff88ff88Reward:|r |cffffffff" .. plan.rewardText .. "|r")
        rewardText:SetJustifyH("LEFT")
        rewardText:SetWordWrap(true)
        rewardText:SetMaxLines(2)
        rewardText:SetNonSpaceWrap(false)
        lastTextElement = rewardText
    end
    
    -- Requirements header
    local requirementsHeader = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
    if lastTextElement then
        requirementsHeader:SetPoint("TOPLEFT", lastTextElement, "BOTTOMLEFT", 0, -5)  -- Reduced spacing from -20 to -5
    else
        requirementsHeader:SetPoint("TOPLEFT", 10, currentY - 5)
    end
    requirementsHeader:SetPoint("RIGHT", card, "RIGHT", -30, 0)
    requirementsHeader:SetText("|cffffcc00Requirements:|r ...")
    requirementsHeader:SetJustifyH("LEFT")
    requirementsHeader:SetTextColor(1, 1, 1)
    card.requirementsHeader = requirementsHeader
    
    -- Create expandable content
    local expandedContent = self:CreateExpandableContent(card, requirementsHeader)
    
    -- Set up expand/collapse handler
    self:SetupAchievementExpandHandler(card, plan)
    
    -- CRITICAL: Restore expanded state if card was previously expanded
    -- This ensures UI matches the persisted state after window resize or layout recalculation
    if card.isExpanded then
        local achievementID = plan.achievementID
        if achievementID then
            local numCriteria = GetAchievementNumCriteria(achievementID)
            if numCriteria and numCriteria > 0 then
                -- ExpandAchievementContent already handles: expandedContent:Show(), requirementsHeader text, and card height
                PlanCardFactory:ExpandAchievementContent(card, achievementID)
            else
                -- ExpandAchievementEmpty already handles: expandedContent:Show(), requirementsHeader text, and card height
                PlanCardFactory:ExpandAchievementEmpty(card)
            end
            
            -- Update Information text to full version (not handled by ExpandAchievementContent)
            if card.infoText and card.fullDescription then
                card.infoText:SetText("|cff88ff88Information:|r |cffffffff" .. card.fullDescription .. "|r")
                card.infoText:SetMaxLines(0)  -- No limit when expanded
            end
            
            -- Update expand button icon (not handled by ExpandAchievementContent)
            if card._expandButton then
                self:UpdateExpandButtonIcon(card, true)
            end
        end
    else
        -- Ensure collapsed state is correct
        if card.expandedContent then
            card.expandedContent:Hide()
        end
        if card.requirementsHeader then
            card.requirementsHeader:SetText("|cffffcc00Requirements:|r ...")
        end
        if card._expandButton then
            self:UpdateExpandButtonIcon(card, false)
        end
    end
end

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
            if cardFrame.originalHeight then
                cardFrame:SetHeight(cardFrame.originalHeight)
                if CardLayoutManager and cardFrame._layoutManager then
                    CardLayoutManager:UpdateCardHeight(cardFrame, cardFrame.originalHeight)
                end
            end
            if cardFrame.requirementsHeader then
                cardFrame.requirementsHeader:SetText("|cffffcc00Requirements:|r ...")
            end
            
            -- Update Information text to truncated version
            if cardFrame.infoText and cardFrame.fullDescription then
                local cardWidth = cardFrame:GetWidth() or 200
                local availableWidth = cardWidth - 40
                local charsPerLine = math.floor(availableWidth / 6)
                local maxChars = math.min(charsPerLine * 2, 80)
                local truncatedDescription = cardFrame.fullDescription
                if #truncatedDescription > maxChars then
                    truncatedDescription = truncatedDescription:sub(1, maxChars - 3) .. "..."
                end
                cardFrame.infoText:SetText("|cff88ff88Information:|r |cffffffff" .. truncatedDescription .. "|r")
                cardFrame.infoText:SetMaxLines(2)
            end
            
            -- Recalculate progress when collapsed to show same format as expanded
            if achievementID and cardFrame.progressLabel then
                local numCriteria = GetAchievementNumCriteria(achievementID)
                if numCriteria and numCriteria > 0 then
                    local completedCount = 0
                    local totalQuantity = 0
                    local totalReqQuantity = 0
                    local hasProgressBased = false
                    
                    for criteriaIndex = 1, numCriteria do
                        local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
                        if criteriaName and criteriaName ~= "" then
                            if completed then
                                completedCount = completedCount + 1
                            end
                            if quantity and reqQuantity and reqQuantity > 0 then
                                totalQuantity = totalQuantity + (quantity or 0)
                                totalReqQuantity = totalReqQuantity + (reqQuantity or 0)
                                hasProgressBased = true
                            end
                        end
                    end
                    
                    local progressColor = (completedCount == numCriteria) and "|cff00ff00" or "|cffffffff"
                    if hasProgressBased and totalReqQuantity > 0 then
                        -- Progress-based: "You are X/Y on the progress"
                        cardFrame.progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou are %d/%d on the progress|r", progressColor, totalQuantity, totalReqQuantity))
                    else
                        -- Criteria-based: "You completed X of Y total requirements"
                        cardFrame.progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou completed %d of %d total requirements|r", progressColor, completedCount, numCriteria))
                    end
                else
                    cardFrame.progressLabel:SetText("|cffffcc00Progress:|r")
                end
            elseif cardFrame.progressLabel then
                cardFrame.progressLabel:SetText("|cffffcc00Progress:|r")
            end
            
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
            else
                PlanCardFactory:ExpandAchievementEmpty(cardFrame)
            end
            
            -- Ensure expandedContent is shown after expansion
            if cardFrame.expandedContent then
                cardFrame.expandedContent:Show()
            end
            
            -- Update requirements header text
            if cardFrame.requirementsHeader then
                cardFrame.requirementsHeader:SetText("|cffffcc00Requirements:|r")
            end
            
            -- Update Information text to full version
            if cardFrame.infoText and cardFrame.fullDescription then
                cardFrame.infoText:SetText("|cff88ff88Information:|r |cffffffff" .. cardFrame.fullDescription .. "|r")
                cardFrame.infoText:SetMaxLines(0)  -- No limit when expanded
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
    
    -- CRITICAL: Re-anchor expandedContent to requirementsHeader to ensure correct positioning
    local anchorFrame = card.requirementsHeader
    if anchorFrame then
        -- Clear all points and re-anchor to ensure correct position
        expandedContent:ClearAllPoints()
        expandedContent:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -8)
        expandedContent:SetPoint("RIGHT", card, "RIGHT", -30, 0)
    end
    
    -- Clear previous content
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            child:SetParent(nil)
        end
    end
    
    local completedCount = 0
    local criteriaDetails = {}
    local totalQuantity = 0
    local totalReqQuantity = 0
    local hasProgressBased = false
    
    for criteriaIndex = 1, GetAchievementNumCriteria(achievementID) do
        local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
        if criteriaName and criteriaName ~= "" then
            if completed then
                completedCount = completedCount + 1
            end
            
            local statusIcon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t |cff00ff00" or "|cff888888•|r"
            local textColor = completed and "|cff88ff88" or "|cffdddddd"
            local progressText = ""
            
            if quantity and reqQuantity and reqQuantity > 0 then
                progressText = string.format(" |cff888888(%d/%d)|r", quantity, reqQuantity)
                totalQuantity = totalQuantity + (quantity or 0)
                totalReqQuantity = totalReqQuantity + (reqQuantity or 0)
                hasProgressBased = true
            end
            
            table.insert(criteriaDetails, statusIcon .. " " .. textColor .. criteriaName .. "|r" .. progressText)
        end
    end
    
    -- Update progress label with appropriate text based on achievement type
    local numCriteria = #criteriaDetails
    local progressColor = (completedCount == numCriteria) and "|cff00ff00" or "|cffffffff"
    
    if card.progressLabel then
        if hasProgressBased and totalReqQuantity > 0 then
            -- Progress-based: "You are X/Y on the progress"
            card.progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou are %d/%d on the progress|r", progressColor, totalQuantity, totalReqQuantity))
        else
            -- Criteria-based: "You completed X of Y total requirements"
            card.progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou completed %d of %d total requirements|r", progressColor, completedCount, numCriteria))
        end
    end
    
    -- Information text is now updated in card.infoText directly (not in expandedContent)
    -- This ensures it's shown/hidden correctly on expand/collapse
    local contentY = 0
    
    -- Criteria list in 3 columns (start from contentY position)
    local columnsPerRow = 3
    local availableWidth = expandedContent:GetWidth()
    local columnWidth = availableWidth / columnsPerRow
    local criteriaY = contentY - 8  -- Start below information text (if shown) or at top
    local currentRow = {}
    
    for i, criteriaLine in ipairs(criteriaDetails) do
        table.insert(currentRow, criteriaLine)
        
        if #currentRow == columnsPerRow or i == #criteriaDetails then
            for colIndex, criteriaText in ipairs(currentRow) do
                local xOffset = (colIndex - 1) * columnWidth
                local colLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                colLabel:SetPoint("TOPLEFT", xOffset, criteriaY)
                colLabel:SetWidth(columnWidth - 4)
                colLabel:SetJustifyH("LEFT")
                colLabel:SetText(criteriaText)
                colLabel:SetWordWrap(true)  -- Enable word wrap to prevent truncation
                colLabel:SetMaxLines(3)  -- Allow up to 3 lines per requirement
                colLabel:SetNonSpaceWrap(false)
            end
            -- Calculate actual height of this row (may be multi-line due to word wrap)
            local maxRowHeight = 16  -- Minimum height for single line
            for colIndex, criteriaText in ipairs(currentRow) do
                -- Estimate height based on text length (rough calculation)
                local textLength = #criteriaText
                local estimatedLines = math.ceil(textLength / (columnWidth / 6))  -- ~6 pixels per char
                estimatedLines = math.min(estimatedLines, 3)  -- Cap at 3 lines
                local lineHeight = estimatedLines * 14  -- 14px per line
                if lineHeight > maxRowHeight then
                    maxRowHeight = lineHeight
                end
            end
            criteriaY = criteriaY - maxRowHeight - 2  -- Add 2px spacing between rows
            currentRow = {}
        end
    end
    
    -- Calculate height (include information text if shown)
    local numRows = math.ceil(#criteriaDetails / columnsPerRow)
    local infoHeight = 0
    if card.fullDescription and card.fullDescription ~= "" then
        local truncatedDescription = card.infoText and card.infoText:GetText() or ""
        if truncatedDescription:find("%.%.%.") or #truncatedDescription < #card.fullDescription then
            infoHeight = math.ceil(#card.fullDescription / 60) * 14 + 16  -- Approximate height
        end
    end
    -- Calculate requirements height more accurately (accounting for multi-line text)
    local requirementsHeight = math.abs(criteriaY) + 8
    local expandedHeight = card.originalHeight + infoHeight + requirementsHeight
    card:SetHeight(expandedHeight)
    expandedContent:Show()
    card.requirementsHeader:SetText("|cffffcc00Requirements:|r")
    
    -- Update layout
    if CardLayoutManager and card._layoutManager then
        CardLayoutManager:UpdateCardHeight(card, expandedHeight)
    end
end

--[[
    Expand achievement with no criteria
]]
function PlanCardFactory:ExpandAchievementEmpty(card)
    local expandedContent = card.expandedContent
    if not expandedContent then return end
    
    -- Clear previous content
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            child:SetParent(nil)
        end
    end
    
    local noCriteriaText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
    noCriteriaText:SetPoint("TOPLEFT", 0, 0)
    noCriteriaText:SetPoint("RIGHT", 0, 0)
    noCriteriaText:SetText("|cff888888No requirements (instant completion)|r")
    noCriteriaText:SetJustifyH("LEFT")
    
    local expandedHeight = card.originalHeight + 30
    card:SetHeight(expandedHeight)
    expandedContent:Show()
    card.requirementsHeader:SetText("|cffffcc00Requirements:|r")
    
    -- Update layout
    if CardLayoutManager and card._layoutManager then
        CardLayoutManager:UpdateCardHeight(card, expandedHeight)
    end
end

--[[
    Create mount card
]]
function PlanCardFactory:CreateMountCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    -- Create type badge
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    -- Create source info (always creates something, even if source is missing)
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    
    -- Setup expand handler for multiple sources (without Details label)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "mount", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "mount", anchorFrame)
    end
    
    -- CRITICAL: Restore source expansion state if card was previously expanded
    -- This ensures UI matches the persisted state after window resize or layout recalculation
    if card._isSourceExpanded and card._sourceExpandButton then
        -- Recreate source info with expanded state
        self:CreateSourceInfo(card, plan, -60)
        
        -- Update expand button icon
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
        
        -- Calculate expanded height
        if card.originalHeight and card._sources then
            local contentHeight = 0
            for i, source in ipairs(card._sources) do
                if source.vendor or source.npc then
                    contentHeight = contentHeight + 18
                end
                if source.zone then
                    contentHeight = contentHeight + 18
                end
                if i < #card._sources then
                    contentHeight = contentHeight + 4
                end
            end
            local expandedHeight = card.originalHeight + (contentHeight - (card.originalHeight - 60))
            card:SetHeight(expandedHeight)
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    end
end

--[[
    Create pet card
]]
function PlanCardFactory:CreatePetCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "pet", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "pet", anchorFrame)
    end
    
    -- CRITICAL: Restore source expansion state if card was previously expanded
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
        if card.originalHeight and card._sources then
            local contentHeight = 0
            for i, source in ipairs(card._sources) do
                if source.vendor or source.npc then contentHeight = contentHeight + 18 end
                if source.zone then contentHeight = contentHeight + 18 end
                if i < #card._sources then contentHeight = contentHeight + 4 end
            end
            local expandedHeight = card.originalHeight + (contentHeight - (card.originalHeight - 60))
            card:SetHeight(expandedHeight)
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    end
end

--[[
    Create toy card
]]
function PlanCardFactory:CreateToyCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "toy", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "toy", anchorFrame)
    end
    
    -- CRITICAL: Restore source expansion state if card was previously expanded
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
        if card.originalHeight and card._sources then
            local contentHeight = 0
            for i, source in ipairs(card._sources) do
                if source.vendor or source.npc then contentHeight = contentHeight + 18 end
                if source.zone then contentHeight = contentHeight + 18 end
                if i < #card._sources then contentHeight = contentHeight + 4 end
            end
            local expandedHeight = card.originalHeight + (contentHeight - (card.originalHeight - 60))
            card:SetHeight(expandedHeight)
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    end
end

--[[
    Create illusion card
]]
function PlanCardFactory:CreateIllusionCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "illusion", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "illusion", anchorFrame)
    end
    
    -- CRITICAL: Restore source expansion state if card was previously expanded
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
        if card.originalHeight and card._sources then
            local contentHeight = 0
            for i, source in ipairs(card._sources) do
                if source.vendor or source.npc then contentHeight = contentHeight + 18 end
                if source.zone then contentHeight = contentHeight + 18 end
                if i < #card._sources then contentHeight = contentHeight + 4 end
            end
            local expandedHeight = card.originalHeight + (contentHeight - (card.originalHeight - 60))
            card:SetHeight(expandedHeight)
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    end
end

--[[
    Create title card
]]
function PlanCardFactory:CreateTitleCard(card, plan, progress, nameText)
    if not card or not plan then
        return
    end
    
    if nameText then
        self:CreateTypeBadge(card, plan, nameText)
    end
    
    local lastTextElement = self:CreateSourceInfo(card, plan, -60)
    if lastTextElement then
        self:SetupSourceExpandHandler(card, plan, "title", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupSourceExpandHandler(card, plan, "title", anchorFrame)
    end
    
    -- CRITICAL: Restore source expansion state if card was previously expanded
    if card._isSourceExpanded and card._sourceExpandButton then
        self:CreateSourceInfo(card, plan, -60)
        if card._sourceExpandButton then
            self:UpdateExpandButtonIcon(card, true)
        end
        if card.originalHeight and card._sources then
            local contentHeight = 0
            for i, source in ipairs(card._sources) do
                if source.vendor or source.npc then contentHeight = contentHeight + 18 end
                if source.zone then contentHeight = contentHeight + 18 end
                if i < #card._sources then contentHeight = contentHeight + 4 end
            end
            local expandedHeight = card.originalHeight + (contentHeight - (card.originalHeight - 60))
            card:SetHeight(expandedHeight)
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    end
end

--[[
    Create default card for other types
]]
function PlanCardFactory:CreateDefaultCard(card, plan, progress, nameText)
    -- Custom cards: Only show type badge and description (no source info)
    if plan.type == "custom" then
        if nameText then
            self:CreateTypeBadge(card, plan, nameText)
        end
        
        -- Show description text (user-entered text) below type badge with expand/collapse
        -- Use same container approach as non-achievement cards
        self:CreateCustomDescription(card, plan, -60)
        
        -- CRITICAL: Restore expanded state if card was previously expanded
        if card._isDescriptionExpanded and card.descriptionText and card.fullDescription then
            -- Update description text to full version
            card.descriptionText:SetText("|cff88ff88Description:|r |cffffffff" .. card.fullDescription .. "|r")
            card.descriptionText:SetWordWrap(true)  -- Allow wrapping
            card.descriptionText:SetMaxLines(0)  -- No limit when expanded
            
            -- Update expand button icon
            if card._expandButton then
                self:UpdateExpandButtonIcon(card, true)
            end
            
            -- Calculate and set expanded height
            local originalHeight = card.originalHeight or 130
            local textHeight = card.descriptionText:GetStringHeight()
            
            -- If height is too small (text not rendered yet), use estimation
            if textHeight < 14 then
                local cardWidth = card:GetWidth() or 200
                local availableWidth = cardWidth - 40
                local charsPerLine = math.floor(availableWidth / 6)
                local estimatedLines = math.max(1, math.ceil(string.len(card.fullDescription) / charsPerLine))
                textHeight = estimatedLines * 14
            end
            
            local collapsedHeight = 14  -- Single line height (14px)
            local expandedHeight = originalHeight + (textHeight - collapsedHeight)
            card:SetHeight(expandedHeight)
            
            -- Update layout
            if CardLayoutManager and card._layoutManager then
                CardLayoutManager:UpdateCardHeight(card, expandedHeight)
            end
        end
    else
        -- Other default cards: show type badge and source info
        self:CreateTypeBadge(card, plan, nameText)
        self:CreateSourceInfo(card, plan, -60)
    end
end

--[[
    Create custom description with expand/collapse (EXACTLY like achievement Information field)
    @param card Frame - Card frame
    @param plan table - Plan data
    @param descY number - Y offset for description
]]
function PlanCardFactory:CreateCustomDescription(card, plan, descY)
    local description = plan.source or plan.description or plan.note or ""
    if not description or description == "" or description == "Custom plan" then
        return
    end
    
    -- Store full description
    card.fullDescription = description
    
    -- Initialize expand state (restore from persistent storage)
    if not card.cardKey then
        card.cardKey = "plan_" .. (plan.id or "unknown")
    end
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    local descExpandKey = card.cardKey .. "_description"
    if card._isDescriptionExpanded == nil then
        card._isDescriptionExpanded = ns.expandedCards[descExpandKey] or false
    end
    if type(card._isDescriptionExpanded) ~= "boolean" then
        card._isDescriptionExpanded = false
    end
    
    -- Destroy old description elements if exist
    if card.descriptionText then
        card.descriptionText:Hide()
        card.descriptionText:SetParent(nil)
        card.descriptionText = nil
    end
    if card.descriptionTextRest then
        card.descriptionTextRest:Hide()
        card.descriptionTextRest:SetParent(nil)
        card.descriptionTextRest = nil
    end
    if card.descriptionLabel then
        card.descriptionLabel:Hide()
        card.descriptionLabel:SetParent(nil)
        card.descriptionLabel = nil
    end
    
    -- Calculate truncated description
    local cardWidth = card:GetWidth() or 200
    local availableWidth = cardWidth - 110  -- 10px left + label width (~85px) + 15px spacing
    local charsPerLine = math.floor(availableWidth / 6)  -- ~6 pixels per char
    local maxChars = charsPerLine * 2  -- 2 lines max for collapsed view
    maxChars = math.min(maxChars, 80)  -- Cap at 80 chars for safety
    
    local truncatedDescription = description
    if #description > maxChars then
        truncatedDescription = description:sub(1, maxChars - 3) .. "..."
    end
    
    -- Check if description needs expand
    local needsExpand = string.len(description) > maxChars
    card._needsDescriptionExpand = needsExpand
    
    -- Create label
    local descLabel = FontManager:CreateFontString(card, "body", "OVERLAY")
    descLabel:SetPoint("TOPLEFT", 10, descY)
    descLabel:SetText("|cff88ff88Description:|r")
    card.descriptionLabel = descLabel
    
    local labelWidth = descLabel:GetStringWidth()
    
    if not card._isDescriptionExpanded then
        -- Collapsed: First line text only
        local descText = FontManager:CreateFontString(card, "body", "OVERLAY")
        descText:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
        descText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        descText:SetJustifyH("LEFT")
        descText:SetWordWrap(false)
        descText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        descText:SetMaxLines(1)
        descText:SetText(truncatedDescription)
        card.descriptionText = descText
    else
        -- Expanded: Manual text breaking for multi-line
        -- Calculate how many chars fit in first line (after label)
        local cardWidth = card:GetWidth() or 200
        local firstLineWidth = cardWidth - (10 + labelWidth + 5 + 30)  -- left + label + spacing + right
        local subsequentLineWidth = cardWidth - 40  -- 10px left + 30px right
        
        local charsPerFirstLine = math.floor(firstLineWidth / 6)
        local charsPerSubsequentLine = math.floor(subsequentLineWidth / 6)
        
        -- Store for potential use
        card._charsPerFirstLine = charsPerFirstLine
        card._charsPerSubsequentLine = charsPerSubsequentLine
        
        -- Break text into lines
        local firstLineText = description:sub(1, math.min(charsPerFirstLine, #description))
        local remainingText = #description > charsPerFirstLine and description:sub(charsPerFirstLine + 1) or ""
        
        -- First line (after label)
        local firstLineFS = FontManager:CreateFontString(card, "body", "OVERLAY")
        firstLineFS:SetPoint("LEFT", descLabel, "RIGHT", 5, 0)
        firstLineFS:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        firstLineFS:SetJustifyH("LEFT")
        firstLineFS:SetWordWrap(false)
        firstLineFS:SetNonSpaceWrap(false)  -- Prevent long word overflow
        firstLineFS:SetMaxLines(1)
        firstLineFS:SetText(firstLineText)
        card.descriptionText = firstLineFS
        
        -- Subsequent lines (below label start)
        if #remainingText > 0 then
            local restText = FontManager:CreateFontString(card, "body", "OVERLAY")
            restText:SetPoint("TOPLEFT", 10, descY - 14)
            restText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
            restText:SetJustifyH("LEFT")
            restText:SetJustifyV("TOP")
            restText:SetWordWrap(true)
            restText:SetNonSpaceWrap(false)  -- Changed: Don't break long words awkwardly
            restText:SetMaxLines(5)  -- Max 5 lines for expanded description
            restText:SetText(remainingText)
            card.descriptionTextRest = restText
        end
    end
    
    -- Setup expand handler if needed
    if needsExpand and not card._descriptionExpandHandlerSetup then
        card._descriptionExpandHandlerSetup = true
        self:SetupDescriptionExpandHandler(card, plan)
    end
end

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
            if cardFrame.descriptionText then
                cardFrame.descriptionText:Hide()
                cardFrame.descriptionText:SetParent(nil)
                cardFrame.descriptionText = nil
            end
            if cardFrame.descriptionTextRest then
                cardFrame.descriptionTextRest:Hide()
                cardFrame.descriptionTextRest:SetParent(nil)
                cardFrame.descriptionTextRest = nil
            end
            if cardFrame.descriptionLabel then
                cardFrame.descriptionLabel:Hide()
                cardFrame.descriptionLabel:SetParent(nil)
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
            descLabel:SetText("|cff88ff88Description:|r")
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
                descText:SetText(truncatedDescription)
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
                -- Wait for text to render, then calculate accurate height
                local updateFrame = CreateFrame("Frame")
                local updateCount = 0
                updateFrame:SetScript("OnUpdate", function(self, elapsed)
                    updateCount = updateCount + 1
                    if updateCount >= 2 then
                        -- Get height of rest text (multi-line part)
                        local restTextHeight = 0
                        if cardFrame.descriptionTextRest then
                            restTextHeight = cardFrame.descriptionTextRest:GetStringHeight()
                        end
                        
                        -- Expanded: collapsed(14) replaced by: label(14) + firstLine(14) + restText
                        -- Height change = 14 + restText
                        local collapsedHeight = 14
                        local labelAndFirstLineHeight = 14  -- Label and first line share same height
                        local calculatedHeight = originalHeight - collapsedHeight + labelAndFirstLineHeight + restTextHeight
                        
                        cardFrame:SetHeight(calculatedHeight)
                        if CardLayoutManager and cardFrame._layoutManager then
                            CardLayoutManager:UpdateCardHeight(cardFrame, calculatedHeight)
                        end
                        
                        self:SetScript("OnUpdate", nil)
                        updateFrame = nil
                    end
                end)
                
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
    -- Check if expand is needed (content exceeds card height or multiple sources)
    if not card._sources or #card._sources == 0 then
        return
    end
    
    local originalHeight = card.originalHeight or 130
    local maxContentHeight = originalHeight - 60
    local estimatedContentHeight = 0
    
    -- Estimate height needed for all sources
    for i, source in ipairs(card._sources) do
        if source.vendor or source.npc then
            estimatedContentHeight = estimatedContentHeight + 18
        end
        if source.zone then
            estimatedContentHeight = estimatedContentHeight + 18
        end
        if i < #card._sources then
            estimatedContentHeight = estimatedContentHeight + 4
        end
    end
    
    -- Only show expand button if content exceeds card height
    local needsExpand = estimatedContentHeight > maxContentHeight
    if not needsExpand then
        return
    end
    
    -- Store needsExpand flag in card for CreateSourceInfo to use
    card._needsExpand = true
    
    -- Create unified expand button (20x20, same size as delete button)
    local expandButton = self:CreateExpandButton(card, card._isSourceExpanded or false)
    
    local factory = self
    -- Setup expand callback (mimicking achievement system exactly)
    local expandCallback = function(cardFrame)
        -- Toggle source expansion state FIRST
        local wasExpanded = cardFrame._isSourceExpanded or false
        cardFrame._isSourceExpanded = not wasExpanded
        
        -- CRITICAL: Save state to persistent storage (like achievement cards)
        if cardFrame.cardKey then
            local sourceExpandKey = cardFrame.cardKey .. "_source"
            if not ns.expandedCards then
                ns.expandedCards = {}
            end
            ns.expandedCards[sourceExpandKey] = cardFrame._isSourceExpanded
        end
        
        -- CRITICAL: Ensure _needsExpand is set if expand button exists
        if cardFrame._sourceExpandButton then
            cardFrame._needsExpand = true
        end
        
        -- CRITICAL: Ensure state is boolean, not nil
        if cardFrame._isSourceExpanded == nil then
            cardFrame._isSourceExpanded = false
        end
        
        if cardFrame._isSourceExpanded then
            -- Expand: Show all sources (like achievement shows expandedContent)
            -- Recreate source info with all sources
            factory:CreateSourceInfo(cardFrame, plan, -60)
        else
            -- Collapse: Show only first source (like achievement hides expandedContent)
            -- Recreate source info with only first source
            factory:CreateSourceInfo(cardFrame, plan, -60)
            
            -- Reset card height to original (like achievement system)
            if cardFrame.originalHeight then
                cardFrame:SetHeight(cardFrame.originalHeight)
                if CardLayoutManager and cardFrame._layoutManager then
                    CardLayoutManager:UpdateCardHeight(cardFrame, cardFrame.originalHeight)
                end
            end
        end
        
        -- Update expand button icon
        factory:UpdateExpandButtonIcon(cardFrame, cardFrame._isSourceExpanded)
        
        -- Calculate new card height based on expansion state (like achievement system)
        local originalHeight = cardFrame.originalHeight or 130
        local newHeight = originalHeight
        
        if cardFrame._isSourceExpanded then
            -- Expand: Calculate actual content height for all sources
            local contentHeight = 0
            if cardFrame._sources then
                for i, source in ipairs(cardFrame._sources) do
                    if source.vendor or source.npc then
                        contentHeight = contentHeight + 18
                    end
                    if source.zone then
                        contentHeight = contentHeight + 18
                    end
                    if i < #cardFrame._sources then
                        contentHeight = contentHeight + 4
                    end
                end
            end
            -- Calculate height needed: originalHeight - reserved space + actual content
            newHeight = originalHeight + (contentHeight - (originalHeight - 60))
        end
        -- else: Collapse - newHeight already set to originalHeight above
        
        -- Update card height
        cardFrame:SetHeight(newHeight)
        
        -- Update layout if needed
        if CardLayoutManager and cardFrame._layoutManager then
            CardLayoutManager:UpdateCardHeight(cardFrame, newHeight)
        end
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

--[[
    Setup generic expand handler for achievement cards only
    NOTE: This is now handled by SetupAchievementExpandHandler
    This function is kept for backward compatibility but does nothing
]]
function PlanCardFactory:SetupExpandHandler(card, plan, planType, anchorFrame)
    -- Only Achievement cards have expand functionality
    -- But this is now handled by SetupAchievementExpandHandler
    -- This function is kept for backward compatibility
    if planType ~= "achievement" then
        return
    end
end

--[[
    Expand card content based on type
]]
function PlanCardFactory:ExpandCardContent(card, planType)
    local expandedContent = card.expandedContent
    if not expandedContent then return end
    
    -- Clear previous content
    for i = expandedContent:GetNumChildren(), 1, -1 do
        local child = select(i, expandedContent:GetChildren())
        if child then
            child:Hide()
            child:SetParent(nil)
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
    card.expandHeader:SetText("|cffffcc00Details:|r")
    
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
    if plan.source and WarbandNexus and WarbandNexus.ParseMultipleSources then
        local success, sources = pcall(function()
            return WarbandNexus:ParseMultipleSources(plan.source)
        end)
        
        if success and sources and #sources > 0 then
            -- Show each source with full details
            for i, source in ipairs(sources) do
                -- Vendor or Drop
                if source.vendor then
                    local vendorText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    vendorText:SetPoint("TOPLEFT", 0, yOffset)
                    vendorText:SetPoint("RIGHT", 0, 0)
                    vendorText:SetText("|cff99ccffVendor:|r |cffffffff" .. source.vendor .. "|r")
                    vendorText:SetJustifyH("LEFT")
                    vendorText:SetWordWrap(true)
                    vendorText:SetNonSpaceWrap(false)
                    yOffset = yOffset - (vendorText:GetStringHeight() or 18) - 4
                elseif source.npc then
                    local dropText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    dropText:SetPoint("TOPLEFT", 0, yOffset)
                    dropText:SetPoint("RIGHT", 0, 0)
                    dropText:SetText("|cff99ccffDrop:|r |cffffffff" .. source.npc .. "|r")
                    dropText:SetJustifyH("LEFT")
                    dropText:SetWordWrap(true)
                    dropText:SetNonSpaceWrap(false)
                    yOffset = yOffset - (dropText:GetStringHeight() or 18) - 4
                end
                
                -- Location (Zone)
                if source.zone then
                    local locationText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    locationText:SetPoint("TOPLEFT", 0, yOffset)
                    locationText:SetPoint("RIGHT", 0, 0)
                    locationText:SetText("|cff99ccffLocation:|r |cffffffff" .. source.zone .. "|r")
                    locationText:SetJustifyH("LEFT")
                    locationText:SetWordWrap(true)
                    locationText:SetNonSpaceWrap(false)
                    yOffset = yOffset - (locationText:GetStringHeight() or 18) - 4
                end
                
                -- Cost (if available)
                if source.cost then
                    local costText = source.cost
                    local currencyName = nil
                    
                    -- Try to identify currency from source text
                    if plan.source then
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
                                    if info and info.name then
                                        currencyName = info.name
                                        break
                                    end
                                end
                            end
                        end
                    end
                    
                    if costText:match("[Gg]old") then
                        currencyName = "Gold"
                    end
                    
                    if currencyName and currencyName ~= "Gold" then
                        costText = costText:gsub("|T.-|t", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        costText = costText .. " (" .. currencyName .. ")"
                    end
                    
                    local costLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    costLabel:SetPoint("TOPLEFT", 0, yOffset)
                    costLabel:SetPoint("RIGHT", 0, 0)
                    costLabel:SetText("|A:Class:16:16|a |cff99ccffCost:|r |cffffffff" .. costText .. "|r")
                    costLabel:SetJustifyH("LEFT")
                    costLabel:SetWordWrap(true)
                    costLabel:SetNonSpaceWrap(false)
                    yOffset = yOffset - (costLabel:GetStringHeight() or 18) - 4
                end
                
                -- Faction (if available)
                if source.faction then
                    local factionText = "|A:Class:16:16|a |cff99ccffFaction:|r |cffffffff" .. source.faction .. "|r"
                    if source.renown then
                        local repType = source.isFriendship and "Friendship" or "Renown"
                        factionText = factionText .. " |cffffcc00(" .. repType .. " " .. source.renown .. ")|r"
                    end
                    local factionLabel = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
                    factionLabel:SetPoint("TOPLEFT", 0, yOffset)
                    factionLabel:SetPoint("RIGHT", 0, 0)
                    factionLabel:SetText(factionText)
                    factionLabel:SetJustifyH("LEFT")
                    factionLabel:SetWordWrap(true)
                    factionLabel:SetNonSpaceWrap(false)
                    yOffset = yOffset - (factionLabel:GetStringHeight() or 18) - 4
                end
                
                -- Add spacing between sources
                if i < #sources then
                    yOffset = yOffset - 8
                end
            end
        else
            -- Fallback: Show raw source text if parsing fails
            local cleanSource = plan.source
            if WarbandNexus.CleanSourceText then
                cleanSource = WarbandNexus:CleanSourceText(cleanSource)
            end
            local sourceText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
            sourceText:SetPoint("TOPLEFT", 0, yOffset)
            sourceText:SetPoint("RIGHT", 0, 0)
            sourceText:SetText("|cff99ccffSource:|r |cffffffff" .. cleanSource .. "|r")
            sourceText:SetJustifyH("LEFT")
            sourceText:SetWordWrap(true)
            yOffset = yOffset - (sourceText:GetStringHeight() or 20) - 8
        end
    elseif plan.source then
        -- No ParseMultipleSources available, show raw text
        local cleanSource = plan.source
        if WarbandNexus.CleanSourceText then
            cleanSource = WarbandNexus:CleanSourceText(cleanSource)
        end
        local sourceText = FontManager:CreateFontString(expandedContent, "body", "OVERLAY")
        sourceText:SetPoint("TOPLEFT", 0, yOffset)
        sourceText:SetPoint("RIGHT", 0, 0)
        sourceText:SetText("|cff99ccffSource:|r |cffffffff" .. cleanSource .. "|r")
        sourceText:SetJustifyH("LEFT")
        sourceText:SetWordWrap(true)
        yOffset = yOffset - (sourceText:GetStringHeight() or 20) - 8
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

--[[
    Create Weekly Vault card with 3 progress slots
]]
function PlanCardFactory:CreateWeeklyVaultCard(card, plan, progress, nameText)
    local COLORS = ns.UI_COLORS
    local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
    local CreateIcon = ns.UI_CreateIcon
    local FontManager = ns.FontManager
    
    -- Get character class color
    local classColor = {1, 1, 1}
    if plan.characterClass then
        local classColors = RAID_CLASS_COLORS[plan.characterClass]
        if classColors then
            classColor = {classColors.r, classColors.g, classColors.b}
        end
    end
    
    -- === HEADER WITH ICON ===
    local iconBorder = CreateFrame("Frame", nil, card)
    iconBorder:SetSize(46, 46)
    iconBorder:SetPoint("TOPLEFT", 10, -10)
    
    local iconFrameObj = CreateIcon(card, "greatVault-whole-normal", 42, true, nil, false)
    iconFrameObj:SetPoint("CENTER", iconBorder, "CENTER", 0, 0)
    iconFrameObj:Show()
    
    -- Title (accent color, title font - larger)
    local titleText = FontManager:CreateFontString(card, "title", "OVERLAY")
    titleText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
    if plan.fullyCompleted then
        titleText:SetTextColor(0.2, 1, 0.2)
        titleText:SetText("Weekly Vault Card - Complete")
    else
        titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        titleText:SetText("Weekly Vault Card")
    end
    titleText:SetJustifyH("LEFT")
    titleText:SetWordWrap(false)
    
    -- Character name + Realm (single line, below title)
    local charText = FontManager:CreateFontString(card, "body", "OVERLAY")
    charText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    charText:SetTextColor(classColor[1], classColor[2], classColor[3])
    local characterDisplay = plan.characterName
    if plan.characterRealm and plan.characterRealm ~= "" then
        characterDisplay = characterDisplay .. " - " .. plan.characterRealm
    end
    charText:SetText(characterDisplay)
    
    -- Reset timer (same format as PvE: "Reset: 15h 26m")
    local function FormatResetTime(seconds)
        if not seconds or seconds <= 0 then return "Soon" end
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        if days > 0 then return string.format("%dd %dh", days, hours)
        elseif hours > 0 then return string.format("%dh %dm", hours, mins)
        else return string.format("%dm", mins) end
    end
    
    local resetTimestamp = WarbandNexus:GetWeeklyResetTime()
    local secondsUntil = resetTimestamp - GetServerTime()
    local resetText = FontManager:CreateFontString(card, "body", "OVERLAY")
    resetText:SetPoint("TOPRIGHT", -35, -10)  -- More space from delete button
    resetText:SetTextColor(0.3, 0.9, 0.3)
    resetText:SetText("Reset: " .. FormatResetTime(secondsUntil))
    card.resetText = resetText  -- Store for updates
    
    -- Auto-update timer every 60 seconds
    card:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceUpdate = (self.timeSinceUpdate or 0) + elapsed
        if self.timeSinceUpdate >= 60 then
            self.timeSinceUpdate = 0
            local resetTs = WarbandNexus:GetWeeklyResetTime()
            local secs = resetTs - GetServerTime()
            self.resetText:SetText("Reset: " .. FormatResetTime(secs))
        end
    end)
    
    -- Delete button
    local removeBtn = CreateFrame("Button", nil, card)
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("TOPRIGHT", -8, -8)
    removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    removeBtn:SetScript("OnClick", function()
        WarbandNexus:RemovePlan(plan.id)
        if WarbandNexus.RefreshUI then
            WarbandNexus:RefreshUI()
        end
    end)
    
    -- === 3 PROGRESS SLOTS ===
    local currentProgress = WarbandNexus:GetWeeklyVaultProgress(plan.characterName, plan.characterRealm) or {
        dungeonCount = 0,
        raidBossCount = 0,
        worldActivityCount = 0
    }
    
    local contentY = -70
    local cardWidth = card:GetWidth()
    local availableWidth = cardWidth - 10 - 15
    local slotSpacing = 10
    local slotWidth = (availableWidth - slotSpacing * 2) / 3
    local slotHeight = 92
    
    local slots = {
        {
            atlas = "questlog-questtypeicon-heroic",
            title = "Dungeon",
            current = currentProgress.dungeonCount,
            max = 8,
            slotData = plan.slots.dungeon,
            thresholds = {1, 4, 8}
        },
        {
            atlas = "questlog-questtypeicon-raid",
            title = "Raids",
            current = currentProgress.raidBossCount,
            max = 6,
            slotData = plan.slots.raid,
            thresholds = {2, 4, 6}
        },
        {
            atlas = "questlog-questtypeicon-Delves",
            title = "World",
            current = currentProgress.worldActivityCount,
            max = 8,
            slotData = plan.slots.world,
            thresholds = {2, 4, 8}
        }
    }
    
    for slotIndex, slot in ipairs(slots) do
        local slotX = 10 + (slotIndex - 1) * (slotWidth + slotSpacing)
        
        local slotFrame = CreateFrame("Frame", nil, card)
        slotFrame:SetSize(slotWidth, slotHeight)
        slotFrame:SetPoint("TOPLEFT", slotX, contentY)
        
        -- Title (centered above bar, no icon)
        local title = FontManager:CreateFontString(slotFrame, "title", "OVERLAY")
        title:SetPoint("TOP", slotFrame, "TOP", 0, -8)  -- Centered, moved up
        title:SetText(slot.title)
        title:SetTextColor(0.95, 0.95, 0.95)
        
        -- Progress Bar (closer to title)
        local barY = -32  -- Moved up from -52
        local barPadding = 18
        local barWidth = slotWidth - (barPadding * 2)
        local barHeight = 16
        
        local barBg = CreateFrame("Frame", nil, slotFrame)
        barBg:SetSize(barWidth, barHeight)
        barBg:SetPoint("TOP", slotFrame, "TOP", 0, barY)
        
        if ApplyVisuals then
            local accentBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}
            ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.3}, accentBorderColor)
        end
        
        -- Progress Fill
        local fillPercent = slot.current / slot.max
        local fillWidth = (barWidth - 2) * fillPercent
        if fillWidth > 0 then
            local fill = barBg:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
            fill:SetSize(fillWidth, barHeight - 2)
            fill:SetTexture("Interface\\Buttons\\WHITE8x8")
            fill:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        end
        
        -- Checkpoint Markers
        for i, threshold in ipairs(slot.thresholds) do
            local checkpointSlot = slot.slotData[i]
            local slotProgress = math.min(slot.current, threshold)
            local completed = slot.current >= threshold
            
            local markerXPercent = threshold / slot.max
            local markerX = markerXPercent * barWidth
            
            -- Checkpoint arrow
            local checkArrow = barBg:CreateTexture(nil, "OVERLAY")
            checkArrow:SetSize(24, 24)
            checkArrow:SetPoint("CENTER", barBg, "BOTTOMLEFT", markerX, 0)
            checkArrow:SetAtlas("MiniMap-QuestArrow")
            if completed then
                checkArrow:SetVertexColor(0.2, 1, 0.2, 1)
            else
                checkArrow:SetVertexColor(0.9, 0.9, 0.9, 1)
            end
            
            -- Checkpoint label (closer to bar)
            if completed then
                local checkFrame = CreateFrame("Frame", nil, slotFrame)
                checkFrame:SetSize(16, 16)
                checkFrame:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -8)  -- Closer
                
                local checkmark = checkFrame:CreateTexture(nil, "OVERLAY")
                checkmark:SetAllPoints()
                checkmark:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
            else
                local label = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                label:SetPoint("TOP", barBg, "BOTTOMLEFT", markerX, -4)  -- Closer
                label:SetTextColor(1, 1, 1)
                label:SetText(string.format("%d/%d", slotProgress, threshold))
            end
            
            -- Hidden checkbox for manual override
            local checkbox = CreateThemedCheckbox(slotFrame, checkpointSlot.completed)
            checkbox:SetSize(8, 8)
            checkbox:SetPoint("CENTER", barBg, "LEFT", markerX, 0)
            checkbox:SetAlpha(0.01)
            checkbox:SetScript("OnClick", function(self)
                checkpointSlot.completed = self:GetChecked()
                checkpointSlot.manualOverride = true
            end)
        end
    end
end

--[[
    Create Add Button
    @param parent Frame - Parent frame
    @param options table - Configuration options:
        - width: number (default from BUTTON_SIZES)
        - height: number (default from BUTTON_SIZES)
        - label: string (default "+ Add")
        - anchorPoint: string (default "BOTTOMRIGHT")
        - x: number (default -10)
        - y: number (default 10)
        - buttonType: string "row" or "card" (default "card")
        - onClick: function - Callback when button is clicked
    @return Frame - Button frame
]]
function PlanCardFactory.CreateAddButton(parent, options)
    options = options or {}
    local BUTTON_SIZES = ns.UI_BUTTON_SIZES or {ROW = {width = 28, height = 28}, CARD = {width = 24, height = 24}}
    local buttonType = options.buttonType or "card"
    local defaultSize = buttonType == "row" and BUTTON_SIZES.ROW or BUTTON_SIZES.CARD
    
    local width = options.width or defaultSize.width
    local height = options.height or defaultSize.height
    local label = options.label or "+"
    local anchorPoint = options.anchorPoint or (buttonType == "row" and "RIGHT" or "BOTTOMRIGHT")
    local x = options.x or (buttonType == "row" and -8 or -10)
    local y = options.y or (buttonType == "row" and 0 or 10)
    
    local CreateThemedButton = ns.UI_CreateThemedButton
    local addBtn = CreateThemedButton(parent, label, width)
    addBtn:SetSize(width, height)
    addBtn:SetPoint(anchorPoint, x, y)
    addBtn:SetFrameLevel(parent:GetFrameLevel() + 10)
    addBtn:EnableMouse(true)
    addBtn:RegisterForClicks("LeftButtonUp")
    
    -- Prevent click propagation
    addBtn:SetScript("OnMouseDown", function(self, button)
        -- Stop propagation
    end)
    
    if options.onClick then
        addBtn:SetScript("OnClick", function(self, button)
            if button == "LeftButton" then
                options.onClick(self)
            end
        end)
    end
    
    return addBtn
end

--[[
    Create Added Indicator
    @param parent Frame - Parent frame
    @param options table - Configuration options:
        - width: number (default from BUTTON_SIZES)
        - height: number (default from BUTTON_SIZES)
        - label: string (default "Added")
        - fontCategory: string (default "body")
        - anchorPoint: string (default "BOTTOMRIGHT")
        - x: number (default -10)
        - y: number (default 10)
        - buttonType: string "row" or "card" (default "card")
    @return Frame - Indicator frame
]]
function PlanCardFactory.CreateAddedIndicator(parent, options)
    options = options or {}
    local BUTTON_SIZES = ns.UI_BUTTON_SIZES or {ROW = {width = 28, height = 28}, CARD = {width = 24, height = 24}}
    local buttonType = options.buttonType or "card"
    local defaultSize = buttonType == "row" and BUTTON_SIZES.ROW or BUTTON_SIZES.CARD
    
    local width = options.width or defaultSize.width
    local height = options.height or defaultSize.height
    local label = options.label or "Added"
    local fontCategory = options.fontCategory or "body"  -- Default to "body" for consistency
    local anchorPoint = options.anchorPoint or (buttonType == "row" and "RIGHT" or "BOTTOMRIGHT")
    local x = options.x or (buttonType == "row" and -8 or -10)
    local y = options.y or (buttonType == "row" and 0 or 10)
    
    local ICON_CHECK = "common-icon-checkmark"
    
    -- Create frame
    local addedFrame = CreateFrame("Frame", nil, parent)
    addedFrame:SetSize(width, height)
    addedFrame:SetPoint(anchorPoint, x, y)
    
    -- Create checkmark icon (14px size, isAtlas=true, noBorder=true)
    local addedIcon = CreateIcon(addedFrame, ICON_CHECK, 14, true, nil, true)
    addedIcon:SetPoint("LEFT", 6, 0)  -- 6px inset to match button padding
    addedIcon:Show()  -- CRITICAL: Show icon
    
    -- Create text
    local addedText = FontManager:CreateFontString(addedFrame, fontCategory, "OVERLAY")
    addedText:SetPoint("LEFT", addedIcon, "RIGHT", 4, 0)
    addedText:SetText("|cff88ff88" .. label .. "|r")
    
    return addedFrame
end

-- Export
ns.UI_PlanCardFactory = PlanCardFactory
