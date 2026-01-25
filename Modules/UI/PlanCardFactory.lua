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
    
    -- Icon border frame for positioning reference (used for checkmark and nameText)
    local iconBorder = CreateFrame("Frame", nil, card)
    iconBorder:SetSize(46, 46)
    iconBorder:SetPoint("TOPLEFT", 10, -10)
    iconBorder:EnableMouse(false)
    
    -- Create icon (centered in iconBorder, like old code)
    local iconFrameObj = CreateIcon(card, plan.icon or "Interface\\Icons\\INV_Misc_QuestionMark", 42, false, nil, true)
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
    
    -- Name text
    local nameText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", 10, -2)
    nameText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
    local nameColor = (progress and progress.collected) and "|cff44ff44" or "|cffffffff"
    nameText:SetText(nameColor .. (plan.name or "Unknown") .. "|r")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:EnableMouse(false)
    card.nameText = nameText
    
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
        end
    end
    
    -- Create type badge text (ALWAYS create, even if anchor is card)
    local typeBadge = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if iconFrame then
        typeBadge:SetPoint("LEFT", iconFrame, "RIGHT", 4, 0)
    else
        if anchorFrame == card then
            typeBadge:SetPoint("TOPLEFT", 10, -60)
        else
            typeBadge:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
        end
    end
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
    
    local pointsText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pointsText:SetPoint("LEFT", shieldFrame, "RIGHT", 4, 0)
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
    local firstSource = {}
    
    -- Safely parse source
    if plan.source and type(plan.source) == "string" and plan.source ~= "" then
        if WarbandNexus and WarbandNexus.ParseMultipleSources then
            local success, result = pcall(function()
                return WarbandNexus:ParseMultipleSources(plan.source)
            end)
            if success and result and #result > 0 then
                sources = result
                firstSource = sources[1] or {}
            end
        end
    end
    
    local lastTextElement = nil
    
    -- Vendor
    if firstSource.vendor then
        local vendorText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vendorText:SetPoint("TOPLEFT", 10, line3Y)
        vendorText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        vendorText:SetText("|cff99ccffVendor:|r |cffffffff" .. firstSource.vendor .. "|r")
        vendorText:SetJustifyH("LEFT")
        vendorText:SetWordWrap(true)
        vendorText:SetMaxLines(2)
        vendorText:SetNonSpaceWrap(false)
        lastTextElement = vendorText
    elseif firstSource.npc then
        local npcText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        npcText:SetPoint("TOPLEFT", 10, line3Y)
        npcText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        npcText:SetText("|cff99ccffNPC:|r |cffffffff" .. firstSource.npc .. "|r")
        npcText:SetJustifyH("LEFT")
        npcText:SetWordWrap(true)
        npcText:SetMaxLines(2)
        npcText:SetNonSpaceWrap(false)
        lastTextElement = npcText
    elseif firstSource.faction then
        local factionText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        factionText:SetPoint("TOPLEFT", 10, line3Y)
        factionText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        local displayText = "|cff99ccffFaction:|r |cffffffff" .. firstSource.faction .. "|r"
        if firstSource.renown then
            local repType = firstSource.isFriendship and "Friendship" or "Renown"
            displayText = displayText .. " |cffffcc00(" .. repType .. " " .. firstSource.renown .. ")|r"
        end
        factionText:SetText(displayText)
        factionText:SetJustifyH("LEFT")
        factionText:SetWordWrap(true)
        factionText:SetMaxLines(2)
        factionText:SetNonSpaceWrap(false)
        lastTextElement = factionText
    end
    
    -- Zone info
    if firstSource.zone then
        local zoneY = lastTextElement and -74 or line3Y
        local zoneText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        zoneText:SetPoint("TOPLEFT", 10, zoneY)
        zoneText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        zoneText:SetText("|cff99ccffZone:|r |cffffffff" .. firstSource.zone .. "|r")
        zoneText:SetJustifyH("LEFT")
        zoneText:SetWordWrap(true)
        zoneText:SetMaxLines(2)
        zoneText:SetNonSpaceWrap(false)
        lastTextElement = zoneText
    end
    
    -- If no structured data, show full source text as fallback
    -- This ALWAYS runs if no vendor/npc/faction/zone was found
    if not firstSource.vendor and not firstSource.zone and not firstSource.npc and not firstSource.faction then
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
        
        local sourceText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sourceText:SetPoint("TOPLEFT", 10, line3Y)
        sourceText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        
        -- Check if text already has a source type prefix
        local sourceType, sourceDetail = rawText:match("^([^:]+:%s*)(.*)$")
        
        if sourceType and sourceDetail and sourceDetail ~= "" then
            -- Text already has source type prefix
            sourceText:SetText("|cff99ccff" .. sourceType .. "|r|cffffffff" .. sourceDetail .. "|r")
        else
            -- No source type prefix, add "Source:" label
            sourceText:SetText("|cff99ccffSource:|r |cffffffff" .. rawText .. "|r")
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
        local placeholderText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        placeholderText:SetPoint("TOPLEFT", 10, line3Y)
        placeholderText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        placeholderText:SetText("|cff99ccffSource:|r |cffffffffUnknown source|r")
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
        -- Weekly vault handled separately in PlansUI
        -- Just return base card
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
        
        local infoText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        infoText:SetPoint("TOPLEFT", 10, currentY)
        infoText:SetPoint("RIGHT", card, "RIGHT", -30, 0)
        infoText:SetText("|cff88ff88Information:|r |cffffffff" .. truncatedDescription .. "|r")
        infoText:SetJustifyH("LEFT")
        infoText:SetWordWrap(true)
        infoText:SetMaxLines(2)
        infoText:SetNonSpaceWrap(false)
        -- Force text to fit within bounds (prevent overflow)
        infoText:SetWidth(card:GetWidth() - 40)  -- 10px left + 30px right margin
        card.infoText = infoText  -- Store for reference
        lastTextElement = infoText
    end
    
    -- Progress (calculate actual progress from achievement criteria)
    local progressLabel = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        local rewardText = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    local requirementsHeader = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if lastTextElement then
        requirementsHeader:SetPoint("TOPLEFT", lastTextElement, "BOTTOMLEFT", 0, -20)
    else
        requirementsHeader:SetPoint("TOPLEFT", 10, currentY - 20)
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
end

