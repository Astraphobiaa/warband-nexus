--[[
    Warband Nexus - Statistics Tab
    Display account-wide statistics: gold, collections, storage overview
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
    local function refreshStatsIfVisible()
        InvalidateStatsCache()

        if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab == "stats" then
            if self.SendMessage then
                self:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
            end
        end
    end

    -- Register for collection and character wealth update events
    -- NOTE: Uses StatisticsUIEvents as 'self' key to avoid overwriting other modules' handlers.
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.COLLECTION_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.MONEY_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.ITEMS_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.BAGS_UPDATED, refreshStatsIfVisible)
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.CHARACTER_UPDATED, function(_, payload)
        if payload and payload.dataType == "gold" then
            refreshStatsIfVisible()
        end
    end)
    
    -- Event listeners initialized (verbose logging removed)
end

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local FormatMoney = ns.UI_FormatMoney
local FormatNumber = ns.UI_FormatNumber
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

local function PaintStatisticsClassRow(parent, rowCenterY, rowH, classFile, charName, nameRightInset)
    local barH = rowH - 4
    local colorBar = (ns.UI_CreateClassColorStripe and ns.UI_CreateClassColorStripe(parent, parent, 15, rowCenterY, 3, barH, classFile))
    if not colorBar then
        colorBar = parent:CreateTexture(nil, "ARTWORK")
        colorBar:SetSize(3, barH)
        colorBar:SetPoint("LEFT", parent, "TOPLEFT", 15, rowCenterY)
        local cr, cg, cb = 0.8, 0.8, 0.8
        if ns.UI_GetClassColorForSurface and classFile then
            cr, cg, cb = ns.UI_GetClassColorForSurface(classFile)
        end
        colorBar:SetColorTexture(cr, cg, cb, 1)
    end
    local nameText = FontManager:CreateFontString(parent, "body", "OVERLAY")
    nameText:SetPoint("LEFT", colorBar, "RIGHT", 8, 0)
    nameText:SetPoint("RIGHT", parent, "RIGHT", nameRightInset or -120, 0)
    nameText:SetWordWrap(false)
    nameText:SetJustifyH("LEFT")
    if ns.UI_FormatClassColoredName then
        nameText:SetText(ns.UI_FormatClassColoredName(charName, classFile))
    else
        nameText:SetText(charName or "")
    end
    if FontManager and FontManager.ApplyFont then
        FontManager:ApplyFont(nameText, "body")
    end
    return nameText, colorBar
end

local STAT_CARD_H = 90
local STORAGE_CARD_H = 92

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
    park(b.goldCard)
    park(b.mpCard)
    b.goldCard = nil
    b.mpCard = nil
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
local BANK_STATS_CACHE_TTL = 3  -- short TTL: tab pool revisits skip slot tally rescans
local _bankStatsCache = nil

-- Invalidate cache so next DrawStatistics recomputes from API
-- (forward-declared above InitializeStatisticsUI so event callbacks can reference it)
InvalidateStatsCache = function()
    _statsCache = nil
    _bankStatsCache = nil
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
        }
    end
    _statsCache = {
        timestamp = now,
        achievementPoints = api.achievementPoints or 0,
        mounts = api.mounts or { collected = 0, total = 0 },
        pets = api.pets or { collected = 0, totalSpecies = 0, uniqueSpecies = 0, journalEntries = 0 },
        toys = api.toys or { collected = 0, total = 0 },
    }
    return _statsCache
end

local function GetCachedBankStatistics(addon)
    local now = GetTime()
    if _bankStatsCache and (now - _bankStatsCache.timestamp) < BANK_STATS_CACHE_TTL then
        return _bankStatsCache.stats
    end
    local stats = addon:GetBankStatistics()
    _bankStatsCache = { timestamp = now, stats = stats }
    return stats
end

--- Reposition cached Statistics fixedHeader title (Items/Collections parity — WN-PERF tab revisit).
local function RepositionStatisticsFixedHeader(hdrCache, headerParent, chrome, headerYOffset, SIDE)
    local titleCard = hdrCache.titleCard
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
        return ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    end
    return headerYOffset + (GetLayout().afterHeader or 72)
end

-- DRAW STATISTICS (Modern Design)

