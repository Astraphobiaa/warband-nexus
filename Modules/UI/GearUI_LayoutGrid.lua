--[[
    Warband Nexus - Gear tab responsive layout metrics (single source of truth).
    Zones: top row = paperdoll (left) + stats/currencies (right); bottom = recommendations.

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
    SIDE_BAND_GAP = 12,
    REC_BAND_MIN_H = 128,
    REC_BAND_IDEAL_SHARE = 0.24,
    SIDE_COL_MAX_W = 320,
    SIDE_COL_IDEAL_W = 288,
    CURR_AMOUNT_COL_W = 108,
    SUBPANEL_PAD = 12,
    SUBPANEL_TITLE_INSET = 4,
    SIDE_PANEL_INSET = 8,
    SECTION_HDR_H = 28,
    SECTION_ACCENT_W = 3,
    SUBPANEL_HDR = 36,
    STAT_ROW_H = 24,
    CREST_ROW_H = 28,
    HERO_RIBBON_H = 44,
    HERO_CLASS_STRIP_W = 4,
    HERO_ILVL_PILL_W = 92,
    HERO_ILVL_PILL_H = 24,
    STORAGE_TABLE_HDR_H = 24,
    STORAGE_PANEL_HDR = 36,
    -- Stat row typography floors (label | pct | value)
    STAT_LABEL_MIN_W = 88,
    STAT_PCT_MIN_W = 52,
    STAT_VAL_MIN_W = 72,
    STAT_COL_GAP = 8,
    SIDE_COL_MIN_W = 280,
}

local L = ns.GEAR_LAYOUT

--- Minimum width for stats+currencies column from readable stat columns.
---@return number
function ns.GearUI_GetReadableSideColumnMinW()
    local pad = L.SUBPANEL_PAD * 2
    return math.max(L.SIDE_COL_MIN_W,
        pad + L.STAT_LABEL_MIN_W + L.STAT_PCT_MIN_W + L.STAT_VAL_MIN_W + L.STAT_COL_GAP * 2)
end

function ns.GearUI_GetGearTabMinCardInnerW(_recEnabled)
    return paperFixedW() + L.COL_GAP + ns.GearUI_GetReadableSideColumnMinW()
end

--- Scroll child outer width (margins + card pad included).
function ns.GearUI_GetGearTabMinScrollWidth()
    local side = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 16
    return 2 * side + 2 * L.CARD_PAD + ns.GearUI_GetGearTabMinCardInnerW(true)
end

--- Recompute after paperdoll constants bind (GearUI.lua loads before Paperdoll).
function ns.GearUI_RefreshMinScrollWidthCache()
    ns.MIN_GEAR_CARD_W = ns.GearUI_GetGearTabMinScrollWidth()
end

--- Layout math must never use a width below content minimum (scroll instead of squeeze).
---@param innerW number|nil
---@return number
function ns.GearUI_ClampCardInnerWidth(innerW)
    return math.max(ns.GearUI_GetGearTabMinCardInnerW(true), innerW or 0)
end

--- Top row: fixed paper footprint + stats/currencies column on the right.
---@param cardInnerW number
---@param _recEnabled boolean|nil
---@return number paperColW
---@return number sideColW
function ns.GearUI_ComputeTopRowWidths(cardInnerW, _recEnabled)
    local paperMin = paperFixedW()
    local sideMin = ns.GearUI_GetReadableSideColumnMinW()
    local sideMax = L.SIDE_COL_MAX_W or 340
    local sideIdeal = L.SIDE_COL_IDEAL_W or 300
    local gap = L.COL_GAP
    local sideW = math.min(sideMax, math.max(sideMin, sideIdeal))
    local minInner = ns.GearUI_GetTopRowMinInnerW(paperMin, sideW)
    local inner = math.max(minInner, cardInnerW or 0)
    -- Paperdoll column is a fixed footprint; extra card width becomes gap before the right rail.
    local paperW = paperMin
    return paperW, sideW, inner
end

---@param cardInnerW number
---@param recEnabled boolean
function ns.GearUI_ComputeLayoutWidths(cardInnerW, recEnabled)
    local paperW, sideW, _ = ns.GearUI_ComputeTopRowWidths(cardInnerW, recEnabled)
    return paperW, sideW
end

--- Top band is always paperdoll | stats+currencies; viewport narrower than min -> horizontal scroll.
---@param cardInnerW number
---@param _viewportInnerW number|nil unused (kept for callers)
---@return string mode always "row"
---@return number paperColW
---@return number sideColW
---@return number layoutInnerW
function ns.GearUI_ComputeTopRowLayout(cardInnerW, _viewportInnerW)
    local inner = ns.GearUI_ClampCardInnerWidth(cardInnerW)
    local paperW, sideW, layoutInnerW = ns.GearUI_ComputeTopRowWidths(inner)
    paperW = math.max(paperW, paperFixedW())
    return "row", paperW, sideW, layoutInnerW
end

--- Show hint when horizontal scroll is required (viewport narrower than content min).
---@param mf Frame|nil
function ns.GearUI_UpdateScrollWidthHint(mf)
    if not mf then return end
    local hint = mf._gearScrollWidthHint
    if mf.currentTab ~= "gear" then
        if hint and hint.Hide then hint:Hide() end
        return
    end
    local scroll = mf.scroll
    local rng = (scroll and scroll.GetHorizontalScrollRange and scroll:GetHorizontalScrollRange()) or 0
    local show = rng and rng > 4
    if not show then
        if hint and hint.Hide then hint:Hide() end
        return
    end
    local card = mf._gearPaperdollCard
    if not card then return end
    if not hint then
        local FontManager = ns.FontManager
        if not FontManager then return end
        hint = FontManager:CreateFontString(card, "small", "OVERLAY")
        mf._gearScrollWidthHint = hint
        hint:SetJustifyH("CENTER")
        hint:SetTextColor(0.55, 0.58, 0.65)
    end
    local msg = (ns.L and ns.L["GEAR_LAYOUT_SCROLL_HINT"]) or "Narrow window: scroll horizontally or widen the frame."
    hint:SetText("|cff999999" .. msg .. "|r")
    hint:ClearAllPoints()
    hint:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 14, 10)
    hint:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -14, 10)
    hint:Show()
