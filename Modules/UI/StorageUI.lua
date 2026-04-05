--[[
    Warband Nexus - Storage Tab
    Hierarchical storage browser with search and category organization
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Unique AceEvent handler identity for StorageUI
local StorageUIEvents = {}

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
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
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
local function GetLayout() return ns.UI_LAYOUT or {} end
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local HEADER_SPACING = GetLayout().HEADER_SPACING or 40
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
-- ROW_COLOR_EVEN/ODD: Now handled by Factory:ApplyRowBackground()

-- Performance: Local function references
local format = string.format

--============================================================================
-- EVENT LISTENERS (Real-time Updates)
--============================================================================

local function RegisterStorageEvents(parent)
    if parent.storageUpdateHandler then
        return  -- Already registered
    end
    parent.storageUpdateHandler = true
    
    -- Debug print helper
    local DebugPrint = ns.DebugPrint
    
    -- Debounced DrawStorageTab: coalesces rapid WN_ITEMS_UPDATED + WN_ITEM_METADATA_READY
    -- into a single redraw (e.g., bank open fires both within milliseconds)
    local pendingDrawTimer = nil
    local DRAW_DEBOUNCE = 0.1  -- 100ms coalesce window
    
    -- Check if Storage tab is actually the active tab (parent:IsVisible() is not enough
    -- because the scroll child is shared across all tabs and always visible)
    local function IsStorageTabActive()
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        return mf and mf:IsShown() and mf.currentTab == "storage"
    end
    
    local function ScheduleStorageRefresh()
        if not IsStorageTabActive() then return end
        if pendingDrawTimer then return end  -- already scheduled
        pendingDrawTimer = C_Timer.After(DRAW_DEBOUNCE, function()
            pendingDrawTimer = nil
            if IsStorageTabActive() and parent then
                local resultsContainer = parent.storageResultsContainer or parent._storageResultsContainer
                if resultsContainer and resultsContainer:GetParent() == parent and WarbandNexus.DrawStorageResults then
                    local searchText = SearchStateManager:GetQuery("storage")
                    local contentWidth = parent:GetWidth() - 20
                    local contentHeight = WarbandNexus:DrawStorageResults(resultsContainer, 0, contentWidth, searchText)
                    resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
                else
                    WarbandNexus:DrawStorageTab(parent)
                end
            end
        end)
    end
    
    -- WN_ITEMS_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- storage tab refresh via PopulateContent → DrawStorageTab. Having both caused double rebuild.
    
    -- Async item metadata resolution (items that were "Loading..." now have real names)
    -- Keep: UI.lua does NOT handle WN_ITEM_METADATA_READY.
    -- Rate-limited to prevent infinite redraw loop: metadata refresh wipes caches,
    -- redraw triggers new async loads which fire another metadata refresh.
    local lastMetadataRefreshDraw = 0
    local METADATA_REFRESH_COOLDOWN = 2

    WarbandNexus.RegisterMessage(StorageUIEvents, "WN_ITEM_METADATA_READY", function()
        if IsStorageTabActive() then
            local now = GetTime()
            if now - lastMetadataRefreshDraw < METADATA_REFRESH_COOLDOWN then return end
            lastMetadataRefreshDraw = now
            DebugPrint("|cff00ff00[StorageUI]|r WN_ITEM_METADATA_READY received, refreshing names")
            ScheduleStorageRefresh()
        end
    end)
    
    DebugPrint("|cff9370DB[StorageUI]|r Event listeners registered: WN_ITEM_METADATA_READY")
end

--============================================================================
-- DRAW STORAGE TAB (Hierarchical Storage Browser)
--============================================================================

function WarbandNexus:DrawStorageTab(parent)
-- Register event listeners (only once)
    RegisterStorageEvents(parent)
    -- Release all pooled children before redrawing (performance optimization)
    ReleaseAllPooledChildren(parent)
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.personalBanks"
        if self.db.global.storageCache and next(self.db.global.storageCache.characters or {}) then
            local cacheVersion = self.db.global.storageCache.version or "unknown"
            dataSource = "StorageCache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    elseif parent.dbVersionBadge:GetParent() ~= parent then
        parent.dbVersionBadge:SetParent(parent)
    end
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    HideEmptyStateCard(parent, "storage")
    
    local width = parent:GetWidth() - 20
    local indent = 20
    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8
    
    -- Get search text from SearchStateManager
    local storageSearchText = SearchStateManager:GetQuery("storage")
    
    -- ===== HEADER CARD (in fixedHeader - non-scrolling) =====
    if not parent._storageTitleCard then
        local titleCard = CreateCard(headerParent, 70)

        -- Header icon with ring border (standardized)
        local CreateHeaderIcon = ns.UI_CreateHeaderIcon
        local GetTabIcon = ns.UI_GetTabIcon
        local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("storage"))

        -- Create container for text group (using Factory pattern)
        local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)

        -- Create title text (header font, colored)
        local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
        titleText:SetJustifyH("LEFT")

        -- Create subtitle text
        local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
        subtitleText:SetTextColor(1, 1, 1)  -- White
        subtitleText:SetJustifyH("LEFT")

        -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
        titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)
        titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)
        subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)

        -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
        textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
        textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)

        -- Sort Dropdown on the Title Card (Header)
        if ns.UI_CreateCharacterSortDropdown then
            local sortOptions = {
                {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
                {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
                {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
                {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
                {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            }
            if not self.db.profile.storageSort then self.db.profile.storageSort = {} end
            local sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.storageSort, function() self:RefreshUI() end)
            sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -20, 0)
            sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
        end

        -- Store references for reuse
        parent._storageTitleCard = titleCard
        parent._storageTitleText = titleText
        parent._storageSubtitleText = subtitleText
    end

    local titleCard = parent._storageTitleCard

    -- Re-parent to fixedHeader
    if titleCard:GetParent() ~= headerParent then
        titleCard:SetParent(headerParent)
    end

    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["STORAGE_HEADER"]) or "Storage Browser") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["STORAGE_HEADER_DESC"]) or "Browse all items organized by type"
    parent._storageTitleText:SetText(titleTextContent)
    parent._storageSubtitleText:SetText(subtitleTextContent)

    titleCard:ClearAllPoints()
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    titleCard:Show()
    
    headerYOffset = headerYOffset + GetLayout().afterHeader
    
    -- Check if module is disabled
    if not ns.Utilities:IsModuleEnabled("storage") then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["STORAGE_DISABLED_TITLE"]) or "Character Storage")
        return 8 + cardHeight
    end
    
    -- ===== SEARCH BOX (in fixedHeader - non-scrolling) =====
    local CreateSearchBox = ns.UI_CreateSearchBox

    if not parent._storageSearchBox then
        parent._storageSearchBox = CreateSearchBox(headerParent, width, (ns.L and ns.L["STORAGE_SEARCH"]) or "Search storage...", function(text)
            SearchStateManager:SetSearchQuery("storage", text)
            local resultsContainer = parent.storageResultsContainer
            if resultsContainer then
                SearchResultsRenderer:PrepareContainer(resultsContainer)
                local contentWidth = parent:GetWidth() - 20
                local contentHeight = self:DrawStorageResults(resultsContainer, 0, contentWidth, text)
                resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
            end
        end, 0.4, storageSearchText)
    end

    local searchBox = parent._storageSearchBox
    if searchBox:GetParent() ~= headerParent then
        searchBox:SetParent(headerParent)
    end
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    searchBox:Show()

    headerYOffset = headerYOffset + 32 + GetLayout().afterElement

    -- Set fixedHeader height so scroll area starts below it
    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    -- ===== RESULTS CONTAINER (in scroll area) =====
    if not parent._storageResultsContainer then
        parent._storageResultsContainer = CreateResultsContainer(parent, 8, SIDE_MARGIN)
    end
    local resultsContainer = parent._storageResultsContainer
    if resultsContainer:GetParent() ~= parent then
        resultsContainer:SetParent(parent)
    end
    resultsContainer:ClearAllPoints()
    resultsContainer:SetPoint("TOPLEFT", SIDE_MARGIN, -8)
    resultsContainer:SetPoint("TOPRIGHT", -SIDE_MARGIN, -8)
    resultsContainer:SetHeight(1)
    resultsContainer:Show()
    parent.storageResultsContainer = resultsContainer
    
    local contentHeight = self:DrawStorageResults(resultsContainer, 0, width, storageSearchText)
    resultsContainer:SetHeight(math.max(contentHeight, 1))
    
    return 8 + contentHeight
