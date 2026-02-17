--[[
    Warband Nexus - PvE Progress Tab
    Display Great Vault, Mythic+ keystones, and Raid lockouts for all characters
    
    DATA FLOW ARCHITECTURE (CACHE-FIRST):
    ==========================================
    1. PvECacheService: Event-driven data collection (WEEKLY_REWARDS_UPDATE, MYTHIC_PLUS_*, etc.)
    2. Database: Persistent storage (db.global.pveCache)
    3. UI (this file): Reads from cache via GetPvEData(charKey)
    
    ACCEPTABLE API CALLS (UI-only):
    - C_DateAndTime.GetSecondsUntilWeeklyReset() - Fallback for weekly reset timer
    - C_ChallengeMode.GetMapUIInfo() - Dungeon name/icon (not cached, static data)
    - C_CurrencyInfo.GetCurrencyInfo() - Currency details for TWW currencies
    
    DEPRECATED API CALLS (Moved to PvECacheService):
    - C_MythicPlus.GetOwnedKeystoneLevel() → Use pveData.keystone.level
    - C_MythicPlus.GetOwnedKeystoneChallengeMapID() → Use pveData.keystone.mapID
    - C_MythicPlus.GetCurrentAffixes() → Use allPveData.currentAffixes
    - C_WeeklyRewards.GetActivities() → Use pveData.vaultActivities
    
    Event Registration: WN_PVE_UPDATED (auto-refresh UI when cache updates)
]]

local ADDON_NAME, ns = ...

-- Unique AceEvent handler identity for PvEUI
local PvEUIEvents = {}
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateIcon = ns.UI_CreateIcon
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local ApplyVisuals = ns.UI_ApplyVisuals  -- For border re-application
local FormatNumber = ns.UI_FormatNumber
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

-- Expand/Collapse State Management
local expandedStates = {}

local function IsExpanded(key, defaultState)
    -- Check for Expand All override
    if WarbandNexus and WarbandNexus.pveExpandAllActive then
        return true
    end
    if expandedStates[key] == nil then
        expandedStates[key] = defaultState
    end
    return expandedStates[key]
end

local function ToggleExpand(key, newState)
    expandedStates[key] = newState
    WarbandNexus:RefreshUI()
end

--============================================================================
-- EVENT-DRIVEN UI REFRESH
--============================================================================

---Register event listener for PvE updates
---@param parent Frame Parent frame for event registration
local function RegisterPvEEvents(parent)
    -- Register only once per parent
    if parent.pveUpdateHandler then
        return
    end
    parent.pveUpdateHandler = true
    
    -- WN_PVE_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- pve tab refresh via PopulateContent → DrawPvEProgress. Having both caused double rebuild.
    
    -- Event listener cleanup (silent)
end

--============================================================================
-- GREAT VAULT HELPER FUNCTIONS
--============================================================================

--[[
    Determine if a vault activity slot is at maximum completion level
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name ("Raid", "M+", "World", "PvP")
    @return boolean - True if at maximum level, false otherwise
]]
local function IsVaultSlotAtMax(activity, typeName)
    if not activity or not activity.level then
        return false
    end
    
    local level = activity.level
    
    -- Define max thresholds per activity type
    if typeName == "Raid" then
        -- For raids, level is difficulty ID (14=Normal, 15=Heroic, 16=Mythic)
        return level >= 16 -- Mythic is max
    elseif typeName == "M+" then
        -- For M+: 0=Heroic, 1=Mythic, 2+=Keystone level
        -- Max is keystone level 10 or higher
        return level >= 10
    elseif typeName == "World" then
        -- For World/Delves, Tier 8 is max
        return level >= 8
    elseif typeName == "PvP" then
        -- PvP has no tier progression
        return true
    end
    
    return false
end

--[[
    Get reward item level from activity data or calculate fallback
    @param activity table - Activity data from Great Vault
    @return number|nil - Item level or nil if unavailable
]]
local function GetRewardItemLevel(activity)
    if not activity then
        return nil
    end
    
    -- Priority: Use rewardItemLevel field (extracted from C_WeeklyRewards.GetExampleRewardItemHyperlinks)
    if activity.rewardItemLevel and activity.rewardItemLevel > 0 then
        return activity.rewardItemLevel
    end
    
    return nil
end

--[[
    Get next tier/difficulty name for upgrade display
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name
    @return string|nil - Next tier/difficulty name (e.g., "Tier 2", "+6", "Mythic")
]]
local function GetNextTierName(activity, typeName)
    if not activity or not activity.level then
        return nil
    end
    
    local currentLevel = activity.level
    
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local normalLabel = (ns.L and ns.L["DIFFICULTY_NORMAL"]) or "Normal"
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    
    -- World/Delves tier progression (Tier 1-8)
    if typeName == "World" then
        if currentLevel >= 8 then
            return nil -- Already at max (Tier 8)
        end
        return string.format(tierFmt, currentLevel + 1)
    end
    
    -- Raid difficulty progression
    if typeName == "Raid" then
        -- Level: 14=Normal, 15=Heroic, 16=Mythic, <14=LFR
        if currentLevel >= 16 then
            return nil -- Already at Mythic (max)
        elseif currentLevel >= 15 then
            return mythicLabel
        elseif currentLevel >= 14 then
            return heroicLabel
        else
            return normalLabel
        end
    end
    
    -- M+ keystone progression
    if typeName == "M+" or typeName == "Dungeon" then
        if currentLevel >= 10 then
            return nil -- Max is +10
        end
        
        local nextLevel = currentLevel + 1
        if nextLevel == 0 then
            return heroicLabel
        elseif nextLevel == 1 then
            return mythicLabel
        else
            return string.format("+%d", nextLevel)
        end
    end
    
    return nil
end

