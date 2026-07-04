--[[
    Warband Nexus - PvP Tab (Draw)
    Loaded via WarbandNexus.toc after PvPUI.lua.
    Split from PvPUI.lua to stay under Lua 5.1 60-upvalue limit per function.
]]

local _, ns = ...
local M = ns.PvPUI
assert(M, "PvPUI.lua must load before PvPUI_Draw.lua")

function M.DrawTab(parent)
    local mf = M.WarbandNexus.UI and M.WarbandNexus.UI.mainFrame
    local metrics = M.ns.UI_GetMainTabLayoutMetrics and M.ns.UI_GetMainTabLayoutMetrics(mf)
    local SIDE = (metrics and metrics.sideMargin) or 16
    local width = (metrics and metrics.contentWidth)
        or (M.ns.UI_ResolveMainTabContentWidth and M.ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)

    local chrome = M.ns.UI_BeginTabChromeLayout and M.ns.UI_BeginTabChromeLayout(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or (metrics and metrics.topMargin) or 12

    local bundle = parent._wnPvPBundle
    if not bundle then
        bundle = {}
        parent._wnPvPBundle = bundle
    end

    -- Title card
    local r, g, b = M.COLORS.accent[1], M.COLORS.accent[2], M.COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleCard = bundle.titleCard
    if not titleCard then
        titleCard = select(1, M.ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "pvp",
            titleText = "|cff" .. hexColor .. ((M.L and M.L["TAB_PVP"]) or "PvP") .. "|r",
            subtitleText = (M.L and M.L["PVP_SUBTITLE"]) or "Rated progress, honor, and match history",
            showUnderline = false,
        }))
        bundle.titleCard = titleCard
    end
    titleCard:SetParent(headerParent)
    if chrome and M.ns.UI_AnchorTabTitleCard then
        M.ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", SIDE, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -SIDE, -headerYOffset)
    end
    titleCard:Show()
    if M.ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = M.ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        if M.ns.UI_CommitTabFixedHeader then M.ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    elseif fixedHeader then
        headerYOffset = headerYOffset + (titleCard:GetHeight() or 64) + 8
        fixedHeader:SetHeight(headerYOffset)
    end

    local yOffset = (M.ns.UI_GetTabScrollContentStartY and M.ns.UI_GetTabScrollContentStartY()) or 8

    local progress, matches
    if M.ns.PvPService then
        progress, matches = M.ns.PvPService:GetSummary()
    end
    local honorCur, conqCur
    if M.ns.PvPService and M.ns.PvPService.GetCurrencyOverview then
        honorCur, conqCur = M.ns.PvPService:GetCurrencyOverview()
    end
    local brackets = (progress and progress.brackets) or {}
    local honor = (progress and progress.honor) or {}
    -- Snapshot taken before this week's reset → weekly W/P values display as 0
    local weeklyStaleCur = M.ns.PvPService and M.ns.PvPService.IsRatedWeeklyStale
        and M.ns.PvPService:IsRatedWeeklyStale(progress) or false
    local muted = M.MutedHex()
    local bright = M.BrightHex()
    local goldColor = (M.ns.UI_GetSemanticGoldColor and { M.ns.UI_GetSemanticGoldColor() }) or { 1, 0.82, 0.2 }
    local accentColor = { M.COLORS.accent[1], M.COLORS.accent[2], M.COLORS.accent[3] }

    -- Row 1: PvP Level Progress | Honor | Conquest (three equal cards)
    do
        if bundle.capsCard then
            bundle.capsCard:Hide()
        end

        local progressCardH = M.CARD_PAD + M.HEADER_BLOCK_H + 20 + M.BAR_H + M.CARD_PAD
        local availW = width - SIDE * 2
        local triGap = M.CARD_GAP
        local triW = math.max(M.PROGRESS_CARD_MIN_W, math.floor((availW - triGap * 2) / 3))
        local barY = M.CARD_PAD + M.HEADER_BLOCK_H
        local lvlFmt = (M.L and M.L["PVP_HONOR_LEVEL"]) or "Honor Level %d"

        local levelCard = M.EnsureCard(bundle, "levelCard", parent, progressCardH)
        levelCard:ClearAllPoints()
        levelCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        levelCard:SetWidth(triW)
        levelCard:SetHeight(progressCardH)
        M.EnsureCardTitle(bundle, "levelTitle", levelCard, (M.L and M.L["PVP_LEVEL_PROGRESS"]) or "PvP Level Progress")
        M.EnsureBarRow(bundle, "levelBarRow", levelCard, barY,
            string.format(lvlFmt, honor.level or 0), honor.current or 0, honor.max or 0, goldColor)

        local honorCard = M.EnsureCard(bundle, "honorCard", parent, progressCardH)
        honorCard:ClearAllPoints()
        honorCard:SetPoint("TOPLEFT", SIDE + triW + triGap, -yOffset)
        honorCard:SetWidth(triW)
        honorCard:SetHeight(progressCardH)
        M.EnsureCardTitle(bundle, "honorTitle", honorCard, (HONOR) or "Honor")
        M.EnsureBarRow(bundle, "honorBarRow", honorCard, barY,
            (HONOR) or "Honor", (honorCur and honorCur.quantity) or 0,
            (honorCur and honorCur.maxQuantity) or 0, goldColor)

        local conquestCard = M.EnsureCard(bundle, "conquestCard", parent, progressCardH)
        conquestCard:ClearAllPoints()
        conquestCard:SetPoint("TOPLEFT", SIDE + (triW + triGap) * 2, -yOffset)
        conquestCard:SetWidth(triW)
        conquestCard:SetHeight(progressCardH)
        M.EnsureCardTitle(bundle, "conquestTitle", conquestCard, (M.L and M.L["PVP_CONQUEST"]) or "Conquest")
        local conqLabel = (M.L and M.L["PVP_CONQUEST"]) or "Conquest"
        if conqCur and conqCur.canEarnPerWeek and (conqCur.weeklyMax or 0) > 0 then
            conqLabel = conqLabel .. "  " .. muted .. ((M.L and M.L["PVP_WEEKLY_CAP"]) or "Weekly cap") .. "|r"
            M.EnsureBarRow(bundle, "conqBarRow", conquestCard, barY,
                conqLabel, conqCur.weeklyEarned or 0, conqCur.weeklyMax or 0, accentColor)
        elseif conqCur and conqCur.useTotalEarnedForMaxQty and (conqCur.maxQuantity or 0) > 0 then
            conqLabel = conqLabel .. "  " .. muted .. ((M.L and M.L["PVP_SEASON_CAP"]) or "Season cap") .. "|r"
            M.EnsureBarRow(bundle, "conqBarRow", conquestCard, barY,
                conqLabel, conqCur.totalEarned or 0, conqCur.maxQuantity or 0, accentColor)
        else
            -- Season ended / no cap: progress bar track + quantity / infinity max.
            M.EnsureBarRow(bundle, "conqBarRow", conquestCard, barY,
                conqLabel, (conqCur and conqCur.quantity) or 0, 0, accentColor, { uncapped = true })
        end

        yOffset = yOffset + progressCardH + M.SECTION_GAP
    end

    -- Row 2: Rated brackets — one card per mode (2v2, 3v3, RBG, Shuffle, Blitz)
    do
        if bundle.ratedCard then
            bundle.ratedCard:Hide()
        end

        local ratedBrackets = (M.ns.PvPService and M.ns.PvPService.RATED_BRACKETS) or {}
        local bracketCount = #ratedBrackets
        if bracketCount > 0 then
            local sectionFrame = bundle.ratedSectionFrame
            if not sectionFrame then
                sectionFrame = (M.ns.UI.Factory and M.ns.UI.Factory:CreateContainer(parent, width, M.HEADER_BLOCK_H, false))
                    or M.EnsureCard(bundle, "ratedSectionFrame", parent, M.HEADER_BLOCK_H)
                sectionFrame._wnKeepOnTabSwitch = true
                bundle.ratedSectionFrame = sectionFrame
                bundle.ratedSectionTitle = M.FontManager:CreateFontString(sectionFrame, "title", "OVERLAY")
            else
                sectionFrame:SetParent(parent)
                sectionFrame:Show()
            end
            sectionFrame:ClearAllPoints()
            sectionFrame:SetPoint("TOPLEFT", SIDE, -yOffset)
            sectionFrame:SetPoint("TOPRIGHT", -SIDE, -yOffset)
            sectionFrame:SetHeight(M.HEADER_BLOCK_H)

            local sectionFs = bundle.ratedSectionTitle
            sectionFs:ClearAllPoints()
            sectionFs:SetPoint("TOPLEFT", sectionFrame, "TOPLEFT", 0, 0)
            sectionFs:SetText((M.L and M.L["PVP_RATED_BRACKETS"]) or "Rated Brackets")
            M.ns.UI_SetTextColorRole(sectionFs, "Bright")
            sectionFs:Show()
            yOffset = yOffset + M.HEADER_BLOCK_H

            local availW = width - SIDE * 2
            local gap = M.CARD_GAP
            local cardW = math.max(M.RATED_CARD_MIN_W, math.floor((availW - gap * (bracketCount - 1)) / bracketCount))
            local cardH = M.CARD_PAD + M.HEADER_BLOCK_H + M.RATED_CARD_STAT_H * 4 + M.CARD_PAD
            local ratingLabel = (M.L and M.L["PVP_RATING"]) or "Rating"
            local seasonLabel = (M.L and M.L["PVP_SEASON_BEST"]) or "Season Best"
            local weeklyLabel = (M.L and M.L["PVP_WEEKLY"]) or "Weekly W/P"
            local roundsLabel = (M.L and M.L["PVP_WEEKLY_ROUNDS"]) or "Weekly Rounds"
            local winRateLabel = (M.L and M.L["PVP_WIN_RATE"]) or "Win Rate"

            for i = 1, bracketCount do
                local bdef = ratedBrackets[i]
                local bkey = bdef.key
                local row = brackets[bkey] or {}
                local card = M.EnsureBracketCard(bundle, bkey, parent, cardW, cardH)
                card:ClearAllPoints()
                card:SetPoint("TOPLEFT", SIDE + (i - 1) * (cardW + gap), -yOffset)
                local titleFs = M.EnsureCardTitle(bundle, "ratedTitle_" .. bkey, card, M.BRACKET_LABELS[bkey] or bkey)

                -- Tier badge (Combatant/Challenger/...) on the title line.
                -- Skipped for unrated brackets (API names there are "<bracket> - Unranked" noise);
                -- clamped to one line between the title and the card edge.
                local tierFs = bundle["ratedTier_" .. bkey]
                if not tierFs then
                    tierFs = M.FontManager:CreateFontString(card, "small", "OVERLAY")
                    bundle["ratedTier_" .. bkey] = tierFs
                end
                tierFs:ClearAllPoints()
                tierFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CARD_PAD, -(M.CARD_PAD + 2))
                tierFs:SetPoint("TOPLEFT", titleFs, "TOPRIGHT", 6, -2)
                tierFs:SetJustifyH("RIGHT")
                tierFs:SetWordWrap(false)
                tierFs:SetMaxLines(1)
                local tierLabel
                if (row.rating or 0) > 0 and M.ns.PvPService and M.ns.PvPService.GetTierLabel then
                    tierLabel = M.ns.PvPService:GetTierLabel(row.tier)
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

                local statY = M.CARD_PAD + M.HEADER_BLOCK_H
                M.EnsureBracketStatRow(bundle, bkey, 1, card, statY,
                    ratingLabel, bright .. tostring(row.rating or 0) .. "|r")
                statY = statY + M.RATED_CARD_STAT_H
                M.EnsureBracketStatRow(bundle, bkey, 2, card, statY,
                    seasonLabel, muted .. tostring(row.seasonBest or 0) .. "|r")
                statY = statY + M.RATED_CARD_STAT_H
                M.EnsureBracketStatRow(bundle, bkey, 3, card, statY,
                    useRounds and roundsLabel or weeklyLabel,
                    muted .. string.format("%d / %d", wkWon, wkPlayed) .. "|r")
                statY = statY + M.RATED_CARD_STAT_H
                local winRateText
                if ssPlayed > 0 then
                    winRateText = bright .. string.format("%d%%", math.floor(ssWon / ssPlayed * 100 + 0.5)) .. "|r"
                else
                    winRateText = muted .. "-|r"
                end
                M.EnsureBracketStatRow(bundle, bkey, 4, card, statY, winRateLabel, winRateText)
            end
            yOffset = yOffset + cardH + M.SECTION_GAP
        end
    end

    -- Row 3: Warband PvP Overview — one row per tracked character (multi-alt view)
    do
        local rosterRows, seasonNumber
        if M.ns.PvPService and M.ns.PvPService.GetWarbandOverview then
            rosterRows, seasonNumber = M.ns.PvPService:GetWarbandOverview()
        end
        rosterRows = rosterRows or {}
        local rosterCount = #rosterRows

        if rosterCount > 1 then
            if not M.ns._pvpExpandedStates then
                M.ns._pvpExpandedStates = {}
            end
            local isRosterExpanded = M.ns._pvpExpandedStates["warbandOverview"] or false
            local hasOverflow = rosterCount > M.ROSTER_VISIBLE_ROWS
            local visibleCount = isRosterExpanded and rosterCount
                or math.min(rosterCount, M.ROSTER_VISIBLE_ROWS)
            local toggleSpace = hasOverflow and M.ROSTER_TOGGLE_H or 0

            local card = M.EnsureCard(bundle, "rosterCard", parent, 100)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", SIDE, -yOffset)
            card:SetPoint("TOPRIGHT", -SIDE, -yOffset)

            local innerW = math.max(0, (card:GetWidth() or 0) - M.CARD_PAD * 2)
            if innerW <= 0 then
                innerW = width - SIDE * 2 - M.CARD_PAD * 2
            end

            local measureFs = bundle.rosterMeasureFs
            if not measureFs then
                measureFs = M.FontManager:CreateFontString(card, "body", "OVERLAY")
                measureFs:Hide()
                bundle.rosterMeasureFs = measureFs
            else
                measureFs:SetParent(card)
            end
            local wName, wRealm, wHonor, wConquest, wWeekly, wBracket =
                M.MeasureRosterColumnWidths(measureFs, rosterRows)
            local cols = M.BuildRosterColumns(innerW, wName, wRealm, wHonor, wConquest, wWeekly, wBracket)
            local hdrRowH = M.RosterHeaderRowHeight()
            local hdrTop = M.CARD_PAD + M.RECENT_TITLE_H + M.RECENT_FILTER_GAP
            local rowTop = hdrTop + hdrRowH + M.RECENT_LIST_DIVIDER_H + 4
            local cardH = rowTop + visibleCount * M.ROW_H + M.CARD_PAD + toggleSpace
            card:SetHeight(cardH)
            M.EnsureCardTitle(bundle, "rosterTitle", card,
                (M.L and M.L["PVP_WARBAND_OVERVIEW"]) or "Warband PvP Overview")

            -- Season number, right-aligned on the title line
            local seasonFs = bundle.rosterSeasonFs
            if not seasonFs then
                seasonFs = M.FontManager:CreateFontString(card, "body", "OVERLAY")
                bundle.rosterSeasonFs = seasonFs
            end
            seasonFs:ClearAllPoints()
            seasonFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CARD_PAD, -M.CARD_PAD)
            seasonFs:SetJustifyH("RIGHT")
            if seasonNumber then
                local fmt = (M.L and M.L["PVP_SEASON_N"]) or "Season %d"
                seasonFs:SetText(muted .. string.format(fmt, seasonNumber) .. "|r")
                seasonFs:Show()
            else
                seasonFs:SetText("")
                seasonFs:Hide()
            end

            -- Column headers (Modern: icon + compact label; Classic: full text like Prof/PvE)
            local hdrExtra = hdrTop - M.CARD_PAD - M.HEADER_BLOCK_H
            local hdr = M.EnsureRosterRowCells(bundle, "rosterHdr", 1, card, cols, hdrExtra)
            hdr[1]:SetText(muted .. ((M.L and M.L["PVP_COL_CHARACTER"]) or "Character") .. "|r")
            hdr[2]:SetText(muted .. M.RosterRealmHeaderLabel() .. "|r")
            if M.RosterUseModernHeaders() then
                hdr[3]:SetText("")
                hdr[4]:SetText("")
                for bi = 1, #M.ROSTER_BRACKET_ORDER do
                    hdr[4 + bi]:SetText("")
                end
                hdr[M.RosterWeeklyColIndex()]:SetText("")
                M.PaintRosterColumnHeaders(bundle, card, cols, hdrExtra, muted)
            else
                M.HideRosterModernHeaders(bundle)
                hdr[3]:SetText(muted .. M.RosterHonorHeaderLabel() .. "|r")
                hdr[4]:SetText(muted .. M.RosterConquestHeaderLabel() .. "|r")
                for bi = 1, #M.ROSTER_BRACKET_ORDER do
                    hdr[4 + bi]:SetText(muted .. M.ROSTER_BRACKET_HEADERS[bi] .. "|r")
                end
                hdr[M.RosterWeeklyColIndex()]:SetText(muted .. ((M.L and M.L["PVP_WEEKLY"]) or "Weekly W/P") .. "|r")
            end
            M.EnsureListDivider(bundle, "rosterListDivider", card, hdrTop + hdrRowH)

            -- Highest rating across the whole roster → gold cell (which alt is best)
            local overallBest = 0
            for i = 1, rosterCount do
                local br = rosterRows[i].bestRating or 0
                if br > overallBest then overallBest = br end
            end
            local goldHex = (M.ns.UI_GetSemanticGoldHex and M.ns.UI_GetSemanticGoldHex()) or "|cffffd700"
            local noData = muted .. "-|r"

            local dataExtra = rowTop - M.CARD_PAD - M.HEADER_BLOCK_H
            local currentRowY
            for i = 1, visibleCount do
                local rrow = rosterRows[i]
                local cells = M.EnsureRosterRowCells(bundle, "rosterRows", i, card, cols, dataExtra)

                local nameStr = tostring(rrow.name or "?")
                local realmStr = (M.ns.Utilities and M.ns.Utilities.FormatRealmName)
                    and M.ns.Utilities:FormatRealmName(rrow.realm) or (rrow.realm or "")
                if issecretvalue and issecretvalue(nameStr) then
                    nameStr = "?"
                end
                if realmStr ~= "" and issecretvalue and issecretvalue(realmStr) then
                    realmStr = ""
                end
                cells[1]:SetText(M.ClassColorHex(rrow.classFile) .. nameStr .. "|r")
                if realmStr ~= "" then
                    cells[2]:SetText(muted .. realmStr .. "|r")
                else
                    cells[2]:SetText("")
                end

                local honorQty = M.RosterCurrencyQuantity(rrow.charKey, M.ROSTER_HONOR_CURRENCY_ID)
                local honorText = M.FormatRosterCurrencyQty(honorQty)
                if honorText then
                    cells[3]:SetText(bright .. honorText .. "|r")
                else
                    cells[3]:SetText(noData)
                end

                local conqQty = M.RosterCurrencyQuantity(rrow.charKey, M.ROSTER_CONQUEST_CURRENCY_ID)
                local conqText = M.FormatRosterCurrencyQty(conqQty)
                if conqText then
                    cells[4]:SetText(bright .. conqText .. "|r")
                else
                    cells[4]:SetText(noData)
                end

                local weeklyWon, weeklyPlayed = 0, 0
                local hasBrackets = type(rrow.brackets) == "table"
                for bi = 1, #M.ROSTER_BRACKET_ORDER do
                    local cell = cells[4 + bi]
                    local b = hasBrackets and rrow.brackets[M.ROSTER_BRACKET_ORDER[bi]] or nil
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

                local weeklyCell = cells[M.RosterWeeklyColIndex()]
                if hasBrackets then
                    weeklyCell:SetText(muted .. string.format("%d / %d", weeklyWon, weeklyPlayed) .. "|r")
                else
                    weeklyCell:SetText(noData)
                end

                if rrow.isCurrent then
                    currentRowY = M.CARD_PAD + M.HEADER_BLOCK_H + dataExtra + (i - 1) * M.ROW_H
                end
            end
            M.HideRowsFrom(bundle, "rosterRows", visibleCount + 1)
            M.EnsureRosterRowHighlight(bundle, card, currentRowY or 0, currentRowY ~= nil)

            if bundle.rosterMoreText then
                bundle.rosterMoreText:Hide()
            end
            if hasOverflow then
                local expandBtn = bundle.rosterExpandBtn
                if not expandBtn then
                    expandBtn = M.ns.UI.Factory:CreateButton(card, 20, 20, true)
                    expandBtn:EnableMouse(true)
                    local arrowTex = expandBtn:CreateTexture(nil, "OVERLAY")
                    arrowTex:SetAllPoints(expandBtn)
                    expandBtn._wnArrowTex = arrowTex
                    expandBtn:SetScript("OnClick", M.TogglePvPRosterExpanded)
                    bundle.rosterExpandBtn = expandBtn
                end
                expandBtn:SetParent(card)
                expandBtn:ClearAllPoints()
                expandBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -M.CARD_PAD, M.ROSTER_BOTTOM_PAD)
                if expandBtn._wnArrowTex then
                    if isRosterExpanded then
                        expandBtn._wnArrowTex:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
                    else
                        expandBtn._wnArrowTex:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
                    end
                end
                expandBtn:Show()

                if not isRosterExpanded then
                    local hiddenCount = rosterCount - M.ROSTER_VISIBLE_ROWS
                    local moreText = bundle.rosterMoreText
                    if not moreText then
                        moreText = M.FontManager:CreateFontString(card, "small", "OVERLAY")
                        bundle.rosterMoreText = moreText
                    end
                    moreText:SetParent(card)
                    moreText:ClearAllPoints()
                    moreText:SetPoint("RIGHT", expandBtn, "LEFT", -4, 0)
                    moreText:SetJustifyH("RIGHT")
                    local moreLabel = hiddenCount > 1
                        and ((M.L and M.L["MORE_CHARACTERS_PLURAL"]) or "more characters")
                        or ((M.L and M.L["MORE_CHARACTERS"]) or "more character")
                    moreText:SetText(muted .. hiddenCount .. " " .. moreLabel .. "|r")
                    moreText:Show()
                end

                card:EnableMouse(true)
                card:SetScript("OnMouseDown", function(_, button)
                    if button == "LeftButton" then
                        M.TogglePvPRosterExpanded()
                    end
                end)
            else
                if bundle.rosterExpandBtn then
                    bundle.rosterExpandBtn:Hide()
                end
                card:EnableMouse(false)
                card:SetScript("OnMouseDown", nil)
            end

            yOffset = yOffset + cardH + M.SECTION_GAP
        elseif bundle.rosterCard then
            bundle.rosterCard:Hide()
            M.HideRosterModernHeaders(bundle)
        end
    end

    -- Row 4: Recent matches with mode filter sub-tabs
    do
        local recent = (matches and matches.recent) or {}
        local activeFilter = bundle.recentFilter or "all"
        local PvPS = M.ns.PvPService
        local filtered = (PvPS and PvPS.FilterRecentMatches and PvPS:FilterRecentMatches(recent, activeFilter)) or recent
        local rowsToShow = math.min(#filtered, 12)
        local innerW = width - SIDE * 2 - M.CARD_PAD * 2
        local recentCols = M.BuildRecentColumns(innerW)

        local filterDefs = (PvPS and PvPS.RECENT_FILTER_DEFS) or {}
        local subTabH = 30
        local filterTop = M.CARD_PAD + M.RECENT_TITLE_H + M.RECENT_FILTER_GAP
        local hdrTop = filterTop + subTabH + 8
        local rowTop = hdrTop + M.ROW_H + M.RECENT_LIST_DIVIDER_H + 4
        local cardH = rowTop + math.max(1, rowsToShow) * M.ROW_H + M.RECENT_FOOTER_H + M.CARD_PAD
        local card = M.EnsureCard(bundle, "recentCard", parent, cardH)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", SIDE, -yOffset)
        card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        card:SetHeight(cardH)
        M.EnsureCardTitle(bundle, "recentTitle", card, (M.L and M.L["PVP_RECENT_MATCHES"]) or "Recent Matches")

        local statsFs = bundle.recentStatsFs
        if not statsFs then
            statsFs = M.FontManager:CreateFontString(card, "body", "OVERLAY")
            bundle.recentStatsFs = statsFs
        end
        statsFs:ClearAllPoints()
        statsFs:SetPoint("TOPLEFT", card, "TOPLEFT", M.CARD_PAD + 180, -M.CARD_PAD)
        statsFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CARD_PAD, -M.CARD_PAD)
        statsFs:SetJustifyH("RIGHT")
        do
            local sw, sp = 0, 0
            local lw, lp = 0, 0
            if PvPS and PvPS.SumMatchScope then
                sw, sp = PvPS:SumMatchScope(matches and matches.session, activeFilter)
                lw, lp = PvPS:SumMatchScope(matches and matches.lifetime, activeFilter)
            end
            statsFs:SetText(muted
                .. ((M.L and M.L["PVP_SESSION_STATS"]) or "This Session") .. ": |r" .. bright .. sw .. "/" .. sp .. "|r"
                .. muted .. "  |  " .. ((M.L and M.L["PVP_LIFETIME_STATS"]) or "Lifetime") .. ": |r" .. bright .. lw .. "/" .. lp .. "|r")
        end
        statsFs:Show()

        local subBar = bundle.recentSubBar
        if subBar and (
            (bundle.recentSubBarInnerW and bundle.recentSubBarInnerW ~= innerW)
            or bundle.recentSubBarLayoutKey ~= M.RECENT_SUBBAR_LAYOUT_KEY
        ) then
            subBar:Hide()
            subBar = nil
            bundle.recentSubBar = nil
        end
        if not subBar and M.ns.UI_CreateSubTabBar then
            local tabs = {}
            for i = 1, #filterDefs do
                local key = filterDefs[i].key
                tabs[i] = { key = key, label = M.RecentFilterLabel(key), hideIcon = true }
            end
            subBar = M.ns.UI_CreateSubTabBar(card, {
                tabs = tabs,
                activeKey = activeFilter,
                maxWidth = innerW,
                wrapRows = true,
                accent = accentColor,
                btnHeight = M.RECENT_FILTER_BTN_H,
                btnSpacing = M.RECENT_FILTER_BTN_GAP,
                iconLeft = M.RECENT_FILTER_PAD_H,
                textRight = M.RECENT_FILTER_PAD_H,
                activeBarInset = 4,
                activeBarBottom = 2,
                onSelect = function(key)
                    bundle.recentFilter = key
                    M.WarbandNexus:SendMessage(M.ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                        tab = "pvp",
                        skipCooldown = true,
                    })
                end,
            })
            bundle.recentSubBar = subBar
            bundle.recentSubBarInnerW = innerW
            bundle.recentSubBarLayoutKey = M.RECENT_SUBBAR_LAYOUT_KEY
        end
        if subBar then
            subBar:SetParent(card)
            subBar:ClearAllPoints()
            subBar:SetPoint("TOPLEFT", card, "TOPLEFT", M.CARD_PAD, -filterTop)
            subBar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CARD_PAD, -filterTop)
            subTabH = subBar:GetHeight() or subTabH
            hdrTop = filterTop + subTabH + 8
            rowTop = hdrTop + M.ROW_H + M.RECENT_LIST_DIVIDER_H + 4
            if subBar.SetActiveTab then
                subBar:SetActiveTab(activeFilter)
            end
            subBar:Show()
        end

        local colResult = (M.L and M.L["PVP_COL_RESULT"]) or "Result"
        local colMode = (M.L and M.L["PVP_COL_MODE"]) or "Mode"
        local colDelta = (M.L and M.L["PVP_COL_DELTA"]) or "+/-"
        local colDuration = (M.L and M.L["PVP_COL_DURATION"]) or "Time"
        local colMap = (M.L and M.L["PVP_COL_MAP"]) or "Map"
        local colAgo = (M.L and M.L["PVP_COL_AGO"]) or "When"
        local rowExtra = hdrTop - M.CARD_PAD - M.HEADER_BLOCK_H
        local hdr = M.EnsureRowCells(bundle, "recentHdr", 1, card, recentCols, rowExtra)
        hdr[1]:SetText(muted .. colResult .. "|r")
        hdr[2]:SetText(muted .. colMode .. "|r")
        hdr[3]:SetText(muted .. colDelta .. "|r")
        hdr[4]:SetText(muted .. colDuration .. "|r")
        hdr[5]:SetText(muted .. colMap .. "|r")
        hdr[6]:SetText(muted .. colAgo .. "|r")
        M.EnsureListDivider(bundle, "recentListDivider", card, hdrTop + M.ROW_H)

        local dataExtra = rowTop - M.CARD_PAD - M.HEADER_BLOCK_H
        for i = 1, rowsToShow do
            local m = filtered[i]
            local cells = M.EnsureRowCells(bundle, "recentRows", i, card, recentCols, dataExtra)
            local rowY = M.CARD_PAD + M.HEADER_BLOCK_H + dataExtra + (i - 1) * M.ROW_H
            local hit = M.EnsureRecentHitFrame(bundle, i, card, rowY, innerW)
            if hit then
                hit._wnMatch = M.MatchHasTooltipData(m) and m or nil
            end
            cells[1]:SetText(M.OutcomeMarkup(m.outcome))
            cells[2]:SetText(M.BRACKET_LABELS[m.mode] or m.mode or "?")
            M.ns.UI_SetTextColorRole(cells[2], "Normal")
            if m.ratingChange and m.ratingChange ~= 0 then
                local sign = m.ratingChange > 0 and "+" or ""
                local hex = m.ratingChange > 0
                    and ((M.ns.UI_GetSemanticGreenHex and M.ns.UI_GetSemanticGreenHex()) or "|cff33cc55")
                    or "|cffcc4433"
                cells[3]:SetText(hex .. sign .. tostring(m.ratingChange) .. "|r")
            else
                cells[3]:SetText("")
            end
            cells[4]:SetText(muted .. M.FormatDuration(m.duration) .. "|r")
            cells[5]:SetText(muted .. (m.mapName or "") .. "|r")
            cells[6]:SetText(muted .. M.FormatTimeAgo(m.endedAt) .. "|r")
        end
        if rowsToShow == 0 then
            local cells = M.EnsureRowCells(bundle, "recentRows", 1, card, recentCols, dataExtra)
            cells[1]:SetWidth(math.min(400, innerW))
            cells[1]:SetText(muted .. ((M.L and M.L["PVP_NO_MATCHES"]) or "No recorded matches yet") .. "|r")
            for c = 2, #cells do cells[c]:SetText("") end
            M.HideRowsFrom(bundle, "recentRows", 2)
            M.HideRecentHitsFrom(bundle, 1)
        else
            M.HideRowsFrom(bundle, "recentRows", rowsToShow + 1)
            M.HideRecentHitsFrom(bundle, rowsToShow + 1)
        end

        local resetBtn = bundle.resetBtn
        if not resetBtn then
            resetBtn = M.ns.UI_CreateThemedButton(card, (M.L and M.L["PVP_RESET_HISTORY"]) or "Reset Statistics", 150)
            resetBtn:SetScript("OnClick", function()
                if M.ns.PvPService then
                    M.ns.PvPService:ResetMatchStats(nil, "all")
                end
            end)
            bundle.resetBtn = resetBtn
        end
        resetBtn:SetParent(card)
        resetBtn:ClearAllPoints()
        resetBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -M.CARD_PAD, M.CARD_PAD)
        resetBtn:Show()

        cardH = rowTop + math.max(1, rowsToShow) * M.ROW_H + M.RECENT_FOOTER_H + M.CARD_PAD
        card:SetHeight(cardH)
        yOffset = yOffset + cardH + M.SECTION_GAP
    end

    -- Row 5: Active Brawl (live read, logged-in character only; hidden when not queueable)
    do
        local brawl = M.ns.PvPService and M.ns.PvPService.GetActiveBrawl and M.ns.PvPService:GetActiveBrawl()
        if brawl then
            local descH = brawl.shortDescription and 18 or 0
            local cardH = M.CARD_PAD + M.RECENT_TITLE_H + 4 + 18 + descH + M.CARD_PAD
            local card = M.EnsureCard(bundle, "brawlCard", parent, cardH)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", SIDE, -yOffset)
            card:SetPoint("TOPRIGHT", -SIDE, -yOffset)
            card:SetHeight(cardH)
            M.EnsureCardTitle(bundle, "brawlTitle", card, (M.L and M.L["PVP_BRAWL_TITLE"]) or "Weekly Brawl")

            local timeFs = bundle.brawlTimeFs
            if not timeFs then
                timeFs = M.FontManager:CreateFontString(card, "body", "OVERLAY")
                bundle.brawlTimeFs = timeFs
            end
            timeFs:ClearAllPoints()
            timeFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CARD_PAD, -M.CARD_PAD)
            timeFs:SetJustifyH("RIGHT")
            local left = M.FormatTimeLeft(brawl.timeLeft)
            if left then
                local fmt = (M.L and M.L["PVP_BRAWL_TIME_LEFT"]) or "Changes in %s"
                timeFs:SetText(muted .. string.format(fmt, left) .. "|r")
                timeFs:Show()
            else
                timeFs:SetText("")
                timeFs:Hide()
            end

            local nameFs = bundle.brawlNameFs
            if not nameFs then
                nameFs = M.FontManager:CreateFontString(card, "body", "OVERLAY")
                bundle.brawlNameFs = nameFs
            end
            nameFs:ClearAllPoints()
            nameFs:SetPoint("TOPLEFT", card, "TOPLEFT", M.CARD_PAD, -(M.CARD_PAD + M.RECENT_TITLE_H + 4))
            nameFs:SetText(bright .. brawl.name .. "|r")
            nameFs:Show()

            local descFs = bundle.brawlDescFs
            if not descFs then
                descFs = M.FontManager:CreateFontString(card, "small", "OVERLAY")
                bundle.brawlDescFs = descFs
            end
            descFs:ClearAllPoints()
            descFs:SetPoint("TOPLEFT", card, "TOPLEFT", M.CARD_PAD, -(M.CARD_PAD + M.RECENT_TITLE_H + 4 + 18))
            descFs:SetPoint("TOPRIGHT", card, "TOPRIGHT", -M.CARD_PAD, -(M.CARD_PAD + M.RECENT_TITLE_H + 4 + 18))
            descFs:SetJustifyH("LEFT")
            if brawl.shortDescription then
                descFs:SetText(muted .. brawl.shortDescription .. "|r")
                descFs:Show()
            else
                descFs:SetText("")
                descFs:Hide()
            end

            yOffset = yOffset + cardH + M.SECTION_GAP
        elseif bundle.brawlCard then
            bundle.brawlCard:Hide()
        end
    end

    return yOffset + 20
end

function ns.WarbandNexus:DrawPvPTab(parent)
    return M.DrawTab(parent)
end
