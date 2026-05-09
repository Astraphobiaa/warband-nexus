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
local Constants = ns.Constants
local E = Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management
local ReputationUIEvents = {} -- Unique AceEvent identity for this module

local issecretvalue = issecretvalue

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

-- Debug helper
local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter("|cff00ff00[RepUI]|r"))
    or ns.DebugPrint
    or function() end
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Import shared UI components
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
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
local ReleaseReputationRow = ns.UI_ReleaseReputationRow

local ReleaseReputationRowsFromSubtree = ns.UI_ReleaseReputationRowsFromSubtree
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance: Local function references
local format = string.format
local floor = math.floor

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
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
local SUBHEADER_SPACING = GetLayout().SUBHEADER_SPACING or 44
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
    if not searchText then
        return true
    end
    if issecretvalue and issecretvalue(searchText) then
        return true
    end
    if searchText == "" then
        return true
    end
    
    local name = SafeLower(reputation.name)
    
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
    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(char.name, char.realm)
        if charKey then charLookup[charKey] = char end
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
    
    for cfi = 1, #cachedFactions do
        local cachedData = cachedFactions[cfi]
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
                local charKey = cachedData._characterKey or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
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
    
    
    for ghi = 1, #globalHeaders do
        local headerData = globalHeaders[ghi]
        if headerData and headerData.name then
            
                if not seenHeaders[headerData.name] then
                    seenHeaders[headerData.name] = true
                    table.insert(headerOrder, headerData.name)
                    headerFactionLists[headerData.name] = {}  -- Array, not set
                end
                
                -- Add factions in ORDER, avoiding duplicates
                local existingFactions = {}
                local hflExisting = headerFactionLists[headerData.name]
                for fii = 1, #hflExisting do
                    local fid = hflExisting[fii]
                    -- Convert to number for consistent comparison
                    local numFid = tonumber(fid) or fid
                    existingFactions[numFid] = true
                end
                
            local hdrFactions = headerData.factions or {}
            for fai = 1, #hdrFactions do
                local factionID = hdrFactions[fai]
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
    for hoi = 1, #headerOrder do
        local headerName = headerOrder[hoi]
        local headerFactions = {}
        
        -- Iterate in ORDER (not random key-value pairs)
        local hflOrdered = headerFactionLists[headerName]
        for fii = 1, #hflOrdered do
            local factionID = hflOrdered[fii]
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
    for hoi = 1, #headerOrder do
        local headerName = headerOrder[hoi]
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
---@return number newYOffset
---@return boolean|nil isExpanded
local function CreateReputationRow(parent, reputation, factionID, rowIndex, indent, rowWidth, yOffset, subfactions, IsExpanded, ToggleExpand, characterInfo)
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
                local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(characterInfo.realm) or characterInfo.realm
                badgeString = badgeString .. " - " .. displayRealm
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
            baseReputationMaxed = ((reputation.renown.level or 0) >= reputation.renown.maxLevel)
        elseif reputation.maxValue == 1 and currentValue >= 1 then
            baseReputationMaxed = true
        end
    elseif reputation.type == "friendship" and reputation.friendship then
        if reputation.friendship.maxLevel and reputation.friendship.maxLevel > 0 then
            baseReputationMaxed = ((reputation.friendship.level or 0) >= reputation.friendship.maxLevel)
        elseif reputation.maxValue == 1 and currentValue >= 1 then
            baseReputationMaxed = true
        end
    elseif reputation.standingID == 8 then
        baseReputationMaxed = (reputation.maxValue == 1 or currentValue >= maxValue)
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
        
        if not iconCreated and IsDebugModeEnabled and IsDebugModeEnabled() then
            local repLabel = "Unknown"
            local n = reputation.name
            if n and type(n) == "string" and n ~= "" and not (issecretvalue and issecretvalue(n)) then
                repLabel = n
            end
            DebugPrint("|cffff0000[RepUI ERROR]|r Failed to create paragon icon for " .. repLabel)
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
            row.progressText:SetJustifyH("CENTER")
            row.progressText:SetJustifyV("MIDDLE")
        end
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
                
                for aci = 1, #allCharData do
                    local charData = allCharData[aci]
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
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                local errMsg = "(error)"
                if type(err) == "string" and err ~= "" and not (issecretvalue and issecretvalue(err)) then
                    errMsg = err
                end
                DebugPrint("|cffff0000[RepUI Tooltip Error]|r " .. errMsg)
            end
        end
    end)
    
    row:SetScript("OnLeave", function(self)
        if HideTooltip then
            HideTooltip()
        end
    end)
    
    -- ===== ANIMATION: Staggered fade-in (centralized helper) =====
    return yOffset + ROW_HEIGHT + GetLayout().betweenRows, isExpanded
end

