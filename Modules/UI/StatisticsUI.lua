--[[
    Warband Nexus - Statistics Tab
    Display account-wide statistics: gold, collections, storage overview
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local CreateIcon = ns.UI_CreateIcon
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Import shared UI layout constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.rowHeight or 26
local ROW_SPACING = UI_LAYOUT.rowSpacing or 28
local HEADER_SPACING = UI_LAYOUT.headerSpacing or 40
local SECTION_SPACING = UI_LAYOUT.betweenSections or 40  -- Updated to match SharedWidgets
local BASE_INDENT = UI_LAYOUT.BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = UI_LAYOUT.SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = UI_LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = UI_LAYOUT.TOP_MARGIN or 8
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING or 40
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 8
local SIDE_MARGIN = UI_LAYOUT.sideMargin or 10
local TOP_MARGIN = UI_LAYOUT.topMargin or 8

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
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("statistics"))
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Account Statistics|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, -12)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetText("Collection progress, gold, and storage overview")
    
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
    
    -- Get pet count
    local numPets = 0
    local numCollectedPets = 0
    if C_PetJournal then
        C_PetJournal.SetSearchFilter("")
        C_PetJournal.ClearSearchFilter()
        numPets, numCollectedPets = C_PetJournal.GetNumPets()
    end
    
    -- Get toy count
    local numCollectedToys = 0
    local numTotalToys = 0
    if C_ToyBox then
        -- TWW API: Count toys manually
        numTotalToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
        numCollectedToys = C_ToyBox.GetNumLearnedDisplayedToys() or 0
    end
    
    -- Achievement Card (Account-wide since TWW) - Full width
    local achCard = CreateCard(parent, 90)
    achCard:SetPoint("TOPLEFT", 10, -yOffset)
    achCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local achIconFrame = CreateIcon(achCard, "Interface\\Icons\\Achievement_General_StayClassy", 36, false, nil, true)
    achIconFrame:SetPoint("LEFT", 15, 0)
    
    local achLabel = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achLabel:SetPoint("TOPLEFT", achIconFrame, "TOPRIGHT", 12, -2)
    achLabel:SetText("ACHIEVEMENT POINTS")
    achLabel:SetTextColor(1, 1, 1)  -- White
    
    local achValue = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    achValue:SetPoint("BOTTOMLEFT", achIconFrame, "BOTTOMRIGHT", 12, 0)
    achValue:SetText("|cffffcc00" .. achievementPoints .. "|r")
    
    local achNote = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achNote:SetPoint("BOTTOMRIGHT", -10, 10)
    achNote:SetText("Account-wide")
    achNote:SetTextColor(1, 1, 1)  -- White
    
    yOffset = yOffset + 100
    
    -- Mount Card (3-column layout)
    local mountCard = CreateCard(parent, 90)
    mountCard:SetWidth(threeCardWidth)
    mountCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    local mountIconFrame = CreateIcon(mountCard, "Interface\\Icons\\Ability_Mount_RidingHorse", 36, false, nil, true)
    mountIconFrame:SetPoint("LEFT", 15, 0)
    
    local mountLabel = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountLabel:SetPoint("TOPLEFT", mountIconFrame, "TOPRIGHT", 12, -2)
    mountLabel:SetText("MOUNTS COLLECTED")
    mountLabel:SetTextColor(1, 1, 1)  -- White
    
    local mountValue = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mountValue:SetPoint("BOTTOMLEFT", mountIconFrame, "BOTTOMRIGHT", 12, 0)
    mountValue:SetText("|cff0099ff" .. numCollectedMounts .. "/" .. numTotalMounts .. "|r")
    
    local mountNote = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountNote:SetPoint("BOTTOMRIGHT", -10, 10)
    mountNote:SetText("Account-wide")
    mountNote:SetTextColor(1, 1, 1)  -- White
    
    -- Pet Card (Center)
    local petCard = CreateCard(parent, 90)
    petCard:SetWidth(threeCardWidth)
    petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
    
    local petIconFrame = CreateIcon(petCard, "Interface\\Icons\\INV_Box_PetCarrier_01", 36, false, nil, true)
    petIconFrame:SetPoint("LEFT", 15, 0)
    
    local petLabel = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petLabel:SetPoint("TOPLEFT", petIconFrame, "TOPRIGHT", 12, -2)
    petLabel:SetText("BATTLE PETS")
    petLabel:SetTextColor(1, 1, 1)  -- White
    
    local petValue = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    petValue:SetPoint("BOTTOMLEFT", petIconFrame, "BOTTOMRIGHT", 12, 0)
    petValue:SetText("|cffff69b4" .. numCollectedPets .. "/" .. numPets .. "|r")
    
    local petNote = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petNote:SetPoint("BOTTOMRIGHT", -10, 10)
    petNote:SetText("Account-wide")
    petNote:SetTextColor(1, 1, 1)  -- White
    
    -- Toys Card (Right)
    local toyCard = CreateCard(parent, 90)
    toyCard:SetWidth(threeCardWidth)
    toyCard:SetPoint("LEFT", petCard, "RIGHT", cardSpacing, 0)
    -- Also anchor to right to ensure it fills the space
    toyCard:SetPoint("RIGHT", -rightMargin, 0)
    
    local toyIconFrame = CreateIcon(toyCard, "Interface\\Icons\\INV_Misc_Toy_10", 36, false, nil, true)
    toyIconFrame:SetPoint("LEFT", 15, 0)
    
    local toyLabel = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyLabel:SetPoint("TOPLEFT", toyIconFrame, "TOPRIGHT", 12, -2)
    toyLabel:SetText("TOYS")
    toyLabel:SetTextColor(1, 1, 1)  -- White
    
    local toyValue = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    toyValue:SetPoint("BOTTOMLEFT", toyIconFrame, "BOTTOMRIGHT", 12, 0)
    toyValue:SetText("|cffff66ff" .. numCollectedToys .. "/" .. numTotalToys .. "|r")
    
    local toyNote = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyNote:SetPoint("BOTTOMRIGHT", -10, 10)
    toyNote:SetText("Account-wide")
    toyNote:SetTextColor(1, 1, 1)  -- White
    
    yOffset = yOffset + 100
    
    -- ===== STORAGE STATS =====
    local storageCard = CreateCard(parent, 100)  -- Reduced height from 120 to 100
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = storageCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    stTitle:SetText("|cff" .. hexColor .. "Storage Overview|r")
    
    -- Stats grid - improved layout with better spacing and alignment
    local function AddStat(parent, label, value, x, y, color)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)
        l:SetTextColor(0.8, 0.8, 0.8)  -- Light gray for labels
        
        local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
    
    AddStat(storageCard, "WARBAND SLOTS", (wb.usedSlots or 0) .. "/" .. (wb.totalSlots or 0), 15, -40)
    AddStat(storageCard, "PERSONAL SLOTS", (pb.usedSlots or 0) .. "/" .. (pb.totalSlots or 0), 15 + columnWidth * 1, -40)
    AddStat(storageCard, "TOTAL FREE", tostring(freeSlots), 15 + columnWidth * 2, -40, {0.3, 0.9, 0.3})
    AddStat(storageCard, "TOTAL ITEMS", tostring((wb.itemCount or 0) + (pb.itemCount or 0)), 15 + columnWidth * 3, -40)
    
    -- Progress bar removed (will be redesigned in new styling system)
    
    yOffset = yOffset + 110  -- Adjusted from 130 to 110
    
    -- Last scan info removed - now only shown in footer
    
    return yOffset
end

