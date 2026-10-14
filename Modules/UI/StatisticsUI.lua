--[[
    Warband Nexus - Statistics Tab
    Display account-wide statistics: gold, collections, to-do, playtime
]]

local ADDON_NAME, ns = ...
local E = ns.Constants.EVENTS

-- Unique AceEvent handler identity for StatisticsUI
local StatisticsUIEvents = {}

local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

local issecretvalue = issecretvalue

--- Display name for stats rows: never :match on secret charKey or use secret stored name.
local function GetStatCharDisplayName(charData, charKey)
    local n = charData and charData.name
    if n and not (issecretvalue and issecretvalue(n)) then return n end
    if charKey and not (issecretvalue and issecretvalue(charKey)) then
        return charKey:match("^([^-]+)") or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    end
    return (ns.L and ns.L["UNKNOWN"]) or "Unknown"
end

-- Forward declaration (defined in COLLECTION STATS CACHE section below)
local InvalidateStatsCache

--[[
    Initialize Statistics UI event listeners
    Called during addon startup to register for data update events
]]
function WarbandNexus:InitializeStatisticsUI()
    -- Same-frame bursts (COLLECTION_UPDATED + PLANS_UPDATED + MONEY_UPDATED for one loot) collapse
    -- into one refresh request; the shell's populate debounce then coalesces across frames.
    local statsRefreshPending = false
    local function refreshStatsIfVisible()
        InvalidateStatsCache()
        if statsRefreshPending then return end
        statsRefreshPending = true
        C_Timer.After(0, function()
            statsRefreshPending = false
            if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab == "stats" then
                if self.SendMessage then
                    self:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
                end
            end
        end)
    end

    -- Register for collection and character wealth update events
    -- NOTE: Uses StatisticsUIEvents as 'self' key to avoid overwriting other modules' handlers.
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.COLLECTION_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.COLLECTION_SCAN_COMPLETE, function(_, payload)
        if not payload then
            refreshStatsIfVisible()
            return
        end
        local cat = payload.category
        if cat == "achievement" or cat == "all" then
            refreshStatsIfVisible()
        end
    end)
    -- Stats tab shows collections, To-Do counts, Warband Wealth (character gold + warband bank money)
    -- and Most Played. Nothing reads bag/item contents, so ITEMS_UPDATED / BAGS_UPDATED are not wired.
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.MONEY_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.PLANS_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.CHARACTER_UPDATED, function(_, payload)
        if payload and payload.dataType == "gold" then
            refreshStatsIfVisible()
        end
    end)
    
    -- Event listeners initialized (verbose logging removed)
end

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local FormatMoneyPartsColumn = ns.UI_FormatMoneyPartsColumn

-- Warband Wealth money columns (right-aligned G / S / C stacks per row)
local GW_MONEY_PAD_R = 15
local GW_MONEY_ICON_ROW = 12
local GW_MONEY_ICON_HDR = 14
local GW_COL_COPPER_W = 52
local GW_COL_SILVER_W = 52
local GW_COL_GOLD_W = 108
local GW_NAME_RIGHT_INSET = -(GW_MONEY_PAD_R + GW_COL_GOLD_W + GW_COL_SILVER_W + GW_COL_COPPER_W + 8)

---@param slot table|nil When given, the three FontStrings are cached on it and reused on repaint.
local function PaintStatisticsMoneyColumns(parent, anchorY, copper, iconSize, slot)
    if not FormatMoneyPartsColumn then return end
    copper = tonumber(copper) or 0
    iconSize = iconSize or GW_MONEY_ICON_ROW
    local gStr, sStr, cStr = FormatMoneyPartsColumn(copper, iconSize)

    local cFs = slot and slot.moneyC
    if not cFs then
        cFs = FontManager:CreateFontString(parent, "body", "OVERLAY")
        cFs:SetWidth(GW_COL_COPPER_W)
        cFs:SetJustifyH("RIGHT")
        if slot then slot.moneyC = cFs end
    end
    cFs:ClearAllPoints()
    cFs:SetPoint("RIGHT", parent, "TOPRIGHT", -GW_MONEY_PAD_R, anchorY)
    cFs:SetText(cStr)
    cFs:Show()

    local sFs = slot and slot.moneyS
    if not sFs then
        sFs = FontManager:CreateFontString(parent, "body", "OVERLAY")
        sFs:SetWidth(GW_COL_SILVER_W)
        sFs:SetJustifyH("RIGHT")
        if slot then slot.moneyS = sFs end
    end
    sFs:ClearAllPoints()
    sFs:SetPoint("RIGHT", parent, "TOPRIGHT", -(GW_MONEY_PAD_R + GW_COL_COPPER_W), anchorY)
    sFs:SetText(sStr)
    sFs:Show()

    local gFs = slot and slot.moneyG
    if not gFs then
        gFs = FontManager:CreateFontString(parent, "body", "OVERLAY")
        gFs:SetWidth(GW_COL_GOLD_W)
        gFs:SetJustifyH("RIGHT")
        if slot then slot.moneyG = gFs end
    end
    gFs:ClearAllPoints()
    gFs:SetPoint("RIGHT", parent, "TOPRIGHT", -(GW_MONEY_PAD_R + GW_COL_COPPER_W + GW_COL_SILVER_W), anchorY)
    gFs:SetText(gStr)
    gFs:Show()
end
local FormatNumber = ns.UI_FormatNumber

local function FormatStatCountPair(current, max)
    return FormatNumber(current) .. " / " .. FormatNumber(max)
end

local function FormatStatCountPairPct(collected, total)
    local c = tonumber(collected) or 0
    local t = tonumber(total) or 0
    local pct = t > 0 and math.floor(c / t * 100) or 0
    return FormatStatCountPair(c, t) .. " (" .. pct .. "%)"
end

local CreateIcon = ns.UI_CreateIcon
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local COLORS = ns.UI_COLORS

local function ThemeTextHex(role)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    if role == "Dim" then return "|cff888888" end
    if role == "Muted" then return "|cffaaaaaa" end
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function SemanticGoldHex()
    if ns.UI_GetSemanticGoldHex then
        return ns.UI_GetSemanticGoldHex()
    end
    return "|cffffcc00"
end

local function SemanticGoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    return 1, 0.82, 0
end

local function SemanticGreenRGB()
    if ns.UI_GetSemanticGreenColor then
        return ns.UI_GetSemanticGreenColor()
    end
    return 0.3, 0.9, 0.3, 1
end

local function AccentHex()
    if ns.UI_GetAccentHexColor then
        return "|cff" .. ns.UI_GetAccentHexColor()
    end
    local a = COLORS and COLORS.accent
    if a then
        return string.format("|cff%02x%02x%02x", a[1] * 255, a[2] * 255, a[3] * 255)
    end
    return "|cff0099ff"
end

local function SemanticInfoHex()
    if ns.UI_GetSemanticInfoHex then
        return ns.UI_GetSemanticInfoHex()
    end
    return AccentHex()
end

local function SemanticPetHex()
    if ns.UI_GetSemanticPetHex then
        return ns.UI_GetSemanticPetHex()
    end
    return "|cffff69b4"
end

local function SemanticToyHex()
    if ns.UI_GetSemanticToyHex then
        return ns.UI_GetSemanticToyHex()
    end
    return "|cffff66ff"
end

