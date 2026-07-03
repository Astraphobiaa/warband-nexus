--[[
    Warband Nexus - PvP Tab
    Card layout: PvP level progress | Conquest & Honor caps, rated brackets
    table, and a mode-filtered recent match log.
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

-- Recent-match filter sub-tabs. matches(m) decides membership per tab.
local RECENT_FILTERS = {
    { key = "all", label = (ALL) or "All", matches = function() return true end },
    { key = "shuffle", label = BRACKET_LABELS.shuffle, matches = function(m) return m.mode == "shuffle" end },
    { key = "blitz", label = BRACKET_LABELS.blitz, matches = function(m) return m.mode == "blitz" end },
    { key = "2v2", label = "2v2", matches = function(m) return m.mode == "2v2" end },
    { key = "3v3", label = "3v3", matches = function(m) return m.mode == "3v3" end },
    { key = "bg", label = BRACKET_LABELS.bg, matches = function(m) return m.mode == "bg" or m.mode == "rbg" end },
}

local RATED_COLS = {
    { x = 0,   w = 150, justify = "LEFT" },
    { x = 160, w = 90,  justify = "RIGHT" },
    { x = 270, w = 110, justify = "RIGHT" },
    { x = 400, w = 110, justify = "RIGHT" },
}
local RECENT_COLS = {
    { x = 0,   w = 90,  justify = "LEFT" },
    { x = 100, w = 120, justify = "LEFT" },
    { x = 230, w = 60,  justify = "RIGHT" },
    { x = 300, w = 60,  justify = "RIGHT" },
    { x = 380, w = 260, justify = "LEFT" },
    { x = 650, w = 70,  justify = "LEFT" },
}

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
local function EnsureBarRow(bundle, key, card, y, labelText, cur, maxV, barColor)
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
    if maxV and maxV > 0 then
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
        if maxV and maxV > 0 then
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

function WarbandNexus:DrawPvPTab(parent)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local SIDE = (metrics and metrics.sideMargin) or 16
    local width = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local halfW = math.max(220, math.floor((width - CARD_GAP) / 2))

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
    local muted = MutedHex()
    local bright = BrightHex()
    local goldColor = (ns.UI_GetSemanticGoldColor and { ns.UI_GetSemanticGoldColor() }) or { 1, 0.82, 0.2 }
    local accentColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] }

    -- Row 1: PvP Level Progress | Conquest & Honor caps
    do
        local rowCardH = CARD_PAD + HEADER_BLOCK_H + (20 + BAR_H) * 2 + 12 + CARD_PAD

        -- Card A: honor level progress
        local cardA = EnsureCard(bundle, "levelCard", parent, rowCardH)
        cardA:ClearAllPoints()
        cardA:SetPoint("TOPLEFT", SIDE, -yOffset)
        cardA:SetWidth(halfW)
        cardA:SetHeight(rowCardH)
        EnsureCardTitle(bundle, "levelTitle", cardA, (L and L["PVP_LEVEL_PROGRESS"]) or "PvP Level Progress")
        local lvlFmt = (L and L["PVP_HONOR_LEVEL"]) or "Honor Level %d"
        EnsureBarRow(bundle, "levelBarRow", cardA, CARD_PAD + HEADER_BLOCK_H,
            string.format(lvlFmt, honor.level or 0), honor.current or 0, honor.max or 0, goldColor)

        -- Card B: Conquest weekly cap + Honor cap
        local cardB = EnsureCard(bundle, "capsCard", parent, rowCardH)
        cardB:ClearAllPoints()
        cardB:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        cardB:SetWidth(halfW)
        cardB:SetHeight(rowCardH)
        EnsureCardTitle(bundle, "capsTitle", cardB,
            ((L and L["PVP_CONQUEST"]) or "Conquest") .. " / " .. ((HONOR) or "Honor"))

        local by = CARD_PAD + HEADER_BLOCK_H
        local conqLabel = (L and L["PVP_CONQUEST"]) or "Conquest"
        if conqCur and conqCur.canEarnPerWeek and (conqCur.weeklyMax or 0) > 0 then
            conqLabel = conqLabel .. "  " .. muted .. ((L and L["PVP_WEEKLY_CAP"]) or "Weekly cap") .. "|r"
            EnsureBarRow(bundle, "conqBarRow", cardB, by,
                conqLabel, conqCur.weeklyEarned or 0, conqCur.weeklyMax or 0, accentColor)
        elseif conqCur and conqCur.useTotalEarnedForMaxQty and (conqCur.maxQuantity or 0) > 0 then
            conqLabel = conqLabel .. "  " .. muted .. ((L and L["PVP_SEASON_CAP"]) or "Season cap") .. "|r"
            EnsureBarRow(bundle, "conqBarRow", cardB, by,
                conqLabel, conqCur.totalEarned or 0, conqCur.maxQuantity or 0, accentColor)
        else
            EnsureBarRow(bundle, "conqBarRow", cardB, by,
                conqLabel, (conqCur and conqCur.quantity) or 0, 0, accentColor)
        end

        by = by + 20 + BAR_H + 12
        EnsureBarRow(bundle, "honorBarRow", cardB, by,
            (HONOR) or "Honor", (honorCur and honorCur.quantity) or 0,
            (honorCur and honorCur.maxQuantity) or 0, goldColor)

        yOffset = yOffset + rowCardH + SECTION_GAP
    end

    -- Row 2: Rated brackets table
    do
        local ratedBrackets = (ns.PvPService and ns.PvPService.RATED_BRACKETS) or {}
        local cardH = CARD_PAD + HEADER_BLOCK_H + (#ratedBrackets + 1) * ROW_H + CARD_PAD
        local card = EnsureCard(bundle, "ratedCard", parent, cardH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", SIDE, -yOffset)
        card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        card:SetHeight(cardH)
        EnsureCardTitle(bundle, "ratedTitle", card, (L and L["PVP_RATED_BRACKETS"]) or "Rated Brackets")

        local hdr = EnsureRowCells(bundle, "ratedRows", 1, card, RATED_COLS)
        hdr[1]:SetText("")
        hdr[2]:SetText(muted .. ((L and L["PVP_RATING"]) or "Rating") .. "|r")
        hdr[3]:SetText(muted .. ((L and L["PVP_SEASON_BEST"]) or "Season Best") .. "|r")
        hdr[4]:SetText(muted .. ((L and L["PVP_WEEKLY"]) or "Weekly W/P") .. "|r")

        for i = 1, #ratedBrackets do
            local bdef = ratedBrackets[i]
            local row = brackets[bdef.key] or {}
            local cells = EnsureRowCells(bundle, "ratedRows", i + 1, card, RATED_COLS)
            cells[1]:SetText(BRACKET_LABELS[bdef.key] or bdef.key)
            ns.UI_SetTextColorRole(cells[1], "Normal")
            cells[2]:SetText(bright .. tostring(row.rating or 0) .. "|r")
            cells[3]:SetText(muted .. tostring(row.seasonBest or 0) .. "|r")
            cells[4]:SetText(muted .. string.format("%d / %d", row.weeklyWon or 0, row.weeklyPlayed or 0) .. "|r")
        end
        HideRowsFrom(bundle, "ratedRows", #ratedBrackets + 2)
        yOffset = yOffset + cardH + SECTION_GAP
    end

    -- Row 3: Recent matches with mode filter sub-tabs
    do
        local recent = (matches and matches.recent) or {}
        local activeFilter = bundle.recentFilter or "all"
        local filterDef
        for i = 1, #RECENT_FILTERS do
            if RECENT_FILTERS[i].key == activeFilter then
                filterDef = RECENT_FILTERS[i]
                break
            end
        end
        filterDef = filterDef or RECENT_FILTERS[1]

        local filtered = {}
        for i = 1, #recent do
            local m = recent[i]
            if m and filterDef.matches(m) then
                filtered[#filtered + 1] = m
            end
        end
        local rowsToShow = math.min(#filtered, 12)

        local subTabH = 30
        local buttonStripH = 34
        local cardH = CARD_PAD + HEADER_BLOCK_H + subTabH + 8
            + math.max(1, rowsToShow) * ROW_H + buttonStripH + CARD_PAD
        local card = EnsureCard(bundle, "recentCard", parent, cardH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", SIDE, -yOffset)
        card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        card:SetHeight(cardH)
        EnsureCardTitle(bundle, "recentTitle", card, (L and L["PVP_RECENT_MATCHES"]) or "Recent Matches")

        -- Session / lifetime aggregate for the selected filter, shown next to the title.
        local statsFs = bundle.recentStatsFs
        if not statsFs then
            statsFs = FontManager:CreateFontString(card, "body", "OVERLAY")
            bundle.recentStatsFs = statsFs
        end
        statsFs:ClearAllPoints()
        statsFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -CARD_PAD)
        statsFs:SetJustifyH("RIGHT")
        do
            local function sumScope(bucket)
                local played, won = 0, 0
                if bucket then
                    for modeKey, agg in pairs(bucket) do
                        local probe = { mode = modeKey }
                        if filterDef.matches(probe) or activeFilter == "all" then
                            played = played + (agg.played or 0)
                            won = won + (agg.won or 0)
                        end
                    end
                end
                return won, played
            end
            local sw, sp = sumScope(matches and matches.session)
            local lw, lp = sumScope(matches and matches.lifetime)
            statsFs:SetText(muted
                .. ((L and L["PVP_SESSION_STATS"]) or "This Session") .. ": |r" .. bright .. sw .. "/" .. sp .. "|r"
                .. muted .. "   " .. ((L and L["PVP_LIFETIME_STATS"]) or "Lifetime") .. ": |r" .. bright .. lw .. "/" .. lp .. "|r")
        end
        statsFs:Show()

        -- Sub-tab bar (created once; active state synced per draw)
        local subBar = bundle.recentSubBar
        if not subBar and ns.UI_CreateSubTabBar then
            local tabs = {}
            for i = 1, #RECENT_FILTERS do
                tabs[i] = { key = RECENT_FILTERS[i].key, label = RECENT_FILTERS[i].label }
            end
            subBar = ns.UI_CreateSubTabBar(card, {
                tabs = tabs,
                activeKey = activeFilter,
                onSelect = function(key)
                    bundle.recentFilter = key
                    WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                        tab = "pvp",
                        skipCooldown = true,
                    })
                end,
            })
            bundle.recentSubBar = subBar
        end
        if subBar then
            subBar:SetParent(card)
            subBar:ClearAllPoints()
            subBar:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(CARD_PAD + HEADER_BLOCK_H))
            subBar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(CARD_PAD + HEADER_BLOCK_H))
            if subBar.SetActiveTab then
                subBar:SetActiveTab(activeFilter)
            end
            subBar:Show()
        end

        local listTop = subTabH + 8
        for i = 1, rowsToShow do
            local m = filtered[i]
            local cells = EnsureRowCells(bundle, "recentRows", i, card, RECENT_COLS, listTop)
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
            local cells = EnsureRowCells(bundle, "recentRows", 1, card, RECENT_COLS, listTop)
            cells[1]:SetWidth(400)
            cells[1]:SetText(muted .. ((L and L["PVP_NO_MATCHES"]) or "No recorded matches yet") .. "|r")
            for c = 2, #cells do cells[c]:SetText("") end
            HideRowsFrom(bundle, "recentRows", 2)
        else
            HideRowsFrom(bundle, "recentRows", rowsToShow + 1)
        end

        -- Reset button (bottom-right of the log card)
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
        resetBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -CARD_PAD, 8)
        resetBtn:Show()

        yOffset = yOffset + cardH + SECTION_GAP
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
