--[[
    Warband Nexus - PvP Tab
    Card layout: three progress cards (Level / Honor / Conquest), five rated-bracket
    stat cards, and a mode-filtered recent match log.
    Read-only view over PvPService (db.global.pvpProgress / pvpMatches);
    refreshes on WN_PVP_UPDATED.

    Lifecycle note: PopulateContent parks unflagged scrollChild children into
    the recycle bin on every pass — every cached top-level frame here carries
    _wnKeepOnTabSwitch and is re-parented + re-anchored on each draw.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS

local L = ns.L

local M = ns.PvPUI or {}
ns.PvPUI = M
M.ns = ns
M.WarbandNexus = WarbandNexus
M.FontManager = FontManager
M.COLORS = COLORS
M.L = L

local CARD_PAD = 14
local ROW_H = 24
local HEADER_BLOCK_H = 30 -- card title row height inside a card
local SECTION_GAP = 10
local CARD_GAP = 10
local BAR_H = 16

local BRACKET_LABELS = {
    ["2v2"] = "2v2",
    ["3v3"] = "3v3",
    rbg = (L and L["PVP_MODE_RBG"]) or "Rated BG",
    shuffle = (L and L["PVP_MODE_SHUFFLE"]) or "Solo Shuffle",
    blitz = (L and L["PVP_MODE_BLITZ"]) or "Blitz",
    arena = (L and L["PVP_MODE_ARENA"]) or "Arena",
    bg = (L and L["PVP_MODE_BG"]) or "Battleground",
    unknown = "?",
}

-- Recent-match filter keys (match logic lives in PvPService.RECENT_FILTER_DEFS).
local function RecentFilterLabel(key)
    if key == "all" then return (ALL) or "All" end
    if key == "2v2" or key == "3v3" then return key end
    return BRACKET_LABELS[key] or key
end

local RECENT_TITLE_H = 22
local RECENT_FILTER_GAP = 8
local RECENT_FILTER_BTN_H = 26
local RECENT_FILTER_BTN_GAP = 6
local RECENT_FILTER_PAD_H = 8
local RECENT_SUBBAR_LAYOUT_KEY = 1
local RECENT_LIST_DIVIDER_H = 1
local RECENT_FOOTER_H = 36
local PROGRESS_CARD_MIN_W = 160

local function BuildRecentColumns(innerW)
    local gap = 6
    local wOutcome = math.max(56, math.floor(innerW * 0.13))
    local wMode = math.max(64, math.floor(innerW * 0.14))
    local wDelta = math.max(44, math.floor(innerW * 0.09))
    local wDur = math.max(44, math.floor(innerW * 0.08))
    local wAgo = math.max(40, math.floor(innerW * 0.08))
    local wMap = math.max(80, innerW - (wOutcome + wMode + wDelta + wDur + wAgo + gap * 5))
    local x = 0
    local cols = {}
    local function add(w, justify)
        cols[#cols + 1] = { x = x, w = w, justify = justify or "LEFT" }
        x = x + w + gap
    end
    add(wOutcome, "LEFT")
    add(wMode, "LEFT")
    add(wDelta, "RIGHT")
    add(wDur, "RIGHT")
    add(wMap, "LEFT")
    add(wAgo, "LEFT")
    return cols
end

local RATED_CARD_STAT_H = 18
local RATED_CARD_MIN_W = 108

-- UI_GetTextRoleHex returns the FULL "|cffXXXXXX" escape — never re-prefix it.
local function MutedHex()
    return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffaaaaaa"
end

local function BrightHex()
    return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function OutcomeMarkup(outcome)
    if outcome == "win" then
        local hex = (ns.UI_GetSemanticGreenHex and ns.UI_GetSemanticGreenHex()) or "|cff33cc55"
        return hex .. ((VICTORY) or "Victory") .. "|r"
    elseif outcome == "loss" then
        return "|cffcc4433" .. ((DEFEAT) or "Defeat") .. "|r"
    elseif outcome == "draw" then
        return MutedHex() .. ((L and L["PVP_DRAW"]) or "Draw") .. "|r"
    end
    return MutedHex() .. "?|r"
end

local function FormatDuration(sec)
    sec = tonumber(sec)
    if not sec or sec <= 0 then return "" end
    return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

local function FormatTimeLeft(sec)
    sec = tonumber(sec)
    if not sec or sec <= 0 then return nil end
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    end
    local mins = math.floor((sec % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", math.max(1, mins))
end

local function FormatTimeAgo(ts)
    ts = tonumber(ts)
    if not ts then return "" end
    local diff = math.max(0, time() - ts)
    if diff < 3600 then
        return string.format("%dm", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("%dh", math.floor(diff / 3600))
    end
    return string.format("%dd", math.floor(diff / 86400))
end

-- Cached top-level card: survives PopulateContent teardown via _wnKeepOnTabSwitch,
-- re-parented + re-themed on every draw (tab returns and theme toggles).
local function EnsureCard(bundle, key, parent, height)
    local card = bundle[key]
    if not card then
        card = (ns.UI_CreateCard and ns.UI_CreateCard(parent, height or 100))
            or (ns.UI.Factory and ns.UI.Factory:CreateContainer(parent, 200, height or 100, true))
        card._wnKeepOnTabSwitch = true
        bundle[key] = card
    end
    card:SetParent(parent)
    if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
        if ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(card)
        end
    elseif ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(card)
    end
    card:Show()
    return card
end

local function EnsureCardTitle(bundle, key, card, text)
    local fs = bundle[key]
    if not fs then
        fs = FontManager:CreateFontString(card, "title", "OVERLAY")
        bundle[key] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
    fs:SetText(text)
    ns.UI_SetTextColorRole(fs, "Bright")
    fs:Show()
    return fs
end

-- Label + status bar + right-aligned "cur / max" value line.
--- opts.uncapped: show progress bar track with no cap; max slot uses L["PVP_INFINITY"].
local function EnsureBarRow(bundle, key, card, y, labelText, cur, maxV, barColor, opts)
    opts = type(opts) == "table" and opts or {}
    local row = bundle[key]
    if not row then
        row = {}
        row.label = FontManager:CreateFontString(card, "body", "OVERLAY")
        row.value = FontManager:CreateFontString(card, "body", "OVERLAY")
        row.bar = ns.UI_CreateStatusBar and ns.UI_CreateStatusBar(card, 200, BAR_H)
        bundle[key] = row
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    row.label:SetText(labelText)
    ns.UI_SetTextColorRole(row.label, "Normal")
    row.label:Show()

    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    row.value:SetJustifyH("RIGHT")
    if opts.uncapped then
        local infText = (L and L["PVP_INFINITY"]) or "oo"
        row.value:SetText(BrightHex() .. tostring(cur or 0) .. "|r" .. MutedHex() .. " / " .. infText .. "|r")
    elseif maxV and maxV > 0 then
        row.value:SetText(BrightHex() .. tostring(cur) .. "|r" .. MutedHex() .. " / " .. tostring(maxV) .. "|r")
    else
        row.value:SetText(BrightHex() .. tostring(cur) .. "|r")
    end
    row.value:Show()

    if row.bar then
        row.bar:ClearAllPoints()
        row.bar:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(y + 20))
        row.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(y + 20))
        row.bar:SetHeight(BAR_H)
        if opts.uncapped then
            row.bar:SetMinMaxValues(0, 1)
            row.bar:SetValue(0)
            row.bar:Show()
        elseif maxV and maxV > 0 then
            row.bar:SetMinMaxValues(0, maxV)
            row.bar:SetValue(math.min(cur or 0, maxV))
            row.bar:Show()
        else
            row.bar:SetMinMaxValues(0, 1)
            row.bar:SetValue(0)
            row.bar:Hide()
        end
        if barColor then
            row.bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)
        end
    end
    return row
end

-- Cached row of column cells: bundle[listKey][rowIdx] = { fs1, fs2, ... }.
local function EnsureRowCells(bundle, listKey, rowIdx, card, cols, extraTopOffset)
    bundle[listKey] = bundle[listKey] or {}
    local cells = bundle[listKey][rowIdx]
    if not cells then
        cells = {}
        for c = 1, #cols do
            cells[c] = FontManager:CreateFontString(card, "body", "OVERLAY")
        end
        bundle[listKey][rowIdx] = cells
    end
    local rowY = CARD_PAD + HEADER_BLOCK_H + (extraTopOffset or 0) + (rowIdx - 1) * ROW_H
    for c = 1, #cols do
        local fs = cells[c]
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + cols[c].x, -rowY)
        fs:SetWidth(cols[c].w)
        fs:SetJustifyH(cols[c].justify or "LEFT")
        -- Single-line cells: long headers/values truncate instead of wrapping into the next row
        fs:SetWordWrap(false)
        fs:SetMaxLines(1)
        fs:Show()
    end
    return cells
end

local function HideRowsFrom(bundle, listKey, fromIdx)
    local rows = bundle[listKey]
    if not rows then return end
    for i = fromIdx, #rows do
        local cells = rows[i]
        for c = 1, #cells do
            cells[c]:Hide()
        end
    end
end

-- One rated-bracket stat card (2v2, 3v3, …): title + rating / season best / weekly W-P rows.
local function EnsureBracketCard(bundle, bracketKey, parent, width, height)
    local card = EnsureCard(bundle, "ratedCard_" .. bracketKey, parent, height)
    card:SetWidth(width)
    card:SetHeight(height)
    return card
end

local function EnsureBracketStatRow(bundle, bracketKey, rowIdx, card, y, labelText, valueText)
    bundle.ratedStatRows = bundle.ratedStatRows or {}
    bundle.ratedStatRows[bracketKey] = bundle.ratedStatRows[bracketKey] or {}
    local row = bundle.ratedStatRows[bracketKey][rowIdx]
    if not row then
        row = {
            label = FontManager:CreateFontString(card, "body", "OVERLAY"),
            value = FontManager:CreateFontString(card, "body", "OVERLAY"),
        }
        bundle.ratedStatRows[bracketKey][rowIdx] = row
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    row.label:SetText(labelText)
    ns.UI_SetTextColorRole(row.label, "Muted")
    row.label:Show()

    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    row.value:SetJustifyH("RIGHT")
    row.value:SetText(valueText)
    row.value:Show()
    return row
end

local function EnsureListDivider(bundle, key, card, y)
    local line = bundle[key]
    if not line then
        line = card:CreateTexture(nil, "ARTWORK")
        bundle[key] = line
    end
    local bc = COLORS.border or COLORS.accent or { 0.5, 0.5, 0.55, 0.45 }
    line:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.45)
    line:ClearAllPoints()
    line:SetHeight(RECENT_LIST_DIVIDER_H)
    line:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    line:Show()
end

-- WARBAND ROSTER (one row per tracked character; data from PvPService:GetWarbandOverview)

local ROSTER_BRACKET_ORDER = { "2v2", "3v3", "rbg", "shuffle", "blitz" }
local ROSTER_BRACKET_HEADERS = { "2v2", "3v3", "RBG", "SS", "BL" }
local ROSTER_VISIBLE_ROWS = 10
local ROSTER_TOGGLE_H = 28
local ROSTER_BOTTOM_PAD = 10
local ROSTER_COL_GAP = 8
local ROSTER_COL_WIDTH_PAD = 6
local ROSTER_COL_MIN_W = 32
local ROSTER_RATING_COL_W = 58
local ROSTER_CURRENCY_COL_MIN = 64
local ROSTER_WEEKLY_COL_MIN = 96
local ROSTER_HDR_ICON_SIZE = 22
local ROSTER_HDR_ROW_H = 48
local ROSTER_IDENTITY_GAP = 0
local ROSTER_HONOR_CURRENCY_ID = 1792
local ROSTER_CONQUEST_CURRENCY_ID = 1602

local ROSTER_STAT_HEADER_ICONS = {
    ["2v2"] = {
        iconAtlases = { "pvpqueue-sidebar-icon-arena-2v2", "PVPMatchmaking-Ico-2v2" },
        iconFallback = "Interface\\Icons\\Achievement_PVP_A_02",
    },
    ["3v3"] = {
        iconAtlases = { "pvpqueue-sidebar-icon-arena-3v3", "PVPMatchmaking-Ico-3v3" },
        iconFallback = "Interface\\Icons\\Achievement_PVP_A_03",
    },
    rbg = {
        iconAtlases = { "pvpqueue-sidebar-icon-standard", "pvpqueue-sidebar-icon-battleground" },
        iconFallback = "Interface\\Icons\\Achievement_PVP_H_13",
    },
    shuffle = {
        iconAtlases = { "pvpqueue-sidebar-icon-shuffle" },
        iconFallback = "Interface\\Icons\\Achievement_PVP_G_03",
    },
    blitz = {
        iconAtlases = { "pvpqueue-sidebar-icon-battleground" },
        iconFallback = "Interface\\Icons\\Achievement_PVP_G_01",
    },
    weekly = {
        iconAtlases = { "questlog-questtypeicon-weekly", "questlog-questtypeicon-daily" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\INV_Scroll_03",
    },
}

local _pvpRosterCurrencyIconCache = {}

local function RosterHonorHeaderLabel()
    return (HONOR) or "Honor"
end

local function RosterConquestHeaderLabel()
    return (L and L["PVP_CONQUEST"]) or "Conquest"
end

local function RosterCurrencyQuantity(charKey, currencyID)
    if not charKey or not currencyID or not WarbandNexus or not WarbandNexus.GetCurrencyData then
        return nil
    end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, currencyID, charKey)
    if not ok or not cd then return nil end
    return tonumber(cd.quantity)
end

local function FormatRosterCurrencyQty(qty)
    qty = tonumber(qty)
    if not qty then return nil end
    if qty >= 1e9 then return string.format("%.2fB", qty / 1e9) end
    if qty >= 1e6 then return string.format("%.2fM", qty / 1e6) end
    if qty >= 1e4 then return string.format("%.1fK", qty / 1e3) end
    return tostring(math.floor(qty + 0.5))
end

local function RosterWeeklyColIndex()
    return 4 + #ROSTER_BRACKET_ORDER + 1
end

local ROSTER_NAME_PAD = 4
local ROSTER_IDENTITY_MAX_NAME = 128

local function RosterUseModernHeaders()
    return not (ns.UI_IsClassicMode and ns.UI_IsClassicMode())
end

local function RosterHeaderRowHeight()
    return RosterUseModernHeaders() and ROSTER_HDR_ROW_H or ROW_H
end

local function GetRosterCurrencyIconDef(currencyID)
    if not currencyID then return nil end
    local hit = _pvpRosterCurrencyIconCache[currencyID]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    local iconFileID
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
        if ok and info and info.iconFileID then
            iconFileID = info.iconFileID
        end
    end
    if not iconFileID then
        _pvpRosterCurrencyIconCache[currencyID] = false
        return nil
    end
    local def = { icon = iconFileID, iconIsAtlas = false }
    _pvpRosterCurrencyIconCache[currencyID] = def
    return def
end

local function HideRosterModernHeaders(bundle)
    if not bundle then return end
    if bundle.rosterHdrHits then
        for _, hit in pairs(bundle.rosterHdrHits) do
            if hit and hit.Hide then hit:Hide() end
        end
    end
    if bundle.rosterHdrCompactLabels then
        for _, fs in pairs(bundle.rosterHdrCompactLabels) do
            if fs and fs.Hide then fs:Hide() end
        end
    end
end

local function ApplyRosterHeaderIconTexture(iconTex, iconDef)
    if not iconTex or not iconDef then return end
    local PUI = ns.ProfessionsUI
    if PUI and PUI.ApplyProfessionHeaderIconTexture then
        PUI.ApplyProfessionHeaderIconTexture(iconTex, iconDef)
        return
    end
    iconTex:Hide()
    if iconDef.icon and iconTex.SetTexture then
        iconTex:SetTexture(iconDef.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if ns.UI_EnsureTextureFullColor then ns.UI_EnsureTextureFullColor(iconTex) end
        iconTex:Show()
    end
end

local function PaintRosterModernStatHeader(bundle, card, colKey, col, iconDef, compactLabel, tooltipTitle, hdrExtra)
    if not bundle or not card or not col then return end
    bundle.rosterHdrHits = bundle.rosterHdrHits or {}
    bundle.rosterHdrCompactLabels = bundle.rosterHdrCompactLabels or {}

    local hitW, hitH = ROSTER_HDR_ICON_SIZE + 4, ROSTER_HDR_ICON_SIZE + 4
    local hit = bundle.rosterHdrHits[colKey]
    if not hit then
        local FactHdr = ns.UI and ns.UI.Factory
        hit = FactHdr and FactHdr:CreateContainer(card, hitW, hitH, false)
        if not hit then
            hit = CreateFrame("Frame", nil, card)
            hit:SetSize(hitW, hitH)
        end
        local iconTex = hit:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(ROSTER_HDR_ICON_SIZE, ROSTER_HDR_ICON_SIZE)
        iconTex:SetPoint("CENTER")
        hit._wnHeaderIconTex = iconTex
        bundle.rosterHdrHits[colKey] = hit
    end
    hit:SetParent(card)
    hit:SetSize(hitW, hitH)
    hit:Show()
    hit:ClearAllPoints()
    local bandTop = CARD_PAD + HEADER_BLOCK_H + (hdrExtra or 0)
    local centerX = CARD_PAD + col.x + col.w * 0.5
    hit:SetPoint("TOP", card, "TOPLEFT", centerX, -(bandTop + 6))

    local iconTex = hit._wnHeaderIconTex
    if iconTex then
        if iconDef then
            ApplyRosterHeaderIconTexture(iconTex, iconDef)
            iconTex:Show()
        else
            iconTex:Hide()
        end
    end

    if compactLabel and compactLabel ~= "" then
        local fs = bundle.rosterHdrCompactLabels[colKey]
        if not fs then
            fs = FontManager:CreateFontString(card, "small", "OVERLAY")
            bundle.rosterHdrCompactLabels[colKey] = fs
        else
            fs:SetParent(card)
            fs:Show()
        end
        fs:ClearAllPoints()
        fs:SetPoint("TOP", hit, "BOTTOM", 0, 0)
        fs:SetWidth(math.max(24, col.w - 4))
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        local hex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffaaaaaa"
        fs:SetText(hex .. compactLabel .. "|r")
        if ns.UI_IsLightMode and ns.UI_IsLightMode() then
            fs:SetShadowOffset(0, 0)
        else
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 0.9)
        end
    end

    if hit.EnableMouse then hit:EnableMouse(true) end
    if tooltipTitle and tooltipTitle ~= "" and GameTooltip then
        hit:SetScript("OnEnter", function(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            local tr, tg, tb = 1, 1, 1
            if ns.UI_GetTooltipTitleColor then
                tr, tg, tb = ns.UI_GetTooltipTitleColor()
            end
            GameTooltip:SetText(tooltipTitle, tr, tg, tb)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    else
        hit:SetScript("OnEnter", nil)
        hit:SetScript("OnLeave", nil)
    end
end

local function PaintRosterColumnHeaders(bundle, card, cols, hdrExtra, muted)
    if not RosterUseModernHeaders() then
        HideRosterModernHeaders(bundle)
        return
    end
    HideRosterModernHeaders(bundle)

    local honorDef = GetRosterCurrencyIconDef(ROSTER_HONOR_CURRENCY_ID)
    local conqDef = GetRosterCurrencyIconDef(ROSTER_CONQUEST_CURRENCY_ID)
    PaintRosterModernStatHeader(bundle, card, "honor", cols[3], honorDef, "Hon",
        RosterHonorHeaderLabel(), hdrExtra)
    PaintRosterModernStatHeader(bundle, card, "conquest", cols[4], conqDef, "Conq",
        RosterConquestHeaderLabel(), hdrExtra)

    for bi = 1, #ROSTER_BRACKET_ORDER do
        local bkey = ROSTER_BRACKET_ORDER[bi]
        PaintRosterModernStatHeader(bundle, card, bkey, cols[4 + bi],
            ROSTER_STAT_HEADER_ICONS[bkey], ROSTER_BRACKET_HEADERS[bi],
            BRACKET_LABELS[bkey] or bkey, hdrExtra)
    end

    local weeklyIdx = RosterWeeklyColIndex()
    PaintRosterModernStatHeader(bundle, card, "weekly", cols[weeklyIdx],
        ROSTER_STAT_HEADER_ICONS.weekly, "W/P",
        (L and L["PVP_WEEKLY"]) or "Weekly W/P", hdrExtra)
end

-- Identity left; stat columns packed flush to content right (natural widths, centered text).
local function BuildRosterColumns(innerW, wName, wRealm, wHonor, wConquest, wWeekly, wBracket)
    local wRating = math.max(ROSTER_RATING_COL_W, tonumber(wBracket) or ROSTER_RATING_COL_W)
    wName = math.max(48, tonumber(wName) or 72)
    wRealm = math.max(56, tonumber(wRealm) or 80)
    wHonor = math.max(ROSTER_CURRENCY_COL_MIN, tonumber(wHonor) or ROSTER_CURRENCY_COL_MIN)
    wConquest = math.max(ROSTER_CURRENCY_COL_MIN, tonumber(wConquest) or ROSTER_CURRENCY_COL_MIN)
    wWeekly = math.max(ROSTER_WEEKLY_COL_MIN, tonumber(wWeekly) or ROSTER_WEEKLY_COL_MIN)
    local bracketCount = #ROSTER_BRACKET_ORDER

    local statWs = { wHonor, wConquest }
    for _ = 1, bracketCount do
        statWs[#statWs + 1] = wRating
    end
    statWs[#statWs + 1] = wWeekly

    local cols = {}
    cols[1] = { x = 0, w = wName, justify = "LEFT" }
    cols[2] = { x = wName + ROSTER_IDENTITY_GAP, w = wRealm, justify = "LEFT" }

    local xCur = innerW
    local statCols = {}
    for i = #statWs, 1, -1 do
        xCur = xCur - statWs[i]
        statCols[i] = { x = xCur, w = statWs[i], justify = "CENTER" }
        if i > 1 then
            xCur = xCur - ROSTER_COL_GAP
        end
    end
    for i = 1, #statWs do
        cols[#cols + 1] = statCols[i]
    end
    return cols
end

local function EnsureRosterRowCells(bundle, listKey, rowIdx, card, cols, extraTopOffset)
    bundle[listKey] = bundle[listKey] or {}
    local cells = bundle[listKey][rowIdx]
    if not cells then
        cells = {}
        for c = 1, #cols do
            cells[c] = FontManager:CreateFontString(card, "body", "OVERLAY")
        end
        bundle[listKey][rowIdx] = cells
    end
    local rowY = CARD_PAD + HEADER_BLOCK_H + (extraTopOffset or 0) + (rowIdx - 1) * ROW_H
    for c = 1, #cols do
        local fs = cells[c]
        local col = cols[c]
        fs:ClearAllPoints()
        fs:SetWidth(col.w)
        fs:SetJustifyH(col.justify or "LEFT")
        fs:SetWordWrap(false)
        fs:SetMaxLines(1)
        local leftX = CARD_PAD + (col.x or 0)
        if col.justify == "CENTER" then
            fs:SetPoint("TOP", card, "TOPLEFT", leftX + col.w * 0.5, -rowY)
        else
            fs:SetPoint("TOPLEFT", card, "TOPLEFT", leftX, -rowY)
        end
        fs:Show()
    end
    return cells
end

local function ClassColorHex(classFile)
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if cc then
        return string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
    end
    return "|cffffffff"
end

local function RosterRealmHeaderLabel()
    return (L and L["CUSTOM_HEADER_COL_REALM"]) or "Realm"
end

local function MeasureRosterColumnWidths(measureFs, rosterRows)
    local maxName = 0
    local maxRealm = 0
    for i = 1, #rosterRows do
        local r = rosterRows[i]
        local nameStr = tostring(r.name or "?")
        if issecretvalue and issecretvalue(nameStr) then
            nameStr = "?"
        end
        measureFs:SetText(nameStr)
        maxName = math.max(maxName, measureFs:GetStringWidth() or 0)
        local realmStr = (ns.Utilities and ns.Utilities.FormatRealmName)
            and ns.Utilities:FormatRealmName(r.realm) or (r.realm or "")
        if realmStr ~= "" and issecretvalue and issecretvalue(realmStr) then
            realmStr = ""
        end
        if realmStr ~= "" then
            measureFs:SetText(realmStr)
            maxRealm = math.max(maxRealm, measureFs:GetStringWidth() or 0)
        end
    end
    measureFs:SetText((L and L["PVP_COL_CHARACTER"]) or "Character")
    maxName = math.max(maxName, measureFs:GetStringWidth() or 0)
    measureFs:SetText(RosterRealmHeaderLabel())
    maxRealm = math.max(maxRealm, measureFs:GetStringWidth() or 0)
    measureFs:SetText(RosterHonorHeaderLabel())
    local wHonor = math.ceil((measureFs:GetStringWidth() or 0) + ROSTER_COL_WIDTH_PAD * 2)
    measureFs:SetText(RosterConquestHeaderLabel())
    local wConquest = math.ceil((measureFs:GetStringWidth() or 0) + ROSTER_COL_WIDTH_PAD * 2)
    measureFs:SetText((L and L["PVP_WEEKLY"]) or "Weekly W/P")
    local wWeekly = math.ceil((measureFs:GetStringWidth() or 0) + ROSTER_COL_WIDTH_PAD * 2)
    local wBracket = ROSTER_RATING_COL_W
    for bi = 1, #ROSTER_BRACKET_HEADERS do
        measureFs:SetText(ROSTER_BRACKET_HEADERS[bi])
        wBracket = math.max(wBracket, math.ceil((measureFs:GetStringWidth() or 0) + ROSTER_COL_WIDTH_PAD * 2))
    end
    if RosterUseModernHeaders() then
        local iconFloor = ROSTER_HDR_ICON_SIZE + ROSTER_COL_WIDTH_PAD * 2
        wHonor = math.max(wHonor, iconFloor, ROSTER_CURRENCY_COL_MIN)
        wConquest = math.max(wConquest, iconFloor, ROSTER_CURRENCY_COL_MIN)
        wWeekly = math.max(wWeekly, iconFloor, ROSTER_WEEKLY_COL_MIN)
        wBracket = math.max(wBracket, iconFloor, ROSTER_RATING_COL_W)
    end
    wHonor = math.max(wHonor, ROSTER_CURRENCY_COL_MIN)
    wConquest = math.max(wConquest, ROSTER_CURRENCY_COL_MIN)
    wWeekly = math.max(wWeekly, ROSTER_WEEKLY_COL_MIN)
    wBracket = math.max(wBracket, ROSTER_RATING_COL_W)
    local wName = math.min(math.ceil(maxName + ROSTER_NAME_PAD * 2), ROSTER_IDENTITY_MAX_NAME)
    local wRealm = math.ceil(maxRealm + ROSTER_NAME_PAD * 2)
    return wName, wRealm, wHonor, wConquest, wWeekly, wBracket
end

local function TogglePvPRosterExpanded()
    if not ns._pvpExpandedStates then
        ns._pvpExpandedStates = {}
    end
    local key = "warbandOverview"
    ns._pvpExpandedStates[key] = not ns._pvpExpandedStates[key]
    if WarbandNexus and ns.Constants and ns.Constants.EVENTS then
        WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
            tab = "pvp",
            skipCooldown = true,
        })
    end
end

-- Selection tint behind the logged-in character's roster row.
local function EnsureRosterRowHighlight(bundle, card, rowY, show)
    local tex = bundle.rosterCurrentTint
    if not tex then
        tex = card:CreateTexture(nil, "BACKGROUND")
        bundle.rosterCurrentTint = tex
    end
    if not show then
        tex:Hide()
        return
    end
    local tint = (ns.UI_GetRowSelectionTint and ns.UI_GetRowSelectionTint()) or { 0.3, 0.25, 0.4, 0.35 }
    tex:SetColorTexture(tint[1], tint[2], tint[3], tint[4] or 0.35)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD - 4, -(rowY - 3))
    tex:SetPoint("TOPRIGHT", card, "TOPRIGHT", -(CARD_PAD - 4), -(rowY - 3))
    tex:SetHeight(ROW_H)
    tex:Show()
end

-- MATCH DETAIL TOOLTIP (Recent Matches row hover; data from entry.score)

local function FormatBigNumber(n)
    n = tonumber(n)
    if not n then return "" end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

local function MatchHasTooltipData(m)
    if not m then return false end
    local s = m.score
    if type(s) ~= "table" then return false end
    return s.killingBlows ~= nil or s.deaths ~= nil or s.damageDone ~= nil
        or s.healingDone ~= nil or s.honorGained ~= nil
        or s.prematchMMR ~= nil or s.postmatchMMR ~= nil or s.mmrChange ~= nil
end

local function ShowMatchTooltip(owner, m)
    if not (GameTooltip and MatchHasTooltipData(m)) then return end
    local s = m.score
    local tr, tg, tb = 1, 0.82, 0.2
    if ns.UI_GetTooltipTitleColor then tr, tg, tb = ns.UI_GetTooltipTitleColor() end
    local lr, lg, lb = 0.7, 0.7, 0.7
    if ns.UI_GetTooltipLabelColor then lr, lg, lb = ns.UI_GetTooltipLabelColor() end
    local br, bg, bb = 0.9, 0.9, 0.9
    if ns.UI_GetTooltipBodyColor then br, bg, bb = ns.UI_GetTooltipBodyColor() end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local modeLabel = BRACKET_LABELS[m.mode] or m.mode or "?"
    GameTooltip:AddLine(modeLabel, tr, tg, tb)
    if m.mapName then
        GameTooltip:AddLine(m.mapName, br, bg, bb)
    end

    local function addStat(label, value)
        if value == nil then return end
        GameTooltip:AddDoubleLine(label, tostring(value), lr, lg, lb, br, bg, bb)
    end
    addStat((L and L["PVP_TT_KILLING_BLOWS"]) or "Killing Blows", s.killingBlows)
    addStat((L and L["PVP_TT_DEATHS"]) or "Deaths", s.deaths)
    if s.damageDone ~= nil then
        addStat((L and L["PVP_TT_DAMAGE"]) or "Damage", FormatBigNumber(s.damageDone))
    end
    if s.healingDone ~= nil then
        addStat((L and L["PVP_TT_HEALING"]) or "Healing", FormatBigNumber(s.healingDone))
    end
    addStat((L and L["PVP_TT_HONOR_GAINED"]) or "Honor Gained", s.honorGained)

    local pre, post = tonumber(s.prematchMMR), tonumber(s.postmatchMMR)
    if not post and pre and tonumber(s.mmrChange) then
        post = pre + tonumber(s.mmrChange)
    end
    if pre or post then
        local delta = (post and pre) and (post - pre) or tonumber(s.mmrChange)
        local deltaStr = ""
        if delta and delta ~= 0 then
            local hex = delta > 0
                and ((ns.UI_GetSemanticGreenHex and ns.UI_GetSemanticGreenHex()) or "|cff33cc55")
                or "|cffcc4433"
            deltaStr = string.format(" %s(%s%d)|r", hex, delta > 0 and "+" or "", delta)
        end
        GameTooltip:AddDoubleLine((L and L["PVP_TT_MMR"]) or "MMR",
            string.format("%s > %s%s", pre and tostring(pre) or "?", post and tostring(post) or "?", deltaStr),
            lr, lg, lb, br, bg, bb)
    end
    GameTooltip:Show()
end

-- Invisible pooled hover-catcher over one recent-match row (cells are FontStrings).
local function EnsureRecentHitFrame(bundle, idx, card, rowY, innerW)
    bundle.recentHits = bundle.recentHits or {}
    local hit = bundle.recentHits[idx]
    if not hit then
        hit = (ns.UI.Factory and ns.UI.Factory:CreateContainer(card, innerW, ROW_H, false))
        if not hit then return nil end
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            if self._wnMatch then
                ShowMatchTooltip(self, self._wnMatch)
            end
        end)
        hit:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        bundle.recentHits[idx] = hit
    end
    hit:SetParent(card)
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -rowY)
    hit:SetSize(math.max(1, innerW), ROW_H)
    hit:Show()
    return hit
end

local function HideRecentHitsFrom(bundle, fromIdx)
    local hits = bundle.recentHits
    if not hits then return end
    for i = fromIdx, #hits do
        hits[i]._wnMatch = nil
        hits[i]:Hide()
    end
end

-- Export helpers/constants for PvPUI_Draw.lua (M.DrawTab uses M.* only → one upvalue).
M.CARD_PAD = CARD_PAD
M.ROW_H = ROW_H
M.HEADER_BLOCK_H = HEADER_BLOCK_H
M.SECTION_GAP = SECTION_GAP
M.CARD_GAP = CARD_GAP
M.BAR_H = BAR_H
M.BRACKET_LABELS = BRACKET_LABELS
M.RECENT_TITLE_H = RECENT_TITLE_H
M.RECENT_FILTER_GAP = RECENT_FILTER_GAP
M.RECENT_FILTER_BTN_H = RECENT_FILTER_BTN_H
M.RECENT_FILTER_BTN_GAP = RECENT_FILTER_BTN_GAP
M.RECENT_FILTER_PAD_H = RECENT_FILTER_PAD_H
M.RECENT_SUBBAR_LAYOUT_KEY = RECENT_SUBBAR_LAYOUT_KEY
M.RECENT_LIST_DIVIDER_H = RECENT_LIST_DIVIDER_H
M.RECENT_FOOTER_H = RECENT_FOOTER_H
M.PROGRESS_CARD_MIN_W = PROGRESS_CARD_MIN_W
M.RATED_CARD_STAT_H = RATED_CARD_STAT_H
M.RATED_CARD_MIN_W = RATED_CARD_MIN_W
M.ROSTER_BRACKET_ORDER = ROSTER_BRACKET_ORDER
M.ROSTER_BRACKET_HEADERS = ROSTER_BRACKET_HEADERS
M.ROSTER_VISIBLE_ROWS = ROSTER_VISIBLE_ROWS
M.ROSTER_TOGGLE_H = ROSTER_TOGGLE_H
M.ROSTER_BOTTOM_PAD = ROSTER_BOTTOM_PAD
M.ROSTER_COL_GAP = ROSTER_COL_GAP
M.ROSTER_IDENTITY_GAP = ROSTER_IDENTITY_GAP
M.ROSTER_HONOR_CURRENCY_ID = ROSTER_HONOR_CURRENCY_ID
M.ROSTER_CONQUEST_CURRENCY_ID = ROSTER_CONQUEST_CURRENCY_ID
M.RecentFilterLabel = RecentFilterLabel
M.BuildRecentColumns = BuildRecentColumns
M.MutedHex = MutedHex
M.BrightHex = BrightHex
M.OutcomeMarkup = OutcomeMarkup
M.FormatDuration = FormatDuration
M.FormatTimeLeft = FormatTimeLeft
M.FormatTimeAgo = FormatTimeAgo
M.EnsureCard = EnsureCard
M.EnsureCardTitle = EnsureCardTitle
M.EnsureBarRow = EnsureBarRow
M.EnsureRowCells = EnsureRowCells
M.HideRowsFrom = HideRowsFrom
M.EnsureBracketCard = EnsureBracketCard
M.EnsureBracketStatRow = EnsureBracketStatRow
M.EnsureListDivider = EnsureListDivider
M.RosterHonorHeaderLabel = RosterHonorHeaderLabel
M.RosterConquestHeaderLabel = RosterConquestHeaderLabel
M.RosterCurrencyQuantity = RosterCurrencyQuantity
M.FormatRosterCurrencyQty = FormatRosterCurrencyQty
M.RosterWeeklyColIndex = RosterWeeklyColIndex
M.ROSTER_COL_WIDTH_PAD = ROSTER_COL_WIDTH_PAD
M.ROSTER_RATING_COL_W = ROSTER_RATING_COL_W
M.RosterUseModernHeaders = RosterUseModernHeaders
M.RosterHeaderRowHeight = RosterHeaderRowHeight
M.PaintRosterColumnHeaders = PaintRosterColumnHeaders
M.HideRosterModernHeaders = HideRosterModernHeaders
M.BuildRosterColumns = BuildRosterColumns
M.EnsureRosterRowCells = EnsureRosterRowCells
M.ClassColorHex = ClassColorHex
M.RosterRealmHeaderLabel = RosterRealmHeaderLabel
M.MeasureRosterColumnWidths = MeasureRosterColumnWidths
M.TogglePvPRosterExpanded = TogglePvPRosterExpanded
M.EnsureRosterRowHighlight = EnsureRosterRowHighlight
M.FormatBigNumber = FormatBigNumber
M.MatchHasTooltipData = MatchHasTooltipData
M.ShowMatchTooltip = ShowMatchTooltip
M.EnsureRecentHitFrame = EnsureRecentHitFrame
M.HideRecentHitsFrom = HideRecentHitsFrom

-- DrawPvPTab lives in PvPUI_Draw.lua (WarbandNexus:DrawPvPTab facade there).


-- Thin listener: data changed → request a debounced tab repaint (no direct draw).
do
    local PvPUIListener = {}
    if WarbandNexus and WarbandNexus.RegisterMessage and ns.Constants and ns.Constants.EVENTS
        and ns.Constants.EVENTS.PVP_UPDATED then
        WarbandNexus.RegisterMessage(PvPUIListener, ns.Constants.EVENTS.PVP_UPDATED, function()
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf and mf:IsShown() and mf.currentTab == "pvp" then
                WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                    tab = "pvp",
                    skipCooldown = true,
                })
            end
        end)
    end
end
