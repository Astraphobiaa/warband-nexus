--[[
    Shared achievement category browser: flat list + nested collapsible headers + virtual rows.
    Same behavior as Collections ▸ Achievements; used by Plans ▸ To-Do browse achievement category.
]]

local ADDON_NAME, ns = ...

local wipe = wipe
local format = string.format
local tonumber = tonumber

local COLORS = ns.UI_COLORS
local Factory = ns.UI.Factory
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n) end

local function GetLayout()
    return ns.UI_LAYOUT or {}
end

local LAYOUT = GetLayout()
--- Shared by Plans (To-Do ▸ Achievements) and Collections ▸ Achievements virtual rows.
ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE = 1.155
local ACH_ROW_GAP = 4
local SIDE_MARGIN = LAYOUT.SIDE_MARGIN or 10
local PADDING = SIDE_MARGIN
local ROW_HEIGHT = LAYOUT.ROW_HEIGHT or 26
local HEADER_HEIGHT = LAYOUT.HEADER_HEIGHT or 32
-- Must match CreateCollapsibleHeader / section wraps (same bug class as Collections mount lists).
local COLLAPSE_HEADER_HEIGHT_ACH = LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT or 36
local BASE_INDENT = LAYOUT.BASE_INDENT or 15
local SECTION_SPACING = LAYOUT.SECTION_SPACING or LAYOUT.betweenSections or 8
local MINI_SPACING = LAYOUT.MINI_SPACING or LAYOUT.miniSpacing or 4
local ACHIEVEMENT_HEADER_CHUNK = (ns.CollectionsUI and ns.CollectionsUI.COLLECTIONS_HEADER_CHUNK) or 4
local ACHIEVEMENT_HEADER_CHUNK_DEFERRED = (ns.CollectionsUI and ns.CollectionsUI.COLLECTIONS_HEADER_CHUNK_DEFERRED) or 99999

local function BeginAchievementBrowseDeferredChrome(opts)
    local cui = ns.CollectionsUI
    if cui and cui.CollectionsBeginListChromeDefer and cui.CollectionsListChromeFramesForSubTab then
        return cui.CollectionsBeginListChromeDefer(cui.CollectionsListChromeFramesForSubTab("achievements", opts and opts.chromeHostFrame))
    end
    return false
end

local function EndAchievementBrowseDeferredChrome()
    local cui = ns.CollectionsUI
    if cui and cui.CollectionsEndListChromeDefer then
        cui.CollectionsEndListChromeDefer()
    end
end

--- Measure root section wraps on the achievement list scroll child (respects collapsed nested bodies).
local function SyncAchievementBrowseScrollChildHeight(state)
    local scrollChild = state and state.achievementListScrollChild
    if not scrollChild or not scrollChild.GetTop then return end
    local scTop = scrollChild:GetTop()
    if not scTop then return end
    local maxExtent = 0
    local n = scrollChild:GetNumChildren() or 0
    for i = 1, n do
        local c = select(i, scrollChild:GetChildren())
        if c and c.IsShown and c:IsShown() then
            local bot = c:GetBottom()
            if bot then
                maxExtent = math.max(maxExtent, scTop - bot)
            end
        end
    end
    local contentH = math.max(maxExtent + PADDING, 1)
    scrollChild:SetHeight(contentH)
    state._achFlatListTotalHeight = contentH
    local scrollFrame = state.achievementListScrollFrame
    if scrollFrame then
        if scrollFrame.GetVerticalScroll and scrollFrame.GetHeight and scrollFrame.SetVerticalScroll then
            local viewH = scrollFrame:GetHeight() or 0
            local scrollTop = scrollFrame:GetVerticalScroll() or 0
            local maxScroll = math.max(0, contentH - viewH)
            if scrollTop > maxScroll then
                scrollFrame:SetVerticalScroll(maxScroll)
            end
        end
        if state.achievementListScrollBarContainer and Factory.EnsureScrollBarColumnSync then
            local colW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 22
            local gap = (ns.CollectionsUI and ns.CollectionsUI.SCROLLBAR_SIDE_GAP) or 4
            Factory:EnsureScrollBarColumnSync(scrollFrame, state.achievementListScrollBarContainer, { width = colW, gap = gap })
        end
        if Factory.DeferScrollBarVisibility then
            Factory:DeferScrollBarVisibility(scrollFrame)
        elseif Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scrollFrame)
        end
    end
end

local _populateAchievementBrowseBusy = false
local _populateAchievementBrowseQueued = nil

