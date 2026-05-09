--[[
    Warband Nexus - Items Tab
    Display and manage Warband and Personal bank items with interactive controls
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

local issecretvalue = issecretvalue

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

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
local BuildAccordionVisualOpts = ns.UI_BuildAccordionVisualOpts
local GetTypeIcon = ns.UI_GetTypeIcon
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local AcquireItemRow = ns.UI_AcquireItemRow
local ReleaseItemRow = ns.UI_ReleaseItemRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateStatsBar = ns.UI_CreateStatsBar
local CreateResultsContainer = ns.UI_CreateResultsContainer
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local FormatNumber = ns.UI_FormatNumber
local NormalizeColonLabelSpacing = ns.UI_NormalizeColonLabelSpacing

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
-- ROW_COLOR_EVEN/ODD: Now handled by Factory:ApplyRowBackground()

-- Performance: Local function references
local format = string.format
local date = date

-- Bank alt sekmeler: CollectionsUI CreateSubTabBar ile aynı ölçü ve davranış (ikon + hover + _active).
local ITEMS_BANK_SUBTAB_BTN_HEIGHT = 40
local ITEMS_BANK_SUBTAB_BTN_SPACING = 8
local ITEMS_BANK_SUBTAB_ICON_SIZE = 28
local ITEMS_BANK_SUBTAB_ICON_LEFT = 10
local ITEMS_BANK_SUBTAB_ICON_TEXT_GAP = 8
local ITEMS_BANK_SUBTAB_TEXT_RIGHT = 10
local ITEMS_BANK_SUBTAB_DEFAULT_WIDTH = 150
local ITEMS_BANK_SUBTAB_GOLD_RESERVE = 136

local function ItemsBankSubTabIconApply(tex, tabInfo)
    if not tex or not tabInfo then return end
    tex:SetTexture(nil)
    local sz = ITEMS_BANK_SUBTAB_ICON_SIZE - 2
    if tabInfo.iconAtlas then
        local ok = pcall(function()
            tex:SetAtlas(tabInfo.iconAtlas, false)
        end)
        if ok then
            tex:SetSize(sz, sz)
            return
        end
    end
    tex:SetTexture(tabInfo.icon or tabInfo.iconFallback or "Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:SetSize(sz, sz)
end

--- @return Frame bar with bar:SetActiveTab(key), bar.buttons
local function CreateItemsBankSubTabBar(headerParent, yOffset, currentKey, accentColor)
    local tabDefs = {
        { key = "personal", label = (ns.L and ns.L["CHARACTER_BANK"]) or "Personal Bank", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
        { key = "warband", label = (ns.L and ns.L["ITEMS_WARBAND_BANK"]) or "Warband Bank", iconAtlas = "warbands-icon", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
        { key = "guild", label = (ns.L and ns.L["ITEMS_GUILD_BANK"]) or "Guild Bank", iconAtlas = "poi-workorders", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
        { key = "inventory", label = (ns.L and ns.L["CHARACTER_INVENTORY"]) or "Inventory", icon = "Interface\\Icons\\INV_Misc_Bag_07" },
    }

    local bar = CreateFrame("Frame", nil, headerParent)
    bar:SetHeight(ITEMS_BANK_SUBTAB_BTN_HEIGHT)
    bar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    bar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)

    local btnArea = CreateFrame("Frame", nil, bar)
    btnArea:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    btnArea:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -ITEMS_BANK_SUBTAB_GOLD_RESERVE, 0)

    local btnWidths = {}
    for i = 1, #tabDefs do
        local tabInfo = tabDefs[i]
        local tempFs = FontManager:CreateFontString(bar, "body", "OVERLAY")
        tempFs:SetText(tabInfo.label)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local needed = ITEMS_BANK_SUBTAB_ICON_LEFT + ITEMS_BANK_SUBTAB_ICON_SIZE + ITEMS_BANK_SUBTAB_ICON_TEXT_GAP + textW + ITEMS_BANK_SUBTAB_TEXT_RIGHT
        btnWidths[i] = math.max(needed, ITEMS_BANK_SUBTAB_DEFAULT_WIDTH)
    end

    local buttons = {}
    local xPos = 0
    local acc = accentColor or COLORS.accent

    for i = 1, #tabDefs do
        local tabInfo = tabDefs[i]
        local btnWidth = btnWidths[i]
        local btn = ns.UI.Factory:CreateButton(btnArea, btnWidth, ITEMS_BANK_SUBTAB_BTN_HEIGHT)
        btn:SetPoint("TOPLEFT", btnArea, "TOPLEFT", xPos, 0)
        btn._tabKey = tabInfo.key

        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc[1], acc[2], acc[3], 0.6})
        end
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end

        local activeBarTex = btn:CreateTexture(nil, "OVERLAY")
        activeBarTex:SetHeight(3)
        activeBarTex:SetPoint("BOTTOMLEFT", 8, 4)
        activeBarTex:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBarTex:SetColorTexture(acc[1], acc[2], acc[3], 1)
        activeBarTex:SetAlpha(0)
        btn.activeBar = activeBarTex

        local btnIcon = btn:CreateTexture(nil, "ARTWORK")
        ItemsBankSubTabIconApply(btnIcon, tabInfo)
        btnIcon:SetPoint("LEFT", ITEMS_BANK_SUBTAB_ICON_LEFT, 0)

        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText:SetPoint("LEFT", btnIcon, "RIGHT", ITEMS_BANK_SUBTAB_ICON_TEXT_GAP, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -ITEMS_BANK_SUBTAB_TEXT_RIGHT, 0)
        btnText:SetText(tabInfo.label)
        btnText:SetJustifyH("LEFT")
        btnText:SetWordWrap(false)
        local tn = COLORS.textNormal or {0.85, 0.85, 0.85}
        btnText:SetTextColor(tn[1], tn[2], tn[3])
        btn._text = btnText

        btn:SetScript("OnClick", function()
            if ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == tabInfo.key then return end
            if tabInfo.key == "guild" and not IsInGuild() then
                WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["GUILD_BANK_REQUIRED"]) or "You must be in a guild to access Guild Bank.") .. "|r")
                return
            end
            ns.UI_SetItemsSubTab(tabInfo.key)
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "items", skipCooldown = true })
        end)

        if UpdateBorderColor then
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                UpdateBorderColor(self, {acc[1] * 1.2, acc[2] * 1.2, acc[3] * 1.2, 0.9})
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                UpdateBorderColor(self, {acc[1], acc[2], acc[3], 0.6})
            end)
        else
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.10, 0.10, 0.12, 0.95) end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.12, 0.12, 0.15, 1) end
            end)
        end

        buttons[tabInfo.key] = btn
        xPos = xPos + btnWidth + ITEMS_BANK_SUBTAB_BTN_SPACING

        if tabInfo.key == "guild" and not IsInGuild() then
            btn:Disable()
            btn:SetAlpha(0.5)
        end
    end

    bar.buttons = buttons

    function bar:SetActiveTab(key)
        local acc2 = accentColor or COLORS.accent
        for k, btn in pairs(buttons) do
            if k == key then
                btn._active = true
                if btn.activeBar then btn.activeBar:SetAlpha(1) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {acc2[1] * 0.3, acc2[2] * 0.3, acc2[3] * 0.3, 1}, {acc2[1], acc2[2], acc2[3], 1})
                end
                if btn._text then
                    btn._text:SetTextColor(1, 1, 1)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "OUTLINE") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc2[1], acc2[2], acc2[3], 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(acc2[1] * 0.3, acc2[2] * 0.3, acc2[3] * 0.3, 1) end
            else
                btn._active = false
                if btn.activeBar then btn.activeBar:SetAlpha(0) end
                if btn:IsEnabled() then
                    if ApplyVisuals then
                        ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc2[1] * 0.6, acc2[2] * 0.6, acc2[3] * 0.6, 1})
                    end
                    if btn._text then
                        btn._text:SetTextColor(0.7, 0.7, 0.7)
                        local font, size = btn._text:GetFont()
                        if font and size then btn._text:SetFont(font, size, "") end
                    end
                    if UpdateBorderColor then UpdateBorderColor(btn, {acc2[1] * 0.6, acc2[2] * 0.6, acc2[3] * 0.6, 1}) end
                    if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.12, 0.15, 1) end
                elseif btn._text then
                    btn._text:SetTextColor(0.45, 0.45, 0.45)
                end
            end
        end
    end

    bar:SetActiveTab(currentKey)
    return bar
