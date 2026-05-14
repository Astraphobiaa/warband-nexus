--[[
    Warband Nexus - Virtual List Module
    Shared virtual scroll for list-based tabs. Only renders visible rows.
    Reduces frame count and improves FPS on long lists.

    Usage pattern for any tab:
        1. Build flatList = { {type="header"|"row", yOffset=N, height=H, data=...}, ... }
        2. Call SetupVirtualList(mainFrame, container, containerTopOffset, flatList, opts)
        3. Module handles scroll events and row lifecycle automatically.

    Tabs that create headers INLINE (before calling SetupVirtualList) are safe because
    orphan cleanup only targets frames tagged with _isVirtualRow.
]]

local ADDON_NAME, ns = ...

local wipe = wipe

local BUFFER_ROWS = 2
local DEFAULT_ROW_HEIGHT = 26

--- Reused header-key buffer for FlatListHeaderSignature / RefreshVirtualListFlatList (avoid GC each refresh).
local _flatListHeaderSigScratch = {}
--- Reused offset-candidate list for UpdateVisible (avoids a small table alloc per scroll tick).
local _vlmCandidateScratch = {}

--- Pixels from scroll content top down to `listFrame` top (TOP anchor chain). Same idea as
--- AchievementBrowseVirtualList, extended for Storage/ChainSectionFrameBelow patterns.
--- Returns nil if the chain cannot be resolved.
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
            local pt, rel, rp, _x, yo = f:GetPoint(i)
            if not rel or not rp or not pt then
                -- skip invalid point
            elseif rel == p and (rp == "TOPLEFT" or rp == "TOP" or rp == "TOPRIGHT")
                and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT") then
                delta = -(yo or 0)
                break
            elseif rel ~= p and rel.GetParent and rel:GetParent() == p
                and (rp == "BOTTOMLEFT" or rp == "BOTTOM" or rp == "BOTTOMRIGHT")
                and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT") then
                delta = -(yo or 0)
                break
            end
        end
        -- Second pass: any TOP→BOTTOM chain to sibling or parent (handles GetPoint order quirks).
        if delta == nil and n > 0 then
            for i = 1, n do
                local pt, rel, rp, _x, yo = f:GetPoint(i)
                if rel and rp and pt
                    and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT")
                    and (rp == "BOTTOMLEFT" or rp == "BOTTOM" or rp == "BOTTOMRIGHT") then
                    if rel == p or (rel.GetParent and rel:GetParent() == p) then
                        delta = -(yo or 0)
                        break
                    end
                end
            end
        end
        if delta == nil then return nil end
        sum = sum + delta
        f = p
    end
    return nil
end

--- Pack `frame:GetChildren()` into one reused array (WoW returns variadic children).
local _vlmOrphanChildScratch = {}
local function PackVariadicInto(dest, ...)
    wipe(dest)
    local n = select("#", ...)
    for i = 1, n do
        dest[i] = select(i, ...)
    end
    return n
end

