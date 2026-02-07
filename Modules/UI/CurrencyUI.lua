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
local FontManager = ns.FontManager  -- Centralized font management

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatGold = ns.UI_FormatGold
local FormatNumber = ns.UI_FormatNumber
local DrawEmptyState = ns.UI_DrawEmptyState
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local AcquireCurrencyRow = ns.UI_AcquireCurrencyRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateNoticeFrame = ns.UI_CreateNoticeFrame
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge

local COLORS = ns.UI_COLORS

-- Performance: Local function references
local format = string.format
local floor = math.floor
local ipairs = ipairs
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
local HEADER_HEIGHT = GetLayout().HEADER_HEIGHT or 32
local HEADER_SPACING = GetLayout().HEADER_SPACING or 40
local SUBHEADER_SPACING = GetLayout().SUBHEADER_SPACING or 40
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local ROW_COLOR_EVEN = GetLayout().ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
local ROW_COLOR_ODD = GetLayout().ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}

--============================================================================
-- CURRENCY FORMATTING & HELPERS
--============================================================================

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
-- EVENT-DRIVEN UI REFRESH
--============================================================================
-- Event registration is now handled in DrawCurrencyTab (REPUTATION STYLE)
-- This ensures events are registered only once per parent and matches ReputationUI pattern

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
    local ROW_COLOR_EVEN = GetLayout().ROW_COLOR_EVEN or {0.08, 0.08, 0.10, 1}
    local ROW_COLOR_ODD = GetLayout().ROW_COLOR_ODD or {0.06, 0.06, 0.08, 1}
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
    local displayName = currency.name or ((ns.L and ns.L["CURRENCY_UNKNOWN"]) or "Unknown Currency")
    row.nameText:SetText(displayName)
    -- Color set by pooling reset (white), but confirm:
    row.nameText:SetTextColor(1, 1, 1) -- Always white per StorageUI style
    
    -- Character Badge (separate column, like ReputationUI)
    if currency.characterName then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
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
    
    -- Amount (always show max if available - NO hideMax)
    local maxQuantity = currency.maxQuantity or 0
    row.amountText:SetText(FormatCurrencyAmount(currency.quantity or 0, maxQuantity))
    row.amountText:SetTextColor(1, 1, 1) -- Always white
    
    -- Hover effect (use new tooltip system)
    row:SetScript("OnEnter", function(self)
        if not ShowTooltip then
            -- Use TooltipService fallback
            local tooltipData = {
                type = "currency",
                currencyID = currencyID,
                name = currency.name or "Currency"
            }
            ns.TooltipService:Show(self, tooltipData)
            return
        end
        
        -- Use new tooltip system
        ShowTooltip(self, {
            type = "currency",
            currencyID = currencyID,
            anchor = "ANCHOR_LEFT"
        })
    end)
    
    row:SetScript("OnLeave", function(self)
        if HideTooltip then
            HideTooltip()
        else
            ns.TooltipService:Hide()
        end
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
    
    return yOffset + ROW_HEIGHT + GetLayout().betweenRows
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
    
    -- Get currency data from new Direct DB architecture
    local globalCurrencies = {}
    if self.GetCurrenciesLegacyFormat then
        globalCurrencies = self:GetCurrenciesLegacyFormat()
        
        DebugPrint(string.format("[AggregateCurrencies] Processing %d currencies with headers", 
            (function() local c = 0 for _ in pairs(globalCurrencies) do c = c + 1 end return c end)()))
    else
        DebugPrint("|cffff0000[AggregateCurrencies]|r ERROR: GetCurrenciesLegacyFormat not found")
        return result
    end
    
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
                        local quantity = 0
                        if currData.isAccountWide then
                            -- Account-wide currencies use 'value' field
                            quantity = currData.value or 0
                        elseif currData.isAccountTransferable then
                            -- Transferable currencies use 'chars' table - sum across all characters
                            for charKey, amount in pairs(currData.chars or {}) do
                                quantity = quantity + amount
                            end
                        end
                        
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
    local processedHeaders = 0
    if currencyHeaders and type(currencyHeaders) == "table" then
        for _, header in ipairs(currencyHeaders) do
            if (header.depth or 0) == 0 then
                processedHeaders = processedHeaders + 1
                local warbandHeader, charHeader = ProcessHeader(header)
                if warbandHeader then
                    table.insert(result.warbandTransferable, warbandHeader)
                end
                if charHeader then
                    table.insert(result.characterSpecific, charHeader)
                end
            end
        end
    else
        DebugPrint("|cffff0000[AggregateCurrencies]|r ERROR: currencyHeaders is nil or not a table!")
    end
    
    DebugPrint(string.format("[AggregateCurrencies] Result: %d warband headers, %d char-specific headers", 
        #result.warbandTransferable, #result.characterSpecific))
    
    return result
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawCurrencyList(container, width)
    if not container then return 0 end
    
    self.recentlyExpanded = self.recentlyExpanded or {}
    
    -- Hide empty state container (will be shown again if needed)
    if container.emptyStateContainer then
        container.emptyStateContainer:Hide()
    end
    
    -- PERFORMANCE: Release pooled frames (safe - doesn't touch emptyStateContainer)
    if ReleaseAllPooledChildren then 
        ReleaseAllPooledChildren(container)
    end
    
    local parent = container
    local yOffset = 0
    
    
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    -- Get search text from SearchStateManager
    local currencySearchText = SearchStateManager:GetQuery("currency")
    
    -- Get all characters (filter tracked only)
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    if allCharacters then
        for _, char in ipairs(allCharacters) do
            if char.isTracked ~= false then  -- Only tracked characters
                table.insert(characters, char)
            end
        end
    end
    
    if not characters or #characters == 0 then
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, "", "currency")
        SearchStateManager:UpdateResults("currency", 0)
        return height
    end
    
    -- Get current online character
    local currentCharKey = ns.Utilities:GetCharacterKey()
    
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
    
    -- Build currency data from global storage (Direct DB architecture)
    local globalCurrencies = {}
    if self.GetCurrenciesLegacyFormat then
        globalCurrencies = self:GetCurrenciesLegacyFormat()
        DebugPrint("[CurrencyUI] Loaded currency data from CurrencyCacheService")
    else
        DebugPrint("|cffff0000[CurrencyUI]|r ERROR: GetCurrenciesLegacyFormat not found")
    end
    
    -- Get headers from Direct DB
    local globalHeaders = {}
    if self.db.global.currencyData and self.db.global.currencyData.headers then
        globalHeaders = self.db.global.currencyData.headers
        local headerCount = 0
        for _ in pairs(globalHeaders) do headerCount = headerCount + 1 end
        DebugPrint(string.format("[CurrencyUI] Loaded %d headers from DB", headerCount))
    else
        DebugPrint("[CurrencyUI] WARNING: No headers in DB")
    end
    
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
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, currencySearchText, "currency")
        SearchStateManager:UpdateResults("currency", 0)
        return height
    end
    
    -- ===== SHOW ALL MODE (ONLY) =====
    local aggregated = AggregateCurrencies(self, characters, globalHeaders, currencySearchText, showZero)
        
        -- Section 1: Warband Transferable
        if #aggregated.warbandTransferable > 0 then
            local sectionKey = "currency-warband"
            local sectionExpanded = IsExpanded(sectionKey, true)
            
            local sectionHeader, _, warbandIcon = CreateCollapsibleHeader(
                parent,
                (ns.L and ns.L["CURRENCY_WARBAND_TRANSFERABLE"]) or "All Warband Transferable",
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
                    
                    -- Render header only if it has actual currencies (hide empty headers)
                    if totalCount > 0 then
                        local GetCurrencyHeaderIcon = ns.UI_GetCurrencyHeaderIcon
                        local headerIcon = GetCurrencyHeaderIcon(headerData.name)
                        local blizHeader = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. FormatNumber(totalCount) .. ")",
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
                                    -- Create display data with aggregated quantity
                                    local displayData = {}
                                    for k, v in pairs(curr.data) do 
                                        displayData[k] = v 
                                    end
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
                (ns.L and ns.L["CURRENCY_CHARACTER_SPECIFIC"]) or "Character-Specific Currencies",
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
                    
                    -- Render header only if it has actual currencies (hide empty headers)
                    if totalCount > 0 then
                        local GetCurrencyHeaderIcon = ns.UI_GetCurrencyHeaderIcon
                        local headerIcon = GetCurrencyHeaderIcon(headerData.name)
                        local blizHeader = CreateCollapsibleHeader(
                            parent,
                            headerData.name .. " (" .. FormatNumber(totalCount) .. ")",
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
        local height = SearchResultsRenderer:RenderEmptyState(self, parent, currencySearchText, "currency")
        SearchStateManager:UpdateResults("currency", 0)
        return height
    end
    
    -- ===== API LIMITATION NOTICE =====
    yOffset = yOffset + (SECTION_SPACING * 2)
    
    local noticeFrame = CreateNoticeFrame(
        parent,
        (ns.L and ns.L["CURRENCY_TRANSFER_NOTICE_TITLE"]) or "Currency Transfer Limitation",
        (ns.L and ns.L["CURRENCY_TRANSFER_NOTICE_DESC"]) or "Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies.",
        "alert",
        width - 20,
        60
    )
    noticeFrame:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + GetLayout().afterHeader
    
    -- Update SearchStateManager with result count (track total rendered currencies)
    local totalCurrencies = 0
    for _, charData in ipairs(charactersWithCurrencies) do
        totalCurrencies = totalCurrencies + #(charData.currencies or {})
    end
    SearchStateManager:UpdateResults("currency", totalCurrencies)
    
    return yOffset
end

--============================================================================
-- CURRENCY TAB WRAPPER (Fixes focus issue)
--============================================================================

function WarbandNexus:DrawCurrencyTab(parent)
    if not parent then
        self:Print("|cffff0000ERROR: No parent container provided to DrawCurrencyTab|r")
        return
    end
    
    -- Register event listeners (only once per parent) - REPUTATION STYLE
    if not parent.currencyUpdateHandler then
        parent.currencyUpdateHandler = true
        
        -- Loading started - always refresh (tab switch will render if visible)
        self:RegisterMessage("WN_CURRENCY_LOADING_STARTED", function()
            if parent then
                self:DrawCurrencyTab(parent)
            end
        end)
        
        -- Cache ready - always refresh
        self:RegisterMessage("WN_CURRENCY_CACHE_READY", function()
            if parent then
                self:DrawCurrencyTab(parent)
            end
        end)
        
        -- Cache cleared - always refresh
        self:RegisterMessage("WN_CURRENCY_CACHE_CLEARED", function()
            if parent then
                self:DrawCurrencyTab(parent)
            end
        end)
        
        -- Real-time update event - only refresh if visible
        self:RegisterMessage("WN_CURRENCY_UPDATED", function()
            if parent and parent:IsVisible() then
                self:DrawCurrencyTab(parent)
            end
        end)
    end
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "CurrencyData [Loading...]"
        if self.db.global.currencyData and next(self.db.global.currencyData.currencies or {}) then
            local cacheVersion = self.db.global.currencyData.version or "unknown"
            dataSource = "CurrencyData v" .. cacheVersion
        end
        parent.dbVersionBadge = CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    
    -- CRITICAL: Clear all old frames (REPUTATION STYLE) - Keep only persistent elements
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
        -- Keep only persistent UI elements (badge, emptyStateContainer)
        if child ~= parent.dbVersionBadge 
           and child ~= parent.emptyStateContainer then
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
    
    local yOffset = 8 -- Top padding
    local width = parent:GetWidth() - 20
    
    -- Check if module is enabled (early check)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.currencies ~= false
    
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    
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
    
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    -- Use factory pattern positioning for standardized header layout
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["CURRENCY_TITLE"]) or "Currency Tracker") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["CURRENCY_SUBTITLE"]) or "Track all currencies across your characters"
    
    -- Create container for text group (using Factory pattern)
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    
    -- Create title text (header font, colored)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    
    -- Create subtitle text
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetJustifyH("LEFT")
    
    -- Position texts: label at CENTER (0px), value at CENTER (-4px) - matching factory pattern
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)  -- Value below center
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD (no checkbox)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)  -- Center to card!
    
    -- Show 0 Toggle (rightmost, standardized to 100px)
    local showZeroBtn = CreateThemedButton(titleCard, showZero and ((ns.L and ns.L["CURRENCY_HIDE_EMPTY"]) or "Hide Empty") or ((ns.L and ns.L["CURRENCY_SHOW_EMPTY"]) or "Show Empty"), 100)
    showZeroBtn:SetPoint("RIGHT", titleCard, "RIGHT", -15, 0)
    
    -- Hide button if module disabled
    if not moduleEnabled then
        showZeroBtn:Hide()
    end
    
    showZeroBtn:SetScript("OnClick", function(btn)
        showZero = not showZero
        self.db.profile.currencyShowZero = showZero
        btn.text:SetText(showZero and ((ns.L and ns.L["CURRENCY_HIDE_EMPTY"]) or "Hide Empty") or ((ns.L and ns.L["CURRENCY_SHOW_EMPTY"]) or "Show Empty"))
        self:RefreshUI()
    end)
    
    titleCard:Show()
    
    yOffset = yOffset + GetLayout().afterHeader
    
    -- If module is disabled, show beautiful disabled state card
    if not moduleEnabled then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (ns.L and ns.L["CURRENCY_DISABLED_TITLE"]) or "Currency Tracking")
        return yOffset + cardHeight
    end
    
    -- ===== LOADING STATE =====
    -- Show loading card if currency scan is in progress
    if ns.CurrencyLoadingState and ns.CurrencyLoadingState.isLoading then
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                ns.CurrencyLoadingState,
                (ns.L and ns.L["CURRENCY_LOADING_TITLE"]) or "Loading Currency Data"
            )
            return newYOffset  -- STOP HERE - don't render anything else
        end
    end
    
    -- Search Box
    local CreateSearchBox = ns.UI_CreateSearchBox
    -- Use SearchStateManager for state management
    local currencySearchText = SearchStateManager:GetQuery("currency")
    
    local searchBox = CreateSearchBox(parent, width, (ns.L and ns.L["CURRENCY_SEARCH"]) or "Search currencies...", function(text)
        -- Update search state via SearchStateManager (throttled, event-driven)
        SearchStateManager:SetSearchQuery("currency", text)
        
        -- Prepare container for rendering
        if parent.resultsContainer then
            SearchResultsRenderer:PrepareContainer(parent.resultsContainer)
            
            -- Redraw currency list
            self:DrawCurrencyList(parent.resultsContainer, width)
        end
    end, 0.4, currencySearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    yOffset = yOffset + 32 + GetLayout().afterElement  -- Search box height + standard gap
    
    -- Container - CRITICAL FIX: Always create fresh container to prevent layout corruption
    -- REASON: Reusing containers with hidden pooled rows causes yOffset to accumulate
    local container
    if parent.resultsContainer then
        container = parent.resultsContainer
        -- Hide emptyStateContainer before clearing children
        if container.emptyStateContainer then
            container.emptyStateContainer:Hide()
        end
        SearchResultsRenderer:PrepareContainer(container)
    else
        container = ns.UI.Factory:CreateContainer(parent)
        parent.resultsContainer = container
    end
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
