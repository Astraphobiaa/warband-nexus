--[[
    Warband Nexus - Statistics Tab
    Display account-wide statistics: gold, collections, storage overview
]]

local ADDON_NAME, ns = ...

-- Unique AceEvent handler identity for StatisticsUI
local StatisticsUIEvents = {}

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Forward declaration (defined in COLLECTION STATS CACHE section below)
local InvalidateStatsCache

--[[
    Initialize Statistics UI event listeners
    Called during addon startup to register for data update events
]]
function WarbandNexus:InitializeStatisticsUI()
    -- Register for collection update events
    -- NOTE: Uses StatisticsUIEvents as 'self' key to avoid overwriting other modules' handlers.
    WarbandNexus.RegisterMessage(StatisticsUIEvents, "WN_COLLECTION_UPDATED", function(event, charKey)
        DebugPrint("|cff9370DB[WN StatisticsUI]|r Collection updated event received for " .. tostring(charKey))
        
        -- Invalidate stats cache so fresh counts are computed on next draw
        InvalidateStatsCache()
        
        -- Only refresh if Statistics tab is currently active
        if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab == "stats" then
            if self.RefreshUI then
                self:RefreshUI()
                DebugPrint("|cff00ff00[WN StatisticsUI]|r UI refreshed after collection update")
            end
        end
    end)
    
    -- Register for character data updates (played time, gold, etc.)
    -- NOTE: Do NOT invalidate collection stats cache here — WN_CHARACTER_UPDATED fires for
    -- gold, zone, ilvl, spec changes which don't affect mount/pet/toy counts.
    -- Collection stats are only invalidated by WN_COLLECTION_UPDATED (above).
    -- Invalidating here caused GetCachedCollectionStats to rebuild (1000+ API calls) on every
    -- character event, causing severe performance issues.
    WarbandNexus.RegisterMessage(StatisticsUIEvents, "WN_CHARACTER_UPDATED", function(event, payload)
        DebugPrint("|cff9370DB[WN StatisticsUI]|r Character updated event received")
        
        -- Only refresh if Statistics tab is currently active
        -- (Gold totals, played time etc. come from DB, not from collection API)
        if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab == "stats" then
            if self.RefreshUI then
                self:RefreshUI()
                DebugPrint("|cff00ff00[WN StatisticsUI]|r UI refreshed after character update")
            end
        end
    end)
    
    -- Event listeners initialized (verbose logging removed)
end

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local FormatNumber = ns.UI_FormatNumber
local CreateIcon = ns.UI_CreateIcon
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local COLORS = ns.UI_COLORS

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().headerSpacing or 40
local SECTION_SPACING = GetLayout().betweenSections or 40  -- Updated to match SharedWidgets
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local HEADER_SPACING = GetLayout().HEADER_SPACING or 40
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8

-- Performance: Local function references
local format = string.format
local date = date
local floor = math.floor

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

