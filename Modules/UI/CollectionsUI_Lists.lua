--[[
    Warband Nexus - Collections tab (Lists)
    Loaded via WarbandNexus.toc after CollectionsUI_Shared.lua.

    WN_PERF: Mounts/Pets/Toys browse collapsible headers paint in COLLECTIONS_HEADER_CHUNK
    frames (C_Timer.After); drawGen + sub-tab gen cancel superseded pumps (WN-PERF-warband-nexus).
]]

local _, ns = ...
local M = ns.CollectionsUI
assert(M and M.state, "CollectionsUI_Shared.lua must load before this file")

local WarbandNexus = M.WarbandNexus
local FontManager = M.FontManager
local Constants = M.Constants
local Utilities = M.Utilities
local issecretvalue = M.issecretvalue
local SafeLower = M.SafeLower
local CreateCard = M.CreateCard
local CreateEmptyStateCard = M.CreateEmptyStateCard
local HideEmptyStateCard = M.HideEmptyStateCard
local CreateThemedCheckbox = M.CreateThemedCheckbox
local PlanCardFactory = M.PlanCardFactory
local COLORS = M.COLORS
local ApplyVisuals = M.ApplyVisuals
local UpdateBorderColor = M.UpdateBorderColor
local CreateCollapsibleHeader = M.CreateCollapsibleHeader
local ChainSectionFrameBelow = M.ChainSectionFrameBelow
local CreateIcon = M.CreateIcon
local LAYOUT = M.LAYOUT
local SIDE_MARGIN = M.SIDE_MARGIN
local TOP_MARGIN = M.TOP_MARGIN
local CARD_GAP = M.CARD_GAP
local AFTER_ELEMENT = M.AFTER_ELEMENT
local ROW_ICON_SIZE = M.ROW_ICON_SIZE
local DETAIL_ICON_SIZE = M.DETAIL_ICON_SIZE
local STATUS_ICON_SIZE = M.STATUS_ICON_SIZE
local SCROLL_CONTENT_TOP_PADDING = M.SCROLL_CONTENT_TOP_PADDING
local CONTENT_INSET = M.CONTENT_INSET
local CONTAINER_INSET = M.CONTAINER_INSET
local TEXT_GAP = M.TEXT_GAP
local SEARCH_ROW_HEIGHT = M.SEARCH_ROW_HEIGHT
local COLLECTIONS_TITLE_CARD_HEIGHT = M.COLLECTIONS_TITLE_CARD_HEIGHT
local RECENT_SECTION_ORDER = M.RECENT_SECTION_ORDER
local RECENT_CARD_ICON = M.RECENT_CARD_ICON
local RECENT_CARD_HEADER_PAD = M.RECENT_CARD_HEADER_PAD
local RECENT_ROW_ICON_BORDER_ALPHA = M.RECENT_ROW_ICON_BORDER_ALPHA
local RECENT_CARD_MIN_WIDTH = M.RECENT_CARD_MIN_WIDTH
local SUBTAB_BAR_HEIGHT = M.SUBTAB_BAR_HEIGHT
local PROGRESS_ROW_HEIGHT = M.PROGRESS_ROW_HEIGHT
local BAR_INSET = M.BAR_INSET
local SD = M.SD
local Factory = M.Factory
local PADDING = M.PADDING
local SCROLLBAR_GAP = M.SCROLLBAR_GAP
local SCROLLBAR_SIDE_GAP = M.SCROLLBAR_SIDE_GAP
local COLLECTION_HEAVY_DELAY = M.COLLECTION_HEAVY_DELAY
local RUN_CHUNK_SIZE = M.RUN_CHUNK_SIZE
local COLLECTIONS_HEADER_CHUNK = M.COLLECTIONS_HEADER_CHUNK or 6
local COLLECTIONS_HEADER_CHUNK_DEFERRED = M.COLLECTIONS_HEADER_CHUNK_DEFERRED or 99999
local ROW_HEIGHT = M.ROW_HEIGHT
local ROW_GAP = M.ROW_GAP
local ROW_STRIDE = M.ROW_STRIDE
local COLLAPSE_HEADER_HEIGHT_COLL = M.COLLAPSE_HEADER_HEIGHT_COLL
local COLLECTION_LIST_DETAIL_SPLIT = M.COLLECTION_LIST_DETAIL_SPLIT
local DETAIL_SCROLLBAR_VERTICAL_INSET = M.DETAIL_SCROLLBAR_VERTICAL_INSET
local BORDER_INSET = M.BORDER_INSET
local VALID_COLLECTIONS_SUBTABS = M.VALID_COLLECTIONS_SUBTABS
local format = string.format
local time = time
local date = date
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove
local wipe = table.wipe

