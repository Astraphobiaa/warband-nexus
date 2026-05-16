--[[
    Warband Nexus - Collections Tab
    Sub-tab system: Mounts, Pets, Toys, etc.
    Mounts tab: Virtual scroll list grouped by Source, Model Viewer, Description panel.

    WN_PERF: Chunked virtual fills (`RUN_CHUNK_SIZE`), sub-tab defer delay (`COLLECTION_HEAVY_DELAY`), avoids blocking first paint where possible.
]]

local ns = select(2, ...)
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local Constants = ns.Constants

local issecretvalue = issecretvalue
local Utilities = ns.Utilities
local function SafeLower(s)
    if Utilities and Utilities.SafeLower then
        return Utilities:SafeLower(s)
    end
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

local CreateCard = ns.UI_CreateCard
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local PlanCardFactory = ns.UI_PlanCardFactory
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local CreateIcon = ns.UI_CreateIcon

-- Single source for layout (matches CurrencyUI, PlansUI, SharedWidgets)
local function GetLayout()
    if ns.GetUILayoutTokens then return ns.GetUILayoutTokens() end
    return ns.UI_LAYOUT or ns.UI_SPACING or {}
end
local LAYOUT, SIDE_MARGIN, TOP_MARGIN, CARD_GAP, AFTER_ELEMENT, ROW_ICON_SIZE
local DETAIL_ICON_SIZE, STATUS_ICON_SIZE, SCROLL_CONTENT_TOP_PADDING
local function RefreshCollectionsLayout()
    LAYOUT = GetLayout()
    SIDE_MARGIN = LAYOUT.SIDE_MARGIN or 10
    TOP_MARGIN = LAYOUT.TOP_MARGIN or 8
    CARD_GAP = LAYOUT.CARD_GAP or 8
    AFTER_ELEMENT = LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8
    ROW_ICON_SIZE = LAYOUT.ROW_ICON_SIZE or 20
    DETAIL_ICON_SIZE = LAYOUT.DETAIL_ICON_SIZE or 64
    STATUS_ICON_SIZE = LAYOUT.STATUS_ICON_SIZE or 16
    SCROLL_CONTENT_TOP_PADDING = LAYOUT.SCROLL_CONTENT_TOP_PADDING or 12
end
RefreshCollectionsLayout()
-- Symmetric layout: all panels use same inset; no magic numbers.
local CONTENT_INSET = LAYOUT.CONTENT_INSET or LAYOUT.CARD_GAP or 8
local CONTAINER_INSET = LAYOUT.CONTAINER_INSET or 2
local TEXT_GAP = AFTER_ELEMENT
local SEARCH_ROW_HEIGHT = 32  -- Plans ile birebir aynı
-- Title card: 70px + text block 200x40 + icon gap 12 — birebir CurrencyUI / ItemsUI.
local COLLECTIONS_TITLE_CARD_HEIGHT = 70
local RECENT_SECTION_ORDER = { "achievement", "mount", "pet", "toy" }
local RECENT_CARD_ICON = 20
local RECENT_CARD_HEADER_PAD = 8
local SUBTAB_BAR_HEIGHT = LAYOUT.HEADER_HEIGHT or 32
local PROGRESS_ROW_HEIGHT = 28
local BAR_INSET = 2  -- Bar 2px each side = total 4px inside border

local function CollectionsRecentCategoryLabel(ctype)
    local loc = ns.L
    if ctype == "mount" then return (loc and loc["CATEGORY_MOUNTS"]) or "Mounts"
    elseif ctype == "pet" then return (loc and loc["CATEGORY_PETS"]) or "Pets"
    elseif ctype == "toy" then return (loc and loc["CATEGORY_TOYS"]) or "Toys"
    elseif ctype == "achievement" then return (loc and loc["CATEGORY_ACHIEVEMENTS"]) or "Achievements"
    elseif ctype == "title" then return (loc and loc["CATEGORY_TITLES"]) or "Titles"
    elseif ctype == "illusion" then return (loc and loc["CATEGORY_ILLUSIONS"]) or "Illusions"
    elseif ctype == "transmog" then return (loc and loc["CATEGORY_TRANSMOG"]) or "Transmog"
    end
    return tostring(ctype or "")
end

local function FormatCollectionsRecentRelativeTime(ts)
    if not ts or type(ts) ~= "number" then return "" end
    local now = time()
    local sec = now - ts
    if sec < 0 then sec = 0 end
    local loc = ns.L
    if sec < 60 then
        return (loc and loc["COLLECTIONS_RECENT_JUST_NOW"]) or "Just now"
    end
    if sec < 3600 then
        return format((loc and loc["COLLECTIONS_RECENT_MINUTES_AGO"]) or "%d min ago", math.floor(sec / 60))
    end
    if sec < 86400 then
        return format((loc and loc["COLLECTIONS_RECENT_HOURS_AGO"]) or "%d hr ago", math.floor(sec / 3600))
    end
    return format((loc and loc["COLLECTIONS_RECENT_DAYS_AGO"]) or "%d days ago", math.floor(sec / 86400))
end

-- Detail panel: when the addon last logged this collectible (same source as the recent strip).
local function FormatCollectionsAcquiredDetail(ts)
    if not ts or type(ts) ~= "number" then return nil end
    local loc = ns.L
    local rel = FormatCollectionsRecentRelativeTime(ts)
    local label = (loc and loc["COLLECTIONS_ACQUIRED_LABEL"]) or "Recorded"
    return format((loc and loc["COLLECTIONS_ACQUIRED_LINE"]) or "%s: %s", label, rel)
end

local format = string.format
local SD = ns.CollectionsUI_SourceData

-- ============================================================================
-- MOUNT LIST (Factory layout: ScrollFrame + SectionHeader + DataRow)
-- ============================================================================

local Factory = ns.UI.Factory
local PADDING = SIDE_MARGIN
-- Single source: bar/button sizes and column width so Mounts/Pets/Toys/Achievements look identical
local SCROLLBAR_GAP = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
local SCROLLBAR_SIDE_GAP = 5  -- Equal gap between list <-> scrollbar and scrollbar <-> details
-- Match Plans: defer sub-tab draw and heavy work by 0.05s for smooth switching.
local COLLECTION_HEAVY_DELAY = 0.05
--- Avoid synchronous EnsureCollectionData from tab timers when store is already warm; coalesce pipeline start otherwise.
local function RequestCollectionFillFromUI()
    if ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading then
        return
    end
    if WarbandNexus.IsCollectionEnsureDataComplete and WarbandNexus:IsCollectionEnsureDataComplete() then
        return
    end
    if ns.ScheduleEnsureCollectionDataDeferred then
        ns.ScheduleEnsureCollectionDataDeferred()
    elseif WarbandNexus.EnsureCollectionData then
        WarbandNexus:EnsureCollectionData()
    end
end
-- Process this many mounts/pets per frame to avoid 1s freeze (spread over multiple frames).
local RUN_CHUNK_SIZE = 100
-- Same row/header dimensions for all three sub-tabs (Mounts, Pets, Achievements); matches SharedWidgets/UI_SPACING
local ROW_HEIGHT = LAYOUT.ROW_HEIGHT or 26
-- Mount/Pet/Toy category headers: must match CreateCollapsibleHeader + CollectionVirtual_FillRowScrollIndex (collapsible sections + virtual rows).
local COLLAPSE_HEADER_HEIGHT_COLL = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT) or 36

-- Detail container border: SharedWidgets 4-texture border system (accent)
local function ApplyDetailAccentVisuals(frame)
    if ns.UI_ApplyDetailContainerVisuals then
        ns.UI_ApplyDetailContainerVisuals(frame)
    elseif frame and ApplyVisuals then
        ApplyVisuals(frame, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
end

local function ScrollFrameByMouseWheel(scrollFrame, delta)
    if not scrollFrame then return end
    local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
    local cur = scrollFrame:GetVerticalScroll()
    local maxS = scrollFrame:GetVerticalScrollRange()
    local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
    scrollFrame:SetVerticalScroll(newScroll)
    if scrollFrame.ScrollBar and scrollFrame.ScrollBar.SetValue then
        scrollFrame.ScrollBar:SetValue(newScroll)
    end
end

local function EnableStandardScrollWheel(scrollFrame)
    if not scrollFrame then return end
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        ScrollFrameByMouseWheel(self, delta)
    end)
end

local function CreateStandardScrollChild(scrollFrame, width, height)
    if not scrollFrame or not Factory or not Factory.CreateContainer then return nil end
    local scrollChild = Factory:CreateContainer(scrollFrame, width or 1, height or 1, false)
    if width then
        scrollChild:SetWidth(width)
    end
    if height then
        scrollChild:SetHeight(height)
    end
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:EnableMouseWheel(true)
    scrollChild:SetScript("OnMouseWheel", function(_, delta)
        ScrollFrameByMouseWheel(scrollFrame, delta)
    end)
    return scrollChild
end

local function EnsureListScrollBarContainer(existingContainer, parent, anchorFrame, columnWidth, height, sideGap)
    local container = existingContainer
    if not container then
        container = Factory:CreateContainer(parent, columnWidth, height, false)
    end
    container:SetSize(columnWidth, height)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", sideGap or 0, 0)
    container:SetFrameLevel((anchorFrame and anchorFrame:GetFrameLevel() or 0) + 4)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

-- Details scrollbar: üst/alt boşluk (küçük = scrollbar daha uzun, aşağı/yukarı uzar)
local DETAIL_SCROLLBAR_VERTICAL_INSET = 4

local function EnsureDetailScrollBarContainer(existingContainer, parent, columnWidth, inset, verticalInset)
    verticalInset = verticalInset or DETAIL_SCROLLBAR_VERTICAL_INSET
    local container = existingContainer
    if not container then
        container = Factory:CreateContainer(parent, columnWidth, 1, false)
    end
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -verticalInset)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, verticalInset)
    container:SetWidth(columnWidth)
    container:SetFrameLevel((parent and parent:GetFrameLevel() or 0) + 4)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

-- ============================================================================
-- DETAILS WINDOW DIFFERENCES: Mounts vs ToyBox vs Achievement
-- ============================================================================
-- Mounts: viewerContainer (CreateContainer) → mountDetailEmptyOverlay + modelViewer (CreateModelViewer).
--   Single panel: icon, name, source, description, 3D model. No scroll; content fixed in one panel.
-- ToyBox: toyDetailContainer (CreateContainer) → toyDetailEmptyOverlay + _toyDetailScroll (ScrollFrame).
--   ScrollChild has: headerRow (icon, name), collectedBadge, sourceLabel. Scroll-based; no 3D model.
-- Achievement: achievementDetailContainer (CreateContainer) → achDetailEmptyOverlay + achievementDetailPanel.
--   achievementDetailPanel = CreateAchievementDetailPanel (Frame + inner ScrollFrame, dynamic content:
--   description, achievement series list, criteria). Panel has its own border/ApplyVisuals and scroll.
-- All three use CreateDetailEmptyOverlay(container, typeKey) for empty state; same overlay styling.
-- ============================================================================

-- Empty detail state: single centered line "Select a X to see details." (all 4 collection tabs)
-- Neutral grey background, no border. Inset by 1px so parent's accent border stays visible.
local BORDER_INSET = 1
local function CreateDetailEmptyOverlay(parent, typeKey)
    if not parent then return nil end
    local w = parent:GetWidth() or 200
    local h = parent:GetHeight() or 200
    local overlay = Factory:CreateContainer(parent, w, h, false)
    if not overlay then return nil end
    overlay:SetPoint("TOPLEFT", parent, "TOPLEFT", BORDER_INSET, -BORDER_INSET)
    overlay:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
    overlay:EnableMouse(false)
    if ApplyVisuals then ApplyVisuals(overlay, {0.08, 0.08, 0.10, 0.98}, {0, 0, 0, 0}) end
    local fmt = (ns.L and ns.L["SELECT_TO_SEE_DETAILS"]) or "Select a %s to see details."
    if fmt == "SELECT_TO_SEE_DETAILS" then fmt = "Select a %s to see details." end
    local typeName = (typeKey == "mount" and ((ns.L and ns.L["TYPE_MOUNT"]) or "mount"))
        or (typeKey == "pet" and ((ns.L and ns.L["TYPE_PET"]) or "pet"))
        or (typeKey == "toy" and ((ns.L and ns.L["TYPE_TOY"]) or "toy"))
        or (typeKey == "achievement" and ((ns.L and ns.L["ACHIEVEMENT"]) or "achievement"))
        or typeKey
    if typeName == "TYPE_MOUNT" then typeName = "mount" end
    if typeName == "TYPE_PET" then typeName = "pet" end
    if typeName == "TYPE_TOY" then typeName = "toy" end
    if typeName == "ACHIEVEMENT" then typeName = "achievement" end
    local text = format(fmt, typeName)
    local fs = FontManager:CreateFontString(overlay, "body", "OVERLAY")
    fs:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText("|cff888888" .. text .. "|r")
    fs:SetWordWrap(true)
    overlay.text = fs
    overlay:Hide()
    return overlay
end

-- State for Collections tab (must be defined before PopulateMountList / ApplySessionCollectionsSubTab — Lua 5.1 local scope)
local VALID_COLLECTIONS_SUBTABS = {
    recent = true,
    mounts = true,
    pets = true,
    toys = true,
    achievements = true,
}

-- Must appear before ApplySessionCollectionsSubTab: Lua 5.1 local scope starts after this statement,
-- so a function defined above would otherwise resolve `collectionsState` as a nil global.
local collectionsState = {
    currentSubTab = "recent",
    mountListContainer = nil,
    mountListScrollFrame = nil,
    mountListScrollChild = nil,
    petListContainer = nil,
    petListScrollFrame = nil,
    petListScrollChild = nil,
    modelViewer = nil,
    descriptionPanel = nil,
    loadingPanel = nil,
    searchBox = nil,
    contentFrame = nil,
    subTabBar = nil,
    showCollected = true,
    showUncollected = true,
    collapsedHeaders = {},
    collapsedHeadersMounts = {},
    collapsedHeadersPets = {},
    selectedMountID = nil,
    selectedPetID = nil,
    selectedAchievementID = nil,
    achievementListContainer = nil,
    achievementListScrollFrame = nil,
    achievementListScrollChild = nil,
    achievementListScrollBarContainer = nil,
    achievementDetailPanel = nil,
    toyListContainer = nil,
    toyListScrollFrame = nil,
    toyListScrollChild = nil,
    toyListScrollBarContainer = nil,
    toyDetailContainer = nil,
    toyDetailScrollBarContainer = nil,
    collapsedHeadersToys = {},
    selectedToyID = nil,
    initialized = false,
    recentTabPanel = nil,
    --- Last viewport height cap for Recent layout (rows fill vs main-window scroll); refreshed in DrawCollectionsTab.
    recentViewportCap = nil,
    _recentEmptyFs = nil,
}

--- Per login/reload: nil → default Recent. After user picks a sub-tab, restored while the UI session lasts.
local function ApplySessionCollectionsSubTab()
    local s = ns._sessionCollectionsSubTab
    if s and VALID_COLLECTIONS_SUBTABS[s] then
        collectionsState.currentSubTab = s
    else
        collectionsState.currentSubTab = "recent"
    end
end

---Bump draw generations so RunChunked* callbacks exit (tab switch / AbortTabOperations).
function WarbandNexus:AbortCollectionsChunkedBuilds()
    collectionsState._mountsDrawGen = (collectionsState._mountsDrawGen or 0) + 1
    collectionsState._petDrawGen = (collectionsState._petDrawGen or 0) + 1
    collectionsState._toysDrawGen = (collectionsState._toysDrawGen or 0) + 1
end

local _populateMountListBusy = false

--- Coalesce virtual-list visible-range refreshes after layout (scroll metrics). Two passes (0 + 50ms)
--- were enough for header/width sync; a third pass at 120ms duplicated heavy work (mount/pet/toy lists).
local function ScheduleCollectionsVisibleSync(subTabKey, refreshFn)
    if type(refreshFn) ~= "function" then return end
    C_Timer.After(0, function()
        if collectionsState.currentSubTab == subTabKey then
            refreshFn()
        end
    end)
    C_Timer.After(0.05, function()
        if collectionsState.currentSubTab == subTabKey then
            refreshFn()
        end
    end)
end

