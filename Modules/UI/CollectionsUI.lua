--[[
    Warband Nexus - Collections Tab (entry: DrawCollectionsTab, listeners)
    Sub-modules: CollectionsUI_Shared, _Lists, _Model, _Recent, _Draw.
]]

local _, ns = ...
local M = ns.CollectionsUI
assert(M and M.state, "CollectionsUI_Shared.lua must load first")

local WarbandNexus = M.WarbandNexus
local collectionsState = M.state
local LAYOUT = M.LAYOUT
local COLORS = M.COLORS or ns.UI_COLORS
local format = string.format
local AFTER_ELEMENT = M.AFTER_ELEMENT
local SEARCH_ROW_HEIGHT = M.SEARCH_ROW_HEIGHT
local CONTENT_INSET = M.CONTENT_INSET
local SUBTAB_BTN_HEIGHT = 40
local COLLECTIONS_TITLE_CARD_HEIGHT = M.COLLECTIONS_TITLE_CARD_HEIGHT
local COLLECTION_HEAVY_DELAY = M.COLLECTION_HEAVY_DELAY
local HideEmptyStateCard = M.HideEmptyStateCard
local Factory = M.Factory
local FontManager = M.FontManager
local Constants = M.Constants
local CreateThemedCheckbox = M.CreateThemedCheckbox
local CreateSubTabBar = M.CreateSubTabBar
local ApplyCollectionsContentHeader = M.ApplyCollectionsContentHeader
local RequestCollectionFillFromUI = M.RequestCollectionFillFromUI
local RefreshCollectionsLayout = M.RefreshCollectionsLayout
local ApplySessionCollectionsSubTab = M.ApplySessionCollectionsSubTab
local LayoutCollectionsSearchBar = M.LayoutCollectionsSearchBar
local DrawRecentContent = M.DrawRecentContent
local ComputeRecentTabMinScrollWidth = M.ComputeRecentTabMinScrollWidth

if ns.UI_RegisterTabMinScrollWidth and not M.state._recentMinScrollRegistered then
    M.state._recentMinScrollRegistered = true
    ns.UI_RegisterTabMinScrollWidth("collections", function()
        if M.state.currentSubTab ~= "recent" then
            return nil
        end
        return ComputeRecentTabMinScrollWidth(M.state._recentMinScrollSideMargin)
    end)
end
local DrawMountsContent = M.DrawMountsContent
local DrawPetsContent = M.DrawPetsContent
local DrawToysContent = M.DrawToysContent
local DrawAchievementsContent = M.DrawAchievementsContent
local CreateSearchBox = ns.UI_CreateSearchBox

local function RedrawCollectionsSearchContentImmediate()
    local cf = M.state.contentFrame
    if not cf then return end
    local sub = M.state.currentSubTab
    if sub == "recent" then
        DrawRecentContent(cf)
    elseif sub == "mounts" then
        DrawMountsContent(cf)
    elseif sub == "pets" then
        DrawPetsContent(cf)
    elseif sub == "toys" then
        DrawToysContent(cf)
    elseif sub == "achievements" then
        DrawAchievementsContent(cf)
    end
end

local function ScheduleCollectionsSearchRedraw()
    local sub = M.state.currentSubTab or "collections"
    ns.UI_ScheduleSearchRefresh("collections_" .. sub, RedrawCollectionsSearchContentImmediate)
end

local function CollectionsSearchRefreshKey()
    return "collections_" .. (M.state.currentSubTab or "collections")
end

-- Fixed header: search bar uses full row width when Owned/Missing row is hidden (Recent).
function M.LayoutCollectionsSearchBar(hdrCache)
    if not hdrCache or not hdrCache.searchBar or not hdrCache.searchRow then return end
    local bar = hdrCache.searchBar
    local sr = hdrCache.searchRow
    local fr = hdrCache.filterRow
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", sr, "TOPLEFT", 0, 0)
    if fr and fr:IsShown() then
        bar:SetPoint("TOPRIGHT", fr, "TOPLEFT", -8, 0)
    else
        bar:SetPoint("TOPRIGHT", sr, "TOPRIGHT", 0, 0)
    end
