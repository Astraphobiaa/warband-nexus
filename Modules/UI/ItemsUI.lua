--[[
    Warband Nexus - Items tab + Warband aggregate storage tree (bank subtabs, hierarchical storage).

    WN_FACTORY: Bank sub-tab bar uses `Factory:CreateContainer` and `CreateButton` with guarded fallbacks when
    Factory is unavailable (plain `BackdropTemplate` buttons + ApplyVisuals); item rows/storage use pooled factories elsewhere.
    WN_PERF: Virtual lists where applicable (`VirtualListModule`); storage warband subtree is profiler-sliced (`Stor_*` timings in DrawStorageResults).
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

-- Storage aggregate tree (DrawStorageResults) needs StorageSectionLayout loaded first (TOC order).
local StorageSectionLayout = ns.StorageSectionLayout
if not StorageSectionLayout then
    error("StorageSectionLayout missing — load Modules/UI/StorageSectionLayout.lua before ItemsUI.lua in WarbandNexus.toc")
end

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local COLORS = ns.UI_COLORS
local GetQualityHex = ns.UI_GetQualityHex
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local BuildCollapsibleSectionOpts = ns.UI_BuildCollapsibleSectionOpts
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
local GetItemTypeName = ns.UI_GetItemTypeName
local GetItemClassID = ns.UI_GetItemClassID
local ReleasePooledRowsInSubtree = ns.UI_ReleasePooledRowsInSubtree
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
--- Storage tree leaf rows only (FramePoolFactory AcquireStorageRow); body-font glyphs need > ROW_HEIGHT so descenders clear the next row background.
local STORAGE_ROW_HEIGHT = GetLayout().STORAGE_ROW_HEIGHT or GetLayout().storageRowHeight or ROW_HEIGHT
--- WN-PERF (`WN-PERF-warband-nexus`): Personal/Warband aggregate leaf tables exceed sync cap → `C_Timer.After(0)` chunks + paint generation cancel.
local STORAGE_LEAF_ROW_CHUNK = 40
local STORAGE_LEAF_ROW_SYNC_MAX = 40
--- Bags / Bank / Guild virtual list rows: same stride as storage leaves (BuildItemsVirtualFlatList + VirtualListModule + AcquireItemRow).
local ITEMS_VIRTUAL_ROW_HEIGHT = STORAGE_ROW_HEIGHT
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
-- ROW_COLOR_EVEN/ODD: Now handled by Factory:ApplyRowBackground()

-- Performance: Local function references
local format = string.format
local date = date
local wipe = table.wipe
local tinsert = table.insert
local tremove = table.remove

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
        { key = "inventory", label = (ns.L and ns.L["ITEMS_SUBTAB_BAGS"]) or "Bags", icon = "Interface\\Icons\\INV_Misc_Bag_07" },
        { key = "personal", label = (ns.L and ns.L["ITEMS_SUBTAB_BANK"]) or "Bank", icon = "Interface\\Icons\\INV_Misc_Bag_08" },
        { key = "warband", label = (ns.L and ns.L["ITEMS_SUBTAB_WARBAND"]) or "Warband", iconAtlas = "warbands-icon", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
        { key = "guild", label = (ns.L and ns.L["ITEMS_GUILD_BANK"]) or "Guild Bank", iconAtlas = "poi-workorders", icon = "Interface\\Icons\\INV_Shirt_GuildTabard_01" },
    }

    local Factory = ns.UI and ns.UI.Factory

    local bar = Factory and Factory:CreateContainer(headerParent, 400, ITEMS_BANK_SUBTAB_BTN_HEIGHT, false)
    if not bar then
        bar = CreateFrame("Frame", nil, headerParent)
        bar:SetHeight(ITEMS_BANK_SUBTAB_BTN_HEIGHT)
    end
    bar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    bar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)

    local btnArea = Factory and Factory:CreateContainer(bar, 200, ITEMS_BANK_SUBTAB_BTN_HEIGHT, false)
    if not btnArea then
        btnArea = CreateFrame("Frame", nil, bar)
    end
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
        local btn = Factory and Factory.CreateButton and Factory:CreateButton(btnArea, btnWidth, ITEMS_BANK_SUBTAB_BTN_HEIGHT, false)
        if not btn then
            btn = CreateFrame("Button", nil, btnArea, "BackdropTemplate")
            btn:SetSize(btnWidth, ITEMS_BANK_SUBTAB_BTN_HEIGHT)
        end
        btn:SetPoint("TOPLEFT", btnArea, "TOPLEFT", xPos, 0)
        btn._tabKey = tabInfo.key

        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc[1], acc[2], acc[3], 0.6})
        end
        if Factory and Factory.ApplyHighlight then
            Factory:ApplyHighlight(btn)
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
            if not (WarbandNexus.RefreshItemsSubTabBodyOnly and WarbandNexus:RefreshItemsSubTabBodyOnly()) then
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "items", skipCooldown = true })
            end
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

    function bar:RefreshGuildLock()
        local gbtn = buttons.guild
        if not gbtn then return end
        if IsInGuild() then
            gbtn:Enable()
            gbtn:SetAlpha(1)
        else
            gbtn:Disable()
            gbtn:SetAlpha(0.5)
        end
    end

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

    -- Check if Items tab is actually the active tab (parent:IsVisible() is not enough
    -- because the scroll child is shared across all tabs and always visible)
    local function IsItemsTabActive()
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        return mf and mf:IsShown() and mf.currentTab == "items"
    end

    -- Sync redraw on item metadata resolve (no timer-deferred DrawItemList for now).
    local function FlushItemsMetadataRedraw()
        if not IsItemsTabActive() or not parent then return end
        if WarbandNexus.RedrawItemsResultsOnly then
            WarbandNexus:RedrawItemsResultsOnly()
        end
    end
    
    -- WN_ITEMS_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- items tab refresh via PopulateContent → DrawItemList. Having both caused double rebuild.
    
    -- Async item metadata resolution (items that were "Loading..." now have real names)
    -- Keep: UI.lua does NOT handle WN_ITEM_METADATA_READY.
    WarbandNexus.RegisterMessage(ItemsUIEvents, E.ITEM_METADATA_READY, function()
        if not IsItemsTabActive() then return end
        -- Warband aggregate tree: storage embed listener handles metadata (in-place or RedrawStorageResultsOnly).
        if ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband" and ns.Utilities and ns.Utilities:IsModuleEnabled("items") then
            return
        end
        -- Virtual list (Bags / Bank / Guild): item rows reference live cache objects — repaint visible rows only.
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local rc = mf and mf.scrollChild and mf.scrollChild.resultsContainer
        if rc and rc._virtualUpdater then
            rc._virtualUpdater()
            return
        end
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("|cff00ff00[ItemsUI]|r WN_ITEM_METADATA_READY received, refreshing names")
        end
        FlushItemsMetadataRedraw()
    end)
    
    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("|cff9370DB[ItemsUI]|r Event listeners registered: WN_ITEM_METADATA_READY")
    end
end

--============================================================================
-- STORAGE / WARBAND AGGREGATE TREE (merged from StorageUI.lua)
-- Saved data: unchanged (db.profile.storage*, db.global.*). Warband aggregate UI uses Items module toggle.
-- Requires StorageSectionLayout.lua to load BEFORE this file (see WarbandNexus.toc).
--============================================================================

local function CompareCharNameLower(a, b)
    return SafeLower(a.name) < SafeLower(b.name)
end

local ItemsStorageEmbedEvents = {}

-- Reused buffers: avoid `{frame:GetChildren()}` allocations on every Storage full redraw (large trees).
local _wnStorTopScratch = {}
local _wnStorChildScratch = {}
local _wnStorReflowScratch = {}

local function PackChildrenInto(dest, frame)
    wipe(dest)
    local n = select("#", frame:GetChildren())
    for i = 1, n do
        dest[i] = select(i, frame:GetChildren())
    end
    return n
end

--- Vertical extent (px): container top to lowest shown child bottom. Matches ReflowStorageStackParentBody
--- (same global GetTop/GetBottom space); avoids mixing container top with a single tail frame when siblings exist.
local function MeasureStorageResultsContentExtent(container)
    if not container then return nil end
    local pTop = container:GetTop()
    if not pTop then return nil end
    local lowest = pTop
    local nc = PackChildrenInto(_wnStorChildScratch, container)
    for i = 1, nc do
        local c = _wnStorChildScratch[i]
        if c and c:IsShown() and not c._isVirtualRow and c ~= container.emptyStateContainer and not c._wnExcludedFromStorageExtent then
            local cb = c:GetBottom()
            if cb and cb < lowest then
                lowest = cb
            end
        end
    end
    local extent = pTop - lowest
    if extent < 1 then
        extent = math.max(0.1, container:GetHeight() or 0.1)
    end
    return extent
end

--- Items results width: scrollChild often reports 0 before layout; sync scrollChild from scroll viewport first.
local MIN_ITEMS_RESULTS_WIDTH = 280

local function ResolveItemsTabScrollContentWidth(scrollChild)
    if not scrollChild then return MIN_ITEMS_RESULTS_WIDTH end
    if ns.UI_EnsureMainScrollLayout then
        ns.UI_EnsureMainScrollLayout()
    end
    local function contentW(frame)
        if not frame or not frame.GetWidth then return nil end
        local raw = frame:GetWidth()
        if not raw or raw < 2 then return nil end
        return raw - 20
    end
    local w = contentW(scrollChild)
    if w and w >= 1 then return w end
    local scroll = scrollChild:GetParent()
    w = contentW(scroll)
    if w and w >= 1 then return w end
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mf and mf.scroll then
        w = contentW(mf.scroll)
        if w and w >= 1 then return w end
    end
    return MIN_ITEMS_RESULTS_WIDTH
end

--- Match RedrawItemsResultsOnly: keep scrollChild height and scrollbars aligned after Warband-only redraws.
local function SyncItemsTabScrollChrome(mf, scrollChild, contentHeight)
    if not mf or not scrollChild then return end
    local CONTENT_BOTTOM_PADDING = 8
    local tabBodyHeight = 8 + (contentHeight or 0)
    if mf.scroll then
        scrollChild:SetHeight(math.max(tabBodyHeight + CONTENT_BOTTOM_PADDING, mf.scroll:GetHeight() or 0))
    end
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

