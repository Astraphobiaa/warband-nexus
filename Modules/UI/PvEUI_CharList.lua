--[[ PvEUI character row pool acquire (ops split) ]]
local _, ns = ...
local FontManager = ns.FontManager

--- Shared with PvEUI.lua (`_pveDrawPool`, assigned to ns.PvEUI._pveDrawPool at load) and BodyPaint (L._pveDrawPool).
local function getPool()
    local PvEUI = ns.PvEUI
    local pool = PvEUI._pveDrawPool
    if not pool then
        pool = {}
        PvEUI._pveDrawPool = pool
    end
    pool.charRows = pool.charRows or {}
    pool.inline = pool.inline or {}
    return pool
end

--- Reused rows come back unanchored: the caller re-chains them (stale anchors into a recycled
--- section body or an old row order must not survive). BodyPaint registers new rows in pool.charRows.
local function PvEAcquireCharRowFrames(rowHost, charKey)
    local pool = getPool()
    local row = pool.charRows[charKey]
    if row and row.header and row.detail then
        local header, detail = row.header, row.detail
        if header:GetParent() ~= rowHost then header:SetParent(rowHost) end
        if detail:GetParent() ~= rowHost then detail:SetParent(rowHost) end
        header:ClearAllPoints()
        header:Show()
        return header, detail, row.expandIcon, true
    end
    return nil, nil, nil, false
end

local function PvEAcquireInlineCell(charHeader, charKey, colKey)
    local pool = getPool()
    local byCol = pool.inline[charKey]
    if not byCol then
        byCol = {}
        pool.inline[charKey] = byCol
    end
    local cell = byCol[colKey]
    if not cell then
        cell = {}
        cell.fs = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        cell.fs._pvePooledInline = true
        byCol[colKey] = cell
    else
        cell.fs:SetParent(charHeader)
        cell.fs:Show()
    end
    return cell
end

ns.PvEUI = ns.PvEUI or {}
ns.PvEUI.PvEAcquireCharRowFrames = PvEAcquireCharRowFrames
ns.PvEUI.PvEAcquireInlineCell = PvEAcquireInlineCell