-- Build flat list for virtual scrolling: [{ type = "header", ... } | { type = "row", ... }], totalHeight
-- Counts (Drop 669, Quest 87, etc.) come from grouped[key] length; consistent with the list.
function M.BuildFlatMountList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local whiteHex = M.CollectionsListWhiteHex and M.CollectionsListWhiteHex() or "|cffffffff"
    local countColor = whiteHex
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
                flat[#flat + 1] = { type = "row", mount = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_STRIDE, rowPaintHeight = ROW_HEIGHT }
                yOffset = yOffset + ROW_STRIDE
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

function M.BuildFlatPetList(groupedData, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local whiteHex = M.CollectionsListWhiteHex and M.CollectionsListWhiteHex() or "|cffffffff"
    local countColor = whiteHex
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
                flat[#flat + 1] = { type = "row", pet = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_STRIDE, rowPaintHeight = ROW_HEIGHT }
                yOffset = yOffset + ROW_STRIDE
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

---categoriesOverride: optional list of { key, label } for toys (C_ToyBox source type). If nil, uses SD.SOURCE_CATEGORIES.
function M.BuildFlatToyList(groupedData, collapsedHeaders, categoriesOverride)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local whiteHex = M.CollectionsListWhiteHex and M.CollectionsListWhiteHex() or "|cffffffff"
    local countColor = whiteHex
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
                flat[#flat + 1] = { type = "row", toy = items[ji], rowIndex = rowCounter, yOffset = yOffset, height = ROW_STRIDE, rowPaintHeight = ROW_HEIGHT }
                yOffset = yOffset + ROW_STRIDE
            end
        end
    end
    return flat, math.max(yOffset + PADDING, 1)
end

-- Toys: flat list only (no categories). items = array of { id, name, icon, collected }.
function M.BuildFlatToyListOnly(items)
    local flat = {}
    local yOffset = 0
    for i = 1, #items do
        flat[#flat + 1] = { type = "row", toy = items[i], rowIndex = i, yOffset = yOffset, height = ROW_STRIDE, rowPaintHeight = ROW_HEIGHT }
        yOffset = yOffset + ROW_STRIDE
    end
    return flat, math.max(yOffset + PADDING, 1)
end

-- Achievement grouping: API category hierarchy (GetCategoryList, GetCategoryInfo) — same as Plans.
function M.BuildGroupedAchievementData(searchText, showCollected, showUncollected)
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local allCategoryIDs = GetCategoryList and GetCategoryList() or {}
    if #allCategoryIDs == 0 then return {}, {}, 0 end

    local sig = query .. "|" .. (showC and "1" or "0") .. "|" .. (showU and "1" or "0")
        .. "|cats:" .. #allCategoryIDs
    local cache = M.state._achGroupedCache
    if cache and cache.sig == sig and cache.categoryData then
        return cache.categoryData, cache.rootCategories, cache.totalCount
    end

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

    M.state._achGroupedCache = {
        sig = sig,
        categoryData = categoryData,
        rootCategories = rootCategories,
        totalCount = totalCount,
    }

    return categoryData, rootCategories, totalCount
end

-- Achievement flat list: ns.UI_AchievementBrowse_BuildFlatList (AchievementBrowseVirtualList.lua).
local SECTION_SPACING = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_SPACING) or (ns.UI_LAYOUT and ns.UI_LAYOUT.betweenSections) or 8

function M.AnnotateFlatRowsByNearestHeader(flatList)
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

-- Mount/Pet/Toy virtual list: scroll-layout index + visible-range binary search
-- Scroll pixel Y for each row matches ChainSectionFrameBelow stacking: per section,
-- wrap height = COLLAPSE_HEADER_HEIGHT_COLL + (expanded and bodyContentHeight or 0.1).
-- Data rows use fixed ROW_HEIGHT within an expanded section; headers are not virtualized.
-- Binary search runs on parallel arrays built when the flat list is populated or section collapse changes.
local wipe = table.wipe

--- Scrollable height for mount/pet/toy lists: collapsed section bodies contribute 0.1px, not full row stack.
function M.CollectionVirtual_ComputeScrollContentHeight(flatList, sectionContentH, collapsedHeaders, sectionSpacing, collapseHdrH, rowStride)
    collapseHdrH = collapseHdrH or COLLAPSE_HEADER_HEIGHT_COLL
    rowStride = rowStride or ROW_STRIDE
    sectionSpacing = sectionSpacing or SECTION_SPACING
    if not flatList then return 1 end
    local y = 0
    local firstSec = true
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
                secH = (it.itemCount * rowStride)
            end
            local expanded = collapsedHeaders and (collapsedHeaders[key] == false)
            local bodyH = expanded and math.max(0.1, secH) or 0.1
            y = y + collapseHdrH + bodyH
        end
    end
    return math.max(y + PADDING, 1)
end

function M.CollectionVirtual_FillRowScrollIndex(flatList, sectionContentH, collapsedHeaders, sectionSpacing, outFlatIdx, outTops, outHeights)
    wipe(outFlatIdx)
    wipe(outTops)
    wipe(outHeights)
    if not flatList then return 1 end
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
                secH = (it.itemCount * ROW_STRIDE)
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
    return math.max(y + PADDING, 1)
end

--- Flat list without collapsible headers.
function M.CollectionVirtual_FillSimpleFlatRowScrollIndex(flatList, outFlatIdx, outTops, outHeights)
    wipe(outFlatIdx)
    wipe(outTops)
    wipe(outHeights)
    if not flatList then return 1 end
    local contentH = 0
    for i = 1, #flatList do
        local it = flatList[i]
        if it and it.type == "row" then
            local top = it.yOffset or 0
            local h = it.height or ROW_STRIDE
            outFlatIdx[#outFlatIdx + 1] = i
            outTops[#outTops + 1] = top
            outHeights[#outHeights + 1] = h
            local bottom = top + h
            if bottom > contentH then contentH = bottom end
        end
    end
    return math.max(contentH + PADDING, 1)
end

local function CollectionVirtual_SyncListScrollChildHeight(scrollChild, scrollFrame, contentH, barContainer)
    if scrollChild and contentH and contentH > 0 then
        scrollChild:SetHeight(contentH)
    end
    if scrollFrame then
        if scrollFrame.GetVerticalScroll and scrollFrame.GetHeight and scrollFrame.SetVerticalScroll then
            local viewH = scrollFrame:GetHeight() or 0
            local scrollTop = scrollFrame:GetVerticalScroll() or 0
            local maxScroll = math.max(0, (contentH or 0) - viewH)
            if scrollTop > maxScroll then
                scrollFrame:SetVerticalScroll(maxScroll)
            end
        end
        if barContainer and Factory and Factory.EnsureScrollBarColumnSync then
            local colW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 22
            Factory:EnsureScrollBarColumnSync(scrollFrame, barContainer, { width = colW, gap = SCROLLBAR_SIDE_GAP or 4 })
        end
        if Factory and Factory.DeferScrollBarVisibility then
            Factory:DeferScrollBarVisibility(scrollFrame)
        elseif Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scrollFrame)
        end
    end
end

function M.CollectionVirtual_FindFirstVisibleRow(rowTops, rowHeights, n, scrollTop)
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

function M.CollectionVirtual_FindLastVisibleRow(rowTops, rowHeights, n, bottom)
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

function M.CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
    local n = rowTops and #rowTops or 0
    if n == 0 then return 1, 0 end
    local firstK = M.CollectionVirtual_FindFirstVisibleRow(rowTops, rowHeights, n, scrollTop)
    local lastK = M.CollectionVirtual_FindLastVisibleRow(rowTops, rowHeights, n, bottom)
    if firstK > lastK then return 1, 0 end
    return firstK, lastK
end

function M.CollectionVirtual_RefreshMountRowScrollIndex()
    local state = M.state
    local contentH = M.CollectionVirtual_FillRowScrollIndex(
        state._mountFlatList,
        state._mountSectionContentH,
        state._mountListCollapsedHeaders or {},
        SECTION_SPACING,
        state._mountRowScrollFlatIdx or {},
        state._mountRowScrollTops or {},
        state._mountRowScrollHeights or {}
    )
    state._mountFlatListTotalHeight = contentH
    CollectionVirtual_SyncListScrollChildHeight(
        state.mountListScrollChild, state.mountListScrollFrame, contentH, state.mountListScrollBarContainer)
end

function M.CollectionVirtual_RefreshPetRowScrollIndex()
    local state = M.state
    local contentH = M.CollectionVirtual_FillRowScrollIndex(
        state._petFlatList,
        state._petSectionContentH,
        state._petListCollapsedHeaders or {},
        SECTION_SPACING,
        state._petRowScrollFlatIdx or {},
        state._petRowScrollTops or {},
        state._petRowScrollHeights or {}
    )
    state._petFlatListTotalHeight = contentH
    CollectionVirtual_SyncListScrollChildHeight(
        state.petListScrollChild, state.petListScrollFrame, contentH, state.petListScrollBarContainer)
end

function M.CollectionVirtual_RefreshToyRowScrollIndex()
    local state = M.state
    local contentH = M.CollectionVirtual_FillRowScrollIndex(
        state._toyFlatList,
        state._toySectionContentH,
        state._toyListCollapsedHeaders or {},
        SECTION_SPACING,
        state._toyRowScrollFlatIdx or {},
        state._toyRowScrollTops or {},
        state._toyRowScrollHeights or {}
    )
    state._toyFlatListTotalHeight = contentH
    CollectionVirtual_SyncListScrollChildHeight(
        state.toyListScrollChild, state.toyListScrollFrame, contentH, state.toyListScrollBarContainer)
end

-- Forward declarations: scroll handlers schedule next-frame refresh via C_Timer.After(0).
-- forward ref: M.UpdateMountListVisibleRange assigned below
-- forward ref: M.UpdatePetListVisibleRange assigned below
-- forward ref: M.UpdateToyListVisibleRange assigned below
local mountListScrollVisibleCoalesce = false
local petListScrollVisibleCoalesce = false
local toyListScrollVisibleCoalesce = false

function M.RequestMountListVisibleRangeAfterScroll()
    if mountListScrollVisibleCoalesce then return end
    mountListScrollVisibleCoalesce = true
    C_Timer.After(0, function()
        mountListScrollVisibleCoalesce = false
        M.UpdateMountListVisibleRange()
    end)
end

function M.RequestPetListVisibleRangeAfterScroll()
    if petListScrollVisibleCoalesce then return end
    petListScrollVisibleCoalesce = true
    C_Timer.After(0, function()
        petListScrollVisibleCoalesce = false
        M.UpdatePetListVisibleRange()
    end)
end

function M.RequestToyListVisibleRangeAfterScroll()
    if toyListScrollVisibleCoalesce then return end
    toyListScrollVisibleCoalesce = true
    C_Timer.After(0, function()
        toyListScrollVisibleCoalesce = false
        M.UpdateToyListVisibleRange()
    end)
end

-- Shared row pool for all three collection lists (Mounts, Pets, Achievements). Row structure from SharedWidgets.
local CollectionRowPool = {}
local function CollectionsCollectedNameHex()
    return M.CollectionsCollectedHex and M.CollectionsCollectedHex() or "|cff33e533"
end
local function CollectionsUncollectedNameHex()
    return M.CollectionsBrightHex and M.CollectionsBrightHex() or "|cffeeeeee"
end
local DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
local DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"
local DEFAULT_ICON_TOY = "Interface\\Icons\\INV_Misc_Toy_07"
local DEFAULT_ICON_ACHIEVEMENT = "Interface\\Icons\\Achievement_General"

function M.RemoveFirstMatchingPlan(pred)
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

function M.CollectionRowTodoSlotTooltip(onTodo, canInteract)
    local L = ns.L
    local title = (L and L["COLLECTIONS_TT_TODO_TITLE"]) or "To-Do list"
    if onTodo then
        return {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TODO_REMOVE"]) or "Left-click to remove this entry from your To-Do list." },
        }
    end
    if canInteract then
        return {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TODO_ADD"]) or "Left-click to add this entry to your To-Do list." },
        }
    end
    return nil
end

function M.CollectionRowTrackSlotTooltip(achCollected, onTrack)
    local L = ns.L
    local title = (L and L["COLLECTIONS_TT_TRACK_TITLE"]) or "Objectives tracker"
    if achCollected then
        return {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TRACK_COMPLETED"]) or "This achievement is already completed. Tracking is not available." },
        }
    end
    if onTrack then
        return {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TRACK_DISABLE"]) or "Left-click to stop tracking in Blizzard objectives." },
        }
    end
    return {
        title = title,
        lines = { (L and L["COLLECTIONS_TT_TRACK_ENABLE"]) or "Left-click to show progress in Blizzard objectives (up to 10 at once)." },
    }
end

-- Acquire a collection list row (SharedWidgets layout: status icon + icon + label). Used by Mounts, Pets, Achievements.
function M.CollectionRowPaintHeight(item)
    if item and item.rowPaintHeight and item.rowPaintHeight > 0 then
        return item.rowPaintHeight
    end
    return ROW_HEIGHT
end

function M.AcquireCollectionRow(rowParent, item, leftIndent, iconPath, labelText, isCollected, selectedID, itemID, onSelect, refreshFn, planSlotState, rightAlignedText, leftAlignedText)
    if not rowParent then return nil end
    local rowH = M.CollectionRowPaintHeight(item)
    local f = table.remove(CollectionRowPool)
    if not f then
        f = Factory:CreateCollectionListRow(rowParent, rowH)
        f:ClearAllPoints()
    end
    f:SetParent(rowParent)
    local rightPad = 4
    f:SetPoint("TOPLEFT", rowParent, "TOPLEFT", leftIndent or 0, -(item.yOffset or 0))
    f:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -rightPad, -(item.yOffset or 0))
    f:SetHeight(rowH)
    if f.SetClipsChildren then
        f:SetClipsChildren(true)
    end
    local onClick
    if onSelect or refreshFn then
        onClick = function()
            if onSelect then onSelect() end
            if refreshFn then refreshFn() end
        end
    end
    Factory:ApplyCollectionListRowContent(f, item.rowIndex, iconPath, labelText, isCollected, (selectedID == itemID), onClick, rightAlignedText, nil, planSlotState, leftAlignedText)
    M.ApplyCollectionsRowIconChrome(f)
    f:Show()
    return f
end

function M.AcquireMountRow(scrollChild, listWidth, item, selectedMountID, onSelectMount, redraw, cf)
    local mount = item.mount
    local nameColor = mount.isCollected and CollectionsCollectedNameHex() or CollectionsUncollectedNameHex()
    local labelText = nameColor .. (mount.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("mount", mount.id)
    local rowParent = scrollChild
    if item._collSectionKey and M.state._mountSectionBodies and M.state._mountSectionBodies[item._collSectionKey] then
        rowParent = M.state._mountSectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = { mount = item.mount, rowIndex = item.rowIndex, yOffset = item._collRelY, height = item.height, rowPaintHeight = item.rowPaintHeight }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsMountPlanned and WN:IsMountPlanned(mount.id) or false
    local function refreshMountListVisible()
        if M.state._mountFlatList and M.state.mountListScrollFrame then
            M.state._mountListSelectedID = mount.id
            local r = M.state._mountListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = false,
        achievementRow = false,
        showTrackSlot = false,
        todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not mount.isCollected),
        onTodoClick = (onTodo or not mount.isCollected) and function()
            if not WN then return end
            if WN.IsMountPlanned and WN:IsMountPlanned(mount.id) then
                M.RemoveFirstMatchingPlan(function(p)
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
    return M.AcquireCollectionRow(rowParent, rowItem, 0, mount.icon or DEFAULT_ICON_MOUNT, labelText, mount.isCollected, selectedMountID, mount.id, function()
        if onSelectMount then
            onSelectMount(mount.id, mount.name, mount.icon, mount.source, mount.creatureDisplayID, mount.description, mount.isCollected)
        end
    end, refreshMountListVisible, planSlotState)
end

function M.AcquirePetRow(scrollChild, listWidth, item, selectedPetID, onSelectPet, redraw, cf)
    local pet = item.pet
    local nameColor = pet.isCollected and CollectionsCollectedNameHex() or CollectionsUncollectedNameHex()
    local labelText = nameColor .. (pet.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("pet", pet.id)
    local rowParent = scrollChild
    if item._collSectionKey and M.state._petSectionBodies and M.state._petSectionBodies[item._collSectionKey] then
        rowParent = M.state._petSectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = { pet = item.pet, rowIndex = item.rowIndex, yOffset = item._collRelY, height = item.height, rowPaintHeight = item.rowPaintHeight }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsPetPlanned and WN:IsPetPlanned(pet.id) or false
    local function refreshPetListVisible()
        if M.state._petFlatList and M.state.petListScrollFrame then
            M.state._petListSelectedID = pet.id
            local r = M.state._petListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = false,
        achievementRow = false,
        showTrackSlot = false,
        todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not pet.isCollected),
        onTodoClick = (onTodo or not pet.isCollected) and function()
            if not WN then return end
            if WN.IsPetPlanned and WN:IsPetPlanned(pet.id) then
                M.RemoveFirstMatchingPlan(function(p)
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
    return M.AcquireCollectionRow(rowParent, rowItem, 0, pet.icon or DEFAULT_ICON_PET, labelText, pet.isCollected, selectedPetID, pet.id, function()
        if onSelectPet then
            onSelectPet(pet.id, pet.name, pet.icon, pet.source, pet.creatureDisplayID, pet.description, pet.isCollected)
        end
    end, refreshPetListVisible, planSlotState)
end

function M.CollectionsUsesToyListPipeline()
    local sub = M.state and M.state.currentSubTab
    return sub == "toys"
end

function M.AcquireToyRow(scrollChild, listWidth, item, selectedToyID, onSelectToy, redraw, cf)
    local toy = item.toy
    local nameColor = (toy.isCollected or toy.collected) and CollectionsCollectedNameHex() or CollectionsUncollectedNameHex()
    local trySuffix = (SD and SD.FormatMountPetToyListTrySuffix and toy.id)
        and SD.FormatMountPetToyListTrySuffix("toy", toy.id) or ""
    local labelText = nameColor .. (toy.name or "") .. "|r" .. trySuffix
    local rowParent = scrollChild
    if item._collSectionKey then
        local sectionBodies = M.state._toySectionBodies
        if sectionBodies and sectionBodies[item._collSectionKey] then
            rowParent = sectionBodies[item._collSectionKey]
        end
    end
    local rowItem = item
    if item._collRelY then
        rowItem = { toy = item.toy, rowIndex = item.rowIndex, yOffset = item._collRelY, height = item.height, rowPaintHeight = item.rowPaintHeight }
    end
    local WN = WarbandNexus
    local planKey = toy.id
    local onTodo = WN and WN.IsItemPlanned and WN:IsItemPlanned("toy", planKey) or false
    local toyCollected = (toy.isCollected == true) or (toy.collected == true)
    local function refreshToyListVisible()
        if M.state._toyFlatList and M.state.toyListScrollFrame then
            M.state._toyListSelectedID = toy.id
            local r = M.state._toyListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = false,
        achievementRow = false,
        showTrackSlot = false,
        todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not toyCollected),
        onTodoClick = (onTodo or not toyCollected) and function()
            if not WN then return end
            if WN.IsItemPlanned and WN:IsItemPlanned("toy", planKey) then
                M.RemoveFirstMatchingPlan(function(p)
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
    return M.AcquireCollectionRow(rowParent, rowItem, 0, toy.icon or DEFAULT_ICON_TOY, labelText, toyCollected, selectedToyID, toy.id, function()
        if onSelectToy then
            onSelectToy(toy.id, toy.name, toy.icon, toy.source, toy.description, toyCollected, toy.sourceTypeName)
        end
    end, refreshToyListVisible, planSlotState)
end

function M.AcquireAchievementRow(scrollChild, listWidth, item, selectedAchievementID, onSelectAchievement, redraw, cf)
    local ach = item.achievement
    local achCollected = ach.isCollected == true
    local whiteHex = M.CollectionsListWhiteHex and M.CollectionsListWhiteHex() or "|cffffffff"
    local nameColor = achCollected and CollectionsCollectedNameHex() or whiteHex
    local pointsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
    local labelText = nameColor .. (ach.name or "") .. "|r" .. (pointsStr ~= "" and (whiteHex .. pointsStr .. "|r") or "")
    local earnedDateRich, earnedEarnerRich
    if achCollected and ach.id and M.FormatAchievementEarnedRowMetaSplit then
        earnedDateRich, earnedEarnerRich = M.FormatAchievementEarnedRowMetaSplit(ach.id)
    end
    local indent = item.indent or 0
    local rowParent = scrollChild
    if item._collSectionKey and M.state._achSectionBodies and M.state._achSectionBodies[item._collSectionKey] then
        rowParent = M.state._achSectionBodies[item._collSectionKey]
    end
    local rowItem = item
    if item._collRelY then
        rowItem = {
            achievement = item.achievement,
            rowIndex = item.rowIndex,
            yOffset = item._collRelY,
            height = item.height,
            rowPaintHeight = item.rowPaintHeight,
            indent = item.indent,
        }
    end
    local WN = WarbandNexus
    local onTodo = WN and WN.IsAchievementPlanned and WN:IsAchievementPlanned(ach.id) or false
    local onTrack = WN and WN.IsAchievementTracked and WN:IsAchievementTracked(ach.id) or false
    local function refreshAchListVisible()
        if M.state._achFlatList and M.state.achievementListScrollFrame then
            M.state._achListSelectedID = ach.id
            local r = M.state._achListRefreshVisible
            if r then r() end
        end
    end
    local planSlotState = {
        onTodo = onTodo,
        onTrack = onTrack,
        achievementRow = true,
        achievementCollected = achCollected,
        todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not achCollected),
        trackTooltip = M.CollectionRowTrackSlotTooltip(achCollected, onTrack),
        onTodoClick = (onTodo or not achCollected) and function()
            if not WN or not ach.id then return end
            local planned = WN.IsAchievementPlanned and WN:IsAchievementPlanned(ach.id)
            if planned then
                M.RemoveFirstMatchingPlan(function(p)
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
    return M.AcquireCollectionRow(rowParent, rowItem, indent, ach.icon or DEFAULT_ICON_ACHIEVEMENT, labelText, ach.isCollected, selectedAchievementID, ach.id, function()
        if onSelectAchievement then onSelectAchievement(ach) end
    end, refreshAchListVisible, planSlotState, earnedEarnerRich, earnedDateRich)
end

-- Update visible row frames only (virtual scroll). Headers are created in PopulateMountList.
M.UpdateMountListVisibleRange = function()
    local state = M.state
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
        local firstK, lastK = M.CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
        for k = firstK, lastK do
            local i = rowFlatIdx[k]
            local it = flatList[i]
            if it and it.type == "row" then
                local body = state._mountSectionBodies and state._mountSectionBodies[it._collSectionKey]
                if body and body:IsShown() then
                    local frame = M.AcquireMountRow(scrollChild, listWidth, it, selectedMountID, onSelectMount, redraw, cf)
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
            if it._collSectionKey and M.state._mountSectionBodies then
                local body = M.state._mountSectionBodies[it._collSectionKey]
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
                local frame = M.AcquireMountRow(scrollChild, listWidth, it, selectedMountID, onSelectMount, redraw, cf)
                tinsert(state._mountVisibleRowFrames, { frame = frame, flatIndex = i })
            end
        end
    end
end

-- Populate scrollChild: build flat list, create headers only, set height; visible rows updated by UpdateMountListVisibleRange (virtual scroll).
-- contentFrameForRefresh, redrawFn: redrawFn(contentFrame) is called on next frame for refresh; pass same DrawMountsContent from caller so closure sees it.
function M.PopulateMountList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedMountID, onSelectMount, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    if not scrollChild or not Factory then return end
    if _populateMountListBusy then
        -- An older pump is mid-chunk. Dropping this populate would leave the caller's
        -- draw busy flag held; if superseded release it, otherwise retry next tick
        -- (the old pump finishes or aborts on gen mismatch within a tick).
        if drawGen and M.state._mountsDrawGen and M.state._mountsDrawGen ~= drawGen then
            M.ReleaseCollectionsDrawBusy("Mounts", drawGen)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                M.PopulateMountList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedMountID, onSelectMount, contentFrameForRefresh, redrawFn, drawGen, onListReady)
            end)
        else
            M.ReleaseCollectionsDrawBusy("Mounts", drawGen)
        end
        return
    end
    _populateMountListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local deferListChrome = M.CollectionsBeginListChromeDefer(M.CollectionsListChromeFramesForSubTab("mounts"))
    local headerChunkSize = deferListChrome and COLLECTIONS_HEADER_CHUNK_DEFERRED or COLLECTIONS_HEADER_CHUNK
    M.CollectionsSubTabTrace("PopulateMountList_start", { deferChrome = deferListChrome, headersChunk = headerChunkSize })
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = ns.UI_ResolveListContentWidth and ns.UI_ResolveListContentWidth(scrollChild, listWidth or 260, 0)
        or (listWidth or 260)
    scrollChild:SetWidth(listWidth)

    -- Release any visible row frames back to pool before clearing
    local visible = M.state._mountVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        M.state._mountVisibleRowFrames = {}
    end

    -- Clear existing children (headers from previous run); unparent to avoid accumulating on re-populate.
    -- KNOWN COST: section wraps/headers are rebuilt per populate (search keystroke after
    -- debounce, filter toggle). Reusing them needs an update mode on the
    -- CreateCollapsibleHeader factory (label/count text, expanded state, re-chaining)
    -- plus closure-lifetime review — a planned refactor, not a drop-in change here.
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

    local flatList = M.BuildFlatMountList(groupedData, collapsedHeaders)

    if not M.FlatListHasDataRows(flatList) and M.TryShowCollectionsListEmpty(scrollChild, "mounts") then
        M.state._mountFlatList = flatList
        M.state._mountVisibleRowFrames = {}
        M.CollectionsEndListChromeDefer()
        _populateMountListBusy = false
        if onListReady then onListReady() end
        return
    end

    M.HideCollectionsListEmptyCards(scrollChild)

    M.state._mountSectionBodies = {}
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
    M.AnnotateFlatRowsByNearestHeader(flatList)

    local function finishMountListPopulate()
        M.state._mountFlatList = flatList
        M.state._mountSectionContentH = mountSectionContentH
        M.state._mountRowScrollFlatIdx = M.state._mountRowScrollFlatIdx or {}
        M.state._mountRowScrollTops = M.state._mountRowScrollTops or {}
        M.state._mountRowScrollHeights = M.state._mountRowScrollHeights or {}
        M.state._mountListWidth = listWidth
        M.state._mountListSelectedID = selectedMountID
        M.state._mountListOnSelectMount = onSelectMount
        M.state._mountListCollapsedHeaders = collapsedHeaders
        M.state._mountListRedrawFn = redraw
        M.state._mountListContentFrame = cf
        M.state._mountListRefreshVisible = M.UpdateMountListVisibleRange
        M.CollectionVirtual_RefreshMountRowScrollIndex()
        local scrollFrame = M.state.mountListScrollFrame
        if scrollFrame then
            scrollFrame:SetScript("OnVerticalScroll", function()
                M.RequestMountListVisibleRangeAfterScroll()
            end)
        end
        M.UpdateMountListVisibleRange()
        M.ScheduleCollectionsVisibleSync("mounts", M.UpdateMountListVisibleRange)
        M.CollectionsEndListChromeDefer()
        M.CollectionsSubTabTrace("PopulateMountList_done", { flatRows = flatList and #flatList or 0 })
        if type(onListReady) == "function" then
            onListReady()
        end
        _populateMountListBusy = false
    end

    local function abortMountListPopulate()
        M.CollectionsEndListChromeDefer()
        _populateMountListBusy = false
        if drawGen then
            M.ReleaseCollectionsDrawBusy("Mounts", drawGen)
        end
    end

    local collHdrChainTail = nil
    local flatIdx = 1
    local function hasRemainingMountHeaders()
        for hi = flatIdx, #flatList do
            if flatList[hi].type == "header" then
                return true
            end
        end
        return false
    end

    local function pumpMountHeaders()
        if drawGen and M.state._mountsDrawGen and M.state._mountsDrawGen ~= drawGen then
            abortMountListPopulate()
            return
        end
        if drawGen and M.state._collectionsSubTabGen and M.state.currentSubTab ~= "mounts" then
            abortMountListPopulate()
            return
        end

        local built = 0
        while flatIdx <= #flatList and built < headerChunkSize do
            while flatIdx <= #flatList and flatList[flatIdx].type ~= "header" do
                flatIdx = flatIdx + 1
            end
            if flatIdx > #flatList then
                break
            end
            local it = flatList[flatIdx]
            flatIdx = flatIdx + 1
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
                secH = ((it.itemCount or 0) * ROW_STRIDE) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                if isExpanded then
                    M.CollectionVirtual_RefreshMountRowScrollIndex()
                    M.UpdateMountListVisibleRange()
                end
            end, SD.GetMountCategoryIcon(key), true, 0, nil, ns.UI_BuildCollapsibleSectionOpts({
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
                    M.CollectionVirtual_RefreshMountRowScrollIndex()
                    M.UpdateMountListVisibleRange()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    M.CollectionVirtual_RefreshMountRowScrollIndex()
                    M.UpdateMountListVisibleRange()
                end,
            }))
            if ns.UI_AnchorSectionHeaderInWrap then
                ns.UI_AnchorSectionHeaderInWrap(header, sectionWrap, listWidth)
            else
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
                header:SetWidth(listWidth)
            end
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
            M.state._mountSectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
            built = built + 1
        end

        if hasRemainingMountHeaders() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, pumpMountHeaders)
            else
                pumpMountHeaders()
            end
            return
        end
        finishMountListPopulate()
    end

    pumpMountHeaders()
end

local _populatePetListBusy = false

M.UpdatePetListVisibleRange = function()
    local state = M.state
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
        local firstK, lastK = M.CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
        for k = firstK, lastK do
            local i = rowFlatIdx[k]
            local it = flatList[i]
            if it and it.type == "row" then
                local body = state._petSectionBodies and state._petSectionBodies[it._collSectionKey]
                if body and body:IsShown() then
                    local frame = M.AcquirePetRow(scrollChild, listWidth, it, selectedPetID, onSelectPet, redraw, cf)
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
            if it._collSectionKey and M.state._petSectionBodies then
                local body = M.state._petSectionBodies[it._collSectionKey]
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
                local frame = M.AcquirePetRow(scrollChild, listWidth, it, selectedPetID, onSelectPet, redraw, cf)
                tinsert(state._petVisibleRowFrames, { frame = frame, flatIndex = i })
            end
        end
    end
end

function M.PopulatePetList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedPetID, onSelectPet, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    if not scrollChild or not Factory then return end
    if _populatePetListBusy then
        -- See PopulateMountList: never drop a populate while the caller holds its busy flag.
        if drawGen and M.state._petDrawGen and M.state._petDrawGen ~= drawGen then
            M.ReleaseCollectionsDrawBusy("Pets", drawGen)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                M.PopulatePetList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedPetID, onSelectPet, contentFrameForRefresh, redrawFn, drawGen, onListReady)
            end)
        else
            M.ReleaseCollectionsDrawBusy("Pets", drawGen)
        end
        return
    end
    _populatePetListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local deferListChrome = M.CollectionsBeginListChromeDefer(M.CollectionsListChromeFramesForSubTab("pets"))
    local headerChunkSize = deferListChrome and COLLECTIONS_HEADER_CHUNK_DEFERRED or COLLECTIONS_HEADER_CHUNK
    M.CollectionsSubTabTrace("PopulatePetList_start", { deferChrome = deferListChrome, headersChunk = headerChunkSize })
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = ns.UI_ResolveListContentWidth and ns.UI_ResolveListContentWidth(scrollChild, listWidth or 260, 0)
        or (listWidth or 260)
    scrollChild:SetWidth(listWidth)

    local visible = M.state._petVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        M.state._petVisibleRowFrames = {}
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

    local flatList = M.BuildFlatPetList(groupedData, collapsedHeaders)

    if not M.FlatListHasDataRows(flatList) and M.TryShowCollectionsListEmpty(scrollChild, "pets") then
        M.state._petFlatList = flatList
        M.state._petVisibleRowFrames = {}
        M.CollectionsEndListChromeDefer()
        _populatePetListBusy = false
        if onListReady then onListReady() end
        return
    end

    M.HideCollectionsListEmptyCards(scrollChild)

    M.state._petSectionBodies = {}
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
    M.AnnotateFlatRowsByNearestHeader(flatList)

    local function finishPetListPopulate()
        M.state._petFlatList = flatList
        M.state._petSectionContentH = petSectionContentH
        M.state._petRowScrollFlatIdx = M.state._petRowScrollFlatIdx or {}
        M.state._petRowScrollTops = M.state._petRowScrollTops or {}
        M.state._petRowScrollHeights = M.state._petRowScrollHeights or {}
        M.state._petListWidth = listWidth
        M.state._petListSelectedID = selectedPetID
        M.state._petListOnSelectPet = onSelectPet
        M.state._petListCollapsedHeaders = collapsedHeaders
        M.state._petListRedrawFn = redraw
        M.state._petListContentFrame = cf
        M.state._petListRefreshVisible = M.UpdatePetListVisibleRange
        M.CollectionVirtual_RefreshPetRowScrollIndex()
        local scrollFrame = M.state.petListScrollFrame
        if scrollFrame then
            scrollFrame:SetScript("OnVerticalScroll", function()
                M.RequestPetListVisibleRangeAfterScroll()
            end)
        end
        M.UpdatePetListVisibleRange()
        M.ScheduleCollectionsVisibleSync("pets", M.UpdatePetListVisibleRange)
        M.CollectionsEndListChromeDefer()
        M.CollectionsSubTabTrace("PopulatePetList_done", { flatRows = flatList and #flatList or 0 })
        if type(onListReady) == "function" then
            onListReady()
        end
        _populatePetListBusy = false
    end

    local function abortPetListPopulate()
        M.CollectionsEndListChromeDefer()
        _populatePetListBusy = false
        if drawGen then
            M.ReleaseCollectionsDrawBusy("Pets", drawGen)
        end
    end

    local collHdrChainTail = nil
    local flatIdx = 1
    local function hasRemainingPetHeaders()
        for hi = flatIdx, #flatList do
            if flatList[hi].type == "header" then
                return true
            end
        end
        return false
    end

    local function pumpPetHeaders()
        if drawGen and M.state._petDrawGen and M.state._petDrawGen ~= drawGen then
            abortPetListPopulate()
            return
        end
        if drawGen and M.state._collectionsSubTabGen and M.state.currentSubTab ~= "pets" then
            abortPetListPopulate()
            return
        end

        local built = 0
        while flatIdx <= #flatList and built < headerChunkSize do
            while flatIdx <= #flatList and flatList[flatIdx].type ~= "header" do
                flatIdx = flatIdx + 1
            end
            if flatIdx > #flatList then
                break
            end
            local it = flatList[flatIdx]
            flatIdx = flatIdx + 1
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
                secH = ((it.itemCount or 0) * ROW_STRIDE) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                if isExpanded then
                    M.CollectionVirtual_RefreshPetRowScrollIndex()
                    M.UpdatePetListVisibleRange()
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
                    M.CollectionVirtual_RefreshPetRowScrollIndex()
                    M.UpdatePetListVisibleRange()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    M.CollectionVirtual_RefreshPetRowScrollIndex()
                    M.UpdatePetListVisibleRange()
                end,
            }))
            if ns.UI_AnchorSectionHeaderInWrap then
                ns.UI_AnchorSectionHeaderInWrap(header, sectionWrap, listWidth)
            else
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
                header:SetWidth(listWidth)
            end
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
            M.state._petSectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
            built = built + 1
        end

        if hasRemainingPetHeaders() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, pumpPetHeaders)
            else
                pumpPetHeaders()
            end
            return
        end
        finishPetListPopulate()
    end

    pumpPetHeaders()
end

local _populateToyListBusy = false

M.UpdateToyListVisibleRange = function()
    local state = M.state
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
        local firstK, lastK = M.CollectionVirtual_GetVisibleRowIndexRange(rowTops, rowHeights, scrollTop, bottom)
        for k = firstK, lastK do
            local i = rowFlatIdx[k]
            local it = flatList[i]
            if it and it.type == "row" then
                local body = state._toySectionBodies and state._toySectionBodies[it._collSectionKey]
                if body and body:IsShown() then
                    local frame = M.AcquireToyRow(scrollChild, listWidth, it, selectedToyID, onSelectToy, nil, cf)
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
            if it._collSectionKey and M.state._toySectionBodies then
                local body = M.state._toySectionBodies[it._collSectionKey]
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
                local frame = M.AcquireToyRow(scrollChild, listWidth, it, selectedToyID, onSelectToy, nil, cf)
                tinsert(state._toyVisibleRowFrames, { frame = frame, flatIndex = i })
            end
        end
    end
end

function M.PopulateToyList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedToyID, onSelectToy, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    if not scrollChild or not Factory then return end
    if _populateToyListBusy then
        -- See PopulateMountList: never drop a populate while the caller holds its busy flag.
        if drawGen and M.state._toysDrawGen and M.state._toysDrawGen ~= drawGen then
            M.ReleaseCollectionsDrawBusy("Toys", drawGen)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                M.PopulateToyList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedToyID, onSelectToy, contentFrameForRefresh, redrawFn, drawGen, onListReady)
            end)
        else
            M.ReleaseCollectionsDrawBusy("Toys", drawGen)
        end
        return
    end
    _populateToyListBusy = true
    collapsedHeaders = collapsedHeaders or {}
    local deferListChrome = M.CollectionsBeginListChromeDefer(M.CollectionsListChromeFramesForSubTab("toys"))
    local headerChunkSize = deferListChrome and COLLECTIONS_HEADER_CHUNK_DEFERRED or COLLECTIONS_HEADER_CHUNK
    M.CollectionsSubTabTrace("PopulateToyList_start", { deferChrome = deferListChrome, headersChunk = headerChunkSize })
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = ns.UI_ResolveListContentWidth and ns.UI_ResolveListContentWidth(scrollChild, listWidth or 260, 0)
        or (listWidth or 260)
    scrollChild:SetWidth(listWidth)

    local visible = M.state._toyVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                CollectionRowPool[#CollectionRowPool + 1] = v.frame
            end
        end
        M.state._toyVisibleRowFrames = {}
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

    local flatList = M.BuildFlatToyList(groupedData, collapsedHeaders, SD.TOY_SOURCE_CATEGORIES)

    if not M.FlatListHasDataRows(flatList) and M.TryShowCollectionsListEmpty(scrollChild, "toys") then
        M.state._toyFlatList = flatList
        M.state._toyVisibleRowFrames = {}
        M.CollectionsEndListChromeDefer()
        _populateToyListBusy = false
        if onListReady then onListReady() end
        return
    end

    M.HideCollectionsListEmptyCards(scrollChild)

    M.state._toySectionBodies = {}
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
    M.AnnotateFlatRowsByNearestHeader(flatList)

    local function finishToyListPopulate()
        M.state._toyFlatList = flatList
        M.state._toySectionContentH = toySectionContentH
        M.state._toyRowScrollFlatIdx = M.state._toyRowScrollFlatIdx or {}
        M.state._toyRowScrollTops = M.state._toyRowScrollTops or {}
        M.state._toyRowScrollHeights = M.state._toyRowScrollHeights or {}
        M.state._toyListWidth = listWidth
        M.state._toyListSelectedID = selectedToyID
        M.state._toyListOnSelectToy = onSelectToy
        M.state._toyListCollapsedHeaders = collapsedHeaders
        M.state._toyListRedrawFn = redraw
        M.state._toyListContentFrame = cf
        M.state._toyListRefreshVisible = M.UpdateToyListVisibleRange
        M.CollectionVirtual_RefreshToyRowScrollIndex()
        local scrollFrame = M.state.toyListScrollFrame
        if scrollFrame then
            scrollFrame:SetScript("OnVerticalScroll", function()
                M.RequestToyListVisibleRangeAfterScroll()
            end)
        end
        M.UpdateToyListVisibleRange()
        M.ScheduleCollectionsVisibleSync(browseSubKey, M.UpdateToyListVisibleRange)
        M.CollectionsEndListChromeDefer()
        M.CollectionsSubTabTrace("PopulateToyList_done", { flatRows = flatList and #flatList or 0 })
        if type(onListReady) == "function" then
            onListReady()
        end
        _populateToyListBusy = false
    end

    local function abortToyListPopulate()
        M.CollectionsEndListChromeDefer()
        _populateToyListBusy = false
        if drawGen then
            M.ReleaseCollectionsDrawBusy("Toys", drawGen)
        end
    end

    local collHdrChainTail = nil
    local flatIdx = 1
    local function hasRemainingToyHeaders()
        for hi = flatIdx, #flatList do
            if flatList[hi].type == "header" then
                return true
            end
        end
        return false
    end

    local function pumpToyHeaders()
        if drawGen and M.state._toysDrawGen and M.state._toysDrawGen ~= drawGen then
            abortToyListPopulate()
            return
        end
        if drawGen and M.state._collectionsSubTabGen and not M.CollectionsUsesToyListPipeline() then
            abortToyListPopulate()
            return
        end

        local built = 0
        while flatIdx <= #flatList and built < headerChunkSize do
            while flatIdx <= #flatList and flatList[flatIdx].type ~= "header" do
                flatIdx = flatIdx + 1
            end
            if flatIdx > #flatList then
                break
            end
            local it = flatList[flatIdx]
            flatIdx = flatIdx + 1
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
                secH = ((it.itemCount or 0) * ROW_STRIDE) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                if isExpanded then
                    M.CollectionVirtual_RefreshToyRowScrollIndex()
                    M.UpdateToyListVisibleRange()
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
                    M.CollectionVirtual_RefreshToyRowScrollIndex()
                    M.UpdateToyListVisibleRange()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    M.CollectionVirtual_RefreshToyRowScrollIndex()
                    M.UpdateToyListVisibleRange()
                end,
            }))
            if ns.UI_AnchorSectionHeaderInWrap then
                ns.UI_AnchorSectionHeaderInWrap(header, sectionWrap, listWidth)
            else
                header:ClearAllPoints()
                header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
                header:SetWidth(listWidth)
            end
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
            M.state._toySectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
            built = built + 1
        end

        if hasRemainingToyHeaders() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, pumpToyHeaders)
            else
                pumpToyHeaders()
            end
            return
        end
        finishToyListPopulate()
    end

    pumpToyHeaders()
