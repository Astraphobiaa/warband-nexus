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
local SIDE_MARGIN = GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().topMargin or 8

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
    
    -- Get pet count (unique species)
    local numPets = 0
    local numCollectedPets = 0
    if C_PetJournal then
        -- GetNumPets returns (numPets, numOwned) – numPets = total unique species in journal
        C_PetJournal.ClearSearchFilter()
        numPets, numCollectedPets = C_PetJournal.GetNumPets()
        -- numCollectedPets from GetNumPets already returns the correct owned count
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
    
    -- Pet Card (Center)
    local petCard = CreateCard(parent, 90)
    petCard:SetWidth(threeCardWidth)
    petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
    
    -- Use factory pattern for standardized card header layout
    local petLayout = CreateCardHeaderLayout(
        petCard,
        "Interface\\Icons\\INV_Box_PetCarrier_01",
        36,
        false,
        (ns.L and ns.L["BATTLE_PETS"]) or "BATTLE PETS",
        "|cffff69b4" .. FormatNumber(numCollectedPets) .. "/" .. FormatNumber(numPets) .. " (" .. (numPets > 0 and math.floor(numCollectedPets / numPets * 100) or 0) .. "%)|r",
        "subtitle",
        "header"
    )
    -- Override label color to white (factory defaults to white, but ensure it)
    if petLayout.label then
        petLayout.label:SetTextColor(1, 1, 1)
    end
    
    local petNote = FontManager:CreateFontString(petCard, "small", "OVERLAY")
    petNote:SetPoint("BOTTOMRIGHT", -10, 10)
    petNote:SetText(accountWideLabel)
    petNote:SetTextColor(1, 1, 1)  -- White
    
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

