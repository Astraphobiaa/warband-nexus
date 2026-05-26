--[[
    Warband Nexus - Column order helpers
    Shared merge/move/reset for Columns picker UIs (Professions, PvE, ...).
]]

local ADDON_NAME, ns = ...
local ColumnOrder = {}
ns.ColumnOrder = ColumnOrder

local tinsert = table.insert

--- Copy keys from `saved` that exist in `validSet`, then append any `defaultOrder` keys not yet listed.
---@param saved string[]|nil
---@param defaultOrder string[]
---@param validSet table<string, boolean>|nil optional whitelist; nil = accept any string key in defaultOrder or saved
---@return string[]
function ColumnOrder.MergeOrder(saved, defaultOrder, validSet)
    local out = {}
    local seen = {}
    local function accept(key)
        if type(key) ~= "string" or key == "" or seen[key] then return false end
        if validSet and not validSet[key] then return false end
        return true
    end
    if type(saved) == "table" then
        for i = 1, #saved do
            local key = saved[i]
            if accept(key) then
                seen[key] = true
                out[#out + 1] = key
            end
        end
    end
    for di = 1, #defaultOrder do
        local key = defaultOrder[di]
        if accept(key) then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    return out
end

--- Move `key` up (-1) or down (+1) within `order` (in-place). Returns true if moved.
---@param order string[]
---@param key string
---@param delta number -1 | 1
---@return boolean
function ColumnOrder.MoveKey(order, key, delta)
    if type(order) ~= "table" or type(key) ~= "string" or delta == 0 then return false end
    local idx
    for i = 1, #order do
        if order[i] == key then
            idx = i
            break
        end
    end
    if not idx then return false end
    local swap = idx + delta
    if swap < 1 or swap > #order then return false end
    order[idx], order[swap] = order[swap], order[idx]
    return true
end

--- Replace `order` contents with a copy of `defaultOrder` (filtered by validSet when provided).
---@param order string[]
---@param defaultOrder string[]
---@param validSet table<string, boolean>|nil
function ColumnOrder.ResetToDefault(order, defaultOrder, validSet)
    if type(order) ~= "table" then return end
    for i = #order, 1, -1 do
        order[i] = nil
    end
    local merged = ColumnOrder.MergeOrder(nil, defaultOrder, validSet)
    for i = 1, #merged do
        order[i] = merged[i]
    end
end

--- Sort an array of column defs (each with `.key`) by key order sequence.
---@param columns table[] rows with `.key`
---@param keySequence string[]
function ColumnOrder.SortColumnsByKeySequence(columns, keySequence)
    if type(columns) ~= "table" or type(keySequence) ~= "table" then return end
    local rank = {}
    for i = 1, #keySequence do
        rank[keySequence[i]] = i
    end
    table.sort(columns, function(a, b)
        local ra = rank[a and a.key] or 9999
        local rb = rank[b and b.key] or 9999
        if ra == rb then
            return tostring(a and a.key or "") < tostring(b and b.key or "")
        end
        return ra < rb
    end)
end

local ARROW_UP = "housing-floor-arrow-up-default"
local ARROW_DOWN = "housing-floor-arrow-down-default"

--- Attach compact up/down reorder controls on the right of a picker row.
---@param row Frame
---@param order string[] live profile order array (mutated on click)
---@param key string
---@param onMoved function|nil called after a successful move
---@return Frame|nil container holding up/down buttons
function ColumnOrder.AttachPickerReorderButtons(row, order, key, onMoved)
    local Factory = ns.UI and ns.UI.Factory
    if not row or not Factory or not Factory.CreateButton then return nil end
    local container = row._wnColReorderRail
    if not container then
        container = Factory:CreateContainer(row, 40, 22, false)
        row._wnColReorderRail = container
        container:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        local up = Factory:CreateButton(container, 16, 16, true)
        if Factory.ApplyIconOnlyButtonChrome then Factory:ApplyIconOnlyButtonChrome(up) end
        up:SetPoint("RIGHT", container, "RIGHT", -2, 0)
        up:SetNormalAtlas(ARROW_UP)
        container._wnUp = up
        local down = Factory:CreateButton(container, 16, 16, true)
        if Factory.ApplyIconOnlyButtonChrome then Factory:ApplyIconOnlyButtonChrome(down) end
        down:SetPoint("RIGHT", up, "LEFT", -2, 0)
        down:SetNormalAtlas(ARROW_DOWN)
        container._wnDown = down
    end
    local upBtn = container._wnUp
    local downBtn = container._wnDown
    if upBtn then
        upBtn:SetScript("OnClick", function()
            if ColumnOrder.MoveKey(order, key, -1) then
                if onMoved then onMoved() end
            end
        end)
    end
    if downBtn then
        downBtn:SetScript("OnClick", function()
            if ColumnOrder.MoveKey(order, key, 1) then
                if onMoved then onMoved() end
            end
        end)
    end
    container:Show()
    if upBtn then upBtn:Show() end
    if downBtn then downBtn:Show() end
    return container
end

return ColumnOrder
