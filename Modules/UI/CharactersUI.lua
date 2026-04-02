--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Unique AceEvent handler identity for CharactersUI
local CharactersUIEvents = {}

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

local CHAR_ROW_COLUMNS = ns.UI_CHAR_ROW_COLUMNS

-- Canonical character key (Utilities only; no manual key construction).
local function GetCharKey(char)
    if char and char._key then return char._key end
    if not ns.Utilities or not ns.Utilities.GetCharacterKey then return nil end
    return ns.Utilities:GetCharacterKey(char and char.name or "Unknown", char and char.realm or "Unknown")
end
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

local function BuildGuildText(char, isCurrentCharacter)
    local guildName = (char and char.guildName) or nil
    if isCurrentCharacter then
        guildName = IsInGuild() and GetGuildInfo("player") or guildName
    end

    if guildName and guildName ~= "" then
        -- Guild name: soft lavender so it’s visible but not louder than name
        return string.format("|cffffffff%s|r", guildName)
    end

    return "|cff5c5c5c—|r"
end

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
    
    -- WN_CHARACTER_UPDATED: REMOVED — UI.lua's SchedulePopulateContent already handles
    -- chars tab refresh via PopulateContent → DrawCharacterList. Having both caused double rebuild.
    
    -- WN_CHARACTER_TRACKING_CHANGED: keep — UI.lua does NOT handle this event.
    local Constants = ns.Constants
    WarbandNexus.RegisterMessage(CharactersUIEvents, "WN_CHARACTER_TRACKING_CHANGED", function(event, data)
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.currentTab == "chars" then
            DebugPrint("|cff9370DB[WN CharactersUI]|r Tracking status changed, refreshing UI...")
            WarbandNexus:RefreshUI()
        end
    end)
    
    DebugPrint("|cff00ff00[WN CharactersUI]|r Event listeners registered (WN_CHARACTER_TRACKING_CHANGED)")