--- Stable signature of header keys (Items: data.group.groupKey; generic: it.key).
local function FlatListHeaderSignature(flatList)
    if not flatList then return "" end
    local parts = _flatListHeaderSigScratch
    wipe(parts)
    for i = 1, #flatList do
        local it = flatList[i]
        if it and it.type == "header" then
            local gk = it.key or (it.data and it.data.group and it.data.group.groupKey)
            parts[#parts + 1] = tostring(gk or ("_" .. i))
        end
    end
    return table.concat(parts, "\001")
end

local function EnsureVirtualUpdaterDispatcher(mainFrame)
    if not mainFrame then return nil end
    if not mainFrame._virtualScrollUpdaters then
        mainFrame._virtualScrollUpdaters = {}
    end
    if not mainFrame._virtualScrollUpdate then
        mainFrame._virtualScrollUpdate = function()
            local updaters = mainFrame._virtualScrollUpdaters
            if not updaters then return end
            for i = 1, #updaters do
                local fn = updaters[i]
                if type(fn) == "function" then
                    fn()
                end
            end
        end
    end
    return mainFrame._virtualScrollUpdaters
end

local function RegisterVirtualUpdater(mainFrame, container, updateFn)
    if not mainFrame or not container or type(updateFn) ~= "function" then return end
    local updaters = EnsureVirtualUpdaterDispatcher(mainFrame)
    if not updaters then return end

    local previous = container._virtualUpdater
    if previous then
        for i = #updaters, 1, -1 do
            if updaters[i] == previous then
                table.remove(updaters, i)
            end
        end
    end

    container._virtualUpdater = updateFn
    updaters[#updaters + 1] = updateFn
end

--[[
    Binary search: find first item whose (yOffset + height) > target.
    flatList must be sorted by yOffset (ascending).
]]
local function FindFirstVisible(flatList, target)
    local lo, hi = 1, #flatList
    local result = hi + 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local it = flatList[mid]
        local bottom = (it.yOffset or 0) + (it.height or DEFAULT_ROW_HEIGHT)
        if bottom > target then
            result = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    return result
end

--- Row frames may be parented under group shells (Bank/Items collapsible groups); walk ancestors.
local function VirtualRowIsUnderContainer(rowFrame, container)
    local p = rowFrame and rowFrame:GetParent()
    while p do
        if p == container then return true end
        p = p:GetParent()
    end
    return false
end

--- Reposition inline chained headers after flatList yOffsets change (Refresh path).
--- SetupVirtualList stores chain frames in `container._vlm_chainHeaders` when opts.chainCollapsibleHeaders is true.
local function RepositionChainedHeadersFromFlatList(container, flatList)
    if not container._vlm_chainCollapsibleHeaders or not container._vlm_chainHeaders then
        return true
    end
    local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
    if not ChainSectionFrameBelow then
        return false
    end
    local headers = container._vlm_chainHeaders
    local layoutCollapseH = container._vlm_layoutCollapseH or DEFAULT_ROW_HEIGHT
    local secGap = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_SPACING) or 8
    local hi = 1
    local prevHeaderFrame, prevHeaderYO, prevHeaderH = nil, nil, nil
    for i = 1, #flatList do
        local it = flatList[i]
        if it and it.type == "header" then
            local hf = headers[hi]
            if not hf then
                return false
            end
            hi = hi + 1
            hf:ClearAllPoints()
            local xOff = it.xOffset or 0
            local yTop = it.yOffset or 0
            if container._vlm_chainAnimatedSections then
                if prevHeaderFrame then
                    ChainSectionFrameBelow(container, hf, prevHeaderFrame, xOff, secGap, nil)
                else
                    ChainSectionFrameBelow(container, hf, nil, xOff, nil, yTop)
                end
                prevHeaderFrame = hf
            else
                local hfH = it.height or layoutCollapseH
                local gapBelow = nil
                if prevHeaderFrame and prevHeaderYO ~= nil then
                    gapBelow = yTop - prevHeaderYO - (prevHeaderH or layoutCollapseH)
                    if gapBelow < 0 then gapBelow = 0 end
                end
                ChainSectionFrameBelow(container, hf, prevHeaderFrame, xOff, gapBelow, prevHeaderFrame and nil or yTop)
                prevHeaderFrame = hf
                prevHeaderYO = yTop
                prevHeaderH = hfH
            end
        end
    end
    if hi - 1 ~= #headers then
        return false
    end
    return true
end

--[[
    Setup virtual list for a tab's results container.

    opts = {
        createRowFn(parent, item, index) -> frame,
        populateRowFn(frame, item, index),      -- optional: re-populate pooled frame
        createHeaderFn(parent, item, index) -> frame,  -- optional
        releaseRowFn(frame),                    -- optional: custom release logic
        rowPool = {},                           -- optional: reuse table
        chainCollapsibleHeaders = false,        -- optional: set true — BOTTOMLEFT chain + parent-relative X (Storage parity)
        chainAnimatedSections = false,          -- optional: chained frames are section wraps (header + tweened body); fixed SECTION_SPACING gap; rows parent under body shells
        skipChainRepositionOnRefresh = false,   -- optional: skip RepositionChainedHeaders on Refresh (animated sections — heights drive layout)
        incrementalRowReuse = false,            -- optional: reuse visible row frames by flatList rowReuseSig; populateRowFn still runs every paint when set
    }
]]
local function SetupVirtualList(mainFrame, container, containerTopOffset, flatList, opts)
    if not mainFrame or not mainFrame.scroll or not container or not flatList then return 0 end
    container._vlm_flatList = flatList
    container._vlm_headerSig = FlatListHeaderSignature(flatList)
    opts = opts or {}
    local createRowFn = opts.createRowFn
    local populateRowFn = opts.populateRowFn
    local createHeaderFn = opts.createHeaderFn
    local releaseRowFn = opts.releaseRowFn
    local rowPool = opts.rowPool
    local chainCollapsibleHeaders = opts.chainCollapsibleHeaders == true
    local chainAnimatedSections = opts.chainAnimatedSections == true
    container._vlm_incrementalRowReuse = opts.incrementalRowReuse == true
    container._vlm_chainAnimatedSections = chainAnimatedSections
    container._vlm_skipChainRepositionOnRefresh = (opts.skipChainRepositionOnRefresh == true) or chainAnimatedSections
    container._vlm_groupShellByKey = chainAnimatedSections and {} or nil
    local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
    local layoutCollapseH = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT) or DEFAULT_ROW_HEIGHT
    local secGap = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_SPACING) or 8

    if not createRowFn or type(createRowFn) ~= "function" then return 0 end

    local scrollFrame = mainFrame.scroll
    if not scrollFrame then return 0 end

    local totalHeight = 1
    if #flatList > 0 then
        local last = flatList[#flatList]
        totalHeight = (last.yOffset or 0) + (last.height or DEFAULT_ROW_HEIGHT)
    end
    totalHeight = math.max(totalHeight, 1)

    -- Release previous visible frames tracked by _virtualVisibleFrames
    local function ReleaseOneVirtualRow(f)
        if not f then return end
        if f:IsShown() and VirtualRowIsUnderContainer(f, container) then
            f._isVirtualRow = nil
            f._vlm_rowSig = nil
            if releaseRowFn then
                releaseRowFn(f)
            else
                f:Hide()
                f:ClearAllPoints()
                if rowPool then rowPool[#rowPool + 1] = f end
            end
        end
    end

    local function ReleaseVisible()
        local visible = container._virtualVisibleFrames
        if not visible then return end
        for i = 1, #visible do
            local entry = visible[i]
            ReleaseOneVirtualRow(entry and entry.frame)
        end
        wipe(visible)
    end

    ReleaseVisible()
    local visBufA = container._vlm_visBufA
    local visBufB = container._vlm_visBufB
    if not visBufA then
        visBufA = {}
        container._vlm_visBufA = visBufA
    end
    if not visBufB then
        visBufB = {}
        container._vlm_visBufB = visBufB
    end
    wipe(visBufA)
    wipe(visBufB)
    container._virtualVisibleFrames = visBufA

    -- Clean up orphaned virtual row frames from previous renders.
    -- PopulateContent clears _virtualVisibleFrames before tab redraw, so ReleaseVisible()
    -- can miss them. Only target frames tagged _isVirtualRow to avoid hiding inline headers
    -- that tabs create before calling SetupVirtualList (e.g. StorageUI).
    local noc = PackVariadicInto(_vlmOrphanChildScratch, container:GetChildren())
    for i = 1, noc do
        local child = _vlmOrphanChildScratch[i]
        if child._isVirtualRow then
            child._isVirtualRow = nil
            if releaseRowFn then
                pcall(releaseRowFn, child)
            else
                child:Hide()
            end
        end
    end

    -- Create headers upfront (headers are few; not virtualized)
    if createHeaderFn then
        container._vlm_chainHeaders = nil
        container._vlm_chainCollapsibleHeaders = nil
        container._vlm_layoutCollapseH = nil
        if chainCollapsibleHeaders then
            container._vlm_chainHeaders = {}
            container._vlm_chainCollapsibleHeaders = true
            container._vlm_layoutCollapseH = layoutCollapseH
        end
        local prevHeaderFrame = nil
        local prevHeaderYO = nil
        local prevHeaderH = nil
        for i = 1, #flatList do
            local it = flatList[i]
            if it and it.type == "header" then
                local ok, hf = pcall(createHeaderFn, container, it, i)
                if ok and hf then
                    hf:ClearAllPoints()
                    if chainCollapsibleHeaders and ChainSectionFrameBelow then
                        local xOff = it.xOffset or 0
                        local yTop = it.yOffset or 0
                        if chainAnimatedSections then
                            if prevHeaderFrame then
                                ChainSectionFrameBelow(container, hf, prevHeaderFrame, xOff, secGap, nil)
                            else
                                ChainSectionFrameBelow(container, hf, nil, xOff, nil, yTop)
                            end
                            prevHeaderFrame = hf
                        else
                            local hfH = it.height or layoutCollapseH
                            local gapBelow = nil
                            if prevHeaderFrame and prevHeaderYO ~= nil then
                                gapBelow = yTop - prevHeaderYO - (prevHeaderH or layoutCollapseH)
                                if gapBelow < 0 then gapBelow = 0 end
                            end
                            ChainSectionFrameBelow(container, hf, prevHeaderFrame, xOff, gapBelow, prevHeaderFrame and nil or yTop)
                            prevHeaderFrame = hf
                            prevHeaderYO = yTop
                            prevHeaderH = hfH
                        end
                        container._vlm_chainHeaders[#container._vlm_chainHeaders + 1] = hf
                    else
                        hf:SetPoint("TOPLEFT", container, "TOPLEFT", it.xOffset or 0, -(it.yOffset or 0))
                    end
                    hf:Show()
                end
            end
        end
    end

    local function UpdateVisible()
        if not container:IsVisible() then return end
        local scrollTop = scrollFrame:GetVerticalScroll()
        local viewHeight = scrollFrame:GetHeight()
        if not viewHeight or viewHeight < 10 then
            viewHeight = 1000 -- Fallback to ensure rows render even if layout is pending
        end

        -- Map main scroll position into this container's coordinate space. Nested lists
        -- (Items groups, Storage type rows) must not use scrollChild:GetTop()-container:GetTop()
        -- (different parent spaces — caused invisible virtual rows).
        local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
        if not scrollChild and mainFrame.scrollChild then
            scrollChild = mainFrame.scrollChild
        end

        local bufferPx = BUFFER_ROWS * DEFAULT_ROW_HEIGHT
        local walkOff = nil
        if scrollChild then
            walkOff = ListTopOffsetDownFromScrollContent(container, scrollChild)
        end
        -- Try several offsets when the anchor walk returns a bogus non-nil (over-counted chain):
        -- rangeMax can shrink so much that y > rangeMax on the first row and nothing paints.
        wipe(_vlmCandidateScratch)
        local candidates = _vlmCandidateScratch
        local function pushUnique(v)
            if v == nil then return end
            for j = 1, #candidates do
                if candidates[j] == v then return end
            end
            candidates[#candidates + 1] = v
        end
        pushUnique(containerTopOffset)
        pushUnique(walkOff)
        pushUnique(0)
        if scrollChild then
            local scTop = scrollChild:GetTop()
            local cTop = container:GetTop()
            if scTop and cTop then
                pushUnique(scTop - cTop)
            end
        end
        if #candidates == 0 then
            candidates[1] = 0
        end

        local incrementalReuse = container._vlm_incrementalRowReuse == true
        local oldVis = container._virtualVisibleFrames

        local function TakeReuseFrameForSig(sig)
            if not incrementalReuse or not oldVis or not sig then return nil end
            for j = 1, #oldVis do
                local f = oldVis[j] and oldVis[j].frame
                if f and f._vlm_stale and f._vlm_rowSig == sig then
                    f._vlm_stale = false
                    return f
                end
            end
            return nil
        end

        if incrementalReuse then
            if oldVis then
                for j = 1, #oldVis do
                    local f = oldVis[j] and oldVis[j].frame
                    if f then
                        f._vlm_stale = true
                    end
                end
            end
        else
            ReleaseVisible()
        end

        local visA = container._vlm_visBufA
        local visB = container._vlm_visBufB
        if not visA or not visB then
            visA = visA or {}
            visB = visB or {}
            container._vlm_visBufA = visA
            container._vlm_visBufB = visB
        end
        local newVis = (oldVis == visA) and visB or visA
        wipe(newVis)

        local fl = container._vlm_flatList or flatList
        if not fl or #fl == 0 then
            if incrementalReuse and oldVis then
                for j = 1, #oldVis do
                    ReleaseOneVirtualRow(oldVis[j] and oldVis[j].frame)
                end
            end
            container._virtualVisibleFrames = newVis
            return
        end

        local hasRowEntries = false
        for ii = 1, #fl do
            if fl[ii] and fl[ii].type == "row" then
                hasRowEntries = true
                break
            end
        end

        local function tryPaint(off)
            local rm = scrollTop - off - bufferPx
            local rx = scrollTop - off + viewHeight + bufferPx
            local startIdx = FindFirstVisible(fl, rm)
            for i = startIdx, #fl do
                local it = fl[i]
                if not it then break end

                local y = it.yOffset or 0
                if y > rx then break end

                if it.type == "row" then
                    local h = it.height or DEFAULT_ROW_HEIGHT
                    if y + h > rm then
                        local sig = it.rowReuseSig
                        local frame = TakeReuseFrameForSig(sig)

                        if not frame then
                            if rowPool and #rowPool > 0 then
                                frame = rowPool[#rowPool]
                                rowPool[#rowPool] = nil
                            end
                            if not frame then
                                local ok, result = pcall(createRowFn, container, it, i)
                                if ok then frame = result end
                            end
                        end

                        if frame and populateRowFn then
                            pcall(populateRowFn, frame, it, i)
                        end

                        if frame then
                            if sig then
                                frame._vlm_rowSig = sig
                            end
                            frame._isVirtualRow = true
                            local rowParent = container
                            local pointY = y
                            local xOff = it.xOffset or 0
                            if container._vlm_groupShellByKey and it.groupKey then
                                local shell = container._vlm_groupShellByKey[it.groupKey]
                                if shell then
                                    rowParent = shell
                                    pointY = it.localY or 0
                                end
                            end
                            frame:SetParent(rowParent)
                            frame:ClearAllPoints()
                            frame:SetPoint("TOPLEFT", rowParent, "TOPLEFT", xOff, -pointY)
                            frame:Show()

                            newVis[#newVis + 1] = { frame = frame, index = i }
                        end
                    end
                end
            end
        end

        for ci = 1, #candidates do
            wipe(newVis)
            tryPaint(candidates[ci])
            if #newVis > 0 or not hasRowEntries then
                break
            end
        end

        if incrementalReuse and oldVis then
            for j = 1, #oldVis do
                local f = oldVis[j] and oldVis[j].frame
                if f and f._vlm_stale then
                    ReleaseOneVirtualRow(f)
                    f._vlm_stale = nil
                end
            end
        end

        container._virtualVisibleFrames = newVis
    end

    RegisterVirtualUpdater(mainFrame, container, UpdateVisible)

    -- Staggered layout passes (0 / 0.1 / 0.25s) in one chain to avoid three independent timer registrations.
    C_Timer.After(0, function()
        if container._virtualUpdater ~= UpdateVisible then return end
        UpdateVisible()
        C_Timer.After(0.1, function()
            if container._virtualUpdater ~= UpdateVisible then return end
            UpdateVisible()
            C_Timer.After(0.15, function()
                if container._virtualUpdater == UpdateVisible then
                    UpdateVisible()
                end
            end)
        end)
    end)

    return totalHeight
end

--- Swap flat list data without rebuilding headers (same header signature as last SetupVirtualList).
--- Returns totalHeight, or nil + true when callers must run full SetupVirtualList again.
local function RefreshVirtualListFlatList(mainFrame, container, flatList)
    if not container or not flatList then return 0 end
    local newSig = FlatListHeaderSignature(flatList)
    if not container._vlm_headerSig then
        return nil, true
    end
    if newSig ~= container._vlm_headerSig then
        return nil, true
    end
    container._vlm_flatList = flatList
    local totalHeight = 1
    if #flatList > 0 then
        local last = flatList[#flatList]
        totalHeight = (last.yOffset or 0) + (last.height or DEFAULT_ROW_HEIGHT)
    end
    totalHeight = math.max(totalHeight, 1)
    if container.SetHeight then
        container:SetHeight(totalHeight)
    end
    -- Animated section wraps resize during layout — reposition from flatList fights in-flight heights.
    if not container._vlm_skipChainRepositionOnRefresh then
        if not RepositionChainedHeadersFromFlatList(container, flatList) then
            return nil, true
        end
    end
    if container._virtualUpdater then
        container._virtualUpdater()
    end
    return totalHeight
end

local function ClearVirtualScroll(mainFrame)
    if mainFrame then
        mainFrame._virtualScrollUpdaters = nil
        mainFrame._virtualScrollUpdate = nil
    end
end

ns.VirtualListModule = {
    SetupVirtualList = SetupVirtualList,
    RefreshVirtualListFlatList = RefreshVirtualListFlatList,
    ClearVirtualScroll = ClearVirtualScroll,
    ListTopOffsetDownFromScrollContent = ListTopOffsetDownFromScrollContent,
}
