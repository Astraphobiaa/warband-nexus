--[[
    Shared achievement category browser: ONE flat absolute-Y layout model, headers and rows both
    virtualized against it. Used by Collections ▸ Achievements and Plans ▸ To-Do browse.

    Layout contract: `UI_AchievementBrowse_BuildFlatList` owns every position. A collapsed category
    contributes its header and nothing else — no nested wrap/body frames, no frame measurement, no
    second height model to drift against on collapse/expand.
]]

local ADDON_NAME, ns = ...

local wipe = wipe
local format = string.format
local tonumber = tonumber

local COLORS = ns.UI_COLORS
local Factory = ns.UI.Factory
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local RebindCollapsibleHeader = ns.UI_RebindCollapsibleHeader
local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n) end
assert(CreateCollapsibleHeader and RebindCollapsibleHeader,
    "AchievementBrowseVirtualList: SharedWidgets_Collapsible must load first (WarbandNexus.toc)")

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

--- Apply the flat model's content height to the scroll child + chrome. No frame measurement: the
--- layout model owns the height, so this never disagrees with where rows were actually placed
--- (the old GetChildren() sweep was both O(n^2) and a second, drifting source of truth).
local function ApplyAchievementBrowseContentHeight(state, totalH)
    local scrollChild = state and state.achievementListScrollChild
    if not scrollChild then return end
    local contentH = math.max((totalH or 1), 1)
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

    -- Single layout model: `yOffset` here is the ONLY source of truth for every frame's position.
    -- A collapsed category contributes its header and nothing else — its rows and child subtrees are
    -- absent from the list rather than hidden behind a nested body frame. That removes the second
    -- (frame-measured) height model that used to drift against this one on every collapse/expand.
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
            categoryID = catID,
            label = titleColor .. (cat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(totalAchievements) .. ")|r",
            rightStr = countColor .. FormatNumber(totalAchievements) .. "|r",
            itemCount = totalAchievements,
            isCollapsed = not catExpanded,
            yOffset = yOffset,
            height = COLLAPSE_HEADER_HEIGHT_ACH,
            indent = headerIndentPx,
        }
        yOffset = yOffset + COLLAPSE_HEADER_HEIGHT_ACH
        if not catExpanded then return end
        yOffset = yOffset + MINI_SPACING

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
      achievementListScrollFrame, achievementListScrollChild, _achFlatList, _achHeaderPool,
      _achVisibleRowFrames, _achListWidth, _achListSelectedID, _achListOnSelect, _achListContentFrame,
      _achListCollapsedHeaders, _achListRefreshVisible, _achListRebuild (set by this populate)
    Plans To-Do only (optional): _achUseOuterScroll, _achOuterScrollFrame, _achOuterScrollChild (tab scrollChild),
      _achOuterScrollActive — virtual rows use main tab ScrollFrame (single scrollbar). Hook uses ns._plansAchOuterVirtualState.
    opts.scrollChild, listWidth, categoryData, rootCategories, collapsedHeaders
    opts.selectedAchievementID, opts.onSelectAchievement, opts.contentFrameForRefresh, opts.redrawFn
    opts.acquireRow(scrollChild, listWidth, item, selectedID, onSelect, redraw, cf) -> frame
    opts.releaseRowFrame(frame)
    opts.scheduleVisibleSync(function(refreshFn)) — optional; Collections passes ScheduleCollectionsVisibleSync
    opts.onContentHeight(totalH) — optional; fired on populate AND on every collapse/expand rebuild so the
      host frame (Plans rootFrame / tab scrollChild) can follow the model height.
    opts.drawGen — optional generation token; stored on state._achPopulateGen
    opts.collectionsSubTabGen — optional; Collections sub-tab switch abort
    opts.plansCategoryGen — optional; Plans To-Do browse category switch abort
    opts.rowHeightScale — optional number passed to BuildFlatList (Plans & Collections achievements use `ns.UI_ACHIEVEMENT_BROWSE_ROW_HEIGHT_SCALE`).
]]