--- Warband aggregate: banner while DrawStorageResults runs (heavy sync tree build).
local function EnsureWarbandDrawIndicator(container)
    if not container then return nil end
    local fs = container._wnWarbandDrawingText
    if not fs then
        fs = FontManager:CreateFontString(container, "body", "OVERLAY")
        fs:SetPoint("CENTER", container, "CENTER", 0, -48)
        fs:SetWidth(math.max(220, (container.GetWidth and container:GetWidth() or 400) - 48))
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(true)
        container._wnWarbandDrawingText = fs
    end
    if fs.SetWidth and container.GetWidth then
        local cw = container:GetWidth()
        if cw and cw > 48 then
            fs:SetWidth(cw - 48)
        end
    end
    local line1 = (ns.L and ns.L["ITEMS_LOADING"]) or "Loading..."
    local line2 = (ns.L and ns.L["ITEMS_WARBAND_UPDATING"]) or "Building Warband list..."
    fs:SetText("|cffaaaaaa" .. line1 .. "\n" .. line2 .. "|r")
    return fs
end

--- ItemsCacheService patches cached item tables in place; refresh row text/icons without full tree teardown.
local function TryRefreshStorageRowsMetadataInPlace(resultsContainer)
    if not resultsContainer then return false end
    local refs = resultsContainer._wnStorageRowRefs
    local fn = resultsContainer._wnStorageApplyRowVisual
    if not refs or #refs == 0 or type(fn) ~= "function" then
        return false
    end
    for i = 1, #refs do
        local row = refs[i]
        if row and row:IsShown() then
            local item = row._wnStorageItemRef
            if item then
                local rw = row:GetWidth()
                if rw and rw >= 1 then
                    local idx = row._wnStorageRowIdx or i
                    local loc = row._wnStorageLocText or ""
                    fn(row, item, idx, rw, loc)
                end
            end
        end
    end
    return true
end

--- Used by DrawStorageResults and partial leaf reflow (Bank > Warband aggregate tree).
local function ReflowStorageStackParentBody(stackParent, outerWrap, outerHeaderH)
    if not stackParent then return end
    local pTop = stackParent:GetTop()
    if not pTop then return end
    local lowest = pTop
    local nc = PackChildrenInto(_wnStorReflowScratch, stackParent)
    for i = 1, nc do
        local c = _wnStorReflowScratch[i]
        if c and c:IsShown() then
            local cb = c:GetBottom()
            if cb and cb < lowest then
                lowest = cb
            end
        end
    end
    local extent = pTop - lowest
    if extent < 1 then
        extent = math.max(0.1, stackParent:GetHeight() or 0.1)
    end
    stackParent:SetHeight(math.max(0.1, extent))
    if outerWrap and outerHeaderH then
        outerWrap:SetHeight(outerHeaderH + stackParent:GetHeight())
    end
end

local function RegisterStorageEvents(parent)
    if parent.storageUpdateHandler then
        return  -- Already registered
    end
    parent.storageUpdateHandler = true
    
    -- WN_ITEM_METADATA_READY: sync redraw when in-place row refresh cannot run (no timer defer).
    -- WN_ITEMS_UPDATED is handled by UI.lua PopulateContent only.
    local function IsWarbandAggregateViewActive()
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not (mf and mf:IsShown() and mf.currentTab == "items") then return false end
        if not (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband") then return false end
        return ns.Utilities and ns.Utilities:IsModuleEnabled("items")
    end
    
    local function RunWarbandStorageEmbedRedraw()
        if not IsWarbandAggregateViewActive() or not parent then return end
        local resultsContainer = parent.resultsContainer
        if resultsContainer and resultsContainer:GetParent() == parent and WarbandNexus.DrawStorageResults then
            local searchText = ""
            if SearchStateManager and SearchStateManager.GetQuery then
                searchText = SearchStateManager:GetQuery("items") or ""
            end
            local contentWidth = ResolveItemsTabScrollContentWidth(parent)
            local contentHeight = WarbandNexus:DrawStorageResults(resultsContainer, 0, contentWidth, searchText)
            resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
            if ns.UI_AnnexResultsToScrollBottom then
                ns.UI_AnnexResultsToScrollBottom(resultsContainer, parent, SIDE_MARGIN, 8)
            end
            local mf2 = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf2 then
                SyncItemsTabScrollChrome(mf2, parent, contentHeight)
            end
        else
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "items", skipCooldown = true, instantPopulate = true })
        end
    end
    
    -- WN_ITEM_METADATA_READY: prefer in-place row text refresh (TryRefreshStorageRowsMetadataInPlace).
    -- Full tree redraw is rate-limited when refs are missing (e.g. before first draw completes).
    local lastMetadataRefreshDraw = 0
    local METADATA_REFRESH_COOLDOWN = 0.12

    WarbandNexus.RegisterMessage(ItemsStorageEmbedEvents, E.ITEM_METADATA_READY, function()
        if not IsWarbandAggregateViewActive() then return end
        local rc = parent.resultsContainer
        if rc and TryRefreshStorageRowsMetadataInPlace(rc) then
            return
        end
        local now = GetTime()
        if now - lastMetadataRefreshDraw < METADATA_REFRESH_COOLDOWN then return end
        lastMetadataRefreshDraw = now
        RunWarbandStorageEmbedRedraw()
    end)
end

ns.UI_RegisterStorageEmbedListeners = RegisterStorageEvents