-- Compute and cache expensive collection statistics
local function GetCachedCollectionStats()
    local now = GetTime()
    if _statsCache and (now - _statsCache.timestamp) < STATS_CACHE_TTL then
        return _statsCache
    end

    local cache = { timestamp = now }

    -- ── Achievement Points ──
    cache.achievementPoints = GetTotalAchievementPoints() or 0

    -- ── Mount Counts ──
    local numCollectedMounts = 0
    local numTotalMounts = 0
    if C_MountJournal then
        local mountIDs = C_MountJournal.GetMountIDs()
        numTotalMounts = #mountIDs
        for _, mountID in ipairs(mountIDs) do
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if isCollected then
                numCollectedMounts = numCollectedMounts + 1
            end
        end
    end
    cache.mounts = { collected = numCollectedMounts, total = numTotalMounts }

    -- ── Pet Counts ──
    local numTotalSpecies = 0
    local numCollectedPets = 0
    local numUniqueSpecies = 0
    local numJournalEntries = 0
    if C_PetJournal then
        -- Ensure Blizzard_Collections is loaded for full pet journal data
        if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end

        -- Clear ALL filters so the journal shows every entry
        -- TAINT GUARD: Filter manipulation taints PetJournal; skip during combat
        if not InCombatLockdown() then
            if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
            if C_PetJournal.SetFilterChecked then
                C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
            end
            if C_PetJournal.SetPetTypeFilter and C_PetJournal.GetNumPetTypes then
                for i = 1, C_PetJournal.GetNumPetTypes() do
                    C_PetJournal.SetPetTypeFilter(i, true)
                end
            end
            if C_PetJournal.SetPetSourceChecked and C_PetJournal.GetNumPetSources then
                for i = 1, C_PetJournal.GetNumPetSources() do
                    C_PetJournal.SetPetSourceChecked(i, true)
                end
            end
        end

        -- Raw counts from GetNumPets
        numJournalEntries, numCollectedPets = C_PetJournal.GetNumPets()

        -- Count unique species owned via GetOwnedPetIDs (modern API)
        if C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetPetInfoTableByPetID then
            local ownedPetIDs = C_PetJournal.GetOwnedPetIDs()
            numCollectedPets = #ownedPetIDs

            local ownedSpecies = {}
            for i = 1, #ownedPetIDs do
                local info = C_PetJournal.GetPetInfoTableByPetID(ownedPetIDs[i])
                if info and info.speciesID then
                    ownedSpecies[info.speciesID] = true
                end
            end
            for _ in pairs(ownedSpecies) do
                numUniqueSpecies = numUniqueSpecies + 1
            end
        end

        -- Count total unique species by scanning ALL journal entries
        if C_PetJournal.GetPetInfoByIndex then
            local allSpecies = {}
            local nilSpeciesUnowned = 0
            for i = 1, numJournalEntries do
                local petID, speciesID = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID then
                    allSpecies[speciesID] = true
                elseif not petID then
                    nilSpeciesUnowned = nilSpeciesUnowned + 1
                end
            end
            for _ in pairs(allSpecies) do
                numTotalSpecies = numTotalSpecies + 1
            end
            numTotalSpecies = numTotalSpecies + nilSpeciesUnowned
        else
            numTotalSpecies = numJournalEntries
        end
    end
    cache.pets = {
        collected = numCollectedPets,
        totalSpecies = numTotalSpecies,
        uniqueSpecies = numUniqueSpecies,
        journalEntries = numJournalEntries,
    }

    -- ── Toy Counts ──
    local numCollectedToys = 0
    local numTotalToys = 0
    if C_ToyBox then
        numTotalToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
        numCollectedToys = C_ToyBox.GetNumLearnedDisplayedToys() or 0
    end
    cache.toys = { collected = numCollectedToys, total = numTotalToys }

    _statsCache = cache
    return cache
end

--============================================================================
-- DRAW STATISTICS (Modern Design)
--============================================================================