--[[
    Get maximum tier/difficulty name
    @param typeName string - Activity type name
    @return string|nil - Max tier/difficulty name
]]
local function GetMaxTierName(typeName)
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    if typeName == "World" then
        return string.format(tierFmt, 8)
    elseif typeName == "Raid" then
        return (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    elseif typeName == "M+" or typeName == "Dungeon" then
        return "+10"
    elseif typeName == "PvP" then
        return nil -- PvP has no progression
    end
    return nil
end

--[[
    Get display text for vault activity completion
    @param activity table - Activity data
    @param typeName string - Activity type name
    @return string - Display text for the activity (e.g., "Heroic", "+7", "Tier 1")
]]
local function GetVaultActivityDisplayText(activity, typeName)
    local unknownLabel = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local normalLabel = (ns.L and ns.L["DIFFICULTY_NORMAL"]) or "Normal"
    local lfrLabel = (ns.L and ns.L["DIFFICULTY_LFR"]) or "LFR"
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    local pvpLabel = (ns.L and ns.L["PVP_TYPE"]) or "PvP"
    
    if not activity then
        return unknownLabel
    end
    
    if typeName == "Raid" then
        local difficulty = unknownLabel
        if activity.level then
            -- Raid level corresponds to difficulty ID
            if activity.level >= 16 then
                difficulty = mythicLabel
            elseif activity.level >= 15 then
                difficulty = heroicLabel
            elseif activity.level >= 14 then
                difficulty = normalLabel
            else
                difficulty = lfrLabel
            end
        end
        return difficulty
    elseif typeName == "M+" then
        local level = activity.level or 0
        -- Level 0 = Heroic dungeon, Level 1 = Mythic dungeon, Level 2+ = Keystone
        if level == 0 then
            return heroicLabel
        elseif level == 1 then
            return mythicLabel
        else
            return string.format("+%d", level)
        end
    elseif typeName == "World" then
        local tier = activity.level or 1
        return string.format(tierFmt, tier)
    elseif typeName == "PvP" then
        return pvpLabel
    end
    
    return typeName
end

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================

function WarbandNexus:DrawPvEProgress(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.pveProgress [LEGACY]"
        if self.db.global.pveCache and self.db.global.pveCache.version then
            local cacheVersion = self.db.global.pveCache.version or "unknown"
            dataSource = "PvECache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Register event listener (only once)
    RegisterPvEEvents(parent)
    
    -- Hide empty state card (will be shown again if needed)
    HideEmptyStateCard(parent, "pve")
    
    -- ===== AUTO-REFRESH CHECK (FULLY AUTOMATIC) =====
    local charKey = ns.Utilities:GetCharacterKey()
    local pveData = self:GetPvEData(charKey)  -- Use PvECacheService API
    
    -- AUTOMATIC: Check if data needs refresh (no user action required)
    local needsRefresh = false
    if not pveData or not pveData.keystone then
        needsRefresh = true
    end
    
    -- AUTOMATIC: Trigger refresh if needed and not already loading
    if needsRefresh and not ns.PvELoadingState.isLoading then
        -- Check if enough time passed since last attempt (avoid spam)
        local timeSinceLastAttempt = time() - (ns.PvELoadingState.lastAttempt or 0)
        if timeSinceLastAttempt > 10 then
            ns.PvELoadingState.lastAttempt = time()
            -- Use PvECacheService for update
            if self.UpdatePvEData then
                self:UpdatePvEData()
            end
        end
    end
    
    -- ===== HEADER CARD (Always shown) =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Header icon with ring border (standardized)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("pve"))
    
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    -- Use factory pattern positioning for standardized header layout
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["PVE_TITLE"]) or "PvE Progress") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["PVE_SUBTITLE"]) or "Great Vault, Raid Lockouts & Mythic+ across your Warband"
    
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
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    -- Weekly reset timer (standardized widget)
    local CreateResetTimer = ns.UI_CreateResetTimer
    local resetTimer = CreateResetTimer(
        titleCard,
        "RIGHT",
        -20,  -- 20px from right edge
        0,
        function()
            -- Use centralized GetWeeklyResetTime from PlansManager
            if WarbandNexus.GetWeeklyResetTime then
                local resetTimestamp = WarbandNexus:GetWeeklyResetTime()
                return resetTimestamp - GetServerTime()
            end
            
            -- Fallback: Use Blizzard API
            if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            
            return 0
        end
    )
    
    titleCard:Show()
    
    yOffset = yOffset + GetLayout().afterHeader  -- Standard spacing after title card
    
    -- ===== LOADING STATE INDICATOR (AUTOMATIC - NO USER ACTION) =====
    if ns.PvELoadingState and ns.PvELoadingState.isLoading then
        local loadingCard = CreateCard(parent, 90)
        loadingCard:SetPoint("TOPLEFT", 10, -yOffset)
        loadingCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        -- Animated spinner (using built-in WoW atlas)
        local spinnerFrame = CreateIcon(loadingCard, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
        spinnerFrame:SetPoint("LEFT", 20, 0)
        spinnerFrame:Show()
        local spinner = spinnerFrame.texture
        
        -- Animate rotation
        local rotation = 0
        loadingCard:SetScript("OnUpdate", function(self, elapsed)
            rotation = rotation + (elapsed * 270) -- 270 degrees per second (smooth rotation)
            spinner:SetRotation(math.rad(rotation))
        end)
        
        -- Loading text with stage info
        local loadingText = FontManager:CreateFontString(loadingCard, "title", "OVERLAY")
        loadingText:SetPoint("LEFT", spinner, "RIGHT", 15, 10)
        local loadingPveLabel = (ns.L and ns.L["LOADING_PVE"]) or "Loading PvE Data..."
        loadingText:SetText("|cff00ccff" .. loadingPveLabel .. "|r")
        
        -- Progress indicator with current stage
        local progressText = FontManager:CreateFontString(loadingCard, "body", "OVERLAY")
        progressText:SetPoint("LEFT", spinner, "RIGHT", 15, -8)
        
        local attempt = ns.PvELoadingState.attempts or 1
        local currentStage = ns.PvELoadingState.currentStage or ((ns.L and ns.L["PREPARING"]) or "Preparing")
        local progress = ns.PvELoadingState.loadingProgress or 0
        
        progressText:SetText(string.format("|cff888888%s - %d%%|r", currentStage, progress))
        
        -- Hint text
        local hintText = FontManager:CreateFontString(loadingCard, "small", "OVERLAY")
        hintText:SetPoint("LEFT", spinner, "RIGHT", 15, -25)
        hintText:SetTextColor(0.6, 0.6, 0.6)
        hintText:SetText((ns.L and ns.L["PVE_APIS_LOADING"]) or "Please wait, WoW APIs are initializing...")
        
        loadingCard:Show()
        
        yOffset = yOffset + 100
        
        -- Don't show character data while loading - return early
        return yOffset + 50
    end
    
    -- ===== ERROR STATE (IF DATA COLLECTION FAILED) =====
    if ns.PvELoadingState and ns.PvELoadingState.error and not ns.PvELoadingState.isLoading then
        local errorCard = CreateCard(parent, 60)
        errorCard:SetPoint("TOPLEFT", 10, -yOffset)
        errorCard:SetPoint("TOPRIGHT", -10, -yOffset)
        
        -- Warning icon
        local warningIconFrame = CreateIcon(errorCard, "services-icon-warning", 24, true, nil, true)
        warningIconFrame:SetPoint("LEFT", 20, 0)
        warningIconFrame:Show()
        
        -- Error message
        local errorText = FontManager:CreateFontString(errorCard, "body", "OVERLAY")
        errorText:SetPoint("LEFT", warningIcon, "RIGHT", 10, 0)
        errorText:SetTextColor(1, 0.7, 0)
        errorText:SetText("|cffffcc00" .. ns.PvELoadingState.error .. "|r")
        
        errorCard:Show()
        
        yOffset = yOffset + 70
    end
    
    -- Check if module is disabled - show beautiful disabled state card
    if not ns.Utilities:IsModuleEnabled("pve") then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (ns.L and ns.L["PVE_TITLE"]) or "PvE Progress")
        return yOffset + cardHeight
    end
    
    -- Get all characters (filter tracked only for PvE display)
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    for _, char in ipairs(allCharacters) do
        if char.isTracked ~= false then  -- Default to tracked if not set
            table.insert(characters, char)
        end
    end
    
    -- Get current player key
    local currentPlayerKey = ns.Utilities:GetCharacterKey()
    
    -- Load sorting preferences from profile (persistent across sessions)
    if not parent.sortPrefsLoaded then
        parent.sortKey = self.db.profile.pveSort.key
        parent.sortAscending = self.db.profile.pveSort.ascending
        parent.sortPrefsLoaded = true
    end
    
    -- ===== SORT CHARACTERS WITH FAVORITES ALWAYS ON TOP =====
    -- Use the same sorting logic as Characters tab
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        -- CRITICAL: Use GetCharacterKey() normalization to match PvECacheService DB keys (same as CurrencyUI/ReputationUI)
        local charKey = (ns.Utilities and ns.Utilities:GetCharacterKey(char.name, char.realm)) or char._key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
        
        -- Separate current character
        if charKey == currentPlayerKey then
            currentChar = char
        elseif ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(self, charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Sort function (with custom order support, same as Characters tab)
    local function sortCharacters(list, orderKey)
        local customOrder = self.db.profile.characterOrder and self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for _, char in ipairs(list) do
                local key = (ns.Utilities and ns.Utilities:GetCharacterKey(char.name, char.realm)) or char._key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
                charMap[key] = char
            end
            
            -- Add characters in custom order
            for _, charKey in ipairs(customOrder) do
                if charMap[charKey] then
                    table.insert(ordered, charMap[charKey])
                    charMap[charKey] = nil  -- Remove to track remaining
                end
            end
            
            -- Add any new characters not in custom order (at the end, sorted)
            local remaining = {}
            for _, char in pairs(charMap) do
                table.insert(remaining, char)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            for _, char in ipairs(remaining) do
                table.insert(ordered, char)
            end
            
            return ordered
        else
            -- Default sort: level desc → name asc
            table.sort(list, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            return list
        end
    end
    
    -- Sort both groups with custom order
    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")
    
    -- Merge: Current first, then favorites, then regular
    local sortedCharacters = {}
    if currentChar then
        table.insert(sortedCharacters, currentChar)
    end
    for _, char in ipairs(favorites) do
        table.insert(sortedCharacters, char)
    end
    for _, char in ipairs(regular) do
        table.insert(sortedCharacters, char)
    end
    characters = sortedCharacters
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local _, height = CreateEmptyStateCard(parent, "pve", yOffset)
        return yOffset + height
    end
    
    -- ===== CHARACTER COLLAPSIBLE HEADERS (Favorites first, then regular) =====
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        -- CRITICAL: Use GetCharacterKey() normalization to match PvECacheService DB keys
        local charKey = (ns.Utilities and ns.Utilities:GetCharacterKey(char.name, char.realm)) or char._key or ((char.name or "Unknown") .. "-" .. (char.realm or "Unknown"))
        local isFavorite = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(self, charKey)
        
        -- Get PvE data from PvECacheService
        local pveData = self:GetPvEData(charKey) or {}
        
        -- Build legacy-compatible structure for rendering (backward compatibility)
        local pve = {
            keystone = pveData.keystone,
            vaultActivities = pveData.vaultActivities,
            hasUnclaimedRewards = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards,
            raidLockouts = pveData.raidLockouts,
            worldBosses = pveData.worldBosses,
            mythicPlus = pveData.mythicPlus,  -- Now includes overallScore and dungeons
        }
        
        -- Only the current (online) character starts expanded; all others collapsed.
        local charExpandKey = "pve-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
        local hasVaultReward = pve.hasUnclaimedRewards or false
        
        local charExpanded = IsExpanded(charExpandKey, isCurrentChar)
        
        -- Create collapsible header
        local charHeader, charBtn = CreateCollapsibleHeader(
            parent,
            "", -- Empty text, we'll add it manually
            charExpandKey,
            charExpanded,
            function(isExpanded) ToggleExpand(charExpandKey, isExpanded) end
        )
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
        
        yOffset = yOffset + GetLayout().headerSpacing  -- Standardized header spacing
        
        -- Favorite icon (view-only, left side, next to collapse button)
        -- Match Characters/Professions tabs: 33px column, 65% visual icon (~21px)
        local StyleFavoriteIcon = ns.UI_StyleFavoriteIcon
        local favColSize = 33
        local favIconSize = favColSize * 0.65
        
        local favFrame = CreateFrame("Frame", nil, charHeader)
        favFrame:SetSize(favColSize, favColSize)
        favFrame:SetPoint("LEFT", charBtn, "RIGHT", 4, 0)
        
        local favIcon = favFrame:CreateTexture(nil, "ARTWORK")
        favIcon:SetSize(favIconSize, favIconSize)
        favIcon:SetPoint("CENTER", 0, 0)
        StyleFavoriteIcon(favIcon, isFavorite)
        favFrame:Show()
        
        -- Character name text (after favorite icon, class colored)
        -- Use fixed-width columns for perfect alignment across all characters
        -- Column widths optimized for visual balance and equal spacing
        local xOffset = 0
        local nameWidth = 230     -- Character name + " - " + realm (e.g., "Superluminal - Twisting Nether")
        local spacerWidth = 30    -- Spacing around bullets (equal spacing)
        local levelWidth = 60     -- "Lv XX" 
        local ilvlWidth = 80      -- "iLvl XXX"
        
        -- Column 1: Character Name - Realm (single line, fixed width, left aligned)
        local charNameText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charNameText:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
        charNameText:SetWidth(nameWidth)
        charNameText:SetJustifyH("LEFT")
        local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ""
        charNameText:SetText(string.format("|cff%02x%02x%02x%s  -  %s|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name,
            displayRealm))
        xOffset = xOffset + nameWidth
        
        -- Column 2: Bullet separator (centered in spacer)
        local bullet1 = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        bullet1:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
        bullet1:SetWidth(spacerWidth)
        bullet1:SetJustifyH("CENTER")
        bullet1:SetText("|cff666666•|r")
        xOffset = xOffset + spacerWidth
        
        -- Column 3: Level (fixed width, CENTER aligned for visual balance)
        local levelText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        levelText:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
        levelText:SetWidth(levelWidth)
        levelText:SetJustifyH("CENTER")  -- CENTER for equal spacing on both sides
        local levelFormat = (ns.L and ns.L["LV_FORMAT"]) or "Lv %d"
        local levelString = string.format("|cff%02x%02x%02x" .. levelFormat .. "|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.level or 1)
        levelText:SetText(levelString)
        xOffset = xOffset + levelWidth
        
        -- Column 4: Bullet separator (only if iLvl exists, centered in spacer)
        if char.itemLevel and char.itemLevel > 0 then
            local bullet2 = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
            bullet2:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
            bullet2:SetWidth(spacerWidth)
            bullet2:SetJustifyH("CENTER")
            bullet2:SetText("|cff666666•|r")
            xOffset = xOffset + spacerWidth
            
            -- Column 5: iLvl (fixed width, left aligned)
            local ilvlText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
            ilvlText:SetPoint("LEFT", favFrame, "RIGHT", 6 + xOffset, 0)
            ilvlText:SetWidth(ilvlWidth)
            ilvlText:SetJustifyH("LEFT")
            local ilvlFormat = (ns.L and ns.L["ILVL_FORMAT"]) or "iLvl %d"
            ilvlText:SetText(string.format("|cffffd700" .. ilvlFormat .. "|r", char.itemLevel))
        end
        
        -- Vault badge (right side of header)
        if hasVaultReward then
            -- Measure text to size container dynamically
            local vaultLabel = (ns.L and ns.L["GREAT_VAULT"]) or "Great Vault"
            local tempFs = FontManager:CreateFontString(charHeader, "small", "OVERLAY")
            tempFs:SetText(vaultLabel)
            local textW = tempFs:GetStringWidth() or 80
            tempFs:Hide()
            local containerW = 16 + 4 + textW + 4 + 14 + 4  -- icon + gap + text + gap + checkmark + pad
            
            local vaultContainer = ns.UI.Factory:CreateContainer(charHeader, math.max(containerW, 110), 20)
            vaultContainer:SetPoint("RIGHT", -10, 0)
            
            local vaultIconFrame = CreateIcon(vaultContainer, "Interface\\Icons\\achievement_guildperk_bountifulbags", 16, false, nil, true)
            vaultIconFrame:SetPoint("LEFT", 0, 0)
            vaultIconFrame:Show()
            
            local vaultText = FontManager:CreateFontString(vaultContainer, "small", "OVERLAY")
            vaultText:SetPoint("LEFT", vaultIconFrame, "RIGHT", 4, 0)
            vaultText:SetText(vaultLabel)
            vaultText:SetTextColor(0.9, 0.9, 0.9)
            
            local checkmark = vaultContainer:CreateTexture(nil, "OVERLAY")
            checkmark:SetSize(14, 14)
            checkmark:SetPoint("LEFT", vaultText, "RIGHT", 4, 0)
            checkmark:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
        end
        
        -- 3 Cards (only when expanded)
        if charExpanded then
            local cardContainer = ns.UI.Factory:CreateContainer(parent)
            cardContainer:SetPoint("TOPLEFT", 10, -yOffset)
            cardContainer:SetPoint("TOPRIGHT", -10, -yOffset)
            
            -- Calculate responsive card widths (pixel-snapped)
            local PixelSnap = ns.PixelSnap or function(v) return v end
            local totalWidth = PixelSnap(parent:GetWidth() - 20)
            local card1Width = PixelSnap(totalWidth * 0.30)
            local card2Width = PixelSnap(totalWidth * 0.35)
            local card3Width = PixelSnap(totalWidth - card1Width - card2Width)  -- Use remaining space
            local cardSpacing = 5
            
            -- Card height will be calculated from vault card grid (with fallback)
            local cardHeight = 200  -- Default fallback height
            
            -- === CARD 1: GREAT VAULT (30%) ===
            local baseCardHeight = 200
            local vaultCard = CreateCard(cardContainer, baseCardHeight)
            vaultCard:SetPoint("TOPLEFT", 0, 0)
            local baseCardWidth = card1Width - cardSpacing
            
            -- Helper function to get WoW icon textures for vault activity types
            local function GetVaultTypeIcon(typeName)
                local icons = {
                    ["Raid"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
                    ["M+"] = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
                    ["World"] = "Interface\\Icons\\INV_Misc_Map_01"
                }
                return icons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
            
            local vaultY = 0  -- No top padding - start from 0
        
        -- Get vault activities (from PvECacheService structure)
        local vaultActivitiesData = pve.vaultActivities
        
        -- CRITICAL: Create a NEW table on each render (don't reuse old data)
        local vaultActivities = {}
        
        -- Flatten vault activities (raids, mythicPlus, pvp, world) into single array
        if vaultActivitiesData then
            if vaultActivitiesData.raids then
                for _, activity in ipairs(vaultActivitiesData.raids) do
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.mythicPlus then
                for _, activity in ipairs(vaultActivitiesData.mythicPlus) do
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.pvp then
                for _, activity in ipairs(vaultActivitiesData.pvp) do
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.world then
                for _, activity in ipairs(vaultActivitiesData.world) do
                    table.insert(vaultActivities, activity)
                end
            end
        end
        
        if #vaultActivities > 0 then
            local vaultByType = {}
            for _, activity in ipairs(vaultActivities) do
                local typeName = ns.L["UNKNOWN"] or "Unknown"
                local typeNum = activity.type
                
                if Enum and Enum.WeeklyRewardChestThresholdType then
                        if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = ns.L["VAULT_RAID"] or "Raid"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = ns.L["MYTHIC_PLUS_LABEL"] or "M+"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = ns.L["PVP_TYPE"] or "PvP"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = ns.L["VAULT_WORLD"] or "World"
                    end
                else
                    -- Fallback numeric values based on API:
                    -- 1 = Activities (M+), 2 = RankedPvP, 3 = Raid, 6 = World
                    if typeNum == 3 then typeName = ns.L["VAULT_RAID"] or "Raid"
                    elseif typeNum == 1 then typeName = ns.L["MYTHIC_PLUS_LABEL"] or "M+"
                    elseif typeNum == 2 then typeName = ns.L["PVP_TYPE"] or "PvP"
                    elseif typeNum == 6 then typeName = ns.L["VAULT_WORLD"] or "World"
                    end
                end
                
                if not vaultByType[typeName] then vaultByType[typeName] = {} end
                table.insert(vaultByType[typeName], activity)
            end
            
            -- 4x3 GRID LAYOUT - PERFECT EQUAL DIVISIONS (WITH BORDER PADDING)
            
            -- Border padding (2px on all sides for 1px border)
            local borderPadding = 2
            
            -- Adjust dimensions to ensure perfect integer division
            local numRows = 3
            local numCols = 4
            
            -- Calculate perfect cell sizes (accounting for border)
            local availableWidth = baseCardWidth - (borderPadding * 2)
            local availableHeight = baseCardHeight - (borderPadding * 2)
            
            local cellWidth = math.floor(availableWidth / numCols)
            local cellHeight = math.floor(availableHeight / numRows)
            
            -- Recalculate exact card dimensions (add border padding back)
            cardWidth = (cellWidth * numCols) + (borderPadding * 2)
            cardHeight = (cellHeight * numRows) + (borderPadding * 2)
            
            -- CRITICAL: Set card dimensions for proper border
            vaultCard:SetHeight(cardHeight)
            vaultCard:SetWidth(cardWidth)
            
            -- Re-apply border after dimension change
            if ApplyVisuals then
                local accentColor = COLORS.accent
                ApplyVisuals(vaultCard, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
            end
            
            -- Default thresholds for each activity type (when no data exists)
            local defaultThresholds = {
                ["Raid"] = {2, 4, 6},
                ["Dungeon"] = {1, 4, 8},
                ["World"] = {3, 3, 3},
                ["PvP"] = {3, 3, 3}
            }
            
            -- Table Rows (3 ROWS - perfect grid alignment)
            local sortedTypes = {"Raid", "Dungeon", "World"}
            
            for rowIndex, typeName in ipairs(sortedTypes) do
                -- Map display name to actual data key
                local dataKey = typeName
                if typeName == "Dungeon" then
                    dataKey = "M+"
                end
                local activities = vaultByType[dataKey]
                
                -- Calculate Y position (row 0, 1, 2) with border padding
                local rowY = borderPadding + ((rowIndex - 1) * cellHeight)
                
                -- Create row frame container (using Factory pattern)
                local rowFrame = ns.UI.Factory:CreateContainer(vaultCard)
                rowFrame:SetPoint("TOPLEFT", borderPadding, -rowY)
                rowFrame:SetSize(cardWidth - (borderPadding * 2), cellHeight)
                
                -- Row background: solid black (consistent with Overall/Affix cards)
                if not rowFrame.bg then
                    rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
                    rowFrame.bg:SetAllPoints()
                    rowFrame.bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)  -- Solid dark background
                end
                
                -- Type label (COLUMN 0 - Cell 0, left-aligned, vertically centered)
                local label = FontManager:CreateFontString(rowFrame, "title", "OVERLAY")
                label:SetPoint("LEFT", 5, 0)  -- 5px padding for readability
                label:SetWidth(cellWidth - 10)
                label:SetJustifyH("LEFT")
                -- Map typeName to locale key
                local typeDisplayName = typeName
                if typeName == "Raid" then
                    typeDisplayName = (ns.L and ns.L["VAULT_RAID"]) or "Raid"
                elseif typeName == "Dungeon" then
                    typeDisplayName = (ns.L and ns.L["VAULT_DUNGEON"]) or "Dungeon"
                elseif typeName == "World" then
                    typeDisplayName = (ns.L and ns.L["VAULT_WORLD"]) or "World"
                end
                label:SetText(string.format("|cffffffff%s|r", typeDisplayName))
                
                -- Create individual slot frames in COLUMNS 1, 2, 3
                local thresholds = defaultThresholds[typeName] or {3, 3, 3}
                
                for slotIndex = 1, 3 do
                    -- Create slot container frame (using Factory pattern)
                    local slotFrame = ns.UI.Factory:CreateContainer(rowFrame)
                    local xOffset = slotIndex * cellWidth  -- Column 1, 2, 3
                    slotFrame:SetSize(cellWidth, cellHeight)
                    slotFrame:SetPoint("LEFT", rowFrame, "LEFT", xOffset, 0)
                    
                    -- Get activity data for this slot
                    local activity = activities and activities[slotIndex]
                    
                    local threshold = (activity and activity.threshold) or thresholds[slotIndex] or 0
                    local progress = activity and activity.progress or 0
                    local isComplete = (threshold > 0 and progress >= threshold)
                    
                    if activity and isComplete then
                        -- COMPLETED SLOT: Show 2 centered lines (no green tick)
                        -- Line 1: Tier/Difficulty/Keystone Level
                        local displayText = GetVaultActivityDisplayText(activity, dataKey)
                        local tierText = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                        tierText:SetPoint("CENTER", slotFrame, "CENTER", 0, 8)
                        tierText:SetWidth(cellWidth - 10)  -- Fit within cell
                        tierText:SetJustifyH("CENTER")
                        tierText:SetWordWrap(false)
                        tierText:SetText(string.format("|cff00ff00%s|r", displayText))
                        
                        -- Line 2: Reward iLvL (if available)
                        local rewardIlvl = GetRewardItemLevel(activity)
                        local ilvlText = nil
                        if rewardIlvl and rewardIlvl > 0 then
                            ilvlText = FontManager:CreateFontString(slotFrame, "body", "OVERLAY")
                            ilvlText:SetPoint("TOP", tierText, "BOTTOM", 0, -2)
                            ilvlText:SetWidth(cellWidth - 10)  -- Fit within cell
                            ilvlText:SetJustifyH("CENTER")
                            ilvlText:SetWordWrap(false)
                            local ilvlFormat = (ns.L and ns.L["ILVL_FORMAT"]) or "iLvl %d"
                            ilvlText:SetText(string.format("|cffffd700" .. ilvlFormat .. "|r", rewardIlvl))
                        end
                        
                        -- Check if not at max level (moved OUTSIDE rewardIlvl check)
                        local isAtMax = IsVaultSlotAtMax(activity, dataKey)
                        
                        -- Show upgrade arrow for ALL non-max completed slots
                        if not isAtMax then
                            local arrowTexture = slotFrame:CreateTexture(nil, "OVERLAY")
                            arrowTexture:SetSize(16, 16)  -- Larger arrow (12 -> 16)
                            -- Position arrow at RIGHT EDGE of cell, vertically centered + 2px down
                            arrowTexture:SetPoint("RIGHT", slotFrame, "RIGHT", -5, 2)  -- +2px down
                            arrowTexture:SetAtlas("loottoast-arrow-green")
                        end
                        
                        -- Add tooltip for completed slots
                        if ShowTooltip then
                            slotFrame:EnableMouse(true)
                            slotFrame:SetScript("OnEnter", function(self)
                                local lines = {}
                                
                                -- Next Tier Upgrade Reward (API data + tier name)
                                if activity.nextLevelIlvl and activity.nextLevelIlvl > 0 then
                                    local nextTierName = GetNextTierName(activity, typeName)
                                    if nextTierName then
                                        local nextTierFormat = (ns.L and ns.L["VAULT_NEXT_TIER_FORMAT"]) or "Next Tier: %d iLvL on complete %s"
                                        table.insert(lines, {
                                            text = string.format("|cffffd700" .. nextTierFormat .. "|r", activity.nextLevelIlvl, nextTierName),
                                            color = {0.8, 0.8, 0.8}
                                        })
                                    end
                                end
                                
                                local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                                ShowTooltip(self, {
                                    type = "custom",
                                    icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                    title = string.format(slotTitleFormat, typeName, slotIndex),
                                    lines = lines,
                                    anchor = "ANCHOR_TOP"
                                })
                            end)
                            
                            slotFrame:SetScript("OnLeave", function(self)
                                if HideTooltip then
                                    HideTooltip()
                                end
                            end)
                        end


                    elseif activity and not isComplete then
                        -- Incomplete: Show progress numbers (centered, larger font)
                        local progressText = FontManager:CreateFontString(slotFrame, "title", "OVERLAY")
                        progressText:SetPoint("CENTER", 0, 0)
                        progressText:SetWidth(cellWidth - 10)  -- Fit within cell
                        progressText:SetJustifyH("CENTER")
                        progressText:SetWordWrap(false)
                        progressText:SetText(string.format("|cffffcc00%s|r |cffffffff/|r |cffffcc00%s|r", 
                            FormatNumber(progress), FormatNumber(threshold)))
                        
                        -- Add tooltip for incomplete slots
                        if ShowTooltip then
                            slotFrame:EnableMouse(true)
                            slotFrame:SetScript("OnEnter", function(self)
                                local lines = {}
                                
                                local progressFormat = (ns.L and ns.L["VAULT_PROGRESS_FORMAT"]) or "Progress: %s / %s"
                                table.insert(lines, {
                                    text = string.format("|cffffcc00" .. progressFormat .. "|r", FormatNumber(progress), FormatNumber(threshold)),
                                    color = {0.8, 0.8, 0.8}
                                })
                                
                                local remainingFormat = (ns.L and ns.L["VAULT_REMAINING_FORMAT"]) or "Remaining: %s activities"
                                table.insert(lines, {
                                    text = string.format("|cffff6600" .. remainingFormat .. "|r", FormatNumber(threshold - progress)),
                                    color = {0.7, 0.7, 0.7}
                                })
                                
                                local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                                ShowTooltip(self, {
                                    type = "custom",
                                    icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                    title = string.format(slotTitleFormat, typeName, slotIndex),
                                    lines = lines,
                                    anchor = "ANCHOR_TOP"
                                })
                            end)
                            
                            slotFrame:SetScript("OnLeave", function(self)
                                if HideTooltip then
                                    HideTooltip()
                                end
                            end)
                        end
                    else
                        -- No data: Show empty with threshold (centered, larger font)
                        local emptyText = FontManager:CreateFontString(slotFrame, "title", "OVERLAY")
                        emptyText:SetPoint("CENTER", 0, 0)
                        emptyText:SetWidth(cellWidth - 10)  -- Fit within cell
                        emptyText:SetJustifyH("CENTER")
                        emptyText:SetWordWrap(false)
                        if threshold > 0 then
                            emptyText:SetText(string.format("|cff888888%s|r |cff666666/|r |cff888888%s|r", FormatNumber(0), FormatNumber(threshold)))
                            
                            -- Add tooltip for empty slots
                            if ShowTooltip then
                                slotFrame:EnableMouse(true)
                                slotFrame:SetScript("OnEnter", function(self)
                                    local noProgressLabel = (ns.L and ns.L["VAULT_NO_PROGRESS"]) or "No progress yet"
                                    local unlockFormat = (ns.L and ns.L["VAULT_UNLOCK_FORMAT"]) or "Complete %s activities to unlock"
                                    local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                                    ShowTooltip(self, {
                                        type = "custom",
                                        icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                        title = string.format(slotTitleFormat, typeName, slotIndex),
                                        lines = {
                                            {text = noProgressLabel, color = {0.6, 0.6, 0.6}},
                                            {text = string.format("|cffffcc00" .. unlockFormat .. "|r", FormatNumber(threshold)), color = {0.7, 0.7, 0.7}}
                                        },
                                        anchor = "ANCHOR_TOP"
                                    })
                                end)
                                
                                slotFrame:SetScript("OnLeave", function(self)
                                    if HideTooltip then
                                        HideTooltip()
                                    end
                                end)
                            end
                        else
                            emptyText:SetText("|cff666666-|r")
                        end
                    end
                end
                
                -- No need to increment vaultY anymore (using rowIndex)
            end
        else
            -- No vault data: Still set card dimensions so it's visible
            vaultCard:SetHeight(baseCardHeight)
            vaultCard:SetWidth(baseCardWidth)
            
            local noVault = FontManager:CreateFontString(vaultCard, "small", "OVERLAY")
            noVault:SetPoint("CENTER", vaultCard, "CENTER", 0, 0)
            local noVaultLabel = (ns.L and ns.L["NO_VAULT_DATA"]) or "No vault data"
            noVault:SetText("|cff666666" .. noVaultLabel .. "|r")
        end
        
        vaultCard:Show()
            
            -- === CARD 2: M+ DUNGEONS (35%) ===
            local mplusCard = CreateCard(cardContainer, cardHeight)  -- Use same cardHeight from vault card
            mplusCard:SetPoint("TOPLEFT", PixelSnap(card1Width), 0)
            mplusCard:SetWidth(PixelSnap(card2Width - cardSpacing))
            
            local mplusY = 15
            
            -- GUARD: Ensure mythicPlus table exists
            if not pve.mythicPlus then
                pve.mythicPlus = { overallScore = 0, bestRuns = {} }
            end
            
            -- Overall Score (larger, at top) with color based on score
            local totalScore = pve.mythicPlus.overallScore or 0
            local scoreText = FontManager:CreateFontString(mplusCard, "title", "OVERLAY")
            scoreText:SetPoint("TOP", mplusCard, "TOP", 0, -mplusY)
            
            -- Color code based on Mythic+ rating brackets (Blizzard system)
            local scoreColor
            if totalScore >= 2500 then
                scoreColor = "|cffff8000"  -- Legendary Orange (2500+)
            elseif totalScore >= 2000 then
                scoreColor = "|cffa335ee"  -- Epic Purple (2000-2499)
            elseif totalScore >= 1500 then
                scoreColor = "|cff0070dd"  -- Rare Blue (1500-1999)
            elseif totalScore >= 1000 then
                scoreColor = "|cff1eff00"  -- Uncommon Green (1000-1499)
            elseif totalScore >= 500 then
                scoreColor = "|cffffffff"  -- Common White (500-999)
            else
                scoreColor = "|cff9d9d9d"  -- Poor Gray (0-499)
            end
            
            local overallScoreLabel = (ns.L and ns.L["OVERALL_SCORE_LABEL"]) or "Overall Score:"
            scoreText:SetText(string.format("%s %s%s|r", overallScoreLabel, scoreColor, FormatNumber(totalScore)))
            mplusY = mplusY + 35  -- Space before grid
            
            if pve.mythicPlus.dungeons and #pve.mythicPlus.dungeons > 0 then
                local totalDungeons = #pve.mythicPlus.dungeons
                local iconSize = 48
                local maxIconsPerRow = 6  -- Allow up to 6 icons per row
                local iconSpacing = 6  -- Tighter spacing for 6 icons
                
                -- Calculate how many rows needed
                local numRows = math.ceil(totalDungeons / maxIconsPerRow)
                
                -- Find highest key level for highlighting
                local highestKeyLevel = 0
                for _, dungeon in ipairs(pve.mythicPlus.dungeons) do
                    if dungeon.bestLevel and dungeon.bestLevel > highestKeyLevel then
                        highestKeyLevel = dungeon.bestLevel
                    end
                end
                
                -- Card dimensions and padding
                local cardWidthInner = (card2Width - cardSpacing)
                local borderPadding = 2
                local gridY = mplusY
                local rowSpacing = 24  -- Space between rows
                
                -- Group dungeons by row for centered positioning
                local dungeonsByRow = {}
                for i = 1, numRows do
                    dungeonsByRow[i] = {}
                end
                
                for i, dungeon in ipairs(pve.mythicPlus.dungeons) do
                    local row = math.floor((i - 1) / maxIconsPerRow) + 1
                    table.insert(dungeonsByRow[row], dungeon)
                end
                
                -- Calculate spacing based on first/fullest row for consistency
                local sidePadding = 12
                local firstRowIcons = math.min(maxIconsPerRow, totalDungeons)
                local availableWidth = cardWidthInner - (2 * (borderPadding + sidePadding))
                local consistentSpacing = (availableWidth - (firstRowIcons * iconSize)) / (firstRowIcons - 1)
                
                -- Render each row with justified (row 1) or centered (other rows) positioning
                for rowIndex, dungeons in ipairs(dungeonsByRow) do
                    local iconsInThisRow = #dungeons
                    local rowY = gridY + ((rowIndex - 1) * (iconSize + rowSpacing))
                    
                    local startX
                    
                    if rowIndex == 1 and iconsInThisRow >= 4 then
                        -- First row with 4+ icons: JUSTIFY (edge to edge)
                        startX = borderPadding + sidePadding
                    else
                        -- Other rows: CENTER (using same spacing for consistency)
                        local totalRowWidth = (iconsInThisRow * iconSize) + ((iconsInThisRow - 1) * consistentSpacing)
                        startX = (cardWidthInner - totalRowWidth) / 2
                    end
                    
                    for colIndex, dungeon in ipairs(dungeons) do
                        local iconX = startX + ((colIndex - 1) * (iconSize + consistentSpacing))
                        
                        -- Create icon frame (noBorder=true, we'll add custom border)
                        local iconFrame = CreateIcon(mplusCard, dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark", iconSize, false, nil, false)
                        -- Round position to nearest pixel to prevent border jitter
                        local roundedX = math.floor(iconX + 0.5)
                        local roundedY = math.floor(rowY + 0.5)
                        iconFrame:SetPoint("TOPLEFT", roundedX, -roundedY)
                        iconFrame:EnableMouse(true)
                        
                        local texture = iconFrame.texture
                        
                        -- Prevent texture bleeding: Crop 5% from edges
                        if texture then
                            texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
                        end
                        local hasBestLevel = dungeon.bestLevel and dungeon.bestLevel > 0
                        local isHighest = hasBestLevel and dungeon.bestLevel == highestKeyLevel and highestKeyLevel >= 10
                        
                        -- Update border color (reuse existing border from CreateIcon)
                        if iconFrame.BorderTop then
                            local r, g, b, a
                            if isHighest then
                                -- Highest key: Gold border
                                r, g, b, a = 1, 0.82, 0, 0.9
                            elseif hasBestLevel then
                                -- Completed: Accent color border
                                local accentColor = COLORS.accent
                                r, g, b, a = accentColor[1], accentColor[2], accentColor[3], 0.8
                            else
                                -- Not done: Gray border
                                r, g, b, a = 0.4, 0.4, 0.4, 0.6
                            end
                            
                            -- Update all 4 border textures
                            iconFrame.BorderTop:SetVertexColor(r, g, b, a)
                            iconFrame.BorderBottom:SetVertexColor(r, g, b, a)
                            iconFrame.BorderLeft:SetVertexColor(r, g, b, a)
                            iconFrame.BorderRight:SetVertexColor(r, g, b, a)
                        end
                    
                    if hasBestLevel then
                        -- Semi-transparent backdrop behind text for readability
                        local backdrop = iconFrame:CreateTexture(nil, "BACKGROUND")
                        backdrop:SetSize(iconSize * 0.8, iconSize * 0.5)
                        backdrop:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        backdrop:SetColorTexture(0, 0, 0, 0.7)  -- Black, 70% opacity
                        
                        -- Key level INSIDE icon (with shadow for readability)
                        local levelShadow = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        levelShadow:SetPoint("CENTER", iconFrame, "CENTER", 1, -1)  -- Shadow offset
                        levelShadow:SetText(string.format("|cff000000+%d|r", dungeon.bestLevel))
                        
                        local levelText = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        levelText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        levelText:SetText(string.format("|cffffcc00+%d|r", dungeon.bestLevel))
                        
                        -- Score BELOW icon with color
                        local dungeonScore = FontManager:CreateFontString(iconFrame, "title", "OVERLAY")
                        dungeonScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        
                        -- Color based on score brackets
                        local score = dungeon.score or 0
                        local scoreColor
                        if score >= 312 then
                            scoreColor = "|cffff8000"  -- Legendary Orange (312+)
                        elseif score >= 250 then
                            scoreColor = "|cffa335ee"  -- Epic Purple (250-311)
                        elseif score >= 187 then
                            scoreColor = "|cff0070dd"  -- Rare Blue (187-249)
                        elseif score >= 125 then
                            scoreColor = "|cff1eff00"  -- Uncommon Green (125-186)
                        elseif score >= 62 then
                            scoreColor = "|cffffffff"  -- Common White (62-124)
                        else
                            scoreColor = "|cff9d9d9d"  -- Poor Gray (0-61)
                        end
                        
                        dungeonScore:SetText(string.format("%s%s|r", scoreColor, FormatNumber(score)))
                    else
                        -- Not Done - Dimmed icon
                        texture:SetDesaturated(true)
                        texture:SetAlpha(0.4)
                        
                        -- "?" in icon
                        local notDone = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        notDone:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        notDone:SetText("|cff666666?|r")
                        
                        -- "-" below
                        local zeroScore = FontManager:CreateFontString(iconFrame, "title", "OVERLAY")
                        zeroScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        zeroScore:SetText("|cff444444-|r")
                    end
                    
                    -- Tooltip with detailed info
                    if ShowTooltip and HideTooltip then
                        iconFrame:SetScript("OnEnter", function(self)
                            local tooltipLines = {}
                            local mapID = dungeon.mapID  -- Store mapID for time lookup
                            
                            -- Dungeon name
                            if dungeon.name then
                                table.insert(tooltipLines, {
                                    text = dungeon.name,
                                    color = {1, 1, 1}
                                })
                            end
                            
                            if hasBestLevel then
                                -- Best key level
                                local bestKeyLabel = (ns.L and ns.L["VAULT_BEST_KEY"]) or "Best Key:"
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffcc00+%d|r", bestKeyLabel, dungeon.bestLevel),
                                    color = {0.9, 0.9, 0.9}
                                })
                                
                                -- Score
                                local scoreLabel = (ns.L and ns.L["VAULT_SCORE"]) or "Score:"
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffffff%s|r", scoreLabel, FormatNumber(dungeon.score or 0)),
                                    color = {0.9, 0.9, 0.9}
                                })
                            else
                                -- Not completed
                                local notCompletedLabel = (ns.L and ns.L["NOT_COMPLETED_SEASON"]) or "Not completed this season"
                                table.insert(tooltipLines, {
                                    text = "|cff888888" .. notCompletedLabel .. "|r",
                                    color = {0.6, 0.6, 0.6}
                                })
                            end
                            
                            ShowTooltip(self, {
                                type = "custom",
                                icon = dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                                title = dungeon.name or ((ns.L and ns.L["VAULT_DUNGEON"]) or "Dungeon"),
                                lines = tooltipLines,
                                anchor = "ANCHOR_TOP"
                            })
                        end)
                        
                        iconFrame:SetScript("OnLeave", function(self)
                            HideTooltip()
                        end)
                    end
                    
                    iconFrame:Show()
                    end  -- End dungeon loop (for each dungeon in this row)
                end  -- End row loop
            else
                local noData = FontManager:CreateFontString(mplusCard, "small", "OVERLAY")
                noData:SetPoint("TOPLEFT", 15, -mplusY)
                local noDataLabel = (ns.L and ns.L["NO_DATA"]) or "No data"
                noData:SetText("|cff666666" .. noDataLabel .. "|r")
            end
            
            mplusCard:Show()
            
            -- === CARD 3: PVE SUMMARY (35%) - 2 COLUMN TOP + 1 ROW BOTTOM LAYOUT ===
            local summaryCard = CreateCard(cardContainer, cardHeight)  -- Use same cardHeight from vault card
            summaryCard:SetPoint("TOPLEFT", PixelSnap(card1Width + card2Width), 0)
            summaryCard:SetWidth(PixelSnap(card3Width))
            
            -- ===== LAYOUT CONSTANTS (UI/UX Optimized) =====
            local cardPadding = 10
            local sectionSpacing = 20  -- Clear separation between sections
            local topSectionHeight = 115  -- Compact upper section
            local currencyRowY = topSectionHeight + sectionSpacing  -- Currency section with clear gap
            
            -- Calculate widths for top 2 columns (Keystone + Affixes)
            local columnSpacing = 15
            local topColumnWidth = (card3Width - cardPadding * 2 - columnSpacing) / 2
            
            -- === TOP SECTION: KEYSTONE (Left) ===
            local col1X = cardPadding
            local col1Y = 15
            
            -- Keystone title (centered)
            local keystoneTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            keystoneTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col1X + topColumnWidth / 2, -col1Y)
            local keystoneLabel = (ns.L and ns.L["KEYSTONE"]) or "Keystone"
            keystoneTitle:SetText("|cffffffff" .. keystoneLabel .. "|r")
            keystoneTitle:SetJustifyH("CENTER")
            
            -- CRITICAL: Use THIS character's keystone (from loop's charKey, not current player)
            -- pveData is already fetched for this specific character at line 589
            local keystoneData = pveData and pveData.keystone
            
            if keystoneData and keystoneData.level and keystoneData.level > 0 and keystoneData.mapID then
                local keystoneLevel = keystoneData.level
                local keystoneMapID = keystoneData.mapID
                
                if C_ChallengeMode then
                    local mapName, _, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(keystoneMapID)
                    
                    -- Dungeon icon (below title, centered in column) - matching affix size
                    local iconSize = 38  -- Same as affixes for visual consistency
                    local keystoneIcon = CreateIcon(summaryCard, texture or "Interface\\Icons\\Achievement_ChallengeMode_Gold", iconSize, false, nil, false)
                    keystoneIcon:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -8)
                    
                    -- Apply border to keystone icon
                    if keystoneIcon.BorderTop then
                        local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                        keystoneIcon.BorderTop:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderBottom:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderLeft:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderRight:SetVertexColor(r, g, b, a)
                    end
                    
                    keystoneIcon:Show()
                    
                    -- Key level (below icon, centered)
                    local levelText = FontManager:CreateFontString(summaryCard, "header", "OVERLAY")
                    levelText:SetPoint("TOP", keystoneIcon, "BOTTOM", 0, -6)
                    levelText:SetText(string.format("|cff00ff00+%d|r", keystoneLevel))
                    levelText:SetJustifyH("CENTER")
                    
                    -- Dungeon name (below level, centered)
                    local nameText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                    nameText:SetPoint("TOP", levelText, "BOTTOM", 0, -4)
                    nameText:SetWidth(topColumnWidth - 10)
                    nameText:SetJustifyH("CENTER")
                    nameText:SetWordWrap(true)
                    nameText:SetMaxLines(2)
                    nameText:SetText(mapName or ((ns.L and ns.L["KEYSTONE"]) or "Keystone"))
                else
                    -- No keystone (centered below title)
                    local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                    noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                    local noKeyLabel = (ns.L and ns.L["NO_KEY"]) or "No Key"
                    noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                    noKeyText:SetJustifyH("CENTER")
                end
            else
                -- API not available
                local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                local noKeyLabel = (ns.L and ns.L["NO_KEY"]) or "No Key"
                noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                noKeyText:SetJustifyH("CENTER")
            end
            
            -- === TOP SECTION: AFFIXES (Right) ===
            local col2X = col1X + topColumnWidth + columnSpacing
            local col2Y = 15
            
            -- Affixes title (centered)
            local affixesTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            affixesTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col2X + topColumnWidth / 2, -col2Y)
            local affixesLabel = (ns.L and ns.L["AFFIXES"]) or "Affixes"
            affixesTitle:SetText("|cffffffff" .. affixesLabel .. "|r")
            affixesTitle:SetJustifyH("CENTER")
            
            -- Get current affixes from PvECacheService
            local allPveData = self:GetPvEData()  -- Get all data (includes currentAffixes)
            local currentAffixes = allPveData and allPveData.currentAffixes
            
            -- Affixes render (independent of C_ChallengeMode - icons already cached)
            if currentAffixes and #currentAffixes > 0 then
                    -- MODERN LAYOUT: Single horizontal row (4x1)
                    local affixSize = 38
                    local affixSpacing = 10
                    local maxAffixes = math.min(#currentAffixes, 4)  -- Max 4 affixes
                    
                    -- Center the horizontal row in column (below title)
                    local totalWidth = (maxAffixes * affixSize) + ((maxAffixes - 1) * affixSpacing)
                    local startX = col2X + (topColumnWidth - totalWidth) / 2
                    local startY = col2Y + 23  -- Aligned with keystone icon (title + 8px gap)
                    
                    -- Render affixes (data already cached from PvECacheService)
                    for i, affixData in ipairs(currentAffixes) do
                        if i <= maxAffixes then
                            -- Use cached affix data (no API call needed)
                            local name = affixData.name
                            local description = affixData.description
                            local filedataid = affixData.icon
                            
                            if filedataid then
                                    -- Horizontal positioning (single row)
                                    local xOffset = startX + ((i - 1) * (affixSize + affixSpacing))
                                    local yOffset = startY
                                    
                                    local affixIcon = CreateIcon(summaryCard, filedataid, affixSize, false, nil, false)
                                    -- Round position to prevent border jitter
                                    local roundedX = math.floor(xOffset + 0.5)
                                    local roundedY = math.floor(yOffset + 0.5)
                                    affixIcon:SetPoint("TOPLEFT", roundedX, -roundedY)
                                    
                                    -- Apply border to affix icon
                                    if affixIcon.BorderTop then
                                        local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                                        affixIcon.BorderTop:SetVertexColor(r, g, b, a)
                                        affixIcon.BorderBottom:SetVertexColor(r, g, b, a)
                                        affixIcon.BorderLeft:SetVertexColor(r, g, b, a)
                                        affixIcon.BorderRight:SetVertexColor(r, g, b, a)
                                    end
                                    
                                    -- Tooltip
                                    if ShowTooltip then
                                        affixIcon:EnableMouse(true)
                                        affixIcon:SetScript("OnEnter", function(self)
                                            ShowTooltip(self, {
                                                type = "custom",
                                                icon = filedataid,
                                                title = name or ((ns.L and ns.L["AFFIX_TITLE_FALLBACK"]) or "Affix"),
                                                description = description,
                                                lines = {},
                                                anchor = "ANCHOR_RIGHT"
                                            })
                                        end)
                                        affixIcon:SetScript("OnLeave", function(self)
                                            if HideTooltip then HideTooltip() end
                                        end)
                                    end
                                    
                                    affixIcon:Show()
                            end  -- if filedataid
                        end  -- if i <= 4
                    end  -- for currentAffixes
            else
                -- No affixes or API not available
                local noAffixesText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noAffixesText:SetPoint("TOP", affixesTitle, "BOTTOM", 0, -30)
                local noAffixesLabel = (ns.L and ns.L["NO_AFFIXES"]) or "No Affixes"
                noAffixesText:SetText("|cff888888" .. noAffixesLabel .. "|r")
                noAffixesText:SetJustifyH("CENTER")
            end  -- if currentAffixes
            
            -- === BOTTOM SECTION: TWW SEASON 3 CURRENCIES (Single Row) ===
            -- TWW Season 3 currencies: Valorstone and all Ethereal Crests
            local twwCurrencies = {
                {id = 3008, name = "Valorstone", fallbackIcon = 5868902},
                {id = 3284, name = "Weathered Ethereal Crest", fallbackIcon = 5872061},
                {id = 3286, name = "Carved Ethereal Crest", fallbackIcon = 5872055},
                {id = 3288, name = "Runed Ethereal Crest", fallbackIcon = 5872059},
                {id = 3290, name = "Gilded Ethereal Crest", fallbackIcon = 5872057},
            }
            
            local numCurrencies = #twwCurrencies
            local availableWidth = card3Width - (cardPadding * 2)
            local iconSize = 30  -- Slightly smaller for better spacing
            local currencySpacing = 10  -- More breathing room
            local currencyItemWidth = (availableWidth - (currencySpacing * (numCurrencies - 1))) / numCurrencies
            
            -- Calculate starting X position to center all currencies
            local totalCurrencyWidth = (numCurrencies * currencyItemWidth) + ((numCurrencies - 1) * currencySpacing)
            local currencyStartX = cardPadding + (availableWidth - totalCurrencyWidth) / 2
            
            for i, curr in ipairs(twwCurrencies) do
                -- Get currency data from CurrencyCacheService (per-character API)
                local currencyEntry = WarbandNexus:GetCurrencyData(curr.id, charKey)
                    
                    -- Calculate position for this currency (always, even if info is nil)
                    local currencyX = currencyStartX + ((i - 1) * (currencyItemWidth + currencySpacing))
                    
                    -- Extract data from DB
                    local iconFileID = currencyEntry and currencyEntry.icon or curr.fallbackIcon
                    local quantity = currencyEntry and currencyEntry.quantity or 0
                    local maxQuantity = currencyEntry and currencyEntry.maxQuantity or 0
                    local currencyName = currencyEntry and currencyEntry.name or curr.name
                    
                    -- Render currency icon and text
                    if iconFileID then
                        -- Currency icon (centered in its column)
                        local iconX = currencyX + (currencyItemWidth - iconSize) / 2
                        local currIcon = CreateIcon(summaryCard, iconFileID, iconSize, false, nil, false)
                        -- Round position to prevent border jitter
                        local roundedCurrX = math.floor((currencyX + currencyItemWidth / 2) + 0.5)
                        local roundedCurrY = math.floor(currencyRowY + 0.5)
                        currIcon:SetPoint("TOP", summaryCard, "TOPLEFT", roundedCurrX, -roundedCurrY)
                        
                        -- Apply border to currency icon
                        if currIcon.BorderTop then
                            local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                            currIcon.BorderTop:SetVertexColor(r, g, b, a)
                            currIcon.BorderBottom:SetVertexColor(r, g, b, a)
                            currIcon.BorderLeft:SetVertexColor(r, g, b, a)
                            currIcon.BorderRight:SetVertexColor(r, g, b, a)
                        end
                        
                        -- Currency amount (below icon, centered)
                        local currText = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
                        currText:SetPoint("TOP", currIcon, "BOTTOM", 0, -4)
                        currText:SetJustifyH("CENTER")
                        currText:SetWordWrap(false)
                        currText:SetMaxLines(1)
                        
                        -- Compact format with color coding
                        if maxQuantity > 0 then
                            local percentage = (quantity / maxQuantity) * 100
                            local color = "|cffffffff"
                            if percentage >= 100 then
                                color = "|cffff4444" -- Red (capped)
                            elseif percentage >= 80 then
                                color = "|cffffaa00" -- Orange
                            end
                            currText:SetText(string.format("%s%s|r / %s", color, FormatNumber(quantity), FormatNumber(maxQuantity)))
                        else
                            currText:SetText(string.format("|cffffffff%s|r", FormatNumber(quantity)))
                        end
                        
                        -- Dynamic width: measure rendered text width and use max of column width or text width
                        local renderedWidth = currText:GetStringWidth() or 0
                        local minWidth = currencyItemWidth + 10
                        currText:SetWidth(math.max(minWidth, renderedWidth + 6))
                        
                        -- Make icon interactive for tooltip
                        currIcon:EnableMouse(true)
                        
                        -- Tooltip on icon hover
                        if ShowTooltip and HideTooltip then
                            currIcon:SetScript("OnEnter", function(self)
                                local tooltipLines = {}
                                
                                if maxQuantity > 0 then
                                    local currentMaxFormat = (ns.L and ns.L["CURRENT_MAX_FORMAT"]) or "Current: %s / %s"
                                    table.insert(tooltipLines, {
                                        text = string.format(currentMaxFormat, FormatNumber(quantity), FormatNumber(maxQuantity)),
                                        color = {1, 1, 1}
                                    })
                                    
                                    local percentage = (quantity / maxQuantity) * 100
                                    local percentColor = {0.5, 1, 0.5}
                                    if percentage >= 100 then
                                        percentColor = {1, 0.3, 0.3}
                                    elseif percentage >= 80 then
                                        percentColor = {1, 0.7, 0.3}
                                    end
                                    local progressPercentFormat = (ns.L and ns.L["PROGRESS_PERCENT_FORMAT"]) or "Progress: %.1f%%"
                                    table.insert(tooltipLines, {
                                        text = string.format(progressPercentFormat, percentage),
                                        color = percentColor
                                    })
                                else
                                    local currentFormat = (ns.L and ns.L["CURRENT_MAX_FORMAT"]) or "Current: %s / %s"
                                    -- Extract just the "Current: %s" part if format includes "/ %s"
                                    local currentOnly = currentFormat:match("^(.-) / %%s") or currentFormat:gsub(" / %%s", "")
                                    table.insert(tooltipLines, {
                                        text = string.format(currentOnly, FormatNumber(quantity)),
                                        color = {1, 1, 1}
                                    })
                                    local noCapLimitLabel = (ns.L and ns.L["NO_CAP_LIMIT"]) or "No cap limit"
                                    table.insert(tooltipLines, {
                                        text = noCapLimitLabel,
                                        color = {0.7, 0.7, 0.7}
                                    })
                                end
                                
                                ShowTooltip(self, {
                                    type = "custom",
                                    icon = iconFileID,
                                    title = currencyName or ((ns.L and ns.L["TAB_CURRENCY"]) or "Currency"),
                                    lines = tooltipLines,
                                    anchor = "ANCHOR_TOP"
                                })
                            end)
                            
                            currIcon:SetScript("OnLeave", function(self)
                                HideTooltip()
                            end)
                        end
                        
                        currIcon:Show()
                    end
                end
            
            summaryCard:Show()
            
            -- Calculate minimum required height for new layout
            -- currencyRowY (135) + iconSize (30) + text height (20) + bottom padding (15) = 200
            local minSummaryHeight = currencyRowY + 30 + 20 + 15
            
            -- Use maximum of vault cardHeight or minimum required height
            local finalHeight = math.max(cardHeight or 200, minSummaryHeight)
            
            cardContainer:SetHeight(finalHeight)
            yOffset = yOffset + finalHeight + GetLayout().afterElement
        end
        
        -- Character sections flow directly one after another (like Characters tab)
    end
    
    return yOffset + 20
end