--- Redraw Storage scroll content only (results container). Skips PopulateContent, scrollChild purge,
--- and UI_MAIN_REFRESH_REQUESTED debounce — use after section toggles for perf.
function WarbandNexus:RedrawStorageResultsOnly()
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "items" then return end
    if not (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband") then return end
    if not (ns.Utilities and ns.Utilities:IsModuleEnabled("items")) then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.resultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = ResolveItemsTabScrollContentWidth(scrollChild)
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery then
        q = SearchStateManager:GetQuery("items") or ""
    end
    local contentHeight = self:DrawStorageResults(rc, 0, width, q)
    rc:SetHeight(math.max(contentHeight or 1, 1))
    if ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(rc, scrollChild, SIDE_MARGIN, 8)
    end
    SyncItemsTabScrollChrome(mf, scrollChild, contentHeight)
end

--- After leaf type section height changes (no full DrawStorageResults), resize results container from layout tail.
function WarbandNexus:SyncStorageResultsLayoutFromTail(resultsContainer)
    if not resultsContainer then return end
    local pad = GetLayout().minBottomSpacing or 0
    local extent = MeasureStorageResultsContentExtent(resultsContainer)
    if extent then
        resultsContainer:SetHeight(math.max(1, extent + pad))
    else
        local tail = resultsContainer._wnStorageLayoutTail
        if tail and resultsContainer.GetTop and tail.GetBottom then
            local pTop = resultsContainer:GetTop()
            local bot = tail:GetBottom()
            if pTop and bot then
                local measured = pTop - bot + pad
                resultsContainer:SetHeight(math.max(1, measured))
            end
        end
    end
    local mf = self.UI and self.UI.mainFrame
    if mf and mf.scroll and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(mf.scroll)
    end
    local sc = mf and mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
    if mf and mf._virtualScrollUpdate then
        mf._virtualScrollUpdate()
    end
    if resultsContainer and ns.UI_AnnexResultsToScrollBottom then
        local sc = resultsContainer:GetParent()
        if sc then
            ns.UI_AnnexResultsToScrollBottom(resultsContainer, sc, SIDE_MARGIN, 8)
        end
    end
end

--- Partial update for Bank > Warband type leaf (avoid full DrawStorageResults on expand/collapse).
function WarbandNexus:_StorageLeafItemMatchesSearch(item, storageSearchText)
    if not storageSearchText or storageSearchText == "" then
        return true
    end
    if issecretvalue and issecretvalue(storageSearchText) then
        return true
    end
    local itemName = SafeLower(item.name)
    local linkStr = item.itemLink or item.link
    local itemLink = SafeLower(linkStr)
    return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
end

function WarbandNexus:_CollectPersonalTypeItems(charKey, typeName)
    local out = {}
    local itemsData = self:GetItemsData(charKey)
    if not itemsData then
        return out
    end
    local function pushBagList(bagList)
        if not bagList then
            return
        end
        for bi = 1, #bagList do
            local item = bagList[bi]
            if item and item.itemID then
                local cid = item.classID
                if not cid then
                    cid = GetItemClassID(item.itemID)
                    item.classID = cid
                end
                if GetItemTypeName(cid) == typeName then
                    out[#out + 1] = item
                end
            end
        end
    end
    pushBagList(itemsData.bags)
    pushBagList(itemsData.bank)
    return out
end

function WarbandNexus:_CollectWarbandTypeItems(typeName)
    local out = {}
    local warbandData = self:GetWarbandBankData()
    if not warbandData or not warbandData.items then
        return out
    end
    for ii = 1, #warbandData.items do
        local item = warbandData.items[ii]
        if item and item.itemID then
            local cid = item.classID
            if not cid then
                cid = GetItemClassID(item.itemID)
                item.classID = cid
            end
            if GetItemTypeName(cid) == typeName then
                out[#out + 1] = item
            end
        end
    end
    return out
end

--- Remove pooled storage row pointers for one leaf's rowsContainer (partial expand/collapse).
--- Must run before ReleasePooledRowsInSubtree so row:GetParent() still matches.
local function PruneStorageRowRefsForRowsContainer(refs, rowsContainer)
    if not refs or not rowsContainer then
        return
    end
    for i = #refs, 1, -1 do
        local row = refs[i]
        if row and row:GetParent() == rowsContainer then
            tremove(refs, i)
        end
    end
end

function WarbandNexus:_RenderStorageLeafRowsQuick(rowsContainer, rowWidth, typeItemsForRows, locTextForItem, storageSearchText, populateRow, resultsContainer)
    if not rowsContainer then
        return 0
    end
    rowsContainer._wnVirtualContentHeight = nil
    local searchActive = storageSearchText
        and storageSearchText ~= ""
        and not (issecretvalue and issecretvalue(storageSearchText))
    local betweenRows = GetLayout().betweenRows or 0
    local stride = STORAGE_ROW_HEIGHT + betweenRows
    local y = 0
    local rowIdx = 0
    local pop = type(populateRow) == "function" and populateRow
    for ti = 1, #typeItemsForRows do
        local item = typeItemsForRows[ti]
        if not searchActive or self:_StorageLeafItemMatchesSearch(item, storageSearchText) then
            rowIdx = rowIdx + 1
            local row = AcquireStorageRow(rowsContainer, rowWidth, STORAGE_ROW_HEIGHT)
            if row then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", rowsContainer, "TOPLEFT", 0, -y)
                row:Show()
                local loc = ""
                if locTextForItem then
                    loc = locTextForItem(item) or ""
                end
                if pop then
                    pcall(pop, row, item, rowIdx, rowWidth, loc)
                end
                row._wnStorageItemRef = item
                row._wnStorageRowIdx = rowIdx
                row._wnStorageLocText = loc
                if resultsContainer and resultsContainer._wnStorageRowRefs then
                    tinsert(resultsContainer._wnStorageRowRefs, row)
                end
                y = y + stride
            end
        end
    end
    if y <= 0 then
        rowsContainer:SetHeight(0.1)
        return 0
    end
    rowsContainer._wnVirtualContentHeight = y
    rowsContainer:SetHeight(math.max(0.1, y))
    return y
end

function WarbandNexus:_ApplyStorageTypeLeafTogglePartial(wrap)
    local mfInv = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local rcInv = mfInv and mfInv.scrollChild and mfInv.scrollChild.resultsContainer
    if not wrap or not wrap._wnStorageLeafMeta then
        self:RedrawStorageResultsOnly()
        return
    end
    local meta = wrap._wnStorageLeafMeta
    local rows = wrap._wnRowsContainer
    if not rows then
        self:RedrawStorageResultsOnly()
        return
    end
    local exp = self:GetStorageTreeExpandState().categories[meta.storageKey] == true
    local TYPE_H = meta.typeHeaderH or StorageSectionLayout.GetTypeSectionHeaderHeight()
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery and meta.searchQueryTabKey then
        q = SearchStateManager:GetQuery(meta.searchQueryTabKey) or ""
    end
    if rcInv and rcInv._wnStorageRowRefs then
        PruneStorageRowRefsForRowsContainer(rcInv._wnStorageRowRefs, rows)
    end
    if exp then
        local items
        if meta.kind == "personal_type" then
            items = self:_CollectPersonalTypeItems(meta.charKey, meta.typeName)
        else
            items = self:_CollectWarbandTypeItems(meta.typeName)
        end
        if not meta.locTextForItem or type(meta.locTextForItem) ~= "function" then
            self:RedrawStorageResultsOnly()
            return
        end
        local h = self:_RenderStorageLeafRowsQuick(rows, meta.rowWidth, items, meta.locTextForItem, q, meta.populateRow, rcInv)
        rows._wnSectionFullH = h
        rows:Show()
        rows:SetHeight(math.max(0.1, h))
        wrap:SetHeight(TYPE_H + math.max(0.1, h))
    else
        if ReleasePooledRowsInSubtree then
            ReleasePooledRowsInSubtree(rows)
        end
        rows:Hide()
        rows:SetHeight(0.1)
        rows._wnSectionFullH = 0
        wrap:SetHeight(TYPE_H + 0.1)
    end
    if rcInv then
        WarbandNexus:SyncStorageResultsLayoutFromTail(rcInv)
    end
end

--============================================================================
-- STORAGE RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawStorageResults(parent, yOffset, width, storageSearchText)
    local mfPaint = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local leafPaintGen = 0
    if mfPaint then
        leafPaintGen = (mfPaint._wnStorageLeafPaintGen or 0) + 1
        mfPaint._wnStorageLeafPaintGen = leafPaintGen
        mfPaint._wnStorageLeafStage = { gen = leafPaintGen, pending = 0 }
    end

    local storageSearchActive = storageSearchText
        and not (issecretvalue and issecretvalue(storageSearchText))
        and storageSearchText ~= ""

    local mfEmbed = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local embedItemsWarband = mfEmbed and mfEmbed.currentTab == "items" and ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband"
    local searchResultTabKey = embedItemsWarband and "items" or "storage"
    local emptyRenderTab = embedItemsWarband and "items" or "storage"

    -- Type leaf toggles: WarbandNexus:_ApplyStorageTypeLeafTogglePartial (CreateCollapsibleHeader calls
    -- onToggle before expand height; see SharedWidgets expand branch).

    local P = ns.Profiler
    local profOn = P and P.enabled
    local function stStart(name)
        if profOn and P.StartSlice then P:StartSlice(P.CAT.UI, name) end
    end
    local function stStop(name)
        if profOn and P.StopSlice then P:StopSlice(P.CAT.UI, name) end
    end

    stStart("Stor_teardown")
    local mfForVirtual = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfForVirtual and ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
    end

    -- Clean up rows created for subheader section containers in previous render.
    if parent._wnStorageAnimatedRows and ReleaseStorageRow then
        for i = 1, #parent._wnStorageAnimatedRows do
            local row = parent._wnStorageAnimatedRows[i]
            if row and row.rowType == "storage" then
                ReleaseStorageRow(row)
            end
        end
    end
    parent._wnStorageAnimatedRows = {}

    -- Clean up old children (headers, section containers, rows) from previous render.
    local recycleBin = ns.UI_RecycleBin
    if ReleasePooledRowsInSubtree then
        ReleasePooledRowsInSubtree(parent)
    end
    local nTop = PackChildrenInto(_wnStorTopScratch, parent)
    for i = 1, nTop do
        local child = _wnStorTopScratch[i]
        if not child._isVirtualRow and not child._wnSkipStorageTeardown then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end
    stStop("Stor_teardown")

    parent._wnStorageApplyRowVisual = nil
    if not parent._wnStorageRowRefs then
        parent._wnStorageRowRefs = {}
    else
        wipe(parent._wnStorageRowRefs)
    end

    local loadIndicator = nil
    local function hideWarbandBanner()
        if loadIndicator then loadIndicator:Hide() end
    end
    --- Delay hiding the Warband "building" banner while staged leaf renders are pending (same generation).
    local function hideDrawIndicatorWithStagingGate()
        if mfPaint and mfPaint._wnStorageLeafStage then
            local st = mfPaint._wnStorageLeafStage
            if st.gen == leafPaintGen and (st.pending or 0) > 0 then
                return
            end
        end
        hideWarbandBanner()
    end
    if embedItemsWarband then
        loadIndicator = EnsureWarbandDrawIndicator(parent)
        if loadIndicator then loadIndicator:Show() end
    end

    local globalRowIdxAll = 0
    --- Vertical chain tail: major headers + type wraps share one anchor stack so sibling layout
    --- tracks section height immediately (instant layout; no tween).
    local storageStackAnchor = nil

    -- Session-only expand state (see WarbandNexus:GetStorageTreeExpandState / ResetStorageTreeExpandState in Core.lua).
    local expanded = self:GetStorageTreeExpandState()

    local function CreateStorageRowsContainer(contentParent, anchorFrame, leftOffset, rightOffset)
        contentParent = contentParent or parent
        local frame = ns.UI.Factory:CreateContainer(contentParent, math.max(1, contentParent:GetWidth()), 1, false)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", leftOffset or 0, 0)
        frame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", rightOffset or 0, 0)
        frame:SetHeight(0.1)
        frame._wnSectionFullH = 0
        return frame
    end

    local TYPE_SECTION_HEADER_H = StorageSectionLayout.GetTypeSectionHeaderHeight()
    local MAIN_SECTION_HEADER_H = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36

    --- After a type (leaf) section height change, section bodies/wraps above the type row stay at initial heights.
    --- Reflow measured stacks so character rows and items below sit below expanded content (not drawn on top).
    --- ctx: { contentBody, sectionWrap, sectionHeaderH, stackParent?, outerSectionWrap?, outerSectionHeaderH? }
    local function ApplyStorageLeafAncestorReflow(ctx)
        if not ctx or not ctx.contentBody or not ctx.sectionWrap or not ctx.sectionHeaderH then return end
        ReflowStorageStackParentBody(ctx.contentBody, ctx.sectionWrap, ctx.sectionHeaderH)
        ctx.contentBody._wnSectionFullH = math.max(0.1, ctx.contentBody:GetHeight() or 0.1)
        if ctx.stackParent and ctx.outerSectionWrap and ctx.outerSectionHeaderH then
            ReflowStorageStackParentBody(ctx.stackParent, ctx.outerSectionWrap, ctx.outerSectionHeaderH)
            ctx.stackParent._wnSectionFullH = math.max(0.1, ctx.stackParent:GetHeight() or 0.1)
        end
        WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
    end

    --- Major section (Personal / Warband / Guild / character): wrapped header + body (instant expand/collapse).
    --- Optional `stackReflowCtx`: { stackParent, outerWrap, outerHeaderH } for nested stacks (Personal → characters).
    local function MajorStorageSectionOpts(wrapFrame, bodyGetter, headerH, persistFn, stackReflowCtx)
        return BuildCollapsibleSectionOpts({
            wrapFrame = wrapFrame,
            bodyGetter = bodyGetter,
            headerHeight = headerH,
            hideOnCollapse = true,
            persistFn = function(exp)
                if type(exp) == "boolean" and persistFn then
                    persistFn(exp)
                end
            end,
            -- Per-frame: outer stack tracks wrap tween; defer full SyncStorageResultsLayoutFromTail to onComplete.
            onUpdate = function(_drawH)
                if stackReflowCtx and stackReflowCtx.stackParent then
                    ReflowStorageStackParentBody(
                        stackReflowCtx.stackParent,
                        stackReflowCtx.outerWrap,
                        stackReflowCtx.outerHeaderH
                    )
                end
            end,
            onComplete = function(exp)
                if not exp then
                    local b = bodyGetter()
                    if b then
                        b:Hide()
                        b:SetHeight(0.1)
                    end
                end
                if stackReflowCtx and stackReflowCtx.stackParent then
                    ReflowStorageStackParentBody(
                        stackReflowCtx.stackParent,
                        stackReflowCtx.outerWrap,
                        stackReflowCtx.outerHeaderH
                    )
                end
                WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            end,
            -- Bodies that were collapsed during this DrawStorageResults pass never ran the inner build; they keep
            -- placeholder _wnSectionFullH (~0.1). CreateCollapsibleHeader expand uses that height and the char
            -- onToggle is a no-op, so rows stay missing until a full tab redraw. Rebuild next frame (defer: avoid
            -- tearing down the clicked header inside its own OnClick).
            refreshFn = function(exp)
                if not exp then return end
                local b = bodyGetter()
                local fh = b and b._wnSectionFullH
                if fh and fh < 2 and C_Timer and C_Timer.After and WarbandNexus.RedrawStorageResultsOnly then
                    C_Timer.After(0, function()
                        WarbandNexus:RedrawStorageResultsOnly()
                    end)
                end
            end,
        })
    end

    --- Leaf type rows live under `rowsContainer`; instant resize without full tab redraw.
    --- Optional `ancestorReflowCtx`: reflow char/warband/guild section + Personal outer after height changes.
    local function LeafTypeSectionVisualOpts(wrapFrame, rowsGetter, leafKey, ancestorReflowCtx)
        return BuildCollapsibleSectionOpts({
            wrapFrame = wrapFrame,
            bodyGetter = rowsGetter,
            headerHeight = TYPE_SECTION_HEADER_H,
            hideOnCollapse = true,
            persistFn = function(exp)
                if type(exp) == "boolean" then
                    expanded.categories[leafKey] = exp
                end
            end,
            onUpdate = function(_drawH)
                if ancestorReflowCtx then
                    ApplyStorageLeafAncestorReflow(ancestorReflowCtx)
                end
            end,
            onComplete = function(exp)
                if not exp then
                    local rc = rowsGetter()
                    if rc then
                        rc:Hide()
                        rc:SetHeight(0.1)
                    end
                end
                if ancestorReflowCtx then
                    ApplyStorageLeafAncestorReflow(ancestorReflowCtx)
                else
                    WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
                end
            end,
        })
    end

    -- Per-draw caches: class/type work repeats per slot; rows duplicate C_Item.GetItemInfo for shared itemIDs (cold chars→storage path).
    local storageDrawClassIDByItemID = {}
    local storageDrawTypeNameByClassID = {}
    local storageDrawItemInfoNameByItemID = {}

    local function ResolvedStorageClassID(entry)
        if entry.classID then return entry.classID end
        local id = entry.itemID
        if not id then return 15 end
        local c = storageDrawClassIDByItemID[id]
        if not c then
            c = GetItemClassID(id)
            storageDrawClassIDByItemID[id] = c
        end
        entry.classID = c
        return c
    end

    local function ResolvedStorageTypeName(classID)
        local t = storageDrawTypeNameByClassID[classID]
        if not t then
            t = GetItemTypeName(classID)
            storageDrawTypeNameByClassID[classID] = t
        end
        return t
    end

    local function PopulateStorageRowDirect(row, item, rowIdx, rowWidth, locText)
        row:SetAlpha(1)
        if row.anim then row.anim:Stop() end
        ns.UI.Factory:ApplyRowBackground(row, rowIdx)

        row.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
        row.icon:SetTexture(item.iconFileID or 134400)

        local baseName = item.name
        if not baseName and item.link and not (issecretvalue and issecretvalue(item.link)) then
            baseName = item.link:match("%[(.-)%]")
        end
        if not baseName and item.pending then
            baseName = (ns.L and ns.L["ITEM_LOADING_NAME"]) or "Loading..."
        end
        if not baseName and item.itemID then
            local iid = item.itemID
            local cachedName = storageDrawItemInfoNameByItemID[iid]
            if cachedName == nil then
                cachedName = C_Item.GetItemInfo(iid) or false
                storageDrawItemInfoNameByItemID[iid] = cachedName
            end
            if cachedName and cachedName ~= false then
                baseName = cachedName
            end
        end
        baseName = baseName or format((ns.L and ns.L["ITEM_FALLBACK_FORMAT"]) or "Item %s", tostring(item.itemID or "?"))

        local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
        if item.pending then
            row.nameText:SetText(format("|cff888888%s|r", displayName))
        else
            row.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
        end

        row.locationText:SetText(locText or "")
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
    
    -- Search filtering helper
    local function ItemMatchesSearch(item)
        if not storageSearchActive then
            return true
        end
        local itemName = SafeLower(item.name)
        local linkStr = item.itemLink or item.link
        local itemLink = SafeLower(linkStr)
        return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
    end

    --- Type-leaf item rows under a collapsible header (`rowsContainer`).
    --- Warband/storage aggregate: small lists sync; larger lists chunked via `STORAGE_LEAF_ROW_*` + paint generation cancel (`WN-PERF-warband-nexus`).
    local function RenderStorageLeafRows(rowsContainer, rowWidth, typeItemsForRows, locTextForItem)
        rowsContainer._wnVirtualContentHeight = nil
        if not rowsContainer then
            return 0
        end
        local betweenRows = GetLayout().betweenRows or 0
        local stride = STORAGE_ROW_HEIGHT + betweenRows

        local matchN = 0
        for mxi = 1, #typeItemsForRows do
            if ItemMatchesSearch(typeItemsForRows[mxi]) then
                matchN = matchN + 1
            end
        end
        if matchN <= 0 then
            rowsContainer:SetHeight(0.1)
            rowsContainer._wnStorageLeafStaging = nil
            return 0
        end

        local function finalizeSyncedHeight(yy)
            if yy <= 0 then
                rowsContainer:SetHeight(0.1)
                return 0
            end
            rowsContainer._wnVirtualContentHeight = yy
            rowsContainer:SetHeight(math.max(0.1, yy))
            return yy
        end

        if matchN <= STORAGE_LEAF_ROW_SYNC_MAX then
            local yy = 0
            for ti = 1, #typeItemsForRows do
                local item = typeItemsForRows[ti]
                if ItemMatchesSearch(item) then
                    globalRowIdxAll = globalRowIdxAll + 1
                    local row = AcquireStorageRow(rowsContainer, rowWidth, STORAGE_ROW_HEIGHT)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", rowsContainer, "TOPLEFT", 0, -yy)
                    row:Show()
                    pcall(PopulateStorageRowDirect, row, item, globalRowIdxAll, rowWidth, locTextForItem(item))
                    row._wnStorageItemRef = item
                    row._wnStorageRowIdx = globalRowIdxAll
                    row._wnStorageLocText = locTextForItem(item) or ""
                    table.insert(parent._wnStorageRowRefs, row)
                    yy = yy + stride
                end
            end
            rowsContainer._wnStorageLeafStaging = nil
            return finalizeSyncedHeight(yy)
        end

        local reservedH = matchN * stride
        rowsContainer:SetHeight(math.max(0.1, reservedH))
        rowsContainer._wnVirtualContentHeight = reservedH
        rowsContainer._wnStorageLeafStaging = true

        local stPatch = mfPaint and mfPaint._wnStorageLeafStage
        if stPatch and stPatch.gen == leafPaintGen then
            stPatch.pending = (stPatch.pending or 0) + 1
        end

        local leafCreditConsumed = false
        local function consumeLeafStagingCredit()
            if leafCreditConsumed then return end
            leafCreditConsumed = true
            local st = mfPaint and mfPaint._wnStorageLeafStage
            if st and st.gen == leafPaintGen then
                st.pending = math.max(0, (st.pending or 1) - 1)
                if st.pending <= 0 then
                    hideWarbandBanner()
                end
            end
        end

        local function chromeAfterChunk()
            WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            if embedItemsWarband and mfPaint then
                local sc = parent:GetParent()
                if sc then
                    local ext = MeasureStorageResultsContentExtent(parent)
                    SyncItemsTabScrollChrome(mfPaint, sc, ext or (parent.GetHeight and parent:GetHeight()) or 1)
                end
            end
        end

        local tiCursor = 1
        local yAcc = 0
        local function processChunk()
            if not mfPaint or mfPaint._wnStorageLeafPaintGen ~= leafPaintGen then
                consumeLeafStagingCredit()
                return
            end
            if InCombatLockdown and InCombatLockdown() then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, processChunk)
                end
                return
            end

            local emittedThis = 0
            while tiCursor <= #typeItemsForRows do
                if emittedThis >= STORAGE_LEAF_ROW_CHUNK then
                    break
                end
                local item = typeItemsForRows[tiCursor]
                tiCursor = tiCursor + 1
                if ItemMatchesSearch(item) then
                    globalRowIdxAll = globalRowIdxAll + 1
                    local row = AcquireStorageRow(rowsContainer, rowWidth, STORAGE_ROW_HEIGHT)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", rowsContainer, "TOPLEFT", 0, -yAcc)
                    row:Show()
                    pcall(PopulateStorageRowDirect, row, item, globalRowIdxAll, rowWidth, locTextForItem(item))
                    row._wnStorageItemRef = item
                    row._wnStorageRowIdx = globalRowIdxAll
                    row._wnStorageLocText = locTextForItem(item) or ""
                    table.insert(parent._wnStorageRowRefs, row)
                    yAcc = yAcc + stride
                    emittedThis = emittedThis + 1
                end
            end

            rowsContainer._wnVirtualContentHeight = math.max(yAcc, 1)
            rowsContainer:SetHeight(math.max(0.1, reservedH))
            chromeAfterChunk()

            if tiCursor > #typeItemsForRows then
                rowsContainer._wnVirtualContentHeight = yAcc
                rowsContainer:SetHeight(math.max(0.1, yAcc))
                rowsContainer._wnStorageLeafStaging = nil
                consumeLeafStagingCredit()
                chromeAfterChunk()
                return
            end

            if C_Timer and C_Timer.After then
                C_Timer.After(0, processChunk)
            else
                processChunk()
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0, processChunk)
        else
            processChunk()
        end

        return reservedH
    end
    
    stStart("Stor_scan")
    -- PRE-SCAN: If search is active, find which categories have matches
    local categoriesWithMatches = {}
    local hasAnyMatches = false
    local allCharacters = self:GetAllCharacters() or {}
    local trackedCharacters = {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        if char.isTracked ~= false then
            trackedCharacters[#trackedCharacters + 1] = char
        end
    end

    -- Search: personal/warband match counts from pre-scan. No-search: personal tallied with hasAnyData pass; warband from grouped data below.
    local personalTotalMatches = 0
    local warbandTotalMatches = 0
    
    if storageSearchActive then
        -- Scan Warband Bank (NEW ItemsCacheService API)
        local warbandData = self:GetWarbandBankData()
        if warbandData and warbandData.items then
            local wbItems = warbandData.items
            for ii = 1, #wbItems do
                local item = wbItems[ii]
                if item.itemID and ItemMatchesSearch(item) then
                    local classID = ResolvedStorageClassID(item)
                    local typeName = ResolvedStorageTypeName(classID)
                    local categoryKey = "warband_" .. typeName
                    categoriesWithMatches[categoryKey] = true
                    categoriesWithMatches["warband"] = true
                    hasAnyMatches = true
                    warbandTotalMatches = warbandTotalMatches + 1
                end
            end
        end
        
        -- Scan Personal Items (Bank + Bags) (NEW ItemsCacheService API)
        -- Direct DB access (DB-First pattern)
        local characters = trackedCharacters
        
        for ci = 1, #characters do
            local char = characters[ci]
            local charKey = char._key
            local itemsData = self:GetItemsData(charKey)
            if itemsData then
                -- Scan bags
                if itemsData.bags then
                    local bags = itemsData.bags
                    for bi = 1, #bags do
                        local item = bags[bi]
                        if item.itemID and ItemMatchesSearch(item) then
                            local classID = ResolvedStorageClassID(item)
                            local typeName = ResolvedStorageTypeName(classID)
                            local charCategoryKey = "personal_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["personal"] = true
                            hasAnyMatches = true
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
                
                -- Scan bank
                if itemsData.bank then
                    local bankItems = itemsData.bank
                    for bi = 1, #bankItems do
                        local item = bankItems[bi]
                        if item.itemID and ItemMatchesSearch(item) then
                            local classID = ResolvedStorageClassID(item)
                            local typeName = ResolvedStorageTypeName(classID)
                            local charCategoryKey = "personal_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["personal"] = true
                            hasAnyMatches = true
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
            end
        end
        
    end
    
    -- If search is active but no matches, show empty state and return
    if storageSearchActive and not hasAnyMatches then
        stStop("Stor_scan")
        hideDrawIndicatorWithStagingGate()
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, storageSearchText, emptyRenderTab)
        -- Update SearchStateManager with result count
        SearchStateManager:UpdateResults(searchResultTabKey, 0)
        return height
    end
    
    -- Quick check for general "no data" empty state (no search). Also tally personal item rows once.
    if not storageSearchActive then
        local hasAnyData = false

        local warbandData = self:GetWarbandBankData()
        if warbandData and warbandData.items and #warbandData.items > 0 then
            hasAnyData = true
        end

        for i = 1, #trackedCharacters do
            local char = trackedCharacters[i]
            local itemsData = self:GetItemsData(char._key)
            if itemsData then
                local bagN = itemsData.bags and #itemsData.bags or 0
                local bankN = itemsData.bank and #itemsData.bank or 0
                personalTotalMatches = personalTotalMatches + bagN + bankN
                if bagN > 0 or bankN > 0 then
                    hasAnyData = true
                end
            end
        end

        if not hasAnyData then
            stStop("Stor_scan")
            hideDrawIndicatorWithStagingGate()
            local _, height = CreateEmptyStateCard(parent, "storage", yOffset)
            SearchStateManager:UpdateResults(searchResultTabKey, 0)
            return height
        end
    end
    
    stStop("Stor_scan")
    
    -- ===== PERSONAL BANKS SECTION =====
    local characters = trackedCharacters
    
    -- Only render Personal Banks section if it has matching items
    stStart("Stor_personal")
    if personalTotalMatches > 0 then
        -- Default collapsed; expand-all / search matches override.
        local personalExpanded = (self.storageExpandAllActive == true) or (expanded.personal == true)
        if storageSearchActive and categoriesWithMatches["personal"] then
            personalExpanded = true
        end
        
        local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon

        local personalWrap = ns.UI.Factory:CreateContainer(parent, math.max(1, width), MAIN_SECTION_HEADER_H + 0.1, false)
        personalWrap:ClearAllPoints()
        if personalWrap.SetClipsChildren then
            personalWrap:SetClipsChildren(true)
        end
        ChainSectionFrameBelow(parent, personalWrap, storageStackAnchor, 0, storageStackAnchor and SECTION_SPACING or nil, yOffset)

        local personalBody
        local personalHeader = CreateCollapsibleHeader(
            personalWrap,
            (ns.L and ns.L["PERSONAL_ITEMS"]) or "Personal Items",
            "personal",
            personalExpanded,
            function() end,
            GetCharacterSpecificIcon(),
            true,
            nil,
            nil,
            MajorStorageSectionOpts(personalWrap, function() return personalBody end, MAIN_SECTION_HEADER_H, function(exp)
                expanded.personal = exp
            end)
        )
        personalHeader:SetPoint("TOPLEFT", personalWrap, "TOPLEFT", 0, 0)
        personalHeader:SetWidth(width)

        personalBody = ns.UI.Factory:CreateContainer(personalWrap, math.max(1, width), 0.1, false)
        personalBody:ClearAllPoints()
        personalBody:SetPoint("TOPLEFT", personalHeader, "BOTTOMLEFT", 0, 0)
        personalBody:SetPoint("TOPRIGHT", personalHeader, "BOTTOMRIGHT", 0, 0)

        local personalInnerTail = nil
        local personalInnerAccum = 0

        if personalExpanded then
        yOffset = yOffset + HEADER_SPACING
        local hasAnyPersonalItems = false

        -- Direct DB access (DB-First pattern) (tracked only)
        local characters = {}
        for i = 1, #trackedCharacters do
            characters[i] = trackedCharacters[i]
        end
        
        -- Sort Characters
        local sortMode = self.db.profile.storageSort and self.db.profile.storageSort.key
        if sortMode and sortMode ~= "manual" then
            table.sort(characters, function(a, b)
                if sortMode == "name" then
                    return CompareCharNameLower(a, b)
                elseif sortMode == "level" then
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return CompareCharNameLower(a, b)
                elseif sortMode == "ilvl" then
                    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
                    return CompareCharNameLower(a, b)
                elseif sortMode == "gold" then
                    local goldA = ns.Utilities:GetCharTotalCopper(a)
                    local goldB = ns.Utilities:GetCharTotalCopper(b)
                    if goldA ~= goldB then return goldA > goldB end
                    return CompareCharNameLower(a, b)
                elseif sortMode == "realm" then
                    local ra = SafeLower(a.realm or "")
                    local rb = SafeLower(b.realm or "")
                    if ra ~= rb then return ra < rb end
                    return CompareCharNameLower(a, b)
                end
                return (a.level or 0) > (b.level or 0)
            end)
        else
            -- Manual order or default
            local customOrder = self.db.profile.characterOrder and self.db.profile.characterOrder.regular or {}
            if #customOrder > 0 then
                local ordered, charMap = {}, {}
                for ci = 1, #characters do
                    local c = characters[ci]
                    local ck = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(c.name, c.realm)
                    if ck then charMap[ck] = c end
                end
                for coi = 1, #customOrder do
                    local ck = customOrder[coi]
                    if charMap[ck] then table.insert(ordered, charMap[ck]); charMap[ck] = nil end
                end
                local remaining = {}
                for _, c in pairs(charMap) do table.insert(remaining, c) end
                table.sort(remaining, function(a, b)
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return CompareCharNameLower(a, b)
                end)
                for ri = 1, #remaining do table.insert(ordered, remaining[ri]) end
                characters = ordered
            else
                table.sort(characters, function(a, b)
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return CompareCharNameLower(a, b)
                end)
            end
        end
        
        for ci = 1, #characters do
            local char = characters[ci]
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
                if storageSearchActive and not categoriesWithMatches[charCategoryKey] then
                    -- Skip this character
                else
                    -- Default collapsed; expand-all / search matches override.
                    local isCharExpanded = (self.storageExpandAllActive == true) or (expanded.categories[charCategoryKey] == true)
                    if storageSearchActive and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if char.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. char.classFile
                    end
                    
                    -- Character block: wrapped header + body (major section); types always built inside body.
                    local charIndent = BASE_INDENT * 1  -- 15px
                    local charWrap = ns.UI.Factory:CreateContainer(personalBody, math.max(1, width - charIndent), MAIN_SECTION_HEADER_H + 0.1, false)
                    charWrap:ClearAllPoints()
                    if charWrap.SetClipsChildren then
                        charWrap:SetClipsChildren(true)
                    end
                    if personalInnerTail then
                        ChainSectionFrameBelow(personalBody, charWrap, personalInnerTail, charIndent, SECTION_SPACING, nil)
                    else
                        ChainSectionFrameBelow(personalBody, charWrap, nil, charIndent, nil, SECTION_SPACING)
                    end

                    local charBody
                    local charHeader, charBtn = CreateCollapsibleHeader(
                        charWrap,
                        (charDisplayName or charKey),
                        charCategoryKey,
                        isCharExpanded,
                        function() end,
                        charIcon,
                        false,
                        1,
                        nil,
                        MajorStorageSectionOpts(charWrap, function() return charBody end, MAIN_SECTION_HEADER_H, function(exp)
                            expanded.categories[charCategoryKey] = exp
                        end, {
                            stackParent = personalBody,
                            outerWrap = personalWrap,
                            outerHeaderH = MAIN_SECTION_HEADER_H,
                        })
                    )
                    charHeader:SetPoint("TOPLEFT", charWrap, "TOPLEFT", 0, 0)
                    charHeader:SetWidth(charWrap:GetWidth())

                    charBody = ns.UI.Factory:CreateContainer(charWrap, math.max(1, charWrap:GetWidth()), 0.1, false)
                    charBody:ClearAllPoints()
                    charBody:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
                    charBody:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)

                    local charBodyAdvance = SECTION_SPACING
                    if isCharExpanded then
                    local stackAnchor = nil
                    local gapBelowStack = SECTION_SPACING
                    -- Group character's items by type (NEW: Array-based iteration)
                    local charItems = {}
                    
                    -- Process bags
                    if itemsData.bags then
                        local bags = itemsData.bags
                        for bi = 1, #bags do
                            local item = bags[bi]
                            if item.itemID then
                                local classID = ResolvedStorageClassID(item)
                                local typeName = ResolvedStorageTypeName(classID)

                                if not charItems[typeName] then
                                    charItems[typeName] = {}
                                end
                                table.insert(charItems[typeName], item)
                            end
                        end
                    end
                    
                    -- Process bank
                    if itemsData.bank then
                        local bankItems = itemsData.bank
                        for bi = 1, #bankItems do
                            local item = bankItems[bi]
                            if item.itemID then
                                local classID = ResolvedStorageClassID(item)
                                local typeName = ResolvedStorageTypeName(classID)

                                if not charItems[typeName] then
                                    charItems[typeName] = {}
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
                        if storageSearchActive then
                            local typeItems = charItems[typeName]
                            for ti = 1, #typeItems do
                                local item = typeItems[ti]
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
                    for sti = 1, #charSortedTypes do
                        local typeName = charSortedTypes[sti]
                        local typeKey = "personal_" .. charKey .. "_" .. typeName
                        
                        -- Skip category if search active and no matches
                        if storageSearchActive and not categoriesWithMatches[typeKey] then
                            -- Skip this category
                        else
                            -- Default collapsed; expand-all / search matches override.
                            local isTypeExpanded = (self.storageExpandAllActive == true) or (expanded.categories[typeKey] == true)
                            if storageSearchActive and categoriesWithMatches[typeKey] then
                                isTypeExpanded = true
                            end
                            
                            -- Count items that match search (for display)
                            local matchCount = 0
                            local typeItemsForCount = charItems[typeName]
                            for ti = 1, #typeItemsForCount do
                                local item = typeItemsForCount[ti]
                                if ItemMatchesSearch(item) then
                                    matchCount = matchCount + 1
                                end
                            end
                            
                            -- Calculate display count
                            local displayCount = (storageSearchActive) and matchCount or #charItems[typeName]
                            
                            -- Skip header if it has no items to show
                            if displayCount == 0 then
                                -- Skip this empty header
                            else
                                -- Get icon from first item in category
                                local typeIcon2 = nil
                                if charItems[typeName][1] and charItems[typeName][1].classID then
                                    typeIcon2 = GetTypeIcon(charItems[typeName][1].classID)
                                end
                                
                                -- Type header + rows: synchronous leaf rows (see RenderStorageLeafRows).
                                local typeIndent = BASE_INDENT * 2  -- 30px
                                local typeSectionWrap = ns.UI.Factory:CreateContainer(charBody, math.max(1, charBody:GetWidth() - typeIndent), TYPE_SECTION_HEADER_H + 0.1, false)
                                typeSectionWrap:ClearAllPoints()
                                if typeSectionWrap.SetClipsChildren then
                                    typeSectionWrap:SetClipsChildren(true)
                                end
                                if stackAnchor then
                                    ChainSectionFrameBelow(charBody, typeSectionWrap, stackAnchor, typeIndent, gapBelowStack, nil)
                                else
                                    ChainSectionFrameBelow(charBody, typeSectionWrap, nil, typeIndent, nil, SECTION_SPACING)
                                end
                                gapBelowStack = SECTION_SPACING
                                stackAnchor = typeSectionWrap

                                local leafAncestorCtxPersonal = {
                                    contentBody = charBody,
                                    sectionWrap = charWrap,
                                    sectionHeaderH = MAIN_SECTION_HEADER_H,
                                    stackParent = personalBody,
                                    outerSectionWrap = personalWrap,
                                    outerSectionHeaderH = MAIN_SECTION_HEADER_H,
                                }
                                local function locTextForPersonalStorageItem(item)
                                    if not item then
                                        return ""
                                    end
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
                                    return locText
                                end

                                local rowsContainer
                                local typeHeader2, typeBtn2 = CreateCollapsibleHeader(
                                typeSectionWrap,
                                typeName .. " (" .. FormatNumber(displayCount) .. ")",
                                typeKey,
                                isTypeExpanded,
                                function()
                                    WarbandNexus:_ApplyStorageTypeLeafTogglePartial(typeSectionWrap)
                                end,
                                typeIcon2,
                                false,  -- isAtlas = false (item icons are texture paths)
                                0,      -- indent in wrap only; typeSectionWrap already offset under character header
                                nil,
                                LeafTypeSectionVisualOpts(typeSectionWrap, function() return rowsContainer end, typeKey, leafAncestorCtxPersonal)
                            )
                            typeHeader2:SetPoint("TOPLEFT", typeSectionWrap, "TOPLEFT", 0, 0)
                            typeHeader2:SetWidth(typeSectionWrap:GetWidth())
                            rowsContainer = CreateStorageRowsContainer(typeSectionWrap, typeHeader2, 0, 0)
                            -- Match typeSectionWrap width (charBody full width minus typeIndent); warband path uses the same idea.
                            local rowWidthPersonal = math.max(1, width - charIndent - typeIndent)
                            local typeItemsForRows = charItems[typeName]
                            local rowsYOffset
                            if isTypeExpanded then
                                rowsYOffset = RenderStorageLeafRows(rowsContainer, rowWidthPersonal, typeItemsForRows, locTextForPersonalStorageItem)
                            else
                                rowsYOffset = 0
                            end
                            rowsContainer._wnSectionFullH = rowsYOffset
                            if isTypeExpanded then
                                rowsContainer:Show()
                                rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                            else
                                rowsContainer:Hide()
                                rowsContainer:SetHeight(0.1)
                            end
                            typeSectionWrap:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                            typeSectionWrap._wnRowsContainer = rowsContainer
                            typeSectionWrap._wnStorageLeafMeta = {
                                storageKey = typeKey,
                                kind = "personal_type",
                                charKey = charKey,
                                typeName = typeName,
                                rowWidth = rowWidthPersonal,
                                typeHeaderH = TYPE_SECTION_HEADER_H,
                                locTextForItem = locTextForPersonalStorageItem,
                                populateRow = PopulateStorageRowDirect,
                                searchQueryTabKey = searchResultTabKey,
                            }
                            charBodyAdvance = charBodyAdvance + typeSectionWrap:GetHeight() + SECTION_SPACING
                            end  -- if displayCount > 0
                        end  -- if not skipped by search
                    end
                    end

                    local charInnerH = math.max(0.1, charBodyAdvance - SECTION_SPACING)
                    charBody._wnSectionFullH = charInnerH
                    if isCharExpanded then
                        charBody:Show()
                        charBody:SetHeight(charInnerH)
                    else
                        charBody:Hide()
                        charBody:SetHeight(0.1)
                    end
                    charWrap:SetHeight(MAIN_SECTION_HEADER_H + charBody:GetHeight())
                    personalInnerAccum = personalInnerAccum + charWrap:GetHeight() + SECTION_SPACING
                    personalInnerTail = charWrap

                hasAnyPersonalItems = true
            end  -- else (closes the else at line 449)
        end  -- if itemsData
        end  -- for char

        personalBody._wnSectionFullH = math.max(0.1, personalInnerAccum - SECTION_SPACING)
        personalBody:Show()
        personalBody:SetHeight(personalBody._wnSectionFullH)
        else
            personalBody._wnSectionFullH = 0.1
            personalBody:Hide()
            personalBody:SetHeight(0.1)
        end
        personalWrap:SetHeight(MAIN_SECTION_HEADER_H + personalBody:GetHeight())
        storageStackAnchor = personalWrap
    end  -- if personalTotalMatches > 0
    stStop("Stor_personal")
    
    stStart("Stor_warband")
    -- Warband Bank: default collapsed. Skip per-item class/type grouping when collapsed + no search (large banks).
    local warbandExpanded = (self.storageExpandAllActive == true) or (expanded.warband == true)
    if storageSearchActive and categoriesWithMatches["warband"] then
        warbandExpanded = true
    end

    local warbandItems = {}
    local warbandData = self:GetWarbandBankData()

    if warbandData and warbandData.items then
        local wbItems2 = warbandData.items
        -- Items > Warband embed: always build type index (WN-PERF: collapsed-only fast path leaves an empty body).
        local needWarbandTypeIndex = embedItemsWarband or warbandExpanded or (storageSearchActive and categoriesWithMatches["warband"])
        if storageSearchActive and not categoriesWithMatches["warband"] and not warbandExpanded and not embedItemsWarband then
            -- No warband search hits and body collapsed: avoid scanning thousands of slots for grouping.
        elseif needWarbandTypeIndex then
            for ii = 1, #wbItems2 do
                local item = wbItems2[ii]
                if item.itemID then
                    if storageSearchActive and not ItemMatchesSearch(item) then
                        -- Index only matches when a filter is active.
                    else
                        local classID = ResolvedStorageClassID(item)
                        local typeName = ResolvedStorageTypeName(classID)
                        if not warbandItems[typeName] then
                            warbandItems[typeName] = {}
                        end
                        table.insert(warbandItems[typeName], item)
                    end
                end
            end
            warbandTotalMatches = 0
            for _tn, items in pairs(warbandItems) do
                warbandTotalMatches = warbandTotalMatches + #items
            end
        else
            -- Collapsed, no search: item count only (no GetItemClassID / type tables).
            local nwb = 0
            for jj = 1, #wbItems2 do
                if wbItems2[jj] and wbItems2[jj].itemID then
                    nwb = nwb + 1
                end
            end
            warbandTotalMatches = nwb
        end
    end

    -- Only render Warband Bank section if it has matching items
    if warbandTotalMatches > 0 then
        local warbandWrap = ns.UI.Factory:CreateContainer(parent, math.max(1, width), MAIN_SECTION_HEADER_H + 0.1, false)
        warbandWrap:ClearAllPoints()
        if warbandWrap.SetClipsChildren then
            warbandWrap:SetClipsChildren(true)
        end
        ChainSectionFrameBelow(parent, warbandWrap, storageStackAnchor, 0, storageStackAnchor and SECTION_SPACING or nil, yOffset)

        local warbandBody
        local warbandHeader, expandBtn, warbandIcon = CreateCollapsibleHeader(
            warbandWrap,
            (ns.L and ns.L["STORAGE_WARBAND_BANK"]) or "Warband Bank",
            "warband",
            warbandExpanded,
            function() end,
            "dummy",
            false,
            nil,
            nil,
            MajorStorageSectionOpts(warbandWrap, function() return warbandBody end, MAIN_SECTION_HEADER_H, function(exp)
                expanded.warband = exp
            end)
        )
        warbandHeader:SetPoint("TOPLEFT", warbandWrap, "TOPLEFT", 0, 0)
        warbandHeader:SetWidth(width)

        warbandBody = ns.UI.Factory:CreateContainer(warbandWrap, math.max(1, width), 0.1, false)
        warbandBody:ClearAllPoints()
        warbandBody:SetPoint("TOPLEFT", warbandHeader, "BOTTOMLEFT", 0, 0)
        warbandBody:SetPoint("TOPRIGHT", warbandHeader, "BOTTOMRIGHT", 0, 0)

        -- Replace with Warband atlas icon (27x36 for proper aspect ratio)
        if warbandIcon then
            warbandIcon:SetTexture(nil)  -- Clear dummy texture
            warbandIcon:SetAtlas("warbands-icon")
            warbandIcon:SetSize(27, 36)  -- Native atlas proportions (23:31)
        end

        local warbandBodyAdvance = SECTION_SPACING
        if warbandExpanded then
        local stackAnchor = nil
        local gapBelowStack = SECTION_SPACING
        -- Sort types alphabetically
            local sortedTypes = {}
            for typeName in pairs(warbandItems) do
                -- Only include types that have matching items
                local hasMatchingItems = false
                if storageSearchActive then
                    local wbTypeItems = warbandItems[typeName]
                    for wi = 1, #wbTypeItems do
                        local item = wbTypeItems[wi]
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
        for sti = 1, #sortedTypes do
            local typeName = sortedTypes[sti]
            local categoryKey = "warband_" .. typeName
            -- Items > Warband embed: default type groups to expanded when state is unset (nil), so rows
            -- appear after the per-subtab reset in UI.lua; explicit false preserves user collapse.
            if embedItemsWarband and not storageSearchActive and expanded.categories[categoryKey] == nil then
                expanded.categories[categoryKey] = true
            end

            -- Skip category if search active and no matches
            if storageSearchActive and not categoriesWithMatches[categoryKey] then
                -- Skip this category
            else
                -- Default collapsed; expand-all / search matches override.
                local isTypeExpanded = (self.storageExpandAllActive == true) or (expanded.categories[categoryKey] == true)
                if storageSearchActive and categoriesWithMatches[categoryKey] then
                    isTypeExpanded = true
                end
                
                -- Count items that match search (for display)
                local matchCount = 0
                local wbTypeItems2 = warbandItems[typeName]
                for wi = 1, #wbTypeItems2 do
                    local item = wbTypeItems2[wi]
                    if ItemMatchesSearch(item) then
                        matchCount = matchCount + 1
                    end
                end
                
                -- Calculate display count
                local displayCount = (storageSearchActive) and matchCount or #warbandItems[typeName]
                
                -- Skip header if it has no items to show
                if displayCount == 0 then
                    -- Skip this empty header
                else
                    -- Get icon from first item in category
                    local typeIcon = nil
                    if warbandItems[typeName][1] and warbandItems[typeName][1].classID then
                        typeIcon = GetTypeIcon(warbandItems[typeName][1].classID)
                    end
                    
                    local typeIndentWB = BASE_INDENT
                    local typeSectionWrapWB = ns.UI.Factory:CreateContainer(warbandBody, math.max(1, warbandBody:GetWidth() - typeIndentWB), TYPE_SECTION_HEADER_H + 0.1, false)
                    typeSectionWrapWB:ClearAllPoints()
                    if typeSectionWrapWB.SetClipsChildren then
                        typeSectionWrapWB:SetClipsChildren(true)
                    end
                    if stackAnchor then
                        ChainSectionFrameBelow(warbandBody, typeSectionWrapWB, stackAnchor, typeIndentWB, gapBelowStack, nil)
                    else
                        ChainSectionFrameBelow(warbandBody, typeSectionWrapWB, nil, typeIndentWB, nil, SECTION_SPACING)
                    end
                    gapBelowStack = SECTION_SPACING
                    stackAnchor = typeSectionWrapWB

                    local leafAncestorCtxWarband = {
                        contentBody = warbandBody,
                        sectionWrap = warbandWrap,
                        sectionHeaderH = MAIN_SECTION_HEADER_H,
                    }
                    local function locTextForWarbandStorageItem(item)
                        if not item then
                            return ""
                        end
                        return item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex) or ""
                    end

                    local rowsContainer
                    local typeHeader, typeBtn = CreateCollapsibleHeader(
                        typeSectionWrapWB,
                        typeName .. " (" .. FormatNumber(displayCount) .. ")",
                        categoryKey,
                        isTypeExpanded,
                        function()
                            WarbandNexus:_ApplyStorageTypeLeafTogglePartial(typeSectionWrapWB)
                        end,
                        typeIcon,
                        false,
                        nil,
                        nil,
                        LeafTypeSectionVisualOpts(typeSectionWrapWB, function() return rowsContainer end, categoryKey, leafAncestorCtxWarband)
                    )
                    typeHeader:SetPoint("TOPLEFT", typeSectionWrapWB, "TOPLEFT", 0, 0)
                    typeHeader:SetWidth(typeSectionWrapWB:GetWidth())
                    rowsContainer = CreateStorageRowsContainer(typeSectionWrapWB, typeHeader, 0, 0)
                    local rowWidthWB = width - BASE_INDENT
                    local wbTypeItems3 = warbandItems[typeName]
                    local rowsYOffset
                    if isTypeExpanded then
                        rowsYOffset = RenderStorageLeafRows(rowsContainer, rowWidthWB, wbTypeItems3, locTextForWarbandStorageItem)
                    else
                        rowsYOffset = 0
                    end
                    rowsContainer._wnSectionFullH = rowsYOffset
                    if isTypeExpanded then
                        rowsContainer:Show()
                        rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                    else
                        rowsContainer:Hide()
                        rowsContainer:SetHeight(0.1)
                    end
                    typeSectionWrapWB:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                    typeSectionWrapWB._wnRowsContainer = rowsContainer
                    typeSectionWrapWB._wnStorageLeafMeta = {
                        storageKey = categoryKey,
                        kind = "warband_type",
                        typeName = typeName,
                        rowWidth = rowWidthWB,
                        typeHeaderH = TYPE_SECTION_HEADER_H,
                        locTextForItem = locTextForWarbandStorageItem,
                        populateRow = PopulateStorageRowDirect,
                        searchQueryTabKey = searchResultTabKey,
                    }
                    warbandBodyAdvance = warbandBodyAdvance + typeSectionWrapWB:GetHeight() + SECTION_SPACING
                end  -- if displayCount > 0
            end  -- if not skipped by search
        end

        warbandBody._wnSectionFullH = math.max(0.1, warbandBodyAdvance - SECTION_SPACING)
        warbandBody:Show()
        warbandBody:SetHeight(warbandBody._wnSectionFullH)
        else
            warbandBody._wnSectionFullH = 0.1
            warbandBody:Hide()
            warbandBody:SetHeight(0.1)
        end
        warbandWrap:SetHeight(MAIN_SECTION_HEADER_H + warbandBody:GetHeight())
        storageStackAnchor = warbandWrap
    end  -- if warbandTotalMatches > 0
    
    stStop("Stor_warband")
    local stageNow = mfPaint and mfPaint._wnStorageLeafStage
    local hasAsyncLeaves = stageNow and stageNow.gen == leafPaintGen and (stageNow.pending or 0) > 0
    if (parent._wnStorageRowRefs and #parent._wnStorageRowRefs > 0) or hasAsyncLeaves then
        parent._wnStorageApplyRowVisual = function(row, item, rowIdx, rowWidth, locText)
            PopulateStorageRowDirect(row, item, rowIdx, rowWidth, locText)
        end
    else
        parent._wnStorageApplyRowVisual = nil
    end
    local pad = GetLayout().minBottomSpacing or 0
    parent._wnStorageLayoutTail = storageStackAnchor
    local extent = MeasureStorageResultsContentExtent(parent)
    if extent then
        hideDrawIndicatorWithStagingGate()
        return math.max(1, extent + pad, yOffset + pad)
    end
    if storageStackAnchor and parent.GetTop and storageStackAnchor.GetBottom then
        local pTop = parent:GetTop()
        local bot = storageStackAnchor:GetBottom()
        if pTop and bot then
            local measured = pTop - bot + pad
            hideDrawIndicatorWithStagingGate()
            return math.max(1, measured, yOffset + pad)
        end
    end
    hideDrawIndicatorWithStagingGate()
    return yOffset + pad
end -- DrawStorageResults

-- Light-weight Items sub-tab switch: updates gold/stats + results only (avoids full PopulateContent / header rebuild).
local function ApplyItemsSubTabGoldDisplay(goldDisplay, currentItemsSubTab)
    if not goldDisplay then return end
    local FormatMoney = ns.UI_FormatMoney
    if currentItemsSubTab == "personal" then
        goldDisplay:Hide()
        return
    end
    goldDisplay:Show()
    if currentItemsSubTab == "warband" then
        local warbandGold = ns.Utilities:GetWarbandBankMoney() or 0
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(warbandGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(warbandGold))
        end
    elseif currentItemsSubTab == "guild" then
        if IsInGuild() then
            local guildName = GetGuildInfo("player")
            if guildName and issecretvalue and issecretvalue(guildName) then guildName = nil end
            local guildGold = nil
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
                goldDisplay:SetText("|cff888888" .. ((ns.L and ns.L["NO_SCAN"]) or "Not scanned") .. "|r")
            end
        else
            goldDisplay:SetText("|cff888888" .. ((ns.L and ns.L["NOT_IN_GUILD"]) or "Not in guild") .. "|r")
        end
    elseif currentItemsSubTab == "inventory" then
        local charGold = ns.Utilities:GetLiveCharacterMoneyCopper(0)
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(charGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(charGold))
        end
    elseif goldDisplay:IsShown() then
        goldDisplay:SetText("")
    end
end

local function ApplyItemsSubTabStatsText(addon, statsText, currentItemsSubTab)
    if not statsText then return end
    local items = {}
    if currentItemsSubTab == "warband" then
        items = addon:GetWarbandBankItems() or {}
    elseif currentItemsSubTab == "guild" then
        items = addon:GetGuildBankItems() or {}
    elseif currentItemsSubTab == "inventory" then
        items = addon:GetInventoryItems() or {}
    elseif currentItemsSubTab == "personal" then
        items = addon:GetBankItems() or {}
    end
    local bankStats = addon:GetBankStatistics()
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
        local bagsData = addon.db.char.bags or { usedSlots = 0, totalSlots = 0, lastScan = 0 }
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(format("|cff88ccff" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(bagsData.usedSlots or 0), FormatNumber(bagsData.totalSlots or 0),
            (bagsData.lastScan or 0) > 0 and date("%H:%M", bagsData.lastScan) or neverText))
    elseif currentItemsSubTab == "personal" then
        local pb = bankStats.personal or {}
        local itemsLabel = (ns.L and ns.L["ITEMS_STATS_ITEMS"]) or "%s items"
        local slotsLabel = (ns.L and ns.L["ITEMS_STATS_SLOTS"]) or "%s / %s slots"
        local lastLabel = (ns.L and ns.L["ITEMS_STATS_LAST"]) or "Last: %s"
        local neverText = (ns.L and ns.L["NEVER"]) or "Never"
        statsText:SetText(format("|cff88ff88" .. itemsLabel .. "|r  •  " .. slotsLabel .. "  •  " .. lastLabel,
            FormatNumber(#items), FormatNumber(pb.usedSlots or 0), FormatNumber(pb.totalSlots or 0),
            (pb.lastScan or 0) > 0 and date("%H:%M", pb.lastScan) or neverText))
    end
    statsText:SetTextColor(1, 1, 1)
end

function WarbandNexus:RefreshItemsSubTabBodyOnly()
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "items" then return false end
    if not ns.Utilities:IsModuleEnabled("items") then return false end
    local sc = mf.scrollChild
    if not sc or not sc._itemsSubTabBar or not sc._itemsStatsText then return false end
    local sub = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "inventory"
    sc._itemsSubTabBar:SetActiveTab(sub)
    if sc._itemsSubTabBar.RefreshGuildLock then
        sc._itemsSubTabBar:RefreshGuildLock()
    end
    ApplyItemsSubTabGoldDisplay(sc._itemsGoldDisplay, sub)
    ApplyItemsSubTabStatsText(self, sc._itemsStatsText, sub)
    self:RedrawItemsResultsOnly()
    return true
end

--============================================================================
-- DRAW ITEM LIST (Main Items Tab)
--============================================================================

function WarbandNexus:DrawItemList(parent)
    -- Register event listeners (only once)
    RegisterItemsEvents(parent)
    RegisterStorageEvents(parent)
    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local yOffset = 8
    local width = ResolveItemsTabScrollContentWidth(parent)
    
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
    local headerBtnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local HeaderFact = ns.UI and ns.UI.Factory
    local itemsEcReserve = headerBtnH + ((GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8)
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "items",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["ITEMS_HEADER"]) or "Bank Items") .. "|r",
        subtitleText = (ns.L and ns.L["ITEMS_SUBTITLE"]) or "Browse your Warband Bank and Personal Items (Bank + Inventory)",
        textRightInset = 230 + itemsEcReserve,
    }))
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- ===== GOLD MANAGER BUTTON (Header - ALWAYS visible) =====
    local titleCardRightInset = GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20
    local goldMgrBtn = HeaderFact and HeaderFact.CreateButton and HeaderFact:CreateButton(titleCard, 100, headerBtnH)
    if not goldMgrBtn then
        goldMgrBtn = CreateFrame("Button", nil, titleCard, "BackdropTemplate")
        goldMgrBtn:SetSize(100, headerBtnH)
    end
    goldMgrBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleCardRightInset, 0)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(goldMgrBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end
    
    -- Apply highlight effect
    if HeaderFact and HeaderFact.ApplyHighlight then
        HeaderFact:ApplyHighlight(goldMgrBtn)
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
    local moneyLogsBtn = HeaderFact and HeaderFact.CreateButton and HeaderFact:CreateButton(titleCard, 100, headerBtnH)
    if not moneyLogsBtn then
        moneyLogsBtn = CreateFrame("Button", nil, titleCard, "BackdropTemplate")
        moneyLogsBtn:SetSize(100, headerBtnH)
    end
    local hdrGap = GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8
    moneyLogsBtn:SetPoint("RIGHT", goldMgrBtn, "LEFT", -hdrGap, 0)

    if ApplyVisuals then
        ApplyVisuals(moneyLogsBtn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end

    if HeaderFact and HeaderFact.ApplyHighlight then
        HeaderFact:ApplyHighlight(moneyLogsBtn)
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

    local hdrGapEc = GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8
    --- Items > Warband uses DrawStorageResults + session `_wnStorageTreeExpanded`; other sub-tabs use `expandedGroups` + virtual list.
    local function StorageTreeAnyExpandedForToolbar()
        if not WarbandNexus.GetStorageTreeExpandState then return false end
        local st = WarbandNexus:GetStorageTreeExpandState()
        if not st then return false end
        if st.personal == true or st.warband == true then return true end
        local cats = st.categories
        if not cats then return false end
        for _, v in pairs(cats) do
            if v == true then return true end
        end
        return false
    end
    if ns.UI_EnsureTitleCardExpandCollapseButtons then
        ns.UI_EnsureTitleCardExpandCollapseButtons(parent, titleCard, moneyLogsBtn, "LEFT", -hdrGapEc, 0, {
            getIsCollapseMode = function()
                local sub = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"
                if sub == "warband" then
                    if WarbandNexus.storageExpandAllActive == true then return true end
                    return StorageTreeAnyExpandedForToolbar()
                end
                if WarbandNexus.itemsExpandAllActive then return true end
                local eg = ns.UI_GetExpandedGroups and ns.UI_GetExpandedGroups() or {}
                local prefix = sub .. "_"
                for k, v in pairs(eg) do
                    if type(k) == "string" and k:sub(1, #prefix) == prefix and v ~= false then
                        return true
                    end
                end
                return false
            end,
            expandTooltip = (ns.L and ns.L["ITEMS_EXPAND_ALL_TOOLTIP"]) or "Expand all item type groups for this bank view.",
            collapseTooltip = (ns.L and ns.L["ITEMS_COLLAPSE_ALL_TOOLTIP"]) or "Collapse all item type groups for this bank view.",
            onExpandClick = function()
                local sub = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"
                if sub == "warband" then
                    WarbandNexus.storageExpandAllActive = true
                    WarbandNexus:RedrawItemsResultsOnly()
                    return
                end
                local eg = ns.UI_GetExpandedGroups and ns.UI_GetExpandedGroups() or {}
                local prefix = sub .. "_"
                local rm = {}
                for k in pairs(eg) do
                    if type(k) == "string" and k:sub(1, #prefix) == prefix then
                        rm[#rm + 1] = k
                    end
                end
                for i = 1, #rm do
                    eg[rm[i]] = nil
                end
                WarbandNexus:ApplyItemsVirtualFlatListOnly()
            end,
            onCollapseClick = function()
                local sub = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"
                if sub == "warband" then
                    WarbandNexus.storageExpandAllActive = false
                    if WarbandNexus.ResetStorageTreeExpandState then
                        WarbandNexus:ResetStorageTreeExpandState()
                    end
                    WarbandNexus:RedrawItemsResultsOnly()
                    return
                end
                local eg = ns.UI_GetExpandedGroups and ns.UI_GetExpandedGroups() or {}
                local prefix = sub .. "_"
                for k in pairs(eg) do
                    if type(k) == "string" and k:sub(1, #prefix) == prefix then
                        eg[k] = false
                    end
                end
                WarbandNexus:ApplyItemsVirtualFlatListOnly()
            end,
        })
    end
    
    titleCard:Show()
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after title card
    
    -- Check if module is disabled - show beautiful disabled state card
    if not ns.Utilities:IsModuleEnabled("items") then
        if parent._wnExpandCollapseToggleBtn then parent._wnExpandCollapseToggleBtn:Hide() end
        if parent._wnExpandCollapseCollapseBtn then parent._wnExpandCollapseCollapseBtn:Hide() end
        if parent._wnExpandCollapseExpandBtn then parent._wnExpandCollapseExpandBtn:Hide() end
        if parent._wnResultsAnnexSheet then parent._wnResultsAnnexSheet:Hide() end
        if fixedHeader then fixedHeader:SetHeight(yOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["ITEMS_DISABLED_TITLE"]) or "Warband Bank Items")
        return 8 + cardHeight
    end
    
    -- ===== LOADING STATE (INITIAL SCAN) =====
    if ns.ItemsLoadingState and ns.ItemsLoadingState.isLoading then
        if parent._wnResultsAnnexSheet then parent._wnResultsAnnexSheet:Hide() end
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
            local sub = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "personal"
            local contentHeight
            if sub == "warband" and ns.Utilities:IsModuleEnabled("items") then
                local rw = ResolveItemsTabScrollContentWidth(parent)
                contentHeight = WarbandNexus:DrawStorageResults(resultsContainer, 0, rw, text)
            else
                contentHeight = WarbandNexus:DrawItemsResults(resultsContainer, 0, width, sub, text)
            end
            resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
            if ns.UI_AnnexResultsToScrollBottom and parent then
                ns.UI_AnnexResultsToScrollBottom(resultsContainer, parent, SIDE_MARGIN, 8)
            end
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

    parent._itemsSubTabBar = itemsBankSubTabBar
    parent._itemsGoldDisplay = goldDisplay
    parent._itemsStatsText = statsText
    
    yOffset = yOffset + 24 + GetLayout().afterElement

    -- Set fixedHeader height so scroll area starts below all header elements
    if fixedHeader then fixedHeader:SetHeight(yOffset) end
    
    -- ===== RESULTS CONTAINER (in scroll area) =====
    local resultsContainer = CreateResultsContainer(parent, 8, SIDE_MARGIN)
    parent.resultsContainer = resultsContainer

    local contentHeight
    if currentItemsSubTab == "warband" and ns.Utilities:IsModuleEnabled("items") then
        if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
        end
        contentHeight = self:DrawStorageResults(resultsContainer, 0, width, itemsSearchText)
    else
        contentHeight = self:DrawItemsResults(resultsContainer, 0, width, currentItemsSubTab, itemsSearchText)
    end
    resultsContainer:SetHeight(math.max(contentHeight or 1, 1))
    if ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(resultsContainer, parent, SIDE_MARGIN, 8)
    end

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
    local width = ResolveItemsTabScrollContentWidth(scrollChild)
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery then
        q = SearchStateManager:GetQuery("items") or ""
    end
    local subTab = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"

    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(rc)
    end

    local contentHeight
    if subTab == "warband" and ns.Utilities:IsModuleEnabled("items") then
        contentHeight = self:DrawStorageResults(rc, 0, width, q)
    else
        contentHeight = self:DrawItemsResults(rc, 0, width, subTab, q)
    end
    rc:SetHeight(math.max(contentHeight or 1, 1))
    if ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(rc, scrollChild, SIDE_MARGIN, 8)
    end

    SyncItemsTabScrollChrome(mf, scrollChild, contentHeight)
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
            local linkStr = item.itemLink or item.link
            local itemLink = SafeLower(linkStr)
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
                local it = items[i]
                local nm = it.name
                if not nm and it.link and type(it.link) == "string" and not (issecretvalue and issecretvalue(it.link)) then
                    nm = it.link:match("%[(.-)%]")
                end
                keys[i] = SafeLower(nm)
                if keys[i] == "" and it.itemID then
                    keys[i] = "id:" .. tostring(it.itemID)
                end
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
                -- Stable identity for virtual row reuse (collapsible sections / Refresh without repopulating textures & text).
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
                    height = ITEMS_VIRTUAL_ROW_HEIGHT,
                    data = item,
                    rowIdx = rowIdx,
                    groupKey = group.groupKey,
                    localY = localY,
                    rowReuseSig = rowReuseSig,
                }
                localY = localY + ITEMS_VIRTUAL_ROW_HEIGHT
                yOffset = yOffset + ITEMS_VIRTUAL_ROW_HEIGHT
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
    local width = ResolveItemsTabScrollContentWidth(scrollChild)
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery then
        q = SearchStateManager:GetQuery("items") or ""
    end
    local subTab = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "personal"

    if subTab == "warband" and ns.Utilities:IsModuleEnabled("items") then
        self:RedrawItemsResultsOnly()
        return
    end

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
    if currentItemsSubTab == "warband" and ns.Utilities:IsModuleEnabled("items") then
        if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
            SearchResultsRenderer:PrepareContainer(parent)
        end
        return self:DrawStorageResults(parent, yOffset, width, itemsSearchText)
    end

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
                if button == "LeftButton" and IsShiftKeyDown() then
                    local lk = item.itemLink or item.link
                    if lk and not (issecretvalue and issecretvalue(lk)) then
                        ChatEdit_InsertLink(lk)
                    end
                end
            end)
        end

        local HEADER_STRIP_H = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
        local Factory = ns.UI.Factory

        local totalHeight = VLM.SetupVirtualList(mainFrame, parent, nil, flatList, {
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
                local rowsBodyH = math.max(0.1, nItems * ITEMS_VIRTUAL_ROW_HEIGHT)

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
                    BuildCollapsibleSectionOpts({
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
                groupShell._wnSectionFullH = rowsBodyH
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
                return AcquireItemRow(container, width, ITEMS_VIRTUAL_ROW_HEIGHT)
            end,
            releaseRowFn = function(frame)
                ReleaseItemRow(frame)
            end,
        })

        return math.max(totalHeight, yOffset) + GetLayout().minBottomSpacing
    end

    return yOffset + GetLayout().minBottomSpacing
end -- DrawItemsResults

