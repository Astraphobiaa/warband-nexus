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
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateFactionIcon = ns.UI_CreateFactionIcon
local CreateRaceIcon = ns.UI_CreateRaceIcon
local CreateClassIcon = ns.UI_CreateClassIcon
local CreateFavoriteButton = ns.UI_CreateFavoriteButton
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local CreateOnlineIndicator = ns.UI_CreateOnlineIndicator
local GetColumnOffset = ns.UI_GetColumnOffset
local CreateCharRowColumnDivider = ns.UI_CreateCharRowColumnDivider
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local CreateIcon = ns.UI_CreateIcon -- Factory for icons
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
        local showPlannerBtn = CreateThemedButton(titleCard, "Show Planner", 90)
        showPlannerBtn:SetPoint("RIGHT", -15, 0)
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
                
                collapseBtnFrame:SetScript("OnEnter", function(btn)
                    collapseIcon:SetAtlas(plannerCollapsed and "QuestLog-icon-Expand" or "QuestLog-icon-shrink")
                    collapseIcon:SetAlpha(1.0)  -- Highlight on hover
                end)
                collapseBtnFrame:SetScript("OnLeave", function(btn)
                    collapseIcon:SetAtlas(plannerCollapsed and "QuestLog-icon-Expand" or "QuestLog-icon-shrink")
                    collapseIcon:SetAlpha(0.85)  -- Normal state
                end)
                
                local plannerIconFrame = CreateIcon(plannerCard, "Interface\\Icons\\INV_Misc_Note_01", 24, false, nil, true)
                plannerIconFrame:SetPoint("LEFT", collapseBtnFrame, "RIGHT", 8, 0)
                
            local plannerTitle = plannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
                        local alertText = alertRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                        alertText:SetPoint("LEFT", bulletFrame, "RIGHT", 6, 0)
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
                    local emptyIconFrame = CreateIcon(plannerCard, "Interface\\RaidFrame\\ReadyCheck-Ready", 24, false, nil, true)
                    emptyIconFrame:SetPoint("LEFT", 48, -10)
                    
                    local emptyText = plannerCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    emptyText:SetPoint("LEFT", emptyIconFrame, "RIGHT", 8, 0)
                    emptyText:SetText("|cff888888No pending tasks for recently active characters.|r")
                end
            end
            
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
    local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
    local cg1IconFrame = CreateIcon(charGoldCard, GetCharacterSpecificIcon(), 40, true, nil, true)  -- atlas, no border
    cg1IconFrame:SetPoint("LEFT", 15, 0)
    
    local cg1Label = charGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cg1Label:SetPoint("TOPLEFT", cg1IconFrame, "TOPRIGHT", 12, -2)
    cg1Label:SetText("CURRENT CHARACTER")
    cg1Label:SetTextColor(1, 1, 1)  -- White
    
    local cg1Value = charGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cg1Value:SetPoint("BOTTOMLEFT", cg1IconFrame, "BOTTOMRIGHT", 12, 0)
    cg1Value:SetText(FormatMoney(currentCharGold, 14))
    
    -- Warband Gold Card (Middle)
    local wbGoldCard = CreateCard(parent, 90)
    wbGoldCard:SetWidth(threeCardWidth)
    wbGoldCard:SetPoint("LEFT", charGoldCard, "RIGHT", cardSpacing, 0)
    
    -- Apply visuals with accent border
    if ApplyVisuals then
        local COLORS = GetCOLORS()
        ApplyVisuals(wbGoldCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    
    local wb1IconFrame = CreateIcon(wbGoldCard, "warbands-icon", 40, true, nil, true)  -- atlas, no border
    wb1IconFrame:SetPoint("LEFT", 15, 0)
    
    local wb1Label = wbGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    wb1Label:SetPoint("TOPLEFT", wb1IconFrame, "TOPRIGHT", 12, -2)
    wb1Label:SetText("WARBAND GOLD")
    wb1Label:SetTextColor(1, 1, 1)  -- White
    
    local wb1Value = wbGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    wb1Value:SetPoint("BOTTOMLEFT", wb1IconFrame, "BOTTOMRIGHT", 12, 0)
    wb1Value:SetText(FormatMoney(warbandBankGold, 14))
    
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
    
    local tg1IconFrame = CreateIcon(totalGoldCard, "BonusLoot-Chest", 36, true, nil, true)  -- atlas, no border
    tg1IconFrame:SetPoint("LEFT", 15, 0)
    
    local tg1Label = totalGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tg1Label:SetPoint("TOPLEFT", tg1IconFrame, "TOPRIGHT", 12, -2)
    tg1Label:SetText("TOTAL GOLD")
    tg1Label:SetTextColor(1, 1, 1)  -- White
    
    local tg1Value = totalGoldCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    tg1Value:SetPoint("BOTTOMLEFT", tg1IconFrame, "BOTTOMRIGHT", 12, 0)
    tg1Value:SetText(FormatMoney(totalWithWarband, 14))
    
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
        string.format("Characters |cff888888(%d)|r", #regular),
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
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -8)
        row.nameText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
    end
    row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.name or "Unknown"))
        
    if not row.realmText then
        row.realmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.realmText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -22)
        row.realmText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetTextColor(1, 1, 1)
    end
    row.realmText:SetText("|cffffffff" .. (char.realm or "Unknown") .. "|r")
    
    -- COLUMN 6: Level
    local levelOffset = GetColumnOffset("level")
    if not row.levelText then
        row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.levelText:SetPoint("LEFT", levelOffset, 0)
        row.levelText:SetWidth(CHAR_ROW_COLUMNS.level.width)
        row.levelText:SetJustifyH("CENTER")
    end
    row.levelText:SetText(string.format("|cff%02x%02x%02x%d|r", 
        classColor.r * 255, classColor.g * 255, classColor.b * 255, 
        char.level or 1))
        
    -- COLUMN 7: Item Level
    local itemLevelOffset = GetColumnOffset("itemLevel")
    if not row.itemLevelText then
        row.itemLevelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
        row.itemLevelText:SetWidth(CHAR_ROW_COLUMNS.itemLevel.width)
        row.itemLevelText:SetJustifyH("CENTER")
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
        row.goldText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.goldText:SetPoint("LEFT", goldOffset, 0)
        row.goldText:SetWidth(CHAR_ROW_COLUMNS.gold.width)
        row.goldText:SetJustifyH("RIGHT")
    end
    local totalCopper = WarbandNexus:GetCharTotalCopper(char)
    row.goldText:SetText(FormatMoney(totalCopper, 12))
    
    -- COLUMN 9: Professions (Dynamic)
    local profOffset = GetColumnOffset("professions")
    if not row.profIcons then row.profIcons = {} end
    
    -- Hide all existing profession icons first
    for _, icon in ipairs(row.profIcons) do icon:Hide() end
    
    if char.professions then
        local iconSize = 34  -- Increased 20% (28 → 34)
        local iconSpacing = 5  -- Increased 20% (4 → 5)
        local currentProfX = profOffset + 10 -- +10 padding
        
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
            
            pFrame:SetPoint("LEFT", currentProfX, 0)
            pFrame.icon:SetTexture(prof.icon)
            pFrame:Show()
            
            -- Tooltip
            pFrame:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(prof.name, 1, 1, 1)
                 if prof.recipes and prof.recipes.known and prof.recipes.total then
                    local recipeColor = (prof.recipes.known == prof.recipes.total) and {0, 1, 0} or {0.8, 0.8, 0.8}
                    GameTooltip:AddDoubleLine("Recipes", prof.recipes.known .. "/" .. prof.recipes.total, 
                        0.7, 0.7, 0.7, recipeColor[1], recipeColor[2], recipeColor[3])
                end
                
                if prof.expansions and #prof.expansions > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Expansion Progress:", 1, 0.82, 0)
                    local expansions = {}
                    for _, exp in ipairs(prof.expansions) do table.insert(expansions, exp) end
                    table.sort(expansions, function(a, b) return (a.skillLine or 0) > (b.skillLine or 0) end)

                    for _, exp in ipairs(expansions) do
                        local color = (exp.rank == exp.maxRank) and {0, 1, 0} or {0.8, 0.8, 0.8}
                        GameTooltip:AddDoubleLine("  " .. (exp.name or "Unknown"), exp.rank .. "/" .. exp.maxRank, 
                            0.9, 0.9, 0.9, color[1], color[2], color[3])
                    end
                else
                     GameTooltip:AddLine(" ")
                     GameTooltip:AddDoubleLine("Skill", (prof.rank or 0) .. "/" .. (prof.maxRank or 0), 1, 1, 1, 1, 1, 1)
                end

                GameTooltip:Show()
            end)
            pFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
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
        local secondaries = {"cooking", "fishing", "archaeology"}
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
        row.keystoneText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)  -- Icon(24) + gap(5) + padding(5)
        row.keystoneText:SetWidth(CHAR_ROW_COLUMNS.mythicKey.width - 30)
        row.keystoneText:SetJustifyH("LEFT")
        row.keystoneText:SetWordWrap(false)
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
    
    -- Reorder Buttons
    if not row.reorderButtons then
        local rb = CreateFrame("Frame", nil, row)
        rb:SetSize(48, 24)
        rb:SetPoint("RIGHT", -90, 0)
        rb:SetAlpha(0.7)  -- Start at 0.7 (normal state)
        rb.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
        
        rb.up = CreateFrame("Button", nil, rb)
        rb.up:SetSize(22, 22)
        rb.up:SetPoint("LEFT", 0, 0)
        rb.up:SetNormalAtlas("glues-characterSelect-icon-arrowUp")
        
        -- Add highlight on hover
        rb.up:SetScript("OnEnter", function(self)
            if row.reorderButtons then row.reorderButtons:SetAlpha(1.0) end
        end)
        rb.up:SetScript("OnLeave", function(self)
            if row.reorderButtons then row.reorderButtons:SetAlpha(0.7) end
        end)
        
        rb.down = CreateFrame("Button", nil, rb)
        rb.down:SetSize(22, 22)
        rb.down:SetPoint("RIGHT", 0, 0)
        rb.down:SetNormalAtlas("glues-characterSelect-icon-arrowDown")
        
        -- Add highlight on hover
        rb.down:SetScript("OnEnter", function(self)
            if row.reorderButtons then row.reorderButtons:SetAlpha(1.0) end
        end)
        rb.down:SetScript("OnLeave", function(self)
            if row.reorderButtons then row.reorderButtons:SetAlpha(0.7) end
        end)
        
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
    
    -- COLUMN: Last Seen
    local lastSeenX = -45
    
    if isCurrent then
        if not row.onlineText then
            row.onlineText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.onlineText:SetPoint("RIGHT", lastSeenX, 0)
            row.onlineText:SetWidth(90)
            row.onlineText:SetJustifyH("RIGHT")
            row.onlineText:SetText("Online")
            row.onlineText:SetTextColor(0, 1, 0) 
        end
        row.onlineText:Show()
        if row.lastSeenText then row.lastSeenText:Hide() end
    else
        if row.onlineText then row.onlineText:Hide() end
        
        local timeDiff = char.lastSeen and (time() - char.lastSeen) or math.huge
        
        if not row.lastSeenText then
            row.lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.lastSeenText:SetPoint("RIGHT", lastSeenX, 0)
            row.lastSeenText:SetWidth(90)
            row.lastSeenText:SetJustifyH("RIGHT")
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
    
    -- COLUMN: Delete button
    if not isCurrent then
        if not row.deleteBtn then
            -- Create as Button (not Frame) to support OnClick
            local deleteBtn = CreateFrame("Button", nil, row)
            deleteBtn:SetSize(22, 22)
            deleteBtn:SetPoint("RIGHT", -10, 0)
            deleteBtn.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
            
            -- Add icon texture
            local icon = deleteBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            icon:SetDesaturated(true)
            icon:SetVertexColor(0.8, 0.2, 0.2)
            deleteBtn.texture = icon
            deleteBtn.icon = icon
            
            deleteBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:SetText("|cffff5555Delete Character|r\nClick to remove this character's data")
                GameTooltip:Show()
            end)
            deleteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
            row.deleteBtn = deleteBtn
        end
        
        row.deleteBtn.charKey = charKey
        row.deleteBtn.charName = char.name or "Unknown"
        
        -- Safely set OnClick
        if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
            row.deleteBtn:SetScript("OnClick", function(self)
            StaticPopupDialogs["WARBANDNEXUS_DELETE_CHARACTER"] = {
                text = string.format("|cffff9900Delete Character?|r\n\nAre you sure you want to delete |cff00ccff%s|r?\n\n|cffff0000This action cannot be undone!|r", self.charName),
                button1 = "Delete",
                button2 = "Cancel",
                OnAccept = function()
                    local success = WarbandNexus:DeleteCharacter(self.charKey)
                    if success and WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
                StaticPopup_Show("WARBANDNEXUS_DELETE_CHARACTER")
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
    
    -- Hover effects removed (no backdrop)
    -- FIX: Don't change reorderButtons alpha on row hover, only on button hover
    row:SetScript("OnEnter", function(self)
        -- Removed reorderButtons alpha change (now handled by individual buttons)
    end)
    
    row:SetScript("OnLeave", function(self)
        -- Removed reorderButtons alpha change (now handled by individual buttons)
        GameTooltip:Hide()
    end)

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
