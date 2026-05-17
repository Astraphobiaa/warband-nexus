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

--- Visual row height for painting (may be less than `it.height` slot stride for inter-row gaps).
local function ResolveRowPaintHeight(it)
    if it and it.rowPaintHeight and it.rowPaintHeight > 0 then
        return it.rowPaintHeight
    end
    return (it and it.height) or DEFAULT_ROW_HEIGHT
end

--- Anchor a virtual row: optional fixed width from populateEntry, or full container span (Characters section stack).
local function AnchorVirtualRowGeometry(frame, rowParent, container, it, pointY)
    local xOff = it.xOffset or 0
    local rightPad = container._vlm_rowPaintRightPad
    if rightPad == nil then rightPad = 4 end
    frame:SetPoint("TOPLEFT", rowParent, "TOPLEFT", xOff, -pointY)
    if container._vlm_rowSpanContainerWidth then
        frame:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -rightPad, -pointY)
        return
    end
    local paintW
    if container._vlm_fixedRowWidthFromEntry and it.populateEntry then
        paintW = it.populateEntry.rowWidth
    end
    if paintW and paintW > 0 then
        if ns.UI_ClampRowPaintWidth then
            paintW = ns.UI_ClampRowPaintWidth(rowParent, xOff, paintW, rightPad)
        end
        frame:SetPoint("TOPRIGHT", rowParent, "TOPLEFT", xOff + paintW, -pointY)
    else
        frame:SetPoint("TOPRIGHT", rowParent, "TOPRIGHT", -rightPad, -pointY)
    end
end

--- Reused header-key buffer for FlatListHeaderSignature / RefreshVirtualListFlatList (avoid GC each refresh).
local _flatListHeaderSigScratch = {}
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
            elseif rel == p
                and (rp == "BOTTOMLEFT" or rp == "BOTTOM" or rp == "BOTTOMRIGHT")
                and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT") then
                -- Section body: contentFrame TOPLEFT on header BOTTOMLEFT (Characters collapsible sections).
                local relH = (rel.GetHeight and rel:GetHeight()) or 0
                if relH > 0 then
                    delta = relH - (yo or 0)
                else
                    delta = -(yo or 0)
                end
                break
            elseif rel ~= p and rel.GetParent and rel:GetParent() == p
                and (rp == "BOTTOMLEFT" or rp == "BOTTOM" or rp == "BOTTOMRIGHT")
                and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT") then
                delta = -(yo or 0)
                break
            elseif rel ~= p
                and (rp == "BOTTOMLEFT" or rp == "BOTTOM" or rp == "BOTTOMRIGHT")
                and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT") then
                -- Section stack: header below prior section body (Characters Favorites -> Characters).
                local relH = (rel.GetHeight and rel:GetHeight()) or 0
                if relH > 0 then
                    delta = relH - (yo or 0)
                    break
                end
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
        -- Sibling under same parent (e.g. section body anchored below header): walk through header chain.
        if delta == nil and n > 0 then
            for i = 1, n do
                local pt, rel, rp, _x, yo = f:GetPoint(i)
                if rel and rel ~= f and rel.GetParent and rel:GetParent() == p
                    and (pt == "TOPLEFT" or pt == "TOP" or pt == "TOPRIGHT")
                    and (rp == "BOTTOMLEFT" or rp == "BOTTOM" or rp == "BOTTOMRIGHT") then
                    local sub = ListTopOffsetDownFromScrollContent(rel, scrollContent)
                    if sub then
                        return sum + sub
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

--- Screen-space offset from scrollChild top to container top (stable while vertical scroll changes).
local function ScreenTopOffsetDownFromScrollContent(container, scrollChild)
    if not container or not scrollChild or container == scrollChild then
        return nil
    end
    if not container.GetTop or not scrollChild.GetTop then
        return nil
    end
    local cTop = container:GetTop()
    local sTop = scrollChild:GetTop()
    if not cTop or not sTop then
        return nil
    end
    local off = sTop - cTop
    if off < 0 or off > 200000 then
        return nil
    end
    return off
end