-- Headers are virtual items in the same flat model as rows, so only the ones inside the viewport exist
-- as frames. A collapsed tree costs a handful of frames instead of one wrap + header + body per
-- category — that eager build was the multi-second To-Do browse repopulate.
local function AcquireAchievementHeader(state, scrollChild, item, listWidth, onToggle)
    local pool = state._achHeaderPool
    if not pool then
        pool = {}
        state._achHeaderPool = pool
    end
    -- Indent is carried by the frame anchor + width, NOT by the header's internal indentLevel:
    -- applying both double-indented every nested category.
    local indentPx = item.indent or 0
    local header = pool[#pool]
    if header then
        pool[#pool] = nil
        if header:GetParent() ~= scrollChild then
            header:SetParent(scrollChild)
        end
        RebindCollapsibleHeader(header, item.label, not item.isCollapsed, onToggle, 0)
    else
        header = CreateCollapsibleHeader(scrollChild, item.label, item.key, not item.isCollapsed, onToggle,
            "UI-Achievement-Shield-NoPoints", true, 0, nil, nil)
        if not header then return nil end
        header._wnAchPooledHeader = true
        header._wnCollOnToggle = onToggle
    end
    header._wnAchSectionKey = item.key
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", indentPx, -(item.yOffset or 0))
    header:SetWidth(math.max(1, listWidth - indentPx))
    header:SetHeight(item.height or COLLAPSE_HEADER_HEIGHT_ACH)
    header:Show()
    return header
end

local function ReleaseAchievementHeader(state, header)
    if not header then return end
    header:Hide()
    header:ClearAllPoints()
    local pool = state._achHeaderPool
    if not pool then
        pool = {}
        state._achHeaderPool = pool
    end
    pool[#pool + 1] = header
end

--- Recycle every frame the list currently shows (headers to the header pool, rows to the caller's pool).
local function ReleaseAchievementVisibleFrames(state, releaseRowFrame)
    local visible = state._achVisibleRowFrames
    if not visible then return end
    local entryPool = state._achVisEntryPool
    if not entryPool then
        entryPool = {}
        state._achVisEntryPool = entryPool
    end
    for i = 1, #visible do
        local v = visible[i]
        if v then
            local frame = v.frame
            if frame then
                if v.isHeader then
                    ReleaseAchievementHeader(state, frame)
                else
                    frame:Hide()
                    frame:ClearAllPoints()
                    releaseRowFrame(frame)
                end
            end
            v.frame = nil
            v.isHeader = nil
            entryPool[#entryPool + 1] = v
        end
    end
    wipe(visible)
end

ns.UI_AchievementBrowse_ReleaseVisibleFrames = ReleaseAchievementVisibleFrames

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

    scrollChild:SetWidth(listWidth)

    ReleaseAchievementVisibleFrames(state, releaseRowFrame)

    -- Purge leftovers from an earlier draw. Pooled headers stay parented here (recycled in place, so the
    -- list never pays a reparent storm); anything still shown is an orphan from a caller that dropped
    -- `_achVisibleRowFrames` and must go back to the pool rather than linger at a stale position.
    local nch = PackVariadicInto(_achChildEnumScratch, scrollChild:GetChildren())
    for i = 1, nch do
        local c = _achChildEnumScratch[i]
        if c._wnAchPooledHeader then
            if c:IsShown() then
                ReleaseAchievementHeader(state, c)
            end
        else
            c:Hide()
            c:ClearAllPoints()
            local bin = ns.UI_RecycleBin
            if bin then c:SetParent(bin) else c:SetParent(nil) end
        end
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

    local onContentHeight = opts.onContentHeight

    --- Single rebuild path: model -> content height -> host height. Used by the first paint and by
    --- every collapse/expand. There is no second (frame-measured) height model to drift against.
    local function rebuildAchievementList()
        local flat, totalH = ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders, listBuildOpts)
        state._achFlatList = flat
        ApplyAchievementBrowseContentHeight(state, totalH)
        if type(onContentHeight) == "function" then
            onContentHeight(totalH)
        end
        return flat, totalH
    end

    local function refreshVisibleInternal()
        ns.UI_AchievementBrowse_UpdateVisibleRange({
            state = state,
            acquireRow = acquireRow,
            releaseRowFrame = releaseRowFrame,
        })
    end

    --- Section toggle: flip the model flag, rebuild O(n), re-window. No reflow pass, no measurement.
    --- `rawset` on purpose: Plans wraps `collapsedHeaders` in a metatable whose `__newindex` mirrors the
    --- durable store, and `__newindex` only fires while the key is absent — a plain write silently
    --- stopped persisting after the first toggle, so sections snapped back on the next repopulate.
    --- The durable write goes through `opts.persistCollapsed` instead, on every toggle.
    local persistCollapsed = opts.persistCollapsed
    local function onHeaderToggle(isExpanded, header)
        local key = header and header._wnAchSectionKey
        if not key then return end
        local collapsed = (isExpanded ~= true)
        rawset(collapsedHeaders, key, collapsed)
        if type(persistCollapsed) == "function" then
            persistCollapsed(key, collapsed)
        end
        rebuildAchievementList()
        refreshVisibleInternal()
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

    -- Bind list state before the first window pass (UpdateVisibleRange reads all of it).
    state._achSectionBodies = nil
    state._achListWidth = listWidth
    state._achListSelectedID = opts.selectedAchievementID
    state._achListOnSelect = opts.onSelectAchievement
    state._achListCollapsedHeaders = collapsedHeaders
    state._achListContentFrame = opts.contentFrameForRefresh
    state._achListRedrawFn = opts.redrawFn or function() end
    state._achHeaderToggleFn = onHeaderToggle
    state._achListRebuild = rebuildAchievementList

    if opts.drawGen then
        state._achPopulateGen = opts.drawGen
    end
    if opts.collectionsSubTabGen then
        state._collectionsSubTabGen = opts.collectionsSubTabGen
    end
    if opts.plansCategoryGen then
        state._plansCategoryGen = opts.plansCategoryGen
    end

    local flatList = rebuildAchievementList()

    do
        local cui = ns.CollectionsUI
        if cui and cui.CollectionsSubTabTrace then
            cui.CollectionsSubTabTrace("PopulateAchievementList_start", {
                deferChrome = deferListChrome,
                flatItems = #flatList,
            })
        end
    end

    if ns.UI_HideEmptyStateCard then
        ns.UI_HideEmptyStateCard(scrollChild, ns.UI_SEARCH_EMPTY_TAB_KEY or "search")
        ns.UI_HideEmptyStateCard(scrollChild, "collections_achievements")
    end
    -- Empty means "no categories at all". A fully collapsed tree still has headers, so it must not
    -- fall into the empty state (the flat model omits collapsed content by design).
    local searchTextRaw = opts.searchText or (state and state.searchText) or ""
    if #flatList == 0 then
        local shown = false
        if opts.searchActive and ns.UI_TryShowSearchEmptyInContainer then
            shown = ns.UI_TryShowSearchEmptyInContainer(scrollChild, searchTextRaw, 0) and true or false
        end
        if not shown and ns.UI_ShowTabEmptyStateCard then
            ns.UI_ShowTabEmptyStateCard(scrollChild, "collections_achievements", 0, { fillParent = true })
            shown = true
        end
        if shown then
            local emptyH = math.max(200, (scrollChild:GetParent() and scrollChild:GetParent():GetHeight()) or 200)
            ApplyAchievementBrowseContentHeight(state, emptyH)
            if type(onContentHeight) == "function" then
                onContentHeight(emptyH)
            end
            EndAchievementBrowseDeferredChrome()
            _populateAchievementBrowseBusy = false
            InvokeAchievementBrowseListReady(opts)
            DrainAchievementBrowsePopulateQueue()
            return
        end
    end

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

--- Overscan so a scroll delta never exposes an unbuilt header/row edge.
local ACH_WINDOW_OVERSCAN = ROW_HEIGHT * 3

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

    local scrollTop = scrollFrame:GetVerticalScroll() or 0
    local visibleHeight = scrollFrame:GetHeight() or 0
    local windowTop = scrollTop - ACH_WINDOW_OVERSCAN
    local windowBottom = scrollTop + visibleHeight + ACH_WINDOW_OVERSCAN

    -- Plans To-Do rides the main tab ScrollFrame: shift model Y into that scroll content's space.
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

    -- Entry tables + the outer list are reused across refreshes (this runs per scroll delta).
    local visible = state._achVisibleRowFrames
    local entryPool = state._achVisEntryPool
    if not entryPool then
        entryPool = {}
        state._achVisEntryPool = entryPool
    end
    if visible then
        ReleaseAchievementVisibleFrames(state, releaseRowFrame)
    else
        visible = {}
        state._achVisibleRowFrames = visible
    end

    local cf = state._achListContentFrame
    local selectedID = state._achListSelectedID or state.selectedAchievementID
    local onSelect = state._achListOnSelect
    local listWidth = state._achListWidth or scrollChild:GetWidth()
    local redrawFn = state._achListRedrawFn
    local onHeaderToggle = state._achHeaderToggleFn

    for i = 1, #flatList do
        local it = flatList[i]
        local top = (it.yOffset or 0) + listTopInContent
        local bottomEdge = top + (it.height or ROW_HEIGHT)
        if bottomEdge > windowTop and top < windowBottom then
            local frame, isHeader
            if it.type == "row" then
                frame = acquireRow(scrollChild, listWidth, it, selectedID, onSelect, redrawFn, cf)
            elseif it.type == "header" and onHeaderToggle then
                frame = AcquireAchievementHeader(state, scrollChild, it, listWidth, onHeaderToggle)
                isHeader = true
            end
            if frame then
                local entry = entryPool[#entryPool]
                if entry then
                    entryPool[#entryPool] = nil
                else
                    entry = {}
                end
                entry.frame = frame
                entry.isHeader = isHeader
                entry.flatIndex = i
                visible[#visible + 1] = entry
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
