--[[
    Warband Nexus - Characters Tab
    Display all tracked characters with gold, level, and last seen info
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local function GetCOLORS()
    return ns.UI_COLORS
end
local CreateCard = ns.UI_CreateCard
local FormatGold = ns.UI_FormatGold
local FormatMoney = ns.UI_FormatMoney
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateFactionIcon = ns.UI_CreateFactionIcon
local CreateRaceIcon = ns.UI_CreateRaceIcon
local CreateClassIcon = ns.UI_CreateClassIcon
local CreateFavoriteButton = ns.UI_CreateFavoriteButton
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local GetColumnOffset = ns.UI_GetColumnOffset
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local CreateIcon = ns.UI_CreateIcon -- Factory for icons
local FormatNumber = ns.UI_FormatNumber
-- Pooling constants
local AcquireCharacterRow = ns.UI_AcquireCharacterRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

local CHAR_ROW_COLUMNS = ns.UI_CHAR_ROW_COLUMNS
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.rowHeight or 26
local ROW_SPACING = UI_LAYOUT.rowSpacing or 28
local HEADER_HEIGHT = UI_LAYOUT.HEADER_HEIGHT or 32
local HEADER_SPACING = UI_LAYOUT.headerSpacing or 40
local SECTION_SPACING = UI_LAYOUT.betweenSections or 8
local BASE_INDENT = UI_LAYOUT.BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = UI_LAYOUT.SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = UI_LAYOUT.SIDE_MARGIN or 10
local TOP_MARGIN = UI_LAYOUT.TOP_MARGIN or 8

--============================================================================
-- DRAW CHARACTER LIST
--============================================================================

function WarbandNexus:DrawCharacterList(parent)
    self.recentlyExpanded = self.recentlyExpanded or {}
    local yOffset = 8 -- Top padding for breathing room
    local width = parent:GetWidth() - 20
    
    -- Get all characters (cached for performance)
    local characters = self.GetCachedCharacters and self:GetCachedCharacters() or self:GetAllCharacters()

    -- PERFORMANCE: Release pooled frames
    if ReleaseAllPooledChildren then ReleaseAllPooledChildren(parent) end
    
    -- Get current player key
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentPlayerKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Apply visuals (dark background, accent border)
    if ApplyVisuals then
        local COLORS = GetCOLORS()
        ApplyVisuals(titleCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Header icon with ring border (standardized system from SharedWidgets)
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("characters"))
    headerIcon.border:SetPoint("CENTER", titleCard, "LEFT", 35, 0)  -- Icon centered vertically at 35px from left
    
    -- Create text container (manual setup due to special requirements: colored title, header font)
    local titleTextContainer = CreateFrame("Frame", nil, titleCard)
    titleTextContainer:SetSize(200, 40)
    
    local titleText = FontManager:CreateFontString(titleTextContainer, "header", "OVERLAY")
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Your Characters|r")
    titleText:SetJustifyH("LEFT")
    
    local subtitleText = FontManager:CreateFontString(titleTextContainer, "subtitle", "OVERLAY")
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetText(FormatNumber(#characters) .. " characters tracked")
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
    
    -- Show "Planner" toggle button in title bar if planner is hidden
    if self.db and self.db.profile and self.db.profile.showWeeklyPlanner == false then
        local showPlannerBtn = CreateThemedButton(titleCard, "Show Planner", 90)
        showPlannerBtn:SetPoint("RIGHT", -15, 0)
        showPlannerBtn:SetScript("OnClick", function()
            self.db.profile.showWeeklyPlanner = true
            if self.RefreshUI then self:RefreshUI() end
        end)
    end
    
    titleCard:Show()
    
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
            
            -- Apply visuals with accent border
            if ApplyVisuals then
                local COLORS = GetCOLORS()
                ApplyVisuals(plannerCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
            end
            
            -- Header row with collapse button
            local collapseBtnFrame = CreateIcon(plannerCard, plannerCollapsed and "QuestLog-icon-Expand" or "QuestLog-icon-shrink", 24, true, nil, true)
            collapseBtnFrame:SetPoint("LEFT", 12, plannerCollapsed and 0 or (plannerHeight/2 - 20))
            collapseBtnFrame:EnableMouse(true)
            -- RegisterForClicks is Button-only, Frame uses OnMouseDown script instead
            
            local collapseIcon = collapseBtnFrame.texture
            
            collapseBtnFrame:SetScript("OnMouseDown", function()
                self.db.profile.weeklyPlannerCollapsed = not self.db.profile.weeklyPlannerCollapsed
                    if not self.db.profile.weeklyPlannerCollapsed then
                        self.recentlyExpanded["weeklyPlanner"] = GetTime()
                    end
                    if self.RefreshUI then self:RefreshUI() end
                end)
                
                local plannerIconFrame = CreateIcon(plannerCard, "Interface\\Icons\\INV_Misc_Note_01", 24, false, nil, true)
                plannerIconFrame:SetPoint("LEFT", collapseBtnFrame, "RIGHT", 8, 0)
                plannerIconFrame:Show()
                
            local plannerTitle = FontManager:CreateFontString(plannerCard, "subtitle", "OVERLAY")
            plannerTitle:SetPoint("LEFT", plannerIconFrame, "RIGHT", 10, 0)
            if alertCount > 0 then
                plannerTitle:SetText("|cff88cc88This Week|r  |cff666666(" .. alertCount .. " task" .. (alertCount > 1 and "s" or "") .. ")|r")
            else
                plannerTitle:SetText("|cff88cc88This Week|r  |cff44aa44All caught up!|r")
            end
            
            -- Hide button on the right
            local hideBtn = CreateThemedButton(plannerCard, "Hide", 70)
            hideBtn:SetPoint("RIGHT", -12, plannerCollapsed and 0 or (plannerHeight/2 - 20))
            hideBtn:SetScript("OnClick", function()
                self.db.profile.showWeeklyPlanner = false
                if self.RefreshUI then self:RefreshUI() end
            end)
            
            -- Draw alerts if not collapsed
            if not plannerCollapsed then
                if alertCount > 0 then
                    local alertY = -44
                    local maxAlerts = 8  -- Limit visible alerts
                    
                    local shouldAnimate = self.recentlyExpanded["weeklyPlanner"] and (GetTime() - self.recentlyExpanded["weeklyPlanner"] < 0.5)
                    for i, alert in ipairs(alerts) do
                        if i > maxAlerts then break end
                        
                        local alertRow = CreateFrame("Frame", nil, plannerCard)
                        
                        -- Smart Animation
                        if shouldAnimate then
                            alertRow:SetAlpha(0)
                            local anim = alertRow:CreateAnimationGroup()
                            local fade = anim:CreateAnimation("Alpha")
                            fade:SetFromAlpha(0)
                            fade:SetToAlpha(1)
                            fade:SetDuration(0.15)
                            fade:SetStartDelay(i * 0.05)
                            fade:SetSmoothing("OUT")
                            anim:SetScript("OnFinished", function() alertRow:SetAlpha(1) end)
                            anim:Play()
                        end
                        
                        alertRow:SetSize(plannerCard:GetWidth() - 24, 24)
                        alertRow:SetPoint("TOPLEFT", 12, alertY)
                        
                        -- Alert icon
                        local aIconFrame = CreateIcon(alertRow, alert.icon or "Interface\\Icons\\INV_Misc_QuestionMark", 20, false, nil, true)
                        aIconFrame:SetPoint("LEFT", 0, 0)
                        aIconFrame:Show()
                        
                        -- Priority indicator (color bullet)
                        local priorityColors = {
                            [1] = {1, 0.3, 0.3},    -- High priority (vault) - red
                            [2] = {1, 0.6, 0},      -- Medium (knowledge) - orange
                            [3] = {0.3, 0.7, 1},    -- Low (reputation) - blue
                        }
                        local pColor = priorityColors[alert.priority] or {0.7, 0.7, 0.7}
                        
                        local bulletFrame = CreateIcon(alertRow, "Interface\\COMMON\\Indicator-Green", 8, false, nil, true)
                        bulletFrame:SetPoint("LEFT", aIconFrame, "RIGHT", 6, 0)
                        bulletFrame.texture:SetVertexColor(pColor[1], pColor[2], pColor[3], 1)
                        
                        -- Character name + message
                        local alertText = FontManager:CreateFontString(alertRow, "small", "OVERLAY")
                        alertText:SetPoint("LEFT", bulletFrame, "RIGHT", 6, 0)
                        alertText:SetText((alert.character or "") .. ": " .. (alert.message or ""))
                        alertText:SetJustifyH("LEFT")
                        
                        alertY = alertY - 26
                    end
                    
                    -- Show "and X more..." if truncated
                    if alertCount > maxAlerts then
                        local moreText = FontManager:CreateFontString(plannerCard, "small", "OVERLAY")
                        moreText:SetPoint("BOTTOMLEFT", 48, 8)
                        moreText:SetText("|cff666666...and " .. (alertCount - maxAlerts) .. " more|r")
                    end
                else
                    -- Empty state - all caught up!
                    local emptyIconFrame = CreateIcon(plannerCard, "Interface\\RaidFrame\\ReadyCheck-Ready", 24, false, nil, true)
                    emptyIconFrame:SetPoint("LEFT", 48, -10)
                    emptyIconFrame:Show()
                    
                    local emptyText = FontManager:CreateFontString(plannerCard, "small", "OVERLAY")
                    emptyText:SetPoint("LEFT", emptyIconFrame, "RIGHT", 8, 0)
                    emptyText:SetText("|cff888888No pending tasks for recently active characters.|r")
                end
            end
            
            plannerCard:Show()
            
            yOffset = yOffset + plannerHeight + 8
        end
    end)
    -- If planner fails, just continue with the rest of the UI
    
    -- ===== TOTAL GOLD DISPLAY =====
    local currentCharGold = 0
    local totalCharGold = 0
    
    for _, char in ipairs(characters) do
        local charGold = WarbandNexus:GetCharTotalCopper(char)
        totalCharGold = totalCharGold + charGold
        
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
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        local COLORS = GetCOLORS()
        ApplyVisuals(charGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Current Character icon (same as Characters header)
    -- Use factory for standardized card header layout
    local CreateCardHeaderLayout = ns.UI_CreateCardHeaderLayout
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    local cg1Layout = CreateCardHeaderLayout(
        charGoldCard,
        GetCharacterSpecificIcon(),
        40,
        true,
        "CURRENT CHARACTER",
        FormatMoney(currentCharGold, 14),
        "subtitle",
        "body"
    )
    
    -- NO TRACKING: Numbers rarely overflow (formatted gold)
    
    -- Warband Gold Card (Middle)
    local wbGoldCard = CreateCard(parent, 90)
    wbGoldCard:SetWidth(threeCardWidth)
    wbGoldCard:SetPoint("LEFT", charGoldCard, "RIGHT", cardSpacing, 0)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        local COLORS = GetCOLORS()
        ApplyVisuals(wbGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Use factory for standardized card header layout
    local wb1Layout = CreateCardHeaderLayout(
        wbGoldCard,
        "warbands-icon",
        40,
        true,
        "WARBAND GOLD",
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
        local COLORS = GetCOLORS()
        ApplyVisuals(totalGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Use factory for standardized card header layout
    local tg1Layout = CreateCardHeaderLayout(
        totalGoldCard,
        "BonusLoot-Chest",
        36,
        true,
        "TOTAL GOLD",
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
    
    -- Sort both groups with custom order
    favorites = sortCharacters(favorites, "favorites")
    regular = sortCharacters(regular, "regular")
    
    -- Update current character's lastSeen to now (so it shows as online)
    if self.db.global.characters and self.db.global.characters[currentPlayerKey] then
        self.db.global.characters[currentPlayerKey].lastSeen = time()
    end
    
    -- ===== EMPTY STATE =====
    if #characters == 0 then
        local emptyIconFrame = CreateIcon(parent, "Interface\\Icons\\Ability_Spy", 48, false, nil, true)
        emptyIconFrame:SetPoint("TOP", 0, -yOffset - 30)
        emptyIconFrame.texture:SetDesaturated(true)
        emptyIconFrame.texture:SetAlpha(0.4)
        emptyIconFrame:Show()
        
        local emptyText = FontManager:CreateFontString(parent, "title", "OVERLAY")
        emptyText:SetPoint("TOP", 0, -yOffset - 90)
        emptyText:SetText("|cff666666No characters tracked yet|r")
        
        local emptyDesc = FontManager:CreateFontString(parent, "body", "OVERLAY")
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
        string.format("Favorites |cff888888(%s)|r", FormatNumber(#favorites)),
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
    favHeader:SetPoint("TOPLEFT", 10, -yOffset)
    favHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        local COLORS = GetCOLORS()
        ApplyVisuals(favHeader, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    -- Remove vertex color tinting for atlas icon
    -- (Atlas icons should use their natural colors)
    
    yOffset = yOffset + HEADER_HEIGHT  -- Header height (32px)
    
    if self.db.profile.ui.favoritesExpanded then
        if #favorites > 0 then
            for i, char in ipairs(favorites) do
                -- Calculate actual position in list (not loop index)
                local actualPosition = nil
                for pos, c in ipairs(favorites) do
                    if c == char then
                        actualPosition = pos
                        break
                    end
                end
                local shouldAnimate = self.recentlyExpanded["favorites"] and (GetTime() - self.recentlyExpanded["favorites"] < 0.5)
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, true, true, favorites, "favorites", actualPosition, #favorites, currentPlayerKey, shouldAnimate)
            end
        else
            -- Empty state
            yOffset = DrawSectionEmptyState(parent, "No favorite characters yet. Click the star icon to favorite a character.", yOffset, 30, width - 40)
        end
    end
    
    -- ===== REGULAR CHARACTERS SECTION (Always show header) =====
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    local charHeader = CreateCollapsibleHeader(
        parent,
        string.format("Characters |cff888888(%s)|r", FormatNumber(#regular)),
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
    charHeader:SetPoint("TOPLEFT", 10, -yOffset)
    charHeader:SetPoint("TOPRIGHT", -10, -yOffset)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        local COLORS = GetCOLORS()
        ApplyVisuals(charHeader, {0.08, 0.08, 0.10, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    yOffset = yOffset + HEADER_HEIGHT  -- Header height (32px)
    
    if self.db.profile.ui.charactersExpanded then
        if #regular > 0 then
            for i, char in ipairs(regular) do
                -- Calculate actual position in list (not loop index)
                local actualPosition = nil
                for pos, c in ipairs(regular) do
                    if c == char then
                        actualPosition = pos
                        break
                    end
                end
                local shouldAnimate = self.recentlyExpanded["characters"] and (GetTime() - self.recentlyExpanded["characters"] < 0.5)
                yOffset = self:DrawCharacterRow(parent, char, i, width, yOffset, false, true, regular, "regular", actualPosition, #regular, currentPlayerKey, shouldAnimate)
            end
        else
            -- Empty state
            yOffset = DrawSectionEmptyState(parent, "All characters are favorited!", yOffset, 30, width - 40)
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
    row:SetPoint("TOPLEFT", 10, -yOffset)
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
    
    -- Set alternating background colors
    local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
    local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
    local bgColor = (index % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
    
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    row.bgColor = bgColor
    
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
            local newStatus = WarbandNexus:ToggleFavoriteCharacter(charKey)
            WarbandNexus:RefreshUI()
            return newStatus
        end)
    end
    
    -- Tooltip for favorite button
    if ShowTooltip and row.favButton.SetScript then
        row.favButton:SetScript("OnEnter", function(self)
            local isFav = WarbandNexus:IsFavoriteCharacter(charKey)
            ShowTooltip(self, {
                type = "custom",
                title = isFav and "Remove from Favorites" or "Add to Favorites",
                lines = {
                    {text = "Favorite characters appear at the top of the list", color = {0.8, 0.8, 0.8}},
                    {type = "spacer"},
                    {text = "|cff00ff00Click|r to toggle", color = {1, 1, 1}}
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
    
    
    -- COLUMN 2: Faction icon
    local factionOffset = GetColumnOffset("faction")
    if char.faction then
        if not row.factionIcon then
            row.factionIcon = CreateFactionIcon(row, char.faction, CHAR_ROW_COLUMNS.faction.width, "LEFT", factionOffset + (CHAR_ROW_COLUMNS.faction.spacing / 2), 0)
        end
        -- Update texture based on faction
        if char.faction == "Alliance" then
            row.factionIcon:SetAtlas("AllianceEmblem")
        elseif char.faction == "Horde" then
            row.factionIcon:SetAtlas("HordeEmblem")
        else
            -- Fallback/Neutral
            row.factionIcon:SetAtlas("bfa-landingbutton-alliance-up") -- Placeholder or generic
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
        -- Update existing icon atlas manually.
        local raceAtlas = ns.UI_GetRaceAtlas and ns.UI_GetRaceAtlas(char.raceFile, char.gender) or "raceicon-" .. (char.raceFile or "human") .. "-" .. (char.gender == 3 and "female" or "male")
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
        char.name or "Unknown"))
        
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
    row.realmText:SetText("|cffffffff" .. (char.realm or "Unknown") .. "|r")
    
    
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
        row.itemLevelText:SetText(string.format("|cffffd700iLvl %d|r", itemLevel))
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
    local totalCopper = WarbandNexus:GetCharTotalCopper(char)
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
        
        local function SetupProfIcon(prof, idx)
            if not prof or not prof.icon then return end
            
            -- Reuse or create
            local pFrame = row.profIcons[idx]
            if not pFrame then
                pFrame = CreateIcon(row, nil, iconSize, false, nil, true)
                pFrame:EnableMouse(true)
                pFrame.icon = pFrame.texture
                -- SetHighlightTexture is for Buttons only, Frame doesn't have this method
                
                row.profIcons[idx] = pFrame
            end
            
            -- Clear previous position and set new centered position
            pFrame:ClearAllPoints()
            pFrame:SetPoint("LEFT", currentProfX, 0)
            pFrame.icon:SetTexture(prof.icon)
            pFrame:Show()
            
            -- Setup tooltip
            pFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(prof.name or "Unknown Profession", 1, 1, 1)
                if prof.skill and prof.maxSkill then
                    GameTooltip:AddLine(string.format("Skill: %d / %d", prof.skill, prof.maxSkill), 0.8, 0.8, 0.8)
                end
                GameTooltip:Show()
            end)
            pFrame:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
            end)
            
            return true
        end
        
        local pIdx = 1
        -- Primary
        if char.professions[1] then 
            SetupProfIcon(char.professions[1], pIdx) 
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        if char.professions[2] then 
            SetupProfIcon(char.professions[2], pIdx) 
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        -- Secondary
        for _, sec in ipairs(secondaries) do
            if char.professions[sec] then
                SetupProfIcon(char.professions[sec], pIdx)
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
        local keystoneText = "|cff888888+0|r |cff666666•|r |cffaaaaaaNone|r"
        
        row.keystoneText:SetText(keystoneText)
        
        -- Dimmed, desaturated icon
        row.keystoneIcon:SetDesaturated(true)
        row.keystoneIcon:SetVertexColor(0.6, 0.6, 0.6)
        row.keystoneIcon:SetAlpha(0.4)
    end
    
    row.keystoneIcon:Show()
    row.keystoneText:Show()
    
    
    -- Reorder Buttons (right-aligned column, centered content)
    if not row.reorderButtons then
        local rb = CreateFrame("Frame", nil, row)
        rb:SetSize(60, 46)  -- Full row height for click area
        rb:SetPoint("RIGHT", -120, 0)  -- Right-aligned: -(80+40) from right edge
        rb:SetAlpha(0.7)  -- Start at 0.7 (normal state)
        rb.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
        
        rb.up = CreateFrame("Button", nil, rb)
        rb.up:SetSize(18, 18)  -- Larger buttons for better usability
        rb.up:SetPoint("CENTER", -12, 0)  -- Centered, left side
        rb.up:SetNormalAtlas("housing-floor-arrow-up-default")
        
        rb.down = CreateFrame("Button", nil, rb)
        rb.down:SetSize(18, 18)  -- Larger buttons for better usability
        rb.down:SetPoint("CENTER", 12, 0)  -- Centered, right side
        rb.down:SetNormalAtlas("housing-floor-arrow-down-default")
        
        row.reorderButtons = rb
    end
    
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
    
    
    -- COLUMN: Last Seen (right-aligned column, centered content)
    if isCurrent then
        if not row.onlineText then
            row.onlineText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.onlineText:SetPoint("RIGHT", -40, 0)  -- Right-aligned: -40 (delete width)
            row.onlineText:SetWidth(80)  -- Column width
            row.onlineText:SetJustifyH("CENTER")
            row.onlineText:SetText("Online")
            row.onlineText:SetTextColor(0, 1, 0) 
        end
        row.onlineText:Show()
        if row.lastSeenText then row.lastSeenText:Hide() end
    else
        if row.onlineText then row.onlineText:Hide() end
        
        local timeDiff = char.lastSeen and (time() - char.lastSeen) or math.huge
        
        if not row.lastSeenText then
            row.lastSeenText = FontManager:CreateFontString(row, "body", "OVERLAY")
            row.lastSeenText:SetPoint("RIGHT", -40, 0)  -- Right-aligned: -40 (delete width)
            row.lastSeenText:SetWidth(80)  -- Column width
            row.lastSeenText:SetJustifyH("CENTER")
        end
        
        local lastSeenStr = ""
        if timeDiff < 60 then
            lastSeenStr = "< 1m ago"
        elseif timeDiff < 3600 then
            lastSeenStr = math.floor(timeDiff / 60) .. "m ago"
        elseif timeDiff < 86400 then
            lastSeenStr = math.floor(timeDiff / 3600) .. "h ago"
        else
            lastSeenStr = math.floor(timeDiff / 86400) .. "d ago"
        end
        row.lastSeenText:SetText(lastSeenStr)
        row.lastSeenText:SetTextColor(1, 1, 1)
        row.lastSeenText:Show()
    end
    
    
    -- COLUMN: Delete button (right-aligned column, centered content)
    if not isCurrent then
        if not row.deleteBtn then
            -- Create as Button (not Frame) to support OnClick
            local deleteBtn = CreateFrame("Button", nil, row)
            deleteBtn:SetSize(24, 24)  -- Icon size
            deleteBtn:SetPoint("CENTER", row, "RIGHT", -20, 0)  -- Centered in 40px column (column center at -20)
            deleteBtn.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
            
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
        
        row.deleteBtn.charKey = charKey
        row.deleteBtn.charName = char.name or "Unknown"
        
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
                    print("[WarbandNexus] ERROR: CreateExternalWindow not found!")
                    return
                end
                
                -- Create custom delete confirmation dialog
                local dialog, contentFrame = CreateExternalWindow({
                    name = "DeleteCharacterDialog",
                    title = "Delete Character?",
                    icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
                    width = 420,
                    height = 180,
                })
                
                if not dialog then
                    print("[WarbandNexus] ERROR: Failed to create delete dialog!")
                    return
                end
                
                -- Warning text
                local warning = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                warning:SetPoint("TOP", contentFrame, "TOP", 0, -20)
                warning:SetWidth(380)
                warning:SetJustifyH("CENTER")
                warning:SetTextColor(1, 0.85, 0.1)  -- Gold/Orange
                warning:SetText(string.format("Are you sure you want to delete |cff00ccff%s|r?", charName or "this character"))
                
                local subtext = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                subtext:SetPoint("TOP", warning, "BOTTOM", 0, -10)
                subtext:SetWidth(380)
                subtext:SetJustifyH("CENTER")
                subtext:SetTextColor(1, 0.3, 0.3)  -- Red
                subtext:SetText("|cffff0000This action cannot be undone!|r")
                
                -- Buttons container
                local btnContainer = CreateFrame("Frame", nil, contentFrame)
                btnContainer:SetSize(320, 40)
                btnContainer:SetPoint("BOTTOM", contentFrame, "BOTTOM", 0, 20)
                
                -- Delete button (LEFT)
                local deleteBtn = CreateThemedButton and CreateThemedButton(btnContainer, "Delete", 150, 36) or CreateFrame("Button", nil, btnContainer)
                if not CreateThemedButton then
                    deleteBtn:SetSize(150, 36)
                    deleteBtn:SetNormalFontObject("GameFontNormal")
                    deleteBtn:SetText("Delete")
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
                local cancelBtn = CreateThemedButton and CreateThemedButton(btnContainer, "Cancel", 150, 36) or CreateFrame("Button", nil, btnContainer)
                if not CreateThemedButton then
                    cancelBtn:SetSize(150, 36)
                    cancelBtn:SetNormalFontObject("GameFontNormal")
                    cancelBtn:SetText("Cancel")
                end
                cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
                cancelBtn:SetScript("OnClick", function()
                    dialog:Hide()
                end)
                
                -- Show dialog
                dialog:Show()
            end)
        end
        
        -- Tooltip for delete button
        if ShowTooltip and row.deleteBtn.SetScript then
            row.deleteBtn:SetScript("OnEnter", function(self)
                ShowTooltip(self, {
                    type = "custom",
                    title = "|cffff6600Delete Character|r",
                    lines = {
                        {text = "Remove " .. (self.charName or "this character") .. " from tracking", color = {0.8, 0.8, 0.8}},
                        {type = "spacer"},
                        {text = "|cffff0000This action cannot be undone!|r", color = {1, 0.2, 0.2}},
                        {type = "spacer"},
                        {text = "|cff00ff00Click|r to delete", color = {1, 1, 1}}
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
    
    return yOffset + 46 + UI_LAYOUT.betweenRows  -- Updated from 38 to 46 (20% increase)
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