end

-- DRAW COLLECTIONS TAB (Main Entry)

--- Live resize: relayout active sub-tab split chrome without full main-window PopulateContent.
function ns.Collections_RelayoutActiveSubTabChrome()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if ns.UI_RefreshFixedHeaderChrome and mf then
        ns.UI_RefreshFixedHeaderChrome(mf)
    end
    local cf = M.state.contentFrame
    if not cf or not cf:IsVisible() then return end
    local sub = M.state.currentSubTab or "recent"
    if sub == "recent" then
        M.DrawRecentContent(cf)
    elseif sub == "mounts" then
        M.DrawMountsContent(cf)
    elseif sub == "pets" then
        M.DrawPetsContent(cf)
    elseif sub == "toys" then
        M.DrawToysContent(cf)
    elseif sub == "achievements" then
        M.DrawAchievementsContent(cf)
    end
end

function WarbandNexus:DrawCollectionsTab(parent)
    M.RefreshCollectionsLayout()
    M.ApplySessionCollectionsSubTab()
    M.state._collectionsSubTabRedrawScheduled = nil
    if M.ClearCollectionsDrawBusyFlags then
        M.ClearCollectionsDrawBusyFlags()
    end

    local hdrCacheEarly = M.state._fixedHeaderCache
    M.CollectionsSubTabTrace("DrawCollectionsTab_enter", {
        sub = M.state.currentSubTab,
        fixedHeaderReuse = (hdrCacheEarly and hdrCacheEarly.titleCard) and true or false,
    })

    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or 0
    local sideMargin = (chrome and chrome.side) or (metrics and metrics.sideMargin) or (LAYOUT.SIDE_MARGIN or 12)
    local width = (metrics and metrics.contentWidth) or ((parent:GetWidth() or 680) - 20)

    HideEmptyStateCard(parent, "collections")

    -- Fixed top area (title card, sub-tabs, search): reuse frames on intra-tab changes.
    local hdrCache = M.state._fixedHeaderCache

    if hdrCache and hdrCache.titleCard then
        M.CollectionsSubTabTrace("DrawCollectionsTab_fixedHeader_reuse", { sub = M.state.currentSubTab })
        hdrCache.titleCard:SetParent(headerParent)
        if chrome and ns.UI_AnchorTabTitleCard then
            ns.UI_AnchorTabTitleCard(hdrCache.titleCard, chrome)
        else
            hdrCache.titleCard:ClearAllPoints()
            hdrCache.titleCard:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
            hdrCache.titleCard:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        end
        if ns.UI_HideTitleCardUnderline then ns.UI_HideTitleCardUnderline(hdrCache.titleCard) end
        hdrCache.titleCard:Show()

        if hdrCache.recentObtainedPanel then
            hdrCache.recentObtainedPanel:Hide()
        end

        if hdrCache.collectionsTextContainer and hdrCache.collectionsHeaderIcon and ns.UI_ReanchorStandardTabTitleLayout then
            ns.UI_ReanchorStandardTabTitleLayout(
                hdrCache.collectionsHeaderIcon,
                hdrCache.titleCard,
                hdrCache.collectionsTextContainer,
                COLLECTIONS_TITLE_CARD_HEIGHT)
            hdrCache.collectionsTextContainer:Show()
            if hdrCache.collectionsTitleText then hdrCache.collectionsTitleText:Show() end
            if hdrCache.collectionsSubtitleText then
                hdrCache.collectionsSubtitleText:SetWordWrap(false)
                hdrCache.collectionsSubtitleText:SetMaxLines(1)
                hdrCache.collectionsSubtitleText:Show()
            end
        end
        if hdrCache.collectionsHeaderIcon then
            if hdrCache.collectionsHeaderIcon.border then hdrCache.collectionsHeaderIcon.border:Show() end
            if hdrCache.collectionsHeaderIcon.icon then hdrCache.collectionsHeaderIcon.icon:Show() end
        end

        if ns.UI_AdvanceTabChromeYOffset then
            headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, hdrCache.titleCard and hdrCache.titleCard:GetHeight())
        else
            headerYOffset = headerYOffset + (M.GetLayout().afterHeader or 72)
        end

        hdrCache.subTabBar:SetParent(headerParent)
        hdrCache.subTabBar:ClearAllPoints()
        hdrCache.subTabBar:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        hdrCache.subTabBar:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.subTabBar:SetActiveTab(M.state.currentSubTab)
        hdrCache.subTabBar:Show()
        M.state.subTabBar = hdrCache.subTabBar

        headerYOffset = headerYOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)

        if M.LayoutCollectionsFixedSubHeader then
            headerYOffset = M.LayoutCollectionsFixedSubHeader(hdrCache, headerParent, sideMargin, headerYOffset, M.state.currentSubTab)
        end

        hdrCache.searchRow:SetParent(headerParent)
        hdrCache.searchRow:ClearAllPoints()
        hdrCache.searchRow:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        hdrCache.searchRow:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.searchRow:Show()

        hdrCache.filterRow:SetParent(hdrCache.searchRow)
        hdrCache.filterRow:ClearAllPoints()
        hdrCache.filterRow:SetPoint("TOPRIGHT", hdrCache.searchRow, "TOPRIGHT", 0, 0)
        if M.state.currentSubTab == "recent" then
            hdrCache.filterRow:Hide()
        else
            hdrCache.filterRow:Show()
        end
        M.LayoutCollectionsSearchBar(hdrCache)
        M.UpdateCollectionsSearchPlaceholder(hdrCache, M.state.currentSubTab)

        headerYOffset = headerYOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT
    else
        M.CollectionsSubTabTrace("DrawCollectionsTab_fixedHeader_create", { sub = M.state.currentSubTab })
        hdrCache = {}
        M.state._fixedHeaderCache = hdrCache

        local accent = (COLORS and COLORS.accent) or { 0.40, 0.20, 0.58 }
        local r, g, b = accent[1], accent[2], accent[3]
        local hexColor = format("%02x%02x%02x", r * 255, g * 255, b * 255)
        local titleCard, headerIcon, textContainer, titleText, subtitleText = ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "collections",
            titleText = "|cff" .. hexColor .. ((ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections") .. "|r",
            subtitleText = (ns.L and ns.L["COLLECTIONS_SUBTITLE"]) or "Mounts, pets, toys, and transmog overview",
        })
        if chrome and ns.UI_AnchorTabTitleCard then
            ns.UI_AnchorTabTitleCard(titleCard, chrome)
        else
            titleCard:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
            titleCard:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        end
        hdrCache.titleCard = titleCard

        hdrCache.collectionsHeaderIcon = headerIcon
        hdrCache.collectionsTextContainer = textContainer
        hdrCache.collectionsTitleText = titleText
        hdrCache.collectionsSubtitleText = subtitleText

        titleCard:Show()
        if ns.UI_AdvanceTabChromeYOffset then
            headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        else
            headerYOffset = headerYOffset + (M.GetLayout().afterHeader or 72)
        end

        if ns.UI_HideTitleCardExpandCollapseControls then
            ns.UI_HideTitleCardExpandCollapseControls(parent)
        end

        local subTabBar = CreateSubTabBar(headerParent, function(tabKey)
            if M.state.currentSubTab == tabKey then
                if M.state.subTabBar then
                    M.state.subTabBar:SetActiveTab(tabKey)
                end
                return
            end
            local fromSub = M.state.currentSubTab
            M.CollectionsSubTabTrace("SubTabBar_click", { from = fromSub, to = tabKey })
            M.state.currentSubTab = tabKey
            ns._sessionCollectionsSubTab = tabKey
            if fromSub and ns.UI_CancelSearchRefresh then
                ns.UI_CancelSearchRefresh("collections_" .. fromSub)
            end
            if M.state.subTabBar then
                M.state.subTabBar:SetActiveTab(tabKey)
            end
            M.state.searchText = ""
            local hcSearch = M.state._fixedHeaderCache
            if hcSearch and hcSearch.searchClearFn then
                hcSearch.searchClearFn(false)
            end
            if M.ResetCollectionsListScrollPositions then
                M.ResetCollectionsListScrollPositions()
            end
            local hc = M.state._fixedHeaderCache
            if hc and M.UpdateCollectionsFixedSubHeaderText then
                M.UpdateCollectionsFixedSubHeaderText(hc, tabKey)
            end
            local perfOn = ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled()
            local wallStart = perfOn and GetTime() or nil
            M.ScheduleCollectionsSubTabRedraw(fromSub, tabKey, wallStart)
            local hc = M.state._fixedHeaderCache
            if hc and hc.filterRow then
                if M.state.currentSubTab == "recent" then hc.filterRow:Hide() else hc.filterRow:Show() end
                M.LayoutCollectionsSearchBar(hc)
                M.UpdateCollectionsSearchPlaceholder(hc, tabKey)
            end
        end)
        subTabBar:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        subTabBar:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        subTabBar:SetActiveTab(M.state.currentSubTab)
        hdrCache.subTabBar = subTabBar
        M.state.subTabBar = subTabBar

        headerYOffset = headerYOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)

        if M.LayoutCollectionsFixedSubHeader then
            headerYOffset = M.LayoutCollectionsFixedSubHeader(hdrCache, headerParent, sideMargin, headerYOffset, M.state.currentSubTab)
        end

        local rowWsr = math.max(200, headerParent:GetWidth() or ((headerParent.GetParent and headerParent:GetParent() and headerParent:GetParent():GetWidth()) or 660))
        local searchRow = Factory:CreateContainer(headerParent, rowWsr, SEARCH_ROW_HEIGHT, false)
        if not searchRow then
            searchRow = CreateFrame("Frame", nil, headerParent)
            searchRow:SetHeight(SEARCH_ROW_HEIGHT)
        end
        searchRow:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        searchRow:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.searchRow = searchRow

        local FILTER_BLOCK_WIDTH = 200
        local filterRow = Factory:CreateContainer(searchRow, FILTER_BLOCK_WIDTH, SEARCH_ROW_HEIGHT, false)
        if not filterRow then
            filterRow = CreateFrame("Frame", nil, searchRow)
            filterRow:SetSize(FILTER_BLOCK_WIDTH, SEARCH_ROW_HEIGHT)
        end
        filterRow:SetPoint("TOPRIGHT", searchRow, "TOPRIGHT", 0, 0)
        hdrCache.filterRow = filterRow

        local searchPlaceholder = M.GetCollectionsSearchPlaceholder(M.state.currentSubTab)
        local searchBar, clearSearch = CreateSearchBox(
            searchRow,
            1,
            searchPlaceholder,
            function(text)
                M.state.searchText = text
                if text == "" then
                    ns.UI_CancelSearchRefresh(CollectionsSearchRefreshKey())
                    RedrawCollectionsSearchContentImmediate()
                else
                    ScheduleCollectionsSearchRedraw()
                end
            end,
            nil,
            M.state.searchText or "",
            "collections"
        )
        searchBar:SetPoint("TOPLEFT", searchRow, "TOPLEFT", 0, 0)
        hdrCache.searchBar = searchBar
        hdrCache.searchClearFn = clearSearch
        M.state.searchContainer = searchBar

        local lblOwned = (ns.L and (ns.L["FILTER_SHOW_OWNED"] or ns.L["FILTER_COLLECTED"])) or "Owned"
        local lblMissing = (ns.L and (ns.L["FILTER_SHOW_MISSING"] or ns.L["FILTER_UNCOLLECTED"])) or "Missing"

        local cbCollected = CreateThemedCheckbox(filterRow, M.state.showCollected)
        cbCollected:SetPoint("LEFT", filterRow, "LEFT", CONTENT_INSET, 0)
        local lblCollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblCollected:SetPoint("LEFT", cbCollected, "RIGHT", 4, 0)
        lblCollected:SetText(lblOwned)
        local textNormal = (COLORS and COLORS.textNormal) or { 0.92, 0.94, 0.98 }
        lblCollected:SetTextColor(textNormal[1], textNormal[2], textNormal[3])
        lblCollected:SetJustifyH("LEFT")
        cbCollected:SetScript("OnClick", function(self)
            M.state.showCollected = self:GetChecked()
            if self:GetChecked() then cbCollected.checkTexture:Show() else cbCollected.checkTexture:Hide() end
            if M.state.contentFrame then
                if M.state.currentSubTab == "recent" then
                    M.DrawRecentContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "mounts" then
                    M.DrawMountsContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "pets" then
                    M.DrawPetsContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "toys" then
                    M.DrawToysContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "achievements" then
                    M.DrawAchievementsContent(M.state.contentFrame)
                end
            end
        end)

        local cbUncollected = CreateThemedCheckbox(filterRow, M.state.showUncollected)
        cbUncollected:SetPoint("LEFT", lblCollected, "RIGHT", CONTENT_INSET * 2, 0)
        local lblUncollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblUncollected:SetPoint("LEFT", cbUncollected, "RIGHT", 4, 0)
        lblUncollected:SetText(lblMissing)
        lblUncollected:SetTextColor(textNormal[1], textNormal[2], textNormal[3])
        lblUncollected:SetJustifyH("LEFT")
        cbUncollected:SetScript("OnClick", function(self)
            M.state.showUncollected = self:GetChecked()
            if self:GetChecked() then cbUncollected.checkTexture:Show() else cbUncollected.checkTexture:Hide() end
            if M.state.contentFrame then
                if M.state.currentSubTab == "recent" then
                    M.DrawRecentContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "mounts" then
                    M.DrawMountsContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "pets" then
                    M.DrawPetsContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "toys" then
                    M.DrawToysContent(M.state.contentFrame)
                elseif M.state.currentSubTab == "achievements" then
                    M.DrawAchievementsContent(M.state.contentFrame)
                end
            end
        end)

        if not M.state.showCollected and not M.state.showUncollected then
            M.state.showCollected = true
            M.state.showUncollected = true
            cbCollected:SetChecked(true)
            cbCollected.checkTexture:Show()
            cbUncollected:SetChecked(true)
            cbUncollected.checkTexture:Show()
        end

        if M.state.currentSubTab == "recent" then
            filterRow:Hide()
        end
        M.LayoutCollectionsSearchBar(hdrCache)

        headerYOffset = headerYOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT
    end

    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif fixedHeader then
        fixedHeader:SetHeight(headerYOffset)
    end

    local yOffset = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8

    local scrollFrame = parent:GetParent()
    local viewHeight = (scrollFrame and scrollFrame:GetHeight()) or 450
    local bottomPad = 0
    local contentHeight = math.max(250, viewHeight - yOffset - bottomPad)
    local parentWidth = parent:GetWidth() or 680
    local contentWidth = math.max(1, parentWidth - (sideMargin * 2))
    if M.state.currentSubTab == "recent" and ns.UI_ResolveMainTabBodyWidth then
        local bodyW = ns.UI_ResolveMainTabBodyWidth(mf, parent)
        if bodyW and bodyW > 0 then
            contentWidth = bodyW
        end
    end

    local contentFrame = M.state.contentFrame
    if contentFrame then
        contentFrame:SetParent(parent)
        contentFrame:ClearAllPoints()
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        contentFrame._wnKeepOnTabSwitch = true
        M.state.contentFrame = contentFrame
    else
        contentFrame = Factory:CreateContainer(parent, contentWidth, contentHeight, false)
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        contentFrame._wnKeepOnTabSwitch = true
        M.state.contentFrame = contentFrame
        M.state.viewerContainer = nil
        M.state.mountListContainer = nil
        M.state.mountListScrollFrame = nil
        M.state.mountListScrollChild = nil
        M.state.mountListScrollBarContainer = nil
        M.state.petListContainer = nil
        M.state.petListScrollFrame = nil
        M.state.petListScrollChild = nil
        M.state.petListScrollBarContainer = nil
        M.state.achievementListContainer = nil
        M.state.achievementListScrollFrame = nil
        M.state.achievementListScrollChild = nil
        M.state.achievementListScrollBarContainer = nil
        M.state.achievementDetailPanel = nil
        M.state.achievementDetailContainer = nil
        M.state.toyListContainer = nil
        M.state.toyListScrollFrame = nil
        M.state.toyListScrollChild = nil
        M.state.toyListScrollBarContainer = nil
        M.state.toyDetailContainer = nil
        M.state.toyDetailScrollBarContainer = nil
        M.state.collectionRightColumn = nil
        M.state.collectionProgressFrame = nil
        M.state.collectionProgressBar = nil
        M.state.collectionProgressLabel = nil
        M.state.modelViewer = nil
        M.state.loadingPanel = nil
        M.state._achFlatList = nil
        M.state._achVisibleRowFrames = nil
        M.state._achListContentFrame = nil
        M.state.recentTabPanel = nil
        M.state.recentViewportCap = nil
        M.state._recentEmptyFs = nil
    end

    if M.ScheduleCollectionsSubTabPrewarm and C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf and mf:IsShown() and mf.currentTab == "collections" then
                M.ScheduleCollectionsSubTabPrewarm()
            end
        end)
    end

    -- Draw current sub-tab content
    if M.state.currentSubTab == "recent" then
        M.state.recentViewportCap = contentHeight
        M.state._recentMinScrollSideMargin = sideMargin
        M.state._recentGridScrollWidth = nil
        M.DrawRecentContent(contentFrame)
        contentHeight = contentFrame:GetHeight() or contentHeight
    elseif M.state.currentSubTab == "mounts" then
        M.DrawMountsContent(contentFrame)
    elseif M.state.currentSubTab == "pets" then
        M.DrawPetsContent(contentFrame)
    elseif M.state.currentSubTab == "toys" then
        M.DrawToysContent(contentFrame)
    elseif M.state.currentSubTab == "achievements" then
        M.DrawAchievementsContent(contentFrame)
    end

    yOffset = yOffset + contentHeight + bottomPad

    -- Event-driven updates (same events as Plans): all sub-tabs (Mounts, Pets, Achievements) refresh when these fire.
    -- Use a dedicated listener key (CUIListeners) instead of WarbandNexus as self.
    -- AceEvent allows only ONE handler per (event, self) pair â€” using WarbandNexus would
    -- overwrite CollectionService's handlers for the same events (e.g. RemoveFromUncollected).
    if not M.state._messageRegistered then
        M.state._messageRegistered = true
        local CUIListeners = {}
        M.state._listeners = CUIListeners

        local function InvalidateAllCollectionCaches()
            M.state._collectionsPrewarmGen = (M.state._collectionsPrewarmGen or 0) + 1
            M.state._cachedMountsData = nil
            M.state._cachedPetsData = nil
            M.state._cachedToysData = nil
            M.state._lastGroupedMountData = nil
            M.state._mountFlatList = nil
            M.state._lastGroupedPetData = nil
            M.state._petFlatList = nil
            M.state._lastGroupedToyData = nil
            M.state._toyFlatList = nil
            M.state._achGroupedCache = nil
            M.state._lastAchievementCategoryData = nil
            M.state._achFlatList = nil
        end

        local function InvalidateCollectionCachesForType(collectionType)
            if collectionType == "mount" then
                M.state._cachedMountsData = nil
                M.state._lastGroupedMountData = nil
                M.state._mountFlatList = nil
            elseif collectionType == "pet" then
                M.state._cachedPetsData = nil
                M.state._lastGroupedPetData = nil
                M.state._petFlatList = nil
            elseif collectionType == "toy" then
                M.state._cachedToysData = nil
                M.state._lastGroupedToyData = nil
                M.state._toyFlatList = nil
            elseif collectionType == "achievement" then
                M.state._achGroupedCache = nil
                M.state._lastAchievementCategoryData = nil
                M.state._achFlatList = nil
            else
                InvalidateAllCollectionCaches()
            end
        end

        local function RedrawActiveCollectionSubTab()
            if not M.state.contentFrame then return end
            if M.state.currentSubTab == "recent" then
                M.DrawRecentContent(M.state.contentFrame)
            elseif M.state.currentSubTab == "mounts" then
                M.DrawMountsContent(M.state.contentFrame)
            elseif M.state.currentSubTab == "pets" then
                M.DrawPetsContent(M.state.contentFrame)
            elseif M.state.currentSubTab == "toys" then
                M.DrawToysContent(M.state.contentFrame)
            elseif M.state.currentSubTab == "achievements" then
                M.DrawAchievementsContent(M.state.contentFrame)
            end
        end

        -- Full tab redraw on every SCAN_PROGRESS is very heavy on low-end CPUs (DrawMountsContent rebuilds UI).
        -- Always bump the lightweight progress bar; throttle full redraw + trailing coalesce.
        local SCAN_PROGRESS_FULL_REDRAW_INTERVAL = 0.45
        local scanProgressRedrawTimer = nil
        local function CancelScanProgressRedrawTimer()
            if scanProgressRedrawTimer then
                if scanProgressRedrawTimer.Cancel then
                    scanProgressRedrawTimer:Cancel()
                end
                scanProgressRedrawTimer = nil
            end
        end
        local function ScheduleCoalescedScanProgressRedraw()
            CancelScanProgressRedrawTimer()
            scanProgressRedrawTimer = C_Timer.NewTimer(SCAN_PROGRESS_FULL_REDRAW_INTERVAL, function()
                scanProgressRedrawTimer = nil
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if mf and mf:IsShown() and mf.currentTab == "collections" and M.state.contentFrame then
                    M.state._lastScanProgressFullRedraw = GetTime()
                    RedrawActiveCollectionSubTab()
                end
            end)
        end

        local eventName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_PROGRESS) or "WN_COLLECTION_SCAN_PROGRESS"
        WarbandNexus.RegisterMessage(CUIListeners, eventName, function(_, data)
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if not mf or not mf:IsShown() or mf.currentTab ~= "collections" or not M.state.contentFrame then
                return
            end
            if data then
                M.SetCollectionProgress(data.scanned, data.total)
            end
            local now = GetTime()
            local last = M.state._lastScanProgressFullRedraw or 0
            if (now - last) >= SCAN_PROGRESS_FULL_REDRAW_INTERVAL then
                M.state._lastScanProgressFullRedraw = now
                CancelScanProgressRedrawTimer()
                RedrawActiveCollectionSubTab()
            else
                ScheduleCoalescedScanProgressRedraw()
            end
        end)

        local completeName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_COMPLETE) or "WN_COLLECTION_SCAN_COMPLETE"
        WarbandNexus.RegisterMessage(CUIListeners, completeName, function()
            CancelScanProgressRedrawTimer()
            InvalidateAllCollectionCaches()
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() and mf.currentTab == "collections" then
                RedrawActiveCollectionSubTab()
            end
        end)

        local updatedName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED) or "WN_COLLECTION_UPDATED"
        WarbandNexus.RegisterMessage(CUIListeners, updatedName, function(_, updatedType)
            if updatedType ~= "mount" and updatedType ~= "pet" and updatedType ~= "toy" and updatedType ~= "achievement" then return end
            InvalidateCollectionCachesForType(updatedType)
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                RedrawActiveCollectionSubTab()
            end)
        end)

        local plansUpdatedName = (Constants and Constants.EVENTS and Constants.EVENTS.PLANS_UPDATED) or "WN_PLANS_UPDATED"
        WarbandNexus.RegisterMessage(CUIListeners, plansUpdatedName, function()
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                RedrawActiveCollectionSubTab()
            end)
        end)

        local trackingUpdatedName = (Constants and Constants.EVENTS and Constants.EVENTS.ACHIEVEMENT_TRACKING_UPDATED) or "WN_ACHIEVEMENT_TRACKING_UPDATED"
        WarbandNexus.RegisterMessage(CUIListeners, trackingUpdatedName, function(_, payload)
            if not payload or not payload.achievementID then return end
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                if M.state.currentSubTab ~= "achievements" then return end
                if not M.state.contentFrame then return end
                M.DrawAchievementsContent(M.state.contentFrame)
            end)
        end)

        local obtainedName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTIBLE_OBTAINED) or "WN_COLLECTIBLE_OBTAINED"
        WarbandNexus.RegisterMessage(CUIListeners, obtainedName, function(_, data)
            if not data or not data.type then return end
            if data.type ~= "mount" and data.type ~= "pet" and data.type ~= "toy" and data.type ~= "achievement" then return end
            InvalidateCollectionCachesForType(data.type)
            C_Timer.After(0.05, function()
                local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
                if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
                RedrawActiveCollectionSubTab()
            end)
        end)

        local metadataReadyName = (Constants and Constants.EVENTS and Constants.EVENTS.ITEM_METADATA_READY) or "WN_ITEM_METADATA_READY"
        WarbandNexus.RegisterMessage(CUIListeners, metadataReadyName, function(_, achievementID)
            if not achievementID then return end
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if not mf or not mf:IsShown() or mf.currentTab ~= "collections" then return end
            if M.state.currentSubTab ~= "achievements" then return end
            if M.state.achievementDetailPanel and M.state.achievementDetailPanel.SetAchievement then
                local currentAch = M.state.achievementDetailPanel._currentAchievement
                if currentAch and currentAch.id == achievementID then
                    M.state.achievementDetailPanel:SetAchievement(currentAch)
                end
            end
        end)
    end

    return yOffset
end

if ns.UI_LayoutCoordinator then
    local LC = ns.UI_LayoutCoordinator
    local function CollectionsViewportRelayout(_scrollChild, _contentWidth, mf)
        if not mf or mf.currentTab ~= "collections" then return false end
        if ns.Collections_RelayoutActiveSubTabChrome then
            ns.Collections_RelayoutActiveSubTabChrome()
            return true
        end
        return false
    end
    LC:RegisterTabAdapter("collections", {
        OnViewportWidthChanged = function(scrollChild, contentWidth, mf)
            -- Corner-drag: shell only (Items/Chars parity). Full sub-tab Draw* during drag caused flicker + CPU spikes.
            if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mf) then
                return true
            end
            local tokens = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SCROLL or {}
            local delay = tokens.COLLECTIONS_LIVE_RELAYOUT_DEBOUNCE_SEC or 0.12
            LC:ScheduleTabLiveRelayout("collections_live", delay, function()
                CollectionsViewportRelayout(scrollChild, contentWidth, mf)
            end)
            return true
        end,
        OnViewportLayoutCommit = CollectionsViewportRelayout,
    })
end