end

function M.UpdateAchievementListVisibleRange()
    ns.UI_AchievementBrowse_UpdateVisibleRange({
        state = M.state,
        acquireRow = M.AcquireAchievementRow,
        releaseRowFrame = function(f)
            CollectionRowPool[#CollectionRowPool + 1] = f
        end,
    })
end

function M.PopulateAchievementList(scrollChild, listWidth, categoryData, rootCategories, collapsedHeaders, selectedAchievementID, onSelectAchievement, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    local searchSnap = M.state and M.state.searchText
    local searchActive = searchSnap and searchSnap ~= ""
    ns.UI_AchievementBrowse_Populate({
        state = M.state,
        scrollChild = scrollChild,
        listWidth = listWidth,
        categoryData = categoryData,
        rootCategories = rootCategories,
        collapsedHeaders = collapsedHeaders,
        selectedAchievementID = selectedAchievementID,
        onSelectAchievement = onSelectAchievement,
        contentFrameForRefresh = contentFrameForRefresh,
        redrawFn = redrawFn,
        acquireRow = M.AcquireAchievementRow,
        releaseRowFrame = function(f)
            CollectionRowPool[#CollectionRowPool + 1] = f
        end,
        scheduleVisibleSync = function(fn)
            M.ScheduleCollectionsVisibleSync("achievements", fn)
        end,
        rowHeightScale = ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE or 1.155,
        searchActive = searchActive,
        searchText = searchSnap,
        drawGen = drawGen,
        collectionsSubTabGen = M.state._collectionsSubTabGen,
        onListReady = onListReady,
    })
end

-- MODEL VIEWER PANEL — Mounts: Blizzard Mount Journal pipeline (ModelScene WrappedAndUnwrappedModelScene + TransitionToModelSceneID).
-- Pets/fallback: Frame (clip) + PlayerModel + interaction layer. Layout: viewport below descText.

local FIXED_CAM_SCALE = 1.8
local CAM_SCALE_MIN = 0.6
local CAM_SCALE_MAX = 6
local ZOOM_STEP = 0.1
local ROTATE_SENSITIVITY = 0.02
-- All models same size/position: we scale the model to REFERENCE_RADIUS, single fixed camera distance.
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
-- Viewport top gap (description → model; close to Mount Journal, tight)
local MODEL_VIEWPORT_TOP_GAP = 6
-- Pet: the thin band still nudges slightly up; when a mount uses full height these px may be inactive
local MOUNT_VIEWPORT_NUDGE_UP = 6
-- 1–2 px inside the viewport: softens the edge-hugging look (within the clip rect).
local MODEL_VIEWPORT_INSET = 2
-- Pet/PlayerModel: height ceiling in the wide slot. Removed for mounts (avoided large gap below + bottom clipping).
local MODEL_PREVIEW_MAX_HEIGHT_PER_WIDTH = 0.62
-- ModelScene: framing close to Mount Journal; a too-large mult could clip feet/bottom.
local MOUNT_JOURNAL_SCENE_BASE_DISTANCE_MULT = 1.04
-- ModelScene: nudge content slightly up (screen space; foot line close to Blizzard journal)
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