function ns.UI_AchievementBrowse_ResetPopulateBusy()
    _populateAchievementBrowseBusy = false
    _populateAchievementBrowseQueued = nil
    EndAchievementBrowseDeferredChrome()
end

--- Drop session caches when achievement APIs become ready (login) or collection scan finishes.
function ns.UI_InvalidateAchievementCategoryCaches()
    if ns.UI_InvalidatePlansAchievementCategoryTree then
        ns.UI_InvalidatePlansAchievementCategoryTree()
    end
    local cui = ns.CollectionsUI
    if cui and cui.state then
        cui.state._achGroupedCache = nil
    end
end

local function InvokeAchievementBrowseListReady(opts)
    if type(opts) ~= "table" or type(opts.onListReady) ~= "function" then
        return
    end
    opts.onListReady()
end

local function DrainAchievementBrowsePopulateQueue()
    local queued = _populateAchievementBrowseQueued
    _populateAchievementBrowseQueued = nil
    if queued then
        ns.UI_AchievementBrowse_Populate(queued)
    end
end

local _achChildEnumScratch = {}
local _achRegionEnumScratch = {}
local function PackVariadicInto(dest, ...)
    wipe(dest)
    local n = select("#", ...)
    for i = 1, n do
        dest[i] = select(i, ...)
    end
    return n
end

--- Pixels from scroll content top down to `listFrame` top (TOP→TOP anchor chain). Fallback nil if ambiguous.
local function ListTopOffsetDownFromScrollContent(listFrame, scrollContent)
    if not listFrame or not scrollContent then return nil end
    local sum = 0
    local f = listFrame
    while f do
        if f == scrollContent then
            return sum
        end
        local p = f:GetParent()
        if not p then return nil end
        local delta = nil
        local n = f.GetNumPoints and f:GetNumPoints() or 0
        for i = 1, n do
            local pt, rel, rp, x, yo = f:GetPoint(i)
            if rel == p and rp and (rp == "TOPLEFT" or rp == "TOP") and pt and (pt == "TOPLEFT" or pt == "TOPRIGHT") then
                delta = -(yo or 0)
                break
            end
        end
        if delta == nil then return nil end
        sum = sum + delta
        f = p
    end
    return nil
end

