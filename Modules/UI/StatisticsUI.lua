--[[
    Warband Nexus - Statistics Tab
    Display account-wide statistics: gold, collections, storage overview
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold

-- Performance: Local function references
local format = string.format
local date = date
local floor = math.floor

--============================================================================
-- DRAW STATISTICS (Modern Design)
--============================================================================

function WarbandNexus:DrawStatistics(parent)
    local yOffset = 10
    local width = parent:GetWidth() - 20
    local cardWidth = (width - 15) / 2
    
    -- ===== HEADER CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    titleText:SetText("|cffa335eeAccount Statistics|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Collection progress, gold, and storage overview")
    
    yOffset = yOffset + 80
    
    -- Get statistics
    local stats = self:GetBankStatistics()
    local warbandGold = self:GetWarbandBankMoney() or 0
    local playerGold = GetMoney() or 0
    local depositable = self:GetDepositableGold() or 0
    
    -- Calculate total gold across all characters
    local totalAccountGold = 0
    for charKey, charData in pairs(self.db.global.characters or {}) do
        if charData.gold then
            totalAccountGold = totalAccountGold + charData.gold
        end
    end
    
    -- ===== GOLD CARDS ROW =====
    -- Warband Bank Gold Card
    local goldCard1 = CreateCard(parent, 90)
    goldCard1:SetWidth(cardWidth)
    goldCard1:SetPoint("TOPLEFT", 10, -yOffset)
    
    local gc1Icon = goldCard1:CreateTexture(nil, "ARTWORK")
    gc1Icon:SetSize(36, 36)
    gc1Icon:SetPoint("LEFT", 15, 0)
    gc1Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    
    local gc1Label = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc1Label:SetPoint("TOPLEFT", gc1Icon, "TOPRIGHT", 12, -2)
    gc1Label:SetText("WARBAND BANK")
    gc1Label:SetTextColor(0.6, 0.6, 0.6)
    
    local gc1Value = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    gc1Value:SetPoint("BOTTOMLEFT", gc1Icon, "BOTTOMRIGHT", 12, 0)
    gc1Value:SetText("|cffffd700" .. FormatGold(warbandGold) .. "|r")
    
    local gc1Full = goldCard1:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc1Full:SetPoint("BOTTOMRIGHT", -10, 10)
    gc1Full:SetText("")
    gc1Full:SetTextColor(0.5, 0.5, 0.5)
    
    -- Your Gold Card
    local goldCard2 = CreateCard(parent, 90)
    goldCard2:SetWidth(cardWidth)
    goldCard2:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local gc2Icon = goldCard2:CreateTexture(nil, "ARTWORK")
    gc2Icon:SetSize(36, 36)
    gc2Icon:SetPoint("LEFT", 15, 0)
    gc2Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    
    local gc2Label = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc2Label:SetPoint("TOPLEFT", gc2Icon, "TOPRIGHT", 12, -2)
    gc2Label:SetText("CURRENT CHARACTER")
    gc2Label:SetTextColor(0.6, 0.6, 0.6)
    
    local gc2Value = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    gc2Value:SetPoint("BOTTOMLEFT", gc2Icon, "BOTTOMRIGHT", 12, 0)
    gc2Value:SetText("|cffffff00" .. FormatGold(playerGold) .. "|r")
    
    local gc2Full = goldCard2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gc2Full:SetPoint("BOTTOMRIGHT", -10, 10)
    gc2Full:SetText("|cff888888Total: " .. FormatGold(totalAccountGold) .. "|r")
    gc2Full:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- ===== COLLECTION STATS TITLE =====
    local collectionTitle = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    collectionTitle:SetPoint("TOPLEFT", 15, -yOffset)
    collectionTitle:SetText("|cffa335eeCollection Progress|r")
    
    yOffset = yOffset + 30
    
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
    
    local achIcon = achCard:CreateTexture(nil, "ARTWORK")
    achIcon:SetSize(36, 36)
    achIcon:SetPoint("LEFT", 15, 0)
    achIcon:SetTexture("Interface\\Icons\\Achievement_General_StayClassy")
    
    local achLabel = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achLabel:SetPoint("TOPLEFT", achIcon, "TOPRIGHT", 12, -2)
    achLabel:SetText("ACHIEVEMENT POINTS")
    achLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local achValue = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    achValue:SetPoint("BOTTOMLEFT", achIcon, "BOTTOMRIGHT", 12, 0)
    achValue:SetText("|cffffcc00" .. achievementPoints .. "|r")
    
    local achNote = achCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achNote:SetPoint("BOTTOMRIGHT", -10, 10)
    achNote:SetText("|cff888888Account-wide|r")
    achNote:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- Mount Card (3-column layout)
    local mountCard = CreateCard(parent, 90)
    mountCard:SetWidth(threeCardWidth)
    mountCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    local mountIcon = mountCard:CreateTexture(nil, "ARTWORK")
    mountIcon:SetSize(36, 36)
    mountIcon:SetPoint("LEFT", 15, 0)
    mountIcon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    
    local mountLabel = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountLabel:SetPoint("TOPLEFT", mountIcon, "TOPRIGHT", 12, -2)
    mountLabel:SetText("MOUNTS COLLECTED")
    mountLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local mountValue = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    mountValue:SetPoint("BOTTOMLEFT", mountIcon, "BOTTOMRIGHT", 12, 0)
    mountValue:SetText("|cff0099ff" .. numCollectedMounts .. "/" .. numTotalMounts .. "|r")
    
    local mountNote = mountCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mountNote:SetPoint("BOTTOMRIGHT", -10, 10)
    mountNote:SetText("|cff888888Account-wide|r")
    mountNote:SetTextColor(0.5, 0.5, 0.5)
    
    -- Pet Card (Center)
    local petCard = CreateCard(parent, 90)
    petCard:SetWidth(threeCardWidth)
    petCard:SetPoint("LEFT", mountCard, "RIGHT", cardSpacing, 0)
    
    local petIcon = petCard:CreateTexture(nil, "ARTWORK")
    petIcon:SetSize(36, 36)
    petIcon:SetPoint("LEFT", 15, 0)
    petIcon:SetTexture("Interface\\Icons\\INV_Box_PetCarrier_01")
    
    local petLabel = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petLabel:SetPoint("TOPLEFT", petIcon, "TOPRIGHT", 12, -2)
    petLabel:SetText("BATTLE PETS")
    petLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local petValue = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    petValue:SetPoint("BOTTOMLEFT", petIcon, "BOTTOMRIGHT", 12, 0)
    petValue:SetText("|cffff69b4" .. numCollectedPets .. "/" .. numPets .. "|r")
    
    local petNote = petCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    petNote:SetPoint("BOTTOMRIGHT", -10, 10)
    petNote:SetText("|cff888888Account-wide|r")
    petNote:SetTextColor(0.5, 0.5, 0.5)
    
    -- Toys Card (Right)
    local toyCard = CreateCard(parent, 90)
    toyCard:SetWidth(threeCardWidth)
    toyCard:SetPoint("LEFT", petCard, "RIGHT", cardSpacing, 0)
    -- Also anchor to right to ensure it fills the space
    toyCard:SetPoint("RIGHT", -rightMargin, 0)
    
    local toyIcon = toyCard:CreateTexture(nil, "ARTWORK")
    toyIcon:SetSize(36, 36)
    toyIcon:SetPoint("LEFT", 15, 0)
    toyIcon:SetTexture("Interface\\Icons\\INV_Misc_Toy_10")
    
    local toyLabel = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyLabel:SetPoint("TOPLEFT", toyIcon, "TOPRIGHT", 12, -2)
    toyLabel:SetText("TOYS")
    toyLabel:SetTextColor(0.6, 0.6, 0.6)
    
    local toyValue = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    toyValue:SetPoint("BOTTOMLEFT", toyIcon, "BOTTOMRIGHT", 12, 0)
    toyValue:SetText("|cffff66ff" .. numCollectedToys .. "/" .. numTotalToys .. "|r")
    
    local toyNote = toyCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toyNote:SetPoint("BOTTOMRIGHT", -10, 10)
    toyNote:SetText("|cff888888Account-wide|r")
    toyNote:SetTextColor(0.5, 0.5, 0.5)
    
    yOffset = yOffset + 100
    
    -- ===== STORAGE STATS =====
    local storageCard = CreateCard(parent, 120)
    storageCard:SetPoint("TOPLEFT", 10, -yOffset)
    storageCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local stTitle = storageCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    stTitle:SetPoint("TOPLEFT", 15, -12)
    stTitle:SetText("|cffa335eeStorage Overview|r")
    
    -- Stats grid
    local function AddStat(parent, label, value, x, y, color)
        local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        l:SetPoint("TOPLEFT", x, y)
        l:SetText(label)
        l:SetTextColor(0.6, 0.6, 0.6)
        
        local v = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        v:SetPoint("TOPLEFT", x, y - 14)
        v:SetText(value)
        if color then v:SetTextColor(unpack(color)) end
    end
    
    -- Use warband stats from new structure
    local wb = stats.warband or {}
    local pb = stats.personal or {}
    local totalSlots = (wb.totalSlots or 0) + (pb.totalSlots or 0)
    local usedSlots = (wb.usedSlots or 0) + (pb.usedSlots or 0)
    local freeSlots = (wb.freeSlots or 0) + (pb.freeSlots or 0)
    local usedPct = totalSlots > 0 and floor((usedSlots / totalSlots) * 100) or 0
    
    AddStat(storageCard, "WARBAND SLOTS", (wb.usedSlots or 0) .. "/" .. (wb.totalSlots or 0), 15, -40)
    AddStat(storageCard, "PERSONAL SLOTS", (pb.usedSlots or 0) .. "/" .. (pb.totalSlots or 0), 160, -40)
    AddStat(storageCard, "TOTAL FREE", tostring(freeSlots), 320, -40, {0.3, 0.9, 0.3})
    AddStat(storageCard, "TOTAL ITEMS", tostring((wb.itemCount or 0) + (pb.itemCount or 0)), 420, -40)
    
    -- Progress bar (Warband usage)
    local wbPct = (wb.totalSlots or 0) > 0 and floor(((wb.usedSlots or 0) / (wb.totalSlots or 1)) * 100) or 0
    
    local barBg = storageCard:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(storageCard:GetWidth() - 30, 8)
    barBg:SetPoint("BOTTOMLEFT", 15, 15)
    barBg:SetColorTexture(0.2, 0.2, 0.2, 1)
    
    local barFill = storageCard:CreateTexture(nil, "ARTWORK")
    barFill:SetHeight(8)
    barFill:SetPoint("BOTTOMLEFT", 15, 15)
    barFill:SetWidth(math.max(1, (storageCard:GetWidth() - 30) * (wbPct / 100)))
    
    if wbPct > 90 then
        barFill:SetColorTexture(0.9, 0.3, 0.3, 1)
    elseif wbPct > 70 then
        barFill:SetColorTexture(0.9, 0.7, 0.2, 1)
    else
        barFill:SetColorTexture(0, 0.8, 0.9, 1)  -- Cyan for warband
    end
    
    yOffset = yOffset + 130
    
    -- Last scan info
    local wbScan = wb.lastScan or 0
    local pbScan = pb.lastScan or 0
    local scanInfo = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanInfo:SetPoint("TOPLEFT", 15, -yOffset)
    scanInfo:SetTextColor(0.4, 0.4, 0.4)
    
    local scanText = ""
    if wbScan > 0 then
        scanText = "Warband: " .. date("%H:%M", wbScan)
    end
    if pbScan > 0 then
        if scanText ~= "" then scanText = scanText .. "  •  " end
        scanText = scanText .. "Personal: " .. date("%H:%M", pbScan)
    end
    if scanText == "" then
        scanText = "Never scanned - visit a banker to scan"
    else
        scanText = "Last scan - " .. scanText
    end
    scanInfo:SetText(scanText)
    
    return yOffset + 40
end

