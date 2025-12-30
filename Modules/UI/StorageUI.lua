--[[
    Warband Nexus - Storage Tab
    Hierarchical storage browser with search and category organization
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetItemTypeName = ns.UI_GetItemTypeName
local GetItemClassID = ns.UI_GetItemClassID
local GetTypeIcon = ns.UI_GetTypeIcon
local GetQualityHex = ns.UI_GetQualityHex
local DrawEmptyState = ns.UI_DrawEmptyState
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Import pooling functions
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING

-- Performance: Local function references
local format = string.format

--============================================================================
-- DRAW STORAGE TAB (Hierarchical Storage Browser)
--============================================================================

function WarbandNexus:DrawStorageTab(parent)
    -- Release all pooled children before redrawing (performance optimization)
    ReleaseAllPooledChildren(parent)
    
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    local indent = 20
    
    -- Get search text from namespace
    local storageSearchText = ns.UI_GetStorageSearchText()
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_36")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Storage Browser|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Browse all items organized by type")
    
    yOffset = yOffset + 78 -- Header height + spacing
    
    -- NOTE: Search box is now persistent in UI.lua (searchArea)
    -- No need to create it here!
    
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
            else
                expanded.categories[key] = isExpanded
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
        -- Expand normalized items for search
        local expandedItem = item
        if item.id and not item.name then
            expandedItem = WarbandNexus:ExpandItemData(item) or item
        end
        
        local itemName = (expandedItem.name or ""):lower()
        local itemLink = (expandedItem.itemLink or expandedItem.link or ""):lower()
        return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
    end
    
    -- PRE-SCAN: If search is active, find which categories have matches
    local categoriesWithMatches = {}
    local hasAnyMatches = false
    
    if storageSearchText and storageSearchText ~= "" then
        -- Scan Warband Bank
        local warbandBankData = self.db.global.warbandBank and self.db.global.warbandBank.items or {}
        for bagID, bagData in pairs(warbandBankData) do
            for slotID, item in pairs(bagData) do
                local itemID = item.itemID or item.id
                if itemID and ItemMatchesSearch(item) then
                    -- Expand normalized items to get classID
                    local expandedItem = item
                    if item.id and not item.name then
                        expandedItem = WarbandNexus:ExpandItemData(item) or item
                    end
                    
                    local classID = expandedItem.classID or GetItemClassID(itemID)
                    local typeName = GetItemTypeName(classID)
                    local categoryKey = "warband_" .. typeName
                    categoriesWithMatches[categoryKey] = true
                    categoriesWithMatches["warband"] = true
                    hasAnyMatches = true
                end
            end
        end
        
        -- Scan Personal Banks
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, item in pairs(bagData) do
                        local itemID = item.itemID or item.id
                        if itemID and ItemMatchesSearch(item) then
                            -- Expand normalized items to get classID
                            local expandedItem = item
                            if item.id and not item.name then
                                expandedItem = WarbandNexus:ExpandItemData(item) or item
                            end
                            
                            local classID = expandedItem.classID or GetItemClassID(itemID)
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
    
    -- If search is active but no matches, show empty state
    if storageSearchText and storageSearchText ~= "" and not hasAnyMatches then
        return DrawEmptyState(self, parent, yOffset, true, storageSearchText)
    end
    
    -- ===== WARBAND BANK SECTION =====
    -- Auto-expand if search has matches in this section
    local warbandExpanded = expanded.warband
    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["warband"] then
        warbandExpanded = true
    end
    
    -- Skip section entirely if search active and no matches
    if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["warband"] then
        -- Skip this section
    else
        local warbandHeader, warbandBtn = CreateCollapsibleHeader(
            parent,
            "Warband Bank",
            "warband",
            warbandExpanded,
            function(isExpanded) ToggleExpand("warband", isExpanded) end,
            "Interface\\Icons\\INV_Misc_Bag_36"
        )
        warbandHeader:SetPoint("TOPLEFT", 10, -yOffset)
        yOffset = yOffset + HEADER_SPACING
    end
    
    if warbandExpanded and not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["warband"]) then
        -- Group warband items by type
        local warbandItems = {}
        local warbandBankData = self.db.global.warbandBank and self.db.global.warbandBank.items or {}
        
        for bagID, bagData in pairs(warbandBankData) do
            for slotID, item in pairs(bagData) do
                local itemID = item.itemID or item.id
                if itemID then
                    -- Expand normalized items to get classID
                    local expandedItem = item
                    if item.id and not item.name then
                        expandedItem = WarbandNexus:ExpandItemData(item) or item
                    end
                    
                    -- Use expanded classID or get from API
                    local classID = expandedItem.classID or GetItemClassID(itemID)
                    local typeName = GetItemTypeName(classID)
                    
                    if not warbandItems[typeName] then
                        warbandItems[typeName] = {}
                    end
                    -- Store classID in item for icon lookup (mutate original for consistency)
                    if not item.classID then
                        item.classID = classID
                    end
                    table.insert(warbandItems[typeName], item)
                end
            end
        end
        
        -- Sort types alphabetically
        local sortedTypes = {}
        for typeName in pairs(warbandItems) do
            table.insert(sortedTypes, typeName)
        end
        table.sort(sortedTypes)
        
        -- Draw each type category
        for _, typeName in ipairs(sortedTypes) do
            local categoryKey = "warband_" .. typeName
            
            -- Skip category if search active and no matches
            if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[categoryKey] then
                -- Skip this category
            else
                -- Auto-expand if search has matches in this category
                local isTypeExpanded = expanded.categories[categoryKey]
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
                
                -- Get icon from first item in category
                local typeIcon = nil
                if warbandItems[typeName][1] and warbandItems[typeName][1].classID then
                    typeIcon = GetTypeIcon(warbandItems[typeName][1].classID)
                end
                
                -- Type header (indented) - show match count if searching
                local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #warbandItems[typeName]
                local typeHeader, typeBtn = CreateCollapsibleHeader(
                    parent,
                    typeName .. " (" .. displayCount .. ")",
                    categoryKey,
                    isTypeExpanded,
                    function(isExpanded) ToggleExpand(categoryKey, isExpanded) end,
                    typeIcon
                )
                typeHeader:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                typeHeader:SetWidth(width - indent)
                yOffset = yOffset + HEADER_SPACING
                
                if isTypeExpanded then
                    -- Display items in this category (with search filter)
                    local rowIdx = 0
                    for _, item in ipairs(warbandItems[typeName]) do
                        -- Apply search filter
                        local shouldShow = ItemMatchesSearch(item)
                        
                        if shouldShow then
                            rowIdx = rowIdx + 1
                            local i = rowIdx
                            
                            -- Items tab style row
                            local itemRow = CreateFrame("Button", nil, parent, "BackdropTemplate")
                            itemRow:SetSize(width - indent, ROW_HEIGHT)
                            itemRow:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                            itemRow:SetBackdrop({
                                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                            })
                            -- Alternating row colors (Items style)
                            itemRow:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                            
                            -- Quantity (left side, Items style)
                            local qtyText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                            qtyText:SetPoint("LEFT", 15, 0)
                            qtyText:SetWidth(45)
                            qtyText:SetJustifyH("RIGHT")
                            qtyText:SetText(format("|cffffff00%d|r", item.stackCount or item.count or 1))
                            
                            -- Icon
                            -- Expand normalized item data first (handles cache miss gracefully)
                            local expandedItem = item
                            if item.id and not item.name then
                                -- This is a normalized item, expand it
                                expandedItem = WarbandNexus:ExpandItemData(item) or item
                            end
                            
                            local itemID = expandedItem.itemID or expandedItem.id
                            
                            -- Icon
                            local icon = itemRow:CreateTexture(nil, "ARTWORK")
                            icon:SetSize(22, 22)
                            icon:SetPoint("LEFT", 70, 0)
                            icon:SetTexture(expandedItem.iconFileID or 134400)
                            
                            -- Name (with pet cage handling and quality color, Items style)
                            local nameText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                            nameText:SetPoint("LEFT", 98, 0)
                            nameText:SetJustifyH("LEFT")
                            nameText:SetWordWrap(false)
                            nameText:SetWidth(width - indent - 200)
                            
                            local baseName = expandedItem.name or format("Item %s", tostring(itemID or "?"))
                            local quality = expandedItem.quality or 0
                            local displayName = WarbandNexus:GetItemDisplayName(itemID, baseName, expandedItem.classID)
                            nameText:SetText(format("|cff%s%s|r", GetQualityHex(quality), displayName))
                            
                            -- Location (right side, Items style)
                            local locationText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                            locationText:SetPoint("RIGHT", -10, 0)
                            locationText:SetWidth(60)
                            locationText:SetJustifyH("RIGHT")
                            local locText = item.tabIndex and format("Tab %d", item.tabIndex) or ""
                            locationText:SetText(locText)
                            locationText:SetTextColor(0.5, 0.5, 0.5)
                            
                            -- Tooltip support (Items style)
                            itemRow:SetScript("OnEnter", function(self)
                                self:SetBackdropColor(0.15, 0.15, 0.20, 1)
                                if item.itemLink then
                                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                    GameTooltip:SetHyperlink(item.itemLink)
                                    GameTooltip:Show()
                                elseif item.itemID then
                                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                    GameTooltip:SetItemByID(item.itemID)
                                    GameTooltip:Show()
                                end
                            end)
                            itemRow:SetScript("OnLeave", function(self)
                                self:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                GameTooltip:Hide()
                            end)
                            
                            yOffset = yOffset + ROW_SPACING
                        end
                    end
                end
            end
        end
        
        if #sortedTypes == 0 then
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 10 + indent, -yOffset)
            emptyText:SetTextColor(0.5, 0.5, 0.5)
            emptyText:SetText("  No items in Warband Bank")
            yOffset = yOffset + SECTION_SPACING
        end
    end
    
    yOffset = yOffset + 10
    
    -- ===== PERSONAL BANKS SECTION =====
    -- Auto-expand if search has matches in this section
    local personalExpanded = expanded.personal
    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches["personal"] then
        personalExpanded = true
    end
    
    -- Skip section entirely if search active and no matches
    if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["personal"] then
        -- Skip this section
    else
        local personalHeader, personalBtn = CreateCollapsibleHeader(
            parent,
            "Personal Banks",
            "personal",
            personalExpanded,
            function(isExpanded) ToggleExpand("personal", isExpanded) end,
            "Interface\\Icons\\Achievement_Character_Human_Male"
        )
        personalHeader:SetPoint("TOPLEFT", 10, -yOffset)
        yOffset = yOffset + HEADER_SPACING
    end
    
    if personalExpanded and not (storageSearchText and storageSearchText ~= "" and not categoriesWithMatches["personal"]) then
        -- Iterate through each character
        for charKey, charData in pairs(self.db.global.characters or {}) do
            if charData.personalBank then
                local charName = charKey:match("^([^-]+)")
                local charCategoryKey = "personal_" .. charKey
                
                -- Skip character if search active and no matches
                if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[charCategoryKey] then
                    -- Skip this character
                else
                    -- Auto-expand if search has matches for this character
                    local isCharExpanded = expanded.categories[charCategoryKey]
                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if charData.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. charData.classFile
                    end
                    
                    -- Character header (indented)
                    local charHeader, charBtn = CreateCollapsibleHeader(
                        parent,
                        (charName or charKey),
                        charCategoryKey,
                        isCharExpanded,
                        function(isExpanded) ToggleExpand(charCategoryKey, isExpanded) end,
                        charIcon
                    )
                    charHeader:SetPoint("TOPLEFT", 10 + indent, -yOffset)
                    charHeader:SetWidth(width - indent)
                    yOffset = yOffset + HEADER_SPACING
                    
                    if isCharExpanded then
                    -- Group character's items by type
                    local charItems = {}
                    for bagID, bagData in pairs(charData.personalBank) do
                        for slotID, item in pairs(bagData) do
                            local itemID = item.itemID or item.id
                            if itemID then
                                -- Expand normalized items to get classID
                                local expandedItem = item
                                if item.id and not item.name then
                                    expandedItem = WarbandNexus:ExpandItemData(item) or item
                                end
                                
                                -- Use expanded classID or get from API
                                local classID = expandedItem.classID or GetItemClassID(itemID)
                                local typeName = GetItemTypeName(classID)
                                
                                if not charItems[typeName] then
                                    charItems[typeName] = {}
                                end
                                -- Store classID in item for icon lookup (mutate original for consistency)
                                if not item.classID then
                                    item.classID = classID
                                end
                                table.insert(charItems[typeName], item)
                            end
                        end
                    end
                    
                    -- Sort types
                    local charSortedTypes = {}
                    for typeName in pairs(charItems) do
                        table.insert(charSortedTypes, typeName)
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
                            local isTypeExpanded = expanded.categories[typeKey]
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
                            
                            -- Get icon from first item in category
                            local typeIcon2 = nil
                            if charItems[typeName][1] and charItems[typeName][1].classID then
                                typeIcon2 = GetTypeIcon(charItems[typeName][1].classID)
                            end
                            
                            -- Type header (double indented) - show match count if searching
                            local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #charItems[typeName]
                            local typeHeader2, typeBtn2 = CreateCollapsibleHeader(
                                parent,
                                typeName .. " (" .. displayCount .. ")",
                                typeKey,
                                isTypeExpanded,
                                function(isExpanded) ToggleExpand(typeKey, isExpanded) end,
                                typeIcon2
                            )
                            typeHeader2:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                            typeHeader2:SetWidth(width - indent * 2)
                            yOffset = yOffset + HEADER_SPACING
                            
                            if isTypeExpanded then
                                -- Display items (with search filter)
                                local rowIdx = 0
                                for _, item in ipairs(charItems[typeName]) do
                                    -- Apply search filter
                                    local shouldShow = ItemMatchesSearch(item)
                                    
                                    if shouldShow then
                                        rowIdx = rowIdx + 1
                                        local i = rowIdx
                                        
                                        -- Items tab style row
                                        local itemRow = CreateFrame("Button", nil, parent, "BackdropTemplate")
                                        itemRow:SetSize(width - indent * 2, ROW_HEIGHT)
                                        itemRow:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                                        itemRow:SetBackdrop({
                                            bgFile = "Interface\\BUTTONS\\WHITE8X8",
                                        })
                                        -- Alternating row colors (Items style)
                                        itemRow:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                        
                                        -- Quantity (left side, Items style)
                                        local qtyText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                                        qtyText:SetPoint("LEFT", 15, 0)
                                        qtyText:SetWidth(45)
                                        qtyText:SetJustifyH("RIGHT")
                                        qtyText:SetText(format("|cffffff00%d|r", item.stackCount or item.count or 1))
                                        
                                        -- Icon
                                        -- Expand normalized item data first (handles cache miss gracefully)
                                        local expandedItem = item
                                        if item.id and not item.name then
                                            -- This is a normalized item, expand it
                                            expandedItem = WarbandNexus:ExpandItemData(item) or item
                                        end
                                        
                                        local itemID = expandedItem.itemID or expandedItem.id
                                        
                                        -- Icon
                                        local icon = itemRow:CreateTexture(nil, "ARTWORK")
                                        icon:SetSize(22, 22)
                                        icon:SetPoint("LEFT", 70, 0)
                                        icon:SetTexture(expandedItem.iconFileID or 134400)
                                        
                                        -- Name (with pet cage handling and quality color, Items style)
                                        local nameText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                                        nameText:SetPoint("LEFT", 98, 0)
                                        nameText:SetJustifyH("LEFT")
                                        nameText:SetWordWrap(false)
                                        nameText:SetWidth(width - indent * 2 - 200)
                                        
                                        local baseName = expandedItem.name or format("Item %s", tostring(itemID or "?"))
                                        local quality = expandedItem.quality or 0
                                        local displayName = WarbandNexus:GetItemDisplayName(itemID, baseName, expandedItem.classID)
                                        nameText:SetText(format("|cff%s%s|r", GetQualityHex(quality), displayName))
                                        
                                        -- Location (right side, Items style)
                                        local locationText = itemRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                                        locationText:SetPoint("RIGHT", -10, 0)
                                        locationText:SetWidth(60)
                                        locationText:SetJustifyH("RIGHT")
                                        local locText = item.bagIndex and format("Bag %d", item.bagIndex) or ""
                                        locationText:SetText(locText)
                                        locationText:SetTextColor(0.5, 0.5, 0.5)
                                        
                                        -- Tooltip support (Items style)
                                        itemRow:SetScript("OnEnter", function(self)
                                            self:SetBackdropColor(0.15, 0.15, 0.20, 1)
                                            if item.itemLink then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                                GameTooltip:SetHyperlink(item.itemLink)
                                                GameTooltip:Show()
                                            elseif item.itemID then
                                                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                                                GameTooltip:SetItemByID(item.itemID)
                                                GameTooltip:Show()
                                            end
                                        end)
                                        itemRow:SetScript("OnLeave", function(self)
                                            self:SetBackdropColor(i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.07 or 0.05, i % 2 == 0 and 0.09 or 0.06, 1)
                                            GameTooltip:Hide()
                                        end)
                                        
                                        yOffset = yOffset + ROW_SPACING
                                    end
                                end
                            end
                        end
                    end
                    
                    if #charSortedTypes == 0 then
                        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        emptyText:SetPoint("TOPLEFT", 10 + indent * 2, -yOffset)
                        emptyText:SetTextColor(0.5, 0.5, 0.5)
                        emptyText:SetText("    No items in personal bank")
                        yOffset = yOffset + SECTION_SPACING
                    end
                    end
                end
            end
        end
    end
    
    return yOffset + 20
end