end

--- Stat row columns inside the side panel (shared by draw + live relayout).
---@param statInnerW number
---@param colGap number|nil
---@return number labelColW
---@return number valColW
---@return number pctColW
function ns.GearUI_ComputeStatColumnWidths(statInnerW, colGap)
    local gap = colGap or L.STAT_COL_GAP
    local valColW = L.STAT_VAL_MIN_W
    local pctColW = L.STAT_PCT_MIN_W
    local minInner = L.STAT_LABEL_MIN_W + pctColW + valColW + gap * 2
    local inner = math.max(minInner, statInnerW or 0)
    -- Reserve value + percent columns first; label absorbs remaining space.
    local labelColW = math.max(L.STAT_LABEL_MIN_W, inner - pctColW - valColW - gap * 2)
    return labelColW, valColW, pctColW
end

--- Stats over currencies in the right column (always stacked).
function ns.GearUI_ComputeSideColumnLayout(sideColW, statPanelH, currenciesH, centerGap)
    local gap = centerGap or L.SIDE_BAND_GAP
    local w = math.max(ns.GearUI_GetReadableSideColumnMinW(), sideColW or 0)
    local statH = statPanelH or 120
    local currH = currenciesH or 120
    return "stack", w, w, gap, statH + gap + currH
end

--- Measured paperdoll footprint (slots + track labels + optional model boost).
---@param modelBoost number|nil
---@return number
function ns.GearUI_GetPaperdollColumnWidth(modelBoost)
    if ns.GearUI_PaperdollColumnWidth then
        local modelW = (ns.GEAR_PAPERDOLL and ns.GEAR_PAPERDOLL.MODEL_W) or nil
        if modelW then
            return ns.GearUI_PaperdollColumnWidth(modelW + math.max(0, modelBoost or 0))
        end
    end
    return paperFixedW()
end

--- Minimum inner width for paper | gap | stats row without overlap.
---@param paperColW number|nil
---@param sideColW number|nil
---@return number
function ns.GearUI_GetTopRowMinInnerW(paperColW, sideColW)
    local gap = L.COL_GAP
    local paper = paperColW or paperFixedW()
    local side = sideColW or ns.GearUI_GetReadableSideColumnMinW()
    return paper + gap + side
end

function ns.GearUI_ComputeRecBandHeight(recEnabled, panelH, topZoneH)
    if not recEnabled then return 0 end
    local minH = L.REC_BAND_MIN_H
    local panel = panelH or 0
    local top = topZoneH or 0
    if panel > top + L.SECTION_GAP + minH then
        local remain = panel - top - L.SECTION_GAP
        return math.max(minH, math.floor(remain * L.REC_BAND_IDEAL_SHARE + 0.5))
    end
    return minH
end

function ns.GearUI_ComputeBottomBandLayout(paperColW, statPanelH, currenciesH, centerGap)
    return ns.GearUI_ComputeSideColumnLayout(paperColW, statPanelH, currenciesH, centerGap)
end

function ns.GearUI_ResolveCardInnerWidth(scrollChildW, sideMargin)
    local side = sideMargin or 16
    local minInner = ns.GearUI_GetGearTabMinCardInnerW(true)
    local w = scrollChildW or 0
    if w < 1 then
        return minInner
    end
    return ns.GearUI_ClampCardInnerWidth(w - 2 * side - 2 * L.CARD_PAD)
end