---Populate a reputation row frame with data (for virtual list reuse)
---@param row Frame Pooled reputation row frame
---@param entry table Flat list entry with .data (reputation), .factionID, .rowIdx, .rowWidth, .subfactions, .characterInfo, .IsExpanded, .ToggleExpand, .isSubfaction
local function PopulateReputationRow(row, entry)
    local reputation = entry.data
    local factionID = entry.factionID
    local rowIndex = entry.rowIdx
    local rowWidth = entry.rowWidth or 800
    local subfactions = entry.subfactions
    local characterInfo = entry.characterInfo
    local IsExpanded = entry.IsExpanded
    local ToggleExpand = entry.ToggleExpand

    -- Alternating background
    ns.UI.Factory:ApplyRowBackground(row, rowIndex)

    -- ===== COLLAPSE BUTTON (conditional: only for rows with subfactions) =====
    local isExpanded = false
    local hasSubfactions = subfactions and #subfactions > 0

    if hasSubfactions then
        local collapseKey = "rep-subfactions-" .. factionID
        isExpanded = IsExpanded(collapseKey, true)

        if not row.collapseBtn then
            row.collapseBtn = CreateFrame("Button", nil, row)
            row.collapseBtn:SetSize(20, 20)
            row.collapseBtnTexture = row.collapseBtn:CreateTexture(nil, "ARTWORK")
            row.collapseBtnTexture:SetAllPoints()
        end

        row.collapseBtn:ClearAllPoints()
        row.collapseBtn:SetPoint("LEFT", 6, 0)

        if isExpanded then
            row.collapseBtnTexture:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
        else
            row.collapseBtnTexture:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
        end

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
    else
        if row.collapseBtn then row.collapseBtn:Hide() end
    end

    -- ===== STANDING DISPLAY =====
    local standingWord = ""
    local standingNumber = ""
    local standingColorCode = ""

    if reputation.friendship and reputation.friendship.reactionText then
        standingWord = reputation.friendship.reactionText
        standingColorCode = "|cffffcc00"
    elseif reputation.renown and reputation.renown.level and reputation.renown.level > 0 then
        standingWord = (ns.L and ns.L["RENOWN_TYPE_LABEL"]) or "Renown"
        standingNumber = tostring(reputation.renown.level)
        standingColorCode = "|cffffcc00"
    elseif reputation.friendship and reputation.friendship.level and reputation.friendship.level > 0 then
        standingWord = LEVEL or "Level"
        standingNumber = tostring(reputation.friendship.level)
        standingColorCode = "|cffffcc00"
    elseif reputation.standing and reputation.standing.name then
        standingWord = reputation.standing.name
        local c = reputation.standing.color
        if c then
            standingColorCode = format("|cff%02x%02x%02x", (c.r or 1) * 255, (c.g or 1) * 255, (c.b or 1) * 255)
        else
            standingColorCode = "|cffffffff"
        end
    else
        standingWord = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
        standingColorCode = "|cffff0000"
    end

    local textStartOffset = hasSubfactions and 32 or 10

    if standingWord ~= "" then
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

        if not row.separator then
            row.separator = FontManager:CreateFontString(row, "body", "OVERLAY")
        end
        row.separator:ClearAllPoints()
        row.separator:SetPoint("LEFT", row.standingText, "RIGHT", 10, 0)
        row.separator:SetText("|cff666666-|r")
        row.separator:Show()

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

    -- ===== CHARACTER BADGE =====
    if characterInfo then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.badgeText:SetJustifyH("LEFT")
            row.badgeText:SetWidth(220)
        end
        local BADGE_ABSOLUTE_X = 475
        local indent = entry.xOffset or 0
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
                local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(characterInfo.realm) or characterInfo.realm
                badgeString = badgeString .. " - " .. displayRealm
            end
            badgeString = badgeString .. "|r|cff666666)|r"
            row.badgeText:SetText(badgeString)
        end
        row.badgeText:Show()
    else
        if row.badgeText then row.badgeText:Hide() end
    end

    -- ===== PROGRESS DATA =====
    local currentValue = reputation.currentValue or 0
    local maxValue = reputation.maxValue or 1
    local isParagon = reputation.hasParagon or false

    local baseReputationMaxed = false
    if isParagon then
        baseReputationMaxed = true
    elseif reputation.type == "renown" and reputation.renown then
        if reputation.renown.maxLevel and reputation.renown.maxLevel > 0 then
            baseReputationMaxed = ((reputation.renown.level or 0) >= reputation.renown.maxLevel)
        elseif reputation.maxValue == 1 and currentValue >= 1 then
            baseReputationMaxed = true
        end
    elseif reputation.type == "friendship" and reputation.friendship then
        if reputation.friendship.maxLevel and reputation.friendship.maxLevel > 0 then
            baseReputationMaxed = ((reputation.friendship.level or 0) >= reputation.friendship.maxLevel)
        elseif reputation.maxValue == 1 and currentValue >= 1 then
            baseReputationMaxed = true
        end
    elseif reputation.standingID == 8 then
        baseReputationMaxed = (reputation.maxValue == 1 or currentValue >= maxValue)
    end

    -- ===== PROGRESS BAR =====
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

    local pb = row._progressBar
    local barWidth, barHeight = 200, 19
    local borderInset = 1
    local fillInset = borderInset + 1
    local contentWidth = barWidth - (borderInset * 2)

    pb.bg:SetSize(barWidth, barHeight)
    pb.bg:ClearAllPoints()
    pb.bg:SetPoint("RIGHT", -10, 0)
    pb.bg:Show()

    local bgColor = COLORS.bgCard or {COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.8}
    pb.bgTexture:ClearAllPoints()
    pb.bgTexture:SetPoint("TOPLEFT", pb.bg, "TOPLEFT", borderInset, -borderInset)
    pb.bgTexture:SetPoint("BOTTOMRIGHT", pb.bg, "BOTTOMRIGHT", -borderInset, borderInset)
    pb.bgTexture:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)

    local progress = 0
    if maxValue > 0 then
        progress = math.min(1, math.max(0, currentValue / maxValue))
    end
    if baseReputationMaxed and not isParagon then progress = 1 end

    local fillWidth = math.max((contentWidth - 2) * progress, 0.001)
    pb.fill:ClearAllPoints()
    pb.fill:SetPoint("LEFT", pb.bg, "LEFT", fillInset, 0)
    pb.fill:SetPoint("TOP", pb.bg, "TOP", 0, -fillInset)
    pb.fill:SetPoint("BOTTOM", pb.bg, "BOTTOM", 0, fillInset)
    pb.fill:SetWidth(fillWidth)
    pb.fill:Show()

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

    local progressBg = pb.bg

    -- ===== PARAGON ICON =====
    if isParagon then
        local iconCreated = false
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
    else
        if row.paragonFrame then row.paragonFrame:Hide() end
    end

    -- ===== CHECKMARK =====
    if baseReputationMaxed then
        if not row.checkFrame then
            row.checkFrame = CreateIcon(row, "Interface\\RaidFrame\\ReadyCheck-Ready", 16, false, nil, true)
        end
        row.checkFrame:ClearAllPoints()
        row.checkFrame:SetPoint("RIGHT", progressBg or row, progressBg and "LEFT" or "RIGHT", -4, 0)
        row.checkFrame:Show()
    else
        if row.checkFrame then row.checkFrame:Hide() end
    end

    -- ===== PROGRESS TEXT =====
    if progressBg then
        if not row.progressText then
            row.progressText = FontManager:CreateFontString(progressBg, "small", "OVERLAY")
            row.progressText:SetJustifyH("CENTER")
            row.progressText:SetJustifyV("MIDDLE")
        end
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

            local allCharData = (characterInfo and characterInfo.allCharData) or {}
            if #allCharData >= 1 then
                table.insert(lines, {type = "spacer", height = 8})
                table.insert(lines, {text = (ns.L and ns.L["REP_CHARACTER_PROGRESS"]) or "Character Progress:", color = {1, 0.82, 0}})

                for aci = 1, #allCharData do
                    local charData = allCharData[aci]
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
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                local errMsg = "(error)"
                if type(err) == "string" and err ~= "" and not (issecretvalue and issecretvalue(err)) then
                    errMsg = err
                end
                DebugPrint("|cffff0000[RepUI Tooltip Error]|r " .. errMsg)
            end
        end
    end)

    row:SetScript("OnLeave", function(self)
        if HideTooltip then
            HideTooltip()
        end
    end)
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawReputationList(container, width)
    if not container then return 0 end
    
    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(container, "reputation")

    local mfForVirtual = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfForVirtual and ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
    end
    
    -- PERFORMANCE: Release pooled frames back to pool (prevents frame leaks)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end
    
    -- Clean up old non-virtual children (headers, notice frames, empty-state text)
    -- from previous render. VLM handles its own _isVirtualRow frames.
    local recycleBin = ns.UI_RecycleBin
    local oldChildren = {container:GetChildren()}
    for i = 1, #oldChildren do
        ReleaseReputationRowsFromSubtree(oldChildren[i])
    end
    for i = 1, #oldChildren do
        local child = oldChildren[i]
        if not child._isVirtualRow then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end
    local oldRegions = {container:GetRegions()}
    for i = 1, #oldRegions do
        local region = oldRegions[i]
        if region:GetObjectType() == "FontString" then
            region:Hide()
        end
    end
    
    local parent = container
    local yOffset = 0
    local repChainTail = nil
    local COLLAPSE_H_REP = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
    
    -- ===== TITLE CARD (Always shown) =====
    
    
    -- Check if C_Reputation API is available (for modern WoW)
    if not C_Reputation or not C_Reputation.GetNumFactions then
        local errorFrame = CreateNoticeFrame(
            parent,
            (ns.L and ns.L["REP_API_UNAVAILABLE_TITLE"]) or "Reputation API Not Available",
            (ns.L and ns.L["REP_API_UNAVAILABLE_DESC"]) or "The C_Reputation API is not available on this server. This feature requires WoW 12.0.5 (Midnight).",
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
        for ai = 1, #allCharacters do
            local char = allCharacters[ai]
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
        if self.db.profile.reputationExpandOverride == "all_collapsed" then
            return false
        end
        if expanded[key] == nil then
            return default or false
        end
        return expanded[key]
    end
    
    local function PersistExpand(key, isExpanded)
        if self.db.profile.reputationExpandOverride then
            self.db.profile.reputationExpandOverride = nil
        end
        if not self.db.profile.reputationExpanded then
            self.db.profile.reputationExpanded = {}
        end
        self.db.profile.reputationExpanded[key] = isExpanded
    end

    local function ToggleExpand(key, isExpanded)
        PersistExpand(key, isExpanded)
        WarbandNexus:RedrawReputationResultsOnly(true)
    end
    
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
        if not headerName or headerName == "" then
            return "Interface\\Icons\\Achievement_Reputation_01"
        end
        if issecretvalue and issecretvalue(headerName) then
            return "Interface\\Icons\\Achievement_Reputation_01"
        end
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
    
    for ahi = 1, #aggregatedHeaders do
        local headerData = aggregatedHeaders[ahi]
        local awFactions = {}
        local cbFactions = {}
        
        local hdrFacs = headerData.factions
        for fi = 1, #hdrFacs do
            local faction = hdrFacs[fi]
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
    for hi = 1, #accountWideHeaders do
        local h = accountWideHeaders[hi]
        local hf = h.factions
        for fi = 1, #hf do
            local faction = hf[fi]
            if faction and faction.data and not faction.data.parentFactionID then
                totalAccountWide = totalAccountWide + 1
            end
        end
    end
    
    local totalCharacterBased = 0
    for hi = 1, #characterBasedHeaders do
        local h = characterBasedHeaders[hi]
        local hf = h.factions
        for fi = 1, #hf do
            local faction = hf[fi]
            if faction and faction.data and not faction.data.parentFactionID then
                totalCharacterBased = totalCharacterBased + 1
            end
        end
    end
    
    local Factory = ns.UI.Factory
    local betweenRows = GetLayout().betweenRows or 0
    local globalRowIdx = 0

    local function MeasureChildrenHeight(frame)
        if not frame then return 0.1 end
        local top = frame:GetTop()
        if not top then
            return math.max(0.1, frame._wnAccordionFullH or frame:GetHeight() or 0.1)
        end
        local lowest = top
        local children = {frame:GetChildren()}
        for i = 1, #children do
            local child = children[i]
            if child and child:IsShown() then
                local bottom = child:GetBottom()
                if bottom and bottom < lowest then
                    lowest = bottom
                end
            end
        end
        return math.max(0.1, top - lowest)
    end

    local function SyncScrollMetrics()
        local totalH = MeasureChildrenHeight(parent)
        parent:SetHeight(math.max(1, totalH))
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local scrollChild = parent and parent:GetParent()
        if not (mf and scrollChild and mf.scroll and scrollChild == mf.scrollChild) then
            return
        end
        local targetTabBodyH = 8 + totalH
        local targetScrollChildH = math.max(targetTabBodyH + 8, mf.scroll:GetHeight())
        scrollChild:SetHeight(targetScrollChildH)
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(mf.scroll)
        end
        if Factory and Factory.UpdateHorizontalScrollBarVisibility then
            Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
        end
        if mf._virtualScrollUpdate then
            mf._virtualScrollUpdate()
        end
    end

    local function CreateWrap(parentFrame, wrapWidth)
        local wrap = Factory and Factory.CreateContainer and Factory:CreateContainer(parentFrame) or nil
        if not wrap then return nil end
        wrap:SetWidth(math.max(1, wrapWidth))
        wrap:SetHeight(COLLAPSE_H_REP + 0.1)
        if wrap.SetClipsChildren then
            wrap:SetClipsChildren(true)
        end
        return wrap
    end

    local function CreateBody(wrap, bodyWidth)
        local body = Factory and Factory.CreateContainer and Factory:CreateContainer(wrap) or nil
        if not body then return nil end
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, -COLLAPSE_H_REP)
        body:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, -COLLAPSE_H_REP)
        body:SetWidth(math.max(1, bodyWidth))
        body:SetHeight(0.1)
        body:Hide()
        return body
    end

    local function FinalizeBodyHeight(body)
        if not body then return 0.1 end
        if body._wnVirtualContentHeight then
            local fullH = body._wnVirtualContentHeight
            body._wnAccordionFullH = fullH
            return fullH
        end
        local fullH = MeasureChildrenHeight(body)
        body._wnAccordionFullH = fullH
        return fullH
    end

    local function ChainTopFrame(frame, gap)
        if not frame then return end
        ChainSectionFrameBelow(parent, frame, repChainTail, 0, gap, repChainTail and nil or 0)
        repChainTail = frame
    end

    local function BuildFilteredList(headerData, scopeTag)
        local factionList = {}
        local bff = headerData.factions or {}
        for fi = 1, #bff do
            local faction = bff[fi]
            if faction and faction.data and not faction.data.parentFactionID then
                table.insert(factionList, {
                    faction = faction,
                    subfactions = faction.subfactions,
                    originalIndex = faction.factionID
                })
            end
        end

        local rawSearch = reputationSearchText or ""
        local isSecret = rawSearch and issecretvalue and issecretvalue(rawSearch)
        local searchTextKey = isSecret and "" or rawSearch
        local isSearching = not isSecret and rawSearch ~= ""
        local cacheKey = (headerData.name or "") .. "|" .. scopeTag .. "|" .. searchTextKey
        local cached = cachedFilteredResults[cacheKey]
        if cached and cached.searchText == searchTextKey then
            return factionList, cached.filteredList, isSearching
        end

        local filtered = {}
        for ii = 1, #factionList do
            local item = factionList[ii]
            local itemName = SafeLower(item.faction.data.name)
            local parentMatches = not isSearching or itemName:find(reputationSearchText, 1, true)
            local filteredSubs = nil
            local hasMatchingSub = false
            if isSearching and item.subfactions and not parentMatches then
                filteredSubs = {}
                local subs = item.subfactions
                for si = 1, #subs do
                    local sub = subs[si]
                    local subName = SafeLower(sub.data.name)
                    if subName:find(reputationSearchText, 1, true) then
                        table.insert(filteredSubs, sub)
                        hasMatchingSub = true
                    end
                end
            end
            if parentMatches then
                table.insert(filtered, item)
            elseif hasMatchingSub then
                table.insert(filtered, {
                    faction = item.faction,
                    subfactions = filteredSubs,
                    originalIndex = item.originalIndex,
                    _forceExpand = true,
                })
            end
        end

        cachedFilteredResults[cacheKey] = {
            searchText = searchTextKey,
            filteredList = filtered
        }
        return factionList, filtered, isSearching
    end

    local function RenderRowsIntoBody(body, bodyWidth, filteredFactionList)
        body._wnVirtualContentHeight = nil
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local VLM = ns.VirtualListModule
        if not mf or not mf.scroll or not body or not VLM or not VLM.SetupVirtualList then
            return
        end

        local stride = ROW_HEIGHT + betweenRows
        local flatList = {}
        local rowY = 0

        for ri = 1, #filteredFactionList do
            local item = filteredFactionList[ri]
            globalRowIdx = globalRowIdx + 1
            local charInfo = {
                name = item.faction.characterName,
                class = item.faction.characterClass,
                level = item.faction.characterLevel,
                isAccountWide = item.faction.isAccountWide,
                realm = item.faction.characterRealm,
                allCharData = item.faction.allCharData or {}
            }
            local collapseKey = "rep-subfactions-" .. tostring(item.faction.factionID or 0)
            local subExpanded = IsExpanded(collapseKey, true)
            local subsToRender = item.subfactions
            local showSubs = subExpanded or item._forceExpand

            flatList[#flatList + 1] = {
                type = "row",
                yOffset = rowY,
                height = stride,
                xOffset = 0,
                rowWidth = bodyWidth,
                populateEntry = {
                    data = item.faction.data,
                    factionID = item.faction.factionID,
                    rowIdx = globalRowIdx,
                    rowWidth = bodyWidth,
                    isSubfaction = false,
                    subfactions = subsToRender,
                    characterInfo = charInfo,
                    IsExpanded = IsExpanded,
                    ToggleExpand = ToggleExpand,
                },
            }
            rowY = rowY + stride

            if showSubs and subsToRender and #subsToRender > 0 then
                local subIndent = BASE_INDENT + SUBROW_EXTRA_INDENT
                local subRowWidth = math.max(1, bodyWidth - subIndent)
                for si = 1, #subsToRender do
                    local subFaction = subsToRender[si]
                    globalRowIdx = globalRowIdx + 1
                    flatList[#flatList + 1] = {
                        type = "row",
                        yOffset = rowY,
                        height = stride,
                        xOffset = subIndent,
                        rowWidth = subRowWidth,
                        populateEntry = {
                            data = subFaction.data,
                            factionID = subFaction.factionID,
                            rowIdx = globalRowIdx,
                            rowWidth = subRowWidth,
                            isSubfaction = true,
                            subfactions = nil,
                            characterInfo = {
                                name = subFaction.characterName,
                                class = subFaction.characterClass,
                                level = subFaction.characterLevel,
                                isAccountWide = subFaction.isAccountWide,
                                realm = subFaction.characterRealm,
                                allCharData = subFaction.allCharData or {}
                            },
                            IsExpanded = IsExpanded,
                            ToggleExpand = ToggleExpand,
                        },
                    }
                    rowY = rowY + stride
                end
            end
        end

        if #flatList == 0 then
            body:SetHeight(0.1)
            return
        end

        local totalHeight = VLM.SetupVirtualList(mf, body, nil, flatList, {
            createRowFn = function(container, it, _idx)
                local row = AcquireReputationRow(container, it.rowWidth, ROW_HEIGHT)
                local ok, err = pcall(PopulateReputationRow, row, it.populateEntry)
                if not ok and IsDebugModeEnabled and IsDebugModeEnabled() then
                    DebugPrint("|cffff0000[RepUI VLM]|r createRowFn: " .. tostring(err))
                end
                return row
            end,
            populateRowFn = function(row, it, _idx)
                local ok, err = pcall(PopulateReputationRow, row, it.populateEntry)
                if not ok and IsDebugModeEnabled and IsDebugModeEnabled() then
                    DebugPrint("|cffff0000[RepUI VLM]|r populateRowFn: " .. tostring(err))
                end
            end,
            releaseRowFn = ReleaseReputationRow,
        })

        body._wnVirtualContentHeight = totalHeight
        body:SetHeight(math.max(0.1, totalHeight or rowY))
    end

    local function RenderSection(sectionKey, sectionTitle, iconTexture, isAtlas, headers, scopeTag)
        local sectionExpanded = IsExpanded(sectionKey, true)
        local sectionWrap = CreateWrap(parent, width)
        local sectionBody = CreateBody(sectionWrap, width)
        if not (sectionWrap and sectionBody) then return end

        ChainTopFrame(sectionWrap, repChainTail and SECTION_SPACING or nil)
        local sectionHeader, _, sectionIcon = CreateCollapsibleHeader(
            sectionWrap,
            sectionTitle,
            sectionKey,
            sectionExpanded,
            function() end,
            iconTexture,
            isAtlas,
            nil,
            nil,
            {
                animatedContent = function() return sectionBody end,
                persistToggle = function(exp)
                    PersistExpand(sectionKey, exp)
                end,
                accordionOnUpdate = function(drawH)
                    sectionWrap:SetHeight(COLLAPSE_H_REP + math.max(0.1, drawH or 0))
                    SyncScrollMetrics()
                end,
                accordionComplete = function(exp)
                    if not exp then
                        sectionBody:Hide()
                        sectionBody:SetHeight(0.1)
                    end
                    sectionBody._wnAccordionFullH = FinalizeBodyHeight(sectionBody)
                    sectionWrap:SetHeight(COLLAPSE_H_REP + (exp and sectionBody._wnAccordionFullH or 0.1))
                    SyncScrollMetrics()
                end,
            }
        )
        sectionHeader:ClearAllPoints()
        sectionHeader:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
        sectionHeader:SetPoint("TOPRIGHT", sectionWrap, "TOPRIGHT", 0, 0)
        sectionHeader:SetHeight(COLLAPSE_H_REP)
        if sectionIcon and scopeTag == "AW" then
            sectionIcon:SetTexture(nil)
            sectionIcon:SetAtlas("warbands-icon")
            sectionIcon:SetSize(27, 36)
        end

        local headerTail = nil
        local sectionHeaders = headers or {}
        for shi = 1, #sectionHeaders do
            local headerData = sectionHeaders[shi]
            if #headerData.factions > 0 then
                local factionList, filteredFactionList, isSearching = BuildFilteredList(headerData, scopeTag)
                if not isSearching or #filteredFactionList > 0 then
                    local headerKey = (scopeTag == "AW" and "filtered-header-" or "filtered-cb-header-") .. (headerData.name or "")
                    local headerExpanded = isSearching and true or IsExpanded(headerKey, true)
                    local headerWrap = CreateWrap(sectionBody, width - BASE_INDENT)
                    local headerBody = CreateBody(headerWrap, width - BASE_INDENT)
                    if headerWrap and headerBody then
                        ChainSectionFrameBelow(sectionBody, headerWrap, headerTail, BASE_INDENT, headerTail and SECTION_SPACING or nil, headerTail and nil or SECTION_SPACING)
                        headerTail = headerWrap

                        local filteredCount = isSearching and #filteredFactionList or #factionList
                        local header = CreateCollapsibleHeader(
                            headerWrap,
                            (headerData.name or "") .. " (" .. FormatNumber(filteredCount) .. ")",
                            headerKey,
                            headerExpanded,
                            function() end,
                            GetHeaderIcon(headerData.name),
                            nil,
                            nil,
                            nil,
                            {
                                animatedContent = function() return headerBody end,
                                persistToggle = function(exp)
                                    PersistExpand(headerKey, exp)
                                end,
                                accordionOnUpdate = function(drawH)
                                    headerWrap:SetHeight(COLLAPSE_H_REP + math.max(0.1, drawH or 0))
                                    sectionBody:SetHeight(math.max(0.1, FinalizeBodyHeight(sectionBody)))
                                    sectionWrap:SetHeight(COLLAPSE_H_REP + sectionBody:GetHeight())
                                    SyncScrollMetrics()
                                end,
                                accordionComplete = function(exp)
                                    if not exp then
                                        headerBody:Hide()
                                        headerBody:SetHeight(0.1)
                                    end
                                    headerBody._wnAccordionFullH = FinalizeBodyHeight(headerBody)
                                    headerWrap:SetHeight(COLLAPSE_H_REP + (exp and headerBody._wnAccordionFullH or 0.1))
                                    sectionBody:SetHeight(math.max(0.1, FinalizeBodyHeight(sectionBody)))
                                    sectionWrap:SetHeight(COLLAPSE_H_REP + sectionBody:GetHeight())
                                    SyncScrollMetrics()
                                end,
                            }
                        )
                        header:ClearAllPoints()
                        header:SetPoint("TOPLEFT", headerWrap, "TOPLEFT", 0, 0)
                        header:SetPoint("TOPRIGHT", headerWrap, "TOPRIGHT", 0, 0)
                        header:SetHeight(COLLAPSE_H_REP)

                        RenderRowsIntoBody(headerBody, width - BASE_INDENT, filteredFactionList)
                        headerBody._wnAccordionFullH = FinalizeBodyHeight(headerBody)
                        if headerExpanded then
                            headerBody:Show()
                            headerBody:SetHeight(math.max(0.1, headerBody._wnAccordionFullH))
                            headerWrap:SetHeight(COLLAPSE_H_REP + headerBody:GetHeight())
                        else
                            headerBody:Hide()
                            headerBody:SetHeight(0.1)
                            headerWrap:SetHeight(COLLAPSE_H_REP + 0.1)
                        end
                    end
                end
            end
        end

        sectionBody._wnAccordionFullH = FinalizeBodyHeight(sectionBody)
        if sectionExpanded then
            sectionBody:Show()
            sectionBody:SetHeight(math.max(0.1, sectionBody._wnAccordionFullH))
            sectionWrap:SetHeight(COLLAPSE_H_REP + sectionBody:GetHeight())
        else
            sectionBody:Hide()
            sectionBody:SetHeight(0.1)
            sectionWrap:SetHeight(COLLAPSE_H_REP + 0.1)
        end
    end

    RenderSection(
        "filtered-section-accountwide",
        format((ns.L and ns.L["REP_SECTION_ACCOUNT_WIDE"]) or "Account-Wide Reputations (%s)", FormatNumber(totalAccountWide)),
        "dummy",
        nil,
        accountWideHeaders,
        "AW"
    )
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    RenderSection(
        "filtered-section-characterbased",
        format((ns.L and ns.L["REP_SECTION_CHARACTER_BASED"]) or "Character-Based Reputations (%s)", FormatNumber(totalCharacterBased)),
        GetCharacterSpecificIcon and GetCharacterSpecificIcon() or nil,
        true,
        characterBasedHeaders,
        "CB"
    )

    local noticeFrame = CreateNoticeFrame(
        parent,
        (ns.L and ns.L["REP_FOOTER_TITLE"]) or "Reputation Tracking",
        (ns.L and ns.L["REP_FOOTER_DESC"]) or "Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards.",
        "info",
        width - 20,
        60
    )
    ChainTopFrame(noticeFrame, SECTION_SPACING * 2)

    local totalReputations = 0
    local aggHdrs = aggregatedHeaders or {}
    for agi = 1, #aggHdrs do
        local headerGroup = aggHdrs[agi]
        if headerGroup and headerGroup.factions then
            totalReputations = totalReputations + #headerGroup.factions
        end
    end
    SearchStateManager:UpdateResults("reputation", totalReputations)

    SyncScrollMetrics()
    local finalHeight = MeasureChildrenHeight(parent) + (GetLayout().minBottomSpacing or 0)
    parent:SetHeight(math.max(1, finalHeight))
    return finalHeight
