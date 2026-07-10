--[[
    Warband Nexus - Column order helpers
    Shared merge/move/reset for Columns picker UIs (Professions, PvE, ...).
]]

local ADDON_NAME, ns = ...
local ColumnOrder = {}
ns.ColumnOrder = ColumnOrder

local tinsert = table.insert
local tremove = table.remove

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

--- Move `key` so it sits immediately before `beforeKey` (in-place). `beforeKey == nil` moves it to the end.
--- Used by drag-and-drop reorder: the drop target is expressed as "insert before this key".
---@param order string[]
---@param key string
---@param beforeKey string|nil
---@return boolean changed true when the resulting sequence actually differs
function ColumnOrder.MoveKeyBeforeKey(order, key, beforeKey)
    if type(order) ~= "table" or type(key) ~= "string" then return false end
    local from
    for i = 1, #order do
        if order[i] == key then
            from = i
            break
        end
    end
    if not from then return false end
    local before = table.concat(order, "\1")
    tremove(order, from)
    local insertAt = #order + 1
    if type(beforeKey) == "string" then
        for i = 1, #order do
            if order[i] == beforeKey then
                insertAt = i
                break
            end
        end
    end
    tinsert(order, insertAt, key)
    return table.concat(order, "\1") ~= before
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

-- DRAG-AND-DROP REORDER --------------------------------------------------------
-- Rows are re-created on every populate and may live in a clipped scroll frame, so
-- we never move the real row: the dragged row dims in place, a floating ghost follows
-- the cursor, and a drop-line marks where it lands. Siblings are discovered live from
-- the shared parent via a per-row tag, so this works with or without a scroll frame.

local activeDrag  -- { key, row, parent, order, onMoved, beforeKey }

local function AccentRGB()
    local c = ns.UI_COLORS and ns.UI_COLORS.accent
    if c then return c[1] or 0.5, c[2] or 0.6, c[3] or 1.0 end
    return 0.5, 0.6, 1.0
end

--- Cursor Y in the reference frame's coordinate space (matches GetTop/GetBottom).
local function CursorY(ref)
    local s = (ref and ref:GetEffectiveScale()) or 1
    if s <= 0 then s = 1 end
    local _, cy = GetCursorPosition()
    return (cy or 0) / s
end

--- Reorderable siblings under `parent`, top-first, excluding the dragged key.
local function CollectSiblings(parent, excludeKey)
    local out = {}
    local kids = { parent:GetChildren() }
    for i = 1, #kids do
        local f = kids[i]
        local k = f._wnColDragKey
        if k and k ~= excludeKey and f:IsShown() then
            local top, bottom = f:GetTop(), f:GetBottom()
            if top and bottom then
                out[#out + 1] = { key = k, top = top, center = (top + bottom) * 0.5, bottom = bottom }
            end
        end
    end
    table.sort(out, function(a, b) return a.center > b.center end)
    return out
end

--- Resolve drop target from cursor position: returns beforeKey (nil = append) and the line Y.
local function ResolveDrop(parent, excludeKey, cursorY)
    local rows = CollectSiblings(parent, excludeKey)
    for i = 1, #rows do
        if cursorY >= rows[i].center then
            return rows[i].key, rows[i].top
        end
    end
    if #rows > 0 then
        return nil, rows[#rows].bottom
    end
    return nil, nil
end

local function PositionDropLine(parent, lineY)
    local line = parent._wnColDropLine
    if not line then
        line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
        line:SetHeight(2)
        parent._wnColDropLine = line
    end
    local pTop = parent:GetTop()
    if not pTop or not lineY then
        line:Hide()
        return
    end
    local r, g, b = AccentRGB()
    line:SetColorTexture(r, g, b, 0.95)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 2, lineY - pTop)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -2, lineY - pTop)
    line:Show()
end

local function EnsureGhost()
    local g = ColumnOrder._dragGhost
    if not g then
        g = CreateFrame("Frame", nil, UIParent)
        g:SetFrameStrata("TOOLTIP")
        g:SetFrameLevel(9000)
        g:SetSize(180, 22)
        g:EnableMouse(false)
        local bg = g:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.75)
        g._bg = bg
        local border = g:CreateTexture(nil, "BORDER")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        g._border = border
        local fm = ns.FontManager
        local fs = fm and fm:CreateFontString(g, "body", "OVERLAY") or g:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("LEFT", 8, 0)
        fs:SetPoint("RIGHT", -8, 0)
        fs:SetJustifyH("LEFT")
        g._fs = fs
        ColumnOrder._dragGhost = g
    end
    local r, gr, b = AccentRGB()
    if g._border then g._border:SetColorTexture(r, gr, b, 0.6) end
    return g