-- Build flat list for virtual scrolling: [{ type = "header", ... } | { type = "row", ... }], totalHeight
-- Sayılar (Drop 669, Quest 87, vb.) grouped[key] uzunluğundan gelir; liste ile tutarlıdır.
local function BuildFlatMountList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD = COLORS.textDim[1] or 0.55
    local gD = COLORS.textDim[2] or 0.55
    local bD = COLORS.textDim[3] or 0.55
    local countColor = format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
    local rB = COLORS.textBright[1] or 1
    local gB = COLORS.textBright[2] or 1
    local bB = COLORS.textBright[3] or 1
    local titleColor = format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)
    local sectionGap = (LAYOUT.betweenSections or LAYOUT.SECTION_SPACING or 8)
    local nCats = #SD.SOURCE_CATEGORIES
    for ci = 1, nCats do
        local catInfo = SD.SOURCE_CATEGORIES[ci]
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            if #flat > 0 then
                yOffset = yOffset + sectionGap
            end
            local isCollapsed = (collapsedHeaders[key] ~= false)
            local itemCount = #items
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. catInfo.label .. "|r " .. countColor .. "(" .. itemCount .. ")|r",
                rightStr = countColor .. itemCount .. "|r",
                itemCount = itemCount,
                isCollapsed = isCollapsed,
                yOffset = yOffset,
                height = COLLAPSE_HEADER_HEIGHT_COLL,
            }
            yOffset = yOffset + COLLAPSE_HEADER_HEIGHT_COLL
            local nItems = #items
            for ji = 1, nItems do
                rowCounter = rowCounter + 1
                flat[#flat + 1] = { type = "row", mount = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                yOffset = yOffset + ROW_HEIGHT
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

local function BuildFlatPetList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD = COLORS.textDim[1] or 0.55
    local gD = COLORS.textDim[2] or 0.55
    local bD = COLORS.textDim[3] or 0.55
    local countColor = format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
    local rB = COLORS.textBright[1] or 1
    local gB = COLORS.textBright[2] or 1
    local bB = COLORS.textBright[3] or 1
    local titleColor = format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)
    local sectionGap = (LAYOUT.betweenSections or LAYOUT.SECTION_SPACING or 8)
    local nCats = #SD.PET_SOURCE_CATEGORIES
    for ci = 1, nCats do
        local catInfo = SD.PET_SOURCE_CATEGORIES[ci]
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            if #flat > 0 then
                yOffset = yOffset + sectionGap
            end
            local isCollapsed = (collapsedHeaders[key] ~= false)
            local itemCount = #items
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. catInfo.label .. "|r " .. countColor .. "(" .. itemCount .. ")|r",
                rightStr = countColor .. itemCount .. "|r",
                itemCount = itemCount,
                isCollapsed = isCollapsed,
                yOffset = yOffset,
                height = COLLAPSE_HEADER_HEIGHT_COLL,
            }
            yOffset = yOffset + COLLAPSE_HEADER_HEIGHT_COLL
            local nItems = #items
            for ji = 1, nItems do
                rowCounter = rowCounter + 1
                flat[#flat + 1] = { type = "row", pet = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                yOffset = yOffset + ROW_HEIGHT
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

---categoriesOverride: optional list of { key, label } for toys (C_ToyBox source type). If nil, uses SD.SOURCE_CATEGORIES.
local function BuildFlatToyList(groupedData, collapsedHeaders, categoriesOverride)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD = COLORS.textDim[1] or 0.55
    local gD = COLORS.textDim[2] or 0.55
    local bD = COLORS.textDim[3] or 0.55
    local countColor = format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
    local rB = COLORS.textBright[1] or 1
    local gB = COLORS.textBright[2] or 1
    local bB = COLORS.textBright[3] or 1
    local titleColor = format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)
    local sectionGap = (LAYOUT.betweenSections or LAYOUT.SECTION_SPACING or 8)
    local categories = (categoriesOverride and #categoriesOverride > 0) and categoriesOverride or SD.SOURCE_CATEGORIES
    local nCats = #categories
    for ci = 1, nCats do
        local catInfo = categories[ci]
        local key = catInfo.key
        local items = groupedData and groupedData[key]
        if items and #items > 0 then
            if #flat > 0 then
                yOffset = yOffset + sectionGap
            end
            local isCollapsed = (collapsedHeaders[key] ~= false)
            local itemCount = #items
            local labelText = (catInfo.label and catInfo.label ~= "") and catInfo.label or key
            flat[#flat + 1] = {
                type = "header",
                key = key,
                label = titleColor .. labelText .. "|r " .. countColor .. "(" .. itemCount .. ")|r",
                rightStr = countColor .. itemCount .. "|r",
                itemCount = itemCount,
                isCollapsed = isCollapsed,
                yOffset = yOffset,
                height = COLLAPSE_HEADER_HEIGHT_COLL,
            }
            yOffset = yOffset + COLLAPSE_HEADER_HEIGHT_COLL
            local nItems = #items
            for ji = 1, nItems do
                rowCounter = rowCounter + 1
                flat[#flat + 1] = { type = "row", toy = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT }
                yOffset = yOffset + ROW_HEIGHT
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

-- Toys: flat list only (no categories). items = array of { id, name, icon, collected }.
local function BuildFlatToyListOnly(items)
    local flat = {}
    local yOffset = 0
    for i = 1, #items do
        flat[#flat + 1] = { type = "row", toy = items[i], rowIndex = i, yOffset = yOffset, height = ROW_HEIGHT }
        yOffset = yOffset + ROW_HEIGHT
    end
    return flat, math.max(yOffset + PADDING, 1)
end

-- Achievement grouping: API category hierarchy (GetCategoryList, GetCategoryInfo) — same as Plans.
local function BuildGroupedAchievementData(searchText, showCollected, showUncollected)
    local allCategoryIDs = GetCategoryList and GetCategoryList() or {}
    if #allCategoryIDs == 0 then return {}, {}, 0 end

    local categoryData = {}
    local rootCategories = {}

    for index = 1, #allCategoryIDs do
        local categoryID = allCategoryIDs[index]
        local categoryName, parentCategoryID = GetCategoryInfo(categoryID)
        categoryData[categoryID] = {
            id = categoryID,
            name = categoryName or ((ns.L and ns.L["UNKNOWN_CATEGORY"]) or "Unknown Category"),
            parentID = parentCategoryID,
            children = {},
            achievements = {},
            order = index,
        }
    end

    for ai = 1, #allCategoryIDs do
        local categoryID = allCategoryIDs[ai]
        local data = categoryData[categoryID]
        if data then
            if data.parentID and data.parentID > 0 then
                if categoryData[data.parentID] then
                    table.insert(categoryData[data.parentID].children, categoryID)
                end
            else
                table.insert(rootCategories, categoryID)
            end
        end
    end

    local allAchievements = (WarbandNexus.GetAllAchievementsData and WarbandNexus:GetAllAchievementsData()) or {}
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local totalCount = 0

    for i = 1, #allAchievements do
        local a = allAchievements[i]
        if not a or not a.id then
        elseif not ((showC and a.isCollected) or (showU and not a.isCollected)) then
        elseif query ~= "" and (not a.name or not SafeLower(a.name):find(query, 1, true)) then
        else
            local categoryID = a.categoryID
            if not categoryID and GetAchievementCategory then
                categoryID = GetAchievementCategory(a.id)
            end
            -- If category is not in our tree, walk up the parent chain until we find one that is
            if categoryID and not categoryData[categoryID] and GetCategoryInfo then
                local walked = categoryID
                for _ = 1, 10 do  -- max depth guard
                    local _, parentID = GetCategoryInfo(walked)
                    if not parentID or parentID <= 0 then break end
                    if categoryData[parentID] then
                        categoryID = parentID
                        break
                    end
                    walked = parentID
                end
            end
            if categoryID and categoryData[categoryID] then
                table.insert(categoryData[categoryID].achievements, a)
                totalCount = totalCount + 1
            end
        end
    end

    return categoryData, rootCategories, totalCount
end

-- Achievement flat list: ns.UI_AchievementBrowse_BuildFlatList (AchievementBrowseVirtualList.lua).
local SECTION_SPACING = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_SPACING) or (ns.UI_LAYOUT and ns.UI_LAYOUT.betweenSections) or 8

local function AnnotateFlatRowsByNearestHeader(flatList)
    local headerKey, headerTop = nil, nil
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            headerKey = it.key
            headerTop = (it.yOffset or 0) + (it.height or COLLAPSE_HEADER_HEIGHT_COLL)
        elseif it.type == "row" and headerKey then
            it._collSectionKey = headerKey
            it._collRelY = (it.yOffset or 0) - (headerTop or 0)
            it.groupKey = headerKey
            it.localY = it._collRelY
        end
    end
end

-- ============================================================================
-- Mount/Pet/Toy virtual list: scroll-layout index + visible-range binary search
-- ============================================================================
-- Scroll pixel Y for each row matches ChainSectionFrameBelow stacking: per section,
-- wrap height = COLLAPSE_HEADER_HEIGHT_COLL + (expanded and bodyContentHeight or 0.1).
-- Data rows use fixed ROW_HEIGHT within an expanded section; headers are not virtualized.
-- Binary search runs on parallel arrays built when the flat list is populated or section collapse changes.
local wipe = table.wipe

local function CollectionVirtual_FillRowScrollIndex(flatList, sectionContentH, collapsedHeaders, sectionSpacing, outFlatIdx, outTops, outHeights)
    wipe(outFlatIdx)
    wipe(outTops)
    wipe(outHeights)
    if not flatList then return end
    local y = 0
    local firstSec = true
    local bodyTopByKey = {}
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            if not firstSec then
                y = y + sectionSpacing
            end
            firstSec = false
            local key = it.key
            local secH = (sectionContentH and sectionContentH[key]) or 0
            if secH <= 0 and it.itemCount then
                secH = (it.itemCount * ROW_HEIGHT)
            end
            local expanded = collapsedHeaders and (collapsedHeaders[key] == false)
            local bodyH = expanded and math.max(0.1, secH) or 0.1
            bodyTopByKey[key] = y + COLLAPSE_HEADER_HEIGHT_COLL
            y = y + COLLAPSE_HEADER_HEIGHT_COLL + bodyH
        elseif it.type == "row" and it._collSectionKey then
            local key = it._collSectionKey
            local expanded = collapsedHeaders and (collapsedHeaders[key] == false)
            if expanded then
                local bt = bodyTopByKey[key]
                if bt then
                    outFlatIdx[#outFlatIdx + 1] = i
                    outTops[#outTops + 1] = bt + (it._collRelY or 0)
                    outHeights[#outHeights + 1] = it.height or ROW_HEIGHT
                end
            end
        end
    end
end

local function CollectionVirtual_FindFirstVisibleRow(rowTops, rowHeights, n, scrollTop)
    local lo, hi = 1, n
    while lo <= hi do
        local mid = math.floor((lo + hi) * 0.5)
        local rb = rowTops[mid] + rowHeights[mid]
        if rb <= scrollTop then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return lo
end

local function CollectionVirtual_FindLastVisibleRow(rowTops, rowHeights, n, bottom)
    local lo, hi = 1, n
    while lo <= hi do
        local mid = math.floor((lo + hi) * 0.5)
        if rowTops[mid] < bottom then
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return hi
end

local function CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
    local n = rowTops and #rowTops or 0
    if n == 0 then return 1, 0 end
    local firstK = CollectionVirtual_FindFirstVisibleRow(rowTops, rowHeights, n, scrollTop)
    local lastK = CollectionVirtual_FindLastVisibleRow(rowTops, rowHeights, n, bottom)
    if firstK > lastK then return 1, 0 end
    return firstK, lastK
end

local function CollectionVirtual_RefreshMountRowScrollIndex()
    local state = collectionsState
    CollectionVirtual_FillRowScrollIndex(
        state._mountFlatList,
        state._mountSectionContentH,
        state._mountListCollapsedHeaders or {},
        SECTION_SPACING,
        state._mountRowScrollFlatIdx or {},
        state._mountRowScrollTops or {},
        state._mountRowScrollHeights or {}
    )
end

local function CollectionVirtual_RefreshPetRowScrollIndex()
    local state = collectionsState
    CollectionVirtual_FillRowScrollIndex(
        state._petFlatList,
        state._petSectionContentH,
        state._petListCollapsedHeaders or {},
        SECTION_SPACING,
        state._petRowScrollFlatIdx or {},
        state._petRowScrollTops or {},
        state._petRowScrollHeights or {}
    )
end

local function CollectionVirtual_RefreshToyRowScrollIndex()
    local state = collectionsState
    CollectionVirtual_FillRowScrollIndex(
        state._toyFlatList,
        state._toySectionContentH,
        state._toyListCollapsedHeaders or {},
        SECTION_SPACING,
        state._toyRowScrollFlatIdx or {},
        state._toyRowScrollTops or {},
        state._toyRowScrollHeights or {}
    )
end

-- Forward declarations: scroll handlers schedule next-frame refresh via C_Timer.After(0).
local UpdateMountListVisibleRange
local UpdatePetListVisibleRange
local UpdateToyListVisibleRange

local mountListScrollVisibleCoalesce = false
local petListScrollVisibleCoalesce = false
local toyListScrollVisibleCoalesce = false

local function RequestMountListVisibleRangeAfterScroll()
    if mountListScrollVisibleCoalesce then return end
    mountListScrollVisibleCoalesce = true
    C_Timer.After(0, function()
        mountListScrollVisibleCoalesce = false
        UpdateMountListVisibleRange()
    end)
end

local function RequestPetListVisibleRangeAfterScroll()
    if petListScrollVisibleCoalesce then return end
    petListScrollVisibleCoalesce = true
    C_Timer.After(0, function()
        petListScrollVisibleCoalesce = false
        UpdatePetListVisibleRange()
    end)
end

local function RequestToyListVisibleRangeAfterScroll()
    if toyListScrollVisibleCoalesce then return end
    toyListScrollVisibleCoalesce = true
    C_Timer.After(0, function()
        toyListScrollVisibleCoalesce = false
        UpdateToyListVisibleRange()
    end)
end

-- Shared row pool for all three collection lists (Mounts, Pets, Achievements). Row structure from SharedWidgets.
local CollectionRowPool = {}
local COLLECTED_COLOR = "|cff33e533"
local DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
local DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"
local DEFAULT_ICON_TOY = "Interface\\Icons\\INV_Misc_Toy_07"
local DEFAULT_ICON_ACHIEVEMENT = "Interface\\Icons\\Achievement_General"

local function RemoveFirstMatchingPlan(pred)
    local WN = WarbandNexus
    if not WN or not WN.RemovePlan then return false end
    local plans = WN.db and WN.db.global and WN.db.global.plans
    if not plans then return false end
    for i = 1, #plans do
        local p = plans[i]
        if p and p.id and pred(p) then
            return WN:RemovePlan(p.id) and true or false
        end
    end
    return false
end

local function CollectionRowTodoSlotTooltip(onTodo, canInteract)
    local L = ns.L
    if onTodo then
        return (L and L["TODO_SLOT_TOOLTIP_REMOVE"]) or "Click to remove from your To-Do list."
    end
    if canInteract then
        return (L and L["TODO_SLOT_TOOLTIP_ADD"]) or "Click to add to your To-Do list."
    end
    return ""
end

local function CollectionRowTrackSlotTooltip(achCollected, onTrack)
    local L = ns.L
    if achCollected then
        return (L and L["TRACK_SLOT_DISABLED_COMPLETED"]) or "Completed achievements cannot be tracked in objectives."
    end
    if onTrack then
        return (L and L["TRACK_SLOT_TOOLTIP_UNTRACK"]) or "Click to stop tracking in Blizzard objectives."
    end
    return (L and L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)"
end

-- Acquire a collection list row (SharedWidgets layout: status icon + icon + label). Used by Mounts, Pets, Achievements.
local function AcquireCollectionRow(rowParent, item, leftIndent, iconPath, labelText, isCollected, selectedID, itemID, onSelect, refreshFn, planSlotState)
    if not rowParent then return nil end
    local rowH = (item and type(item.height) == "number" and item.height > 0) and item.height or ROW_HEIGHT
    local f = table.remove(CollectionRowPool)
    if not f then
        f = Factory:CreateCollectionListRow(rowParent, rowH)
        f:ClearAllPoints()
    end
    f:SetParent(rowParent)
    f:SetPoint("TOPLEFT", rowParent, "TOPLEFT", leftIndent or 0, -(item.yOffset or 0))
    f:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", 0, -(item.yOffset or 0))
    f:SetHeight(rowH)
    local onClick
    if onSelect or refreshFn then
        onClick = function()
            if onSelect then onSelect() end
            if refreshFn then refreshFn() end
        end
    end
    Factory:ApplyCollectionListRowContent(f, item.rowIndex, iconPath, labelText, isCollected, (selectedID == itemID), onClick, nil, nil, planSlotState)
    f:Show()
    return f
end

local function AcquireMountRow(scrollChild, listWidth, item, selectedMountID, onSelectMount, redraw, cf)
    local mount = item.mount
    local nameColor = mount.isCollected and COLLECTED_COLOR or "|cffffffff"
    local labelText = nameColor .. (mount.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("mount", mount.id)
    local rowParent = scrollChild
    if item._collSectionKey and collectionsState._mountSectionBodies and collectionsState._mountSectionBodies[item._collSectionKey] then
        rowParent = collectionsState._mountSectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = { mount = item.mount, rowIndex = item.rowIndex, yOffset = item._collRelY, height = item.height }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsMountPlanned and WN:IsMountPlanned(mount.id) or false
    local function refreshMountListVisible()
        if collectionsState._mountFlatList and collectionsState.mountListScrollFrame then
            collectionsState._mountListSelectedID = mount.id
            local r = collectionsState._mountListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = false,
        achievementRow = false,
        showTrackSlot = false,
        todoTooltip = CollectionRowTodoSlotTooltip(onTodo, onTodo or not mount.isCollected),
        onTodoClick = (onTodo or not mount.isCollected) and function()
            if not WN then return end
            if WN.IsMountPlanned and WN:IsMountPlanned(mount.id) then
                RemoveFirstMatchingPlan(function(p)
                    return p.type == "mount" and p.mountID == mount.id
                end)
            elseif not mount.isCollected and WN.AddPlan then
                WN:AddPlan({
                    type = "mount",
                    mountID = mount.id,
                    name = mount.name,
                    icon = mount.icon,
                    source = mount.source or "",
                })
            end
            refreshMountListVisible()
        end or nil,
    }
    return AcquireCollectionRow(rowParent, rowItem, 0, mount.icon or DEFAULT_ICON_MOUNT, labelText, mount.isCollected, selectedMountID, mount.id, function()
        if onSelectMount then
            onSelectMount(mount.id, mount.name, mount.icon, mount.source, mount.creatureDisplayID, mount.description, mount.isCollected)
        end
    end, refreshMountListVisible, planSlotState)
end

local function AcquirePetRow(scrollChild, listWidth, item, selectedPetID, onSelectPet, redraw, cf)
    local pet = item.pet
    local nameColor = pet.isCollected and COLLECTED_COLOR or "|cffffffff"
    local labelText = nameColor .. (pet.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("pet", pet.id)
    local rowParent = scrollChild
    if item._collSectionKey and collectionsState._petSectionBodies and collectionsState._petSectionBodies[item._collSectionKey] then
        rowParent = collectionsState._petSectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = { pet = item.pet, rowIndex = item.rowIndex, yOffset = item._collRelY, height = item.height }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsPetPlanned and WN:IsPetPlanned(pet.id) or false
    local function refreshPetListVisible()
        if collectionsState._petFlatList and collectionsState.petListScrollFrame then
            collectionsState._petListSelectedID = pet.id
            local r = collectionsState._petListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = false,
        achievementRow = false,
        showTrackSlot = false,
        todoTooltip = CollectionRowTodoSlotTooltip(onTodo, onTodo or not pet.isCollected),
        onTodoClick = (onTodo or not pet.isCollected) and function()
            if not WN then return end
            if WN.IsPetPlanned and WN:IsPetPlanned(pet.id) then
                RemoveFirstMatchingPlan(function(p)
                    return p.type == "pet" and p.speciesID == pet.id
                end)
            elseif not pet.isCollected and WN.AddPlan then
                WN:AddPlan({
                    type = "pet",
                    speciesID = pet.id,
                    name = pet.name,
                    icon = pet.icon,
                    source = pet.source or "",
                })
            end
            refreshPetListVisible()
        end or nil,
    }
    return AcquireCollectionRow(rowParent, rowItem, 0, pet.icon or DEFAULT_ICON_PET, labelText, pet.isCollected, selectedPetID, pet.id, function()
        if onSelectPet then
            onSelectPet(pet.id, pet.name, pet.icon, pet.source, pet.creatureDisplayID, pet.description, pet.isCollected)
        end
    end, refreshPetListVisible, planSlotState)
end

local function AcquireToyRow(scrollChild, listWidth, item, selectedToyID, onSelectToy, redraw, cf)
    local toy = item.toy
    local nameColor = (toy.isCollected or toy.collected) and COLLECTED_COLOR or "|cffffffff"
    local labelText = nameColor .. (toy.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("toy", toy.id)
    local rowParent = scrollChild
    if item._collSectionKey and collectionsState._toySectionBodies and collectionsState._toySectionBodies[item._collSectionKey] then
        rowParent = collectionsState._toySectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = { toy = item.toy, rowIndex = item.rowIndex, yOffset = item._collRelY, height = item.height }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsItemPlanned and WN:IsItemPlanned("toy", toy.id) or false
    local toyCollected = (toy.isCollected == true) or (toy.collected == true)
    local function refreshToyListVisible()
        if collectionsState._toyFlatList and collectionsState.toyListScrollFrame then
            collectionsState._toyListSelectedID = toy.id
            local r = collectionsState._toyListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = false,
        achievementRow = false,
        showTrackSlot = false,
        todoTooltip = CollectionRowTodoSlotTooltip(onTodo, onTodo or not toyCollected),
        onTodoClick = (onTodo or not toyCollected) and function()
            if not WN then return end
            if WN.IsItemPlanned and WN:IsItemPlanned("toy", toy.id) then
                RemoveFirstMatchingPlan(function(p)
                    return p.type == "toy" and p.itemID == toy.id
                end)
            elseif not toyCollected and WN.AddPlan then
                WN:AddPlan({
                    type = "toy",
                    itemID = toy.id,
                    name = toy.name,
                    icon = toy.icon,
                    source = toy.sourceTypeName or "",
                })
            end
            refreshToyListVisible()
        end or nil,
    }
    return AcquireCollectionRow(rowParent, rowItem, 0, toy.icon or DEFAULT_ICON_TOY, labelText, toyCollected, selectedToyID, toy.id, function()
        if onSelectToy then
            onSelectToy(toy.id, toy.name, toy.icon, toy.source, toy.description, toyCollected, toy.sourceTypeName)
        end
    end, refreshToyListVisible, planSlotState)
end

local function AcquireAchievementRow(scrollChild, listWidth, item, selectedAchievementID, onSelectAchievement, redraw, cf)
    local ach = item.achievement
    local nameColor = ach.isCollected and COLLECTED_COLOR or "|cffffffff"
    local pointsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
    local labelText = nameColor .. (ach.name or "") .. "|r" .. pointsStr
    local indent = item.indent or 0
    local rowParent = scrollChild
    if item._collSectionKey and collectionsState._achSectionBodies and collectionsState._achSectionBodies[item._collSectionKey] then
        rowParent = collectionsState._achSectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = {
            achievement = item.achievement,
            rowIndex = item.rowIndex,
            yOffset = item._collRelY,
            height = item.height,
            indent = item.indent,
        }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsAchievementPlanned and WN:IsAchievementPlanned(ach.id) or false
    local onTrack = WN and WN.IsAchievementTracked and WN:IsAchievementTracked(ach.id) or false
    local achCollected = ach.isCollected == true
    local function refreshAchListVisible()
        if collectionsState._achFlatList and collectionsState.achievementListScrollFrame then
            collectionsState._achListSelectedID = ach.id
            local r = collectionsState._achListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = onTrack,
        achievementRow = true,
        achievementCollected = achCollected,
        todoTooltip = CollectionRowTodoSlotTooltip(onTodo, onTodo or not achCollected),
        trackTooltip = CollectionRowTrackSlotTooltip(achCollected, onTrack),
        onTodoClick = (onTodo or not achCollected) and function()
            if not WN or not ach.id then return end
            local planned = WN.IsAchievementPlanned and WN:IsAchievementPlanned(ach.id)
            if planned then
                RemoveFirstMatchingPlan(function(p)
                    return p.type == "achievement" and p.achievementID == ach.id
                end)
            elseif not achCollected and WN.AddPlan then
                local rewardInfo = WN.GetAchievementRewardInfo and WN:GetAchievementRewardInfo(ach.id)
                local rewardText = rewardInfo and (rewardInfo.title or rewardInfo.itemName) or nil
                if not rewardText or rewardText == "" then
                    rewardText = ach.rewardText or ach.rewardTitle
                end
                WN:AddPlan({
                    type = "achievement",
                    achievementID = ach.id,
                    name = ach.name,
                    icon = ach.icon,
                    points = ach.points,
                    source = ach.source,
                    rewardText = rewardText,
                })
            end
            refreshAchListVisible()
        end or nil,
        onTrackClick = (not achCollected) and function()
            if WN and WN.ToggleAchievementTracking and ach.id then
                WN:ToggleAchievementTracking(ach.id)
            end
            refreshAchListVisible()
        end or nil,
    }
    return AcquireCollectionRow(rowParent, rowItem, indent, ach.icon or DEFAULT_ICON_ACHIEVEMENT, labelText, ach.isCollected, selectedAchievementID, ach.id, function()
        if onSelectAchievement then onSelectAchievement(ach) end
    end, refreshAchListVisible, planSlotState)
end

-- Update visible row frames only (virtual scroll). Headers are created in PopulateMountList.
UpdateMountListVisibleRange = function()
    local state = collectionsState
    local flatList = state._mountFlatList
    local scrollFrame = state.mountListScrollFrame
    local scrollChild = state.mountListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._mountVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
    end
    state._mountVisibleRowFrames = {}
    local redraw = state._mountListRedrawFn
    local cf = state._mountListContentFrame
    local selectedMountID = state._mountListSelectedID or state.selectedMountID
    local onSelectMount = state._mountListOnSelectMount
    local listWidth = state._mountListWidth or scrollChild:GetWidth()
    local tinsert = table.insert

    local rowFlatIdx = state._mountRowScrollFlatIdx
    local rowTops = state._mountRowScrollTops
    local rowHeights = state._mountRowScrollHeights
    if rowFlatIdx and rowTops and rowHeights then
        local firstK, lastK = CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
        for k = firstK, lastK do
            local i = rowFlatIdx[k]
            local it = flatList[i]
            if it and it.type == "row" then
                local body = state._mountSectionBodies and state._mountSectionBodies[it._collSectionKey]
                if body and body:IsShown() then
                    local frame = AcquireMountRow(scrollChild, listWidth, it, selectedMountID, onSelectMount, redraw, cf)
                    tinsert(state._mountVisibleRowFrames, { frame = frame, flatIndex = i })
                end
            end
        end
        return
    end

    local n = #flatList
    for i = 1, n do
        local it = flatList[i]
        if it.type == "row" then
            local rowTop = it.yOffset or 0
            local rowHeight = it.height or ROW_HEIGHT
            local rowBottom = rowTop + rowHeight
            if it._collSectionKey and collectionsState._mountSectionBodies then
                local body = collectionsState._mountSectionBodies[it._collSectionKey]
                if not body or not body:IsShown() then
                    rowTop, rowBottom = nil, nil
                else
                    local scTop = scrollChild:GetTop()
                    local bodyTop = body:GetTop()
                    if scTop and bodyTop then
                        local relY = it._collRelY or 0
                        rowTop = (scTop - bodyTop) + relY
                        rowBottom = rowTop + rowHeight
                    end
                end
            end
            if rowTop and rowBottom and rowBottom > scrollTop and rowTop < bottom then
                local frame = AcquireMountRow(scrollChild, listWidth, it, selectedMountID, onSelectMount, redraw, cf)
                tinsert(state._mountVisibleRowFrames, { frame = frame, flatIndex = i })
            end
        end
    end
end

-- Populate scrollChild: build flat list, create headers only, set height; visible rows updated by UpdateMountListVisibleRange (virtual scroll).
-- contentFrameForRefresh, redrawFn: redrawFn(contentFrame) is called on next frame for refresh; pass same DrawMountsContent from caller so closure sees it.
local function PopulateMountList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedMountID, onSelectMount, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populateMountListBusy then return end
    _populateMountListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    -- Release any visible row frames back to pool before clearing
    local visible = collectionsState._mountVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._mountVisibleRowFrames = {}
    end

    -- Clear existing children (headers from previous run); unparent to avoid accumulating on re-populate
    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatMountList(groupedData, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

    collectionsState._mountSectionBodies = {}
    local mountSectionContentH = {}
    for fi = 1, #flatList do
        local fit = flatList[fi]
        if fit.type == "header" then
            local sk = fit.key
            local sh = 0
            for fj = fi + 1, #flatList do
                local r = flatList[fj]
                if r.type == "header" then break end
                if r.type == "row" then sh = sh + (r.height or ROW_HEIGHT) end
            end
            mountSectionContentH[sk] = sh
        end
    end
    AnnotateFlatRowsByNearestHeader(flatList)

    local collHdrChainTail = nil
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local gap = collHdrChainTail and SECTION_SPACING or nil

            local sectionWrap = Factory:CreateContainer(scrollChild, listWidth, COLLAPSE_HEADER_HEIGHT_COLL + 0.1, false)
            sectionWrap:ClearAllPoints()
            if sectionWrap.SetClipsChildren then
                sectionWrap:SetClipsChildren(true)
            end
            ChainSectionFrameBelow(scrollChild, sectionWrap, collHdrChainTail, 0, gap, collHdrChainTail and nil or 0)

            local sectionBody
            local secH = mountSectionContentH[key] or 0
            if secH <= 0 then
                secH = ((it.itemCount or 0) * ROW_HEIGHT) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                -- Pre-populate visible rows before expand tween so first open is animated with content.
                if isExpanded then
                    CollectionVirtual_RefreshMountRowScrollIndex()
                    UpdateMountListVisibleRange()
                end
            end, SD.GetMountCategoryIcon(key), true, 0, nil, ns.UI_BuildCollapsibleSectionOpts({
                wrapFrame = sectionWrap,
                bodyGetter = function() return sectionBody end,
                headerHeight = COLLAPSE_HEADER_HEIGHT_COLL,
                hideOnCollapse = true,
                applyToggleBeforeCollapseAnimate = true,
                -- Expand: persist immediately. Collapse: defer until section height settles — otherwise virtual
                -- scroll drops hundreds of rows on first frame while height still tweens (looks instant / broken).
                persistFn = function(exp)
                    if exp then
                        collapsedHeaders[key] = false
                    end
                end,
                updateVisibleFn = function()
                    CollectionVirtual_RefreshMountRowScrollIndex()
                    UpdateMountListVisibleRange()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    CollectionVirtual_RefreshMountRowScrollIndex()
                    UpdateMountListVisibleRange()
                end,
            }))
            header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
            header:SetWidth(listWidth)
            header:SetHeight(it.height)

            sectionBody = Factory:CreateContainer(sectionWrap, listWidth, 0.1, false)
            sectionBody:ClearAllPoints()
            sectionBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            sectionBody:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            sectionBody._wnSectionFullH = secH
            if not it.isCollapsed then
                sectionBody:Show()
                sectionBody:SetHeight(math.max(0.1, secH))
            else
                sectionBody:Hide()
                sectionBody:SetHeight(0.1)
            end
            sectionWrap:SetHeight(COLLAPSE_HEADER_HEIGHT_COLL + sectionBody:GetHeight())
            collectionsState._mountSectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
        end
    end

    -- Store state for virtual scroll callback (refreshVisible: row tıklanınca sadece seçim vurgusunu günceller)
    collectionsState._mountFlatList = flatList
    collectionsState._mountFlatListTotalHeight = totalHeight
    collectionsState._mountSectionContentH = mountSectionContentH
    collectionsState._mountRowScrollFlatIdx = collectionsState._mountRowScrollFlatIdx or {}
    collectionsState._mountRowScrollTops = collectionsState._mountRowScrollTops or {}
    collectionsState._mountRowScrollHeights = collectionsState._mountRowScrollHeights or {}
    collectionsState._mountListWidth = listWidth
    collectionsState._mountListSelectedID = selectedMountID
    collectionsState._mountListOnSelectMount = onSelectMount
    collectionsState._mountListCollapsedHeaders = collapsedHeaders
    collectionsState._mountListRedrawFn = redraw
    collectionsState._mountListContentFrame = cf
    collectionsState._mountListRefreshVisible = UpdateMountListVisibleRange
    CollectionVirtual_RefreshMountRowScrollIndex()
    local scrollFrame = collectionsState.mountListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            RequestMountListVisibleRangeAfterScroll()
        end)
    end
    UpdateMountListVisibleRange()
    ScheduleCollectionsVisibleSync("mounts", UpdateMountListVisibleRange)
    _populateMountListBusy = false
end

local _populatePetListBusy = false

UpdatePetListVisibleRange = function()
    local state = collectionsState
    local flatList = state._petFlatList
    local scrollFrame = state.petListScrollFrame
    local scrollChild = state.petListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._petVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
    end
    state._petVisibleRowFrames = {}
    local redraw = state._petListRedrawFn
    local cf = state._petListContentFrame
    local selectedPetID = state._petListSelectedID or state.selectedPetID
    local onSelectPet = state._petListOnSelectPet
    local listWidth = state._petListWidth or scrollChild:GetWidth()
    local tinsert = table.insert

    local rowFlatIdx = state._petRowScrollFlatIdx
    local rowTops = state._petRowScrollTops
    local rowHeights = state._petRowScrollHeights
    if rowFlatIdx and rowTops and rowHeights then
        local firstK, lastK = CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
        for k = firstK, lastK do
            local i = rowFlatIdx[k]
            local it = flatList[i]
            if it and it.type == "row" then
                local body = state._petSectionBodies and state._petSectionBodies[it._collSectionKey]
                if body and body:IsShown() then
                    local frame = AcquirePetRow(scrollChild, listWidth, it, selectedPetID, onSelectPet, redraw, cf)
                    tinsert(state._petVisibleRowFrames, { frame = frame, flatIndex = i })
                end
            end
        end
        return
    end

    local n = #flatList
    for i = 1, n do
        local it = flatList[i]
        if it.type == "row" then
            local rowTop = it.yOffset or 0
            local rowHeight = it.height or ROW_HEIGHT
            local rowBottom = rowTop + rowHeight
            if it._collSectionKey and collectionsState._petSectionBodies then
                local body = collectionsState._petSectionBodies[it._collSectionKey]
                if not body or not body:IsShown() then
                    rowTop, rowBottom = nil, nil
                else
                    local scTop = scrollChild:GetTop()
                    local bodyTop = body:GetTop()
                    if scTop and bodyTop then
                        local relY = it._collRelY or 0
                        rowTop = (scTop - bodyTop) + relY
                        rowBottom = rowTop + rowHeight
                    end
                end
            end
            if rowTop and rowBottom and rowBottom > scrollTop and rowTop < bottom then
                local frame = AcquirePetRow(scrollChild, listWidth, it, selectedPetID, onSelectPet, redraw, cf)
                tinsert(state._petVisibleRowFrames, { frame = frame, flatIndex = i })
            end
        end
    end
end

local function PopulatePetList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedPetID, onSelectPet, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populatePetListBusy then return end
    _populatePetListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    local visible = collectionsState._petVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._petVisibleRowFrames = {}
    end

    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatPetList(groupedData, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

    collectionsState._petSectionBodies = {}
    local petSectionContentH = {}
    for fi = 1, #flatList do
        local fit = flatList[fi]
        if fit.type == "header" then
            local sk = fit.key
            local sh = 0
            for fj = fi + 1, #flatList do
                local r = flatList[fj]
                if r.type == "header" then break end
                if r.type == "row" then sh = sh + (r.height or ROW_HEIGHT) end
            end
            petSectionContentH[sk] = sh
        end
    end
    AnnotateFlatRowsByNearestHeader(flatList)

    local collHdrChainTail = nil
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local gap = collHdrChainTail and SECTION_SPACING or nil

            local sectionWrap = Factory:CreateContainer(scrollChild, listWidth, COLLAPSE_HEADER_HEIGHT_COLL + 0.1, false)
            sectionWrap:ClearAllPoints()
            if sectionWrap.SetClipsChildren then
                sectionWrap:SetClipsChildren(true)
            end
            ChainSectionFrameBelow(scrollChild, sectionWrap, collHdrChainTail, 0, gap, collHdrChainTail and nil or 0)

            local sectionBody
            local secH = petSectionContentH[key] or 0
            if secH <= 0 then
                secH = ((it.itemCount or 0) * ROW_HEIGHT) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                -- Pre-populate visible rows before expand tween so first open is animated with content.
                if isExpanded then
                    CollectionVirtual_RefreshPetRowScrollIndex()
                    UpdatePetListVisibleRange()
                end
            end, SD.GetPetCategoryIcon(key), true, 0, nil, ns.UI_BuildCollapsibleSectionOpts({
                wrapFrame = sectionWrap,
                bodyGetter = function() return sectionBody end,
                headerHeight = COLLAPSE_HEADER_HEIGHT_COLL,
                hideOnCollapse = true,
                applyToggleBeforeCollapseAnimate = true,
                persistFn = function(exp)
                    if exp then
                        collapsedHeaders[key] = false
                    end
                end,
                updateVisibleFn = function()
                    CollectionVirtual_RefreshPetRowScrollIndex()
                    UpdatePetListVisibleRange()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    CollectionVirtual_RefreshPetRowScrollIndex()
                    UpdatePetListVisibleRange()
                end,
            }))
            header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
            header:SetWidth(listWidth)
            header:SetHeight(it.height)

            sectionBody = Factory:CreateContainer(sectionWrap, listWidth, 0.1, false)
            sectionBody:ClearAllPoints()
            sectionBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            sectionBody:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            sectionBody._wnSectionFullH = secH
            if not it.isCollapsed then
                sectionBody:Show()
                sectionBody:SetHeight(math.max(0.1, secH))
            else
                sectionBody:Hide()
                sectionBody:SetHeight(0.1)
            end
            sectionWrap:SetHeight(COLLAPSE_HEADER_HEIGHT_COLL + sectionBody:GetHeight())
            collectionsState._petSectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
        end
    end

    collectionsState._petFlatList = flatList
    collectionsState._petFlatListTotalHeight = totalHeight
    collectionsState._petSectionContentH = petSectionContentH
    collectionsState._petRowScrollFlatIdx = collectionsState._petRowScrollFlatIdx or {}
    collectionsState._petRowScrollTops = collectionsState._petRowScrollTops or {}
    collectionsState._petRowScrollHeights = collectionsState._petRowScrollHeights or {}
    collectionsState._petListWidth = listWidth
    collectionsState._petListSelectedID = selectedPetID
    collectionsState._petListOnSelectPet = onSelectPet
    collectionsState._petListCollapsedHeaders = collapsedHeaders
    collectionsState._petListRedrawFn = redraw
    collectionsState._petListContentFrame = cf
    collectionsState._petListRefreshVisible = UpdatePetListVisibleRange
    CollectionVirtual_RefreshPetRowScrollIndex()
    local scrollFrame = collectionsState.petListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            RequestPetListVisibleRangeAfterScroll()
        end)
    end
    UpdatePetListVisibleRange()
    ScheduleCollectionsVisibleSync("pets", UpdatePetListVisibleRange)
    _populatePetListBusy = false
end

local _populateToyListBusy = false

UpdateToyListVisibleRange = function()
    local state = collectionsState
    local flatList = state._toyFlatList
    local scrollFrame = state.toyListScrollFrame
    local scrollChild = state.toyListScrollChild
    if not flatList or not scrollFrame or not scrollChild then return end
    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight
    local visible = state._toyVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
    end
    state._toyVisibleRowFrames = {}
    local redraw = state._toyListRedrawFn
    local cf = state._toyListContentFrame
    local selectedToyID = state._toyListSelectedID or state.selectedToyID
    local onSelectToy = state._toyListOnSelectToy
    local listWidth = state._toyListWidth or scrollChild:GetWidth()
    local tinsert = table.insert

    local rowFlatIdx = state._toyRowScrollFlatIdx
    local rowTops = state._toyRowScrollTops
    local rowHeights = state._toyRowScrollHeights
    if rowFlatIdx and rowTops and rowHeights then
        local firstK, lastK = CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
        for k = firstK, lastK do
            local i = rowFlatIdx[k]
            local it = flatList[i]
            if it and it.type == "row" then
                local body = state._toySectionBodies and state._toySectionBodies[it._collSectionKey]
                if body and body:IsShown() then
                    local frame = AcquireToyRow(scrollChild, listWidth, it, selectedToyID, onSelectToy, nil, cf)
                    tinsert(state._toyVisibleRowFrames, { frame = frame, flatIndex = i })
                end
            end
        end
        return
    end

    local n = #flatList
    for i = 1, n do
        local it = flatList[i]
        if it.type == "row" then
            local rowTop = it.yOffset or 0
            local rowHeight = it.height or ROW_HEIGHT
            local rowBottom = rowTop + rowHeight
            if it._collSectionKey and collectionsState._toySectionBodies then
                local body = collectionsState._toySectionBodies[it._collSectionKey]
                if not body or not body:IsShown() then
                    rowTop, rowBottom = nil, nil
                else
                    local scTop = scrollChild:GetTop()
                    local bodyTop = body:GetTop()
                    if scTop and bodyTop then
                        local relY = it._collRelY or 0
                        rowTop = (scTop - bodyTop) + relY
                        rowBottom = rowTop + rowHeight
                    end
                end
            end
            if rowTop and rowBottom and rowBottom > scrollTop and rowTop < bottom then
                local frame = AcquireToyRow(scrollChild, listWidth, it, selectedToyID, onSelectToy, nil, cf)
                tinsert(state._toyVisibleRowFrames, { frame = frame, flatIndex = i })
            end
        end
    end
end

local function PopulateToyList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedToyID, onSelectToy, contentFrameForRefresh, redrawFn)
    if not scrollChild or not Factory then return end
    if _populateToyListBusy then return end
    _populateToyListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = listWidth or 260
    scrollChild:SetWidth(listWidth)

    local visible = collectionsState._toyVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        collectionsState._toyVisibleRowFrames = {}
    end

    local children = { scrollChild:GetChildren() }
    for i = 1, #children do
        local c = children[i]
        c:Hide()
        c:ClearAllPoints()
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    local regions = { scrollChild:GetRegions() }
    for i = 1, #regions do
        regions[i]:Hide()
    end

    local flatList, totalHeight = BuildFlatToyList(groupedData, collapsedHeaders, SD.TOY_SOURCE_CATEGORIES)
    scrollChild:SetHeight(totalHeight)

    collectionsState._toySectionBodies = {}
    local toySectionContentH = {}
    for fi = 1, #flatList do
        local fit = flatList[fi]
        if fit.type == "header" then
            local sk = fit.key
            local sh = 0
            for fj = fi + 1, #flatList do
                local r = flatList[fj]
                if r.type == "header" then break end
                if r.type == "row" then sh = sh + (r.height or ROW_HEIGHT) end
            end
            toySectionContentH[sk] = sh
        end
    end
    AnnotateFlatRowsByNearestHeader(flatList)

    local collHdrChainTail = nil
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            local key = it.key
            local gap = collHdrChainTail and SECTION_SPACING or nil

            local sectionWrap = Factory:CreateContainer(scrollChild, listWidth, COLLAPSE_HEADER_HEIGHT_COLL + 0.1, false)
            sectionWrap:ClearAllPoints()
            if sectionWrap.SetClipsChildren then
                sectionWrap:SetClipsChildren(true)
            end
            ChainSectionFrameBelow(scrollChild, sectionWrap, collHdrChainTail, 0, gap, collHdrChainTail and nil or 0)

            local sectionBody
            local secH = toySectionContentH[key] or 0
            if secH <= 0 then
                secH = ((it.itemCount or 0) * ROW_HEIGHT) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                -- Pre-populate visible rows before expand tween so first open is animated with content.
                if isExpanded then
                    CollectionVirtual_RefreshToyRowScrollIndex()
                    UpdateToyListVisibleRange()
                end
            end, SD.GetToyCategoryIcon(key), true, 0, nil, ns.UI_BuildCollapsibleSectionOpts({
                wrapFrame = sectionWrap,
                bodyGetter = function() return sectionBody end,
                headerHeight = COLLAPSE_HEADER_HEIGHT_COLL,
                hideOnCollapse = true,
                applyToggleBeforeCollapseAnimate = true,
                persistFn = function(exp)
                    if exp then
                        collapsedHeaders[key] = false
                    end
                end,
                updateVisibleFn = function()
                    CollectionVirtual_RefreshToyRowScrollIndex()
                    UpdateToyListVisibleRange()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    CollectionVirtual_RefreshToyRowScrollIndex()
                    UpdateToyListVisibleRange()
                end,
            }))
            header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
            header:SetWidth(listWidth)
            header:SetHeight(it.height)

            sectionBody = Factory:CreateContainer(sectionWrap, listWidth, 0.1, false)
            sectionBody:ClearAllPoints()
            sectionBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            sectionBody:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            sectionBody._wnSectionFullH = secH
            if not it.isCollapsed then
                sectionBody:Show()
                sectionBody:SetHeight(math.max(0.1, secH))
            else
                sectionBody:Hide()
                sectionBody:SetHeight(0.1)
            end
            sectionWrap:SetHeight(COLLAPSE_HEADER_HEIGHT_COLL + sectionBody:GetHeight())
            collectionsState._toySectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
        end
    end

    collectionsState._toyFlatList = flatList
    collectionsState._toyFlatListTotalHeight = totalHeight
    collectionsState._toySectionContentH = toySectionContentH
    collectionsState._toyRowScrollFlatIdx = collectionsState._toyRowScrollFlatIdx or {}
    collectionsState._toyRowScrollTops = collectionsState._toyRowScrollTops or {}
    collectionsState._toyRowScrollHeights = collectionsState._toyRowScrollHeights or {}
    collectionsState._toyListWidth = listWidth
    collectionsState._toyListSelectedID = selectedToyID
    collectionsState._toyListOnSelectToy = onSelectToy
    collectionsState._toyListCollapsedHeaders = collapsedHeaders
    collectionsState._toyListRedrawFn = redraw
    collectionsState._toyListContentFrame = cf
    collectionsState._toyListRefreshVisible = UpdateToyListVisibleRange
    CollectionVirtual_RefreshToyRowScrollIndex()
    local scrollFrame = collectionsState.toyListScrollFrame
    if scrollFrame then
        scrollFrame:SetScript("OnVerticalScroll", function()
            RequestToyListVisibleRangeAfterScroll()
        end)
    end
    UpdateToyListVisibleRange()
    ScheduleCollectionsVisibleSync("toys", UpdateToyListVisibleRange)
    _populateToyListBusy = false
