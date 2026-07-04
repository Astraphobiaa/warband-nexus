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

    -- Title card + tab header filter (PvE parity: sort + section filter on title card)
    local WN = M.WarbandNexus
    local profile = WN and WN.db and WN.db.profile
    local r, g, b = M.COLORS.accent[1], M.COLORS.accent[2], M.COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local tm = M.ns.UI_GetTitleCardToolbarMetrics and M.ns.UI_GetTitleCardToolbarMetrics() or {}
    local hdrGapPvp = tm.gap or 8
    local pvpToolbarReserve = (M.ns.UI_ComputeTitleToolbarReserve and M.ns.UI_ComputeTitleToolbarReserve({
        168,
        tm.filterW or 96,
    })) or (200 + hdrGapPvp)
    local titleCard = bundle.titleCard
    if not titleCard then
        titleCard = select(1, M.ns.UI_CreateStandardTabTitleCard(headerParent, {
            tabKey = "pvp",
            titleText = "|cff" .. hexColor .. ((M.L and M.L["TAB_PVP"]) or "PvP") .. "|r",
            subtitleText = (M.L and M.L["PVP_SUBTITLE"]) or "Rated progress, honor, and match history",
            showUnderline = false,
            textRightInset = pvpToolbarReserve,
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

    if profile then
        profile.pvpSort = profile.pvpSort or { key = "pvpRating", ascending = true }
        if not profile.pvpSectionFilter then profile.pvpSectionFilter = { sectionKey = "all" } end
        if M.ns.CharacterService and M.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            M.ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
        end
        if not profile.ui then profile.ui = {} end
        if profile.ui.pvpFavoritesExpanded == nil then profile.ui.pvpFavoritesExpanded = true end
        if profile.ui.pvpCharactersExpanded == nil then profile.ui.pvpCharactersExpanded = true end
    end

    local titleEdgeInset = tm.edgeInset or 0
    local sortOptions = (M.ns.UI_BuildPvpOverviewSortOptions and M.ns.UI_BuildPvpOverviewSortOptions())
        or (M.ns.UI_BuildCharacterSortOptions and M.ns.UI_BuildCharacterSortOptions())
        or {}
    local filterBtn = bundle.pvpFilterBtn
    if M.ns.UI_CreateCharacterTabAdvancedFilterButton and profile and sortOptions then
        if not filterBtn then
            filterBtn = M.ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
                sortOptions = sortOptions,
                dbSortTable = profile.pvpSort,
                sortTabId = "pvp",
                dbSectionFilter = profile.pvpSectionFilter,
                getCustomSections = function()
                    return profile.characterCustomGroups or {}
                end,
                onRefresh = function()
                    WN:SendMessage(M.ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "pvp", skipCooldown = true })
                end,
            })
            bundle.pvpFilterBtn = filterBtn
        end
        if filterBtn then
            filterBtn:SetParent(titleCard)
            filterBtn:ClearAllPoints()
            if M.ns.UI_AnchorTitleCardToolbarControl then
                M.ns.UI_AnchorTitleCardToolbarControl(filterBtn, titleCard, titleCard, "RIGHT", -titleEdgeInset)
            else
                filterBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
            end
            filterBtn:Show()
        end
    elseif bundle.pvpFilterBtn then
        bundle.pvpFilterBtn:Hide()
    end

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
        M.EnsureCardTitleWithIcon(bundle, "levelTitle", "levelTitleIcon", levelCard,
            (M.L and M.L["PVP_LEVEL_PROGRESS"]) or "PvP Level Progress", M.PROGRESS_TITLE_ICONS.level)
        M.EnsureBarRow(bundle, "levelBarRow", levelCard, barY,
            string.format(lvlFmt, honor.level or 0), honor.current or 0, honor.max or 0, goldColor)

        local honorCard = M.EnsureCard(bundle, "honorCard", parent, progressCardH)
        honorCard:ClearAllPoints()
        honorCard:SetPoint("TOPLEFT", SIDE + triW + triGap, -yOffset)
        honorCard:SetWidth(triW)
        honorCard:SetHeight(progressCardH)
        M.EnsureCardTitleWithIcon(bundle, "honorTitle", "honorTitleIcon", honorCard,
            (HONOR) or "Honor", M.PROGRESS_TITLE_ICONS.honor)
        M.EnsureBarRow(bundle, "honorBarRow", honorCard, barY,
            (HONOR) or "Honor", (honorCur and honorCur.quantity) or 0,
            (honorCur and honorCur.maxQuantity) or 0, goldColor)

        local conquestCard = M.EnsureCard(bundle, "conquestCard", parent, progressCardH)
        conquestCard:ClearAllPoints()
        conquestCard:SetPoint("TOPLEFT", SIDE + (triW + triGap) * 2, -yOffset)
        conquestCard:SetWidth(triW)
        conquestCard:SetHeight(progressCardH)
        M.EnsureCardTitleWithIcon(bundle, "conquestTitle", "conquestTitleIcon", conquestCard,
            (M.L and M.L["PVP_CONQUEST"]) or "Conquest", M.PROGRESS_TITLE_ICONS.conquest)
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
            if bundle.ratedSectionFrame then bundle.ratedSectionFrame:Hide() end
            if bundle.ratedSectionTitle then bundle.ratedSectionTitle:Hide() end

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
                local bracketIcon = M.ROSTER_STAT_HEADER_ICONS and M.ROSTER_STAT_HEADER_ICONS[bkey]
                local titleFs = M.EnsureCardTitleWithIcon(bundle, "ratedTitle_" .. bkey, "ratedTitleIcon_" .. bkey,
                    card, M.BRACKET_LABELS[bkey] or bkey, bracketIcon)

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

    -- Row 3: Recent matches with mode filter sub-tabs
    do
        local recent = (matches and matches.recent) or {}
        local activeFilter = bundle.recentFilter or "all"
        local PvPS = M.ns.PvPService
        local filtered = (PvPS and PvPS.FilterRecentMatches and PvPS:FilterRecentMatches(recent, activeFilter)) or recent
        local recentMax = M.RECENT_MATCHES_COLLAPSED or 20
        local totalFiltered = #filtered
        local canExpand = totalFiltered > recentMax
        local expanded = bundle.recentExpanded and canExpand
        local rowsToShow
        if totalFiltered == 0 then
            rowsToShow = 0
        elseif expanded then
            rowsToShow = totalFiltered
        else
            rowsToShow = math.min(totalFiltered, recentMax)
        end
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
            M.EnsureRecentOutcomeStripe(bundle, i, card, rowY, m.outcome)
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
            M.HideRecentOutcomeStripesFrom(bundle, 1)
        else
            M.HideRowsFrom(bundle, "recentRows", rowsToShow + 1)
            M.HideRecentHitsFrom(bundle, rowsToShow + 1)
            M.HideRecentOutcomeStripesFrom(bundle, rowsToShow + 1)
        end

        local showMoreBtn = bundle.recentShowMoreBtn
        if canExpand then
            if not showMoreBtn then
                showMoreBtn = M.ns.UI_CreateThemedButton(card, "", 120)
                showMoreBtn:SetScript("OnClick", function()
                    bundle.recentExpanded = not bundle.recentExpanded
                    M.WarbandNexus:SendMessage(M.ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                        tab = "pvp",
                        skipCooldown = true,
                    })
                end)
                bundle.recentShowMoreBtn = showMoreBtn
            end
            showMoreBtn:SetParent(card)
            showMoreBtn:ClearAllPoints()
            showMoreBtn:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", M.CARD_PAD, M.CARD_PAD)
            local label
            if expanded then
                label = (M.L and M.L["PVP_SHOW_LESS"]) or "Show Less"
            else
                label = ((M.L and M.L["SHOW_ALL"]) or "Show All")
                    .. " (" .. tostring(totalFiltered - recentMax) .. ")"
            end
            if showMoreBtn.text and showMoreBtn.text.SetText then
                showMoreBtn.text:SetText(label)
            elseif showMoreBtn.SetText then
                showMoreBtn:SetText(label)
            end
            local textFs = showMoreBtn.text or showMoreBtn
            if textFs and textFs.GetStringWidth then
                local textW = textFs:GetStringWidth() or 0
                if textW + 20 > showMoreBtn:GetWidth() then
                    showMoreBtn:SetWidth(textW + 20)
                end
            end
            showMoreBtn:Show()
        elseif showMoreBtn then
            showMoreBtn:Hide()
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

    -- Row 4: Warband PvP Overview (Prof/PvE grid; multi-alt only)
    if M.DrawWarbandOverview then
        yOffset = yOffset + M.DrawWarbandOverview(parent, bundle, {
            SIDE = SIDE,
            width = width,
            yOffset = yOffset,
            muted = muted,
            bright = bright,
        })
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