end

local function GhostOnUpdate(g)
    local d = activeDrag
    if not d then
        g:SetScript("OnUpdate", nil)
        return
    end
    local s = UIParent:GetEffectiveScale() or 1
    if s <= 0 then s = 1 end
    local cx, cy = GetCursorPosition()
    cx, cy = (cx or 0) / s, (cy or 0) / s
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx + 12, cy + 12)
    local beforeKey, lineY = ResolveDrop(d.parent, d.key, CursorY(d.parent))
    d.beforeKey = beforeKey
    PositionDropLine(d.parent, lineY)
end

local function OnRowDragStart(row)
    local order = row._wnColOrderRef
    local parent = row:GetParent()
    if not row._wnColDragKey or not parent or type(order) ~= "table" then return end
    activeDrag = {
        key = row._wnColDragKey,
        row = row,
        parent = parent,
        order = order,
        onMoved = row._wnColOnMoved,
    }
    row:SetAlpha(0.35)
    local g = EnsureGhost()
    if g._fs then g._fs:SetText(row._wnColLabel or row._wnColDragKey) end
    g:Show()
    g:SetScript("OnUpdate", GhostOnUpdate)
end

local function OnRowDragStop(row)
    local d = activeDrag
    activeDrag = nil
    if row and row.SetAlpha then row:SetAlpha(1) end
    local g = ColumnOrder._dragGhost
    if g then
        g:SetScript("OnUpdate", nil)
        g:Hide()
    end
    if d and d.parent and d.parent._wnColDropLine then
        d.parent._wnColDropLine:Hide()
    end
    if not d then return end
    local changed = ColumnOrder.MoveKeyBeforeKey(d.order, d.key, d.beforeKey)
    if changed and d.onMoved then d.onMoved() end
end

--- Draw a 2x3 dot "grip" on the right of the row as a drag affordance. Mouse-transparent
--- so clicks/drags still reach the row. Solid textures (no atlas) — guaranteed to render.
local function EnsureRowGrip(row)
    local grip = row._wnColDragGrip
    local r, g, b = AccentRGB()
    if not grip then
        grip = CreateFrame("Frame", nil, row)
        grip:SetSize(10, 16)
        grip:EnableMouse(false)
        grip._dots = {}
        local dot, gapX, gapY = 2, 4, 5
        for col = 0, 1 do
            for rowIdx = 0, 2 do
                local t = grip:CreateTexture(nil, "OVERLAY")
                t:SetSize(dot, dot)
                t:SetPoint("TOPLEFT", grip, "TOPLEFT", 1 + col * gapX, -2 - rowIdx * gapY)
                grip._dots[#grip._dots + 1] = t
            end
        end
        row._wnColDragGrip = grip
    end
    for i = 1, #grip._dots do
        grip._dots[i]:SetColorTexture(r, g, b, 0.55)
    end
    return grip
end

--- Make a picker row drag-reorderable. Grab anywhere on the row (children like the
--- checkbox keep their own clicks) and drop it at a new position.
---@param row Frame|Button the picker row
---@param order string[] live profile order array (mutated on drop)
---@param key string this row's column key
---@param onMoved function|nil called after the order actually changes
---@param opts table|nil { label = display text shown in the drag ghost }
function ColumnOrder.AttachPickerDragReorder(row, order, key, onMoved, opts)
    if not row or type(order) ~= "table" or type(key) ~= "string" then return end
    opts = opts or {}
    -- Retire any legacy up/down rail from older builds on this recycled frame.
    if row._wnColReorderRail then row._wnColReorderRail:Hide() end
    row._wnColDragKey = key
    row._wnColOrderRef = order
    row._wnColOnMoved = onMoved
    row._wnColLabel = opts.label
    local grip = EnsureRowGrip(row)
    if grip then
        grip:ClearAllPoints()
        grip:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        grip:Show()
    end
    if row.EnableMouse then row:EnableMouse(true) end
    if row.RegisterForDrag then
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", OnRowDragStart)
        row:SetScript("OnDragStop", OnRowDragStop)
    end
end

return ColumnOrder
