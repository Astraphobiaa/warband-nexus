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
local FontManager = ns.FontManager  -- Centralized font management

-- Debug helper
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        print("|cff00ff00[RepUI]|r", ...)
    end
end

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Import shared UI components
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateNoticeFrame = ns.UI_CreateNoticeFrame
local CreateIcon = ns.UI_CreateIcon
-- CreateReputationProgressBar no longer imported - progress bar is now inline lazy-created on pooled rows
-- (eliminates ~150 Frame + ~900 texture creations per refresh cycle)
local FormatNumber = ns.UI_FormatNumber
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local COLORS = ns.UI_COLORS

-- Import pooling functions (performance: reuse frames instead of creating new ones)
local AcquireReputationRow = ns.UI_AcquireReputationRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance: Local function references
local format = string.format
local floor = math.floor
local ipairs = ipairs

local pairs = pairs
local next = next

-- Import shared UI constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local HEADER_SPACING = GetLayout().HEADER_SPACING or 40
local SUBHEADER_SPACING = GetLayout().SUBHEADER_SPACING or 40
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local ROW_COLOR_EVEN = GetLayout().ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = GetLayout().ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

--============================================================================
-- REPUTATION FORMATTING & HELPERS
--============================================================================

---Get standing name from standing ID
---@param standingID number Standing ID (1-8)
---@return string Standing name
local function GetStandingName(standingID)
    local standings = {
        [1] = FACTION_STANDING_LABEL1 or "Hated",
        [2] = FACTION_STANDING_LABEL2 or "Hostile",
        [3] = FACTION_STANDING_LABEL3 or "Unfriendly",
        [4] = FACTION_STANDING_LABEL4 or "Neutral",
        [5] = FACTION_STANDING_LABEL5 or "Friendly",
        [6] = FACTION_STANDING_LABEL6 or "Honored",
        [7] = FACTION_STANDING_LABEL7 or "Revered",
        [8] = FACTION_STANDING_LABEL8 or "Exalted",
    }
    return standings[standingID] or (ns.L and ns.L["UNKNOWN"]) or "Unknown"
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
    -- If maxed (1/1 means completed reputation), show "Max." instead of numbers
    if current == 1 and max == 1 then
        return "|cffffffff" .. ((ns.L and ns.L["REP_MAX"]) or "Max.") .. "|r"  -- White "Max." text
    elseif max > 0 then
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

