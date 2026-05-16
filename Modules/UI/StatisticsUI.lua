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
    -- Register for collection update events
    -- NOTE: Uses StatisticsUIEvents as 'self' key to avoid overwriting other modules' handlers.
    WarbandNexus.RegisterMessage(StatisticsUIEvents, E.COLLECTION_UPDATED, function()
        InvalidateStatsCache()

        if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab == "stats" then
            if self.SendMessage then
                self:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
            end
        end
    end)
    
    -- CHARACTER_UPDATED refresh is centralized in UI.lua for stats tab.
    
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

--============================================================================
-- COLLECTION STATS CACHE
-- Mount/Pet/Toy iteration is extremely expensive (1000+ API calls per frame).
-- Cache results with a short TTL so visual-only operations like expand/collapse
-- don't re-run thousands of synchronous WoW API calls.
--============================================================================
local STATS_CACHE_TTL = 60  -- seconds before cache is considered stale (invalidated on WN_COLLECTION_UPDATED)
local _statsCache = nil     -- { mounts={}, pets={}, toys={}, achievements={}, timestamp=number }

-- Invalidate cache so next DrawStatistics recomputes from API
-- (forward-declared above InitializeStatisticsUI so event callbacks can reference it)
InvalidateStatsCache = function()
    _statsCache = nil
end

-- Compute and cache collection statistics (single source: CollectionService GetCollectionCountsFromAPI)
local function GetCachedCollectionStats()
    local now = GetTime()
    if _statsCache and (now - _statsCache.timestamp) < STATS_CACHE_TTL then
        return _statsCache
    end
    local api = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
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

--============================================================================
-- DRAW STATISTICS (Modern Design)
--============================================================================

