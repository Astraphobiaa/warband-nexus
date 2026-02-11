--[[
    Warband Nexus - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
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

-- Feature Flags
local ENABLE_GUILD_BANK = false -- Set to true when ready to enable Guild Bank features

-- Import shared UI components (always get fresh reference)
local COLORS = ns.UI_COLORS
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local GetTypeIcon = ns.UI_GetTypeIcon
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateStatsBar = ns.UI_CreateStatsBar
local CreateResultsContainer = ns.UI_CreateResultsContainer
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local FormatNumber = ns.UI_FormatNumber

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
local ROW_COLOR_EVEN = GetLayout().ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = GetLayout().ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

-- Performance: Local function references
local format = string.format
local date = date

-- Module-level state (shared with main UI.lua via namespace)
-- State is accessed via ns.UI_GetItemsSubTab(), SearchStateManager, etc.

--============================================================================
-- EVENT LISTENERS (Real-time Updates)
--============================================================================

local function RegisterItemsEvents(parent)
    if parent.itemsUpdateHandler then
        return  -- Already registered
    end
    parent.itemsUpdateHandler = true
    
    -- Debug print helper
    local function DebugPrint(...)
        if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
            _G.print(...)
        end
    end
    
    -- Debounced DrawItemList: coalesces rapid WN_ITEMS_UPDATED + WN_ITEM_METADATA_READY
    -- into a single redraw (e.g., bank open fires both within milliseconds)
    local pendingDrawTimer = nil
    local DRAW_DEBOUNCE = 0.1  -- 100ms coalesce window
    
    local function ScheduleDrawItemList()
        if not parent or not parent:IsVisible() then return end
        if pendingDrawTimer then return end  -- already scheduled
        pendingDrawTimer = C_Timer.After(DRAW_DEBOUNCE, function()
            pendingDrawTimer = nil
            if parent and parent:IsVisible() then
                WarbandNexus:DrawItemList(parent)
            end
        end)
    end
    
    -- Real-time item update event (BAG_UPDATE, BANK_UPDATE, etc.)
    WarbandNexus:RegisterMessage("WN_ITEMS_UPDATED", function(event, data)
        -- Only process if Items tab is visible
        if parent and parent:IsVisible() then
            DebugPrint("|cff00ff00[ItemsUI]|r WN_ITEMS_UPDATED received:", data and data.type or "unknown")
            ScheduleDrawItemList()
        end
    end)
    
    -- Async item metadata resolution (items that were "Loading..." now have real names)
    WarbandNexus:RegisterMessage("WN_ITEM_METADATA_READY", function()
        if parent and parent:IsVisible() then
            DebugPrint("|cff00ff00[ItemsUI]|r WN_ITEM_METADATA_READY received, refreshing names")
            ScheduleDrawItemList()
        end
    end)
    
    DebugPrint("|cff9370DB[ItemsUI]|r Event listeners registered: WN_ITEMS_UPDATED, WN_ITEM_METADATA_READY")
end

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    -- Register event listeners (only once)
    RegisterItemsEvents(parent)
    self.recentlyExpanded = self.recentlyExpanded or {}
    local yOffset = 8 -- Top padding for consistency with other tabs
    local width = parent:GetWidth() - 20 -- Match header padding (10 left + 10 right)
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    HideEmptyStateCard(parent, "items")
    
    -- PERFORMANCE: Release pooled frames back to pool before redrawing
    ReleaseAllPooledChildren(parent)
    
    -- ===== HEADER CARD (Always shown) =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("items"))
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    -- Use factory pattern positioning for standardized header layout
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["ITEMS_HEADER"]) or "Bank Items") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["ITEMS_SUBTITLE"]) or "Browse your Warband Bank and Personal Items (Bank + Inventory)"
    
    -- Create container for text group (using Factory pattern)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
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
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled - show beautiful disabled state card
    if not ns.Utilities:IsModuleEnabled("items") then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (ns.L and ns.L["ITEMS_DISABLED_TITLE"]) or "Warband Bank Items")
        return yOffset + cardHeight
    end
    
    -- ===== LOADING STATE (INITIAL SCAN) =====
    if ns.ItemsLoadingState and ns.ItemsLoadingState.isLoading then
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                ns.ItemsLoadingState,
                (ns.L and ns.L["ITEMS_LOADING"]) or "Loading Inventory Data"
            )
            return newYOffset  -- STOP HERE - don't render anything else
        end
    end
    
    -- Get state from namespace (managed by main UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = SearchStateManager:GetQuery("items")
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- ===== SUB-TAB BUTTONS (using Factory pattern) =====
    local tabFrame = ns.UI.Factory:CreateContainer(parent)
    tabFrame:SetHeight(32)
    tabFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    tabFrame:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Get theme colors
    local tabActiveColor = COLORS.tabActive
    local tabInactiveColor = COLORS.tabInactive
    local accentColor = COLORS.accent
    
    -- PERSONAL BANK BUTTON (using Factory pattern)
    local DEFAULT_SUBTAB_WIDTH = 130
    local personalBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
    personalBtn:SetPoint("LEFT", 0, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(personalBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply highlight effect (safe check for Factory)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(personalBtn)
    end
    
    local personalText = FontManager:CreateFontString(personalBtn, "body", "OVERLAY")
    personalText:SetPoint("CENTER")
    personalText:SetText((ns.L and ns.L["PERSONAL_ITEMS"]) or "Personal Items")
    personalText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    -- Auto-fit: expand if text is wider than default
    local pTextW = personalText:GetStringWidth() or 0
    if pTextW + 20 > DEFAULT_SUBTAB_WIDTH then
        personalBtn:SetWidth(pTextW + 20)
    end
    
    personalBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("personal")  -- Switch to Personal Items (Bank + Inventory)
        WarbandNexus:RefreshUI()
    end)
    
    -- WARBAND BANK BUTTON (using Factory pattern)
    local warbandBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(warbandBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply highlight effect (safe check for Factory)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(warbandBtn)
    end
    
    local warbandText = FontManager:CreateFontString(warbandBtn, "body", "OVERLAY")
    warbandText:SetPoint("CENTER")
    warbandText:SetText((ns.L and ns.L["ITEMS_WARBAND_BANK"]) or "Warband Bank")
    warbandText:SetTextColor(1, 1, 1)  -- Fixed white color
    
    -- Auto-fit: expand if text is wider than default
    local wTextW = warbandText:GetStringWidth() or 0
    if wTextW + 20 > DEFAULT_SUBTAB_WIDTH then
        warbandBtn:SetWidth(wTextW + 20)
    end
    
    warbandBtn:SetScript("OnClick", function()
        ns.UI_SetItemsSubTab("warband")  -- Switch to Warband Bank tab
        WarbandNexus:RefreshUI()
    end)
    
    -- GUILD BANK BUTTON (Third/Right) - DISABLED BY DEFAULT
    if ENABLE_GUILD_BANK then
        local guildBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
        guildBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
        
        -- No backdrop (naked frame)
        
        local guildText = FontManager:CreateFontString(guildBtn, "body", "OVERLAY")
        guildText:SetPoint("CENTER")
        guildText:SetText((ns.L and ns.L["ITEMS_GUILD_BANK"]) or "Guild Bank")
        guildText:SetTextColor(1, 1, 1)  -- Fixed white color
        
        -- Auto-fit: expand if text is wider than default
        local gTextW = guildText:GetStringWidth() or 0
        if gTextW + 20 > DEFAULT_SUBTAB_WIDTH then
            guildBtn:SetWidth(gTextW + 20)
        end
        
        -- Check if player is in a guild
        local isInGuild = IsInGuild()
        if not isInGuild then
            guildBtn:Disable()
            guildBtn:SetAlpha(0.5)
            guildText:SetTextColor(1, 1, 1)  -- White
        end
        
        guildBtn:SetScript("OnClick", function()
            if not isInGuild then
                WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["GUILD_BANK_REQUIRED"]) or "You must be in a guild to access Guild Bank.") .. "|r")
                return
            end
            ns.UI_SetItemsSubTab("guild")  -- Switch to Guild Bank tab
            WarbandNexus:RefreshUI()
        end)
        -- Hover effects removed (no backdrop)
    end -- ENABLE_GUILD_BANK
    
    -- Update tab button borders based on active state
    if UpdateBorderColor then
        if currentItemsSubTab == "personal" then
            -- Active state - full accent color
            UpdateBorderColor(personalBtn, {accentColor[1], accentColor[2], accentColor[3], 1})
            if personalBtn.SetBackdropColor then
                personalBtn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
            end
        else
            -- Inactive state - dimmed accent color
            UpdateBorderColor(personalBtn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1})
            if personalBtn.SetBackdropColor then
                personalBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            end
        end
        
        if currentItemsSubTab == "warband" then
            -- Active state - full accent color
            UpdateBorderColor(warbandBtn, {accentColor[1], accentColor[2], accentColor[3], 1})
            if warbandBtn.SetBackdropColor then
                warbandBtn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
            end
        else
            -- Inactive state - dimmed accent color
            UpdateBorderColor(warbandBtn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1})
            if warbandBtn.SetBackdropColor then
                warbandBtn:SetBackdropColor(0.12, 0.12, 0.15, 1)
            end
        end
    end
    
    -- ===== GOLD CONTROLS (Warband Bank ONLY) =====
    if currentItemsSubTab == "warband" then
        -- Gold display for Warband Bank
        local goldDisplay = FontManager:CreateFontString(tabFrame, "body", "OVERLAY")
        goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -10, 0)
        local warbandGold = ns.Utilities:GetWarbandBankMoney() or 0
        -- Use UI_FormatMoney for consistent formatting with icons
        local FormatMoney = ns.UI_FormatMoney
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(warbandGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(warbandGold))
        end
    end
    -- Personal Bank has no gold controls (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 32 + GetLayout().afterElement  -- Tab frame height + spacing
    
    -- ===== SEARCH BOX (Below sub-tabs) =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    -- Use SearchStateManager for state management
    local itemsSearchText = SearchStateManager:GetQuery("items")
    
    local searchBox = CreateSearchBox(parent, width, (ns.L and ns.L["ITEMS_SEARCH"]) or "Search items...", function(text)
        -- Update search state via SearchStateManager (throttled, event-driven)
        SearchStateManager:SetSearchQuery("items", text)
        
        -- Prepare container for rendering
        local resultsContainer = parent.resultsContainer
        if resultsContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
            
            -- Redraw results with new search text
            local contentHeight = WarbandNexus:DrawItemsResults(resultsContainer, 0, width, ns.UI_GetItemsSubTab(), text)
            
            -- Update state with result count
            resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
        end
    end, 0.4, itemsSearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + GetLayout().afterElement  -- Search box height + spacing
    
    -- ===== STATS BAR =====
    -- Get items for stats (before results container)
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    else
        items = self:GetPersonalBankItems() or {}
    end
    
    local statsBar, statsText = CreateStatsBar(parent, 24)
    statsBar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    statsBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    local bankStats = self:GetBankStatistics()
    
    if currentItemsSubTab == "warband" then
        local wb = bankStats.warband or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s/%s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cffa335ee" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(wb.usedSlots or 0), FormatNumber(wb.totalSlots or 0),
            (wb.lastScan or 0) > 0 and date("%H:%M", wb.lastScan) or neverText))
    elseif currentItemsSubTab == "guild" then
        local gb = bankStats.guild or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s/%s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cff00ff00" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(gb.usedSlots or 0), FormatNumber(gb.totalSlots or 0),
            (gb.lastScan or 0) > 0 and date("%H:%M", gb.lastScan) or neverText))
    else
        -- Personal Items = Bank + Inventory
        local pb = bankStats.personal or {}
        local bagsData = self.db.char.bags or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        local combinedUsed = (pb.usedSlots or 0) + (bagsData.usedSlots or 0)
        local combinedTotal = (pb.totalSlots or 0) + (bagsData.totalSlots or 0)
        local lastScan = math.max(pb.lastScan or 0, bagsData.lastScan or 0)
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s/%s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cff88ff88" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(combinedUsed), FormatNumber(combinedTotal),
            lastScan > 0 and date("%H:%M", lastScan) or neverText))
    end
    statsText:SetTextColor(1, 1, 1)  -- White (9/196 slots - Last updated)
    
    yOffset = yOffset + 24 + GetLayout().afterElement  -- Stats bar height + spacing
    
    -- ===== RESULTS CONTAINER (After stats bar) =====
    local resultsContainer = CreateResultsContainer(parent, yOffset, SIDE_MARGIN)
    parent.resultsContainer = resultsContainer  -- Store reference for search callback
    
    -- Initial draw of results
    local contentHeight = self:DrawItemsResults(resultsContainer, 0, width, currentItemsSubTab, itemsSearchText)
    
    -- CRITICAL FIX: Update container height AFTER content is drawn
    resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
    
    return yOffset + (contentHeight or 0)