---@param slot table|nil When given, stripe + name FontString are cached on it and reused on repaint.
local function PaintStatisticsClassRow(parent, rowCenterY, rowH, classFile, charName, nameRightInset, slot)
    local barH = rowH - 4
    local colorBar = slot and slot.colorBar
    if colorBar then
        colorBar:SetSize(3, barH)
        colorBar:ClearAllPoints()
        colorBar:SetPoint("LEFT", parent, "TOPLEFT", 15, rowCenterY)
        local cr, cg, cb = 0.8, 0.8, 0.8
        if ns.UI_GetClassColorRaw then
            cr, cg, cb = ns.UI_GetClassColorRaw(classFile)
        end
        colorBar:SetColorTexture(cr, cg, cb, 1)
        colorBar:Show()
    else
        colorBar = (ns.UI_CreateClassColorStripe and ns.UI_CreateClassColorStripe(parent, parent, 15, rowCenterY, 3, barH, classFile))
    end
    if slot then slot.colorBar = colorBar end
    if not colorBar then
        colorBar = parent:CreateTexture(nil, "ARTWORK")
        colorBar:SetSize(3, barH)
        colorBar:SetPoint("LEFT", parent, "TOPLEFT", 15, rowCenterY)
        local cr, cg, cb = 0.8, 0.8, 0.8
        if ns.UI_GetClassColorForSurface and classFile then
            cr, cg, cb = ns.UI_GetClassColorForSurface(classFile)
        end
        colorBar:SetColorTexture(cr, cg, cb, 1)
        if slot then slot.colorBar = colorBar end
    end
    local nameText = slot and slot.nameText
    if not nameText then
        nameText = FontManager:CreateFontString(parent, "body", "OVERLAY")
        nameText:SetWordWrap(false)
        nameText:SetJustifyH("LEFT")
        if FontManager and FontManager.ApplyFont then
            FontManager:ApplyFont(nameText, "body")
        end
        if slot then slot.nameText = nameText end
    end
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", colorBar, "RIGHT", 8, 0)
    nameText:SetPoint("RIGHT", parent, "RIGHT", nameRightInset or -120, 0)
    if ns.UI_FormatClassColoredName then
        nameText:SetText(ns.UI_FormatClassColoredName(charName, classFile))
    else
        nameText:SetText(charName or "")
    end
    nameText:Show()
    return nameText, colorBar
end

--- Hide every cached widget of a pooled Warband Wealth / Most Played row slot.
local function HideStatisticsRowSlot(slot)
    if not slot then return end
    if slot.bg then slot.bg:Hide() end
    if slot.colorBar then slot.colorBar:Hide() end
    if slot.nameText then slot.nameText:Hide() end
    if slot.moneyC then slot.moneyC:Hide() end
    if slot.moneyS then slot.moneyS:Hide() end
    if slot.moneyG then slot.moneyG:Hide() end
    if slot.timeText then slot.timeText:Hide() end
end

--- Pooled striped row background on a cached card.
local function PaintStatisticsRowBg(card, slot, rowIndex, rowTop, rowH)
    local rowBg = slot.bg
    if not rowBg then
        rowBg = card:CreateTexture(nil, "BACKGROUND", nil, 1)
        slot.bg = rowBg
    end
    rowBg:ClearAllPoints()
    rowBg:SetPoint("TOPLEFT", card, "TOPLEFT", 10, rowTop)
    rowBg:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, rowTop)
    rowBg:SetHeight(rowH)
    local stripe = (rowIndex % 2 == 0) and (COLORS.surfaceRowEven or COLORS.bgLight)
        or (COLORS.surfaceRowOdd or COLORS.bg)
    stripe = stripe or { 0.768, 0.760, 0.744, 0.98 }
    rowBg:SetColorTexture(stripe[1], stripe[2], stripe[3], stripe[4] or 0.98)
    rowBg:Show()
end

local function ToggleStatisticsExpandState(stateKey)
    if not ns._statisticsExpandedStates then
        ns._statisticsExpandedStates = {}
    end
    ns._statisticsExpandedStates[stateKey] = not (ns._statisticsExpandedStates[stateKey] or false)
    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
end

--- Expand/collapse arrow + "N more characters" on a cached card (PlanCardFactory glues atlas pattern).
--- Scripts are bound once and read the live expand state, so the card can be repainted in place.
local function PaintStatisticsExpandToggle(card, toggle, stateKey, hasOverflow, isExpanded, hiddenCount, bottomPad)
    toggle.active = hasOverflow == true
    if not hasOverflow then
        if toggle.btn then toggle.btn:Hide() end
        if toggle.moreText then toggle.moreText:Hide() end
        return
    end
    local expandBtn = toggle.btn
    if not expandBtn then
        expandBtn = ns.UI.Factory:CreateButton(card, 20, 20, true)
        expandBtn:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, bottomPad)
        expandBtn:EnableMouse(true)
        local arrowTex = expandBtn:CreateTexture(nil, "OVERLAY")
        arrowTex:SetAllPoints(expandBtn)
        expandBtn:SetScript("OnClick", function()
            ToggleStatisticsExpandState(stateKey)
        end)
        -- Entire card toggles too (only while the overflow toggle is active).
        card:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" and toggle.active then
                ToggleStatisticsExpandState(stateKey)
            end
        end)
        toggle.btn = expandBtn
        toggle.arrowTex = arrowTex
    end
    ns.UI_SetIcon(toggle.arrowTex, isExpanded and "chevron_up" or "chevron_down")
    expandBtn:Show()
    card:EnableMouse(true)

    if isExpanded then
        if toggle.moreText then toggle.moreText:Hide() end
        return
    end
    local moreText = toggle.moreText
    if not moreText then
        moreText = FontManager:CreateFontString(card, "small", "OVERLAY")
        moreText:SetPoint("RIGHT", expandBtn, "LEFT", -4, 0)
        moreText:SetJustifyH("RIGHT")
        toggle.moreText = moreText
    end
    local moreLabel = hiddenCount > 1
        and ((ns.L and ns.L["MORE_CHARACTERS_PLURAL"]) or "more characters")
        or ((ns.L and ns.L["MORE_CHARACTERS"]) or "more character")
    moreText:SetText(ThemeTextHex("Muted") .. hiddenCount .. " " .. moreLabel .. "|r")
    moreText:Show()
end

local STAT_CARD_H = 90

local function ParkStatisticsHeavyDynamicCards(parent)
    local b = parent._wnStatsHeavyBundle
    if not b then return end
    local bin = ns.UI_RecycleBin
    local function park(frame)
        if not frame then return end
        frame:Hide()
        frame:ClearAllPoints()
        if bin then
            frame:SetParent(bin)
        end
    end
    -- Warband Wealth / Most Played cards are cached on the bundle and repainted in place
    -- (PaintHeavyStatisticsBody re-shows them); only hide here so a no-data pass leaves nothing behind.
    if b.goldCard then b.goldCard:Hide() end
    if b.mpCard then b.mpCard:Hide() end
    park(b.storageCard)
    b.storageCard = nil
    b.storageTitle = nil
    b.storageCols = nil
end

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8

-- Performance: Local function references
local format = string.format

-- COLLECTION STATS CACHE
-- Mount/Pet/Toy iteration is extremely expensive (1000+ API calls per frame).
-- Cache results with a short TTL so visual-only operations like expand/collapse
-- don't re-run thousands of synchronous WoW API calls.
local STATS_CACHE_TTL = 60  -- seconds before cache is considered stale (invalidated on WN_COLLECTION_UPDATED)
local _statsCache = nil     -- { mounts={}, pets={}, toys={}, achievements={}, timestamp=number }