end

local function UpdateAchievementListVisibleRange()
    ns.UI_AchievementBrowse_UpdateVisibleRange({
        state = collectionsState,
        acquireRow = AcquireAchievementRow,
        releaseRowFrame = function(f)
            CollectionRowPool[#CollectionRowPool + 1] = f
        end,
    })
end

local function PopulateAchievementList(scrollChild, listWidth, categoryData, rootCategories, collapsedHeaders, selectedAchievementID, onSelectAchievement, contentFrameForRefresh, redrawFn)
    ns.UI_AchievementBrowse_Populate({
        state = collectionsState,
        scrollChild = scrollChild,
        listWidth = listWidth,
        categoryData = categoryData,
        rootCategories = rootCategories,
        collapsedHeaders = collapsedHeaders,
        selectedAchievementID = selectedAchievementID,
        onSelectAchievement = onSelectAchievement,
        contentFrameForRefresh = contentFrameForRefresh,
        redrawFn = redrawFn,
        acquireRow = AcquireAchievementRow,
        releaseRowFrame = function(f)
            CollectionRowPool[#CollectionRowPool + 1] = f
        end,
        scheduleVisibleSync = function(fn)
            ScheduleCollectionsVisibleSync("achievements", fn)
        end,
        rowHeightScale = ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE or 1.1,
    })
end

-- ============================================================================
-- MODEL VIEWER PANEL — Mounts: Blizzard Mount Journal pipeline (ModelScene WrappedAndUnwrappedModelScene + TransitionToModelSceneID).
-- Pets/fallback: Frame (clip) + PlayerModel + interaction layer. Layout: viewport below descText.
-- ============================================================================

local FIXED_CAM_SCALE = 1.8
local CAM_SCALE_MIN = 0.6
local CAM_SCALE_MAX = 6
local ZOOM_STEP = 0.1
local ROTATE_SENSITIVITY = 0.02
-- Tüm modeller aynı boyut/pozisyon: modeli REFERENCE_RADIUS'a scale ediyoruz, tek sabit kamera mesafesi.
-- Slightly below 1.0 so normalized mounts sit a bit smaller in frame (Mount Journal leaves headroom).
local REFERENCE_RADIUS = 0.86
-- Base camera distance after radius normalize; multiplied by MODEL_VIEWER_CAMERA_FIT_PADDING so wings/tails
-- that extend outside GetModelRadius() still fit (phoenix-type mounts were clipping the viewport).
local FIXED_CAM_DISTANCE = 3.55
-- Extra pull-back after normalize (Blizzard journal effectively uses scene-specific framing; we approximate).
-- Bumped from 1.30: tall mounts with banners/wings (e.g. Geargrinder Mk. 11) were drawing
-- past viewport bounds; Model widgets bypass SetClipsChildren, so the framing must do the
-- containment. Higher value = camera pulls back further = model occupies less of the box
-- but stays fully inside it.
local MODEL_VIEWER_CAMERA_FIT_PADDING = 1.60
-- Viewport üst boşluk (açıklama → model; Mount Journal’e yakın, sıkı)
local MODEL_VIEWPORT_TOP_GAP = 6
-- Pet: ince bant hâlâ hafif yukarı; mount tam yükseklik kullandığında bu px devre dışı kalabilir
local MOUNT_VIEWPORT_NUDGE_UP = 6
-- Viewport içinde 1–2 px: kenara yapışık görüntüyü yumuşatır (clip rect içinde).
local MODEL_VIEWPORT_INSET = 2
-- Pet/PlayerModel: geniş yuvarda yükseklik tavanı. Mount’ta bu tavan kaldırılır (aşağıda büyük boşluk + altta kırpma önlendi).
local MODEL_PREVIEW_MAX_HEIGHT_PER_WIDTH = 0.62
-- ModelScene: Mount Journal’e yakın çerçeve; çok büyük mult ayak/alt kesilmesine yol açabiliyordu.
local MOUNT_JOURNAL_SCENE_BASE_DISTANCE_MULT = 1.04
-- ModelScene: içeriği hafif yukarı (ekran; ayak hizası Blizzard journal’e yakın)
local MOUNT_JOURNAL_SCENE_VIEW_TRANSLATE_Y = 14
local MODEL_SCALE_MIN = 0.15
local MODEL_SCALE_MAX = 6.0
local ZOOM_MULTIPLIER_MIN = 0.5
local ZOOM_MULTIPLIER_MAX = 2.0
-- Pet models often sit low in the box vs mounts; small upward offset in model space after centering.
local PET_MODEL_VERTICAL_OFFSET = 0.12
-- PlayerModel mount yolu (ModelScene yok): dikey hizalama
local MOUNT_PLAYERMODEL_FALLBACK_Y_OFFSET = 0.16

-- Blizzard_Collections Mainline: MountJournal uses ModelScene:TransitionToModelSceneID + GetActorByTag("unwrapped"),
-- not PlayerModel alone (Blizzard_MountCollection.lua — MountJournal_UpdateMountDisplay).

local function Collections_LoadBlizzardCollections()
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_Collections")
    end
end

local function Collections_SanitizeMountExtra(v, default)
    if v == nil then return default end
    if issecretvalue and issecretvalue(v) then return default end
    return v
end

local function ApplyJournalModelSceneZoom(scene, zoomMultiplier)
    if not scene then return end
    local mul = MOUNT_JOURNAL_SCENE_BASE_DISTANCE_MULT * (zoomMultiplier or 1.0)
    if scene.SetCameraDistanceScale then
        pcall(scene.SetCameraDistanceScale, scene, mul)
    end
    if scene.SetCamDistanceScale then
        pcall(scene.SetCamDistanceScale, scene, mul)
    end
    -- Mount Journal: önizleme biraz yukarıda; aksi halde binek+binici frame altında kalıyor
    if scene.SetViewTranslation then
        pcall(scene.SetViewTranslation, scene, 0, MOUNT_JOURNAL_SCENE_VIEW_TRANSLATE_Y)
    end
end

--- Same pipeline as MountJournal_UpdateMountDisplay (ModelScene path). Returns true if scene was updated.
local function ApplyMountJournalModelSceneDisplay(scene, mountID, creatureDisplayIDFromCache, forceSceneChange)
    if not scene or not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoExtraByID then
        return false
    end
    local creatureDisplayID, _desc, _src, isSelfMount, _, modelSceneID, animID, spellVisualKitID, disablePlayerMountPreview =
        C_MountJournal.GetMountInfoExtraByID(mountID)
    creatureDisplayID = Collections_SanitizeMountExtra(creatureDisplayID, nil)
    isSelfMount = Collections_SanitizeMountExtra(isSelfMount, false) == true
    modelSceneID = Collections_SanitizeMountExtra(modelSceneID, nil)
    animID = Collections_SanitizeMountExtra(animID, nil)
    spellVisualKitID = Collections_SanitizeMountExtra(spellVisualKitID, nil)
    disablePlayerMountPreview = Collections_SanitizeMountExtra(disablePlayerMountPreview, true) == true

    if not creatureDisplayID or creatureDisplayID <= 0 then
        creatureDisplayID = creatureDisplayIDFromCache
    end
    if (not creatureDisplayID or creatureDisplayID <= 0) and C_MountJournal.GetMountAllCreatureDisplayInfoByID then
        local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
        if all and #all > 0 and all[1] and type(all[1].creatureDisplayID) == "number" then
            creatureDisplayID = all[1].creatureDisplayID
        end
    end
    if not creatureDisplayID or creatureDisplayID <= 0 then
        return false
    end

    local needsFanfare = false
    if C_MountJournal.NeedsFanfare then
        local nf = C_MountJournal.NeedsFanfare(mountID)
        if not (issecretvalue and nf and issecretvalue(nf)) then
            needsFanfare = nf == true
        end
    end

    local trans = _G.CAMERA_TRANSITION_TYPE_IMMEDIATE
    local disc = _G.CAMERA_MODIFICATION_TYPE_DISCARD
    if forceSceneChange and type(modelSceneID) == "number" and modelSceneID > 0 and trans and disc and scene.TransitionToModelSceneID then
        pcall(scene.TransitionToModelSceneID, scene, modelSceneID, trans, disc, true)
    end

    if scene.PrepareForFanfare then
        pcall(scene.PrepareForFanfare, scene, needsFanfare)
    end

    local mountActor = scene.GetActorByTag and scene:GetActorByTag("unwrapped")
    if not mountActor then
        return false
    end

    mountActor:Hide()
    if mountActor.SetOnModelLoadedCallback then
        mountActor:SetOnModelLoadedCallback(function()
            mountActor:Show()
        end)
    else
        mountActor:Show()
    end
    if mountActor.SetModelByCreatureDisplayID then
        local okSet = pcall(mountActor.SetModelByCreatureDisplayID, mountActor, creatureDisplayID, true)
        if not okSet then
            return false
        end
    else
        return false
    end

    local blend = Enum and Enum.ModelBlendOperation
    if isSelfMount and blend then
        if mountActor.SetAnimationBlendOperation then
            pcall(mountActor.SetAnimationBlendOperation, mountActor, blend.None)
        end
        if mountActor.SetAnimation then
            pcall(mountActor.SetAnimation, mountActor, 618)
        end
    else
        if mountActor.SetAnimationBlendOperation and blend then
            pcall(mountActor.SetAnimationBlendOperation, mountActor, blend.Anim)
        end
        if mountActor.SetAnimation then
            pcall(mountActor.SetAnimation, mountActor, 0)
        end
    end

    local showPlayer = false
    if GetCVarBool then
        local okCv, cv = pcall(GetCVarBool, "mountJournalShowPlayer")
        if okCv then showPlayer = cv end
    end
    local disablePreview = disablePlayerMountPreview
    if not disablePreview and not showPlayer then
        disablePreview = true
    end

    local useNativeForm = false
    if PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene then
        local okN, n = pcall(PlayerUtil.ShouldUseNativeFormInModelScene)
        if okN then useNativeForm = n end
    end

    if scene.AttachPlayerToMount then
        pcall(scene.AttachPlayerToMount, scene, mountActor, animID, isSelfMount, disablePreview, spellVisualKitID, useNativeForm)
    end

    scene:Show()
    return true
end

-- Fallback when Journal ModelScene is unavailable: PlayerModel + cinematic scene ID (approximate).
local function TryApplyMountJournalModelScene(pm, panel_)
    if not pm or not panel_ or not panel_._lastMountID then return false end
    local sid = panel_._mountUiModelSceneID
    if type(sid) ~= "number" or sid <= 0 then return false end
    if pm.ApplyUICinematicCamera then
        local ok = pcall(pm.ApplyUICinematicCamera, pm, sid)
        if ok then return true end
    end
    if pm.TransitionToModelSceneID then
        local ok = pcall(pm.TransitionToModelSceneID, pm, sid)
        if ok then return true end
    end
    return false
end

-- Largest sensible bounding radius for framing. GetModelRadius alone under-reports some flying mounts
-- (wings above the sphere); GetBoundingRadius (when present) often closer to visible extent — use max().
local function GetEffectiveModelBoundingRadius(m)
    if not m then return nil end
    local best = nil
    if m.GetModelRadius then
        local ok, r = pcall(m.GetModelRadius, m)
        if ok and type(r) == "number" and r > 0 then best = r end
    end
    if m.GetBoundingRadius then
        local ok, r = pcall(m.GetBoundingRadius, m)
        if ok and type(r) == "number" and r > 0 then
            best = best and math.max(best, r) or r
        end
    end
    return best
end

-- Mount API helpers — CreateModelViewer closure'ları bunlara ihtiyaç duyduğu için burada tanımlı.
local function SafeGetMountCollected(mountID)
    if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return false end
    local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    if issecretvalue and collected and issecretvalue(collected) then
        return false
    end
    return collected == true
end

local function SafeGetMountInfoExtra(mountID)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoExtraByID then
        return nil, "", "", nil
    end
    local displayID, description, source, _, _, uiModelSceneID = C_MountJournal.GetMountInfoExtraByID(mountID)
    if issecretvalue and displayID and issecretvalue(displayID) then displayID = nil end
    if issecretvalue and description and issecretvalue(description) then description = "" end
    if issecretvalue and source and issecretvalue(source) then source = "" end
    if issecretvalue and uiModelSceneID and issecretvalue(uiModelSceneID) then uiModelSceneID = nil end
    return displayID, description or "", source or "", uiModelSceneID
end

-- Pet API helpers — same pattern as mounts.
local function SafeGetPetCollected(speciesID)
    if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return false end
    local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
    if issecretvalue and numCollected and issecretvalue(numCollected) then
        return false
    end
    return numCollected and numCollected > 0
end

local function SafeGetPetInfoExtra(speciesID)
    if not speciesID or not C_PetJournal then return nil, "", "" end
    local creatureDisplayID = nil
    if C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
        local numDisplays = C_PetJournal.GetNumDisplays(speciesID) or 0
        if numDisplays > 0 then
            creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(speciesID, 1)
        end
    end
    if issecretvalue and creatureDisplayID and issecretvalue(creatureDisplayID) then creatureDisplayID = nil end
    local name, icon, _, _, source, description = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if issecretvalue and source and issecretvalue(source) then source = "" end
    if issecretvalue and description and issecretvalue(description) then description = "" end
    return creatureDisplayID, description or "", source or ""
end

local function CreateModelViewer(parent, width, height)
    local panel = Factory:CreateContainer(parent, width, height, false)
    if not panel then return nil end
    panel:SetSize(width, height)
    ApplyDetailAccentVisuals(panel)

    -- Slot: full width from desc bottom to panel bottom; viewport inside is height-capped and vertically centered.
    local modelViewportSlot = Factory:CreateContainer(panel, math.max(1, width), math.max(1, height), false)
    if not modelViewportSlot then
        modelViewportSlot = CreateFrame("Frame", nil, panel)
    end
    modelViewportSlot:SetFrameLevel(panel:GetFrameLevel() + 1)
    panel.modelViewportSlot = modelViewportSlot

    -- Model stage: plain Frame with SetClipsChildren (ScriptRegion child tree); PlayerModel draws past bounds — clip here.
    local modelViewport = Factory:CreateContainer(modelViewportSlot, math.max(1, width), math.max(1, height), false)
    if not modelViewport then
        modelViewport = CreateFrame("Frame", nil, modelViewportSlot)
    end
    modelViewport:SetFrameLevel(modelViewportSlot:GetFrameLevel() + 1)
    if modelViewport.SetClipsChildren then
        modelViewport:SetClipsChildren(true)
    end
    panel.modelViewport = modelViewport

    -- Widget type Model / PlayerModel — see Widget API; mouse off on model, hits on interactionLayer (ScriptRegion).
    local model = CreateFrame("PlayerModel", nil, modelViewport)
    model:SetModelDrawLayer("ARTWORK")
    model:SetFrameLevel(modelViewport:GetFrameLevel())
    model:EnableMouse(false)
    model:EnableMouseWheel(false)

    local function ApplyModelToViewportInsets()
        local inset = MODEL_VIEWPORT_INSET
        model:ClearAllPoints()
        model:SetPoint("TOPLEFT", modelViewport, "TOPLEFT", inset, -inset)
        model:SetPoint("BOTTOMRIGHT", modelViewport, "BOTTOMRIGHT", -inset, inset)
        local js = panel._journalMountScene
        if js then
            js:ClearAllPoints()
            js:SetPoint("TOPLEFT", modelViewport, "TOPLEFT", inset, -inset)
            js:SetPoint("BOTTOMRIGHT", modelViewport, "BOTTOMRIGHT", -inset, inset)
        end
    end

    -- Journal-quality mount preview: same ModelScene template as Mount Journal (Blizzard_Collections).
    local function TryInitJournalMountModelScene()
        if panel._journalMountScene then return panel._journalMountScene end
        if panel._journalMountSceneFailed then return nil end
        Collections_LoadBlizzardCollections()
        local ok, scene = pcall(CreateFrame, "ModelScene", nil, modelViewport, "WrappedAndUnwrappedModelScene")
        if not ok or not scene then
            panel._journalMountSceneFailed = true
            return nil
        end
        panel._journalMountScene = scene
        scene:SetFrameLevel(model:GetFrameLevel() + 2)
        if scene.SetResetCallback then
            scene:SetResetCallback(function()
                if panel._lastMountID and panel._mountDisplayUsesJournalScene and panel._journalMountScene then
                    ApplyMountJournalModelSceneDisplay(panel._journalMountScene, panel._lastMountID, panel._lastCreatureDisplayID, true)
                    ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
                end
            end)
        end
        if scene.ControlFrame and scene.ControlFrame.SetModelScene then
            pcall(scene.ControlFrame.SetModelScene, scene.ControlFrame, scene)
        end
        scene:Hide()
        ApplyModelToViewportInsets()
        return scene
    end

    -- Defined before interactionLayer exists; use panel._interactionLayer at call time (not local interactionLayer — scope).
    local function ShowPlayerModelPath(show)
        local il = panel._interactionLayer
        if show then
            model:Show()
            if il then il:Show() end
        else
            model:Hide()
            if il then il:Hide() end
        end
    end

    -- Layout: slot from descText bottom (or fallback) to panel bottom; viewport height capped vs width and centered in slot.
    local MODEL_FALLBACK_TOP_RATIO = 0.36
    local function UpdateModelFrameSize()
        local w = panel:GetWidth()
        local h = panel:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        local slot = panel.modelViewportSlot
        if not slot then return end
        slot:ClearAllPoints()
        if panel.descText and panel.descText:IsShown() then
            slot:SetPoint("TOPLEFT", panel.descText, "BOTTOMLEFT", 0, -MODEL_VIEWPORT_TOP_GAP)
            slot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
        else
            slot:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_INSET, -h * MODEL_FALLBACK_TOP_RATIO)
            slot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
        end
        local sw = slot:GetWidth()
        local sh = slot:GetHeight()
        if not sw or sw < 1 then sw = math.max(1, w - 2 * CONTENT_INSET) end
        if not sh or sh < 2 then sh = math.max(2, h * (1 - MODEL_FALLBACK_TOP_RATIO)) end
        -- Mount: tüm slot yüksekliğini model için kullan (Blizzard Mount Journal; 0.62 tavan büyük üst/alt siyah bant yaratıyordu).
        local isMountView = panel._lastMountID and (not panel._lastPetID)
        local maxH = sw * MODEL_PREVIEW_MAX_HEIGHT_PER_WIDTH
        local vh = isMountView and sh or math.min(sh, maxH)
        local totalVPad = math.max(0, sh - vh)
        local vCenter = totalVPad * 0.5
        local nudgeUp = isMountView and MOUNT_VIEWPORT_NUDGE_UP or 0
        nudgeUp = math.min(nudgeUp, vCenter)
        local vPadTop = math.max(0, vCenter - nudgeUp)
        local vPadBottom = totalVPad - vPadTop
        modelViewport:ClearAllPoints()
        modelViewport:SetPoint("LEFT", slot, "LEFT", 0, 0)
        modelViewport:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
        modelViewport:SetPoint("TOP", slot, "TOP", 0, -vPadTop)
        modelViewport:SetPoint("BOTTOM", slot, "BOTTOM", 0, vPadBottom)
        ApplyModelToViewportInsets()
    end
    panel.UpdateModelFrameSize = UpdateModelFrameSize
    panel:SetScript("OnSizeChanged", function()
        UpdateModelFrameSize()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UpdateModelFrameSize() end)
        end
    end)

    panel.modelRotation = 0
    panel.camScale = FIXED_CAM_SCALE
    panel.normalizedRadius = false
    panel.modelScale = 1.0
    panel.zoomMultiplier = 1.0
    panel._dragButton = nil

    -- Transparent layer above PlayerModel: reliable hit-testing for wheel + drag (journal-style: right-drag rotate; left-drag also supported).
    local interactionLayer = Factory:CreateContainer(modelViewport, math.max(1, width), math.max(1, height), false)
    if not interactionLayer then
        interactionLayer = CreateFrame("Frame", nil, modelViewport)
    end
    interactionLayer:SetAllPoints()
    interactionLayer:SetFrameLevel(model:GetFrameLevel() + 20)
    interactionLayer:EnableMouse(true)
    interactionLayer:EnableMouseWheel(true)
    panel._interactionLayer = interactionLayer

    -- Centered preview: UseModelCenterToTransform + optional pet vertical nudge; idle pose + zero pitch for consistency.
    local function ApplyTransform()
        if panel._mountDisplayUsesJournalScene and panel._journalMountScene then
            ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
            return
        end
        if panel._usesJournalCamera and panel._lastMountID then
            model:SetPosition(0, 0, 0)
            if model.UseModelCenterToTransform then model:UseModelCenterToTransform(true) end
            if model.SetPitch then pcall(model.SetPitch, model, 0) end
            model:SetFacing(panel.modelRotation)
            if model.SetPortraitZoom then model:SetPortraitZoom(0) end
            if model.SetCamDistanceScale then
                model:SetCamDistanceScale(FIXED_CAM_SCALE * panel.zoomMultiplier)
            end
            if model.SetViewTranslation then model:SetViewTranslation(0, 0) end
            return
        end
        local yOff = 0
        if panel._lastPetID and not panel._lastMountID then
            yOff = PET_MODEL_VERTICAL_OFFSET
        elseif panel._lastMountID and (not panel._lastPetID) and (not panel._mountDisplayUsesJournalScene) then
            yOff = MOUNT_PLAYERMODEL_FALLBACK_Y_OFFSET
        end
        model:SetPosition(0, yOff, 0)
        if model.UseModelCenterToTransform then model:UseModelCenterToTransform(true) end
        if model.SetPitch then pcall(model.SetPitch, model, 0) end
        model:SetFacing(panel.modelRotation)
        if model.SetPortraitZoom then model:SetPortraitZoom(0) end
        if panel.normalizedRadius then
            if model.SetModelScale then model:SetModelScale(panel.modelScale) end
            if model.SetCameraDistance then
                local vw, vh = modelViewport:GetWidth(), modelViewport:GetHeight()
                local aspectPad = 1.0
                if vw and vh and vw > 1 and vh > 1 then
                    local ratio = vw / vh
                    if ratio > 1.12 then
                        -- Wide preview: tall mounts (banners, wings) clip vertically — pull camera back
                        -- proportionally to the aspect ratio so they fit.
                        aspectPad = math.min(1.45, 1.0 + (ratio - 1.0) * 0.35)
                    elseif ratio < 0.85 then
                        -- Tall preview: wide mounts clip horizontally — same logic, mirrored.
                        aspectPad = math.min(1.45, 1.0 + (1.0 / ratio - 1.0) * 0.35)
                    end
                end
                local camDist = FIXED_CAM_DISTANCE
                    * MODEL_VIEWER_CAMERA_FIT_PADDING
                    * aspectPad
                    * panel.zoomMultiplier
                    * panel.modelScale
                local ok = pcall(model.SetCameraDistance, model, math.max(0.1, camDist))
                if not ok and model.SetCamDistanceScale then
                    model:SetCamDistanceScale(panel.camScale)
                end
            end
        else
            if model.SetCamDistanceScale then model:SetCamDistanceScale(panel.camScale) end
        end
        if model.SetViewTranslation then model:SetViewTranslation(0, 0) end
    end

    local function ScheduleJournalSceneAfterMount(midLock)
        if not midLock then return end
        local function tryOnce()
            if panel._lastMountID ~= midLock then return end
            if TryApplyMountJournalModelScene(model, panel) then
                panel._usesJournalCamera = true
                panel.zoomMultiplier = 1.0
                ApplyTransform()
            end
        end
        C_Timer.After(0, tryOnce)
        C_Timer.After(0.1, tryOnce)
    end

    -- Model script OnModelLoaded (Widget script handlers): radius APIs often valid here; complements deferred retries.
    local function TryApplyBoundingRadiusNormalize(lockMountID, lockCreatureID)
        if panel._usesJournalCamera then return false end
        if lockMountID and panel._lastMountID ~= lockMountID then return false end
        if lockCreatureID and lockCreatureID > 0 and panel._lastCreatureDisplayID ~= lockCreatureID then return false end
        local r = GetEffectiveModelBoundingRadius(model)
        if not r or r <= 0 or not model.SetModelScale or not model.SetCameraDistance then return false end
        local scale = (REFERENCE_RADIUS / r) * 0.94
        if scale < MODEL_SCALE_MIN then scale = MODEL_SCALE_MIN elseif scale > MODEL_SCALE_MAX then scale = MODEL_SCALE_MAX end
        panel.normalizedRadius = true
        panel.modelScale = scale
        ApplyTransform()
        return true
    end

    local FRAMING_RETRY_DELAYS = { 0, 0.06, 0.14, 0.30, 0.60 }
    local function ScheduleBoundingRadiusRetries(lockMountID, lockCreatureID)
        for i = 1, #FRAMING_RETRY_DELAYS do
            local delay = FRAMING_RETRY_DELAYS[i]
            C_Timer.After(delay, function()
                TryApplyBoundingRadiusNormalize(lockMountID, lockCreatureID)
            end)
        end
    end

    model:SetScript("OnModelLoaded", function()
        TryApplyBoundingRadiusNormalize(panel._lastMountID, panel._lastCreatureDisplayID)
        ApplyTransform()
    end)

    local function InteractionEffectiveScale()
        local s = interactionLayer:GetEffectiveScale()
        if s and s > 0 then return s end
        return model:GetEffectiveScale() or 1
    end

    local function interactionDragOnUpdate()
        if panel._dragCursorX == nil or not panel._dragButton then
            interactionLayer:SetScript("OnUpdate", nil)
            return
        end
        if not IsMouseButtonDown(panel._dragButton) then
            panel._dragCursorX = nil
            panel._dragButton = nil
            interactionLayer:SetScript("OnUpdate", nil)
            return
        end
        local x = GetCursorPosition()
        local s = InteractionEffectiveScale()
        if s > 0 then x = x / s end
        local dx = x - panel._dragCursorX
        panel._dragCursorX = x
        panel.modelRotation = (panel._dragRotation or 0) - dx * ROTATE_SENSITIVITY
        panel._dragRotation = panel.modelRotation
        model:SetFacing(panel.modelRotation)
        ApplyTransform()
    end

    interactionLayer:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        local x = GetCursorPosition()
        local s = InteractionEffectiveScale()
        if s > 0 then x = x / s end
        panel._dragCursorX = x
        panel._dragRotation = panel.modelRotation
        panel._dragButton = button
        interactionLayer:SetScript("OnUpdate", interactionDragOnUpdate)
    end)
    interactionLayer:SetScript("OnMouseUp", function(_, button)
        if button == panel._dragButton then
            panel._dragCursorX = nil
            panel._dragButton = nil
        end
        interactionLayer:SetScript("OnUpdate", nil)
    end)
    interactionLayer:SetScript("OnHide", function()
        panel._dragCursorX = nil
        panel._dragButton = nil
        interactionLayer:SetScript("OnUpdate", nil)
    end)
    interactionLayer:SetScript("OnMouseWheel", function(_, delta)
        if panel._mountDisplayUsesJournalScene and panel._journalMountScene then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
            ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
            return
        end
        if panel._usesJournalCamera then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
            ApplyTransform()
            return
        end
        if panel.normalizedRadius then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
        else
            local v = panel.camScale + (delta > 0 and -ZOOM_STEP or ZOOM_STEP)
            if v < CAM_SCALE_MIN then v = CAM_SCALE_MIN elseif v > CAM_SCALE_MAX then v = CAM_SCALE_MAX end
            panel.camScale = v
        end
        ApplyTransform()
    end)

    -- Text on top of model: overlay frame with higher frame level so text is always in front.
    local textOverlay = Factory:CreateContainer(panel, math.max(1, width), math.max(1, height), false)
    if not textOverlay then
        textOverlay = CreateFrame("Frame", nil, panel)
    end
    textOverlay:SetFrameLevel(panel:GetFrameLevel() + 10)
    textOverlay:SetAllPoints(panel)
    textOverlay:EnableMouse(false)
    panel.textOverlay = textOverlay

    local DETAIL_HEADER_GAP = 10
    local collectionsDetailIcon = math.floor((DETAIL_ICON_SIZE or 64) * 1.14)
    -- Detail icon with border (Factory CreateContainer + accent override)
    local iconBorder = Factory:CreateContainer(textOverlay, collectionsDetailIcon, collectionsDetailIcon, true)
    iconBorder:SetPoint("TOPLEFT", textOverlay, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    if ApplyVisuals then
        ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
    end
    if iconBorder.EnableMouse then iconBorder:EnableMouse(false) end
    panel.detailIconBorder = iconBorder
    local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.detailIconTexture = iconTex

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0
    local whiteR, whiteG, whiteB = 1, 1, 1

    -- Sağ üst: Factory sütunu — Wowhead + Add/Added; try satırı yalnızca Add sütunu genişliğinde (hizalı).
    local addCol = Factory.CreateCollectionsDetailRightColumn and Factory:CreateCollectionsDetailRightColumn(textOverlay, { withTryRow = true })
    local addContainer = addCol and addCol.root
    local actionSlot = addCol and addCol.actionSlot
    if addContainer then
        addContainer:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        addContainer:Hide()
    end
    panel._addContainer = addContainer
    panel._detailActionSlot = actionSlot

    if PlanCardFactory and actionSlot then
        panel._addBtn = PlanCardFactory.CreateAddButton(actionSlot, {
            buttonType = "row",
            anchorPoint = "TOPRIGHT",
            x = 0,
            y = 0,
        })
        if panel._addBtn then
            panel._addBtn:ClearAllPoints()
            panel._addBtn:SetPoint("TOPRIGHT", actionSlot, "TOPRIGHT", 0, 0)
        end
        panel._addedIndicator = PlanCardFactory.CreateAddedIndicator(actionSlot, {
            buttonType = "row",
            label = (ns.L and ns.L["ADDED"]) or "Added",
            fontCategory = "body",
            anchorPoint = "TOPRIGHT",
            x = 0,
            y = 0,
        })
        if panel._addedIndicator then
            panel._addedIndicator:ClearAllPoints()
            panel._addedIndicator:SetPoint("TOPRIGHT", actionSlot, "TOPRIGHT", 0, 0)
            panel._addedIndicator:Hide()
        end
    end

    panel._wowheadBtn = addCol and addCol.wowheadBtn
    panel._tryCountRow = addCol and addCol.tryCountRow

    local nameText = FontManager:CreateFontString(textOverlay, "header", "OVERLAY")
    do
        local fp, fsz, flg = nameText:GetFont()
        if type(fsz) == "number" and fp and flg then
            pcall(nameText.SetFont, nameText, fp, fsz + 2, flg)
        end
    end
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
    if addContainer then
        nameText:SetPoint("TOPRIGHT", addContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
    else
        nameText:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    end
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    nameText:SetTextColor(whiteR, whiteG, whiteB)
    panel.nameText = nameText

    local headerRowBottom = Factory:CreateContainer(textOverlay, math.max(1, width), 1, false)
    if not headerRowBottom then
        headerRowBottom = CreateFrame("Frame", nil, textOverlay)
        headerRowBottom:SetHeight(1)
    end
    headerRowBottom:SetPoint("TOPLEFT", iconBorder, "BOTTOMLEFT", 0, 0)
    headerRowBottom:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, 0)
    if headerRowBottom.EnableMouse then headerRowBottom:EnableMouse(false) end
    panel.headerRowBottom = headerRowBottom

    local sourceContainer = Factory:CreateContainer(textOverlay, math.max(1, width), 2, false)
    if not sourceContainer then
        sourceContainer = CreateFrame("Frame", nil, textOverlay)
        sourceContainer:SetHeight(1)
    end
    sourceContainer:SetPoint("TOPLEFT", headerRowBottom, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceContainer:SetPoint("TOPRIGHT", headerRowBottom, "BOTTOMRIGHT", 0, -TEXT_GAP)
    if sourceContainer.EnableMouse then sourceContainer:EnableMouse(false) end
    panel.sourceContainer = sourceContainer

    panel.sourceLines = {}

    -- Source label: gold color (consistent with Toy and all collection detail panels)
    local sourceLabel = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    sourceLabel:SetPoint("TOPLEFT", headerRowBottom, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceLabel:SetPoint("TOPRIGHT", headerRowBottom, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceLabel:SetJustifyH("LEFT")
    sourceLabel:SetWordWrap(true)
    sourceLabel:SetNonSpaceWrap(false)
    sourceLabel:SetTextColor(goldR, goldG, goldB)
    panel.sourceLabel = sourceLabel

    local descText = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
    descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetTextColor(whiteR, whiteG, whiteB)
    panel.descText = descText

    local obtainedAtLine = FontManager:CreateFontString(textOverlay, "small", "OVERLAY")
    obtainedAtLine:SetJustifyH("LEFT")
    obtainedAtLine:SetWordWrap(true)
    obtainedAtLine:SetTextColor(0.68, 0.70, 0.74, 1)
    obtainedAtLine:Hide()
    panel.obtainedAtLine = obtainedAtLine

    local collectedBadge = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    collectedBadge:SetPoint("BOTTOMLEFT", textOverlay, "BOTTOMLEFT", CONTENT_INSET, CONTENT_INSET)
    collectedBadge:SetPoint("RIGHT", textOverlay, "RIGHT", -CONTENT_INSET, 0)
    collectedBadge:SetJustifyH("LEFT")
    collectedBadge:Hide()
    panel.collectedBadge = collectedBadge

    -- descText exists: anchor model viewport below it (first layout; was previously deferred until SetMountInfo).
    UpdateModelFrameSize()

    panel.model = model

    panel:SetScript("OnShow", function()
        if panel._mountDisplayUsesJournalScene and panel._lastMountID and panel._journalMountScene then
            ApplyMountJournalModelSceneDisplay(panel._journalMountScene, panel._lastMountID, panel._lastCreatureDisplayID, true)
            ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
            return
        end
        local mid = panel._lastMountID
        if panel._useSetMountForRestore and mid and type(model.SetMount) == "function" then
            model:ClearModel()
            local ok = pcall(model.SetMount, model, mid)
            if ok then
                ApplyTransform()
                ScheduleJournalSceneAfterMount(mid)
                return
            end
        end
        local cid = panel._lastCreatureDisplayID
        if cid and cid > 0 and model.SetDisplayInfo then
            model:ClearModel()
            model:SetDisplayInfo(cid)
            ApplyTransform()
        end
    end)

    local function scheduleModelViewerLayout()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UpdateModelFrameSize() end)
        else
            UpdateModelFrameSize()
        end
    end

    function panel:SetMount(mountID, creatureDisplayIDFromCache)
        if not mountID then
            if panel._journalMountScene then
                panel._journalMountScene:Hide()
            end
            panel._mountDisplayUsesJournalScene = false
            ShowPlayerModelPath(true)
            model:ClearModel()
            panel._lastMountID = nil
            panel._lastCreatureDisplayID = nil
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            scheduleModelViewerLayout()
            return
        end
        local extraDisplayID, _, _, uiScene = SafeGetMountInfoExtra(mountID)
        panel._mountUiModelSceneID = uiScene
        panel._usesJournalCamera = false

        local creatureDisplayID = creatureDisplayIDFromCache
        if not creatureDisplayID or creatureDisplayID <= 0 then
            creatureDisplayID = extraDisplayID
        end

        local journalScene = TryInitJournalMountModelScene()
        if journalScene then
            panel._lastPetID = nil
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = (creatureDisplayID and creatureDisplayID > 0) and creatureDisplayID or nil
            panel._useSetMountForRestore = false
            local okJournal = ApplyMountJournalModelSceneDisplay(journalScene, mountID, creatureDisplayIDFromCache, true)
            if okJournal then
                panel._mountDisplayUsesJournalScene = true
                panel.zoomMultiplier = 1.0
                ApplyJournalModelSceneZoom(journalScene, panel.zoomMultiplier)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if panel._lastMountID ~= mountID or not panel._mountDisplayUsesJournalScene or not panel._journalMountScene then return end
                        ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
                    end)
                end
                model:ClearModel()
                ShowPlayerModelPath(false)
                panel.normalizedRadius = false
                scheduleModelViewerLayout()
                return
            end
        end

        panel._mountDisplayUsesJournalScene = false
        if panel._journalMountScene then
            panel._journalMountScene:Hide()
        end
        ShowPlayerModelPath(true)

        local usedSetMount = false
        if type(model.SetMount) == "function" then
            model:ClearModel()
            usedSetMount = pcall(model.SetMount, model, mountID) == true
        end
        if usedSetMount then
            panel._useSetMountForRestore = true
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = (creatureDisplayID and creatureDisplayID > 0) and creatureDisplayID or nil
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            panel.normalizedRadius = true
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            if model.SetAnimation then pcall(model.SetAnimation, model, 0) end
            ScheduleJournalSceneAfterMount(mountID)
            ScheduleBoundingRadiusRetries(mountID, 0)
            scheduleModelViewerLayout()
            return
        end
        if creatureDisplayID and creatureDisplayID > 0 then
            panel._useSetMountForRestore = false
            model:ClearModel()
            model:SetDisplayInfo(creatureDisplayID)
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = creatureDisplayID
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            -- İlk frame zoom-in olmasın: başta normalizedRadius=true, modelScale=1 ile sabit kamera kullan; radius gelince güncelle.
            panel.normalizedRadius = true
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            if model.SetAnimation then pcall(model.SetAnimation, model, 0) end
            ScheduleJournalSceneAfterMount(mountID)
            ScheduleBoundingRadiusRetries(mountID, creatureDisplayID)
        else
            model:ClearModel()
            panel._lastMountID = nil
            panel._lastCreatureDisplayID = nil
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            panel.normalizedRadius = false
        end
        scheduleModelViewerLayout()
    end

    function panel:SetPet(speciesID, creatureDisplayIDFromCache)
        if not speciesID then
            if panel._journalMountScene then
                panel._journalMountScene:Hide()
            end
            panel._mountDisplayUsesJournalScene = false
            ShowPlayerModelPath(true)
            model:ClearModel()
            panel._lastPetID = nil
            panel._lastCreatureDisplayID = nil
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            scheduleModelViewerLayout()
            return
        end
        if panel._journalMountScene then
            panel._journalMountScene:Hide()
        end
        panel._mountDisplayUsesJournalScene = false
        ShowPlayerModelPath(true)
        local creatureDisplayID = creatureDisplayIDFromCache
        if not creatureDisplayID or creatureDisplayID <= 0 then
            creatureDisplayID = select(1, SafeGetPetInfoExtra(speciesID))
        end
        if creatureDisplayID and creatureDisplayID > 0 then
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            panel._lastMountID = nil
            model:ClearModel()
            model:SetDisplayInfo(creatureDisplayID)
            panel._lastPetID = speciesID
            panel._lastCreatureDisplayID = creatureDisplayID
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            panel.normalizedRadius = true
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            if model.SetAnimation then pcall(model.SetAnimation, model, 0) end
            ScheduleBoundingRadiusRetries(nil, creatureDisplayID)
        else
            model:ClearModel()
            panel._lastPetID = nil
            panel._lastCreatureDisplayID = nil
            panel.normalizedRadius = false
        end
        scheduleModelViewerLayout()
    end

    local DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
    local DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"

    function panel:SetMountInfo(mountID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not mountID then
            local placeholder = (ns.L and ns.L["SELECT_MOUNT_FROM_LIST"]) or "Select a mount from the list"
            if placeholder == "" or placeholder == "SELECT_MOUNT_FROM_LIST" then placeholder = "Select a mount from the list" end
            nameText:SetText("|cff888888" .. placeholder .. "|r")
            if panel.detailIconTexture then
                panel.detailIconTexture:SetTexture(DEFAULT_ICON_MOUNT)
                panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            sourceLabel:SetText("")
            local mountSrcLines = panel.sourceLines
            for li = 1, #mountSrcLines do
                local line = mountSrcLines[li]
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            collectedBadge:Hide()
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            if panel._addContainer then panel._addContainer:Hide() end
            if panel._wowheadBtn then panel._wowheadBtn:Hide() end
            if panel._tryCountRow then panel._tryCountRow:Hide() end
            if panel.obtainedAtLine then panel.obtainedAtLine:Hide() end
            return
        end
        if panel._addContainer and panel._addBtn and panel._addedIndicator then
            panel._addContainer:Show()
            local planned = WarbandNexus and WarbandNexus.IsMountPlanned and WarbandNexus:IsMountPlanned(mountID)
            local collected = isCollectedFromCache
            if collected then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(0.45)
            elseif planned then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(1)
            else
                panel._addedIndicator:Hide()
                panel._addBtn:Show()
                panel._addBtn:SetScript("OnClick", function()
                    if WarbandNexus and WarbandNexus.AddPlan then
                        WarbandNexus:AddPlan({
                            type = "mount",
                            mountID = mountID,
                            name = name,
                            icon = icon,
                            source = sourceTextRaw or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                        })
                    end
                end)
            end
        end
        if panel.detailIconTexture then
            panel.detailIconTexture:SetTexture(icon or DEFAULT_ICON_MOUNT)
            panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        collectedBadge:Hide()
        local gR = (COLORS.gold and COLORS.gold[1]) or 1
        local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local gB = (COLORS.gold and COLORS.gold[3]) or 0
        local goldHex = format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
        nameText:SetText(goldHex .. (name or "") .. "|r")
        local description, source = descriptionFromCache, sourceTextRaw
        if (not source or source == "") or (not description or description == "") then
            local _, extraDesc, extraSrc = SafeGetMountInfoExtra(mountID)
            if not source or source == "" then source = extraSrc or "" end
            if not description or description == "" then description = extraDesc or "" end
        end
        source = source or ""
        description = description or ""
        if WarbandNexus.CleanSourceText then
            source = WarbandNexus:CleanSourceText(source)
            description = WarbandNexus:CleanSourceText(description)
        else
            source = SD.StripWoWFormatCodes(source)
            description = SD.StripWoWFormatCodes(description)
        end
        local rawSource = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawSource == "" or rawSource == "Unknown" then
            rawSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        end
        local whiteHex = "|cffffffff"
        -- Cost/Amount satırlarına para birimi ikonu (satın alma)
        local L = ns.L
        local costKey = (L and L["PARSE_COST"]) or "Cost"
        local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
        local function isCostOrAmountLine(text)
            if not text or text == "" then return false end
            if issecretvalue and issecretvalue(text) then return false end
            local t = text:gsub("^%s+", "")
            return t:sub(1, #costKey):lower() == costKey:lower() or t:sub(1, #amountKey):lower() == amountKey:lower()
        end
        -- API satırları: "Label: Value" ise etiket (Drop, Zone, Location vb.) sarı, değer beyaz
        local lines = {}
        for line in (rawSource .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colonPos = line:find(":", 1, true)
                if colonPos and colonPos > 1 then
                    local label = line:sub(1, colonPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colonPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(value)) or ""
                    lines[#lines + 1] = goldHex .. label .. ": |r" .. whiteHex .. value .. "|r" .. suffix
                else
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(line)) or ""
                    lines[#lines + 1] = whiteHex .. line .. "|r" .. suffix
                end
            end
        end
        if #lines == 0 then
            lines[1] = whiteHex .. rawSource .. "|r"
        end
        sourceLabel:SetText("")
        local TEXT_GAP_LINE = TEXT_GAP
        local lastAnchor = sourceContainer
        local lastPoint = "TOPLEFT"
        local lastY = 0
        for i = 1, #lines do
            local lineFs = panel.sourceLines[i]
            if not lineFs then
                lineFs = FontManager:CreateFontString(sourceContainer, "body", "OVERLAY")
                lineFs:SetPoint("TOPLEFT", sourceContainer, "TOPLEFT", 0, 0)
                lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, 0)
                lineFs:SetJustifyH("LEFT")
                lineFs:SetWordWrap(true)
                lineFs:SetNonSpaceWrap(false)
                lineFs:SetTextColor(whiteR, whiteG, whiteB)
                panel.sourceLines[i] = lineFs
            end
            lineFs:ClearAllPoints()
            lineFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
            lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
            lineFs:SetText(lines[i])
            lineFs:Show()
            lastAnchor = lineFs
            lastPoint = "BOTTOMLEFT"
            lastY = -TEXT_GAP_LINE
        end
        for i = #lines + 1, #panel.sourceLines do
            panel.sourceLines[i]:SetText("")
            panel.sourceLines[i]:Hide()
        end
        local isCollected = isCollectedFromCache
        if isCollected == nil and C_MountJournal and C_MountJournal.GetMountInfoByID then
            local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
            if issecretvalue and collected and issecretvalue(collected) then
                isCollected = false
            else
                isCollected = collected == true
            end
        end

        local anchorBeforeDesc, pointBeforeDesc, yBeforeDesc = lastAnchor, lastPoint, lastY
        if panel.obtainedAtLine then
            panel.obtainedAtLine:ClearAllPoints()
            local obtText = (isCollected and WarbandNexus.GetCollectionsAcquiredAt)
                and FormatCollectionsAcquiredDetail(WarbandNexus:GetCollectionsAcquiredAt("mount", mountID))
                or nil
            if obtText then
                panel.obtainedAtLine:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
                panel.obtainedAtLine:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
                panel.obtainedAtLine:SetText(obtText)
                panel.obtainedAtLine:Show()
                anchorBeforeDesc = panel.obtainedAtLine
                pointBeforeDesc = "BOTTOMLEFT"
                yBeforeDesc = -TEXT_GAP_LINE
            else
                panel.obtainedAtLine:Hide()
            end
        end

        descText:ClearAllPoints()
        descText:SetPoint("TOPLEFT", anchorBeforeDesc, pointBeforeDesc, 0, yBeforeDesc)
        descText:SetPoint("TOPRIGHT", anchorBeforeDesc, "BOTTOMRIGHT", 0, yBeforeDesc)

        description = (description or ""):gsub("^%s+", ""):gsub("%s+$", "")
        -- API'den gelen description olduğu gibi, beyaz
        descText:SetText(description ~= "" and (whiteHex .. description .. "|r") or "")

        if panel._wowheadBtn then
            local spellID = nil
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, sid = C_MountJournal.GetMountInfoByID(mountID)
                if sid and sid > 0 then spellID = sid end
            end
            if spellID then
                panel._wowheadBtn:SetScript("OnClick", function(self)
                    if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                        ns.UI.Factory:ShowWowheadCopyURL("mount", spellID, self)
                    end
                end)
                panel._wowheadBtn:Show()
            else
                panel._wowheadBtn:Hide()
            end
        end

        if panel._tryCountRow and panel._tryCountRow.WnUpdateTryCount then
            panel._tryCountRow:WnUpdateTryCount("mount", mountID, name)
        end

        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    function panel:SetPetInfo(speciesID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not speciesID then
            local placeholder = (ns.L and ns.L["SELECT_PET_FROM_LIST"]) or "Select a pet from the list"
            if placeholder == "" or placeholder == "SELECT_PET_FROM_LIST" then placeholder = "Select a pet from the list" end
            nameText:SetText("|cff888888" .. placeholder .. "|r")
            if panel.detailIconTexture then
                panel.detailIconTexture:SetTexture(DEFAULT_ICON_PET)
                panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            sourceLabel:SetText("")
            local petSrcLines = panel.sourceLines
            for li = 1, #petSrcLines do
                local line = petSrcLines[li]
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            collectedBadge:Hide()
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            if panel._addContainer then panel._addContainer:Hide() end
            if panel._wowheadBtn then panel._wowheadBtn:Hide() end
            if panel._tryCountRow then panel._tryCountRow:Hide() end
            if panel.obtainedAtLine then panel.obtainedAtLine:Hide() end
            return
        end
        if panel._addContainer and panel._addBtn and panel._addedIndicator then
            panel._addContainer:Show()
            local planned = WarbandNexus and WarbandNexus.IsPetPlanned and WarbandNexus:IsPetPlanned(speciesID)
            local collected = isCollectedFromCache
            if collected then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(0.45)
            elseif planned then
                panel._addBtn:Hide()
                panel._addedIndicator:Show()
                panel._addedIndicator:SetAlpha(1)
            else
                panel._addedIndicator:Hide()
                panel._addBtn:Show()
                panel._addBtn:SetScript("OnClick", function()
                    if WarbandNexus and WarbandNexus.AddPlan then
                        WarbandNexus:AddPlan({
                            type = "pet",
                            speciesID = speciesID,
                            name = name,
                            icon = icon,
                            source = sourceTextRaw or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                        })
                    end
                end)
            end
        end
        if panel.detailIconTexture then
            panel.detailIconTexture:SetTexture(icon or DEFAULT_ICON_PET)
            panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        collectedBadge:Hide()
        local gR = (COLORS.gold and COLORS.gold[1]) or 1
        local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local gB = (COLORS.gold and COLORS.gold[3]) or 0
        local goldHex = format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
        nameText:SetText(goldHex .. (name or "") .. "|r")
        local description, source = descriptionFromCache, sourceTextRaw
        if (not source or source == "") or (not description or description == "") then
            local _, extraDesc, extraSrc = SafeGetPetInfoExtra(speciesID)
            if not source or source == "" then source = extraSrc or "" end
            if not description or description == "" then description = extraDesc or "" end
        end
        source = source or ""
        description = description or ""
        if WarbandNexus.CleanSourceText then
            source = WarbandNexus:CleanSourceText(source)
            description = WarbandNexus:CleanSourceText(description)
        else
            source = SD.StripWoWFormatCodes(source)
            description = SD.StripWoWFormatCodes(description)
        end
        local rawSource = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawSource == "" or rawSource == "Unknown" then
            rawSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        end
        local whiteHex = "|cffffffff"
        local L = ns.L
        local costKey = (L and L["PARSE_COST"]) or "Cost"
        local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
        local function isCostOrAmountLine(text)
            if not text or text == "" then return false end
            if issecretvalue and issecretvalue(text) then return false end
            local t = text:gsub("^%s+", "")
            return t:sub(1, #costKey):lower() == costKey:lower() or t:sub(1, #amountKey):lower() == amountKey:lower()
        end
        local lines = {}
        for line in (rawSource .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colonPos = line:find(":", 1, true)
                if colonPos and colonPos > 1 then
                    local label = line:sub(1, colonPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colonPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(value)) or ""
                    lines[#lines + 1] = goldHex .. label .. ": |r" .. whiteHex .. value .. "|r" .. suffix
                else
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(line)) or ""
                    lines[#lines + 1] = whiteHex .. line .. "|r" .. suffix
                end
            end
        end
        if #lines == 0 then
            lines[1] = whiteHex .. rawSource .. "|r"
        end
        sourceLabel:SetText("")
        local TEXT_GAP_LINE = TEXT_GAP
        local lastAnchor = sourceContainer
        local lastPoint = "TOPLEFT"
        local lastY = 0
        for i = 1, #lines do
            local lineFs = panel.sourceLines[i]
            if not lineFs then
                lineFs = FontManager:CreateFontString(sourceContainer, "body", "OVERLAY")
                lineFs:SetPoint("TOPLEFT", sourceContainer, "TOPLEFT", 0, 0)
                lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, 0)
                lineFs:SetJustifyH("LEFT")
                lineFs:SetWordWrap(true)
                lineFs:SetNonSpaceWrap(false)
                lineFs:SetTextColor(whiteR, whiteG, whiteB)
                panel.sourceLines[i] = lineFs
            end
            lineFs:ClearAllPoints()
            lineFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
            lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
            lineFs:SetText(lines[i])
            lineFs:Show()
            lastAnchor = lineFs
            lastPoint = "BOTTOMLEFT"
            lastY = -TEXT_GAP_LINE
        end
        for i = #lines + 1, #panel.sourceLines do
            panel.sourceLines[i]:SetText("")
            panel.sourceLines[i]:Hide()
        end
        local petCollected = isCollectedFromCache
        if petCollected == nil then
            petCollected = SafeGetPetCollected(speciesID)
        end

        local anchorBeforeDescP, pointBeforeDescP, yBeforeDescP = lastAnchor, lastPoint, lastY
        if panel.obtainedAtLine then
            panel.obtainedAtLine:ClearAllPoints()
            local obtText = (petCollected and WarbandNexus.GetCollectionsAcquiredAt)
                and FormatCollectionsAcquiredDetail(WarbandNexus:GetCollectionsAcquiredAt("pet", speciesID))
                or nil
            if obtText then
                panel.obtainedAtLine:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
                panel.obtainedAtLine:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
                panel.obtainedAtLine:SetText(obtText)
                panel.obtainedAtLine:Show()
                anchorBeforeDescP = panel.obtainedAtLine
                pointBeforeDescP = "BOTTOMLEFT"
                yBeforeDescP = -TEXT_GAP_LINE
            else
                panel.obtainedAtLine:Hide()
            end
        end

        descText:ClearAllPoints()
        descText:SetPoint("TOPLEFT", anchorBeforeDescP, pointBeforeDescP, 0, yBeforeDescP)
        descText:SetPoint("TOPRIGHT", anchorBeforeDescP, "BOTTOMRIGHT", 0, yBeforeDescP)
        description = (description or ""):gsub("^%s+", ""):gsub("%s+$", "")
        descText:SetText(description ~= "" and (whiteHex .. description .. "|r") or "")

        if panel._wowheadBtn and speciesID then
            panel._wowheadBtn:SetScript("OnClick", function(self)
                if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                    ns.UI.Factory:ShowWowheadCopyURL("pet", speciesID, self)
                end
            end)
            panel._wowheadBtn:Show()
        elseif panel._wowheadBtn then
            panel._wowheadBtn:Hide()
        end

        if panel._tryCountRow and panel._tryCountRow.WnUpdateTryCount then
            panel._tryCountRow:WnUpdateTryCount("pet", speciesID, name)
        end

        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    return panel
end

-- ============================================================================
-- DESCRIPTION PANEL (standalone; used only if we need separate panel elsewhere)
-- ============================================================================

local function CreateDescriptionPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    function panel:SetMountInfo() end
    return panel
end

-- ============================================================================
-- LOADING STATE PANEL
-- ============================================================================

local function GetOrCreateLoadingPanel(parent)
    local UI_CreateLoadingStatePanel = ns.UI_CreateLoadingStatePanel
    if UI_CreateLoadingStatePanel then
        return UI_CreateLoadingStatePanel(parent)
    end
    local fallback = Factory:CreateContainer(parent, math.max(1, parent:GetWidth() or 200), math.max(1, parent:GetHeight() or 200), false)
    if not fallback then
        fallback = CreateFrame("Frame", nil, parent)
    end
    fallback:SetAllPoints(parent)
    function fallback:ShowLoading() self:Show() end
    function fallback:HideLoading() self:Hide() end
    return fallback
end

-- ============================================================================
-- ACHIEVEMENT DETAIL PANEL — Parent/Children, Description, Criteria (replaces model viewer)
-- ============================================================================
-- Achievement detail header: matched heights so To-Do + Track align; width fits localized labels.
local ACH_ROW_ADD_WIDTH = 84
local ACH_ROW_ADD_HEIGHT = 30
local ACH_TRACK_WIDTH = 64
local ACH_TRACK_HEIGHT = 30
local ACH_ACTION_GAP = 6

-- Build full achievement series (e.g. Level 10, 20, 30... 80): walk to root via GetPreviousAchievement, then collect all via GetSupercedingAchievements.
-- Returns ordered array of achievement IDs from first tier to last; length >= 1 when achievement is part of a chain.
local function BuildAchievementSeries(achievementID)
    if not achievementID or achievementID <= 0 then return {} end
    if issecretvalue and issecretvalue(achievementID) then return {} end
    local GetPrev = GetPreviousAchievement
    local GetSuperceding = (C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements) or function() return {} end
    if not GetPrev then return { achievementID } end
    local id = achievementID
    local guard = 0
    local MAX_CHAIN = 250
    while true do
        guard = guard + 1
        if guard > MAX_CHAIN then break end
        local okp, prev = pcall(GetPrev, id)
        if not okp or prev == nil then break end
        if issecretvalue and issecretvalue(prev) then break end
        if type(prev) ~= "number" or prev <= 0 then break end
        id = prev
    end
    local series = { id }
    local idx = 1
    guard = 0
    while true do
        guard = guard + 1
        if guard > MAX_CHAIN then break end
        local cur = series[idx]
        if cur == nil then break end
        if issecretvalue and issecretvalue(cur) then break end
        local okn, nextIds = pcall(GetSuperceding, cur)
        if not okn or not nextIds or type(nextIds) ~= "table" or #nextIds == 0 then break end
        local nxt = nextIds[1]
        if nxt == nil then break end
        if issecretvalue and issecretvalue(nxt) then break end
        if type(nxt) ~= "number" or nxt <= 0 then break end
        series[idx + 1] = nxt
        idx = idx + 1
    end
    return series
end

local function IsAchievementTracked(achievementID)
    if not achievementID then return false end
    if WarbandNexus and WarbandNexus.IsAchievementTracked then
        return WarbandNexus:IsAchievementTracked(achievementID)
    end
    return false
end

local function ToggleAchievementTracking(achievementID)
    if not achievementID then return false end
    if WarbandNexus and WarbandNexus.ToggleAchievementTracking then
        return WarbandNexus:ToggleAchievementTracking(achievementID)
    end
    return false
end

local function CreateAchievementDetailPanel(parent, width, height, onSelectAchievement)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyDetailAccentVisuals(panel)

    panel._scrollBarContainer = EnsureDetailScrollBarContainer(panel._scrollBarContainer, panel, SCROLLBAR_GAP, CONTAINER_INSET)
    local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
    scroll:SetPoint("BOTTOMRIGHT", panel._scrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
    EnableStandardScrollWheel(scroll)
    panel.scrollFrame = scroll

    local child = CreateStandardScrollChild(scroll, width - (CONTAINER_INSET * 2) - SCROLLBAR_GAP, 1)
    if scroll.ScrollBar then
        Factory:PositionScrollBarInContainer(scroll.ScrollBar, panel._scrollBarContainer, CONTAINER_INSET)
    end

    local content = child
    local lastAnchor = content
    local lastPoint = "TOPLEFT"
    local lastY = 0
    local TEXT_GAP_LINE = TEXT_GAP

    panel._detailElements = {}

    local function clearDetailElements()
        local bin = ns.UI_RecycleBin
        local dels = panel._detailElements
        for ei = 1, #dels do
            local el = dels[ei]
            el:Hide()
            if bin then el:SetParent(bin) else el:SetParent(nil) end
        end
        panel._detailElements = {}
    end

    local function addDetailElement(el)
        if el then
            panel._detailElements[#panel._detailElements + 1] = el
        end
    end

    -- Achievement details: sola hizalı (tüm içerik CONTENT_INSET’ten başlar)
    local SECTION_GAP = 4       -- gap between section title and body
    local SECTION_HEADER_GAP = 10  -- gap between section blocks (Description / Series / Criteria)
    local ICON_LEFT_INSET = 2  -- icons 2px right from row edge
    local CONTENT_COLUMN_LEFT = CONTENT_INSET  -- section titles, description, criteria (sola hizalı)
    local ROW_TEXT_LEFT = CONTENT_INSET + ICON_LEFT_INSET + ROW_ICON_SIZE + (CONTENT_INSET / 2)  -- series row name (after icon; completed/not icon kaldırıldı)

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0

    local function addSection(title, fn)
        local titleFs = FontManager:CreateFontString(content, "body", "OVERLAY")
        titleFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
        titleFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
        titleFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(true)
        titleFs:SetTextColor(goldR, goldG, goldB)
        titleFs:SetText(title or "")
        addDetailElement(titleFs)
        lastAnchor = titleFs
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP
        fn(titleFs)
    end

    local function addAchievementRow(ach, label, currentAchievementID)
        if not ach or not ach.id then return end
        if issecretvalue and issecretvalue(ach.id) then return end
        if ach.name and issecretvalue and issecretvalue(ach.name) then return end
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetPoint("TOP", lastAnchor, lastPoint, 0, lastY)
        row:SetPoint("LEFT", content, "LEFT", CONTENT_INSET, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        local isCurrent = false
        if currentAchievementID and ach.id then
            if not (issecretvalue and issecretvalue(currentAchievementID)) and not (issecretvalue and issecretvalue(ach.id)) then
                isCurrent = (ach.id == currentAchievementID)
            end
        end
        if ApplyVisuals then
            if isCurrent then
                ApplyVisuals(row, {0.1, 0.08, 0.05, 0.9}, {goldR, goldG, goldB, 0.85})
            else
                ApplyVisuals(row, {0.06, 0.06, 0.08, 0.5}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4})
            end
        end
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_ICON_SIZE, ROW_ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 2, 0)
        icon:SetTexture(ach.icon or "Interface\\Icons\\Achievement_General")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local nameFs = FontManager:CreateFontString(row, "body", "OVERLAY")
        nameFs:SetPoint("LEFT", row, "LEFT", ROW_TEXT_LEFT, 0)
        nameFs:SetPoint("RIGHT", row, "RIGHT", -PADDING, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        local ptsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
        nameFs:SetText((ach.name or "") .. ptsStr)
        row:SetScript("OnMouseDown", function()
            if onSelectAchievement then onSelectAchievement(ach) end
            if ach.id and not InCombatLockdown() and OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, ach.id)
            end
        end)
        addDetailElement(row)
        lastAnchor = row
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP
    end

    function panel:SetAchievement(achievement)
        clearDetailElements()
        lastAnchor = content
        lastPoint = "TOPLEFT"
        lastY = 0
        panel._currentAchievement = achievement

        if not achievement or not achievement.id then
            child:SetHeight(1)
            return
        end

        -- Header: same hierarchy as Mounts/Pets (CONTENT_INSET from edges, icon then name)
        local CDH = ns.CollectionsDetailHeaderLayout or {}
        local achRightColMinH = ACH_ROW_ADD_HEIGHT + (CDH.TRY_GAP or 4) + (CDH.TRY_ROW_H or 18)
        local achHdrH = math.max(ROW_HEIGHT + SECTION_GAP, DETAIL_ICON_SIZE + SECTION_GAP, achRightColMinH)
        local achHdrW = math.max(220, (child.GetWidth and child:GetWidth()) or 620)
        local headerRow = Factory:CreateContainer(content, achHdrW, achHdrH, false)
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, content)
        end
        headerRow:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(achHdrH)
        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        if ApplyVisuals then
            ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
        end
        local headerIcon = iconBorder:CreateTexture(nil, "OVERLAY")
        headerIcon:SetAllPoints()
        headerIcon:SetTexture(achievement.icon or "Interface\\Icons\\Achievement_General")
        headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local DETAIL_HEADER_GAP = 10
        local goldR = (COLORS.gold and COLORS.gold[1]) or 1
        local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local goldB = (COLORS.gold and COLORS.gold[3]) or 0
        -- Sağ üst: mount/pet/toy ile aynı Factory sütunu (Wowhead en sağ, try satırı action genişliğinde; slot Add+Track için genişletildi)
        local achActionW = ACH_ROW_ADD_WIDTH + ACH_ACTION_GAP + ACH_TRACK_WIDTH
        local achAddCol = Factory:CreateCollectionsDetailRightColumn(headerRow, {
            withTryRow = true,
            actionSlotWidth = achActionW,
            actionSlotHeight = ACH_ROW_ADD_HEIGHT,
        })
        achAddCol.root:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        local achControls = Factory:CreateContainer(achAddCol.actionSlot, ACH_ACTION_GAP + ACH_TRACK_WIDTH + ACH_ROW_ADD_WIDTH, ACH_ROW_ADD_HEIGHT, false)
        if not achControls then
            achControls = CreateFrame("Frame", nil, achAddCol.actionSlot)
        end
        achControls:SetAllPoints(achAddCol.actionSlot)

        local headerWowheadBtn = achAddCol.wowheadBtn
        local achIDForWh = achievement.id
        headerWowheadBtn:SetScript("OnClick", function(self)
            if achIDForWh and ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                ns.UI.Factory:ShowWowheadCopyURL("achievement", achIDForWh, self)
            end
        end)
        if achievement.id then
            headerWowheadBtn:Show()
        else
            headerWowheadBtn:Hide()
        end

        local trackBtn = Factory:CreateButton(achControls, ACH_TRACK_WIDTH, ACH_TRACK_HEIGHT, false)
        trackBtn:SetPoint("TOPRIGHT", achControls, "TOPRIGHT", 0, 0)
        trackBtn:SetFrameLevel(headerRow:GetFrameLevel() + 25)
        trackBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        local trackLabel = FontManager:CreateFontString(trackBtn, "body", "OVERLAY")
        trackLabel:SetPoint("CENTER")
        if trackLabel.EnableMouse then
            trackLabel:EnableMouse(false)
        end
        local trackedStr = (ns.L and ns.L["TRACKED"]) or "Tracked"
        local trackStr = (ns.L and ns.L["TRACK"]) or "Track"
        local function UpdateTrackButton()
            if achievement.isCollected then
                trackLabel:SetText(trackStr)
                trackLabel:SetTextColor(0.52, 0.54, 0.58, 0.72)
                trackBtn:SetAlpha(0.4)
                trackBtn:EnableMouse(false)
            elseif IsAchievementTracked(achievement.id) then
                trackLabel:SetText(trackedStr)
                trackLabel:SetTextColor(0.42, 0.68, 0.52, 0.78)
                trackBtn:SetAlpha(0.68)
                trackBtn:EnableMouse(true)
            else
                trackLabel:SetText(trackStr)
                trackLabel:SetTextColor(1, 0.84, 0.28, 1)
                trackBtn:SetAlpha(1)
                trackBtn:EnableMouse(true)
            end
        end
        trackBtn:SetScript("OnClick", function()
            if achievement.id then
                ToggleAchievementTracking(achievement.id)
                UpdateTrackButton()
            end
        end)
        trackBtn:SetScript("OnEnter", function()
            if trackBtn:IsMouseEnabled() then
                if trackLabel then trackLabel:SetTextColor(1, 1, 1, 1) end
                GameTooltip:SetOwner(trackBtn, "ANCHOR_TOP")
                GameTooltip:SetText((ns.L and ns.L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)")
                GameTooltip:Show()
            end
        end)
        trackBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
            UpdateTrackButton()
        end)

        local addLabelText = (ns.L and ns.L["ADD_BUTTON"]) or "To-Do"
        local addedLabelText = (ns.L and ns.L["ADDED"]) or "Added"
        local isPlanned = WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(achievement.id)
        local addBtn, addedIndicator
        if achievement.isCollected then
            addedIndicator = PlanCardFactory and PlanCardFactory.CreateAddedIndicator(achControls, {
                buttonType = "row",
                width = ACH_ROW_ADD_WIDTH,
                height = ACH_ROW_ADD_HEIGHT,
                label = addedLabelText,
                fontCategory = "body",
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
            })
            if addedIndicator then
                addedIndicator:ClearAllPoints()
                addedIndicator:SetPoint("RIGHT", trackBtn, "LEFT", -ACH_ACTION_GAP, 0)
                addedIndicator:SetAlpha(0.45)
            end
        elseif isPlanned then
            addedIndicator = PlanCardFactory and PlanCardFactory.CreateAddedIndicator(achControls, {
                buttonType = "row",
                width = ACH_ROW_ADD_WIDTH,
                height = ACH_ROW_ADD_HEIGHT,
                label = addedLabelText,
                fontCategory = "body",
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
            })
            if addedIndicator then
                addedIndicator:ClearAllPoints()
                addedIndicator:SetPoint("RIGHT", trackBtn, "LEFT", -ACH_ACTION_GAP, 0)
            end
        else
            addBtn = PlanCardFactory and PlanCardFactory.CreateAddButton(achControls, {
                buttonType = "row",
                width = ACH_ROW_ADD_WIDTH,
                height = ACH_ROW_ADD_HEIGHT,
                label = addLabelText,
                anchorPoint = "RIGHT",
                x = 0,
                y = 0,
                onClick = function()
                    if not achievement.id or not WarbandNexus or not WarbandNexus.AddPlan then return end
                    local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
                    local rewardText = rewardInfo and (rewardInfo.title or rewardInfo.itemName) or nil
                    if not rewardText or rewardText == "" then
                        rewardText = achievement.rewardText or achievement.rewardTitle
                    end
                    WarbandNexus:AddPlan({
                        type = "achievement",
                        achievementID = achievement.id,
                        name = achievement.name,
                        icon = achievement.icon,
                        points = achievement.points,
                        source = achievement.source,
                        rewardText = rewardText,
                    })
                end,
            })
            if addBtn then
                addBtn:ClearAllPoints()
                addBtn:SetPoint("RIGHT", trackBtn, "LEFT", -ACH_ACTION_GAP, 0)
                addBtn:SetFrameLevel(headerRow:GetFrameLevel() + 25)
                if addBtn.text then
                    addBtn.text:SetTextColor(0.98, 0.94, 0.72, 1)
                end
            end
        end

        UpdateTrackButton()

        if achAddCol.tryCountRow and achAddCol.tryCountRow.WnUpdateTryCount then
            achAddCol.tryCountRow:WnUpdateTryCount("achievement", achievement.id, achievement.name)
        end

        local headerName = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        headerName:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        headerName:SetPoint("TOPRIGHT", achAddCol.root, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
        headerName:SetJustifyH("LEFT")
        headerName:SetWordWrap(true)
        headerName:SetTextColor(goldR, goldG, goldB)
        headerName:SetText((achievement.name or "") .. (achievement.points and achievement.points > 0 and (" (" .. achievement.points .. " pts)") or ""))

        addDetailElement(headerRow)
        lastAnchor = headerRow
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP

        if achievement.isCollected and WarbandNexus and WarbandNexus.GetCollectionsAcquiredAt then
            local obtTs = WarbandNexus:GetCollectionsAcquiredAt("achievement", achievement.id)
            local obtStr = obtTs and FormatCollectionsAcquiredDetail(obtTs) or nil
            if obtStr then
                local obtFs = FontManager:CreateFontString(content, "small", "OVERLAY")
                obtFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
                obtFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
                obtFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
                obtFs:SetJustifyH("LEFT")
                obtFs:SetWordWrap(true)
                obtFs:SetTextColor(0.68, 0.70, 0.74, 1)
                obtFs:SetText(obtStr)
                addDetailElement(obtFs)
                lastAnchor = obtFs
                lastPoint = "BOTTOMLEFT"
                lastY = -SECTION_GAP
            end
        end

        -- Description: tek satır "Description: metin" — sadece baş harf büyük, etiket sarı
        if achievement.description and achievement.description ~= "" then
            local rawLabel = (ns.L and ns.L["DESCRIPTION"]) or "Description"
            local descLabel = (rawLabel and rawLabel ~= "" and (string.upper(string.sub(rawLabel, 1, 1)) .. string.lower(string.sub(rawLabel, 2)))) or "Description"
            local goldHex = format("|cff%02x%02x%02x", goldR * 255, goldG * 255, goldB * 255)
            local descFs = FontManager:CreateFontString(content, "body", "OVERLAY")
            descFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
            descFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
            descFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
            descFs:SetJustifyH("LEFT")
            descFs:SetWordWrap(true)
            descFs:SetText(goldHex .. descLabel .. ":|r " .. (achievement.description or ""))
            addDetailElement(descFs)
            lastAnchor = descFs
            lastPoint = "BOTTOMLEFT"
            lastY = -SECTION_GAP
        end

        -- Achievement series (e.g. Level 10, 20, 30... 80): all tiers with check/cross; current achievement highlighted
        local seriesIds = BuildAchievementSeries(achievement.id)
        if seriesIds and #seriesIds > 1 then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["ACHIEVEMENT_SERIES"]) or "Achievement Series", function()
                for i = 1, #seriesIds do
                    local achID = seriesIds[i]
                    if achID and not (issecretvalue and issecretvalue(achID)) then
                        -- GetAchievementInfo: id, name, points, completed, month, day, year, description, flags, icon, ...
                        local ok, _, aName, aPoints, aCompleted, _, _, _, aDesc, _, aIcon = pcall(GetAchievementInfo, achID)
                        if ok and aName and not (issecretvalue and issecretvalue(aName)) then
                            addAchievementRow({ id = achID, name = aName, icon = aIcon, points = aPoints, isCollected = aCompleted, description = aDesc }, nil, achievement.id)
                        end
                    end
                end
            end)
        end

        local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
        local rewardDisplayText
        if rewardInfo then
            rewardDisplayText = rewardInfo.title or rewardInfo.itemName
        end
        if not rewardDisplayText or rewardDisplayText == "" then
            rewardDisplayText = achievement.rewardText or achievement.rewardTitle
        end
        if rewardDisplayText and rewardDisplayText ~= "" then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["REWARD_LABEL"]) or "Reward", function(anchor)
                local rewardFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                rewardFs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -SECTION_GAP)
                rewardFs:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, 0)
                rewardFs:SetJustifyH("LEFT")
                rewardFs:SetWordWrap(true)
                local rewardColor = (rewardInfo and rewardInfo.type == "title") and "|cffffcc00" or "|cff00ff00"
                rewardFs:SetText(rewardColor .. rewardDisplayText .. "|r")
                addDetailElement(rewardFs)
                lastAnchor = rewardFs
                lastPoint = "BOTTOMLEFT"
                lastY = -SECTION_GAP
            end)
        end

        local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(achievement.id) or 0
        if numCriteria > 0 then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["CRITERIA"]) or "Criteria", function(anchor)
                local CRITERIA_LINE_HEIGHT = 16
                for i = 1, numCriteria do
                    local criteriaName, criteriaType, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievement.id, i)
                    if criteriaName and criteriaName ~= "" then
                        local progressStr = ""
                        if quantity and reqQuantity and reqQuantity > 1 then
                            local fmt = ns.UI_FormatNumber or tostring
                            progressStr = format(" (%s / %s)", fmt(quantity), fmt(reqQuantity))
                        end
                        local critW = math.max(80, (content.GetWidth and content:GetWidth()) or 400)
                        local row = Factory:CreateContainer(content, critW, CRITERIA_LINE_HEIGHT, false)
                        if not row then
                            row = CreateFrame("Frame", nil, content)
                        end
                        row:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
                        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, lastY)
                        row:SetHeight(CRITERIA_LINE_HEIGHT)
                        -- Criteria satırı başlıkla aynı hizada: X ve metin CONTENT_COLUMN_LEFT’ten başlar
                        local critFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                        critFs:SetPoint("LEFT", row, "LEFT", CONTENT_COLUMN_LEFT + ICON_LEFT_INSET, 0)
                        critFs:SetPoint("RIGHT", row, "RIGHT", -CONTENT_INSET, 0)
                        critFs:SetJustifyH("LEFT")
                        critFs:SetWordWrap(true)
                        critFs:SetText(color .. (criteriaName or "") .. progressStr .. "|r")
                        addDetailElement(row)
                        lastAnchor = row
                        lastPoint = "BOTTOMLEFT"
                        lastY = -SECTION_GAP
                    end
                end
            end)
        end

        local totalH = math.abs(lastY) + PADDING
        child:SetHeight(math.max(totalH, 1))
    end

    return panel
