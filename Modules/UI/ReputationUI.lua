--[[
    Warband Nexus - Reputation Tab
    Display all reputations across characters with progress bars, Renown, and Paragon support
    
    Hierarchy (All Characters view - matches Filtered View):
    - Character Header (0px) → HEADER_SPACING (40px)
      - Expansion Header (BASE_INDENT = 15px) → HEADER_HEIGHT (32px)
        - Reputation Rows (BASE_INDENT = 15px, same as header)
        - Sub-Rows (BASE_INDENT + BASE_INDENT + SUBROW_EXTRA_INDENT = 40px)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateNoticeFrame = ns.UI_CreateNoticeFrame
local CreateIcon = ns.UI_CreateIcon
local CreateReputationProgressBar = ns.UI_CreateReputationProgressBar
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format
local floor = math.floor
local ipairs = ipairs

local pairs = pairs
local next = next

-- Import shared UI constants
local UI_LAYOUT = ns.UI_LAYOUT
local BASE_INDENT = UI_LAYOUT.BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = UI_LAYOUT.SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = UI_LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = UI_LAYOUT.TOP_MARGIN or 8
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT or 26
local ROW_SPACING = UI_LAYOUT.ROW_SPACING or 26
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING or 40
local SUBHEADER_SPACING = UI_LAYOUT.SUBHEADER_SPACING or 40
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 8
local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

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
            local progress = repData.value
            
            -- FALLBACK: If value is nil, try chars (data might be stored incorrectly)
            if not progress and repData.chars then
                for k, v in pairs(repData.chars) do
                    progress = v
                    break
                end
            end
            progress = progress or {}
            
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
                                characterRealm = char.realm,
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
                                factionMap[factionID].characterRealm = char.realm
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
                    characterRealm = factionData.characterRealm,
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
local function CreateReputationRow(parent, reputation, factionID, rowIndex, indent, rowWidth, yOffset, subfactions, IsExpanded, ToggleExpand, characterInfo)
    -- Create new row (StorageUI pattern: rowWidth is pre-calculated by caller)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(rowWidth, ROW_HEIGHT)  -- Use pre-calculated width
    row:ClearAllPoints()  -- Clear any existing anchors (StorageUI pattern)
    row:SetPoint("TOPLEFT", indent, -yOffset)
    
    -- Set alternating background colors
    local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
    local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
    local bgColor = (rowIndex % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
    
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    
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
        local btnIconFrame = ns.UI_CreateIcon(collapseBtn, 
            isExpanded and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up", 
            16, false, nil, true)
        btnIconFrame:SetAllPoints(collapseBtn)
        local btnTexture = btnIconFrame.texture
        
        -- Make button clickable
        collapseBtn:SetScript("OnClick", function()
            ToggleExpand(collapseKey, not isExpanded)
        end)
        
        -- Also make row clickable (like headers)
        row:SetScript("OnClick", function()
            ToggleExpand(collapseKey, not isExpanded)
        end)
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
        standingText:SetPoint("LEFT", 10, 0)
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
        nameText:SetPoint("LEFT", 10, 0)
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
        badgeText:SetPoint("LEFT", 302, 0)  -- Adjusted for no icon (330 - 28)
        badgeText:SetJustifyH("LEFT")
        badgeText:SetWidth(250)  -- Increased width for character name + realm
        
        if characterInfo.isAccountWide then
            badgeText:SetText("|cff666666(|r|cff00ff00Account-Wide|r|cff666666)|r")
        elseif characterInfo.name then
            local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
            local classHex = format("%02x%02x%02x", classColor.r*255, classColor.g*255, classColor.b*255)
            badgeText:SetText("|cff666666(|r|cff" .. classHex .. characterInfo.name .. "  -  " .. (characterInfo.realm or "") .. "|r|cff666666)|r")
        end
    end
    
    -- Determine if we should use Paragon values or base reputation
    local currentValue = reputation.currentValue or 0
    -- If maxValue is explicitly 0, keep it 0 (for empty reputations), otherwise default to 1
    local maxValue = (reputation.maxValue ~= nil) and reputation.maxValue or 1
    local isParagon = false
    
    -- Priority: If Paragon exists, use Paragon values instead
    -- FIX: Only use paragon if both values are valid numbers > 0
    if reputation.paragonValue and reputation.paragonThreshold and 
       type(reputation.paragonValue) == "number" and type(reputation.paragonThreshold) == "number" and
       reputation.paragonValue > 0 and reputation.paragonThreshold > 0 then
        currentValue = reputation.paragonValue
        maxValue = reputation.paragonThreshold
        isParagon = true
    end
    
    -- Check if BASE reputation is maxed (independent of Paragon)
    local baseReputationMaxed = false
    
    if isParagon then
        -- If Paragon exists, base reputation is ALWAYS maxed
        baseReputationMaxed = true
    elseif reputation.renownLevel and reputation.renownMaxLevel and reputation.renownMaxLevel > 0 and type(reputation.renownLevel) == "number" then
        -- Renown system: check if at max level
        baseReputationMaxed = (reputation.renownLevel >= reputation.renownMaxLevel)
    else
        -- Classic reputation: check if at max
        baseReputationMaxed = (reputation.currentValue >= reputation.maxValue)
    end
    
    -- Use Factory: Create progress bar with auto-styling
    local standingID = reputation.standingID or 4
    local hasRenown = reputation.renownLevel and type(reputation.renownLevel) == "number" and reputation.renownLevel > 0
    local progressBg, progressFill = CreateReputationProgressBar(
        row, 200, 19, 
        currentValue, maxValue, 
        isParagon, baseReputationMaxed, 
        (hasRenown or reputation.rankName) and nil or standingID
    )
    progressBg:SetPoint("RIGHT", -10, 0)
    
    -- Add Paragon reward icon if Paragon is active (LEFT of checkmark)
    if isParagon then
        -- Use layered paragon icon (glow + bag + checkmark)
        local CreateParagonIcon = ns.UI_CreateParagonIcon
        if CreateParagonIcon then
            local paragonFrame = CreateParagonIcon(row, 18, reputation.paragonRewardPending)
            paragonFrame:SetPoint("RIGHT", progressBg, "LEFT", -24, 0)
        else
            -- Fallback to simple icon if function not available
            local iconTexture = "ParagonReputation_Bag"
            local useAtlas = true
            
            local success = pcall(function()
                local testFrame = CreateFrame("Frame")
                local testTex = testFrame:CreateTexture()
                testTex:SetAtlas("ParagonReputation_Bag")
                testFrame:Hide()
            end)
            
            if not success then
                iconTexture = "Interface\\Icons\\INV_Misc_Bag_10"
                useAtlas = false
            end
            
            local paragonFrame = CreateIcon(row, iconTexture, 18, useAtlas, nil, true)
            paragonFrame:SetPoint("RIGHT", progressBg, "LEFT", -24, 0)
            
            if not reputation.paragonRewardPending then
                paragonFrame.texture:SetVertexColor(0.5, 0.5, 0.5, 1)
            end
        end
    end
    
    -- Add completion checkmark if base reputation is maxed (LEFT of progress bar)
    if baseReputationMaxed then
        -- Use Factory: CreateIcon with auto-border and anti-flicker
        local checkFrame = CreateIcon(row, "Interface\\RaidFrame\\ReadyCheck-Ready", 16, false, nil, true)  -- noBorder = true
        checkFrame:SetPoint("RIGHT", progressBg, "LEFT", -4, 0)
    end
    
    -- Progress Text - positioned INSIDE the progress bar (centered, white text)
    -- Create text as child of progressBg in OVERLAY layer (highest priority)
    local progressText = progressBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("CENTER", progressBg, "CENTER", 0, -1)  -- Center inside the progress bar, 1px down
    progressText:SetJustifyH("CENTER")
    
    -- Add outline for better readability
    local font, size = progressText:GetFont()
    progressText:SetFont(font, size + 1, "OUTLINE")  -- OUTLINE adds shadow/outline
    
    -- Format progress text based on state (NO color codes - pure white)
    local progressDisplay
    if isParagon then
        -- Show Paragon progress only
        progressDisplay = FormatReputationProgress(currentValue, maxValue)
    elseif baseReputationMaxed then
        -- Show "Maxed" for completed reputations
        progressDisplay = "Maxed"
    else
        -- Show normal progress
        progressDisplay = FormatReputationProgress(currentValue, maxValue)
    end
    
    -- Set text without color codes to ensure pure white
    progressText:SetText(progressDisplay)
    progressText:SetTextColor(1, 1, 1)  -- Pure white text (RGB: 255, 255, 255)

    
    -- Hover effect (use new tooltip system for custom data)
    row:SetScript("OnEnter", function(self)
        if not ShowTooltip then
            -- Fallback if service not ready
            return
        end
        
        -- Build tooltip lines
        local lines = {}
        
        -- Description
        if reputation.description and reputation.description ~= "" then
            table.insert(lines, {text = reputation.description, color = {0.8, 0.8, 0.8}, wrap = true})
            table.insert(lines, {type = "spacer"})
        end
        
        -- Standing info
        if reputation.rankName then
            -- Friendship rank
            table.insert(lines, {left = "Current Rank:", right = reputation.rankName, leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 0.82, 0}})
            
            if reputation.renownLevel and type(reputation.renownLevel) == "number" and 
               reputation.renownMaxLevel and reputation.renownMaxLevel > 0 then
                table.insert(lines, {left = "Rank:", right = format("%d / %d", reputation.renownLevel, reputation.renownMaxLevel), 
                    leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 0.82, 0}})
            end
            
            -- Paragon for friendship
            if reputation.paragonValue and reputation.paragonThreshold then
                table.insert(lines, {type = "spacer"})
                table.insert(lines, {left = "Paragon Progress:", right = FormatReputationProgress(reputation.paragonValue, reputation.paragonThreshold),
                    leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}})
                if reputation.paragonRewardPending then
                    table.insert(lines, {text = "|cff00ff00Reward Available!|r", color = {1, 1, 1}})
                end
            end
        elseif reputation.renownLevel and type(reputation.renownLevel) == "number" and reputation.renownLevel > 0 then
            -- Renown system
            local maxLevel = reputation.renownMaxLevel
            if (not maxLevel or maxLevel == 0) and factionID and C_MajorFactions and C_MajorFactions.GetMaximumRenownLevel then
                maxLevel = C_MajorFactions.GetMaximumRenownLevel(factionID)
            end
            
            local renownText = maxLevel and maxLevel > 0 and format("%d / %d", reputation.renownLevel, maxLevel) or tostring(reputation.renownLevel)
            table.insert(lines, {left = "Renown Level:", right = renownText, leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 0.82, 0}})
        else
            -- Standard standing
            local standingName = GetStandingName(reputation.standingID or 4)
            local r, g, b = GetStandingColor(reputation.standingID or 4)
            table.insert(lines, {left = "Standing:", right = standingName, leftColor = {0.7, 0.7, 0.7}, rightColor = {r, g, b}})
        end
        
        -- Paragon for non-friendship
        if not reputation.rankName and reputation.paragonValue and reputation.paragonThreshold then
            table.insert(lines, {type = "spacer"})
            table.insert(lines, {text = "Paragon Progress:", color = {1, 0.4, 1}})
            table.insert(lines, {left = "Progress:", right = FormatReputationProgress(reputation.paragonValue, reputation.paragonThreshold),
                leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 0.4, 1}})
            if reputation.paragonRewardPending then
                table.insert(lines, {text = "|cff00ff00Reward Available!|r", color = {1, 1, 1}})
            end
        end
        
        -- Renown indicator
        if reputation.isRenown then
            table.insert(lines, {type = "spacer"})
            table.insert(lines, {text = "|cff00ff00Major Faction (Renown)|r", color = {0.8, 0.8, 0.8}})
        end
        
        -- Show tooltip
        ShowTooltip(self, {
            type = "custom",
            title = reputation.name or "Reputation",
            lines = lines,
            anchor = "ANCHOR_LEFT"
        })
    end)
    
    row:SetScript("OnLeave", function(self)
        if HideTooltip then
            HideTooltip()
        end
    end)
    
    return yOffset + ROW_HEIGHT + UI_LAYOUT.betweenRows, isExpanded -- Standard Storage row pitch (40px headers, 34px rows)
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawReputationList(container, width)
    if not container then return 0 end
    
    -- Clear container
    local children = {container:GetChildren()}
    for _, child in pairs(children) do
        child:Hide()
        child:SetParent(nil)
    end
    
    local parent = container
    local yOffset = 0
    local viewMode = self.db.profile.reputationViewMode or "all"
    

    
    -- ===== TITLE CARD (Always shown) =====
    

    
    -- Check if module is disabled - show message below header
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.reputations then
        local disabledText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        disabledText:SetPoint("TOP", parent, "TOP", 0, -yOffset - 50)
        disabledText:SetText("|cff888888Module disabled. Check the box above to enable.|r")
        return yOffset + UI_LAYOUT.emptyStateSpacing
    end
    
    -- Check if C_Reputation API is available (for modern WoW)
    if not C_Reputation or not C_Reputation.GetNumFactions then
        local errorFrame = CreateNoticeFrame(
            parent,
            "Reputation API Not Available",
            "The C_Reputation API is not available on this server. This feature requires WoW 11.0+ (The War Within).",
            "alert",
            width - 20,
            100
        )
        errorFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
        
        return yOffset + UI_LAYOUT.emptyStateSpacing + BASE_INDENT
    end
    
    -- Get search text
    local reputationSearchText = (ns.reputationSearchText or ""):lower()
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    if not characters or #characters == 0 then
        DrawEmptyState(parent, "No character data available", yOffset)
        return yOffset + HEADER_SPACING
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
            -- FIX: Try both account-wide and character-specific paths
            local progress = nil
            if repData.isAccountWide then
                progress = repData.value
            else
                progress = repData.chars and repData.chars[charKey]
            end
            
            -- FALLBACK: If progress not found and isAccountWide is false, try value (data might be stored incorrectly)
            if not progress and not repData.isAccountWide then
                progress = repData.value
            end
            
            -- FALLBACK: If still not found and chars exists, try first available character data
            if not progress and repData.chars then
                for k, v in pairs(repData.chars) do
                    progress = v
                    break
                end
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
                    maxValue = (progress.maxValue ~= nil) and progress.maxValue or (progress.maxValue == 0 and 0 or 1),  -- Preserve 0 if explicitly 0, otherwise default to 1
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
        return yOffset + UI_LAYOUT.emptyStateSpacing
    end
    
    -- Check view mode and render accordingly
    if viewMode == "filtered" then
        local COLORS = GetCOLORS() -- Define COLORS for this block
        -- ===== FILTERED VIEW: Show highest reputation from any character =====
        
        local aggregatedHeaders = AggregateReputations(characters, factionMetadata, reputationSearchText)
        
        if not aggregatedHeaders or #aggregatedHeaders == 0 then
            DrawEmptyState(parent, 
                reputationSearchText ~= "" and "No reputations match your search" or "No reputations found",
                yOffset)
            return yOffset + UI_LAYOUT.emptyStateSpacing
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
        awSectionHeader:SetPoint("TOPLEFT", 0, -yOffset)
        awSectionHeader:SetPoint("TOPRIGHT", 0, -yOffset)
        awSectionHeader:SetWidth(width)
        -- Removing custom tint to match other tabs/headers
        -- awSectionHeader:SetBackdropColor(0.15, 0.08, 0.20, 1)  -- Purple-ish
        -- local COLORS = GetCOLORS()
        -- awSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        
        yOffset = yOffset + HEADER_SPACING  -- Section header + spacing before content
        
        if awSectionExpanded then
            if totalAccountWide == 0 then
                -- Empty state
                local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                emptyText:SetTextColor(1, 1, 1)  -- White
                emptyText:SetText("No account-wide reputations")
                yOffset = yOffset + 60  -- Empty state spacing
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
            header:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)  -- Level 1 indent
            header:SetWidth(width - BASE_INDENT)  -- Adjust width for indent
            
            yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT  -- Expansion header (no extra spacing before rows)
            
            if headerExpanded then
                local headerIndent = BASE_INDENT  -- Rows at same indent as expansion header
                
                -- Group factions and subfactions (same as non-filtered)
                local factionList = {}
                local subfactionMap = {}
                
                for _, faction in ipairs(headerData.factions) do
                    -- Nil safety: check faction and faction.data exist
                    if faction and faction.data and faction.data.isHeaderWithRep and faction.data.name then
                        subfactionMap[faction.data.name] = {
                            parent = faction,
                            subfactions = {},
                            index = faction.factionID
                        }
                    end
                end
                
                for _, faction in ipairs(headerData.factions) do
                    -- Nil safety: check faction and faction.data exist
                    if not faction or not faction.data then
                        -- Skip invalid faction
                    else
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
                    end  -- end nil safety check
                end
                
                -- Render factions
                local rowIdx = 0
                for _, item in ipairs(factionList) do
                    rowIdx = rowIdx + 1
                    
                    local charInfo = {
                        name = item.faction.characterName,
                        class = item.faction.characterClass,
                        level = item.faction.characterLevel,
                        isAccountWide = item.faction.isAccountWide,
                        realm = item.faction.characterRealm
                    }
                    
                    -- StorageUI pattern: pass calculated row width
                    local rowWidth = width - headerIndent  -- width - BASE_INDENT
                    local newYOffset, isExpanded = CreateReputationRow(
                        parent, 
                        item.faction.data, 
                        item.faction.factionID, 
                        rowIdx, 
                        headerIndent, 
                        rowWidth, 
                        yOffset, 
                        item.subfactions, 
                        IsExpanded, 
                        ToggleExpand, 
                        charInfo
                    )
                    yOffset = newYOffset
                    
                    if isExpanded and item.subfactions and #item.subfactions > 0 then
                        local subIndent = headerIndent + BASE_INDENT + SUBROW_EXTRA_INDENT  -- Level 2 indent (40px)
                        local subRowIdx = 0
                        for _, subFaction in ipairs(item.subfactions) do
                            subRowIdx = subRowIdx + 1
                            
                            local subCharInfo = {
                                name = subFaction.characterName,
                                class = subFaction.characterClass,
                                level = subFaction.characterLevel,
                                isAccountWide = subFaction.isAccountWide,
                                realm = subFaction.characterRealm
                            }
                            
                            -- StorageUI pattern: pass calculated row width
                            local subRowWidth = width - subIndent
                            yOffset = CreateReputationRow(
                                parent, 
                                subFaction.data, 
                                subFaction.factionID, 
                                subRowIdx, 
                                subIndent, 
                                subRowWidth, 
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
            
            -- Add spacing after each expansion section (whether expanded or not)
            yOffset = yOffset + SECTION_SPACING
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
        cbSectionHeader:SetPoint("TOPLEFT", 0, -yOffset)
        cbSectionHeader:SetPoint("TOPRIGHT", 0, -yOffset)
        cbSectionHeader:SetWidth(width)
        -- Removing custom tint to match other tabs/headers
        -- cbSectionHeader:SetBackdropColor(0.08, 0.12, 0.15, 1)  -- Blue-ish
        -- cbSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        
        yOffset = yOffset + HEADER_SPACING  -- Section header + spacing before content
        
        if cbSectionExpanded then
            if totalCharacterBased == 0 then
                -- Empty state
                local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                emptyText:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                emptyText:SetTextColor(1, 1, 1)  -- White
                emptyText:SetText("No character-based reputations")
                yOffset = yOffset + SECTION_SPACING
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
                    header:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                    header:SetWidth(width - BASE_INDENT)
                    
                    yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT  -- Expansion header (no extra spacing before rows)
                    
                    if headerExpanded then
                        local headerIndent = BASE_INDENT  -- Rows at BASE_INDENT (same as Expansion header)
                        
                        -- Group factions and subfactions (same logic)
                        local factionList = {}
                        local subfactionMap = {}
                        
                        for _, faction in ipairs(headerData.factions) do
                            -- Nil safety: check faction and faction.data exist
                            if faction and faction.data and faction.data.isHeaderWithRep and faction.data.name then
                                subfactionMap[faction.data.name] = {
                                    parent = faction,
                                    subfactions = {},
                                    index = faction.factionID
                                }
                            end
                        end
                        
                        for _, faction in ipairs(headerData.factions) do
                            -- Nil safety: check faction and faction.data exist
                            if not faction or not faction.data then
                                -- Skip invalid faction
                            else
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
                            end  -- end nil safety check
                        end
                        
                        -- Render factions
                        local rowIdx = 0
                        for _, item in ipairs(factionList) do
                            rowIdx = rowIdx + 1
                            
                            local charInfo = {
                                name = item.faction.characterName,
                                class = item.faction.characterClass,
                                level = item.faction.characterLevel,
                                isAccountWide = item.faction.isAccountWide,
                                realm = item.faction.characterRealm
                            }
                            
                            -- StorageUI pattern: pass calculated row width
                            local rowWidth = width - headerIndent
                            local newYOffset, isExpanded = CreateReputationRow(
                                parent, 
                                item.faction.data, 
                                item.faction.factionID, 
                                rowIdx, 
                                headerIndent, 
                                rowWidth, 
                                yOffset, 
                                item.subfactions, 
                                IsExpanded, 
                                ToggleExpand, 
                                charInfo
                            )
                            yOffset = newYOffset
                            
                            if isExpanded and item.subfactions and #item.subfactions > 0 then
                                local subIndent = BASE_INDENT  -- SubRow at BASE_INDENT (15px from Row which is at 0px)
                                local subRowIdx = 0
                                for _, subFaction in ipairs(item.subfactions) do
                                    subRowIdx = subRowIdx + 1
                                    
                                    local subCharInfo = {
                                        name = subFaction.characterName,
                                        class = subFaction.characterClass,
                                        level = subFaction.characterLevel,
                                        isAccountWide = subFaction.isAccountWide,
                                        realm = subFaction.characterRealm
                                    }
                                    
                                    -- StorageUI pattern: pass calculated row width
                                    local subRowWidth = width - subIndent
                                    yOffset = CreateReputationRow(
                                        parent, 
                                        subFaction.data, 
                                        subFaction.factionID, 
                                        subRowIdx, 
                                        subIndent, 
                                        subRowWidth, 
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
                
                -- Add spacing after each expansion section (whether expanded or not)
                yOffset = yOffset + SECTION_SPACING
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
        local charName = format("|c%s%s  -  %s|r", 
            format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            char.name or "Unknown",
            char.realm or "")
        
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
            format("%s%s - |cffffffff%d reputations|r", charName, onlineBadge, #reputations),
            charKey_expand,
            charExpanded,
            function(isExpanded) ToggleExpand(charKey_expand, isExpanded) end,
            classIconPath
        )
        
        if classIcon and coords then
            classIcon:SetTexCoord(unpack(coords))
        end
        
        charHeader:SetPoint("TOPLEFT", 0, -yOffset)
        charHeader:SetPoint("TOPRIGHT", 0, -yOffset)
        charHeader:SetWidth(width)
        
        yOffset = yOffset + HEADER_SPACING
        
        if charExpanded then
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
                    local globalReputations = self.db.global.reputations or {}
                    local factionMetadata = self.db.global.factionMetadata or {}
                    
                    for _, factionID in ipairs(headerFactions) do
                        -- Ensure consistent type comparison (both as numbers)
                        local numFactionID = tonumber(factionID) or factionID
                        local found = false
                        
                        -- First try to find in existing reputations array
                        for _, rep in ipairs(reputations) do
                            local numRepID = tonumber(rep.id) or rep.id
                            if numRepID == numFactionID then
                                table.insert(headerReputations, rep)
                                found = true
                                break
                            end
                        end
                        
                        -- If not found in reputations array, try to build from global storage
                        if not found then
                            local repData = globalReputations[numFactionID]
                            if repData then
                                local metadata = factionMetadata[numFactionID] or factionMetadata[tostring(numFactionID)] or {}
                                
                                -- Get progress data for this character
                                -- FIX: Try both account-wide and character-specific paths
                                local progress = nil
                                if repData.isAccountWide then
                                    progress = repData.value
                                else
                                    progress = repData.chars and repData.chars[charKey]
                                end
                                
                                -- FALLBACK: If progress not found and isAccountWide is false, try value (data might be stored incorrectly)
                                if not progress and not repData.isAccountWide then
                                    progress = repData.value
                                end
                                
                                -- FALLBACK: If still not found and chars exists, try first available character data
                                if not progress and repData.chars then
                                    for k, v in pairs(repData.chars) do
                                        progress = v
                                        break
                                    end
                                end
                                
                                -- Build reputation even if progress is missing (for subfactions)
                                local reputation = {
                                    name = repData.name or metadata.name or ("Faction " .. tostring(numFactionID)),
                                    description = metadata.description,
                                    iconTexture = repData.icon or metadata.iconTexture,
                                    isRenown = repData.isRenown or metadata.isRenown,
                                    canToggleAtWar = metadata.canToggleAtWar,
                                    parentHeaders = metadata.parentHeaders,
                                    isHeader = metadata.isHeader,
                                    isHeaderWithRep = metadata.isHeaderWithRep,
                                    isMajorFaction = repData.isMajorFaction,
                                    
                                    standingID = progress and progress.standingID or 4,
                                    currentValue = progress and (progress.currentValue or 0) or 0,
                                    maxValue = progress and (progress.maxValue or 0) or 0,
                                    renownLevel = progress and progress.renownLevel,
                                    renownMaxLevel = progress and progress.renownMaxLevel,
                                    rankName = progress and progress.rankName,
                                    paragonValue = progress and progress.paragonValue,
                                    paragonThreshold = progress and progress.paragonThreshold,
                                    paragonRewardPending = progress and progress.hasParagonReward,
                                    isWatched = progress and progress.isWatched,
                                    atWarWith = progress and progress.atWarWith,
                                    lastUpdated = progress and progress.lastUpdated,
                                }
                                
                                table.insert(headerReputations, {
                                    id = numFactionID,
                                    data = reputation,
                                })
                            end
                        end
                    end
                    
                    if #headerReputations > 0 then
                        local headerKey = charKey .. "-header-" .. headerData.name
                        local headerExpanded = IsExpanded(headerKey, true)
                        
                        if reputationSearchText ~= "" then
                            headerExpanded = true
                        end
                        
                        -- Expansion Header at BASE_INDENT (15px)
                        local header, headerBtn = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. #headerReputations .. ")",
                            headerKey,
                            headerExpanded,
                            function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                            GetHeaderIcon(headerData.name)
                        )
                        header:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                        header:SetPoint("TOPRIGHT", 0, -yOffset)
                        
                        yOffset = yOffset + UI_LAYOUT.HEADER_HEIGHT
                        
                        if headerExpanded then
                            local headerIndent = BASE_INDENT  -- Rows at BASE_INDENT (15px, same as header)
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
                            
                            -- Render factions (with global row counter for zebra striping)
                            local globalRowIdx = 0  -- Global counter for alternating colors across parent and children
                            for _, item in ipairs(factionList) do
                                globalRowIdx = globalRowIdx + 1
                                -- FIX: Row width from parent width
                                local rowWidth = width - headerIndent
                                local newYOffset, isExpanded = CreateReputationRow(parent, item.rep.data, item.rep.id, globalRowIdx, headerIndent, rowWidth, yOffset, item.subfactions, IsExpanded, ToggleExpand)
                                yOffset = newYOffset
                                
                                -- If expanded and has subfactions, render them nested
                                if isExpanded and item.subfactions and #item.subfactions > 0 then
                                    local subIndent = headerIndent + BASE_INDENT + SUBROW_EXTRA_INDENT  -- SubRows at headerIndent + BASE_INDENT + SUBROW_EXTRA_INDENT (40px)
                                    for _, subRep in ipairs(item.subfactions) do
                                        globalRowIdx = globalRowIdx + 1  -- Continue global counter
                                        -- Sub-row width from parent width
                                        local subRowWidth = width - subIndent
                                        
                                        yOffset = CreateReputationRow(parent, subRep.data, subRep.id, globalRowIdx, subIndent, subRowWidth, yOffset, nil, IsExpanded, ToggleExpand)
                                    end
                                end
                            end
                        end
                        
                        -- Add spacing after each expansion section
                        yOffset = yOffset + SECTION_SPACING
                    end
                end
                
                -- Remove last SECTION_SPACING before character ends (to prevent double spacing)
                yOffset = yOffset - SECTION_SPACING
        end
    end
    end  -- End of viewMode if/else
    
    -- ===== FOOTER NOTE =====
    yOffset = yOffset + (SECTION_SPACING * 2)  -- Double spacing before footer
    
    local noticeFrame = CreateNoticeFrame(
        parent,
        "Reputation Tracking",
        "Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards.",
        "info",
        width - 20,
        60
    )
    noticeFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + UI_LAYOUT.afterHeader  -- Standard spacing after notice
    
    return yOffset
end

--============================================================================
-- REPUTATION TAB WRAPPER (Fixes focus issue)
--============================================================================

function WarbandNexus:DrawReputationTab(parent)
    -- Clear all old frames
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
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
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Header icon with ring border
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("reputation"))
    
    -- Module Enable/Disable Checkbox (icon'un sağında)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.reputations ~= false
    local enableCheckbox = CreateThemedCheckbox(titleCard, moduleEnabled)
    enableCheckbox:SetPoint("LEFT", headerIcon.border, "RIGHT", 8, 0)
    
    enableCheckbox:SetScript("OnClick", function(checkbox)
        local enabled = checkbox:GetChecked()
        -- Use ModuleManager for proper event handling
        if self.SetReputationModuleEnabled then
            self:SetReputationModuleEnabled(enabled)
            if enabled and self.UpdateReputationData then
                self:UpdateReputationData()
            end
        else
            -- Fallback
            self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
            self.db.profile.modulesEnabled.reputations = enabled
            if enabled and self.UpdateReputationData then
                self:UpdateReputationData()
            end
            if self.RefreshUI then self:RefreshUI() end
        end
    end)
    
    -- Title text (checkbox'ın sağında)
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 8, 5)
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Reputation Overview|r")
    
    -- Subtitle (title'ın altında)
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -4)
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetText("Track factions and renown across your warband")
    
    -- View Mode Toggle Button (en sağda) - only if module enabled
    local viewMode = self.db.profile.reputationViewMode or "all"
    local toggleBtn = CreateThemedButton(titleCard, viewMode == "filtered" and "Filtered View" or "All Characters", 140)
    toggleBtn:SetPoint("RIGHT", titleCard, "RIGHT", -10, 0)
    
    -- Hide button if module disabled
    if not moduleEnabled then
        toggleBtn:Hide()
    end
    
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
    
    yOffset = yOffset + UI_LAYOUT.afterHeader  -- Standard spacing after title card
    
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
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + UI_LAYOUT.afterElement  -- Search box height + standard gap
    
    -- Results Container
    if not parent.resultsContainer then
        local container = CreateFrame("Frame", nil, parent)
        parent.resultsContainer = container
    end
    
    local container = parent.resultsContainer
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", 10, -yOffset)
    container:SetWidth(width)
    container:SetHeight(1) -- Dynamic, but needed for layout
    container:Show()
    
    -- Draw List
    local listHeight = self:DrawReputationList(container, width)
    
    return yOffset + listHeight
end