-- Invalidate cache so next DrawStatistics recomputes from API
-- (forward-declared above InitializeStatisticsUI so event callbacks can reference it)
InvalidateStatsCache = function()
    _statsCache = nil
end

-- Compute and cache collection statistics (store fast-path, else CollectionService API counts).
local function GetCachedCollectionStats()
    local now = GetTime()
    if _statsCache and (now - _statsCache.timestamp) < STATS_CACHE_TTL then
        return _statsCache
    end

    local api
    if WarbandNexus.GetCollectionCountsFromStore and WarbandNexus.IsCollectionEnsureDataComplete
        and WarbandNexus:IsCollectionEnsureDataComplete() then
        api = WarbandNexus:GetCollectionCountsFromStore()
        if api and C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if WarbandNexus.GetCollectionCountsFromAPI then
                    WarbandNexus:GetCollectionCountsFromAPI()
                end
            end)
        end
    end
    if not api then
        api = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
    end
    if not api then
        if _statsCache then return _statsCache end
        api = {
            mounts = { collected = 0, total = 0 },
            pets = { collected = 0, totalSpecies = 0, uniqueSpecies = 0, journalEntries = 0 },
            toys = { collected = 0, total = 0 },
            achievementPoints = 0,
            achievementPointsCharacter = 0,
            achievementPointsMax = 0,
            achievementsTotal = 0,
            achievementsCompleted = 0,
        }
    end
    _statsCache = {
        timestamp = now,
        achievementPoints = api.achievementPoints or 0,
        achievementPointsCharacter = api.achievementPointsCharacter or 0,
        achievementPointsMax = api.achievementPointsMax or 0,
        achievementsTotal = api.achievementsTotal or 0,
        achievementsCompleted = api.achievementsCompleted or 0,
        mounts = api.mounts or { collected = 0, total = 0 },
        pets = api.pets or { collected = 0, totalSpecies = 0, uniqueSpecies = 0, journalEntries = 0 },
        toys = api.toys or { collected = 0, total = 0 },
    }
    return _statsCache
end

--- Reposition cached Statistics fixedHeader title (Items/Collections parity — WN-PERF tab revisit).
local function RepositionStatisticsFixedHeader(hdrCache, headerParent, chrome, headerYOffset, SIDE)
    local titleCard = hdrCache.titleCard
    titleCard:SetParent(headerParent)
    if chrome and ns.UI_PageStack_Place then
        titleCard:Show()
        chrome.yOffset = headerYOffset
        return ns.UI_PageStack_Place(chrome, titleCard)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", SIDE, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -SIDE, -headerYOffset)
    end
    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        return ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    end
    return headerYOffset + (GetLayout().afterHeader or 72)
end

local function FormatTodoProgressLine(completed, total)
    local c = tonumber(completed) or 0
    local t = tonumber(total) or 0
    local remain = math.max(0, t - c)
    local L = ns.L
    local fmt = (L and L["STATS_TODO_PROGRESS"]) or "%s / %s completed (%s remaining)"
    return string.format(fmt, FormatNumber(c), FormatNumber(t), FormatNumber(remain))
end

local function HideLegacyAchievementWidgets(bundle)
    if not bundle then return end
    local legacyKeys = {
        "achTitle", "achAccountLabel", "achAccountValue", "achProgress",
        "achCharLine",
        "achProgLabel", "achProgValue", "achScoreLabel", "achScoreValue",
    }
    for i = 1, #legacyKeys do
        local fs = bundle[legacyKeys[i]]
        if fs then fs:Hide() end
    end
    if bundle.achCols then
        for ci = 1, #bundle.achCols do
            local col = bundle.achCols[ci]
            if col and col.label then col.label:Hide() end
            if col and col.value then col.value:Hide() end
        end
    end
    local layout = bundle.achLayout
    if layout then
        if layout.icon then layout.icon:Hide() end
        if layout.label then layout.label:Hide() end
        if layout.value then layout.value:Hide() end
        if layout.container then layout.container:Hide() end
    end
end

--- Achievement stat cards: same left-icon header layout as mount/toy (36px atlas).
local ACH_HEADER_CARD_VER = 6
local ACH_COLL_ICON_SIZE = 36
local STAT_CARD_ICON_LEFT = 15
local ACH_ATLAS_SCORE = "UI-Achievement-Shield-NoPoints"
local ACH_ATLAS_CHARACTER = "shop-icon-housing-characters-up"
local ACH_ATLAS_PROGRESS = "UI-Frame-DastardlyDuos-icon-Speed"

local function FormatAchPointsCurrentMax(hex, current, max)
    local c = tonumber(current) or 0
    local m = tonumber(max) or 0
    if m > 0 and m >= c then
        return hex .. FormatStatCountPair(c, m) .. "|r"
    end
    return hex .. FormatNumber(c) .. "|r"
end

local function FitCardHeaderLayoutToCard(card, layout, iconSize)
    if not card or not layout or not layout.container or not layout.icon then return end
    iconSize = iconSize or ACH_COLL_ICON_SIZE
    local cardW = card:GetWidth() or 200
    local textW = cardW - STAT_CARD_ICON_LEFT - iconSize - 12 - 8
    if textW < 48 then textW = 48 end
    layout.container:SetWidth(textW)
    layout.icon:ClearAllPoints()
    layout.icon:SetPoint("CENTER", card, "LEFT", STAT_CARD_ICON_LEFT + (iconSize / 2), 0)
    layout.container:ClearAllPoints()
    layout.container:SetPoint("LEFT", layout.icon, "RIGHT", 12, 0)
    layout.container:SetPoint("CENTER", card, "CENTER", 0, 0)
end

local function TeardownAchievementCardBundle(bundle, prefix)
    if not bundle then return end
    local layout = bundle[prefix .. "Layout"]
    if layout then
        if layout.icon then layout.icon:Hide() end
        if layout.label then layout.label:Hide() end
        if layout.value then layout.value:Hide() end
        if layout.container then layout.container:Hide() end
        bundle[prefix .. "Layout"] = nil
    end
    for mi = 1, 3 do
        local suffix = (mi == 1 and "Title") or (mi == 2 and "Metric") or "Value"
        local key = prefix .. suffix
        local fs = bundle[key]
        if fs then fs:Hide(); bundle[key] = nil end
    end
    bundle[prefix .. "LayoutVer"] = nil
    bundle[prefix .. "HeaderVer"] = nil
end

local function GetLoggedInClassColorHex()
    local _, classFile = UnitClass("player")
    if classFile and ns.UI_GetClassColorHexForSurface then
        return ns.UI_GetClassColorHexForSurface(classFile)
    end
    return "ffffff"
end

