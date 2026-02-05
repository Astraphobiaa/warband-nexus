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
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local DrawEmptyState = ns.UI_DrawEmptyState
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
    
    -- Listen for PvE data updates
    local Constants = ns.Constants
    WarbandNexus:RegisterMessage(Constants.EVENTS.PVE_UPDATED, function()
        -- Only refresh if we're currently showing the PvE tab
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.currentTab == "pve" then
            WarbandNexus:RefreshUI()
        end
    end)
    
    -- Event listener registered (silent)
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
    
    -- World/Delves tier progression (Tier 1-8)
    if typeName == "World" then
        if currentLevel >= 8 then
            return nil -- Already at max (Tier 8)
        end
        return string.format("Tier %d", currentLevel + 1)
    end
    
    -- Raid difficulty progression
    if typeName == "Raid" then
        -- Level: 14=Normal, 15=Heroic, 16=Mythic, <14=LFR
        if currentLevel >= 16 then
            return nil -- Already at Mythic (max)
        elseif currentLevel >= 15 then
            return "Mythic"
        elseif currentLevel >= 14 then
            return "Heroic"
        else
            return "Normal"
        end
    end
    
    -- M+ keystone progression
    if typeName == "M+" or typeName == "Dungeon" then
        if currentLevel >= 10 then
            return nil -- Max is +10
        end
        
        local nextLevel = currentLevel + 1
        if nextLevel == 0 then
            return "Heroic"
        elseif nextLevel == 1 then
            return "Mythic"
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
    if typeName == "World" then
        return "Tier 8"
    elseif typeName == "Raid" then
        return "Mythic"
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
    if not activity then
        return "Unknown"
    end
    
    if typeName == "Raid" then
        local difficulty = "Unknown"
        if activity.level then
            -- Raid level corresponds to difficulty ID
            if activity.level >= 16 then
                difficulty = "Mythic"
            elseif activity.level >= 15 then
                difficulty = "Heroic"
            elseif activity.level >= 14 then
                difficulty = "Normal"
            else
                difficulty = "LFR"
            end
        end
        return difficulty
    elseif typeName == "M+" then
        local level = activity.level or 0
        -- Level 0 = Heroic dungeon, Level 1 = Mythic dungeon, Level 2+ = Keystone
        if level == 0 then
            return "Heroic"
        elseif level == 1 then
            return "Mythic"
        else
            return string.format("+%d", level)
        end
    elseif typeName == "World" then
        local tier = activity.level or 1
        return string.format("Tier %d", tier)
    elseif typeName == "PvP" then
        return "PvP"
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
        if self.db.global.pveCache and next(self.db.global.pveCache.characters or {}) then
            local cacheVersion = self.db.global.pveCache.version or "unknown"
            dataSource = "PvECache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Register event listener (only once)
    RegisterPvEEvents(parent)
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    
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
    local titleTextContent = "|cff" .. hexColor .. "PvE Progress|r"
    local subtitleTextContent = "Great Vault, Raid Lockouts & Mythic+ across your Warband"
    
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
        loadingText:SetText("|cff00ccffLoading PvE Data...|r")
        
        -- Progress indicator with current stage
        local progressText = FontManager:CreateFontString(loadingCard, "body", "OVERLAY")
        progressText:SetPoint("LEFT", spinner, "RIGHT", 15, -8)
        
        local attempt = ns.PvELoadingState.attempts or 1
        local currentStage = ns.PvELoadingState.currentStage or "Preparing"
        local progress = ns.PvELoadingState.loadingProgress or 0
        
        progressText:SetText(string.format("|cff888888%s - %d%%|r", currentStage, progress))
        
        -- Hint text
        local hintText = FontManager:CreateFontString(loadingCard, "small", "OVERLAY")
        hintText:SetPoint("LEFT", spinner, "RIGHT", 15, -25)
        hintText:SetTextColor(0.6, 0.6, 0.6)
        hintText:SetText("Please wait, WoW APIs are initializing...")
        
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
        local cardHeight = CreateDisabledCard(parent, yOffset, "PvE Progress")
        return yOffset + cardHeight
    end
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    
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
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        
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
                local key = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
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
        yOffset = DrawEmptyState(self, parent, yOffset, false, "No character data available")
        return yOffset
    end
    
    -- ===== CHARACTER COLLAPSIBLE HEADERS (Favorites first, then regular) =====
    for i, char in ipairs(characters) do
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
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
        
        -- Smart expand: expand if current character, has unclaimed vault rewards, OR has any vault data
        local charExpandKey = "pve-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
        local hasVaultReward = pve.hasUnclaimedRewards or false
        
        -- Check if character has ANY vault activity data (for auto-expand)
        local hasVaultData = false
        if pve.vaultActivities then
            if (pve.vaultActivities.raids and #pve.vaultActivities.raids > 0) or
               (pve.vaultActivities.mythicPlus and #pve.vaultActivities.mythicPlus > 0) or
               (pve.vaultActivities.pvp and #pve.vaultActivities.pvp > 0) or
               (pve.vaultActivities.world and #pve.vaultActivities.world > 0) then
                hasVaultData = true
            end
        end
        
        local charExpanded = IsExpanded(charExpandKey, isCurrentChar or hasVaultReward or hasVaultData)
        
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
        -- Use same sizing as Characters tab: 24px button, 27.6px icon (1.15x multiplier), -2px down
        local StyleFavoriteIcon = ns.UI_StyleFavoriteIcon
        local favSize = 24
        local favIconSize = favSize * 1.15
        
        local favFrame = CreateIcon(charHeader, "Interface\\COMMON\\FavoritesIcon", favIconSize, false, nil, true)
        favFrame:SetSize(favSize, favSize)
        favFrame:SetPoint("LEFT", charBtn, "RIGHT", 4, -2)  -- Match Characters tab position (-2px down)
        
        local favIcon = favFrame.texture
        favIcon:SetSize(favIconSize, favIconSize)
        favIcon:SetPoint("CENTER", 0, 0)  -- Center larger icon within frame
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
        charNameText:SetText(string.format("|cff%02x%02x%02x%s  -  %s|r", 
            classColor.r * 255, classColor.g * 255, classColor.b * 255, 
            char.name,
            char.realm or ""))
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
        local levelString = string.format("|cff%02x%02x%02xLv %d|r", 
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
            ilvlText:SetText(string.format("|cffffd700iLvl %d|r", char.itemLevel))
        end
        
        -- Vault badge (right side of header)
        if hasVaultReward then
            local vaultContainer = ns.UI.Factory:CreateContainer(charHeader, 110, 20)
            vaultContainer:SetPoint("RIGHT", -10, 0)
            
            local vaultIconFrame = CreateIcon(vaultContainer, "Interface\\Icons\\achievement_guildperk_bountifulbags", 16, false, nil, true)
            vaultIconFrame:SetPoint("LEFT", 0, 0)
            vaultIconFrame:Show()
            
            local vaultText = FontManager:CreateFontString(vaultContainer, "small", "OVERLAY")
            vaultText:SetPoint("LEFT", vaultIconFrame, "RIGHT", 4, 0)
            vaultText:SetText("Great Vault")
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
                local typeName = "Unknown"
                local typeNum = activity.type
                
                if Enum and Enum.WeeklyRewardChestThresholdType then
                        if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then typeName = "Raid"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then typeName = "M+"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then typeName = "PvP"
                        elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then typeName = "World"
                    end
                else
                    -- Fallback numeric values based on API:
                    -- 1 = Activities (M+), 2 = RankedPvP, 3 = Raid, 6 = World
                    if typeNum == 3 then typeName = "Raid"
                    elseif typeNum == 1 then typeName = "M+"
                    elseif typeNum == 2 then typeName = "PvP"
                    elseif typeNum == 6 then typeName = "World"
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
                
                -- Row background removed (naked frame)
                
                -- Set alternating background colors
                local ROW_COLOR_EVEN = GetLayout().ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
                local ROW_COLOR_ODD = GetLayout().ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
                local bgColor = (i % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
                
                if not rowFrame.bg then
                    rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
                    rowFrame.bg:SetAllPoints()
                end
                rowFrame.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
                
                -- Type label (COLUMN 0 - Cell 0, left-aligned, vertically centered)
                local label = FontManager:CreateFontString(rowFrame, "title", "OVERLAY")
                label:SetPoint("LEFT", 5, 0)  -- 5px padding for readability
                label:SetWidth(cellWidth - 10)
                label:SetJustifyH("LEFT")
                label:SetText(string.format("|cffffffff%s|r", typeName))
                
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
                            ilvlText:SetText(string.format("|cffffd700iLvL %d|r", rewardIlvl))
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
                                        table.insert(lines, {
                                            text = string.format("Next Tier: |cffffd700%d iLvL|r on complete |cffffcc00%s|r", activity.nextLevelIlvl, nextTierName),
                                            color = {0.8, 0.8, 0.8}
                                        })
                                    end
                                end
                                
                                ShowTooltip(self, {
                                    type = "custom",
                                    title = typeName .. " Slot " .. slotIndex,
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
                        progressText:SetText(string.format("|cffffcc00%s|r|cffffffff/|r|cffffcc00%s|r", 
                            FormatNumber(progress), FormatNumber(threshold)))
                        
                        -- Add tooltip for incomplete slots
                        if ShowTooltip then
                            slotFrame:EnableMouse(true)
                            slotFrame:SetScript("OnEnter", function(self)
                                local lines = {}
                                
                                table.insert(lines, {
                                    text = string.format("Progress: |cffffcc00%s|r / |cffffcc00%s|r", FormatNumber(progress), FormatNumber(threshold)),
                                    color = {0.8, 0.8, 0.8}
                                })
                                
                                table.insert(lines, {
                                    text = string.format("Remaining: |cffff6600%s|r activities", FormatNumber(threshold - progress)),
                                    color = {0.7, 0.7, 0.7}
                                })
                                
                                ShowTooltip(self, {
                                    type = "custom",
                                    title = typeName .. " Slot " .. slotIndex,
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
                            emptyText:SetText(string.format("|cff888888%s|r|cff666666/|r|cff888888%s|r", FormatNumber(0), FormatNumber(threshold)))
                            
                            -- Add tooltip for empty slots
                            if ShowTooltip then
                                slotFrame:EnableMouse(true)
                                slotFrame:SetScript("OnEnter", function(self)
                                    ShowTooltip(self, {
                                        type = "custom",
                                        title = typeName .. " Slot " .. slotIndex,
                                        lines = {
                                            {text = "No progress yet", color = {0.6, 0.6, 0.6}},
                                            {text = string.format("Complete |cffffcc00%s|r activities to unlock", FormatNumber(threshold)), color = {0.7, 0.7, 0.7}}
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
            noVault:SetText("|cff666666No vault data|r")
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
            
            scoreText:SetText(string.format("Overall Score: %s%s|r", scoreColor, FormatNumber(totalScore)))
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
                                table.insert(tooltipLines, {
                                    text = string.format("Best Key: |cffffcc00+%d|r", dungeon.bestLevel),
                                    color = {0.9, 0.9, 0.9}
                                })
                                
                                -- Score
                                table.insert(tooltipLines, {
                                    text = string.format("Score: |cffffffff%s|r", FormatNumber(dungeon.score or 0)),
                                    color = {0.9, 0.9, 0.9}
                                })
                            else
                                -- Not completed
                                table.insert(tooltipLines, {
                                    text = "|cff888888Not completed this season|r",
                                    color = {0.6, 0.6, 0.6}
                                })
                            end
                            
                            ShowTooltip(self, {
                                type = "custom",
                                title = dungeon.name or "Dungeon",
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
                noData:SetText("|cff666666No data|r")
            end
            
            mplusCard:Show()
            
            -- === CARD 3: PVE SUMMARY (35%) - 2 COLUMN TOP + 1 ROW BOTTOM LAYOUT ===
            local summaryCard = CreateCard(cardContainer, cardHeight)  -- Use same cardHeight from vault card
            summaryCard:SetPoint("TOPLEFT", PixelSnap(card1Width + card2Width), 0)
            summaryCard:SetWidth(PixelSnap(card3Width))
            
            local cardPadding = 10
            local columnSpacing = 15
            local topSectionHeight = 140  -- Height for Keystone + Affixes section
            local currencyRowY = topSectionHeight - 5  -- Start currency row below Keystone/Affixes section
            
            -- Calculate widths for top 2 columns
            local topColumnWidth = (card3Width - cardPadding * 2 - columnSpacing) / 2
            
            -- === TOP SECTION: KEYSTONE (Left) ===
            local col1X = cardPadding
            local col1Y = 15
            
            -- Keystone title (centered)
            local keystoneTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            keystoneTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col1X + topColumnWidth / 2, -col1Y)
            keystoneTitle:SetText("|cffffffffKeystone|r")
            keystoneTitle:SetJustifyH("CENTER")
            
            -- Get current character's keystone from PvECacheService
            local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
            local pveData = self:GetPvEData(charKey)
            local keystoneData = pveData and pveData.keystone
            
            if keystoneData and keystoneData.level and keystoneData.level > 0 and keystoneData.mapID then
                local keystoneLevel = keystoneData.level
                local keystoneMapID = keystoneData.mapID
                
                if C_ChallengeMode then
                    local mapName, _, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(keystoneMapID)
                    
                    -- Dungeon icon (below title, centered in column)
                    local iconSize = 48
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
                    nameText:SetText(mapName or "Keystone")
                else
                    -- No keystone (centered below title)
                    local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                    noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                    noKeyText:SetText("|cff888888No Key|r")
                    noKeyText:SetJustifyH("CENTER")
                end
            else
                -- API not available
                local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                noKeyText:SetText("|cff888888No Key|r")
                noKeyText:SetJustifyH("CENTER")
            end
            
            -- === TOP SECTION: AFFIXES (Right) ===
            local col2X = col1X + topColumnWidth + columnSpacing
            local col2Y = 15
            
            -- Affixes title (centered)
            local affixesTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            affixesTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col2X + topColumnWidth / 2, -col2Y)
            affixesTitle:SetText("|cffffffffAffixes|r")
            affixesTitle:SetJustifyH("CENTER")
            
            -- Get current affixes from PvECacheService
            local allPveData = self:GetPvEData()  -- Get all data (includes currentAffixes)
            local currentAffixes = allPveData and allPveData.currentAffixes
            
            if currentAffixes and #currentAffixes > 0 and C_ChallengeMode then
                    local affixSize = 36
                    local affixSpacing = 8
                    local gridCols = 2
                    local gridRows = 2
                    
                    -- Center the 2x2 grid in column (below title)
                    local gridWidth = (gridCols * affixSize) + ((gridCols - 1) * affixSpacing)
                    local gridHeight = (gridRows * affixSize) + ((gridRows - 1) * affixSpacing)
                    local startX = col2X + (topColumnWidth - gridWidth) / 2
                    local startY = col2Y + 25  -- Below title
                    
                    -- Render affixes (data already cached from PvECacheService)
                    for i, affixData in ipairs(currentAffixes) do
                        if i <= 4 then -- Max 4 affixes (2x2)
                            -- Use cached affix data (no API call needed)
                            local name = affixData.name
                            local description = affixData.description
                            local filedataid = affixData.icon
                            
                            if filedataid then
                                    -- Calculate grid position (2 columns)
                                    local col = (i - 1) % gridCols
                                    local row = math.floor((i - 1) / gridCols)
                                    
                                    local xOffset = startX + (col * (affixSize + affixSpacing))
                                    local yOffset = startY + (row * (affixSize + affixSpacing))
                                    
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
                                                title = name or "Affix",
                                                lines = {{text = description or "", color = {1, 1, 1}, wrap = true}},
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
                noAffixesText:SetPoint("TOP", affixesTitle, "BOTTOM", 0, -20)
                noAffixesText:SetText("|cff888888No Affixes|r")
                noAffixesText:SetJustifyH("CENTER")
            end  -- if currentAffixes
            
            -- === BOTTOM SECTION: TWW SEASON 3 CURRENCIES (Single Row) ===
            if C_CurrencyInfo then
                -- Get current character key for fallback data lookup
                local currentCharKey = ns.Utilities:GetCharacterKey()
                
                -- TWW Season 3 currencies: Valorstone and all Ethereal Crests
                -- Updated currency IDs and icons (matching CurrencyUI.lua API data)
                local twwCurrencies = {
                    {id = 3008, name = "Valorstone", fallbackIcon = 5868902},
                    {id = 3284, name = "Weathered Ethereal Crest", fallbackIcon = 5872061},
                    {id = 3286, name = "Carved Ethereal Crest", fallbackIcon = 5872055},
                    {id = 3288, name = "Runed Ethereal Crest", fallbackIcon = 5872059},
                    {id = 3290, name = "Gilded Ethereal Crest", fallbackIcon = 5872057},
                }
                
                local numCurrencies = #twwCurrencies
                local availableWidth = card3Width - (cardPadding * 2)
                local iconSize = 32
                local currencySpacing = 8
                local currencyItemWidth = (availableWidth - (currencySpacing * (numCurrencies - 1))) / numCurrencies
                
                -- Calculate starting X position to center all currencies
                local totalCurrencyWidth = (numCurrencies * currencyItemWidth) + ((numCurrencies - 1) * currencySpacing)
                local currencyStartX = cardPadding + (availableWidth - totalCurrencyWidth) / 2
                
                for i, curr in ipairs(twwCurrencies) do
                    local info = C_CurrencyInfo.GetCurrencyInfo(curr.id)
                    
                    -- Calculate position for this currency (always, even if info is nil)
                    local currencyX = currencyStartX + ((i - 1) * (currencyItemWidth + currencySpacing))
                    
                    -- Use icon from API response (iconFileID is the correct field)
                    local iconFileID = nil
                    local quantity = 0
                    local maxQuantity = 0
                    local currencyName = curr.name
                    
                    if info then
                        iconFileID = info.iconFileID or info.icon
                        quantity = info.quantity or 0
                        maxQuantity = info.maxQuantity or 0
                        currencyName = info.name or curr.name
                    end
                    
                    -- Fallback icon resolution
                    if not iconFileID then
                        -- Fallback 1: try to get from global storage if available
                        local globalCurrencies = WarbandNexus.GetCurrenciesLegacyFormat and WarbandNexus:GetCurrenciesLegacyFormat() or {}
                        local currData = globalCurrencies[curr.id]
                        if currData and currData.icon then
                            iconFileID = currData.icon
                            if not info then
                                -- Use stored quantity if API info not available
                                if currData.isAccountWide then
                                    quantity = currData.value or 0
                                else
                                    quantity = (currData.chars and currData.chars[currentCharKey]) or 0
                                end
                                maxQuantity = currData.maxQuantity or 0
                            end
                        else
                            -- Fallback 2: use hardcoded icon from CurrencyUI.lua data
                            iconFileID = curr.fallbackIcon
                        end
                    end
                    
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
                        currText:SetWidth(currencyItemWidth + 10)  -- Wider to prevent truncation
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
                        
                        -- Make icon interactive for tooltip
                        currIcon:EnableMouse(true)
                        
                        -- Tooltip on icon hover
                        if ShowTooltip and HideTooltip then
                            currIcon:SetScript("OnEnter", function(self)
                                local tooltipLines = {}
                                
                                if maxQuantity > 0 then
                                    table.insert(tooltipLines, {
                                        text = string.format("Current: %s / %s", FormatNumber(quantity), FormatNumber(maxQuantity)),
                                        color = {1, 1, 1}
                                    })
                                    
                                    local percentage = (quantity / maxQuantity) * 100
                                    local percentColor = {0.5, 1, 0.5}
                                    if percentage >= 100 then
                                        percentColor = {1, 0.3, 0.3}
                                    elseif percentage >= 80 then
                                        percentColor = {1, 0.7, 0.3}
                                    end
                                    table.insert(tooltipLines, {
                                        text = string.format("Progress: %.1f%%", percentage),
                                        color = percentColor
                                    })
                                else
                                    table.insert(tooltipLines, {
                                        text = string.format("Current: %s", FormatNumber(quantity)),
                                        color = {1, 1, 1}
                                    })
                                    table.insert(tooltipLines, {
                                        text = "No cap limit",
                                        color = {0.7, 0.7, 0.7}
                                    })
                                end
                                
                                ShowTooltip(self, {
                                    type = "custom",
                                    title = currencyName or "Currency",
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
            end
            
            summaryCard:Show()
            
            -- Guard: Ensure cardHeight is valid
            if cardHeight and type(cardHeight) == "number" and cardHeight > 0 then
                cardContainer:SetHeight(cardHeight)
                yOffset = yOffset + cardHeight + GetLayout().afterElement
            else
                -- Fallback if cardHeight is invalid
                cardContainer:SetHeight(200)
                yOffset = yOffset + 200 + GetLayout().afterElement
            end
        end
        
        -- Character sections flow directly one after another (like Characters tab)
    end
    
    return yOffset + 20
end