end

-- ============================================================================
-- SUB-TAB BUTTONS
-- ============================================================================

local SUB_TABS = {
    { key = "recent", label = (ns.L and ns.L["COLLECTIONS_SUBTAB_RECENT"]) or "Recent", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "achievements", label = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements", icon = "Interface\\Icons\\Achievement_General" },
    { key = "mounts", label = (ns.L and ns.L["CATEGORY_MOUNTS"]) or MOUNTS or "Mounts", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { key = "pets", label = (ns.L and ns.L["CATEGORY_PETS"]) or PETS or "Pets", icon = "Interface\\Icons\\INV_Box_PetCarrier_01" },
    { key = "toys", label = (ns.L and ns.L["CATEGORY_TOYS"]) or (TOY_BOX or "Toys"), icon = "Interface\\Icons\\INV_Misc_Toy_07" },
}

-- Plans category bar ile birebir aynı (catBtnHeight=40, catBtnSpacing=8, DEFAULT_CAT_BTN_WIDTH=150)
local SUBTAB_BTN_HEIGHT = 40
local SUBTAB_BTN_SPACING = 8
local SUBTAB_ICON_SIZE = 28
local SUBTAB_ICON_LEFT = 10
local SUBTAB_ICON_TEXT_GAP = 8
local SUBTAB_TEXT_RIGHT = 10
local SUBTAB_DEFAULT_WIDTH = 150

local function CreateSubTabBar(parent, onTabSelect)
    local bar = Factory:CreateContainer(parent, 400, SUBTAB_BTN_HEIGHT, false)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)

    -- Plans gibi metne göre buton genişliği hesapla
    local btnWidths = {}
    for i = 1, #SUB_TABS do
        local tabInfo = SUB_TABS[i]
        local tempFs = FontManager:CreateFontString(bar, "body", "OVERLAY")
        tempFs:SetText(tabInfo.label)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local needed = SUBTAB_ICON_LEFT + SUBTAB_ICON_SIZE + SUBTAB_ICON_TEXT_GAP + textW + SUBTAB_TEXT_RIGHT
        btnWidths[i] = math.max(needed, SUBTAB_DEFAULT_WIDTH)
    end

    local buttons = {}
    local xPos = 0
    local btnHeight = SUBTAB_BTN_HEIGHT
    local spacing = SUBTAB_BTN_SPACING

    local accentColor = COLORS.accent
    for i = 1, #SUB_TABS do
        local tabInfo = SUB_TABS[i]
        local btnWidth = btnWidths[i]
        local btn = ns.UI.Factory:CreateButton(bar, btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", xPos, 0)
        btn._tabKey = tabInfo.key

        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
        end
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end

        -- Active indicator bar (main window tab ile aynı: alt çizgi vurgusu)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

        local btnIcon = btn:CreateTexture(nil, "ARTWORK")
        btnIcon:SetSize(SUBTAB_ICON_SIZE - 2, SUBTAB_ICON_SIZE - 2)
        btnIcon:SetPoint("LEFT", SUBTAB_ICON_LEFT, 0)
        btnIcon:SetTexture(tabInfo.icon)
        btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText:SetPoint("LEFT", btnIcon, "RIGHT", SUBTAB_ICON_TEXT_GAP, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -SUBTAB_TEXT_RIGHT, 0)
        btnText:SetText(tabInfo.label)
        btnText:SetJustifyH("LEFT")
        btnText:SetWordWrap(false)
        btnText:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        btn._text = btnText

        btn:SetScript("OnClick", function()
            if onTabSelect then onTabSelect(tabInfo.key) end
        end)

        if UpdateBorderColor then
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                UpdateBorderColor(self, {accentColor[1] * 1.2, accentColor[2] * 1.2, accentColor[3] * 1.2, 0.9})
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                UpdateBorderColor(self, {accentColor[1], accentColor[2], accentColor[3], 0.6})
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
        xPos = xPos + btnWidths[i] + spacing
    end

    bar.buttons = buttons

    function bar:SetActiveTab(key)
        local acc = COLORS.accent
        for k, btn in pairs(buttons) do
            if k == key then
                btn._active = true
                if btn.activeBar then btn.activeBar:SetAlpha(1) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1}, {acc[1], acc[2], acc[3], 1})
                end
                if btn._text then
                    btn._text:SetTextColor(1, 1, 1)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "OUTLINE") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc[1], acc[2], acc[3], 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1) end
            else
                btn._active = false
                if btn.activeBar then btn.activeBar:SetAlpha(0) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1})
                end
                if btn._text then
                    btn._text:SetTextColor(0.7, 0.7, 0.7)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.12, 0.15, 1) end
            end
        end
    end

    return bar