--[[
    Setup achievement expand/collapse handler
]]
function PlanCardFactory:SetupAchievementExpandHandler(card, plan)
    card.clickedOnRemoveBtn = false
    
    card:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        
        local achievementID = self.planAchievementID or plan.achievementID
        if not achievementID then return end
        
        if self.clickedOnRemoveBtn then
            self.clickedOnRemoveBtn = false
            return
        end
        
        if self.isExpanded then
            -- Collapse
            self.isExpanded = false
            if self.cardKey then
                ns.expandedCards[self.cardKey] = false
            end
            if self.expandedContent then
                self.expandedContent:Hide()
            end
            if self.originalHeight then
                self:SetHeight(self.originalHeight)
                if CardLayoutManager and self._layoutManager then
                    CardLayoutManager:UpdateCardHeight(self, self.originalHeight)
                end
            end
            if self.requirementsHeader then
                self.requirementsHeader:SetText("|cffffcc00Requirements:|r ...")
            end
            -- Recalculate progress when collapsed to show same format as expanded
            local achievementID = self.planAchievementID or plan.achievementID
            if achievementID and self.progressLabel then
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
                        self.progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou are %d/%d on the progress|r", progressColor, totalQuantity, totalReqQuantity))
                    else
                        -- Criteria-based: "You completed X of Y total requirements"
                        self.progressLabel:SetText(string.format("|cffffcc00Progress:|r %sYou completed %d of %d total requirements|r", progressColor, completedCount, numCriteria))
                    end
                else
                    self.progressLabel:SetText("|cffffcc00Progress:|r")
                end
            elseif self.progressLabel then
                self.progressLabel:SetText("|cffffcc00Progress:|r")
            end
        else
            -- Expand
            self.isExpanded = true
            if self.cardKey then
                ns.expandedCards[self.cardKey] = true
            end
            
            local numCriteria = GetAchievementNumCriteria(achievementID)
            if numCriteria and numCriteria > 0 then
                PlanCardFactory:ExpandAchievementContent(self, achievementID)
            else
                PlanCardFactory:ExpandAchievementEmpty(self)
            end
            
            -- Ensure expandedContent is shown after expansion
            if self.expandedContent then
                self.expandedContent:Show()
            end
            
            -- Update requirements header text
            if self.requirementsHeader then
                self.requirementsHeader:SetText("|cffffcc00Requirements:|r")
            end
        end
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
    
    -- Show full Information text in expanded content if it was truncated
    local contentY = 0
    if card.fullDescription and card.fullDescription ~= "" then
        local truncatedDescription = card.infoText and card.infoText:GetText() or ""
        local fullDescription = card.fullDescription
        
        -- Check if description was truncated (contains "..." or is shorter than full)
        if truncatedDescription:find("%.%.%.") or #truncatedDescription < #fullDescription then
            local infoText = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            infoText:SetPoint("TOPLEFT", 0, contentY)
            infoText:SetPoint("RIGHT", 0, 0)
            infoText:SetText("|cff88ff88Information:|r |cffffffff" .. fullDescription .. "|r")
            infoText:SetJustifyH("LEFT")
            infoText:SetWordWrap(true)
            infoText:SetNonSpaceWrap(false)
            -- Calculate approximate height based on text length and width
            local textWidth = expandedContent:GetWidth() or 200
            local charsPerLine = math.floor(textWidth / 6)  -- Approximate chars per line
            local numLines = math.ceil(#fullDescription / charsPerLine)
            contentY = contentY - (numLines * 14 + 8)  -- 14px per line + 8px spacing
        end
    end
    
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
                local colLabel = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    
    local noCriteriaText = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    
    -- Setup expand handler (requires lastTextElement)
    if lastTextElement then
        self:SetupExpandHandler(card, plan, "mount", lastTextElement)
    else
        -- Fallback: use nameText or create anchor
        local anchorFrame = nameText or card
        self:SetupExpandHandler(card, plan, "mount", anchorFrame)
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
        self:SetupExpandHandler(card, plan, "pet", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupExpandHandler(card, plan, "pet", anchorFrame)
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
        self:SetupExpandHandler(card, plan, "toy", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupExpandHandler(card, plan, "toy", anchorFrame)
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
        self:SetupExpandHandler(card, plan, "illusion", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupExpandHandler(card, plan, "illusion", anchorFrame)
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
        self:SetupExpandHandler(card, plan, "title", lastTextElement)
    else
        local anchorFrame = nameText or card
        self:SetupExpandHandler(card, plan, "title", anchorFrame)
    end
end

--[[
    Create default card for other types
]]
function PlanCardFactory:CreateDefaultCard(card, plan, progress, nameText)
    self:CreateTypeBadge(card, plan, nameText)
    self:CreateSourceInfo(card, plan, -60)
end

--[[
    Setup generic expand handler for non-achievement cards
]]
function PlanCardFactory:SetupExpandHandler(card, plan, planType, anchorFrame)
    -- Create expand header
    local expandHeader = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if anchorFrame then
        expandHeader:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -12)
    else
        -- Fallback: use nameText or default position
        if card.nameText then
            expandHeader:SetPoint("TOPLEFT", card.nameText, "BOTTOMLEFT", 0, -50)
        else
            expandHeader:SetPoint("TOPLEFT", 10, -100)
        end
    end
    expandHeader:SetPoint("RIGHT", card, "RIGHT", -30, 0)
    expandHeader:SetText("|cffffcc00Details:|r ...")
    expandHeader:SetJustifyH("LEFT")
    expandHeader:SetTextColor(1, 1, 1)
    card.expandHeader = expandHeader
    
    -- Create expandable content
    local expandedContent = self:CreateExpandableContent(card, expandHeader)
    
    -- Setup click handler
    card.clickedOnRemoveBtn = false
    local factory = self  -- Capture factory reference
    card:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" then return end
        if self.clickedOnRemoveBtn then
            self.clickedOnRemoveBtn = false
            return
        end
        
        if self.isExpanded then
            -- Collapse
            self.isExpanded = false
            if self.cardKey then
                ns.expandedCards[self.cardKey] = false
            end
            if self.expandedContent then
                self.expandedContent:Hide()
            end
            if self.originalHeight then
                self:SetHeight(self.originalHeight)
                if CardLayoutManager and self._layoutManager then
                    CardLayoutManager:UpdateCardHeight(self, self.originalHeight)
                end
            end
            if self.expandHeader then
                self.expandHeader:SetText("|cffffcc00Details:|r ...")
            end
        else
            -- Expand
            self.isExpanded = true
            if self.cardKey then
                ns.expandedCards[self.cardKey] = true
            end
            factory:ExpandCardContent(self, planType)
        end
    end)
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
    if planType == "mount" then
        contentHeight = self:ExpandMountContent(expandedContent, plan)
    elseif planType == "pet" then
        contentHeight = self:ExpandPetContent(expandedContent, plan)
    elseif planType == "toy" then
        contentHeight = self:ExpandToyContent(expandedContent, plan)
    elseif planType == "illusion" then
        contentHeight = self:ExpandIllusionContent(expandedContent, plan)
    elseif planType == "title" then
        contentHeight = self:ExpandTitleContent(expandedContent, plan)
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
    Expand mount content
]]
function PlanCardFactory:ExpandMountContent(expandedContent, plan)
    local yOffset = 0
    
    -- Show full source text
    if plan.source then
        local sourceText = expandedContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sourceText:SetPoint("TOPLEFT", 0, yOffset)
        sourceText:SetPoint("RIGHT", 0, 0)
        local cleanSource = plan.source
        if WarbandNexus.CleanSourceText then
            cleanSource = WarbandNexus:CleanSourceText(cleanSource)
        end
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

-- Export
ns.UI_PlanCardFactory = PlanCardFactory
