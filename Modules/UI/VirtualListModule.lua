--[[
    Warband Nexus - Virtual List Module
    Shared virtual scroll for list-based tabs. Only renders visible rows.
    Reduces frame count and improves FPS on long lists.
]]

local ADDON_NAME, ns = ...

--[[
    Setup virtual list for a tab's results container.
    flatList: array of { type="header"|"row", yOffset, height, ... }
    createRowFn(parent, item, index) -> frame
    createHeaderFn(parent, item, index) -> frame (optional)
    containerTopOffset: Y offset of container from scrollChild top (for visibility calc)
]]
local function SetupVirtualList(mainFrame, container, containerTopOffset, flatList, createRowFn, createHeaderFn, rowPool)
    if not mainFrame or not mainFrame.scroll or not container or not flatList then return 0 end
    if not createRowFn or type(createRowFn) ~= "function" then return 0 end

    local scrollFrame = mainFrame.scroll
    local scrollChild = mainFrame.scrollChild
    if not scrollFrame or not scrollChild then return 0 end

    -- Compute total height from last item
    local totalHeight = 1
    if #flatList > 0 then
        local last = flatList[#flatList]
        totalHeight = (last.yOffset or 0) + (last.height or 26)
    end
    totalHeight = math.max(totalHeight, 1)

    -- Release previous visible frames to pool
    local visibleFrames = container._virtualVisibleFrames or {}
    for i = 1, #visibleFrames do
        local f = visibleFrames[i]
        if f and f.Hide then f:Hide() f:ClearAllPoints() end
        if rowPool and type(rowPool) == "table" then
            rowPool[#rowPool + 1] = f
        end
    end
    container._virtualVisibleFrames = {}

    -- Create headers (fixed, always in DOM when in range - we create all for simplicity on first draw)
    -- Headers are few; only virtualize rows
    local headerFrames = {}
    for i = 1, #flatList do
        local it = flatList[i]
        if it and it.type == "header" and createHeaderFn then
            local hf = createHeaderFn(container, it, i)
            if hf then
                hf:ClearAllPoints()
                hf:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(it.yOffset or 0))
                hf:Show()
                headerFrames[#headerFrames + 1] = hf
            end
        end
    end

    local function UpdateVisible()
        if not container:IsVisible() then return end
        local scrollTop = scrollFrame:GetVerticalScroll()
        local viewHeight = scrollFrame:GetHeight() or 400
        local bottom = scrollTop + viewHeight

        -- Visible range in container coordinates
        local rangeMin = scrollTop - containerTopOffset
        local rangeMax = bottom - containerTopOffset

        -- Release current visible row frames
        local visible = container._virtualVisibleFrames or {}
        for i = 1, #visible do
            local v = visible[i]
            if v and v.frame and v.frame.Hide then
                v.frame:Hide()
                v.frame:ClearAllPoints()
                if rowPool and type(rowPool) == "table" then
                    rowPool[#rowPool + 1] = v.frame
                end
            end
        end
        container._virtualVisibleFrames = {}

        -- Create row frames for visible range
        for i = 1, #flatList do
            local it = flatList[i]
            if it and it.type == "row" then
                local y = it.yOffset or 0
                local h = it.height or 26
                if y + h > rangeMin and y < rangeMax then
                    local frame = nil
                    if rowPool and #rowPool > 0 then
                        frame = rowPool[#rowPool]
                        rowPool[#rowPool] = nil
                    end
                    if not frame then
                        frame = createRowFn(container, it, i)
                    end
                    if frame then
                        frame:ClearAllPoints()
                        frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
                        frame:Show()
                        table.insert(container._virtualVisibleFrames, { frame = frame, index = i })
                    end
                end
            end
        end
    end

    -- Register with main frame
    mainFrame._virtualScrollUpdate = UpdateVisible

    -- Initial population
    UpdateVisible()

    return totalHeight
end

-- Clear virtual scroll state when switching tabs
local function ClearVirtualScroll(mainFrame)
    if mainFrame then
        mainFrame._virtualScrollUpdate = nil
    end
end

ns.VirtualListModule = {
    SetupVirtualList = SetupVirtualList,
    ClearVirtualScroll = ClearVirtualScroll,
}