end

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function WarbandNexus:DrawCharacterList(parent)
    -- Request updated WoW Token market price (async; result used by Total Gold card)
    if C_WowTokenPublic and C_WowTokenPublic.UpdateMarketPrice then
        C_WowTokenPublic.UpdateMarketPrice()
    end

    self.recentlyExpanded = self.recentlyExpanded or {}
    local width = parent:GetWidth() - 20

    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.characters"
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

    -- Pooled character rows: released in UI.lua PopulateContent (ReleaseAllPooledChildren) before
    -- this runs — do not call again here (double-release duplicated pool entries / shared frames).
    
    local currentPlayerKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if self.db.global.characters and currentPlayerKey and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    local characters = self:GetAllCharacters()
    if self.db.profile.debugMode and self.db.global.characters then
        local nDb = 0
        for _ in pairs(self.db.global.characters) do nDb = nDb + 1 end
        DebugPrint(string.format("[CharactersUI] db.global.characters count=%d GetAllCharacters count=%d", nDb, #characters))
    end
    
    -- ===== TITLE CARD (in fixedHeader - non-scrolling) =====
    local titleCard = CreateCard(headerParent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
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
    
    -- Sort Dropdown on the Title Card (Header)
    if ns.UI_CreateCharacterSortDropdown then
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
        }
        if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
        local sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.characterSort, function() self:RefreshUI() end)
        sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -20, 0)
        sortBtn:SetFrameLevel(titleCard:GetFrameLevel() + 5)
    end
    
    -- NO TRACKING: Static text, never overflows
    
    titleCard:Show()
    headerYOffset = headerYOffset + 75

    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    local yOffset = 8

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
        
        local charKey = GetCharKey(char)
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
    
    -- Total Gold + Token Card (Right — wider card spanning remaining space)
    local totalGoldCard = CreateCard(parent, 90)
    totalGoldCard:SetPoint("LEFT", wbGoldCard, "RIGHT", cardSpacing, 0)
    totalGoldCard:SetPoint("RIGHT", -rightMargin, 0)

    -- Apply visuals with accent border
    if ApplyVisuals then
        ApplyVisuals(totalGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end

    -- Left half: Total Gold (icon + label + value)
    local tgIcon = CreateIcon(totalGoldCard, "BonusLoot-Chest", 36, true, nil, true)
    tgIcon:SetPoint("CENTER", totalGoldCard, "LEFT", 15 + 18, 0)
    tgIcon:Show()

    local tgTextContainer = CreateFrame("Frame", nil, totalGoldCard)
    tgTextContainer:SetSize(150, 40)
    tgTextContainer:SetPoint("LEFT", tgIcon, "RIGHT", 12, 0)

    local tgLabel = FontManager:CreateFontString(tgTextContainer, "subtitle", "OVERLAY")
    tgLabel:SetText((ns.L and ns.L["HEADER_TOTAL_GOLD"]) or "TOTAL GOLD")
    tgLabel:SetTextColor(1, 1, 1)
    tgLabel:SetJustifyH("LEFT")
    tgLabel:SetPoint("BOTTOM", tgTextContainer, "CENTER", 0, 0)
    tgLabel:SetPoint("LEFT", tgTextContainer, "LEFT", 0, 0)

    local tgValue = FontManager:CreateFontString(tgTextContainer, "body", "OVERLAY")
    tgValue:SetText(FormatMoney(totalWithWarband, 14))
    tgValue:SetJustifyH("LEFT")
    tgValue:SetPoint("TOP", tgTextContainer, "CENTER", 0, -4)
    tgValue:SetPoint("LEFT", tgTextContainer, "LEFT", 0, 0)

    -- Vertical divider
    local divider = totalGoldCard:CreateTexture(nil, "ARTWORK")
    divider:SetSize(1, 50)
    divider:SetPoint("CENTER", totalGoldCard, "CENTER", 0, 0)
    divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4)

    -- Right half: WoW Token (icon + label + price with token count)
    local tokenPrice = C_WowTokenPublic and C_WowTokenPublic.GetCurrentMarketPrice and C_WowTokenPublic.GetCurrentMarketPrice()

    local tkIcon = totalGoldCard:CreateTexture(nil, "ARTWORK")
    tkIcon:SetSize(28, 28)
    tkIcon:SetTexture("Interface\\Icons\\WoW_Token01")
    tkIcon:SetPoint("LEFT", divider, "RIGHT", 14, 0)
    tkIcon:Show()

    local tkTextContainer = CreateFrame("Frame", nil, totalGoldCard)
    tkTextContainer:SetSize(150, 40)
    tkTextContainer:SetPoint("LEFT", tkIcon, "RIGHT", 10, 0)

    local tkLabel = FontManager:CreateFontString(tkTextContainer, "subtitle", "OVERLAY")
    tkLabel:SetText((ns.L and ns.L["WOW_TOKEN_LABEL"]) or "WOW TOKEN")
    tkLabel:SetTextColor(1, 1, 1)
    tkLabel:SetJustifyH("LEFT")
    tkLabel:SetPoint("BOTTOM", tkTextContainer, "CENTER", 0, 0)
    tkLabel:SetPoint("LEFT", tkTextContainer, "LEFT", 0, 0)

    local tkValue = FontManager:CreateFontString(tkTextContainer, "body", "OVERLAY")
    tkValue:SetJustifyH("LEFT")
    tkValue:SetPoint("TOP", tkTextContainer, "CENTER", 0, -4)
    tkValue:SetPoint("LEFT", tkTextContainer, "LEFT", 0, 0)

    if tokenPrice and tokenPrice > 0 then
        local affordableCount = math.floor(totalWithWarband / tokenPrice)
        tkValue:SetText(FormatMoney(tokenPrice, 12) .. "  |cff66c0ff(" .. affordableCount .. " Tokens)|r")
    else
        tkValue:SetText("|cff888888N/A|r")
    end

    charGoldCard:Show()
    wbGoldCard:Show()
    totalGoldCard:Show()

    yOffset = yOffset + 100
    
    local sortOptions = {
        {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
        {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
        {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
        {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
        {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
    }
    
    if not self.db.profile.characterSort then self.db.profile.characterSort = {} end
    local currentSortKey = self.db.profile.characterSort.key or "manual"
    
    -- ===== SORT CHARACTERS: FAVORITES -> REGULAR =====
    local trackedFavorites = {}
    local trackedRegular = {}
    local untracked = {}
    
    for _, char in ipairs(characters) do
        local charKey = GetCharKey(char)
        local isTracked = char.isTracked ~= false  -- Default to true if not set
        
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
        local sortMode = self.db.profile.characterSort and self.db.profile.characterSort.key
        
        if sortMode and sortMode ~= "manual" then
            table.sort(list, function(a, b)
                if sortMode == "name" then
                    return (a.name or ""):lower() < (b.name or ""):lower()
                elseif sortMode == "level" then
                    if (a.level or 0) ~= (b.level or 0) then
                        return (a.level or 0) > (b.level or 0)
                    else
                        return (a.name or ""):lower() < (b.name or ""):lower()
                    end
                elseif sortMode == "ilvl" then
                    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
                        return (a.itemLevel or 0) > (b.itemLevel or 0)
                    else
                        return (a.name or ""):lower() < (b.name or ""):lower()
                    end
                elseif sortMode == "gold" then
                    local goldA = ns.Utilities:GetCharTotalCopper(a)
                    local goldB = ns.Utilities:GetCharTotalCopper(b)
                    if goldA ~= goldB then
                        return goldA > goldB
                    else
                        return (a.name or ""):lower() < (b.name or ""):lower()
                    end
                end
                -- Fallback
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return (a.name or ""):lower() < (b.name or ""):lower()
                end
            end)
            return list
        end
        
        local customOrder = self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for _, char in ipairs(list) do
                local key = GetCharKey(char)
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
    
    -- Guild column width: max guild name width across all visible characters (centered text)
    do
        if not parent.guildMeasureFs then
            parent.guildMeasureFs = FontManager:CreateFontString(parent, "body", "OVERLAY")
            parent.guildMeasureFs:Hide()
        end
        local fs = parent.guildMeasureFs
        local maxW = 0
        for _, list in ipairs({trackedFavorites, trackedRegular, untracked}) do
            for i = 1, #list do
                local char = list[i]
                local isCurrent = (GetCharKey(char) == currentPlayerKey)
                fs:SetText(BuildGuildText(char, isCurrent))
                local w = fs:GetStringWidth()
                if w > maxW then maxW = w end
            end
        end
        local GUILD_PADDING = 20
        local GUILD_MIN = 60
        local GUILD_MAX = 280
        self._charListMaxGuildWidth = math.min(math.max(maxW + GUILD_PADDING, GUILD_MIN), GUILD_MAX)
    end
    
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
    local SECTION_H = 44
    local favHeader, _, favIcon, favHeaderText = CreateCollapsibleHeader(
        parent,
        ((ns.L and ns.L["HEADER_FAVORITES"]) or "Favorites"),
        "favorites",
        self.charactersExpandAllActive or self.db.profile.ui.favoritesExpanded,
        function(isExpanded)
            self.db.profile.ui.favoritesExpanded = isExpanded
            if isExpanded then self.recentlyExpanded["favorites"] = GetTime() end
            self:RefreshUI()
        end,
        "GM-icon-assistActive-hover",
        true
    )
    favHeader:SetHeight(SECTION_H)
    favHeader:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    favHeader:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    if favIcon then favIcon:SetSize(28, 28) end
    if favHeaderText then
        FontManager:ApplyFont(favHeaderText, "title")
    end
    
    local favAccent = favHeader:CreateTexture(nil, "ARTWORK", nil, 2)
    favAccent:SetSize(3, SECTION_H - 8)
    favAccent:SetPoint("LEFT", 4, 0)
    favAccent:SetColorTexture(1, 0.82, 0.2, 0.9)
    
    local favCount = FontManager:CreateFontString(favHeader, "body", "OVERLAY")
    favCount:SetPoint("RIGHT", -14, 0)
    favCount:SetText("|cffaaaaaa" .. FormatNumber(#trackedFavorites) .. "|r")
    
    if ApplyVisuals then
        ApplyVisuals(favHeader, {0.06, 0.06, 0.08, 0.95}, {1, 0.82, 0.2, 0.5})
    end
    
    yOffset = yOffset + SECTION_H
    
    if self.db.profile.ui.favoritesExpanded then
        if #trackedFavorites > 0 then
            for i = 1, #trackedFavorites do
                local char = trackedFavorites[i]
                local ok, result = pcall(self.DrawCharacterRow, self, parent, char, i, width, yOffset, true, currentSortKey == "manual", trackedFavorites, "favorites", i, #trackedFavorites, currentPlayerKey)
                if ok and result then
                    yOffset = result
                else
                    yOffset = yOffset + (ROW_HEIGHT or 36)
                end
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
    local charHeader, _, charIcon, charHeaderText = CreateCollapsibleHeader(
        parent,
        ((ns.L and ns.L["HEADER_CHARACTERS"]) or "Characters"),
        "characters",
        self.db.profile.ui.charactersExpanded,
        function(isExpanded)
            self.db.profile.ui.charactersExpanded = isExpanded
            if isExpanded then self.recentlyExpanded["characters"] = GetTime() end
            self:RefreshUI()
        end,
        "GM-icon-headCount",
        true
    )
    charHeader:SetHeight(SECTION_H)
    charHeader:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    charHeader:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    if charHeaderText then
        FontManager:ApplyFont(charHeaderText, "title")
    end
    
    local charAccent = charHeader:CreateTexture(nil, "ARTWORK", nil, 2)
    charAccent:SetSize(3, SECTION_H - 8)
    charAccent:SetPoint("LEFT", 4, 0)
    charAccent:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    
    local charCount = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
    charCount:SetPoint("RIGHT", -14, 0)
    charCount:SetText("|cffaaaaaa" .. FormatNumber(#trackedRegular) .. "|r")
    
    if ApplyVisuals then
        ApplyVisuals(charHeader, {0.06, 0.06, 0.08, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
    end
    
    yOffset = yOffset + SECTION_H
    
    if self.db.profile.ui.charactersExpanded then
        if #trackedRegular > 0 then
            for i = 1, #trackedRegular do
                local char = trackedRegular[i]
                local ok, result = pcall(self.DrawCharacterRow, self, parent, char, i, width, yOffset, false, currentSortKey == "manual", trackedRegular, "regular", i, #trackedRegular, currentPlayerKey)
                if ok and result then
                    yOffset = result
                else
                    yOffset = yOffset + (ROW_HEIGHT or 36)
                end
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
        
        local untrackedHeader, _, untrackedIcon, untrackedHeaderText = CreateCollapsibleHeader(
            parent,
            ((ns.L and ns.L["UNTRACKED_CHARACTERS"]) or "Untracked Characters"),
            "untracked",
            self.db.profile.ui.untrackedExpanded,
            function(isExpanded)
                self.db.profile.ui.untrackedExpanded = isExpanded
                if isExpanded then self.recentlyExpanded["untracked"] = GetTime() end
                self:RefreshUI()
            end,
            "DungeonStoneCheckpointDeactivated",
            true
        )
        untrackedHeader:SetHeight(SECTION_H)
        untrackedHeader:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
        untrackedHeader:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
        if untrackedHeaderText then
            FontManager:ApplyFont(untrackedHeaderText, "title")
            untrackedHeaderText:SetTextColor(0.7, 0.7, 0.7)
        end
        
        local untrackedAccent = untrackedHeader:CreateTexture(nil, "ARTWORK", nil, 2)
        untrackedAccent:SetSize(3, SECTION_H - 8)
        untrackedAccent:SetPoint("LEFT", 4, 0)
        untrackedAccent:SetColorTexture(0.8, 0.25, 0.25, 0.9)
        
        local untrackedCount = FontManager:CreateFontString(untrackedHeader, "body", "OVERLAY")
        untrackedCount:SetPoint("RIGHT", -14, 0)
        untrackedCount:SetText("|cff888888" .. FormatNumber(#untracked) .. "|r")
        
        if ApplyVisuals then
            ApplyVisuals(untrackedHeader, {0.06, 0.06, 0.08, 0.95}, {0.8, 0.25, 0.25, 0.5})
        end
        
        yOffset = yOffset + SECTION_H
        
        if self.db.profile.ui.untrackedExpanded then
            for i = 1, #untracked do
                local char = untracked[i]
                local ok, result = pcall(self.DrawCharacterRow, self, parent, char, i, width, yOffset, false, currentSortKey == "manual", untracked, "untracked", i, #untracked, currentPlayerKey)
                if ok and result then
                    yOffset = result
                else
                    yOffset = yOffset + (ROW_HEIGHT or 36)
                end
            end
        end
    end
    
    return yOffset
end

--============================================================================
-- DRAW SINGLE CHARACTER ROW
--============================================================================

function WarbandNexus:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey)
    -- PERFORMANCE: Acquire from pool
    local row = AcquireCharacterRow(parent)
    row:ClearAllPoints()
    row:SetSize(width, 46)  -- Increased 20% (38 → 46)
    row:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    row:EnableMouse(true)
    
    -- Ensure alpha is reset (pooling safety)
    row:SetAlpha(1)
    
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end

    -- Define charKey for use in buttons (canonical key for DB/service consistency)
    local charKey = GetCharKey(char)
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
    local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    row.realmText:SetText("|cffb0b0b8" .. displayRealm .. "|r")
    
    -- COLUMN: Guild — width from max guild name; text centered; strictly between Name and Level
    local guildOffset = nameOffset + (CHAR_ROW_COLUMNS.name.total or 115)
    local guildColW = self._charListMaxGuildWidth or (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.width) or 130
    local guildSpacing = (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.spacing) or 15
    if not row.guildText then
        row.guildText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.guildText:SetJustifyH("CENTER")
        if row.guildText.SetJustifyV then row.guildText:SetJustifyV("MIDDLE") end
        row.guildText:SetWordWrap(false)
        row.guildText:SetNonSpaceWrap(false)
        row.guildText:SetMaxLines(1)
    end
    row.guildText:ClearAllPoints()
    local rowH = row:GetHeight() or 46
    local centerY = -rowH / 2
    row.guildText:SetPoint("CENTER", row, "TOPLEFT", guildOffset + (guildColW - 4) / 2, centerY)
    row.guildText:SetWidth(guildColW - 4)
    row.guildText:SetText(BuildGuildText(char, isCurrent))
    row.guildText:Show()
    
    -- Level column: level + rested line (DB-driven).
    local guildTotal = guildColW + guildSpacing
    local levelOffset = guildOffset + guildTotal
    local levelColW = CHAR_ROW_COLUMNS.level.width
    if not row.levelText then
        row.levelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.levelText:SetWidth(levelColW)
        row.levelText:SetJustifyH("CENTER")
        row.levelText:SetWordWrap(false)
        row.levelText:SetMaxLines(1)
    end

    if not row.levelRestedText then
        row.levelRestedText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.levelRestedText:SetWidth(levelColW)
        row.levelRestedText:SetJustifyH("CENTER")
        row.levelRestedText:SetWordWrap(false)
        row.levelRestedText:SetMaxLines(1)
    end

    local restedState = self.GetCharacterRestedState and self:GetCharacterRestedState(char)
    local maxPlayerLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
    local showRestedLine = restedState ~= nil and (char.level or 1) < maxPlayerLevel
    local showZzz = restedState and restedState.isRestingArea

    row.levelText:ClearAllPoints()
    if showRestedLine then
        row.levelText:SetPoint("TOP", row, "TOPLEFT", levelOffset + (levelColW / 2), -7)
    else
        row.levelText:SetPoint("LEFT", levelOffset, 0)
    end
    row.levelText:SetText(string.format("|cff%02x%02x%02x%d|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.level or 1))
    row.levelText:Show()

    if showRestedLine then
        local restedPct = restedState.restedPercentOfLevel or 0
        row.levelRestedText:ClearAllPoints()
        row.levelRestedText:SetPoint("TOP", row.levelText, "BOTTOM", 0, -2)
        if showZzz then
            row.levelRestedText:SetText(string.format("|cff66c0ffZzz %.2f%%|r", restedPct))
        else
            row.levelRestedText:SetText(string.format("|cff66c0ff%.2f%%|r", restedPct))
        end
        row.levelRestedText:Show()
    else
        row.levelRestedText:Hide()
    end

    if row.levelRestedIcon then row.levelRestedIcon:Hide() end
    if row.levelRestedHitFrame then row.levelRestedHitFrame:Hide() end

    -- COLUMN: Item Level (dynamic offset, chained from level column)
    local itemLevelOffset = levelOffset + (CHAR_ROW_COLUMNS.level.total or 97)
    if not row.itemLevelText then
        row.itemLevelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.itemLevelText:SetWidth(CHAR_ROW_COLUMNS.itemLevel.width)
        row.itemLevelText:SetJustifyH("CENTER")
        row.itemLevelText:SetMaxLines(1)  -- Single line only
    end
    row.itemLevelText:ClearAllPoints()
    row.itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
    local itemLevel = char.itemLevel or 0
    if itemLevel > 0 then
        row.itemLevelText:SetText(string.format("|cffffd700%s %d|r", (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", itemLevel))
    else
        row.itemLevelText:SetText("|cff666666--|r")
    end
    
    
    -- COLUMN 8: Gold (dynamic offset, chained from itemLevel column)
    local goldOffset = itemLevelOffset + (CHAR_ROW_COLUMNS.itemLevel.total or 90)
    if not row.goldText then
        row.goldText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.goldText:SetWidth(CHAR_ROW_COLUMNS.gold.width)
        row.goldText:SetJustifyH("RIGHT")
        row.goldText:SetMaxLines(1)  -- Single line only
    end
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("LEFT", goldOffset, 0)
    local totalCopper = ns.Utilities:GetCharTotalCopper(char)
    row.goldText:SetText(FormatMoney(totalCopper, 12))
    
    
    -- COLUMN 9: Professions (dynamic offset, chained from gold column)
    local profOffset = goldOffset + (CHAR_ROW_COLUMNS.gold.total or 205)
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
        local secondaries = {"cooking"}
        for _, sec in ipairs(secondaries) do
            if char.professions[sec] then numProfs = numProfs + 1 end
        end
        
        -- Calculate centered starting position (within column content area, excluding right spacing)
        local profColumnWidth = CHAR_ROW_COLUMNS.professions.width  -- Content width only
        local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * iconSpacing)
        -- Center the icons within the column width
        local leftPadding = (profColumnWidth - totalIconWidth) / 2
        local currentProfX = profOffset + leftPadding
        
        local charKey = GetCharKey(char)
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
            local kd = nil
            if profName and char.knowledgeData then
                -- Prefer highest skillLineID (newest expansion) for current data
                local bestKey = -1
                for key, entry in pairs(char.knowledgeData) do
                    if type(key) == "number" and type(entry) == "table" and entry.professionName == profName then
                        if key > bestKey then
                            bestKey = key
                            kd = entry
                        end
                    end
                end
                -- Fallback: legacy profName-keyed data
                if not kd then
                    kd = char.knowledgeData[profName]
                end
            end
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
                local kd = nil
                if char.knowledgeData then
                    -- Prefer highest skillLineID (newest expansion) for current data
                    local bestKey = -1
                    for kKey, kEntry in pairs(char.knowledgeData) do
                        if type(kKey) == "number" and type(kEntry) == "table" and kEntry.professionName == profName then
                            if kKey > bestKey then
                                bestKey = kKey
                                kd = kEntry
                            end
                        end
                    end
                    -- Fallback: legacy profName-keyed data
                    if not kd then
                        kd = char.knowledgeData[profName]
                    end
                end
                if kd then
                    local unspent = kd.unspentPoints or 0
                    local spent = kd.spentPoints or 0
                    local maxPts = kd.maxPoints or 0
                    local collectible = (maxPts > 0) and (maxPts - unspent - spent) or 0
                    local hasKnowledgeLine = (collectible > 0) or (unspent > 0)
                    if hasKnowledgeLine then
                        lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                        local cName = kd.currencyName or "Knowledge"
                        if collectible > 0 then
                            lines[#lines + 1] = {
                                left = "Collectible",
                                right = tostring(collectible),
                                leftColor = {1, 1, 1},
                                rightColor = {0.3, 0.9, 0.3}
                            }
                        end
                        if unspent > 0 then
                            lines[#lines + 1] = {
                                left = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. unspent .. " " .. ((ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent Points"),
                                leftColor = {1, 0.82, 0}
                            }
                        end
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

                -- ====== SECTION 4: Profession equipment (per-profession only; no fallback to avoid showing wrong profession's equipment) ======
                local eqByProf = char.professionEquipment
                local eqData = eqByProf and eqByProf[profName] or nil
                if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    local slotKeys = { "tool", "accessory1", "accessory2" }
                    local tooltipSvc = ns.TooltipService
                    for _, slotKey in ipairs(slotKeys) do
                        local item = eqData[slotKey]
                        if item then
                            local iconStr = item.icon and string.format("|T%s:0|t ", tostring(item.icon)) or ""
                            -- Get stat lines first to extract actual slot type (Head, Chest, Tool, etc.)
                            local statLines = tooltipSvc and tooltipSvc.GetItemTooltipSummaryLines and tooltipSvc:GetItemTooltipSummaryLines(item.itemLink, item.itemID, slotKey) or {}
                            -- First line contains the slot type (e.g., "Head", "Chest", "Tool")
                            local slotLabel = (statLines[1] and statLines[1].left) or (slotKey == "tool" and "Tool" or "Accessory")
                            lines[#lines + 1] = {
                                left = iconStr .. (item.name or "Unknown"),
                                right = slotLabel,
                                leftColor = {1, 1, 1},
                                rightColor = {0.5, 0.5, 0.5},
                            }
                            -- Add remaining stat lines (skip first since it's now used as slot label)
                            for si = 2, #statLines do
                                local sLine = statLines[si]
                                lines[#lines + 1] = {
                                    left = "    " .. sLine.left,
                                    right = sLine.right or "",
                                    leftColor = sLine.leftColor or {0.7, 0.7, 0.7},
                                    rightColor = sLine.rightColor or {0.7, 0.7, 0.7},
                                }
                            end
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
    
    
    -- COLUMN 10: Mythic Keystone (dynamic offset, chained from professions column)
    local mythicKeyOffset = profOffset + (CHAR_ROW_COLUMNS.professions.total or 150)
    
    -- Create keystone icon (shared for has-key and no-key)
    if not row.keystoneIcon then
        row.keystoneIcon = row:CreateTexture(nil, "ARTWORK")
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
    row.keystoneIcon:ClearAllPoints()
    row.keystoneIcon:SetPoint("LEFT", mythicKeyOffset + 5, 0)  -- 5px padding from column edge

    -- Create keystone text (shared for has-key and no-key)
    if not row.keystoneText then
        row.keystoneText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.keystoneText:SetWidth(CHAR_ROW_COLUMNS.mythicKey.width - 30)
        row.keystoneText:SetJustifyH("LEFT")
        row.keystoneText:SetWordWrap(false)
        row.keystoneText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.keystoneText:SetMaxLines(1)  -- Single line only
    end
    row.keystoneText:ClearAllPoints()
    row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)  -- Icon(24) + gap(5) + padding(5)
    
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
    
    -- RIGHT-ANCHORED COLUMNS: [Delete] [LastSeen] [Reorder] (track column removed)
    local R_MARGIN = 6
    local R_GAP = 6
    local deleteRight = R_MARGIN
    local lastSeenRight = deleteRight + CHAR_ROW_COLUMNS.delete.width + R_GAP
    local reorderRight = lastSeenRight + CHAR_ROW_COLUMNS.lastSeen.width + R_GAP
    
    if row.trackingIcon then
        row.trackingIcon:Hide()
    end
    
    -- Reorder Buttons (right-aligned column, centered content)
    if not row.reorderButtons then
        local rb = ns.UI.Factory:CreateContainer(row, CHAR_ROW_COLUMNS.reorder.width, 46)
        rb:SetAlpha(0.7)
        rb.isPersistentRowElement = true
        
        rb.up = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        rb.up:SetPoint("CENTER", -11, 0)
        rb.up:SetNormalAtlas("housing-floor-arrow-up-default")
        rb.up:EnableMouse(true)
        rb.down = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        rb.down:SetPoint("CENTER", 11, 0)
        rb.down:SetNormalAtlas("housing-floor-arrow-down-default")
        rb.down:EnableMouse(true)
        row.reorderButtons = rb
    end
    row.reorderButtons:ClearAllPoints()
    row.reorderButtons:SetPoint("RIGHT", row, "RIGHT", -reorderRight, 0)
    
    if showReorder and charList then
        row.reorderButtons:Show()
        -- Always set OnClick (WoW Button supports SetScript even without prior script; HasScript can be false before first set)
        if row.reorderButtons.up then
            row.reorderButtons.up:EnableMouse(true)
            row.reorderButtons.up:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, -1) end)
        end
        if row.reorderButtons.down then
            row.reorderButtons.down:EnableMouse(true)
            row.reorderButtons.down:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, 1) end)
        end
    else
        row.reorderButtons:Hide()
        if row.reorderButtons.up then row.reorderButtons.up:SetScript("OnClick", nil) end
        if row.reorderButtons.down then row.reorderButtons.down:SetScript("OnClick", nil) end
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
                    if dialog.Close then
                        dialog:Close()
                    else
                        dialog:Hide()
                    end
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
                    if dialog.Close then
                        dialog:Close()
                    else
                        dialog:Hide()
                    end
                end)
                
                -- NOTE: Do NOT override dialog:SetScript("OnHide") here!
                -- WindowFactory's OnHide handles hiding the clickOutsideFrame overlay.
                -- Overriding it leaves an invisible full-screen mouse blocker.
                -- dialog.Close() already handles SetParent(nil) and _G cleanup.
                
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
    

    
    local betweenRows = GetLayout().betweenRows or 0
    return yOffset + 46 + betweenRows  -- Row 46px + spacing (betweenRows from UI_LAYOUT)
end


--============================================================================
-- REORDER CHARACTER IN LIST
--============================================================================

function WarbandNexus:ReorderCharacter(char, charList, listKey, direction)
    if not char or not listKey then
        return
    end
    
    local charKey = GetCharKey(char)
    
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
            local key = GetCharKey(c)
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
