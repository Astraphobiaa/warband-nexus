--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local FormatMoney = ns.UI_FormatMoney
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local CreateFactionIcon = ns.UI_CreateFactionIcon
local CreateRaceIcon = ns.UI_CreateRaceIcon
local CreateClassIcon = ns.UI_CreateClassIcon
local CreateFavoriteButton = ns.UI_CreateFavoriteButton
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local GetColumnOffset = ns.UI_GetColumnOffset
local CreateCharRowColumnDivider = ns.UI_CreateCharRowColumnDivider
local CHAR_ROW_COLUMNS = ns.UI_CHAR_ROW_COLUMNS

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function WarbandNexus:DrawCharacterList(parent)
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters (cached for performance)
    local characters = self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters()
    
    -- Get current player key
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Header icon with ring border (standardized system from SharedWidgets)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("characters"))
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Your Characters|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, -12)
    subtitleText:SetTextColor(1, 1, 1)  -- White
    subtitleText:SetText(#characters .. " characters tracked")
    
    -- Show "Planner" toggle button in title bar if planner is hidden
    if self.db and self.db.profile and self.db.profile.showWeeklyPlanner == false then
        local showPlannerBtn = CreateFrame("Button", nil, titleCard, "UIPanelButtonTemplate")
        showPlannerBtn:SetSize(90, 22)
        showPlannerBtn:SetPoint("RIGHT", -15, 0)
        showPlannerBtn:SetText("Show Planner")
        showPlannerBtn:SetScript("OnClick", function()
            self.db.profile.showWeeklyPlanner = true
            if self.RefreshUI then self:RefreshUI() end
        end)
        showPlannerBtn:SetScript("OnEnter", function(btn)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText("Weekly Planner")
            GameTooltip:AddLine("Shows tasks for characters logged in within 3 days", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        showPlannerBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    
    yOffset = yOffset + 75 -- Reduced spacing
    
    -- ===== WEEKLY PLANNER SECTION =====
    local plannerSuccess = pcall(function()
        local showPlanner = self.db.profile.showWeeklyPlanner ~= false
        local plannerCollapsed = self.db.profile.weeklyPlannerCollapsed or false
        
        if showPlanner and self.GenerateWeeklyAlerts then
            local alerts = self:GenerateWeeklyAlerts() or {}
            local alertCount = (alerts and type(alerts) == "table") and #alerts or 0
            
            -- Always show planner section (even if empty - shows "All caught up!")
            local plannerHeight = plannerCollapsed and 44 or (alertCount > 0 and (44 + math.min(alertCount, 8) * 26 + 10) or 70)
            local plannerCard = CreateCard(parent, plannerHeight)
            if not plannerCard then return end
            
            plannerCard:SetPoint("TOPLEFT", 10, -yOffset)
            plannerCard:SetPoint("TOPRIGHT", -10, -yOffset)
            plannerCard:SetBackdropColor(0.08, 0.12, 0.08, 1)  -- Slight green tint
            plannerCard:SetBackdropBorderColor(0.3, 0.5, 0.3, 1)
            
            -- Header row with collapse button
            local collapseBtn = CreateFrame("Button", nil, plannerCard)
            collapseBtn:SetSize(24, 24)
            collapseBtn:SetPoint("LEFT", 12, plannerCollapsed and 0 or (plannerHeight/2 - 20))
            
            local collapseIcon = collapseBtn:CreateTexture(nil, "ARTWORK")
            collapseIcon:SetAllPoints()
            collapseIcon:SetTexture(plannerCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            
            collapseBtn:SetScript("OnClick", function()
                self.db.profile.weeklyPlannerCollapsed = not self.db.profile.weeklyPlannerCollapsed
                    if self.RefreshUI then self:RefreshUI() end
                end)
                
                collapseBtn:SetScript("OnEnter", function(btn)
                    collapseIcon:SetTexture(plannerCollapsed and "Interface\\Buttons\\UI-PlusButton-Hilight" or "Interface\\Buttons\\UI-MinusButton-Hilight")
                end)
                collapseBtn:SetScript("OnLeave", function(btn)
                    collapseIcon:SetTexture(plannerCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
                end)
                
                local plannerIcon = plannerCard:CreateTexture(nil, "ARTWORK")
                plannerIcon:SetSize(24, 24)
                plannerIcon:SetPoint("LEFT", collapseBtn, "RIGHT", 8, 0)
                plannerIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
                
            local plannerTitle = plannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            plannerTitle:SetPoint("LEFT", plannerIcon, "RIGHT", 8, 0)
            if alertCount > 0 then
                plannerTitle:SetText("|cff88cc88This Week|r  |cff666666(" .. alertCount .. " task" .. (alertCount > 1 and "s" or "") .. ")|r")
            else
                plannerTitle:SetText("|cff88cc88This Week|r  |cff44aa44All caught up!|r")
            end
            
            -- Hide button on the right
            local hideBtn = CreateFrame("Button", nil, plannerCard, "UIPanelButtonTemplate")
            hideBtn:SetSize(70, 22)
            hideBtn:SetPoint("RIGHT", -12, plannerCollapsed and 0 or (plannerHeight/2 - 20))
            hideBtn:SetText("Hide")
            hideBtn:SetScript("OnClick", function()
                self.db.profile.showWeeklyPlanner = false
                if self.RefreshUI then self:RefreshUI() end
            end)
            
            -- Draw alerts if not collapsed
            if not plannerCollapsed then
                if alertCount > 0 then
                    local alertY = -44
                    local maxAlerts = 8  -- Limit visible alerts
                    
                    for i, alert in ipairs(alerts) do
                        if i > maxAlerts then break end
                        
                        local alertRow = CreateFrame("Frame", nil, plannerCard)
                        alertRow:SetSize(plannerCard:GetWidth() - 24, 24)
                        alertRow:SetPoint("TOPLEFT", 12, alertY)
                        
                        -- Alert icon
                        local aIcon = alertRow:CreateTexture(nil, "ARTWORK")
                        aIcon:SetSize(20, 20)
                        aIcon:SetPoint("LEFT", 0, 0)
                        aIcon:SetTexture(alert.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                        
                        -- Priority indicator (color bullet)
                        local priorityColors = {
                            [1] = {1, 0.3, 0.3},    -- High priority (vault) - red
                            [2] = {1, 0.6, 0},      -- Medium (knowledge) - orange
                            [3] = {0.3, 0.7, 1},    -- Low (reputation) - blue
                        }
                        local pColor = priorityColors[alert.priority] or {0.7, 0.7, 0.7}
                        
                        local bullet = alertRow:CreateTexture(nil, "ARTWORK")
                        bullet:SetSize(8, 8)
                        bullet:SetPoint("LEFT", aIcon, "RIGHT", 6, 0)
                        bullet:SetTexture("Interface\\COMMON\\Indicator-Green")  -- Circle texture
                        bullet:SetVertexColor(pColor[1], pColor[2], pColor[3], 1)
                        
                        -- Character name + message
                        local alertText = alertRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        alertText:SetPoint("LEFT", bullet, "RIGHT", 6, 0)
                        alertText:SetText((alert.character or "") .. ": " .. (alert.message or ""))
                        alertText:SetJustifyH("LEFT")
                        
                        alertY = alertY - 26
                    end
                    
                    -- Show "and X more..." if truncated
                    if alertCount > maxAlerts then
                        local moreText = plannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        moreText:SetPoint("BOTTOMLEFT", 48, 8)
                        moreText:SetText("|cff666666...and " .. (alertCount - maxAlerts) .. " more|r")
                    end
                else
                    -- Empty state - all caught up!
                    local emptyIcon = plannerCard:CreateTexture(nil, "ARTWORK")
                    emptyIcon:SetSize(24, 24)
                    emptyIcon:SetPoint("LEFT", 48, -10)
                    emptyIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    
                    local emptyText = plannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    emptyText:SetPoint("LEFT", emptyIcon, "RIGHT", 8, 0)
                    emptyText:SetText("|cff888888No pending tasks for recently active characters.|r")
                end
            end
            
            yOffset = yOffset + plannerHeight + 8
        end
    end)
    -- If planner fails, just continue with the rest of the UI
    
    -- ===== TOTAL GOLD DISPLAY =====
    local currentCharGold = 0  -- Current character only
    local totalCharGold = 0    -- All characters
    
    for _, char in ipairs(characters) do
        local charGold = char.gold or 0
        totalCharGold = totalCharGold + charGold
        
        -- Check if this is the current character
        local charKey = (char.name or "") .. "-" .. (char.realm or "")
        if charKey == currentPlayerKey then
            currentCharGold = charGold
        end
    end
    
    local warbandBankGold = self:GetWarbandBankMoney() or 0
    local totalWithWarband = totalCharGold + warbandBankGold
    
    -- Calculate card width for 3 cards in a row (same as Statistics)
    local leftMargin = 10
    local rightMargin = 10
    local cardSpacing = 10
    local totalSpacing = cardSpacing * 2  -- 2 gaps between 3 cards
    local threeCardWidth = (width - leftMargin - rightMargin - totalSpacing) / 3
    
    -- Characters Gold Card (Left)
    local charGoldCard = CreateCard(parent, 90)
    charGoldCard:SetWidth(threeCardWidth)
    charGoldCard:SetPoint("TOPLEFT", leftMargin, -yOffset)
    charGoldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    charGoldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    -- Current Character icon (same as Characters header)
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    local cg1Icon = charGoldCard:CreateTexture(nil, "ARTWORK")
    cg1Icon:SetSize(40, 40)
    cg1Icon:SetPoint("LEFT", 15, 0)
    cg1Icon:SetAtlas(GetCharacterSpecificIcon(), false)
    
    local cg1Label = charGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cg1Label:SetPoint("TOPLEFT", cg1Icon, "TOPRIGHT", 12, -2)
    cg1Label:SetText("CURRENT CHARACTER")
    cg1Label:SetTextColor(1, 1, 1)  -- White
    
    local cg1Value = charGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cg1Value:SetPoint("BOTTOMLEFT", cg1Icon, "BOTTOMRIGHT", 12, 0)
    cg1Value:SetText(FormatMoney(currentCharGold, 14))
    
    -- Warband Gold Card (Middle)
    local wbGoldCard = CreateCard(parent, 90)
    wbGoldCard:SetWidth(threeCardWidth)
    wbGoldCard:SetPoint("LEFT", charGoldCard, "RIGHT", cardSpacing, 0)
    wbGoldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    wbGoldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local wb1Icon = wbGoldCard:CreateTexture(nil, "ARTWORK")
    wb1Icon:SetSize(30, 40)  -- Aspect ratio: 23:31 (native), larger size to match other icons
    wb1Icon:SetPoint("LEFT", 15, 0)
    wb1Icon:SetAtlas("warbands-icon")  -- TWW Warband campfire atlas
    
    local wb1Label = wbGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wb1Label:SetPoint("TOPLEFT", wb1Icon, "TOPRIGHT", 12, -2)
    wb1Label:SetText("WARBAND GOLD")
    wb1Label:SetTextColor(1, 1, 1)  -- White
    
    local wb1Value = wbGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    wb1Value:SetPoint("BOTTOMLEFT", wb1Icon, "BOTTOMRIGHT", 12, 0)
    wb1Value:SetText(FormatMoney(warbandBankGold, 14))
    
    -- Total Gold Card (Right)
    local totalGoldCard = CreateCard(parent, 90)
    totalGoldCard:SetWidth(threeCardWidth)
    totalGoldCard:SetPoint("LEFT", wbGoldCard, "RIGHT", cardSpacing, 0)
    totalGoldCard:SetPoint("RIGHT", -rightMargin, 0)
    totalGoldCard:SetBackdropColor(0.12, 0.10, 0.05, 1)
    totalGoldCard:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
    
    local tg1Icon = totalGoldCard:CreateTexture(nil, "ARTWORK")
    tg1Icon:SetSize(36, 36)
    tg1Icon:SetPoint("LEFT", 15, 0)
    tg1Icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")  -- Gold pile
    
    local tg1Label = totalGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tg1Label:SetPoint("TOPLEFT", tg1Icon, "TOPRIGHT", 12, -2)
    tg1Label:SetText("TOTAL GOLD")
    tg1Label:SetTextColor(1, 1, 1)  -- White
    
    local tg1Value = totalGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tg1Value:SetPoint("BOTTOMLEFT", tg1Icon, "BOTTOMRIGHT", 12, 0)
    tg1Value:SetText(FormatMoney(totalWithWarband, 14))
    
    yOffset = yOffset + 100
    
    -- ===== SORT CHARACTERS: FAVORITES → REGULAR =====
    local favorites = {}
    local regular = {}
    
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        
        -- Add to appropriate list (current character is not separated)
        if self:IsFavoriteCharacter(charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Load custom order from profile
    if not self.db.profile.characterOrder then
        self.db.profile.characterOrder = {
            favorites = {},
            regular = {}
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
            -- Default sort: level desc → name asc (ignore table header sorting for now)
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
    
    -- Update current character's lastSeen to now (so it shows as online)
    if self.db.global.characters and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIcon = parent:CreateTexture(nil, "ARTWORK")
        emptyIcon:SetSize(48, 48)
        emptyIcon:SetPoint("TOP", 0, -yOffset - 30)
        emptyIcon:SetTexture("Interface\\Icons\\Ability_Spy")
        emptyIcon:SetDesaturated(true)
        emptyIcon:SetAlpha(0.4)
        
        local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        emptyText:SetPoint("TOP", 0, -yOffset - 90)
        emptyText:SetText("|cff666666No characters tracked yet|r")
        
        local emptyDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyDesc:SetPoint("TOP", 0, -yOffset - 115)
        emptyDesc:SetTextColor(1, 1, 1)  -- White
        emptyDesc:SetText("Characters are automatically registered on login")
        
        return yOffset + 200
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
        string.format("Favorites |cff888888(%d)|r", #favorites),
        "favorites",
        self.db.profile.ui.favoritesExpanded,
        function(isExpanded)
            self.db.profile.ui.favoritesExpanded = isExpanded
            self:RefreshUI()
        end,
        "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"  -- Heart/people icon
    )
    favHeader:SetPoint("TOPLEFT", 10, -yOffset)
    favHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Color the favorites header icon gold
    if favIcon then
        favIcon:SetVertexColor(1, 0.84, 0)
    end
    
    yOffset = yOffset + 38  -- Standard header spacing
    
    if self.db.profile.ui.favoritesExpanded then
        yOffset = yOffset + 3  -- Small spacing after header
        if #favorites > 0 then
            for i, char in ipairs(favorites) do
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, true, true, favorites, "favorites", i, #favorites, currentPlayerKey)
            end
        else
            -- Empty state
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(1, 1, 1)  -- White
            emptyText:SetText("No favorite characters yet. Click the star icon to favorite a character.")
            yOffset = yOffset + 35
        end
    end
    
    -- ===== REGULAR CHARACTERS SECTION (Always show header) =====
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    local charHeader = CreateCollapsibleHeader(
        parent,
        string.format("Characters |cff888888(%d)|r", #regular),
        "characters",
        self.db.profile.ui.charactersExpanded,
        function(isExpanded)
            self.db.profile.ui.charactersExpanded = isExpanded
            self:RefreshUI()
        end,
        GetCharacterSpecificIcon(),
        true  -- isAtlas = true
    )
    charHeader:SetPoint("TOPLEFT", 10, -yOffset)
    charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    yOffset = yOffset + 38  -- Standard header spacing
    
    if self.db.profile.ui.charactersExpanded then
        yOffset = yOffset + 3  -- Small spacing after header
        if #regular > 0 then
            for i, char in ipairs(regular) do
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, false, true, regular, "regular", i, #regular, currentPlayerKey)
            end
        else
            -- Empty state
            local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            emptyText:SetPoint("TOPLEFT", 30, -yOffset)
            emptyText:SetTextColor(1, 1, 1)  -- White
            emptyText:SetText("All characters are favorited!")
            yOffset = yOffset + 35
        end
    end
    
    return yOffset
end

--============================================================================
-- DRAW SINGLE CHARACTER ROW
--============================================================================

function WarbandNexus:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, 38)  -- Use full width (padding already calculated in DrawCharacterList)
    row:SetPoint("TOPLEFT", 10, -yOffset)
    row:EnableMouse(true)
    
    -- Check if this is the current character
    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    local isCurrent = (charKey == currentPlayerKey)
    
    -- Row background (alternating colors)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    local bgColor = index % 2 == 0 and {0.08, 0.08, 0.10, 1} or {0.05, 0.05, 0.06, 1}
    bg:SetColorTexture(unpack(bgColor))
    row.bgColor = bgColor
    
    -- Class color
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
    
    -- COLUMN 1: Favorite button (centered in column)
    local favOffset = GetColumnOffset("favorite")
    local favButton = CreateFavoriteButton(
        row,
        charKey,
        isFavorite,
        CHAR_ROW_COLUMNS.favorite.width,
        "LEFT",
        favOffset + (CHAR_ROW_COLUMNS.favorite.spacing / 2),  -- Center with half of spacing on each side
        0,
        function(key)
            local newStatus = WarbandNexus:ToggleFavoriteCharacter(key)
            WarbandNexus:RefreshUI()
            return newStatus
        end
    )
    
    -- COLUMN 2: Faction icon (centered in column)
    local factionOffset = GetColumnOffset("faction")
    if char.faction then
        CreateFactionIcon(row, char.faction, CHAR_ROW_COLUMNS.faction.width, "LEFT", factionOffset + (CHAR_ROW_COLUMNS.faction.spacing / 2), 0)
    end
    
    -- COLUMN 3: Race icon (centered in column) - NOW WITH GENDER
    local raceOffset = GetColumnOffset("race")
    if char.raceFile then
        CreateRaceIcon(row, char.raceFile, char.gender, CHAR_ROW_COLUMNS.race.width, "LEFT", raceOffset + (CHAR_ROW_COLUMNS.race.spacing / 2), 0)
    end
    
    -- COLUMN 4: Class icon (centered in column)
    local classOffset = GetColumnOffset("class")
    if char.classFile then
        CreateClassIcon(row, char.classFile, CHAR_ROW_COLUMNS.class.width, "LEFT", classOffset + (CHAR_ROW_COLUMNS.class.spacing / 2), 0)
    end
    
    -- COLUMN 5: Name (two lines: name on top, realm below)
    local nameOffset = GetColumnOffset("name")
    local nameLeftPadding = 4  -- Fine-tuning: left padding for name text
    
    -- Character name (top line, shifted right)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -8)  -- Left padding, offset up
    nameText:SetWidth(CHAR_ROW_COLUMNS.name.width - 50)  -- Reserve space for reorder buttons
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetText(string.format("|cff%02x%02x%02x%s|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.name or "Unknown"))
    
    -- Realm (bottom line, smaller and white, shifted right)
    local realmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    realmText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -22)  -- Same left padding, below name
    realmText:SetWidth(CHAR_ROW_COLUMNS.name.width - 50)
    realmText:SetJustifyH("LEFT")
    realmText:SetWordWrap(false)
    realmText:SetText("|cffffffff" .. (char.realm or "Unknown") .. "|r")  -- Pure white
    realmText:SetTextColor(1, 1, 1)  -- White (realm name)
    
    -- COLUMN 6: Level
    local levelOffset = GetColumnOffset("level")
    local levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    levelText:SetPoint("LEFT", levelOffset, 0)
    levelText:SetWidth(CHAR_ROW_COLUMNS.level.width)
    levelText:SetJustifyH("CENTER")
    levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.level or 1))
    
    -- COLUMN 7: Item Level
    local itemLevelOffset = GetColumnOffset("itemLevel")
    local itemLevelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
    itemLevelText:SetWidth(CHAR_ROW_COLUMNS.itemLevel.width)
    itemLevelText:SetJustifyH("CENTER")
    
    -- Format: "iLvl 450"
    local itemLevel = char.itemLevel or 0
    if itemLevel > 0 then
        itemLevelText:SetText(string.format("|cffffd700iLvl %d|r", itemLevel))
    else
        itemLevelText:SetText("|cff666666--|r")  -- Gray dash for missing data
    end
    
    -- COLUMN 8: Gold
    local goldOffset = GetColumnOffset("gold")
    local goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    goldText:SetPoint("LEFT", goldOffset, 0)
    goldText:SetWidth(CHAR_ROW_COLUMNS.gold.width)
    goldText:SetJustifyH("RIGHT")
    goldText:SetText(FormatMoney(char.gold or 0, 12))  -- Use new money format with 12px icons
    
    -- COLUMN 9: Professions
    local profOffset = GetColumnOffset("professions")
    
    -- Reorder buttons (after name, on the right side)
    if showReorder and charList then
        local reorderButtons = CreateFrame("Frame", nil, row)
        reorderButtons:SetSize(48, 24)
        reorderButtons:SetPoint("LEFT", nameOffset + nameLeftPadding + CHAR_ROW_COLUMNS.name.width - 48, 0)  -- Right side of name area
        reorderButtons:Hide()
        reorderButtons:SetFrameLevel(row:GetFrameLevel() + 10)
        
        -- Store reference immediately for closures
        row.reorderButtons = reorderButtons
        
        -- Up arrow (LEFT side) - Move character UP in list
        local upBtn = CreateFrame("Button", nil, reorderButtons)
        upBtn:SetSize(22, 22)
        upBtn:SetPoint("LEFT", 0, 0)
        
        -- Disable if first in list
        if positionInList and positionInList == 1 then
            upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
            upBtn:SetAlpha(0.5)
            upBtn:Disable()
            upBtn:EnableMouse(false)
        else
            upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
            upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
            upBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            
            upBtn:SetScript("OnClick", function()
                WarbandNexus:ReorderCharacter(char, charList, listKey, -1)
            end)
            
            upBtn:SetScript("OnEnter", function(self)
                row.reorderButtons:Show()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Move Up")
                GameTooltip:Show()
            end)
            
            upBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
        
        -- Down arrow (RIGHT side) - Move character DOWN in list
        local downBtn = CreateFrame("Button", nil, reorderButtons)
        downBtn:SetSize(22, 22)
        downBtn:SetPoint("RIGHT", 0, 0)
        
        -- Disable if last in list
        if positionInList and totalInList and positionInList == totalInList then
            downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
            downBtn:SetAlpha(0.5)
            downBtn:Disable()
            downBtn:EnableMouse(false)
        else
            downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
            downBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
            
            downBtn:SetScript("OnClick", function()
                WarbandNexus:ReorderCharacter(char, charList, listKey, 1)
            end)
            
            downBtn:SetScript("OnEnter", function(self)
                row.reorderButtons:Show()
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText("Move Down")
                GameTooltip:Show()
            end)
            
            downBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
    
    -- Profession Icons (centered in column)
    if char.professions then
        local iconSize = 28
        local iconSpacing = 4
        
        -- Count professions first
        local profCount = 0
        if char.professions[1] then profCount = profCount + 1 end
        if char.professions[2] then profCount = profCount + 1 end
        if char.professions.cooking then profCount = profCount + 1 end
        if char.professions.fishing then profCount = profCount + 1 end
        if char.professions.archaeology then profCount = profCount + 1 end
        
        -- Calculate total width of all profession icons
        local totalProfWidth = (profCount * iconSize) + ((profCount - 1) * iconSpacing)
        
        -- Start from center of profession column
        local profColumnCenter = profOffset + (CHAR_ROW_COLUMNS.professions.width / 2)
        local currentProfX = profColumnCenter - (totalProfWidth / 2)
        
        -- Helper to draw icon
        local function DrawProfIcon(prof)
            if not prof or not prof.icon then return end
            
            local profIcon = row:CreateTexture(nil, "ARTWORK")
            profIcon:SetSize(iconSize, iconSize)
            profIcon:SetPoint("LEFT", currentProfX, 0)
            profIcon:SetTexture(prof.icon)
            
            -- Tooltip button
            local pBtn = CreateFrame("Button", nil, row)
            pBtn:SetAllPoints(profIcon)
            pBtn:SetScript("OnEnter", function(self)
                -- Hide row tooltip
                bg:SetColorTexture(unpack(row.bgColor))
                GameTooltip:Hide()
                
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(prof.name, 1, 1, 1)
                
                -- Show recipe count if available
                if prof.recipes and prof.recipes.known and prof.recipes.total then
                    local recipeColor = (prof.recipes.known == prof.recipes.total) and {0, 1, 0} or {0.8, 0.8, 0.8}
                    GameTooltip:AddDoubleLine("Recipes", prof.recipes.known .. "/" .. prof.recipes.total, 
                        0.7, 0.7, 0.7, recipeColor[1], recipeColor[2], recipeColor[3])
                end
                
                if prof.expansions and #prof.expansions > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Expansion Progress:", 1, 0.82, 0)
                    
                    -- Sort expansions: Newest (highest ID/skillLine) first
                    local expansions = {}
                    for _, exp in ipairs(prof.expansions) do table.insert(expansions, exp) end
                    table.sort(expansions, function(a, b) return (a.skillLine or 0) > (b.skillLine or 0) end)

                    for _, exp in ipairs(expansions) do
                        local color = (exp.rank == exp.maxRank) and {0, 1, 0} or {0.8, 0.8, 0.8}
                        -- Show expansion skill level
                        GameTooltip:AddDoubleLine("  " .. (exp.name or "Unknown"), exp.rank .. "/" .. exp.maxRank, 
                            0.9, 0.9, 0.9, color[1], color[2], color[3])
                        
                        -- Show knowledge points if available (Dragonflight+)
                        if exp.knowledgePoints then
                            local kp = exp.knowledgePoints
                            local unspent = kp.unspent or 0
                            if unspent > 0 then
                                -- Highlight unspent knowledge in orange
                                GameTooltip:AddDoubleLine("    Knowledge", unspent .. " unspent!", 
                                    0.5, 0.5, 0.5, 1, 0.6, 0)
                            elseif kp.current and kp.current > 0 then
                                GameTooltip:AddDoubleLine("    Knowledge", kp.current .. " spent", 
                                    0.5, 0.5, 0.5, 0.6, 0.6, 0.6)
                            end
                        end
                        
                        -- Show specialization status if available
                        if exp.hasSpecialization and exp.specializations then
                            local unlockedCount = 0
                            for _, spec in ipairs(exp.specializations) do
                                if spec.state == "Unlocked" or spec.state == 1 then
                                    unlockedCount = unlockedCount + 1
                                end
                            end
                            if #exp.specializations > 0 then
                                local specColor = (unlockedCount == #exp.specializations) and {0, 1, 0} or {0.6, 0.6, 0.6}
                                GameTooltip:AddDoubleLine("    Specializations", unlockedCount .. "/" .. #exp.specializations,
                                    0.5, 0.5, 0.5, specColor[1], specColor[2], specColor[3])
                            end
                        end
                    end
                else
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddDoubleLine("Skill", (prof.rank or 0) .. "/" .. (prof.maxRank or 0), 1, 1, 1, 1, 1, 1)
                    GameTooltip:AddLine("|cff888888Open Profession window to scan details|r", 0.5, 0.5, 0.5)
                end
                
                -- Show last scan time if available
                if prof.lastDetailedScan then
                    local scanTime = date("%b %d, %H:%M", prof.lastDetailedScan)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Last scanned: " .. scanTime, 0.5, 0.5, 0.5)
                end
                
                GameTooltip:Show()
            end)
            
            pBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
                -- Restore row hover effect
                if row:IsMouseOver() then
                    bg:SetColorTexture(0.18, 0.18, 0.25, 1)
                end
            end)
            
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        
        -- Draw Primary Professions (1 & 2)
        if char.professions[1] then DrawProfIcon(char.professions[1]) end
        if char.professions[2] then DrawProfIcon(char.professions[2]) end
        
        -- Draw Secondary Professions
        if char.professions.cooking then DrawProfIcon(char.professions.cooking) end
        if char.professions.fishing then DrawProfIcon(char.professions.fishing) end
        if char.professions.archaeology then DrawProfIcon(char.professions.archaeology) end
    end
    
    -- COLUMN 10: Mythic Keystone
    local mythicKeyOffset = GetColumnOffset("mythicKey")
    
    if char.mythicKey and char.mythicKey.level then
        -- Dungeon abbreviations (Blizzard Group Finder style)
        local dungeonAbbreviations = {
            -- The War Within (TWW)
            ["Ara-Kara, City of Echoes"] = "ARAK",
            ["The Dawnbreaker"] = "DAWN",
            ["City of Threads"] = "COT",
            ["The Stonevault"] = "SV",
            ["Cinderbrew Meadery"] = "MEAD",
            ["Darkflame Cleft"] = "DFC",
            ["Priory of the Sacred Flame"] = "PSF",
            ["The Rookery"] = "ROOK",
            ["Grim Batol"] = "GMBT",
            ["Siege of Boralus"] = "SIEGE",
            
            -- Dragonflight (DF)
            ["Ruby Life Pools"] = "RLP",
            ["The Nokhud Offensive"] = "NO",
            ["The Azure Vault"] = "AV",
            ["Algeth'ar Academy"] = "AA",
            ["Uldaman: Legacy of Tyr"] = "ULD",
            ["Neltharus"] = "NELT",
            ["Brackenhide Hollow"] = "BH",
            ["Halls of Infusion"] = "HOI",
            
            -- Shadowlands (SL)
            ["The Necrotic Wake"] = "NW",
            ["Plaguefall"] = "PF",
            ["Mists of Tirna Scithe"] = "MISTS",
            ["Halls of Atonement"] = "HOA",
            ["Theater of Pain"] = "TOP",
            ["De Other Side"] = "DOS",
            ["Spires of Ascension"] = "SOA",
            ["Sanguine Depths"] = "SD",
        }
        
        local dungeonAbbrev = dungeonAbbreviations[char.mythicKey.dungeonName] or char.mythicKey.dungeonName:sub(1, 4):upper()
        
        -- Create a container frame centered in the column
        local keyContainer = CreateFrame("Frame", nil, row)
        keyContainer:SetSize(CHAR_ROW_COLUMNS.mythicKey.width, 20)
        keyContainer:SetPoint("CENTER", row, "LEFT", mythicKeyOffset + (CHAR_ROW_COLUMNS.mythicKey.width / 2), 0)
        
        -- Inner container for centering all elements as a group
        local innerContainer = CreateFrame("Frame", nil, keyContainer)
        innerContainer:SetSize(1, 16)  -- Height set, width will be calculated
        innerContainer:SetPoint("CENTER", keyContainer, "CENTER", 0, 0)
        
        -- Key icon (ChromieTime-32x32 atlas) - 16x16 size
        local keyIcon = innerContainer:CreateTexture(nil, "ARTWORK")
        keyIcon:SetSize(16, 16)
        keyIcon:SetPoint("LEFT", 0, 0)
        keyIcon:SetAtlas("ChromieTime-32x32", false)
        
        -- Level number (next to icon)
        local keyLevelText = innerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        keyLevelText:SetPoint("LEFT", keyIcon, "RIGHT", 4, 0)
        keyLevelText:SetText(string.format("|cffff8000%d|r", char.mythicKey.level))
        
        -- Bullet separator
        local bulletText = innerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bulletText:SetPoint("LEFT", keyLevelText, "RIGHT", 6, 0)
        bulletText:SetText("|cff999999•|r")
        
        -- Dungeon abbreviation
        local dungeonText = innerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dungeonText:SetPoint("LEFT", bulletText, "RIGHT", 6, 0)
        dungeonText:SetText(string.format("|cffffd700%s|r", dungeonAbbrev))
        
        -- Calculate total width and resize innerContainer
        local totalWidth = 16 + 4 + keyLevelText:GetStringWidth() + 6 + bulletText:GetStringWidth() + 6 + dungeonText:GetStringWidth()
        innerContainer:SetWidth(totalWidth)
    else
        -- No key - centered
        local noKeyContainer = CreateFrame("Frame", nil, row)
        noKeyContainer:SetSize(CHAR_ROW_COLUMNS.mythicKey.width, 20)
        noKeyContainer:SetPoint("CENTER", row, "LEFT", mythicKeyOffset + (CHAR_ROW_COLUMNS.mythicKey.width / 2), 0)
        
        local mythicKeyText = noKeyContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        mythicKeyText:SetPoint("CENTER", noKeyContainer, "CENTER", 0, 0)
        mythicKeyText:SetText("|cffffffffNo Key|r")  -- Pure white
    end
    
    -- COLUMN 11: Last Seen (RIGHT side, before delete button)
    if isCurrent then
        -- Show online icon for current character (right side)
        CreateOnlineIndicator(row, 20, "RIGHT", -10, 0)  -- 10px from right edge
    else
        -- Show last seen text for other characters
        local timeDiff = char.lastSeen and (time() - char.lastSeen) or math.huge
        
        if timeDiff < 60 then
            -- Recently online - show green icon (right side, before delete button)
            local rightOffset = -62  -- More space: 22px delete + 30px space + 10px padding
            CreateOnlineIndicator(row, 20, "RIGHT", rightOffset, 0)
        else
            -- Show time text (right side, before delete button)
            local lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            local rightOffset = -62  -- More space between Last Seen and Delete
            lastSeenText:SetPoint("RIGHT", rightOffset, 0)
            lastSeenText:SetWidth(100)
            lastSeenText:SetJustifyH("RIGHT")
            
            local lastSeenStr = ""
            if timeDiff < 3600 then
                lastSeenStr = math.floor(timeDiff / 60) .. "m ago"
            elseif timeDiff < 86400 then
                lastSeenStr = math.floor(timeDiff / 3600) .. "h ago"
            else
                lastSeenStr = math.floor(timeDiff / 86400) .. "d ago"
            end
            
            if lastSeenStr == "" then
                lastSeenStr = "Unknown"
            end
            
            lastSeenText:SetText(lastSeenStr)
            lastSeenText:SetTextColor(1, 1, 1)  -- White (last seen time)
        end
    end
    
    -- COLUMN 12: Delete button (RIGHT side) - Only show if NOT current character
    if not isCurrent then
        local deleteBtn = CreateFrame("Button", nil, row)
        deleteBtn:SetSize(22, 22)
        deleteBtn:SetPoint("RIGHT", -10, 0)  -- 10px from right edge
        
        local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
        deleteIcon:SetAllPoints()
        deleteIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        deleteIcon:SetDesaturated(true)
        deleteIcon:SetVertexColor(0.8, 0.2, 0.2)
        deleteBtn.icon = deleteIcon
        deleteBtn.charKey = charKey
        deleteBtn.charName = char.name or "Unknown"
        
        deleteBtn:SetScript("OnClick", function(self)
            -- Show confirmation dialog
            StaticPopupDialogs["WARBANDNEXUS_DELETE_CHARACTER"] = {
                text = string.format(
                    "|cffff9900Delete Character?|r\n\n" ..
                    "Are you sure you want to delete |cff00ccff%s|r?\n\n" ..
                    "This will remove:\n" ..
                    "• Gold data\n" ..
                    "• Personal bank cache\n" ..
                    "• Profession info\n" ..
                    "• PvE progress\n" ..
                    "• All statistics\n\n" ..
                    "|cffff0000This action cannot be undone!|r",
                    self.charName
                ),
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    local success = WarbandNexus:DeleteCharacter(self.charKey)
                    if success and WarbandNexus.RefreshUI then
                        WarbandNexus:RefreshUI()
                    end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            
            StaticPopup_Show("WARBANDNEXUS_DELETE_CHARACTER")
        end)
        
        deleteBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("|cffff5555Delete Character|r\nClick to remove this character's data")
            GameTooltip:Show()
        end)
        
        deleteBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
        
    -- Hover effect + Tooltip
    row:SetScript("OnEnter", function(self)
        bg:SetColorTexture(0.18, 0.18, 0.25, 1)
        
        -- Show reorder buttons on hover (no animation)
        if showReorder and self.reorderButtons then
            self.reorderButtons:SetAlpha(1)
            self.reorderButtons:Show()
        end
        
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(char.name or "Unknown", classColor.r, classColor.g, classColor.b)
        GameTooltip:AddLine(char.realm or "", 0.5, 0.5, 0.5)
        
        if isCurrent then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ff00● Currently Online|r", 0.3, 1, 0.3)
        end
        
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine("Class:", char.class or "Unknown", 1, 1, 1, classColor.r, classColor.g, classColor.b)
        GameTooltip:AddDoubleLine("Level:", tostring(char.level or 1), 1, 1, 1, 1, 1, 1)
        if char.itemLevel and char.itemLevel > 0 then
            GameTooltip:AddDoubleLine("Item Level:", tostring(char.itemLevel), 1, 1, 1, 1, 0.82, 0)
        end
        GameTooltip:AddDoubleLine("Gold:", FormatMoney(char.gold or 0, 12), 1, 1, 1, 1, 1, 1)  -- Use new money format
        if char.faction then
            GameTooltip:AddDoubleLine("Faction:", char.faction, 1, 1, 1, 0.7, 0.7, 0.7)
        end
        if char.race then
            GameTooltip:AddDoubleLine("Race:", char.race, 1, 1, 1, 0.7, 0.7, 0.7)
        end
        
        -- Mythic Keystone info
        if char.mythicKey and char.mythicKey.level then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffff8000Mythic Keystone|r")
            GameTooltip:AddDoubleLine("Level:", "+" .. char.mythicKey.level, 1, 1, 1, 1, 0.5, 0)
            GameTooltip:AddDoubleLine("Dungeon:", char.mythicKey.dungeonName, 1, 1, 1, 0.8, 0.8, 1)
        end
        
        
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        bg:SetColorTexture(unpack(self.bgColor))
        GameTooltip:Hide()
        
        -- Hide reorder buttons (no animation, direct hide)
        if showReorder and self.reorderButtons then
            self.reorderButtons:Hide()
        end
    end)
    
    return yOffset + 40  -- Row height (38) + spacing (2)
end

--============================================================================
-- REORDER CHARACTER IN LIST
--============================================================================

function WarbandNexus:ReorderCharacter(char, charList, listKey, direction)
    if not char or not listKey then return end
    
    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
    
    -- Don't update lastSeen when reordering (keep current timestamps)
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
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
        local currentPlayerName = UnitName("player")
        local currentPlayerRealm = GetRealmName()
        local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
        
        for _, c in ipairs(allChars) do
            local key = (c.name or "Unknown") .. "-" .. (c.realm or "Unknown")
            -- Skip current player
            if key ~= currentPlayerKey then
                local isFav = self:IsFavoriteCharacter(key)
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
    if newIndex < 1 or newIndex > #customOrder then return end
    
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
