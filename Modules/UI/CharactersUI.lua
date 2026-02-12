--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local FormatMoney = ns.UI_FormatMoney
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateFactionIcon = ns.UI_CreateFactionIcon
local CreateRaceIcon = ns.UI_CreateRaceIcon
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateClassIcon = ns.UI_CreateClassIcon
local CreateFavoriteButton = ns.UI_CreateFavoriteButton
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local GetColumnOffset = ns.UI_GetColumnOffset
local DrawEmptyState = ns.UI_DrawEmptyState
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateIcon = ns.UI_CreateIcon -- Factory for icons
local FormatNumber = ns.UI_FormatNumber
-- Pooling constants
local AcquireCharacterRow = ns.UI_AcquireCharacterRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

local CHAR_ROW_COLUMNS = ns.UI_CHAR_ROW_COLUMNS
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_HEIGHT = GetLayout().HEADER_HEIGHT or 32
local HEADER_SPACING = GetLayout().headerSpacing or 40
local SECTION_SPACING = GetLayout().betweenSections or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8

--============================================================================
-- EVENT-DRIVEN UI REFRESH
--============================================================================

---Register event listener for character updates
---@param parent Frame Parent frame for event registration
local function RegisterCharacterEvents(parent)
    -- Register only once per parent
    if parent.characterUpdateHandler then
        return
    end
    parent.characterUpdateHandler = true
    
    -- Listen for character data updates (DB-First pattern)
    local Constants = ns.Constants
    WarbandNexus:RegisterMessage(Constants.EVENTS.CHARACTER_UPDATED, function(event, data)
        -- Only refresh if we're currently showing the characters tab
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.currentTab == "chars" then
            DebugPrint("|cff9370DB[WN CharactersUI]|r Character data updated in DB, refreshing UI...")
            WarbandNexus:RefreshUI()
        end
    end)
    
    -- Also listen for tracking changes (immediate UI update needed)
    WarbandNexus:RegisterMessage("WN_CHARACTER_TRACKING_CHANGED", function(event, data)
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.currentTab == "chars" then
            DebugPrint("|cff9370DB[WN CharactersUI]|r Tracking status changed, refreshing UI...")
            WarbandNexus:RefreshUI()
        end
    end)
    
    DebugPrint("|cff00ff00[WN CharactersUI]|r Event listeners registered (WN_CHARACTER_UPDATED, WN_CHARACTER_TRACKING_CHANGED)")
