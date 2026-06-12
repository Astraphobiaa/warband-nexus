--[[
    Warband Nexus - Plans browse tab virtual list / draw slice (ops-036)
    DrawBrowser, DrawBrowserResults, achievement browse virtual list.
    Loaded after PlansUI_SourceParser.lua, before PlansUI.lua.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local FontManager = ns.FontManager

local Browse = ns.PlansUI_Browse or {}
ns.PlansUI_Browse = Browse

local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local CreateSearchBox = ns.UI_CreateSearchBox
local CreateExpandableRow
local CardLayoutManager = ns.UI_CardLayoutManager
local FormatTextNumbers = ns.UI_FormatTextNumbers
local PLAN_TYPES = ns.PLAN_TYPES
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateResultsContainer = ns.UI_CreateResultsContainer
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

local ReflowPlansCardLayout
local TeardownPlansAchievementBrowse
local ProfileBool
local PlansContentPadH
local GetLayout
local getCachedCategoryTree
local setCachedCategoryTree
local PLANS_ACH_CATEGORY_CACHE_MIN_IDS

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

local function ResolvePlansContentWidth(parent, fallbackWidth)
    if parent and parent.GetWidth then
        local pw = parent:GetWidth()
        if pw and pw > 1 then
            return pw
        end
    end
    return fallbackWidth or 400
end

local function SchedulePlansVisibleSync(refreshFn)
    if type(refreshFn) ~= "function" then return end
    C_Timer.After(0, function()
        if (ns.PlansUI_GetCurrentCategory and ns.PlansUI_GetCurrentCategory()) ~= "achievement" then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return end
        refreshFn()
    end)
    C_Timer.After(0.05, function()
        if (ns.PlansUI_GetCurrentCategory and ns.PlansUI_GetCurrentCategory()) ~= "achievement" then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return end
        refreshFn()
    end)
end

function Browse.Install(addon, deps)
    ReflowPlansCardLayout = deps.ReflowPlansCardLayout
    TeardownPlansAchievementBrowse = deps.TeardownPlansAchievementBrowse
    ProfileBool = deps.ProfileBool
    PlansContentPadH = deps.PlansContentPadH
    GetLayout = deps.GetLayout
    getCachedCategoryTree = deps.cachedCategoryTree
    setCachedCategoryTree = deps.setCachedCategoryTree
    PLANS_ACH_CATEGORY_CACHE_MIN_IDS = deps.PLANS_ACH_CATEGORY_CACHE_MIN_IDS
    CreateExpandableRow = function(parent, width, rowHeight, data, isExpanded, onToggle)
        local fn = ns.UI_CreateExpandableRow
        if not fn then
            error("WarbandNexus: UI_CreateExpandableRow missing")
        end
        return fn(parent, width, rowHeight, data, isExpanded, onToggle)
    end
end

local function ClearPlanReminderForBrowseItem(addon, category, itemID)
    if not addon or not itemID or not addon.RemovePlanReminder then return end
    ns._plansBrowseReminderCleared = ns._plansBrowseReminderCleared or {}
    local memoKey = (category or "") .. ":" .. tostring(itemID)
    if ns._plansBrowseReminderCleared[memoKey] then return end
    local plans = addon.db and addon.db.global and addon.db.global.plans
    if not plans then return end
    for _, plan in pairs(plans) do
        if plan and plan.id and plan.type == category then
            local match = false
            if category == "mount" and plan.mountID == itemID then match = true
            elseif category == "pet" and plan.speciesID == itemID then match = true
            elseif category == "toy" and plan.itemID == itemID then match = true
            elseif category == "illusion" and (plan.illusionID == itemID or plan.sourceID == itemID) then match = true
            elseif category == "achievement" and plan.achievementID == itemID then match = true
            elseif category == "title" and plan.titleID == itemID then match = true
            end
            if match then
                local r = plan.reminder
                if r and r.enabled ~= false then
                    if addon:RemovePlanReminder(plan.id) then
                        ns._plansBrowseReminderCleared[memoKey] = true
                    end
                else
                    ns._plansBrowseReminderCleared[memoKey] = true
                end
                return
            end
        end
    end
    ns._plansBrowseReminderCleared[memoKey] = true
end

local function MergePlansBrowseResults(collectedList, uncollectedList, showPlanned, showCompleted)
    if showCompleted and showPlanned then
        local seen, out = {}, {}
        for i = 1, #(uncollectedList or {}) do
            local item = uncollectedList[i]
            local id = item and item.id
            if item and item.isPlanned and id and not seen[id] then
                seen[id] = true
                out[#out + 1] = item
            end
        end
        for i = 1, #(collectedList or {}) do
            local item = collectedList[i]
            local id = item and item.id
            if item and item.isPlanned and id and not seen[id] then
                seen[id] = true
                out[#out + 1] = item
            end
        end
        return out
    elseif showCompleted and not showPlanned then
        local out = {}
        for i = 1, #(collectedList or {}) do
            local item = collectedList[i]
            if item and item.isPlanned then
                out[#out + 1] = item
            end
        end
        return out
    elseif showPlanned and not showCompleted then
        local out = {}
        for i = 1, #(uncollectedList or {}) do
            local item = uncollectedList[i]
            if item and item.isPlanned then
                out[#out + 1] = item
            end
        end
        return out
    end
    return uncollectedList or {}
end

function WarbandNexus:DrawBrowser(parent, yOffset, width, category)
    parent._plansCardLayoutManager = nil
    if HideEmptyStateCard then
        HideEmptyStateCard(parent, "plans")
        HideEmptyStateCard(parent, "plans_browse")
    end
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end

    -- Use SharedWidgets search bar (like Items tab)
    -- Create results container that can be refreshed independently
    local padH = PlansContentPadH()
    local resultsContainer = CreateResultsContainer(parent, yOffset + 40, padH)
    if resultsContainer then
        resultsContainer._plansBrowseTopInset = yOffset + 40
    end
    if resultsContainer and SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(resultsContainer)
    end
    
    -- Create unique search ID for this category (e.g., "plans_mount", "plans_pet")
    local searchId = "plans_" .. (category or "unknown"):lower()
    local initialSearchText = SearchStateManager:GetQuery(searchId)
    
    local searchPlaceholder = format((ns.L and ns.L["SEARCH_CATEGORY_FORMAT"]) or "Search %s...", category)
    local searchContainer = CreateSearchBox(parent, width, searchPlaceholder, function(text)
        -- Update search state via SearchStateManager (debounced at search box)
        SearchStateManager:SetSearchQuery(searchId, text)
        
        -- Prepare container for rendering
        if resultsContainer then
            SearchResultsRenderer:PrepareContainer(resultsContainer)
        end
        
        -- Redraw only results in the container
        local resultsYOffset = 0
        self:DrawBrowserResults(resultsContainer, resultsYOffset, width, category, text)
    end, nil, initialSearchText or "", searchId)
    searchContainer:SetPoint("TOPLEFT", padH, -yOffset)
    searchContainer:SetPoint("TOPRIGHT", -padH, -yOffset)
    
    yOffset = yOffset + 40
    
    -- Initial draw of results
    local resultsYOffset = 0
    local actualResultsHeight = self:DrawBrowserResults(resultsContainer, resultsYOffset, width, category, initialSearchText or "")

    local measuredH = (resultsContainer and resultsContainer.GetHeight and resultsContainer:GetHeight()) or actualResultsHeight
    return yOffset + math.max(measuredH or 0, actualResultsHeight or 0, 1)
end

-- ACHIEVEMENTS BROWSE (To-Do ▸ Achievements) — Collections-parity virtual list + collapsible headers (AchievementBrowseVirtualList).

local COLLECTED_COLOR_PLANS_ACH = "|cff33e533"
local DEFAULT_ICON_PLANS_ACHIEVEMENT = "Interface\\Icons\\Achievement_General"

function WarbandNexus:DrawAchievementsTable(parent, results, yOffset, width, searchText)
    searchText = searchText or ""

    if #results == 0 then
        if parent.plansAchBrowseRoot then
            parent.plansAchBrowseRoot:Hide()
        end
        if parent._plansAchBrowseState then
            parent._plansAchBrowseState._achOuterScrollActive = false
        end
        local searchId = "plans_achievement"
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, searchText, searchId)
        SearchStateManager:UpdateResults(searchId, 0)
        return height
    end

    if parent.plansAchBrowseRoot then
        parent.plansAchBrowseRoot:Show()
    end

    local treeSource = getCachedCategoryTree()
    if not treeSource then
        local allCategoryIDs = GetCategoryList() or {}
        local catData = {}
        local roots = {}
        for index = 1, #allCategoryIDs do
            local categoryID = allCategoryIDs[index]
            local categoryName, parentCategoryID = GetCategoryInfo(categoryID)
            catData[categoryID] = {
                id = categoryID,
                name = categoryName or ((ns.L and ns.L["UNKNOWN_CATEGORY"]) or "Unknown Category"),
                parentID = parentCategoryID,
                children = {},
                order = index,
            }
        end
        for ai = 1, #allCategoryIDs do
            local categoryID = allCategoryIDs[ai]
            local data = catData[categoryID]
            if data then
                if data.parentID and data.parentID > 0 then
                    if catData[data.parentID] then
                        table.insert(catData[data.parentID].children, categoryID)
                    end
                else
                    table.insert(roots, categoryID)
                end
            end
        end
        treeSource = { categoryData = catData, rootCategories = roots }
        if #allCategoryIDs >= PLANS_ACH_CATEGORY_CACHE_MIN_IDS then
            setCachedCategoryTree(treeSource)
        end
    end

    local categoryData = {}
    for catID, src in pairs(treeSource.categoryData) do
        categoryData[catID] = {
            id = src.id, name = src.name, parentID = src.parentID,
            children = src.children, order = src.order,
            achievements = {},
        }
    end
    local rootCategories = treeSource.rootCategories

    local profileAchBrowse = WarbandNexus.db and WarbandNexus.db.profile
    local showCompletedAchBrowse = ProfileBool(profileAchBrowse, "plansShowCompleted", false)
    local showPlannedAchBrowse = ProfileBool(profileAchBrowse, "plansShowPlanned", false)
    -- Full uncollected browse only: mix of planned / not — suffix helps. Any filter that restricts to "on To-Do" makes (Planned) redundant noise.
    local showAchievementPlannedSuffix = (not showCompletedAchBrowse) and (not showPlannedAchBrowse)

    for ri = 1, #results do
        local achievement = results[ri]
        local categoryID = achievement.categoryID
        if not categoryID and GetAchievementCategory then
            categoryID = GetAchievementCategory(achievement.id)
            achievement.categoryID = categoryID
        end
        if categoryID and not categoryData[categoryID] and GetCategoryInfo then
            local walked = categoryID
            for _ = 1, 12 do
                local _, parentID = GetCategoryInfo(walked)
                if not parentID or parentID <= 0 then break end
                if categoryData[parentID] then
                    categoryID = parentID
                    achievement.categoryID = categoryID
                    break
                end
                walked = parentID
            end
        end
        if categoryData[categoryID] then
            achievement.isPlanned = self:IsAchievementPlanned(achievement.id)
            table.insert(categoryData[categoryID].achievements, achievement)
        end
    end

    local expandedGroups = ns.UI_GetExpandedGroups()
    local achExpandAll = self.achievementsExpandAllActive
    local searchActive = searchText ~= ""

    local collapsedHeaders = {}
    setmetatable(collapsedHeaders, {
        __index = function(t, k)
            local r = rawget(t, k)
            if r ~= nil then return r end
            if achExpandAll or searchActive then return false end
            if expandedGroups[k] == true then return false end
            return true
        end,
        __newindex = function(t, k, v)
            rawset(t, k, v)
            expandedGroups[k] = (v == false)
        end,
    })

    local layout = GetLayout()
    local achRowScale = ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE or 1.155
    local baseRowH = layout.rowHeight or layout.ROW_HEIGHT or 26
    local ROW_H = math.max(18, math.floor(baseRowH * achRowScale + 0.5))
    local innerPad = 8
    local listInnerW = math.max(40, width - innerPad * 2)

    local rootFrame = parent.plansAchBrowseRoot
    if not rootFrame then
        local rw, rh = math.max(listInnerW, 100), math.max(80, ROW_H * 14)
        rootFrame = ns.UI.Factory and ns.UI.Factory:CreateContainer(parent, rw, rh, false)
        if not rootFrame then
            rootFrame = CreateFrame("Frame", nil, parent)
            rootFrame:SetSize(rw, rh)
        end
        parent.plansAchBrowseRoot = rootFrame
    end
    if not parent._plansAchBrowseState then
        parent._plansAchBrowseState = {}
    end
    local st = parent._plansAchBrowseState

    -- Do not tear down st.achievementListScrollFrame here: on outer-scroll path it is the main tab ScrollFrame.
    DetachOwnedPlansInnerScroll(st, rootFrame)
    if st.achievementListScrollFrame == st._plansAchInnerScroll then
        st.achievementListScrollFrame = nil
    end

    if not st.achievementListScrollChild or st.achievementListScrollChild:GetParent() ~= rootFrame then
        if st.achievementListScrollChild then
            st.achievementListScrollChild:SetParent(nil)
        end
        local scNew = ns.UI.Factory:CreateContainer(rootFrame, listInnerW, 1, false)
        scNew:SetWidth(listInnerW)
        st.achievementListScrollChild = scNew
    end

    local tabScrollChild = parent:GetParent()
    local mfAch = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local mainScrollAch = mfAch and mfAch.scroll
    if (not mainScrollAch) and tabScrollChild and tabScrollChild.GetParent then
        local p = tabScrollChild:GetParent()
        if p and p.GetObjectType and p:GetObjectType() == "ScrollFrame" then
            mainScrollAch = p
        end
    end

    rootFrame:ClearAllPoints()
    rootFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(yOffset or 0))
    rootFrame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(yOffset or 0))

    local scrollChild = st.achievementListScrollChild
    scrollChild:SetWidth(listInnerW)

    if mainScrollAch then
        DetachOwnedPlansInnerScroll(st, rootFrame)
        scrollChild:SetParent(rootFrame)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)
        st.achievementListScrollFrame = mainScrollAch
        st._achUseOuterScroll = true
        st._achOuterScrollFrame = mainScrollAch
        st._achOuterScrollChild = tabScrollChild
    else
        st._achUseOuterScroll = false
        st._achOuterScrollFrame = nil
        st._achOuterScrollChild = nil
        local sf = st._plansAchInnerScroll
        if not sf then
            sf = ns.UI.Factory:CreateScrollFrame(rootFrame, "UIPanelScrollFrameTemplate", true)
            st._plansAchInnerScroll = sf
        end
        sf:SetParent(rootFrame)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)
        sf:SetPoint("BOTTOMRIGHT", rootFrame, "BOTTOMRIGHT", 0, 0)
        sf:Show()
        scrollChild:SetParent(sf)
        sf:SetScrollChild(scrollChild)
        scrollChild:ClearAllPoints()
        scrollChild:SetPoint("TOPLEFT", sf, "TOPLEFT", 0, 0)
        st.achievementListScrollFrame = sf
    end

    local scrollFrame = st.achievementListScrollFrame

    local flatListOpts = { rowHeightScale = achRowScale }
    if searchActive then
        flatListOpts.searchActive = true
    end
    local _, totalPrev = ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders, flatListOpts)
    rootFrame:SetHeight(math.max(1, totalPrev))
    if parent.SetHeight then
        parent:SetHeight(math.max(1, (yOffset or 0) + totalPrev + innerPad))
    end

    local rowPool = parent._plansAchBrowseRowPool
    if not rowPool then
        rowPool = {}
        parent._plansAchBrowseRowPool = rowPool
    end

    local function releaseRowFrame(f)
        if not f then return end
        f:Hide()
        f:ClearAllPoints()
        rowPool[#rowPool + 1] = f
    end

    local function refreshVisible()
        if st._achListRefreshVisible then
            st._achListRefreshVisible()
        end
    end

    local Factory = ns.UI.Factory

    local function acquireRow(scChild, listW, item, selectedID, onSelect, redraw, cf)
        local ach = item.achievement
        if not ach then return nil end
        local rowParent = scChild
        if item._collSectionKey and st._achSectionBodies and st._achSectionBodies[item._collSectionKey] then
            rowParent = st._achSectionBodies[item._collSectionKey]
        end
        local indent = item.indent or 0
        local rowItem = item
        if item._collRelY then
            rowItem = {
                achievement = ach,
                rowIndex = item.rowIndex,
                yOffset = item._collRelY,
                height = item.height,
                rowPaintHeight = item.rowPaintHeight,
                indent = indent,
            }
        end

        local paintH = (rowItem.rowPaintHeight and rowItem.rowPaintHeight > 0) and rowItem.rowPaintHeight or ROW_H
        local row = table.remove(rowPool)
        if not row then
            row = Factory:CreateCollectionListRow(rowParent, paintH)
        else
            row:SetParent(rowParent)
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", indent, -(rowItem.yOffset or 0))
        row:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -4, -(rowItem.yOffset or 0))
        row:SetHeight(paintH)
        if row.SetClipsChildren then
            row:SetClipsChildren(true)
        end

        local title = FormatTextNumbers(ach.name or "")
        if ach.isPlanned and showAchievementPlannedSuffix then
            title = title .. " |cffffcc00(" .. ((ns.L and ns.L["PLANNED"]) or "Planned") .. ")|r"
        end
        local pointsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
        local nameColor = ach.isCollected and COLLECTED_COLOR_PLANS_ACH or "|cffffffff"
        local labelText = nameColor .. title .. "|r" .. pointsStr

        local function IsTracked(id)
            return WarbandNexus.IsAchievementTracked and WarbandNexus:IsAchievementTracked(id)
        end

        local applyAchRowPlanSlots
        applyAchRowPlanSlots = function()
            local L = ns.L
            local col = ach.isCollected == true
            local tracked = IsTracked(ach.id)
            local plannedNow = WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(ach.id) or false
            local todoTip = plannedNow and ((L and L["TODO_SLOT_TOOLTIP_REMOVE"]) or "Click to remove from your To-Do list.")
                or (not col and ((L and L["TODO_SLOT_TOOLTIP_ADD"]) or "Click to add to your To-Do list.") or "")
            local trackTip = col and ((L and L["TRACK_SLOT_DISABLED_COMPLETED"]) or "Completed achievements cannot be tracked in objectives.")
                or (tracked and ((L and L["TRACK_SLOT_TOOLTIP_UNTRACK"]) or "Click to stop tracking in Blizzard objectives."))
                or ((L and L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)")
            Factory:ApplyCollectionListRowContent(row, item.rowIndex or 1, ach.icon or DEFAULT_ICON_PLANS_ACHIEVEMENT, labelText, col, false, nil, nil, nil, {
                onTodo = plannedNow,
                onTrack = tracked,
                achievementRow = true,
                achievementCollected = col,
                todoTooltip = todoTip,
                trackTooltip = trackTip,
                onTodoClick = (plannedNow or not col) and function()
                    if not WarbandNexus then return end
                    if WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(ach.id) then
                        local plans = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.plans
                        if plans then
                            for pi = 1, #plans do
                                local p = plans[pi]
                                if p and p.id and p.type == PLAN_TYPES.ACHIEVEMENT and p.achievementID == ach.id then
                                    WarbandNexus:RemovePlan(p.id)
                                    break
                                end
                            end
                        end
                        ach.isPlanned = false
                        refreshVisible()
                    elseif not col and WarbandNexus.AddPlan then
                        WarbandNexus:AddPlan({
                            type = PLAN_TYPES.ACHIEVEMENT,
                            achievementID = ach.id,
                            name = ach.name,
                            icon = ach.icon,
                            points = ach.points,
                            source = ach.source,
                        })
                        ach.isPlanned = true
                        refreshVisible()
                    end
                end or nil,
                onTrackClick = (not col) and function()
                    if WarbandNexus.ToggleAchievementTracking then
                        WarbandNexus:ToggleAchievementTracking(ach.id)
                    end
                    applyAchRowPlanSlots()
                end or nil,
            })
            if row.label then
                local labelPad = layout.SIDE_MARGIN or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 10
                row.label:SetPoint("RIGHT", row, "RIGHT", -labelPad, 0)
                if row.label.SetMouseClickEnabled then
                    row.label:SetMouseClickEnabled(false)
                end
            end
        end
        applyAchRowPlanSlots()

        if row._wnPlansTrackBtn then
            row._wnPlansTrackBtn:Hide()
            row._wnPlansTrackBtn:SetScript("OnEnter", nil)
            row._wnPlansTrackBtn:SetScript("OnLeave", nil)
            row._wnPlansTrackBtn:SetScript("OnClick", nil)
        end
        if row._wnPlansAddBtn then
            row._wnPlansAddBtn:Hide()
        end
        if row._wnPlansAddedFs then
            row._wnPlansAddedFs:Hide()
        end

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", self, "TOPRIGHT", 6, 0)
            if GameTooltip.SetAchievementByID then
                GameTooltip:SetAchievementByID(ach.id)
            elseif ach.name then
                GameTooltip:SetText(ach.name, 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:Show()
        return row
    end

    SearchStateManager:UpdateResults("plans_achievement", #results)

    ns._plansAchPopulateGen = (ns._plansAchPopulateGen or 0) + 1
    local popGen = ns._plansAchPopulateGen
    local catBodyGen = ns._plansCategoryBodyGen or 0
    st._achPopulateGen = popGen
    st._plansCategoryGen = catBodyGen
    local populateOpts = {
        state = st,
        scrollChild = scrollChild,
        listWidth = listInnerW,
        categoryData = categoryData,
        rootCategories = rootCategories,
        collapsedHeaders = collapsedHeaders,
        selectedAchievementID = nil,
        onSelectAchievement = nil,
        contentFrameForRefresh = parent,
        redrawFn = nil,
        acquireRow = acquireRow,
        releaseRowFrame = releaseRowFrame,
        scheduleVisibleSync = SchedulePlansVisibleSync,
        rowHeightScale = achRowScale,
        searchActive = searchActive,
        searchText = searchText,
        drawGen = popGen,
        plansCategoryGen = catBodyGen,
        onListReady = function()
            if searchActive and mainScrollAch and mainScrollAch.SetVerticalScroll then
                mainScrollAch:SetVerticalScroll(0)
            end
            if st._achListRefreshVisible then
                st._achListRefreshVisible()
            end
            if ns.UI_EnsureMainScrollLayout then
                ns.UI_EnsureMainScrollLayout()
            end
        end,
    }

    ns.UI_AchievementBrowse_Populate(populateOpts)
    if Factory.UpdateScrollBarVisibility and scrollFrame and not st._achUseOuterScroll then
        Factory:UpdateScrollBarVisibility(scrollFrame)
    end
    local totalHNow = st._achFlatListTotalHeight or totalPrev or 1
    rootFrame:SetHeight(math.max(1, totalHNow))
    if parent.SetHeight then
        parent:SetHeight(math.max(1, (yOffset or 0) + totalHNow + innerPad))
    end
    if ns.UI_EnsureMainScrollLayout then
        ns.UI_EnsureMainScrollLayout()
    end

    local totalH = totalHNow
    rootFrame:SetHeight(math.max(1, totalH))
    return (yOffset or 0) + totalH + innerPad
end

-- BROWSER RESULTS RENDERING (Separated for search refresh)

-- Phase 4.4: Performance limit for browse results rendering
local MAX_BROWSE_RESULTS = 100
local PLANS_BROWSE_CARD_CHUNK = 8
-- Collected fetch for Plans browse: Show Completed filters collected rows by isPlanned. A low cap (e.g. 50)
-- leaves tabs empty when the user's planned-completed entries are not among the first N collected (Achievements already used 99999).
local COLLECTED_BROWSE_FETCH_LIMIT = 99999

local PLANS_BROWSE_STORE_CATEGORIES = {
    mount = true, pet = true, toy = true, illusion = true, title = true,
}

local function RunChunkedPlansBrowseCardPaint(opts)
    local addon = opts.addon
    local parent = opts.parent
    local layoutManager = opts.layoutManager
    local results = opts.results
    local resultsToRender = opts.resultsToRender
    local category = opts.category
    local cardWidth = opts.cardWidth
    local todoHeaderH = opts.todoHeaderH
    local PCM = opts.PCM
    local browseExpanded = opts.browseExpanded
    local browserTryTypes = opts.browserTryTypes
    local drawGen = opts.drawGen
    local baseYOffset = opts.yOffset or 0
    if not addon or not parent or not layoutManager or not results then return end

    local idx = 1
    local function pump()
        if ns._plansBrowsePaintGen ~= drawGen then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return end
        if not parent:GetParent() then return end

        local limit = math.min(idx + PLANS_BROWSE_CARD_CHUNK - 1, resultsToRender)
        for i = idx, limit do
            local item = results[i]
            item.category = category
            addon:RenderPlansBrowseUnifiedRow(parent, layoutManager, item, category, i, cardWidth, todoHeaderH, PCM, browseExpanded, browserTryTypes)
        end
        idx = limit + 1

        if idx <= resultsToRender then
            C_Timer.After(0, pump)
            return
        end

        ReflowPlansCardLayout(layoutManager)
        if ns.UI_SyncPlansScrollContentHeight then
            ns.UI_SyncPlansScrollContentHeight(parent)
        end
        local yOff = CardLayoutManager and CardLayoutManager:GetFinalYOffset(layoutManager) or baseYOffset
        local totalH = yOff + 10
        if parent.SetHeight then
            parent:SetHeight(math.max(totalH, 1))
        end
        if ns.UI_EnsureMainScrollLayout then
            ns.UI_EnsureMainScrollLayout()
        end
    end

    C_Timer.After(0, pump)
end

--- One EnsureCollectionData request per browse category until scan completes (stops PopulateContent loops).
ns._plansBrowseCollectionEnsurePending = ns._plansBrowseCollectionEnsurePending or {}
ns._plansBrowseScanUIMilestone = ns._plansBrowseScanUIMilestone or {}

local function PlansBrowseCategoryStoreEmpty(category)
    if WarbandNexus and WarbandNexus.IsPlansBrowseCategoryStoreEmpty then
        return WarbandNexus:IsPlansBrowseCategoryStoreEmpty(category)
    end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local store = db and db.collectionStore
    if not store then return true end
    local tbl = store[category]
    return not tbl or next(tbl) == nil
end

function ns.RequestPlansBrowseCollectionEnsure(category)
    if not category or not PLANS_BROWSE_STORE_CATEGORIES[category] then return end
    if ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading then return end
    local cs = ns.PlansLoadingState and ns.PlansLoadingState[category]
    if cs and cs.isLoading then return end
    if not PlansBrowseCategoryStoreEmpty(category) then
        ns._plansBrowseCollectionEnsurePending[category] = nil
        return
    end
    if ns._plansBrowseCollectionEnsurePending[category] then return end
    ns._plansBrowseCollectionEnsurePending[category] = true
    if ns.ScheduleEnsureCollectionDataDeferred then
        ns.ScheduleEnsureCollectionDataDeferred()
    elseif WarbandNexus and WarbandNexus.EnsureCollectionData then
        WarbandNexus:EnsureCollectionData()
    end
end

local function DrawPlansBrowseLoadingCard(parent, yOffset, category, categoryState)
    local collLoading = ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading
    local state = collLoading and ns.CollectionLoadingState or categoryState
    local loadingStateData = {
        isLoading = true,
        loadingProgress = (state and state.loadingProgress) or 0,
        currentStage = (state and state.currentStage) or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
    }
    local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
    if not UI_CreateLoadingStateCard then
        return yOffset + 120
    end
    local categoryNameMap = {
        mount = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts",
        pet = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets",
        toy = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys",
        achievement = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements",
        illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
        title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
        transmog = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog",
    }
    local displayName = categoryNameMap[category] or (category and (category:gsub("^%l", string.upper) .. "s")) or "Items"
    return UI_CreateLoadingStateCard(
        parent,
        yOffset,
        loadingStateData,
        format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
    )
end

local function DrawPlansBrowseEmptyCard(parent, yOffset, width, category, searchText, showPlanned, showCompleted)
    local st = searchText or ""
    if st ~= "" and SearchResultsRenderer and SearchResultsRenderer.RenderEmptyState then
        local searchId = "plans_" .. (category or "unknown"):lower()
        return SearchResultsRenderer:RenderEmptyState(WarbandNexus, parent, st, searchId)
    end
    local L = ns.L
    local labelCat = category or "item"
    local titleStr
    local descStr
    if showCompleted and showPlanned then
        titleStr = (L and L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"]) or "Nothing to show"
        descStr = (L and L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"])
            or "No planned items in this category match these filters. Add entries to your To-Do or adjust Show Planned / Show Completed."
    elseif showCompleted and not showPlanned then
        titleStr = (L and L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"]) or "No completed To-Do items"
        descStr = (L and L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"])
            or "Nothing on your To-Do List in this category is collected or completed yet. Turn off Show Completed to see entries still in progress."
    elseif showPlanned and not showCompleted then
        titleStr = (L and L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"]) or "No in-progress To-Do items"
        descStr = (L and L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"])
            or "Nothing on your To-Do List in this category is still uncollected. Turn on Show Completed to see finished ones, or add goals from this tab."
    else
        titleStr = (L and L["ALL_COLLECTED_CATEGORY"] and format(L["ALL_COLLECTED_CATEGORY"], labelCat))
            or ("All " .. labelCat .. "s collected!")
        descStr = (L and L["COLLECTED_EVERYTHING"]) or "You've collected everything in this category!"
    end
    local atlasByCategory = {
        mount = "dragon-rostrum",
        pet = "WildBattlePetCapturable",
        toy = "CreationCatalyst-32x32",
        transmog = "poi-transmogrifier",
        illusion = "UpgradeItem-32x32",
        title = "poi-legendsoftheharanir",
        achievement = "Achievement-Icon",
    }
    if ns.UI_ShowTabEmptyStateCard then
        return ns.UI_ShowTabEmptyStateCard(parent, "plans", yOffset, {
            fillParent = true,
            cacheKey = "plans_browse",
            titleText = titleStr,
            descText = descStr,
            atlas = atlasByCategory[category] or "poi-workorders",
        })
    end
    return yOffset + 200
end

--- Single browse card: To-Do unified expandable row (Mounts / Pets / Toys / Illusions / Titles / Transmog).
function WarbandNexus:RenderPlansBrowseUnifiedRow(parent, layoutManager, item, category, gridIndex, cardWidth, todoHeaderH, PCM, browseExpanded, browserTryTypes)
    if not item or not layoutManager or not parent then return end
    local PCF = ns.UI_PlanCardFactory
    local isCompletedCard = (item.isCollected == true)
    if isCompletedCard and item.isPlanned and item.id then
        ClearPlanReminderForBrowseItem(self, category, item.id)
    end

    local sourceMissing = not item.source
    if not sourceMissing and item.source then
        if issecretvalue and issecretvalue(item.source) then
            sourceMissing = true
        elseif item.source == "" then
            sourceMissing = true
        end
    end
    if sourceMissing and item.id then
        if category == "mount" and C_MountJournal and C_MountJournal.GetMountInfoExtraByID then
            local ok, _, _, src = pcall(C_MountJournal.GetMountInfoExtraByID, item.id)
            if ok and src and type(src) == "string" and not (issecretvalue and issecretvalue(src)) and src ~= "" then
                item.source = src
            end
        elseif category == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
            local ok, _, _, _, _, src = pcall(C_PetJournal.GetPetInfoBySpeciesID, item.id)
            if ok and src and type(src) == "string" and not (issecretvalue and issecretvalue(src)) and src ~= "" then
                item.source = src
            end
        end
    end

    local sources = self:ParseMultipleSources(item.source)
    local expandKey = (category or "x") .. ":" .. tostring(item.id or gridIndex)
    local isExpanded = false
    browseExpanded[expandKey] = false
    local col = (gridIndex - 1) % 2

    local trySuffix = ""
    if browserTryTypes[category] and item.id and self.ShouldShowTryCountInUI
        and self:ShouldShowTryCountInUI(category, item.id) and self.GetTryCount then
        local count = self:GetTryCount(category, item.id) or 0
        local triesLabel = (ns.L and ns.L["TRIES"]) or "Tries"
        trySuffix = "|cffaaddff" .. triesLabel .. ":|r |cffffffff" .. tostring(count) .. "|r"
    end

    local summaryLines = ns.UI_BuildBrowseTodoSummaryLines and ns.UI_BuildBrowseTodoSummaryLines(item, category, sources, { maxLines = 2 }) or {}
    local allSourceItems = ns.UI_BuildBrowseSourceCriteriaItems and ns.UI_BuildBrowseSourceCriteriaItems(item, category, sources) or {}
    local canExpand = false

    local typeAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS[category]

    local displayName = FormatTextNumbers(item.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"))
    local iconTexture = item.iconAtlas or item.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
    local iconIsAtlas = (item.iconAtlas ~= nil)
    local ACTION_SIZE = (ns.UI_PlansHeaderActionSize and ns.UI_PlansHeaderActionSize()) or ((PCM and PCM.todoTypeBadgeSize) or 24)
    local ACTION_GAP = 4
    local titleRightInset = 6 + ACTION_SIZE + ACTION_GAP
    if not item.isPlanned and not isCompletedCard then
        titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
    end
    if trySuffix ~= "" then
        titleRightInset = titleRightInset + ((PCM and PCM.todoMetaRightReserve) or 76)
    end

    local collapsedH = ns.UI_PlansTodoFixedCollapsedHeight and ns.UI_PlansTodoFixedCollapsedHeight(true)
        or todoHeaderH
    local rowData = {
        todoUnifiedHeader = true,
        summaryInHeader = true,
        canExpand = canExpand,
        icon = iconTexture,
        iconIsAtlas = iconIsAtlas,
        iconSize = (PCM and PCM.todoUnifiedIconSize) or 40,
        typeAtlas = typeAtlas,
        title = displayName,
        summaryLines = summaryLines,
        metaRightText = (trySuffix ~= "") and trySuffix or nil,
        collapsedHeight = collapsedH,
        criteriaData = isExpanded and allSourceItems or {},
        criteriaShowHeader = false,
        titleRightInset = titleRightInset,
        onSectionResize = function(rowFrame, currentH)
            if CardLayoutManager and CardLayoutManager.UpdateCardHeight then
                CardLayoutManager:UpdateCardHeight(rowFrame, currentH)
            end
            if ns.UI_SyncPlansScrollContentHeight then
                ns.UI_SyncPlansScrollContentHeight(parent)
            end
        end,
        onExpandPopulate = function(data)
            local all = ns.UI_BuildBrowseSourceCriteriaItems and ns.UI_BuildBrowseSourceCriteriaItems(item, category, sources) or {}
            if #all > 1 then
                local rest = {}
                for si = 2, #all do
                    rest[#rest + 1] = all[si]
                end
                data.criteriaData = rest
            else
                data.criteriaData = all
            end
            data.criteriaShowHeader = false
            data.summaryInHeader = true
        end,
    }

    local row = CreateExpandableRow(parent, cardWidth, collapsedH, rowData, isExpanded, function(expanded)
        browseExpanded[expandKey] = expanded
        if layoutManager and CardLayoutManager then
            CardLayoutManager:RecalculateAllPositions(layoutManager)
            if ns.UI_SyncPlansScrollContentHeight then
                ns.UI_SyncPlansScrollContentHeight(parent)
            end
        end
    end)
    if not row then return end
    row:SetWidth(cardWidth)
    CardLayoutManager:AddCard(layoutManager, row, col, collapsedH)
    if row.isExpanded then
        CardLayoutManager:UpdateCardHeight(row, row:GetHeight())
    end

    if ApplyVisuals then
        local borderColor
        if item.isCollected or item.isPlanned then
            borderColor = { 0.30, 0.90, 0.30, 0.8 }
        else
            borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 }
        end
        ApplyVisuals(row, COLORS.bgCard, borderColor)
    end

    local rightOffset = 6
    row._todoActionControls = {}
    row._todoActionOffsets = {}
    local function anchorAction(control, w)
        if not control then return end
        w = w or ACTION_SIZE
        row._todoActionControls[#row._todoActionControls + 1] = control
        row._todoActionOffsets[#row._todoActionOffsets + 1] = rightOffset
        if ns.UI_PlansAnchorHeaderAction then
            ns.UI_PlansAnchorHeaderAction(control, row.headerFrame, rightOffset, w, 0, row.iconFrame)
        else
            control:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
        end
        rightOffset = rightOffset + w + ACTION_GAP
    end

    if item.isPlanned and PCF and PCF.CreateAddButton then
        local plannedBtn = PCF.CreateAddButton(row.headerFrame, {
            buttonType = "card",
            iconOnly = true,
            plannedState = true,
            width = ACTION_SIZE,
            height = ACTION_SIZE,
        })
        if plannedBtn then anchorAction(plannedBtn, ACTION_SIZE) end
    elseif not isCompletedCard and PCF and PCF.CreateAddButton then
        local addBtn = PCF.CreateAddButton(row.headerFrame, {
            buttonType = "card",
            iconOnly = true,
            width = ACTION_SIZE,
            height = ACTION_SIZE,
            onClick = function(btn)
                local planData = {
                    itemID = (category == "toy") and item.id or item.itemID,
                    name = item.name,
                    icon = item.icon,
                    source = item.source,
                    mountID = (category == "mount") and item.id or nil,
                    speciesID = (category == "pet") and item.id or nil,
                    achievementID = (category == "achievement") and item.id or nil,
                    illusionID = (category == "illusion") and item.id or nil,
                    titleID = (category == "title") and item.id or nil,
                    rewardText = item.rewardText,
                    type = category,
                }
                self:AddPlan(planData)
                if ApplyVisuals then
                    ApplyVisuals(row, COLORS.bgCard, { 0.30, 0.90, 0.30, 0.8 })
                end
                btn:Hide()
                local plannedBtn = PCF.CreateAddButton(row.headerFrame, {
                    buttonType = "card",
                    iconOnly = true,
                    plannedState = true,
                    width = ACTION_SIZE,
                    height = ACTION_SIZE,
                })
                if plannedBtn then anchorAction(plannedBtn, ACTION_SIZE) end
            end,
        })
        if addBtn then anchorAction(addBtn, ACTION_SIZE) end
    end

    if ns.UI_PlansSyncTitleRightInset then
        ns.UI_PlansSyncTitleRightInset(row, rightOffset)
    end

    if category == "title" and item.sourceAchievement then
        row.headerFrame:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                self:ShowTab("achievements")
            end
        end)
    end

    if browserTryTypes[category] and item.id and self.ShouldShowTryCountInUI
        and self:ShouldShowTryCountInUI(category, item.id) then
        local tryId, tryName, tryCat = item.id, item.name, category
        local prevMouseDown
        do
            local ok, res = pcall(function() return row.headerFrame:GetScript("OnMouseDown") end)
            if ok then prevMouseDown = res end
        end
        row.headerFrame:SetScript("OnMouseDown", function(frame, button)
            if button == "RightButton" then
                if WarbandNexus.ShouldShowTryCountInUI and WarbandNexus:ShouldShowTryCountInUI(tryCat, tryId) and ns.UI_ShowTryCountPopup then
                    ns.UI_ShowTryCountPopup(tryCat, tryId, tryName)
                end
                return
            end
            if prevMouseDown then prevMouseDown(frame, button) end
        end)
    end

    row:Show()
end

function WarbandNexus:DrawBrowserResults(parent, yOffset, width, category, searchText)
    if category ~= "achievement" then
        TeardownPlansAchievementBrowse(parent)
        ns._plansAchOuterVirtualState = nil
    end

    -- Same path as search refresh: repool/recycle children so achievement section rebuild is clean.
    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer and parent then
        SearchResultsRenderer:PrepareContainer(parent)
    elseif parent and parent.GetChildren then
        local children = { parent:GetChildren() }
        for chi = 1, #children do
            local child = children[chi]
            if child and child.Hide then
                child:Hide()
            end
        end
    end

    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local showCompletedBrowse = ProfileBool(profile, "plansShowCompleted", false)
    local showPlannedBrowse = ProfileBool(profile, "plansShowPlanned", false)
    
    -- Initialize category state if needed
    if not ns.PlansLoadingState[category] then
        ns.PlansLoadingState[category] = { isLoading = false, loader = nil }
    end
    
    local categoryState = ns.PlansLoadingState[category]
    
    -- UNIFIED LOADING STATE: Core init (EnsureCollectionData) veya kategori scan
    local collLoading = ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading
    local categoryLoading = categoryState.isLoading
    if collLoading or categoryLoading then
        local state = collLoading and ns.CollectionLoadingState or categoryState
        local loadingStateData = {
            isLoading = true,
            loadingProgress = (state and state.loadingProgress) or 0,
            currentStage = (state and state.currentStage) or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
        }
        
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            -- Use localized category name for display
            local categoryNameMap = {
                mount = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts",
                pet = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets",
                toy = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys",
                achievement = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements",
                illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
                title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
                transmog = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog",
            }
            local displayName = categoryNameMap[category] or (category:gsub("^%l", string.upper) .. "s")

            if category == "achievement" and parent._plansAchBrowseState then
                parent._plansAchBrowseState._achOuterScrollActive = false
            end

            local newYOffset = UI_CreateLoadingStateCard(
                parent, 
                yOffset, 
                loadingStateData, 
                format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
            )
            return newYOffset
        else
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("|cffff0000[WN PlansUI]|r UI_CreateLoadingStateCard not found!")
            end
            return yOffset + 120
        end
    end
    
    -- Fetch lists: neither checkbox = uncollected only; Show Completed = use collected list (filtered to planned);
    -- Show Planned without Completed = uncollected + planned; both = union of planned from both lists.
    local needUncollected = (not showCompletedBrowse) or (showPlannedBrowse and showCompletedBrowse)
    local needCollected = showCompletedBrowse

    local resultsUncollected = {}
    local resultsCollected = {}

    local dbgPlansBrowse = IsDebugModeEnabled and IsDebugModeEnabled()
    if category == "mount" then
        if needUncollected then resultsUncollected = self:GetUncollectedMounts(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedMounts and self:GetCollectedMounts(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
        if dbgPlansBrowse then
        end
    elseif category == "pet" then
        if needUncollected then resultsUncollected = self:GetUncollectedPets(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedPets and self:GetCollectedPets(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
        if dbgPlansBrowse then
        end
    elseif category == "toy" then
        if needUncollected then resultsUncollected = self:GetUncollectedToys(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedToys and self:GetCollectedToys(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
        if dbgPlansBrowse then
        end
    end

    -- Re-check loading: Core init (EnsureCollectionData) or a scan triggered while the store is empty
    if categoryState.isLoading or (ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading) then
        local loadingStateData = {
            isLoading = true,
            loadingProgress = categoryState.loadingProgress or 0,
            currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
        }
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local categoryNameMap = {
                mount = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts",
                pet = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets",
                toy = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys",
                achievement = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements",
                illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
                title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
                transmog = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog",
            }
            local displayName = categoryNameMap[category] or (category:gsub("^%l", string.upper) .. "s")

            if category == "achievement" and parent._plansAchBrowseState then
                parent._plansAchBrowseState._achOuterScrollActive = false
            end

            local newYOffset = UI_CreateLoadingStateCard(
                parent, yOffset, loadingStateData,
                format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName)
            )
            return newYOffset
        end
    end

    if category == "transmog" then
        -- Transmog browser with sub-categories
        return self:DrawTransmogBrowser(parent, yOffset, width)
    elseif category == "illusion" then
        if needUncollected then resultsUncollected = self:GetUncollectedIllusions(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedIllusions and self:GetCollectedIllusions(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
    elseif category == "title" then
        if needUncollected then resultsUncollected = self:GetUncollectedTitles(searchText, 50) end
        if needCollected then resultsCollected = self.GetCollectedTitles and self:GetCollectedTitles(searchText, COLLECTED_BROWSE_FETCH_LIMIT) or {} end
    elseif category == "achievement" then
        if needUncollected then resultsUncollected = self:GetUncollectedAchievements(searchText, 99999) end
        if needCollected then resultsCollected = self.GetCompletedAchievements and self:GetCompletedAchievements(searchText, 99999) or {} end

        -- Re-check loading: GetUncollected/CompletedAchievements may have triggered scan (store empty)
        if categoryState.isLoading then
            if parent._plansAchBrowseState then
                parent._plansAchBrowseState._achOuterScrollActive = false
            end
            if parent.plansAchBrowseRoot then
                parent.plansAchBrowseRoot:Hide()
            end
            local loadingStateData = {
                isLoading = true,
                loadingProgress = categoryState.loadingProgress or 0,
                currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
            }
            local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
            if UI_CreateLoadingStateCard then
                local displayName = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements"
                return UI_CreateLoadingStateCard(parent, yOffset, loadingStateData,
                    format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName))
            end
        end

        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsAchievementPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsAchievementPlanned(item.id)
        end
        local achResults = MergePlansBrowseResults(resultsCollected, resultsUncollected, showPlannedBrowse, showCompletedBrowse)
        local achievementHeight = self:DrawAchievementsTable(parent, achResults, yOffset, width, searchText)
        if parent and parent.SetHeight then
            parent:SetHeight(math.max(achievementHeight, 1))
        end
        return achievementHeight
    elseif category == "recipe" then
        -- Recipes require profession window to be open - show message
        local helpCard = CreateCard(parent, 80)
        helpCard:SetPoint("TOPLEFT", 0, -yOffset)
        helpCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local helpText = FontManager:CreateFontString(helpCard, "body", "OVERLAY")
        helpText:SetPoint("CENTER", 0, 10)
        helpText:SetText("|cffffcc00" .. ((ns.L and ns.L["RECIPE_BROWSER"]) or "Recipe Browser") .. "|r")
        
        local helpDesc = FontManager:CreateFontString(helpCard, "small", "OVERLAY")
        helpDesc:SetPoint("TOP", helpText, "BOTTOM", 0, -8)
        helpDesc:SetText("|cffffffff" .. ((ns.L and ns.L["RECIPE_BROWSER_DESC"]) or "Open your Profession window in-game to browse recipes.\nThe addon will scan available recipes when the window is open.") .. "|r")
        helpDesc:SetJustifyH("CENTER")
        helpDesc:SetWidth(width - 40)
        
        helpCard:Show()
        
        return yOffset + 100
    end

    -- Re-check loading for illusion/title: GetUncollected* may have triggered scan (store empty)
    if (category == "illusion" or category == "title") and categoryState.isLoading then
        local loadingStateData = {
            isLoading = true,
            loadingProgress = categoryState.loadingProgress or 0,
            currentStage = categoryState.currentStage or ((ns.L and ns.L["REP_LOADING_PREPARING"]) or "Preparing..."),
        }
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local categoryNameMap = {
                illusion = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
                title = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
            }
            local displayName = categoryNameMap[category] or (category:gsub("^%l", string.upper) .. "s")
            return UI_CreateLoadingStateCard(parent, yOffset, loadingStateData,
                format((ns.L and ns.L["SCANNING_FORMAT"]) or "Scanning %s", displayName))
        end
    end
    
    -- isPlanned + merge matrix (mount, pet, toy, illusion, title)
    if category == "mount" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsMountPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsMountPlanned(item.id)
        end
    elseif category == "pet" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsPetPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsPetPlanned(item.id)
        end
    elseif category == "toy" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsItemPlanned(PLAN_TYPES.TOY, item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsItemPlanned(PLAN_TYPES.TOY, item.id)
        end
    elseif category == "illusion" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsIllusionPlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsIllusionPlanned(item.id)
        end
    elseif category == "title" then
        for i = 1, #resultsUncollected do
            local item = resultsUncollected[i]
            item.isPlanned = self:IsTitlePlanned(item.id)
        end
        for i = 1, #resultsCollected do
            local item = resultsCollected[i]
            item.isPlanned = self:IsTitlePlanned(item.id)
        end
    end

    local results = MergePlansBrowseResults(resultsCollected, resultsUncollected, showPlannedBrowse, showCompletedBrowse)

    if #results == 0 then
        if PLANS_BROWSE_STORE_CATEGORIES[category] then
            if (ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading) or categoryState.isLoading then
                return DrawPlansBrowseLoadingCard(parent, yOffset, category, categoryState)
            end
            if PlansBrowseCategoryStoreEmpty(category) then
                ns.RequestPlansBrowseCollectionEnsure(category)
                return DrawPlansBrowseLoadingCard(parent, yOffset, category, categoryState)
            end
        end
        if dbgPlansBrowse then
        end
        return DrawPlansBrowseEmptyCard(parent, yOffset, width, category, searchText, showPlannedBrowse, showCompletedBrowse)
    end

    table.sort(results, function(a, b)
        return SafeLower(a.name) < SafeLower(b.name)
    end)

    -- Phase 4.4: Limit browse results rendering for performance
    local totalResults = #results
    local resultsToRender = math.min(totalResults, MAX_BROWSE_RESULTS)
    
    if parent and parent.SetClipsChildren then
        parent:SetClipsChildren(false)
    end

    local PCM = ns.UI_PLANS_CARD_METRICS
    local gridW = ResolvePlansContentWidth(parent, width)
    -- `parent` is the browse results container (already inset to match the search bar).
    local browseGridOpts = { padH = 0 }
    local cardWidth, cardSpacing, gridPadH
    if ns.UI_PlansCardGridLayout then
        cardWidth, cardSpacing, gridPadH = ns.UI_PlansCardGridLayout(gridW, 2, browseGridOpts)
    else
        cardSpacing = (PCM and PCM.gridSpacing) or 8
        gridPadH = 0
        cardWidth = math.max(100, (gridW - cardSpacing) / 2)
    end
    local todoHeaderH = ns.UI_PlansTodoExpandableHeaderHeight and ns.UI_PlansTodoExpandableHeaderHeight(gridW) or 78
    local todoBadgeSz = (PCM and PCM.todoTypeBadgeSize) or 24
    local ACTION_SIZE = (ns.UI_PlansHeaderActionSize and ns.UI_PlansHeaderActionSize()) or todoBadgeSz
    local ACTION_GAP = 4
    local layoutManager = CardLayoutManager:Create(parent, 2, cardSpacing, yOffset)
    layoutManager.padH = 0
    parent._plansBrowseLayoutManager = layoutManager
    parent._plansCardLayoutManager = nil
    if not ns._plansBrowseExpanded then ns._plansBrowseExpanded = {} end
    local browseExpanded = ns._plansBrowseExpanded
    local PCF = ns.UI_PlanCardFactory
    local typeNames = PCF and PCF.TYPE_NAMES
    local typeIcons = PCF and PCF.TYPE_ICONS
    local typeColors = PCF and PCF.TYPE_COLORS
    local browserTryTypes = { mount = true, pet = true, toy = true, illusion = true }
    
    -- Show truncation message if results were limited
    if totalResults > MAX_BROWSE_RESULTS then
        local truncationMsg = FontManager:CreateFontString(parent, "body", "OVERLAY")
        truncationMsg:SetPoint("TOPLEFT", 0, -yOffset)
        truncationMsg:SetPoint("TOPRIGHT", 0, -yOffset)
        truncationMsg:SetJustifyH("CENTER")
        local showingFormat = (ns.L and ns.L["SHOWING_X_OF_Y"]) or "Showing %d of %d results"
        truncationMsg:SetText("|cff888888" .. format(showingFormat, MAX_BROWSE_RESULTS, totalResults) .. "|r")
        yOffset = yOffset + 24
    end

    ns._plansBrowsePaintGen = (ns._plansBrowsePaintGen or 0) + 1
    local drawGen = ns._plansBrowsePaintGen
    RunChunkedPlansBrowseCardPaint({
        addon = self,
        parent = parent,
        layoutManager = layoutManager,
        results = results,
        resultsToRender = resultsToRender,
        category = category,
        cardWidth = cardWidth,
        todoHeaderH = todoHeaderH,
        PCM = PCM,
        browseExpanded = browseExpanded,
        browserTryTypes = browserTryTypes,
        drawGen = drawGen,
        yOffset = yOffset,
    })

    local estRows = math.ceil(resultsToRender / 2)
    yOffset = yOffset + estRows * (todoHeaderH + cardSpacing) + 10

    local searchId = "plans_" .. (category or "unknown"):lower()
    SearchStateManager:UpdateResults(searchId, #results)

    local totalH = yOffset + 10
    if parent and parent.SetHeight then
        parent:SetHeight(math.max(totalH, 1))
    end
    return totalH
end

