--[[
    Warband Nexus - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Unique AceEvent handler identity for ItemsUI
local ItemsUIEvents = {}

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Feature Flags (Guild Bank now always enabled)

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
local ReleaseItemRow = ns.UI_ReleaseItemRow
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
-- ROW_COLOR_EVEN/ODD: Now handled by Factory:ApplyRowBackground()

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
    
    -- Check if Items tab is actually the active tab (parent:IsVisible() is not enough
    -- because the scroll child is shared across all tabs and always visible)
    local function IsItemsTabActive()
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        return mf and mf:IsShown() and mf.currentTab == "items"
    end
    
    local function ScheduleDrawItemList()
        if not IsItemsTabActive() then return end
        if pendingDrawTimer then return end  -- already scheduled
        pendingDrawTimer = C_Timer.After(DRAW_DEBOUNCE, function()
            pendingDrawTimer = nil
            if IsItemsTabActive() and parent then
                WarbandNexus:DrawItemList(parent)
            end
        end)
    end
    
    -- WN_ITEMS_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- items tab refresh via PopulateContent → DrawItemList. Having both caused double rebuild.
    
    -- Async item metadata resolution (items that were "Loading..." now have real names)
    -- Keep: UI.lua does NOT handle WN_ITEM_METADATA_READY.
    WarbandNexus.RegisterMessage(ItemsUIEvents, "WN_ITEM_METADATA_READY", function()
        if IsItemsTabActive() then
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
    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local yOffset = 8
    local width = parent:GetWidth() - 20
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    HideEmptyStateCard(parent, "items")
    
    -- PERFORMANCE: Release pooled frames back to pool before redrawing
    ReleaseAllPooledChildren(parent)
    
    -- ===== HEADER CARD (in fixedHeader - non-scrolling) =====
    local titleCard = CreateCard(headerParent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("items"))
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local accentColor = COLORS.accent  -- Define accentColor for button usage
    
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
    
    -- ===== GOLD MANAGER BUTTON (Header - ALWAYS visible) =====
    local goldMgrBtn = ns.UI.Factory:CreateButton(titleCard, 100, 32)  -- Initial width, will auto-size
    goldMgrBtn:SetPoint("RIGHT", titleCard, "RIGHT", -12, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(goldMgrBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply highlight effect
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(goldMgrBtn)
    end
    
    -- Button text (no icon)
    local goldMgrText = FontManager:CreateFontString(goldMgrBtn, "body", "OVERLAY")
    goldMgrText:SetPoint("CENTER")
    goldMgrText:SetText((ns.L and ns.L["GOLD_MANAGER_BTN"]) or "Gold Target")
    goldMgrText:SetTextColor(1, 1, 1)
    goldMgrText:SetJustifyH("CENTER")
    goldMgrText:SetWordWrap(false)
    
    -- Auto-size button based on text width (with padding)
    C_Timer.After(0, function()
        if goldMgrText and goldMgrText:GetStringWidth() > 0 then
            local textWidth = goldMgrText:GetStringWidth()
            goldMgrBtn:SetWidth(textWidth + 24)  -- 12px padding each side
        end
    end)
    
    goldMgrBtn:SetScript("OnClick", function()
        if self.ShowGoldManagementPopup then
            self:ShowGoldManagementPopup()
        end
    end)

    -- ===== MONEY LOGS BUTTON (Left of Gold Target) =====
    local moneyLogsBtn = ns.UI.Factory:CreateButton(titleCard, 100, 32)
    moneyLogsBtn:SetPoint("RIGHT", goldMgrBtn, "LEFT", -8, 0)

    if ApplyVisuals then
        ApplyVisuals(moneyLogsBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end

    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(moneyLogsBtn)
    end

    local moneyLogsText = FontManager:CreateFontString(moneyLogsBtn, "body", "OVERLAY")
    moneyLogsText:SetPoint("CENTER")
    moneyLogsText:SetText((ns.L and ns.L["MONEY_LOGS_BTN"]) or "Money Logs")
    moneyLogsText:SetTextColor(1, 1, 1)
    moneyLogsText:SetJustifyH("CENTER")
    moneyLogsText:SetWordWrap(false)

    C_Timer.After(0, function()
        if moneyLogsText and moneyLogsText:GetStringWidth() > 0 then
            local textWidth = moneyLogsText:GetStringWidth()
            moneyLogsBtn:SetWidth(textWidth + 24)
        end
    end)

    moneyLogsBtn:SetScript("OnClick", function()
        if self.ShowCharacterBankMoneyLogPopup then
            self:ShowCharacterBankMoneyLogPopup()
        end
    end)
    
    titleCard:Show()
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled - show beautiful disabled state card
    if not ns.Utilities:IsModuleEnabled("items") then
        if fixedHeader then fixedHeader:SetHeight(yOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["ITEMS_DISABLED_TITLE"]) or "Warband Bank Items")
        return 8 + cardHeight
    end
    
    -- ===== LOADING STATE (INITIAL SCAN) =====
    if ns.ItemsLoadingState and ns.ItemsLoadingState.isLoading then
        if fixedHeader then fixedHeader:SetHeight(yOffset) end
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(parent, 8, ns.ItemsLoadingState, (ns.L and ns.L["ITEMS_LOADING"]) or "Loading Inventory Data")
            return newYOffset
        end
    end
    
    -- Get state from namespace (managed by main UI.lua)
    local currentItemsSubTab = ns.UI_GetItemsSubTab()
    local itemsSearchText = SearchStateManager:GetQuery("items")
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- ===== SUB-TAB BUTTONS (in fixedHeader - non-scrolling) =====
    local tabFrame = ns.UI.Factory:CreateContainer(headerParent)
    tabFrame:SetHeight(32)
    tabFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    tabFrame:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Get theme colors
    local tabActiveColor = COLORS.tabActive
    local tabInactiveColor = COLORS.tabInactive
    local accentColor = COLORS.accent
    
    local DEFAULT_SUBTAB_WIDTH = 130
    local tabButtons = {}  -- Store buttons for border updates
    
    -- INVENTORY BUTTON (First tab)
    local inventoryBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
    inventoryBtn:SetPoint("LEFT", 0, 0)
    
    if ApplyVisuals then
        ApplyVisuals(inventoryBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(inventoryBtn)
    end
    
    local inventoryText = FontManager:CreateFontString(inventoryBtn, "body", "OVERLAY")
    inventoryText:SetPoint("CENTER")
    inventoryText:SetText((ns.L and ns.L["CHARACTER_INVENTORY"]) or "Inventory")
    inventoryText:SetTextColor(1, 1, 1)
    
    local invTextW = inventoryText:GetStringWidth() or 0
    if invTextW + 20 > DEFAULT_SUBTAB_WIDTH then
        inventoryBtn:SetWidth(invTextW + 20)
    end
    
    inventoryBtn:SetScript("OnClick", function()
        if (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) == "inventory" then return end
        ns.UI_SetItemsSubTab("inventory")
        WarbandNexus:RefreshUI()
    end)
    local ab1 = inventoryBtn:CreateTexture(nil, "OVERLAY")
    ab1:SetHeight(3)
    ab1:SetPoint("BOTTOMLEFT", 8, 4)
    ab1:SetPoint("BOTTOMRIGHT", -8, 4)
    ab1:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
    ab1:SetAlpha(0)
    inventoryBtn.activeBar = ab1
    inventoryBtn._text = inventoryText
    tabButtons["inventory"] = inventoryBtn
    
    -- PERSONAL BANK BUTTON (Second tab)
    local personalBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
    personalBtn:SetPoint("LEFT", inventoryBtn, "RIGHT", 8, 0)
    
    if ApplyVisuals then
        ApplyVisuals(personalBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(personalBtn)
    end
    
    local personalText = FontManager:CreateFontString(personalBtn, "body", "OVERLAY")
    personalText:SetPoint("CENTER")
    personalText:SetText((ns.L and ns.L["CHARACTER_BANK"]) or "Personal Bank")
    personalText:SetTextColor(1, 1, 1)
    
    local pTextW = personalText:GetStringWidth() or 0
    if pTextW + 20 > DEFAULT_SUBTAB_WIDTH then
        personalBtn:SetWidth(pTextW + 20)
    end
    
    personalBtn:SetScript("OnClick", function()
        if (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) == "personal" then return end
        ns.UI_SetItemsSubTab("personal")
        WarbandNexus:RefreshUI()
    end)
    local ab2 = personalBtn:CreateTexture(nil, "OVERLAY")
    ab2:SetHeight(3)
    ab2:SetPoint("BOTTOMLEFT", 8, 4)
    ab2:SetPoint("BOTTOMRIGHT", -8, 4)
    ab2:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
    ab2:SetAlpha(0)
    personalBtn.activeBar = ab2
    personalBtn._text = personalText
    tabButtons["personal"] = personalBtn
    
    -- WARBAND BANK BUTTON (Third tab)
    local warbandBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
    warbandBtn:SetPoint("LEFT", personalBtn, "RIGHT", 8, 0)
    
    if ApplyVisuals then
        ApplyVisuals(warbandBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(warbandBtn)
    end
    
    local warbandText = FontManager:CreateFontString(warbandBtn, "body", "OVERLAY")
    warbandText:SetPoint("CENTER")
    warbandText:SetText((ns.L and ns.L["ITEMS_WARBAND_BANK"]) or "Warband Bank")
    warbandText:SetTextColor(1, 1, 1)
    
    local wTextW = warbandText:GetStringWidth() or 0
    if wTextW + 20 > DEFAULT_SUBTAB_WIDTH then
        warbandBtn:SetWidth(wTextW + 20)
    end
    
    warbandBtn:SetScript("OnClick", function()
        if (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) == "warband" then return end
        ns.UI_SetItemsSubTab("warband")
        WarbandNexus:RefreshUI()
    end)
    local ab3 = warbandBtn:CreateTexture(nil, "OVERLAY")
    ab3:SetHeight(3)
    ab3:SetPoint("BOTTOMLEFT", 8, 4)
    ab3:SetPoint("BOTTOMRIGHT", -8, 4)
    ab3:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
    ab3:SetAlpha(0)
    warbandBtn.activeBar = ab3
    warbandBtn._text = warbandText
    tabButtons["warband"] = warbandBtn
    
    -- GUILD BANK BUTTON (Fourth tab) - Always visible, disabled if not in guild
    local guildBtn = ns.UI.Factory:CreateButton(tabFrame, DEFAULT_SUBTAB_WIDTH, 28)
    guildBtn:SetPoint("LEFT", warbandBtn, "RIGHT", 8, 0)
    
    if ApplyVisuals then
        ApplyVisuals(guildBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(guildBtn)
    end
    
    local guildText = FontManager:CreateFontString(guildBtn, "body", "OVERLAY")
    guildText:SetPoint("CENTER")
    guildText:SetText((ns.L and ns.L["ITEMS_GUILD_BANK"]) or "Guild Bank")
    guildText:SetTextColor(1, 1, 1)
    
    local gTextW = guildText:GetStringWidth() or 0
    if gTextW + 20 > DEFAULT_SUBTAB_WIDTH then
        guildBtn:SetWidth(gTextW + 20)
    end
    
    -- Check if player is in a guild
    local isInGuild = IsInGuild()
    if not isInGuild then
        guildBtn:Disable()
        guildBtn:SetAlpha(0.5)
    end
    
    guildBtn:SetScript("OnClick", function()
        if not IsInGuild() then
            WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["GUILD_BANK_REQUIRED"]) or "You must be in a guild to access Guild Bank.") .. "|r")
            return
        end
        if (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) == "guild" then return end
        ns.UI_SetItemsSubTab("guild")
        WarbandNexus:RefreshUI()
    end)
    local ab4 = guildBtn:CreateTexture(nil, "OVERLAY")
    ab4:SetHeight(3)
    ab4:SetPoint("BOTTOMLEFT", 8, 4)
    ab4:SetPoint("BOTTOMRIGHT", -8, 4)
    ab4:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
    ab4:SetAlpha(0)
    guildBtn.activeBar = ab4
    guildBtn._text = guildText
    tabButtons["guild"] = guildBtn

    -- Sub-tab vurgusu: Collections/Plans ile aynı (activeBar + ApplyVisuals + metin rengi/outline)
    for tabKey, btn in pairs(tabButtons) do
        if currentItemsSubTab == tabKey then
            if btn.activeBar then btn.activeBar:SetAlpha(1) end
            if ApplyVisuals then
                ApplyVisuals(btn, {accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1}, {accentColor[1], accentColor[2], accentColor[3], 1})
            end
            if btn._text then
                btn._text:SetTextColor(1, 1, 1)
                local font, size = btn._text:GetFont()
                if font and size then btn._text:SetFont(font, size, "OUTLINE") end
            end
            if UpdateBorderColor then UpdateBorderColor(btn, {accentColor[1], accentColor[2], accentColor[3], 1}) end
        else
            if btn.activeBar then btn.activeBar:SetAlpha(0) end
            if ApplyVisuals then
                ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1})
            end
            if btn._text then
                btn._text:SetTextColor(0.7, 0.7, 0.7)
                local font, size = btn._text:GetFont()
                if font and size then btn._text:SetFont(font, size, "") end
            end
            if UpdateBorderColor then UpdateBorderColor(btn, {accentColor[1] * 0.6, accentColor[2] * 0.6, accentColor[3] * 0.6, 1}) end
        end
    end
    
    -- ===== GOLD DISPLAY (Per Sub-Tab) =====
    local goldDisplay = FontManager:CreateFontString(tabFrame, "body", "OVERLAY")
    goldDisplay:SetPoint("RIGHT", tabFrame, "RIGHT", -10, 0)
    local FormatMoney = ns.UI_FormatMoney
    
    if currentItemsSubTab == "warband" then
        -- Warband Bank gold (account-wide)
        local warbandGold = ns.Utilities:GetWarbandBankMoney() or 0
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(warbandGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(warbandGold))
        end
    elseif currentItemsSubTab == "guild" then
        -- Guild Bank gold (ONLY use cached value from scan - no live API fallback)
        if IsInGuild() then
            local guildName = GetGuildInfo("player")
            local guildGold = nil
            
            -- Try to get cached gold from scan data for CURRENT guild only
            if guildName and WarbandNexus.db.global.guildBank and WarbandNexus.db.global.guildBank[guildName] then
                guildGold = WarbandNexus.db.global.guildBank[guildName].cachedGold
            end
            
            if guildGold then
                if FormatMoney then
                    goldDisplay:SetText(FormatMoney(guildGold, 14))
                else
                    goldDisplay:SetText(WarbandNexus:API_FormatMoney(guildGold))
                end
            else
                -- No cached gold for this guild - need to scan
                goldDisplay:SetText("|cff888888" .. ((ns.L and ns.L["NO_SCAN"]) or "Not scanned") .. "|r")
            end
        else
            goldDisplay:SetText("|cff888888" .. ((ns.L and ns.L["NOT_IN_GUILD"]) or "Not in guild") .. "|r")
        end
    elseif currentItemsSubTab == "inventory" then
        -- Character inventory gold (current character only)
        local charGold = GetMoney()
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(charGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(charGold))
        end
    end
    -- Personal Bank has no gold display (WoW doesn't support gold storage in personal bank)
    
    yOffset = yOffset + 32 + GetLayout().afterElement  -- Tab frame height + spacing
    
    -- ===== SEARCH BOX (in fixedHeader - non-scrolling) =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    local itemsSearchText = SearchStateManager:GetQuery("items")
    
    local searchBox = CreateSearchBox(headerParent, width, (ns.L and ns.L["ITEMS_SEARCH"]) or "Search items...", function(text)
        SearchStateManager:SetSearchQuery("items", text)
        local resultsContainer = parent.resultsContainer
        if resultsContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
            local contentHeight = WarbandNexus:DrawItemsResults(resultsContainer, 0, width, ns.UI_GetItemsSubTab(), text)
            resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
        end
    end, 0.4, itemsSearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + GetLayout().afterElement
    
    -- ===== STATS BAR (in fixedHeader) =====
    -- Get items for stats (before results container)
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    elseif currentItemsSubTab == "inventory" then
        items = self:GetInventoryItems() or {}
    elseif currentItemsSubTab == "personal" then
        items = self:GetBankItems() or {}
    end
    
    local statsBar, statsText = CreateStatsBar(headerParent, 24)
    statsBar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    statsBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    local bankStats = self:GetBankStatistics()
    
    if currentItemsSubTab == "warband" then
        local wb = bankStats.warband or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cffa335ee" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(wb.usedSlots or 0), FormatNumber(wb.totalSlots or 0),
            (wb.lastScan or 0) > 0 and date("%H:%M", wb.lastScan) or neverText))
    elseif currentItemsSubTab == "guild" then
        local gb = bankStats.guild or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cff00ff00" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(gb.usedSlots or 0), FormatNumber(gb.totalSlots or 0),
            (gb.lastScan or 0) > 0 and date("%H:%M", gb.lastScan) or neverText))
    elseif currentItemsSubTab == "inventory" then
        -- Inventory bags only
        local bagsData = self.db.char.bags or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cff88ccff" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(bagsData.usedSlots or 0), FormatNumber(bagsData.totalSlots or 0),
            (bagsData.lastScan or 0) > 0 and date("%H:%M", bagsData.lastScan) or neverText))
    elseif currentItemsSubTab == "personal" then
        -- Personal Bank only
        local pb = bankStats.personal or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(string.format("|cff88ff88" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(pb.usedSlots or 0), FormatNumber(pb.totalSlots or 0),
            (pb.lastScan or 0) > 0 and date("%H:%M", pb.lastScan) or neverText))
    end
    statsText:SetTextColor(1, 1, 1)  -- White
    
    yOffset = yOffset + 24 + GetLayout().afterElement

    -- Set fixedHeader height so scroll area starts below all header elements
    if fixedHeader then fixedHeader:SetHeight(yOffset) end
    
    -- ===== RESULTS CONTAINER (in scroll area) =====
    local resultsContainer = CreateResultsContainer(parent, 8, SIDE_MARGIN)
    parent.resultsContainer = resultsContainer
    
    local contentHeight = self:DrawItemsResults(resultsContainer, 0, width, currentItemsSubTab, itemsSearchText)
    resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
    
    return 8 + (contentHeight or 0)
