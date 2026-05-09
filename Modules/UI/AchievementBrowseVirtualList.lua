--[[
    Shared achievement category browser: flat list + nested accordion headers + virtual rows.
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
local SIDE_MARGIN = LAYOUT.SIDE_MARGIN or 10
local PADDING = SIDE_MARGIN
local ROW_HEIGHT = LAYOUT.ROW_HEIGHT or 26
local HEADER_HEIGHT = LAYOUT.HEADER_HEIGHT or 32
local BASE_INDENT = LAYOUT.BASE_INDENT or 15
local SECTION_SPACING = LAYOUT.SECTION_SPACING or LAYOUT.betweenSections or 8
local MINI_SPACING = LAYOUT.MINI_SPACING or LAYOUT.miniSpacing or 4

local _populateAchievementBrowseBusy = false

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
function ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders)
    local flat = {}
    local yOffset = 0
    local rowCounter = 0
    local rD, gD, bD = (COLORS.textDim[1] or 0.55), (COLORS.textDim[2] or 0.55), (COLORS.textDim[3] or 0.55)
    local countColor = format("|cff%02x%02x%02x", rD * 255, gD * 255, bD * 255)
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

    for rootIndex = 1, #rootCategories do
        local rootID = rootCategories[rootIndex]
        local rootCat = categoryData[rootID]
        local totalAchievements = CountCategoryAchievements(rootID)
        if rootCat and totalAchievements > 0 then
            local rootKey = "achievement_cat_" .. rootID
            local rootExpanded = (collapsedHeaders[rootKey] == false)
            flat[#flat + 1] = {
                type = "header",
                key = rootKey,
                label = titleColor .. (rootCat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(totalAchievements) .. ")|r",
                rightStr = countColor .. FormatNumber(totalAchievements) .. "|r",
                itemCount = totalAchievements,
                isCollapsed = not rootExpanded,
                yOffset = yOffset,
                height = HEADER_HEIGHT,
                indent = 0,
            }
            yOffset = yOffset + HEADER_HEIGHT + MINI_SPACING

            for i = 1, #rootCat.achievements do
                local ach = rootCat.achievements[i]
                rowCounter = rowCounter + 1
                flat[#flat + 1] = { type = "row", achievement = ach, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT, indent = BASE_INDENT }
                yOffset = yOffset + ROW_HEIGHT
            end
            if #(rootCat.children or {}) > 0 and #rootCat.achievements > 0 then
                yOffset = yOffset + SECTION_SPACING
            end

            for childIdx = 1, #rootCat.children do
                local childID = rootCat.children[childIdx]
                local childCat = categoryData[childID]
                local childAchievementCount = CountCategoryAchievements(childID)
                if childCat and childAchievementCount > 0 then
                    local childKey = "achievement_cat_" .. childID
                    local childExpanded = (collapsedHeaders[childKey] == false)
                    flat[#flat + 1] = {
                        type = "header",
                        key = childKey,
                        label = titleColor .. (childCat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(childAchievementCount) .. ")|r",
                        rightStr = countColor .. FormatNumber(childAchievementCount) .. "|r",
                        itemCount = childAchievementCount,
                        isCollapsed = not childExpanded,
                        yOffset = yOffset,
                        height = HEADER_HEIGHT,
                        indent = BASE_INDENT,
                    }
                    yOffset = yOffset + HEADER_HEIGHT + MINI_SPACING

                    for i = 1, #childCat.achievements do
                        local ach = childCat.achievements[i]
                        rowCounter = rowCounter + 1
                        flat[#flat + 1] = { type = "row", achievement = ach, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT, indent = BASE_INDENT * 2 }
                        yOffset = yOffset + ROW_HEIGHT
                    end
                    if #(childCat.children or {}) > 0 and #childCat.achievements > 0 then
                        yOffset = yOffset + SECTION_SPACING
                    end

                    local childChildren = childCat.children or {}
                    for grandchildIdx = 1, #childChildren do
                        local grandchildID = childChildren[grandchildIdx]
                        local grandchildCat = categoryData[grandchildID]
                        local grandchildCount = CountCategoryAchievements(grandchildID)
                        if grandchildCat and grandchildCount > 0 then
                            local gcKey = "achievement_cat_" .. grandchildID
                            local gcExpanded = (collapsedHeaders[gcKey] == false)
                            flat[#flat + 1] = {
                                type = "header",
                                key = gcKey,
                                label = titleColor .. (grandchildCat.name or "") .. "|r " .. countColor .. "(" .. FormatNumber(grandchildCount) .. ")|r",
                                rightStr = countColor .. FormatNumber(grandchildCount) .. "|r",
                                itemCount = grandchildCount,
                                isCollapsed = not gcExpanded,
                                yOffset = yOffset,
                                height = HEADER_HEIGHT,
                                indent = BASE_INDENT * 2,
                            }
                            yOffset = yOffset + HEADER_HEIGHT + MINI_SPACING

                            for i = 1, #grandchildCat.achievements do
                                local ach = grandchildCat.achievements[i]
                                rowCounter = rowCounter + 1
                                flat[#flat + 1] = { type = "row", achievement = ach, rowIndex = rowCounter, yOffset = yOffset, height = ROW_HEIGHT, indent = BASE_INDENT * 3 }
                                yOffset = yOffset + ROW_HEIGHT
                            end
                        end
                        if grandchildIdx < #childChildren then
                            yOffset = yOffset + SECTION_SPACING
                        end
                    end
                end
                if childIdx < #(rootCat.children or {}) then
                    yOffset = yOffset + SECTION_SPACING
                end
            end

            yOffset = yOffset + SECTION_SPACING
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
]]
function ns.UI_AchievementBrowse_Populate(opts)
    if not opts or not opts.scrollChild or not Factory then return end
    if _populateAchievementBrowseBusy then return end
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
        return
    end

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

    local flatList, totalHeight = ns.UI_AchievementBrowse_BuildFlatList(categoryData, rootCategories, collapsedHeaders)
    scrollChild:SetHeight(totalHeight)

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
            local yBottom = yTop + (fit.height or ROW_HEIGHT)

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
                local contentTopY = yTop + (fit.height or HEADER_HEIGHT)
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

    local function ComputeAchievementContentHeight(catID, activeAnimKey, activeAnimBodyH)
        local cat = categoryData and categoryData[catID]
        if not cat then return 0 end
        local bodyH = MINI_SPACING + (#(cat.achievements or {}) * ROW_HEIGHT)
        local children = cat.children or {}
        if #children > 0 and #(cat.achievements or {}) > 0 then
            bodyH = bodyH + SECTION_SPACING
        end
        for childIdx = 1, #children do
            local childID = children[childIdx]
            local childCount = CountAchievementTree(childID)
            if childCount > 0 then
                local childKey = "achievement_cat_" .. childID
                bodyH = bodyH + HEADER_HEIGHT
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
                if childIdx < #children then
                    bodyH = bodyH + SECTION_SPACING
                end
            end
        end
        return math.max(0.1, bodyH)
    end

    local function ReflowAchievementAccordionHeights(activeAnimKey, activeAnimBodyH)
        for i = 1, #achHeaderKeys do
            local key = achHeaderKeys[i]
            local meta = achHeaderMeta[key]
            local catID = meta and meta.categoryID
            local body = state._achSectionBodies and state._achSectionBodies[key]
            local wrap = achSectionWraps[key]
            if catID and body then
                local fullH = ComputeAchievementContentHeight(catID, activeAnimKey, activeAnimBodyH)
                body._wnAccordionFullH = fullH
                if key ~= activeAnimKey and collapsedHeaders[key] == false then
                    body:SetHeight(fullH)
                end
                if wrap then
                    wrap:SetHeight(COLLAPSE_H_COLL + math.max(0.1, body:GetHeight() or 0.1))
                end
            end
        end
    end

    for i = 1, #flatList do
        local it = flatList[i]
        if it.type == "header" then
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
            local secH = achSectionContentH[key] or 0
            if secH <= 0 then
                secH = ((it.itemCount or 0) * ROW_HEIGHT) or 0
            end
            local header = CreateCollapsibleHeader(sectionWrap, it.label, key, not it.isCollapsed, function(isExpanded)
                if isExpanded then
                    refreshVisibleInternal()
                end
            end, "UI-Achievement-Shield-NoPoints", true, indentLevel, nil, ns.UI_BuildAccordionVisualOpts({
                wrapFrame = sectionWrap,
                bodyGetter = function() return sectionBody end,
                headerHeight = COLLAPSE_H_COLL,
                hideOnCollapse = true,
                applyToggleBeforeCollapseAnimate = true,
                persistFn = function(exp)
                    collapsedHeaders[key] = not exp
                end,
                onUpdate = function(drawH)
                    ReflowAchievementAccordionHeights(key, drawH)
                end,
                updateVisibleFn = function()
                    refreshVisibleInternal()
                end,
                onComplete = function(exp)
                    ReflowAchievementAccordionHeights()
                    if not exp then
                        refreshVisibleInternal()
                    end
                end,
            }))
            header:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
            header:SetWidth(wrapW)
            header:SetHeight(it.height)

            sectionBody = Factory:CreateContainer(sectionWrap, wrapW, 0.1, false)
            sectionBody:ClearAllPoints()
            sectionBody:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            sectionBody:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
            sectionBody._wnAccordionFullH = secH
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
        end
    end

    ReflowAchievementAccordionHeights()

    state._achFlatList = flatList
    state._achFlatListTotalHeight = totalHeight
    state._achListWidth = listWidth
    state._achListSelectedID = selectedAchievementID
    state._achListOnSelect = onSelectAchievement
    state._achListCollapsedHeaders = collapsedHeaders
    state._achListContentFrame = cf
    state._achListRedrawFn = redraw
    state._achListRefreshVisible = refreshVisibleInternal

    local scrollFrame = state.achievementListScrollFrame
    if scrollFrame then
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
    refreshVisibleInternal()
    if type(scheduleVisibleSync) == "function" then
        scheduleVisibleSync(refreshVisibleInternal)
    end
    _populateAchievementBrowseBusy = false
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