end

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
    local DebugPrint = ns.DebugPrint
    local IsDebugModeEnabled = ns.IsDebugModeEnabled
    
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
        pendingDrawTimer = C_Timer.NewTimer(DRAW_DEBOUNCE, function()
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
    WarbandNexus.RegisterMessage(ItemsUIEvents, E.ITEM_METADATA_READY, function()
        if IsItemsTabActive() then
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("|cff00ff00[ItemsUI]|r WN_ITEM_METADATA_READY received, refreshing names")
            end
            ScheduleDrawItemList()
        end
    end)
    
    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("|cff9370DB[ItemsUI]|r Event listeners registered: WN_ITEM_METADATA_READY")
    end
end

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    -- Register event listeners (only once)
    RegisterItemsEvents(parent)
    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local yOffset = 8
    local width = parent:GetWidth() - 20
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    HideEmptyStateCard(parent, "items")
    
    -- PERFORMANCE: Release pooled frames for partial redraw calls.
    -- PopulateContent already does this once per full-tab render.
    if not parent._preparedByPopulate then
        ReleaseAllPooledChildren(parent)
    end
    
    -- ===== HEADER CARD (in fixedHeader - non-scrolling) — Characters-tab layout =====
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local accentColor = COLORS.accent
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "items",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["ITEMS_HEADER"]) or "Bank Items") .. "|r",
        subtitleText = (ns.L and ns.L["ITEMS_SUBTITLE"]) or "Browse your Warband Bank and Personal Items (Bank + Inventory)",
        textRightInset = 230,
    }))
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- ===== GOLD MANAGER BUTTON (Header - ALWAYS visible) =====
    local headerBtnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local titleCardRightInset = GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20
    local goldMgrBtn = ns.UI.Factory:CreateButton(titleCard, 100, headerBtnH)  -- Initial width, will auto-size
    goldMgrBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleCardRightInset, 0)
    
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
    local moneyLogsBtn = ns.UI.Factory:CreateButton(titleCard, 100, headerBtnH)
    local hdrGap = GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8
    moneyLogsBtn:SetPoint("RIGHT", goldMgrBtn, "LEFT", -hdrGap, 0)

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
    
    -- ===== SUB-TAB BAR (Collections CreateSubTabBar parity: 40px, icons, hover, gold reserve) =====
    local accentColor = COLORS.accent
    local itemsBankSubTabBar = CreateItemsBankSubTabBar(headerParent, yOffset, currentItemsSubTab, accentColor)

    -- ===== GOLD DISPLAY (Per Sub-Tab; personal bank has no account gold — hide to avoid stale text) =====
    local goldDisplay = FontManager:CreateFontString(itemsBankSubTabBar, "body", "OVERLAY")
    goldDisplay:SetPoint("RIGHT", itemsBankSubTabBar, "RIGHT", -10, 0)
    local FormatMoney = ns.UI_FormatMoney

    if currentItemsSubTab == "personal" then
        goldDisplay:Hide()
    else
        goldDisplay:Show()
    end

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
            if guildName and issecretvalue and issecretvalue(guildName) then guildName = nil end
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
        local charGold = ns.Utilities:GetLiveCharacterMoneyCopper(0)
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(charGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(charGold))
        end
    elseif goldDisplay:IsShown() then
        goldDisplay:SetText("")
    end

    yOffset = yOffset + ITEMS_BANK_SUBTAB_BTN_HEIGHT + GetLayout().afterElement
    
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
    
    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
    yOffset = yOffset + searchH + GetLayout().afterElement
    
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
        statsText:SetText(format("|cffa335ee" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(wb.usedSlots or 0), FormatNumber(wb.totalSlots or 0),
            (wb.lastScan or 0) > 0 and date("%H:%M", wb.lastScan) or neverText))
    elseif currentItemsSubTab == "guild" then
        local gb = bankStats.guild or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(format("|cff00ff00" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(gb.usedSlots or 0), FormatNumber(gb.totalSlots or 0),
            (gb.lastScan or 0) > 0 and date("%H:%M", gb.lastScan) or neverText))
    elseif currentItemsSubTab == "inventory" then
        -- Inventory bags only
        local bagsData = self.db.char.bags or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(format("|cff88ccff" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(bagsData.usedSlots or 0), FormatNumber(bagsData.totalSlots or 0),
            (bagsData.lastScan or 0) > 0 and date("%H:%M", bagsData.lastScan) or neverText))
    elseif currentItemsSubTab == "personal" then
        -- Personal Bank only
        local pb = bankStats.personal or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(format("|cff88ff88" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
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

--- Redraw Items scroll results only (virtual list + group headers). Skips PopulateContent /
--- scrollChild purge — same contract as RedrawStorageResultsOnly for expand/collapse perf.
function WarbandNexus:RedrawItemsResultsOnly()
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "items" then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.resultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = scrollChild:GetWidth() - 20
    if width < 1 then return end
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery then
        q = SearchStateManager:GetQuery("items") or ""
    end
    local subTab = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"

    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(rc)
    end

    local contentHeight = self:DrawItemsResults(rc, 0, width, subTab, q)
    rc:SetHeight(math.max(contentHeight or 1, 1))

    local CONTENT_BOTTOM_PADDING = 8
    local tabBodyHeight = 8 + (contentHeight or 0)
    scrollChild:SetHeight(math.max(tabBodyHeight + CONTENT_BOTTOM_PADDING, mf.scroll:GetHeight()))

    if ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(mf.scroll)
    end
    if ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
    end

    local sc = mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
end

--- Build grouped flat list for Items virtual scroll. Returns flatList, endYOffset, itemCount, itemsSearchActive;
--- flatList is nil when there are no items (caller renders empty state).
function WarbandNexus:BuildItemsVirtualFlatList(width, currentItemsSubTab, itemsSearchText, startYOffset)
    local itemsSearchActive = itemsSearchText
        and not (issecretvalue and issecretvalue(itemsSearchText))
        and itemsSearchText ~= ""

    local expandedGroups = ns.UI_GetExpandedGroups()

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

    if itemsSearchActive then
        local filtered = {}
        for i = 1, #items do
            local item = items[i]
            local itemName = SafeLower(item.name)
            local itemLink = SafeLower(item.itemLink)
            if itemName:find(itemsSearchText, 1, true) or itemLink:find(itemsSearchText, 1, true) then
                table.insert(filtered, item)
            end
        end
        items = filtered
    end

    do
        local n = #items
        if n > 1 then
            local order = {}
            local keys = {}
            for i = 1, n do
                order[i] = i
                keys[i] = SafeLower(items[i].name)
            end
            table.sort(order, function(ia, ib)
                local ka, kb = keys[ia], keys[ib]
                if ka ~= kb then return ka < kb end
                return ia < ib
            end)
            local sorted = {}
            for i = 1, n do
                sorted[i] = items[order[i]]
            end
            items = sorted
        end
    end

    if #items == 0 then
        return nil, startYOffset, 0, itemsSearchActive
    end

    SearchStateManager:UpdateResults("items", #items)

    local groups = {}
    local groupOrder = {}
    local hasSearchFilter = itemsSearchActive
    -- Keep first group visually separated from section/title header area.
    local yOffset = startYOffset + SECTION_SPACING

    for i = 1, #items do
        local item = items[i]
        local typeName = item.itemType or ((ns.L and ns.L["GROUP_MISC"]) or "Miscellaneous")
        if not groups[typeName] then
            local groupKey = currentItemsSubTab .. "_" .. typeName
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

    table.sort(groupOrder)

    local HEADER_HEIGHT = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
    local flatList = {}
    local rowIdx = 0

    for typeIndex = 1, #groupOrder do
        local typeName = groupOrder[typeIndex]
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
            local localY = 0
            for itemIndex = 1, #group.items do
                local item = group.items[itemIndex]
                rowIdx = rowIdx + 1
                -- Stable identity for virtual row reuse (accordion / Refresh without repopulating textures & text).
                local rowReuseSig = (group.groupKey or "")
                    .. "\001"
                    .. tostring(item.itemID or 0)
                    .. "\001"
                    .. tostring(item.tabIndex or "")
                    .. "\001"
                    .. tostring(item.actualBagID or item.bagID or "")
                    .. "\001"
                    .. tostring(item.slotIndex or item.slot or item.slotID or "")
                    .. "\001"
                    .. tostring(item.stackCount or 1)
                    .. "\001"
                    .. (item.pending and "p" or "r")
                flatList[#flatList + 1] = {
                    type = "row",
                    yOffset = yOffset,
                    height = ROW_SPACING,
                    data = item,
                    rowIdx = rowIdx,
                    groupKey = group.groupKey,
                    localY = localY,
                    rowReuseSig = rowReuseSig,
                }
                localY = localY + ROW_SPACING
                yOffset = yOffset + ROW_SPACING
            end
        end

        yOffset = yOffset + SECTION_SPACING
    end

    return flatList, yOffset, #items, itemsSearchActive
end

--- Group header toggle: swap flat list only (same header keys) — avoids full DrawItemsResults / ClearVirtualScroll.
function WarbandNexus:ApplyItemsVirtualFlatListOnly()
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "items" then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.resultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = scrollChild:GetWidth() - 20
    if width < 1 then return end
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery then
        q = SearchStateManager:GetQuery("items") or ""
    end
    local subTab = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"

    local flatList = self:BuildItemsVirtualFlatList(width, subTab, q, 0)
    if not flatList then
        self:RedrawItemsResultsOnly()
        return
    end

    local VLM = ns.VirtualListModule
    if not VLM or not VLM.RefreshVirtualListFlatList then
        self:RedrawItemsResultsOnly()
        return
    end

    local contentHeight, forceFull = VLM.RefreshVirtualListFlatList(mf, rc, flatList)
    if forceFull then
        self:RedrawItemsResultsOnly()
        return
    end

    rc:SetHeight(math.max(contentHeight or 1, 1))

    local CONTENT_BOTTOM_PADDING = 8
    local tabBodyHeight = 8 + (contentHeight or 0)
    scrollChild:SetHeight(math.max(tabBodyHeight + CONTENT_BOTTOM_PADDING, mf.scroll:GetHeight()))

    if ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(mf.scroll)
    end
    if ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
    end

    local sc = mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
end

--============================================================================
-- ITEMS RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawItemsResults(parent, yOffset, width, currentItemsSubTab, itemsSearchText)
    local flatList, contentEndY, _itemCount, itemsSearchActive = self:BuildItemsVirtualFlatList(width, currentItemsSubTab, itemsSearchText, yOffset)

    if not flatList then
        if itemsSearchActive then
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, itemsSearchText, "items")
            SearchStateManager:UpdateResults("items", 0)
            return height
        else
            local emptyStateKey = "items_" .. currentItemsSubTab
            local _, height = CreateEmptyStateCard(parent, emptyStateKey, yOffset)
            SearchStateManager:UpdateResults("items", 0)
            return height
        end
    end

    yOffset = contentEndY

    -- ===== VIRTUAL SCROLL SETUP =====
    local mainFrame = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local VLM = ns.VirtualListModule
    if mainFrame and VLM and VLM.ClearVirtualScroll then
        VLM.ClearVirtualScroll(mainFrame)
    end

    if mainFrame and VLM and #flatList > 0 then

        local expandedGroups = ns.UI_GetExpandedGroups()

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
            if not baseName and item.link and not (issecretvalue and issecretvalue(item.link)) then
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
                    table.insert(additionalLines, {text = NormalizeColonLabelSpacing((ns.L and ns.L["STACK_LABEL"]) or "Stack:") .. FormatNumber(item.stackCount), color = {1, 1, 1}})
                end
                if item.location then
                    table.insert(additionalLines, {text = NormalizeColonLabelSpacing((ns.L and ns.L["LOCATION_LABEL"]) or "Location:") .. item.location, color = {0.7, 0.7, 0.7}})
                end
                table.insert(additionalLines, {text = NormalizeColonLabelSpacing((ns.L and ns.L["ITEM_ID_LABEL"]) or "Item ID:") .. tostring(item.itemID or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")), color = {0.4, 0.8, 1}})
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

        local HEADER_STRIP_H = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
        local Factory = ns.UI.Factory

        local totalHeight = VLM.SetupVirtualList(mainFrame, parent, 0, flatList, {
            chainCollapsibleHeaders = true,
            chainAnimatedSections = true,
            incrementalRowReuse = true,
            populateRowFn = function(frame, entry, _idx)
                PopulateRow(frame, entry.data, entry.rowIdx, entry.rowIdx)
            end,
            createHeaderFn = function(container, entry)
                local d = entry.data
                local gKey = d.group.groupKey
                local nItems = #d.group.items
                local rowsBodyH = math.max(0.1, nItems * ROW_SPACING)

                local groupWrap = Factory:CreateContainer(container, math.max(1, width), HEADER_STRIP_H + 0.1, false)
                if groupWrap.SetClipsChildren then
                    groupWrap:SetClipsChildren(true)
                end

                local groupShell
                local headerStripH = HEADER_STRIP_H
                local headerBtn = CreateCollapsibleHeader(
                    groupWrap,
                    format("%s (%s)", d.typeName, FormatNumber(nItems)),
                    gKey,
                    d.isExpanded,
                    function(_isExpanded)
                        WarbandNexus:ApplyItemsVirtualFlatListOnly()
                    end,
                    d.typeIcon,
                    false,
                    nil,
                    nil,
                    BuildAccordionVisualOpts({
                        wrapFrame = groupWrap,
                        bodyGetter = function() return groupShell end,
                        headerHeight = headerStripH,
                        hideOnCollapse = true,
                        showOnExpand = true,
                        -- Collapse: refresh flatList before height tween so VirtualListModule culling matches
                        -- layout while rows shift (expand already calls onToggle before tween).
                        applyToggleBeforeCollapseAnimate = true,
                        persistFn = function(exp)
                            if type(exp) == "boolean" then
                                expandedGroups[gKey] = exp
                            end
                        end,
                        onComplete = function(exp)
                            if groupShell and not exp then
                                groupWrap:SetHeight(headerStripH + 0.1)
                            end
                            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
                            if mf and mf.scroll and Factory and Factory.UpdateScrollBarVisibility then
                                Factory:UpdateScrollBarVisibility(mf.scroll)
                            end
                            local sc = mf and mf.scroll
                            if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
                                local maxV = sc:GetVerticalScrollRange() or 0
                                local cur = sc:GetVerticalScroll() or 0
                                if cur > maxV then
                                    sc:SetVerticalScroll(maxV)
                                end
                            end
                        end,
                    })
                )
                headerBtn:SetPoint("TOPLEFT", groupWrap, "TOPLEFT", 0, 0)
                headerBtn:SetWidth(math.max(1, width))

                groupShell = Factory:CreateContainer(groupWrap, math.max(1, width), 0.1, false)
                groupShell:ClearAllPoints()
                groupShell:SetPoint("TOPLEFT", headerBtn, "BOTTOMLEFT", 0, 0)
                groupShell:SetPoint("TOPRIGHT", headerBtn, "BOTTOMRIGHT", 0, 0)
                groupShell._wnAccordionFullH = rowsBodyH
                if d.isExpanded then
                    groupShell:Show()
                    groupShell:SetHeight(rowsBodyH)
                else
                    groupShell:Hide()
                    groupShell:SetHeight(0.1)
                end
                groupWrap:SetHeight(headerStripH + math.max(0.1, groupShell:GetHeight() or 0.1))

                container._vlm_groupShellByKey[gKey] = groupShell

                return groupWrap
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

