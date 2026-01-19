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
    if WarbandNexus.db.profile.debugMode then
        local timestamp = date("%H:%M")
        print(string.format("%s - %s → %s (%s)", timestamp, operationName, status, trigger or "UI_REFRESH"))
    end
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
    local renown1 = (type(rep1.renownLevel) == "number") and rep1.renownLevel or 0
    local renown2 = (type(rep2.renownLevel) == "number") and rep2.renownLevel or 0
    
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
---Reads from db.global.reputations (global storage)
---@param characters table List of character data
---@param factionMetadata table Faction metadata
---@param reputationSearchText string Search filter
---@return table List of {headerName, factions={factionID, data, characterKey, characterName, characterClass, isAccountWide}}
local function AggregateReputations(characters, factionMetadata, reputationSearchText)
    -- Collect all unique faction IDs and their best reputation
    local factionMap = {} -- [factionID] = {data, characterKey, characterName, characterClass, allCharData}
    
    -- Read from global reputation storage
    local globalReputations = WarbandNexus.db.global.reputations or {}
    
    -- Build character lookup table
    local charLookup = {}
    for _, char in ipairs(characters) do
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        charLookup[charKey] = char
    end
    
    -- Iterate through all reputations in global storage
    for factionID, repData in pairs(globalReputations) do
        factionID = tonumber(factionID) or factionID
        -- Try both numeric and string keys for metadata lookup
        local metadata = factionMetadata[factionID] or factionMetadata[tostring(factionID)] or {}
        
        -- Build base reputation data from global storage
        local baseReputation = {
            name = repData.name or metadata.name or ("Faction " .. tostring(factionID)),
                        description = metadata.description,
            iconTexture = repData.icon or metadata.iconTexture,
            isRenown = repData.isRenown or metadata.isRenown,
                        canToggleAtWar = metadata.canToggleAtWar,
                        parentHeaders = metadata.parentHeaders,
                        isHeader = metadata.isHeader,
                        isHeaderWithRep = metadata.isHeaderWithRep,
            isMajorFaction = repData.isMajorFaction,
        }
        
        if repData.isAccountWide then
            -- Account-wide reputation: single value for all characters
            local progress = repData.value or {}
            local reputation = {
                name = baseReputation.name,
                description = baseReputation.description,
                iconTexture = baseReputation.iconTexture,
                isRenown = baseReputation.isRenown,
                canToggleAtWar = baseReputation.canToggleAtWar,
                parentHeaders = baseReputation.parentHeaders,
                isHeader = baseReputation.isHeader,
                isHeaderWithRep = baseReputation.isHeaderWithRep,
                isMajorFaction = baseReputation.isMajorFaction,
                        
                        standingID = progress.standingID,
                currentValue = progress.currentValue or 0,
                maxValue = progress.maxValue or 0,
                        renownLevel = progress.renownLevel,
                        renownMaxLevel = progress.renownMaxLevel,
                        rankName = progress.rankName,
                        paragonValue = progress.paragonValue,
                        paragonThreshold = progress.paragonThreshold,
                paragonRewardPending = progress.hasParagonReward,
                        isWatched = progress.isWatched,
                        atWarWith = progress.atWarWith,
                        lastUpdated = progress.lastUpdated,
                    }
                    
                    -- Check search filter
                    if ReputationMatchesSearch(reputation, reputationSearchText) then
                -- Use first character as representative
                local firstChar = characters[1]
                local charKey = firstChar and ((firstChar.name or "Unknown") .. "-" .. (firstChar.realm or "Unknown")) or "Account"
                
                factionMap[factionID] = {
                    data = reputation,
                    characterKey = charKey,
                    characterName = firstChar and firstChar.name or "Account",
                    characterClass = firstChar and (firstChar.classFile or firstChar.class) or "WARRIOR",
                    characterLevel = firstChar and firstChar.level or 80,
                    isAccountWide = true,
                    allCharData = {{
                        charKey = charKey,
                        reputation = reputation,
                    }}
                }
            end
        else
            -- Character-specific reputation: iterate through chars table
            local chars = repData.chars or {}
            
            for charKey, progress in pairs(chars) do
                local char = charLookup[charKey]
                if char then
                    local reputation = {
                        name = baseReputation.name,
                        description = baseReputation.description,
                        iconTexture = baseReputation.iconTexture,
                        isRenown = baseReputation.isRenown,
                        canToggleAtWar = baseReputation.canToggleAtWar,
                        parentHeaders = baseReputation.parentHeaders,
                        isHeader = baseReputation.isHeader,
                        isHeaderWithRep = baseReputation.isHeaderWithRep,
                        isMajorFaction = baseReputation.isMajorFaction,
                        
                        standingID = progress.standingID,
                        currentValue = progress.currentValue or 0,
                        maxValue = progress.maxValue or 0,
                        renownLevel = progress.renownLevel,
                        renownMaxLevel = progress.renownMaxLevel,
                        rankName = progress.rankName,
                        paragonValue = progress.paragonValue,
                        paragonThreshold = progress.paragonThreshold,
                        paragonRewardPending = progress.hasParagonReward,
                        isWatched = progress.isWatched,
                        atWarWith = progress.atWarWith,
                        lastUpdated = progress.lastUpdated,
                    }
                    
                    -- Check search filter
                    if ReputationMatchesSearch(reputation, reputationSearchText) then
                        if not factionMap[factionID] then
                            -- First time seeing this faction
                            factionMap[factionID] = {
                                data = reputation,
                                characterKey = charKey,
                                characterName = char.name,
                                characterClass = char.classFile or char.class,
                                characterLevel = char.level,
                                isAccountWide = false,
                                allCharData = {{
                                        charKey = charKey,
                                        reputation = reputation,
                                }}
                            }
                        else
                            -- Add this character's data
                            table.insert(factionMap[factionID].allCharData, {
                                charKey = charKey,
                                reputation = reputation,
                            })
                            
                            -- Compare with existing entry
                            if IsReputationHigher(reputation, factionMap[factionID].data) then
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
        
        -- Method 0: Check stored isAccountWide flag from API (highest priority)
        local globalRepData = globalReputations[factionID]
        if globalRepData and globalRepData.isAccountWide ~= nil then
            isAccountWide = globalRepData.isAccountWide
        -- Method 1: Check isMajorFaction flag from API
        elseif factionData.data.isMajorFaction then
            isAccountWide = true
        else
            -- Method 2: Calculate - if all characters have the exact same values, it's account-wide
            if #factionData.allCharData > 1 then
                local firstRep = factionData.allCharData[1].reputation
                local allSame = true
                
                for i = 2, #factionData.allCharData do
                    local otherRep = factionData.allCharData[i].reputation
                    
                    -- Compare key values (including paragon reward status)
                    if firstRep.renownLevel ~= otherRep.renownLevel or
                       firstRep.standingID ~= otherRep.standingID or
                       firstRep.currentValue ~= otherRep.currentValue or
                       firstRep.paragonValue ~= otherRep.paragonValue or
                       firstRep.paragonRewardPending ~= otherRep.paragonRewardPending then
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
    
    -- Use global reputation headers
    local globalHeaders = WarbandNexus.db.global.reputationHeaders or {}
    
    for _, headerData in ipairs(globalHeaders) do
        if headerData and headerData.name then
                if not seenHeaders[headerData.name] then
                    seenHeaders[headerData.name] = true
                    table.insert(headerOrder, headerData.name)
                    headerFactionLists[headerData.name] = {}  -- Array, not set
                end
                
                -- Add factions in ORDER, avoiding duplicates
                local existingFactions = {}
                for _, fid in ipairs(headerFactionLists[headerData.name]) do
                -- Convert to number for consistent comparison
                local numFid = tonumber(fid) or fid
                existingFactions[numFid] = true
                end
                
            for _, factionID in ipairs(headerData.factions or {}) do
                -- Convert to number for consistent comparison
                local numFactionID = tonumber(factionID) or factionID
                if not existingFactions[numFactionID] then
                    table.insert(headerFactionLists[headerData.name], numFactionID)
                    existingFactions[numFactionID] = true
                end
            end
        end
    end
    
    -- Build header groups (preserve order from factionLists)
    for _, headerName in ipairs(headerOrder) do
        local headerFactions = {}
        
        -- Iterate in ORDER (not random key-value pairs)
        for _, factionID in ipairs(headerFactionLists[headerName]) do
            -- Ensure consistent type for lookup
            local numFactionID = tonumber(factionID) or factionID
            local factionData = factionMap[numFactionID]
            if factionData then
                table.insert(headerFactions, {
                    factionID = numFactionID,
                    data = factionData.data,
                    characterKey = factionData.characterKey,
                    characterName = factionData.characterName,
                    characterClass = factionData.characterClass,
                    characterLevel = factionData.characterLevel,
                    isAccountWide = factionData.isAccountWide,
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

---Truncate text if it's too long
---@param text string Text to truncate
---@param maxLength number Maximum length before truncation
---@return string Truncated text
local function TruncateText(text, maxLength)
    if not text then return "" end
    if string.len(text) <= maxLength then
        return text
    end
    return string.sub(text, 1, maxLength - 3) .. "..."
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
    row:SetPoint("TOPLEFT", indent, -yOffset)
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
    
    -- Priority: Check if named rank (Friendship), then Renown level, then standing
    if reputation.rankName then
        -- Named rank (Friendship system)
        -- Show only rank name in main display (scores shown in tooltip only)
        standingWord = reputation.rankName
        standingNumber = "" -- No separate number column for Friendship
        standingColorCode = "|cffffcc00" -- Gold for Special Ranks
    elseif reputation.isMajorFaction or (reputation.renownLevel and type(reputation.renownLevel) == "number" and reputation.renownLevel > 0) then
        -- Renown system: word + number
        standingWord = "Renown"
        standingNumber = tostring(reputation.renownLevel or 0)
        -- Don't append " / ?" - just show current level
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
            -- Leave empty for classic reputation or named ranks, but still reserve the space
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
        nameText:SetNonSpaceWrap(true)
        nameText:SetWidth(250)  -- Fixed width for name column
        nameText:SetText(TruncateText(reputation.name or "Unknown Faction", 35))
        nameText:SetTextColor(1, 1, 1)
    else
        -- No standing: just faction name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(true)
        nameText:SetWidth(250)  -- Fixed width for name column
        nameText:SetText(TruncateText(reputation.name or "Unknown Faction", 35))
        nameText:SetTextColor(1, 1, 1)
    end
    
    -- Character Badge Column (filtered view only)
    if characterInfo then
        local badgeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badgeText:SetPoint("LEFT", icon, "RIGHT", 330, 0)
        badgeText:SetJustifyH("LEFT")
        badgeText:SetWidth(150)
        
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
    local progressBarHeight = 16  -- Increased from 14 to 16
    
    -- Border frame for progress bar
    local progressBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
    progressBorder:SetSize(progressBarWidth + 2, progressBarHeight + 2)
    progressBorder:SetPoint("RIGHT", -10, 0)  -- Moved closer to right edge
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
    elseif reputation.renownLevel and reputation.renownMaxLevel and reputation.renownMaxLevel > 0 and type(reputation.renownLevel) == "number" then
        -- Renown system: check if at max level (numeric comparison only)
        baseReputationMaxed = (reputation.renownLevel >= reputation.renownMaxLevel)
    else
        -- Classic reputation: check if at max
        baseReputationMaxed = (reputation.currentValue >= reputation.maxValue)
    end
    
    -- Add Paragon reward icon if Paragon is active (LEFT of checkmark)
    if isParagon then
        -- Create frame for tooltip support
        local paragonFrame = CreateFrame("Frame", nil, row)
        paragonFrame:SetSize(18, 18)
        paragonFrame:SetPoint("RIGHT", progressBorder, "LEFT", -24, 0)
        
        local paragonIcon = paragonFrame:CreateTexture(nil, "OVERLAY")
        paragonIcon:SetAllPoints()
        
        -- Use modern atlas system (TWW compatible)
        if reputation.paragonRewardPending then
            -- Gold/highlighted - reward available!
            local success = pcall(function()
                paragonIcon:SetAtlas("ParagonReputation_Bag")
            end)
            
            if not success then
                paragonIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
            end
        else
            -- Gray - no reward yet
            local success = pcall(function()
                paragonIcon:SetAtlas("ParagonReputation_Bag")
            end)
            
            if success then
                paragonIcon:SetVertexColor(0.5, 0.5, 0.5, 1)
            else
                paragonIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
                paragonIcon:SetVertexColor(0.5, 0.5, 0.5, 1)
            end
        end
        
        -- Add tooltip
        paragonFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if reputation.paragonRewardPending then
                GameTooltip:SetText("Paragon Reward Available", 1, 0.82, 0, 1)
                GameTooltip:AddLine("You can claim a reward!", 1, 1, 1, true)
                
                -- Show character name if in filtered view
                if characterInfo and characterInfo.name and not characterInfo.isAccountWide then
                    local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
                    GameTooltip:AddLine(" ", 1, 1, 1)  -- Spacer
                    GameTooltip:AddLine(format("Character: |cff%02x%02x%02x%s|r", 
                        classColor.r*255, classColor.g*255, classColor.b*255, 
                        characterInfo.name), 0.8, 0.8, 0.8)
                end
            else
                GameTooltip:SetText("Paragon Progress", 1, 0.4, 1, 1)
                GameTooltip:AddLine("Continue earning reputation for rewards", 1, 1, 1, true)
                
                -- Show character name if in filtered view
                if characterInfo and characterInfo.name and not characterInfo.isAccountWide then
                    local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
                    GameTooltip:AddLine(" ", 1, 1, 1)  -- Spacer
                    GameTooltip:AddLine(format("Character: |cff%02x%02x%02x%s|r", 
                        classColor.r*255, classColor.g*255, classColor.b*255, 
                        characterInfo.name), 0.8, 0.8, 0.8)
                end
            end
            GameTooltip:Show()
        end)
        paragonFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    
    -- Add completion checkmark if base reputation is maxed (LEFT of progress bar)
    if baseReputationMaxed then
        -- Create frame for tooltip support
        local checkFrame = CreateFrame("Frame", nil, row)
        checkFrame:SetSize(16, 16)
        checkFrame:SetPoint("RIGHT", progressBorder, "LEFT", -4, 0)
        
        local checkmark = checkFrame:CreateTexture(nil, "OVERLAY")
        checkmark:SetAllPoints()
        checkmark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        
        -- Add tooltip with specific type
        checkFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Max Reached", 0, 1, 0, 1)
            
            -- Determine reputation type and show appropriate message
            if reputation.rankName then
                -- Friendship reputation
                GameTooltip:AddLine("This friendship is at maximum level", 1, 1, 1, true)
            elseif reputation.renownLevel and type(reputation.renownLevel) == "number" and reputation.renownLevel > 0 then
                -- Renown faction
                GameTooltip:AddLine("This renown is at maximum level", 1, 1, 1, true)
            else
                -- Classic reputation
                GameTooltip:AddLine("This reputation is at maximum level", 1, 1, 1, true)
            end
            
            GameTooltip:Show()
        end)
        checkFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    
    -- Only draw progress fill if there's actual progress (> 0) OR if maxed
    if currentValue > 0 or baseReputationMaxed then
        local progressBar = row:CreateTexture(nil, "ARTWORK")
        progressBar:SetPoint("LEFT", progressBg, "LEFT", 0, 0)
        progressBar:SetHeight(progressBarHeight)
        
        local progress = maxValue > 0 and (currentValue / maxValue) or 0
        progress = math.min(1, math.max(0, progress))
        
        -- If maxed and not paragon, fill the entire bar
        if baseReputationMaxed and not isParagon then
            progress = 1
        end
        
        progressBar:SetWidth(progressBarWidth * progress)
        
        -- Color progress bar
        if baseReputationMaxed and not isParagon then
            -- Maxed: Green
            progressBar:SetColorTexture(0, 0.8, 0, 1)  -- Nice green color
        elseif isParagon then
            -- Paragon: Pink
            progressBar:SetColorTexture(1, 0.4, 1, 1)
        elseif reputation.rankName or (reputation.renownLevel and type(reputation.renownLevel) == "number" and reputation.renownLevel > 0) then
            -- Renown / Special Rank: Gold
            progressBar:SetColorTexture(1, 0.82, 0, 1)
        else
            -- Standing color
            local r, g, b = GetStandingColor(reputation.standingID or 4)
            progressBar:SetColorTexture(r, g, b, 1)
        end
    end
    
    -- Progress Text - positioned INSIDE the progress bar with shadow
    local progressText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("CENTER", progressBg, "CENTER", 0, 0)  -- Center in the progress bar
    progressText:SetJustifyH("CENTER")
    
    -- Make text bold with shadow for readability
    local font, size = progressText:GetFont()
    progressText:SetFont(font, size + 1, "OUTLINE")  -- OUTLINE adds shadow
    progressText:SetShadowOffset(1, -1)  -- Additional shadow for better contrast
    progressText:SetShadowColor(0, 0, 0, 1)  -- Black shadow
    
    -- Format progress text based on state
    local progressDisplay
    if isParagon then
        -- Show Paragon progress only
        progressDisplay = FormatReputationProgress(currentValue, maxValue)
    elseif baseReputationMaxed then
        -- Show "Maxed" for completed reputations (white text)
        progressDisplay = "|cffffffffMaxed|r"
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
        if reputation.rankName then
            -- Friendship rank with named title (e.g., Mastermind, Professional, True Friend)
            
            -- Always show rank name
            GameTooltip:AddDoubleLine("Current Rank:", reputation.rankName, 0.7, 0.7, 0.7, 1, 0.82, 0)
            
            -- Show rank number if available (e.g., "Rank: 9 / 9" or "Rank: 5 / 8")
            if reputation.renownLevel and type(reputation.renownLevel) == "number" and 
               reputation.renownMaxLevel and reputation.renownMaxLevel > 0 then
                GameTooltip:AddDoubleLine("Rank:", 
                    format("%d / %d", reputation.renownLevel, reputation.renownMaxLevel), 
                    0.7, 0.7, 0.7, 1, 0.82, 0)
            end
            
            -- Show Paragon Progress for Friendship reputations (entire line pink)
            if reputation.paragonValue and reputation.paragonThreshold then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine("Paragon Progress:", 
                    FormatReputationProgress(reputation.paragonValue, reputation.paragonThreshold), 
                    1, 0.4, 1, 1, 0.4, 1)  -- Both label and value in pink
                if reputation.paragonRewardPending then
                    GameTooltip:AddLine("|cff00ff00Reward Available!|r", 1, 1, 1)
                end
            end
        elseif reputation.renownLevel and type(reputation.renownLevel) == "number" and reputation.renownLevel > 0 then
            -- Standard Renown system - only show " / max" if max is known
            local maxLevel = reputation.renownMaxLevel
            
            -- If maxLevel is 0 or nil, try to get it from API in real-time
            if (not maxLevel or maxLevel == 0) and factionID and C_MajorFactions and C_MajorFactions.GetMaximumRenownLevel then
                maxLevel = C_MajorFactions.GetMaximumRenownLevel(factionID)
            end
            
            -- Only show " / max" format if max is known and greater than 0
            if maxLevel and maxLevel > 0 then
                GameTooltip:AddDoubleLine("Renown Level:", 
                    format("%d / %d", reputation.renownLevel, maxLevel), 
                    0.7, 0.7, 0.7, 1, 0.82, 0)
            else
                -- Don't show max if unknown (no " / ?")
                GameTooltip:AddDoubleLine("Renown Level:", 
                    tostring(reputation.renownLevel), 
                    0.7, 0.7, 0.7, 1, 0.82, 0)
            end
        else
            local standingName = GetStandingName(reputation.standingID or 4)
            local r, g, b = GetStandingColor(reputation.standingID or 4)
            GameTooltip:AddDoubleLine("Standing:", standingName, 0.7, 0.7, 0.7, r, g, b)
        end
        
        -- Paragon info for NON-friendship reputations (Friendship already shows paragon above)
        if not reputation.rankName and reputation.paragonValue and reputation.paragonThreshold then
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

