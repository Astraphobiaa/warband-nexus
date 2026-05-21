--[[
    Warband Nexus - Gear tab responsive layout metrics (single source of truth).
    Zones: single row = paperdoll (left) | recommendations (right); hero ribbon above.

    Resize contract (matches LayoutCoordinator / UI.lua):
    - Content has a hard minimum width; never squeeze columns below readable floors.
    - Viewport narrower than minimum -> horizontal scroll (scrollChild stays at min width).
    - Do not overlap: if inner width < sum(mins), clamp to min and scroll.
]]

local _, ns = ...

local PAPERDOLL_BLOCK_W = nil

function ns.GearUI_BindPaperdollLayoutConstants(paperdollBlockW, _leftPanelW)
    PAPERDOLL_BLOCK_W = paperdollBlockW
    if ns.GearUI_RefreshMinScrollWidthCache then
        ns.GearUI_RefreshMinScrollWidthCache()
    end
end

local function paperFixedW()
    return (PAPERDOLL_BLOCK_W or 700) + 8
end

---@class GearUILayoutTokens
ns.GEAR_LAYOUT = {
    CARD_PAD = 14,
    COL_GAP = 32,
    PAPER_COL_INSET = 6,
    SECTION_GAP = 16,
    REC_COL_MIN_W = 300,
    REC_COL_IDEAL_W = 380,
    REC_COL_MAX_W = 520,
    PAPER_COL_IDEAL_SHARE = 0.56,
    PAPER_COL_MAX_EXTRA_W = 120,
    SUBPANEL_PAD = 12,
    SUBPANEL_TITLE_INSET = 4,
    SECTION_HDR_H = 28,
    SECTION_ACCENT_W = 3,
    SUBPANEL_HDR = 36,
    STORAGE_TABLE_HDR_H = 24,
    STORAGE_PANEL_HDR = 36,
    CONTENT_BAND_MIN_H = 360,
    PAPER_BOTTOM_BAND_MIN_H = 132,
    STAT_ROW_H = 24,
    CREST_ROW_H = 28,
    SIDE_BAND_GAP = 8,
    CURR_AMOUNT_COL_W = 108,
}

local L = ns.GEAR_LAYOUT

function ns.GearUI_GetReadableRecColumnMinW()
    return L.REC_COL_MIN_W or 300
end

function ns.GearUI_GetGearTabMinCardInnerW(_recEnabled)
    local recMin = (_recEnabled ~= false) and ns.GearUI_GetReadableRecColumnMinW() or 0
    return paperFixedW() + (recMin > 0 and (L.COL_GAP + recMin) or 0)
end

function ns.GearUI_GetGearTabMinScrollWidth()
    local side = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 16
    return 2 * side + 2 * L.CARD_PAD + ns.GearUI_GetGearTabMinCardInnerW(true)
end

function ns.GearUI_RefreshMinScrollWidthCache()
    ns.MIN_GEAR_CARD_W = ns.GearUI_GetGearTabMinScrollWidth()
end

function ns.GearUI_ClampCardInnerWidth(innerW)
    return math.max(ns.GearUI_GetGearTabMinCardInnerW(true), innerW or 0)
end

--- Top row: fixed paper footprint + flexible recommendations column.
---@param cardInnerW number
---@param recEnabled boolean|nil
---@return number paperColW
---@return number recColW
---@return number layoutInnerW
function ns.GearUI_ComputeTopRowWidths(cardInnerW, recEnabled)
    local paperMin = paperFixedW()
    local gap = L.COL_GAP
    if recEnabled == false then
        local inner = math.max(paperMin, cardInnerW or 0)
        return paperMin, 0, inner
    end
    local recMin = ns.GearUI_GetReadableRecColumnMinW()
    local recMax = L.REC_COL_MAX_W or 520
    local recIdeal = L.REC_COL_IDEAL_W or 380
    local inner = math.max(1, cardInnerW or 0)
    if inner < paperMin + gap + recMin then
        return paperMin, recMin, inner
    end
    local avail = math.max(0, inner - gap)
    local paperShare = L.PAPER_COL_IDEAL_SHARE or 0.56
    local paperTarget = math.max(paperMin, math.floor(avail * paperShare + 0.5))
    local paperExtraCap = L.PAPER_COL_MAX_EXTRA_W or 120
    paperTarget = math.min(paperTarget, paperMin + paperExtraCap)
    local paperW = math.min(paperTarget, avail - recMin)
    paperW = math.max(paperMin, paperW)
    local recW = math.min(recMax, math.max(recMin, recIdeal, avail - paperW))
    if avail > paperW + recW then
        recW = avail - paperW
    end
    return paperW, recW, inner
end

---@param cardInnerW number
---@param recEnabled boolean
function ns.GearUI_ComputeLayoutWidths(cardInnerW, recEnabled)
    local paperW, recW = ns.GearUI_ComputeTopRowWidths(cardInnerW, recEnabled)
    return paperW, recW
end

---@param cardInnerW number
---@param _viewportInnerW number|nil unused (kept for callers)
---@return string mode always "row"
---@return number paperColW
---@return number recColW
---@return number layoutInnerW
function ns.GearUI_ComputeTopRowLayout(cardInnerW, _viewportInnerW)
    local inner = ns.GearUI_ClampCardInnerWidth(cardInnerW)
    local paperW, recW, layoutInnerW = ns.GearUI_ComputeTopRowWidths(inner, true)
    paperW = math.max(paperW, paperFixedW())
    return "row", paperW, recW, layoutInnerW
end

function ns.GearUI_UpdateScrollWidthHint(mf)
    -- Layout uses stack mode when narrow; an on-card hint overlapped stats/currencies and confused users.
    if not mf then return end
    local hint = mf._gearScrollWidthHint
    if hint and hint.Hide then hint:Hide() end
end

--- Legacy stat column helper (Characters tab / other callers); unused by Gear tab layout.
function ns.GearUI_ComputeStatColumnWidths(statInnerW, colGap)
    local gap = colGap or 8
    local valColW = 72
    local pctColW = 52
    local minInner = 88 + pctColW + valColW + gap * 2
    local inner = math.max(minInner, statInnerW or 0)
    local labelColW = math.max(88, inner - pctColW - valColW - gap * 2)
    return labelColW, valColW, pctColW
end

---@param paperColW number|nil
---@param recColW number|nil
---@return number
function ns.GearUI_GetTopRowMinInnerW(paperColW, recColW)
    local gap = L.COL_GAP
    local paper = paperColW or paperFixedW()
    local rec = recColW or ns.GearUI_GetReadableRecColumnMinW()
    if rec < 1 then return paper end
    return paper + gap + rec
end

function ns.GearUI_GetPaperdollColumnWidth(modelBoost)
    if ns.GearUI_PaperdollColumnWidth then
        local modelW = (ns.GEAR_PAPERDOLL and ns.GEAR_PAPERDOLL.MODEL_W) or nil
        if modelW then
            return ns.GearUI_PaperdollColumnWidth(modelW + math.max(0, modelBoost or 0))
        end
    end
    return paperFixedW()
end

function ns.GearUI_ResolveCardInnerWidth(scrollChildW, sideMargin)
    local side = sideMargin or 16
    local w = scrollChildW or 0
    if w < 1 then
        return ns.GearUI_GetGearTabMinCardInnerW(true)
    end
    return math.max(1, w - 2 * side - 2 * L.CARD_PAD)
end