local function EnsureAchievementHeaderCard(card, bundle, prefix, atlas, titleText, valueText)
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    if not CreateCardHeaderLayout then return end
    local verKey = prefix .. "HeaderVer"
    if bundle[verKey] ~= ACH_HEADER_CARD_VER then
        TeardownAchievementCardBundle(bundle, prefix)
        local layout = CreateCardHeaderLayout(card, atlas, ACH_COLL_ICON_SIZE, true, titleText, valueText, "subtitle", "header")
        if layout and layout.label then
            ns.UI_SetTextColorRole(layout.label, "Bright")
        end
        bundle[prefix .. "Layout"] = layout
        bundle[verKey] = ACH_HEADER_CARD_VER
    else
        local layout = bundle[prefix .. "Layout"]
        if layout then
            if layout.label then
                layout.label:SetText(titleText)
                layout.label:Show()
            end
            if layout.value then
                layout.value:SetText(valueText)
                layout.value:Show()
            end
            if layout.icon then layout.icon:Show() end
            if layout.container then layout.container:Show() end
        end
    end
    FitCardHeaderLayoutToCard(card, bundle[prefix .. "Layout"], ACH_COLL_ICON_SIZE)
end

local function PaintAchievementCollectionCards(bundle, achScoreCard, achCharCard, achProgCard,
    accountPoints, characterPoints, accountPointsMax, completed, total)
    local L = ns.L
    local gold = SemanticGoldHex()
    local toyHex = SemanticToyHex()
    local classHex = GetLoggedInClassColorHex()
    local c = tonumber(completed) or 0
    local t = tonumber(total) or 0
    local titleScore = (L and L["STATS_ACH_CARD_SCORE"]) or "Achievement Score"
    local titleChar = (L and L["STATS_ACH_CARD_CHARACTER"]) or "Character Achievements"
    local titleProg = (L and L["ACHIEVEMENT_PROGRESS_TITLE"]) or "Achievement Progress"
    HideLegacyAchievementWidgets(bundle)
    EnsureAchievementHeaderCard(achScoreCard, bundle, "achScore", ACH_ATLAS_SCORE, titleScore,
        FormatAchPointsCurrentMax(gold, accountPoints, accountPointsMax))
    EnsureAchievementHeaderCard(achCharCard, bundle, "achChar", ACH_ATLAS_CHARACTER, titleChar,
        FormatAchPointsCurrentMax("|cff" .. classHex, characterPoints, accountPoints))
    EnsureAchievementHeaderCard(achProgCard, bundle, "achProg", ACH_ATLAS_PROGRESS, titleProg,
        FormatAchPointsCurrentMax(toyHex, c, t))
end

local function PositionStatsCollectionCard(card, parent, colIndex, rowIndex, leftMargin, yBase, cardW, cardSpacing, rowStep)
    local xOff = leftMargin + (colIndex - 1) * (cardW + cardSpacing)
    local yOff = yBase + (rowIndex - 1) * rowStep
    card:SetParent(parent)
    card:ClearAllPoints()
    card:SetWidth(cardW)
    card:SetHeight(STAT_CARD_H)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, -yOff)
    card:Show()
end

local function PaintTodoSummaryCard(card, bundle, completed, total)
    local todoIcon = CreateIcon(card, "Interface\\Icons\\INV_Misc_Note_06", 36, false, nil, true)
    todoIcon:SetPoint("TOPLEFT", card, "TOPLEFT", 15, -14)
    todoIcon:Show()

    local titleFs = bundle and bundle.todoTitle
    if not titleFs then
        titleFs = FontManager:CreateFontString(card, "subtitle", "OVERLAY")
        titleFs:SetPoint("TOPLEFT", todoIcon, "TOPRIGHT", 12, -2)
        titleFs:SetText((ns.L and ns.L["STATS_TODO_TITLE"]) or "To-Do")
        ns.UI_SetTextColorRole(titleFs, "Bright")
        if bundle then bundle.todoTitle = titleFs end
    end
    titleFs:Show()

    local valueFs = bundle and bundle.todoValue
    if not valueFs then
        valueFs = FontManager:CreateFontString(card, "header", "OVERLAY")
        valueFs:SetPoint("TOPLEFT", todoIcon, "BOTTOMLEFT", 0, -8)
        valueFs:SetJustifyH("LEFT")
        if bundle then bundle.todoValue = valueFs end
    end
    local gr, gg, gb = SemanticGreenRGB()
    valueFs:SetText(string.format("|cff%02x%02x%02x%s|r",
        math.floor(gr * 255), math.floor(gg * 255), math.floor(gb * 255),
        FormatTodoProgressLine(completed, total)))
    valueFs:Show()
end

-- DRAW STATISTICS (Modern Design)