--- Scroll-child Y of `container` top. Live screen/walk first; setup-time `containerTopOffset` is fallback only.
local function ResolveScrollTopOffset(container, scrollChild, containerTopOffset)
    if scrollChild and container then
        local screenOff = ScreenTopOffsetDownFromScrollContent(container, scrollChild)
        if screenOff then
            return screenOff
        end
        local walkOff = ListTopOffsetDownFromScrollContent(container, scrollChild)
        if walkOff and walkOff >= 0 then
            return walkOff
        end
    end
    if containerTopOffset and containerTopOffset >= 0 then
        return containerTopOffset
    end
    return 0
end

--- Per paint: never prefer stale setup snap over current layout (section stacks under headers).
local function ResolveLayoutOffsetForPaint(container, scrollChild, containerTopOffset)
    local off = ResolveScrollTopOffset(container, scrollChild, nil)
    if off and off >= 0 then
        return off
    end
    if containerTopOffset and containerTopOffset >= 0 then
        return containerTopOffset
    end
    return 0
end

local function RefreshContainerTopOffsetCache(container, scrollChild, containerTopOffset)
    if not container or not scrollChild then return end
    container._vlm_layoutTopOffset = ResolveScrollTopOffset(container, scrollChild, containerTopOffset)
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

--- Binary search in scroll-child Y: first row whose bottom > scrollTop - buffer.
local function FindFirstRowInScrollSpace(flatList, scrollTop, layoutOff, bufferPx)
    local target = scrollTop - bufferPx
    local lo, hi = 1, #flatList
    local result = hi + 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local it = flatList[mid]
        local rowTop = layoutOff + (it.yOffset or 0)
        local bottom = rowTop + (it.height or DEFAULT_ROW_HEIGHT)
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
        populateRowFn(frame, item, index),      -- full row paint (new rows, or every paint when not resizing)
        layoutRowFn(frame, item, index),        -- optional: width/geometry only (resize + reused row)
        resizeLayoutOnly = false,               -- optional: corner-drag skips cull/release; only relayout visible rows
        createHeaderFn(parent, item, index) -> frame,  -- optional
        releaseRowFn(frame),                    -- optional: custom release logic
        rowPool = {},                           -- optional: reuse table
        fixedRowWidthFromEntry = false,         -- optional: anchor TOPRIGHT at TOPLEFT+populateEntry.rowWidth (Characters live resize)
        chainCollapsibleHeaders = false,        -- optional: set true — BOTTOMLEFT chain + parent-relative X (Storage parity)
        chainAnimatedSections = false,          -- optional: chained frames are section wraps (header + tweened body); fixed SECTION_SPACING gap; rows parent under body shells
        skipChainRepositionOnRefresh = false,   -- optional: skip RepositionChainedHeaders on Refresh (animated sections — heights drive layout)
        incrementalRowReuse = false,            -- optional: reuse visible row frames by flatList rowReuseSig
    }
]]
local function SetupVirtualList(mainFrame, container, containerTopOffset, flatList, opts)
    if not mainFrame or not mainFrame.scroll or not container or not flatList then return 0 end
    container._vlm_flatList = flatList
    container._vlm_headerSig = FlatListHeaderSignature(flatList)
    opts = opts or {}
    local createRowFn = opts.createRowFn
    local populateRowFn = opts.populateRowFn
    local layoutRowFn = opts.layoutRowFn
    container._vlm_populateRowFn = populateRowFn
    container._vlm_layoutRowFn = layoutRowFn
    container._vlm_resizeLayoutOnly = opts.resizeLayoutOnly == true
    container._vlm_fixedRowWidthFromEntry = opts.fixedRowWidthFromEntry == true
    container._vlm_rowSpanContainerWidth = opts.rowSpanContainerWidth == true
    container._vlm_rowPaintRightPad = (type(opts.rowPaintRightPad) == "number") and opts.rowPaintRightPad or 4
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

    local scrollChildForNest = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild() or mainFrame.scrollChild
    container._vlm_nestedInScrollChild = scrollChildForNest and container ~= scrollChildForNest

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
            f._wnVlmPopulated = nil
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

    --- Corner-drag: relayout anchors/width on already-visible rows only (no cull, no release).
    local function UpdateVisibleRowsLayoutOnly(fl)
        local vis = container._virtualVisibleFrames
        if not vis or not fl then return end
        local layoutFn = layoutRowFn or container._vlm_layoutRowFn
        for j = 1, #vis do
            local entry = vis[j]
            local frame = entry and entry.frame
            local idx = entry and entry.index
            if frame and idx then
                local it = fl[idx]
                if it and it.type == "row" then
                    if layoutFn then
                        pcall(layoutFn, frame, it, idx)
                    end
                    local rowParent = frame:GetParent()
                    if rowParent then
                        local pointY = it.yOffset or 0
                        local xOff = it.xOffset or 0
                        if container._vlm_groupShellByKey and it.groupKey then
                            local shell = container._vlm_groupShellByKey[it.groupKey]
                            if shell then
                                rowParent = shell
                                pointY = it.localY or 0
                            end
                        end
                        frame:ClearAllPoints()
                        local paintH = ResolveRowPaintHeight(it)
                        if frame.SetHeight then frame:SetHeight(paintH) end
                        AnchorVirtualRowGeometry(frame, rowParent, container, it, pointY)
                        frame:Show()
                        if frame._wnGradientRefresh then
                            pcall(frame._wnGradientRefresh)
                        end
                    end
                end
            end
        end
    end

    local function UpdateVisible()
        if not container:IsVisible() then return end
        local resizing = mainFrame and ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(mainFrame)
        local flEarly = container._vlm_flatList or flatList
        if resizing and container._vlm_resizeLayoutOnly then
            return
        end
        local scrollTop = scrollFrame:GetVerticalScroll()
        local PixelSnap = ns.PixelSnap
        if PixelSnap then
            scrollTop = PixelSnap(scrollTop)
        end
        local viewHeight = scrollFrame:GetHeight()
        if not viewHeight or viewHeight < 10 then
            local sTop = scrollFrame:GetTop()
            local sBot = scrollFrame:GetBottom()
            if sTop and sBot then
                viewHeight = sTop - sBot
            end
        end
        if not viewHeight or viewHeight < 10 then
            viewHeight = 200
        end

        -- Map main scroll position into this container's coordinate space. Nested lists
        -- (Items groups, Storage type rows) must not use scrollChild:GetTop()-container:GetTop()
        -- (different parent spaces — caused invisible virtual rows).
        local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
        if not scrollChild and mainFrame.scrollChild then
            scrollChild = mainFrame.scrollChild
        end

        local flForBuf = container._vlm_flatList or flatList
        local bufRowH = DEFAULT_ROW_HEIGHT
        if flForBuf and flForBuf[1] and flForBuf[1].height and flForBuf[1].height > bufRowH then
            bufRowH = flForBuf[1].height
        end
        bufRowH = math.max(bufRowH, (ns.UI_LAYOUT and ns.UI_LAYOUT.STORAGE_ROW_HEIGHT) or 0)
        local bufferPx = BUFFER_ROWS * bufRowH

        -- Nested section bodies (Characters Favorites -> Characters): remeasure every paint; do not
        -- trust setup-time containerTopOffset (layout above may still be settling).
        local layoutOff = ResolveLayoutOffsetForPaint(container, scrollChild, containerTopOffset)
        container._vlm_layoutTopOffset = layoutOff
        container._vlm_remeasureTopOffset = nil

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

        local scrollBottom = scrollTop + viewHeight
        if PixelSnap then
            scrollBottom = PixelSnap(scrollBottom)
        end
        local useScrollSpaceCull = scrollChild
            and not container._vlm_groupShellByKey
            and container._vlm_nestedInScrollChild

        local function tryPaint(paintOff)
            local effectiveOff = useScrollSpaceCull and layoutOff or paintOff
            local rm = scrollTop - effectiveOff - bufferPx
            local rx = scrollTop - effectiveOff + viewHeight + bufferPx
            local startIdx = useScrollSpaceCull
                and FindFirstRowInScrollSpace(fl, scrollTop, effectiveOff, bufferPx)
                or FindFirstVisible(fl, rm)
            for i = startIdx, #fl do
                local it = fl[i]
                if not it then break end

                local y = it.yOffset or 0
                if it.type == "row" then
                    local h = it.height or DEFAULT_ROW_HEIGHT
                    local rowVisible
                    if useScrollSpaceCull then
                        local rowTop = effectiveOff + y
                        local rowBottom = rowTop + h
                        if rowTop > scrollBottom + bufferPx then
                            break
                        end
                        rowVisible = rowBottom > scrollTop and rowTop < scrollBottom
                    else
                        rowVisible = y + h > rm
                        if y > rx then
                            break
                        end
                    end
                    if rowVisible then
                        local sig = it.rowReuseSig
                        local frameReused = false
                        local frame = TakeReuseFrameForSig(sig)
                        if frame then
                            frameReused = true
                        else
                            if rowPool and #rowPool > 0 then
                                frame = rowPool[#rowPool]
                                rowPool[#rowPool] = nil
                            end
                            if not frame then
                                local ok, result = pcall(createRowFn, container, it, i)
                                if ok then frame = result end
                            end
                        end

                        local layoutFn = layoutRowFn or container._vlm_layoutRowFn
                        if frame then
                            local needsPopulate = populateRowFn
                                and (not resizing or not frameReused or not frame._wnVlmPopulated)
                            if needsPopulate then
                                pcall(populateRowFn, frame, it, i)
                                frame._wnVlmPopulated = true
                            elseif resizing and layoutFn then
                                pcall(layoutFn, frame, it, i)
                            end
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
                            local paintH = ResolveRowPaintHeight(it)
                            if frame.SetHeight then frame:SetHeight(paintH) end
                            AnchorVirtualRowGeometry(frame, rowParent, container, it, pointY)
                            if frame._wnGradientRefresh then
                                pcall(frame._wnGradientRefresh)
                            end
                            if frame.SetClipsChildren and frame._isVirtualRow then
                                frame:SetClipsChildren(true)
                            end
                            frame:Show()

                            newVis[#newVis + 1] = { frame = frame, index = i }
                        end
                    end
                elseif y > rx then
                    break
                end
            end
        end

        wipe(newVis)
        tryPaint(layoutOff)

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

    container._vlm_remeasureTopOffset = true
    if scrollFrame then
        local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild() or mainFrame.scrollChild
        if scrollChild then
            RefreshContainerTopOffsetCache(container, scrollChild, containerTopOffset)
        end
    end

    -- Staggered layout passes (0 / 0.1 / 0.25s) in one chain to avoid three independent timer registrations.
    C_Timer.After(0, function()
        if container._virtualUpdater ~= UpdateVisible then return end
        container._vlm_remeasureTopOffset = true
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
    container._vlm_remeasureTopOffset = true
    if mainFrame and mainFrame.scroll then
        local scrollChild = mainFrame.scroll:GetScrollChild() or mainFrame.scrollChild
        if scrollChild then
            RefreshContainerTopOffsetCache(container, scrollChild, nil)
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

--- Relayout visible virtual rows without culling (Characters corner-drag).
function ns.UI_VirtualListRelayoutVisibleRowsOnly(container, flatList)
    if not container or not flatList or not container._virtualVisibleFrames then return end
    local layoutFn = container._vlm_layoutRowFn
    local vis = container._virtualVisibleFrames
    for j = 1, #vis do
        local entry = vis[j]
        local frame = entry and entry.frame
        local idx = entry and entry.index
        if frame and idx then
            local it = flatList[idx]
            if it and it.type == "row" then
                if layoutFn then
                    pcall(layoutFn, frame, it, idx)
                end
                local rowParent = frame:GetParent()
                if rowParent then
                    local pointY = it.yOffset or 0
                    local xOff = it.xOffset or 0
                    frame:ClearAllPoints()
                    local paintH = ResolveRowPaintHeight(it)
                    if frame.SetHeight then frame:SetHeight(paintH) end
                    AnchorVirtualRowGeometry(frame, rowParent, container, it, pointY)
                    frame:Show()
                    if frame._wnGradientRefresh then
                        pcall(frame._wnGradientRefresh)
                    end
                end
            end
        end
    end
end

ns.VirtualListModule = {
    SetupVirtualList = SetupVirtualList,
    RefreshVirtualListFlatList = RefreshVirtualListFlatList,
    ClearVirtualScroll = ClearVirtualScroll,
    ListTopOffsetDownFromScrollContent = ListTopOffsetDownFromScrollContent,
    ResolveScrollTopOffset = ResolveScrollTopOffset,
    RefreshContainerTopOffsetCache = RefreshContainerTopOffsetCache,
    RelayoutVisibleRowsOnly = ns.UI_VirtualListRelayoutVisibleRowsOnly,
}