function WarbandNexus:DrawStatistics(parent)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local SIDE = metrics and metrics.sideMargin or SIDE_MARGIN
    local CARD_GAP_M = metrics and metrics.cardGap or (GetLayout().CARD_GAP or 10)
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

    -- Check for data availability
    local allCharacters = self:GetAllCharacters() or {}
    if #allCharacters == 0 then
        if parent._wnResultsAnnexSheet then parent._wnResultsAnnexSheet:Hide() end
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local _, height = CreateEmptyStateCard(parent, "statistics", headerYOffset)
        return headerYOffset + (height or 120)
    end

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
        subtitleText = (ns.L and ns.L["STATISTICS_SUBTITLE"]) or "Collection progress, gold, and storage overview",
        showUnderline = false,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", SIDE, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -SIDE, -headerYOffset)
    end

    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
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
    local sectionGap = (metrics and metrics.sectionGap) or CARD_GAP_M or 10
    local ApplyPanelCardChrome = ns.UI_ApplyStandardCardElevatedChrome

    -- Tab pool revisit: allow deferred heavy body on every PopulateContent pass (not only first visit).
    if parent._preparedByPopulate then
        parent._wnStatsHeavyPaintDone = false
    end

    -- Get statistics
    local stats = GetCachedBankStatistics(self)
    
    -- Use cached collection stats to avoid expensive API iteration on every redraw
    -- (mount/pet scanning is 1000+ API calls; cache is invalidated on real data changes)
    local collectionStats = GetCachedCollectionStats()
    
    local achievementPoints = collectionStats.achievementPoints
    local numCollectedMounts = collectionStats.mounts.collected
    local numTotalMounts = collectionStats.mounts.total
    local numCollectedPets = collectionStats.pets.collected
    local numTotalSpecies = collectionStats.pets.totalSpecies
    local numUniqueSpecies = collectionStats.pets.uniqueSpecies
    local numJournalEntries = collectionStats.pets.journalEntries
    local numCollectedToys = collectionStats.toys.collected
    local numTotalToys = collectionStats.toys.total
    
    -- Collection row: 3 cards (Mount, Pet, Toy). Wraps to 2 rows to avoid overflow in narrow windows.
    local leftMargin = SIDE
    local rightMargin = SIDE
    local cardSpacing = CARD_GAP_M
    local MIN_STAT_CARD_W = 220  -- Minimum width so the card shows without clipping
    local availableW = width - leftMargin - rightMargin
    local totalSpacing = cardSpacing * 2
    local threeCardWidth = (availableW - totalSpacing) / 3
    local useTwoRows = (threeCardWidth < MIN_STAT_CARD_W)
    local cardW, secondRowY
    if useTwoRows then
        cardW = (availableW - cardSpacing) / 2
        secondRowY = STAT_CARD_H + sectionGap
    else
        cardW = threeCardWidth
        secondRowY = nil
    end
    
    local accountWideLabel = (ns.L and ns.L["ACCOUNT_WIDE"]) or "Account-wide"
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local collLayoutSig = (useTwoRows and "2" or "3") .. ":" .. math.floor(cardW + 0.5)
    local collBundle = parent._wnStatsCollectionBundle
    local achCard, mountCard, petCard, toyCard

    local collectionRowY = yOffset + STAT_CARD_H + sectionGap

    if collBundle and collBundle.layoutSig == collLayoutSig and collBundle.achCard then
        achCard = collBundle.achCard
        mountCard = collBundle.mountCard
        petCard = collBundle.petCard
        toyCard = collBundle.toyCard
        achCard:SetParent(parent)
        achCard:ClearAllPoints()
        achCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        achCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        achCard:Show()
        if collBundle.achValue then
            collBundle.achValue:SetText(SemanticGoldHex() .. FormatNumber(achievementPoints) .. "|r")
        end
        mountCard:SetParent(parent)
        mountCard:ClearAllPoints()
        mountCard:SetWidth(cardW)
        mountCard:SetPoint("TOPLEFT", leftMargin, -collectionRowY)
        mountCard:Show()
        if collBundle.mountValue then
            collBundle.mountValue:SetText(SemanticInfoHex() .. FormatNumber(numCollectedMounts) .. "/" .. FormatNumber(numTotalMounts) .. " (" .. (numTotalMounts > 0 and math.floor(numCollectedMounts / numTotalMounts * 100) or 0) .. "%)|r")
        end
        petCard:SetParent(parent)
        petCard:ClearAllPoints()
        petCard:SetWidth(cardW)
        petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
        petCard:Show()
        if collBundle.bpValue then
            collBundle.bpValue:SetText(SemanticPetHex() .. FormatNumber(numCollectedPets) .. "/" .. FormatNumber(numJournalEntries) .. "|r")
        end
        if collBundle.upValue then
            collBundle.upValue:SetText(SemanticPetHex() .. FormatNumber(numUniqueSpecies) .. "/" .. FormatNumber(numTotalSpecies) .. "|r")
        end
        toyCard:SetParent(parent)
        toyCard:ClearAllPoints()
        if useTwoRows then
            toyCard:SetPoint("TOPLEFT", leftMargin, -(collectionRowY + secondRowY))
            toyCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightMargin, -(collectionRowY + secondRowY))
        else
            toyCard:SetWidth(cardW)
            toyCard:SetPoint("TOPLEFT", leftMargin + (cardW + cardSpacing) * 2, -collectionRowY)
        end
        toyCard:Show()
        if collBundle.toyValue then
            collBundle.toyValue:SetText(SemanticToyHex() .. FormatNumber(numCollectedToys) .. "/" .. FormatNumber(numTotalToys) .. " (" .. (numTotalToys > 0 and math.floor(numCollectedToys / numTotalToys * 100) or 0) .. "%)|r")
        end
    else
    -- Achievement Card (Account-wide since TWW) - Full width
    achCard = CreateCard(parent, STAT_CARD_H)
    achCard:SetPoint("TOPLEFT", SIDE, -yOffset)
    achCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)
    if ApplyPanelCardChrome then ApplyPanelCardChrome(achCard) end
    
    local achLayout = CreateCardHeaderLayout(
        achCard,
        "Interface\\Icons\\Achievement_General_StayClassy",
        36,
        false,
        (ns.L and ns.L["ACHIEVEMENT_POINTS"]) or "ACHIEVEMENT POINTS",
        SemanticGoldHex() .. FormatNumber(achievementPoints) .. "|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if achLayout.label then
        ns.UI_SetTextColorRole(achLayout.label, "Bright")
    end
    
    local achNote = FontManager:CreateFontString(achCard, "small", "OVERLAY")
    achNote:SetPoint("BOTTOMRIGHT", -10, 10)
    achNote:SetText(accountWideLabel)
    ns.UI_SetTextColorRole(achNote, "Bright") -- White
    
    achCard:Show()

    -- Mount Card (collection row)
    mountCard = CreateCard(parent, STAT_CARD_H)
    mountCard:SetWidth(cardW)
    mountCard:SetPoint("TOPLEFT", leftMargin, -collectionRowY)
    
    -- Use factory pattern for standardized card header layout
    local mountLayout = CreateCardHeaderLayout(
        mountCard,
        "Interface\\Icons\\Ability_Mount_RidingHorse",
        36,
        false,
        (ns.L and ns.L["MOUNTS_COLLECTED"]) or "MOUNTS COLLECTED",
        SemanticInfoHex() .. FormatNumber(numCollectedMounts) .. "/" .. FormatNumber(numTotalMounts) .. " (" .. (numTotalMounts > 0 and math.floor(numCollectedMounts / numTotalMounts * 100) or 0) .. "%)|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if mountLayout.label then
        ns.UI_SetTextColorRole(mountLayout.label, "Bright")
    end
    
    local mountNote = FontManager:CreateFontString(mountCard, "small", "OVERLAY")
    mountNote:SetPoint("BOTTOMRIGHT", -10, 10)
    mountNote:SetText(accountWideLabel)
    ns.UI_SetTextColorRole(mountNote, "Bright") -- White
    
    if ApplyPanelCardChrome then ApplyPanelCardChrome(mountCard) end
    mountCard:Show()

    -- Pet Card (collection row)
    petCard = CreateCard(parent, STAT_CARD_H)
    petCard:SetWidth(cardW)
    petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
    
    -- Single icon (left, vertically centered)
    local petIcon = CreateIcon(petCard, "Interface\\Icons\\INV_Box_PetCarrier_01", 36, false, nil, true)
    petIcon:SetPoint("CENTER", petCard, "LEFT", 15 + 18, 0)
    petIcon:Show()
    
    local textX = 15 + 36 + 12  -- left margin + icon + gap
    
    -- Two side-by-side columns, both vertically centered to icon center
    -- Left column: Battle Pets (label above icon center, value below)
    local bpLabel = FontManager:CreateFontString(petCard, "subtitle", "OVERLAY")
    bpLabel:SetPoint("BOTTOMLEFT", petIcon, "RIGHT", 10, 2)
    bpLabel:SetText((ns.L and ns.L["BATTLE_PETS"]) or "BATTLE PETS")
    ns.UI_SetTextColorRole(bpLabel, "Bright")
    bpLabel:SetJustifyH("LEFT")
    
    local bpValue = FontManager:CreateFontString(petCard, "header", "OVERLAY")
    bpValue:SetPoint("TOPLEFT", petIcon, "RIGHT", 10, -2)
    bpValue:SetText(SemanticPetHex() .. FormatNumber(numCollectedPets) .. "/" .. FormatNumber(numJournalEntries) .. "|r")
    bpValue:SetJustifyH("LEFT")
    
    -- Right column: Unique Pets â€” start after Battle Pets *value* (not only the label), or counts merge visually.
    local upLabel = FontManager:CreateFontString(petCard, "subtitle", "OVERLAY")
    upLabel:SetPoint("TOP", bpLabel, "TOP", 0, 0)
    upLabel:SetPoint("LEFT", bpValue, "RIGHT", 20, 0)
    upLabel:SetText((ns.L and ns.L["UNIQUE_PETS"]) or "UNIQUE PETS")
    ns.UI_SetTextColorRole(upLabel, "Bright")
    upLabel:SetJustifyH("LEFT")
    
    local upValue = FontManager:CreateFontString(petCard, "header", "OVERLAY")
    upValue:SetPoint("TOPLEFT", upLabel, "BOTTOMLEFT", 0, -4)
    upValue:SetText(SemanticPetHex() .. FormatNumber(numUniqueSpecies) .. "/" .. FormatNumber(numTotalSpecies) .. "|r")
    upValue:SetJustifyH("LEFT")
    
    local petNote = FontManager:CreateFontString(petCard, "small", "OVERLAY")
    petNote:SetPoint("BOTTOMRIGHT", -10, 8)
    petNote:SetText(accountWideLabel)
    ns.UI_SetTextColorRole(petNote, "Bright")
    
    if ApplyPanelCardChrome then ApplyPanelCardChrome(petCard) end
    petCard:Show()

    -- Toys Card: second row when narrow, same row when wide
    toyCard = CreateCard(parent, STAT_CARD_H)
    if useTwoRows then
        toyCard:SetPoint("TOPLEFT", leftMargin, -(collectionRowY + secondRowY))
        toyCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightMargin, -(collectionRowY + secondRowY))
    else
        toyCard:SetWidth(cardW)
        toyCard:SetPoint("TOPLEFT", leftMargin + (cardW + cardSpacing) * 2, -collectionRowY)
    end
    
    -- Use factory pattern for standardized card header layout
    local toyLayout = CreateCardHeaderLayout(
        toyCard,
        "Interface\\Icons\\INV_Misc_Toy_10",
        36,
        false,
        (ns.L and ns.L["CATEGORY_TOYS"]) or "TOYS",
        SemanticToyHex() .. FormatNumber(numCollectedToys) .. "/" .. FormatNumber(numTotalToys) .. " (" .. (numTotalToys > 0 and math.floor(numCollectedToys / numTotalToys * 100) or 0) .. "%)|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if toyLayout.label then
        ns.UI_SetTextColorRole(toyLayout.label, "Bright")
    end
    
    local toyNote = FontManager:CreateFontString(toyCard, "small", "OVERLAY")
    toyNote:SetPoint("BOTTOMRIGHT", -10, 10)
    toyNote:SetText(accountWideLabel)
    ns.UI_SetTextColorRole(toyNote, "Bright") -- White
    
    if ApplyPanelCardChrome then ApplyPanelCardChrome(toyCard) end
    toyCard:Show()

    parent._wnStatsCollectionBundle = {
        layoutSig = collLayoutSig,
        achCard = achCard,
        achValue = achLayout and achLayout.value,
        mountCard = mountCard,
        mountValue = mountLayout and mountLayout.value,
        petCard = petCard,
        bpValue = bpValue,
        upValue = upValue,
        toyCard = toyCard,
        toyValue = toyLayout and toyLayout.value,
    }
    end -- collection bundle create

    local collBlockH = STAT_CARD_H
    if useTwoRows then
        collBlockH = STAT_CARD_H + sectionGap + STAT_CARD_H
    end
    yOffset = yOffset + STAT_CARD_H + sectionGap + collBlockH + sectionGap

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
        
        local goldCard = CreateCard(parent, goldCardHeight)
        goldCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        goldCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        if ApplyPanelCardChrome then ApplyPanelCardChrome(goldCard) end
        
        local gwIcon = CreateIcon(goldCard, "BonusLoot-Chest", 28, true, nil, true)
        gwIcon:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 15, -10)
        gwIcon:Show()
        
        local gwTitle = FontManager:CreateFontString(goldCard, "subtitle", "OVERLAY")
        gwTitle:SetPoint("LEFT", gwIcon, "RIGHT", 10, 0)
        gwTitle:SetText((ns.L and ns.L["WARBAND_WEALTH"]) or "WARBAND WEALTH")
        ns.UI_SetTextColorRole(gwTitle, "Bright")
        gwTitle:SetJustifyH("LEFT")
        
        local gwTotal = FontManager:CreateFontString(goldCard, "header", "OVERLAY")
        gwTotal:SetPoint("RIGHT", goldCard, "TOPRIGHT", -15, -24)
        gwTotal:SetText(FormatMoney(grandTotalCopper, 14))
        gwTotal:SetJustifyH("RIGHT")
        
        local gwRowY = GW_HEADER_AREA
        local maxCopper = goldChars[1] and goldChars[1].copper or 1
        if maxCopper <= 0 then maxCopper = 1 end
        
        for i = 1, goldVisibleCount do
            local charInfo = goldChars[i]
            local rowTop = -gwRowY
            local rowCenterY = rowTop - (GW_ROW_HEIGHT / 2)
            
            local rowBg = goldCard:CreateTexture(nil, "BACKGROUND", nil, 1)
            rowBg:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 10, rowTop)
            rowBg:SetPoint("TOPRIGHT", goldCard, "TOPRIGHT", -10, rowTop)
            rowBg:SetHeight(GW_ROW_HEIGHT)
            local stripe = (i % 2 == 0) and (COLORS.surfaceRowEven or COLORS.bgLight)
                or (COLORS.surfaceRowOdd or COLORS.bg)
            stripe = stripe or { 0.768, 0.760, 0.744, 0.98 }
            rowBg:SetColorTexture(stripe[1], stripe[2], stripe[3], stripe[4] or 0.98)
            
            PaintStatisticsClassRow(goldCard, rowCenterY, GW_ROW_HEIGHT, charInfo.classFile, charInfo.name, -160)
            
            local goldText = FontManager:CreateFontString(goldCard, "body", "OVERLAY")
            goldText:SetPoint("RIGHT", goldCard, "TOPRIGHT", -15, rowCenterY)
            if charInfo.copper > 0 then
                goldText:SetText(FormatMoney(charInfo.copper, 12))
            else
                goldText:SetText(ThemeTextHex("Dim") .. "-|r")
            end
            goldText:SetJustifyH("RIGHT")
            
            gwRowY = gwRowY + GW_ROW_HEIGHT + GW_ROW_SPACING
        end
        
        -- Warband bank row (distinct style)
        if warbandBankCopper > 0 then
            local rowTop = -gwRowY
            local rowCenterY = rowTop - (GW_ROW_HEIGHT / 2)
            
            local wbSep = goldCard:CreateTexture(nil, "ARTWORK")
            wbSep:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 15, rowTop)
            wbSep:SetPoint("TOPRIGHT", goldCard, "TOPRIGHT", -15, rowTop)
            wbSep:SetHeight(1)
            wbSep:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
            
            local wbIcon = goldCard:CreateTexture(nil, "ARTWORK")
            wbIcon:SetSize(16, 16)
            wbIcon:SetPoint("LEFT", goldCard, "TOPLEFT", 18, rowCenterY)
            wbIcon:SetAtlas("warbands-icon")
            
            local wbName = FontManager:CreateFontString(goldCard, "body", "OVERLAY")
            wbName:SetPoint("LEFT", wbIcon, "RIGHT", 6, 0)
            wbName:SetText(SemanticInfoHex() .. ((ns.L and ns.L["WARBAND_BANK"]) or "Warband Bank") .. "|r")
            wbName:SetJustifyH("LEFT")
            
            local wbGold = FontManager:CreateFontString(goldCard, "body", "OVERLAY")
            wbGold:SetPoint("RIGHT", goldCard, "TOPRIGHT", -15, rowCenterY)
            wbGold:SetText(FormatMoney(warbandBankCopper, 12))
            wbGold:SetJustifyH("RIGHT")
            
            gwRowY = gwRowY + GW_ROW_HEIGHT + GW_ROW_SPACING
        end
        
        -- Expand/collapse
        if goldHasOverflow then
            local hiddenCount = #goldChars - GW_VISIBLE_ROWS
            
            local expandBtn = ns.UI.Factory:CreateButton(goldCard, 20, 20, true)
            expandBtn:SetPoint("BOTTOMRIGHT", goldCard, "BOTTOMRIGHT", -10, GW_BOTTOM_PAD)
            expandBtn:EnableMouse(true)
            
            local arrowTex = expandBtn:CreateTexture(nil, "OVERLAY")
            arrowTex:SetAllPoints(expandBtn)
            if isGoldExpanded then
                arrowTex:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
            else
                arrowTex:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
            end
            
            expandBtn:SetScript("OnClick", function()
                ns._statisticsExpandedStates["warbandWealth"] = not isGoldExpanded
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
            end)
            
            if not isGoldExpanded then
                local moreText = FontManager:CreateFontString(goldCard, "small", "OVERLAY")
                moreText:SetPoint("RIGHT", expandBtn, "LEFT", -4, 0)
                moreText:SetJustifyH("RIGHT")
                local moreLabel = hiddenCount > 1
                    and ((ns.L and ns.L["MORE_CHARACTERS_PLURAL"]) or "more characters")
                    or ((ns.L and ns.L["MORE_CHARACTERS"]) or "more character")
                moreText:SetText(ThemeTextHex("Muted") .. hiddenCount .. " " .. moreLabel .. "|r")
            end
        end
        
        if goldHasOverflow then
            goldCard:EnableMouse(true)
            goldCard:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then
                    ns._statisticsExpandedStates["warbandWealth"] = not isGoldExpanded
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
                end
            end)
        end
        
        goldCard:Show()
        heavyBundle.goldCard = goldCard
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
        
        -- Full-width card (not half)
        local mpCard = CreateCard(parent, cardHeight)
        mpCard:SetPoint("TOPLEFT", SIDE, -yOffset)
        mpCard:SetPoint("TOPRIGHT", -SIDE, -yOffset)
        if ApplyPanelCardChrome then ApplyPanelCardChrome(mpCard) end

        -- â”€â”€ Header: Icon + "MOST PLAYED" at top-left â”€â”€
        local mpIcon = CreateIcon(mpCard, "Interface\\Icons\\Spell_Holy_BorrowedTime", 28, false, nil, true)
        mpIcon:SetPoint("TOPLEFT", mpCard, "TOPLEFT", 15, -10)
        mpIcon:Show()
        
        local mpTitle = FontManager:CreateFontString(mpCard, "subtitle", "OVERLAY")
        mpTitle:SetPoint("LEFT", mpIcon, "RIGHT", 10, 0)
        mpTitle:SetText((ns.L and ns.L["MOST_PLAYED"]) or "MOST PLAYED")
        ns.UI_SetTextColorRole(mpTitle, "Bright")
        mpTitle:SetJustifyH("LEFT")

        -- â”€â”€ Format toggle button (WoW â†” Steam) â”€â”€
        local fmtBtn = ns.UI.Factory:CreateButton(mpCard, 60, 20)
        fmtBtn:SetPoint("LEFT", mpTitle, "RIGHT", 10, 0)
        ns.UI.Factory:ApplyHighlight(fmtBtn)

        local fmtBtnLabel = FontManager:CreateFontString(fmtBtn, "body", "OVERLAY")
        fmtBtnLabel:SetPoint("CENTER")
        fmtBtnLabel:SetText((ns.L and ns.L["FORMAT_BUTTON"]) or "Format")
        ns.UI_SetTextColorRole(fmtBtnLabel, "Normal")

        fmtBtn:SetScript("OnEnter", function()
            local ar, ag, ab = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
            fmtBtnLabel:SetTextColor(ar, ag, ab, 1)
        end)
        fmtBtn:SetScript("OnLeave", function()
            ns.UI_SetTextColorRole(fmtBtnLabel, "Normal")
        end)
        fmtBtn:SetScript("OnClick", function()
            ns._statisticsExpandedStates["mostPlayedSteamMode"] = not steamMode
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
        end)

        -- â”€â”€ Total played time at top-right (full format for header) â”€â”€
        local mpTotal = FontManager:CreateFontString(mpCard, "header", "OVERLAY")
        mpTotal:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, -24)
        local totalFormatted = steamMode and FormatPlayedSteam(totalPlayedSeconds) or ns.Utilities:FormatPlayedTime(totalPlayedSeconds)
        mpTotal:SetText(AccentHex() .. totalFormatted .. "|r")
        mpTotal:SetJustifyH("RIGHT")
        
        -- â”€â”€ Character rows â”€â”€
        local rowYStart = MP_HEADER_AREA
        for i = 1, visibleCount do
            local charInfo = playedChars[i]
            local rowTop = -rowYStart
            local rowCenterY = rowTop - (MP_ROW_HEIGHT / 2)
            
            -- Alternating row background (both stripes — odd rows were invisible on pale cards)
            local rowBg = mpCard:CreateTexture(nil, "BACKGROUND", nil, 1)
            rowBg:SetPoint("TOPLEFT", mpCard, "TOPLEFT", 10, rowTop)
            rowBg:SetPoint("TOPRIGHT", mpCard, "TOPRIGHT", -10, rowTop)
            rowBg:SetHeight(MP_ROW_HEIGHT)
            local stripe = (i % 2 == 0) and (COLORS.surfaceRowEven or COLORS.bgLight)
                or (COLORS.surfaceRowOdd or COLORS.bg)
            stripe = stripe or { 0.768, 0.760, 0.744, 0.98 }
            rowBg:SetColorTexture(stripe[1], stripe[2], stripe[3], stripe[4] or 0.98)
            
            PaintStatisticsClassRow(mpCard, rowCenterY, MP_ROW_HEIGHT, charInfo.classFile, charInfo.name, -120)
            
            -- Played time (right-aligned, compact format for rows)
            local timeText = FontManager:CreateFontString(mpCard, "body", "OVERLAY")
            timeText:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, rowCenterY)
            if charInfo.timePlayed > 0 then
                timeText:SetText(FormatPlayed(charInfo.timePlayed))
                ns.UI_SetTextColorRole(timeText, "Normal")
            else
                timeText:SetText(ThemeTextHex("Dim") .. "-|r")
            end
            timeText:SetJustifyH("RIGHT")
            
            rowYStart = rowYStart + MP_ROW_HEIGHT + MP_ROW_SPACING
        end
        
        -- â”€â”€ Expand/Collapse (PlanCardFactory pattern: glues-characterSelect atlas) â”€â”€
        if hasOverflow then
            local hiddenCount = #playedChars - MP_VISIBLE_ROWS
            
            -- Arrow button first (anchor point for text)
            local expandBtn = ns.UI.Factory:CreateButton(mpCard, 20, 20, true)
            expandBtn:SetPoint("BOTTOMRIGHT", mpCard, "BOTTOMRIGHT", -10, MP_BOTTOM_PAD)
            expandBtn:EnableMouse(true)
            
            local arrowTex = expandBtn:CreateTexture(nil, "OVERLAY")
            arrowTex:SetAllPoints(expandBtn)
            if isExpanded then
                arrowTex:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover", false)
            else
                arrowTex:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover", false)
            end
            
            expandBtn:SetScript("OnClick", function()
                ns._statisticsExpandedStates["mostPlayed"] = not isExpanded
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
            end)
            
            -- "X more characters" text anchored to button (vertically centered)
            if not isExpanded then
                local moreText = FontManager:CreateFontString(mpCard, "small", "OVERLAY")
                moreText:SetPoint("RIGHT", expandBtn, "LEFT", -4, 0)
                moreText:SetJustifyH("RIGHT")
                local moreLabel = hiddenCount > 1
                    and ((ns.L and ns.L["MORE_CHARACTERS_PLURAL"]) or "more characters")
                    or ((ns.L and ns.L["MORE_CHARACTERS"]) or "more character")
                moreText:SetText(ThemeTextHex("Muted") .. hiddenCount .. " " .. moreLabel .. "|r")
            end
        end
        
        -- Make entire card clickable for expand/collapse
        if hasOverflow then
            mpCard:EnableMouse(true)
            mpCard:SetScript("OnMouseDown", function(self, button)
                if button == "LeftButton" then
                    ns._statisticsExpandedStates["mostPlayed"] = not isExpanded
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
                end
            end)
        end
        
        mpCard:Show()
        heavyBundle.mpCard = mpCard
        yOffset = yOffset + cardHeight + sectionGap
    end
    
    local wb = stats.warband or {}
    local pb = stats.personal or {}
    local freeSlots = (wb.freeSlots or 0) + (pb.freeSlots or 0)
    local itemCount = (wb.itemCount or 0) + (pb.itemCount or 0)

    local storageCard = heavyBundle.storageCard
    if not storageCard then
        storageCard = CreateCard(parent, STORAGE_CARD_H)
        heavyBundle.storageCard = storageCard
        if ApplyPanelCardChrome then ApplyPanelCardChrome(storageCard) end
        local stTitle = FontManager:CreateFontString(storageCard, "title", "OVERLAY")
        stTitle:SetPoint("TOPLEFT", 15, -10)
        stTitle:SetText(AccentHex() .. ((ns.L and ns.L["STORAGE_OVERVIEW"]) or "Storage Overview") .. "|r")
        heavyBundle.storageTitle = stTitle
        heavyBundle.storageCols = {}
        local colDefs = {
            { labelKey = "WARBAND_SLOTS", fallback = "Warband Slots" },
            { labelKey = "PERSONAL_SLOTS", fallback = "Personal Slots" },
            { labelKey = "TOTAL_FREE", fallback = "Total Free", valueGreen = true },
            { labelKey = "TOTAL_ITEMS", fallback = "Total Items" },
        }
        for ci = 1, 4 do
            local def = colDefs[ci]
            local lbl = FontManager:CreateFontString(storageCard, "small", "OVERLAY")
            lbl:SetJustifyH("LEFT")
            local val = FontManager:CreateFontString(storageCard, "title", "OVERLAY")
            val:SetJustifyH("LEFT")
            heavyBundle.storageCols[ci] = {
                label = lbl,
                value = val,
                labelKey = def.labelKey,
                fallback = def.fallback,
                valueGreen = def.valueGreen,
            }
        end
    end
    storageCard:SetParent(parent)
    storageCard:ClearAllPoints()
    storageCard:SetPoint("TOPLEFT", SIDE, -yOffset)
    storageCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE, -yOffset)
    storageCard:SetHeight(STORAGE_CARD_H)
    storageCard:Show()

    local cardWidth = storageCard:GetWidth() or 600
    local padX, padTop, gridGap = 15, 36, 14
    local useGrid2x2 = cardWidth < 520
    local colW = useGrid2x2 and math.floor((cardWidth - padX * 2 - gridGap) / 2)
        or math.floor((cardWidth - padX * 2) / 4)
    local statValues = {
        FormatNumber(wb.usedSlots or 0) .. "/" .. FormatNumber(wb.totalSlots or 0),
        FormatNumber(pb.usedSlots or 0) .. "/" .. FormatNumber(pb.totalSlots or 0),
        FormatNumber(freeSlots),
        FormatNumber(itemCount),
    }
    local gr, gg, gb = SemanticGreenRGB()
    for ci = 1, 4 do
        local col = heavyBundle.storageCols[ci]
        local gridRow = useGrid2x2 and math.floor((ci - 1) / 2) or 0
        local gridCol = useGrid2x2 and ((ci - 1) % 2) or (ci - 1)
        local x = padX + gridCol * (colW + gridGap)
        local y = -(padTop + gridRow * 34)
        col.label:ClearAllPoints()
        col.label:SetPoint("TOPLEFT", storageCard, "TOPLEFT", x, y)
        col.label:SetWidth(colW)
        col.label:SetText((ns.L and ns.L[col.labelKey]) or col.fallback)
        ns.UI_SetTextColorRole(col.label, "Normal")
        col.value:ClearAllPoints()
        col.value:SetPoint("TOPLEFT", col.label, "BOTTOMLEFT", 0, -2)
        col.value:SetWidth(colW)
        col.value:SetText(statValues[ci])
        if col.valueGreen then
            col.value:SetTextColor(gr, gg, gb)
        else
            ns.UI_SetTextColorRole(col.value, "Bright")
        end
        col.label:Show()
        col.value:Show()
    end

    yOffset = yOffset + STORAGE_CARD_H + sectionGap

    if ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(storageCard, parent, SIDE, 8)
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

