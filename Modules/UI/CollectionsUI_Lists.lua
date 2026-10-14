--[[
    Warband Nexus - Collections tab (Lists)
    Loaded via WarbandNexus.toc after CollectionsUI_Shared.lua.

    WN_PERF: Mounts/Pets/Toys browse collapsible headers paint in COLLECTIONS_HEADER_CHUNK
    frames (C_Timer.After); drawGen + sub-tab gen cancel superseded pumps (WN-PERF-warband-nexus).
    Row windowing for every list here (Mounts/Pets/Toys and, via AchievementBrowseVirtualList,
    Achievements) is VirtualListModule.
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

-- Mount/Pet/Toy sectioned lists run on VirtualListModule (groupShellByKey mode): section wraps are
-- built inline by the chunked header pump, rows are culled + pooled by VirtualListModule and parented
-- under their section body at item.localY. The windowed list is the full flat list minus collapsed
-- sections' rows, with yOffset rewritten to the ChainSectionFrameBelow stacking: per section,
-- wrap height = COLLAPSE_HEADER_HEIGHT_COLL + (expanded and bodyContentHeight or 0.1).

--- Refill `out` IN PLACE (VirtualListModule keeps windowing that table). Returns scroll content height.
function M.CollectionVirtual_FillSectionWindowList(flatList, sectionContentH, collapsedHeaders, out)
    wipe(out)
    if not flatList then return 1 end
    local y = 0
    local firstSec = true
    local bodyTop = 0
    local expanded = false
    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
            if not firstSec then
                y = y + SECTION_SPACING
            end
            firstSec = false
            local key = it.key
            local secH = (sectionContentH and sectionContentH[key]) or 0
            if secH <= 0 and it.itemCount then
                secH = (it.itemCount * ROW_STRIDE)
            end
            expanded = collapsedHeaders and (collapsedHeaders[key] == false) or false
            local bodyH = expanded and math.max(0.1, secH) or 0.1
            it.yOffset = y
            out[#out + 1] = it
            bodyTop = y + COLLAPSE_HEADER_HEIGHT_COLL
            y = bodyTop + bodyH
        elseif expanded and it.type == "row" and it._collSectionKey then
            it.yOffset = bodyTop + (it._collRelY or 0)
            out[#out + 1] = it
        end
    end
    return math.max(y + PADDING, 1)
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

-- Stable row callbacks (no per-paint closures). AcquireCollectionRow stores the painted list item on
-- the row frame (_wnCollItem: .mount/.pet/.toy/.achievement) plus the list's onSelect callback
-- (_wnCollSelectCb); handlers below read those fields at click time.
local CollRowCb = {
    planSlotScratch = {},  -- filled by Acquire*Row, copied into the row frame's own table
}

function CollRowCb.OnMouseDown(row)
    local sel = row._wnCollSelect
    if sel then sel(row) end
    local refresh = row._wnCollRefresh
    if refresh then refresh(row) end
end

-- RowPool invokes planSlotState.onTodoClick/onTrackClick with no args: one thunk per frame, created once.
function CollRowCb.EnsureSlotThunks(f)
    if f._wnCollTodoThunk then return end
    f._wnCollTodoThunk = function()
        local h = f._wnCollTodoHandler
        if h then h(f) end
    end
    f._wnCollTrackThunk = function()
        local h = f._wnCollTrackHandler
        if h then h(f) end
    end
end

local function CollRowEntity(row, key)
    local item = row and row._wnCollItem
    return item and item[key]
end

function CollRowCb.MountSelect(row)
    local cb, mount = row._wnCollSelectCb, CollRowEntity(row, "mount")
    if cb and mount then
        cb(mount.id, mount.name, mount.icon, mount.source, mount.creatureDisplayID, mount.description, mount.isCollected)
    end
end
function CollRowCb.MountRefresh(row)
    local mount = CollRowEntity(row, "mount")
    if mount and M.state._mountFlatList and M.state.mountListScrollFrame then
        M.state._mountListSelectedID = mount.id
        local r = M.state._mountListRefreshVisible
        if r then r() end
    end
end
function CollRowCb.MountTodo(row)
    local WN = WarbandNexus
    local mount = CollRowEntity(row, "mount")
    if not WN or not mount then return end
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
    CollRowCb.MountRefresh(row)
end

function CollRowCb.PetSelect(row)
    local cb, pet = row._wnCollSelectCb, CollRowEntity(row, "pet")
    if cb and pet then
        cb(pet.id, pet.name, pet.icon, pet.source, pet.creatureDisplayID, pet.description, pet.isCollected)
    end
end
function CollRowCb.PetRefresh(row)
    local pet = CollRowEntity(row, "pet")
    if pet and M.state._petFlatList and M.state.petListScrollFrame then
        M.state._petListSelectedID = pet.id
        local r = M.state._petListRefreshVisible
        if r then r() end
    end
end
function CollRowCb.PetTodo(row)
    local WN = WarbandNexus
    local pet = CollRowEntity(row, "pet")
    if not WN or not pet then return end
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
    CollRowCb.PetRefresh(row)
end

local function CollToyIsCollected(toy)
    return (toy.isCollected == true) or (toy.collected == true)
end
function CollRowCb.ToySelect(row)
    local cb, toy = row._wnCollSelectCb, CollRowEntity(row, "toy")
    if cb and toy then
        cb(toy.id, toy.name, toy.icon, toy.source, toy.description, CollToyIsCollected(toy), toy.sourceTypeName)
    end
end
function CollRowCb.ToyRefresh(row)
    local toy = CollRowEntity(row, "toy")
    if toy and M.state._toyFlatList and M.state.toyListScrollFrame then
        M.state._toyListSelectedID = toy.id
        local r = M.state._toyListRefreshVisible
        if r then r() end
    end
end
function CollRowCb.ToyTodo(row)
    local WN = WarbandNexus
    local toy = CollRowEntity(row, "toy")
    if not WN or not toy then return end
    if WN.IsItemPlanned and WN:IsItemPlanned("toy", toy.id) then
        M.RemoveFirstMatchingPlan(function(p)
            return p.type == "toy" and p.itemID == toy.id
        end)
    elseif not CollToyIsCollected(toy) and WN.AddPlan then
        WN:AddPlan({
            type = "toy",
            itemID = toy.id,
            name = toy.name,
            icon = toy.icon,
            source = toy.sourceTypeName or "",
        })
    end
    CollRowCb.ToyRefresh(row)
end

function CollRowCb.AchSelect(row)
    local cb, ach = row._wnCollSelectCb, CollRowEntity(row, "achievement")
    if cb and ach then cb(ach) end
end
function CollRowCb.AchRefresh(row)
    local ach = CollRowEntity(row, "achievement")
    if ach and M.state._achFlatList and M.state.achievementListScrollFrame then
        M.state._achListSelectedID = ach.id
        local r = M.state._achListRefreshVisible
        if r then r() end
    end
end
function CollRowCb.AchTodo(row)
    local WN = WarbandNexus
    local ach = CollRowEntity(row, "achievement")
    if not WN or not ach or not ach.id then return end
    local planned = WN.IsAchievementPlanned and WN:IsAchievementPlanned(ach.id)
    if planned then
        M.RemoveFirstMatchingPlan(function(p)
            return p.type == "achievement" and p.achievementID == ach.id
        end)
    elseif not (ach.isCollected == true) and WN.AddPlan then
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
    CollRowCb.AchRefresh(row)
end
function CollRowCb.AchTrack(row)
    local WN = WarbandNexus
    local ach = CollRowEntity(row, "achievement")
    if WN and WN.ToggleAchievementTracking and ach and ach.id then
        WN:ToggleAchievementTracking(ach.id)
    end
    CollRowCb.AchRefresh(row)
end

-- Slot tooltip tables are read-only for consumers (RowPool SetCollectionPlanSlotTooltip reads
-- title/lines), so each variant is built once per session (only once ns.L exists) and shared.
local collPlanSlotTipCache = {}

function M.CollectionRowTodoSlotTooltip(onTodo, canInteract)
    local variant = onTodo and "todoRemove" or (canInteract and "todoAdd") or nil
    if not variant then return nil end
    local cached = collPlanSlotTipCache[variant]
    if cached then return cached end
    local L = ns.L
    local title = (L and L["COLLECTIONS_TT_TODO_TITLE"]) or "To-Do list"
    local tip
    if onTodo then
        tip = {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TODO_REMOVE"]) or "Left-click to remove this entry from your To-Do list." },
        }
    else
        tip = {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TODO_ADD"]) or "Left-click to add this entry to your To-Do list." },
        }
    end
    if L then collPlanSlotTipCache[variant] = tip end
    return tip
end

function M.CollectionRowTrackSlotTooltip(achCollected, onTrack)
    local variant = achCollected and "trackCompleted" or (onTrack and "trackDisable") or "trackEnable"
    local cached = collPlanSlotTipCache[variant]
    if cached then return cached end
    local L = ns.L
    local title = (L and L["COLLECTIONS_TT_TRACK_TITLE"]) or "Objectives tracker"
    local tip
    if achCollected then
        tip = {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TRACK_COMPLETED"]) or "This achievement is already completed. Tracking is not available." },
        }
    elseif onTrack then
        tip = {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TRACK_DISABLE"]) or "Left-click to stop tracking in Blizzard objectives." },
        }
    else
        tip = {
            title = title,
            lines = { (L and L["COLLECTIONS_TT_TRACK_ENABLE"]) or "Left-click to show progress in Blizzard objectives (up to 10 at once)." },
        }
    end
    if L then collPlanSlotTipCache[variant] = tip end
    return tip
end

-- Collection list row (SharedWidgets layout: status icon + icon + label). Used by Mounts, Pets, Toys, Achievements.
function M.CollectionRowPaintHeight(item)
    if item and item.rowPaintHeight and item.rowPaintHeight > 0 then
        return item.rowPaintHeight
    end
    return ROW_HEIGHT
end

--- Paint row content only (no pooling / anchoring). onSelect / refreshFn / planSlotState.onTodoClick /
--- onTrackClick are called with the row frame; selectCb (optional) is stored as row._wnCollSelectCb.
--- The painted item is kept on row._wnCollItem for the stable CollRowCb handlers.
function M.PaintCollectionRow(f, item, iconPath, labelText, isCollected, selectedID, itemID, onSelect, refreshFn, planSlotState, rightAlignedText, leftAlignedText, selectCb)
    f._wnCollItem = item
    f._wnCollSelectCb = selectCb
    f._wnCollSelect = onSelect
    f._wnCollRefresh = refreshFn
    local onClick = (onSelect or refreshFn) and CollRowCb.OnMouseDown or nil
    if planSlotState then
        -- RowPool's slot OnClick closures keep a reference to this table: one per frame, reused.
        local dst = f._wnCollPlanSlot
        if not dst then
            dst = {}
            f._wnCollPlanSlot = dst
        end
        wipe(dst)
        for k, v in pairs(planSlotState) do
            dst[k] = v
        end
        CollRowCb.EnsureSlotThunks(f)
        f._wnCollTodoHandler = planSlotState.onTodoClick
        f._wnCollTrackHandler = planSlotState.onTrackClick
        dst.onTodoClick = planSlotState.onTodoClick and f._wnCollTodoThunk or nil
        dst.onTrackClick = planSlotState.onTrackClick and f._wnCollTrackThunk or nil
        if planSlotState == CollRowCb.planSlotScratch then
            wipe(planSlotState)
        end
        planSlotState = dst
    else
        f._wnCollTodoHandler = nil
        f._wnCollTrackHandler = nil
    end
    Factory:ApplyCollectionListRowContent(f, item.rowIndex, iconPath, labelText, isCollected, (selectedID == itemID), onClick, rightAlignedText, nil, planSlotState, leftAlignedText)
    M.ApplyCollectionsRowIconChrome(f)
end

--- Pool + anchor + paint in one call (achievement browse `acquireRow` contract).
function M.AcquireCollectionRow(rowParent, item, leftIndent, iconPath, labelText, isCollected, selectedID, itemID, onSelect, refreshFn, planSlotState, rightAlignedText, leftAlignedText, selectCb)
    if not rowParent then return nil end
    local rowH = M.CollectionRowPaintHeight(item)
    local f = table.remove(CollectionRowPool)
    if not f then
        f = Factory:CreateCollectionListRow(rowParent, rowH)
        f:ClearAllPoints()
    end
    f:SetParent(rowParent)
    local rightPad = 4
    local yOffset = item._collRelY or item.yOffset or 0
    f:SetPoint("TOPLEFT", rowParent, "TOPLEFT", leftIndent or 0, -yOffset)
    f:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -rightPad, -yOffset)
    f:SetHeight(rowH)
    if f.SetClipsChildren then
        f:SetClipsChildren(true)
    end
    M.PaintCollectionRow(f, item, iconPath, labelText, isCollected, selectedID, itemID, onSelect, refreshFn, planSlotState, rightAlignedText, leftAlignedText, selectCb)
    f:Show()
    return f
end

--- VirtualListModule createRowFn for sectioned lists (pool miss only; rowPool = CollectionRowPool).
function M.CreateCollectionRowFrame(parent, item)
    return Factory:CreateCollectionListRow(parent, M.CollectionRowPaintHeight(item))
end

--- VirtualListModule populateRowFn: Mounts.
function M.PaintMountRow(f, item)
    local state = M.state
    local mount = item.mount
    local nameColor = mount.isCollected and CollectionsCollectedNameHex() or CollectionsUncollectedNameHex()
    local labelText = nameColor .. (mount.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("mount", mount.id)
    local WN = WarbandNexus
    local onTodo = WN and WN.IsMountPlanned and WN:IsMountPlanned(mount.id) or false
    local planSlotState = CollRowCb.planSlotScratch
    planSlotState.onTodo = onTodo
    planSlotState.onTrack = false
    planSlotState.achievementRow = false
    planSlotState.showTrackSlot = false
    planSlotState.todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not mount.isCollected)
    planSlotState.onTodoClick = (onTodo or not mount.isCollected) and CollRowCb.MountTodo or nil
    M.PaintCollectionRow(f, item, mount.icon or DEFAULT_ICON_MOUNT, labelText, mount.isCollected,
        state._mountListSelectedID or state.selectedMountID, mount.id,
        CollRowCb.MountSelect, CollRowCb.MountRefresh, planSlotState, nil, nil, state._mountListOnSelectMount)
end

--- VirtualListModule populateRowFn: Pets.
function M.PaintPetRow(f, item)
    local state = M.state
    local pet = item.pet
    local nameColor = pet.isCollected and CollectionsCollectedNameHex() or CollectionsUncollectedNameHex()
    local labelText = nameColor .. (pet.name or "") .. "|r" .. SD.FormatMountPetToyListTrySuffix("pet", pet.id)
    local WN = WarbandNexus
    local onTodo = WN and WN.IsPetPlanned and WN:IsPetPlanned(pet.id) or false
    local planSlotState = CollRowCb.planSlotScratch
    planSlotState.onTodo = onTodo
    planSlotState.onTrack = false
    planSlotState.achievementRow = false
    planSlotState.showTrackSlot = false
    planSlotState.todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not pet.isCollected)
    planSlotState.onTodoClick = (onTodo or not pet.isCollected) and CollRowCb.PetTodo or nil
    M.PaintCollectionRow(f, item, pet.icon or DEFAULT_ICON_PET, labelText, pet.isCollected,
        state._petListSelectedID or state.selectedPetID, pet.id,
        CollRowCb.PetSelect, CollRowCb.PetRefresh, planSlotState, nil, nil, state._petListOnSelectPet)
end

function M.CollectionsUsesToyListPipeline()
    local sub = M.state and M.state.currentSubTab
    return sub == "toys"
end

--- VirtualListModule populateRowFn: Toys.
function M.PaintToyRow(f, item)
    local state = M.state
    local toy = item.toy
    local nameColor = (toy.isCollected or toy.collected) and CollectionsCollectedNameHex() or CollectionsUncollectedNameHex()
    local trySuffix = (SD and SD.FormatMountPetToyListTrySuffix and toy.id)
        and SD.FormatMountPetToyListTrySuffix("toy", toy.id) or ""
    local labelText = nameColor .. (toy.name or "") .. "|r" .. trySuffix
    local WN = WarbandNexus
    local onTodo = WN and WN.IsItemPlanned and WN:IsItemPlanned("toy", toy.id) or false
    local toyCollected = CollToyIsCollected(toy)
    local planSlotState = CollRowCb.planSlotScratch
    planSlotState.onTodo = onTodo
    planSlotState.onTrack = false
    planSlotState.achievementRow = false
    planSlotState.showTrackSlot = false
    planSlotState.todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not toyCollected)
    planSlotState.onTodoClick = (onTodo or not toyCollected) and CollRowCb.ToyTodo or nil
    M.PaintCollectionRow(f, item, toy.icon or DEFAULT_ICON_TOY, labelText, toyCollected,
        state._toyListSelectedID or state.selectedToyID, toy.id,
        CollRowCb.ToySelect, CollRowCb.ToyRefresh, planSlotState, nil, nil, state._toyListOnSelectToy)
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
    local WN = WarbandNexus
    local onTodo = WN and WN.IsAchievementPlanned and WN:IsAchievementPlanned(ach.id) or false
    local onTrack = WN and WN.IsAchievementTracked and WN:IsAchievementTracked(ach.id) or false
    local planSlotState = CollRowCb.planSlotScratch
    planSlotState.onTodo = onTodo
    planSlotState.onTrack = onTrack
    planSlotState.achievementRow = true
    planSlotState.achievementCollected = achCollected
    planSlotState.todoTooltip = M.CollectionRowTodoSlotTooltip(onTodo, onTodo or not achCollected)
    planSlotState.trackTooltip = M.CollectionRowTrackSlotTooltip(achCollected, onTrack)
    planSlotState.onTodoClick = (onTodo or not achCollected) and CollRowCb.AchTodo or nil
    planSlotState.onTrackClick = (not achCollected) and CollRowCb.AchTrack or nil
    return M.AcquireCollectionRow(scrollChild, item, indent, ach.icon or DEFAULT_ICON_ACHIEVEMENT, labelText, ach.isCollected, selectedAchievementID, ach.id,
        CollRowCb.AchSelect, CollRowCb.AchRefresh, planSlotState, earnedEarnerRich, earnedDateRich, onSelectAchievement)
end

-- Sectioned Mount/Pet/Toy lists: one implementation, three configs. State keys keep their historical
-- names (`_mountFlatList`, `_mountListRefreshVisible`, ...) because CollectionsUI_Draw reads them.
local function SectionedListConfig(subTab, prefix, busyLabel, genKey, traceName, onSelectKey, iconFn, buildFn, paintFn)
    local cfg = {
        subTab = subTab,
        busyLabel = busyLabel,
        genKey = genKey,
        traceStart = traceName .. "_start",
        traceDone = traceName .. "_done",
        iconFn = iconFn,
        buildFn = buildFn,
        paintFn = paintFn,
        kFlat = prefix .. "FlatList",
        kWindow = prefix .. "WindowFlatList",
        kTotalH = prefix .. "FlatListTotalHeight",
        kSecH = prefix .. "SectionContentH",
        kBodies = prefix .. "SectionBodies",
        kWidth = prefix .. "ListWidth",
        kSelected = prefix .. "ListSelectedID",
        kOnSelect = onSelectKey,
        kCollapsed = prefix .. "ListCollapsedHeaders",
        kRedraw = prefix .. "ListRedrawFn",
        kContentFrame = prefix .. "ListContentFrame",
        kRefresh = prefix .. "ListRefreshVisible",
        kScrollFrame = subTab:sub(1, -2) .. "ListScrollFrame",
        kScrollChild = subTab:sub(1, -2) .. "ListScrollChild",
        kBar = subTab:sub(1, -2) .. "ListScrollBarContainer",
        busy = false,
        scrollCoalesce = false,
        lastContainer = nil,
    }
    --- Re-window the current list (scroll, selection change, sub-tab fast path).
    cfg.refresh = function()
        local sc = M.state[cfg.kScrollChild]
        local VLM = ns.VirtualListModule
        if sc and VLM then
            VLM.RepaintVisible(sc)
        end
    end
    --- Collapse model changed: refill the windowed list in place, resync scroll height, re-window.
    cfg.rebuildWindow = function()
        local state = M.state
        local window = state[cfg.kWindow]
        if not window then return end
        local contentH = M.CollectionVirtual_FillSectionWindowList(
            state[cfg.kFlat], state[cfg.kSecH], state[cfg.kCollapsed] or {}, window)
        state[cfg.kTotalH] = contentH
        CollectionVirtual_SyncListScrollChildHeight(
            state[cfg.kScrollChild], state[cfg.kScrollFrame], contentH, state[cfg.kBar])
    end
    cfg.rebuildAndRefresh = function()
        cfg.rebuildWindow()
        cfg.refresh()
    end
    -- Scroll deltas coalesce to one re-window on the next frame.
    cfg.onScroll = function()
        if cfg.scrollCoalesce then return end
        cfg.scrollCoalesce = true
        C_Timer.After(0, function()
            cfg.scrollCoalesce = false
            cfg.refresh()
        end)
    end
    return cfg
end

local SECTIONED_MOUNTS = SectionedListConfig("mounts", "_mount", "Mounts", "_mountsDrawGen", "PopulateMountList",
    "_mountListOnSelectMount",
    function(key) return SD.GetMountCategoryIcon(key) end,
    function(grouped, collapsed) return M.BuildFlatMountList(grouped, collapsed) end,
    M.PaintMountRow)
local SECTIONED_PETS = SectionedListConfig("pets", "_pet", "Pets", "_petDrawGen", "PopulatePetList",
    "_petListOnSelectPet",
    function(key) return SD.GetPetCategoryIcon(key) end,
    function(grouped, collapsed) return M.BuildFlatPetList(grouped, collapsed) end,
    M.PaintPetRow)
local SECTIONED_TOYS = SectionedListConfig("toys", "_toy", "Toys", "_toysDrawGen", "PopulateToyList",
    "_toyListOnSelectToy",
    function(key) return SD.GetToyCategoryIcon(key) end,
    function(grouped, collapsed) return M.BuildFlatToyList(grouped, collapsed, SD.TOY_SOURCE_CATEGORIES) end,
    M.PaintToyRow)

local _sectionedChildScratch = {}
local _sectionedRegionScratch = {}
local function PackVariadicInto(dest, ...)
    wipe(dest)
    local n = select("#", ...)
    for i = 1, n do
        dest[i] = select(i, ...)
    end
    return n
end

-- Populate scrollChild: build flat list, build section wraps (chunked: COLLECTIONS_HEADER_CHUNK per
-- frame, drawGen + sub-tab abort), then hand the windowed list to VirtualListModule.
-- redrawFn(contentFrame) is the caller's draw (DrawMountsContent etc.), stored for row callbacks.
local function PopulateSectionedList(cfg, scrollChild, listWidth, groupedData, collapsedHeaders, selectedID, onSelect, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    if not scrollChild or not Factory then return end
    local state = M.state
    if cfg.busy then
        -- An older pump is mid-chunk. Dropping this populate would leave the caller's
        -- draw busy flag held; if superseded release it, otherwise retry next tick
        -- (the old pump finishes or aborts on gen mismatch within a tick).
        if drawGen and state[cfg.genKey] and state[cfg.genKey] ~= drawGen then
            M.ReleaseCollectionsDrawBusy(cfg.busyLabel, drawGen)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                PopulateSectionedList(cfg, scrollChild, listWidth, groupedData, collapsedHeaders, selectedID, onSelect, contentFrameForRefresh, redrawFn, drawGen, onListReady)
            end)
        else
            M.ReleaseCollectionsDrawBusy(cfg.busyLabel, drawGen)
        end
        return
    end
    cfg.busy = true
    collapsedHeaders = collapsedHeaders or {}
    local VLM = ns.VirtualListModule
    local deferListChrome = M.CollectionsBeginListChromeDefer(M.CollectionsListChromeFramesForSubTab(cfg.subTab))
    local headerChunkSize = deferListChrome and COLLECTIONS_HEADER_CHUNK_DEFERRED or COLLECTIONS_HEADER_CHUNK
    M.CollectionsSubTabTrace(cfg.traceStart, { deferChrome = deferListChrome, headersChunk = headerChunkSize })
    local cf = contentFrameForRefresh
    local redraw = redrawFn or function() end

    listWidth = ns.UI_ResolveListContentWidth and ns.UI_ResolveListContentWidth(scrollChild, listWidth or 260, 0)
        or (listWidth or 260)
    scrollChild:SetWidth(listWidth)

    -- Return the previous paint's rows to CollectionRowPool BEFORE their section wraps are recycled
    -- (rows parent under section bodies; once a wrap is reparented they are no longer under the list).
    if VLM then
        VLM.ReleaseVisibleRows(cfg.lastContainer or scrollChild)
        if cfg.lastContainer and cfg.lastContainer ~= scrollChild then
            VLM.ReleaseVisibleRows(scrollChild)
        end
    end
    cfg.lastContainer = scrollChild
    -- Until finishPopulate refills it, a stray scroll/sync repaint must not paint rows into the old
    -- (about to be recycled) section bodies.
    if state[cfg.kWindow] then
        wipe(state[cfg.kWindow])
    end

    -- Clear existing children (section wraps from previous run); unparent to avoid accumulating on re-populate.
    -- KNOWN COST: section wraps/headers are rebuilt per populate (search keystroke after
    -- debounce, filter toggle). Reusing them needs an update mode on the
    -- CreateCollapsibleHeader factory (label/count text, expanded state, re-chaining)
    -- plus closure-lifetime review — a planned refactor, not a drop-in change here.
    local nch = PackVariadicInto(_sectionedChildScratch, scrollChild:GetChildren())
    for i = 1, nch do
        local c = _sectionedChildScratch[i]
        c:Hide()
        c:ClearAllPoints()
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    wipe(_sectionedChildScratch)
    local nrg = PackVariadicInto(_sectionedRegionScratch, scrollChild:GetRegions())
    for i = 1, nrg do
        _sectionedRegionScratch[i]:Hide()
    end
    wipe(_sectionedRegionScratch)

    local flatList = cfg.buildFn(groupedData, collapsedHeaders)

    if not M.FlatListHasDataRows(flatList) and M.TryShowCollectionsListEmpty(scrollChild, cfg.subTab) then
        state[cfg.kFlat] = flatList
        if state[cfg.kWindow] then
            wipe(state[cfg.kWindow])
        end
        M.CollectionsEndListChromeDefer()
        cfg.busy = false
        if onListReady then onListReady() end
        return
    end

    M.HideCollectionsListEmptyCards(scrollChild)

    local sectionBodies = {}
    state[cfg.kBodies] = sectionBodies
    local sectionContentH = {}
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
            sectionContentH[sk] = sh
        end
    end
    M.AnnotateFlatRowsByNearestHeader(flatList)

    local function finishPopulate()
        state[cfg.kFlat] = flatList
        state[cfg.kSecH] = sectionContentH
        state[cfg.kWidth] = listWidth
        state[cfg.kSelected] = selectedID
        state[cfg.kOnSelect] = onSelect
        state[cfg.kCollapsed] = collapsedHeaders
        state[cfg.kRedraw] = redraw
        state[cfg.kContentFrame] = cf
        state[cfg.kRefresh] = cfg.refresh
        local window = state[cfg.kWindow]
        if not window then
            window = {}
            state[cfg.kWindow] = window
        end
        cfg.rebuildWindow()
        local scrollFrame = state[cfg.kScrollFrame]
        if scrollFrame and VLM then
            -- Rows: pooled in CollectionRowPool, painted by cfg.paintFn, parented under their section
            -- body (groupShellByKey) at item.localY. Headers are the inline wraps built above.
            VLM.SetupVirtualList({ scroll = scrollFrame }, scrollChild, 0, window, {
                createRowFn = M.CreateCollectionRowFrame,
                populateRowFn = cfg.paintFn,
                rowPool = CollectionRowPool,
                groupShellByKey = sectionBodies,
                noStaggeredRepaint = true,
            })
            scrollFrame:SetScript("OnVerticalScroll", cfg.onScroll)
        end
        -- Re-show deferred list chrome first: VirtualListModule skips paints on hidden containers.
        M.CollectionsEndListChromeDefer()
        cfg.refresh()
        M.ScheduleCollectionsVisibleSync(cfg.subTab, cfg.refresh)
        M.CollectionsSubTabTrace(cfg.traceDone, { flatRows = flatList and #flatList or 0 })
        if type(onListReady) == "function" then
            onListReady()
        end
        cfg.busy = false
    end

    local function abortPopulate()
        M.CollectionsEndListChromeDefer()
        cfg.busy = false
        if drawGen then
            M.ReleaseCollectionsDrawBusy(cfg.busyLabel, drawGen)
        end
    end

    local collHdrChainTail = nil
    local flatIdx = 1
    local function hasRemainingHeaders()
        for hi = flatIdx, #flatList do
            if flatList[hi].type == "header" then
                return true
            end
        end
        return false
    end

    local function pumpHeaders()
        if drawGen and state[cfg.genKey] and state[cfg.genKey] ~= drawGen then
            abortPopulate()
            return
        end
        if drawGen and state._collectionsSubTabGen and state.currentSubTab ~= cfg.subTab then
            abortPopulate()
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
            local secH = sectionContentH[key] or 0
            if secH <= 0 then
                secH = ((it.itemCount or 0) * ROW_STRIDE) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                if isExpanded then
                    cfg.rebuildAndRefresh()
                end
            end, cfg.iconFn(key), true, 0, nil, ns.UI_BuildCollapsibleSectionOpts({
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
                updateVisibleFn = cfg.rebuildAndRefresh,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    cfg.rebuildAndRefresh()
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
            sectionBodies[key] = sectionBody

            collHdrChainTail = sectionWrap
            built = built + 1
        end

        if hasRemainingHeaders() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, pumpHeaders)
            else
                pumpHeaders()
            end
            return
        end
        finishPopulate()
    end

    pumpHeaders()
end

function M.PopulateMountList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedMountID, onSelectMount, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    PopulateSectionedList(SECTIONED_MOUNTS, scrollChild, listWidth, groupedData, collapsedHeaders, selectedMountID, onSelectMount, contentFrameForRefresh, redrawFn, drawGen, onListReady)
end

function M.PopulatePetList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedPetID, onSelectPet, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    PopulateSectionedList(SECTIONED_PETS, scrollChild, listWidth, groupedData, collapsedHeaders, selectedPetID, onSelectPet, contentFrameForRefresh, redrawFn, drawGen, onListReady)
end

function M.PopulateToyList(scrollChild, listWidth, groupedData, collapsedHeaders, selectedToyID, onSelectToy, contentFrameForRefresh, redrawFn, drawGen, onListReady)
    PopulateSectionedList(SECTIONED_TOYS, scrollChild, listWidth, groupedData, collapsedHeaders, selectedToyID, onSelectToy, contentFrameForRefresh, redrawFn, drawGen, onListReady)
end

local function ReleaseCollectionAchievementRow(f)
    CollectionRowPool[#CollectionRowPool + 1] = f
end

local function ScheduleCollectionAchievementVisibleSync(fn)
    M.ScheduleCollectionsVisibleSync("achievements", fn)
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
        releaseRowFrame = ReleaseCollectionAchievementRow,
        scheduleVisibleSync = ScheduleCollectionAchievementVisibleSync,
        rowHeightScale = ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE or 1.155,
        searchActive = searchActive,
        searchText = searchSnap,
        -- Only branches that actually hold visible (filtered) achievements. Mirroring every empty
        -- Blizzard journal category produced a wall of "(0)" headers that open onto nothing.
        hideEmptyCategories = true,
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