end

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function WarbandNexus:DrawCharacterList(parent)
    self.recentlyExpanded = self.recentlyExpanded or {}
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.characters [LEGACY]"
        if self.db.global.characterCache and next(self.db.global.characterCache.characters or {}) then
            local cacheVersion = self.db.global.characterCache.version or "unknown"
            dataSource = "CharacterCache v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Register event listener (only once)
    RegisterCharacterEvents(parent)
    
    -- Hide empty state card (will be shown again if needed)
    HideEmptyStateCard(parent, "characters")
    
    -- PERFORMANCE: Release pooled frames
    if ReleaseAllPooledChildren then ReleaseAllPooledChildren(parent) end
    
    -- Get current player key
    local currentPlayerKey = ns.Utilities:GetCharacterKey()
    
    -- CRITICAL: Update current character's lastSeen BEFORE fetching characters
    -- (so it shows as "Online" instead of "< 1m ago")
    if self.db.global.characters and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    -- DIRECT DB ACCESS - No RAM cache (API > DB > UI pattern like Reputation/Currency)
    local characters = self:GetAllCharacters()
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Apply visuals (dark background, accent border)
    if ApplyVisuals then
        ApplyVisuals(titleCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Header icon with ring border (standardized system from SharedWidgets)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("characters"))
    headerIcon.border:SetPoint("CENTER", titleCard, "LEFT", 35, 0)  -- Icon centered vertically at 35px from left
    
    -- Create text container (using Factory pattern)
    local titleTextContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
    local titleText = FontManager:CreateFontString(titleTextContainer, "header", "OVERLAY")
    -- Dynamic theme color for title
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. ((ns.L and ns.L["YOUR_CHARACTERS"]) or "Your Characters") .. "|r")
    titleText:SetJustifyH("LEFT")
    
    local subtitleText = FontManager:CreateFontString(titleTextContainer, "subtitle", "OVERLAY")
    subtitleText:SetTextColor(1, 1, 1)
    local trackedFormat = (ns.L and ns.L["CHARACTERS_TRACKED_FORMAT"]) or "%s characters tracked"
    subtitleText:SetText(string.format(trackedFormat, FormatNumber(#characters)))
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts centered in container
    titleText:SetPoint("BOTTOM", titleTextContainer, "CENTER", 0, 0)  -- Title at center
    titleText:SetPoint("LEFT", titleTextContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", titleTextContainer, "CENTER", 0, -4)  -- Subtitle below center
    subtitleText:SetPoint("LEFT", titleTextContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD
    titleTextContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    titleTextContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)
    
    -- NO TRACKING: Static text, never overflows
    
    titleCard:Show()
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    -- ===== WEEKLY PLANNER SECTION REMOVED =====
    
    -- ===== TOTAL GOLD DISPLAY =====
    -- Get current character's gold (only if tracked)
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local currentCharGold = 0
    local isLoadingCharacterData = false
    
    -- Check if character data is being loaded (SaveCharacter in progress)
    if isTracked then
        currentCharGold = GetMoney() or 0
        
        -- Check if character exists in DB (if not, data is being collected)
        if not self.db.global.characters[currentPlayerKey] then
            isLoadingCharacterData = true
        elseif not self.db.global.characters[currentPlayerKey].gold then
            -- Character exists but gold not saved yet (initial scan)
            -- Note: DB stores gold/silver/copper separately, not totalCopper
            isLoadingCharacterData = true
        end
    end
    
    local totalCharGold = 0
    
    for _, char in ipairs(characters) do
        local charGold = ns.Utilities:GetCharTotalCopper(char)
        
        local charKey = (char.name or "") .. "-" .. (char.realm or "")
        if charKey == currentPlayerKey then
            -- Use real-time gold for current character (if tracked)
            totalCharGold = totalCharGold + currentCharGold
        else
            -- Use cached gold for other characters
            totalCharGold = totalCharGold + charGold
        end
    end
    
    local warbandBankGold = ns.Utilities:GetWarbandBankMoney() or 0
    local totalWithWarband = totalCharGold + warbandBankGold
    
    -- Calculate card width for 3 cards in a row (same as Statistics)
    local leftMargin = SIDE_MARGIN
    local rightMargin = SIDE_MARGIN
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
    -- Characters Gold Card (Left)
    local charGoldCard = CreateCard(parent, 90)
    charGoldCard:SetWidth(threeCardWidth)
    charGoldCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(charGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Current Character icon (same as Characters header)
    -- Use factory for standardized card header layout
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    
    local goldDisplayText = isLoadingCharacterData and "|cff888888" .. ((ns.L and ns.L["LOADING"]) or "Loading...") .. "|r" or FormatMoney(currentCharGold, 14)
    
    local cg1Layout = CreateCardHeaderLayout(
        charGoldCard,
        GetCharacterSpecificIcon(),
        40,
        true,
        (ns.L and ns.L["HEADER_CURRENT_CHARACTER"]) or "CURRENT CHARACTER",
        goldDisplayText,
        "subtitle",
        "body"
    )
    
    -- Add inline loading spinner if data is being collected (Factory pattern)
    if isLoadingCharacterData and cg1Layout.value then
        local UI_CreateInlineLoadingSpinner = ns.UI_CreateInlineLoadingSpinner
        if UI_CreateInlineLoadingSpinner then
            charGoldCard.loadingSpinner = UI_CreateInlineLoadingSpinner(
                charGoldCard,
                cg1Layout.value,
                "LEFT",
                cg1Layout.value:GetStringWidth() + 4,
                0,
                16
            )
        end
    else
        -- Cleanup spinner if data loaded
        charGoldCard:SetScript("OnUpdate", nil)
        if charGoldCard.loadingSpinner then
            charGoldCard.loadingSpinner:Hide()
        end
    end
    
    -- NO TRACKING: Numbers rarely overflow (formatted gold)
    
    -- Warband Gold Card (Middle)
    local wbGoldCard = CreateCard(parent, 90)
    wbGoldCard:SetWidth(threeCardWidth)
    wbGoldCard:SetPoint("LEFT", charGoldCard, "RIGHT", cardSpacing, 0)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(wbGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Use factory for standardized card header layout
    local wb1Layout = CreateCardHeaderLayout(
        wbGoldCard,
        "warbands-icon",
        40,
        true,
        (ns.L and ns.L["HEADER_WARBAND_GOLD"]) or "WARBAND GOLD",
        FormatMoney(warbandBankGold, 14),
        "subtitle",
        "body"
    )
    
    -- NO TRACKING: Numbers rarely overflow (formatted gold)
    
    -- Total Gold Card (Right)
    local totalGoldCard = CreateCard(parent, 90)
    totalGoldCard:SetWidth(threeCardWidth)
    totalGoldCard:SetPoint("LEFT", wbGoldCard, "RIGHT", cardSpacing, 0)
    totalGoldCard:SetPoint("RIGHT", -rightMargin, 0)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(totalGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Use factory for standardized card header layout
    local tg1Layout = CreateCardHeaderLayout(
        totalGoldCard,
        "BonusLoot-Chest",
        36,
        true,
        (ns.L and ns.L["HEADER_TOTAL_GOLD"]) or "TOTAL GOLD",
        FormatMoney(totalWithWarband, 14),
        "subtitle",
        "body"
    )
    
    -- NO TRACKING: Numbers rarely overflow (formatted gold)
    
    charGoldCard:Show()
    wbGoldCard:Show()
    totalGoldCard:Show()
    
    yOffset = yOffset + 100
    
    -- ===== SORT CHARACTERS: FAVORITES â†’ REGULAR =====
    local trackedFavorites = {}
    local trackedRegular = {}
    local untracked = {}
    
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        local isTracked = char.isTracked ~= false  -- Default to true if not set (legacy compatibility)
        
        -- Separate by tracking status first, then favorites
        if not isTracked then
            table.insert(untracked, char)
        elseif ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(self, charKey) then
            table.insert(trackedFavorites, char)
        else
            table.insert(trackedRegular, char)
        end
    end
    
    -- Load custom order from profile
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {},
            untracked = {}
        }
    end
    
    -- Sort function (with custom order support)
    local function sortCharacters(list, orderKey)
        local customOrder = self.db.profile.characterOrder[orderKey] or {}
        
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
            -- Default sort: level desc â†’ name asc (ignore table header sorting for now)
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
    
    -- Sort all three groups with custom order
    trackedFavorites = sortCharacters(trackedFavorites, "favorites")
    trackedRegular = sortCharacters(trackedRegular, "regular")
    untracked = sortCharacters(untracked, "untracked")
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local _, height = CreateEmptyStateCard(parent, "characters", yOffset)
        return yOffset + height
    end
    
    -- Initialize collapse state (persistent)
    if not self.db.profile.ui then
        self.db.profile.ui = {}
    end
    if self.db.profile.ui.favoritesExpanded == nil then
        self.db.profile.ui.favoritesExpanded = true
    end
    if self.db.profile.ui.charactersExpanded == nil then
        self.db.profile.ui.charactersExpanded = true
    end
    
    -- ===== FAVORITES SECTION (Always show header) =====
    local favHeader, _, favIcon = CreateCollapsibleHeader(
        parent,
        string.format(((ns.L and ns.L["HEADER_FAVORITES"]) or "Favorites") .. " |cff888888(%s)|r", FormatNumber(#trackedFavorites)),
        "favorites",
        self.charactersExpandAllActive or self.db.profile.ui.favoritesExpanded,
        function(isExpanded)
            self.db.profile.ui.favoritesExpanded = isExpanded
            if isExpanded then self.recentlyExpanded["favorites"] = GetTime() end
            self:RefreshUI()
        end,
        "GM-icon-assistActive-hover",  -- Favorites star atlas icon
        true  -- isAtlas = true
    )
    if favIcon then
        favIcon:SetSize(34, 34)
    end
    favHeader:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    favHeader:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(favHeader, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Remove vertex color tinting for atlas icon
    -- (Atlas icons should use their natural colors)
    
    yOffset = yOffset + HEADER_HEIGHT  -- Header height (32px)
    
    if self.db.profile.ui.favoritesExpanded then
        if #trackedFavorites > 0 then
            for i, char in ipairs(trackedFavorites) do
                -- Calculate actual position in list (not loop index)
                local actualPosition = nil
                for pos, c in ipairs(trackedFavorites) do
                    if c == char then
                        actualPosition = pos
                        break
                    end
                end
                local shouldAnimate = self.recentlyExpanded["favorites"] and (GetTime() - self.recentlyExpanded["favorites"] < 0.5)
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, true, true, trackedFavorites, "favorites", actualPosition, #trackedFavorites, currentPlayerKey, shouldAnimate)
            end
        else
            -- Empty state - anchor to favorites header
            local emptyText = FontManager:CreateFontString(parent, "body", "OVERLAY")
            emptyText:SetPoint("TOP", favHeader, "BOTTOM", 0, -20)  -- 20px padding from header
            emptyText:SetText("|cff999999" .. ((ns.L and ns.L["NO_FAVORITES"]) or "No favorite characters yet. Click the star icon to favorite a character.") .. "|r")
            emptyText:SetWidth(width - 40)
            emptyText:SetJustifyH("CENTER")
            
            yOffset = yOffset + 50  -- Space for empty state message
        end
    end
    
    -- ===== REGULAR CHARACTERS SECTION (Always show header) =====
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    local charHeader = CreateCollapsibleHeader(
        parent,
        string.format(((ns.L and ns.L["HEADER_CHARACTERS"]) or "Characters") .. " |cff888888(%s)|r", FormatNumber(#trackedRegular)),
        "characters",
        self.db.profile.ui.charactersExpanded,
        function(isExpanded)
            self.db.profile.ui.charactersExpanded = isExpanded
            if isExpanded then self.recentlyExpanded["characters"] = GetTime() end
            self:RefreshUI()
        end,
        "GM-icon-headCount", -- New Characters atlas
        true  -- isAtlas = true
    )
    charHeader:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    charHeader:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(charHeader, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    yOffset = yOffset + HEADER_HEIGHT  -- Header height (32px)
    
    if self.db.profile.ui.charactersExpanded then
        if #trackedRegular > 0 then
            for i, char in ipairs(trackedRegular) do
                -- Calculate actual position in list (not loop index)
                local actualPosition = nil
                for pos, c in ipairs(trackedRegular) do
                    if c == char then
                        actualPosition = pos
                        break
                    end
                end
                local shouldAnimate = self.recentlyExpanded["characters"] and (GetTime() - self.recentlyExpanded["characters"] < 0.5)
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, false, true, trackedRegular, "regular", actualPosition, #trackedRegular, currentPlayerKey, shouldAnimate)
            end
        else
            -- Empty state - anchor to characters header
            local emptyText = FontManager:CreateFontString(parent, "body", "OVERLAY")
            emptyText:SetPoint("TOP", charHeader, "BOTTOM", 0, -20)  -- 20px padding from header
            emptyText:SetText("|cff999999" .. ((ns.L and ns.L["ALL_FAVORITED"]) or "All characters are favorited!") .. "|r")
            emptyText:SetWidth(width - 40)
            emptyText:SetJustifyH("CENTER")
            
            yOffset = yOffset + 50  -- Space for empty state message
        end
    end
    
    -- ===== UNTRACKED CHARACTERS SECTION (Only show if untracked characters exist) =====
    if #untracked > 0 then
        -- Initialize collapse state
        if self.db.profile.ui.untrackedExpanded == nil then
            self.db.profile.ui.untrackedExpanded = false  -- Collapsed by default
        end
        
        local untrackedHeader, _, untrackedIcon = CreateCollapsibleHeader(
            parent,
            string.format(((ns.L and ns.L["UNTRACKED_CHARACTERS"]) or "Untracked Characters") .. " |cff888888(%s)|r", FormatNumber(#untracked)),
            "untracked",
            self.db.profile.ui.untrackedExpanded,
            function(isExpanded)
                self.db.profile.ui.untrackedExpanded = isExpanded
                if isExpanded then self.recentlyExpanded["untracked"] = GetTime() end
                self:RefreshUI()
            end,
            "DungeonStoneCheckpointDeactivated",  -- Deactivated checkpoint icon
            true  -- isAtlas = true
        )
        untrackedHeader:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
        untrackedHeader:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
        
        -- Apply visuals with red tint border
        if ApplyVisuals then
            ApplyVisuals(untrackedHeader, {0.08, 0.08, 0.10, 0.95}, {0.8, 0.2, 0.2, 0.6})  -- Red border
        end
        
        yOffset = yOffset + HEADER_HEIGHT
        
        if self.db.profile.ui.untrackedExpanded then
            for i, char in ipairs(untracked) do
                local actualPosition = nil
                for pos, c in ipairs(untracked) do
                    if c == char then
                        actualPosition = pos
                        break
                    end
                end
                local shouldAnimate = self.recentlyExpanded["untracked"] and (GetTime() - self.recentlyExpanded["untracked"] < 0.5)
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, false, true, untracked, "untracked", actualPosition, #untracked, currentPlayerKey, shouldAnimate)
            end
        end
    end
    
    return yOffset
end

--============================================================================
-- DRAW SINGLE CHARACTER ROW
--============================================================================

function WarbandNexus:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey, shouldAnimate)
    -- PERFORMANCE: Acquire from pool
    local row = AcquireCharacterRow(parent)
    row:ClearAllPoints()
    row:SetSize(width, 46)  -- Increased 20% (38 → 46)
    row:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    row:EnableMouse(true)
    
    -- Ensure alpha is reset (pooling safety)
    row:SetAlpha(1)
    
    -- Stop any previous animations
    if row.anim then row.anim:Stop() end
    
    -- Smart Animation
    if shouldAnimate then
        row:SetAlpha(0)
        
        -- Reuse animation objects to prevent leaks
        if not row.anim then
            local anim = row:CreateAnimationGroup()
            local fade = anim:CreateAnimation("Alpha")
            fade:SetSmoothing("OUT")
            anim:SetScript("OnFinished", function() row:SetAlpha(1) end)
            
            row.anim = anim
            row.fade = fade
        end
        
        row.fade:SetFromAlpha(0)
        row.fade:SetToAlpha(1)
        row.fade:SetDuration(0.15)
        row.fade:SetStartDelay(index * 0.05) -- Stagger relative to group start
        
        row.anim:Play()
    end

    -- Define charKey for use in buttons
    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    local isCurrent = (charKey == currentPlayerKey)
    
    -- Set alternating background colors (Factory pattern)
    ns.UI.Factory:ApplyRowBackground(row, index)
    
    -- Class color
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
    
    -- COLUMN 1: Favorite button
    local favOffset = GetColumnOffset("favorite")
    
    if not row.favButton then
        -- Helper creates button, attach to row
        row.favButton = CreateFavoriteButton(row, charKey, isFavorite, CHAR_ROW_COLUMNS.favorite.width, "LEFT", favOffset + (CHAR_ROW_COLUMNS.favorite.spacing / 2), 0, nil)
        row.favButton.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
        -- Note: callback set below
    end
    -- Update state
    row.favButton.charKey = charKey
    row.favButton:SetChecked(isFavorite)
    
    -- Safely set OnClick (favButton should be a Button type)
    if row.favButton.HasScript and row.favButton:HasScript("OnClick") then
        row.favButton:SetScript("OnClick", function(btn)
            local newStatus = false
            if ns.CharacterService then
                newStatus = ns.CharacterService:ToggleFavoriteCharacter(WarbandNexus, charKey)
            end
            WarbandNexus:RefreshUI()
            return newStatus
        end)
    end
    
    -- Tooltip for favorite button
    if ShowTooltip and row.favButton.SetScript then
        row.favButton:SetScript("OnEnter", function(self)
            local isFav = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey)
            ShowTooltip(self, {
                type = "custom",
                icon = "Interface\\Icons\\Achievement_GuildPerk_HappyHour",
                title = isFav and ((ns.L and ns.L["REMOVE_FROM_FAVORITES"]) or "Remove from Favorites") or ((ns.L and ns.L["ADD_TO_FAVORITES"]) or "Add to Favorites"),
                description = (ns.L and ns.L["FAVORITES_TOOLTIP"]) or "Favorite characters appear at the top of the list",
                lines = {
                    {text = "|cff00ff00" .. ((ns.L and ns.L["CLICK_TO_TOGGLE"]) or "Click to toggle") .. "|r", color = {1, 1, 1}}
                },
                anchor = "ANCHOR_RIGHT"
            })
        end)
        
        row.favButton:SetScript("OnLeave", function(self)
            if HideTooltip then
                HideTooltip()
            end
        end)
    end
    
    
    -- Icon border color (accent) — used for profession icons
    local iconBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    
    -- COLUMN 2: Faction icon
    local factionOffset = GetColumnOffset("faction")
    if char.faction then
        if not row.factionIcon then
            row.factionIcon = CreateFactionIcon(row, char.faction, CHAR_ROW_COLUMNS.faction.width, "LEFT", factionOffset + (CHAR_ROW_COLUMNS.faction.spacing / 2), 0)
        end
        if char.faction == "Alliance" then
            row.factionIcon:SetAtlas("AllianceEmblem")
        elseif char.faction == "Horde" then
            row.factionIcon:SetAtlas("HordeEmblem")
        else
            row.factionIcon:SetAtlas("bfa-landingbutton-alliance-up")
        end
        row.factionIcon:Show()
    elseif row.factionIcon then
        row.factionIcon:Hide()
    end
    
    
    -- COLUMN 3: Race icon
    local raceOffset = GetColumnOffset("race")
    if char.raceFile then
        if not row.raceIcon then
            row.raceIcon = CreateRaceIcon(row, char.raceFile, char.gender, CHAR_ROW_COLUMNS.race.width, "LEFT", raceOffset + (CHAR_ROW_COLUMNS.race.spacing / 2), 0)
        end
        local raceAtlas = ns.UI_GetRaceGenderAtlas(char.raceFile, char.gender)
        row.raceIcon:SetAtlas(raceAtlas)
        row.raceIcon:Show()
    elseif row.raceIcon then
        row.raceIcon:Hide()
    end
    
    
    -- COLUMN 4: Class icon
    local classOffset = GetColumnOffset("class")
    if char.classFile then
        if not row.classIcon then
            row.classIcon = CreateClassIcon(row, char.classFile, CHAR_ROW_COLUMNS.class.width, "LEFT", classOffset + (CHAR_ROW_COLUMNS.class.spacing / 2), 0)
        end
        row.classIcon:SetAtlas("classicon-" .. char.classFile)
        row.classIcon:Show()
    elseif row.classIcon then
        row.classIcon:Hide()
    end
    
    
    -- COLUMN 5: Name
    local nameOffset = GetColumnOffset("name")
    local nameLeftPadding = 4
    
    if not row.nameText then
        row.nameText = FontManager:CreateFontString(row, "subtitle", "OVERLAY")
        row.nameText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -8)
        row.nameText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        row.nameText:SetMaxLines(1)
    end
    row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")))
        
    if not row.realmText then
        row.realmText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.realmText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -23)
        row.realmText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.realmText:SetMaxLines(1)  -- Single line only
        row.realmText:SetTextColor(1, 1, 1)
    end
    row.realmText:SetText("|cffffffff" .. (char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")) .. "|r")
    
    
    -- COLUMN 6: Level
    local levelOffset = GetColumnOffset("level")
    if not row.levelText then
        row.levelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.levelText:SetPoint("LEFT", levelOffset, 0)
        row.levelText:SetWidth(CHAR_ROW_COLUMNS.level.width)
        row.levelText:SetJustifyH("CENTER")
        row.levelText:SetMaxLines(1)  -- Single line only
    end
    row.levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.level or 1))
    
    
    -- COLUMN 7: Item Level
    local itemLevelOffset = GetColumnOffset("itemLevel")
    if not row.itemLevelText then
        row.itemLevelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
        row.itemLevelText:SetWidth(CHAR_ROW_COLUMNS.itemLevel.width)
        row.itemLevelText:SetJustifyH("CENTER")
        row.itemLevelText:SetMaxLines(1)  -- Single line only
    end
    local itemLevel = char.itemLevel or 0
    if itemLevel > 0 then
        row.itemLevelText:SetText(string.format("|cffffd700%s %d|r", (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", itemLevel))
    else
        row.itemLevelText:SetText("|cff666666--|r")
    end
    
    
    -- COLUMN 8: Gold
    local goldOffset = GetColumnOffset("gold")
    if not row.goldText then
        row.goldText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.goldText:SetPoint("LEFT", goldOffset, 0)
        row.goldText:SetWidth(CHAR_ROW_COLUMNS.gold.width)
        row.goldText:SetJustifyH("RIGHT")
        row.goldText:SetMaxLines(1)  -- Single line only
    end
    local totalCopper = ns.Utilities:GetCharTotalCopper(char)
    row.goldText:SetText(FormatMoney(totalCopper, 12))
    
    
    -- COLUMN 9: Professions (Dynamic)
    local profOffset = GetColumnOffset("professions")
    if not row.profIcons then row.profIcons = {} end
    
    -- Hide all existing profession icons first
    for _, icon in ipairs(row.profIcons) do icon:Hide() end
    
    if char.professions then
        local iconSize = 39  -- Increased 15% (34 → 39)
        local iconSpacing = 5  -- Icon spacing
        
        -- Count total professions first
        local numProfs = 0
        if char.professions[1] then numProfs = numProfs + 1 end
        if char.professions[2] then numProfs = numProfs + 1 end
        local secondaries = {"cooking", "fishing", "archaeology"}
        for _, sec in ipairs(secondaries) do
            if char.professions[sec] then numProfs = numProfs + 1 end
        end
        
        -- Calculate centered starting position (within column content area, excluding right spacing)
        local profColumnWidth = CHAR_ROW_COLUMNS.professions.width  -- Content width only
        local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * iconSpacing)
        -- Center the icons within the column width
        local leftPadding = (profColumnWidth - totalIconWidth) / 2
        local currentProfX = profOffset + leftPadding
        
        local charKey = char._key or ((char.name or "") .. "-" .. (char.realm or ""))
        local function SetupProfIcon(prof, idx, profSlotKey)
            if not prof or not prof.icon then return end
            
            -- Reuse or create (with accent border)
            local pFrame = row.profIcons[idx]
            if not pFrame then
                pFrame = CreateIcon(row, nil, iconSize, false, iconBorderColor, false)
                pFrame:EnableMouse(true)
                pFrame.icon = pFrame.texture
                
                row.profIcons[idx] = pFrame
            end
            
            -- Clear previous position and set new centered position
            pFrame:ClearAllPoints()
            pFrame:SetPoint("LEFT", currentProfX, 0)
            pFrame.icon:SetTexture(prof.icon)
            pFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Crop default WoW icon border
            pFrame:Show()
            
            -- Unspent knowledge badge (yellow dot)
            local profName = prof.name
            local kd = profName and char.knowledgeData and char.knowledgeData[profName]
            if kd and kd.unspentPoints and kd.unspentPoints > 0 then
                if not pFrame.knowledgeBadge then
                    local badge = pFrame:CreateTexture(nil, "OVERLAY")
                    badge:SetSize(16, 16)
                    badge:SetPoint("TOPRIGHT", pFrame, "TOPRIGHT", 5, 0)
                    badge:SetAtlas("icons_64x64_important")
                    pFrame.knowledgeBadge = badge
                end
                pFrame.knowledgeBadge:Show()
            else
                if pFrame.knowledgeBadge then
                    pFrame.knowledgeBadge:Hide()
                end
            end
            
            -- Profession detail is now shown automatically when WoW's profession UI opens.
            -- No click action needed on these icons.
            pFrame:SetScript("OnMouseUp", nil)
            
            -- Setup tooltip with detailed information (expansion skills + knowledge + concentration)
            pFrame:SetScript("OnEnter", function(self)
                local profName = prof.name or ((ns.L and ns.L["UNKNOWN_PROFESSION"]) or "Unknown Profession")
                local lines = {}

                -- ====== SECTION 1: Expansion sub-professions (skill levels) ======
                local expansions = char.professionExpansions and char.professionExpansions[profName]
                if expansions and #expansions > 0 then
                    for _, exp in ipairs(expansions) do
                        local skillColor
                        local maxSkill = exp.maxSkillLevel or 0
                        local curSkill = exp.skillLevel or 0

                        if maxSkill > 0 and curSkill >= maxSkill then
                            skillColor = {0.3, 0.9, 0.3}
                        elseif curSkill > 0 then
                            skillColor = {1.0, 0.82, 0.0}
                        else
                            skillColor = {0.4, 0.4, 0.4}
                        end

                        local skillText
                        if maxSkill > 0 then
                            skillText = string.format("%d / %d", curSkill, maxSkill)
                        else
                            skillText = "—"
                        end

                        lines[#lines + 1] = {
                            left = exp.name or "?",
                            right = skillText,
                            leftColor = {1, 1, 1},
                            rightColor = skillColor
                        }
                    end
                else
                    -- Fallback: no expansion data yet, show basic skill
                    if prof.skill and prof.maxSkill then
                        lines[#lines + 1] = {
                            left = profName,
                            right = string.format("%d / %d", prof.skill, prof.maxSkill),
                            leftColor = {1, 1, 1},
                            rightColor = {0.3, 0.9, 0.3}
                        }
                    end
                end

                -- ====== SECTION 2: Knowledge Data (C_Traits) ======
                local kd = char.knowledgeData and char.knowledgeData[profName]
                if kd then
                    -- Spacer
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }

                    local unspent = kd.unspentPoints or 0
                    local spent = kd.spentPoints or 0
                    local maxPts = kd.maxPoints or 0
                    local cName = kd.currencyName or "Knowledge"

                    -- Collectible (remaining earnable)
                    if maxPts > 0 then
                        local collectible = maxPts - unspent - spent
                        if collectible > 0 then
                            lines[#lines + 1] = {
                                left = "Collectible",
                                right = tostring(collectible),
                                leftColor = {1, 1, 1},
                                rightColor = {0.3, 0.9, 0.3}
                            }
                        end
                    end

                    -- Unspent knowledge points alert
                    if unspent > 0 then
                        lines[#lines + 1] = {
                            left = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. unspent .. " Unspent Points",
                            leftColor = {1, 0.82, 0}
                        }
                    end
                end

                -- ====== SECTION 3: Concentration ======
                local concData = char.concentration and char.concentration[profName]
                if concData and concData.max and concData.max > 0 then
                    -- Spacer
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }

                    -- Estimate current concentration (passive regen since snapshot)
                    local estimated = concData.current or 0
                    if WarbandNexus and WarbandNexus.GetEstimatedConcentration then
                        estimated = WarbandNexus:GetEstimatedConcentration(concData)
                    end

                    local concColor = {1, 1, 1}
                    if estimated >= concData.max then
                        concColor = {0.3, 0.9, 0.3}
                    elseif estimated > 0 then
                        concColor = {1, 0.82, 0}
                    end

                    local concText = string.format("%d / %d", estimated, concData.max)

                    lines[#lines + 1] = {
                        left = "Concentration",
                        right = concText,
                        leftColor = {1, 1, 1},
                        rightColor = concColor
                    }

                    -- Recharge timer (white label, yellow duration)
                    if estimated < concData.max and WarbandNexus and WarbandNexus.GetConcentrationTimeToFull then
                        local timeStr = WarbandNexus:GetConcentrationTimeToFull(concData)
                        if timeStr and timeStr ~= "" and timeStr ~= "Full" then
                            lines[#lines + 1] = {
                                left = "Recharge",
                                right = timeStr,
                                leftColor = {1, 1, 1},
                                rightColor = {1, 0.82, 0}
                            }
                        end
                    end
                end

                if not ShowTooltip then
                    -- Fallback: Use TooltipService
                    local tooltipLines = {}
                    for _, line in ipairs(lines) do
                        if line.right then
                            tooltipLines[#tooltipLines + 1] = {
                                text = (line.left or "") .. "  " .. (line.right or ""),
                                color = line.rightColor or line.leftColor or {1, 1, 1}
                            }
                        elseif line.left and line.left ~= " " then
                            tooltipLines[#tooltipLines + 1] = {
                                text = line.left,
                                color = line.leftColor or {1, 1, 1}
                            }
                        end
                    end
                    ns.TooltipService:Show(self, {
                        type = "custom",
                        icon = prof.icon,
                        title = profName,
                        lines = tooltipLines,
                    })
                    return
                end

                ShowTooltip(self, {
                    type = "custom",
                    icon = prof.icon,
                    title = profName,
                    lines = lines,
                    anchor = "ANCHOR_RIGHT"
                })
            end)
            pFrame:SetScript("OnLeave", function(self)
                if HideTooltip then
                    HideTooltip()
                else
                    ns.TooltipService:Hide()
                end
            end)
            
            return true
        end
        
        local pIdx = 1
        -- Primary
        if char.professions[1] then
            SetupProfIcon(char.professions[1], pIdx, 1)
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        if char.professions[2] then
            SetupProfIcon(char.professions[2], pIdx, 2)
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        -- Secondary
        for _, sec in ipairs(secondaries) do
            if char.professions[sec] then
                SetupProfIcon(char.professions[sec], pIdx, sec)
                pIdx = pIdx + 1
                currentProfX = currentProfX + iconSize + iconSpacing
            end
        end
    end
    
    
    -- COLUMN 10: Mythic Keystone (REDESIGNED - Simple & Symmetric)
    local mythicKeyOffset = GetColumnOffset("mythicKey")
    
    -- Create keystone icon (shared for has-key and no-key)
    if not row.keystoneIcon then
        row.keystoneIcon = row:CreateTexture(nil, "ARTWORK")
        row.keystoneIcon:SetPoint("LEFT", mythicKeyOffset + 5, 0)  -- 5px padding from column edge
        row.keystoneIcon:SetSize(24, 24)  -- Increased 20% (20 → 24)
        
        -- Use atlas with fallback
        local atlasInfo = C_Texture.GetAtlasInfo("ChromieTime-32x32")
        if atlasInfo then
            row.keystoneIcon:SetAtlas("ChromieTime-32x32", true)
        else
            row.keystoneIcon:SetTexture(525134)  -- Fallback to item texture
            row.keystoneIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    
    -- Create keystone text (shared for has-key and no-key)
    if not row.keystoneText then
        row.keystoneText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)  -- Icon(24) + gap(5) + padding(5)
        row.keystoneText:SetWidth(CHAR_ROW_COLUMNS.mythicKey.width - 30)
        row.keystoneText:SetJustifyH("LEFT")
        row.keystoneText:SetWordWrap(false)
        row.keystoneText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.keystoneText:SetMaxLines(1)  -- Single line only
    end
    
    -- Format content based on keystone status
    if char.mythicKey and char.mythicKey.level and char.mythicKey.level > 0 then
        -- HAS KEY: +Level • Dungeon (colored, bright icon)
        local dungeonAbbrev = char.mythicKey.dungeonName:sub(1, 4):upper()
        local keystoneText = string.format("|cffff8000+%d|r |cff999999•|r |cffffd700%s|r", 
            char.mythicKey.level, dungeonAbbrev)
        
        row.keystoneText:SetText(keystoneText)
        
        -- Bright, colored icon
        row.keystoneIcon:SetDesaturated(false)
        row.keystoneIcon:SetVertexColor(1, 1, 1)
        row.keystoneIcon:SetAlpha(1.0)
    else
        -- NO KEY: +0 • None (dimmed, desaturated icon)
        local keystoneText = "|cff888888+0|r |cff666666•|r |cffaaaaaa" .. ((ns.L and ns.L["NONE_LABEL"]) or "None") .. "|r"
        
        row.keystoneText:SetText(keystoneText)
        
        -- Dimmed, desaturated icon
        row.keystoneIcon:SetDesaturated(true)
        row.keystoneIcon:SetVertexColor(0.6, 0.6, 0.6)
        row.keystoneIcon:SetAlpha(0.4)
    end
    
    row.keystoneIcon:Show()
    row.keystoneText:Show()
    
    -- Tracking Status Icon (left of Reorder column)
    local isTracked = char.isTracked ~= false  -- Default to true if not set
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    local rowCharKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    local isCurrentCharacter = (currentCharKey == rowCharKey)
    
    -- RIGHT-ANCHORED COLUMNS: compact, icon-sized, flush right
    -- Layout from right: [Delete 24px] 6px [LastSeen 60px] 6px [Reorder 44px] 6px [Track 24px]
    local R_MARGIN = 6   -- Right edge margin
    local R_GAP = 6      -- Gap between right-side columns
    local deleteRight = R_MARGIN                                                           -- 6
    local lastSeenRight = deleteRight + CHAR_ROW_COLUMNS.delete.width + R_GAP              -- 36
    local reorderRight = lastSeenRight + CHAR_ROW_COLUMNS.lastSeen.width + R_GAP           -- 102
    local trackRight = reorderRight + CHAR_ROW_COLUMNS.reorder.width + R_GAP               -- 152
    
    if not row.trackingIcon then
        -- Use Factory pattern (same as Reorder buttons)
        row.trackingIcon = ns.UI.Factory:CreateButton(row, 24, 24, {0, 0, 0, 0}, nil, true)  -- Transparent bg, no border
        row.trackingIcon.isPersistentRowElement = true
    end
    row.trackingIcon:ClearAllPoints()
    row.trackingIcon:SetPoint("CENTER", row, "RIGHT", -(trackRight + 12), 0)
    
    if isTracked then
        -- Tracked: Show green checkpoint
        row.trackingIcon:SetNormalAtlas("DungeonStoneCheckpoint")
        row.trackingIcon:SetAlpha(isCurrentCharacter and 1 or 0.3)  -- Dim if not current character
        
        -- Tooltip
        row.trackingIcon:SetScript("OnEnter", function(self)
            if ShowTooltip then
                local tooltipLines = {
                    {text = (ns.L and ns.L["CHARACTER_IS_TRACKED"]) or "This character is being tracked.", color = {0, 1, 0}},
                    {text = (ns.L and ns.L["TRACKING_ACTIVE_DESC"]) or "Data collection and updates are active.", color = {1, 1, 1}},
                }
                
                if isCurrentCharacter then
                    table.insert(tooltipLines, {text = " ", color = {1, 1, 1}})
                    table.insert(tooltipLines, {text = (ns.L and ns.L["CLICK_DISABLE_TRACKING"]) or "Click to disable tracking.", color = {1, 0.8, 0}})
                else
                    table.insert(tooltipLines, {text = " ", color = {1, 1, 1}})
                    table.insert(tooltipLines, {text = (ns.L and ns.L["MUST_LOGIN_TO_CHANGE"]) or "You must log in to this character to change tracking.", color = {1, 0.5, 0.5}})
                end
                
                ShowTooltip(self, {
                    type = "custom",
                    icon = "Interface\\Icons\\Spell_ChargePositive",
                    title = (ns.L and ns.L["TRACKING_ENABLED"]) or "Tracking Enabled",
                    titleColor = {0, 1, 0},
                    lines = tooltipLines,
                    anchor = "ANCHOR_TOP"
                })
            end
        end)
        row.trackingIcon:SetScript("OnLeave", function(self)
            if HideTooltip then HideTooltip() end
        end)
        
        -- Only clickable for current character
        if isCurrentCharacter then
            row.trackingIcon:Enable()
            row.trackingIcon:SetScript("OnClick", function(self)
                local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                local charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
                if ns.CharacterService then
                    ns.CharacterService:ShowTrackingChangeConfirmation(WarbandNexus, charKey, charName, false)
                end
            end)
        else
            row.trackingIcon:Disable()
            row.trackingIcon:SetScript("OnClick", nil)
        end
    else
        -- Untracked: Show deactivated checkpoint
        row.trackingIcon:SetNormalAtlas("DungeonStoneCheckpointDeactivated")
        row.trackingIcon:SetAlpha(isCurrentCharacter and 0.6 or 0.3)  -- Dim if not current character
        
        -- Tooltip
        row.trackingIcon:SetScript("OnEnter", function(self)
            if ShowTooltip then
                local tooltipLines = {}
                
                if isCurrentCharacter then
                    table.insert(tooltipLines, {text = (ns.L and ns.L["CLICK_ENABLE_TRACKING"]) or "Click to enable tracking for this character.", color = {1, 0.8, 0}})
                    table.insert(tooltipLines, {text = (ns.L and ns.L["TRACKING_WILL_BEGIN"]) or "Data collection will begin immediately.", color = {1, 1, 1}})
                else
                    table.insert(tooltipLines, {text = (ns.L and ns.L["CHARACTER_NOT_TRACKED"]) or "This character is not being tracked.", color = {1, 0.5, 0.5}})
                    table.insert(tooltipLines, {text = " ", color = {1, 1, 1}})
                    table.insert(tooltipLines, {text = (ns.L and ns.L["MUST_LOGIN_TO_ENABLE"]) or "You must log in to this character to enable tracking.", color = {1, 0.5, 0.5}})
                end
                
                ShowTooltip(self, {
                    type = "custom",
                    icon = "Interface\\Icons\\Spell_ChargeNegative",
                    title = (ns.L and ns.L["ENABLE_TRACKING"]) or "Enable Tracking",
                    titleColor = {1, 0.8, 0},
                    lines = tooltipLines,
                    anchor = "ANCHOR_TOP"
                })
            end
        end)
        row.trackingIcon:SetScript("OnLeave", function(self)
            if HideTooltip then HideTooltip() end
        end)
        
        -- Only clickable for current character
        if isCurrentCharacter then
            row.trackingIcon:Enable()
            row.trackingIcon:SetScript("OnClick", function(self)
                local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
                local charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
                if ns.CharacterService then
                    ns.CharacterService:ShowTrackingChangeConfirmation(WarbandNexus, charKey, charName, true)
                end
            end)
        else
            row.trackingIcon:Disable()
            row.trackingIcon:SetScript("OnClick", nil)
        end
    end
    
    row.trackingIcon:Show()
    
    -- Reorder Buttons (right-aligned column, centered content)
    if not row.reorderButtons then
        local rb = ns.UI.Factory:CreateContainer(row, CHAR_ROW_COLUMNS.reorder.width, 46)
        rb:SetAlpha(0.7)
        rb.isPersistentRowElement = true
        
        rb.up = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        rb.up:SetPoint("CENTER", -11, 0)
        rb.up:SetNormalAtlas("housing-floor-arrow-up-default")
        
        rb.down = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        rb.down:SetPoint("CENTER", 11, 0)
        rb.down:SetNormalAtlas("housing-floor-arrow-down-default")
        
        row.reorderButtons = rb
    end
    row.reorderButtons:ClearAllPoints()
    row.reorderButtons:SetPoint("RIGHT", -reorderRight, 0)
    
    if showReorder and charList then
        row.reorderButtons:Show()
        
        -- Check if buttons support OnClick
        
        -- Safely set OnClick handlers
        if row.reorderButtons.up and row.reorderButtons.up.HasScript and row.reorderButtons.up:HasScript("OnClick") then
            row.reorderButtons.up:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, -1) end)
        end
        
        if row.reorderButtons.down and row.reorderButtons.down.HasScript and row.reorderButtons.down:HasScript("OnClick") then
            row.reorderButtons.down:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, 1) end)
        end
    else
        row.reorderButtons:Hide()
        -- Clear scripts when hiding to prevent stale handlers
        if row.reorderButtons.up and row.reorderButtons.up.HasScript and row.reorderButtons.up:HasScript("OnClick") then
            row.reorderButtons.up:SetScript("OnClick", nil)
        end
        if row.reorderButtons.down and row.reorderButtons.down.HasScript and row.reorderButtons.down:HasScript("OnClick") then
            row.reorderButtons.down:SetScript("OnClick", nil)
        end
    end
    
    
    -- COLUMN: Last Seen (RIGHT-anchored, compact)
    if isCurrent then
        if not row.onlineText then
            row.onlineText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.onlineText:SetWidth(CHAR_ROW_COLUMNS.lastSeen.width)
            row.onlineText:SetJustifyH("CENTER")
            row.onlineText:SetText((ns.L and ns.L["ONLINE"]) or "Online")
            row.onlineText:SetTextColor(0, 1, 0) 
        end
        row.onlineText:ClearAllPoints()
        row.onlineText:SetPoint("RIGHT", -lastSeenRight, 0)
        row.onlineText:Show()
        if row.lastSeenText then row.lastSeenText:Hide() end
    else
        if row.onlineText then row.onlineText:Hide() end
        
        local timeDiff = char.lastSeen and (time() - char.lastSeen) or math.huge
        
        if not row.lastSeenText then
            row.lastSeenText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.lastSeenText:SetWidth(CHAR_ROW_COLUMNS.lastSeen.width)
            row.lastSeenText:SetJustifyH("CENTER")
        end
        row.lastSeenText:ClearAllPoints()
        row.lastSeenText:SetPoint("RIGHT", -lastSeenRight, 0)
        
        local lastSeenStr = ""
        if timeDiff < 60 then
            lastSeenStr = (ns.L and ns.L["TIME_LESS_THAN_MINUTE"]) or "< 1m ago"
        elseif timeDiff < 3600 then
            local minutesFormat = (ns.L and ns.L["TIME_MINUTES_FORMAT"]) or "%dm ago"
            lastSeenStr = string.format(minutesFormat, math.floor(timeDiff / 60))
        elseif timeDiff < 86400 then
            local hoursFormat = (ns.L and ns.L["TIME_HOURS_FORMAT"]) or "%dh ago"
            lastSeenStr = string.format(hoursFormat, math.floor(timeDiff / 3600))
        else
            local daysFormat = (ns.L and ns.L["TIME_DAYS_FORMAT"]) or "%dd ago"
            lastSeenStr = string.format(daysFormat, math.floor(timeDiff / 86400))
        end
        row.lastSeenText:SetText(lastSeenStr)
        row.lastSeenText:SetTextColor(1, 1, 1)
        row.lastSeenText:Show()
    end
    
    
    -- COLUMN: Delete button (RIGHT-anchored, compact)
    if not isCurrent then
        if not row.deleteBtn then
            local deleteBtn = ns.UI.Factory:CreateButton(row, 24, 24, true)
            deleteBtn.isPersistentRowElement = true
            
            -- Add icon texture
            local icon = deleteBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            icon:SetDesaturated(true)
            icon:SetVertexColor(0.8, 0.2, 0.2)
            deleteBtn.texture = icon
            deleteBtn.icon = icon
            
            row.deleteBtn = deleteBtn
        end
        row.deleteBtn:ClearAllPoints()
        row.deleteBtn:SetPoint("CENTER", row, "RIGHT", -(deleteRight + 12), 0)
        
        row.deleteBtn.charKey = charKey
        row.deleteBtn.charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        
        -- Safely set OnClick
        if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
            row.deleteBtn:SetScript("OnClick", function(self)
                -- Use custom themed delete dialog
                local charKey = self.charKey
                local charName = self.charName
                
                -- Get UI functions from namespace
                local COLORS = ns.UI_COLORS
                local CreateExternalWindow = ns.UI_CreateExternalWindow
                local CreateThemedButton = ns.UI_CreateThemedButton
                local FontManager = ns.FontManager
                
                if not CreateExternalWindow then
                    DebugPrint("[WarbandNexus] ERROR: CreateExternalWindow not found!")
                    return
                end
                
                -- Create custom delete confirmation dialog
                local dialog, contentFrame = CreateExternalWindow({
                    name = "DeleteCharacterDialog",
                    title = (ns.L and ns.L["DELETE_CHARACTER_TITLE"]) or "Delete Character?",
                    icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
                    width = 420,
                    height = 180,
                })
                
                if not dialog then
                    DebugPrint("[WarbandNexus] ERROR: Failed to create delete dialog!")
                    return
                end
                
                -- Warning text
                local warning = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                warning:SetPoint("TOP", contentFrame, "TOP", 0, -20)
                warning:SetWidth(380)
                warning:SetJustifyH("CENTER")
                warning:SetTextColor(1, 0.85, 0.1)  -- Gold/Orange
                local confirmDeleteFmt = (ns.L and ns.L["CONFIRM_DELETE"]) or "Are you sure you want to delete |cff00ccff%s|r?"
                warning:SetText(string.format(confirmDeleteFmt, charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")))
                
                local subtext = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                subtext:SetPoint("TOP", warning, "BOTTOM", 0, -10)
                subtext:SetWidth(380)
                subtext:SetJustifyH("CENTER")
                subtext:SetTextColor(1, 0.3, 0.3)  -- Red
                local cannotUndoText = (ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!"
                subtext:SetText("|cffff0000" .. cannotUndoText .. "|r")
                
                -- Buttons container (using Factory pattern)
                local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, 320, 40)
                btnContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 20)
                
                -- Delete button (LEFT)
                local deleteBtnLabel = (ns.L and ns.L["DELETE"]) or "Delete"
                local deleteBtn = CreateThemedButton and CreateThemedButton(btnContainer, deleteBtnLabel, 150, 36) or CreateFrame("Button", nil, btnContainer)
                if not CreateThemedButton then
                    deleteBtn:SetSize(150, 36)
                    deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
                    deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
                    deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
                    
                    local deleteBtnText = deleteBtn:CreateFontString(nil, "OVERLAY")
                    deleteBtnText:SetPoint("CENTER")
                    FontManager:SafeSetFont(deleteBtnText, "body")
                    deleteBtnText:SetText(deleteBtnLabel)
                end
                deleteBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
                deleteBtn:SetScript("OnClick", function()
                    local success = WarbandNexus:DeleteCharacter(charKey)
                    if success and WarbandNexus.RefreshUI then 
                        WarbandNexus:RefreshUI() 
                    end
                    dialog:Hide()
                end)
                
                -- Cancel button (RIGHT)
                local cancelBtnLabel = (ns.L and ns.L["CANCEL"]) or "Cancel"
                local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, cancelBtnLabel, 150, 36) or CreateFrame("Button", nil, btnContainer)
                if not CreateThemedButton then
                    cancelBtn:SetSize(150, 36)
                    cancelBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
                    cancelBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
                    cancelBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
                    
                    local cancelBtnText = cancelBtn:CreateFontString(nil, "OVERLAY")
                    cancelBtnText:SetPoint("CENTER")
                    FontManager:SafeSetFont(cancelBtnText, "body")
                    cancelBtnText:SetText(cancelBtnLabel)
                end
                cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
                cancelBtn:SetScript("OnClick", function()
                    dialog:Hide()
                end)
                
                -- Cleanup on hide (prevent stale references)
                dialog:SetScript("OnHide", function(self)
                    self:SetScript("OnHide", nil)
                    self:SetParent(nil)
                end)
                
                -- Show dialog
                dialog:Show()
            end)
        end
        
        -- Tooltip for delete button
        if ShowTooltip and row.deleteBtn.SetScript then
            row.deleteBtn:SetScript("OnEnter", function(self)
                local removeFromTrackingFmt = (ns.L and ns.L["REMOVE_FROM_TRACKING_FORMAT"]) or "Remove %s from tracking"
                ShowTooltip(self, {
                    type = "custom",
                    icon = "Interface\\Icons\\Spell_Shadow_SacrificialShield",
                    title = (ns.L and ns.L["DELETE_CHARACTER"]) or "Delete Character",
                    titleColor = {1, 0.4, 0},
                    description = string.format(removeFromTrackingFmt, self.charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")),
                    lines = {
                        {text = "|cffff0000" .. ((ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!") .. "|r", color = {1, 0.2, 0.2}},
                        {type = "spacer"},
                        {text = "|cff00ff00" .. ((ns.L and ns.L["CLICK_TO_DELETE"]) or "Click to delete") .. "|r", color = {1, 1, 1}}
                    },
                    anchor = "ANCHOR_LEFT"
                })
            end)
            
            row.deleteBtn:SetScript("OnLeave", function(self)
                if HideTooltip then
                    HideTooltip()
                end
            end)
        end
        
        row.deleteBtn:Show()
    else
        if row.deleteBtn then
            row.deleteBtn:Hide()
            -- Clear OnClick when hiding
            if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
                row.deleteBtn:SetScript("OnClick", nil)
            end
        end
    end
    
    return yOffset + 46 + GetLayout().betweenRows  -- Updated from 38 to 46 (20% increase)
end


--============================================================================
-- REORDER CHARACTER IN LIST
--============================================================================

function WarbandNexus:ReorderCharacter(char, charList, listKey, direction)
    if not char or not listKey then
        return
    end
    
    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    
    -- Don't update lastSeen when reordering (keep current timestamps)
    local currentPlayerKey = ns.Utilities:GetCharacterKey()
    
    -- Get or initialize custom order
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {}
        }
    end
    
    if not self.db.profile.characterOrder[listKey] then
        self.db.profile.characterOrder[listKey] = {}
    end
    
    local customOrder = self.db.profile.characterOrder[listKey]
    
    -- If no custom order exists, create one from ALL characters in this category
    if #customOrder == 0 then
        -- Get all characters and rebuild the list for this category
        local allChars = self:GetAllCharacters()
        local currentPlayerKey = ns.Utilities:GetCharacterKey()
        
        for _, c in ipairs(allChars) do
            local key = (c.name or "Unknown") .. "-" .. (c.realm or "Unknown")
            -- Skip current player
            if key ~= currentPlayerKey then
                local isFav = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(self, key)
                -- Add to appropriate list
                if (listKey == "favorites" and isFav) or (listKey == "regular" and not isFav) then
                    table.insert(customOrder, key)
                end
            end
        end
    end
    
    -- Find current index in custom order
    local currentIndex = nil
    for i, key in ipairs(customOrder) do
        if key == charKey then
            currentIndex = i
            break
        end
    end
    
    if not currentIndex then 
        -- Character not in custom order, add it
        table.insert(customOrder, charKey)
        currentIndex = #customOrder
    end
    
    -- Calculate new index
    local newIndex = currentIndex + direction
    
    if newIndex < 1 or newIndex > #customOrder then
        return
    end
    
    -- Swap in custom order
    customOrder[currentIndex], customOrder[newIndex] = customOrder[newIndex], customOrder[currentIndex]
    
    -- Save and refresh
    self.db.profile.characterOrder[listKey] = customOrder
    
    -- Ensure current character's lastSeen stays as "now"
    if self.db.global.characters and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    self:RefreshUI()
end
