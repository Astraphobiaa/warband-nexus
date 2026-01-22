--[[
    Warband Nexus - Currency Tab
    Display all currencies across characters with Blizzard API headers
    
    Hierarchy (matches ReputationUI):
    - Character Header (0px) → HEADER_SPACING (40px)
      - Blizzard Headers (BASE_INDENT = 15px) → HEADER_HEIGHT (32px)
        - Currency Rows (BASE_INDENT = 15px, same as header)
        - Season 3 Sub-Rows (BASE_INDENT + BASE_INDENT + SUBROW_EXTRA_INDENT = 40px)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatGold = ns.UI_FormatGold
local DrawEmptyState = ns.UI_DrawEmptyState
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local AcquireCurrencyRow = ns.UI_AcquireCurrencyRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox

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
local HEADER_HEIGHT = UI_LAYOUT.HEADER_HEIGHT or 32
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING or 40
local SUBHEADER_SPACING = UI_LAYOUT.SUBHEADER_SPACING or 40
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING or 8
local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

--============================================================================
-- CURRENCY FORMATTING & HELPERS
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

---Format currency quantity with cap indicator
---@param quantity number Current amount
---@param maxQuantity number Maximum amount (0 = no cap)
---@return string Formatted text with color
local function FormatCurrencyAmount(quantity, maxQuantity)
    if maxQuantity > 0 then
        local percentage = (quantity / maxQuantity) * 100
        local color
        
        if percentage >= 100 then
            color = "|cffff4444" -- Red (capped)
        elseif percentage >= 80 then
            color = "|cffffaa00" -- Orange (near cap)
        elseif percentage >= 50 then
            color = "|cffffff00" -- Yellow (half)
        else
            color = "|cffffffff" -- White (safe)
        end
        
        return format("%s%s|r / %s", color, FormatNumber(quantity), FormatNumber(maxQuantity))
    else
        return format("|cffffffff%s|r", FormatNumber(quantity))
    end
end

---Check if currency matches search text
---@param currency table Currency data
---@param searchText string Search text (lowercase)
---@return boolean matches
local function CurrencyMatchesSearch(currency, searchText)
    if not searchText or searchText == "" then
        return true
    end
    
    local name = (currency.name or ""):lower()
    local category = (currency.category or ""):lower()
    
    return name:find(searchText, 1, true) or category:find(searchText, 1, true)
end

--============================================================================
-- CURRENCY ROW RENDERING (EXACT StorageUI style)
--============================================================================

---Create a single currency row (PIXEL-PERFECT StorageUI style) - NO POOLING for stability
---@param parent Frame Parent frame
---@param currency table Currency data
---@param currencyID number Currency ID
---@param rowIndex number Row index for alternating colors
---@param indent number Left indent
---@param width number Parent width
---@param yOffset number Y position
---@return number newYOffset
local function CreateCurrencyRow(parent, currency, currencyID, rowIndex, indent, rowWidth, yOffset, shouldAnimate)
    -- PERFORMANCE: Acquire from pool (StorageUI pattern: rowWidth is pre-calculated by caller)
    local row = AcquireCurrencyRow(parent, rowWidth, ROW_HEIGHT)
    
    row:ClearAllPoints()  -- Clear any existing anchors
    row:SetSize(rowWidth, ROW_HEIGHT)  -- Set exact row width
    row:SetPoint("TOPLEFT", indent, -yOffset)  -- Position at indent
    
    -- Ensure alpha is reset (pooling safety)
    row:SetAlpha(1)
    
    -- EXACT alternating row colors (from SharedWidgets)
    local bgColor = rowIndex % 2 == 0 and ROW_COLOR_EVEN or ROW_COLOR_ODD
    row:SetBackdropColor(unpack(bgColor))
    row.bgColor = bgColor -- Save for hover restore (if needed)

    local hasQuantity = (currency.quantity or 0) > 0
    
    -- Icon
    if currency.iconFileID then
        row.icon:SetTexture(currency.iconFileID)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    if not hasQuantity then
        row.icon:SetAlpha(0.4)
    else
        row.icon:SetAlpha(1)
    end
    
    -- Name
    row.nameText:SetWidth(rowWidth - 200)
    row.nameText:SetText(currency.name or "Unknown Currency")
    -- Color set by pooling reset (white), but confirm:
    row.nameText:SetTextColor(1, 1, 1) -- Always white per StorageUI style
    
    -- Amount
    row.amountText:SetText(FormatCurrencyAmount(currency.quantity or 0, currency.maxQuantity or 0))
    row.amountText:SetTextColor(1, 1, 1) -- Always white
    
    -- Hover effect
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.20, 1)
        
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if currencyID and C_CurrencyInfo then
             -- Safety check for ID validity
             pcall(function() GameTooltip:SetCurrencyByID(currencyID) end)
        else
            GameTooltip:SetText(currency.name or "Currency", 1, 1, 1)
            if currency.maxQuantity and currency.maxQuantity > 0 then
                GameTooltip:AddLine(format("Maximum: %d", currency.maxQuantity), 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        local bg = self.bgColor or {0, 0, 0, 0} 
        self:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        GameTooltip:Hide()
    end)
    
    -- ANIMATION
    if row.anim then row.anim:Stop() end
    
    if shouldAnimate then
        row:SetAlpha(0)
        
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
        row.fade:SetStartDelay(rowIndex * 0.05)
        
        row.anim:Play()
    else
        row:SetAlpha(1)
    end
    
    return yOffset + ROW_HEIGHT + UI_LAYOUT.betweenRows
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawCurrencyList(container, width)
    if not container then return 0 end
    
    self.recentlyExpanded = self.recentlyExpanded or {}
    
    -- PERFORMANCE: Release pooled frames
    if ReleaseAllPooledChildren then 
        ReleaseAllPooledChildren(container)
    end
    
    local parent = container
    local yOffset = 0
    
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    -- Check if module is disabled - show message below header
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.currencies then
        local disabledText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        disabledText:SetPoint("TOP", parent, "TOP", 0, -yOffset - 50)
        disabledText:SetText("|cff888888Module disabled. Check the box above to enable.|r")
        return yOffset + UI_LAYOUT.emptyStateSpacing
    end
    
    -- Get search text
    local currencySearchText = (ns.currencySearchText or ""):lower()
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    if not characters or #characters == 0 then
        DrawEmptyState(self, parent, yOffset, false, "No character data available")
        return yOffset + HEADER_SPACING
    end
    
    -- Get current online character
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    local currentCharKey = currentPlayerName .. "-" .. currentRealm
    
    -- Expanded state management
    local expanded = self.db.profile.currencyExpanded or {}
    
    local function IsExpanded(key, default)
        if self.currencyExpandAllActive then return true end
        if expanded[key] == nil then return default or false end
        return expanded[key]
    end
    
    local function ToggleExpand(key, isExpanded)
        if not self.db.profile.currencyExpanded then
            self.db.profile.currencyExpanded = {}
        end
        self.db.profile.currencyExpanded[key] = isExpanded
        if isExpanded then self.recentlyExpanded[key] = GetTime() end
        self:RefreshUI()
    end
    
    -- Build currency data from global storage
    local globalCurrencies = self.db.global.currencies or {}
    local globalHeaders = self.db.global.currencyHeaders or {}
    
    -- Collect characters with currencies
    local charactersWithCurrencies = {}
    local hasAnyData = false
    
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        local isOnline = (charKey == currentCharKey)
        
        -- Build currencies for this character
        local matchingCurrencies = {}
        
        for currencyID, currData in pairs(globalCurrencies) do
            local quantity = 0
            if currData.isAccountWide then
                quantity = currData.value or 0
            else
                quantity = currData.chars and currData.chars[charKey] or 0
            end
            
            local currency = {
                name = currData.name,
                quantity = quantity,
                maxQuantity = currData.maxQuantity or 0,
                iconFileID = currData.icon,
            }
            
            local passesZeroFilter = showZero or (quantity > 0)
            
            if passesZeroFilter and CurrencyMatchesSearch(currency, currencySearchText) then
                table.insert(matchingCurrencies, {
                    id = currencyID,
                    data = currency,
                })
            end
        end
        
        if #matchingCurrencies > 0 then
            hasAnyData = true
            table.insert(charactersWithCurrencies, {
                char = char,
                key = charKey,
                currencies = matchingCurrencies,
                currencyHeaders = globalHeaders,
                isOnline = isOnline,
                sortPriority = isOnline and 0 or 1,
            })
        end
    end
    
    -- Sort (online first)
    table.sort(charactersWithCurrencies, function(a, b)
        if a.sortPriority ~= b.sortPriority then
            return a.sortPriority < b.sortPriority
        end
        return (a.char.name or "") < (b.char.name or "")
    end)
    
    if not hasAnyData then
        local isSearch = currencySearchText ~= ""
        local message = isSearch and "No currencies match your search" or "No currencies found"
        DrawEmptyState(self, parent, yOffset, isSearch, message)
        return yOffset + UI_LAYOUT.emptyStateSpacing
    end
    
    -- Draw each character
    for _, charData in ipairs(charactersWithCurrencies) do
        local char = charData.char
        local charKey = charData.key
        local currencies = charData.currencies
        
        -- #region agent log H3
        print(format("[WBN DEBUG] Character loop start: char=%s yOffset=%.1f", char.name or "Unknown", yOffset))
        -- #endregion
        
        -- Character header
        local classColor = RAID_CLASS_COLORS[char.classFile or char.class] or {r=1, g=1, b=1}
        local onlineBadge = charData.isOnline and " |cff00ff00(Online)|r" or ""
        local charName = format("|c%s%s|r", 
            format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            char.name or "Unknown")
        
        local charKey_expand = "currency-char-" .. charKey
        local charExpanded = IsExpanded(charKey_expand, charData.isOnline)  -- Auto-expand online character
        
        if currencySearchText ~= "" then
            charExpanded = true
        end
        
        -- Get class icon texture path
        local classIconPath = nil
        local coords = CLASS_ICON_TCOORDS[char.classFile or char.class]
        if coords then
            classIconPath = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
        end
        
        local charHeader, charBtn, classIcon = CreateCollapsibleHeader(
            parent,
            format("%s%s - |cffffffff%d currencies|r", charName, onlineBadge, #currencies),  -- Pure white
            charKey_expand,
            charExpanded,
            function(isExpanded) ToggleExpand(charKey_expand, isExpanded) end,
            classIconPath  -- Pass class icon path
        )
        
        -- If we have class icon coordinates, apply them
        if classIcon and coords then
            classIcon:SetTexCoord(unpack(coords))
        end
        
        charHeader:SetPoint("TOPLEFT", 0, -yOffset)
        charHeader:SetPoint("TOPRIGHT", 0, -yOffset)
        charHeader:SetWidth(width)
        
        yOffset = yOffset + HEADER_SPACING
        
        if charExpanded then
            -- ===== Use Blizzard's Currency Headers =====
            -- Use global headers
            local headers = charData.currencyHeaders or self.db.global.currencyHeaders or {}
                
                -- Find War Within and Season 3 headers for special handling
                local warWithinHeader = nil
                local season3Header = nil
                local processedHeaders = {}
                
                for _, headerData in ipairs(headers) do
                    local headerName = headerData.name:lower()
                    
                    -- Skip Timerunning (not in Retail)
                    if headerName:find("timerunning") or headerName:find("time running") then
                        -- Skip this header completely
                    elseif headerName:find("war within") then
                        warWithinHeader = headerData
                    elseif headerName:find("season") and (headerName:find("3") or headerName:find("three")) then
                        season3Header = headerData
                    else
                        table.insert(processedHeaders, headerData)
                    end
                end
                
                -- First: War Within with Season 3 as sub-header
                if warWithinHeader then
                    local warWithinCurrencies = {}
                    for _, currencyID in ipairs(warWithinHeader.currencies or {}) do
                        local numCurrencyID = tonumber(currencyID) or currencyID
                        for _, curr in ipairs(currencies) do
                            local numCurrID = tonumber(curr.id) or curr.id
                            if numCurrID == numCurrencyID then
                                -- Skip Timerunning currencies
                                if not curr.data.name:lower():find("infinite knowledge") then
                                    table.insert(warWithinCurrencies, curr)
                                end
                                break
                            end
                        end
                    end
                    
                    local season3Currencies = {}
                    if season3Header then
                        for _, currencyID in ipairs(season3Header.currencies or {}) do
                            local numCurrencyID = tonumber(currencyID) or currencyID
                            for _, curr in ipairs(currencies) do
                                local numCurrID = tonumber(curr.id) or curr.id
                                if numCurrID == numCurrencyID then
                                    table.insert(season3Currencies, curr)
                                    break
                                end
                            end
                        end
                    end
                    
                    local totalTWW = #warWithinCurrencies + #season3Currencies
                    
                    if totalTWW > 0 then
                        local warKey = charKey .. "-header-" .. warWithinHeader.name
                        local warExpanded = IsExpanded(warKey, true)
                        
                        if currencySearchText ~= "" then
                            warExpanded = true
                        end
                        
                        -- War Within Header
                        local warHeader, warBtn = CreateCollapsibleHeader(
                            parent,
                            warWithinHeader.name .. " (" .. totalTWW .. ")",
                            warKey,
                            warExpanded,
                            function(isExpanded) ToggleExpand(warKey, isExpanded) end,
                            "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
                        )
                        warHeader:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)  -- Header at BASE_INDENT (15px)
                        warHeader:SetPoint("TOPRIGHT", 0, -yOffset)
                        
                        yOffset = yOffset + HEADER_HEIGHT  -- Header height
                        
                        
                        if warExpanded then
                            local warIndent = BASE_INDENT + 10  -- Rows at BASE_INDENT + 10 (25px)
                            -- First: War Within currencies (non-Season 3)
                            if #warWithinCurrencies > 0 then
                                local shouldAnimate = self.recentlyExpanded[warKey] and (GetTime() - self.recentlyExpanded[warKey] < 0.5)
                                local rowIdx = 0
                                for _, curr in ipairs(warWithinCurrencies) do
                                    rowIdx = rowIdx + 1
                                    -- FIX: Row width from parent width, not header width
                                    local rowWidth = width - warIndent
                                    
                                    -- #region agent log H2
                                    print(format("[WBN DEBUG] TWW Row: curr='%s' indent=%.1f rowWidth=%.1f width=%.1f", 
                                        curr.data.name or "Unknown", warIndent, rowWidth, width))
                                    -- #endregion
                                    
                                    yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, warIndent, rowWidth, yOffset, shouldAnimate)
                                end
                                
                                -- Add spacing after War Within rows, before Season 3
                                if #season3Currencies > 0 then
                                    yOffset = yOffset + SECTION_SPACING
                                    
                                    -- #region agent log
                                    print(format("[WBN DEBUG] After TWW rows, before S3: yOffset=%.1f spacing=%.1f", yOffset, SECTION_SPACING))
                                    -- #endregion
                                end
                            end
                            
                            -- Then: Season 3 sub-header
                            if #season3Currencies > 0 then
                                local s3Key = warKey .. "-season3"
                                local s3Expanded = IsExpanded(s3Key, true)
                                
                                if currencySearchText ~= "" then
                                    s3Expanded = true
                                end
                                
                                local s3Header, s3Btn = CreateCollapsibleHeader(
                                    parent,
                                    season3Header.name .. " (" .. #season3Currencies .. ")",
                                    s3Key,
                                    s3Expanded,
                                    function(isExpanded) ToggleExpand(s3Key, isExpanded) end
                                )
                                s3Header:SetPoint("TOPLEFT", BASE_INDENT + SUBROW_EXTRA_INDENT, -yOffset)  -- Sub-header at BASE_INDENT + SUBROW_EXTRA_INDENT (25px)
                                s3Header:SetPoint("TOPRIGHT", 0, -yOffset)
                                
                                yOffset = yOffset + HEADER_HEIGHT  -- Header height
                                
                                if s3Expanded then
                                    local s3RowIndent = warIndent + BASE_INDENT + SUBROW_EXTRA_INDENT  -- SubRows at warIndent + BASE_INDENT + SUBROW_EXTRA_INDENT (40px)
                                    local shouldAnimate = self.recentlyExpanded[s3Key] and (GetTime() - self.recentlyExpanded[s3Key] < 0.5)
                                    local rowIdx = 0
                                    for _, curr in ipairs(season3Currencies) do
                                        rowIdx = rowIdx + 1
                                        -- Sub-row width from parent width
                                        local rowWidth = width - s3RowIndent
                                        yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, s3RowIndent, rowWidth, yOffset, shouldAnimate)
                                    end
                                end
                            end
                        end
                    end
                    
                    -- Add spacing after War Within section
                    yOffset = yOffset + SECTION_SPACING
                end
                
                -- Then: All other Blizzard headers (in order)
                for _, headerData in ipairs(processedHeaders) do
                    local headerCurrencies = {}
                    for _, currencyID in ipairs(headerData.currencies or {}) do
                        local numCurrencyID = tonumber(currencyID) or currencyID
                        for _, curr in ipairs(currencies) do
                            local numCurrID = tonumber(curr.id) or curr.id
                            if numCurrID == numCurrencyID then
                                -- Skip Timerunning currencies
                                if not curr.data.name:lower():find("infinite knowledge") then
                                    table.insert(headerCurrencies, curr)
                                end
                                break
                            end
                        end
                    end
                    
                    if #headerCurrencies > 0 then
                        -- #region agent log H1,H4
                        print(format("[WBN DEBUG] Before header: name='%s' yOffset=%.1f", headerData.name, yOffset))
                        -- #endregion
                        
                        local headerKey = charKey .. "-header-" .. headerData.name
                        local headerExpanded = IsExpanded(headerKey, true)
                        
                        if currencySearchText ~= "" then
                            headerExpanded = true
                        end
                        
                        -- Blizzard Header
                        local headerIcon = nil
                        -- Try to find icon for common headers
                        if headerData.name:find("War Within") then
                            headerIcon = "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
                        elseif headerData.name:find("Dragonflight") then
                            headerIcon = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
                        elseif headerData.name:find("Shadowlands") then
                            headerIcon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
                        elseif headerData.name:find("Battle for Azeroth") then
                            headerIcon = "Interface\\Icons\\INV_Sword_39"
                        elseif headerData.name:find("Legion") then
                            headerIcon = "Interface\\Icons\\Spell_Shadow_Twilight"
                        elseif headerData.name:find("Warlords of Draenor") or headerData.name:find("Draenor") then
                            headerIcon = "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
                        elseif headerData.name:find("Mists of Pandaria") or headerData.name:find("Pandaria") then
                            headerIcon = "Interface\\Icons\\Achievement_Character_Pandaren_Female"
                        elseif headerData.name:find("Cataclysm") then
                            headerIcon = "Interface\\Icons\\Spell_Fire_Flameshock"
                        elseif headerData.name:find("Wrath") or headerData.name:find("Lich King") then
                            headerIcon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
                        elseif headerData.name:find("Burning Crusade") or headerData.name:find("Outland") then
                            headerIcon = "Interface\\Icons\\Spell_Fire_FelFlameStrike"
                        elseif headerData.name:find("PvP") or headerData.name:find("Player vs") then
                            headerIcon = "Interface\\Icons\\Achievement_BG_returnXflags_def_WSG"
                        elseif headerData.name:find("Dungeon") or headerData.name:find("Raid") then
                            headerIcon = "Interface\\Icons\\achievement_boss_archaedas"
                        elseif headerData.name:find("Miscellaneous") then
                            headerIcon = "Interface\\Icons\\INV_Misc_Gear_01"
                        end
                        
                        local header, headerBtn = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. #headerCurrencies .. ")",
                            headerKey,
                            headerExpanded,
                            function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                            headerIcon  -- Pass icon
                        )
                        header:SetPoint("TOPLEFT", BASE_INDENT, -yOffset)  -- Subheader at BASE_INDENT (15px)
                        header:SetWidth(width - BASE_INDENT)
                        
                        -- #region agent log H4
                        print(format("[WBN DEBUG] Header created: name='%s' indent=%.1f width=%.1f", headerData.name, BASE_INDENT, width - BASE_INDENT))
                        -- #endregion
                        
                        yOffset = yOffset + HEADER_HEIGHT  -- Header height
                        
                        if headerExpanded then
                            local headerRowIndent = BASE_INDENT  -- Rows at BASE_INDENT (15px, same as header)
                            local shouldAnimate = self.recentlyExpanded[headerKey] and (GetTime() - self.recentlyExpanded[headerKey] < 0.5)
                            local rowIdx = 0
                            for _, curr in ipairs(headerCurrencies) do
                                rowIdx = rowIdx + 1
                                -- Row width from parent width
                                local rowWidth = width - headerRowIndent
                                
                                -- #region agent log H2
                                print(format("[WBN DEBUG] Row calc: header='%s' rowWidth=%.1f indent=%.1f width=%.1f", 
                                    headerData.name, rowWidth, headerRowIndent, width))
                                -- #endregion
                                
                                yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, headerRowIndent, rowWidth, yOffset, shouldAnimate)
                            end
                        end
                        
                        -- Add spacing after each header section (but NOT after the last header in character)
                        yOffset = yOffset + SECTION_SPACING
                    end
                end
                
                -- Remove last SECTION_SPACING before character ends (to prevent double spacing)
                yOffset = yOffset - SECTION_SPACING
            end
        end
    
    -- ===== API LIMITATION NOTICE =====
    yOffset = yOffset + (SECTION_SPACING * 2)
    
    local noticeFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    noticeFrame:SetSize(width - 20, 60)
    noticeFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    noticeFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    noticeFrame:SetBackdropColor(0.1, 0.1, 0.15, 0.9)
    noticeFrame:SetBackdropBorderColor(0.5, 0.4, 0.2, 0.8)
    
    local noticeIcon = noticeFrame:CreateTexture(nil, "ARTWORK")
    noticeIcon:SetSize(24, 24)
    noticeIcon:SetPoint("LEFT", 10, 0)
    noticeIcon:SetTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    
    local noticeText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noticeText:SetPoint("LEFT", noticeIcon, "RIGHT", 10, 5)
    noticeText:SetPoint("RIGHT", -10, 5)
    noticeText:SetJustifyH("LEFT")
    noticeText:SetText("|cffffcc00Currency Transfer Limitation|r")
    
    local noticeSubText = noticeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noticeSubText:SetPoint("TOPLEFT", noticeIcon, "TOPRIGHT", 10, -15)
    noticeSubText:SetPoint("RIGHT", -10, 0)
    noticeSubText:SetJustifyH("LEFT")
    noticeSubText:SetTextColor(1, 1, 1)  -- White
    noticeSubText:SetText("Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies.")
    
    yOffset = yOffset + UI_LAYOUT.afterHeader
    
    return yOffset