function WarbandNexus:DrawReputationList(container, width)
    if not container then return 0 end
    
    -- Clear container
    for _, child in pairs({container:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local parent = container
    local yOffset = 0
    

    
    -- ===== TITLE CARD (Always shown) =====
    

    
    -- Check if module is disabled - show message below header
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.reputations then
        local disabledText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        disabledText:SetPoint("TOP", parent, "TOP", 0, -yOffset - 50)
        disabledText:SetText("|cff888888Module disabled. Check the box above to enable.|r")
        return yOffset + 100
    end
    
    -- Check if C_Reputation API is available (for modern WoW)
    if not C_Reputation or not C_Reputation.GetNumFactions then
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
    
    -- ===== RENDER CHARACTERS =====
    local hasAnyData = false
    local charactersWithReputations = {}
    
    -- Collect characters with reputations from global storage
    local globalReputations = self.db.global.reputations or {}
    
    -- Build character lookup
    local charLookup = {}
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        charLookup[charKey] = char
    end
    
    -- Build per-character reputation data from global storage
    for _, char in ipairs(characters) do
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
            local isOnline = (charKey == currentCharKey)
            
            local matchingReputations = {}
        
        for factionID, repData in pairs(globalReputations) do
            factionID = tonumber(factionID) or factionID
            -- Try both numeric and string keys for metadata lookup
            local metadata = factionMetadata[factionID] or factionMetadata[tostring(factionID)] or {}
            
            -- Get progress data for this character
            local progress = nil
            if repData.isAccountWide then
                progress = repData.value
            else
                progress = repData.chars and repData.chars[charKey]
            end
            
            if progress then
                -- Build reputation display object
                    local reputation = {
                    name = repData.name or metadata.name or ("Faction " .. tostring(factionID)),
                        description = metadata.description,
                    iconTexture = repData.icon or metadata.iconTexture,
                    isRenown = repData.isRenown or metadata.isRenown,
                        canToggleAtWar = metadata.canToggleAtWar,
                    parentHeaders = metadata.parentHeaders,
                        isHeader = metadata.isHeader,
                        isHeaderWithRep = metadata.isHeaderWithRep,
                    isMajorFaction = repData.isMajorFaction,
                        
                        standingID = progress.standingID,
                    currentValue = progress.currentValue or 0,
                    maxValue = progress.maxValue or 0,
                        renownLevel = progress.renownLevel,
                        renownMaxLevel = progress.renownMaxLevel,
                        rankName = progress.rankName,
                        paragonValue = progress.paragonValue,
                        paragonThreshold = progress.paragonThreshold,
                    paragonRewardPending = progress.hasParagonReward,
                        isWatched = progress.isWatched,
                        atWarWith = progress.atWarWith,
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
        
        local awSectionHeader, awExpandBtn, awSectionIcon = CreateCollapsibleHeader(
            parent,
            format("Account-Wide Reputations (%d)", totalAccountWide),
            awSectionKey,
            awSectionExpanded,
            function(isExpanded) ToggleExpand(awSectionKey, isExpanded) end,
            "dummy"  -- Dummy value to trigger icon creation
        )
        
        -- Replace with Warband atlas icon (27x36 for proper aspect ratio)
        if awSectionIcon then
            awSectionIcon:SetTexture(nil)  -- Clear dummy texture
            awSectionIcon:SetAtlas("warbands-icon")
            awSectionIcon:SetSize(27, 36)  -- Native atlas proportions (23:31)
        end
        awSectionHeader:SetPoint("TOPLEFT", 10, -yOffset)
        awSectionHeader:SetPoint("TOPRIGHT", -10, -yOffset)
        awSectionHeader:SetWidth(width)
        -- Removing custom tint to match other tabs/headers
        -- awSectionHeader:SetBackdropColor(0.15, 0.08, 0.20, 1)  -- Purple-ish
        -- local COLORS = GetCOLORS()
        -- awSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        
        yOffset = yOffset + HEADER_SPACING
        
        if awSectionExpanded then
            if totalAccountWide == 0 then
                -- Empty state
                local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("TOPLEFT", 20, -yOffset)
                emptyText:SetTextColor(1, 1, 1)  -- White
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
            header:SetPoint("TOPLEFT", EXPANSION_INDENT, -yOffset)  -- Indent under Account-Wide section
            header:SetWidth(width - EXPANSION_INDENT)  -- Adjust width for indent
            header:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
            local COLORS = GetCOLORS()
            local borderColor = COLORS.accent
            header:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
            
            yOffset = yOffset + HEADER_SPACING
            
            if headerExpanded then
                local headerIndent = EXPANSION_INDENT + CHAR_INDENT  -- Indent for faction rows under expansion header
                
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
        end
        end  -- End Account-Wide section expanded
        end  -- End Account-Wide section
        
        -- ===== CHARACTER-BASED REPUTATIONS SECTION =====
        local cbSectionKey = "filtered-section-characterbased"
        local cbSectionExpanded = IsExpanded(cbSectionKey, false)  -- Default collapsed
        
        local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
        local cbSectionHeader, _ = CreateCollapsibleHeader(
            parent,
            format("Character-Based Reputations (%d)", totalCharacterBased),
            cbSectionKey,
            cbSectionExpanded,
            function(isExpanded) ToggleExpand(cbSectionKey, isExpanded) end,
            GetCharacterSpecificIcon(),
            true  -- isAtlas = true
        )
        cbSectionHeader:SetPoint("TOPLEFT", 10, -yOffset)
        cbSectionHeader:SetPoint("TOPRIGHT", -10, -yOffset)
        cbSectionHeader:SetWidth(width)
        -- Removing custom tint to match other tabs/headers
        -- cbSectionHeader:SetBackdropColor(0.08, 0.12, 0.15, 1)  -- Blue-ish
        -- cbSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        
        yOffset = yOffset + HEADER_SPACING
        
        if cbSectionExpanded then
            if totalCharacterBased == 0 then
                -- Empty state
                local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("TOPLEFT", 20, -yOffset)
                emptyText:SetTextColor(1, 1, 1)  -- White
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
                    header:SetPoint("TOPLEFT", CHAR_INDENT, -yOffset)
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
        charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
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
            
            -- ===== Use Global Reputation Headers (v2) =====
            local headers = self.db.global.reputationHeaders or {}
                
                for _, headerData in ipairs(headers) do
                    local headerReputations = {}
                    local headerFactions = headerData.factions or {}
                    for _, factionID in ipairs(headerFactions) do
                        -- Ensure consistent type comparison (both as numbers)
                        local numFactionID = tonumber(factionID) or factionID
                        for _, rep in ipairs(reputations) do
                            local numRepID = tonumber(rep.id) or rep.id
                            if numRepID == numFactionID then
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
                        header:SetPoint("TOPLEFT", charIndent, -yOffset)  -- Under character, but left-aligned
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
    noticeSubText:SetTextColor(1, 1, 1)  -- White
    noticeSubText:SetText("Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards.")
    
    yOffset = yOffset + 75
    
    LogOperation("Rep UI", "Finished", "UI_REFRESH")
    return yOffset
end

--============================================================================
-- REPUTATION TAB WRAPPER (Fixes focus issue)
--============================================================================

function WarbandNexus:DrawReputationTab(parent)
    -- Clear all old frames
    for _, child in pairs({parent:GetChildren()}) do
        if child:GetObjectType() ~= "Frame" then
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
        end
    end
    
    local yOffset = 8 -- Top padding
    local width = parent:GetWidth() - 20
    
    -- ===== TITLE CARD =====
    local CreateCard = ns.UI_CreateCard
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Header icon with ring border
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("reputation"))
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 5)
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Reputation Overview|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, -12)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetText("Track factions and renown across your warband")
    
    -- Module Enable/Disable Checkbox
    local enableCheckbox = CreateFrame("CheckButton", nil, titleCard, "UICheckButtonTemplate")
    enableCheckbox:SetSize(24, 24)
    enableCheckbox:SetPoint("RIGHT", titleCard, "RIGHT", -15, 0)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.reputations ~= false
    enableCheckbox:SetChecked(moduleEnabled)
    
    local checkboxLabel = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkboxLabel:SetPoint("RIGHT", enableCheckbox, "LEFT", -5, 0)
    checkboxLabel:SetText("Enable")
    checkboxLabel:SetTextColor(1, 1, 1)
    
    enableCheckbox:SetScript("OnClick", function(checkbox)
        local enabled = checkbox:GetChecked()
        self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
        self.db.profile.modulesEnabled.reputations = enabled
        if enabled and self.UpdateReputationData then
            self:UpdateReputationData()
        end
        if self.RefreshUI then self:RefreshUI() end
    end)
    
    -- View Mode Toggle Button
    local viewMode = self.db.profile.reputationViewMode or "all"
    local toggleBtn = CreateFrame("Button", nil, titleCard, "UIPanelButtonTemplate")
    toggleBtn:SetSize(120, 25)
    toggleBtn:SetPoint("RIGHT", checkboxLabel, "LEFT", -15, 0)
    toggleBtn:SetText(viewMode == "filtered" and "Filtered View" or "All Characters")
    toggleBtn:SetScript("OnClick", function(btn)
        if viewMode == "filtered" then
            viewMode = "all"
            self.db.profile.reputationViewMode = "all"
            btn:SetText("All Characters")
        else
            viewMode = "filtered"
            self.db.profile.reputationViewMode = "filtered"
            btn:SetText("Filtered View")
        end
        self:RefreshUI()
    end)
    
    toggleBtn:SetScript("OnEnter", function(btn)
        btn:SetBackdropColor(COLORS.tabActive[1], COLORS.tabActive[2], COLORS.tabActive[3], 1)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        -- ... tooltip logic omitted for brevity, standard tooltip ...
        GameTooltip:SetText(viewMode == "filtered" and "Filtered View" or "All Characters View", 1, 1, 1)
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
    
    yOffset = yOffset + 75
    
    -- ===== SEARCH BOX =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    local reputationSearchText = ns.reputationSearchText or ""
    
    local searchBox = CreateSearchBox(parent, width, "Search reputations...", function(text)
        ns.reputationSearchText = text
        -- UPDATE LIST ONLY (Fixes focus issue)
        if parent.resultsContainer then
            self:DrawReputationList(parent.resultsContainer, width)
        end
    end, 0.4, reputationSearchText)
    
    searchBox:SetPoint("TOPLEFT", 10, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -10, -yOffset)
    
    yOffset = yOffset + 32 + 10
    
    -- Results Container
    if not parent.resultsContainer then
        local container = CreateFrame("Frame", nil, parent)
        parent.resultsContainer = container
    end
    
    local container = parent.resultsContainer
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", 0, -yOffset)
    container:SetWidth(width)
    container:SetHeight(1) -- Dynamic, but needed for layout
    container:Show()
    
    -- Draw List
    local listHeight = self:DrawReputationList(container, width)
    
    return yOffset + listHeight
end
