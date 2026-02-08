--[[
    Warband Nexus - Statistics Tab
    Display account-wide statistics: gold, collections, storage overview
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

--[[
    Initialize Statistics UI event listeners
    Called during addon startup to register for data update events
]]
function WarbandNexus:InitializeStatisticsUI()
    -- Register for collection update events
    self:RegisterMessage("WN_COLLECTION_UPDATED", function(event, charKey)
        DebugPrint("|cff9370DB[WN StatisticsUI]|r Collection updated event received for " .. tostring(charKey))
        
        -- Only refresh if Statistics tab is currently active
        if self.UI and self.UI.mainFrame and self.UI.mainFrame:IsShown() and self.UI.mainFrame.currentTab == "stats" then
            if self.RefreshUI then
                self:RefreshUI()
                DebugPrint("|cff00ff00[WN StatisticsUI]|r UI refreshed after collection update")
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
    -- TWW Note: Achievements are now account-wide (warband), no separate character score
    local achievementPoints = GetTotalAchievementPoints() or 0
    
    -- Calculate card width for 3 cards in a row
    -- Formula: (Total width - left margin - right margin - total spacing) / 3
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
    -- Get mount count using proper API
    local numCollectedMounts = 0
    local numTotalMounts = 0
    if C_MountJournal then
        local mountIDs = C_MountJournal.GetMountIDs()
        numTotalMounts = #mountIDs
        
        -- Count collected mounts
        for _, mountID in ipairs(mountIDs) do
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
            if isCollected then
                numCollectedMounts = numCollectedMounts + 1
            end
        end
    end
    
    -- Get pet counts using documented modern API (PetJournalInfoDocumentation.lua)
    --
    -- KEY API FACTS:
    --   GetNumPets()              → (numEntries, numOwned) — journal entry count + total individual pets
    --   GetOwnedPetIDs()          → table of WOWGUID — every individual pet the player owns
    --   GetPetInfoTableByPetID(g) → PetJournalPetInfo { speciesID, ... }
    --   GetPetInfoByIndex(i)      → petID, speciesID, ... — per journal entry
    --
    -- numEntries from GetNumPets() is NOT the unique species count.
    -- It includes duplicate entries for owned pets of the same species.
    -- To get accurate counts we must iterate and deduplicate by speciesID.
    --
    local numTotalSpecies = 0    -- True unique species in journal (deduplicated)
    local numCollectedPets = 0   -- Total individual pets owned (including duplicates)
    local numUniqueSpecies = 0   -- Unique species collected (deduplicated)
    local numJournalEntries = 0  -- Raw journal entry count (for Battle Pets line)
    if C_PetJournal then
        -- Ensure Blizzard_Collections is loaded for full pet journal data
        if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
        
        -- Clear ALL filters so the journal shows every entry
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
        
        -- Raw counts from GetNumPets
        numJournalEntries, numCollectedPets = C_PetJournal.GetNumPets()
        
        -- Count unique species owned via GetOwnedPetIDs (modern API)
        -- Each GUID is one individual pet; deduplicate by speciesID for unique count
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
        -- Journal entries are a mix of:
        --   1) Owned individual pets (petID non-nil, may share speciesID with duplicates)
        --   2) Unowned species (petID nil, one entry per species)
        -- Some entries return nil speciesID (API can't describe them), but each
        -- nil-speciesID + nil-petID entry is still a unique unowned species.
        if C_PetJournal.GetPetInfoByIndex then
            local allSpecies = {}
            local nilSpeciesUnowned = 0
            for i = 1, numJournalEntries do
                local petID, speciesID = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID then
                    allSpecies[speciesID] = true
                elseif not petID then
                    -- Unowned species entry where API returned nil speciesID
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

    -- Get toy count (filter-independent)
    local numCollectedToys = 0
    local numTotalToys = 0
    if C_ToyBox then
        numTotalToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
        numCollectedToys = C_ToyBox.GetNumLearnedDisplayedToys() or 0
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
    upLabel:SetPoint("BOTTOMLEFT", bpLabel, "BOTTOMRIGHT", 20, 0)
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
    
    -- Last scan info removed - now only shown in footer
    
    return yOffset
end