end

--============================================================================
-- ITEMS RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawItemsResults(parent, yOffset, width, currentItemsSubTab, itemsSearchText)
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- Get items based on selected sub-tab
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    else
        -- Personal Items = Bank + Inventory combined
        items = self:GetPersonalBankItems() or {}
    end
    
    -- Apply search filter (Items tab specific)
    if itemsSearchText and itemsSearchText ~= "" then
        local filtered = {}
        for _, item in ipairs(items) do
            local itemName = (item.name or ""):lower()
            local itemLink = (item.itemLink or ""):lower()
            if itemName:find(itemsSearchText, 1, true) or itemLink:find(itemsSearchText, 1, true) then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end
    
    -- Sort items alphabetically by name
    table.sort(items, function(a, b)
        local nameA = (a.name or ""):lower()
        local nameB = (b.name or ""):lower()
        return nameA < nameB
    end)
    
    -- ===== EMPTY STATE =====
    if #items == 0 then
        -- If search is active, use SearchResultsRenderer for search-specific empty state
        if itemsSearchText and itemsSearchText ~= "" then
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, itemsSearchText, "items")
            -- Update SearchStateManager with result count
            SearchStateManager:UpdateResults("items", 0)
            return height
        else
            -- No items cached (general empty state) - use standardized factory
            local _, height = CreateEmptyStateCard(parent, "items", yOffset)
            -- Update SearchStateManager with result count
            SearchStateManager:UpdateResults("items", 0)
            return height
        end
    end
    
    -- Update SearchStateManager with result count (after filtering)
    SearchStateManager:UpdateResults("items", #items)
    
    -- ===== GROUP ITEMS BY TYPE =====
    local groups = {}
    local groupOrder = {}
    local hasSearchFilter = itemsSearchText and itemsSearchText ~= ""
    
    for _, item in ipairs(items) do
        local typeName = item.itemType or ((ns.L and ns.L["GROUP_MISC"]) or "Miscellaneous")
        if not groups[typeName] then
            local groupKey = currentItemsSubTab .. "_" .. typeName
            
            -- Auto-expand if search is active, otherwise use persisted state
            if hasSearchFilter then
                expandedGroups[groupKey] = true
            elseif expandedGroups[groupKey] == nil then
                expandedGroups[groupKey] = true
            end
            
            groups[typeName] = { name = typeName, items = {}, groupKey = groupKey }
            table.insert(groupOrder, typeName)
        end
        table.insert(groups[typeName].items, item)
    end
    
    -- Sort group names alphabetically
    table.sort(groupOrder)
    
    -- ===== DRAW GROUPS =====
    local rowIdx = 0
    for _, typeName in ipairs(groupOrder) do
        local group = groups[typeName]
        local isExpanded = self.itemsExpandAllActive or expandedGroups[group.groupKey]
        
        -- Get icon from first item in group
        local typeIcon = nil
        if group.items[1] and group.items[1].classID then
            typeIcon = GetTypeIcon(group.items[1].classID)
        end
        
        -- Toggle function for this group
        local gKey = group.groupKey
        local function ToggleGroup(key, isExpanded)
            -- Use isExpanded if provided (new style), otherwise toggle (old style)
            if type(isExpanded) == "boolean" then
                expandedGroups[key] = isExpanded
                if isExpanded then self.recentlyExpanded[key] = GetTime() end
            else
                expandedGroups[key] = not expandedGroups[key]
                if expandedGroups[key] then self.recentlyExpanded[key] = GetTime() end
            end
            WarbandNexus:RefreshUI()
        end
        
        -- Create collapsible header with purple border and icon
        local groupHeader, expandBtn = CreateCollapsibleHeader(
            parent,
            format("%s (%s)", typeName, FormatNumber(#group.items)),
            gKey,
            isExpanded,
            function(isExpanded) ToggleGroup(gKey, isExpanded) end,
            typeIcon
        )
        groupHeader:SetPoint("TOPLEFT", 0, -yOffset)
        groupHeader:SetWidth(width)  -- Set width to match content area
        
        yOffset = yOffset + GetLayout().HEADER_HEIGHT  -- Header (no extra spacing before rows)
        
        -- Draw items in this group (if expanded)
        if isExpanded then
            local shouldAnimate = self.recentlyExpanded[gKey] and (GetTime() - self.recentlyExpanded[gKey] < 0.5)
            local animIdx = 0
            
            for _, item in ipairs(group.items) do
                rowIdx = rowIdx + 1
                animIdx = animIdx + 1
                local i = rowIdx
                
                -- PERFORMANCE: Acquire from pool instead of creating new
                local row = AcquireItemRow(parent, width, ROW_HEIGHT)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -yOffset)  -- Items tab has NO subheaders, rows at 0px is correct
                
                -- Ensure alpha is reset (pooling safety)
                row:SetAlpha(1)
                
                -- Stop any previous animations
                if row.anim then row.anim:Stop() end
                
                -- Smart Animation
                if shouldAnimate then
                    row:SetAlpha(0)
                    
                    -- Reuse animation objects to prevent leaks
                    if not row.anim then
                        local anim = row:CreateAnimationGroup()
                        local fade = anim:CreateAnimation("Alpha")
                        fade:SetSmoothing("OUT")
                        anim:SetScript("OnFinished", function() row:SetAlpha(1) end)
                        
                        row.anim = anim
                        row.fade = fade
                    end
                    
                    row.fade:SetFromAlpha(0)
                    row.fade:SetToAlpha(1)
                    row.fade:SetDuration(0.15)
                    row.fade:SetStartDelay(animIdx * 0.05) -- Stagger relative to group start
                    
                    row.anim:Play()
                end
                row.idx = i
                
                -- Set alternating background colors
                local ROW_COLOR_EVEN = GetLayout().ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
                local ROW_COLOR_ODD = GetLayout().ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
                local bgColor = (animIdx % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
                
                if not row.bg then
                    row.bg = row:CreateTexture(nil, "BACKGROUND")
                    row.bg:SetAllPoints()
                end
                row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
                
                -- Update quantity
                row.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
                
                -- Update icon
                row.icon:SetTexture(item.iconFileID or 134400)
                
                -- Update name (with pet cage handling)
                local nameWidth = width - 200
                row.nameText:SetWidth(nameWidth)
                
                -- Get item name (pending items show "Loading..." until async resolves)
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
                
                -- Use GetItemDisplayName to handle caged pets (shows pet name instead of "Pet Cage")
                local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
                if item.pending then
                    row.nameText:SetText(format("|cff888888%s|r", displayName))
                else
                    row.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
                end
                
                -- Update location
                local locText = ""
                if currentItemsSubTab == "warband" then
                    locText = item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex) or ""
                else
                    -- Personal Items: distinguish between Bank and Inventory
                    if item.actualBagID then
                        if item.actualBagID == -1 then
                            locText = (ns.L and ns.L["CHARACTER_BANK"]) or "Bank"
                        elseif item.actualBagID >= 0 and item.actualBagID <= 5 then
                            locText = format((ns.L and ns.L["BAG_FORMAT"]) or "Bag %d", item.actualBagID)
                        else
                            locText = format((ns.L and ns.L["BANK_BAG_FORMAT"]) or "Bank Bag %d", item.actualBagID - 5)
                        end
                    end
                end
                row.locationText:SetText(locText)
                row.locationText:SetTextColor(1, 1, 1)  -- White
                
                -- Update hover/tooltip handlers (full item data via C_TooltipInfo)
                row:SetScript("OnEnter", function(self)
                    if not ShowTooltip then
                        return
                    end
                    
                    -- Build additional info lines (shown after Blizzard item data)
                    local additionalLines = {}
                    
                    -- Stack count
                    if item.stackCount and item.stackCount > 1 then
                        local stackLabel = (ns.L and ns.L["STACK_LABEL"]) or "Stack: "
                        table.insert(additionalLines, {text = stackLabel .. FormatNumber(item.stackCount), color = {1, 1, 1}})
                    end
                    
                    -- Location
                    if item.location then
                        local locationLabel = (ns.L and ns.L["LOCATION_LABEL"]) or "Location: "
                        table.insert(additionalLines, {text = locationLabel .. item.location, color = {0.7, 0.7, 0.7}})
                    end
                    
                    -- Item ID
                    local itemIdLabel = (ns.L and ns.L["ITEM_ID_LABEL"]) or "Item ID: "
                    local unknownText = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
                    table.insert(additionalLines, {text = itemIdLabel .. tostring(item.itemID or unknownText), color = {0.4, 0.8, 1}})
                    
                    table.insert(additionalLines, {type = "spacer"})
                    
                    -- Instructions
                    if WarbandNexus.bankIsOpen then
                        local rightClickMove = (ns.L and ns.L["RIGHT_CLICK_MOVE"]) or "Move to bag"
                        table.insert(additionalLines, {text = "|cff00ff00Right-Click|r " .. rightClickMove, color = {1, 1, 1}})
                        if item.stackCount and item.stackCount > 1 then
                            local shiftRightSplit = (ns.L and ns.L["SHIFT_RIGHT_CLICK_SPLIT"]) or "Split stack"
                            table.insert(additionalLines, {text = "|cff00ff00Shift+Right-Click|r " .. shiftRightSplit, color = {1, 1, 1}})
                        end
                        local leftClickPickup = (ns.L and ns.L["LEFT_CLICK_PICKUP"]) or "Pick up"
                        table.insert(additionalLines, {text = "|cff888888Left-Click|r " .. leftClickPickup, color = {0.7, 0.7, 0.7}})
                    else
                        local bankNotOpen = (ns.L and ns.L["ITEMS_BANK_NOT_OPEN"]) or "Bank not open"
                        table.insert(additionalLines, {text = "|cffff6600" .. bankNotOpen .. "|r", color = {1, 1, 1}})
                    end
                    local shiftLeftLink = (ns.L and ns.L["SHIFT_LEFT_CLICK_LINK"]) or "Link in chat"
                    table.insert(additionalLines, {text = "|cff888888Shift+Left-Click|r " .. shiftLeftLink, color = {0.7, 0.7, 0.7}})
                    
                    -- Show item tooltip (full data from C_TooltipInfo + our custom lines)
                    ShowTooltip(self, {
                        type = "item",
                        itemID = item.itemID,
                        itemLink = item.link,
                        additionalLines = additionalLines,
                        anchor = "ANCHOR_LEFT"
                    })
                end)
                row:SetScript("OnLeave", function(self)
                    if HideTooltip then
                        HideTooltip()
                    end
                end)
                
                -- Click handlers for item interaction (read-only: chat link only)
                row:SetScript("OnMouseUp", function(self, button)
                    -- Shift+Left-click: Link item in chat (safe, non-protected function)
                    if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
                        ChatEdit_InsertLink(item.itemLink)
                        return
                    end
                    
                    -- All other clicks: No action (read-only mode)
                    -- Item manipulation has been removed to prevent taint
                end)
                
                yOffset = yOffset + ROW_SPACING
            end  -- for item in group.items
        end  -- if group.expanded
        
        -- Add spacing after each group section
        yOffset = yOffset + SECTION_SPACING
    end  -- for typeName in groupOrder
    
    return yOffset + GetLayout().minBottomSpacing
end -- DrawItemsResults