function WarbandNexus:DrawStatistics(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    local cardWidth = (width - 15) / 2
    
    -- Hide previous empty state
    HideEmptyStateCard(parent, "statistics")
    
    -- Check for data availability
    local characters = self.db and self.db.global and self.db.global.characters
    if not characters or not next(characters) then
        local _, height = CreateEmptyStateCard(parent, "statistics", yOffset)
        return
    end
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("statistics"))
    
    -- Use factory pattern positioning for standardized header layout
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["ACCOUNT_STATISTICS"]) or "Account Statistics") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["STATISTICS_SUBTITLE"]) or "Collection progress, gold, and storage overview"
    
    -- Create container for text group (using Factory pattern)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (matching factory pattern)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    titleCard:Show()
    
    yOffset = yOffset + 75 -- Reduced spacing
    
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
    
    -- Calculate card width for 3 cards in a row
    -- Formula: (Total width - left margin - right margin - total spacing) / 3
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
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
    
    -- Mount Card (3-column layout)
    local mountCard = CreateCard(parent, 90)
    mountCard:SetWidth(threeCardWidth)
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
    
    -- Pet Card (Center) - single icon, two stacked sections
    local petCard = CreateCard(parent, 90)
    petCard:SetWidth(threeCardWidth)
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
    
    -- Right column: Unique Pets (label above icon center, value below)
    -- Anchor both to a fixed X so label and value are vertically aligned
    local upLabel = FontManager:CreateFontString(petCard, "subtitle", "OVERLAY")
    upLabel:SetPoint("BOTTOMLEFT", bpLabel, "BOTTOMRIGHT", 35, 0)
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
    
    -- Toys Card (Right)
    local toyCard = CreateCard(parent, 90)
    toyCard:SetWidth(threeCardWidth)
    toyCard:SetPoint("LEFT", petCard, "RIGHT", cardSpacing, 0)
    -- Also anchor to right to ensure it fills the space
    toyCard:SetPoint("RIGHT", -rightMargin, 0)
    
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
    
    yOffset = yOffset + 100
    
    -- ===== STORAGE STATS =====
    local storageCard = CreateCard(parent, 100)  -- Reduced height from 120 to 100
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = FontManager:CreateFontString(storageCard, "title", "OVERLAY")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    -- Dynamic theme color for title
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local storageOverviewLabel = (ns.L and ns.L["STORAGE_OVERVIEW"]) or "Storage Overview"
    stTitle:SetText("|cff" .. hexColor .. storageOverviewLabel .. "|r")
    
    -- Stats grid - improved layout with better spacing and alignment
    local function AddStat(parent, label, value, x, y, color)
        local l = FontManager:CreateFontString(parent, "small", "OVERLAY")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)
        l:SetTextColor(0.8, 0.8, 0.8)  -- Light gray for labels
        
        local v = FontManager:CreateFontString(parent, "title", "OVERLAY")
        v:SetPoint("TOPLEFT", x, y - 16)
        v:SetText(value)
        if color then 
            v:SetTextColor(unpack(color))
        else
            v:SetTextColor(1, 1, 1)  -- White for values
        end
    end
    
    -- Use warband stats from new structure
    local wb = stats.warband or {}
    local pb = stats.personal or {}
    local totalSlots = (wb.totalSlots or 0) + (pb.totalSlots or 0)
    local usedSlots = (wb.usedSlots or 0) + (pb.usedSlots or 0)
    local freeSlots = (wb.freeSlots or 0) + (pb.freeSlots or 0)
    local usedPct = totalSlots > 0 and floor((usedSlots / totalSlots) * 100) or 0
    
    -- Calculate column width for perfect symmetry (4 columns)
    local cardWidth = storageCard:GetWidth() or 600
    local columnWidth = (cardWidth - 30) / 4  -- 30 = 15px left + 15px right padding
    
    AddStat(storageCard, (ns.L and ns.L["WARBAND_SLOTS"]) or "WARBAND SLOTS", FormatNumber(wb.usedSlots or 0) .. "/" .. FormatNumber(wb.totalSlots or 0), 15, -40)
    AddStat(storageCard, (ns.L and ns.L["PERSONAL_SLOTS"]) or "PERSONAL SLOTS", FormatNumber(pb.usedSlots or 0) .. "/" .. FormatNumber(pb.totalSlots or 0), 15 + columnWidth * 1, -40)
    AddStat(storageCard, (ns.L and ns.L["TOTAL_FREE"]) or "TOTAL FREE", FormatNumber(freeSlots), 15 + columnWidth * 2, -40, {0.3, 0.9, 0.3})
    AddStat(storageCard, (ns.L and ns.L["TOTAL_ITEMS"]) or "TOTAL ITEMS", FormatNumber((wb.itemCount or 0) + (pb.itemCount or 0)), 15 + columnWidth * 3, -40)
    
    storageCard:Show()
    
    -- Progress bar removed (will be redesigned in new styling system)
    
    yOffset = yOffset + 110  -- Adjusted from 130 to 110
    
    -- ===== MOST PLAYED CARD =====
    local MP_VISIBLE_ROWS = 5
    local MP_ROW_HEIGHT = 22
    local MP_ROW_SPACING = 1
    local MP_HEADER_AREA = 48        -- Space for icon + title at top
    local MP_TOGGLE_HEIGHT = 28      -- Height for expand/collapse button
    local MP_BOTTOM_PAD = 8
    
    -- Compact time format for rows (e.g., "363d 16h" instead of "363 Days 16 Hours 55 Minutes")
    -- Row format: keep full words but only show top 2 units
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
    
    -- Collect ALL tracked characters, include those with 0 played time
    local playedChars = {}
    local totalPlayedSeconds = 0
    for charKey, charData in pairs(characters) do
        if charData.isTracked then
            local played = charData.timePlayed or 0
            playedChars[#playedChars + 1] = {
                name = charData.name or charKey:match("^(.+)%-") or "Unknown",
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
        if not ns._statisticsExpandedStates then
            ns._statisticsExpandedStates = {}
        end
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
        
        -- ── Total played time at top-right (full format for header) ──
        local mpTotal = FontManager:CreateFontString(mpCard, "header", "OVERLAY")
        mpTotal:SetPoint("RIGHT", mpCard, "TOPRIGHT", -15, -24)
        mpTotal:SetText("|cff00ccff" .. ns.Utilities:FormatPlayedTime(totalPlayedSeconds) .. "|r")
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
                timeText:SetText(FormatPlayedCompact(charInfo.timePlayed))
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
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
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
                    if WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end
            end)
        end
        
        mpCard:Show()
        yOffset = yOffset + cardHeight + 10
    end
    
    -- Last scan info removed - now only shown in footer
    
    return yOffset
end