-- Phase 2.4: Cache for filtered search results
local cachedSearchText = nil
local cachedFilteredResults = {} -- [headerName][searchText] = filteredFactionList

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
    local renown1 = (rep1.renown and rep1.renown.level) or 0
    local renown2 = (rep2.renown and rep2.renown.level) or 0
    
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
---v2.0.0: Reads from NEW ReputationCacheService with normalized data
---@param characters table List of character data
---@param factionMetadata table Faction metadata (DEPRECATED, for icons only)
---@param reputationSearchText string Search filter
---@return table List of {headerName, factions={factionID, data, characterKey, characterName, characterClass, isAccountWide}}
local function AggregateReputations(characters, factionMetadata, reputationSearchText)
    -- Collect all unique faction IDs and their best reputation
    local factionMap = {} -- [factionID] = {data, characterKey, characterName, characterClass, allCharData}
    
    -- v2.0.0: Read from NEW ReputationCacheService (normalized data)
    local cachedFactions = WarbandNexus:GetAllReputations() or {}
    
    if #cachedFactions == 0 then
        return {}
    end
    
    -- Build character lookup table
    -- CRITICAL: Use GetCharacterKey() normalization (strips spaces) to match reputation DB keys
    local charLookup = {}
    for _, char in ipairs(characters) do
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey(char.name, char.realm)
            or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
        charLookup[charKey] = char
    end
    
    -- Helper function to build reputation object from cached data
    local function BuildReputationObject(cachedData)
        return {
            -- Core
            factionID = cachedData.factionID,  -- CRITICAL: Need this for tooltip matching
            name = cachedData.name,
            description = cachedData.description or "",
            iconTexture = cachedData.icon,
            parentFactionID = cachedData.parentFactionID,
            
            -- Classification
            type = cachedData.type,
            isHeader = cachedData.isHeader or false,
            isHeaderWithRep = cachedData.isHeaderWithRep or false,
            isAccountWide = cachedData.isAccountWide or false,
            parentHeaders = cachedData.parentHeaders or {},
            
            -- Standing
            standingID = cachedData.standingID,
            standing = {
                name = cachedData.standingName,
                color = cachedData.standingColor,
                id = cachedData.standingID,
            },
            
            -- Progress (already normalized in Processor)
            -- Processor sets currentValue/maxValue correctly for all types
            currentValue = cachedData.currentValue or 0,
            maxValue = cachedData.maxValue or 1,
            progressPercent = ((cachedData.currentValue or 0) / (cachedData.maxValue or 1)) * 100,
            
            -- Paragon state (if applicable)
            hasParagon = cachedData.hasParagon or false,
            
            -- Type-specific data
            friendship = cachedData.friendship,
            renown = cachedData.renown,
            paragon = cachedData.paragon,
            
            -- Legacy fields (for compatibility)
            isMajorFaction = (cachedData.type == "renown"),
            isFriendship = (cachedData.type == "friendship"),
            isRenown = (cachedData.type == "renown"),
            
            -- Metadata
            lastUpdated = cachedData._scanTime or time(),
            
            -- CRITICAL: Preserve _scanIndex for Blizzard UI ordering
            _scanIndex = cachedData._scanIndex or 99999,
        }
    end
    
    -- PHASE 1: Collect ALL character data for each faction
    -- Build: factionID -> {charKey -> {reputation, char}}
    local factionCharacterMap = {}
    
    for _, cachedData in ipairs(cachedFactions) do
        local factionID = cachedData.factionID
        
        -- Only process factions with rep (skip pure organizational headers)
        if not (cachedData.isHeader and not cachedData.isHeaderWithRep) then
            
            if cachedData.isAccountWide then
                -- ACCOUNT-WIDE: Create entry with no characters
                -- NOTE: No search filter here — filtering happens in the UI rendering phase
                -- to preserve parent-child relationships (child may match even if parent doesn't)
                local reputation = BuildReputationObject(cachedData)
                
                factionMap[factionID] = {
                    data = reputation,
                    characterKey = (ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide",
                    characterName = (ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account",
                    characterRealm = "",
                    characterClass = "WARRIOR",
                    characterLevel = 80,
                    isAccountWide = true,
                    allCharData = {}
                }
            else
                -- CHARACTER-SPECIFIC: Collect data for this character
                local charKey = cachedData._characterKey or "Unknown"
                local char = charLookup[charKey]
                
                if char then
                    local reputation = BuildReputationObject(cachedData)
                    
                    -- NOTE: No search filter here — filtering happens in UI rendering
                    if not factionCharacterMap[factionID] then
                        factionCharacterMap[factionID] = {}
                    end
                    
                    factionCharacterMap[factionID][charKey] = {
                        reputation = reputation,
                        char = char,
                        charKey = charKey,
                    }
                end
            end
        end  -- end if not isHeader
    end
    
    -- PHASE 2: For each faction, find HIGHEST progress character and build allCharData
    for factionID, charDataMap in pairs(factionCharacterMap) do
        local bestCharKey = nil
        local bestReputation = nil
        local bestChar = nil
        
        local allCharData = {}
        
        -- Iterate all characters for this faction
        for charKey, charData in pairs(charDataMap) do
            local reputation = charData.reputation
            local char = charData.char
            
            -- Add to allCharData array
            table.insert(allCharData, {
                characterName = char.name,
                characterRealm = char.realm or "",
                characterClass = char.classFile or char.class,
                characterLevel = char.level,
                reputation = reputation,
            })
            
            -- Check if this is the best character (highest progress)
            -- FIXED: Use IsReputationHigher() for proper comparison (handles Renown, Paragon, Friendship, etc.)
            if not bestReputation or IsReputationHigher(reputation, bestReputation) then
                bestCharKey = charKey
                bestReputation = reputation
                bestChar = char
            end
        end
        
        -- Sort allCharData by reputation progress (highest first)
        -- FIXED: Use IsReputationHigher() for consistent sorting
        table.sort(allCharData, function(a, b)
            return IsReputationHigher(a.reputation, b.reputation)
        end)
        
        -- Create factionMap entry with BEST character as primary
        if bestCharKey and bestReputation and bestChar then
            -- CRITICAL: Use the hydrated data's isAccountWide flag, NOT hardcoded false.
            -- If the WoW API says this faction is account-wide, respect that even if
            -- it was stored in the character bucket (old data before migration).
            local resolvedAW = (bestReputation and bestReputation.isAccountWide) or false
            
            factionMap[factionID] = {
                data = bestReputation,
                characterKey = resolvedAW and ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide") or bestCharKey,
                characterName = resolvedAW and ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account") or bestChar.name,
                characterRealm = resolvedAW and "" or (bestChar.realm or ""),
                characterClass = resolvedAW and "WARRIOR" or (bestChar.classFile or bestChar.class),
                characterLevel = resolvedAW and 80 or bestChar.level,
                isAccountWide = resolvedAW,
                allCharData = resolvedAW and {} or allCharData,
            }
        end
    end
    
    -- v2.0.0: FIRST - Build parent-child relationships (BEFORE building header groups!)
    -- This ensures subfactions array is populated when we reference it
    local childCount = 0
    
    for factionID, entry in pairs(factionMap) do
        local parentID = entry.data.parentFactionID
        if parentID then
            childCount = childCount + 1
            -- CRITICAL: Type normalization - ensure both are numbers
            local numParentID = tonumber(parentID) or parentID
            local numFactionID = tonumber(factionID) or factionID
            
            -- Try both number and string keys (factionMap might use either)
            local parentEntry = factionMap[numParentID] or factionMap[tostring(numParentID)]
            
            if parentEntry then
                -- This faction is a child of parentID
                if not parentEntry.subfactions then
                    parentEntry.subfactions = {}
                end
                table.insert(parentEntry.subfactions, entry)
            end
        end
    end
    
    -- CRITICAL: Sort subfactions by _scanIndex (Blizzard order), NOT alphabetically
    for factionID, entry in pairs(factionMap) do
        if entry.subfactions and #entry.subfactions > 0 then
            table.sort(entry.subfactions, function(a, b)
                local indexA = (a.data and a.data._scanIndex) or 99999
                local indexB = (b.data and b.data._scanIndex) or 99999
                return indexA < indexB
            end)
        end
    end
    
    -- v2.0.0: Group by expansion headers from NEW cache system
    local headerGroups = {}
    local headerOrder = {}
    local seenHeaders = {}
    local headerFactionLists = {} -- Use ARRAYS to preserve order, not sets
    
    -- Get headers from NEW cache (v2.0.0)
    local cacheHeaders = {}
    if WarbandNexus.GetReputationHeaders then
        cacheHeaders = WarbandNexus:GetReputationHeaders() or {}
    end
    
    -- Fallback to old global headers if new cache not ready
    local globalHeaders = (#cacheHeaders > 0) and cacheHeaders or (WarbandNexus.db.global.reputationHeaders or {})
    
    
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
            
            -- Add if:
            -- 1. Top-level (no parent) OR
            -- 2. HeaderWithRep (can be both parent AND visible row)
            if factionData and (not factionData.data.parentFactionID or factionData.data.isHeaderWithRep) then
                table.insert(headerFactions, {
                    factionID = numFactionID,
                    data = factionData.data,
                    characterKey = factionData.characterKey,
                    characterName = factionData.characterName,
                    characterRealm = factionData.characterRealm,
                    characterClass = factionData.characterClass,
                    characterLevel = factionData.characterLevel,
                    isAccountWide = factionData.isAccountWide,
                    subfactions = factionData.subfactions,  -- NOW populated (built above!)
                    allCharData = factionData.allCharData or {},  -- CRITICAL: Pass allCharData!
                })
            end
        end
        
        -- CRITICAL: Sort by _scanIndex (Blizzard API order), NOT alphabetically
        table.sort(headerFactions, function(a, b)
            local indexA = (a.data and a.data._scanIndex) or 99999
            local indexB = (b.data and b.data._scanIndex) or 99999
            return indexA < indexB
        end)
        
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
        if headerGroups[headerName] then
            table.insert(result, headerGroups[headerName])
        end
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
---PERFORMANCE: Uses pooled rows with lazy child creation (no frame leaks)
---ANIMATION: Supports staggered fade-in via centralized ApplyStaggerAnimation
---@param parent Frame Parent frame
---@param reputation table Reputation data
---@param factionID number Faction ID
---@param rowIndex number Row index for alternating colors
---@param indent number Left indent
---@param rowWidth number Row width
---@param yOffset number Y position
---@param subfactions table|nil Optional subfactions for expandable rows
---@param IsExpanded function Function to check expand state
---@param ToggleExpand function Function to toggle expand state
---@param characterInfo table|nil Optional {name, class, level, isAccountWide} for filtered view
---@param shouldAnimate boolean|nil Whether to play stagger animation
---@return number newYOffset
---@return boolean|nil isExpanded
local function CreateReputationRow(parent, reputation, factionID, rowIndex, indent, rowWidth, yOffset, subfactions, IsExpanded, ToggleExpand, characterInfo, shouldAnimate)
    -- PERFORMANCE: Acquire from pool instead of creating new frames every refresh
    local row = AcquireReputationRow(parent, rowWidth, ROW_HEIGHT)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", indent, -yOffset)
    
    -- Alternating background (centralized helper)
    ns.UI.Factory:ApplyRowBackground(row, rowIndex)
    
    -- ===== COLLAPSE BUTTON (conditional: only for rows with subfactions) =====
    local isExpanded = false
    local hasSubfactions = subfactions and #subfactions > 0
    
    if hasSubfactions then
        local collapseKey = "rep-subfactions-" .. factionID
        isExpanded = IsExpanded(collapseKey, true)
        
        -- Lazy create collapse button (reused across pool cycles)
        if not row.collapseBtn then
            row.collapseBtn = CreateFrame("Button", nil, row)
            row.collapseBtn:SetSize(20, 20)
            row.collapseBtnTexture = row.collapseBtn:CreateTexture(nil, "ARTWORK")
            row.collapseBtnTexture:SetAllPoints()
        end
        
        row.collapseBtn:ClearAllPoints()
        row.collapseBtn:SetPoint("LEFT", 6, 0)
        
        -- Update arrow texture
        if isExpanded then
            row.collapseBtnTexture:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
        else
            row.collapseBtnTexture:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
        end
        
        -- Click handlers (toggle subfaction visibility)
        local function onSubfactionToggle()
            isExpanded = not isExpanded
            if isExpanded then
                row.collapseBtnTexture:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
            else
                row.collapseBtnTexture:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
            end
            ToggleExpand(collapseKey, isExpanded)
        end
        
        row.collapseBtn:SetScript("OnClick", onSubfactionToggle)
        row:SetScript("OnClick", onSubfactionToggle)
        row.collapseBtn:Show()
    end
    
    -- ===== STANDING DISPLAY (normalized data) =====
    local standingWord = ""
    local standingNumber = ""
    local standingColorCode = ""
    
    -- PRIORITY 1: Friendship rank name (e.g., "Mastermind", "Good Friend")
    if reputation.friendship and reputation.friendship.reactionText then
        standingWord = reputation.friendship.reactionText
        standingColorCode = "|cffffcc00"
    -- PRIORITY 2: Renown level (e.g., "Renown 25")
    elseif reputation.renown and reputation.renown.level and reputation.renown.level > 0 then
        standingWord = (ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown"
        standingNumber = tostring(reputation.renown.level)
        standingColorCode = "|cffffcc00"
    -- PRIORITY 3: Friendship level (e.g., "Level 5")
    elseif reputation.friendship and reputation.friendship.level and reputation.friendship.level > 0 then
        standingWord = LEVEL or "Level"
        standingNumber = tostring(reputation.friendship.level)
        standingColorCode = "|cffffcc00"
    -- PRIORITY 4: Classic standing (e.g., "Exalted", "Revered")
    elseif reputation.standing and reputation.standing.name then
        standingWord = reputation.standing.name
        local c = reputation.standing.color
        if c then
            standingColorCode = format("|cff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
        else
            standingColorCode = "|cffffffff"
        end
    -- FALLBACK: Unknown
    else
        standingWord = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
        standingColorCode = "|cffff0000"
    end
    
    -- ===== TEXT ELEMENTS (lazy-created, reused across pool cycles) =====
    local textStartOffset = hasSubfactions and 32 or 10
    
    if standingWord ~= "" then
        -- Standing text
        if not row.standingText then
            row.standingText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.standingText:SetJustifyH("LEFT")
            row.standingText:SetWidth(120)
        end
        row.standingText:ClearAllPoints()
        row.standingText:SetPoint("LEFT", textStartOffset, 0)
        local fullStandingText = standingWord
        if standingNumber ~= "" then
            fullStandingText = standingWord .. " " .. standingNumber
        end
        row.standingText:SetText(standingColorCode .. fullStandingText .. "|r")
        row.standingText:Show()
        
        -- Separator
        if not row.separator then
            row.separator = FontManager:CreateFontString(row, "body", "OVERLAY")
        end
        row.separator:ClearAllPoints()
        row.separator:SetPoint("LEFT", row.standingText, "RIGHT", 10, 0)
        row.separator:SetText("|cff666666-|r")
        row.separator:Show()
        
        -- Faction Name (after separator)
        if not row.nameText then
            row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.nameText:SetNonSpaceWrap(false)
            row.nameText:SetMaxLines(1)
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", row.separator, "RIGHT", 12, 0)
        local actualMaxWidth = math.max(280, (rowWidth or 800) - 240)
        row.nameText:SetWidth(actualMaxWidth)
        row.nameText:SetText(reputation.name or ((ns.L and ns.L["REP_UNKNOWN_FACTION"]) or "Unknown Faction"))
        row.nameText:SetTextColor(1, 1, 1)
        row.nameText:Show()
    else
        -- No standing: hide standing/separator, show name directly
        if row.standingText then row.standingText:Hide() end
        if row.separator then row.separator:Hide() end
        
        if not row.nameText then
            row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.nameText:SetJustifyH("LEFT")
            row.nameText:SetWordWrap(false)
            row.nameText:SetNonSpaceWrap(false)
            row.nameText:SetMaxLines(1)
        end
        row.nameText:ClearAllPoints()
        row.nameText:SetPoint("LEFT", textStartOffset, 0)
        local actualMaxWidth = math.max(300, (rowWidth or 800) - 200)
        row.nameText:SetWidth(actualMaxWidth)
        row.nameText:SetText(reputation.name or ((ns.L and ns.L["REP_UNKNOWN_FACTION"]) or "Unknown Faction"))
        row.nameText:SetTextColor(1, 1, 1)
        row.nameText:Show()
    end
    
    -- ===== CHARACTER BADGE (conditional: only for filtered view) =====
    if characterInfo then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.badgeText:SetJustifyH("LEFT")
            row.badgeText:SetWidth(220)
        end
        local BADGE_ABSOLUTE_X = 475
        local badgeLeftOffset = BADGE_ABSOLUTE_X - indent
        row.badgeText:ClearAllPoints()
        row.badgeText:SetPoint("LEFT", badgeLeftOffset, 0)
        
        if characterInfo.isAccountWide then
            row.badgeText:SetText("|cff666666(|r|cff00ff00" .. ((ns.L and ns.L["ACCOUNT_WIDE_LABEL"]) or "Account-Wide") .. "|r|cff666666)|r")
        elseif characterInfo.name then
            local classColor = RAID_CLASS_COLORS[characterInfo.class] or {r=1, g=1, b=1}
            local classHex = format("%02x%02x%02x", classColor.r*255, classColor.g*255, classColor.b*255)
            local badgeString = "|cff666666(|r|cff" .. classHex .. characterInfo.name
            if characterInfo.realm and characterInfo.realm ~= "" then
                badgeString = badgeString .. " - " .. characterInfo.realm
            end
            badgeString = badgeString .. "|r|cff666666)|r"
            row.badgeText:SetText(badgeString)
        end
        row.badgeText:Show()
    end
    
    -- ===== PROGRESS DATA =====
    local currentValue = reputation.currentValue or 0
    local maxValue = reputation.maxValue or 1
    local isParagon = reputation.hasParagon or false
    
    -- Check if BASE reputation is maxed (for checkmark display)
    local baseReputationMaxed = false
    if isParagon then
        baseReputationMaxed = true
    elseif reputation.type == "renown" and reputation.renown then
        if reputation.renown.maxLevel and reputation.renown.maxLevel > 0 then
            baseReputationMaxed = (reputation.renown.level >= reputation.renown.maxLevel)
        elseif reputation.maxValue == 1 and reputation.currentValue >= 1 then
            baseReputationMaxed = true
        end
    elseif reputation.type == "friendship" and reputation.friendship then
        if reputation.friendship.maxLevel and reputation.friendship.maxLevel > 0 then
            baseReputationMaxed = (reputation.friendship.level >= reputation.friendship.maxLevel)
        elseif reputation.maxValue == 1 and reputation.currentValue >= 1 then
            baseReputationMaxed = true
        end
    elseif reputation.standingID == 8 then
        baseReputationMaxed = (reputation.maxValue == 1 or reputation.currentValue >= reputation.maxValue)
    end
    
    -- ===== PROGRESS BAR (lazy-created, reused across pool cycles) =====
    -- PERFORMANCE FIX: Inline progress bar creation instead of CreateReputationProgressBar()
    -- Old approach created a NEW Frame + 6 textures per row per refresh (~150 rows = ~1050 objects!)
    -- New approach: lazy-create ONCE on the row, then just update values on reuse
    local standingID = reputation.standingID or 4
    local hasRenown = (reputation.type == "renown") or false
    
    if not row._progressBar then
        local pb = {}
        pb.bg = CreateFrame("Frame", nil, row)
        pb.bg:SetFrameLevel(row:GetFrameLevel() + 10)
        
        pb.bgTexture = pb.bg:CreateTexture(nil, "BACKGROUND")
        pb.bgTexture:SetSnapToPixelGrid(false)
        pb.bgTexture:SetTexelSnappingBias(0)
        
        pb.fill = pb.bg:CreateTexture(nil, "ARTWORK")
        pb.fill:SetSnapToPixelGrid(false)
        pb.fill:SetTexelSnappingBias(0)
        
        -- Create all 4 borders once
        local function MakeBorder()
            local t = pb.bg:CreateTexture(nil, "BORDER")
            t:SetTexture("Interface\\Buttons\\WHITE8x8")
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            t:SetDrawLayer("BORDER", 0)
            return t
        end
        pb.borderTop = MakeBorder()
        pb.borderBottom = MakeBorder()
        pb.borderLeft = MakeBorder()
        pb.borderRight = MakeBorder()
        
        row._progressBar = pb
    end
    
    -- Update progress bar with current data (no frame creation on reuse!)
    local pb = row._progressBar
    local barWidth, barHeight = 200, 19
    local borderInset = 1
    local fillInset = borderInset + 1
    local contentWidth = barWidth - (borderInset * 2)
    
    pb.bg:SetSize(barWidth, barHeight)
    pb.bg:ClearAllPoints()
    pb.bg:SetPoint("RIGHT", -10, 0)
    pb.bg:Show()
    
    -- Background
    local bgColor = COLORS.bgCard or {COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.8}
    pb.bgTexture:ClearAllPoints()
    pb.bgTexture:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", borderInset, -borderInset)
    pb.bgTexture:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", -borderInset, borderInset)
    pb.bgTexture:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)
    
    -- Calculate progress
    local progress = 0
    if maxValue > 0 then
        progress = math.min(1, math.max(0, currentValue / maxValue))
    end
    if baseReputationMaxed and not isParagon then progress = 1 end
    
    -- Fill bar
    local fillWidth = math.max((contentWidth - 2) * progress, 0.001)
    pb.fill:ClearAllPoints()
    pb.fill:SetPoint("LEFT", pb.bg, "LEFT", fillInset, 0)
    pb.fill:SetPoint("TOP", pb.bg, "TOP", 0, -fillInset)
    pb.fill:SetPoint("BOTTOM", pb.bg, "BOTTOM", 0, fillInset)
    pb.fill:SetWidth(fillWidth)
    pb.fill:Show()
    
    -- Fill color based on reputation type
    if baseReputationMaxed and not isParagon then
        pb.fill:SetColorTexture(0, 0.8, 0, 1)
    elseif isParagon then
        pb.fill:SetColorTexture(1, 0.4, 1, 1)
    elseif (not hasRenown and reputation.type ~= "friendship") and standingID then
        local standingColors = {
            [1] = {0.8, 0.13, 0.13}, [2] = {0.8, 0.13, 0.13},
            [3] = {0.75, 0.27, 0},    [4] = {0.9, 0.7, 0},
            [5] = {0, 0.6, 0.1},      [6] = {0, 0.6, 0.1},
            [7] = {0, 0.6, 0.1},      [8] = {0, 0.6, 0.1},
        }
        local c = standingColors[standingID] or {0.9, 0.7, 0}
        pb.fill:SetColorTexture(c[1], c[2], c[3], 1)
    else
        local goldColor = COLORS.gold or {1, 0.82, 0, 1}
        pb.fill:SetColorTexture(goldColor[1], goldColor[2], goldColor[3], goldColor[4] or 1)
    end
    
    -- Border color
    local accentColor = COLORS.accent or {0.4, 0.6, 1}
    local br, bgc, bb, ba = accentColor[1], accentColor[2], accentColor[3], 0.6
    
    pb.borderTop:ClearAllPoints()
    pb.borderTop:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", 0, 0)
    pb.borderTop:SetPoint("TOPRIGHT", pb.bg, "TOPRIGHT", 0, 0)
    pb.borderTop:SetHeight(1)
    pb.borderTop:SetVertexColor(br, bgc, bb, ba)
    
    pb.borderBottom:ClearAllPoints()
    pb.borderBottom:SetPoint("BOTTOMLEFT", pb.bg, "BOTTOMLEFT", 0, 0)
    pb.borderBottom:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", 0, 0)
    pb.borderBottom:SetHeight(1)
    pb.borderBottom:SetVertexColor(br, bgc, bb, ba)
    
    pb.borderLeft:ClearAllPoints()
    pb.borderLeft:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", 0, -1)
    pb.borderLeft:SetPoint("BOTTOMLEFT", pb.bg, "BOTTOMLEFT", 0, 1)
    pb.borderLeft:SetWidth(1)
    pb.borderLeft:SetVertexColor(br, bgc, bb, ba)
    
    pb.borderRight:ClearAllPoints()
    pb.borderRight:SetPoint("TOPRIGHT", pb.bg, "TOPRIGHT", 0, -1)
    pb.borderRight:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", 0, 1)
    pb.borderRight:SetWidth(1)
    pb.borderRight:SetVertexColor(br, bgc, bb, ba)
    
    -- Alias for backward compatibility with anchoring below
    local progressBg = pb.bg
    
    -- ===== PARAGON ICON (conditional: only for paragon factions) =====
    if isParagon then
        local iconCreated = false
        
        -- Try layered paragon icon (lazy create)
        local CreateParagonIcon = ns.UI_CreateParagonIcon
        if CreateParagonIcon then
            local hasReward = reputation.paragon and reputation.paragon.hasRewardPending or false
            
            if not row.paragonFrame then
                local success, pFrame = pcall(CreateParagonIcon, row, 18, hasReward)
                if success and pFrame then
                    row.paragonFrame = pFrame
                    row.paragonFrame:EnableMouse(true)
                end
            end
            
            if row.paragonFrame then
                row.paragonFrame:ClearAllPoints()
                row.paragonFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -24, 0)
                
                -- Update tooltip for current data
                row.paragonFrame:SetScript("OnEnter", function(self)
                    local tooltipData = {
                        type = "custom",
                        icon = "Interface\\Icons\\INV_Misc_Bag_10",
                        title = (ns.L and ns.L["REP_PARAGON_TITLE"]) or "Paragon Reputation",
                        lines = {}
                    }
                    if reputation.paragon and reputation.paragon.hasRewardPending then
                        table.insert(tooltipData.lines, {text = (ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward available!", color = {0, 1, 0}})
                    else
                        table.insert(tooltipData.lines, {text = (ns.L and ns.L["REP_CONTINUE_EARNING"]) or "Continue earning reputation for rewards", color = {0.8, 0.8, 0.8}})
                    end
                    if reputation.paragon then
                        table.insert(tooltipData.lines, {text = string.format((ns.L and ns.L["REP_CYCLES_FORMAT"]) or "Cycles: %d", reputation.paragon.completedCycles or 0), color = {0.8, 0.8, 0.8}})
                    end
                    ns.TooltipService:Show(self, tooltipData)
                end)
                row.paragonFrame:SetScript("OnLeave", function(self)
                    ns.TooltipService:Hide()
                end)
                row.paragonFrame:Show()
                iconCreated = true
            end
        end
        
        -- Fallback: Simple bag icon
        if not iconCreated then
            if not row.paragonFrame then
                row.paragonFrame = CreateIcon(row, "Interface\\Icons\\INV_Misc_Bag_10", 18, false, nil, true)
                if row.paragonFrame then
                    row.paragonFrame:EnableMouse(true)
                end
            end
            if row.paragonFrame then
                row.paragonFrame:ClearAllPoints()
                row.paragonFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -24, 0)
                if not (reputation.paragon and reputation.paragon.hasRewardPending) then
                    if row.paragonFrame.texture then
                        row.paragonFrame.texture:SetVertexColor(0.5, 0.5, 0.5, 1)
                    end
                else
                    if row.paragonFrame.texture then
                        row.paragonFrame.texture:SetVertexColor(1, 1, 1, 1)
                    end
                end
                row.paragonFrame:SetScript("OnEnter", function(self)
                    local tooltipData = {
                        type = "custom",
                        icon = "Interface\\Icons\\INV_Misc_Bag_10",
                        title = (ns.L and ns.L["REP_PARAGON_TITLE"]) or "Paragon Reputation",
                        lines = {}
                    }
                    if reputation.paragon and reputation.paragon.hasRewardPending then
                        table.insert(tooltipData.lines, {text = (ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward available!", color = {0, 1, 0}})
                    else
                        table.insert(tooltipData.lines, {text = (ns.L and ns.L["REP_CONTINUE_EARNING"]) or "Continue earning reputation for rewards", color = {0.8, 0.8, 0.8}})
                    end
                    if reputation.paragon then
                        table.insert(tooltipData.lines, {text = string.format((ns.L and ns.L["REP_PROGRESS_HEADER"]) or "Progress: %d / %d", reputation.paragon.current or 0, reputation.paragon.max or 10000), color = {0.8, 0.8, 0.8}})
                        table.insert(tooltipData.lines, {text = string.format((ns.L and ns.L["REP_CYCLES_FORMAT"]) or "Cycles: %d", reputation.paragon.completedCycles or 0), color = {0.8, 0.8, 0.8}})
                    end
                    ns.TooltipService:Show(self, tooltipData)
                end)
                row.paragonFrame:SetScript("OnLeave", function(self)
                    ns.TooltipService:Hide()
                end)
                row.paragonFrame:Show()
                iconCreated = true
            end
        end
        
        if not iconCreated and WarbandNexus.db.profile.debugMode then
            DebugPrint(string.format("|cffff0000[RepUI ERROR]|r Failed to create paragon icon for %s", reputation.name or "Unknown"))
        end
    end
    
    -- ===== CHECKMARK (conditional: only for maxed base reputations) =====
    if baseReputationMaxed then
        if not row.checkFrame then
            row.checkFrame = CreateIcon(row, "Interface\\RaidFrame\\ReadyCheck-Ready", 16, false, nil, true)
        end
        row.checkFrame:ClearAllPoints()
        row.checkFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -4, 0)
        row.checkFrame:Show()
    end
    
    -- ===== PROGRESS TEXT (inside progress bar) =====
    if progressBg then
        if not row.progressText then
            row.progressText = FontManager:CreateFontString(progressBg, "small", "OVERLAY")
            local font, _ = row.progressText:GetFont()
            row.progressText:SetFont(font, 11, "OUTLINE")
            row.progressText:SetJustifyH("CENTER")
            row.progressText:SetJustifyV("MIDDLE")
        end
        -- Reparent to current progress bar (in case it was created by a different pool cycle)
        row.progressText:SetParent(progressBg)
        row.progressText:ClearAllPoints()
        row.progressText:SetPoint("CENTER", progressBg, "CENTER", 0, 0)
        row.progressText:SetText(FormatReputationProgress(currentValue, maxValue))
        row.progressText:SetTextColor(1, 1, 1)
        row.progressText:Show()
    end
    
    -- ===== TOOLTIPS =====
    row:SetScript("OnEnter", function(self)
        local tooltipService = ShowTooltip or (ns and ns.UI_ShowTooltip)
        if not tooltipService then return end
        
        local success, err = pcall(function()
            local lines = {}
            
            -- Paragon info
            if reputation.hasParagon and reputation.paragon then
                table.insert(lines, {
                    left = (ns.L and ns.L["REP_PARAGON_PROGRESS"]) or "Paragon Progress:",
                    right = FormatReputationProgress(reputation.paragon.current, reputation.paragon.max),
                    leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}
                })
                if reputation.paragon.completedCycles and reputation.paragon.completedCycles > 0 then
                    table.insert(lines, {
                        left = (ns.L and ns.L["REP_CYCLES_COLON"]) or "Cycles:",
                        right = tostring(reputation.paragon.completedCycles),
                        leftColor = {1, 0.4, 1}, rightColor = {1, 0.4, 1}
                    })
                end
                if reputation.paragon.hasRewardPending then
                    table.insert(lines, {text = "|cff00ff00" .. ((ns.L and ns.L["REP_REWARD_AVAILABLE"]) or "Reward Available!") .. "|r", color = {1, 1, 1}})
                end
            end
            
            -- Character progress (from aggregated data)
            local allCharData = (characterInfo and characterInfo.allCharData) or {}
            if #allCharData >= 1 then
                table.insert(lines, {type = "spacer", height = 8})
                table.insert(lines, {text = (ns.L and ns.L["REP_CHARACTER_PROGRESS"]) or "Character Progress:", color = {1, 0.82, 0}})
                
                for _, charData in ipairs(allCharData) do
                    local charName = charData.characterName
                    local charReputation = charData.reputation
                    local classFile = string.upper(charData.characterClass or "WARRIOR")
                    local classColor = RAID_CLASS_COLORS[classFile] or {r=1, g=1, b=1}
                    
                    local charProgressText
                    if charReputation.renown and charReputation.renown.level then
                        charProgressText = string.format((ns.L and ns.L["REP_RENOWN_FORMAT"]) or "Renown %d", charReputation.renown.level)
                    elseif charReputation.friendship and charReputation.friendship.standing then
                        charProgressText = string.format("%s (%s)", 
                            charReputation.friendship.standing,
                            FormatReputationProgress(charReputation.currentValue, charReputation.maxValue))
                    elseif charReputation.hasParagon and charReputation.paragon then
                        charProgressText = string.format((ns.L and ns.L["REP_PARAGON_FORMAT"]) or "Paragon (%s)", 
                            FormatReputationProgress(charReputation.paragon.current, charReputation.paragon.max))
                    else
                        charProgressText = string.format("%s (%s)", 
                            charReputation.standing.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"), 
                            FormatReputationProgress(charReputation.currentValue, charReputation.maxValue))
                    end
                    
                    table.insert(lines, {
                        left = charName .. ":", 
                        right = charProgressText,
                        leftColor = {classColor.r, classColor.g, classColor.b},
                        rightColor = {1, 1, 1}
                    })
                end
            end
            
            tooltipService(self, {
                type = "custom",
                icon = reputation.iconTexture,
                title = reputation.name or ((ns.L and ns.L["TAB_REPUTATION"]) or "Reputation"),
                description = (reputation.description and reputation.description ~= "") and reputation.description or nil,
                lines = lines,
                anchor = "ANCHOR_RIGHT"
            })
        end)
        
        if not success then
            DebugPrint("|cffff0000[RepUI Tooltip Error]|r " .. tostring(err))
        end
    end)
    
    row:SetScript("OnLeave", function(self)
        if HideTooltip then
            HideTooltip()
        end
    end)
    
    -- ===== ANIMATION: Staggered fade-in (centralized helper) =====
    ns.UI.Factory:ApplyStaggerAnimation(row, rowIndex, shouldAnimate)
    
    return yOffset + ROW_HEIGHT + GetLayout().betweenRows, isExpanded
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawReputationList(container, width)
    if not container then return 0 end
    
    -- Initialize animation tracking (persistent across refreshes)
    self.recentlyExpanded = self.recentlyExpanded or {}
    
    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(container, "reputation")
    
    -- PERFORMANCE: Release pooled frames back to pool (prevents frame leaks)
    -- This replaces the old SetParent(nil) pattern that caused orphaned frames
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end
    
    local parent = container
    local yOffset = 0
    
    -- ===== TITLE CARD (Always shown) =====
    
    
    -- Check if C_Reputation API is available (for modern WoW)
    if not C_Reputation or not C_Reputation.GetNumFactions then
        local errorFrame = CreateNoticeFrame(
            parent,
            (ns.L and ns.L["REP_API_UNAVAILABLE_TITLE"]) or "Reputation API Not Available",
            (ns.L and ns.L["REP_API_UNAVAILABLE_DESC"]) or "The C_Reputation API is not available on this server. This feature requires WoW 11.0+ (The War Within).",
            "alert",
            width - 20,
            100
        )
        errorFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
        
        return yOffset + GetLayout().emptyStateSpacing + BASE_INDENT
    end
    
    -- Get search text from SearchStateManager
    local reputationSearchText = SearchStateManager:GetQuery("reputation")
    
    -- Get all characters (filter tracked only)
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    if allCharacters then
        for _, char in ipairs(allCharacters) do
            if char.isTracked ~= false then  -- Only tracked characters
                table.insert(characters, char)
            end
        end
    end
    
    if not characters or #characters == 0 then
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, "", "reputation")
        SearchStateManager:UpdateResults("reputation", 0)
        return height
    end
    
    -- Get faction metadata
    local factionMetadata = self.db.global.factionMetadata or {}
    
    -- Expanded state
    local expanded = self.db.profile.reputationExpanded or {}
    
    -- Get current online character
    local currentCharKey = ns.Utilities:GetCharacterKey()
    
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
        -- Track expansion time for stagger animation (like ItemsUI pattern)
        if isExpanded then
            self.recentlyExpanded[key] = GetTime()
        end
        -- PERFORMANCE: Debounce refresh to batch rapid toggle clicks (16ms ≈ 1 frame)
        -- Prevents multiple full rebuilds when user clicks headers quickly
        if self._repToggleTimer then
            self._repToggleTimer:Cancel()
        end
        self._repToggleTimer = C_Timer.NewTimer(0.016, function()
            self._repToggleTimer = nil
            self:RefreshUI()
        end)
    end
    
    -- ===== RENDER CHARACTERS =====
    local hasAnyData = false
    local charactersWithReputations = {}
    
    -- ===== FILTERED VIEW: Show highest reputation from any character =====
    
    local aggregatedHeaders = AggregateReputations(characters, factionMetadata, reputationSearchText)
    
    if not aggregatedHeaders or #aggregatedHeaders == 0 then
        -- Show reputation-specific empty state
        local yOffset = 100
        
        -- Check if this is a search result or general "no data" state
        if reputationSearchText and reputationSearchText ~= "" then
            -- Search-related empty state: use SearchResultsRenderer
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, reputationSearchText, "reputation")
            SearchStateManager:UpdateResults("reputation", 0)
            return height
        else
            -- General "no data" empty state: use standardized factory
            local _, height = CreateEmptyStateCard(parent, "reputation", yOffset)
            SearchStateManager:UpdateResults("reputation", 0)
            return yOffset + height
        end
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
    
    -- Separate account-wide and character-based reputations (single source of truth: entry flag)
    local accountWideHeaders = {}
    local characterBasedHeaders = {}
    local seenInAccountWide = {}  -- [factionID] = true; ensure no faction appears in both sections
    
    for _, headerData in ipairs(aggregatedHeaders) do
        local awFactions = {}
        local cbFactions = {}
        
        for _, faction in ipairs(headerData.factions) do
            -- Use aggregated entry flag first; API fallback only when stored flag is nil (edge case)
            local isAW = faction.isAccountWide or (faction.data and faction.data.isAccountWide)
            if isAW == nil and faction.factionID and C_Reputation and C_Reputation.IsAccountWideReputation then
                isAW = C_Reputation.IsAccountWideReputation(faction.factionID) or false
            end
            if isAW == nil then isAW = false end
            
            local fid = faction.factionID or faction.data and faction.data.factionID
            if isAW then
                table.insert(awFactions, faction)
                if fid then seenInAccountWide[fid] = true end
            else
                -- Stability: do not add to character-based if already in account-wide (should not happen)
                if not (fid and seenInAccountWide[fid]) then
                    table.insert(cbFactions, faction)
                end
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
    
    -- Count total factions (TOP-LEVEL only — excludes children/subfactions)
    local totalAccountWide = 0
    for _, h in ipairs(accountWideHeaders) do
        for _, faction in ipairs(h.factions) do
            if faction and faction.data and not faction.data.parentFactionID then
                totalAccountWide = totalAccountWide + 1
            end
        end
    end
    
    local totalCharacterBased = 0
    for _, h in ipairs(characterBasedHeaders) do
        for _, faction in ipairs(h.factions) do
            if faction and faction.data and not faction.data.parentFactionID then
                totalCharacterBased = totalCharacterBased + 1
            end
        end
    end
    
    -- ===== ACCOUNT-WIDE REPUTATIONS SECTION =====
    local awSectionKey = "filtered-section-accountwide"
    local awSectionExpanded = IsExpanded(awSectionKey, true)  -- Default EXPANDED
    
    local awSectionHeader, awExpandBtn, awSectionIcon = CreateCollapsibleHeader(
        parent,
        format((ns.L and ns.L["REP_SECTION_ACCOUNT_WIDE"]) or "Account-Wide Reputations (%s)", FormatNumber(totalAccountWide)),
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
    
    -- Show expand/collapse button
    if awExpandBtn then
        awExpandBtn:Show()
    end
    
    awSectionHeader:SetPoint("TOPLEFT", 0, -yOffset)
    awSectionHeader:SetPoint("TOPRIGHT", 0, -yOffset)
    awSectionHeader:SetWidth(width)
    -- Removing custom tint to match other tabs/headers
    -- awSectionHeader:SetBackdropColor(0.15, 0.08, 0.20, 1)  -- Purple-ish
    -- awSectionHeader:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    
    yOffset = yOffset + HEADER_SPACING  -- Section header + spacing before content
    
    if awSectionExpanded then
        if totalAccountWide == 0 then
            -- Empty state
            local emptyText = FontManager:CreateFontString(parent, "body", "OVERLAY")
            emptyText:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
            emptyText:SetTextColor(1, 1, 1)  -- White
            emptyText:SetText((ns.L and ns.L["NO_ACCOUNT_WIDE_REPS"]) or "No account-wide reputations")
            yOffset = yOffset + 60  -- Empty state spacing
        else
            -- Render each expansion header (Account-Wide)
            for _, headerData in ipairs(accountWideHeaders) do
                -- Skip header if it has no factions (hide empty headers)
                if #headerData.factions > 0 then
                
                -- PRE-FILTER: Build faction list and apply search BEFORE rendering header
                -- This ensures we skip expansion headers with zero matching results
                local headerIndent = BASE_INDENT
                local factionList = {}
                
                for _, faction in ipairs(headerData.factions) do
                    if not faction or not faction.data then
                        -- Skip invalid faction
                    elseif not faction.data.parentFactionID then
                        table.insert(factionList, {
                            faction = faction,
                            subfactions = faction.subfactions,
                            originalIndex = faction.factionID
                        })
                    end
                end
                
                -- Phase 2.4: Check cache for filtered results
                local searchTextKey = reputationSearchText or ""
                local isSearching = searchTextKey ~= ""  -- Scoped OUTSIDE cache check
                local cacheKey = headerData.name .. "|AW|" .. searchTextKey
                local cachedResult = cachedFilteredResults[cacheKey]
                
                local filteredFactionList
                if cachedResult and cachedResult.searchText == searchTextKey then
                    -- Cache hit: reuse filtered results
                    filteredFactionList = cachedResult.filteredList
                else
                    -- Cache miss: apply search filter
                    filteredFactionList = {}
                    for _, item in ipairs(factionList) do
                        local itemName = (item.faction.data.name or ""):lower()
                        local parentMatches = not isSearching or itemName:find(reputationSearchText, 1, true)
                        
                        local filteredSubs = nil
                        local hasMatchingSub = false
                        if isSearching and item.subfactions and not parentMatches then
                            filteredSubs = {}
                            for _, sub in ipairs(item.subfactions) do
                                local subName = (sub.data.name or ""):lower()
                                if subName:find(reputationSearchText, 1, true) then
                                    table.insert(filteredSubs, sub)
                                    hasMatchingSub = true
                                end
                            end
                        end
                        
                        if parentMatches then
                            table.insert(filteredFactionList, item)
                        elseif hasMatchingSub then
                            table.insert(filteredFactionList, {
                                faction = item.faction,
                                subfactions = filteredSubs,
                                originalIndex = item.originalIndex,
                                _forceExpand = true,
                            })
                        end
                    end
                    
                    -- Cache the result
                    cachedFilteredResults[cacheKey] = {
                        searchText = searchTextKey,
                        filteredList = filteredFactionList
                    }
                end
                
                -- Skip rendering this expansion header entirely if search yields no results
                if not isSearching or #filteredFactionList > 0 then
                
                    local headerKey = "filtered-header-" .. headerData.name
                    local headerExpanded = IsExpanded(headerKey, true)
                    
                    if isSearching then
                        headerExpanded = true
                    end
                    
                    -- Count: use factionList (top-level only) not headerData.factions (includes children)
                    -- This ensures the count matches what the user actually sees
                    local filteredCount = isSearching and #filteredFactionList or #factionList
                    local header, headerBtn = CreateCollapsibleHeader(
                        parent,
                        headerData.name .. " (" .. FormatNumber(filteredCount) .. ")",
                        headerKey,
                        headerExpanded,
                        function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                        GetHeaderIcon(headerData.name)
                    )
                    
                    if headerBtn then
                        headerBtn:Show()
                    end
                    
                    header:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                    header:SetWidth(width - BASE_INDENT)
                    
                    yOffset = yOffset + GetLayout().HEADER_HEIGHT
                    
                    if headerExpanded then
                
                -- Compute animation state for this expansion header's rows
                local shouldAnimate = self.recentlyExpanded[headerKey] and (GetTime() - self.recentlyExpanded[headerKey] < 0.5)
                
                -- Render factions
                local rowIdx = 0
                for _, item in ipairs(filteredFactionList) do
                    rowIdx = rowIdx + 1
                    
                    local charInfo = {
                        name = item.faction.characterName,
                        class = item.faction.characterClass,
                        level = item.faction.characterLevel,
                        isAccountWide = item.faction.isAccountWide,
                        realm = item.faction.characterRealm,
                        allCharData = item.faction.allCharData or {}
                    }
                    
                    local rowWidth = width - headerIndent
                    local subsToRender = item.subfactions
                    local newYOffset, isExpanded = CreateReputationRow(
                        parent, 
                        item.faction.data, 
                        item.faction.factionID, 
                        rowIdx, 
                        headerIndent, 
                        rowWidth, 
                        yOffset, 
                        subsToRender, 
                        IsExpanded, 
                        ToggleExpand, 
                        charInfo,
                        shouldAnimate
                    )
                    yOffset = newYOffset
                    
                    -- Show sub-factions if expanded OR force-expanded by search
                    local showSubs = isExpanded or item._forceExpand
                    if showSubs and subsToRender and #subsToRender > 0 then
                        -- Compute animation for subfaction expand
                        local subfactionKey = "rep-subfactions-" .. item.faction.factionID
                        local subShouldAnimate = self.recentlyExpanded[subfactionKey] and (GetTime() - self.recentlyExpanded[subfactionKey] < 0.5)
                        
                        local subIndent = headerIndent + BASE_INDENT + SUBROW_EXTRA_INDENT
                        local subRowIdx = 0
                        for _, subFaction in ipairs(subsToRender) do
                            subRowIdx = subRowIdx + 1
                            
                            local subCharInfo = {
                                name = subFaction.characterName,
                                class = subFaction.characterClass,
                                level = subFaction.characterLevel,
                                isAccountWide = subFaction.isAccountWide,
                                realm = subFaction.characterRealm,
                                allCharData = subFaction.allCharData or {}
                            }
                            
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
                                subCharInfo,
                                subShouldAnimate or shouldAnimate
                            )
                        end
                    end
                end
                end
                
                -- Add spacing after each expansion section (whether expanded or not)
                yOffset = yOffset + SECTION_SPACING
                
                end  -- if not isSearching or #filteredFactionList > 0
            end  -- if #headerData.factions > 0
        end
        end  -- End Account-Wide section expanded
        end  -- End Account-Wide section
        
        -- ===== CHARACTER-BASED REPUTATIONS SECTION =====
        local cbSectionKey = "filtered-section-characterbased"
        local cbSectionExpanded = IsExpanded(cbSectionKey, true)  -- Default EXPANDED
        
        local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
        local cbSectionHeader, cbExpandBtn = CreateCollapsibleHeader(
            parent,
            format((ns.L and ns.L["REP_SECTION_CHARACTER_BASED"]) or "Character-Based Reputations (%s)", FormatNumber(totalCharacterBased)),
            cbSectionKey,
            cbSectionExpanded,
            function(isExpanded) ToggleExpand(cbSectionKey, isExpanded) end,
            GetCharacterSpecificIcon(),
            true  -- isAtlas = true
        )
        
        -- Show expand/collapse button
        if cbExpandBtn then
            cbExpandBtn:Show()
        end
        
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
                local emptyText = FontManager:CreateFontString(parent, "body", "OVERLAY")
                emptyText:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                emptyText:SetTextColor(1, 1, 1)  -- White
                emptyText:SetText((ns.L and ns.L["NO_CHARACTER_REPS"]) or "No character-based reputations")
                yOffset = yOffset + SECTION_SPACING
            else
                -- Render each expansion header (Character-Based)
                for _, headerData in ipairs(characterBasedHeaders) do
                    -- Skip header if it has no factions (hide empty headers)
                    if #headerData.factions > 0 then
                    
                    -- PRE-FILTER: Build faction list and apply search BEFORE rendering header
                    local headerIndent = BASE_INDENT
                    local factionList = {}
                    
                    for _, faction in ipairs(headerData.factions) do
                        if not faction or not faction.data then
                            -- Skip invalid
                        elseif not faction.data.parentFactionID then
                            table.insert(factionList, {
                                faction = faction,
                                subfactions = faction.subfactions,
                                originalIndex = faction.factionID
                            })
                        end
                    end
                    
                    -- Phase 2.4: Check cache for filtered results
                    local searchTextKey = reputationSearchText or ""
                    local isSearching = searchTextKey ~= ""  -- Scoped OUTSIDE cache check
                    local cacheKey = headerData.name .. "|CB|" .. searchTextKey
                    local cachedResult = cachedFilteredResults[cacheKey]
                    
                    local filteredFactionList
                    if cachedResult and cachedResult.searchText == searchTextKey then
                        -- Cache hit: reuse filtered results
                        filteredFactionList = cachedResult.filteredList
                    else
                        -- Cache miss: apply search filter
                        filteredFactionList = {}
                        for _, item in ipairs(factionList) do
                            local itemName = (item.faction.data.name or ""):lower()
                            local parentMatches = not isSearching or itemName:find(reputationSearchText, 1, true)
                            
                            local filteredSubs = nil
                            local hasMatchingSub = false
                            if isSearching and item.subfactions and not parentMatches then
                                filteredSubs = {}
                                for _, sub in ipairs(item.subfactions) do
                                    local subName = (sub.data.name or ""):lower()
                                    if subName:find(reputationSearchText, 1, true) then
                                        table.insert(filteredSubs, sub)
                                        hasMatchingSub = true
                                    end
                                end
                            end
                            
                            if parentMatches then
                                table.insert(filteredFactionList, item)
                            elseif hasMatchingSub then
                                table.insert(filteredFactionList, {
                                    faction = item.faction,
                                    subfactions = filteredSubs,
                                    originalIndex = item.originalIndex,
                                    _forceExpand = true,
                                })
                            end
                        end
                        
                        -- Cache the result
                        cachedFilteredResults[cacheKey] = {
                            searchText = searchTextKey,
                            filteredList = filteredFactionList
                        }
                    end
                    
                    -- Skip expansion header entirely if search yields no results
                    if not isSearching or #filteredFactionList > 0 then
                    
                        local headerKey = "filtered-cb-header-" .. headerData.name
                        local headerExpanded = IsExpanded(headerKey, true)
                        
                        if isSearching then
                            headerExpanded = true
                        end
                        
                        -- Count: use factionList (top-level only) not headerData.factions (includes children)
                        local filteredCount = isSearching and #filteredFactionList or #factionList
                        local header, headerBtn = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. filteredCount .. ")",
                            headerKey,
                            headerExpanded,
                            function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                            GetHeaderIcon(headerData.name)
                        )
                    
                        if headerBtn then
                            headerBtn:Show()
                        end
                    
                        header:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)
                        header:SetWidth(width - BASE_INDENT)
                    
                        yOffset = yOffset + GetLayout().HEADER_HEIGHT
                    
                    if headerExpanded then
                        
                        -- Compute animation state for this expansion header's rows
                        local shouldAnimate = self.recentlyExpanded[headerKey] and (GetTime() - self.recentlyExpanded[headerKey] < 0.5)
                        
                        -- Render factions
                        local rowIdx = 0
                        for _, item in ipairs(filteredFactionList) do
                            rowIdx = rowIdx + 1
                            
                            local charInfo = {
                                name = item.faction.characterName,
                                class = item.faction.characterClass,
                                level = item.faction.characterLevel,
                                isAccountWide = item.faction.isAccountWide,
                                realm = item.faction.characterRealm,
                                allCharData = item.faction.allCharData or {}
                            }
                            
                            local rowWidth = width - headerIndent
                            local subsToRender = item.subfactions
                            local newYOffset, isExpanded = CreateReputationRow(
                                parent, 
                                item.faction.data, 
                                item.faction.factionID, 
                                rowIdx, 
                                headerIndent, 
                                rowWidth, 
                                yOffset, 
                                subsToRender, 
                                IsExpanded, 
                                ToggleExpand, 
                                charInfo,
                                shouldAnimate
                            )
                            yOffset = newYOffset
                            
                            local showSubs = isExpanded or item._forceExpand
                            if showSubs and subsToRender and #subsToRender > 0 then
                                -- Compute animation for subfaction expand
                                local subfactionKey = "rep-subfactions-" .. item.faction.factionID
                                local subShouldAnimate = self.recentlyExpanded[subfactionKey] and (GetTime() - self.recentlyExpanded[subfactionKey] < 0.5)
                                
                                local subIndent = headerIndent + BASE_INDENT + SUBROW_EXTRA_INDENT
                                local subRowIdx = 0
                                for _, subFaction in ipairs(subsToRender) do
                                    subRowIdx = subRowIdx + 1
                                    
                                    local subCharInfo = {
                                        name = subFaction.characterName,
                                        class = subFaction.characterClass,
                                        level = subFaction.characterLevel,
                                        isAccountWide = subFaction.isAccountWide,
                                        realm = subFaction.characterRealm,
                                        allCharData = subFaction.allCharData or {}
                                    }
                                    
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
                                        subCharInfo,
                                        subShouldAnimate or shouldAnimate
                                    )
                            end
                        end
                    end
                    end
                    
                    -- Add spacing after each expansion section (whether expanded or not)
                    yOffset = yOffset + SECTION_SPACING
                    
                    end  -- if not isSearching or #filteredFactionList > 0
                end  -- if #headerData.factions > 0
            end  -- for headerData
            end  -- else (totalCharacterBased > 0)
        end  -- End Character-Based section expanded
    
    -- ===== FOOTER NOTE =====
    yOffset = yOffset + (SECTION_SPACING * 2)  -- Double spacing before footer
    
    local noticeFrame = CreateNoticeFrame(
        parent,
        (ns.L and ns.L["REP_FOOTER_TITLE"]) or "Reputation Tracking",
        (ns.L and ns.L["REP_FOOTER_DESC"]) or "Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards.",
        "info",
        width - 20,
        60
    )
    noticeFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after notice
    
    -- Update SearchStateManager with result count
    -- Count from aggregated filtered data
    local totalReputations = 0
    if aggregatedHeaders then
        for _, headerGroup in ipairs(aggregatedHeaders) do
            if headerGroup and headerGroup.factions then
                totalReputations = totalReputations + #headerGroup.factions
            end
        end
    end
    SearchStateManager:UpdateResults("reputation", totalReputations)
    
    return yOffset
end

--============================================================================
-- REPUTATION TAB WRAPPER (Fixes focus issue)
--============================================================================

function WarbandNexus:DrawReputationTab(parent)
    if not parent then
        self:Print("|cffff0000ERROR: No parent container provided to DrawReputationTab|r")
        return
    end
    
    -- Register event listener for reputation updates (only once per parent)
    if not parent.reputationUpdateHandler then
        parent.reputationUpdateHandler = true
        
        -- Loading started - only refresh if visible
        self:RegisterMessage("WN_REPUTATION_LOADING_STARTED", function()
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            
            if parent and parent:IsVisible() then
                self:DrawReputationTab(parent)
            end
        end)
        
        -- v2.0.0: Cache cleared - always refresh
        self:RegisterMessage("WN_REPUTATION_CACHE_CLEARED", function()
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            -- Show loading UI if tab is currently visible
            if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab == "reputations" then
                if parent.loadingText then
                    parent.loadingText:Show()
                    parent.loadingText:SetText("|cffffcc00" .. ((ns.L and ns.L["REP_CLEARING_CACHE"]) or "Clearing cache and reloading...") .. "|r")
                end
                
                -- Hide all content frames
                local children = {parent:GetChildren()}
                for _, child in pairs(children) do
                    if child ~= parent.dbVersionBadge 
                       and child ~= parent.emptyStateContainer 
                       and child ~= parent.loadingText then
                        child:Hide()
                    end
                end
            end
        end)
        
    -- v2.0.0: Cache ready (hide loading, show content) - only refresh if visible
    self:RegisterMessage("WN_REPUTATION_CACHE_READY", function()
        -- Phase 2.4: Invalidate search cache
        cachedFilteredResults = {}
        cachedSearchText = nil
        
        if parent.loadingText then
            parent.loadingText:Hide()
        end
        
        -- Only refresh if visible
        if parent and parent:IsVisible() then
            self:DrawReputationTab(parent)
        end
    end)
        
        -- Legacy event support (redraw tab) - only refresh if visible
        self:RegisterMessage("WARBAND_REPUTATIONS_UPDATED", function()
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            
            if parent and parent:IsVisible() then
                self:DrawReputationTab(parent)
            end
        end)
        
        -- Real-time update event (single faction changed) - only refresh if visible
        self:RegisterMessage("WN_REPUTATION_UPDATED", function(event, factionID)
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            
            if parent and parent:IsVisible() then
                self:DrawReputationTab(parent)
            end
        end)
    end
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "ReputationCache [Loading...]"
        if self.db.global.reputationCache and next(self.db.global.reputationCache.factions or {}) then
            local cacheVersion = self.db.global.reputationCache.version or "unknown"
            dataSource = "ReputationCache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Create loading text (persistent element)
    if not parent.loadingText then
        parent.loadingText = FontManager:CreateFontString(parent, "header", "OVERLAY")
        parent.loadingText:SetPoint("CENTER", 0, 0)
        parent.loadingText:SetTextColor(1, 0.8, 0, 1)  -- Gold
        parent.loadingText:SetText("|cffffcc00" .. ((ns.L and ns.L["REP_LOADING_DATA"]) or "Loading reputation data...") .. "|r")
        parent.loadingText:Hide()  -- Hidden by default
    end
    
    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(parent, "reputation")
    
    -- Clear all old frames (including FontStrings)
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
        -- Keep only persistent UI elements (badge, title card, loading text)
        if child ~= parent.dbVersionBadge 
           and child ~= parent.emptyStateContainer 
           and child ~= parent.loadingText then
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
        end
    end
    
    -- Also clear FontStrings (they're not children, they're regions)
    local regions = {parent:GetRegions()}
    for _, region in pairs(regions) do
        if region:GetObjectType() == "FontString" then
            pcall(function()
                region:Hide()
                region:ClearAllPoints()
            end)
        end
    end
    
    local yOffset = 8 -- Top padding
    local width = parent:GetWidth() - 20
    
    -- Check if module is enabled (early check)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.reputations ~= false
    
    -- ===== TITLE CARD =====
    local CreateCard = ns.UI_CreateCard
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Header icon with ring border
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("reputation"))
    
    -- Use factory pattern positioning for standardized header layout
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["REP_TITLE"]) or "Reputation Overview") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["REP_SUBTITLE"]) or "Track factions and renown across your warband"
    
    -- Create container for text group (using Factory pattern)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    -- View Mode: Always use Filtered View (All Characters view removed)
    
    titleCard:Show()
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after title card
    
    -- If module is disabled, show beautiful disabled state card
    if not moduleEnabled then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (ns.L and ns.L["REP_DISABLED_TITLE"]) or "Reputation Tracking")
        return yOffset + cardHeight
    end
    
    -- ===== LOADING STATE =====
    -- Show loading card if reputation scan is in progress
    if ns.ReputationLoadingState and ns.ReputationLoadingState.isLoading then
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                ns.ReputationLoadingState,
                (ns.L and ns.L["REP_LOADING_TITLE"]) or "Loading Reputation Data"
            )
            return newYOffset
        end
    end
    
    -- ===== SEARCH BOX =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    -- Use SearchStateManager for state management
    local reputationSearchText = SearchStateManager:GetQuery("reputation")
    
    local searchBox = CreateSearchBox(parent, width, (ns.L and ns.L["REP_SEARCH"]) or "Search reputations...", function(text)
        -- Update search state via SearchStateManager (throttled, event-driven)
        SearchStateManager:SetSearchQuery("reputation", text)
        
        -- Prepare container for rendering
        if parent.resultsContainer then
            SearchResultsRenderer:PrepareContainer(parent.resultsContainer)
            
            -- Redraw reputation list
            self:DrawReputationList(parent.resultsContainer, width)
        end
    end, 0.4, reputationSearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + GetLayout().afterElement  -- Search box height + standard gap
    
    -- Results Container
    if not parent.resultsContainer then
        local container = ns.UI.Factory:CreateContainer(parent)
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
