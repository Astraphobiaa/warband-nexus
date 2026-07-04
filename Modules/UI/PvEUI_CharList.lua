--[[ PvEUI character row pool acquire (ops split) ]]
local _, ns = ...
local FontManager = ns.FontManager

local function getPool()
    local PvEUI = ns.PvEUI
    PvEUI._pveDrawPool = PvEUI._pveDrawPool or { charRows = {}, inline = {} }
    return PvEUI._pveDrawPool
end

local function PvEAcquireCharRowFrames(rowHost, charKey)
    local pool = getPool()
    pool.charRows = pool.charRows or {}
    local row = pool.charRows[charKey]
    if row and row.header and row.detail then
        row.header:SetParent(rowHost)
        row.detail:SetParent(rowHost)
        row.header:Show()
        return row.header, row.detail, row.expandIcon, true
    end
    row = {}
    pool.charRows[charKey] = row
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