end

-- ============================================================================
-- MOUNT DATA BUILDER (Source Grouped) — From global collection data (DB); fallback to API
-- ============================================================================

-- Pure API: hide-decision is delegated to C_MountJournal.GetMountInfoByID().shouldHideOnChar.
-- Placeholder/ability mounts (e.g. "Soar", "Unstable Rocket") are flagged hidden by the API
-- on characters that cannot use them, so no addon-side blacklist is required.

local function BuildGroupedMountData(searchText, showCollected, showUncollected, optionalMounts)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.SOURCE_CATEGORIES do
        local cat = SD.SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function classify(src)
        return SD.ClassifyMountSourceCached(classifyCache, src)
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local idx = nameIndex[catKey]
        local pos = idx and idx[name]
        if pos then grouped[catKey][pos].isCollected = true end
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    -- Use optionalMounts when provided and non-empty to avoid repeated DB/API calls
    local allMounts
    if optionalMounts and #optionalMounts > 0 then
        allMounts = optionalMounts
    else
        allMounts = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
    end
    local useCache = #allMounts > 0

    -- Tab tıklandığında sadece DB/cache kullan; API çağrısı yapma (FPS ve performans).
    local query = SafeLower(searchText)
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allMounts do
            local d = allMounts[i]
            if d and d.id then
                -- Live-query shouldHideOnChar: DB value may be stale from another character
                local shouldSkip = false
                if d.shouldHideOnChar then
                    shouldSkip = true  -- default to DB value
                    if C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, _, _, _, _, _, _, _, sh = C_MountJournal.GetMountInfoByID(d.id)
                        if issecretvalue and sh and issecretvalue(sh) then
                            shouldSkip = false  -- secret = treat as visible
                        elseif sh == false then
                            shouldSkip = false  -- API says visible on this character
                        end
                    end
                end
                if not shouldSkip then
                    local name = d.name or tostring(d.id)
                    -- Pure API: isCollected from cache (no API call here).
                    local isCollected = (d.isCollected == true) or (d.collected == true)
                    if (showC and isCollected) or (showU and not isCollected) then
                        if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                            local sourceText = d.source or ""
                            local catKey = classify(d.sourceType)
                            if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                            if not nameAlreadyInCategory(catKey, name) then
                                addToCategory(catKey, {
                                    id = d.id,
                                    name = name,
                                    icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                    source = sourceText,
                                    sourceType = d.sourceType,
                                    description = d.description,
                                    creatureDisplayID = d.creatureDisplayID,
                                    isCollected = isCollected,
                                })
                                totalCount = totalCount + 1
                            elseif isCollected then
                                updateCollectedInCategory(catKey, name, true)
                            end
                        end
                    end
                end
            end
        end
    else
        local mountIDs = (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountIDs()) or {}
        if #mountIDs == 0 then return grouped, 0 end
        for i = 1, #mountIDs do
            local mountID = mountIDs[i]
            -- Skip hidden mounts: live-query shouldHideOnChar (10th return, API is character-specific)
            local shouldHide = false
            local liveSourceType = nil
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, _, _, _, _, st, _, _, _, sh = C_MountJournal.GetMountInfoByID(mountID)
                if issecretvalue and sh and issecretvalue(sh) then
                    -- secret = treat as visible
                elseif sh == true then
                    shouldHide = true
                end
                if not (issecretvalue and st and issecretvalue(st)) then liveSourceType = st end
            end
            if not shouldHide then
            local isCollected = SafeGetMountCollected(mountID)
            if (showC and isCollected) or (showU and not isCollected) then
                local meta = WarbandNexus:ResolveCollectionMetadata("mount", mountID)
                local name = (meta and meta.name) or ""
                if not name and C_MountJournal and C_MountJournal.GetMountInfoByID then
                    local n = C_MountJournal.GetMountInfoByID(mountID)
                    if n and not (issecretvalue and issecretvalue(n)) then name = n end
                end
                if not name then name = tostring(mountID) end
                if query == "" or SafeLower(name):find(query, 1, true) then
                    local sourceText = meta and meta.source or ""
                    local creatureDisplayID, description, src = SafeGetMountInfoExtra(mountID)
                    if sourceText == "" then sourceText = src or "" end
                    local icon = (meta and meta.icon) or "Interface\\Icons\\Ability_Mount_RidingHorse"
                    if not icon and C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, ic = C_MountJournal.GetMountInfoByID(mountID)
                        if ic and not (issecretvalue and issecretvalue(ic)) then icon = ic end
                    end
                    local sourceTypeInt = (meta and meta.sourceType) or liveSourceType
                    local catKey = classify(sourceTypeInt)
                    if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        addToCategory(catKey, {
                            id = mountID,
                            name = name,
                            icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                            source = sourceText,
                            sourceType = sourceTypeInt,
                            description = (meta and meta.description) or description or "",
                            creatureDisplayID = creatureDisplayID,
                            isCollected = isCollected,
                        })
                        totalCount = totalCount + 1
                    elseif isCollected then
                        updateCollectedInCategory(catKey, name, true)
                    end
                end
            end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return SafeLower(a.name) < SafeLower(b.name)
        end)
    end

    return grouped, totalCount
end

-- Chunked build: process mounts in small chunks per frame so no single frame freezes for ~1s.
local function RunChunkedMountBuild(allMounts, searchText, showCollected, showUncollected, drawGen, contentFrame, onComplete)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.SOURCE_CATEGORIES do
        local cat = SD.SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src) return SD.ClassifyMountSourceCached(classifyCache, src) end
    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end
    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local pos = nameIndex[catKey] and nameIndex[catKey][name]
        if pos then grouped[catKey][pos].isCollected = true end
    end
    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local startIdx = 1
    local total = #allMounts

    local function processChunk()
        if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
        if not contentFrame or not contentFrame:IsVisible() then return end
        local limit = math.min(startIdx + RUN_CHUNK_SIZE - 1, total)
        for i = startIdx, limit do
            local d = allMounts[i]
            if d and d.id then
                -- Live-query shouldHideOnChar: DB value may be stale from another character
                local shouldSkip = false
                if d.shouldHideOnChar then
                    shouldSkip = true
                    if C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, _, _, _, _, _, _, _, sh = C_MountJournal.GetMountInfoByID(d.id)
                        if issecretvalue and sh and issecretvalue(sh) then
                            shouldSkip = false
                        elseif sh == false then
                            shouldSkip = false
                        end
                    end
                end
                if not shouldSkip then
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(d.sourceType)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                source = sourceText,
                                sourceType = d.sourceType,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
        end
        startIdx = limit + 1
        if startIdx > total then
            for _, items in pairs(grouped) do
                table.sort(items, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
            end
            onComplete(grouped)
        else
            C_Timer.After(0, processChunk)
        end
    end
    C_Timer.After(0, processChunk)
end

-- Chunked build for pets (same idea as mounts).
local function RunChunkedPetBuild(allPets, searchText, showCollected, showUncollected, drawGen, contentFrame, onComplete)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.PET_SOURCE_CATEGORIES do
        local cat = SD.PET_SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src) return SD.ClassifyPetSourceCached(classifyCache, src) end
    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end
    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local pos = nameIndex[catKey] and nameIndex[catKey][name]
        if pos then grouped[catKey][pos].isCollected = true end
    end
    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local startIdx = 1
    local total = #allPets

    local function processChunk()
        if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
        if not contentFrame or not contentFrame:IsVisible() then return end
        local limit = math.min(startIdx + RUN_CHUNK_SIZE - 1, total)
        for i = startIdx, limit do
            local d = allPets[i]
            if d and d.id then
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(d.sourceTypeIndex)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                sourceTypeIndex = d.sourceTypeIndex,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
        startIdx = limit + 1
        if startIdx > total then
            for _, items in pairs(grouped) do
                table.sort(items, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
            end
            onComplete(grouped)
        else
            C_Timer.After(0, processChunk)
        end
    end
    C_Timer.After(0, processChunk)
end

-- BuildGroupedPetData: same structure as mounts, uses C_PetJournal / GetAllPetsData. Pet-specific categories (petbattle, puzzle).
local function BuildGroupedPetData(searchText, showCollected, showUncollected, optionalPets)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.PET_SOURCE_CATEGORIES do
        local cat = SD.PET_SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function classify(src)
        return SD.ClassifyPetSourceCached(classifyCache, src)
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local idx = nameIndex[catKey]
        local pos = idx and idx[name]
        if pos then grouped[catKey][pos].isCollected = true end
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    local allPets
    if optionalPets and #optionalPets > 0 then
        allPets = optionalPets
    else
        allPets = (WarbandNexus.GetAllPetsData and WarbandNexus:GetAllPetsData()) or {}
    end
    local useCache = #allPets > 0

    -- Tab tıklandığında sadece DB/cache kullan; API çağrısı yapma.
    local query = SafeLower(searchText)
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allPets do
            local d = allPets[i]
            if not d or not d.id then
            else
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(d.sourceTypeIndex)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                sourceTypeIndex = d.sourceTypeIndex,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                            totalCount = totalCount + 1
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
    else
        if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
        if not InCombatLockdown() then
            pcall(function()
                if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
                if C_PetJournal.SetFilterChecked then
                    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
                end
            end)
        end
        local numPets = C_PetJournal.GetNumPets and C_PetJournal.GetNumPets() or 0
        if numPets == 0 then return grouped, 0 end
        for i = 1, numPets do
            local _, speciesID = C_PetJournal.GetPetInfoByIndex(i)
            if speciesID then
                local isCollected = SafeGetPetCollected(speciesID)
                if (showC and isCollected) or (showU and not isCollected) then
                    local meta = WarbandNexus:ResolveCollectionMetadata("pet", speciesID)
                    local name = (meta and meta.name) or ""
                    if not name and C_PetJournal.GetPetInfoBySpeciesID then
                        local n = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                        if n and not (issecretvalue and issecretvalue(n)) then name = n end
                    end
                    if not name then name = tostring(speciesID) end
                    if query == "" or SafeLower(name):find(query, 1, true) then
                        local sourceText = meta and meta.source or ""
                        local creatureDisplayID, description, src = SafeGetPetInfoExtra(speciesID)
                        if sourceText == "" then sourceText = src or "" end
                        local icon = (meta and meta.icon) or "Interface\\Icons\\INV_Box_PetCarrier_01"
                        if not icon and C_PetJournal.GetPetInfoBySpeciesID then
                            local _, ic = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                            if ic and not (issecretvalue and issecretvalue(ic)) then icon = ic end
                        end
                        local sourceTypeIndex = meta and meta.sourceTypeIndex or nil
                        local catKey = classify(sourceTypeIndex)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = speciesID,
                                name = name,
                                icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                sourceTypeIndex = sourceTypeIndex,
                                description = (meta and meta.description) or description or "",
                                creatureDisplayID = creatureDisplayID,
                                isCollected = isCollected,
                            })
                            totalCount = totalCount + 1
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return SafeLower(a.name) < SafeLower(b.name)
        end)
    end

    return grouped, totalCount
