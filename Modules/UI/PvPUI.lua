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

-- Honor level is warband-wide in Midnight — no per-character honor column.
local function BuildRosterColumns(innerW)
    local gap = 6
    local wRating = 56
    local wWeekly = 96
    local fixed = wRating * #ROSTER_BRACKET_ORDER + wWeekly
        + gap * (#ROSTER_BRACKET_ORDER + 1)
    local wName = math.max(120, innerW - fixed)
    local x = 0
    local cols = {}
    local function add(w, justify)
        cols[#cols + 1] = { x = x, w = w, justify = justify or "LEFT" }
        x = x + w + gap
    end
    add(wName, "LEFT")
    for _ = 1, #ROSTER_BRACKET_ORDER do
        add(wRating, "RIGHT")
    end
    add(wWeekly, "RIGHT")
    return cols
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

local function ClassColorHex(classFile)
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if cc then
        return string.format("|cff%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
    end
    return "|cffffffff"
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

function WarbandNexus:DrawPvPTab(parent)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local SIDE = (metrics and metrics.sideMargin) or 16
    local width = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)

    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or (metrics and metrics.topMargin) or 12

    local bundle = parent._wnPvPBundle
    if not bundle then
        bundle = {}
        parent._wnPvPBundle = bundle
    end

    -- Title card
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleCard = bundle.titleCard
    if not titleCard then
        titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "pvp",
            titleText = "|cff" .. hexColor .. ((L and L["TAB_PVP"]) or "PvP") .. "|r",
            subtitleText = (L and L["PVP_SUBTITLE"]) or "Rated progress, honor, and match history",
            showUnderline = false,
        }))
        bundle.titleCard = titleCard
    end
    titleCard:SetParent(headerParent)
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", SIDE, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -SIDE, -headerYOffset)
    end
    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    elseif fixedHeader then
        headerYOffset = headerYOffset + (titleCard:GetHeight() or 64) + 8
        fixedHeader:SetHeight(headerYOffset)
    end

    local yOffset = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8

    local progress, matches
    if ns.PvPService then
        progress, matches = ns.PvPService:GetSummary()
    end
    local honorCur, conqCur
    if ns.PvPService and ns.PvPService.GetCurrencyOverview then
        honorCur, conqCur = ns.PvPService:GetCurrencyOverview()
    end
    local brackets = (progress and progress.brackets) or {}
    local honor = (progress and progress.honor) or {}
    -- Snapshot taken before this week's reset → weekly W/P values display as 0
    local weeklyStaleCur = ns.PvPService and ns.PvPService.IsRatedWeeklyStale
        and ns.PvPService:IsRatedWeeklyStale(progress) or false
    local muted = MutedHex()
    local bright = BrightHex()
    local goldColor = (ns.UI_GetSemanticGoldColor and { ns.UI_GetSemanticGoldColor() }) or { 1, 0.82, 0.2 }
    local accentColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }

    -- Row 1: PvP Level Progress | Honor | Conquest (three equal cards)
    do
        if bundle.capsCard then
            bundle.capsCard:Hide()
        end

        local progressCardH = CARD_PAD + HEADER_BLOCK_H + 20 + BAR_H + CARD_PAD
        local availW = width - SIDE * 2
        local triGap = CARD_GAP
        local triW = math.max(PROGRESS_CARD_MIN_W, math.floor((availW - triGap * 2) / 3))
        local barY = CARD_PAD + HEADER_BLOCK_H
        local lvlFmt = (L and L["PVP_HONOR_LEVEL"]) or "Honor Level %d"

        local levelCard = EnsureCard(bundle, "levelCard", parent, progressCardH)
        levelCard:ClearAllPoints()
        levelCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        levelCard:SetWidth(triW)
        levelCard:SetHeight(progressCardH)
        EnsureCardTitle(bundle, "levelTitle", levelCard, (L and L["PVP_LEVEL_PROGRESS"]) or "PvP Level Progress")
        EnsureBarRow(bundle, "levelBarRow", levelCard, barY,
            string.format(lvlFmt, honor.level or 0), honor.current or 0, honor.max or 0, goldColor)

        local honorCard = EnsureCard(bundle, "honorCard", parent, progressCardH)
        honorCard:ClearAllPoints()
        honorCard:SetPoint("TOPLEFT", SIDE + triW + triGap, -yOffset)
        honorCard:SetWidth(triW)
        honorCard:SetHeight(progressCardH)
        EnsureCardTitle(bundle, "honorTitle", honorCard, (HONOR) or "Honor")
        EnsureBarRow(bundle, "honorBarRow", honorCard, barY,
            (HONOR) or "Honor", (honorCur and honorCur.quantity) or 0,
            (honorCur and honorCur.maxQuantity) or 0, goldColor)

        local conquestCard = EnsureCard(bundle, "conquestCard", parent, progressCardH)
        conquestCard:ClearAllPoints()
        conquestCard:SetPoint("TOPLEFT", SIDE + (triW + triGap) * 2, -yOffset)
        conquestCard:SetWidth(triW)
        conquestCard:SetHeight(progressCardH)
        EnsureCardTitle(bundle, "conquestTitle", conquestCard, (L and L["PVP_CONQUEST"]) or "Conquest")
        local conqLabel = (L and L["PVP_CONQUEST"]) or "Conquest"
        if conqCur and conqCur.canEarnPerWeek and (conqCur.weeklyMax or 0) > 0 then
            conqLabel = conqLabel .. "  " .. muted .. ((L and L["PVP_WEEKLY_CAP"]) or "Weekly cap") .. "|r"
            EnsureBarRow(bundle, "conqBarRow", conquestCard, barY,
                conqLabel, conqCur.weeklyEarned or 0, conqCur.weeklyMax or 0, accentColor)
        elseif conqCur and conqCur.useTotalEarnedForMaxQty and (conqCur.maxQuantity or 0) > 0 then
            conqLabel = conqLabel .. "  " .. muted .. ((L and L["PVP_SEASON_CAP"]) or "Season cap") .. "|r"
            EnsureBarRow(bundle, "conqBarRow", conquestCard, barY,
                conqLabel, conqCur.totalEarned or 0, conqCur.maxQuantity or 0, accentColor)
        else
            -- Season ended / no cap: progress bar track + quantity / infinity max.
            EnsureBarRow(bundle, "conqBarRow", conquestCard, barY,
                conqLabel, (conqCur and conqCur.quantity) or 0, 0, accentColor, { uncapped = true })
        end

        yOffset = yOffset + progressCardH + SECTION_GAP
    end

    -- Row 2: Rated brackets — one card per mode (2v2, 3v3, RBG, Shuffle, Blitz)
    do
        if bundle.ratedCard then
            bundle.ratedCard:Hide()
        end

        local ratedBrackets = (ns.PvPService and ns.PvPService.RATED_BRACKETS) or {}
        local bracketCount = #ratedBrackets
        if bracketCount > 0 then
            local sectionFrame = bundle.ratedSectionFrame
            if not sectionFrame then
                sectionFrame = (ns.UI.Factory and ns.UI.Factory:CreateContainer(parent, width, HEADER_BLOCK_H, false))
                    or EnsureCard(bundle, "ratedSectionFrame", parent, HEADER_BLOCK_H)
                sectionFrame._wnKeepOnTabSwitch = true
                bundle.ratedSectionFrame = sectionFrame
                bundle.ratedSectionTitle = FontManager:CreateFontString(sectionFrame, "title", "OVERLAY")
            else
                sectionFrame:SetParent(parent)
                sectionFrame:Show()
            end
            sectionFrame:ClearAllPoints()
            sectionFrame:SetPoint("TOPLEFT", SIDE, -yOffset)
            sectionFrame:SetPoint("TOPRIGHT", -SIDE, -yOffset)
            sectionFrame:SetHeight(HEADER_BLOCK_H)

            local sectionFs = bundle.ratedSectionTitle
            sectionFs:ClearAllPoints()
            sectionFs:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 0, 0)
            sectionFs:SetText((L and L["PVP_RATED_BRACKETS"]) or "Rated Brackets")
            ns.UI_SetTextColorRole(sectionFs, "Bright")
            sectionFs:Show()
            yOffset = yOffset + HEADER_BLOCK_H

            local availW = width - SIDE * 2
            local gap = CARD_GAP
            local cardW = math.max(RATED_CARD_MIN_W, math.floor((availW - gap * (bracketCount - 1)) / bracketCount))
            local cardH = CARD_PAD + HEADER_BLOCK_H + RATED_CARD_STAT_H * 4 + CARD_PAD
            local ratingLabel = (L and L["PVP_RATING"]) or "Rating"
            local seasonLabel = (L and L["PVP_SEASON_BEST"]) or "Season Best"
            local weeklyLabel = (L and L["PVP_WEEKLY"]) or "Weekly W/P"
            local roundsLabel = (L and L["PVP_WEEKLY_ROUNDS"]) or "Weekly Rounds"
            local winRateLabel = (L and L["PVP_WIN_RATE"]) or "Win Rate"

            for i = 1, bracketCount do
                local bdef = ratedBrackets[i]
                local bkey = bdef.key
                local row = brackets[bkey] or {}
                local card = EnsureBracketCard(bundle, bkey, parent, cardW, cardH)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", SIDE + (i - 1) * (cardW + gap), -yOffset)
                local titleFs = EnsureCardTitle(bundle, "ratedTitle_" .. bkey, card, BRACKET_LABELS[bkey] or bkey)

                -- Tier badge (Combatant/Challenger/...) on the title line.
                -- Skipped for unrated brackets (API names there are "<bracket> - Unranked" noise);
                -- clamped to one line between the title and the card edge.
                local tierFs = bundle["ratedTier_" .. bkey]
                if not tierFs then
                    tierFs = FontManager:CreateFontString(card, "small", "OVERLAY")
                    bundle["ratedTier_" .. bkey] = tierFs
                end
                tierFs:ClearAllPoints()
                tierFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(CARD_PAD + 2))
                tierFs:SetPoint("TOPLEFT", titleFs, "TOPRIGHT", 6, -2)
                tierFs:SetJustifyH("RIGHT")
                tierFs:SetWordWrap(false)
                tierFs:SetMaxLines(1)
                local tierLabel
                if (row.rating or 0) > 0 and ns.PvPService and ns.PvPService.GetTierLabel then
                    tierLabel = ns.PvPService:GetTierLabel(row.tier)
                end
                if tierLabel then
                    tierFs:SetText(muted .. tierLabel .. "|r")
                    tierFs:Show()
                else
                    tierFs:SetText("")
                    tierFs:Hide()
                end

                -- Shuffle/Blitz: prefer per-round stats when the API returned them
                local useRounds = (bkey == "shuffle" or bkey == "blitz")
                    and ((row.roundsSeasonPlayed or 0) > 0 or (row.roundsWeeklyPlayed or 0) > 0)
                local wkWon = useRounds and (row.roundsWeeklyWon or 0) or (row.weeklyWon or 0)
                local wkPlayed = useRounds and (row.roundsWeeklyPlayed or 0) or (row.weeklyPlayed or 0)
                if weeklyStaleCur then
                    wkWon, wkPlayed = 0, 0
                end
                local ssWon = useRounds and (row.roundsSeasonWon or 0) or (row.seasonWon or 0)
                local ssPlayed = useRounds and (row.roundsSeasonPlayed or 0) or (row.seasonPlayed or 0)

                local statY = CARD_PAD + HEADER_BLOCK_H
                EnsureBracketStatRow(bundle, bkey, 1, card, statY,
                    ratingLabel, bright .. tostring(row.rating or 0) .. "|r")
                statY = statY + RATED_CARD_STAT_H
                EnsureBracketStatRow(bundle, bkey, 2, card, statY,
                    seasonLabel, muted .. tostring(row.seasonBest or 0) .. "|r")
                statY = statY + RATED_CARD_STAT_H
                EnsureBracketStatRow(bundle, bkey, 3, card, statY,
                    useRounds and roundsLabel or weeklyLabel,
                    muted .. string.format("%d / %d", wkWon, wkPlayed) .. "|r")
                statY = statY + RATED_CARD_STAT_H
                local winRateText
                if ssPlayed > 0 then
                    winRateText = bright .. string.format("%d%%", math.floor(ssWon / ssPlayed * 100 + 0.5)) .. "|r"
                else
                    winRateText = muted .. "-|r"
                end
                EnsureBracketStatRow(bundle, bkey, 4, card, statY, winRateLabel, winRateText)
            end
            yOffset = yOffset + cardH + SECTION_GAP
        end
    end

    -- Row 3: Warband PvP Overview — one row per tracked character (multi-alt view)
    do
        local rosterRows, seasonNumber
        if ns.PvPService and ns.PvPService.GetWarbandOverview then
            rosterRows, seasonNumber = ns.PvPService:GetWarbandOverview()
        end
        rosterRows = rosterRows or {}
        local rosterCount = #rosterRows

        if rosterCount > 1 then
            local innerW = width - SIDE * 2 - CARD_PAD * 2
            local cols = BuildRosterColumns(innerW)
            local hdrTop = CARD_PAD + RECENT_TITLE_H + RECENT_FILTER_GAP
            local rowTop = hdrTop + ROW_H + RECENT_LIST_DIVIDER_H + 4
            local cardH = rowTop + rosterCount * ROW_H + CARD_PAD
            local card = EnsureCard(bundle, "rosterCard", parent, cardH)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", SIDE, -yOffset)
            card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
            card:SetHeight(cardH)
            EnsureCardTitle(bundle, "rosterTitle", card,
                (L and L["PVP_WARBAND_OVERVIEW"]) or "Warband PvP Overview")

            -- Season number, right-aligned on the title line
            local seasonFs = bundle.rosterSeasonFs
            if not seasonFs then
                seasonFs = FontManager:CreateFontString(card, "body", "OVERLAY")
                bundle.rosterSeasonFs = seasonFs
            end
            seasonFs:ClearAllPoints()
            seasonFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
            seasonFs:SetJustifyH("RIGHT")
            if seasonNumber then
                local fmt = (L and L["PVP_SEASON_N"]) or "Season %d"
                seasonFs:SetText(muted .. string.format(fmt, seasonNumber) .. "|r")
                seasonFs:Show()
            else
                seasonFs:SetText("")
                seasonFs:Hide()
            end

            -- Column headers
            local hdrExtra = hdrTop - CARD_PAD - HEADER_BLOCK_H
            local hdr = EnsureRowCells(bundle, "rosterHdr", 1, card, cols, hdrExtra)
            hdr[1]:SetText(muted .. ((L and L["PVP_COL_CHARACTER"]) or "Character") .. "|r")
            for bi = 1, #ROSTER_BRACKET_ORDER do
                hdr[1 + bi]:SetText(muted .. ROSTER_BRACKET_HEADERS[bi] .. "|r")
            end
            hdr[2 + #ROSTER_BRACKET_ORDER]:SetText(muted .. ((L and L["PVP_WEEKLY"]) or "Weekly W/P") .. "|r")
            EnsureListDivider(bundle, "rosterListDivider", card, hdrTop + ROW_H)

            -- Highest rating across the whole roster → gold cell (which alt is best)
            local overallBest = 0
            for i = 1, rosterCount do
                local br = rosterRows[i].bestRating or 0
                if br > overallBest then overallBest = br end
            end
            local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffd700"
            local noData = muted .. "-|r"

            local dataExtra = rowTop - CARD_PAD - HEADER_BLOCK_H
            local currentRowY
            for i = 1, rosterCount do
                local rrow = rosterRows[i]
                local cells = EnsureRowCells(bundle, "rosterRows", i, card, cols, dataExtra)

                local nameStr = tostring(rrow.name or "?")
                local realmStr = (ns.Utilities and ns.Utilities.FormatRealmName)
                    and ns.Utilities:FormatRealmName(rrow.realm) or (rrow.realm or "")
                local label = ClassColorHex(rrow.classFile) .. nameStr .. "|r"
                if realmStr ~= "" then
                    label = label .. " " .. muted .. "- " .. realmStr .. "|r"
                end
                cells[1]:SetText(label)

                local weeklyWon, weeklyPlayed = 0, 0
                local hasBrackets = type(rrow.brackets) == "table"
                for bi = 1, #ROSTER_BRACKET_ORDER do
                    local cell = cells[1 + bi]
                    local b = hasBrackets and rrow.brackets[ROSTER_BRACKET_ORDER[bi]] or nil
                    local rating = b and tonumber(b.rating) or nil
                    if rating and rating > 0 then
                        if rating == overallBest then
                            cell:SetText(goldHex .. tostring(rating) .. "|r")
                        else
                            cell:SetText(bright .. tostring(rating) .. "|r")
                        end
                    elseif b then
                        cell:SetText(muted .. "0|r")
                    else
                        cell:SetText(noData)
                    end
                    if b and not rrow.weeklyStale then
                        weeklyWon = weeklyWon + (tonumber(b.weeklyWon) or 0)
                        weeklyPlayed = weeklyPlayed + (tonumber(b.weeklyPlayed) or 0)
                    end
                end

                local weeklyCell = cells[2 + #ROSTER_BRACKET_ORDER]
                if hasBrackets then
                    weeklyCell:SetText(muted .. string.format("%d / %d", weeklyWon, weeklyPlayed) .. "|r")
                else
                    weeklyCell:SetText(noData)
                end

                if rrow.isCurrent then
                    currentRowY = CARD_PAD + HEADER_BLOCK_H + dataExtra + (i - 1) * ROW_H
                end
            end
            HideRowsFrom(bundle, "rosterRows", rosterCount + 1)
            EnsureRosterRowHighlight(bundle, card, currentRowY or 0, currentRowY ~= nil)

            yOffset = yOffset + cardH + SECTION_GAP
        elseif bundle.rosterCard then
            bundle.rosterCard:Hide()
        end
    end

    -- Row 4: Recent matches with mode filter sub-tabs
    do
        local recent = (matches and matches.recent) or {}
        local activeFilter = bundle.recentFilter or "all"
        local PvPS = ns.PvPService
        local filtered = (PvPS and PvPS.FilterRecentMatches and PvPS:FilterRecentMatches(recent, activeFilter)) or recent
        local rowsToShow = math.min(#filtered, 12)
        local innerW = width - SIDE * 2 - CARD_PAD * 2
        local recentCols = BuildRecentColumns(innerW)

        local filterDefs = (PvPS and PvPS.RECENT_FILTER_DEFS) or {}
        local subTabH = 30
        local filterTop = CARD_PAD + RECENT_TITLE_H + RECENT_FILTER_GAP
        local hdrTop = filterTop + subTabH + 8
        local rowTop = hdrTop + ROW_H + RECENT_LIST_DIVIDER_H + 4
        local cardH = rowTop + math.max(1, rowsToShow) * ROW_H + RECENT_FOOTER_H + CARD_PAD
        local card = EnsureCard(bundle, "recentCard", parent, cardH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", SIDE, -yOffset)
        card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        card:SetHeight(cardH)
        EnsureCardTitle(bundle, "recentTitle", card, (L and L["PVP_RECENT_MATCHES"]) or "Recent Matches")

        local statsFs = bundle.recentStatsFs
        if not statsFs then
            statsFs = FontManager:CreateFontString(card, "body", "OVERLAY")
            bundle.recentStatsFs = statsFs
        end
        statsFs:ClearAllPoints()
        statsFs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + 180, -CARD_PAD)
        statsFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
        statsFs:SetJustifyH("RIGHT")
        do
            local sw, sp = 0, 0
            local lw, lp = 0, 0
            if PvPS and PvPS.SumMatchScope then
                sw, sp = PvPS:SumMatchScope(matches and matches.session, activeFilter)
                lw, lp = PvPS:SumMatchScope(matches and matches.lifetime, activeFilter)
            end
            statsFs:SetText(muted
                .. ((L and L["PVP_SESSION_STATS"]) or "This Session") .. ": |r" .. bright .. sw .. "/" .. sp .. "|r"
                .. muted .. "  |  " .. ((L and L["PVP_LIFETIME_STATS"]) or "Lifetime") .. ": |r" .. bright .. lw .. "/" .. lp .. "|r")
        end
        statsFs:Show()

        local subBar = bundle.recentSubBar
        if subBar and (
            (bundle.recentSubBarInnerW and bundle.recentSubBarInnerW ~= innerW)
            or bundle.recentSubBarLayoutKey ~= RECENT_SUBBAR_LAYOUT_KEY
        ) then
            subBar:Hide()
            subBar = nil
            bundle.recentSubBar = nil
        end
        if not subBar and ns.UI_CreateSubTabBar then
            local tabs = {}
            for i = 1, #filterDefs do
                local key = filterDefs[i].key
                tabs[i] = { key = key, label = RecentFilterLabel(key), hideIcon = true }
            end
            subBar = ns.UI_CreateSubTabBar(card, {
                tabs = tabs,
                activeKey = activeFilter,
                maxWidth = innerW,
                wrapRows = true,
                accent = accentColor,
                btnHeight = RECENT_FILTER_BTN_H,
                btnSpacing = RECENT_FILTER_BTN_GAP,
                iconLeft = RECENT_FILTER_PAD_H,
                textRight = RECENT_FILTER_PAD_H,
                activeBarInset = 4,
                activeBarBottom = 2,
                onSelect = function(key)
                    bundle.recentFilter = key
                    WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                        tab = "pvp",
                        skipCooldown = true,
                    })
                end,
            })
            bundle.recentSubBar = subBar
            bundle.recentSubBarInnerW = innerW
            bundle.recentSubBarLayoutKey = RECENT_SUBBAR_LAYOUT_KEY
        end
        if subBar then
            subBar:SetParent(card)
            subBar:ClearAllPoints()
            subBar:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -filterTop)
            subBar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -filterTop)
            subTabH = subBar:GetHeight() or subTabH
            hdrTop = filterTop + subTabH + 8
            rowTop = hdrTop + ROW_H + RECENT_LIST_DIVIDER_H + 4
            if subBar.SetActiveTab then
                subBar:SetActiveTab(activeFilter)
            end
            subBar:Show()
        end

        local colResult = (L and L["PVP_COL_RESULT"]) or "Result"
        local colMode = (L and L["PVP_COL_MODE"]) or "Mode"
        local colDelta = (L and L["PVP_COL_DELTA"]) or "+/-"
        local colDuration = (L and L["PVP_COL_DURATION"]) or "Time"
        local colMap = (L and L["PVP_COL_MAP"]) or "Map"
        local colAgo = (L and L["PVP_COL_AGO"]) or "When"
        local rowExtra = hdrTop - CARD_PAD - HEADER_BLOCK_H
        local hdr = EnsureRowCells(bundle, "recentHdr", 1, card, recentCols, rowExtra)
        hdr[1]:SetText(muted .. colResult .. "|r")
        hdr[2]:SetText(muted .. colMode .. "|r")
        hdr[3]:SetText(muted .. colDelta .. "|r")
        hdr[4]:SetText(muted .. colDuration .. "|r")
        hdr[5]:SetText(muted .. colMap .. "|r")
        hdr[6]:SetText(muted .. colAgo .. "|r")
        EnsureListDivider(bundle, "recentListDivider", card, hdrTop + ROW_H)

        local dataExtra = rowTop - CARD_PAD - HEADER_BLOCK_H
        for i = 1, rowsToShow do
            local m = filtered[i]
            local cells = EnsureRowCells(bundle, "recentRows", i, card, recentCols, dataExtra)
            local rowY = CARD_PAD + HEADER_BLOCK_H + dataExtra + (i - 1) * ROW_H
            local hit = EnsureRecentHitFrame(bundle, i, card, rowY, innerW)
            if hit then
                hit._wnMatch = MatchHasTooltipData(m) and m or nil
            end
            cells[1]:SetText(OutcomeMarkup(m.outcome))
            cells[2]:SetText(BRACKET_LABELS[m.mode] or m.mode or "?")
            ns.UI_SetTextColorRole(cells[2], "Normal")
            if m.ratingChange and m.ratingChange ~= 0 then
                local sign = m.ratingChange > 0 and "+" or ""
                local hex = m.ratingChange > 0
                    and ((ns.UI_GetSemanticGreenHex and ns.UI_GetSemanticGreenHex()) or "|cff33cc55")
                    or "|cffcc4433"
                cells[3]:SetText(hex .. sign .. tostring(m.ratingChange) .. "|r")
            else
                cells[3]:SetText("")
            end
            cells[4]:SetText(muted .. FormatDuration(m.duration) .. "|r")
            cells[5]:SetText(muted .. (m.mapName or "") .. "|r")
            cells[6]:SetText(muted .. FormatTimeAgo(m.endedAt) .. "|r")
        end
        if rowsToShow == 0 then
            local cells = EnsureRowCells(bundle, "recentRows", 1, card, recentCols, dataExtra)
            cells[1]:SetWidth(math.min(400, innerW))
            cells[1]:SetText(muted .. ((L and L["PVP_NO_MATCHES"]) or "No recorded matches yet") .. "|r")
            for c = 2, #cells do cells[c]:SetText("") end
            HideRowsFrom(bundle, "recentRows", 2)
            HideRecentHitsFrom(bundle, 1)
        else
            HideRowsFrom(bundle, "recentRows", rowsToShow + 1)
            HideRecentHitsFrom(bundle, rowsToShow + 1)
        end

        local resetBtn = bundle.resetBtn
        if not resetBtn then
            resetBtn = ns.UI_CreateThemedButton(card, (L and L["PVP_RESET_HISTORY"]) or "Reset Statistics", 150)
            resetBtn:SetScript("OnClick", function()
                if ns.PvPService then
                    ns.PvPService:ResetMatchStats(nil, "all")
                end
            end)
            bundle.resetBtn = resetBtn
        end
        resetBtn:SetParent(card)
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, CARD_PAD)
        resetBtn:Show()

        cardH = rowTop + math.max(1, rowsToShow) * ROW_H + RECENT_FOOTER_H + CARD_PAD
        card:SetHeight(cardH)
        yOffset = yOffset + cardH + SECTION_GAP
    end

    -- Row 5: Active Brawl (live read, logged-in character only; hidden when not queueable)
    do
        local brawl = ns.PvPService and ns.PvPService.GetActiveBrawl and ns.PvPService:GetActiveBrawl()
        if brawl then
            local descH = brawl.shortDescription and 18 or 0
            local cardH = CARD_PAD + RECENT_TITLE_H + 4 + 18 + descH + CARD_PAD
            local card = EnsureCard(bundle, "brawlCard", parent, cardH)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", SIDE, -yOffset)
            card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
            card:SetHeight(cardH)
            EnsureCardTitle(bundle, "brawlTitle", card, (L and L["PVP_BRAWL_TITLE"]) or "Weekly Brawl")

            local timeFs = bundle.brawlTimeFs
            if not timeFs then
                timeFs = FontManager:CreateFontString(card, "body", "OVERLAY")
                bundle.brawlTimeFs = timeFs
            end
            timeFs:ClearAllPoints()
            timeFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
            timeFs:SetJustifyH("RIGHT")
            local left = FormatTimeLeft(brawl.timeLeft)
            if left then
                local fmt = (L and L["PVP_BRAWL_TIME_LEFT"]) or "Changes in %s"
                timeFs:SetText(muted .. string.format(fmt, left) .. "|r")
                timeFs:Show()
            else
                timeFs:SetText("")
                timeFs:Hide()
            end

            local nameFs = bundle.brawlNameFs
            if not nameFs then
                nameFs = FontManager:CreateFontString(card, "body", "OVERLAY")
                bundle.brawlNameFs = nameFs
            end
            nameFs:ClearAllPoints()
            nameFs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(CARD_PAD + RECENT_TITLE_H + 4))
            nameFs:SetText(bright .. brawl.name .. "|r")
            nameFs:Show()

            local descFs = bundle.brawlDescFs
            if not descFs then
                descFs = FontManager:CreateFontString(card, "small", "OVERLAY")
                bundle.brawlDescFs = descFs
            end
            descFs:ClearAllPoints()
            descFs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(CARD_PAD + RECENT_TITLE_H + 4 + 18))
            descFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(CARD_PAD + RECENT_TITLE_H + 4 + 18))
            descFs:SetJustifyH("LEFT")
            if brawl.shortDescription then
                descFs:SetText(muted .. brawl.shortDescription .. "|r")
                descFs:Show()
            else
                descFs:SetText("")
                descFs:Hide()
            end

            yOffset = yOffset + cardH + SECTION_GAP
        elseif bundle.brawlCard then
            bundle.brawlCard:Hide()
        end
    end

    return yOffset + 20
end

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
