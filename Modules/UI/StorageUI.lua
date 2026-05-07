--[[
    Warband Nexus - Storage Tab
    Hierarchical storage browser with search and category organization
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

local function CompareCharNameLower(a, b)
    return SafeLower(a.name) < SafeLower(b.name)
end

-- Unique AceEvent handler identity for StorageUI
local StorageUIEvents = {}

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip
local DebugPrint = ns.DebugPrint

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
local FormatNumber = ns.UI_FormatNumber
local COLORS = ns.UI_COLORS

-- Type accordion contract (Characters-parity tween + post-tween scroll sync). Loads before StorageUI (see .toc).
local StorageSectionLayout = ns.StorageSectionLayout
if not StorageSectionLayout then
    error("StorageSectionLayout missing — ensure Modules/UI/StorageSectionLayout.lua loads before StorageUI.lua")
end

-- Import pooling functions
local AcquireStorageRow = ns.UI_AcquireStorageRow
local ReleaseStorageRow = ns.UI_ReleaseStorageRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateResultsContainer = ns.UI_CreateResultsContainer
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
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
        pendingDrawTimer = C_Timer.NewTimer(DRAW_DEBOUNCE, function()
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

    WarbandNexus.RegisterMessage(StorageUIEvents, E.ITEM_METADATA_READY, function()
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
    -- Release pooled rows for partial redraw calls.
    -- PopulateContent already does this for full-tab renders.
    if not parent._preparedByPopulate then
        ReleaseAllPooledChildren(parent)
    end
    
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
    
    -- ===== HEADER CARD (in fixedHeader - non-scrolling) — Characters-tab layout =====
    if not parent._storageTitleCard then
        local r0, g0, b0 = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        local hex0 = string.format("%02x%02x%02x", r0 * 255, g0 * 255, b0 * 255)
        local titleCard, headerIcon, textContainer, titleText, subtitleText = ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "storage",
            titleText = "|cff" .. hex0 .. ((ns.L and ns.L["STORAGE_HEADER"]) or "Storage Browser") .. "|r",
            subtitleText = (ns.L and ns.L["STORAGE_HEADER_DESC"]) or "Browse all items organized by type",
        })

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
            local sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.storageSort, function()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "storage", skipCooldown = true, instantPopulate = true })
        end)
            sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -20, 0)
            sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
        end

        -- Store references for reuse
        parent._storageTitleCard = titleCard
        parent._storageHeaderIcon = headerIcon
        parent._storageTextContainer = textContainer
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
    if ns.UI_ReanchorStandardTabTitleLayout and parent._storageHeaderIcon and parent._storageTextContainer then
        ns.UI_ReanchorStandardTabTitleLayout(parent._storageHeaderIcon, titleCard, parent._storageTextContainer, 70)
    end
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

--- Redraw Storage scroll content only (results container). Skips PopulateContent, scrollChild purge,
--- and UI_MAIN_REFRESH_REQUESTED debounce — use after accordion toggles for perf.
function WarbandNexus:RedrawStorageResultsOnly()
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "storage" then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.storageResultsContainer or scrollChild._storageResultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = scrollChild:GetWidth() - 20
    if width < 1 then return end
    local q = ""
    if SearchStateManager and SearchStateManager.GetQuery then
        q = SearchStateManager:GetQuery("storage") or ""
    end
    local contentHeight = self:DrawStorageResults(rc, 0, width, q)
    rc:SetHeight(math.max(contentHeight or 1, 1))
end

--- After leaf type accordion tweens (no full DrawStorageResults), resize results container from layout tail.
function WarbandNexus:SyncStorageResultsLayoutFromTail(resultsContainer)
    if not resultsContainer then return end
    local tail = resultsContainer._wnStorageLayoutTail
    local pad = GetLayout().minBottomSpacing or 0
    if tail and resultsContainer.GetTop and tail.GetBottom then
        local pTop = resultsContainer:GetTop()
        local bot = tail:GetBottom()
        if pTop and bot then
            local measured = pTop - bot + pad
            resultsContainer:SetHeight(math.max(1, measured))
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
end

--============================================================================
-- STORAGE RESULTS RENDERING (Separated for search refresh)
--============================================================================