--- Flat list for virtual scrolling (headers + rows). Mirrors Collections achievement grouping.
---@param listOpts table|nil Optional `{ rowHeightScale = number }` (default 1; Plans/Collections pass `ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE`).
function ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders, listOpts)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local baseRowH = LAYOUT.ROW_HEIGHT or 26
    local scale = (listOpts and type(listOpts.rowHeightScale) == "number") and listOpts.rowHeightScale or 1
    local searchActive = listOpts and listOpts.searchActive == true
    local achRowH = math.max(18, math.floor(baseRowH * scale + 0.5))
    local achRowStride = achRowH + ACH_ROW_GAP
    local whiteHex = (ns.CollectionsUI and ns.CollectionsUI.CollectionsListWhiteHex and ns.CollectionsUI.CollectionsListWhiteHex())
        or "|cffffffff"
    local countColor = whiteHex
    local rB, gB, bB = (COLORS.textBright[1] or 1), (COLORS.textBright[2] or 1), (COLORS.textBright[3] or 1)
    local titleColor = format("|cff%02x%02x%02x", rB * 255, gB * 255, bB * 255)

    local function CountCategoryAchievements(catID)
        local cat = categoryData[catID]
        if not cat then return 0 end
        local total = #cat.achievements
        local children = cat.children or {}
        for i = 1, #children do
            total = total + CountCategoryAchievements(children[i])
        end
        return total
    end

    -- Feats of Strength (and similar): unearned feats are hidden from GetAchievementInfo browse
    -- until earned, but Blizzard still lists the category tabs. includeAll=true matches journal.
    local apiCategoryCountCache = {}
    local function GetApiCategoryAchievementCount(catID)
        if not catID or not GetCategoryNumAchievements then return 0 end
        local cached = apiCategoryCountCache[catID]
        if cached ~= nil then return cached end
        local total = 0
        local ok, n = pcall(function()
            return select(1, GetCategoryNumAchievements(catID, true))
        end)
        if ok and type(n) == "number" and n > 0 then
            total = n
        end
        apiCategoryCountCache[catID] = total
        return total
    end

    local function CategoryHasChildBranches(catID)
        local cat = categoryData[catID]
        local children = cat and cat.children
        return children and #children > 0
    end

    local hideEmptyCategories = listOpts and listOpts.hideEmptyCategories == true

    local function CategoryShouldAppear(catID)
        -- Search / Plans To-Do browse: only branches that contain visible (uncollected/filtered) achievements.
        if searchActive or hideEmptyCategories then
            return CountCategoryAchievements(catID) > 0
        end
        if CountCategoryAchievements(catID) > 0 then return true end
        if GetApiCategoryAchievementCount(catID) > 0 then return true end
        -- Feats of Strength (and similar): journal sub-tabs exist before browse/scan data is ready on first login.
        if CategoryHasChildBranches(catID) then return true end
        local cat = categoryData[catID]
        local children = cat and cat.children or {}
        for i = 1, #children do
            if CategoryShouldAppear(children[i]) then return true end
        end
        return false
    end

    -- Flat Y must match ChainSectionFrameBelow: only SECTION_SPACING between consecutive *rendered*
    -- subsection wraps. The old loop added spacing after every child index (including empty API slots),
    -- inflating yOffset / relY vs real frames — nested headers and rows overlapped the next category.
    local function AppendCategorySubtree(catID, headerIndentPx)
        local cat = categoryData[catID]
        if not cat then return end
        local totalAchievements = CountCategoryAchievements(catID)
        if not CategoryShouldAppear(catID) then return end

        local catKey = "achievement_cat_" .. catID
        local catExpanded = (collapsedHeaders[catKey] == false)
        flat[#flat + 1] = {
            type = "header",
            key = catKey,
            label = titleColor .. (cat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(totalAchievements) .. ")|r",
            rightStr = countColor .. FormatNumber(totalAchievements) .. "|r",
            itemCount = totalAchievements,
            isCollapsed = not catExpanded,
            yOffset = yOffset,
            height = COLLAPSE_HEADER_HEIGHT_ACH,
            indent = headerIndentPx,
        }
        yOffset = yOffset + COLLAPSE_HEADER_HEIGHT_ACH + MINI_SPACING

        local achievements = cat.achievements or {}
        local rowIndent = headerIndentPx + BASE_INDENT
        for i = 1, #achievements do
            local ach = achievements[i]
            rowCounter = rowCounter + 1
            flat[#flat + 1] = {
                type = "row",
                achievement = ach,
                rowIndex = rowCounter,
                yOffset = yOffset,
                height = achRowStride,
                rowPaintHeight = achRowH,
                indent = rowIndent,
            }
            yOffset = yOffset + achRowStride
        end

        local children = cat.children or {}
        if #children > 0 and #achievements > 0 then
            yOffset = yOffset + SECTION_SPACING
        end

        local firstEmittedChild = true
        for cidx = 1, #children do
            local childID = children[cidx]
            local childCat = categoryData[childID]
            if childCat and CategoryShouldAppear(childID) then
                if not firstEmittedChild then
                    yOffset = yOffset + SECTION_SPACING
                end
                firstEmittedChild = false
                AppendCategorySubtree(childID, headerIndentPx + BASE_INDENT)
            end
        end
    end

    local firstRoot = true
    for rootIndex = 1, #rootCategories do
        local rootID = rootCategories[rootIndex]
        local rootCat = categoryData[rootID]
        if rootCat and CategoryShouldAppear(rootID) then
            if not firstRoot then
                yOffset = yOffset + SECTION_SPACING
            end
            firstRoot = false
            AppendCategorySubtree(rootID, 0)
        end
    end

    return flat, math.max(yOffset + PADDING, 1)
end

--[[
    opts.state — table with achievement browse fields (same shape as collectionsState):
      achievementListScrollFrame, achievementListScrollChild, _achFlatList, _achSectionBodies,
      _achVisibleRowFrames, _achListWidth, _achListSelectedID, _achListOnSelect, _achListContentFrame,
      _achListCollapsedHeaders, _achListRefreshVisible (set by this populate)
    Plans To-Do only (optional): _achUseOuterScroll, _achOuterScrollFrame, _achOuterScrollChild (tab scrollChild),
      _achOuterScrollActive — virtual rows use main tab ScrollFrame (single scrollbar). Hook uses ns._plansAchOuterVirtualState.
    opts.scrollChild, listWidth, categoryData, rootCategories, collapsedHeaders
    opts.selectedAchievementID, opts.onSelectAchievement, opts.contentFrameForRefresh, opts.redrawFn
    opts.acquireRow(scrollChild, listWidth, item, selectedID, onSelect, redraw, cf) -> frame
    opts.releaseRowFrame(frame)
    opts.scheduleVisibleSync(function(refreshFn)) — optional; Collections passes ScheduleCollectionsVisibleSync
    opts.drawGen — optional generation token; stored on state._achPopulateGen for pump abort
    opts.collectionsSubTabGen — optional; Collections sub-tab switch abort
    opts.plansCategoryGen — optional; Plans To-Do browse category switch abort
    opts.rowHeightScale — optional number passed to BuildFlatList (Plans & Collections achievements use `ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE`).
]]
function ns.UI_AchievementBrowse_Populate(opts)
    if not opts or not opts.scrollChild or not Factory then return end
    if _populateAchievementBrowseBusy then
        _populateAchievementBrowseQueued = opts
        return
    end
    _populateAchievementBrowseBusy = true

    local state = opts.state
    local scrollChild = opts.scrollChild
    local listWidth = opts.listWidth or 260
    local categoryData = opts.categoryData or {}
    local rootCategories = opts.rootCategories or {}
    local collapsedHeaders = opts.collapsedHeaders or {}
    local selectedAchievementID = opts.selectedAchievementID
    local onSelectAchievement = opts.onSelectAchievement
    local cf = opts.contentFrameForRefresh
    local redraw = opts.redrawFn or function() end
    local acquireRow = opts.acquireRow
    local releaseRowFrame = opts.releaseRowFrame
    local scheduleVisibleSync = opts.scheduleVisibleSync

    if type(acquireRow) ~= "function" or type(releaseRowFrame) ~= "function" then
        _populateAchievementBrowseBusy = false
        InvokeAchievementBrowseListReady(opts)
        DrainAchievementBrowsePopulateQueue()
        return
    end

    local deferListChrome = BeginAchievementBrowseDeferredChrome(opts)
    local headerChunkSize = deferListChrome and ACHIEVEMENT_HEADER_CHUNK_DEFERRED or ACHIEVEMENT_HEADER_CHUNK

    scrollChild:SetWidth(listWidth)

    local visible = state._achVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                releaseRowFrame(v.frame)
            end
        end
        state._achVisibleRowFrames = {}
    end

    local nch = PackVariadicInto(_achChildEnumScratch, scrollChild:GetChildren())
    for i = 1, nch do
        local c = _achChildEnumScratch[i]
        c:Hide()
        c:ClearAllPoints()
        local bin = ns.UI_RecycleBin
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    local nrg = PackVariadicInto(_achRegionEnumScratch, scrollChild:GetRegions())
    for i = 1, nrg do
        _achRegionEnumScratch[i]:Hide()
    end

    local listBuildOpts = nil
    if (opts.rowHeightScale and type(opts.rowHeightScale) == "number") or opts.searchActive or opts.hideEmptyCategories then
        listBuildOpts = {}
        if opts.rowHeightScale and type(opts.rowHeightScale) == "number" then
            listBuildOpts.rowHeightScale = opts.rowHeightScale
        end
        if opts.searchActive then
            listBuildOpts.searchActive = true
        end
        if opts.hideEmptyCategories then
            listBuildOpts.hideEmptyCategories = true
        end
    end
    local flatList = ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders, listBuildOpts)
    do
        local cui = ns.CollectionsUI
        if cui and cui.CollectionsSubTabTrace then
            cui.CollectionsSubTabTrace("PopulateAchievementList_start", {
                deferChrome = deferListChrome,
                headersChunk = headerChunkSize,
                flatItems = #flatList,
            })
        end
    end

    if ns.UI_HideEmptyStateCard then
        ns.UI_HideEmptyStateCard(scrollChild, ns.UI_SEARCH_EMPTY_TAB_KEY or "search")
        ns.UI_HideEmptyStateCard(scrollChild, "collections_achievements")
    end
    local searchTextRaw = opts.searchText or (state and state.searchText) or ""
    if not (ns.UI_FlatListHasDataRows and ns.UI_FlatListHasDataRows(flatList)) then
        if opts.searchActive and ns.UI_TryShowSearchEmptyInContainer and ns.UI_TryShowSearchEmptyInContainer(scrollChild, searchTextRaw, 0) then
            state._achFlatList = flatList
            state._achFlatListTotalHeight = math.max(200, (scrollChild:GetParent() and scrollChild:GetParent():GetHeight()) or 200)
            scrollChild:SetHeight(state._achFlatListTotalHeight)
            EndAchievementBrowseDeferredChrome()
            _populateAchievementBrowseBusy = false
            InvokeAchievementBrowseListReady(opts)
            DrainAchievementBrowsePopulateQueue()
            return
        end
        if ns.UI_ShowTabEmptyStateCard then
            ns.UI_ShowTabEmptyStateCard(scrollChild, "collections_achievements", 0, { fillParent = true })
            state._achFlatList = flatList
            state._achFlatListTotalHeight = math.max(200, (scrollChild:GetParent() and scrollChild:GetParent():GetHeight()) or 200)
            scrollChild:SetHeight(state._achFlatListTotalHeight)
            EndAchievementBrowseDeferredChrome()
            _populateAchievementBrowseBusy = false
            InvokeAchievementBrowseListReady(opts)
            DrainAchievementBrowsePopulateQueue()
            return
        end
    end

    state._achRowHeightUsed = ROW_HEIGHT
    for _fi = 1, #flatList do
        local _it = flatList[_fi]
        if _it.type == "row" and _it.height then
            state._achRowHeightUsed = _it.height
            break
        end
    end

    state._achSectionBodies = {}
    local achSectionContentH = {}
    local achHeaderMeta = {}
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
            achSectionContentH[sk] = sh
        end
    end
    do
        local stack = {}
        local function FinalizeTop()
            local top = stack[#stack]
            if not top then return end
            achSectionContentH[top.key] = math.max(0, (top.maxBottomY or top.contentTopY) - top.contentTopY)
            stack[#stack] = nil
        end
        for fi = 1, #flatList do
            local fit = flatList[fi]
            local yTop = fit.yOffset or 0
            local yBottom = yTop + (fit.height or (fit.type == "header" and COLLAPSE_HEADER_HEIGHT_ACH or ROW_HEIGHT))

            if fit.type == "header" then
                local indent = fit.indent or 0
                while #stack > 0 and ((stack[#stack].indent or 0) >= indent) do
                    FinalizeTop()
                end
                for si = 1, #stack do
                    local s = stack[si]
                    if yBottom > (s.maxBottomY or s.contentTopY) then
                        s.maxBottomY = yBottom
                    end
                end
                local parent = stack[#stack]
                local contentTopY = yTop + (fit.height or COLLAPSE_HEADER_HEIGHT_ACH)
                local categoryID = tonumber((fit.key or ""):match("^achievement_cat_(%-?%d+)$"))
                achHeaderMeta[fit.key] = {
                    parentKey = parent and parent.key or nil,
                    parentIndent = parent and parent.indent or 0,
                    relY = parent and (yTop - (parent.contentTopY or 0)) or 0,
                    categoryID = categoryID,
                }
                stack[#stack + 1] = {
                    key = fit.key,
                    indent = indent,
                    contentTopY = contentTopY,
                    maxBottomY = contentTopY,
                }
            elseif fit.type == "row" and #stack > 0 then
                for si = 1, #stack do
                    local s = stack[si]
                    if yBottom > (s.maxBottomY or s.contentTopY) then
                        s.maxBottomY = yBottom
                    end
                end
                local owner = stack[#stack]
                fit._collSectionKey = owner.key
                fit._collRelY = yTop - (owner.contentTopY or 0)
                fit.groupKey = owner.key
                fit.localY = fit._collRelY
            end
        end
        while #stack > 0 do
            FinalizeTop()
        end
    end

    local achBaseIndent = BASE_INDENT
    local achSiblingTailByParent = {}
    local achSectionWraps = {}
    local achHeaderKeys = {}
    local COLLAPSE_H_COLL = LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT or 36

    local function refreshVisibleInternal()
        ns.UI_AchievementBrowse_UpdateVisibleRange({
            state = state,
            acquireRow = acquireRow,
            releaseRowFrame = releaseRowFrame,
        })
    end

    local function ensureAchievementBrowseScrollHooks()
        local scrollFrame = state.achievementListScrollFrame
        if not scrollFrame then return end
        state._achListRefreshVisible = refreshVisibleInternal
        if state._achUseOuterScroll then
            state._achOuterScrollActive = true
            ns._plansAchOuterVirtualState = state
            if scrollFrame.HookScript and not ns._plansAchOuterScrollHooked then
                ns._plansAchOuterScrollHooked = true
                scrollFrame:HookScript("OnVerticalScroll", function()
                    local st = ns._plansAchOuterVirtualState
                    if st and st._achOuterScrollActive and st._achListRefreshVisible then
                        st._achListRefreshVisible()
                    end
                end)
            end
        else
            scrollFrame:SetScript("OnVerticalScroll", function()
                refreshVisibleInternal()
            end)
        end
    end

    local function CountAchievementTree(catID)
        local cat = categoryData and categoryData[catID]
        if not cat then return 0 end
        local total = #(cat.achievements or {})
        local children = cat.children or {}
        for i = 1, #children do
            total = total + CountAchievementTree(children[i])
        end
        return total
    end

    local rowHAcc = state._achRowHeightUsed or ROW_HEIGHT
    local function ComputeAchievementContentHeight(catID, activeAnimKey, activeAnimBodyH)
        local cat = categoryData and categoryData[catID]
        if not cat then return 0 end
        local bodyH = MINI_SPACING + (#(cat.achievements or {}) * rowHAcc)
        local children = cat.children or {}
        if #children > 0 and #(cat.achievements or {}) > 0 then
            bodyH = bodyH + SECTION_SPACING
        end
        local firstEmittedChild = true
        for childIdx = 1, #children do
            local childID = children[childIdx]
            local childCount = CountAchievementTree(childID)
            if childCount > 0 then
                if not firstEmittedChild then
                    bodyH = bodyH + SECTION_SPACING
                end
                firstEmittedChild = false
                local childKey = "achievement_cat_" .. childID
                bodyH = bodyH + COLLAPSE_H_COLL
                local childExpanded = (collapsedHeaders[childKey] == false) or (activeAnimKey and childKey == activeAnimKey and activeAnimBodyH ~= nil)
                if childExpanded then
                    local childBodyH
                    if activeAnimKey and childKey == activeAnimKey and activeAnimBodyH then
                        childBodyH = math.max(0.1, activeAnimBodyH)
                    else
                        local body = state._achSectionBodies and state._achSectionBodies[childKey]
                        if body and body:IsShown() then
                            childBodyH = body:GetHeight()
                        else
                            childBodyH = ComputeAchievementContentHeight(childID, activeAnimKey, activeAnimBodyH)
                        end
                    end
                    bodyH = bodyH + math.max(0.1, childBodyH or 0)
                end
            end
        end
        return math.max(0.1, bodyH)
    end

    local function ReflowAchievementSectionHeights(activeAnimKey, activeAnimBodyH)
        for i = 1, #achHeaderKeys do
            local key = achHeaderKeys[i]
            local meta = achHeaderMeta[key]
            local catID = meta and meta.categoryID
            local body = state._achSectionBodies and state._achSectionBodies[key]
            local wrap = achSectionWraps[key]
            if catID and body then
                local fullH = ComputeAchievementContentHeight(catID, activeAnimKey, activeAnimBodyH)
                body._wnSectionFullH = fullH
                if key ~= activeAnimKey and collapsedHeaders[key] == false then
                    body:SetHeight(fullH)
                end
                if wrap then
                    wrap:SetHeight(COLLAPSE_H_COLL + math.max(0.1, body:GetHeight() or 0.1))
                end
            end
        end
    end

    local drawGen = opts.drawGen
    if drawGen then
        state._achPopulateGen = drawGen
    end
    if opts.collectionsSubTabGen then
        state._collectionsSubTabGen = opts.collectionsSubTabGen
    end
    if opts.plansCategoryGen then
        state._plansCategoryGen = opts.plansCategoryGen
    end

    -- Bind flat list before header pump (virtual rows paint once in finishAchievementBrowsePopulate;
    -- same as Mounts/Pets/Toys Populate*List — no mid-pump visible-range refresh).
    state._achFlatList = flatList
    state._achListWidth = listWidth
    state._achListSelectedID = selectedAchievementID
    state._achListOnSelect = onSelectAchievement
    state._achListCollapsedHeaders = collapsedHeaders
    state._achListContentFrame = cf
    state._achListRedrawFn = redraw
    ensureAchievementBrowseScrollHooks()

    local function finishAchievementBrowsePopulate()
        ReflowAchievementSectionHeights()
        SyncAchievementBrowseScrollChildHeight(state)
        ensureAchievementBrowseScrollHooks()
        refreshVisibleInternal()
        if type(scheduleVisibleSync) == "function" then
            scheduleVisibleSync(refreshVisibleInternal)
        end
        EndAchievementBrowseDeferredChrome()
        do
            local cui = ns.CollectionsUI
            if cui and cui.CollectionsSubTabTrace then
                cui.CollectionsSubTabTrace("PopulateAchievementList_done", { flatItems = state._achFlatList and #state._achFlatList or 0 })
            end
        end
        InvokeAchievementBrowseListReady(opts)
        _populateAchievementBrowseBusy = false
        DrainAchievementBrowsePopulateQueue()
    end

    local function abortAchievementBrowsePopulate()
        EndAchievementBrowseDeferredChrome()
        _populateAchievementBrowseBusy = false
        InvokeAchievementBrowseListReady(opts)
        DrainAchievementBrowsePopulateQueue()
    end

    local flatHeaderIdx = 1
    local function hasRemainingAchievementHeaders()
        for hi = flatHeaderIdx, #flatList do
            if flatList[hi].type == "header" then
                return true
            end
        end
        return false
    end

    local function pumpAchievementHeaders()
        if state._achPopulateGen == -1 or state._plansCategoryGen == -1 then
            abortAchievementBrowsePopulate()
            return
        end
        if drawGen and state._achPopulateGen and state._achPopulateGen ~= drawGen then
            abortAchievementBrowsePopulate()
            return
        end
        if drawGen and state._collectionsSubTabGen and opts.collectionsSubTabGen and state._collectionsSubTabGen ~= opts.collectionsSubTabGen then
            abortAchievementBrowsePopulate()
            return
        end
        if drawGen and opts.plansCategoryGen and state._plansCategoryGen and state._plansCategoryGen ~= opts.plansCategoryGen then
            abortAchievementBrowsePopulate()
            return
        end

        local built = 0
        while flatHeaderIdx <= #flatList and built < headerChunkSize do
            while flatHeaderIdx <= #flatList and flatList[flatHeaderIdx].type ~= "header" do
                flatHeaderIdx = flatHeaderIdx + 1
            end
            if flatHeaderIdx > #flatList then
                break
            end
            local it = flatList[flatHeaderIdx]
            flatHeaderIdx = flatHeaderIdx + 1
            local key = it.key
            local indentPx = it.indent or 0
            local indentLevel = (indentPx > 0 and math.floor(indentPx / achBaseIndent)) or 0
            local meta = achHeaderMeta[key]
            local parentKey = meta and meta.parentKey or nil
            local parentBody = (parentKey and state._achSectionBodies and state._achSectionBodies[parentKey]) or nil
            local parentToken = parentKey or "__root__"
            local prevSiblingWrap = achSiblingTailByParent[parentToken]

            local wrapW = math.max(1, listWidth - indentPx)
            local sectionWrap = Factory:CreateContainer(parentBody or scrollChild, wrapW, COLLAPSE_H_COLL + 0.1, false)
            sectionWrap:ClearAllPoints()
            if sectionWrap.SetClipsChildren then
                sectionWrap:SetClipsChildren(true)
            end
            if parentBody then
                local leftOffset = math.max(0, indentPx - (meta.parentIndent or 0))
                local fallbackY = math.max(0, meta.relY or 0)
                ChainSectionFrameBelow(parentBody, sectionWrap, prevSiblingWrap, leftOffset, prevSiblingWrap and SECTION_SPACING or nil, prevSiblingWrap and nil or fallbackY)
            else
                ChainSectionFrameBelow(scrollChild, sectionWrap, prevSiblingWrap, indentPx, prevSiblingWrap and SECTION_SPACING or nil, prevSiblingWrap and nil or 0)
            end

            local sectionBody
            local catIDForH = meta and meta.categoryID
            local secH = achSectionContentH[key] or 0
            if secH <= 0 and catIDForH then
                secH = ComputeAchievementContentHeight(catIDForH, nil, nil)
            elseif secH <= 0 then
                secH = ((it.itemCount or 0) * rowHAcc) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                if isExpanded then
                    refreshVisibleInternal()
                end
            end, "UI-Achievement-Shield-NoPoints", true, indentLevel, nil, ns.UI_BuildCollapsibleSectionOpts({
                wrapFrame = sectionWrap,
                bodyGetter = function() return sectionBody end,
                headerHeight = COLLAPSE_H_COLL,
                hideOnCollapse = true,
                applyToggleBeforeCollapseAnimate = true,
                persistFn = function(exp)
                    if exp then
                        collapsedHeaders[key] = false
                    end
                end,
                onUpdate = function(drawH)
                    ReflowAchievementSectionHeights(key, drawH)
                    SyncAchievementBrowseScrollChildHeight(state)
                end,
                updateVisibleFn = function()
                    refreshVisibleInternal()
                end,
                onComplete = function(exp)
                    if not exp then
                        collapsedHeaders[key] = true
                    end
                    ReflowAchievementSectionHeights()
                    SyncAchievementBrowseScrollChildHeight(state)
                    refreshVisibleInternal()
                end,
            }))
            if ns.UI_AnchorSectionHeaderInWrap then
                ns.UI_AnchorSectionHeaderInWrap(header, sectionWrap, wrapW)
            else
                header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
                header:SetWidth(wrapW)
            end
            header:SetHeight(it.height)

            sectionBody = Factory:CreateContainer(sectionWrap, wrapW, 0.1, false)
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
            sectionWrap:SetHeight(COLLAPSE_H_COLL + sectionBody:GetHeight())
            state._achSectionBodies[key] = sectionBody
            achSectionWraps[key] = sectionWrap
            achHeaderKeys[#achHeaderKeys + 1] = key
            achSiblingTailByParent[parentToken] = sectionWrap
            built = built + 1
        end

        if hasRemainingAchievementHeaders() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, pumpAchievementHeaders)
            else
                pumpAchievementHeaders()
            end
            return
        end
        finishAchievementBrowsePopulate()
    end

    pumpAchievementHeaders()
end

function ns.UI_AchievementBrowse_UpdateVisibleRange(opts)
    local state = opts and opts.state
    local acquireRow = opts and opts.acquireRow
    local releaseRowFrame = opts and opts.releaseRowFrame
    if not state or type(acquireRow) ~= "function" or type(releaseRowFrame) ~= "function" then return end

    local flatList = state._achFlatList
    local useOuter = state._achUseOuterScroll == true
    local scrollFrame = useOuter and state._achOuterScrollFrame or state.achievementListScrollFrame
    local scrollChild = state.achievementListScrollChild
    if not flatList or not scrollChild then return end
    if not scrollFrame then
        useOuter = false
        scrollFrame = state.achievementListScrollFrame
    end
    if not scrollFrame then return end

    local scrollTop = scrollFrame:GetVerticalScroll()
    local visibleHeight = scrollFrame:GetHeight()
    local bottom = scrollTop + visibleHeight

    local listTopInContent = 0
    if useOuter then
        local scrollContent = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
        local walked = scrollContent and ListTopOffsetDownFromScrollContent(scrollChild, scrollContent)
        if walked ~= nil then
            listTopInContent = walked
        else
            local outerChild = state._achOuterScrollChild
            if outerChild then
                local ot = outerChild:GetTop()
                local at = scrollChild:GetTop()
                if ot and at then
                    listTopInContent = ot - at
                end
            end
        end
    end
    local visible = state._achVisibleRowFrames
    if visible then
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                releaseRowFrame(v.frame)
            end
        end
    end
    state._achVisibleRowFrames = {}

    local cf = state._achListContentFrame
    local selectedID = state._achListSelectedID or (state.selectedAchievementID)
    local onSelect = state._achListOnSelect
    local listWidth = state._achListWidth or scrollChild:GetWidth()
    local redrawFn = state._achListRedrawFn

    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "row" then
            local rowTop = it.yOffset or 0
            local rowHeight = it.height or ROW_HEIGHT
            local rowBottom = rowTop + rowHeight
            if it._collSectionKey and state._achSectionBodies then
                local body = state._achSectionBodies[it._collSectionKey]
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
            if rowTop and rowBottom then
                if useOuter then
                    rowTop = rowTop + listTopInContent
                    rowBottom = rowBottom + listTopInContent
                end
                if rowBottom > scrollTop and rowTop < bottom then
                local frame = acquireRow(scrollChild, listWidth, it, selectedID, onSelect, redrawFn, cf)
                if frame then
                    state._achVisibleRowFrames[#state._achVisibleRowFrames + 1] = { frame = frame, flatIndex = i }
                end
                end
            end
        end
    end
end

local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
if WarbandNexus and WarbandNexus.RegisterMessage and Constants and Constants.EVENTS then
    local AchBrowseMsgListeners = ns._achBrowseMsgListeners or {}
    ns._achBrowseMsgListeners = AchBrowseMsgListeners
    WarbandNexus.RegisterMessage(AchBrowseMsgListeners, Constants.EVENTS.ACHIEVEMENT_CATEGORY_CACHE_INVALIDATED, function()
        ns.UI_InvalidateAchievementCategoryCaches()
    end)
end
