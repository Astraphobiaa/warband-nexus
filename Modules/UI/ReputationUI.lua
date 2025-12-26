--[[
    Warband Nexus - Reputation Tab
    Display all reputations across characters with progress bars, Renown, and Paragon support
    
    Pattern: EXACT CurrencyUI structure with progress bars
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local DrawEmptyState = ns.UI_DrawEmptyState
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format
local floor = math.floor
local ipairs = ipairs

-- Minimal logging for operations
local function LogOperation(operationName, status, trigger)
    local timestamp = date("%H:%M")
    print(string.format("%s - %s → %s (%s)", timestamp, operationName, status, trigger or "UI_REFRESH"))
end
local pairs = pairs
local next = next

-- Import shared UI constants
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING
local CHAR_INDENT = UI_LAYOUT.CHAR_INDENT
local EXPANSION_INDENT = UI_LAYOUT.EXPANSION_INDENT
local CATEGORY_INDENT = UI_LAYOUT.CATEGORY_INDENT

--============================================================================
-- REPUTATION FORMATTING & HELPERS
--============================================================================

---Format number with thousand separators
---@param num number Number to format
---@return string Formatted number
local function FormatNumber(num)
    local formatted = tostring(num)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return formatted
end

---Get standing name from standing ID
---@param standingID number Standing ID (1-8)
---@return string Standing name
local function GetStandingName(standingID)
    local standings = {
        [1] = "Hated",
        [2] = "Hostile",
        [3] = "Unfriendly",
        [4] = "Neutral",
        [5] = "Friendly",
        [6] = "Honored",
        [7] = "Revered",
        [8] = "Exalted",
    }
    return standings[standingID] or "Unknown"
end

---Get standing color (RGB) from standing ID
---@param standingID number Standing ID (1-8)
---@return number r, number g, number b
local function GetStandingColor(standingID)
    local colors = {
        [1] = {0.8, 0.13, 0.13},  -- Hated (dark red)
        [2] = {0.93, 0.4, 0.4},   -- Hostile (red)
        [3] = {1, 0.6, 0.2},      -- Unfriendly (orange)
        [4] = {1, 1, 0},          -- Neutral (yellow)
        [5] = {0, 1, 0},          -- Friendly (green)
        [6] = {0, 1, 0.59},       -- Honored (light green)
        [7] = {0, 1, 1},          -- Revered (cyan)
        [8] = {0.73, 0.4, 1},     -- Exalted (purple)
    }
    local color = colors[standingID] or {1, 1, 1}
    return color[1], color[2], color[3]
end

---Get standing color hex from standing ID
---@param standingID number Standing ID (1-8)
---@return string Color hex (|cffRRGGBB)
local function GetStandingColorHex(standingID)
    local r, g, b = GetStandingColor(standingID)
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

---Format reputation progress text
---@param current number Current value
---@param max number Max value
---@return string Formatted text
local function FormatReputationProgress(current, max)
    if max > 0 then
        return format("%s / %s", FormatNumber(current), FormatNumber(max))
    else
        return FormatNumber(current)
    end
end

---Check if reputation matches search text
---@param reputation table Reputation data
---@param searchText string Search text (lowercase)
---@return boolean matches
local function ReputationMatchesSearch(reputation, searchText)
    if not searchText or searchText == "" then
        return true
    end
    
    local name = (reputation.name or ""):lower()
    
    return name:find(searchText, 1, true)
end

--============================================================================
-- FILTERED VIEW AGGREGATION
--============================================================================

---Compare two reputation values to determine which is higher
---@param rep1 table First reputation data
---@param rep2 table Second reputation data
---@return boolean true if rep1 is higher than rep2
local function IsReputationHigher(rep1, rep2)
    -- Priority: Paragon > Renown > Standing > CurrentValue
    
    -- Check Paragon first (highest priority)
    local hasParagon1 = (rep1.paragonValue and rep1.paragonThreshold) and true or false
    local hasParagon2 = (rep2.paragonValue and rep2.paragonThreshold) and true or false
    
    if hasParagon1 and not hasParagon2 then
        return true
    elseif hasParagon2 and not hasParagon1 then
        return false
    elseif hasParagon1 and hasParagon2 then
        -- Both have paragon, compare paragon values
        if rep1.paragonValue ~= rep2.paragonValue then
            return rep1.paragonValue > rep2.paragonValue
        end
    end
    
    -- Check Renown level
    local renown1 = rep1.renownLevel or 0
    local renown2 = rep2.renownLevel or 0
    
    if renown1 ~= renown2 then
        return renown1 > renown2
    end
    
    -- Check Standing
    local standing1 = rep1.standingID or 0
    local standing2 = rep2.standingID or 0
    
    if standing1 ~= standing2 then
        return standing1 > standing2
    end
    
    -- Finally compare current value
    local value1 = rep1.currentValue or 0
    local value2 = rep2.currentValue or 0
    
    return value1 > value2
end

---Aggregate reputations across all characters (find highest for each faction)
---@param characters table List of character data
---@param factionMetadata table Faction metadata
---@param reputationSearchText string Search filter
---@return table List of {headerName, factions={factionID, data, characterKey, characterName, characterClass, isAccountWide}}
local function AggregateReputations(characters, factionMetadata, reputationSearchText)
    -- Collect all unique faction IDs and their best reputation
    local factionMap = {} -- [factionID] = {data, characterKey, characterName, characterClass, allCharData}
    
    -- Iterate through all characters
    for _, char in ipairs(characters) do
        if char.reputations and next(char.reputations) then
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
            
            for factionID, progress in pairs(char.reputations) do
                local metadata = factionMetadata[factionID]
                
                if metadata then
                    -- Merge metadata + progress
                    local reputation = {
                        name = metadata.name,
                        description = metadata.description,
                        iconTexture = metadata.iconTexture,
                        isRenown = metadata.isRenown,
                        canToggleAtWar = metadata.canToggleAtWar,
                        parentHeaders = metadata.parentHeaders,
                        isHeader = metadata.isHeader,
                        isHeaderWithRep = metadata.isHeaderWithRep,
                        
                        standingID = progress.standingID,
                        currentValue = progress.currentValue,
                        maxValue = progress.maxValue,
                        renownLevel = progress.renownLevel,
                        renownMaxLevel = progress.renownMaxLevel,
                        paragonValue = progress.paragonValue,
                        paragonThreshold = progress.paragonThreshold,
                        paragonRewardPending = progress.paragonRewardPending,
                        isWatched = progress.isWatched,
                        atWarWith = progress.atWarWith,
                        isMajorFaction = progress.isMajorFaction,
                        lastUpdated = progress.lastUpdated,
                    }
                    
                    -- Check search filter
                    if ReputationMatchesSearch(reputation, reputationSearchText) then
                        -- Check if we already have this faction
                        if not factionMap[factionID] then
                            -- First time seeing this faction
                            factionMap[factionID] = {
                                data = reputation,
                                characterKey = charKey,
                                characterName = char.name,
                                characterClass = char.classFile or char.class,
                                characterLevel = char.level,
                                allCharData = {
                                    {
                                        charKey = charKey,
                                        reputation = reputation,
                                    }
                                }
                            }
                        else
                            -- Add this character's data to the list
                            table.insert(factionMap[factionID].allCharData, {
                                charKey = charKey,
                                reputation = reputation,
                            })
                            
                            -- Compare with existing entry
                            if IsReputationHigher(reputation, factionMap[factionID].data) then
                                -- This character has higher reputation
                                factionMap[factionID].data = reputation
                                factionMap[factionID].characterKey = charKey
                                factionMap[factionID].characterName = char.name
                                factionMap[factionID].characterClass = char.classFile or char.class
                                factionMap[factionID].characterLevel = char.level
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Detect account-wide reputations
    for factionID, factionData in pairs(factionMap) do
        local isAccountWide = false
        
        -- Method 1: Check isMajorFaction flag from API
        if factionData.data.isMajorFaction then
            isAccountWide = true
        else
            -- Method 2: Calculate - if all characters have the exact same values, it's account-wide
            if #factionData.allCharData > 1 then
                local firstRep = factionData.allCharData[1].reputation
                local allSame = true
                
                for i = 2, #factionData.allCharData do
                    local otherRep = factionData.allCharData[i].reputation
                    
                    -- Compare key values
                    if firstRep.renownLevel ~= otherRep.renownLevel or
                       firstRep.standingID ~= otherRep.standingID or
                       firstRep.currentValue ~= otherRep.currentValue or
                       firstRep.paragonValue ~= otherRep.paragonValue then
                        allSame = false
                        break
                    end
                end
                
                if allSame then
                    isAccountWide = true
                end
            end
        end
        
        factionMap[factionID].isAccountWide = isAccountWide
    end
    
    -- Group by expansion headers (merge ALL characters' headers, PRESERVE ORDER)
    local headerGroups = {}
    local headerOrder = {}
    local seenHeaders = {}
    local headerFactionLists = {} -- Use ARRAYS to preserve order, not sets
    
    -- Collect ALL headers and faction IDs from ALL characters (preserve first seen order)
    for _, char in ipairs(characters) do
        if char.reputationHeaders and #char.reputationHeaders > 0 then
            for _, headerData in ipairs(char.reputationHeaders) do
                if not seenHeaders[headerData.name] then
                    seenHeaders[headerData.name] = true
                    table.insert(headerOrder, headerData.name)
                    headerFactionLists[headerData.name] = {}  -- Array, not set
                end
                
                -- Add factions in ORDER, avoiding duplicates
                local existingFactions = {}
                for _, fid in ipairs(headerFactionLists[headerData.name]) do
                    existingFactions[fid] = true
                end
                
                for _, factionID in ipairs(headerData.factions) do
                    if not existingFactions[factionID] then
                        table.insert(headerFactionLists[headerData.name], factionID)
                        existingFactions[factionID] = true
                    end
                end
            end
        end
    end
    
    -- Build header groups (preserve order from factionLists)
    for _, headerName in ipairs(headerOrder) do
        local headerFactions = {}
        
        -- Iterate in ORDER (not random key-value pairs)
        for _, factionID in ipairs(headerFactionLists[headerName]) do
            if factionMap[factionID] then
                table.insert(headerFactions, {
                    factionID = factionID,
                    data = factionMap[factionID].data,
                    characterKey = factionMap[factionID].characterKey,
                    characterName = factionMap[factionID].characterName,
                    characterClass = factionMap[factionID].characterClass,
                    characterLevel = factionMap[factionID].characterLevel,
                    isAccountWide = factionMap[factionID].isAccountWide,
                })
            end
        end
        
        if #headerFactions > 0 then
            headerGroups[headerName] = {
                name = headerName,
                factions = headerFactions,
            }
        end
    end
    
    -- Convert to ordered list
    local result = {}
    for _, headerName in ipairs(headerOrder) do
        table.insert(result, headerGroups[headerName])
    end
    
    return result
end

--============================================================================
-- REPUTATION ROW RENDERING
--============================================================================

---Create a single reputation row with progress bar
---@param parent Frame Parent frame
---@param reputation table Reputation data
---@param factionID number Faction ID
---@param rowIndex number Row index for alternating colors
---@param indent number Left indent
---@param width number Parent width
---@param yOffset number Y position
---@param subfactions table|nil Optional subfactions for expandable rows
---@param IsExpanded function Function to check expand state
---@param ToggleExpand function Function to toggle expand state
---@param characterInfo table|nil Optional {name, class, level, isAccountWide} for filtered view
---@return number newYOffset
---@return boolean|nil isExpanded
local function CreateReputationRow(parent, reputation, factionID, rowIndex, indent, width, yOffset, subfactions, IsExpanded, ToggleExpand, characterInfo)
    -- Create new row
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width - indent, ROW_HEIGHT) -- Standard height
    
    -- ALL main rows at same position (no extra indent for collapse button)
    -- Currency-style: 10 + indent
    row:SetPoint("TOPLEFT", 10 + indent, -yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    
    -- Alternating row colors
    row:SetBackdropColor(rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.09 or 0.06, 1)
    
    -- Collapse button for factions with subfactions
    local isExpanded = false
    
    if subfactions and #subfactions > 0 then
        local collapseKey = "rep-subfactions-" .. factionID
        isExpanded = IsExpanded(collapseKey, true)
        
        -- Create BUTTON frame (not texture) so it's clickable
        local collapseBtn = CreateFrame("Button", nil, row)
        collapseBtn:SetSize(16, 16)
        collapseBtn:SetPoint("RIGHT", row, "LEFT", -4, 0)  -- 4px gap before row starts
        
        -- Add texture to button
        local btnTexture = collapseBtn:CreateTexture(nil, "ARTWORK")
        btnTexture:SetAllPoints(collapseBtn)
        
        -- Set texture based on expand state
        if isExpanded then
            btnTexture:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        else
            btnTexture:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        end
        
        -- Make button clickable
        collapseBtn:SetScript("OnClick", function()
            ToggleExpand(collapseKey, not isExpanded)
        end)
        
        -- Also make row clickable (like headers)
        row:SetScript("OnClick", function()
            ToggleExpand(collapseKey, not isExpanded)
        end)
    end
    
    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", 10, 2)
    if reputation.iconTexture then
        icon:SetTexture(reputation.iconTexture)
    else
        icon:SetTexture("Interface\\Icons\\Achievement_Reputation_01")
    end
    
    -- Determine standing/renown text first
    local standingWord = ""  -- The word part (Renown, Friendly, etc)
    local standingNumber = ""  -- The number part (25, 8, etc)
    local standingColorCode = ""
    
    -- Priority: Check if Major Faction first, then Renown level, then standing
    if reputation.isMajorFaction or (reputation.renownLevel and reputation.renownLevel > 0) then
        -- Renown system: word + number
        standingWord = "Renown"
        standingNumber = tostring(reputation.renownLevel or 0)
        standingColorCode = "|cffffcc00" -- Gold for Renown
    elseif reputation.standingID then
        -- Classic reputation: just the standing name, no number
        standingWord = GetStandingName(reputation.standingID)
        standingNumber = ""  -- No number for classic standings
        local r, g, b = GetStandingColor(reputation.standingID)
        -- Convert RGB (0-1) to hex color code
        standingColorCode = format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    end
    
    -- Standing/Renown columns (fixed width, right-aligned for perfect alignment)
    if standingWord ~= "" then
        -- Standing word column (Renown/Friendly/etc) - RIGHT-aligned
        local standingText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        standingText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        standingText:SetJustifyH("RIGHT")
        standingText:SetWidth(75)  -- Fixed width to accommodate "Unfriendly" (longest standing name)
        standingText:SetText(standingColorCode .. standingWord .. "|r")
        
        -- Number column - ALWAYS reserve space (even if empty) for alignment
        local numberText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numberText:SetPoint("LEFT", standingText, "RIGHT", 2, 0)
        numberText:SetJustifyH("RIGHT")
        numberText:SetWidth(20)  -- Fixed width for 2-digit numbers (max is 30)
        
        if standingNumber ~= "" then
            -- Show number for Renown
            numberText:SetText(standingColorCode .. standingNumber .. "|r")
        else
            -- Leave empty for classic reputation, but still reserve the space
            numberText:SetText("")
        end
        
        -- Separator - always at the same position now
        local separator = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        separator:SetPoint("LEFT", numberText, "RIGHT", 4, 0)
        separator:SetText("|cff666666-|r")
        
        -- Faction Name (starts after separator)
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", separator, "RIGHT", 6, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetWidth(250)  -- Fixed width for name column
        nameText:SetText(reputation.name or "Unknown Faction")
        nameText:SetTextColor(1, 1, 1)
    else
        -- No standing: just faction name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetWidth(250)  -- Fixed width for name column
        nameText:SetText(reputation.name or "Unknown Faction")
        nameText:SetTextColor(1, 1, 1)
    end
    
    -- Character Badge Column (filtered view only)
    if characterInfo then
        local badgeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badgeText:SetPoint("LEFT", icon, "RIGHT", 285, 0)
        badgeText:SetJustifyH("LEFT")
        badgeText:SetWidth(120)
        
        if characterInfo.isAccountWide then
            badgeText:SetText("|cff666666(|r|cff00ff00Account-Wide|r|cff666666)|r")
        elseif characterInfo.name then
            local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
            local classHex = format("%02x%02x%02x", classColor.r*255, classColor.g*255, classColor.b*255)
            badgeText:SetText("|cff666666(|r|cff" .. classHex .. characterInfo.name .. "|r|cff666666)|r")
        end
    end
    
    -- Progress Bar (with border)
    local progressBarWidth = 200
    local progressBarHeight = 14
    
    -- Border frame for progress bar
    local progressBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    progressBorder:SetSize(progressBarWidth + 2, progressBarHeight + 2)
    progressBorder:SetPoint("RIGHT", -180, 0)
    progressBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    progressBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Background (inside border)
    local progressBg = row:CreateTexture(nil, "BACKGROUND")
    progressBg:SetSize(progressBarWidth, progressBarHeight)
    progressBg:SetPoint("CENTER", progressBorder, "CENTER", 0, 0)
    progressBg:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    
    -- Determine if we should use Paragon values or base reputation
    local currentValue = reputation.currentValue or 0
    local maxValue = reputation.maxValue or 1
    local isParagon = false
    local isCompleted = false
    
    -- Priority: If Paragon exists, use Paragon values instead
    if reputation.paragonValue and reputation.paragonThreshold then
        currentValue = reputation.paragonValue
        maxValue = reputation.paragonThreshold
        isParagon = true
    end
    
    -- Check if reputation is fully completed (no more progress possible)
    -- Check if BASE reputation is maxed (independent of Paragon)
    local baseReputationMaxed = false
    
    if isParagon then
        -- If Paragon exists, base reputation is ALWAYS maxed (you can't have Paragon without maxing base)
        baseReputationMaxed = true
    elseif reputation.renownLevel and reputation.renownMaxLevel then
        -- Renown system: check if at max level
        baseReputationMaxed = (reputation.renownLevel >= reputation.renownMaxLevel)
    else
        -- Classic reputation: check if at max
        baseReputationMaxed = (reputation.currentValue >= reputation.maxValue)
    end
    
    -- Add completion checkmark if base reputation is maxed (LEFT of progress bar, outside)
    if baseReputationMaxed then
        local checkmark = row:CreateTexture(nil, "OVERLAY")
        checkmark:SetSize(16, 16)
        checkmark:SetPoint("RIGHT", progressBorder, "LEFT", -4, 0)
        checkmark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    end
    
    -- Add Paragon reward icon if Paragon is active (RIGHT of progress bar, outside)
    if isParagon then
        local paragonIcon = row:CreateTexture(nil, "OVERLAY")
        paragonIcon:SetSize(18, 18)
        paragonIcon:SetPoint("LEFT", progressBorder, "RIGHT", 4, 0)
        
        -- Use modern atlas system (TWW compatible)
        if reputation.paragonRewardPending then
            -- Gold/highlighted - reward available!
            -- Try quest icon first (most likely match based on screenshot)
            local success = pcall(function()
                paragonIcon:SetAtlas("questlog-questtypeicon-legendary")
            end)
            
            if not success then
                -- Fallback to direct texture
                paragonIcon:SetTexture("Interface\\GossipFrame\\ActiveLegendaryQuestIcon")
            end
        else
            -- Gray - no reward yet
            local success = pcall(function()
                paragonIcon:SetAtlas("QuestNormal")
            end)
            
            if success then
                paragonIcon:SetVertexColor(0.5, 0.5, 0.5, 1)  -- Desaturate
            else
                -- Fallback to direct texture
                paragonIcon:SetTexture("Interface\\GossipFrame\\AvailableLegendaryQuestIcon")
                paragonIcon:SetVertexColor(0.5, 0.5, 0.5, 1)  -- Gray out
            end
        end
    end
    
    -- Only draw progress fill if there's actual progress (> 0)
    if currentValue > 0 then
        local progressBar = row:CreateTexture(nil, "ARTWORK")
        progressBar:SetPoint("LEFT", progressBg, "LEFT", 0, 0)
        progressBar:SetHeight(progressBarHeight)
        
        local progress = maxValue > 0 and (currentValue / maxValue) or 0
        progress = math.min(1, math.max(0, progress))
        
        progressBar:SetWidth(progressBarWidth * progress)
        
        -- Color progress bar
        if isParagon then
            -- Paragon: Pink
            progressBar:SetColorTexture(1, 0.4, 1, 1)
        elseif reputation.renownLevel and reputation.renownLevel > 0 then
            -- Renown: Gold
            progressBar:SetColorTexture(1, 0.82, 0, 1)
        else
            -- Standing color
            local r, g, b = GetStandingColor(reputation.standingID or 4)
            progressBar:SetColorTexture(r, g, b, 1)
        end
    end
    
    -- Progress Text (slightly bigger and bold)
    local progressText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("RIGHT", -10, 0)
    progressText:SetWidth(150)
    progressText:SetJustifyH("RIGHT")
    
    -- Make text bold and +2px bigger
    local font, size = progressText:GetFont()
    progressText:SetFont(font, size + 2, "OUTLINE")
    
    -- Format progress text based on state
    local progressDisplay
    if isParagon then
        -- Show Paragon progress only
        progressDisplay = FormatReputationProgress(currentValue, maxValue)
    elseif baseReputationMaxed then
        -- Show "Maxed" for completed reputations
        progressDisplay = "|cff00ff00Maxed|r"
    else
        -- Show normal progress
        progressDisplay = FormatReputationProgress(currentValue, maxValue)
    end
    
    progressText:SetText(progressDisplay)
    progressText:SetTextColor(1, 1, 1)  -- Pure white for better visibility

    
    -- Hover effect
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.20, 1)
        
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(reputation.name or "Reputation", 1, 1, 1)
        
        if reputation.description and reputation.description ~= "" then
            GameTooltip:AddLine(reputation.description, 0.8, 0.8, 0.8, true)
        end
        
        GameTooltip:AddLine(" ")
        
        -- Standing info (updated for new structure)
        if reputation.renownLevel and reputation.renownLevel > 0 then
            GameTooltip:AddDoubleLine("Renown Level:", format("%d / %d", reputation.renownLevel, reputation.renownMaxLevel or 25), 0.7, 0.7, 0.7, 1, 0.82, 0)
            GameTooltip:AddDoubleLine("Progress:", FormatReputationProgress(currentValue, maxValue), 0.7, 0.7, 0.7, 1, 0.82, 0)
        else
            local standingName = GetStandingName(reputation.standingID or 4)
            local r, g, b = GetStandingColor(reputation.standingID or 4)
            GameTooltip:AddDoubleLine("Standing:", standingName, 0.7, 0.7, 0.7, r, g, b)
            GameTooltip:AddDoubleLine("Progress:", FormatReputationProgress(currentValue, maxValue), 0.7, 0.7, 0.7, 1, 1, 1)
        end
        
        -- Paragon info (updated for new structure)
        if reputation.paragonValue and reputation.paragonThreshold then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Paragon Progress:", 1, 0.4, 1)
            GameTooltip:AddDoubleLine("Progress:", FormatReputationProgress(reputation.paragonValue, reputation.paragonThreshold), 0.7, 0.7, 0.7, 1, 0.4, 1)
            if reputation.paragonRewardPending then
                GameTooltip:AddLine("|cff00ff00Reward Available!|r", 1, 1, 1)
            end
        end
        
        -- Show if Renown faction
        if reputation.isRenown then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00Major Faction (Renown)|r", 0.8, 0.8, 0.8)
        end
        
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.09 or 0.06, 1)
        GameTooltip:Hide()
    end)
    
    return yOffset + ROW_SPACING, isExpanded
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawReputationTab(parent)
    LogOperation("Rep UI", "Started", "UI_REFRESH")
    
    -- Validate parent frame
    if not parent or not parent.GetChildren then
        return 0
    end
    
    -- Check if C_Reputation API is available (for modern WoW)
    if not C_Reputation or not C_Reputation.GetNumFactions then
        -- API not available - show error message
        local yOffset = 8
        local width = parent:GetWidth() - 20
        
        local errorFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        errorFrame:SetSize(width - 20, 100)
        errorFrame:SetPoint("TOPLEFT", 10, -yOffset)
        errorFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 }
        })
        errorFrame:SetBackdropColor(0.15, 0.05, 0.05, 0.9)
        errorFrame:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)
        
        local errorIcon = errorFrame:CreateTexture(nil, "ARTWORK")
        errorIcon:SetSize(32, 32)
        errorIcon:SetPoint("LEFT", 15, 0)
        errorIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
        
        local errorText = errorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        errorText:SetPoint("LEFT", errorIcon, "RIGHT", 10, 5)
        errorText:SetPoint("RIGHT", -10, 5)
        errorText:SetJustifyH("LEFT")
        errorText:SetText("|cffff4444Reputation API Not Available|r")
        
        local errorDesc = errorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        errorDesc:SetPoint("TOPLEFT", errorIcon, "TOPRIGHT", 10, -15)
        errorDesc:SetPoint("RIGHT", -10, 0)
        errorDesc:SetJustifyH("LEFT")
        errorDesc:SetTextColor(0.9, 0.9, 0.9)
        errorDesc:SetText("The C_Reputation API is not available on this server. This feature requires WoW 11.0+ (The War Within).")
        
        return yOffset + 120
    end
    
    -- Clear all old frames
    for _, child in pairs({parent:GetChildren()}) do
        if child:GetObjectType() ~= "Frame" then
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
        end
    end
    
    local yOffset = 8
    local width = parent:GetWidth() - 20
    -- No base indent needed at function level
    
    -- Get search text
    local reputationSearchText = (ns.reputationSearchText or ""):lower()
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    if not characters or #characters == 0 then
        DrawEmptyState(parent, "No character data available", yOffset)
        return yOffset + 50
    end
    
    -- Get faction metadata
    local factionMetadata = self.db.global.factionMetadata or {}
    
    -- Expanded state
    local expanded = self.db.profile.reputationExpanded or {}
    
    -- Get current online character
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    local currentCharKey = currentPlayerName .. "-" .. currentRealm
    
    -- Helper functions for expand/collapse
    local function IsExpanded(key, default)
        if expanded[key] == nil then
            return default or false
        end
        return expanded[key]
    end
    
    local function ToggleExpand(key, isExpanded)
        if not self.db.profile.reputationExpanded then
            self.db.profile.reputationExpanded = {}
        end
        self.db.profile.reputationExpanded[key] = isExpanded
        self:RefreshUI()
    end
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\Achievement_Reputation_01")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Reputation Tracker|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Track all active reputations and Renown in Blizzard's order")
    
    -- Toggle button for Filtered/Non-Filtered view
    local viewMode = self.db.profile.reputationViewMode or "all"
    local toggleBtn = CreateFrame("Button", nil, titleCard, "BackdropTemplate")
    toggleBtn:SetSize(160, 28)
    toggleBtn:SetPoint("RIGHT", -15, 0)
    toggleBtn:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    
    local COLORS = GetCOLORS()
    if viewMode == "filtered" then
        toggleBtn:SetBackdropColor(COLORS.tabActive[1], COLORS.tabActive[2], COLORS.tabActive[3], 1)
        toggleBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    else
        toggleBtn:SetBackdropColor(0.08, 0.08, 0.10, 1)
        toggleBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
    end
    
    -- Toggle icon
    local toggleIcon = toggleBtn:CreateTexture(nil, "ARTWORK")
    toggleIcon:SetSize(20, 20)
    toggleIcon:SetPoint("LEFT", 8, 0)
    if viewMode == "filtered" then
        toggleIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    else
        toggleIcon:SetTexture("Interface\\Icons\\Achievement_Character_Human_Male")
    end
    
    -- Toggle text
    local toggleText = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggleText:SetPoint("LEFT", toggleIcon, "RIGHT", 6, 0)
    if viewMode == "filtered" then
        toggleText:SetText("View: Filtered")
    else
        toggleText:SetText("View: All Characters")
    end
    toggleText:SetTextColor(0.9, 0.9, 0.9)
    
    -- Toggle click handler
    toggleBtn:SetScript("OnClick", function(btn)
        -- Toggle mode
        if self.db.profile.reputationViewMode == "filtered" then
            self.db.profile.reputationViewMode = "all"
        else
            self.db.profile.reputationViewMode = "filtered"
        end
        
        -- Refresh UI
        self:RefreshUI()
    end)
    
    -- Hover effect
    toggleBtn:SetScript("OnEnter", function(btn)
        btn:SetBackdropColor(0.15, 0.15, 0.18, 1)
        
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("View Mode", 1, 1, 1)
        GameTooltip:AddLine(" ")
        if viewMode == "filtered" then
            GameTooltip:AddLine("|cff00ff00Current: Filtered View|r", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Shows highest reputation from any character", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff888888Click to show all characters|r", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("|cff00ff00Current: All Characters View|r", 0.8, 0.8, 0.8)
            GameTooltip:AddLine("Shows reputations for each character", 0.7, 0.7, 0.7)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff888888Click to show filtered view|r", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    
    toggleBtn:SetScript("OnLeave", function(btn)
        if viewMode == "filtered" then
            btn:SetBackdropColor(COLORS.tabActive[1], COLORS.tabActive[2], COLORS.tabActive[3], 1)
        else
            btn:SetBackdropColor(0.08, 0.08, 0.10, 1)
        end
        GameTooltip:Hide()
    end)
    
    yOffset = yOffset + 78
    
    -- ===== RENDER CHARACTERS =====
    local hasAnyData = false
    local charactersWithReputations = {}
    
    -- Collect characters with reputations (no inactive filtering - scanner only saves active ones)
    for _, char in ipairs(characters) do
        if char.reputations and next(char.reputations) then
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
            local isOnline = (charKey == currentCharKey)
            
            -- Merge metadata with progress data (no inactive filtering - only active factions are stored)
            local matchingReputations = {}
            for factionID, progress in pairs(char.reputations) do
                local metadata = factionMetadata[factionID]
                
                -- If metadata doesn't exist, skip (shouldn't happen but safe)
                if metadata then
                    -- Merge metadata + progress into display structure
                    local reputation = {
                        name = metadata.name,
                        description = metadata.description,
                        iconTexture = metadata.iconTexture,
                        isRenown = metadata.isRenown,
                        canToggleAtWar = metadata.canToggleAtWar,
                        parentHeaders = metadata.parentHeaders,  -- For multi-level grouping
                        isHeader = metadata.isHeader,
                        isHeaderWithRep = metadata.isHeaderWithRep,
                        
                        -- Progress data from character
                        standingID = progress.standingID,
                        currentValue = progress.currentValue,
                        maxValue = progress.maxValue,
                        renownLevel = progress.renownLevel,
                        renownMaxLevel = progress.renownMaxLevel,
                        paragonValue = progress.paragonValue,
                        paragonThreshold = progress.paragonThreshold,
                        paragonRewardPending = progress.paragonRewardPending,
                        isWatched = progress.isWatched,
                        atWarWith = progress.atWarWith,
                        isMajorFaction = progress.isMajorFaction,  -- Flag to prevent duplicate display
                        lastUpdated = progress.lastUpdated,
                    }
                    
                    if ReputationMatchesSearch(reputation, reputationSearchText) then
                        table.insert(matchingReputations, {
                            id = factionID,
                            data = reputation,
                        })
                    end
                end
            end
            
            if #matchingReputations > 0 then
                hasAnyData = true
                table.insert(charactersWithReputations, {
                    char = char,
                    key = charKey,
                    reputations = matchingReputations,
                    isOnline = isOnline,
                    sortPriority = isOnline and 0 or 1,
                })
            end
        end
    end
    
    -- Sort (online first)
    table.sort(charactersWithReputations, function(a, b)
        if a.sortPriority ~= b.sortPriority then
            return a.sortPriority < b.sortPriority
        end
        return (a.char.name or "") < (b.char.name or "")
    end)
    
    if not hasAnyData then
        DrawEmptyState(parent, 
            reputationSearchText ~= "" and "No reputations match your search" or "No reputations found",
            yOffset)
        return yOffset + 100
    end
    
    -- Check view mode and render accordingly
    if viewMode == "filtered" then
        -- ===== FILTERED VIEW: Show highest reputation from any character =====
        
        local aggregatedHeaders = AggregateReputations(characters, factionMetadata, reputationSearchText)
        
        if not aggregatedHeaders or #aggregatedHeaders == 0 then
            DrawEmptyState(parent, 
                reputationSearchText ~= "" and "No reputations match your search" or "No reputations found",
                yOffset)
            return yOffset + 100
        end
        
        -- Helper function to get header icon
        local function GetHeaderIcon(headerName)
            if headerName:find("Guild") then
                return "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
            elseif headerName:find("Alliance") then
                return "Interface\\Icons\\Achievement_PVP_A_A"
            elseif headerName:find("Horde") then
                return "Interface\\Icons\\Achievement_PVP_H_H"
            elseif headerName:find("War Within") or headerName:find("Khaz Algar") then
                return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
            elseif headerName:find("Dragonflight") or headerName:find("Dragon") then
                return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
            elseif headerName:find("Shadowlands") then
                return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
            elseif headerName:find("Battle") or headerName:find("Azeroth") then
                return "Interface\\Icons\\INV_Sword_39"
            elseif headerName:find("Legion") then
                return "Interface\\Icons\\Spell_Shadow_Twilight"
            elseif headerName:find("Draenor") then
                return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
            elseif headerName:find("Pandaria") then
                return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
            elseif headerName:find("Cataclysm") then
                return "Interface\\Icons\\Spell_Fire_Flameshock"
            elseif headerName:find("Lich King") or headerName:find("Northrend") then
                return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
            elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
                return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
            elseif headerName:find("Classic") then
                return "Interface\\Icons\\INV_Misc_Book_11"
            else
                return "Interface\\Icons\\Achievement_Reputation_01"
            end
        end
        
        -- Separate account-wide and character-based reputations
        local accountWideHeaders = {}
        local characterBasedHeaders = {}
        
        for _, headerData in ipairs(aggregatedHeaders) do
            local awFactions = {}
            local cbFactions = {}
            
            for _, faction in ipairs(headerData.factions) do
                if faction.isAccountWide then
                    table.insert(awFactions, faction)
                else
                    table.insert(cbFactions, faction)
                end
            end
            
            if #awFactions > 0 then
                table.insert(accountWideHeaders, {
                    name = headerData.name,
                    factions = awFactions
                })
            end
            
            if #cbFactions > 0 then
                table.insert(characterBasedHeaders, {
                    name = headerData.name,
                    factions = cbFactions
                })
            end
        end
        
        -- Count total factions
        local totalAccountWide = 0
        for _, h in ipairs(accountWideHeaders) do
            totalAccountWide = totalAccountWide + #h.factions
        end
        
        local totalCharacterBased = 0
        for _, h in ipairs(characterBasedHeaders) do
            totalCharacterBased = totalCharacterBased + #h.factions
        end
        
        -- ===== ACCOUNT-WIDE REPUTATIONS SECTION =====
        local awSectionKey = "filtered-section-accountwide"
        local awSectionExpanded = IsExpanded(awSectionKey, false)  -- Default collapsed
        
        local awSectionHeader, _ = CreateCollapsibleHeader(
            parent,
            format("Account-Wide Reputations (%d)", totalAccountWide),
            awSectionKey,
            awSectionExpanded,
            function(isExpanded) ToggleExpand(awSectionKey, isExpanded) end,
            134376  -- File ID for Inv_Misc_Campfire_01
        )
        awSectionHeader:SetPoint("TOPLEFT", 10, -yOffset)
        awSectionHeader:SetWidth(width)
        awSectionHeader:SetBackdropColor(0.15, 0.08, 0.20, 1)  -- Purple-ish
        local COLORS = GetCOLORS()
        awSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        
        yOffset = yOffset + HEADER_SPACING
        
        if awSectionExpanded then
            if totalAccountWide == 0 then
                -- Empty state
                local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("TOPLEFT", 30, -yOffset)
                emptyText:SetTextColor(0.6, 0.6, 0.6)
                emptyText:SetText("No account-wide reputations")
                yOffset = yOffset + 30
            else
        
        -- Render each expansion header (Account-Wide)
        for _, headerData in ipairs(accountWideHeaders) do
            local headerKey = "filtered-header-" .. headerData.name
            local headerExpanded = IsExpanded(headerKey, true)
            
            if reputationSearchText ~= "" then
                headerExpanded = true
            end
            
            local header, headerBtn = CreateCollapsibleHeader(
                parent,
                headerData.name .. " (" .. #headerData.factions .. ")",
                headerKey,
                headerExpanded,
                function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                GetHeaderIcon(headerData.name)
            )
            header:SetPoint("TOPLEFT", 10, -yOffset)
            header:SetWidth(width)
            header:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
            local COLORS = GetCOLORS()
            local borderColor = COLORS.accent
            header:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
            
            yOffset = yOffset + HEADER_SPACING
            
            if headerExpanded then
                local headerIndent = CHAR_INDENT
                
                -- Group factions and subfactions (same as non-filtered)
                local factionList = {}
                local subfactionMap = {}
                
                for _, faction in ipairs(headerData.factions) do
                    if faction.data.isHeaderWithRep then
                        subfactionMap[faction.data.name] = {
                            parent = faction,
                            subfactions = {},
                            index = faction.factionID
                        }
                    end
                end
                
                for _, faction in ipairs(headerData.factions) do
                    local subHeader = faction.data.parentHeaders and faction.data.parentHeaders[2]
                    local isSpecialDirectFaction = (faction.data.name == "Winterpelt Furbolg" or faction.data.name == "Glimmerogg Racer")
                    
                    if faction.data.isHeaderWithRep then
                        table.insert(factionList, {
                            faction = faction,
                            subfactions = subfactionMap[faction.data.name].subfactions,
                            originalIndex = faction.factionID
                        })
                    elseif isSpecialDirectFaction then
                        table.insert(factionList, {
                            faction = faction,
                            subfactions = nil,
                            originalIndex = faction.factionID
                        })
                    elseif subHeader and subfactionMap[subHeader] then
                        table.insert(subfactionMap[subHeader].subfactions, faction)
                    else
                        table.insert(factionList, {
                            faction = faction,
                            subfactions = nil,
                            originalIndex = faction.factionID
                        })
                    end
                end
                
                -- Render factions
                local rowIdx = 0
                for _, item in ipairs(factionList) do
                    rowIdx = rowIdx + 1
                    
                    local charInfo = {
                        name = item.faction.characterName,
                        class = item.faction.characterClass,
                        level = item.faction.characterLevel,
                        isAccountWide = item.faction.isAccountWide
                    }
                    
                    local newYOffset, isExpanded = CreateReputationRow(
                        parent, 
                        item.faction.data, 
                        item.faction.factionID, 
                        rowIdx, 
                        headerIndent, 
                        width, 
                        yOffset, 
                        item.subfactions, 
                        IsExpanded, 
                        ToggleExpand, 
                        charInfo
                    )
                    yOffset = newYOffset
                    
                    if isExpanded and item.subfactions and #item.subfactions > 0 then
                        local subIndent = headerIndent + CATEGORY_INDENT
                        local subRowIdx = 0
                        for _, subFaction in ipairs(item.subfactions) do
                            subRowIdx = subRowIdx + 1
                            
                            local subCharInfo = {
                                name = subFaction.characterName,
                                class = subFaction.characterClass,
                                level = subFaction.characterLevel,
                                isAccountWide = subFaction.isAccountWide
                            }
                            
                            yOffset = CreateReputationRow(
                                parent, 
                                subFaction.data, 
                                subFaction.factionID, 
                                subRowIdx, 
                                subIndent, 
                                width, 
                                yOffset, 
                                nil, 
                                IsExpanded, 
                                ToggleExpand, 
                                subCharInfo
                            )
                        end
                    end
                end
            end
            
            yOffset = yOffset + 5
        end
        end  -- End Account-Wide section expanded
        end  -- End Account-Wide section
        
        yOffset = yOffset + 10
        
        -- ===== CHARACTER-BASED REPUTATIONS SECTION =====
        local cbSectionKey = "filtered-section-characterbased"
        local cbSectionExpanded = IsExpanded(cbSectionKey, false)  -- Default collapsed
        
        local cbSectionHeader, _ = CreateCollapsibleHeader(
            parent,
            format("Character-Based Reputations (%d)", totalCharacterBased),
            cbSectionKey,
            cbSectionExpanded,
            function(isExpanded) ToggleExpand(cbSectionKey, isExpanded) end,
            "Interface\\Icons\\Achievement_Character_Human_Male"
        )
        cbSectionHeader:SetPoint("TOPLEFT", 10, -yOffset)
        cbSectionHeader:SetWidth(width)
        cbSectionHeader:SetBackdropColor(0.08, 0.12, 0.15, 1)  -- Blue-ish
        cbSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        
        yOffset = yOffset + HEADER_SPACING
        
        if cbSectionExpanded then
            if totalCharacterBased == 0 then
                -- Empty state
                local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("TOPLEFT", 30, -yOffset)
                emptyText:SetTextColor(0.6, 0.6, 0.6)
                emptyText:SetText("No character-based reputations")
                yOffset = yOffset + 30
            else
                -- Render each expansion header (Character-Based)
                for _, headerData in ipairs(characterBasedHeaders) do
                    local headerKey = "filtered-cb-header-" .. headerData.name
                    local headerExpanded = IsExpanded(headerKey, true)
                    
                    if reputationSearchText ~= "" then
                        headerExpanded = true
                    end
                    
                    local header, headerBtn = CreateCollapsibleHeader(
                        parent,
                        headerData.name .. " (" .. #headerData.factions .. ")",
                        headerKey,
                        headerExpanded,
                        function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                        GetHeaderIcon(headerData.name)
                    )
                    header:SetPoint("TOPLEFT", 10 + CHAR_INDENT, -yOffset)
                    header:SetWidth(width - CHAR_INDENT)
                    header:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
                    header:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
                    
                    yOffset = yOffset + HEADER_SPACING
                    
                    if headerExpanded then
                        local headerIndent = CHAR_INDENT + EXPANSION_INDENT
                        
                        -- Group factions and subfactions (same logic)
                        local factionList = {}
                        local subfactionMap = {}
                        
                        for _, faction in ipairs(headerData.factions) do
                            if faction.data.isHeaderWithRep then
                                subfactionMap[faction.data.name] = {
                                    parent = faction,
                                    subfactions = {},
                                    index = faction.factionID
                                }
                            end
                        end
                        
                        for _, faction in ipairs(headerData.factions) do
                            local subHeader = faction.data.parentHeaders and faction.data.parentHeaders[2]
                            local isSpecialDirectFaction = (faction.data.name == "Winterpelt Furbolg" or faction.data.name == "Glimmerogg Racer")
                            
                            if faction.data.isHeaderWithRep then
                                table.insert(factionList, {
                                    faction = faction,
                                    subfactions = subfactionMap[faction.data.name].subfactions,
                                    originalIndex = faction.factionID
                                })
                            elseif isSpecialDirectFaction then
                                table.insert(factionList, {
                                    faction = faction,
                                    subfactions = nil,
                                    originalIndex = faction.factionID
                                })
                            elseif subHeader and subfactionMap[subHeader] then
                                table.insert(subfactionMap[subHeader].subfactions, faction)
                            else
                                table.insert(factionList, {
                                    faction = faction,
                                    subfactions = nil,
                                    originalIndex = faction.factionID
                                })
                            end
                        end
                        
                        -- Render factions
                        local rowIdx = 0
                        for _, item in ipairs(factionList) do
                            rowIdx = rowIdx + 1
                            
                            local charInfo = {
                                name = item.faction.characterName,
                                class = item.faction.characterClass,
                                level = item.faction.characterLevel,
                                isAccountWide = item.faction.isAccountWide
                            }
                            
                            local newYOffset, isExpanded = CreateReputationRow(
                                parent, 
                                item.faction.data, 
                                item.faction.factionID, 
                                rowIdx, 
                                headerIndent, 
                                width, 
                                yOffset, 
                                item.subfactions, 
                                IsExpanded, 
                                ToggleExpand, 
                                charInfo
                            )
                            yOffset = newYOffset
                            
                            if isExpanded and item.subfactions and #item.subfactions > 0 then
                                local subIndent = headerIndent + CATEGORY_INDENT
                                local subRowIdx = 0
                                for _, subFaction in ipairs(item.subfactions) do
                                    subRowIdx = subRowIdx + 1
                                    
                                    local subCharInfo = {
                                        name = subFaction.characterName,
                                        class = subFaction.characterClass,
                                        level = subFaction.characterLevel,
                                        isAccountWide = subFaction.isAccountWide
                                    }
                                    
                                    yOffset = CreateReputationRow(
                                        parent, 
                                        subFaction.data, 
                                        subFaction.factionID, 
                                        subRowIdx, 
                                        subIndent, 
                                        width, 
                                        yOffset, 
                                        nil, 
                                        IsExpanded, 
                                        ToggleExpand, 
                                        subCharInfo
                                    )
                                end
                            end
                        end
                    end
                    
                    yOffset = yOffset + 5
                end
            end
        end  -- End Character-Based section expanded
    else
        -- ===== NON-FILTERED VIEW =====
        
    -- Draw each character
    for _, charData in ipairs(charactersWithReputations) do
        local char = charData.char
        local charKey = charData.key
        local reputations = charData.reputations
        
        -- Character header
        local classColor = RAID_CLASS_COLORS[char.classFile or char.class] or {r=1, g=1, b=1}
        local onlineBadge = charData.isOnline and " |cff00ff00(Online)|r" or ""
        local charName = format("|c%s%s|r", 
            format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            char.name or "Unknown")
        
        local charKey_expand = "reputation-char-" .. charKey
        local charExpanded = IsExpanded(charKey_expand, charData.isOnline)
        
        if reputationSearchText ~= "" then
            charExpanded = true
        end
        
        -- Get class icon
        local classIconPath = nil
        local coords = CLASS_ICON_TCOORDS[char.classFile or char.class]
        if coords then
            classIconPath = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
        end
        
        local charHeader, charBtn, classIcon = CreateCollapsibleHeader(
            parent,
            format("%s%s - |cff888888%d reputations|r", charName, onlineBadge, #reputations),
            charKey_expand,
            charExpanded,
            function(isExpanded) ToggleExpand(charKey_expand, isExpanded) end,
            classIconPath
        )
        
        if classIcon and coords then
            classIcon:SetTexCoord(unpack(coords))
        end
        
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetWidth(width)
        charHeader:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
        local COLORS = GetCOLORS()
        local borderColor = COLORS.accent
        charHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
        
        yOffset = yOffset + HEADER_SPACING
        
        if charExpanded then
            local charIndent = CHAR_INDENT  -- Use standardized indent
            
            -- Header icons - smart detection (shared by both modes)
            local function GetHeaderIcon(headerName)
                -- Special faction types (Guild, Alliance, Horde)
                if headerName:find("Guild") then
                    return "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"
                elseif headerName:find("Alliance") then
                    return "Interface\\Icons\\Achievement_PVP_A_A"
                elseif headerName:find("Horde") then
                    return "Interface\\Icons\\Achievement_PVP_H_H"
                -- Expansions
                elseif headerName:find("War Within") or headerName:find("Khaz Algar") then
                    return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
                elseif headerName:find("Dragonflight") or headerName:find("Dragon") then
                    return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
                elseif headerName:find("Shadowlands") then
                    return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
                elseif headerName:find("Battle") or headerName:find("Azeroth") then
                    return "Interface\\Icons\\INV_Sword_39"
                elseif headerName:find("Legion") then
                    return "Interface\\Icons\\Spell_Shadow_Twilight"
                elseif headerName:find("Draenor") then
                    return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
                elseif headerName:find("Pandaria") then
                    return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
                elseif headerName:find("Cataclysm") then
                    return "Interface\\Icons\\Spell_Fire_Flameshock"
                elseif headerName:find("Lich King") or headerName:find("Northrend") then
                    return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
                elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
                    return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
                elseif headerName:find("Classic") then
                    return "Interface\\Icons\\INV_Misc_Book_11"
                else
                    return "Interface\\Icons\\Achievement_Reputation_01"
                end
            end
            
            -- ===== Use Blizzard's Reputation Headers =====
            local headers = char.reputationHeaders or {}
                
                for _, headerData in ipairs(headers) do
                    local headerReputations = {}
                    for _, factionID in ipairs(headerData.factions) do
                        for _, rep in ipairs(reputations) do
                            if rep.id == factionID then
                                table.insert(headerReputations, rep)
                                break
                            end
                        end
                    end
                    
                    if #headerReputations > 0 then
                        local headerKey = charKey .. "-header-" .. headerData.name
                        local headerExpanded = IsExpanded(headerKey, true)
                        
                        if reputationSearchText ~= "" then
                            headerExpanded = true
                        end
                        
                        -- Header (should be left-aligned, no extra indent)
                        local header, headerBtn = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. #headerReputations .. ")",
                            headerKey,
                            headerExpanded,
                            function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                            GetHeaderIcon(headerData.name)  -- Add icon support
                        )
                        header:SetPoint("TOPLEFT", 10 + charIndent, -yOffset)  -- Under character, but left-aligned
                        header:SetWidth(width - charIndent)
                        header:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
                        local COLORS = GetCOLORS()
                        local borderColor = COLORS.accent
                        header:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                        
                        yOffset = yOffset + HEADER_SPACING
                        
                        if headerExpanded then
                            local headerIndent = charIndent + EXPANSION_INDENT  -- Standardized indent for expansion content
                            
                            -- NEW APPROACH: Group factions and their subfactions (preserve API order)
                            local factionList = {}  -- Ordered list of factions to render
                            local subfactionMap = {}  -- Track which parent has subfactions
                            
                            -- First pass: identify isHeaderWithRep parents and init subfaction arrays
                            for _, rep in ipairs(headerReputations) do
                                if rep.data.isHeaderWithRep then
                                    subfactionMap[rep.data.name] = {
                                        parent = rep,
                                        subfactions = {},
                                        index = rep.id  -- Preserve original index
                                    }
                                end
                            end
                            
                            -- Second pass: assign factions to parents or direct list (preserve order)
                            for _, rep in ipairs(headerReputations) do
                                local subHeader = rep.data.parentHeaders and rep.data.parentHeaders[2]
                                
                                -- SPECIAL CASE: Winterpelt Furbolg and Glimmerogg Racer are direct factions, not subfactions
                                local isSpecialDirectFaction = (rep.data.name == "Winterpelt Furbolg" or rep.data.name == "Glimmerogg Racer")
                                
                                if rep.data.isHeaderWithRep then
                                    -- This is a parent - add to faction list
                                    table.insert(factionList, {
                                        rep = rep,
                                        subfactions = subfactionMap[rep.data.name].subfactions,
                                        originalIndex = rep.id  -- Track original API index
                                    })
                                elseif isSpecialDirectFaction then
                                    -- Force these to be direct factions (ignore parent info)
                                    table.insert(factionList, {
                                        rep = rep,
                                        subfactions = nil,
                                        originalIndex = rep.id
                                    })
                                elseif subHeader and subfactionMap[subHeader] then
                                    -- This is a subfaction of an isHeaderWithRep parent
                                    table.insert(subfactionMap[subHeader].subfactions, rep)
                                else
                                    -- Regular direct faction
                                    table.insert(factionList, {
                                        rep = rep,
                                        subfactions = nil,
                                        originalIndex = rep.id  -- Track original API index
                                    })
                                end
                            end
                            
                            -- NO SORTING - Keep Blizzard's API order
                            -- The order from headerData.factions already matches in-game UI
                            
                            -- Render factions
                            local rowIdx = 0
                            for _, item in ipairs(factionList) do
                                rowIdx = rowIdx + 1
                                local newYOffset, isExpanded = CreateReputationRow(parent, item.rep.data, item.rep.id, rowIdx, headerIndent, width, yOffset, item.subfactions, IsExpanded, ToggleExpand)
                                yOffset = newYOffset
                                
                                -- If expanded and has subfactions, render them nested
                                if isExpanded and item.subfactions and #item.subfactions > 0 then
                                    local subIndent = headerIndent + CATEGORY_INDENT  -- Standardized indent for subfactions
                                    local subRowIdx = 0
                                    for _, subRep in ipairs(item.subfactions) do
                                        subRowIdx = subRowIdx + 1
                                        yOffset = CreateReputationRow(parent, subRep.data, subRep.id, subRowIdx, subIndent, width, yOffset, nil, IsExpanded, ToggleExpand)
                                    end
                                end
                            end
                        end
                    end
                end
        end
        
        yOffset = yOffset + 5
    end
    end  -- End of viewMode if/else
    
    -- ===== FOOTER NOTE =====
    yOffset = yOffset + 15
    
    local noticeFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    noticeFrame:SetSize(width - 20, 60)
    noticeFrame:SetPoint("TOPLEFT", 10, -yOffset)
    noticeFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    noticeFrame:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    noticeFrame:SetBackdropBorderColor(0.5, 0.4, 0.2, 0.8)
    
    local noticeIcon = noticeFrame:CreateTexture(nil, "ARTWORK")
    noticeIcon:SetSize(24, 24)
    noticeIcon:SetPoint("LEFT", 10, 0)
    noticeIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    
    local noticeText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noticeText:SetPoint("LEFT", noticeIcon, "RIGHT", 10, 5)
    noticeText:SetPoint("RIGHT", -10, 5)
    noticeText:SetJustifyH("LEFT")
    noticeText:SetText("|cffffcc00Reputation Tracking|r")
    
    local noticeSubText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noticeSubText:SetPoint("TOPLEFT", noticeIcon, "TOPRIGHT", 10, -15)
    noticeSubText:SetPoint("RIGHT", -10, 0)
    noticeSubText:SetJustifyH("LEFT")
    noticeSubText:SetTextColor(0.8, 0.8, 0.8)
    noticeSubText:SetText("Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards.")
    
    yOffset = yOffset + 75
    
    LogOperation("Rep UI", "Finished", "UI_REFRESH")
    return yOffset
end