end

--============================================================================
-- STORAGE RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawStorageResults(parent, yOffset, width, storageSearchText)
    -- Clean up old non-virtual children (headers, cards) from previous render.
    -- VLM handles its own _isVirtualRow frames; we only need to recycle stale headers.
    local recycleBin = ns.UI_RecycleBin
    local oldChildren = {parent:GetChildren()}
    for i = 1, #oldChildren do
        local child = oldChildren[i]
        if not child._isVirtualRow then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end

    local indent = BASE_INDENT
    local flatList = {}
    local globalRowIdxAll = 0
    self.recentlyExpanded = self.recentlyExpanded or {}
    
    -- Get expanded state
    local expanded = self.db.profile.storageExpanded or {}
    if not expanded.categories then expanded.categories = {} end
    
    -- Toggle function
    local function ToggleExpand(key, isExpanded)
-- If isExpanded is boolean, use it directly (new callback style)
        -- If isExpanded is nil, toggle manually (old callback style for backwards compat)
        if type(isExpanded) == "boolean" then
            if key == "warband" or key == "personal" or key == "guild" then
                expanded[key] = isExpanded
                if isExpanded then self.recentlyExpanded[key] = GetTime() end
            else
                expanded.categories[key] = isExpanded
                if isExpanded then self.recentlyExpanded[key] = GetTime() end
            end
        else
            if key == "warband" or key == "personal" or key == "guild" then
                expanded[key] = not expanded[key]
                isExpanded = expanded[key]
            else
                expanded.categories[key] = not expanded.categories[key]
                isExpanded = expanded.categories[key]
            end
        end

        self._storageExpandedKey = isExpanded and key or nil
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
        -- Scan Warband Bank (NEW ItemsCacheService API)
        local warbandData = self:GetWarbandBankData()
        if warbandData and warbandData.items then
            for _, item in ipairs(warbandData.items) do
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
        
        -- Scan Personal Items (Bank + Bags) (NEW ItemsCacheService API)
        -- Direct DB access (DB-First pattern)
        local allCharacters = self:GetAllCharacters() or {}
        local characters = {}
        for _, char in ipairs(allCharacters) do
            if char.isTracked ~= false then  -- Only tracked characters
                table.insert(characters, char)
            end
        end
        
        for _, char in ipairs(characters) do
            local charKey = char._key
            local itemsData = self:GetItemsData(charKey)
            if itemsData then
                -- Scan bags
                if itemsData.bags then
                    for _, item in ipairs(itemsData.bags) do
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
                
                -- Scan bank
                if itemsData.bank then
                    for _, item in ipairs(itemsData.bank) do
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
        
        -- Scan ALL cached Guild Banks
        if self.db and self.db.global and self.db.global.guildBank then
            for guildName, guildData in pairs(self.db.global.guildBank) do
                if guildData and guildData.tabs then
                    local guildKey = "guild_" .. guildName:gsub("[^%w]", "_")
                    
                    for tabIndex, tabData in pairs(guildData.tabs) do
                        if tabData.items then
                            for slotID, itemData in pairs(tabData.items) do
                                if itemData.itemID and ItemMatchesSearch(itemData) then
                                    local classID = itemData.classID or GetItemClassID(itemData.itemID)
                                    local typeName = GetItemTypeName(classID)
                                    local categoryKey = guildKey .. "_" .. typeName
                                    categoriesWithMatches[categoryKey] = true
                                    categoriesWithMatches[guildKey] = true
                                    hasAnyMatches = true
                                end
                            end
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
    
    -- Quick check for general "no data" empty state (when no search is active)
    if not storageSearchText or storageSearchText == "" then
        -- Check if there's any data at all
        local hasAnyData = false
        
        -- Check warband bank
        local warbandData = self:GetWarbandBankData()
        if warbandData and warbandData.items and #warbandData.items > 0 then
            hasAnyData = true
        end
        
        -- Check personal items if warband is empty
        if not hasAnyData then
            local allCharacters = self:GetAllCharacters() or {}
            for _, char in ipairs(allCharacters) do
                if char.isTracked ~= false then
                    local charKey = char._key
                    local itemsData = self:GetItemsData(charKey)
                    if itemsData then
                        if (itemsData.bags and #itemsData.bags > 0) or (itemsData.bank and #itemsData.bank > 0) then
                            hasAnyData = true
                            break
                        end
                    end
                end
            end
        end
        
        -- Check all cached guild banks if still empty
        if not hasAnyData then
            if self.db and self.db.global and self.db.global.guildBank then
                for guildName, guildData in pairs(self.db.global.guildBank) do
                    if guildData and guildData.tabs then
                        for tabIndex, tabData in pairs(guildData.tabs) do
                            if tabData.items and next(tabData.items) then
                                hasAnyData = true
                                break
                            end
                        end
                        if hasAnyData then break end
                    end
                end
            end
        end
        
        -- If no data at all, show empty state
        if not hasAnyData then
            local _, height = CreateEmptyStateCard(parent, "storage", yOffset)
            -- Update SearchStateManager with result count
            SearchStateManager:UpdateResults("storage", 0)
            return height
        end
    end
    
    -- ===== PERSONAL BANKS SECTION =====
    -- Count total matches in personal section (for search filtering)
    local personalTotalMatches = 0
    
    -- DB-First: Use GetAllCharacters() for direct DB access (tracked only)
    local allCharacters = self:GetAllCharacters() or {}
    local characters = {}
    for _, char in ipairs(allCharacters) do
        if char.isTracked ~= false then  -- Only tracked characters
            table.insert(characters, char)
        end
    end
    
    if storageSearchText and storageSearchText ~= "" then
        for _, char in ipairs(characters) do
            local charKey = char._key
            local itemsData = self:GetItemsData(charKey)  -- NEW ItemsCacheService API
            if itemsData then
                -- Count bags
                if itemsData.bags then
                    for _, item in ipairs(itemsData.bags) do
                        if ItemMatchesSearch(item) then
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
                -- Count bank
                if itemsData.bank then
                    for _, item in ipairs(itemsData.bank) do
                        if ItemMatchesSearch(item) then
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
            end
        end
    else
        -- No search active, count all items
        for _, char in ipairs(characters) do
            local charKey = char._key
            local itemsData = self:GetItemsData(charKey)  -- NEW ItemsCacheService API
            if itemsData then
                -- Count all bags and bank items
                personalTotalMatches = personalTotalMatches + (itemsData.bags and #itemsData.bags or 0)
                personalTotalMatches = personalTotalMatches + (itemsData.bank and #itemsData.bank or 0)
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
            (ns.L and ns.L["PERSONAL_ITEMS"]) or "Personal Items",
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
        -- Iterate through each character
        local hasAnyPersonalItems = false
        
        -- Direct DB access (DB-First pattern) (tracked only)
        local allCharacters = self:GetAllCharacters() or {}
        local characters = {}
        for _, char in ipairs(allCharacters) do
            if char.isTracked ~= false then  -- Only tracked characters
                table.insert(characters, char)
            end
        end
        
        -- Sort Characters
        local sortMode = self.db.profile.storageSort and self.db.profile.storageSort.key
        if sortMode and sortMode ~= "manual" then
            table.sort(characters, function(a, b)
                if sortMode == "name" then
                    return (a.name or ""):lower() < (b.name or ""):lower()
                elseif sortMode == "level" then
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return (a.name or ""):lower() < (b.name or ""):lower()
                elseif sortMode == "ilvl" then
                    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
                    return (a.name or ""):lower() < (b.name or ""):lower()
                elseif sortMode == "gold" then
                    local goldA = ns.Utilities:GetCharTotalCopper(a)
                    local goldB = ns.Utilities:GetCharTotalCopper(b)
                    if goldA ~= goldB then return goldA > goldB end
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
                return (a.level or 0) > (b.level or 0)
            end)
        else
            -- Manual order or default
            local customOrder = self.db.profile.characterOrder and self.db.profile.characterOrder.regular or {}
            if #customOrder > 0 then
                local ordered, charMap = {}, {}
                for _, c in ipairs(characters) do
                    local ck = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(c.name, c.realm)
                    if ck then charMap[ck] = c end
                end
                for _, ck in ipairs(customOrder) do
                    if charMap[ck] then table.insert(ordered, charMap[ck]); charMap[ck] = nil end
                end
                local remaining = {}
                for _, c in pairs(charMap) do table.insert(remaining, c) end
                table.sort(remaining, function(a, b)
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end)
                for _, c in ipairs(remaining) do table.insert(ordered, c) end
                characters = ordered
            else
                table.sort(characters, function(a, b)
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end)
            end
        end
        
        for _, char in ipairs(characters) do
            local charKey = char._key
local itemsData = self:GetItemsData(charKey)  -- NEW ItemsCacheService API
            if itemsData and (itemsData.bags or itemsData.bank) then
                -- Extract name and realm from character data
                local charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
                local charRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
                
                -- Apply class color
                local classColor = RAID_CLASS_COLORS[char.classFile or char.class] or {r=1, g=1, b=1}
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
                    -- Default to true if never set (first time)
                    if isCharExpanded == nil then
                        isCharExpanded = true
                        expanded.categories[charCategoryKey] = true
                    end
                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if char.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. char.classFile
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
-- Group character's items by type (NEW: Array-based iteration)
                    local charItems = {}
                    
                    -- Process bags
                    if itemsData.bags then
                        for _, item in ipairs(itemsData.bags) do
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
                    
                    -- Process bank
                    if itemsData.bank then
                        for _, item in ipairs(itemsData.bank) do
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
                            -- Default to true if never set (first time)
                            if isTypeExpanded == nil then
                                isTypeExpanded = true
                                expanded.categories[typeKey] = true
                            end
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
                            yOffset = yOffset + GetLayout().HEADER_HEIGHT  -- Type header (no extra spacing before rows)
if isTypeExpanded then
-- Display items (with search filter)
                                    for _, item in ipairs(charItems[typeName]) do
                                    -- Apply search filter
                                    local shouldShow = ItemMatchesSearch(item)
                                    
                                    if shouldShow then
                                        globalRowIdxAll = globalRowIdxAll + 1
                                        local locText = ""
                                        if item.actualBagID then
                                            if item.actualBagID == -1 then
                                                locText = (ns.L and ns.L["CHARACTER_BANK"]) or "Bank"
                                            elseif item.actualBagID >= 0 and item.actualBagID <= 5 then
                                                locText = format((ns.L and ns.L["BAG_FORMAT"]) or "Bag %d", item.actualBagID)
                                            else
                                                locText = format((ns.L and ns.L["BANK_BAG_FORMAT"]) or "Bank Bag %d", item.actualBagID - 5)
                                            end
                                        end
                                        flatList[#flatList + 1] = {
                                            type = "row",
                                            yOffset = yOffset,
                                            height = ROW_HEIGHT + GetLayout().betweenRows,
                                            xOffset = BASE_INDENT * 2,
                                            data = item,
                                            rowIdx = globalRowIdxAll,
                                            rowWidth = width - BASE_INDENT * 2,
                                            locText = locText,
                                            sectionKey = typeKey,
                                        }
                                        yOffset = yOffset + ROW_HEIGHT + GetLayout().betweenRows
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
        end  -- if itemsData
        end  -- for char
            
        -- No section-level empty state needed
        end  -- if personalExpanded
    end  -- if personalTotalMatches > 0
    
    -- ===== WARBAND BANK SECTION =====
    -- Group warband items by type FIRST (to check if section has content)
    local warbandItems = {}
    local warbandData = self:GetWarbandBankData()  -- NEW ItemsCacheService API
    
    if warbandData and warbandData.items then
        for _, item in ipairs(warbandData.items) do
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
            (ns.L and ns.L["STORAGE_WARBAND_BANK"]) or "Warband Bank",
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
        
        -- Draw each type category
        for _, typeName in ipairs(sortedTypes) do
            local categoryKey = "warband_" .. typeName
            
            -- Skip category if search active and no matches
            if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[categoryKey] then
                -- Skip this category
            else
                -- Auto-expand if search has matches in this category
                local isTypeExpanded = self.storageExpandAllActive or expanded.categories[categoryKey]
                -- Default to true if never set (first time)
                if isTypeExpanded == nil then
                    isTypeExpanded = true
                    expanded.categories[categoryKey] = true
                end
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
                    yOffset = yOffset + GetLayout().HEADER_HEIGHT  -- Type header (no extra spacing before rows)
                    
                    if isTypeExpanded then
                        -- Display items in this category (with search filter)
                        for _, item in ipairs(warbandItems[typeName]) do
                        -- Apply search filter
                        local shouldShow = ItemMatchesSearch(item)
                        
                        if shouldShow then
                            globalRowIdxAll = globalRowIdxAll + 1
                            local locText = item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex) or ""
                            flatList[#flatList + 1] = {
                                type = "row",
                                yOffset = yOffset,
                                height = ROW_HEIGHT + GetLayout().betweenRows,
                                xOffset = BASE_INDENT,
                                data = item,
                                rowIdx = globalRowIdxAll,
                                rowWidth = width - BASE_INDENT,
                                locText = locText,
                                sectionKey = categoryKey,
                            }
                            yOffset = yOffset + ROW_HEIGHT + GetLayout().betweenRows
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
    
    -- ===== GUILD BANK SECTION =====
    -- Show ALL cached guild banks (not just current character's guild)
    -- This allows viewing guild bank data from other characters
    
    -- Collect all guild bank items from all cached guilds
    local allGuildItems = {}  -- Format: { [guildName] = { [typeName] = {items} } }
    
    if self.db and self.db.global and self.db.global.guildBank then
        for guildName, guildData in pairs(self.db.global.guildBank) do
            if guildData and guildData.tabs then
                if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
                    _G.print("[StorageUI] Found cached guild bank:", guildName)
                end
                
                -- Flatten all items from all tabs for this guild
                local guildItems = {}
                for tabIndex, tabData in pairs(guildData.tabs) do
                    if tabData.items then
                        for slotID, itemData in pairs(tabData.items) do
                            if itemData.itemID then
                                -- Copy item data and add metadata
                                local item = {}
                                for k, v in pairs(itemData) do
                                    item[k] = v
                                end
                                item.tabIndex = tabIndex
                                item.slotID = slotID
                                item.source = "guild"
                                item.tabName = tabData.name
                                item.guildName = guildName  -- Track which guild this belongs to
                                
                                -- Use stored classID or get it from API
                                local classID = item.classID or GetItemClassID(item.itemID)
                                local typeName = GetItemTypeName(classID)
                                
                                if not guildItems[typeName] then
                                    guildItems[typeName] = {}
                                end
                                -- Store classID in item for icon lookup
                                if not item.classID then
                                    item.classID = classID
                                end
                                table.insert(guildItems[typeName], item)
                                
                                if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
                                    _G.print("[StorageUI] Item", item.itemID, "from", guildName, "-> typeName:", typeName)
                                end
                            end
                        end
                    end
                end
                
                -- Store this guild's items
                if next(guildItems) then
                    allGuildItems[guildName] = guildItems
                end
            end
        end
    end
    
    -- Count total matches across all guilds
    local guildTotalMatches = 0
    if storageSearchText and storageSearchText ~= "" then
        for guildName, guildItems in pairs(allGuildItems) do
            for typeName, items in pairs(guildItems) do
                for _, item in ipairs(items) do
                    if ItemMatchesSearch(item) then
                        guildTotalMatches = guildTotalMatches + 1
                    end
                end
            end
        end
    else
        -- No search active, count all items
        for guildName, guildItems in pairs(allGuildItems) do
            for typeName, items in pairs(guildItems) do
                guildTotalMatches = guildTotalMatches + #items
            end
        end
    end
    
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print("[StorageUI] Total guild bank items:", guildTotalMatches, "from", (function()
            local count = 0
            for _ in pairs(allGuildItems) do count = count + 1 end
            return count
        end)(), "guilds")
    end
    
    -- Render each guild's bank separately
    for guildName, guildItems in pairs(allGuildItems) do
        -- Create unique key for each guild
        local guildKey = "guild_" .. guildName:gsub("[^%w]", "_")  -- Sanitize guild name for key
        
        -- Count matches for this specific guild
        local guildMatches = 0
        if storageSearchText and storageSearchText ~= "" then
            for typeName, items in pairs(guildItems) do
                for _, item in ipairs(items) do
                    if ItemMatchesSearch(item) then
                        guildMatches = guildMatches + 1
                    end
                end
            end
        else
            -- No search active, count all items
            for typeName, items in pairs(guildItems) do
                guildMatches = guildMatches + #items
            end
        end
        
        -- Skip this guild if no matches
        if guildMatches > 0 then
            -- Auto-expand if search has matches in this guild
            local guildExpanded = self.storageExpandAllActive or expanded.categories[guildKey]
            -- Default to true if never set (first time)
            if guildExpanded == nil then
                guildExpanded = true
                expanded.categories[guildKey] = true
            end
            if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[guildKey] then
                guildExpanded = true
            end
            
            -- Create header with guild name
            local guildHeaderText = string.format("%s (%s)", 
                (ns.L and ns.L["ITEMS_GUILD_BANK"]) or "Guild Bank",
                guildName)
            
            local guildHeader, expandBtn, guildIcon = CreateCollapsibleHeader(
                parent,
                guildHeaderText,
                guildKey,
                guildExpanded,
                function(isExpanded) ToggleExpand(guildKey, isExpanded) end,
                "dummy"  -- Dummy value to trigger icon creation
            )
            guildHeader:SetPoint("TOPLEFT", 0, -yOffset)
            guildHeader:SetWidth(width)  -- Set width to match content area
            
            -- Replace with Guild Bank icon (using Atlas)
            if guildIcon then
                guildIcon:SetTexture(nil)  -- Clear dummy texture
                guildIcon:SetAtlas("poi-workorders")  -- Guild bank-style icon
                guildIcon:SetSize(24, 24)
            end
            
            yOffset = yOffset + HEADER_SPACING  -- Header + spacing before content
        
        if guildExpanded then
            -- Sort types alphabetically
            local sortedTypes = {}
            for typeName in pairs(guildItems) do
                -- Only include types that have matching items
                local hasMatchingItems = false
                if storageSearchText and storageSearchText ~= "" then
                    for _, item in ipairs(guildItems[typeName]) do
                        if ItemMatchesSearch(item) then
                            hasMatchingItems = true
                            break
                        end
                    end
                else
                    hasMatchingItems = #guildItems[typeName] > 0
                end
                
                if hasMatchingItems then
                    table.insert(sortedTypes, typeName)
                end
            end
            table.sort(sortedTypes)
            
            -- Draw each type category for this guild
            for _, typeName in ipairs(sortedTypes) do
                local categoryKey = guildKey .. "_" .. typeName  -- Changed: unique per guild
                
                -- Skip category if search active and no matches
                if storageSearchText and storageSearchText ~= "" and not categoriesWithMatches[categoryKey] then
                    -- Skip this category
                else
                    -- Auto-expand if search has matches in this category
                    local isTypeExpanded = self.storageExpandAllActive or expanded.categories[categoryKey]
                    -- Default to true if never set (first time)
                    if isTypeExpanded == nil then
                        isTypeExpanded = true
                        expanded.categories[categoryKey] = true
                    end
                    if storageSearchText and storageSearchText ~= "" and categoriesWithMatches[categoryKey] then
                        isTypeExpanded = true
                    end
                    
                    -- Count items that match search (for display)
                    local matchCount = 0
                    for _, item in ipairs(guildItems[typeName]) do
                        if ItemMatchesSearch(item) then
                            matchCount = matchCount + 1
                        end
                    end
                    
                    -- Calculate display count
                    local displayCount = (storageSearchText and storageSearchText ~= "") and matchCount or #guildItems[typeName]
                    
                    -- Skip header if it has no items to show
                    if displayCount == 0 then
                        -- Skip this empty header
                    else
                        -- Get icon from first item in category
                        local typeIcon = nil
                        if guildItems[typeName][1] and guildItems[typeName][1].classID then
                            typeIcon = GetTypeIcon(guildItems[typeName][1].classID)
                        end
                        
                        -- Type header (indented under guild) - show match count if searching
                        local typeHeader, typeBtn = CreateCollapsibleHeader(
                            parent,
                            typeName .. " (" .. FormatNumber(displayCount) .. ")",
                            categoryKey,
                            isTypeExpanded,
                            function(isExpanded) ToggleExpand(categoryKey, isExpanded) end,
                            typeIcon,
                            false,  -- isAtlas = false (item icons are texture paths)
                            1       -- indentLevel = 1 (child of guild header)
                        )
                        typeHeader:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)  -- Subheader at BASE_INDENT (15px)
                        typeHeader:SetWidth(width - BASE_INDENT)
                        yOffset = yOffset + GetLayout().HEADER_HEIGHT  -- Type header (no extra spacing before rows)
                        
                        if isTypeExpanded then
                            -- Display items in this category (with search filter)
                            for _, item in ipairs(guildItems[typeName]) do
                                -- Apply search filter
                                local shouldShow = ItemMatchesSearch(item)
                                
                                if shouldShow then
                                    globalRowIdxAll = globalRowIdxAll + 1
                                    local locText = item.tabName or (item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex)) or ""
                                    flatList[#flatList + 1] = {
                                        type = "row",
                                        yOffset = yOffset,
                                        height = ROW_HEIGHT + GetLayout().betweenRows,
                                        xOffset = BASE_INDENT,
                                        data = item,
                                        rowIdx = globalRowIdxAll,
                                        rowWidth = width - BASE_INDENT,
                                        locText = locText,
                                        sectionKey = categoryKey,
                                    }
                                    yOffset = yOffset + ROW_HEIGHT + GetLayout().betweenRows
                                end
                            end
                        end
                        
                        -- Add spacing after each type section
                        yOffset = yOffset + SECTION_SPACING
                    end  -- if displayCount > 0
                end  -- if not skipped by search
            end  -- for typeName
        end  -- if guildExpanded
        end  -- if guildMatches > 0
    end  -- for guildName (all guilds loop)
    
    -- Virtual scroll setup
    local mainFrame = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local VLM = ns.VirtualListModule

    if mainFrame and VLM and #flatList > 0 then
        local function PopulateStorageRow(row, item, entry)
            row:SetAlpha(1)
            if row.anim then row.anim:Stop() end
            ns.UI.Factory:ApplyRowBackground(row, entry.rowIdx)
            
            row.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
            row.icon:SetTexture(item.iconFileID or 134400)
            
            local nameWidth = entry.rowWidth - 350
            row.nameText:SetWidth(nameWidth)
            
            local baseName = item.name
            if not baseName and item.link then
                baseName = item.link:match("%[(.-)%]")
            end
            if not baseName and item.pending then
                baseName = (ns.L and ns.L["ITEM_LOADING_NAME"]) or "Loading..."
            end
            if not baseName and item.itemID then
                baseName = C_Item.GetItemInfo(item.itemID)
            end
            baseName = baseName or format((ns.L and ns.L["ITEM_FALLBACK_FORMAT"]) or "Item %s", tostring(item.itemID or "?"))
            
            local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
            if item.pending then
                row.nameText:SetText(format("|cff888888%s|r", displayName))
            else
                row.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
            end
            
            row.locationText:SetWidth(0)
            row.locationText:SetText(entry.locText or "")
            row.locationText:SetTextColor(1, 1, 1)
            row.locationText:SetWordWrap(false)
            row.locationText:SetNonSpaceWrap(false)
            
            row:SetScript("OnEnter", function(self)
                if not ShowTooltip then
                    if item.itemLink then
                        ns.TooltipService:Show(self, { type = "item", itemID = item.itemID, itemLink = item.itemLink })
                    end
                    return
                end
                ShowTooltip(self, { type = "item", itemID = item.itemID, itemLink = item.itemLink, anchor = "ANCHOR_LEFT" })
            end)
            row:SetScript("OnLeave", function()
                if HideTooltip then HideTooltip() else ns.TooltipService:Hide() end
            end)
        end
        
        local totalHeight = VLM.SetupVirtualList(mainFrame, parent, 0, flatList, {
            createRowFn = function(container, entry)
                local row = AcquireStorageRow(container, entry.rowWidth, ROW_HEIGHT)
                PopulateStorageRow(row, entry.data, entry)
                return row
            end,
            releaseRowFn = function(frame)
                ReleaseStorageRow(frame)
            end,
        })
        
        return math.max(totalHeight, yOffset) + GetLayout().minBottomSpacing
    end

    -- Nothing to virtualize (all collapsed / filtered out):
    -- ensure stale virtual rows from previous render are removed.
    if mainFrame and VLM then
        VLM.ClearVirtualScroll(mainFrame)
    end
    local recycleBin = ns.UI_RecycleBin
    local remainingChildren = { parent:GetChildren() }
    for i = 1, #remainingChildren do
        local child = remainingChildren[i]
        if child and child._isVirtualRow then
            child._isVirtualRow = nil
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end

    return yOffset + GetLayout().minBottomSpacing
end -- DrawStorageResults

