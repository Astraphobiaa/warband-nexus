--[[
    Warband Nexus - Storage Tab
    Hierarchical storage browser with search and category organization
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetItemTypeName = ns.UI_GetItemTypeName
local GetItemClassID = ns.UI_GetItemClassID
local GetTypeIcon = ns.UI_GetTypeIcon
local GetQualityHex = ns.UI_GetQualityHex
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local FormatNumber = ns.UI_FormatNumber
local COLORS = ns.UI_COLORS

-- Import pooling functions
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateResultsContainer = ns.UI_CreateResultsContainer

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local BASE_INDENT = UI_LAYOUT.BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = UI_LAYOUT.SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = UI_LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = UI_LAYOUT.TOP_MARGIN or 8
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT or 26
local ROW_SPACING = UI_LAYOUT.ROW_SPACING or 26
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING or 40
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 8
local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

-- Performance: Local function references
local format = string.format

--============================================================================
-- DRAW STORAGE TAB (Hierarchical Storage Browser)
--============================================================================

function WarbandNexus:DrawStorageTab(parent)
    -- Release all pooled children before redrawing (performance optimization)
    ReleaseAllPooledChildren(parent)
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    
    local yOffset = 8 -- Top padding for consistency with other tabs
    local width = parent:GetWidth() - 20
    local indent = 20
    
    -- Get search text from SearchStateManager
    local storageSearchText = SearchStateManager:GetQuery("storage")
    
    -- ===== HEADER CARD (Always shown) =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("storage"))
    
    -- Dynamic theme color for title
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    -- Use factory pattern positioning for standardized header layout
    local titleTextContent = "|cff" .. hexColor .. "Storage Browser|r"
    local subtitleTextContent = "Browse all items organized by type"
    
    -- Create container for text group (matching factory pattern positioning)
    local textContainer = CreateFrame("Frame", nil, titleCard)
    textContainer:SetSize(200, 40)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    titleCard:Show()
    
    yOffset = yOffset + UI_LAYOUT.afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled - show beautiful disabled state card
    if not ns.Utilities:IsModuleEnabled("storage") then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, "Character Storage")
        return yOffset + cardHeight
    end
    
    -- ===== SEARCH BOX (Below header) =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    -- Use SearchStateManager for state management
    local storageSearchText = SearchStateManager:GetQuery("storage")
    
    local searchBox = CreateSearchBox(parent, width, "Search storage...", function(text)
        -- Update search state via SearchStateManager (throttled, event-driven)
        SearchStateManager:SetSearchQuery("storage", text)
        
        -- Prepare container for rendering
        local resultsContainer = parent.storageResultsContainer
        if resultsContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
            
            -- Redraw results with new search text
            local contentHeight = self:DrawStorageResults(resultsContainer, 0, width, text)
            
            -- Update container height
            resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
        end
    end, 0.4, storageSearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + UI_LAYOUT.afterElement  -- Search box height + spacing
    
    -- ===== RESULTS CONTAINER (After search box) =====
    local resultsContainer = CreateResultsContainer(parent, yOffset, SIDE_MARGIN)
    resultsContainer:SetHeight(1) -- Will be set after content is drawn
    parent.storageResultsContainer = resultsContainer  -- Store reference for search callback
    
    -- Initial draw of results
    local contentHeight = self:DrawStorageResults(resultsContainer, 0, width, storageSearchText)
    
    -- CRITICAL FIX: Update container height AFTER content is drawn
    resultsContainer:SetHeight(math.max(contentHeight, 1))
    
    return yOffset + contentHeight
end

--============================================================================
-- STORAGE RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawStorageResults(parent, yOffset, width, storageSearchText)
    local indent = BASE_INDENT  -- Level 1 indent
    self.recentlyExpanded = self.recentlyExpanded or {}
    
    -- Get expanded state
    local expanded = self.db.profile.storageExpanded or {}
    if not expanded.categories then expanded.categories = {} end
    
    -- Toggle function
    local function ToggleExpand(key, isExpanded)
        -- If isExpanded is boolean, use it directly (new callback style)
        -- If isExpanded is nil, toggle manually (old callback style for backwards compat)
        if type(isExpanded) == "boolean" then
            if key == "warband" or key == "personal" then
                expanded[key] = isExpanded
                if isExpanded then self.recentlyExpanded[key] = GetTime() end
            else
                expanded.categories[key] = isExpanded
                if isExpanded then self.recentlyExpanded[key] = GetTime() end
            end
        else
            -- Old style toggle (fallback)
            if key == "warband" or key == "personal" then
                expanded[key] = not expanded[key]
            else
                expanded.categories[key] = not expanded.categories[key]
            end
        end
        self:RefreshUI()
    end
    
    -- Search filtering helper
    local function ItemMatchesSearch(item)
        if not storageSearchText or storageSearchText == "" then
            return true
        end
        local itemName = (item.name or ""):lower()
        local itemLink = (item.itemLink or ""):lower()
        return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
    end
    
    -- PRE-SCAN: If search is active, find which categories have matches
    local categoriesWithMatches = {}
    local hasAnyMatches = false
    
    if storageSearchText and storageSearchText ~= "" then
        -- Scan Warband Bank
        local warbandData = self:GetWarbandBankV2()
        local warbandBankData = warbandData and warbandData.items or {}
        for bagID, bagData in pairs(warbandBankData) do
            for slotID, item in pairs(bagData) do
                if item.itemID and ItemMatchesSearch(item) then
                    local classID = item.classID or GetItemClassID(item.itemID)
                    local typeName = GetItemTypeName(classID)
                    local categoryKey = "warband_" .. typeName
                    categoriesWithMatches[categoryKey] = true
                    categoriesWithMatches["warband"] = true
                    hasAnyMatches = true
                end
            end
        end
        
        -- Scan Personal Items (Bank + Bags)
        for charKey, charData in pairs(self.db.global.characters or {}) do
            local personalItems = self:GetPersonalItemsV2(charKey)
            if personalItems then
                for bagID, bagData in pairs(personalItems) do
                    for slotID, item in pairs(bagData) do
                        if item.itemID and ItemMatchesSearch(item) then
                            local classID = item.classID or GetItemClassID(item.itemID)
                            local typeName = GetItemTypeName(classID)
                            local charCategoryKey = "personal_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["personal"] = true
                            hasAnyMatches = true
                        end
                    end
                end
            end
        end
    end
    
    -- If search is active but no matches, show empty state and return
    if storageSearchText and storageSearchText ~= "" and not hasAnyMatches then
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, storageSearchText, "storage")
        -- Update SearchStateManager with result count
        SearchStateManager:UpdateResults("storage", 0)
        return height
    end
    
    -- ===== WARBAND BANK SECTION =====
    -- Group warband items by type FIRST (to check if section has content)
    local warbandItems = {}
    local warbandData = self:GetWarbandBankV2()
    local warbandBankData = warbandData and warbandData.items or {}
    
    for bagID, bagData in pairs(warbandBankData) do
        for slotID, item in pairs(bagData) do
            if item.itemID then
                -- Use stored classID or get it from API
                local classID = item.classID or GetItemClassID(item.itemID)
                local typeName = GetItemTypeName(classID)
                
                if not warbandItems[typeName] then
                    warbandItems[typeName] = {}
                end
                -- Store classID in item for icon lookup
                if not item.classID then
                    item.classID = classID
                end
                table.insert(warbandItems[typeName], item)
            end
        end
    end
    
    -- Count total matches in warband section (for search filtering)
    local warbandTotalMatches = 0
    if storageSearchText and storageSearchText ~= "" then
        for typeName, items in pairs(warbandItems) do
            for _, item in ipairs(items) do
                if ItemMatchesSearch(item) then
                    warbandTotalMatches = warbandTotalMatches + 1
                end
            end
        end
    else
        -- No search active, count all items
        for typeName, items in pairs(warbandItems) do
            warbandTotalMatches = warbandTotalMatches + #items
        end
    end
    
    -- Only render Warband Bank section if it has matching items
    if warbandTotalMatches > 0 then
        -- Auto-expand if search has matches in this section
        local warbandExpanded = self.storageExpandAllActive or expanded.warband
        if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["warband"] then
            warbandExpanded = true
        end
        
        local warbandHeader, expandBtn, warbandIcon = CreateCollapsibleHeader(
            parent,
            "Warband Bank",
            "warband",
            warbandExpanded,
            function(isExpanded) ToggleExpand("warband", isExpanded) end,
            "dummy"  -- Dummy value to trigger icon creation
        )
        warbandHeader:SetPoint("TOPLEFT", 0, -yOffset)
        warbandHeader:SetWidth(width)  -- Set width to match content area
        
        -- Replace with Warband atlas icon (27x36 for proper aspect ratio)
        if warbandIcon then
            warbandIcon:SetTexture(nil)  -- Clear dummy texture
            warbandIcon:SetAtlas("warbands-icon")
            warbandIcon:SetSize(27, 36)  -- Native atlas proportions (23:31)
        end
        
        yOffset = yOffset + HEADER_SPACING  -- Header + spacing before content
        
        if warbandExpanded then
            -- Sort types alphabetically
            local sortedTypes = {}
            for typeName in pairs(warbandItems) do
                -- Only include types that have matching items
                local hasMatchingItems = false
                if storageSearchText and storageSearchText ~= "" then
                    for _, item in ipairs(warbandItems[typeName]) do
                        if ItemMatchesSearch(item) then
                            hasMatchingItems = true
                            break
                        end
                    end
                else
                    hasMatchingItems = #warbandItems[typeName] > 0
                end
                
                if hasMatchingItems then
                    table.insert(sortedTypes, typeName)
                end
            end
            table.sort(sortedTypes)
        
        -- Global row counter for zebra striping across all categories
        local globalRowIdx = 0
        
        -- Draw each type category
        for _, typeName in ipairs(sortedTypes) do
            local categoryKey = "warband_" .. typeName
            
            -- Skip category if search active and no matches
            if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[categoryKey] then
                -- Skip this category
            else
                -- Auto-expand if search has matches in this category
                local isTypeExpanded = self.storageExpandAllActive or expanded.categories[categoryKey]
                if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[categoryKey] then
                    isTypeExpanded = true
                end
                
                -- Count items that match search (for display)
                local matchCount = 0
                for _, item in ipairs(warbandItems[typeName]) do
                    if ItemMatchesSearch(item) then
                        matchCount = matchCount + 1
                    end
                end
                
                -- Calculate display count
                local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #warbandItems[typeName]
                
                -- Skip header if it has no items to show
                if displayCount == 0 then
                    -- Skip this empty header
                else
                    -- Get icon from first item in category
                    local typeIcon = nil
                    if warbandItems[typeName][1] and warbandItems[typeName][1].classID then
                        typeIcon = GetTypeIcon(warbandItems[typeName][1].classID)
                    end
                    
                    -- Type header (indented) - show match count if searching
                    local typeHeader, typeBtn = CreateCollapsibleHeader(
                    parent,
                    typeName .. " (" .. FormatNumber(displayCount) .. ")",
                    categoryKey,
                    isTypeExpanded,
                    function(isExpanded) ToggleExpand(categoryKey, isExpanded) end,
                    typeIcon
                )
                typeHeader:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)  -- Subheader at BASE_INDENT (15px)
                typeHeader:SetWidth(width - BASE_INDENT)
                    yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT  -- Type header (no extra spacing before rows)
                    
                    if isTypeExpanded then
                        -- Display items in this category (with search filter)
                        local shouldAnimate = self.recentlyExpanded[categoryKey] and (GetTime() - self.recentlyExpanded[categoryKey] < 0.5)
                        for _, item in ipairs(warbandItems[typeName]) do
                        -- Apply search filter
                        local shouldShow = ItemMatchesSearch(item)
                        
                        if shouldShow then
                            globalRowIdx = globalRowIdx + 1  -- Increment global counter
                            
                            -- ITEMS ROW (Pooled)
                            local itemRow = AcquireStorageRow(parent, width - BASE_INDENT, ROW_HEIGHT)  -- Row width: parent width - header indent
                            -- Note: AcquireStorageRow sets size. Since we need width-indent, pass it above.
                            
                            -- Smart Animation
                            -- Reset Alpha (pooling safety)
                            if not shouldAnimate then itemRow:SetAlpha(1) end
                            if itemRow.anim then itemRow.anim:Stop() end

                            if shouldAnimate then
                                itemRow:SetAlpha(0)
                                if not itemRow.anim then
                                    local anim = itemRow:CreateAnimationGroup()
                                    local fade = anim:CreateAnimation("Alpha")
                                    fade:SetSmoothing("OUT")
                                    anim:SetScript("OnFinished", function() itemRow:SetAlpha(1) end)
                                    itemRow.anim = anim
                                    itemRow.fade = fade
                                end
                                
                                itemRow.fade:SetFromAlpha(0)
                                itemRow.fade:SetToAlpha(1)
                                itemRow.fade:SetDuration(0.15)
                                itemRow.fade:SetStartDelay(globalRowIdx * 0.05)
                                itemRow.anim:Play()
                            end
                            
                            itemRow:ClearAllPoints()
                            itemRow:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)  -- Row at BASE_INDENT (same as Type header)
                            
                            -- Set alternating background colors (using global counter)
                            local bgColor = (globalRowIdx % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
                            if not itemRow.bg then
                                itemRow.bg = itemRow:CreateTexture(nil, "BACKGROUND")
                                itemRow.bg:SetAllPoints()
                            end
                            itemRow.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
                            
                            -- Update Data (qty, icon, name, location)
                            itemRow.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
                            itemRow.icon:SetTexture(item.iconFileID or 134400)
                            
                            local nameWidth = width - 200  -- No indent for rows
                            itemRow.nameText:SetWidth(nameWidth)
                            local baseName = item.name or format("Item %s", tostring(item.itemID or "?"))
                            local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
                            itemRow.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                            
                            itemRow.locationText:SetWidth(72)  -- Increased by 20% (60 * 1.2 = 72)
                            local locText = item.tabIndex and format("Tab %d", item.tabIndex) or ""
                            itemRow.locationText:SetText(locText)
                            itemRow.locationText:SetTextColor(1, 1, 1)
                            
                            -- Tooltip support
                            itemRow:SetScript("OnEnter", function(self)
                                if not ShowTooltip then
                                    -- Fallback
                                    if item.itemLink then
                                        local tooltipData = {
                                            type = "item",
                                            itemLink = item.itemLink
                                        }
                                        ns.TooltipService:Show(self, tooltipData)
                                    end
                                    return
                                end
                                
                                ShowTooltip(self, {
                                    type = "item",
                                    itemID = item.itemID,
                                    anchor = "ANCHOR_LEFT"
                                })
                            end)
                            itemRow:SetScript("OnLeave", function(self)
                                if HideTooltip then
                                    HideTooltip()
                                else
                                    ns.TooltipService:Hide()
                                end
                            end)
                            
                            yOffset = yOffset + ROW_HEIGHT + UI_LAYOUT.betweenRows  -- Row height + standardized spacing
                        end
                    end
                    end
                    
                    -- Add spacing after each type section
                    yOffset = yOffset + SECTION_SPACING
                end  -- if displayCount > 0
            end  -- if not skipped by search
        end
            
            -- No empty state needed for Warband section
        end  -- if warbandExpanded
    end  -- if warbandTotalMatches > 0
    
    -- ===== PERSONAL BANKS SECTION =====
    -- Count total matches in personal section (for search filtering)
    local personalTotalMatches = 0
    if storageSearchText and storageSearchText ~= "" then
        for charKey, charData in pairs(self.db.global.characters or {}) do
            local personalItems = self:GetPersonalItemsV2(charKey)
            if personalItems then
                for location, items in pairs(personalItems) do
                    for _, item in ipairs(items) do
                        if ItemMatchesSearch(item) then
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
            end
        end
    else
        -- No search active, count all items
        for charKey, charData in pairs(self.db.global.characters or {}) do
            local personalItems = self:GetPersonalItemsV2(charKey)
            if personalItems then
                for location, items in pairs(personalItems) do
                    personalTotalMatches = personalTotalMatches + #items
                end
            end
        end
    end
    
    -- Only render Personal Banks section if it has matching items
    if personalTotalMatches > 0 then
        -- Auto-expand if search has matches in this section
        local personalExpanded = self.storageExpandAllActive or expanded.personal
        if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["personal"] then
            personalExpanded = true
        end
        
        local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
        local personalHeader, personalBtn = CreateCollapsibleHeader(
            parent,
            "Personal Items",
            "personal",
            personalExpanded,
            function(isExpanded) ToggleExpand("personal", isExpanded) end,
            GetCharacterSpecificIcon(),
            true  -- isAtlas = true
        )
        personalHeader:SetPoint("TOPLEFT", 0, -yOffset)
        personalHeader:SetWidth(width)  -- Set width to match content area
        yOffset = yOffset + HEADER_SPACING  -- Header + spacing before content
        
        if personalExpanded then
        -- Global row counter for zebra striping across all characters and types
        local globalRowIdx = 0
        
        -- Iterate through each character
        local hasAnyPersonalItems = false
        for charKey, charData in pairs(self.db.global.characters or {}) do
            local personalItems = self:GetPersonalItemsV2(charKey)
            if personalItems then
                -- Extract name and realm from charKey (format: "Name-Realm")
                local charName = charKey:match("^([^-]+)")
                local charRealm = charKey:match("-(.+)$") or ""
                
                -- Apply class color
                local classColor = RAID_CLASS_COLORS[charData.classFile or charData.class] or {r=1, g=1, b=1}
                local charDisplayName = format("|cff%02x%02x%02x%s  -  %s|r",
                    classColor.r * 255, classColor.g * 255, classColor.b * 255,
                    charName,
                    charRealm)
                local charCategoryKey = "personal_" .. charKey
                
                -- Skip character if search active and no matches
                if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[charCategoryKey] then
                    -- Skip this character
                else
                    -- Auto-expand if search has matches for this character
                    local isCharExpanded = self.storageExpandAllActive or expanded.categories[charCategoryKey]
                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if charData.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. charData.classFile
                    end
                    
                    -- Character header (Level 1, indented under Personal Banks)
                    local charIndent = BASE_INDENT * 1  -- 15px
                    local charHeader, charBtn = CreateCollapsibleHeader(
                        parent,
                        (charDisplayName or charKey),
                        charCategoryKey,
                        isCharExpanded,
                        function(isExpanded) ToggleExpand(charCategoryKey, isExpanded) end,
                        charIcon,
                        false,  -- isAtlas = false (class icons are texture paths)
                        1       -- indentLevel = 1 (child header)
                    )
                    charHeader:SetPoint("TOPLEFT", charIndent, -yOffset)
                    charHeader:SetWidth(width - charIndent)
                    yOffset = yOffset + HEADER_SPACING  -- Character header + spacing before content
                    
                    if isCharExpanded then
                    -- Group character's items by type
                    local charItems = {}
                    for bagID, bagData in pairs(personalItems) do
                        for slotID, item in pairs(bagData) do
                            if item.itemID then
                                -- Use stored classID or get it from API
                                local classID = item.classID or GetItemClassID(item.itemID)
                                local typeName = GetItemTypeName(classID)
                                
                                if not charItems[typeName] then
                                    charItems[typeName] = {}
                                end
                                -- Store classID in item for icon lookup
                                if not item.classID then
                                    item.classID = classID
                                end
                                table.insert(charItems[typeName], item)
                            end
                        end
                    end
                    
                    -- Sort types alphabetically - only include types with matching items
                    local charSortedTypes = {}
                    for typeName in pairs(charItems) do
                        -- Only include types that have matching items
                        local hasMatchingItems = false
                        if storageSearchText and storageSearchText ~= "" then
                            for _, item in ipairs(charItems[typeName]) do
                                if ItemMatchesSearch(item) then
                                    hasMatchingItems = true
                                    break
                                end
                            end
                        else
                            hasMatchingItems = #charItems[typeName] > 0
                        end
                        
                        if hasMatchingItems then
                            table.insert(charSortedTypes, typeName)
                        end
                    end
                    table.sort(charSortedTypes)
                    
                    -- Draw each type category for this character
                    for _, typeName in ipairs(charSortedTypes) do
                        local typeKey = "personal_" .. charKey .. "_" .. typeName
                        
                        -- Skip category if search active and no matches
                        if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[typeKey] then
                            -- Skip this category
                        else
                            -- Auto-expand if search has matches in this category
                            local isTypeExpanded = self.storageExpandAllActive or expanded.categories[typeKey]
                            if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[typeKey] then
                                isTypeExpanded = true
                            end
                            
                            -- Count items that match search (for display)
                            local matchCount = 0
                            for _, item in ipairs(charItems[typeName]) do
                                if ItemMatchesSearch(item) then
                                    matchCount = matchCount + 1
                                end
                            end
                            
                            -- Calculate display count
                            local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #charItems[typeName]
                            
                            -- Skip header if it has no items to show
                            if displayCount == 0 then
                                -- Skip this empty header
                            else
                                -- Get icon from first item in category
                                local typeIcon2 = nil
                                if charItems[typeName][1] and charItems[typeName][1].classID then
                                    typeIcon2 = GetTypeIcon(charItems[typeName][1].classID)
                                end
                                
                                -- Type header (Level 2, double indented under character)
                                local typeIndent = BASE_INDENT * 2  -- 30px
                                local typeHeader2, typeBtn2 = CreateCollapsibleHeader(
                                parent,
                                typeName .. " (" .. FormatNumber(displayCount) .. ")",
                                typeKey,
                                isTypeExpanded,
                                function(isExpanded) ToggleExpand(typeKey, isExpanded) end,
                                typeIcon2,
                                false,  -- isAtlas = false (item icons are texture paths)
                                2       -- indentLevel = 2 (child of character header)
                            )
                            typeHeader2:SetPoint("TOPLEFT", typeIndent, -yOffset)
                            typeHeader2:SetWidth(width - typeIndent)
                            yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT  -- Type header (no extra spacing before rows)
                            
                                if isTypeExpanded then
                                    -- Display items (with search filter)
                                    local shouldAnimate = self.recentlyExpanded[typeKey] and (GetTime() - self.recentlyExpanded[typeKey] < 0.5)
                                    for _, item in ipairs(charItems[typeName]) do
                                    -- Apply search filter
                                    local shouldShow = ItemMatchesSearch(item)
                                    
                                    if shouldShow then
                                        globalRowIdx = globalRowIdx + 1  -- Increment global counter
                                        
                                        -- ITEMS ROW (Pooled) - Level 2 indent (same as Type header)
                                        local itemIndent = BASE_INDENT * 2  -- 30px (same as type header)
                                        local itemRow = AcquireStorageRow(parent, width - itemIndent, ROW_HEIGHT)
                                        
                                        -- Smart Animation
                                        if not shouldAnimate then itemRow:SetAlpha(1) end
                                        if itemRow.anim then itemRow.anim:Stop() end

                                        if shouldAnimate then
                                            itemRow:SetAlpha(0)
                                            if not itemRow.anim then
                                                local anim = itemRow:CreateAnimationGroup()
                                                local fade = anim:CreateAnimation("Alpha")
                                                fade:SetSmoothing("OUT")
                                                anim:SetScript("OnFinished", function() itemRow:SetAlpha(1) end)
                                                itemRow.anim = anim
                                                itemRow.fade = fade
                                            end
                                            
                                            itemRow.fade:SetFromAlpha(0)
                                            itemRow.fade:SetToAlpha(1)
                                            itemRow.fade:SetDuration(0.15)
                                            itemRow.fade:SetStartDelay(globalRowIdx * 0.05)
                                            itemRow.anim:Play()
                                        end
                                        
                                        itemRow:ClearAllPoints()
                                        itemRow:SetPoint("TOPLEFT", itemIndent, -yOffset)  -- Row at Level 2 (30px, same as Type header)
                                        
                                        -- Set alternating background colors (using global counter)
                                        local bgColor = (globalRowIdx % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
                                        if not itemRow.bg then
                                            itemRow.bg = itemRow:CreateTexture(nil, "BACKGROUND")
                                            itemRow.bg:SetAllPoints()
                                        end
                                        itemRow.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
                                        
                                        -- Update Data
                                        itemRow.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
                                        itemRow.icon:SetTexture(item.iconFileID or 134400)
                                        
                                        local nameWidth = width - itemIndent - 200  -- Account for row indent
                                        itemRow.nameText:SetWidth(nameWidth)
                                        local baseName = item.name or format("Item %s", tostring(item.itemID or "?"))
                                        local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
                                        itemRow.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                                        
                                        itemRow.locationText:SetWidth(72)  -- Increased by 20% (60 * 1.2 = 72)
                                        -- Distinguish between bank and inventory bags using actualBagID
                                        local locText = ""
                                        if item.actualBagID then
                                            if item.actualBagID == -1 then
                                                locText = "Bank"
                                            elseif item.actualBagID >= 0 and item.actualBagID <= 5 then
                                                locText = format("Bag %d", item.actualBagID)
                                            else
                                                locText = format("Bank Bag %d", item.actualBagID - 5)
                                            end
                                        end
                                        itemRow.locationText:SetText(locText)
                                        itemRow.locationText:SetTextColor(1, 1, 1)
                                        
                                        -- Tooltip
                                        itemRow:SetScript("OnEnter", function(self)
                                            if not ShowTooltip then
                                                if item.itemLink then
                                                    local tooltipData = {
                                                        type = "item",
                                                        itemLink = item.itemLink
                                                    }
                                                    ns.TooltipService:Show(self, tooltipData)
                                                end
                                                return
                                            end
                                            
                                            ShowTooltip(self, {
                                                type = "item",
                                                itemID = item.itemID,
                                                anchor = "ANCHOR_LEFT"
                                            })
                                        end)
                                        itemRow:SetScript("OnLeave", function(self)
                                            if HideTooltip then
                                                HideTooltip()
                                            else
                                                ns.TooltipService:Hide()
                                            end
                                        end)
                                        
                                        yOffset = yOffset + ROW_HEIGHT + UI_LAYOUT.betweenRows  -- Row height + standardized spacing
                                    end
                                end
                                end
                                
                                -- Add spacing after each type section
                                yOffset = yOffset + SECTION_SPACING
                            end  -- if displayCount > 0
                        end  -- if not skipped by search
                    end
                    
                    -- No per-character empty state needed
                    end  -- if isCharExpanded
                    
                    hasAnyPersonalItems = true
                end  -- else (closes the else at line 449)
            end  -- if personalItems
        end  -- for charKey
            
            -- No section-level empty state needed
        end  -- if personalExpanded
    end  -- if personalTotalMatches > 0
    
    return yOffset + UI_LAYOUT.minBottomSpacing
end -- DrawStorageResults