end

--============================================================================
-- REPUTATION TAB WRAPPER (Fixes focus issue)
--============================================================================

local function ApplyReputationResultsHeight(mainFrame, scrollChild, resultsContainer, listHeight, animate, fromResultsH, fromScrollChildH)
    if not mainFrame or not scrollChild or not resultsContainer then return end
    local targetResultsH = math.max(listHeight or 1, 1)
    local oldResultsH = fromResultsH or resultsContainer:GetHeight() or targetResultsH
    local CONTENT_BOTTOM_PADDING = 8
    local targetTabBodyH = 8 + (listHeight or 0)
    local targetScrollChildH = math.max(targetTabBodyH + CONTENT_BOTTOM_PADDING, mainFrame.scroll:GetHeight())
    local oldScrollChildH = fromScrollChildH or scrollChild:GetHeight() or targetScrollChildH

    local Factory = ns.UI.Factory
    if animate and Factory and Factory.AnimateAccordion and math.abs(targetResultsH - oldResultsH) > 1 then
        Factory:AnimateAccordion(resultsContainer, oldResultsH, targetResultsH, {
            duration = 0.24,
            fadeAlpha = false,
            clipChildren = true,
            onUpdate = function(curH)
                local t = 0
                if math.abs(targetResultsH - oldResultsH) > 0.001 then
                    t = (curH - oldResultsH) / (targetResultsH - oldResultsH)
                end
                if t < 0 then t = 0 elseif t > 1 then t = 1 end
                local curScrollH = oldScrollChildH + (targetScrollChildH - oldScrollChildH) * t
                scrollChild:SetHeight(math.max(curScrollH, mainFrame.scroll:GetHeight()))
                if Factory.UpdateScrollBarVisibility then
                    Factory:UpdateScrollBarVisibility(mainFrame.scroll)
                end
            end,
            onComplete = function()
                scrollChild:SetHeight(targetScrollChildH)
                if Factory.UpdateScrollBarVisibility then
                    Factory:UpdateScrollBarVisibility(mainFrame.scroll)
                end
                if Factory.UpdateHorizontalScrollBarVisibility then
                    Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
                end
            end,
        })
    else
        resultsContainer:SetHeight(targetResultsH)
        scrollChild:SetHeight(targetScrollChildH)
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(mainFrame.scroll)
        end
        if Factory and Factory.UpdateHorizontalScrollBarVisibility then
            Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
        end
    end