end

--============================================================================
-- CURRENCY TAB WRAPPER (Fixes focus issue)
--============================================================================

function WarbandNexus:DrawCurrencyTab(parent)
    local width = parent:GetWidth() - 20
    local yOffset = 8
    
    -- Clear old frames
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
        if child:GetObjectType() ~= "Frame" then
             pcall(function() child:Hide(); child:ClearAllPoints() end)
        end
    end

    -- ===== TITLE CARD Setup =====
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    local CreateCard = ns.UI_CreateCard
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("currency"))
    
    -- Module Enable Checkbox
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.currencies ~= false
    local enableCheckbox = CreateThemedCheckbox(titleCard, moduleEnabled)
    enableCheckbox:SetPoint("LEFT", headerIcon.border, "RIGHT", 8, 0)
    
    enableCheckbox:SetScript("OnClick", function(checkbox)
        local enabled = checkbox:GetChecked()
        -- Use ModuleManager for proper event handling
        if self.SetCurrencyModuleEnabled then
            self:SetCurrencyModuleEnabled(enabled)
            if enabled and self.UpdateCurrencyData then
                self:UpdateCurrencyData()
            end
        else
            -- Fallback
            self.db.profile.modulesEnabled = self.db.profile.modulesEnabled or {}
            self.db.profile.modulesEnabled.currencies = enabled
            if enabled and self.UpdateCurrencyData then self:UpdateCurrencyData() end
            if self.RefreshUI then self:RefreshUI() end
        end
    end)
    
    enableCheckbox:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Currency Module is " .. (btn:GetChecked() and "Enabled" or "Disabled"))
        GameTooltip:AddLine("Click to " .. (btn:GetChecked() and "disable" or "enable"), 1, 1, 1)
        GameTooltip:Show()
    end)
    
    enableCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 12, 5)
    titleText:SetText("|cff" .. hexColor .. "Currency Tracker|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", enableCheckbox, "RIGHT", 12, -12)
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetText("Track all currencies across your characters")
    
    -- Show 0 Toggle (rightmost, standardized to 100px)
    local showZeroBtn = CreateThemedButton(titleCard, showZero and "Hide Empty" or "Show Empty", 100)
    showZeroBtn:SetPoint("RIGHT", titleCard, "RIGHT", -15, 0)
    
    -- Hide button if module disabled
    if not moduleEnabled then
        showZeroBtn:Hide()
    end
    
    showZeroBtn:SetScript("OnClick", function(btn)
        showZero = not showZero
        self.db.profile.currencyShowZero = showZero
        btn.text:SetText(showZero and "Hide Empty" or "Show Empty")
        self:RefreshUI()
    end)
    
    yOffset = yOffset + UI_LAYOUT.afterHeader
    
    -- Search Box
    local CreateSearchBox = ns.UI_CreateSearchBox
    local currencySearchText = ns.currencySearchText or ""
    
    local searchBox = CreateSearchBox(parent, width, "Search currencies...", function(text)
        ns.currencySearchText = text
        -- UPDATE LIST ONLY
        if parent.resultsContainer then
            self:DrawCurrencyList(parent.resultsContainer, width)
        end
    end, 0.4, currencySearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + UI_LAYOUT.afterElement  -- Search box height + standard gap
    
    -- Container - CRITICAL FIX: Always create fresh container to prevent layout corruption
    -- REASON: Reusing containers with hidden pooled rows causes yOffset to accumulate
    if parent.resultsContainer then
        parent.resultsContainer:Hide()
        parent.resultsContainer:SetParent(nil)  -- Detach for GC
    end
    
    local container = CreateFrame("Frame", nil, parent)
    parent.resultsContainer = container
    container:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    container:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    container:SetHeight(1)  -- Dynamic height
    container:Show()
    
    -- Draw List
    local listHeight = self:DrawCurrencyList(container, width)
    
    -- CRITICAL FIX: Update container height AFTER content is drawn
    -- Without this, WoW UI engine thinks container is 1px tall and layout breaks
    container:SetHeight(math.max(listHeight, 1))
    
    return yOffset + listHeight
end
