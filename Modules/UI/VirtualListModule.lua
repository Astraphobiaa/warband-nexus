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

local BUFFER_ROWS = 2
local DEFAULT_ROW_HEIGHT = 26

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

--[[
    Setup virtual list for a tab's results container.

    opts = {
        createRowFn(parent, item, index) -> frame,
        populateRowFn(frame, item, index),      -- optional: re-populate pooled frame
        createHeaderFn(parent, item, index) -> frame,  -- optional
        releaseRowFn(frame),                    -- optional: custom release logic
        rowPool = {},                           -- optional: reuse table
    }
]]
local function SetupVirtualList(mainFrame, container, containerTopOffset, flatList, opts)
    if not mainFrame or not mainFrame.scroll or not container or not flatList then return 0 end
    opts = opts or {}
    local createRowFn = opts.createRowFn
    local populateRowFn = opts.populateRowFn
    local createHeaderFn = opts.createHeaderFn
    local releaseRowFn = opts.releaseRowFn
    local rowPool = opts.rowPool

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
    local function ReleaseVisible()
        local visible = container._virtualVisibleFrames
        if not visible then return end
        for i = 1, #visible do
            local entry = visible[i]
            local f = entry and entry.frame
            if f and f:IsShown() and f:GetParent() == container then
                f._isVirtualRow = nil
                if releaseRowFn then
                    releaseRowFn(f)
                else
                    f:Hide()
                    f:ClearAllPoints()
                    if rowPool then rowPool[#rowPool + 1] = f end
                end
            end
        end
        container._virtualVisibleFrames = {}
    end

    ReleaseVisible()
    container._virtualVisibleFrames = {}

    -- Clean up orphaned virtual row frames from previous renders.
    -- PopulateContent clears _virtualVisibleFrames before tab redraw, so ReleaseVisible()
    -- can miss them. Only target frames tagged _isVirtualRow to avoid hiding inline headers
    -- that tabs create before calling SetupVirtualList (e.g. StorageUI).
    local oldChildren = {container:GetChildren()}
    for i = 1, #oldChildren do
        local child = oldChildren[i]
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
        for i = 1, #flatList do
            local it = flatList[i]
            if it and it.type == "header" then
                local ok, hf = pcall(createHeaderFn, container, it, i)
                if ok and hf then
                    hf:ClearAllPoints()
                    hf:SetPoint("TOPLEFT", container, "TOPLEFT", it.xOffset or 0, -(it.yOffset or 0))
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

        -- Use explicit caller-provided offset when available.
        -- Auto-detect only when caller does not provide one.
        local offset = containerTopOffset
        if offset == nil then
            offset = 0
            local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
            if scrollChild then
                local scTop = scrollChild:GetTop()
                local cTop = container:GetTop()
                if scTop and cTop then
                    offset = scTop - cTop
                end
            end
        end

        local rangeMin = scrollTop - offset
        local rangeMax = rangeMin + viewHeight

        local bufferPx = BUFFER_ROWS * DEFAULT_ROW_HEIGHT
        rangeMin = rangeMin - bufferPx
        rangeMax = rangeMax + bufferPx

        ReleaseVisible()

        local startIdx = FindFirstVisible(flatList, rangeMin)

        for i = startIdx, #flatList do
            local it = flatList[i]
            if not it then break end

            local y = it.yOffset or 0
            if y > rangeMax then break end

            if it.type == "row" then
                local h = it.height or DEFAULT_ROW_HEIGHT
                if y + h > rangeMin then
                    local frame
                    if rowPool and #rowPool > 0 then
                        frame = rowPool[#rowPool]
                        rowPool[#rowPool] = nil
                    end

                    local ok, result
                    if frame and populateRowFn then
                        ok, result = pcall(populateRowFn, frame, it, i)
                        if not ok then frame = nil end
                    end

                    if not frame then
                        ok, result = pcall(createRowFn, container, it, i)
                        if ok then frame = result end
                    end

                    if frame then
                        frame._isVirtualRow = true
                        frame:SetParent(container)
                        frame:ClearAllPoints()
                        frame:SetPoint("TOPLEFT", container, "TOPLEFT", it.xOffset or 0, -y)
                        frame:Show()

                        local vis = container._virtualVisibleFrames
                        vis[#vis + 1] = { frame = frame, index = i }
                    end
                end
            end
        end
    end

    mainFrame._virtualScrollUpdate = UpdateVisible

    C_Timer.After(0, function()
        if mainFrame._virtualScrollUpdate == UpdateVisible then
            UpdateVisible()
        end
    end)
    C_Timer.After(0.1, function()
        if mainFrame._virtualScrollUpdate == UpdateVisible then
            UpdateVisible()
        end
    end)
    C_Timer.After(0.25, function()
        if mainFrame._virtualScrollUpdate == UpdateVisible then
            UpdateVisible()
        end
    end)

    return totalHeight
end

local function ClearVirtualScroll(mainFrame)
    if mainFrame then
        mainFrame._virtualScrollUpdate = nil
    end
end

ns.VirtualListModule = {
    SetupVirtualList = SetupVirtualList,
    ClearVirtualScroll = ClearVirtualScroll,
}