end

function WarbandNexus:RedrawReputationResultsOnly(animateHeight)
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "reputations" then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.resultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = scrollChild:GetWidth() - 20
    if width < 1 then return end

    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(rc)
    end

    local oldResultsH = rc:GetHeight() or 1
    local oldScrollChildH = scrollChild:GetHeight() or mf.scroll:GetHeight()
    local listHeight = self:DrawReputationList(rc, width)
    ApplyReputationResultsHeight(mf, scrollChild, rc, listHeight, animateHeight == true, oldResultsH, oldScrollChildH)

    local sc = mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
end

function WarbandNexus:DrawReputationTab(parent)
    if not parent then
        self:Print("|cffff0000ERROR: No parent container provided to DrawReputationTab|r")
        return
    end
    
    -- Register event listener for reputation updates (only once per parent)
    if not parent.reputationUpdateHandler then
        parent.reputationUpdateHandler = true

        local function IsReputationTabActive()
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            return mf and mf:IsShown() and mf.currentTab == "reputations"
        end
        
        -- Loading started - only refresh if Reputations tab is active (not parent:IsVisible — shared scroll child)
        WarbandNexus.RegisterMessage(ReputationUIEvents, E.REPUTATION_LOADING_STARTED, function()
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            
            if parent and IsReputationTabActive() then
                self:DrawReputationTab(parent)
            end
        end)
        
        -- v2.0.0: Cache cleared - loading UI only when tab active
        WarbandNexus.RegisterMessage(ReputationUIEvents, E.REPUTATION_CACHE_CLEARED, function()
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            if IsReputationTabActive() then
                if parent._loadingPanel then
                    parent._loadingPanel:ShowLoading(
                        (ns.L and ns.L["REP_CLEARING_CACHE"]) or "Clearing cache and reloading...",
                        0, ""
                    )
                end
                
                -- Hide all content frames
                local children = {parent:GetChildren()}
                for _, child in pairs(children) do
                    if child ~= parent.dbVersionBadge 
                       and child ~= parent.emptyStateContainer 
                       and child ~= parent._loadingPanel then
                        child:Hide()
                    end
                end
            end
        end)
        
        -- v2.0.0: Cache ready (hide loading, show content) - full redraw only when tab active
        WarbandNexus.RegisterMessage(ReputationUIEvents, E.REPUTATION_CACHE_READY, function()
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            
            if parent._loadingPanel then
                parent._loadingPanel:HideLoading()
            end
            
            if parent and IsReputationTabActive() then
                self:DrawReputationTab(parent)
            end
        end)
        
        -- Real-time update event (single faction changed)
        WarbandNexus.RegisterMessage(ReputationUIEvents, Constants.EVENTS.REPUTATION_UPDATED, function(event, factionID)
            -- Phase 2.4: Invalidate search cache
            cachedFilteredResults = {}
            cachedSearchText = nil
            
            if parent and IsReputationTabActive() then
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
    
    -- Persistent loading overlay (standard panel from SharedWidgets)
    if not parent._loadingPanel then
        local UI_CreateLoadingStatePanel = ns.UI_CreateLoadingStatePanel
        if UI_CreateLoadingStatePanel then
            parent._loadingPanel = UI_CreateLoadingStatePanel(parent)
        end
    end
    
    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(parent, "reputation")
    
    -- Clear all old frames (including FontStrings)
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
        -- Keep only persistent UI elements (badge, title card, loading panel)
        if child ~= parent.dbVersionBadge 
           and child ~= parent.emptyStateContainer 
           and child ~= parent._loadingPanel then
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
    
    local width = parent:GetWidth() - 20
    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8
    
    -- Check if module is enabled (early check)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.reputations ~= false
    
    -- ===== TITLE CARD (in fixedHeader - non-scrolling) — Characters-tab layout =====
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local repHdrBtnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local repHdrGap = (GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8
    local repRightReserve = repHdrBtnH * 2 + repHdrGap * 2 + (GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20)
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "reputation",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["REP_TITLE"]) or "Reputation Overview") .. "|r",
        subtitleText = (ns.L and ns.L["REP_SUBTITLE"]) or "Track factions and renown across your warband",
        textRightInset = repRightReserve,
    }))
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    -- View Mode: Always use Filtered View (All Characters view removed)
    
    titleCard:Show()

    if moduleEnabled and ns.UI_EnsureTitleCardExpandCollapseButtons then
        local inset = GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20
        ns.UI_EnsureTitleCardExpandCollapseButtons(parent, titleCard, titleCard, "RIGHT", -inset, 0, {
            expandTooltip = (ns.L and ns.L["REP_EXPAND_ALL_TOOLTIP"]) or "Expand all reputation sections and category headers.",
            collapseTooltip = (ns.L and ns.L["REP_COLLAPSE_ALL_TOOLTIP"]) or "Collapse all reputation sections and category headers.",
            onExpandClick = function()
                self.db.profile.reputationExpandOverride = nil
                self.db.profile.reputationExpanded = {}
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "reputation", skipCooldown = true })
            end,
            onCollapseClick = function()
                self.db.profile.reputationExpandOverride = "all_collapsed"
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "reputation", skipCooldown = true })
            end,
        })
    elseif parent._wnExpandCollapseCollapseBtn then
        parent._wnExpandCollapseCollapseBtn:Hide()
        parent._wnExpandCollapseExpandBtn:Hide()
    end
    
    headerYOffset = headerYOffset + GetLayout().afterHeader
    
    -- If module is disabled, show disabled state card in scroll area
    if not moduleEnabled then
        if parent._wnExpandCollapseCollapseBtn then
            parent._wnExpandCollapseCollapseBtn:Hide()
            parent._wnExpandCollapseExpandBtn:Hide()
        end
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["REP_DISABLED_TITLE"]) or "Reputation Tracking")
        return 8 + cardHeight
    end
    
    -- ===== LOADING STATE =====
    if ns.ReputationLoadingState and ns.ReputationLoadingState.isLoading then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(parent, 8, ns.ReputationLoadingState, (ns.L and ns.L["REP_LOADING_TITLE"]) or "Loading Reputation Data")
            return newYOffset
        end
    end
    
    -- ===== SEARCH BOX (in fixedHeader - non-scrolling) =====
    local CreateSearchBox = ns.UI_CreateSearchBox
    local reputationSearchText = SearchStateManager:GetQuery("reputation")
    
    local searchBox = CreateSearchBox(headerParent, width, (ns.L and ns.L["REP_SEARCH"]) or "Search reputations...", function(text)
        SearchStateManager:SetSearchQuery("reputation", text)
        if parent.resultsContainer then
            self:RedrawReputationResultsOnly(false)
        end
    end, 0.4, reputationSearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
    headerYOffset = headerYOffset + searchH + GetLayout().afterElement

    -- Set fixedHeader height so scroll area starts below it
    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    
    -- Results Container (in scroll area)
    if not parent.resultsContainer then
        local container = ns.UI.Factory:CreateContainer(parent)
        parent.resultsContainer = container
    end
    
    local container = parent.resultsContainer
    container:SetParent(parent)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -8)
    container:SetWidth(width)
    container:SetHeight(1)
    container:Show()
    
    local listHeight = self:DrawReputationList(container, width)
    ApplyReputationResultsHeight(WarbandNexus.UI and WarbandNexus.UI.mainFrame, parent, container, listHeight, false)
    
    return 8 + listHeight
end