function WarbandNexus:DrawStorageResults(parent, yOffset, width, storageSearchText)
    local storageSearchActive = storageSearchText
        and not (issecretvalue and issecretvalue(storageSearchText))
        and storageSearchText ~= ""

    -- Clean up rows created for subheader accordion containers in previous render.
    if parent._wnStorageAnimatedRows and ReleaseStorageRow then
        for i = 1, #parent._wnStorageAnimatedRows do
            local row = parent._wnStorageAnimatedRows[i]
            if row and row.rowType == "storage" then
                ReleaseStorageRow(row)
            end
        end
    end
    parent._wnStorageAnimatedRows = {}

    -- Clean up old children (headers, accordion containers, rows) from previous render.
    local recycleBin = ns.UI_RecycleBin
    local function CancelSubtreeAccordion(f)
        if not f then return end
        if ns.UI.Factory and ns.UI.Factory.CancelAccordion then
            ns.UI.Factory:CancelAccordion(f)
        end
        local ch = { f:GetChildren() }
        for j = 1, #ch do
            CancelSubtreeAccordion(ch[j])
        end
    end
    local oldChildren = {parent:GetChildren()}
    for i = 1, #oldChildren do
        local child = oldChildren[i]
        if not child._isVirtualRow then
            CancelSubtreeAccordion(child)
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end

    local globalRowIdxAll = 0
    local animatedRows = parent._wnStorageAnimatedRows
    --- Vertical chain tail: major headers + type wraps share one anchor stack so accordion tweens
    --- reposition following siblings immediately (no deferred yOffset drift).
    local storageStackAnchor = nil

    -- Get expanded state
    local expanded = self.db.profile.storageExpanded or {}
    if not expanded.categories then expanded.categories = {} end
    
    local function CreateStorageRowsContainer(contentParent, anchorFrame, leftOffset, rightOffset)
        contentParent = contentParent or parent
        local frame = ns.UI.Factory:CreateContainer(contentParent, math.max(1, contentParent:GetWidth()), 1, false)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", leftOffset or 0, 0)
        frame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", rightOffset or 0, 0)
        frame:SetHeight(0.1)
        frame._wnAccordionFullH = 0
        return frame
    end

    local TYPE_SECTION_HEADER_H = StorageSectionLayout.GetTypeSectionHeaderHeight()
    local MAIN_SECTION_HEADER_H = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36

    --- Nested Major accordion (e.g. character wraps under Personal): tween updates inner wrap height but
    --- the stack parent (`personalBody`) keeps its initial height — siblings stay visually stuck. Resize
    --- stack parent + outer section wrap from live child bottoms each tick (WoW Y grows upward).
    local function ReflowStorageStackParentBody(stackParent, outerWrap, outerHeaderH)
        if not stackParent then return end
        local pTop = stackParent:GetTop()
        if not pTop then return end
        local lowest = pTop
        local children = { stackParent:GetChildren() }
        for i = 1, #children do
            local c = children[i]
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

    --- After a type (leaf) accordion tweens, section bodies/wraps above the type row stay at initial heights.
    --- Reflow measured stacks so character rows and items below sit below expanded content (not drawn on top).
    --- ctx: { contentBody, sectionWrap, sectionHeaderH, stackParent?, outerSectionWrap?, outerSectionHeaderH? }
    local function ApplyStorageLeafAncestorReflow(ctx)
        if not ctx or not ctx.contentBody or not ctx.sectionWrap or not ctx.sectionHeaderH then return end
        ReflowStorageStackParentBody(ctx.contentBody, ctx.sectionWrap, ctx.sectionHeaderH)
        ctx.contentBody._wnAccordionFullH = math.max(0.1, ctx.contentBody:GetHeight() or 0.1)
        if ctx.stackParent and ctx.outerSectionWrap and ctx.outerSectionHeaderH then
            ReflowStorageStackParentBody(ctx.stackParent, ctx.outerSectionWrap, ctx.outerSectionHeaderH)
            ctx.stackParent._wnAccordionFullH = math.max(0.1, ctx.stackParent:GetHeight() or 0.1)
        end
        WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
    end

    --- Major section (Personal / Warband / Guild / character): wrapped header + body height tween.
    --- Optional `stackReflowCtx`: { stackParent, outerWrap, outerHeaderH } for nested stacks (Personal → characters).
    local function MajorStorageAccordionOpts(wrapFrame, bodyGetter, headerH, persistFn, stackReflowCtx)
        return {
            animatedContent = bodyGetter,
            persistToggle = function(exp)
                if type(exp) == "boolean" and persistFn then
                    persistFn(exp)
                end
            end,
            accordionOnUpdate = function(drawH)
                wrapFrame:SetHeight(headerH + math.max(0.1, drawH or 0))
                if stackReflowCtx and stackReflowCtx.stackParent then
                    ReflowStorageStackParentBody(
                        stackReflowCtx.stackParent,
                        stackReflowCtx.outerWrap,
                        stackReflowCtx.outerHeaderH
                    )
                end
                WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            end,
            accordionComplete = function(exp)
                if not exp then
                    local b = bodyGetter()
                    if b then
                        b:Hide()
                        b:SetHeight(0.1)
                    end
                end
                WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            end,
        }
    end

    --- Leaf type rows live under `rowsContainer`; tween that frame (Characters-parity) without full tab redraw.
    --- Optional `ancestorReflowCtx`: reflow char/warband/guild section + Personal outer after height changes.
    local function LeafTypeAccordionVisualOpts(wrapFrame, rowsGetter, leafKey, ancestorReflowCtx)
        return {
            animatedContent = rowsGetter,
            persistToggle = function(exp)
                if type(exp) == "boolean" then
                    expanded.categories[leafKey] = exp
                end
            end,
            accordionOnUpdate = function(drawH)
                wrapFrame:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, drawH or 0))
                if ancestorReflowCtx then
                    ApplyStorageLeafAncestorReflow(ancestorReflowCtx)
                end
            end,
            accordionComplete = function(exp)
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
        }
    end

    local function PopulateStorageRowDirect(row, item, rowIdx, rowWidth, locText)
        row:SetAlpha(1)
        if row.anim then row.anim:Stop() end
        ns.UI.Factory:ApplyRowBackground(row, rowIdx)

        row.qtyText:SetText(format("|cffffff00%s|r", FormatNumber(item.stackCount or 1)))
        row.icon:SetTexture(item.iconFileID or 134400)

        local nameWidth = rowWidth - 350
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

        row.locationText:SetWidth(0)
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
        local itemLink = SafeLower(item.itemLink)
        return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
    end
    
    -- PRE-SCAN: If search is active, find which categories have matches
    local categoriesWithMatches = {}
    local hasAnyMatches = false
    
    if storageSearchActive then
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
    if storageSearchActive and not hasAnyMatches then
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, storageSearchText, "storage")
        -- Update SearchStateManager with result count
        SearchStateManager:UpdateResults("storage", 0)
        return height
    end
    
    -- Quick check for general "no data" empty state (when no search is active)
    if not storageSearchActive then
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
    
    if storageSearchActive then
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
        if personalExpanded == nil then
            personalExpanded = true
            expanded.personal = true
        end
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
            MajorStorageAccordionOpts(personalWrap, function() return personalBody end, MAIN_SECTION_HEADER_H, function(exp)
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

        yOffset = yOffset + HEADER_SPACING
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
                    return CompareCharNameLower(a, b)
                end)
                for _, c in ipairs(remaining) do table.insert(ordered, c) end
                characters = ordered
            else
                table.sort(characters, function(a, b)
                    if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                    return CompareCharNameLower(a, b)
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
                if storageSearchActive and not categoriesWithMatches[charCategoryKey] then
                    -- Skip this character
                else
                    -- Auto-expand if search has matches for this character
                    local isCharExpanded = self.storageExpandAllActive or expanded.categories[charCategoryKey]
                    -- Default to true if never set (first time)
                    if isCharExpanded == nil then
                        isCharExpanded = true
                        expanded.categories[charCategoryKey] = true
                    end
                    if storageSearchActive and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if char.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. char.classFile
                    end
                    
                    -- Character block: wrapped header + body (major accordion); types always built inside body.
                    local charIndent = BASE_INDENT * 1  -- 15px
                    local charWrap = ns.UI.Factory:CreateContainer(personalBody, math.max(1, width - charIndent), MAIN_SECTION_HEADER_H + 0.1, false)
                    charWrap:ClearAllPoints()
                    if charWrap.SetClipsChildren then
                        charWrap:SetClipsChildren(true)
                    end
                    if personalInnerTail then
                        ChainSectionFrameBelow(personalBody, charWrap, personalInnerTail, charIndent, SECTION_SPACING, nil)
                    else
                        ChainSectionFrameBelow(personalBody, charWrap, nil, charIndent, nil, 0)
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
                        MajorStorageAccordionOpts(charWrap, function() return charBody end, MAIN_SECTION_HEADER_H, function(exp)
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

                    local stackAnchor = nil
                    local gapBelowStack = SECTION_SPACING
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
                        if storageSearchActive then
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
                    local charBodyAdvance = SECTION_SPACING
-- Draw each type category for this character
                    for _, typeName in ipairs(charSortedTypes) do
                        local typeKey = "personal_" .. charKey .. "_" .. typeName
                        
                        -- Skip category if search active and no matches
                        if storageSearchActive and not categoriesWithMatches[typeKey] then
                            -- Skip this category
                        else
                            -- Auto-expand if search has matches in this category
                            local isTypeExpanded = self.storageExpandAllActive or expanded.categories[typeKey]
                            -- Default to true if never set (first time)
                            if isTypeExpanded == nil then
                                isTypeExpanded = true
                                expanded.categories[typeKey] = true
                            end
                            if storageSearchActive and categoriesWithMatches[typeKey] then
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
                                
                                -- Type header + rows: accordion tween on rowsContainer; stagger on rows (SharedWidgets).
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

                                local rowsContainer
                                local typeHeader2, typeBtn2 = CreateCollapsibleHeader(
                                typeSectionWrap,
                                typeName .. " (" .. FormatNumber(displayCount) .. ")",
                                typeKey,
                                isTypeExpanded,
                                function() end,
                                typeIcon2,
                                false,  -- isAtlas = false (item icons are texture paths)
                                0,      -- indent in wrap only; typeSectionWrap already offset under character header
                                nil,
                                LeafTypeAccordionVisualOpts(typeSectionWrap, function() return rowsContainer end, typeKey, {
                                    contentBody = charBody,
                                    sectionWrap = charWrap,
                                    sectionHeaderH = MAIN_SECTION_HEADER_H,
                                    stackParent = personalBody,
                                    outerSectionWrap = personalWrap,
                                    outerSectionHeaderH = MAIN_SECTION_HEADER_H,
                                })
                            )
                            typeHeader2:SetPoint("TOPLEFT", typeSectionWrap, "TOPLEFT", 0, 0)
                            typeHeader2:SetWidth(typeSectionWrap:GetWidth())
                            rowsContainer = CreateStorageRowsContainer(typeSectionWrap, typeHeader2, 0, 0)
                            local rowsYOffset = 0
                            local rowStaggerIdx = 0
                            for _, item in ipairs(charItems[typeName]) do
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
                                    local row = AcquireStorageRow(rowsContainer, width - BASE_INDENT * 2, ROW_HEIGHT)
                                    row:ClearAllPoints()
                                    row:SetPoint("TOPLEFT", 0, -rowsYOffset)
                                    PopulateStorageRowDirect(row, item, globalRowIdxAll, width - BASE_INDENT * 2, locText)
                                    animatedRows[#animatedRows + 1] = row
                                    rowStaggerIdx = rowStaggerIdx + 1
                                    rowsYOffset = rowsYOffset + ROW_HEIGHT + GetLayout().betweenRows
                                end
                            end
                            rowsContainer._wnAccordionFullH = rowsYOffset
                            if isTypeExpanded then
                                rowsContainer:Show()
                                rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                            else
                                rowsContainer:Hide()
                                rowsContainer:SetHeight(0.1)
                            end
                            typeSectionWrap:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                            charBodyAdvance = charBodyAdvance + typeSectionWrap:GetHeight() + SECTION_SPACING
                            end  -- if displayCount > 0
                        end  -- if not skipped by search
                    end
                    
                    local charInnerH = math.max(0.1, charBodyAdvance - SECTION_SPACING)
                    charBody._wnAccordionFullH = charInnerH
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
            
        personalBody._wnAccordionFullH = math.max(0.1, personalInnerAccum - SECTION_SPACING)
        if personalExpanded then
            personalBody:Show()
            personalBody:SetHeight(personalBody._wnAccordionFullH)
        else
            personalBody:Hide()
            personalBody:SetHeight(0.1)
        end
        personalWrap:SetHeight(MAIN_SECTION_HEADER_H + personalBody:GetHeight())
        storageStackAnchor = personalWrap
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
    if storageSearchActive then
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
        if warbandExpanded == nil then
            warbandExpanded = true
            expanded.warband = true
        end
        if storageSearchActive and categoriesWithMatches["warband"] then
            warbandExpanded = true
        end
        
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
            MajorStorageAccordionOpts(warbandWrap, function() return warbandBody end, MAIN_SECTION_HEADER_H, function(exp)
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

        local stackAnchor = nil
        local gapBelowStack = SECTION_SPACING
        local warbandBodyAdvance = SECTION_SPACING
        -- Sort types alphabetically
            local sortedTypes = {}
            for typeName in pairs(warbandItems) do
                -- Only include types that have matching items
                local hasMatchingItems = false
                if storageSearchActive then
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
            if storageSearchActive and not categoriesWithMatches[categoryKey] then
                -- Skip this category
            else
                -- Auto-expand if search has matches in this category
                local isTypeExpanded = self.storageExpandAllActive or expanded.categories[categoryKey]
                -- Default to true if never set (first time)
                if isTypeExpanded == nil then
                    isTypeExpanded = true
                    expanded.categories[categoryKey] = true
                end
                if storageSearchActive and categoriesWithMatches[categoryKey] then
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

                    local rowsContainer
                    local typeHeader, typeBtn = CreateCollapsibleHeader(
                    typeSectionWrapWB,
                    typeName .. " (" .. FormatNumber(displayCount) .. ")",
                    categoryKey,
                    isTypeExpanded,
                    function() end,
                    typeIcon,
                    false,
                    nil,
                    nil,
                    LeafTypeAccordionVisualOpts(typeSectionWrapWB, function() return rowsContainer end, categoryKey, {
                        contentBody = warbandBody,
                        sectionWrap = warbandWrap,
                        sectionHeaderH = MAIN_SECTION_HEADER_H,
                    })
                )
                typeHeader:SetPoint("TOPLEFT", typeSectionWrapWB, "TOPLEFT", 0, 0)
                typeHeader:SetWidth(typeSectionWrapWB:GetWidth())
                    rowsContainer = CreateStorageRowsContainer(typeSectionWrapWB, typeHeader, 0, 0)
                    local rowsYOffset = 0
                    local rowStaggerIdxWB = 0
                    for _, item in ipairs(warbandItems[typeName]) do
                        local shouldShow = ItemMatchesSearch(item)
                        if shouldShow then
                            globalRowIdxAll = globalRowIdxAll + 1
                            local locText = item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex) or ""
                            local row = AcquireStorageRow(rowsContainer, width - BASE_INDENT, ROW_HEIGHT)
                            row:ClearAllPoints()
                            row:SetPoint("TOPLEFT", 0, -rowsYOffset)
                            PopulateStorageRowDirect(row, item, globalRowIdxAll, width - BASE_INDENT, locText)
                            animatedRows[#animatedRows + 1] = row
                            rowStaggerIdxWB = rowStaggerIdxWB + 1
                            rowsYOffset = rowsYOffset + ROW_HEIGHT + GetLayout().betweenRows
                        end
                    end
                    rowsContainer._wnAccordionFullH = rowsYOffset
                    if isTypeExpanded then
                        rowsContainer:Show()
                        rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                    else
                        rowsContainer:Hide()
                        rowsContainer:SetHeight(0.1)
                    end
                    typeSectionWrapWB:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                    warbandBodyAdvance = warbandBodyAdvance + typeSectionWrapWB:GetHeight() + SECTION_SPACING
                end  -- if displayCount > 0
            end  -- if not skipped by search
        end

        warbandBody._wnAccordionFullH = math.max(0.1, warbandBodyAdvance - SECTION_SPACING)
        if warbandExpanded then
            warbandBody:Show()
            warbandBody:SetHeight(warbandBody._wnAccordionFullH)
        else
            warbandBody:Hide()
            warbandBody:SetHeight(0.1)
        end
        warbandWrap:SetHeight(MAIN_SECTION_HEADER_H + warbandBody:GetHeight())
        storageStackAnchor = warbandWrap
    end  -- if warbandTotalMatches > 0
    
    -- ===== GUILD BANK SECTION =====
    -- Show ALL cached guild banks (not just current character's guild)
    -- This allows viewing guild bank data from other characters
    
    -- Collect all guild bank items from all cached guilds
    local allGuildItems = {}  -- Format: { [guildName] = { [typeName] = {items} } }
    
    if self.db and self.db.global and self.db.global.guildBank then
        for guildName, guildData in pairs(self.db.global.guildBank) do
            if guildData and guildData.tabs then
                if DebugPrint then DebugPrint("[StorageUI] Found cached guild bank:", guildName) end
                
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
                                
                                if DebugPrint then DebugPrint("[StorageUI] Item", item.itemID, "from", guildName, "-> typeName:", typeName) end
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
    if storageSearchActive then
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
    
    if DebugPrint then
        DebugPrint("[StorageUI] Total guild bank items:", guildTotalMatches, "from", (function()
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
        if storageSearchActive then
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
            if storageSearchActive and categoriesWithMatches[guildKey] then
                guildExpanded = true
            end
            
            -- Create header with guild name
            local guildHeaderText = string.format("%s (%s)", 
                (ns.L and ns.L["ITEMS_GUILD_BANK"]) or "Guild Bank",
                guildName)
            
            local guildWrap = ns.UI.Factory:CreateContainer(parent, math.max(1, width), MAIN_SECTION_HEADER_H + 0.1, false)
            guildWrap:ClearAllPoints()
            if guildWrap.SetClipsChildren then
                guildWrap:SetClipsChildren(true)
            end
            ChainSectionFrameBelow(parent, guildWrap, storageStackAnchor, 0, storageStackAnchor and SECTION_SPACING or 0, yOffset)

            local guildBody
            local guildHeader, expandBtn, guildIcon = CreateCollapsibleHeader(
                guildWrap,
                guildHeaderText,
                guildKey,
                guildExpanded,
                function() end,
                "dummy",
                false,
                nil,
                nil,
                MajorStorageAccordionOpts(guildWrap, function() return guildBody end, MAIN_SECTION_HEADER_H, function(exp)
                    expanded.categories[guildKey] = exp
                end)
            )
            guildHeader:SetPoint("TOPLEFT", guildWrap, "TOPLEFT", 0, 0)
            guildHeader:SetWidth(width)

            guildBody = ns.UI.Factory:CreateContainer(guildWrap, math.max(1, width), 0.1, false)
            guildBody:ClearAllPoints()
            guildBody:SetPoint("TOPLEFT", guildHeader, "BOTTOMLEFT", 0, 0)
            guildBody:SetPoint("TOPRIGHT", guildHeader, "BOTTOMRIGHT", 0, 0)

            -- Replace with Guild Bank icon (using Atlas)
            if guildIcon then
                guildIcon:SetTexture(nil)  -- Clear dummy texture
                guildIcon:SetAtlas("poi-workorders")  -- Guild bank-style icon
                guildIcon:SetSize(24, 24)
            end

            local stackAnchor = nil
            local gapBelowStack = SECTION_SPACING
            local guildBodyAdvance = SECTION_SPACING
            -- Sort types alphabetically
            local sortedTypes = {}
            for typeName in pairs(guildItems) do
                -- Only include types that have matching items
                local hasMatchingItems = false
                if storageSearchActive then
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
                if storageSearchActive and not categoriesWithMatches[categoryKey] then
                    -- Skip this category
                else
                    -- Auto-expand if search has matches in this category
                    local isTypeExpanded = self.storageExpandAllActive or expanded.categories[categoryKey]
                    -- Default to true if never set (first time)
                    if isTypeExpanded == nil then
                        isTypeExpanded = true
                        expanded.categories[categoryKey] = true
                    end
                    if storageSearchActive and categoriesWithMatches[categoryKey] then
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
                    local displayCount = (storageSearchActive) and matchCount or #guildItems[typeName]
                    
                    -- Skip header if it has no items to show
                    if displayCount == 0 then
                        -- Skip this empty header
                    else
                        -- Get icon from first item in category
                        local typeIcon = nil
                        if guildItems[typeName][1] and guildItems[typeName][1].classID then
                            typeIcon = GetTypeIcon(guildItems[typeName][1].classID)
                        end
                        
                        local typeIndentG = BASE_INDENT
                        local typeSectionWrapG = ns.UI.Factory:CreateContainer(guildBody, math.max(1, guildBody:GetWidth() - typeIndentG), TYPE_SECTION_HEADER_H + 0.1, false)
                        typeSectionWrapG:ClearAllPoints()
                        if typeSectionWrapG.SetClipsChildren then
                            typeSectionWrapG:SetClipsChildren(true)
                        end
                        if stackAnchor then
                            ChainSectionFrameBelow(guildBody, typeSectionWrapG, stackAnchor, typeIndentG, gapBelowStack, nil)
                        else
                            ChainSectionFrameBelow(guildBody, typeSectionWrapG, nil, typeIndentG, nil, SECTION_SPACING)
                        end
                        gapBelowStack = SECTION_SPACING
                        stackAnchor = typeSectionWrapG

                        local rowsContainer
                        local typeHeader, typeBtn = CreateCollapsibleHeader(
                            typeSectionWrapG,
                            typeName .. " (" .. FormatNumber(displayCount) .. ")",
                            categoryKey,
                            isTypeExpanded,
                            function() end,
                            typeIcon,
                            false,  -- isAtlas = false (item icons are texture paths)
                            0,      -- indent via typeSectionWrapG anchor only (parity with Warband type headers)
                            nil,
                            LeafTypeAccordionVisualOpts(typeSectionWrapG, function() return rowsContainer end, categoryKey, {
                                contentBody = guildBody,
                                sectionWrap = guildWrap,
                                sectionHeaderH = MAIN_SECTION_HEADER_H,
                            })
                        )
                        typeHeader:SetPoint("TOPLEFT", typeSectionWrapG, "TOPLEFT", 0, 0)
                        typeHeader:SetWidth(typeSectionWrapG:GetWidth())
                        rowsContainer = CreateStorageRowsContainer(typeSectionWrapG, typeHeader, 0, 0)
                        local rowsYOffset = 0
                        local rowStaggerIdxG = 0
                        for _, item in ipairs(guildItems[typeName]) do
                            local shouldShow = ItemMatchesSearch(item)
                            if shouldShow then
                                globalRowIdxAll = globalRowIdxAll + 1
                                local locText = item.tabName or (item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex)) or ""
                                local row = AcquireStorageRow(rowsContainer, width - BASE_INDENT, ROW_HEIGHT)
                                row:ClearAllPoints()
                                row:SetPoint("TOPLEFT", 0, -rowsYOffset)
                                PopulateStorageRowDirect(row, item, globalRowIdxAll, width - BASE_INDENT, locText)
                                animatedRows[#animatedRows + 1] = row
                                rowStaggerIdxG = rowStaggerIdxG + 1
                                rowsYOffset = rowsYOffset + ROW_HEIGHT + GetLayout().betweenRows
                            end
                        end
                        rowsContainer._wnAccordionFullH = rowsYOffset
                        if isTypeExpanded then
                            rowsContainer:Show()
                            rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                        else
                            rowsContainer:Hide()
                            rowsContainer:SetHeight(0.1)
                        end
                        typeSectionWrapG:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                        guildBodyAdvance = guildBodyAdvance + typeSectionWrapG:GetHeight() + SECTION_SPACING
                    end  -- if displayCount > 0
                end  -- if not skipped by search
            end  -- for typeName

            guildBody._wnAccordionFullH = math.max(0.1, guildBodyAdvance - SECTION_SPACING)
            if guildExpanded then
                guildBody:Show()
                guildBody:SetHeight(guildBody._wnAccordionFullH)
            else
                guildBody:Hide()
                guildBody:SetHeight(0.1)
            end
            guildWrap:SetHeight(MAIN_SECTION_HEADER_H + guildBody:GetHeight())
            storageStackAnchor = guildWrap
        end  -- if guildMatches > 0
    end  -- for guildName (all guilds loop)
    
    -- Legacy virtual-list hook: flat list path was never wired; clear any stale VLM state from older builds.
    local mainFrame = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local VLM = ns.VirtualListModule
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

    local pad = GetLayout().minBottomSpacing or 0
    parent._wnStorageLayoutTail = storageStackAnchor
    if storageStackAnchor and parent.GetTop and storageStackAnchor.GetBottom then
        local pTop = parent:GetTop()
        local bot = storageStackAnchor:GetBottom()
        if pTop and bot then
            local measured = pTop - bot + pad
            -- Prefer numeric yOffset if layout hasn't resolved same-frame (prevents tiny scroll height).
            return math.max(1, measured, yOffset + pad)
        end
    end
    return yOffset + pad
end -- DrawStorageResults