function WarbandNexus:DrawStatistics(parent)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local SIDE = metrics and metrics.sideMargin or SIDE_MARGIN
    local pageStack = GetLayout().PAGE_STACK or {}
    local CARD_GAP_M = pageStack.CARD_GAP or (metrics and metrics.cardGap) or 10
    local width = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local cardWidth = (width - CARD_GAP_M) / 2

    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or (metrics and metrics.topMargin) or TOP_MARGIN

    -- Hide previous empty state
    HideEmptyStateCard(parent, "statistics")

    local allCharacters = self:GetAllCharacters() or {}

    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)

    local hdrCache = mf and mf._statsFixedHeaderCache
    local headerDone = false
    if hdrCache and hdrCache.titleCard then
        headerYOffset = RepositionStatisticsFixedHeader(hdrCache, headerParent, chrome, headerYOffset, SIDE)
        if ns.UI_CommitTabFixedHeader then
            ns.UI_CommitTabFixedHeader(mf, headerYOffset)
        elseif fixedHeader then
            fixedHeader:SetHeight(headerYOffset)
        end
        headerDone = true
    end

    if not headerDone then
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "statistics",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["ACCOUNT_STATISTICS"]) or "Account Statistics") .. "|r",
        subtitleText = (ns.L and ns.L["STATISTICS_SUBTITLE"]) or "Collection progress, gold, and account activity",
        showUnderline = false,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", SIDE, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -SIDE, -headerYOffset)
    end

    titleCard:Show()
    if chrome and ns.UI_PageStack_Place then
        headerYOffset = ns.UI_PageStack_Place(chrome, titleCard)
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    elseif ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    if mf then
        mf._statsFixedHeaderCache = { titleCard = titleCard }
    end
    end

    local yOffset = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    local sectionGap = pageStack.SECTION_GAP or (metrics and metrics.sectionGap) or 12

    -- No characters: title card stays in the fixedHeader; empty card is the first body block (BODY_TOP, +/-SIDE).
    if #allCharacters == 0 then
        if parent._wnResultsAnnexSheet then parent._wnResultsAnnexSheet:Hide() end
        local _, height = CreateEmptyStateCard(parent, "statistics", yOffset, { sideInset = SIDE })
        return yOffset + (height or 120)
    end
    local ApplyPanelCardChrome = ns.UI_ApplyStandardCardElevatedChrome

    -- Tab pool revisit: allow deferred heavy body on every PopulateContent pass (not only first visit).
    if parent._preparedByPopulate then
        parent._wnStatsHeavyPaintDone = false
    end

    -- Use cached collection stats to avoid expensive API iteration on every redraw
    -- (mount/pet scanning is 1000+ API calls; cache is invalidated on real data changes)
    local collectionStats = GetCachedCollectionStats()
    
    local achievementPoints = collectionStats.achievementPoints
    local achievementPointsCharacter = collectionStats.achievementPointsCharacter or 0
    local achievementPointsMax = collectionStats.achievementPointsMax or 0
    local achievementsTotal = collectionStats.achievementsTotal or 0
    local achievementsCompleted = collectionStats.achievementsCompleted or 0
    local numCollectedMounts = collectionStats.mounts.collected
    local numTotalMounts = collectionStats.mounts.total
    local numCollectedPets = collectionStats.pets.collected
    local numTotalSpecies = collectionStats.pets.totalSpecies
    local numUniqueSpecies = collectionStats.pets.uniqueSpecies
    local numJournalEntries = collectionStats.pets.journalEntries
    local numCollectedToys = collectionStats.toys.collected
    local numTotalToys = collectionStats.toys.total
    
    -- Collection grid: row 1 = 3 achievement cards, row 2 = mount / pet / toy.
    local leftMargin = SIDE
    local rightMargin = SIDE
    local cardSpacing = CARD_GAP_M
    local COLL_COLS = 3
    local availableW = width - leftMargin - rightMargin
    local cardW = (availableW - cardSpacing * (COLL_COLS - 1)) / COLL_COLS
    local collRowStep = STAT_CARD_H + cardSpacing  -- grid rows are cards: CARD_GAP, same as columns
    local collectionRowY = yOffset
    local collLayoutSig = "3x2:h7:" .. math.floor(cardW + 0.5)
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local collBundle = parent._wnStatsCollectionBundle
    local achScoreCard, achCharCard, achProgCard, mountCard, petCard, toyCard

    if collBundle and collBundle.layoutSig == collLayoutSig and collBundle.achScoreCard then
        achScoreCard = collBundle.achScoreCard
        achCharCard = collBundle.achCharCard
        achProgCard = collBundle.achProgCard
        mountCard = collBundle.mountCard
        petCard = collBundle.petCard
        toyCard = collBundle.toyCard
        PositionStatsCollectionCard(achScoreCard, parent, 1, 1, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
        PositionStatsCollectionCard(achCharCard, parent, 2, 1, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
        PositionStatsCollectionCard(achProgCard, parent, 3, 1, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
        PaintAchievementCollectionCards(collBundle, achScoreCard, achCharCard, achProgCard,
            achievementPoints, achievementPointsCharacter, achievementPointsMax,
            achievementsCompleted, achievementsTotal)
        PositionStatsCollectionCard(mountCard, parent, 1, 2, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
        PositionStatsCollectionCard(petCard, parent, 2, 2, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
        PositionStatsCollectionCard(toyCard, parent, 3, 2, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
        FitCardHeaderLayoutToCard(mountCard, collBundle.mountLayout, ACH_COLL_ICON_SIZE)
        FitCardHeaderLayoutToCard(toyCard, collBundle.toyLayout, ACH_COLL_ICON_SIZE)
        if collBundle.mountValue then
            collBundle.mountValue:SetText(SemanticInfoHex() .. FormatStatCountPairPct(numCollectedMounts, numTotalMounts) .. "|r")
        end
        if collBundle.bpValue then
            collBundle.bpValue:SetText(SemanticPetHex() .. FormatStatCountPair(numCollectedPets, numJournalEntries) .. "|r")
        end
        if collBundle.upValue then
            collBundle.upValue:SetText(SemanticPetHex() .. FormatStatCountPair(numUniqueSpecies, numTotalSpecies) .. "|r")
        end
        if collBundle.toyValue then
            collBundle.toyValue:SetText(SemanticToyHex() .. FormatStatCountPairPct(numCollectedToys, numTotalToys) .. "|r")
        end
    else
    local collFields = {}

    achScoreCard = CreateCard(parent, STAT_CARD_H)
    if ApplyPanelCardChrome then ApplyPanelCardChrome(achScoreCard) end
    achCharCard = CreateCard(parent, STAT_CARD_H)
    if ApplyPanelCardChrome then ApplyPanelCardChrome(achCharCard) end
    achProgCard = CreateCard(parent, STAT_CARD_H)
    if ApplyPanelCardChrome then ApplyPanelCardChrome(achProgCard) end
    PositionStatsCollectionCard(achScoreCard, parent, 1, 1, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
    PositionStatsCollectionCard(achCharCard, parent, 2, 1, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
    PositionStatsCollectionCard(achProgCard, parent, 3, 1, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
    PaintAchievementCollectionCards(collFields, achScoreCard, achCharCard, achProgCard,
        achievementPoints, achievementPointsCharacter, achievementPointsMax,
        achievementsCompleted, achievementsTotal)

    mountCard = CreateCard(parent, STAT_CARD_H)
    PositionStatsCollectionCard(mountCard, parent, 1, 2, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
    local mountLayout = CreateCardHeaderLayout(
        mountCard,
        "Interface\\Icons\\Ability_Mount_RidingHorse",
        36,
        false,
        (ns.L and ns.L["MOUNTS_COLLECTED"]) or "MOUNTS COLLECTED",
        SemanticInfoHex() .. FormatStatCountPairPct(numCollectedMounts, numTotalMounts) .. "|r",
        "subtitle",
        "header"
    )
    if mountLayout.label then
        ns.UI_SetTextColorRole(mountLayout.label, "Bright")
    end
    FitCardHeaderLayoutToCard(mountCard, mountLayout, ACH_COLL_ICON_SIZE)
    if ApplyPanelCardChrome then ApplyPanelCardChrome(mountCard) end

    petCard = CreateCard(parent, STAT_CARD_H)
    PositionStatsCollectionCard(petCard, parent, 2, 2, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
    local petIcon = CreateIcon(petCard, "Interface\\Icons\\INV_Box_PetCarrier_01", 36, false, nil, true)
    petIcon:SetPoint("CENTER", petCard, "LEFT", 15 + 18, 0)
    petIcon:Show()
    local bpLabel = FontManager:CreateFontString(petCard, "subtitle", "OVERLAY")
    bpLabel:SetPoint("BOTTOMLEFT", petIcon, "RIGHT", 10, 2)
    bpLabel:SetText((ns.L and ns.L["BATTLE_PETS"]) or "BATTLE PETS")
    ns.UI_SetTextColorRole(bpLabel, "Bright")
    bpLabel:SetJustifyH("LEFT")
    local bpValue = FontManager:CreateFontString(petCard, "header", "OVERLAY")
    bpValue:SetPoint("TOPLEFT", petIcon, "RIGHT", 10, -2)
    bpValue:SetText(SemanticPetHex() .. FormatStatCountPair(numCollectedPets, numJournalEntries) .. "|r")
    bpValue:SetJustifyH("LEFT")
    local upLabel = FontManager:CreateFontString(petCard, "subtitle", "OVERLAY")
    upLabel:SetPoint("TOP", bpLabel, "TOP", 0, 0)
    upLabel:SetPoint("LEFT", bpValue, "RIGHT", 20, 0)
    upLabel:SetText((ns.L and ns.L["UNIQUE_PETS"]) or "UNIQUE PETS")
    ns.UI_SetTextColorRole(upLabel, "Bright")
    upLabel:SetJustifyH("LEFT")
    local upValue = FontManager:CreateFontString(petCard, "header", "OVERLAY")
    upValue:SetPoint("TOPLEFT", upLabel, "BOTTOMLEFT", 0, -4)
    upValue:SetText(SemanticPetHex() .. FormatStatCountPair(numUniqueSpecies, numTotalSpecies) .. "|r")
    upValue:SetJustifyH("LEFT")
    if ApplyPanelCardChrome then ApplyPanelCardChrome(petCard) end

    toyCard = CreateCard(parent, STAT_CARD_H)
    PositionStatsCollectionCard(toyCard, parent, 3, 2, leftMargin, collectionRowY, cardW, cardSpacing, collRowStep)
    local toyLayout = CreateCardHeaderLayout(
        toyCard,
        "Interface\\Icons\\INV_Misc_Toy_10",
        36,
        false,
        (ns.L and ns.L["CATEGORY_TOYS"]) or "TOYS",
        SemanticToyHex() .. FormatStatCountPairPct(numCollectedToys, numTotalToys) .. "|r",
        "subtitle",
        "header"
    )
    if toyLayout.label then
        ns.UI_SetTextColorRole(toyLayout.label, "Bright")
    end
    FitCardHeaderLayoutToCard(toyCard, toyLayout, ACH_COLL_ICON_SIZE)
    if ApplyPanelCardChrome then ApplyPanelCardChrome(toyCard) end

    parent._wnStatsCollectionBundle = collFields
    parent._wnStatsCollectionBundle.layoutSig = collLayoutSig
    parent._wnStatsCollectionBundle.achScoreCard = achScoreCard
    parent._wnStatsCollectionBundle.achCharCard = achCharCard
    parent._wnStatsCollectionBundle.achProgCard = achProgCard
    parent._wnStatsCollectionBundle.mountCard = mountCard
    parent._wnStatsCollectionBundle.mountLayout = mountLayout
    parent._wnStatsCollectionBundle.mountValue = mountLayout and mountLayout.value
    parent._wnStatsCollectionBundle.petCard = petCard
    parent._wnStatsCollectionBundle.bpValue = bpValue
    parent._wnStatsCollectionBundle.upValue = upValue
    parent._wnStatsCollectionBundle.toyCard = toyCard
    parent._wnStatsCollectionBundle.toyLayout = toyLayout
    parent._wnStatsCollectionBundle.toyValue = toyLayout and toyLayout.value
    end -- collection bundle create

    local collBlockH = collRowStep + STAT_CARD_H
    yOffset = yOffset + collBlockH + sectionGap

    local todoCounts = self.GetPlansStatisticsCounts and self:GetPlansStatisticsCounts() or { total = 0, completed = 0 }
    local todoCompleted = todoCounts.completed or 0
    local todoTotal = todoCounts.total or 0
    local todoBundle = parent._wnStatsTodoBundle
    local todoCard
    if todoBundle and todoBundle.todoCard then
        todoCard = todoBundle.todoCard
        todoCard:SetParent(parent)
        todoCard:ClearAllPoints()
        todoCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        todoCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        todoCard:Show()
        PaintTodoSummaryCard(todoCard, todoBundle, todoCompleted, todoTotal)
    else
        local todoFields = {}
        todoCard = CreateCard(parent, STAT_CARD_H)
        todoCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        todoCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        if ApplyPanelCardChrome then ApplyPanelCardChrome(todoCard) end
        PaintTodoSummaryCard(todoCard, todoFields, todoCompleted, todoTotal)
        todoCard:Show()
        parent._wnStatsTodoBundle = {
            todoCard = todoCard,
            todoTitle = todoFields.todoTitle,
            todoValue = todoFields.todoValue,
        }
    end
    yOffset = yOffset + STAT_CARD_H + sectionGap

    local PaintHeavyStatisticsBody
    PaintHeavyStatisticsBody = function(startYOffset)
    if not parent._wnStatsHeavyBundle then
        parent._wnStatsHeavyBundle = {}
    end
    ParkStatisticsHeavyDynamicCards(parent)
    local heavyBundle = parent._wnStatsHeavyBundle
    local yOffset = startYOffset
    local GW_VISIBLE_ROWS = 5
    local GW_ROW_HEIGHT = 22
    local GW_ROW_SPACING = 1
    local GW_HEADER_AREA = 48
    local GW_TOGGLE_HEIGHT = 28
    local GW_BOTTOM_PAD = 8
    
    local goldChars = {}
    local totalCharCopper = 0
    for i = 1, #allCharacters do
        local charData = allCharacters[i]
        if charData.isTracked then
            local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(charData)
            local copper = ns.Utilities:GetCharTotalCopper(charData)
            goldChars[#goldChars + 1] = {
                name = GetStatCharDisplayName(charData, charKey),
                classFile = charData.classFile,
                copper = copper,
            }
            totalCharCopper = totalCharCopper + copper
        end
    end
    table.sort(goldChars, function(a, b) return a.copper > b.copper end)
    
    local warbandBankCopper = ns.Utilities:GetWarbandBankMoney() or 0
    local grandTotalCopper = totalCharCopper + warbandBankCopper
    local goldShown, mpShown = false, false
    
    if #goldChars > 0 then
        if not ns._statisticsExpandedStates then
            ns._statisticsExpandedStates = {}
        end
        local isGoldExpanded = ns._statisticsExpandedStates["warbandWealth"] or false
        local goldVisibleCount = isGoldExpanded and #goldChars or math.min(#goldChars, GW_VISIBLE_ROWS)
        local goldHasOverflow = #goldChars > GW_VISIBLE_ROWS
        local goldToggleSpace = goldHasOverflow and GW_TOGGLE_HEIGHT or 0
        
        local goldRowsHeight = goldVisibleCount * (GW_ROW_HEIGHT + GW_ROW_SPACING)
        local goldCardHeight = GW_HEADER_AREA + goldRowsHeight + goldToggleSpace + GW_BOTTOM_PAD
        
        -- Add warband bank row space (always shown)
        if warbandBankCopper > 0 then
            goldCardHeight = goldCardHeight + GW_ROW_HEIGHT + GW_ROW_SPACING
        end
        
        -- Cached per parent (like the collection-card bundle): create chrome once, repaint content.
        local goldCard = heavyBundle.goldCard
        local gw = heavyBundle.goldWidgets
        if not goldCard or not gw then
            goldCard = CreateCard(parent, goldCardHeight)
            if ApplyPanelCardChrome then ApplyPanelCardChrome(goldCard) end

            local gwIcon = CreateIcon(goldCard, "BonusLoot-Chest", 28, true, nil, true)
            gwIcon:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 15, -10)
            gwIcon:Show()

            local gwTitle = FontManager:CreateFontString(goldCard, "subtitle", "OVERLAY")
            gwTitle:SetPoint("LEFT", gwIcon, "RIGHT", 10, 0)
            gwTitle:SetJustifyH("LEFT")

            gw = { title = gwTitle, total = {}, rows = {}, wb = {}, toggle = {} }
            heavyBundle.goldCard = goldCard
            heavyBundle.goldWidgets = gw
        end
        goldCard:SetParent(parent)
        goldCard:SetHeight(goldCardHeight)
        goldCard:ClearAllPoints()
        goldCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        goldCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)

        gw.title:SetText((ns.L and ns.L["WARBAND_WEALTH"]) or "WARBAND WEALTH")
        ns.UI_SetTextColorRole(gw.title, "Bright")

        local gwTotalAnchorY = -24
        PaintStatisticsMoneyColumns(goldCard, gwTotalAnchorY, grandTotalCopper, GW_MONEY_ICON_HDR, gw.total)

        local gwRowY = GW_HEADER_AREA
        local gwRows = gw.rows

        for i = 1, goldVisibleCount do
            local charInfo = goldChars[i]
            local rowTop = -gwRowY
            local rowCenterY = rowTop - (GW_ROW_HEIGHT / 2)
            local slot = gwRows[i]
            if not slot then
                slot = {}
                gwRows[i] = slot
            end

            PaintStatisticsRowBg(goldCard, slot, i, rowTop, GW_ROW_HEIGHT)
            PaintStatisticsClassRow(goldCard, rowCenterY, GW_ROW_HEIGHT, charInfo.classFile, charInfo.name, GW_NAME_RIGHT_INSET, slot)
            PaintStatisticsMoneyColumns(goldCard, rowCenterY, charInfo.copper, GW_MONEY_ICON_ROW, slot)

            gwRowY = gwRowY + GW_ROW_HEIGHT + GW_ROW_SPACING
        end
        for i = goldVisibleCount + 1, #gwRows do
            HideStatisticsRowSlot(gwRows[i])
        end

        -- Warband bank row (distinct style)
        local wb = gw.wb
        if warbandBankCopper > 0 then
            local rowTop = -gwRowY
            local rowCenterY = rowTop - (GW_ROW_HEIGHT / 2)

            if not wb.sep then
                wb.sep = goldCard:CreateTexture(nil, "ARTWORK")
                if ns.UI_SetRuleThickness then ns.UI_SetRuleThickness(wb.sep, "horizontal", 1) else wb.sep:SetHeight(1) end

                wb.icon = goldCard:CreateTexture(nil, "ARTWORK")
                wb.icon:SetSize(16, 16)
                wb.icon:SetAtlas("warbands-icon")

                wb.name = FontManager:CreateFontString(goldCard, "body", "OVERLAY")
                wb.name:SetPoint("LEFT", wb.icon, "RIGHT", 6, 0)
                wb.name:SetPoint("RIGHT", goldCard, "RIGHT", GW_NAME_RIGHT_INSET, 0)
                wb.name:SetWordWrap(false)
                wb.name:SetJustifyH("LEFT")
            end
            wb.sep:ClearAllPoints()
            wb.sep:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 15, rowTop)
            wb.sep:SetPoint("TOPRIGHT", goldCard, "TOPRIGHT", -15, rowTop)
            wb.sep:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
            wb.sep:Show()

            wb.icon:ClearAllPoints()
            wb.icon:SetPoint("LEFT", goldCard, "TOPLEFT", 18, rowCenterY)
            wb.icon:Show()

            wb.name:SetText(SemanticInfoHex() .. ((ns.L and ns.L["WARBAND_BANK"]) or "Warband Bank") .. "|r")
            wb.name:Show()

            PaintStatisticsMoneyColumns(goldCard, rowCenterY, warbandBankCopper, GW_MONEY_ICON_ROW, wb)

            gwRowY = gwRowY + GW_ROW_HEIGHT + GW_ROW_SPACING
        elseif wb.sep then
            wb.sep:Hide()
            wb.icon:Hide()
            wb.name:Hide()
            HideStatisticsRowSlot(wb)
        end

        -- Expand/collapse
        PaintStatisticsExpandToggle(goldCard, gw.toggle, "warbandWealth", goldHasOverflow, isGoldExpanded,
            #goldChars - GW_VISIBLE_ROWS, GW_BOTTOM_PAD)

        goldCard:Show()
        goldShown = true
        yOffset = yOffset + goldCardHeight + sectionGap
    end
    
    local MP_VISIBLE_ROWS = 5
    local MP_ROW_HEIGHT = 22
    local MP_ROW_SPACING = 1
    local MP_HEADER_AREA = 48        -- Space for icon + title at top
    local MP_TOGGLE_HEIGHT = 28      -- Height for expand/collapse button
    local MP_BOTTOM_PAD = 8
    
    -- Compact time format for rows (e.g., "2 Days 16 Hours")
    local function FormatPlayedCompact(seconds)
        local L = ns.L
        local dayS   = (L and L["PLAYED_DAYS"])    or "Days"
        local dayL   = (L and L["PLAYED_DAY"])     or "Day"
        local hourS  = (L and L["PLAYED_HOURS"])   or "Hours"
        local hourL  = (L and L["PLAYED_HOUR"])    or "Hour"
        local minS   = (L and L["PLAYED_MINUTES"]) or "Minutes"
        local minL   = (L and L["PLAYED_MINUTE"])  or "Minute"
        if not seconds or seconds <= 0 then return "0 " .. minS end
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        if days > 0 then
            return days .. " " .. (days == 1 and dayL or dayS) .. " " .. hours .. " " .. (hours == 1 and hourL or hourS)
        elseif hours > 0 then
            return hours .. " " .. (hours == 1 and hourL or hourS) .. " " .. minutes .. " " .. (minutes == 1 and minL or minS)
        else
            return math.max(minutes, 1) .. " " .. (minutes == 1 and minL or minS)
        end
    end

    -- Steam-style format (e.g., "1,234.5 Hours")
    local function FormatPlayedSteam(seconds)
        local L = ns.L
        local z = (L and L["STATS_PLAYED_STEAM_ZERO"]) or "0 Hours"
        local fFloat = (L and L["STATS_PLAYED_STEAM_FLOAT"]) or "%.1f Hours"
        local fThousand = (L and L["STATS_PLAYED_STEAM_THOUSAND"]) or "%d,%03d Hours"
        local fInt = (L and L["STATS_PLAYED_STEAM_INT"]) or "%d Hours"
        if not seconds or seconds <= 0 then return z end
        local hours = seconds / 3600
        if hours < 100 then
            return string.format(fFloat, hours)
        else
            local h = math.floor(hours + 0.5)
            if h >= 1000 then
                return string.format(fThousand, math.floor(h / 1000), h % 1000)
            else
                return string.format(fInt, h)
            end
        end
    end

    if not ns._statisticsExpandedStates then
        ns._statisticsExpandedStates = {}
    end
    local steamMode = ns._statisticsExpandedStates["mostPlayedSteamMode"] or false

    local function FormatPlayed(seconds)
        return steamMode and FormatPlayedSteam(seconds) or FormatPlayedCompact(seconds)
    end
    
    -- Collect ALL tracked characters, include those with 0 played time
    local playedChars = {}
    local totalPlayedSeconds = 0
    for i = 1, #allCharacters do
        local charData = allCharacters[i]
        if charData.isTracked then
            local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(charData)
            local played = charData.timePlayed or 0
            playedChars[#playedChars + 1] = {
                name = GetStatCharDisplayName(charData, charKey),
                classFile = charData.classFile,
                timePlayed = played,
            }
            totalPlayedSeconds = totalPlayedSeconds + played
        end
    end
    
    -- Sort by played time descending (0-time chars go to bottom)
    table.sort(playedChars, function(a, b)
        return a.timePlayed > b.timePlayed
    end)
    
    -- Only render card if there is data
    if #playedChars > 0 then
        -- Determine expand state
        local isExpanded = ns._statisticsExpandedStates["mostPlayed"] or false
        local visibleCount = isExpanded and #playedChars or math.min(#playedChars, MP_VISIBLE_ROWS)
        local hasOverflow = #playedChars > MP_VISIBLE_ROWS
        local toggleSpace = hasOverflow and MP_TOGGLE_HEIGHT or 0
        
        -- Calculate dynamic card height
        local rowsHeight = visibleCount * (MP_ROW_HEIGHT + MP_ROW_SPACING)
        local cardHeight = MP_HEADER_AREA + rowsHeight + toggleSpace + MP_BOTTOM_PAD
        
        -- Full-width card (not half). Cached per parent; chrome built once, content repainted.
        local mpCard = heavyBundle.mpCard
        local mp = heavyBundle.mpWidgets
        if not mpCard or not mp then
            mpCard = CreateCard(parent, cardHeight)
            if ApplyPanelCardChrome then ApplyPanelCardChrome(mpCard) end

            -- Header: Icon + "MOST PLAYED" at top-left
            local mpIcon = CreateIcon(mpCard, "Interface\\Icons\\Spell_Holy_BorrowedTime", 28, false, nil, true)
            mpIcon:SetPoint("TOPLEFT", mpCard, "TOPLEFT", 15, -10)
            mpIcon:Show()

            local mpTitle = FontManager:CreateFontString(mpCard, "subtitle", "OVERLAY")
            mpTitle:SetPoint("LEFT", mpIcon, "RIGHT", 10, 0)
            mpTitle:SetJustifyH("LEFT")

            -- Format toggle button (WoW <-> Steam); reads live state on click
            local fmtBtn = ns.UI.Factory:CreateButton(mpCard, 60, 20)
            fmtBtn:SetPoint("LEFT", mpTitle, "RIGHT", 10, 0)
            ns.UI.Factory:ApplyHighlight(fmtBtn)

            local fmtBtnLabel = FontManager:CreateFontString(fmtBtn, "body", "OVERLAY")
            fmtBtnLabel:SetPoint("CENTER")

            fmtBtn:SetScript("OnEnter", function()
                local ar, ag, ab = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
                fmtBtnLabel:SetTextColor(ar, ag, ab, 1)
            end)
            fmtBtn:SetScript("OnLeave", function()
                ns.UI_SetTextColorRole(fmtBtnLabel, "Normal")
            end)
            fmtBtn:SetScript("OnClick", function()
                ToggleStatisticsExpandState("mostPlayedSteamMode")
            end)

            -- Total played time at top-right (full format for header)
            local mpTotal = FontManager:CreateFontString(mpCard, "header", "OVERLAY")
            mpTotal:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, -24)
            mpTotal:SetJustifyH("RIGHT")

            mp = { title = mpTitle, fmtLabel = fmtBtnLabel, total = mpTotal, rows = {}, toggle = {} }
            heavyBundle.mpCard = mpCard
            heavyBundle.mpWidgets = mp
        end
        mpCard:SetParent(parent)
        mpCard:SetHeight(cardHeight)
        mpCard:ClearAllPoints()
        mpCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        mpCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)

        mp.title:SetText((ns.L and ns.L["MOST_PLAYED"]) or "MOST PLAYED")
        ns.UI_SetTextColorRole(mp.title, "Bright")
        mp.fmtLabel:SetText((ns.L and ns.L["FORMAT_BUTTON"]) or "Format")
        ns.UI_SetTextColorRole(mp.fmtLabel, "Normal")

        local totalFormatted = steamMode and FormatPlayedSteam(totalPlayedSeconds) or ns.Utilities:FormatPlayedTime(totalPlayedSeconds)
        mp.total:SetText(AccentHex() .. totalFormatted .. "|r")

        -- Character rows (pooled slots)
        local mpRows = mp.rows
        local rowYStart = MP_HEADER_AREA
        for i = 1, visibleCount do
            local charInfo = playedChars[i]
            local rowTop = -rowYStart
            local rowCenterY = rowTop - (MP_ROW_HEIGHT / 2)
            local slot = mpRows[i]
            if not slot then
                slot = {}
                mpRows[i] = slot
            end

            -- Alternating row background (both stripes - odd rows were invisible on pale cards)
            PaintStatisticsRowBg(mpCard, slot, i, rowTop, MP_ROW_HEIGHT)

            PaintStatisticsClassRow(mpCard, rowCenterY, MP_ROW_HEIGHT, charInfo.classFile, charInfo.name, -120, slot)

            -- Played time (right-aligned, compact format for rows)
            local timeText = slot.timeText
            if not timeText then
                timeText = FontManager:CreateFontString(mpCard, "body", "OVERLAY")
                timeText:SetJustifyH("RIGHT")
                slot.timeText = timeText
            end
            timeText:ClearAllPoints()
            timeText:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, rowCenterY)
            if charInfo.timePlayed > 0 then
                timeText:SetText(FormatPlayed(charInfo.timePlayed))
                ns.UI_SetTextColorRole(timeText, "Normal")
            else
                timeText:SetText(ThemeTextHex("Dim") .. "-|r")
            end
            timeText:Show()

            rowYStart = rowYStart + MP_ROW_HEIGHT + MP_ROW_SPACING
        end
        for i = visibleCount + 1, #mpRows do
            HideStatisticsRowSlot(mpRows[i])
        end

        -- Expand/Collapse (PlanCardFactory pattern: glues-characterSelect atlas)
        PaintStatisticsExpandToggle(mpCard, mp.toggle, "mostPlayed", hasOverflow, isExpanded,
            #playedChars - MP_VISIBLE_ROWS, MP_BOTTOM_PAD)

        mpCard:Show()
        mpShown = true
        yOffset = yOffset + cardHeight + sectionGap
    end

    local annexAnchor = (mpShown and heavyBundle.mpCard) or (goldShown and heavyBundle.goldCard) or nil
    if annexAnchor and ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(annexAnchor, parent, SIDE, 8)
    end

    return yOffset
    end -- PaintHeavyStatisticsBody

    if parent._preparedByPopulate and not parent._wnStatsHeavyDeferScheduled then
        parent._wnStatsHeavyDeferScheduled = true
        local deferParent = parent
        local deferMf = mf
        local deferStartY = yOffset
        C_Timer.After(0, function()
            deferParent._wnStatsHeavyDeferScheduled = nil
            if not deferMf or deferMf.currentTab ~= "stats" then return end
            local endY = PaintHeavyStatisticsBody(deferStartY)
            deferParent._wnStatsHeavyPaintDone = true
            if ns.UI_SyncMainTabScrollChrome then
                ns.UI_SyncMainTabScrollChrome(deferMf, deferParent, endY)
            end
        end)
        if ns.UI_SyncMainTabScrollChrome then
            ns.UI_SyncMainTabScrollChrome(mf, parent, yOffset)
        end
        return yOffset
    end

    yOffset = PaintHeavyStatisticsBody(yOffset)
    parent._wnStatsHeavyPaintDone = true
    return yOffset
end

--- Minimum scrollChild width where DrawStatistics keeps three collection cards abreast (~220px/card math).
--- Lower window width still works (two-row layout); this value enables horizontal scroll for that crisp layout.
--- See `MIN_STAT_CARD_W` in `:DrawStatistics` and `MAIN_SCROLL` in SharedWidgets.lua.
---@return number
function ns.ComputeStatisticsMinScrollWidth()
    local L = ns.UI_LAYOUT or {}
    local ms = L.MAIN_SCROLL or {}
    local w = ms.STATISTICS_MIN_SCROLL_CHILD_WIDTH_FOR_THREE_CARDS
    if type(w) == "number" and w > 0 then
        return w
    end
    return 740
end

if ns.UI_LayoutCoordinator then
    local LC = ns.UI_LayoutCoordinator
    LC:RegisterTabAdapter("stats", {
        OnViewportLayoutCommit = function(_scrollChild, _contentWidth, mf)
            if not mf or mf.currentTab ~= "stats" then return false end
            return false
        end,
    })
end