end

-- Toys: grouped by C_ToyBox source type. Returns { [catKey] = items[] } filtered by search and owned/missing.
local function GetFilteredToysGrouped(searchText, showCollected, showUncollected)
    local sourceGrouped = (WarbandNexus.GetToysDataGroupedBySourceType and WarbandNexus:GetToysDataGroupedBySourceType()) or {}
    local grouped = {}
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    for sourceIndex, group in pairs(sourceGrouped) do
        local catKey = SD.SOURCE_INDEX_TO_TOY_CAT[sourceIndex] or "unknown"
        if not grouped[catKey] then grouped[catKey] = {} end
        local items = group.items or {}
        for i = 1, #items do
            local item = items[i]
            if item and item.id then
                local isCollected = (item.collected == true) or (item.isCollected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    local name = item.name or tostring(item.id)
                    if query == "" or (SafeLower(name):find(query, 1, true)) then
                        grouped[catKey][#grouped[catKey] + 1] = item
                    end
                end
            end
        end
    end
    return grouped
end

local function BuildGroupedToyData(searchText, showCollected, showUncollected, optionalToys)
    local grouped = {}
    local nameIndex = {}
    for ci = 1, #SD.TOY_SOURCE_CATEGORIES do
        local cat = SD.TOY_SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    local allToys = (optionalToys and #optionalToys > 0) and optionalToys or (WarbandNexus.GetAllToysData and WarbandNexus:GetAllToysData()) or {}
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    local resolveSourceIndex = (WarbandNexus.GetToySourceTypeIndexForItem and function(id)
        return WarbandNexus:GetToySourceTypeIndexForItem(id)
    end) or function() return nil end

    for i = 1, #allToys do
        local d = allToys[i]
        if d and d.id then
            local name = d.name or tostring(d.id)
            local isCollected = (d.isCollected == true) or (d.collected == true)
            if (showC and isCollected) or (showU and not isCollected) then
                if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                    local sourceTypeIndex = d.sourceTypeIndex or resolveSourceIndex(d.id)
                    local catKey = SD.ClassifyBattlePetByAPI(nil, sourceTypeIndex)
                    if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        addToCategory(catKey, {
                            id = d.id,
                            name = name,
                            icon = d.icon or DEFAULT_ICON_TOY,
                            source = d.source or "",
                            sourceTypeIndex = sourceTypeIndex,
                            description = d.description or "",
                            isCollected = isCollected,
                            collected = isCollected,
                        })
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
    end
    return grouped
end

-- ============================================================================
-- DRAW MOUNTS CONTENT
-- Layout: LEFT = Header + Rows (scroll list), RIGHT = Model viewer (vertical, text inside same frame).
-- All in Factory containers; responsive width/height from window.
-- ============================================================================

local CONTENT_GAP = LAYOUT.CARD_GAP or 8

-- Per–sub-tab title block inside contentFrame (below search); reduces inner list/detail height.
local COLLECTIONS_SUBTAB_HEADER_H = 44
local COLLECTIONS_SUBTAB_HEADER_GAP = 8

local CONTENT_HEADER_LOCALE_KEYS = {
    achievements = { title = "COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS", sub = "COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS" },
    mounts = { title = "COLLECTIONS_CONTENT_TITLE_MOUNTS", sub = "COLLECTIONS_CONTENT_SUB_MOUNTS" },
    pets = { title = "COLLECTIONS_CONTENT_TITLE_PETS", sub = "COLLECTIONS_CONTENT_SUB_PETS" },
    toys = { title = "COLLECTIONS_CONTENT_TITLE_TOYS", sub = "COLLECTIONS_CONTENT_SUB_TOYS" },
    recent = { title = "COLLECTIONS_CONTENT_TITLE_RECENT", sub = "COLLECTIONS_CONTENT_SUB_RECENT" },
}

local function ApplyCollectionsContentHeader(contentFrame, tabKey, chFull)
    local loc = ns.L
    local keys = CONTENT_HEADER_LOCALE_KEYS[tabKey]
    local titlePlain = (keys and loc and loc[keys.title])
        or (tabKey == "achievements" and ((loc and loc["CATEGORY_ACHIEVEMENTS"]) or "Achievements"))
        or (tabKey == "mounts" and ((loc and loc["CATEGORY_MOUNTS"]) or "Mounts"))
        or (tabKey == "pets" and ((loc and loc["CATEGORY_PETS"]) or "Pets"))
        or (tabKey == "toys" and ((loc and loc["CATEGORY_TOYS"]) or "Toys"))
        or (tabKey == "recent" and ((loc and loc["COLLECTIONS_SUBTAB_RECENT"]) or "Recent"))
        or tostring(tabKey or "")
    local subPlain = (keys and loc and loc[keys.sub]) or ""

    local hdr = collectionsState._collectionsContentSubHeader
    if not hdr then
        hdr = Factory:CreateContainer(contentFrame, 120, COLLECTIONS_SUBTAB_HEADER_H, false)
        hdr._title = FontManager:CreateFontString(hdr, "header", "OVERLAY")
        hdr._title:SetPoint("TOPLEFT", hdr, "TOPLEFT", 4, -4)
        hdr._title:SetJustifyH("LEFT")
        hdr._subtitle = FontManager:CreateFontString(hdr, "subtitle", "OVERLAY")
        hdr._subtitle:SetPoint("TOPLEFT", hdr._title, "BOTTOMLEFT", 0, -2)
        hdr._subtitle:SetJustifyH("LEFT")
        hdr._subtitle:SetTextColor(1, 1, 1, 1)
        collectionsState._collectionsContentSubHeader = hdr
    end
    hdr:SetParent(contentFrame)
    hdr:ClearAllPoints()
    hdr:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    hdr:SetHeight(COLLECTIONS_SUBTAB_HEADER_H)
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = format("%02x%02x%02x", r * 255, g * 255, b * 255)
    hdr._title:SetText("|cff" .. hexColor .. titlePlain .. "|r")
    hdr._subtitle:SetText(subPlain)
    hdr._subtitle:SetShown(subPlain ~= "")
    hdr:SetFrameLevel((contentFrame:GetFrameLevel() or 0) + 3)
    hdr:Show()

    local headerBlockH = COLLECTIONS_SUBTAB_HEADER_H + COLLECTIONS_SUBTAB_HEADER_GAP
    local innerCh = math.max(80, (chFull or 400) - headerBlockH)
    return headerBlockH, innerCh
end

-- Result container: only one sub-tab's content is visible. Hide all result-area frames before drawing current tab.
local function HideAllCollectionsResultFrames()
    if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
    if collectionsState.mountListContainer then collectionsState.mountListContainer:Hide() end
    if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Hide() end
    if collectionsState.viewerContainer then collectionsState.viewerContainer:Hide() end
    if collectionsState.modelViewer then
        collectionsState.modelViewer:SetMount(nil)
        collectionsState.modelViewer:SetPet(nil)
        collectionsState.modelViewer:SetMountInfo(nil)
        collectionsState.modelViewer:SetPetInfo(nil)
        collectionsState.modelViewer:Hide()
    end
    if collectionsState.petListContainer then collectionsState.petListContainer:Hide() end
    if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Hide() end
    if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Hide() end
    if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Hide() end
    if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Hide() end
    if collectionsState.toyListContainer then collectionsState.toyListContainer:Hide() end
    if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Hide() end
    if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Hide() end
    if collectionsState.toyDetailScrollBarContainer then collectionsState.toyDetailScrollBarContainer:Hide() end
    if collectionsState.recentTabPanel then collectionsState.recentTabPanel:Hide() end
    if collectionsState.collectionRightColumn then collectionsState.collectionRightColumn:Hide() end
    if collectionsState.collectionProgressFrame then collectionsState.collectionProgressFrame:Hide() end
    if collectionsState._collectionsContentSubHeader then collectionsState._collectionsContentSubHeader:Hide() end
end

---Recent sub-tab: four equal cards (Achievements, Mounts, Pets, Toys), recent obtains per column; tall lists extend tab height and use the main window vertical scroll (no nested scrollbars).
local function RecentEntryNameMatches(e, qlower)
    if not e or type(e.name) ~= "string" or e.name == "" then return false end
    if not qlower then return true end
    local nm = e.name
    if issecretvalue and issecretvalue(nm) then return false end
    return SafeLower(nm):find(qlower, 1, true) ~= nil
end

-- Strip legacy "Name — Realm" payloads for Recent display (realm-free; matches CollectiblePayloadObtainedBy).
local UTF8_EM_DASH = "\226\128\148"
local function RecentCharacterLabelForDisplay(ob)
    if not ob or ob == "" then return nil end
    if issecretvalue and issecretvalue(ob) then return nil end
    local emSep = " " .. UTF8_EM_DASH .. " "
    local cut = ob:find(emSep, 1, true)
    if cut then
        return ob:sub(1, cut - 1)
    end
    cut = ob:find(" - ", 1, true)
    if cut then
        return ob:sub(1, cut - 1)
    end
    return ob
end

---@param maxN number|nil nil = all matches within DB (retention-pruned list)
local function RecentPickForType(db, typ, qlower, maxN)
    local out = {}
    if type(db) ~= "table" then return out end
    for i = 1, #db do
        local e = db[i]
        if e and e.type == typ and RecentEntryNameMatches(e, qlower) then
            out[#out + 1] = e
            if maxN and maxN > 0 and #out >= maxN then break end
        end
    end
    return out
end

local function ClearRecentPanelChildren(panel)
    if not panel then return end
    local ch = { panel:GetChildren() }
    for i = 1, #ch do
        ch[i]:SetParent(nil)
        ch[i]:Hide()
    end
end

local function GetRecentSectionCategoryIcon(ctype)
    if ctype == "achievement" then
        return "UI-Achievement-Shield-NoPoints", true
    elseif ctype == "mount" then
        return DEFAULT_ICON_MOUNT, false
    elseif ctype == "pet" then
        return DEFAULT_ICON_PET, false
    elseif ctype == "toy" then
        return DEFAULT_ICON_TOY, false
    end
    return DEFAULT_ICON_ACHIEVEMENT, false
end

local function GetRecentEntryDisplayIcon(ctype, id)
    if WarbandNexus and WarbandNexus.GetPlanDisplayIcon and id ~= nil then
        local plan = { type = ctype }
        if ctype == "achievement" then plan.achievementID = id
        elseif ctype == "mount" then plan.mountID = id
        elseif ctype == "pet" then plan.speciesID = id
        elseif ctype == "toy" then plan.itemID = id
        else return DEFAULT_ICON_ACHIEVEMENT
        end
        return WarbandNexus:GetPlanDisplayIcon(plan)
    end
    local path = select(1, GetRecentSectionCategoryIcon(ctype))
    if ctype == "achievement" then return DEFAULT_ICON_ACHIEVEMENT end
    return path or DEFAULT_ICON_ACHIEVEMENT
end

local function RecentRowNavigateToEntry(ctype, id)
    if not ctype or id == nil then return end
    if ctype == "achievement" then
        collectionsState.currentSubTab = "achievements"
        ns._sessionCollectionsSubTab = "achievements"
        collectionsState.selectedAchievementID = id
    elseif ctype == "mount" then
        collectionsState.currentSubTab = "mounts"
        ns._sessionCollectionsSubTab = "mounts"
        collectionsState.selectedMountID = id
    elseif ctype == "pet" then
        collectionsState.currentSubTab = "pets"
        ns._sessionCollectionsSubTab = "pets"
        collectionsState.selectedPetID = id
    elseif ctype == "toy" then
        collectionsState.currentSubTab = "toys"
        ns._sessionCollectionsSubTab = "toys"
        collectionsState.selectedToyID = id
    else
        return
    end
    WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "collections", skipCooldown = true })
end

local function DrawRecentContent(contentFrame)
    if not contentFrame then return end
    HideAllCollectionsResultFrames()
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local viewCap = collectionsState.recentViewportCap or ch

    local headerBlockH = select(1, ApplyCollectionsContentHeader(contentFrame, "recent", viewCap))

    local panel = collectionsState.recentTabPanel
    if not panel then
        panel = Factory:CreateContainer(contentFrame, cw, innerChViewport, false)
        collectionsState.recentTabPanel = panel
    end
    panel:SetParent(contentFrame)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
    panel:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    panel:Show()

    if WarbandNexus.PruneCollectionsRecentObtained then
        WarbandNexus:PruneCollectionsRecentObtained()
    end

    local db = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.collectionsRecentObtained
    local loc = ns.L
    local qraw = collectionsState.searchText or ""
    local qlower
    if qraw and not (issecretvalue and issecretvalue(qraw)) and qraw ~= "" then
        qlower = qraw:lower()
    end

    local searchEmptyTxt = (loc and loc["COLLECTIONS_RECENT_SEARCH_EMPTY"]) or "No matching entries."
    local noneLine = (loc and loc["COLLECTIONS_RECENT_SECTION_NONE"]) or "No entries yet."
    local inset = CONTENT_INSET or 8
    local gap = CARD_GAP

    ClearRecentPanelChildren(panel)

    local innerW = math.max(1, cw - 2 * inset)
    local cardW = (innerW - 3 * gap) / 4
    local headerBand = RECENT_CARD_HEADER_PAD + RECENT_CARD_ICON + 6
    local listTopPad = headerBand + 4
    local RECENT_ROW_H_SUB = ROW_HEIGHT + 14

    local pickedLists = {}
    for si = 1, #RECENT_SECTION_ORDER do
        pickedLists[si] = RecentPickForType(db, RECENT_SECTION_ORDER[si], qlower, nil)
    end

    --- Account-wide achievement completed but not flagged as earned by the current character (hide earner UI).
    local function RecentAchievementSuppressEarner(achievementID)
        if not achievementID then return false end
        local ok, _, _, _, completed, _, _, _, _, _, _, _, wasEarnedByMe = pcall(GetAchievementInfo, achievementID)
        if not ok then return false end
        return completed == true and wasEarnedByMe == false
    end

    --- Pixel height of the scrollable list block inside one Recent card (rows only; excludes header band).
    local function RecentColumnListPixelHeight(typ, picked)
        local yList = 0
        if qlower and #picked == 0 then
            return ROW_HEIGHT + 2
        elseif #picked == 0 then
            return ROW_HEIGHT + 2
        end
        for j = 1, #picked do
            local e = picked[j]
            local ob = RecentCharacterLabelForDisplay(e.obtainedBy)
            local suppressEarner = (typ == "achievement" and e.id and RecentAchievementSuppressEarner(e.id))
            local rowH = ROW_HEIGHT
            if ob and ob ~= "" and not suppressEarner then
                rowH = RECENT_ROW_H_SUB
            end
            yList = yList + rowH + 2
        end
        return yList
    end

    local maxColContent = 0
    for si = 1, #RECENT_SECTION_ORDER do
        local typ = RECENT_SECTION_ORDER[si]
        local picked = pickedLists[si]
        local colTotal = listTopPad + RecentColumnListPixelHeight(typ, picked) + RECENT_CARD_HEADER_PAD
        if colTotal > maxColContent then
            maxColContent = colTotal
        end
    end

    local inner_viewport = math.max(1, viewCap - headerBlockH)
    local minCardFill = math.max(160, inner_viewport - 2 * inset)
    local cardH = math.max(minCardFill, maxColContent)
    local finalContentH = math.max(viewCap, headerBlockH + inset + cardH + inset)

    contentFrame:SetHeight(finalContentH)
    ApplyCollectionsContentHeader(contentFrame, "recent", finalContentH)

    local rowVisualIndex = 0
    for si = 1, #RECENT_SECTION_ORDER do
        local typ = RECENT_SECTION_ORDER[si]
        local picked = pickedLists[si]
        local cat = CollectionsRecentCategoryLabel(typ)
        local iconTex, iconIsAtlas = GetRecentSectionCategoryIcon(typ)
        local defaultEmptyIcon = (typ == "achievement" and DEFAULT_ICON_ACHIEVEMENT)
            or (typ == "mount" and DEFAULT_ICON_MOUNT)
            or (typ == "pet" and DEFAULT_ICON_PET)
            or DEFAULT_ICON_TOY

        local card = CreateCard(panel, cardH)
        card:SetParent(panel)
        card:SetSize(cardW, cardH)
        card:SetPoint("TOPLEFT", panel, "TOPLEFT", inset + (si - 1) * (cardW + gap), -inset)
        card:Show()

        local iconFr = CreateIcon(card, iconTex, RECENT_CARD_ICON, iconIsAtlas, nil, true)
        if iconFr then
            iconFr:SetPoint("TOPLEFT", card, "TOPLEFT", RECENT_CARD_HEADER_PAD, -RECENT_CARD_HEADER_PAD)
            iconFr:Show()
        end

        local resetBtn = Factory:CreateButton(card, 22, 22, true)
        resetBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -RECENT_CARD_HEADER_PAD, -RECENT_CARD_HEADER_PAD + 1)
        resetBtn:SetFrameLevel((card:GetFrameLevel() or 0) + 8)
        local resetTex = resetBtn:CreateTexture(nil, "ARTWORK")
        resetTex:SetAllPoints()
        local resetAtlasOk = pcall(function() resetTex:SetAtlas("talents-button-reset", true) end)
        if not resetAtlasOk then
            resetTex:SetTexture("Interface\\Buttons\\UI-RefreshButton")
        end
        resetBtn:SetScript("OnEnter", function(self)
            GameTooltip:ClearLines()
            if ns.UI_SetGameTooltipSmartOwner then
                ns.UI_SetGameTooltipSmartOwner(self, 0, 0)
            else
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            end
            GameTooltip:SetText((loc and loc["COLLECTIONS_RECENT_CARD_RESET_TOOLTIP"]) or "Clear recent entries for this category", 1, 1, 1)
            GameTooltip:Show()
        end)
        resetBtn:SetScript("OnLeave", GameTooltip_Hide)
        resetBtn:SetScript("OnClick", function()
            if WarbandNexus.ClearCollectionsRecentObtainedForType then
                WarbandNexus:ClearCollectionsRecentObtainedForType(typ)
            end
            WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                tab = "collections",
                skipCooldown = true,
                instantPopulate = true,
            })
        end)

        local titleFs = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
        titleFs:SetPoint("TOPLEFT", card, "TOPLEFT", RECENT_CARD_HEADER_PAD + RECENT_CARD_ICON + 6, -RECENT_CARD_HEADER_PAD - 2)
        titleFs:SetPoint("TOPRIGHT", resetBtn, "TOPLEFT", -6, -2)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetText(cat)
        titleFs:SetTextColor(1, 0.85, 0.45, 1)

        local listWInner = math.max(1, cardW - RECENT_CARD_HEADER_PAD * 2)
        local listHost = Factory:CreateContainer(card, listWInner, 1, false)
        listHost:SetPoint("TOPLEFT", card, "TOPLEFT", RECENT_CARD_HEADER_PAD, -listTopPad)
        listHost:Show()

        local yList = 0
        local function addRow(iconPath, nameRich, rightTime, clickable, onClick, tooltipBuilder, subtitleRich, rowH)
            rowVisualIndex = rowVisualIndex + 1
            rowH = rowH or ROW_HEIGHT
            local row = Factory:CreateCollectionListRow(listHost, rowH)
            row:SetParent(listHost)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, -yList)
            row:SetWidth(listWInner)
            Factory:ApplyCollectionListRowContent(row, rowVisualIndex, iconPath, nameRich, clickable, false, onClick, rightTime, subtitleRich)
            if tooltipBuilder then
                row:SetScript("OnEnter", function(self)
                    GameTooltip:ClearLines()
                    if ns.UI_SetGameTooltipSmartOwner then
                        ns.UI_SetGameTooltipSmartOwner(self, 0, 0)
                    else
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    end
                    tooltipBuilder(GameTooltip)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", GameTooltip_Hide)
            else
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
            end
            yList = yList + rowH + 2
        end

        if qlower and #picked == 0 then
            addRow(defaultEmptyIcon, "|cff888888" .. searchEmptyTxt .. "|r", nil, false, nil, nil, nil, ROW_HEIGHT)
        elseif #picked == 0 then
            addRow(defaultEmptyIcon, "|cff888888" .. noneLine .. "|r", nil, false, nil, nil, nil, ROW_HEIGHT)
        else
            for j = 1, #picked do
                local e = picked[j]
                local nm = e.name or ""
                if issecretvalue and issecretvalue(nm) then
                    nm = (loc and loc["HIDDEN_ACHIEVEMENT"]) or "—"
                end
                local rel = FormatCollectionsRecentRelativeTime(e.t)
                local iconPath = GetRecentEntryDisplayIcon(typ, e.id)
                local idCopy, typCopy, tsCopy, nmCopy = e.id, typ, e.t, nm
                local ob = RecentCharacterLabelForDisplay(e.obtainedBy)
                local suppressEarner = (typCopy == "achievement" and idCopy and RecentAchievementSuppressEarner(idCopy))
                local subLine = nil
                local rowH = ROW_HEIGHT
                if ob and ob ~= "" and not suppressEarner then
                    local cc = (ns.UI_GetClassColorHexForWarbandCharacter and ns.UI_GetClassColorHexForWarbandCharacter(ob))
                        or "|cffaaaaaa"
                    subLine = format((loc and loc["COLLECTIONS_RECENT_ROW_BY"]) or "By %s", cc .. ob .. "|r")
                    rowH = RECENT_ROW_H_SUB
                end
                local nameRich = COLLECTED_COLOR .. nm .. "|r"

                local function buildTooltip(tt)
                    local hdrDim = 0.52
                    tt:SetText("|cffffd133" .. nmCopy .. "|r")
                    tt:AddLine((loc and loc["COLLECTIONS_RECENT_TOOLTIP_SECTION_CATEGORY"]) or "Category", hdrDim, hdrDim, hdrDim)
                    tt:AddLine(cat, 0.82, 0.82, 0.88)
                    if typCopy == "achievement" and idCopy then
                        tt:AddLine((loc and loc["COLLECTIONS_RECENT_TOOLTIP_SECTION_PROGRESS"]) or "Progress", hdrDim, hdrDim, hdrDim)
                        local ok, _, _, points, completed = pcall(GetAchievementInfo, idCopy)
                        if ok and points and points > 0 then
                            tt:AddLine(format("%d %s", points, (loc and loc["POINTS_LABEL"]) or "Points"), 1, 0.85, 0.45)
                        end
                        if ok and completed then
                            tt:AddLine((loc and loc["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMPLETE"]) or "Completed.", 0.35, 1, 0.45)
                        end
                        if suppressEarner then
                            tt:AddLine((loc and loc["COLLECTIONS_RECENT_ACH_HIDE_ALT_EARNED"]) or "Completed on account before this character.", 0.62, 0.62, 0.68)
                        end
                    end
                    if ob and ob ~= "" and not suppressEarner then
                        tt:AddLine((loc and loc["COLLECTIONS_RECENT_TOOLTIP_SECTION_CHARACTER"]) or "Character", hdrDim, hdrDim, hdrDim)
                        local cc = (ns.UI_GetClassColorHexForWarbandCharacter and ns.UI_GetClassColorHexForWarbandCharacter(ob))
                            or "|cffaaaaaa"
                        local fmtKey = (typCopy == "achievement") and "RECENT_TOOLTIP_ACHIEVEMENT_EARNED_BY" or "RECENT_TOOLTIP_EARNED_BY"
                        local fmt = (loc and loc[fmtKey]) or ((typCopy == "achievement") and "Earned by %s" or "Obtained by %s")
                        tt:AddLine(format(fmt, cc .. ob .. "|r"))
                    end
                    tt:AddLine((loc and loc["COLLECTIONS_RECENT_TOOLTIP_SECTION_TIME"]) or "Recorded", hdrDim, hdrDim, hdrDim)
                    if tsCopy and tsCopy > 0 then
                        local abs = date("%Y-%m-%d %H:%M", tsCopy)
                        tt:AddLine(format("%s  |cff888888(%s)|r", abs, rel), 0.72, 0.72, 0.76)
                    elseif rel and rel ~= "" then
                        tt:AddLine(rel, 0.72, 0.72, 0.76)
                    end
                end

                addRow(iconPath, nameRich, "|cff888888" .. rel .. "|r", true, function()
                    RecentRowNavigateToEntry(typCopy, idCopy)
                end, buildTooltip, subLine, rowH)
            end
        end

        listHost:SetHeight(math.max(yList, 1))
    end
end

local function SetCollectionProgress(current, total)
    local bar = collectionsState.collectionProgressBar
    local lbl = collectionsState.collectionProgressLabel
    if bar then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue((total and total > 0 and current) and (current / total) or 0)
    end
    if lbl then
        lbl:SetText((current ~= nil and total ~= nil) and (tostring(current) .. " / " .. tostring(total)) or "— / —")
    end
end

local function EnsureCollectionProgressBar(rightCol)
    if collectionsState.collectionProgressFrame or not rightCol then return end
    local barWidth = (rightCol:GetWidth() and (rightCol:GetWidth() - 4)) or 200
    local pr = Factory:CreateContainer(rightCol, math.max(64, barWidth), PROGRESS_ROW_HEIGHT, false)
    if not pr then
        pr = CreateFrame("Frame", nil, rightCol)
        pr:SetHeight(PROGRESS_ROW_HEIGHT)
    end
    pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
    local barHeight = 22
    local barWrapper = CreateFrame("Frame", nil, pr, "BackdropTemplate")
    barWrapper:SetAllPoints(pr)
    if ApplyVisuals then
        ApplyVisuals(barWrapper, {0.06, 0.06, 0.08, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
    end
    local innerW = math.max(1, barWidth - (BAR_INSET * 2))
    local innerH = math.max(1, barHeight - (BAR_INSET * 2))
    local statusBar = ns.UI_CreateStatusBar and ns.UI_CreateStatusBar(barWrapper, innerW, innerH, {0.06, 0.06, 0.08, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5}, true)
    if statusBar then
        statusBar:ClearAllPoints()
        statusBar:SetPoint("TOPLEFT", barWrapper, "TOPLEFT", BAR_INSET, -BAR_INSET)
        statusBar:SetPoint("BOTTOMRIGHT", barWrapper, "BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
        statusBar:SetMinMaxValues(0, 1)
        statusBar:SetValue(0)
        local barTexture = statusBar:GetStatusBarTexture()
        if barTexture then barTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85) end
    end
    collectionsState.collectionProgressBar = statusBar
    local progressFs = FontManager:CreateFontString(pr, "body", "OVERLAY")
    if progressFs then
        if statusBar then
            progressFs:SetParent(statusBar)
            progressFs:SetDrawLayer("OVERLAY", 7)
            progressFs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
        else
            progressFs:SetPoint("CENTER", pr, "CENTER", 0, 0)
        end
        progressFs:SetJustifyH("CENTER")
        progressFs:SetJustifyV("MIDDLE")
        progressFs:SetTextColor(1, 1, 1)
        progressFs:SetText("— / —")
    end
    collectionsState.collectionProgressLabel = progressFs
    collectionsState.collectionProgressFrame = pr
end

local function DrawMountsContent(contentFrame)
    if collectionsState._drawMountsContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawMountsContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawMountsContentBusy = true
    collectionsState._mountsDrawGen = (collectionsState._mountsDrawGen or 0) + 1
    local drawGen = collectionsState._mountsDrawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    -- Layout: LEFT = list, gap, scrollbar, gap, RIGHT = 3D viewer (equal SCROLLBAR_SIDE_GAP each side of scrollbar).
    local listContentWidth = math.floor(cw * 0.50) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local viewerWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()
    local headerBlockH, innerCh = ApplyCollectionsContentHeader(contentFrame, "mounts", ch)

    -- LEFT CONTAINER: List only (scroll frame fills it; scrollbar ayrı sütunda)
    if not collectionsState.mountListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        listContainer:Show()
        collectionsState.mountListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.mountListScrollFrame = scrollFrame

        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.mountListScrollChild = scrollChild

        -- SCROLLBAR REZERVE: Liste ile 3D view arasında görünür (eşit boşluk).
        local scrollBarContainer = EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP)
        collectionsState.mountListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        collectionsState.mountListContainer:SetSize(listContentWidth, innerCh)
        collectionsState.mountListScrollBarContainer = EnsureListScrollBarContainer(
            collectionsState.mountListScrollBarContainer,
            contentFrame,
            collectionsState.mountListContainer,
            scrollBarColumnWidth,
            innerCh,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = collectionsState.mountListScrollFrame and collectionsState.mountListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, collectionsState.mountListScrollBarContainer, CONTAINER_INSET)
        end
    end
    collectionsState.mountListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + 3D viewer (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, viewerWidth), math.max(1, innerCh or 400), false)
        rightCol:SetPoint("TOPLEFT", collectionsState.mountListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
        rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.mountListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    if not collectionsState.modelViewer then
        local viewerContainer = Factory:CreateContainer(rightCol, viewerWidth, detailH, true)
        viewerContainer:ClearAllPoints()
        if pr then
            viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        viewerContainer:Show()
        collectionsState.viewerContainer = viewerContainer
        ApplyDetailAccentVisuals(viewerContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(viewerContainer, "mount")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(viewerContainer:GetFrameLevel() + 5)
            collectionsState.mountDetailEmptyOverlay = emptyOverlay
        end
        local mv = CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        collectionsState.modelViewer = mv
        if not collectionsState.selectedMountID then
            mv:Hide()
            if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
        end
    else
        if collectionsState.viewerContainer then
            collectionsState.viewerContainer:SetParent(rightCol)
            collectionsState.viewerContainer:ClearAllPoints()
            if pr then
                collectionsState.viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                collectionsState.viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            collectionsState.viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
            ApplyDetailAccentVisuals(collectionsState.viewerContainer)
            if not collectionsState.mountDetailEmptyOverlay then
                local emptyOverlay = CreateDetailEmptyOverlay(collectionsState.viewerContainer, "mount")
                if emptyOverlay then
                    emptyOverlay:SetFrameLevel(collectionsState.viewerContainer:GetFrameLevel() + 5)
                    collectionsState.mountDetailEmptyOverlay = emptyOverlay
                end
            end
        end
        collectionsState.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
    end

    local function onSelectMount(mountID, name, icon, source, creatureDisplayID, description, isCollected)
        collectionsState.selectedMountID = mountID
        if collectionsState.mountDetailEmptyOverlay then
            collectionsState.mountDetailEmptyOverlay:SetShown(not mountID)
        end
        if collectionsState.modelViewer then
            collectionsState.modelViewer:SetShown(mountID ~= nil)
            if mountID then
                collectionsState.modelViewer:SetMount(mountID, creatureDisplayID)
                collectionsState.modelViewer:SetMountInfo(mountID, name, icon, source, description, isCollected)
            else
                collectionsState.modelViewer:SetMount(nil)
                collectionsState.modelViewer:SetMountInfo(nil)
            end
        end
    end
    if collectionsState.modelViewer and not collectionsState.selectedMountID then
        if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
        collectionsState.modelViewer:Hide()
    else
        if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end
        if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
    end
    if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end

    -- Sync model viewer content with current tab: on Mounts show only mount or empty, never previous pet.
    if collectionsState.modelViewer then
        if collectionsState.selectedMountID then
            local mid = collectionsState.selectedMountID
            local md
            local am = collectionsState._cachedMountsData
            if am then
                for i = 1, #am do
                    if am[i].id == mid then md = am[i]; break end
                end
            end
            if md then
                collectionsState.modelViewer:SetMount(mid, md.creatureDisplayID)
                collectionsState.modelViewer:SetMountInfo(mid, md.name, md.icon, md.source, md.description, md.isCollected)
            else
                collectionsState.modelViewer:SetMount(mid, nil)
                collectionsState.modelViewer:SetMountInfo(mid, nil, nil, nil, nil, nil)
            end
        else
            collectionsState.modelViewer:SetMount(nil)
            collectionsState.modelViewer:SetPet(nil)
            collectionsState.modelViewer:SetMountInfo(nil)
            collectionsState.modelViewer:SetPetInfo(nil)
        end
    end

    -- Loading only when a scan is in progress or we have not yet completed initial fetch (no cache).
    -- Cache is set even when list is empty so we don't show loading forever for 0 mounts.
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allMounts = collectionsState._cachedMountsData
    local dataReady = (allMounts ~= nil)
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if collectionsState.mountListContainer then collectionsState.mountListContainer:Hide() end
        if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Hide() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Hide() end
        -- No cache and no scan in progress: fetch data after short delay so tab switch stays responsive.
        if not (loadingState and loadingState.isLoading) and not dataReady then
            C_Timer.After(COLLECTION_HEAVY_DELAY, function()
                if collectionsState._mountsDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "mounts" then return end
                if not contentFrame or not contentFrame:IsVisible() then return end
                local am = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
                collectionsState._cachedMountsData = am
                if #am == 0 then
                    RequestCollectionFillFromUI()
                end
                local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
                local collected = (apiCounts and apiCounts.mounts and apiCounts.mounts.collected) or 0
                local total = (apiCounts and apiCounts.mounts and apiCounts.mounts.total) or 0
                SetCollectionProgress(collected, total)
                if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
                if collectionsState.mountListContainer then collectionsState.mountListContainer:Show() end
                if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Show() end
                if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
                if not collectionsState.selectedMountID then
                    if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
                else
                    if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
                end
                local listW = listContentWidth - (CONTAINER_INSET * 2)
                local sch = collectionsState.mountListScrollChild
                -- Build and populate even when am is empty (show empty list; EnsureCollectionData may fill store later)
                RunChunkedMountBuild(
                    am,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                        if not sch or not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedMountData = grouped
                        C_Timer.After(0, function()
                            if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulateMountList(sch, listW, grouped, collectionsState.collapsedHeadersMounts, collectionsState.selectedMountID, onSelectMount, contentFrame, DrawMountsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    else
        if collectionsState.loadingPanel then
            collectionsState.loadingPanel:Hide()
        end
        if collectionsState.mountListContainer then collectionsState.mountListContainer:Show() end
        if collectionsState.mountListScrollBarContainer then collectionsState.mountListScrollBarContainer:Show() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
        if not collectionsState.selectedMountID then
            if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Show() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
        else
            if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.mountListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.mounts and apiCounts.mounts.collected) or 0
        local total = (apiCounts and apiCounts.mounts and apiCounts.mounts.total) or 0
        SetCollectionProgress(collected, total)
        local searchUnchanged = (collectionsState._mountLastSearchText == (collectionsState.searchText or ""))
            and (collectionsState._mountLastShowCollected == collectionsState.showCollected)
            and (collectionsState._mountLastShowUncollected == collectionsState.showUncollected)
        -- Tab switch back: list already populated and search/filter unchanged, only refresh visible range (no repopulate).
        if sch and collectionsState._mountFlatList and collectionsState._lastGroupedMountData and searchUnchanged then
            if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
            end
            if collectionsState._mountListRefreshVisible then
                collectionsState._mountListRefreshVisible()
            end
        else
            -- First time or list not built: chunked build then populate.
            C_Timer.After(0, function()
                if collectionsState._mountsDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "mounts" then return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then return end
                RunChunkedMountBuild(
                    allMounts,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                        if not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedMountData = grouped
                        collectionsState._mountLastSearchText = collectionsState.searchText or ""
                        collectionsState._mountLastShowCollected = collectionsState.showCollected
                        collectionsState._mountLastShowUncollected = collectionsState.showUncollected
                        C_Timer.After(0, function()
                            if collectionsState._mountsDrawGen ~= drawGen or collectionsState.currentSubTab ~= "mounts" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulateMountList(sch, listW, grouped, collectionsState.collapsedHeadersMounts, collectionsState.selectedMountID, onSelectMount, contentFrame, DrawMountsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.mountListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.mountListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    end
    collectionsState._drawMountsContentBusy = nil
end

-- DrawPetsContent: same layout as mounts, uses pet API and list.
local function DrawPetsContent(contentFrame)
    if collectionsState._drawPetsContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawPetsContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawPetsContentBusy = true
    collectionsState._petDrawGen = (collectionsState._petDrawGen or 0) + 1
    local drawGen = collectionsState._petDrawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth = math.floor(cw * 0.50) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local viewerWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()
    local headerBlockH, innerCh = ApplyCollectionsContentHeader(contentFrame, "pets", ch)

    -- LEFT CONTAINER: Pet list
    if not collectionsState.petListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        listContainer:Show()
        collectionsState.petListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.petListScrollFrame = scrollFrame

        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.petListScrollChild = scrollChild

        local scrollBarContainer = EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP)
        collectionsState.petListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        collectionsState.petListContainer:SetSize(listContentWidth, innerCh)
        collectionsState.petListScrollBarContainer = EnsureListScrollBarContainer(
            collectionsState.petListScrollBarContainer,
            contentFrame,
            collectionsState.petListContainer,
            scrollBarColumnWidth,
            innerCh,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = collectionsState.petListScrollFrame and collectionsState.petListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, collectionsState.petListScrollBarContainer, CONTAINER_INSET)
        end
    end
    collectionsState.petListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + 3D viewer (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, viewerWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.petListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    if not collectionsState.modelViewer then
        local viewerContainer = Factory:CreateContainer(rightCol, viewerWidth, detailH, true)
        viewerContainer:ClearAllPoints()
        if pr then
            viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        viewerContainer:Show()
        collectionsState.viewerContainer = viewerContainer
        ApplyDetailAccentVisuals(viewerContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(viewerContainer, "pet")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(viewerContainer:GetFrameLevel() + 5)
            collectionsState.petDetailEmptyOverlay = emptyOverlay
        end
        local mv = CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        collectionsState.modelViewer = mv
        if not collectionsState.selectedPetID then
            mv:Hide()
            if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
        end
    else
        if collectionsState.viewerContainer then
            collectionsState.viewerContainer:SetParent(rightCol)
            collectionsState.viewerContainer:ClearAllPoints()
            if pr then
                collectionsState.viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                collectionsState.viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            collectionsState.viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
            ApplyDetailAccentVisuals(collectionsState.viewerContainer)
            if not collectionsState.petDetailEmptyOverlay then
                local emptyOverlay = CreateDetailEmptyOverlay(collectionsState.viewerContainer, "pet")
                if emptyOverlay then
                    emptyOverlay:SetFrameLevel(collectionsState.viewerContainer:GetFrameLevel() + 5)
                    collectionsState.petDetailEmptyOverlay = emptyOverlay
                end
            end
        end
        collectionsState.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
    end

    local function onSelectPet(speciesID, name, icon, source, creatureDisplayID, description, isCollected)
        collectionsState.selectedPetID = speciesID
        if collectionsState.petDetailEmptyOverlay then
            collectionsState.petDetailEmptyOverlay:SetShown(not speciesID)
        end
        if collectionsState.modelViewer then
            collectionsState.modelViewer:SetShown(speciesID ~= nil)
            if speciesID then
                collectionsState.modelViewer:SetPet(speciesID, creatureDisplayID)
                collectionsState.modelViewer:SetPetInfo(speciesID, name, icon, source, description, isCollected)
            else
                collectionsState.modelViewer:SetPet(nil)
                collectionsState.modelViewer:SetPetInfo(nil)
            end
        end
    end
    if collectionsState.modelViewer and not collectionsState.selectedPetID then
        if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
        collectionsState.modelViewer:Hide()
    else
        if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end
        if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
    end
    if collectionsState.mountDetailEmptyOverlay then collectionsState.mountDetailEmptyOverlay:Hide() end

    -- Sync model viewer content with current tab: on Pets show only pet or empty, never previous mount.
    if collectionsState.modelViewer then
        if collectionsState.selectedPetID then
            local sid = collectionsState.selectedPetID
            local pd
            local ap = collectionsState._cachedPetsData
            if ap then
                for i = 1, #ap do
                    if ap[i].id == sid then pd = ap[i]; break end
                end
            end
            if pd then
                collectionsState.modelViewer:SetPet(sid, pd.creatureDisplayID)
                collectionsState.modelViewer:SetPetInfo(sid, pd.name, pd.icon, pd.source, pd.description, pd.isCollected)
            else
                collectionsState.modelViewer:SetPet(sid, nil)
                collectionsState.modelViewer:SetPetInfo(sid, nil, nil, nil, nil, nil)
            end
        else
            collectionsState.modelViewer:SetMount(nil)
            collectionsState.modelViewer:SetPet(nil)
            collectionsState.modelViewer:SetMountInfo(nil)
            collectionsState.modelViewer:SetPetInfo(nil)
        end
    end

    -- Never call GetAllPetsData() in the tab-click frame: defer to next frame to avoid 1s freeze.
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allPets
    if collectionsState._cachedPetsData and #collectionsState._cachedPetsData > 0 then
        allPets = collectionsState._cachedPetsData
    else
        allPets = nil
    end
    local dataReady = allPets and #allPets > 0
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if collectionsState.petListContainer then collectionsState.petListContainer:Hide() end
        if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Hide() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Hide() end
        if not (loadingState and loadingState.isLoading) and not dataReady then
            C_Timer.After(COLLECTION_HEAVY_DELAY, function()
                if collectionsState._petDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "pets" then return end
                if not contentFrame or not contentFrame:IsVisible() then return end
                local ap = (WarbandNexus.GetAllPetsData and WarbandNexus:GetAllPetsData()) or {}
                if #ap > 0 then
                    collectionsState._cachedPetsData = ap
                else
                    RequestCollectionFillFromUI()
                end
                local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
                local collected = (apiCounts and apiCounts.pets and apiCounts.pets.uniqueSpecies) or 0
                local total = (apiCounts and apiCounts.pets and apiCounts.pets.totalSpecies) or 0
                SetCollectionProgress(collected, total)
                if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
                if collectionsState.petListContainer then collectionsState.petListContainer:Show() end
                if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Show() end
                if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
                if not collectionsState.selectedPetID then
                    if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
                else
                    if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end
                    if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
                end
                local listW = listContentWidth - (CONTAINER_INSET * 2)
                local sch = collectionsState.petListScrollChild
                RunChunkedPetBuild(
                    ap,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                        if not sch or not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedPetData = grouped
                        C_Timer.After(0, function()
                            if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulatePetList(sch, listW, grouped, collectionsState.collapsedHeadersPets, collectionsState.selectedPetID, onSelectPet, contentFrame, DrawPetsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    else
        if collectionsState.loadingPanel then
            collectionsState.loadingPanel:Hide()
        end
        if collectionsState.petListContainer then collectionsState.petListContainer:Show() end
        if collectionsState.petListScrollBarContainer then collectionsState.petListScrollBarContainer:Show() end
        if collectionsState.viewerContainer then collectionsState.viewerContainer:Show() end
        if not collectionsState.selectedPetID then
            if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Show() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Hide() end
        else
            if collectionsState.petDetailEmptyOverlay then collectionsState.petDetailEmptyOverlay:Hide() end
            if collectionsState.modelViewer then collectionsState.modelViewer:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.petListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.pets and apiCounts.pets.uniqueSpecies) or 0
        local total = (apiCounts and apiCounts.pets and apiCounts.pets.totalSpecies) or 0
        SetCollectionProgress(collected, total)
        local searchUnchanged = (collectionsState._petLastSearchText == (collectionsState.searchText or ""))
            and (collectionsState._petLastShowCollected == collectionsState.showCollected)
            and (collectionsState._petLastShowUncollected == collectionsState.showUncollected)
        -- Tab switch back: list already populated and search/filter unchanged, only refresh visible range (no repopulate).
        if sch and collectionsState._petFlatList and collectionsState._lastGroupedPetData and searchUnchanged then
            if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
            end
            if collectionsState._petListRefreshVisible then
                collectionsState._petListRefreshVisible()
            end
        else
            -- First time or list not built: chunked build then populate.
            C_Timer.After(0, function()
                if collectionsState._petDrawGen ~= drawGen then return end
                if collectionsState.currentSubTab ~= "pets" then return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then return end
                RunChunkedPetBuild(
                    allPets,
                    collectionsState.searchText or "",
                    collectionsState.showCollected,
                    collectionsState.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                        if not sch:GetParent() or not contentFrame:IsVisible() then return end
                        collectionsState._lastGroupedPetData = grouped
                        collectionsState._petLastSearchText = collectionsState.searchText or ""
                        collectionsState._petLastShowCollected = collectionsState.showCollected
                        collectionsState._petLastShowUncollected = collectionsState.showUncollected
                        C_Timer.After(0, function()
                            if collectionsState._petDrawGen ~= drawGen or collectionsState.currentSubTab ~= "pets" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            PopulatePetList(sch, listW, grouped, collectionsState.collapsedHeadersPets, collectionsState.selectedPetID, onSelectPet, contentFrame, DrawPetsContent)
                            if Factory.UpdateScrollBarVisibility and collectionsState.petListScrollFrame then
                                Factory:UpdateScrollBarVisibility(collectionsState.petListScrollFrame)
                            end
                        end)
                    end
                )
            end)
        end
    end
    collectionsState._drawPetsContentBusy = nil
end

-- DrawToysContent: list left (grouped by source), toy detail panel right (icon, name, source, description). No 3D viewer.
local function DrawToysContent(contentFrame)
    if collectionsState._drawToysContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawToysContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawToysContentBusy = true
    collectionsState._toysDrawGen = (collectionsState._toysDrawGen or 0) + 1
    local drawGen = collectionsState._toysDrawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth = math.floor(cw * 0.55) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local detailWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()
    local headerBlockH, innerCh = ApplyCollectionsContentHeader(contentFrame, "toys", ch)

    -- LEFT: Toy list container + scroll
    if not collectionsState.toyListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        listContainer:Show()
        collectionsState.toyListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.toyListScrollFrame = scrollFrame

        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.toyListScrollChild = scrollChild

        local scrollBarContainer = EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP)
        collectionsState.toyListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        collectionsState.toyListContainer:SetSize(listContentWidth, innerCh)
        collectionsState.toyListScrollBarContainer = EnsureListScrollBarContainer(
            collectionsState.toyListScrollBarContainer,
            contentFrame,
            collectionsState.toyListContainer,
            scrollBarColumnWidth,
            innerCh,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = collectionsState.toyListScrollFrame and collectionsState.toyListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, collectionsState.toyListScrollBarContainer, CONTAINER_INSET)
        end
    end
    collectionsState.toyListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + toy detail panel (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, detailWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.toyListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    -- RIGHT: Toy detail panel — below progress
    local SECTION_BODY_INDENT = (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 12
    local TEXT_GAP_LINE = TEXT_GAP or 8
    if not collectionsState.toyDetailContainer then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, true)
        detailContainer:ClearAllPoints()
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        collectionsState.toyDetailContainer = detailContainer
        ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(detailContainer, "toy")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            collectionsState.toyDetailEmptyOverlay = emptyOverlay
        end

        collectionsState.toyDetailScrollBarContainer = EnsureDetailScrollBarContainer(
            collectionsState.toyDetailScrollBarContainer,
            detailContainer,
            SCROLLBAR_GAP,
            CONTAINER_INSET
        )
        local scroll = Factory:CreateScrollFrame(detailContainer, "UIPanelScrollFrameTemplate", true)
        scroll:SetPoint("TOPLEFT", detailContainer, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
        scroll:SetPoint("BOTTOMRIGHT", collectionsState.toyDetailScrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
        EnableStandardScrollWheel(scroll)
        collectionsState._toyDetailScroll = scroll

        local scrollChild = CreateStandardScrollChild(scroll, detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP, 1)
        collectionsState._toyDetailScrollChild = scrollChild
        if scroll.ScrollBar then
            Factory:PositionScrollBarInContainer(scroll.ScrollBar, collectionsState.toyDetailScrollBarContainer, CONTAINER_INSET)
        end

        -- Header row: Mounts/Pets ile aynı sağ sütun (Wowhead + Add + try, try Add genişliğinde).
        local CDL = ns.CollectionsDetailHeaderLayout or {}
        local toyRightColH = (CDL.ACTION_SLOT_H or 28) + (CDL.TRY_GAP or 4) + (CDL.TRY_ROW_H or 18)
        local toyHdrH = math.max(ROW_HEIGHT + TEXT_GAP_LINE, DETAIL_ICON_SIZE + TEXT_GAP_LINE, toyRightColH)
        local toyHdrW = math.max(200, detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        local headerRow = Factory:CreateContainer(scrollChild, toyHdrW, toyHdrH, false)
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, scrollChild)
        end
        headerRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(toyHdrH)
        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        if ApplyVisuals then
            ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
        end
        local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
        iconTex:SetAllPoints()
        iconTex:SetTexture(DEFAULT_ICON_TOY)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        collectionsState._toyDetailIcon = iconTex
        collectionsState._toyDetailIconBorder = iconBorder

        local DETAIL_HEADER_GAP = 10
        local goldR = (COLORS.gold and COLORS.gold[1]) or 1
        local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local goldB = (COLORS.gold and COLORS.gold[3]) or 0
        local nameFs = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        nameFs:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        nameFs:SetNonSpaceWrap(true)
        nameFs:SetTextColor(goldR, goldG, goldB)
        nameFs:SetText("")
        collectionsState._toyDetailName = nameFs
        collectionsState._toyDetailHeaderRow = headerRow

        local toyAddCol = Factory.CreateCollectionsDetailRightColumn and Factory:CreateCollectionsDetailRightColumn(headerRow, { withTryRow = true })
        local toyAddContainer = toyAddCol and toyAddCol.root
        local toyActionSlot = toyAddCol and toyAddCol.actionSlot
        if toyAddContainer then
            toyAddContainer:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
            toyAddContainer:Hide()
        end
        collectionsState._toyDetailAddContainer = toyAddContainer
        if PlanCardFactory and toyActionSlot then
            collectionsState._toyDetailAddBtn = PlanCardFactory.CreateAddButton(toyActionSlot, {
                buttonType = "row",
                anchorPoint = "TOPRIGHT",
                x = 0,
                y = 0,
            })
            if collectionsState._toyDetailAddBtn then
                collectionsState._toyDetailAddBtn:ClearAllPoints()
                collectionsState._toyDetailAddBtn:SetPoint("TOPRIGHT", toyActionSlot, "TOPRIGHT", 0, 0)
            end
            collectionsState._toyDetailAddedIndicator = PlanCardFactory.CreateAddedIndicator(toyActionSlot, {
                buttonType = "row",
                label = (ns.L and ns.L["ADDED"]) or "Added",
                fontCategory = "body",
                anchorPoint = "TOPRIGHT",
                x = 0,
                y = 0,
            })
            if collectionsState._toyDetailAddedIndicator then
                collectionsState._toyDetailAddedIndicator:ClearAllPoints()
                collectionsState._toyDetailAddedIndicator:SetPoint("TOPRIGHT", toyActionSlot, "TOPRIGHT", 0, 0)
                collectionsState._toyDetailAddedIndicator:Hide()
            end
        end
        if nameFs and toyAddContainer then
            nameFs:ClearAllPoints()
            nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
            nameFs:SetPoint("TOPRIGHT", toyAddContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
        end
        collectionsState._toyDetailWowheadBtn = toyAddCol and toyAddCol.wowheadBtn
        collectionsState._toyDetailTryCountRow = toyAddCol and toyAddCol.tryCountRow

        local collectedBadge = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        collectedBadge:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        collectedBadge:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        collectedBadge:SetJustifyH("LEFT")
        collectedBadge:SetWordWrap(true)
        collectedBadge:SetText("")
        collectedBadge:Hide()
        collectionsState._toyDetailCollectedBadge = collectedBadge

        local sourceLabel = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        sourceLabel:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetJustifyH("LEFT")
        sourceLabel:SetWordWrap(true)
        sourceLabel:SetText("")
        collectionsState._toyDetailSourceLabel = sourceLabel

        local toyObtainedLine = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
        toyObtainedLine:SetJustifyH("LEFT")
        toyObtainedLine:SetWordWrap(true)
        toyObtainedLine:SetTextColor(0.68, 0.70, 0.74, 1)
        toyObtainedLine:Hide()
        collectionsState._toyDetailObtainedLine = toyObtainedLine
    else
        collectionsState.toyDetailContainer:SetParent(rightCol)
        collectionsState.toyDetailContainer:SetSize(detailWidth, detailH)
        collectionsState.toyDetailContainer:ClearAllPoints()
        if pr then
            collectionsState.toyDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            collectionsState.toyDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        collectionsState.toyDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        ApplyDetailAccentVisuals(collectionsState.toyDetailContainer)
        collectionsState.toyDetailScrollBarContainer = EnsureDetailScrollBarContainer(
            collectionsState.toyDetailScrollBarContainer,
            collectionsState.toyDetailContainer,
            SCROLLBAR_GAP,
            CONTAINER_INSET
        )
        if collectionsState._toyDetailScroll then
            collectionsState._toyDetailScroll:ClearAllPoints()
            collectionsState._toyDetailScroll:SetPoint("TOPLEFT", collectionsState.toyDetailContainer, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
            collectionsState._toyDetailScroll:SetPoint("BOTTOMRIGHT", collectionsState.toyDetailScrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
            if collectionsState._toyDetailScroll.ScrollBar then
                Factory:PositionScrollBarInContainer(collectionsState._toyDetailScroll.ScrollBar, collectionsState.toyDetailScrollBarContainer, CONTAINER_INSET)
            end
        end
        if collectionsState._toyDetailScrollChild then
            collectionsState._toyDetailScrollChild:SetWidth(detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        end
    end

    local function UpdateToyDetailPanel(itemID, name, icon, isCollected, sourceTypeName)
        if collectionsState._toyDetailAddContainer then
            if not itemID then
                collectionsState._toyDetailAddContainer:Hide()
            else
                collectionsState._toyDetailAddContainer:Show()
                local addBtn = collectionsState._toyDetailAddBtn
                local addedIndicator = collectionsState._toyDetailAddedIndicator
                if addBtn and addedIndicator and WarbandNexus then
                    local planned = WarbandNexus.IsItemPlanned and WarbandNexus:IsItemPlanned("toy", itemID)
                    if isCollected then
                        addBtn:Hide()
                        addedIndicator:Show()
                        addedIndicator:SetAlpha(0.45)
                    elseif planned then
                        addBtn:Hide()
                        addedIndicator:Show()
                        addedIndicator:SetAlpha(1)
                    else
                        addedIndicator:Hide()
                        addBtn:Show()
                        addBtn:SetScript("OnClick", function()
                            if WarbandNexus and WarbandNexus.AddPlan then
                                WarbandNexus:AddPlan({
                                    type = "toy",
                                    itemID = itemID,
                                    name = name,
                                    icon = icon,
                                    source = sourceTypeName or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                                })
                            end
                        end)
                    end
                end
            end
        end
        -- Resolve display name: avoid showing raw ID when API didn't return name
        local displayName = name and name ~= "" and name or ""
        if (displayName == "" or (itemID and displayName == tostring(itemID))) and itemID and WarbandNexus.ResolveCollectionMetadata then
            local meta = WarbandNexus:ResolveCollectionMetadata("toy", itemID)
            if meta and meta.name and meta.name ~= "" and meta.name ~= tostring(itemID) then
                displayName = meta.name
            elseif itemID and C_Item and C_Item.GetItemInfo then
                local itemName = C_Item.GetItemInfo(itemID)
                if itemName and type(itemName) == "string" and itemName ~= "" then
                    displayName = itemName
                end
            end
        end
        if displayName == "" and itemID then displayName = tostring(itemID) end
        if collectionsState._toyDetailIcon then
            collectionsState._toyDetailIcon:SetTexture(icon or DEFAULT_ICON_TOY)
            collectionsState._toyDetailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if collectionsState._toyDetailName then
            local gR = (COLORS.gold and COLORS.gold[1]) or 1
            local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
            local gB = (COLORS.gold and COLORS.gold[3]) or 0
            collectionsState._toyDetailName:SetText(displayName)
            collectionsState._toyDetailName:SetTextColor(gR, gG, gB)
        end
        if collectionsState._toyDetailCollectedBadge then
            collectionsState._toyDetailCollectedBadge:Hide()
        end
        if collectionsState._toyDetailSourceLabel then
            local srcLabel = collectionsState._toyDetailSourceLabel
            local srcText = (sourceTypeName and sourceTypeName ~= "") and sourceTypeName or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
            if srcText == "SOURCE_UNKNOWN" then srcText = "Unknown" end
            local sourceTitle = (ns.L and ns.L["SOURCE"]) or "Source"
            if sourceTitle == "SOURCE" then sourceTitle = "Source" end
            local gR = (COLORS.gold and COLORS.gold[1]) or 1
            local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
            local gB = (COLORS.gold and COLORS.gold[3]) or 0
            local goldHex = format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
            srcLabel:SetText(goldHex .. sourceTitle .. ":|r |cffffffff" .. srcText .. "|r")
        end
        if collectionsState._toyDetailObtainedLine and collectionsState._toyDetailSourceLabel then
            local ol = collectionsState._toyDetailObtainedLine
            local srcLabel = collectionsState._toyDetailSourceLabel
            ol:ClearAllPoints()
            if isCollected and itemID and WarbandNexus and WarbandNexus.GetCollectionsAcquiredAt then
                local ts = WarbandNexus:GetCollectionsAcquiredAt("toy", itemID)
                local txt = ts and FormatCollectionsAcquiredDetail(ts) or nil
                if txt then
                    ol:SetPoint("TOPLEFT", srcLabel, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
                    ol:SetPoint("TOPRIGHT", srcLabel, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
                    ol:SetText(txt)
                    ol:Show()
                else
                    ol:Hide()
                end
            else
                ol:Hide()
            end
        end
        local toyTryRow = collectionsState._toyDetailTryCountRow
        if toyTryRow and toyTryRow.WnUpdateTryCount then
            if itemID then
                toyTryRow:WnUpdateTryCount("toy", itemID, displayName)
            else
                toyTryRow:Hide()
            end
        end
        if collectionsState._toyDetailWowheadBtn then
            if itemID and itemID > 0 then
                collectionsState._toyDetailWowheadBtn:SetScript("OnClick", function(self)
                    if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                        ns.UI.Factory:ShowWowheadCopyURL("toy", itemID, self)
                    end
                end)
                collectionsState._toyDetailWowheadBtn:Show()
            else
                collectionsState._toyDetailWowheadBtn:Hide()
            end
        end
        if collectionsState._toyDetailScrollChild and C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local child = collectionsState._toyDetailScrollChild
                if not child then return end
                local lastEl = collectionsState._toyDetailObtainedLine
                if not lastEl or not lastEl:IsShown() then
                    lastEl = collectionsState._toyDetailSourceLabel or collectionsState._toyDetailCollectedBadge
                end
                if lastEl and lastEl.GetBottom and child.GetTop then
                    local top = child:GetTop()
                    local bot = lastEl:GetBottom()
                    if top and bot then
                        child:SetHeight(math.max(1, top - bot + PADDING))
                    end
                end
            end)
        end
    end

    local function onSelectToy(itemID, name, icon, _source, _description, isCollected, sourceTypeName)
        collectionsState.selectedToyID = itemID
        if collectionsState.toyDetailEmptyOverlay then
            collectionsState.toyDetailEmptyOverlay:SetShown(not itemID)
        end
        if collectionsState._toyDetailScroll then
            collectionsState._toyDetailScroll:SetShown(itemID ~= nil)
        end
        UpdateToyDetailPanel(itemID, name or "", icon or DEFAULT_ICON_TOY, isCollected, sourceTypeName)
    end

    -- Toys: list from C_ToyBox source type API; no flat cache required
    local dataReady = true
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    if not dataReady and not isLoading then
        isLoading = true
    end

    if isLoading and not dataReady then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if collectionsState.toyListContainer then collectionsState.toyListContainer:Hide() end
        if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Hide() end
        if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Hide() end
        C_Timer.After(COLLECTION_HEAVY_DELAY, function()
            if collectionsState._toysDrawGen ~= drawGen or collectionsState.currentSubTab ~= "toys" then return end
            if not contentFrame or not contentFrame:IsVisible() then return end
            RequestCollectionFillFromUI()
            local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
            local collected = (apiCounts and apiCounts.toys and apiCounts.toys.collected) or 0
            local total = (apiCounts and apiCounts.toys and apiCounts.toys.total) or 0
            SetCollectionProgress(collected, total)
            if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
            if collectionsState.toyListContainer then collectionsState.toyListContainer:Show() end
            if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Show() end
            if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Show() end
            if not collectionsState.selectedToyID then
                if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Show() end
                if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Hide() end
            else
                if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Hide() end
                if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Show() end
            end
            local listW = listContentWidth - (CONTAINER_INSET * 2)
            local sch = collectionsState.toyListScrollChild
            local grouped = GetFilteredToysGrouped(collectionsState.searchText or "", collectionsState.showCollected, collectionsState.showUncollected)
            if collectionsState._toysDrawGen == drawGen and collectionsState.currentSubTab == "toys" and sch and sch:GetParent() and contentFrame:IsVisible() then
                collectionsState._lastGroupedToyData = grouped
                PopulateToyList(sch, listW, grouped, collectionsState.collapsedHeadersToys, collectionsState.selectedToyID, onSelectToy, contentFrame, DrawToysContent)
                if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                    Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
                end
            end
        end)
    else
        if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
        if collectionsState.toyListContainer then collectionsState.toyListContainer:Show() end
        if collectionsState.toyListScrollBarContainer then collectionsState.toyListScrollBarContainer:Show() end
        if collectionsState.toyDetailContainer then collectionsState.toyDetailContainer:Show() end
        if not collectionsState.selectedToyID then
            if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Show() end
            if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Hide() end
        else
            if collectionsState.toyDetailEmptyOverlay then collectionsState.toyDetailEmptyOverlay:Hide() end
            if collectionsState._toyDetailScroll then collectionsState._toyDetailScroll:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = collectionsState.toyListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.toys and apiCounts.toys.collected) or 0
        local total = (apiCounts and apiCounts.toys and apiCounts.toys.total) or 0
        SetCollectionProgress(collected, total)
        local searchUnchanged = (collectionsState._toyLastSearchText == (collectionsState.searchText or ""))
            and (collectionsState._toyLastShowCollected == collectionsState.showCollected)
            and (collectionsState._toyLastShowUncollected == collectionsState.showUncollected)
        if sch and collectionsState._toyFlatList and collectionsState._lastGroupedToyData and searchUnchanged then
            if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
            end
            if collectionsState._toyListRefreshVisible then
                collectionsState._toyListRefreshVisible()
            end
        else
            C_Timer.After(0, function()
                if collectionsState._toysDrawGen ~= drawGen or collectionsState.currentSubTab ~= "toys" then return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then return end
                local grouped = GetFilteredToysGrouped(collectionsState.searchText or "", collectionsState.showCollected, collectionsState.showUncollected)
                if collectionsState._toysDrawGen == drawGen and collectionsState.currentSubTab == "toys" and sch:GetParent() and contentFrame:IsVisible() then
                    collectionsState._toyLastSearchText = collectionsState.searchText or ""
                    collectionsState._toyLastShowCollected = collectionsState.showCollected
                    collectionsState._toyLastShowUncollected = collectionsState.showUncollected
                    collectionsState._lastGroupedToyData = grouped
                    PopulateToyList(sch, listW, grouped, collectionsState.collapsedHeadersToys, collectionsState.selectedToyID, onSelectToy, contentFrame, DrawToysContent)
                    if Factory.UpdateScrollBarVisibility and collectionsState.toyListScrollFrame then
                        Factory:UpdateScrollBarVisibility(collectionsState.toyListScrollFrame)
                    end
                end
            end)
        end
    end
    collectionsState._drawToysContentBusy = nil
end

-- DrawAchievementsContent: list left, achievement detail panel right (parent/children, criteria).
local function DrawAchievementsContent(contentFrame)
    if collectionsState._drawAchievementsContentBusy then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if contentFrame and contentFrame:IsVisible() then
                    DrawAchievementsContent(contentFrame)
                end
            end)
        end
        return
    end
    collectionsState._drawAchievementsContentBusy = true
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = (parent and parent:GetWidth() and (parent:GetWidth() - 20)) or 660
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth = math.floor(cw * 0.55) - SCROLLBAR_GAP
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local detailWidth = math.max(1, cw - listWidth)

    HideAllCollectionsResultFrames()
    local headerBlockH, innerCh = ApplyCollectionsContentHeader(contentFrame, "achievements", ch)

    -- Achievements: list container | scrollbar column | detail (same pattern as Mounts/Pets/Toys)
    local achListContainer = collectionsState.achievementListContainer
    if not achListContainer then
        achListContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        achListContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        collectionsState.achievementListContainer = achListContainer
        local scrollFrame = Factory:CreateScrollFrame(achListContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", achListContainer, "BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        EnableStandardScrollWheel(scrollFrame)
        collectionsState.achievementListScrollFrame = scrollFrame
        local scrollChild = CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        collectionsState.achievementListScrollChild = scrollChild
        collectionsState.achievementListScrollBarContainer = EnsureListScrollBarContainer(
            nil, contentFrame, achListContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP
        )
    end
    achListContainer = collectionsState.achievementListContainer
    achListContainer:SetSize(listContentWidth, innerCh)
    achListContainer:Show()
    -- Liste etrafında border yok
    collectionsState.achievementListScrollBarContainer = EnsureListScrollBarContainer(
        collectionsState.achievementListScrollBarContainer,
        contentFrame,
        achListContainer,
        scrollBarColumnWidth,
        innerCh,
        SCROLLBAR_SIDE_GAP
    )
    collectionsState.achievementListScrollBarContainer:Show()
    local achScrollBar = collectionsState.achievementListScrollFrame and collectionsState.achievementListScrollFrame.ScrollBar
    if achScrollBar and collectionsState.achievementListScrollBarContainer then
        Factory:PositionScrollBarInContainer(achScrollBar, collectionsState.achievementListScrollBarContainer, CONTAINER_INSET)
        achScrollBar:Show()
        if achScrollBar.ScrollUpBtn then achScrollBar.ScrollUpBtn:Show() end
        if achScrollBar.ScrollDownBtn then achScrollBar.ScrollDownBtn:Show() end
    end
    collectionsState.achievementListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + achievement detail panel (below)
    local rightCol = collectionsState.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, detailWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        collectionsState.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", collectionsState.achievementListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    EnsureCollectionProgressBar(rightCol)
    local pr = collectionsState.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    if collectionsState.achievementDetailContainer then
        collectionsState.achievementDetailContainer:Show()
    end

    local function onSelectAchievement(ach)
        collectionsState.selectedAchievementID = ach and ach.id
        if collectionsState.achDetailEmptyOverlay then
            collectionsState.achDetailEmptyOverlay:SetShown(not (ach and ach.id))
        end
        if collectionsState.achievementDetailPanel then
            collectionsState.achievementDetailPanel:SetShown(ach and ach.id ~= nil)
            collectionsState.achievementDetailPanel:SetAchievement(ach)
        end
    end

    if not collectionsState.achievementDetailPanel then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, true)
        detailContainer:ClearAllPoints()
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        collectionsState.achievementDetailContainer = detailContainer
        ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = CreateDetailEmptyOverlay(detailContainer, "achievement")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            collectionsState.achDetailEmptyOverlay = emptyOverlay
        end
        collectionsState.achievementDetailPanel = CreateAchievementDetailPanel(detailContainer, detailWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2), onSelectAchievement)
        collectionsState.achievementDetailPanel:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
    else
        if collectionsState.achievementDetailContainer then
            collectionsState.achievementDetailContainer:SetParent(rightCol)
            collectionsState.achievementDetailContainer:SetSize(detailWidth, detailH)
            collectionsState.achievementDetailContainer:ClearAllPoints()
            if pr then
                collectionsState.achievementDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                collectionsState.achievementDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            collectionsState.achievementDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        end
        ApplyDetailAccentVisuals(collectionsState.achievementDetailContainer)
        collectionsState.achievementDetailPanel:SetSize(detailWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        if collectionsState.achievementDetailPanel._scrollBarContainer then
            collectionsState.achievementDetailPanel._scrollBarContainer = EnsureDetailScrollBarContainer(
                collectionsState.achievementDetailPanel._scrollBarContainer,
                collectionsState.achievementDetailPanel,
                SCROLLBAR_GAP,
                CONTAINER_INSET
            )
        end
        if collectionsState.achievementDetailPanel.scrollFrame and collectionsState.achievementDetailPanel._scrollBarContainer then
            collectionsState.achievementDetailPanel.scrollFrame:ClearAllPoints()
            collectionsState.achievementDetailPanel.scrollFrame:SetPoint("TOPLEFT", collectionsState.achievementDetailPanel, "TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
            collectionsState.achievementDetailPanel.scrollFrame:SetPoint("BOTTOMRIGHT", collectionsState.achievementDetailPanel._scrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
            if collectionsState.achievementDetailPanel.scrollFrame.ScrollBar then
                Factory:PositionScrollBarInContainer(collectionsState.achievementDetailPanel.scrollFrame.ScrollBar, collectionsState.achievementDetailPanel._scrollBarContainer, CONTAINER_INSET)
            end
        end
        local achChild = collectionsState.achievementDetailPanel.scrollFrame and collectionsState.achievementDetailPanel.scrollFrame:GetScrollChild()
        if achChild then
            achChild:SetWidth((detailWidth - (CONTAINER_INSET * 2)) - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        end
    end
    if not collectionsState.selectedAchievementID then
        if collectionsState.achDetailEmptyOverlay then collectionsState.achDetailEmptyOverlay:Show() end
        if collectionsState.achievementDetailPanel then collectionsState.achievementDetailPanel:Hide() end
    else
        if collectionsState.achDetailEmptyOverlay then collectionsState.achDetailEmptyOverlay:Hide() end
        if collectionsState.achievementDetailPanel then collectionsState.achievementDetailPanel:Show() end
    end

    local loadingState = ns.PlansLoadingState and ns.PlansLoadingState.achievement
    local collLoading = ns.CollectionLoadingState
    -- Loading only when a scan/load is actually in progress; not when filters result in empty list (e.g. both Owned and Missing unchecked)
    local isLoading = (loadingState and loadingState.isLoading) or (collLoading and collLoading.isLoading and collLoading.currentCategory == "achievement")
    local categoryData, rootCategories, totalCount = BuildGroupedAchievementData(
        collectionsState.searchText or "",
        collectionsState.showCollected,
        collectionsState.showUncollected
    )

    if isLoading then
        SetCollectionProgress(nil, nil)
        if not collectionsState.loadingPanel then
            collectionsState.loadingPanel = GetOrCreateLoadingPanel(contentFrame)
        end
        collectionsState.loadingPanel:SetParent(contentFrame)
        collectionsState.loadingPanel:SetAllPoints(contentFrame)
        collectionsState.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or (collLoading and collLoading.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or (collLoading and collLoading.currentStage) or ((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...")
        collectionsState.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...", progress, stage)
        if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Hide() end
        if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Hide() end
        if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Hide() end
    else
        if collectionsState.loadingPanel then collectionsState.loadingPanel:Hide() end
        if collectionsState.achievementListContainer then collectionsState.achievementListContainer:Show() end
        if collectionsState.achievementListScrollBarContainer then collectionsState.achievementListScrollBarContainer:Show() end
        if collectionsState.achievementDetailContainer then collectionsState.achievementDetailContainer:Show() end

        local allAchsForProgress = WarbandNexus.GetAllAchievementsData and WarbandNexus:GetAllAchievementsData() or {}
        local achTotal = allAchsForProgress._wnAchTotal or #allAchsForProgress
        local achCollected = allAchsForProgress._wnAchCollected
        if type(achCollected) ~= "number" then
            achCollected = 0
            for i = 1, achTotal do
                local e = allAchsForProgress[i]
                if e and (e.isCollected or e.completed or e.collected) then achCollected = achCollected + 1 end
            end
        end
        SetCollectionProgress(achCollected, achTotal)

        collectionsState._lastAchievementCategoryData = categoryData
        collectionsState._lastAchievementRootCategories = rootCategories
        PopulateAchievementList(
            collectionsState.achievementListScrollChild,
            listContentWidth - (CONTAINER_INSET * 2),
            categoryData,
            rootCategories,
            collectionsState.collapsedHeaders,
            collectionsState.selectedAchievementID,
            onSelectAchievement,
            contentFrame,
            DrawAchievementsContent
        )
        if collectionsState.selectedAchievementID then
            local allAchs = WarbandNexus:GetAllAchievementsData()
            for i = 1, #allAchs do
                if allAchs[i].id == collectionsState.selectedAchievementID then
                    collectionsState.achievementDetailPanel:SetAchievement(allAchs[i])
                    break
                end
            end
        else
            collectionsState.achievementDetailPanel:SetAchievement(nil)
        end
        if Factory.UpdateScrollBarVisibility and collectionsState.achievementListScrollFrame then
            Factory:UpdateScrollBarVisibility(collectionsState.achievementListScrollFrame)
        end
    end
    collectionsState._drawAchievementsContentBusy = nil
end

-- Fixed header: search bar uses full row width when Owned/Missing row is hidden (Recent).
local function LayoutCollectionsSearchBar(hdrCache)
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

-- ============================================================================
-- DRAW COLLECTIONS TAB (Main Entry)
-- ============================================================================

function WarbandNexus:DrawCollectionsTab(parent)
    RefreshCollectionsLayout()
    ApplySessionCollectionsSubTab()

    local sideMargin = (LAYOUT.SIDE_MARGIN or 10)
    local width = (parent:GetWidth() or 680) - 20

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = (LAYOUT.TOP_MARGIN or 8)

    HideEmptyStateCard(parent, "collections")

    -- Sabit üst alan (başlık kartı, alt sekmeler, arama): sekme içi değişimde frame'leri yeniden kullan.
    local hdrCache = collectionsState._fixedHeaderCache

    if hdrCache and hdrCache.titleCard then
        hdrCache.titleCard:SetParent(headerParent)
        hdrCache.titleCard:ClearAllPoints()
        hdrCache.titleCard:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        hdrCache.titleCard:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.titleCard:SetHeight(COLLECTIONS_TITLE_CARD_HEIGHT)
        hdrCache.titleCard:Show()

        if hdrCache.recentObtainedPanel then
            hdrCache.recentObtainedPanel:Hide()
        end

        if hdrCache.collectionsTextContainer and hdrCache.collectionsHeaderIcon and ns.UI_ReanchorStandardTabTitleLayout then
            hdrCache.collectionsTextContainer:SetSize(200, 40)
            if hdrCache.collectionsTitleText and hdrCache.collectionsSubtitleText then
                hdrCache.collectionsTitleText:ClearAllPoints()
                hdrCache.collectionsTitleText:SetPoint("BOTTOM", hdrCache.collectionsTextContainer, "CENTER", 0, 0)
                hdrCache.collectionsTitleText:SetPoint("LEFT", hdrCache.collectionsTextContainer, "LEFT", 0, 0)
                hdrCache.collectionsSubtitleText:ClearAllPoints()
                hdrCache.collectionsSubtitleText:SetPoint("TOP", hdrCache.collectionsTextContainer, "CENTER", 0, -4)
                hdrCache.collectionsSubtitleText:SetPoint("LEFT", hdrCache.collectionsTextContainer, "LEFT", 0, 0)
            end
            ns.UI_ReanchorStandardTabTitleLayout(hdrCache.collectionsHeaderIcon, hdrCache.titleCard, hdrCache.collectionsTextContainer, COLLECTIONS_TITLE_CARD_HEIGHT)
            hdrCache.collectionsTextContainer:Show()
            if hdrCache.collectionsTitleText then hdrCache.collectionsTitleText:Show() end
            if hdrCache.collectionsSubtitleText then hdrCache.collectionsSubtitleText:Show() end
        end
        if hdrCache.collectionsHeaderIcon then
            if hdrCache.collectionsHeaderIcon.border then hdrCache.collectionsHeaderIcon.border:Show() end
            if hdrCache.collectionsHeaderIcon.icon then hdrCache.collectionsHeaderIcon.icon:Show() end
        end

        headerYOffset = headerYOffset + (GetLayout().afterHeader or 75)

        hdrCache.subTabBar:SetParent(headerParent)
        hdrCache.subTabBar:ClearAllPoints()
        hdrCache.subTabBar:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        hdrCache.subTabBar:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.subTabBar:SetActiveTab(collectionsState.currentSubTab)
        hdrCache.subTabBar:Show()
        collectionsState.subTabBar = hdrCache.subTabBar

        headerYOffset = headerYOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)

        hdrCache.searchRow:SetParent(headerParent)
        hdrCache.searchRow:ClearAllPoints()
        hdrCache.searchRow:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        hdrCache.searchRow:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.searchRow:Show()

        hdrCache.filterRow:SetParent(hdrCache.searchRow)
        hdrCache.filterRow:ClearAllPoints()
        hdrCache.filterRow:SetPoint("TOPRIGHT", hdrCache.searchRow, "TOPRIGHT", 0, 0)
        if collectionsState.currentSubTab == "recent" then
            hdrCache.filterRow:Hide()
        else
            hdrCache.filterRow:Show()
        end
        LayoutCollectionsSearchBar(hdrCache)

        headerYOffset = headerYOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT
    else
        hdrCache = {}
        collectionsState._fixedHeaderCache = hdrCache

        -- ===== HEADER CARD — Characters-tab standard title layout =====
        local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        local hexColor = format("%02x%02x%02x", r * 255, g * 255, b * 255)
        local titleCard, headerIcon, textContainer, titleText, subtitleText = ns.UI_CreateStandardTabTitleCard(headerParent, {
            cardHeight = COLLECTIONS_TITLE_CARD_HEIGHT,
            tabKey = "collections",
            titleText = "|cff" .. hexColor .. ((ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections") .. "|r",
            subtitleText = (ns.L and ns.L["COLLECTIONS_SUBTITLE"]) or "Mounts, pets, toys, and transmog overview",
        })
        titleCard:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        hdrCache.titleCard = titleCard

        hdrCache.collectionsHeaderIcon = headerIcon
        hdrCache.collectionsTextContainer = textContainer
        hdrCache.collectionsTitleText = titleText
        hdrCache.collectionsSubtitleText = subtitleText

        titleCard:Show()
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 75)

        -- ===== SUB-TAB BAR (in fixedHeader - non-scrolling) =====
        local subTabBar = CreateSubTabBar(headerParent, function(tabKey)
            if collectionsState.currentSubTab == tabKey then
                if collectionsState.subTabBar then
                    collectionsState.subTabBar:SetActiveTab(tabKey)
                end
                return
            end
            collectionsState.currentSubTab = tabKey
            ns._sessionCollectionsSubTab = tabKey
            if collectionsState.subTabBar then
                collectionsState.subTabBar:SetActiveTab(tabKey)
            end
            collectionsState.searchText = ""
            if collectionsState.searchBox then
                collectionsState.searchBox:SetText("")
            end
            HideAllCollectionsResultFrames()
            C_Timer.After(0, function()
                local cf = collectionsState.contentFrame
                if not cf or not cf:GetParent() then return end
                if collectionsState.currentSubTab == "recent" then
                    DrawRecentContent(cf)
                elseif collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(cf)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(cf)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(cf)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(cf)
                end
            end)
            local hc = collectionsState._fixedHeaderCache
            if hc and hc.filterRow then
                if collectionsState.currentSubTab == "recent" then hc.filterRow:Hide() else hc.filterRow:Show() end
                LayoutCollectionsSearchBar(hc)
            end
        end)
        subTabBar:SetPoint("TOPLEFT", sideMargin, -headerYOffset)
        subTabBar:SetPoint("TOPRIGHT", -sideMargin, -headerYOffset)
        subTabBar:SetActiveTab(collectionsState.currentSubTab)
        hdrCache.subTabBar = subTabBar
        collectionsState.subTabBar = subTabBar

        headerYOffset = headerYOffset + SUBTAB_BTN_HEIGHT + (LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8)

        -- ===== SEARCH ROW (in fixedHeader - non-scrolling) =====
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

        local searchBar = Factory:CreateContainer(searchRow, nil, 32, false)
        searchBar:SetPoint("TOPLEFT", searchRow, "TOPLEFT", 0, 0)
        searchBar:SetPoint("TOPRIGHT", filterRow, "TOPLEFT", -8, 0)
        if ApplyVisuals then
            ApplyVisuals(searchBar, { 0.06, 0.06, 0.08, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
        end

        local searchIcon = searchBar:CreateTexture(nil, "OVERLAY")
        searchIcon:SetSize(14, 14)
        searchIcon:SetPoint("LEFT", 8, 0)
        searchIcon:SetAtlas("common-search-magnifyingglass")
        searchIcon:SetVertexColor(0.6, 0.6, 0.6)

        local searchBox = Factory:CreateEditBox(searchBar)
        searchBox:SetSize(1, 26)
        searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 6, 0)
        searchBox:SetPoint("RIGHT", searchBar, "RIGHT", -8, 0)
        searchBox:SetTextColor(1, 1, 1, 1)
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(50)
        searchBox.Instructions = searchBox:CreateFontString(nil, "ARTWORK")
        if ns.FontManager then
            ns.FontManager:ApplyFont(searchBox.Instructions, "body")
        end
        searchBox.Instructions:SetPoint("LEFT", 0, 0)
        searchBox.Instructions:SetPoint("RIGHT", 0, 0)
        searchBox.Instructions:SetJustifyH("LEFT")
        searchBox.Instructions:SetTextColor(0.5, 0.5, 0.5, 0.8)
        searchBox.Instructions:SetText((ns.L and ns.L["SEARCH_PLACEHOLDER"]) or "Search...")
        searchBox:SetText(collectionsState.searchText or "")
        if (collectionsState.searchText or "") ~= "" then searchBox.Instructions:Hide() end

        searchBox:SetScript("OnTextChanged", function(self, userInput)
            local text = self:GetText()
            if issecretvalue and issecretvalue(text) then
                collectionsState.searchText = ""
                if self.Instructions then self.Instructions:Show() end
                return
            end
            text = text or ""
            collectionsState.searchText = text
            if self.Instructions then
                if text ~= "" then self.Instructions:Hide() else self.Instructions:Show() end
            end
            if not userInput then return end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "recent" then
                    DrawRecentContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
            collectionsState.searchText = ""
            if self.Instructions then self.Instructions:Show() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "recent" then DrawRecentContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "mounts" then DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)
        searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        searchBar:EnableMouse(true)
        searchBar:SetScript("OnMouseDown", function() searchBox:SetFocus() end)
        collectionsState.searchBox = searchBox
        hdrCache.searchBar = searchBar

        -- ===== FILTERS (right side of search row: Owned | Missing) =====
        local lblOwned = (ns.L and (ns.L["FILTER_SHOW_OWNED"] or ns.L["FILTER_COLLECTED"])) or "Owned"
        local lblMissing = (ns.L and (ns.L["FILTER_SHOW_MISSING"] or ns.L["FILTER_UNCOLLECTED"])) or "Missing"

        local cbCollected = CreateThemedCheckbox(filterRow, collectionsState.showCollected)
        cbCollected:SetPoint("LEFT", filterRow, "LEFT", CONTENT_INSET, 0)
        local lblCollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblCollected:SetPoint("LEFT", cbCollected, "RIGHT", 4, 0)
        lblCollected:SetText(lblOwned)
        lblCollected:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        lblCollected:SetJustifyH("LEFT")
        cbCollected:SetScript("OnClick", function(self)
            collectionsState.showCollected = self:GetChecked()
            if self:GetChecked() then cbCollected.checkTexture:Show() else cbCollected.checkTexture:Hide() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "recent" then
                    DrawRecentContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        local cbUncollected = CreateThemedCheckbox(filterRow, collectionsState.showUncollected)
        cbUncollected:SetPoint("LEFT", lblCollected, "RIGHT", CONTENT_INSET * 2, 0)
        local lblUncollected = FontManager:CreateFontString(filterRow, "body", "OVERLAY")
        lblUncollected:SetPoint("LEFT", cbUncollected, "RIGHT", 4, 0)
        lblUncollected:SetText(lblMissing)
        lblUncollected:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        lblUncollected:SetJustifyH("LEFT")
        cbUncollected:SetScript("OnClick", function(self)
            collectionsState.showUncollected = self:GetChecked()
            if self:GetChecked() then cbUncollected.checkTexture:Show() else cbUncollected.checkTexture:Hide() end
            if collectionsState.contentFrame then
                if collectionsState.currentSubTab == "recent" then
                    DrawRecentContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "mounts" then
                    DrawMountsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "pets" then
                    DrawPetsContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "toys" then
                    DrawToysContent(collectionsState.contentFrame)
                elseif collectionsState.currentSubTab == "achievements" then
                    DrawAchievementsContent(collectionsState.contentFrame)
                end
            end
        end)

        if not collectionsState.showCollected and not collectionsState.showUncollected then
            collectionsState.showCollected = true
            collectionsState.showUncollected = true
            cbCollected:SetChecked(true)
            cbCollected.checkTexture:Show()
            cbUncollected:SetChecked(true)
            cbUncollected.checkTexture:Show()
        end

        if collectionsState.currentSubTab == "recent" then
            filterRow:Hide()
        end
        LayoutCollectionsSearchBar(hdrCache)

        headerYOffset = headerYOffset + SEARCH_ROW_HEIGHT + AFTER_ELEMENT
    end

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = 8

    -- ===== CONTENT AREA =====
    local scrollFrame = parent:GetParent()
    local viewHeight = (scrollFrame and scrollFrame:GetHeight()) or 450
    local bottomPad = 0
    local contentHeight = math.max(250, viewHeight - yOffset - bottomPad)
    local parentWidth = parent:GetWidth() or 680
    local contentWidth = math.max(1, parentWidth - (sideMargin * 2))

    local contentFrame = collectionsState.contentFrame
    if contentFrame then
        contentFrame:SetParent(parent)
        contentFrame:ClearAllPoints()
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        collectionsState.contentFrame = contentFrame
    else
        contentFrame = Factory:CreateContainer(parent, contentWidth, contentHeight, false)
        contentFrame:SetSize(contentWidth, contentHeight)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", sideMargin, -yOffset)
        contentFrame:Show()
        collectionsState.contentFrame = contentFrame
        collectionsState.viewerContainer = nil
        collectionsState.mountListContainer = nil
        collectionsState.mountListScrollFrame = nil
        collectionsState.mountListScrollChild = nil
        collectionsState.mountListScrollBarContainer = nil
        collectionsState.petListContainer = nil
        collectionsState.petListScrollFrame = nil
        collectionsState.petListScrollChild = nil
        collectionsState.petListScrollBarContainer = nil
        collectionsState.achievementListContainer = nil
        collectionsState.achievementListScrollFrame = nil
        collectionsState.achievementListScrollChild = nil
        collectionsState.achievementListScrollBarContainer = nil
        collectionsState.achievementDetailPanel = nil
        collectionsState.achievementDetailContainer = nil
        collectionsState.toyListContainer = nil
        collectionsState.toyListScrollFrame = nil
        collectionsState.toyListScrollChild = nil
        collectionsState.toyListScrollBarContainer = nil
        collectionsState.toyDetailContainer = nil
        collectionsState.toyDetailScrollBarContainer = nil
        collectionsState.collectionRightColumn = nil
        collectionsState.collectionProgressFrame = nil
        collectionsState.collectionProgressBar = nil
        collectionsState.collectionProgressLabel = nil
        collectionsState.modelViewer = nil
        collectionsState.loadingPanel = nil
        collectionsState._achFlatList = nil
        collectionsState._achVisibleRowFrames = nil
        collectionsState._achListContentFrame = nil
        collectionsState.recentTabPanel = nil
        collectionsState.recentViewportCap = nil
        collectionsState._recentEmptyFs = nil
    end

    -- Draw current sub-tab content
    if collectionsState.currentSubTab == "recent" then
        collectionsState.recentViewportCap = contentHeight
        DrawRecentContent(contentFrame)
        contentHeight = contentFrame:GetHeight() or contentHeight
    elseif collectionsState.currentSubTab == "mounts" then
        DrawMountsContent(contentFrame)
    elseif collectionsState.currentSubTab == "pets" then
        DrawPetsContent(contentFrame)
    elseif collectionsState.currentSubTab == "toys" then
        DrawToysContent(contentFrame)
    elseif collectionsState.currentSubTab == "achievements" then
        DrawAchievementsContent(contentFrame)
    end

    yOffset = yOffset + contentHeight + bottomPad

    -- Event-driven updates (same events as Plans): all sub-tabs (Mounts, Pets, Achievements) refresh when these fire.
    -- CRITICAL: Use a dedicated listener key (CUIListeners) instead of WarbandNexus as self.
    -- AceEvent allows only ONE handler per (event, self) pair — using WarbandNexus would
    -- overwrite CollectionService's handlers for the same events (e.g. RemoveFromUncollected).
    if not collectionsState._messageRegistered then
        collectionsState._messageRegistered = true
        local CUIListeners = {}
        collectionsState._listeners = CUIListeners

        local function InvalidateAllCollectionCaches()
            collectionsState._cachedMountsData = nil
            collectionsState._cachedPetsData = nil
            collectionsState._cachedToysData = nil
            collectionsState._lastGroupedMountData = nil
            collectionsState._mountFlatList = nil
            collectionsState._lastGroupedPetData = nil
            collectionsState._petFlatList = nil
            collectionsState._lastGroupedToyData = nil
            collectionsState._toyFlatList = nil
        end

        local function InvalidateCollectionCachesForType(collectionType)
            if collectionType == "mount" then
                collectionsState._cachedMountsData = nil
                collectionsState._lastGroupedMountData = nil
                collectionsState._mountFlatList = nil
            elseif collectionType == "pet" then
                collectionsState._cachedPetsData = nil
                collectionsState._lastGroupedPetData = nil
                collectionsState._petFlatList = nil
            elseif collectionType == "toy" then
                collectionsState._cachedToysData = nil
                collectionsState._lastGroupedToyData = nil
                collectionsState._toyFlatList = nil
            elseif collectionType == "achievement" then
                -- Achievements use dedicated lists/detail state; keep mount/pet/toy caches intact.
            else
                InvalidateAllCollectionCaches()
            end
        end

        local function RedrawActiveCollectionSubTab()
            if not collectionsState.contentFrame then return end
            if collectionsState.currentSubTab == "recent" then
                DrawRecentContent(collectionsState.contentFrame)
            elseif collectionsState.currentSubTab == "mounts" then
                DrawMountsContent(collectionsState.contentFrame)
            elseif collectionsState.currentSubTab == "pets" then
                DrawPetsContent(collectionsState.contentFrame)
            elseif collectionsState.currentSubTab == "toys" then
                DrawToysContent(collectionsState.contentFrame)
            elseif collectionsState.currentSubTab == "achievements" then
                DrawAchievementsContent(collectionsState.contentFrame)
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
                if mf and mf:IsShown() and mf.currentTab == "collections" and collectionsState.contentFrame then
                    collectionsState._lastScanProgressFullRedraw = GetTime()
                    RedrawActiveCollectionSubTab()
                end
            end)
        end

        local eventName = (Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_PROGRESS) or "WN_COLLECTION_SCAN_PROGRESS"
        WarbandNexus.RegisterMessage(CUIListeners, eventName, function(_, data)
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if not mf or not mf:IsShown() or mf.currentTab ~= "collections" or not collectionsState.contentFrame then
                return
            end
            if data then
                SetCollectionProgress(data.scanned, data.total)
            end
            local now = GetTime()
            local last = collectionsState._lastScanProgressFullRedraw or 0
            if (now - last) >= SCAN_PROGRESS_FULL_REDRAW_INTERVAL then
                collectionsState._lastScanProgressFullRedraw = now
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
                if collectionsState.currentSubTab ~= "achievements" then return end
                if not collectionsState.contentFrame then return end
                DrawAchievementsContent(collectionsState.contentFrame)
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
            if collectionsState.currentSubTab ~= "achievements" then return end
            if collectionsState.achievementDetailPanel and collectionsState.achievementDetailPanel.SetAchievement then
                local currentAch = collectionsState.achievementDetailPanel._currentAchievement
                if currentAch and currentAch.id == achievementID then
                    collectionsState.achievementDetailPanel:SetAchievement(currentAch)
                end
            end
        end)
    end

    return yOffset
end