function WarbandNexus:DrawStatistics(parent)
    local width = parent:GetWidth() - 20
    local cardWidth = (width - 15) / 2

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8

    -- Hide previous empty state
    HideEmptyStateCard(parent, "statistics")

    -- Check for data availability
    local characters = self.db and self.db.global and self.db.global.characters
    if not characters or not next(characters) then
        if parent._wnResultsAnnexSheet then parent._wnResultsAnnexSheet:Hide() end
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local _, height = CreateEmptyStateCard(parent, "statistics", headerYOffset)
        return headerYOffset + (height or 120)
    end

    -- ===== HEADER CARD (in fixedHeader - non-scrolling) — Characters-tab layout =====
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "statistics",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["ACCOUNT_STATISTICS"]) or "Account Statistics") .. "|r",
        subtitleText = (ns.L and ns.L["STATISTICS_SUBTITLE"]) or "Collection progress, gold, and storage overview",
    }))
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    titleCard:Show()
    headerYOffset = headerYOffset + (GetLayout().afterHeader or 75)

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = 8

    -- Get statistics
    local stats = self:GetBankStatistics()
    
    -- ===== PLAYER STATS CARDS =====
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
    
    -- Collection row: 3 cards (Mount, Pet, Toy). Dar pencerede taşmayı önlemek için 2 satıra geçer.
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local MIN_STAT_CARD_W = 220  -- Kartın kesilmeden görünmesi için minimum genişlik
    local availableW = width - leftMargin - rightMargin
    local totalSpacing = cardSpacing * 2
    local threeCardWidth = (availableW - totalSpacing) / 3
    local useTwoRows = (threeCardWidth < MIN_STAT_CARD_W)
    local cardW, secondRowY
    if useTwoRows then
        -- İlk satır: Mount + Pet yan yana; ikinci satır: Toy tam genişlik (taşma yok)
        cardW = (availableW - cardSpacing) / 2
        secondRowY = 100  -- ilk satır yüksekliği
    else
        cardW = threeCardWidth
        secondRowY = nil
    end
    
    -- Achievement Card (Account-wide since TWW) - Full width
    local achCard = CreateCard(parent, 90)
    achCard:SetPoint("TOPLEFT", 10, -yOffset)
    achCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Use factory pattern for standardized card header layout
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local achLayout = CreateCardHeaderLayout(
        achCard,
        "Interface\\Icons\\Achievement_General_StayClassy",
        36,
        false,
        (ns.L and ns.L["ACHIEVEMENT_POINTS"]) or "ACHIEVEMENT POINTS",
        "|cffffcc00" .. FormatNumber(achievementPoints) .. "|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if achLayout.label then
        achLayout.label:SetTextColor(1, 1, 1)
    end
    
    local accountWideLabel = (ns.L and ns.L["ACCOUNT_WIDE"]) or "Account-wide"
    
    local achNote = FontManager:CreateFontString(achCard, "small", "OVERLAY")
    achNote:SetPoint("BOTTOMRIGHT", -10, 10)
    achNote:SetText(accountWideLabel)
    achNote:SetTextColor(1, 1, 1)  -- White
    
    achCard:Show()

    yOffset = yOffset + 100
    
    -- Mount Card (collection row)
    local mountCard = CreateCard(parent, 90)
    mountCard:SetWidth(cardW)
    mountCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    -- Use factory pattern for standardized card header layout
    local mountLayout = CreateCardHeaderLayout(
        mountCard,
        "Interface\\Icons\\Ability_Mount_RidingHorse",
        36,
        false,
        (ns.L and ns.L["MOUNTS_COLLECTED"]) or "MOUNTS COLLECTED",
        "|cff0099ff" .. FormatNumber(numCollectedMounts) .. "/" .. FormatNumber(numTotalMounts) .. " (" .. (numTotalMounts > 0 and math.floor(numCollectedMounts / numTotalMounts * 100) or 0) .. "%)|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if mountLayout.label then
        mountLayout.label:SetTextColor(1, 1, 1)
    end
    
    local mountNote = FontManager:CreateFontString(mountCard, "small", "OVERLAY")
    mountNote:SetPoint("BOTTOMRIGHT", -10, 10)
    mountNote:SetText(accountWideLabel)
    mountNote:SetTextColor(1, 1, 1)  -- White
    
    mountCard:Show()

    -- Pet Card (collection row)
    local petCard = CreateCard(parent, 90)
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
    bpLabel:SetTextColor(1, 1, 1)
    bpLabel:SetJustifyH("LEFT")
    
    local bpValue = FontManager:CreateFontString(petCard, "header", "OVERLAY")
    bpValue:SetPoint("TOPLEFT", petIcon, "RIGHT", 10, -2)
    bpValue:SetText("|cffff69b4" .. FormatNumber(numCollectedPets) .. "/" .. FormatNumber(numJournalEntries) .. "|r")
    bpValue:SetJustifyH("LEFT")
    
    -- Right column: Unique Pets — start after Battle Pets *value* (not only the label), or counts merge visually.
    local upLabel = FontManager:CreateFontString(petCard, "subtitle", "OVERLAY")
    upLabel:SetPoint("TOP", bpLabel, "TOP", 0, 0)
    upLabel:SetPoint("LEFT", bpValue, "RIGHT", 20, 0)
    upLabel:SetText((ns.L and ns.L["UNIQUE_PETS"]) or "UNIQUE PETS")
    upLabel:SetTextColor(1, 1, 1)
    upLabel:SetJustifyH("LEFT")
    
    local upValue = FontManager:CreateFontString(petCard, "header", "OVERLAY")
    upValue:SetPoint("TOPLEFT", upLabel, "BOTTOMLEFT", 0, -4)
    upValue:SetText("|cffff69b4" .. FormatNumber(numUniqueSpecies) .. "/" .. FormatNumber(numTotalSpecies) .. "|r")
    upValue:SetJustifyH("LEFT")
    
    local petNote = FontManager:CreateFontString(petCard, "small", "OVERLAY")
    petNote:SetPoint("BOTTOMRIGHT", -10, 8)
    petNote:SetText(accountWideLabel)
    petNote:SetTextColor(1, 1, 1)
    
    petCard:Show()

    -- Toys Card: dar alanda ikinci satırda, geniş alanda aynı satırda
    local toyCard = CreateCard(parent, 90)
    if useTwoRows then
        toyCard:SetPoint("TOPLEFT", leftMargin, -(yOffset + secondRowY))
        toyCard:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightMargin, -(yOffset + secondRowY))
    else
        toyCard:SetWidth(cardW)
        toyCard:SetPoint("LEFT", petCard, "RIGHT", cardSpacing, 0)
        toyCard:SetPoint("RIGHT", parent, "RIGHT", -rightMargin, 0)
    end
    
    -- Use factory pattern for standardized card header layout
    local toyLayout = CreateCardHeaderLayout(
        toyCard,
        "Interface\\Icons\\INV_Misc_Toy_10",
        36,
        false,
        (ns.L and ns.L["CATEGORY_TOYS"]) or "TOYS",
        "|cffff66ff" .. FormatNumber(numCollectedToys) .. "/" .. FormatNumber(numTotalToys) .. " (" .. (numTotalToys > 0 and math.floor(numCollectedToys / numTotalToys * 100) or 0) .. "%)|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if toyLayout.label then
        toyLayout.label:SetTextColor(1, 1, 1)
    end
    
    local toyNote = FontManager:CreateFontString(toyCard, "small", "OVERLAY")
    toyNote:SetPoint("BOTTOMRIGHT", -10, 10)
    toyNote:SetText(accountWideLabel)
    toyNote:SetTextColor(1, 1, 1)  -- White
    
    toyCard:Show()

    yOffset = yOffset + (useTwoRows and 200 or 100)  -- 2 satırda 200, tek satırda 100
    
    -- ===== WARBAND WEALTH =====
    local GW_VISIBLE_ROWS = 5
    local GW_ROW_HEIGHT = 22
    local GW_ROW_SPACING = 1
    local GW_HEADER_AREA = 48
    local GW_TOGGLE_HEIGHT = 28
    local GW_BOTTOM_PAD = 8
    
    local goldChars = {}
    local totalCharCopper = 0
    for charKey, charData in pairs(characters) do
        if charData.isTracked then
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
        goldCard:SetPoint("TOPLEFT", 10, -yOffset)
        goldCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        local gwIcon = CreateIcon(goldCard, "BonusLoot-Chest", 28, true, nil, true)
        gwIcon:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 15, -10)
        gwIcon:Show()
        
        local gwTitle = FontManager:CreateFontString(goldCard, "subtitle", "OVERLAY")
        gwTitle:SetPoint("LEFT", gwIcon, "RIGHT", 10, 0)
        gwTitle:SetText((ns.L and ns.L["WARBAND_WEALTH"]) or "WARBAND WEALTH")
        gwTitle:SetTextColor(1, 1, 1)
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
            
            if i % 2 == 0 then
                local rowBg = goldCard:CreateTexture(nil, "BACKGROUND", nil, 1)
                rowBg:SetPoint("TOPLEFT", goldCard, "TOPLEFT", 10, rowTop)
                rowBg:SetPoint("TOPRIGHT", goldCard, "TOPRIGHT", -10, rowTop)
                rowBg:SetHeight(GW_ROW_HEIGHT)
                rowBg:SetColorTexture(1, 1, 1, 0.03)
            end
            
            local classR, classG, classB = 0.8, 0.8, 0.8
            if charInfo.classFile then
                local cr, cg, cb = GetClassColor(charInfo.classFile)
                if cr then classR, classG, classB = cr, cg, cb end
            end
            
            local colorBar = goldCard:CreateTexture(nil, "ARTWORK")
            colorBar:SetSize(3, GW_ROW_HEIGHT - 4)
            colorBar:SetPoint("LEFT", goldCard, "TOPLEFT", 15, rowCenterY)
            colorBar:SetColorTexture(classR, classG, classB, 1)
            
            local nameText = FontManager:CreateFontString(goldCard, "body", "OVERLAY")
            nameText:SetPoint("LEFT", colorBar, "RIGHT", 8, 0)
            nameText:SetPoint("RIGHT", goldCard, "RIGHT", -160, 0)
            nameText:SetWordWrap(false)
            local hexClass = format("%02x%02x%02x", classR * 255, classG * 255, classB * 255)
            nameText:SetText("|cff" .. hexClass .. charInfo.name .. "|r")
            nameText:SetJustifyH("LEFT")
            
            local goldText = FontManager:CreateFontString(goldCard, "body", "OVERLAY")
            goldText:SetPoint("RIGHT", goldCard, "TOPRIGHT", -15, rowCenterY)
            if charInfo.copper > 0 then
                goldText:SetText(FormatMoney(charInfo.copper, 12))
            else
                goldText:SetText("|cff555555—|r")
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
            wbName:SetText("|cff66c0ff" .. ((ns.L and ns.L["WARBAND_BANK"]) or "Warband Bank") .. "|r")
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
                moreText:SetText("|cff888888" .. hiddenCount .. " " .. moreLabel .. "|r")
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
        yOffset = yOffset + goldCardHeight + 10
    end
    
    -- ===== MOST PLAYED CARD =====
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
    for charKey, charData in pairs(characters) do
        if charData.isTracked then
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
        mpCard:SetPoint("TOPLEFT", 10, -yOffset)
        mpCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        -- ── Header: Icon + "MOST PLAYED" at top-left ──
        local mpIcon = CreateIcon(mpCard, "Interface\\Icons\\Spell_Holy_BorrowedTime", 28, false, nil, true)
        mpIcon:SetPoint("TOPLEFT", mpCard, "TOPLEFT", 15, -10)
        mpIcon:Show()
        
        local mpTitle = FontManager:CreateFontString(mpCard, "subtitle", "OVERLAY")
        mpTitle:SetPoint("LEFT", mpIcon, "RIGHT", 10, 0)
        mpTitle:SetText((ns.L and ns.L["MOST_PLAYED"]) or "MOST PLAYED")
        mpTitle:SetTextColor(1, 1, 1)
        mpTitle:SetJustifyH("LEFT")

        -- ── Format toggle button (WoW ↔ Steam) ──
        local fmtBtn = ns.UI.Factory:CreateButton(mpCard, 60, 20)
        fmtBtn:SetPoint("LEFT", mpTitle, "RIGHT", 10, 0)
        ns.UI.Factory:ApplyHighlight(fmtBtn)

        local fmtBtnLabel = FontManager:CreateFontString(fmtBtn, "body", "OVERLAY")
        fmtBtnLabel:SetPoint("CENTER")
        fmtBtnLabel:SetText((ns.L and ns.L["FORMAT_BUTTON"]) or "Format")
        fmtBtnLabel:SetTextColor(0.85, 0.85, 0.85)

        fmtBtn:SetScript("OnEnter", function()
            fmtBtnLabel:SetTextColor(0.6, 0.9, 1)
        end)
        fmtBtn:SetScript("OnLeave", function()
            fmtBtnLabel:SetTextColor(0.85, 0.85, 0.85)
        end)
        fmtBtn:SetScript("OnClick", function()
            ns._statisticsExpandedStates["mostPlayedSteamMode"] = not steamMode
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "stats", skipCooldown = true })
        end)

        -- ── Total played time at top-right (full format for header) ──
        local mpTotal = FontManager:CreateFontString(mpCard, "header", "OVERLAY")
        mpTotal:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, -24)
        local totalFormatted = steamMode and FormatPlayedSteam(totalPlayedSeconds) or ns.Utilities:FormatPlayedTime(totalPlayedSeconds)
        mpTotal:SetText("|cff00ccff" .. totalFormatted .. "|r")
        mpTotal:SetJustifyH("RIGHT")
        
        -- ── Character rows ──
        local rowYStart = MP_HEADER_AREA
        for i = 1, visibleCount do
            local charInfo = playedChars[i]
            local rowTop = -rowYStart
            local rowCenterY = rowTop - (MP_ROW_HEIGHT / 2)
            
            -- Alternating row background
            if i % 2 == 0 then
                local rowBg = mpCard:CreateTexture(nil, "BACKGROUND", nil, 1)
                rowBg:SetPoint("TOPLEFT", mpCard, "TOPLEFT", 10, rowTop)
                rowBg:SetPoint("TOPRIGHT", mpCard, "TOPRIGHT", -10, rowTop)
                rowBg:SetHeight(MP_ROW_HEIGHT)
                rowBg:SetColorTexture(1, 1, 1, 0.03)
            end
            
            -- Class color bar (3px wide vertical line)
            local classR, classG, classB = 0.8, 0.8, 0.8
            if charInfo.classFile then
                local cr, cg, cb = GetClassColor(charInfo.classFile)
                if cr then classR, classG, classB = cr, cg, cb end
            end
            
            local colorBar = mpCard:CreateTexture(nil, "ARTWORK")
            colorBar:SetSize(3, MP_ROW_HEIGHT - 4)
            colorBar:SetPoint("LEFT", mpCard, "TOPLEFT", 15, rowCenterY)
            colorBar:SetColorTexture(classR, classG, classB, 1)
            
            -- Character name (class-colored, width-limited to prevent overlap)
            local nameText = FontManager:CreateFontString(mpCard, "body", "OVERLAY")
            nameText:SetPoint("LEFT", colorBar, "RIGHT", 8, 0)
            nameText:SetPoint("RIGHT", mpCard, "RIGHT", -120, 0)
            nameText:SetWordWrap(false)
            local hexClass = format("%02x%02x%02x", classR * 255, classG * 255, classB * 255)
            nameText:SetText("|cff" .. hexClass .. charInfo.name .. "|r")
            nameText:SetJustifyH("LEFT")
            
            -- Played time (right-aligned, compact format for rows)
            local timeText = FontManager:CreateFontString(mpCard, "body", "OVERLAY")
            timeText:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, rowCenterY)
            if charInfo.timePlayed > 0 then
                timeText:SetText(FormatPlayed(charInfo.timePlayed))
                timeText:SetTextColor(0.85, 0.85, 0.85)
            else
                timeText:SetText("|cff555555—|r")
            end
            timeText:SetJustifyH("RIGHT")
            
            rowYStart = rowYStart + MP_ROW_HEIGHT + MP_ROW_SPACING
        end
        
        -- ── Expand/Collapse (PlanCardFactory pattern: glues-characterSelect atlas) ──
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
                moreText:SetText("|cff888888" .. hiddenCount .. " " .. moreLabel .. "|r")
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
        yOffset = yOffset + cardHeight + 10
    end
    
    -- ===== STORAGE STATS (bottom) =====
    local storageCard = CreateCard(parent, 100)
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = FontManager:CreateFontString(storageCard, "title", "OVERLAY")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local storageOverviewLabel = (ns.L and ns.L["STORAGE_OVERVIEW"]) or "Storage Overview"
    stTitle:SetText("|cff" .. hexColor .. storageOverviewLabel .. "|r")
    
    local function AddStat(statParent, label, value, x, y, color)
        local l = FontManager:CreateFontString(statParent, "small", "OVERLAY")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)
        l:SetTextColor(0.8, 0.8, 0.8)
        
        local v = FontManager:CreateFontString(statParent, "title", "OVERLAY")
        v:SetPoint("TOPLEFT", x, y - 16)
        v:SetText(value)
        if color then
            v:SetTextColor(unpack(color))
        else
            v:SetTextColor(1, 1, 1)
        end
    end
    
    local wb = stats.warband or {}
    local pb = stats.personal or {}
    local totalSlots = (wb.totalSlots or 0) + (pb.totalSlots or 0)
    local usedSlots = (wb.usedSlots or 0) + (pb.usedSlots or 0)
    local freeSlots = (wb.freeSlots or 0) + (pb.freeSlots or 0)
    
    local cardWidth = storageCard:GetWidth() or 600
    local columnWidth = (cardWidth - 30) / 4
    
    AddStat(storageCard, (ns.L and ns.L["WARBAND_SLOTS"]) or "WARBAND SLOTS", FormatNumber(wb.usedSlots or 0) .. "/" .. FormatNumber(wb.totalSlots or 0), 15, -40)
    AddStat(storageCard, (ns.L and ns.L["PERSONAL_SLOTS"]) or "PERSONAL SLOTS", FormatNumber(pb.usedSlots or 0) .. "/" .. FormatNumber(pb.totalSlots or 0), 15 + columnWidth * 1, -40)
    AddStat(storageCard, (ns.L and ns.L["TOTAL_FREE"]) or "TOTAL FREE", FormatNumber(freeSlots), 15 + columnWidth * 2, -40, {0.3, 0.9, 0.3})
    AddStat(storageCard, (ns.L and ns.L["TOTAL_ITEMS"]) or "TOTAL ITEMS", FormatNumber((wb.itemCount or 0) + (pb.itemCount or 0)), 15 + columnWidth * 3, -40)
    
    storageCard:Show()
    yOffset = yOffset + 110

    if ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(storageCard, parent, SIDE_MARGIN, 8)
    end

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

