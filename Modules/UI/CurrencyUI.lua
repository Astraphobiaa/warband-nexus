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
local CreateNoticeFrame = ns.UI_CreateNoticeFrame

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
local function CreateCurrencyRow(parent, currency, currencyID, rowIndex, indent, rowWidth, yOffset, shouldAnimate, hideMax)
    -- PERFORMANCE: Acquire from pool (StorageUI pattern: rowWidth is pre-calculated by caller)
    local row = AcquireCurrencyRow(parent, rowWidth, ROW_HEIGHT)
    
    row:ClearAllPoints()  -- Clear any existing anchors
    row:SetSize(rowWidth, ROW_HEIGHT)  -- Set exact row width
    row:SetPoint("TOPLEFT", indent, -yOffset)  -- Position at indent
    
    -- Ensure alpha is reset (pooling safety)
    row:SetAlpha(1)
    
    -- Set alternating background colors
    local ROW_COLOR_EVEN = UI_LAYOUT.ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
    local ROW_COLOR_ODD = UI_LAYOUT.ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
    local bgColor = (rowIndex % 2 == 0) and ROW_COLOR_EVEN or ROW_COLOR_ODD
    
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    row.bgColor = bgColor

    local hasQuantity = (currency.quantity or 0) > 0
    
    -- Icon (support both iconFileID and icon fields)
    local iconID = currency.iconFileID or currency.icon
    if iconID then
        row.icon:SetTexture(iconID)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    if not hasQuantity then
        row.icon:SetAlpha(0.4)
    else
        row.icon:SetAlpha(1)
    end
    
    -- Name only (no character suffix)
    row.nameText:SetWidth(rowWidth - 200)
    local displayName = currency.name or "Unknown Currency"
    row.nameText:SetText(displayName)
    -- Color set by pooling reset (white), but confirm:
    row.nameText:SetTextColor(1, 1, 1) -- Always white per StorageUI style
    
    -- Character Badge (separate column, like ReputationUI)
    if currency.characterName then
        if not row.badgeText then
            row.badgeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.badgeText:SetPoint("LEFT", 302, 0)  -- Same position as ReputationUI
            row.badgeText:SetJustifyH("LEFT")
            row.badgeText:SetWidth(200)
        end
        row.badgeText:SetText(currency.characterName)
        row.badgeText:Show()
    else
        if row.badgeText then
            row.badgeText:Hide()
        end
    end
    
    -- Amount (hide max in Show All mode)
    local maxToShow = hideMax and 0 or (currency.maxQuantity or 0)
    row.amountText:SetText(FormatCurrencyAmount(currency.quantity or 0, maxToShow))
    row.amountText:SetTextColor(1, 1, 1) -- Always white
    
    -- Hover effect
    row:SetScript("OnEnter", function(self)
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
-- AGGREGATE CURRENCIES (for Show All mode)
--============================================================================

---Aggregate currencies across all characters
---@param self table WarbandNexus instance
---@param characters table List of characters
---@param currencyHeaders table Blizzard currency headers
---@param searchText string Search filter
---@return table { warbandTransferable = {headerData}, characterSpecific = {headerData} }

local function AggregateCurrencies(self, characters, currencyHeaders, searchText, showZero)
    local result = {
        warbandTransferable = {},  -- Account-wide currencies
        characterSpecific = {},     -- Character-specific (with total across all chars)
    }
    
    local globalCurrencies = self.db.global.currencies or {}
    
    -- Build character lookup
    local charLookup = {}
    for _, char in ipairs(characters) do
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
        charLookup[charKey] = char
    end
    
    -- Recursive function to process header tree
    local function ProcessHeader(header)
        local warbandHeaderCurrencies = {}
        local charHeaderCurrencies = {}
        
        -- Process direct currencies
        for _, currencyID in ipairs(header.currencies or {}) do
            currencyID = tonumber(currencyID) or currencyID
            local currData = globalCurrencies[currencyID]
            
            if currData then
                -- Apply search filter
                local matchesSearch = (not searchText or searchText == "" or 
                    (currData.name and currData.name:lower():find(searchText, 1, true)))
                
                if matchesSearch then
                    if currData.isAccountWide or currData.isAccountTransferable then
                        -- Warband Transferable
                        local quantity = currData.value or 0
                        -- Apply showZero filter
                        if showZero or quantity > 0 then
                            table.insert(warbandHeaderCurrencies, {
                                id = currencyID,
                                data = currData,
                                quantity = quantity
                            })
                        end
                    else
                        -- Character-Specific: Calculate total and find best character
                        local bestChar = nil
                        local bestAmount = 0
                        local totalAmount = 0
                        
                        for charKey, amount in pairs(currData.chars or {}) do
                            totalAmount = totalAmount + amount
                            if amount > bestAmount then
                                bestAmount = amount
                                bestChar = charKey
                            end
                        end
                        
                        -- Apply showZero filter
                        if (showZero or totalAmount > 0) and bestChar and charLookup[bestChar] then
                            table.insert(charHeaderCurrencies, {
                                id = currencyID,
                                data = currData,
                                quantity = totalAmount,  -- Total across all characters
                                bestAmount = bestAmount,  -- Highest amount on single character
                                bestCharacter = charLookup[bestChar],
                                bestCharacterKey = bestChar
                            })
                        end
                    end
                end
            end
        end
        
        -- Recursively process children
        local processedWarbandChildren = {}
        local processedCharChildren = {}
        
        for _, child in ipairs(header.children or {}) do
            local warbandChild, charChild = ProcessHeader(child)
            if warbandChild then
                table.insert(processedWarbandChildren, warbandChild)
            end
            if charChild then
                table.insert(processedCharChildren, charChild)
            end
        end
        
        -- Build result headers
        local warbandHeader = nil
        local charHeader = nil
        
        local hasWarbandContent = #warbandHeaderCurrencies > 0 or #processedWarbandChildren > 0
        local hasCharContent = #charHeaderCurrencies > 0 or #processedCharChildren > 0
        
        if hasWarbandContent then
            warbandHeader = {
                name = header.name,
                currencies = warbandHeaderCurrencies,
                depth = header.depth or 0,
                children = processedWarbandChildren,
                hasDescendants = #processedWarbandChildren > 0
            }
        end
        
        if hasCharContent then
            charHeader = {
                name = header.name,
                currencies = charHeaderCurrencies,
                depth = header.depth or 0,
                children = processedCharChildren,
                hasDescendants = #processedCharChildren > 0
            }
        end
        
        return warbandHeader, charHeader
    end
    
    -- Process only root headers (depth 0)
    for _, header in ipairs(currencyHeaders) do
        if (header.depth or 0) == 0 then
            local warbandHeader, charHeader = ProcessHeader(header)
            if warbandHeader then
                table.insert(result.warbandTransferable, warbandHeader)
            end
            if charHeader then
                table.insert(result.characterSpecific, charHeader)
            end
        end
    end
    
    return result
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
    local currentRealm = GetRealmName and GetRealmName() or ""
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
    
    -- Check view mode
    local viewMode = self.db.profile.currencyViewMode or "character"
    
    if viewMode == "all" then
        -- ===== SHOW ALL MODE =====
        local aggregated = AggregateCurrencies(self, characters, globalHeaders, currencySearchText, showZero)
        
        -- Section 1: Warband Transferable
        if #aggregated.warbandTransferable > 0 then
            local sectionKey = "currency-warband"
            local sectionExpanded = IsExpanded(sectionKey, true)
            
            local sectionHeader, _, warbandIcon = CreateCollapsibleHeader(
                parent,
                "All Warband Transferable",
                sectionKey,
                sectionExpanded,
                function(isExpanded) ToggleExpand(sectionKey, isExpanded) end,
                "dummy"  -- Dummy to trigger icon creation
            )
            
            -- Set proper Warband icon (atlas) with correct size
            if warbandIcon then
                warbandIcon:SetTexture(nil)
                warbandIcon:SetAtlas("warbands-icon")
                warbandIcon:SetSize(27, 36)  -- Native atlas proportions
            end
            
            sectionHeader:SetPoint("TOPLEFT", 0, -yOffset)
            sectionHeader:SetPoint("TOPRIGHT", 0, -yOffset)
            yOffset = yOffset + HEADER_SPACING
            
            if sectionExpanded then
                -- Recursive function to render header tree for Show All mode
                local function RenderShowAllTree(headerData, baseDepth, prefix)
                    -- Use original depth for indent calculation (ignore baseDepth for indent)
                    local actualDepth = headerData.depth or 0
                    local headerIndent = BASE_INDENT * (actualDepth + 1)  -- Same as Character View
                    local headerKey = prefix .. headerData.name
                    local headerExpanded = IsExpanded(headerKey, true)
                    
                    -- Use baseDepth only for root comparison
                    local depthForComparison = actualDepth + baseDepth
                    
                    -- Count total currencies (direct + descendants)
                    -- Count only actual currency objects (not IDs)
                    local totalCount = 0
                    for _, curr in ipairs(headerData.currencies or {}) do
                        if type(curr) == "table" and curr.data then
                            totalCount = totalCount + 1
                        end
                    end
                    
                    -- Recursively count children
                    local function CountCurrencies(hdr)
                        local count = 0
                        for _, curr in ipairs(hdr.currencies or {}) do
                            if type(curr) == "table" and curr.data then
                                count = count + 1
                            end
                        end
                        for _, ch in ipairs(hdr.children or {}) do
                            count = count + CountCurrencies(ch)
                        end
                        return count
                    end
                    
                    for _, child in ipairs(headerData.children or {}) do
                        totalCount = totalCount + CountCurrencies(child)
                    end
                    
                    -- Render header if it has content
                    if totalCount > 0 or headerData.hasDescendants then
                        local GetCurrencyHeaderIcon = ns.UI_GetCurrencyHeaderIcon
                        local headerIcon = GetCurrencyHeaderIcon(headerData.name)
                        local blizHeader = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. totalCount .. ")",
                            headerKey,
                            headerExpanded,
                            function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                            headerIcon  -- Add icon
                        )
                        blizHeader:SetPoint("TOPLEFT", headerIndent, -yOffset)
                        blizHeader:SetWidth(width - headerIndent)
                        yOffset = yOffset + HEADER_HEIGHT
                        
                        if headerExpanded then
                            -- Render direct currency rows
                            if #headerData.currencies > 0 then
                                local rowIdx = 0
                                for _, curr in ipairs(headerData.currencies) do
                                    rowIdx = rowIdx + 1
                                    yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, headerIndent, width - headerIndent, yOffset, false, true)
                                end
                            end
                            
                            -- Add spacing before children (always if children exist)
                            if #(headerData.children or {}) > 0 then
                                yOffset = yOffset + SECTION_SPACING
                            end
                            
                            -- Recursively render children
                            for childIdx, childHeader in ipairs(headerData.children or {}) do
                                RenderShowAllTree(childHeader, baseDepth, prefix)
                                -- Add spacing between sibling children
                                if childIdx < #headerData.children then
                                    yOffset = yOffset + SECTION_SPACING
                                end
                            end
                        end
                        
                        -- Add spacing only after root headers
                        if depthForComparison == baseDepth then
                            yOffset = yOffset + SECTION_SPACING
                        end
                    end
                end
                
                -- Render only root headers (depth 0)
                for _, headerData in ipairs(aggregated.warbandTransferable) do
                    if (headerData.depth or 0) == 0 then
                        RenderShowAllTree(headerData, 1, "all-warband-")  -- baseDepth=1 for section indent
                    end
                end
            end
        end
        
        -- Section 2: Character-Specific
        if #aggregated.characterSpecific > 0 then
            local sectionKey = "currency-char-specific"
            local sectionExpanded = IsExpanded(sectionKey, true)
            
            local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
            local sectionHeader = CreateCollapsibleHeader(
                parent,
                "Character-Specific Currencies",
                sectionKey,
                sectionExpanded,
                function(isExpanded) ToggleExpand(sectionKey, isExpanded) end,
                GetCharacterSpecificIcon(),
                true  -- isAtlas
            )
            sectionHeader:SetPoint("TOPLEFT", 0, -yOffset)
            sectionHeader:SetPoint("TOPRIGHT", 0, -yOffset)
            yOffset = yOffset + HEADER_SPACING
            
            if sectionExpanded then
                -- Recursive function for character-specific headers
                local function RenderCharSpecificTree(headerData, baseDepth)
                    -- Use original depth for indent (same as Character View)
                    local actualDepth = headerData.depth or 0
                    local headerIndent = BASE_INDENT * (actualDepth + 1)
                    local headerKey = "all-char-" .. headerData.name
                    local headerExpanded = IsExpanded(headerKey, true)
                    
                    -- Use baseDepth only for root comparison
                    local depthForComparison = actualDepth + baseDepth
                    
                    -- Count total currencies (only actual objects, not IDs)
                    local totalCount = 0
                    for _, curr in ipairs(headerData.currencies or {}) do
                        if type(curr) == "table" and curr.data then
                            totalCount = totalCount + 1
                        end
                    end
                    
                    -- Recursively count children
                    local function CountCurrencies(hdr)
                        local count = 0
                        for _, curr in ipairs(hdr.currencies or {}) do
                            if type(curr) == "table" and curr.data then
                                count = count + 1
                            end
                        end
                        for _, ch in ipairs(hdr.children or {}) do
                            count = count + CountCurrencies(ch)
                        end
                        return count
                    end
                    
                    for _, child in ipairs(headerData.children or {}) do
                        totalCount = totalCount + CountCurrencies(child)
                    end
                    
                    if totalCount > 0 or headerData.hasDescendants then
                        local GetCurrencyHeaderIcon = ns.UI_GetCurrencyHeaderIcon
                        local headerIcon = GetCurrencyHeaderIcon(headerData.name)
                        local blizHeader = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. totalCount .. ")",
                            headerKey,
                            headerExpanded,
                            function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                            headerIcon  -- Add icon
                        )
                        blizHeader:SetPoint("TOPLEFT", headerIndent, -yOffset)
                        blizHeader:SetWidth(width - headerIndent)
                        yOffset = yOffset + HEADER_HEIGHT
                        
                        if headerExpanded then
                            -- Render rows with "Best: CharName" suffix
                            if #headerData.currencies > 0 then
                                local rowIdx = 0
                                for _, curr in ipairs(headerData.currencies) do
                                    rowIdx = rowIdx + 1
                                    
                                    -- Modify currency data to show best character
                                    local displayData = {}
                                    for k, v in pairs(curr.data) do displayData[k] = v end
                                    
                                    local classColor = RAID_CLASS_COLORS[curr.bestCharacter.classFile] or {r=1, g=1, b=1}
                                    local charName = format("|c%s%s  -  %s|r", 
                                        format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
                                        curr.bestCharacter.name,
                                        curr.bestCharacter.realm or "")
                                    
                                    displayData.characterName = format("|cff666666(|r%s|cff666666)|r", charName)
                                    displayData.quantity = curr.quantity
                                    
                                    yOffset = CreateCurrencyRow(parent, displayData, curr.id, rowIdx, headerIndent, width - headerIndent, yOffset, false, true)
                                end
                            end
                            
                            -- Add spacing before children (always if children exist)
                            if #(headerData.children or {}) > 0 then
                                yOffset = yOffset + SECTION_SPACING
                            end
                            
                            -- Recursively render children
                            for childIdx, childHeader in ipairs(headerData.children or {}) do
                                RenderCharSpecificTree(childHeader, baseDepth)
                                -- Add spacing between siblings
                                if childIdx < #headerData.children then
                                    yOffset = yOffset + SECTION_SPACING
                                end
                            end
                        end
                        
                        -- Add spacing only after root headers
                        if depthForComparison == baseDepth then
                            yOffset = yOffset + SECTION_SPACING
                        end
                    end
                end
                
                -- Render only root headers
                for _, headerData in ipairs(aggregated.characterSpecific) do
                    if (headerData.depth or 0) == 0 then
                        RenderCharSpecificTree(headerData, 1)  -- baseDepth=1 for section indent
                    end
                end
            end
        end
        
        if #aggregated.warbandTransferable == 0 and #aggregated.characterSpecific == 0 then
            local isSearch = currencySearchText ~= ""
            local message = isSearch and "No currencies match your search" or "No currencies found"
            DrawEmptyState(self, parent, yOffset, isSearch, message)
            return yOffset + UI_LAYOUT.emptyStateSpacing
        end
    else
        -- ===== CHARACTER MODE (Current) =====
        -- Draw each character
        for charIdx, charData in ipairs(charactersWithCurrencies) do
        local char = charData.char
        local charKey = charData.key
        local currencies = charData.currencies
        
        
        -- Character header
        local classColor = RAID_CLASS_COLORS[char.classFile or char.class] or {r=1, g=1, b=1}
        local onlineBadge = charData.isOnline and " |cff00ff00(Online)|r" or ""
        local charName = format("|c%s%s  -  %s|r", 
            format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            char.name or "Unknown",
            char.realm or "")
        
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
            -- ===== NESTED HIERARCHY (Blizzard's original structure) =====
            local charHeaders = charData.currencyHeaders or self.db.global.currencyHeaders or {}
            
            -- Recursive function to render header tree
            local function RenderHeaderTree(headerData, depth)
                local headerName = headerData.name:lower()
                
                -- Skip Timerunning (not in Retail)
                if headerName:find("timerunning") or headerName:find("time running") then
                    return
                end
                
                -- Get direct currencies for this header
                local headerCurrencies = {}
                for _, currencyID in ipairs(headerData.currencies or {}) do
                    local numCurrencyID = tonumber(currencyID) or currencyID
                    for _, curr in ipairs(currencies) do
                        local numCurrID = tonumber(curr.id) or curr.id
                        if numCurrID == numCurrencyID then
                            table.insert(headerCurrencies, curr)
                            break
                        end
                    end
                end
                
                -- Render header if it has currencies OR descendants
                local hasContent = #headerCurrencies > 0 or headerData.hasDescendants
                
                if hasContent then
                    local headerKey = charKey .. "-header-" .. headerData.name
                    local headerExpanded = IsExpanded(headerKey, true)
                    
                    if currencySearchText ~= "" then
                        headerExpanded = true
                    end
                    
                    -- Calculate indent based on depth
                    local headerIndent = BASE_INDENT * (depth + 1)
                    
                    -- Get header icon using shared function
                    local GetCurrencyHeaderIcon = ns.UI_GetCurrencyHeaderIcon
                    local headerIcon = GetCurrencyHeaderIcon(headerData.name)
                    
                    -- Count total currencies (direct + descendants)
                    local totalCount = #headerCurrencies
                    for _, child in ipairs(headerData.children or {}) do
                        if child.hasDescendants then
                            -- Recursively count child currencies
                            local function CountCurrencies(hdr)
                                local count = #(hdr.currencies or {})
                                for _, ch in ipairs(hdr.children or {}) do
                                    count = count + CountCurrencies(ch)
                                end
                                return count
                            end
                            totalCount = totalCount + CountCurrencies(child)
                        end
                    end
                    
                    -- Create header
                    local header, headerBtn = CreateCollapsibleHeader(
                        parent,
                        headerData.name .. " (" .. totalCount .. ")",
                        headerKey,
                        headerExpanded,
                        function(isExpanded) ToggleExpand(headerKey, isExpanded) end,
                        headerIcon
                    )
                    header:SetPoint("TOPLEFT", headerIndent, -yOffset)
                    header:SetWidth(width - headerIndent)
                    
                    yOffset = yOffset + HEADER_HEIGHT
                    
                    -- Draw content if expanded
                    if headerExpanded then
                        local rowIndent = headerIndent  -- Same indent as header
                        
                        -- First: render direct currencies
                        if #headerCurrencies > 0 then
                            local shouldAnimate = self.recentlyExpanded[headerKey] and (GetTime() - self.recentlyExpanded[headerKey] < 0.5)
                            local rowIdx = 0
                            for _, curr in ipairs(headerCurrencies) do
                                rowIdx = rowIdx + 1
                                local rowWidth = width - rowIndent
                                yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, rowIndent, rowWidth, yOffset, shouldAnimate)
                            end
                        end
                        
                        -- Add spacing between content sections:
                        -- 1. Between currencies and children
                        -- 2. Before children if no currencies (header -> first child)
                        if #(headerData.children or {}) > 0 then
                            yOffset = yOffset + SECTION_SPACING
                        end
                        
                        -- Then: recursively render children
                        for childIdx, childHeader in ipairs(headerData.children or {}) do
                            RenderHeaderTree(childHeader, depth + 1)
                            -- Add spacing BETWEEN sibling children (not after last one)
                            if childIdx < #headerData.children then
                                yOffset = yOffset + SECTION_SPACING
                            end
                        end
                    end
                    
                    -- Add spacing ONLY after ROOT headers
                    if depth == 0 then
                        yOffset = yOffset + SECTION_SPACING
                    end
                end
            end
            
            -- Render only root headers (depth 0)
            for _, headerData in ipairs(charHeaders) do
                if (headerData.depth or 0) == 0 then
                    RenderHeaderTree(headerData, 0)
                end
            end
        end
    end  -- End character loop
    end  -- End of viewMode check (if/else)
    
    -- ===== API LIMITATION NOTICE =====
    yOffset = yOffset + (SECTION_SPACING * 2)
    
    local noticeFrame = CreateNoticeFrame(
        parent,
        "Currency Transfer Limitation",
        "Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies.",
        "alert",
        width - 20,
        60
    )
    noticeFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    
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
    
    -- View Mode Toggle Button (left of Show Empty button)
    local viewMode = self.db.profile.currencyViewMode or "character"
    local toggleBtn = CreateThemedButton(titleCard, 
        viewMode == "all" and "Show All" or "Character View", 
        140)
    toggleBtn:SetPoint("RIGHT", showZeroBtn, "LEFT", -10, 0)
    
    toggleBtn:SetScript("OnClick", function(btn)
        if self.db.profile.currencyViewMode == "all" then
            self.db.profile.currencyViewMode = "character"
            btn.text:SetText("Character View")
        else
            self.db.profile.currencyViewMode = "all"
            btn.text:SetText("Show All")
        end
        self:RefreshUI()
    end)
    
    -- Hide buttons if module disabled
    if not moduleEnabled then
        showZeroBtn:Hide()
        toggleBtn:Hide()
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