end

--============================================================================
-- ITEMS RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawItemsResults(parent, yOffset, width, currentItemsSubTab, itemsSearchText)
    local expandedGroups = ns.UI_GetExpandedGroups()
    
    -- Get items based on selected sub-tab (4 separate sources)
    local items = {}
    if currentItemsSubTab == "warband" then
        items = self:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = self:GetGuildBankItems() or {}
    elseif currentItemsSubTab == "inventory" then
        items = self:GetInventoryItems() or {}
    elseif currentItemsSubTab == "personal" then
        items = self:GetBankItems() or {}
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
            -- No items cached (general empty state) - use standardized factory with sub-tab specific config
            local emptyStateKey = "items_" .. currentItemsSubTab  -- e.g., "items_inventory", "items_guild"
            local _, height = CreateEmptyStateCard(parent, emptyStateKey, yOffset)
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
    
    -- ===== BUILD FLAT LIST FOR VIRTUAL SCROLLING =====
    local HEADER_HEIGHT = GetLayout().HEADER_HEIGHT or 30
    local flatList = {}
    local rowIdx = 0
    
    for _, typeName in ipairs(groupOrder) do
        local group = groups[typeName]
        local isExpanded = self.itemsExpandAllActive or expandedGroups[group.groupKey]
        if isExpanded == nil then
            isExpanded = true
            expandedGroups[group.groupKey] = true
        end
        
        local typeIcon = nil
        if group.items[1] and group.items[1].classID then
            typeIcon = GetTypeIcon(group.items[1].classID)
        end
        
        flatList[#flatList + 1] = {
            type = "header",
            yOffset = yOffset,
            height = HEADER_HEIGHT,
            data = {
                typeName = typeName,
                group = group,
                isExpanded = isExpanded,
                typeIcon = typeIcon,
            },
        }
        yOffset = yOffset + HEADER_HEIGHT
        
        if isExpanded then
            for _, item in ipairs(group.items) do
                rowIdx = rowIdx + 1
                flatList[#flatList + 1] = {
                    type = "row",
                    yOffset = yOffset,
                    height = ROW_SPACING,
                    data = item,
                    rowIdx = rowIdx,
                }
                yOffset = yOffset + ROW_SPACING
            end
        end
        
        yOffset = yOffset + SECTION_SPACING
    end
    
    -- ===== VIRTUAL SCROLL SETUP =====
    local mainFrame = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local VLM = ns.VirtualListModule
    
    if mainFrame and VLM and #flatList > 0 then
        
        local function PopulateRow(row, item, idx, rowNum)
            row:SetAlpha(1)
            if row.anim then row.anim:Stop() end
            row.idx = rowNum
            ns.UI.Factory:ApplyRowBackground(row, rowNum)
            
            row.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
            row.icon:SetTexture(item.iconFileID or 134400)
            
            local nameWidth = width - 350
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
            
            local locText = ""
            if currentItemsSubTab == "warband" then
                locText = item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex) or ""
            elseif currentItemsSubTab == "guild" then
                locText = item.tabName or (item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex)) or ""
            elseif currentItemsSubTab == "inventory" or currentItemsSubTab == "personal" then
                if item.actualBagID then
                    if item.actualBagID == -1 then
                        locText = (ns.L and ns.L["CHARACTER_BANK"]) or "Bank"
                    else
                        locText = format((ns.L and ns.L["BAG_FORMAT"]) or "Bag %d", item.actualBagID)
                    end
                end
            end
            row.locationText:SetWidth(0)
            row.locationText:SetText(locText)
            row.locationText:SetTextColor(1, 1, 1)
            row.locationText:SetWordWrap(false)
            row.locationText:SetNonSpaceWrap(false)
            
            row:SetScript("OnEnter", function(self)
                if not ShowTooltip then return end
                local additionalLines = {}
                if item.stackCount and item.stackCount > 1 then
                    table.insert(additionalLines, {text = ((ns.L and ns.L["STACK_LABEL"]) or "Stack: ") .. FormatNumber(item.stackCount), color = {1, 1, 1}})
                end
                if item.location then
                    table.insert(additionalLines, {text = ((ns.L and ns.L["LOCATION_LABEL"]) or "Location: ") .. item.location, color = {0.7, 0.7, 0.7}})
                end
                table.insert(additionalLines, {text = ((ns.L and ns.L["ITEM_ID_LABEL"]) or "Item ID: ") .. tostring(item.itemID or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")), color = {0.4, 0.8, 1}})
                table.insert(additionalLines, {type = "spacer"})
                if WarbandNexus.bankIsOpen then
                    table.insert(additionalLines, {text = "|cff00ff00Right-Click|r " .. ((ns.L and ns.L["RIGHT_CLICK_MOVE"]) or "Move to bag"), color = {1, 1, 1}})
                    if item.stackCount and item.stackCount > 1 then
                        table.insert(additionalLines, {text = "|cff00ff00Shift+Right-Click|r " .. ((ns.L and ns.L["SHIFT_RIGHT_CLICK_SPLIT"]) or "Split stack"), color = {1, 1, 1}})
                    end
                    table.insert(additionalLines, {text = "|cff888888Left-Click|r " .. ((ns.L and ns.L["LEFT_CLICK_PICKUP"]) or "Pick up"), color = {0.7, 0.7, 0.7}})
                else
                    table.insert(additionalLines, {text = "|cffff6600" .. ((ns.L and ns.L["ITEMS_BANK_NOT_OPEN"]) or "Bank not open") .. "|r", color = {1, 1, 1}})
                end
                table.insert(additionalLines, {text = "|cff888888Shift+Left-Click|r " .. ((ns.L and ns.L["SHIFT_LEFT_CLICK_LINK"]) or "Link in chat"), color = {0.7, 0.7, 0.7}})
                ShowTooltip(self, { type = "item", itemID = item.itemID, itemLink = item.link, additionalLines = additionalLines, anchor = "ANCHOR_LEFT" })
            end)
            row:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
            row:SetScript("OnMouseUp", function(_, button)
                if button == "LeftButton" and IsShiftKeyDown() and item.itemLink then
                    ChatEdit_InsertLink(item.itemLink)
                end
            end)
        end
        
        local totalHeight = VLM.SetupVirtualList(mainFrame, parent, 0, flatList, {
            createHeaderFn = function(container, entry)
                local d = entry.data
                local gKey = d.group.groupKey
                local groupHeader = CreateCollapsibleHeader(
                    container,
                    format("%s (%s)", d.typeName, FormatNumber(#d.group.items)),
                    gKey,
                    d.isExpanded,
                    function(exp)
                        if type(exp) == "boolean" then
                            expandedGroups[gKey] = exp
                            if exp then self.recentlyExpanded[gKey] = GetTime() end
                        else
                            expandedGroups[gKey] = not expandedGroups[gKey]
                            if expandedGroups[gKey] then self.recentlyExpanded[gKey] = GetTime() end
                        end
                        WarbandNexus:RefreshUI()
                    end,
                    d.typeIcon
                )
                groupHeader:SetWidth(width)
                return groupHeader
            end,
            createRowFn = function(container, entry)
                local row = AcquireItemRow(container, width, ROW_HEIGHT)
                PopulateRow(row, entry.data, entry.rowIdx, entry.rowIdx)
                return row
            end,
            releaseRowFn = function(frame)
                ReleaseItemRow(frame)
            end,
        })
        
        return math.max(totalHeight, yOffset) + GetLayout().minBottomSpacing
    end
    
    return yOffset + GetLayout().minBottomSpacing
end -- DrawItemsResults

