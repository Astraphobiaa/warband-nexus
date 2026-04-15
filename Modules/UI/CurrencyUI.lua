--[[
    Warband Nexus - Currency Tab
    Display all currencies across characters with Blizzard API headers
    
    Hierarchy is built by CurrencyCacheService v2.0 via collapse/expand detection.
    DB stores a tree: root headers → sub-headers → currencies.
    UI renders the tree directly — no hardcoded expansion/season name patterns.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

local issecretvalue = issecretvalue

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

-- Unique AceEvent handler identity for CurrencyUI
local CurrencyUIEvents = {}

-- Debug print helper
local DebugPrint = ns.DebugPrint

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- ============================================================================
-- HEADER HIERARCHY
-- CurrencyCacheService v2.0 stores a proper tree in db.headers using the
-- Blizzard API collapse/expand technique.  No client-side inference needed.
-- ============================================================================

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatGold = ns.UI_FormatGold
local FormatNumber = ns.UI_FormatNumber
local DrawEmptyState = ns.UI_DrawEmptyState
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local AcquireCurrencyRow = ns.UI_AcquireCurrencyRow
local ReleaseCurrencyRow = ns.UI_ReleaseCurrencyRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateNoticeFrame = ns.UI_CreateNoticeFrame
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard

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
        local isCapped = quantity >= maxQuantity
        local color = isCapped and "|cffff5959" or "|cff80ff80"
        return format("%s%s / %s|r", color, FormatNumber(quantity), FormatNumber(maxQuantity))
    else
        return format("|cffffffff%s|r", FormatNumber(quantity))
    end
end

---Check if currency matches search text
---@param currency table Currency data
---@param searchText string Search text (lowercase)
---@return boolean matches
local function CurrencyMatchesSearch(currency, searchText)
    if not searchText then
        return true
    end
    if issecretvalue and issecretvalue(searchText) then
        return true
    end
    if searchText == "" then
        return true
    end
    
    local name = SafeLower(currency.name)
    local category = SafeLower(currency.category)
    
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

---Populate a currency row frame with display data (shared by CreateCurrencyRow and virtual list createRowFn)
---@param row Frame Row frame from AcquireCurrencyRow
---@param currency table Currency data
---@param currencyID number Currency ID
---@param rowIndex number Row index for alternating colors
---@param rowWidth number Row width
---@param hideMax boolean Unused (kept for API compatibility)
local function PopulateCurrencyRowFrame(row, currency, currencyID, rowIndex, rowWidth, hideMax)
    row:SetSize(rowWidth, ROW_HEIGHT)
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

    if row.keyBadge then
        row.keyBadge:Hide()
    end

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
        row:SetAlpha(0.65)
    else
        row.icon:SetAlpha(1)
        row:SetAlpha(1)
    end
    
    local zeroAlpha = 0.5  -- Title and value alpha when quantity is 0
    
    -- Name only (no character suffix)
    row.nameText:SetWidth(rowWidth - 280)
    local displayName = currency.name or ((ns.L and ns.L["CURRENCY_UNKNOWN"]) or "Unknown Currency")
    row.nameText:SetText(displayName)
    if hasQuantity then
        row.nameText:SetTextColor(1, 1, 1, 1)
    else
        row.nameText:SetTextColor(1, 1, 1, zeroAlpha)
    end
    
    -- Character Badge (separate column, like ReputationUI)
    if currency.characterName then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.badgeText:SetPoint("LEFT", 302, 0)  -- Same position as ReputationUI
            row.badgeText:SetJustifyH("LEFT")
            row.badgeText:SetWidth(280)
        end
        row.badgeText:SetText(currency.characterName)
        if hasQuantity then
            row.badgeText:SetTextColor(1, 1, 1, 1)
        else
            row.badgeText:SetTextColor(1, 1, 1, zeroAlpha)
        end
        row.badgeText:Show()
    else
        if row.badgeText then
            row.badgeText:Hide()
        end
    end
    
    -- Amount: Gear-style season/cap line when live DB+API data exists (Dawncrests, Coffer Key Shards, …)
    local amountLine
    local usedSeasonProgressLine = false
    local curKey = currency.viewCharKey
    if (not curKey) and ns.Utilities and ns.Utilities.GetCharacterKey then
        curKey = ns.Utilities:GetCharacterKey()
    end
    if curKey and WarbandNexus.GetCurrencyData and ns.UI_FormatSeasonProgressCurrencyLine then
        local cd = WarbandNexus:GetCurrencyData(currencyID, curKey)
        if cd then
            amountLine = ns.UI_FormatSeasonProgressCurrencyLine(cd)
            usedSeasonProgressLine = true
        end
    end
    if not amountLine then
        local maxQuantity = currency.maxQuantity or 0
        amountLine = FormatCurrencyAmount(currency.quantity or 0, maxQuantity)
    end
    row.amountText:SetText(amountLine)
    -- Season/cap lines embed |cff colors; do not dim with SetTextColor or capped red (e.g. 0 / 600) washes out.
    if usedSeasonProgressLine or hasQuantity then
        row.amountText:SetTextColor(1, 1, 1, 1)
    else
        row.amountText:SetTextColor(1, 1, 1, zeroAlpha)
    end
    
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
        local tipKey = currency.viewCharKey
        if (not tipKey) and ns.Utilities and ns.Utilities.GetCharacterKey then
            tipKey = ns.Utilities:GetCharacterKey()
        end
        ShowTooltip(self, {
            type = "currency",
            currencyID = currencyID,
            charKey = tipKey,
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
    
    -- ANIMATION: Use centralized stagger animation helper
end

---Create a single currency row (PIXEL-PERFECT StorageUI style) - NO POOLING for stability
---@param parent Frame Parent frame
---@param currency table Currency data
---@param currencyID number Currency ID
---@param rowIndex number Row index for alternating colors
---@param indent number Left indent
---@param width number Parent width
---@param yOffset number Y position
---@return number newYOffset
local function CreateCurrencyRow(parent, currency, currencyID, rowIndex, indent, rowWidth, yOffset, hideMax)
    local row = AcquireCurrencyRow(parent, rowWidth, ROW_HEIGHT)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", indent, -yOffset)
    PopulateCurrencyRowFrame(row, currency, currencyID, rowIndex, rowWidth, hideMax)
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
    if self.GetCurrenciesForUI then
        globalCurrencies = self:GetCurrenciesForUI()
        
        DebugPrint(string.format("[AggregateCurrencies] Processing %d currencies with headers", 
            (function() local c = 0 for _ in pairs(globalCurrencies) do c = c + 1 end return c end)()))
    else
        DebugPrint("|cffff0000[AggregateCurrencies]|r ERROR: GetCurrenciesForUI not found")
        return result
    end
    
    -- Build character lookup
    -- CRITICAL: Use GetCharacterKey() normalization (strips spaces) to match currency DB keys
    local charLookup = {}
    for _, char in ipairs(characters) do
        local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(char.name, char.realm)
        if charKey then charLookup[charKey] = char end
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
                local matchesSearch
                if not searchText or (issecretvalue and issecretvalue(searchText)) or searchText == "" then
                    matchesSearch = true
                else
                    local cname = currData.name
                    matchesSearch = cname and not (issecretvalue and issecretvalue(cname))
                        and cname:lower():find(searchText, 1, true)
                end
                
                if matchesSearch then
                    -- ALWAYS show CURRENT character's individual quantity as the primary row value.
                    -- Tooltip shows per-character breakdown and total on hover.
                    local currentCharKey = ns.Utilities:GetCharacterKey()
                    
                    -- Resolve current character's quantity from the per-char data
                    local currentCharAmount = 0
                    if currData.chars and currData.chars[currentCharKey] then
                        local stored = currData.chars[currentCharKey]
                        currentCharAmount = (type(stored) == "number") and stored or (type(stored) == "table" and stored.quantity or 0)
                    elseif currData.isAccountWide and currData.value then
                        -- Account-wide currencies have a single shared value (no per-char breakdown)
                        currentCharAmount = currData.value
                    end
                    
                    -- Check if ANY tracked character has this currency (for showZero filter)
                    local anyCharHasIt = false
                    if currData.chars then
                        for _, amount in pairs(currData.chars) do
                            if (type(amount) == "number" and amount > 0) or (type(amount) == "table" and (amount.quantity or 0) > 0) then
                                anyCharHasIt = true
                                break
                            end
                        end
                    elseif currData.isAccountWide and (currData.value or 0) > 0 then
                        anyCharHasIt = true
                    end
                    
                    if currData.isAccountWide or currData.isAccountTransferable then
                        -- Warband Transferable section — row shows CURRENT character's amount
                        -- Hide Empty (showZero=false): only show if current char has > 0
                        -- Show Empty (showZero=true): always show (currency exists in header structure)
                        if showZero or currentCharAmount > 0 then
                            table.insert(warbandHeaderCurrencies, {
                                id = currencyID,
                                data = currData,
                                quantity = currentCharAmount
                            })
                        end
                    else
                        -- Character-Specific section — row shows CURRENT character's amount
                        local displayChar = currentCharKey
                        
                        -- Ensure current character exists in charLookup
                        if not charLookup[displayChar] then
                            for _, char in ipairs(characters) do
                                local ck = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(char.name, char.realm)
                                if ck and charLookup[ck] then
                                    displayChar = ck
                                    currentCharAmount = (currData.chars and currData.chars[ck]) or 0
                                    break
                                end
                            end
                        end
                        
                        -- Show if: showZero is true (show all), or current char has > 0
                        if (showZero or currentCharAmount > 0) and charLookup[displayChar] then
                            table.insert(charHeaderCurrencies, {
                                id = currencyID,
                                data = currData,
                                quantity = currentCharAmount,  -- CURRENT character's amount
                                bestAmount = currentCharAmount,
                                bestCharacter = charLookup[displayChar],
                                bestCharacterKey = displayChar
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
        
        -- Helper function to count currencies recursively
        local function CountCurrenciesRecursive(hdr)
            local count = 0
            for _, curr in ipairs(hdr.currencies or {}) do
                if type(curr) == "table" and curr.data then
                    count = count + 1
                end
            end
            for _, ch in ipairs(hdr.children or {}) do
                count = count + CountCurrenciesRecursive(ch)
            end
            return count
        end
        
        -- Build result headers
        local warbandHeader = nil
        local charHeader = nil
        
        local hasWarbandContent = #warbandHeaderCurrencies > 0 or #processedWarbandChildren > 0
        local hasCharContent = #charHeaderCurrencies > 0 or #processedCharChildren > 0
        
        if hasWarbandContent then
            -- Pre-compute count during data preparation
            local totalCount = #warbandHeaderCurrencies
            for _, child in ipairs(processedWarbandChildren) do
                totalCount = totalCount + CountCurrenciesRecursive(child)
            end
            
            warbandHeader = {
                name = header.name,
                currencies = warbandHeaderCurrencies,
                depth = header.depth or 0,
                children = processedWarbandChildren,
                hasDescendants = #processedWarbandChildren > 0,
                count = totalCount  -- Pre-computed count
            }
        end
        
        if hasCharContent then
            -- Pre-compute count during data preparation
            local totalCount = #charHeaderCurrencies
            for _, child in ipairs(processedCharChildren) do
                totalCount = totalCount + CountCurrenciesRecursive(child)
            end
            
            charHeader = {
                name = header.name,
                currencies = charHeaderCurrencies,
                depth = header.depth or 0,
                children = processedCharChildren,
                hasDescendants = #processedCharChildren > 0,
                count = totalCount  -- Pre-computed count
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
    HideEmptyStateCard(container, "currency")

    -- PERFORMANCE: Release pooled frames (safe - doesn't touch emptyStateContainer)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end

    -- Clean up old non-virtual children (headers, notice frames) from previous render.
    -- VLM handles its own _isVirtualRow frames; we only need to recycle stale headers.
    local recycleBin = ns.UI_RecycleBin
    local oldChildren = {container:GetChildren()}
    for i = 1, #oldChildren do
        local child = oldChildren[i]
        if not child._isVirtualRow then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end
    
    local parent = container
    local yOffset = 0
    local flatList = {}
    local globalRowIdx = 0

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
    if self.GetCurrenciesForUI then
        globalCurrencies = self:GetCurrenciesForUI()
        DebugPrint("[CurrencyUI] Loaded currency data from CurrencyCacheService")
    else
        DebugPrint("|cffff0000[CurrencyUI]|r ERROR: GetCurrenciesForUI not found")
    end
    
    -- Get headers from Direct DB (tree built by CurrencyCacheService v2.0)
    local globalHeaders = {}
    if self.db.global.currencyData and self.db.global.currencyData.headers then
        globalHeaders = self.db.global.currencyData.headers
        DebugPrint(string.format("[CurrencyUI] Loaded %d root headers from DB", #globalHeaders))
    else
        DebugPrint("[CurrencyUI] WARNING: No headers in DB")
    end
    
    -- Collect characters with currencies
    local charactersWithCurrencies = {}
    local hasAnyData = false
    
    for _, char in ipairs(characters) do
        local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey(char.name, char.realm)
        if not charKey then
            -- Skip if canonical key unavailable (should not happen when Utilities loaded)
        else
            local isOnline = (charKey == currentCharKey)
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
                    table.insert(matchingCurrencies, { id = currencyID, data = currency })
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
    end
    
    -- Sort (online first)
    table.sort(charactersWithCurrencies, function(a, b)
        if a.sortPriority ~= b.sortPriority then
            return a.sortPriority < b.sortPriority
        end
        return (a.char.name or "") < (b.char.name or "")
    end)
    
    if not hasAnyData then
        -- Check if this is a search result or general "no data" state
        if currencySearchText and currencySearchText ~= "" then
            -- Search-related empty state: use SearchResultsRenderer
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, currencySearchText, "currency")
            SearchStateManager:UpdateResults("currency", 0)
            return height
        else
            -- General "no data" empty state: use standardized factory
            local yOffset = 100
            local _, height = CreateEmptyStateCard(parent, "currency", yOffset)
            SearchStateManager:UpdateResults("currency", 0)
            return yOffset + height
        end
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
            
            -- Sync Transfer button hidden (manual transfer via in-game currency frame)
            -- local syncBtn = CreateFrame("Button", ...) syncBtn:Hide()
            
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
                    
                    -- Use pre-computed count from data preparation (Phase 4.3 performance fix)
                    local totalCount = headerData.count or 0
                    
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
                            -- Render direct currency rows (build flat list for virtual scroll)
                            if #headerData.currencies > 0 then
                                for _, curr in ipairs(headerData.currencies) do
                                    globalRowIdx = globalRowIdx + 1
                                    local displayData = {}
                                    for k, v in pairs(curr.data) do displayData[k] = v end
                                    displayData.quantity = curr.quantity
                                    displayData.viewCharKey = currentCharKey

                                    flatList[#flatList + 1] = {
                                        type = "row",
                                        yOffset = yOffset,
                                        height = ROW_HEIGHT + (GetLayout().betweenRows or 0),
                                        xOffset = headerIndent,
                                        data = displayData,
                                        currencyID = curr.id,
                                        rowIdx = globalRowIdx,
                                        rowWidth = width - headerIndent,
                                        indent = headerIndent,
                                        isShowAll = true,
                                    }
                                    yOffset = yOffset + ROW_HEIGHT + (GetLayout().betweenRows or 0)
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
                    
                    -- Use pre-computed count from data preparation (Phase 4.3 performance fix)
                    local totalCount = headerData.count or 0
                    
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
                            -- Render rows with "Best: CharName" suffix (build flat list for virtual scroll)
                            if #headerData.currencies > 0 then
                                for _, curr in ipairs(headerData.currencies) do
                                    globalRowIdx = globalRowIdx + 1
                                    local displayData = {}
                                    for k, v in pairs(curr.data) do displayData[k] = v end
                                    local classColor = RAID_CLASS_COLORS[curr.bestCharacter.classFile] or {r=1, g=1, b=1}
                                    local bestRealm = ns.Utilities and ns.Utilities:FormatRealmName(curr.bestCharacter.realm) or curr.bestCharacter.realm or ""
                                    local charName = format("|c%s%s  -  %s|r",
                                        format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
                                        curr.bestCharacter.name,
                                        bestRealm)
                                    displayData.characterName = format("|cff666666(|r%s|cff666666)|r", charName)
                                    displayData.quantity = curr.quantity
                                    displayData.viewCharKey = curr.bestCharacterKey

                                    flatList[#flatList + 1] = {
                                        type = "row",
                                        yOffset = yOffset,
                                        height = ROW_HEIGHT + (GetLayout().betweenRows or 0),
                                        xOffset = headerIndent,
                                        data = displayData,
                                        currencyID = curr.id,
                                        rowIdx = globalRowIdx,
                                        rowWidth = width - headerIndent,
                                        indent = headerIndent,
                                        isShowAll = true,
                                    }
                                    yOffset = yOffset + ROW_HEIGHT + (GetLayout().betweenRows or 0)
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
        -- Check if this is a search result or general "no data" state
        if currencySearchText and currencySearchText ~= "" then
            -- Search-related empty state: use SearchResultsRenderer
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, currencySearchText, "currency")
            SearchStateManager:UpdateResults("currency", 0)
            return height
        else
            -- General "no data" empty state: use standardized factory
            local yOffset = 100
            local _, height = CreateEmptyStateCard(parent, "currency", yOffset)
            SearchStateManager:UpdateResults("currency", 0)
            return yOffset + height
        end
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

    -- ===== VIRTUAL SCROLL SETUP =====
    local mainFrame = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local VLM = ns.VirtualListModule

    if mainFrame and VLM and #flatList > 0 then
        local totalHeight = VLM.SetupVirtualList(mainFrame, parent, 0, flatList, {
            createRowFn = function(container, entry)
                local row = AcquireCurrencyRow(container, entry.rowWidth, ROW_HEIGHT)
                PopulateCurrencyRowFrame(row, entry.data, entry.currencyID, entry.rowIdx, entry.rowWidth, entry.isShowAll)
                return row
            end,
            releaseRowFn = function(frame)
                if ReleaseCurrencyRow then ReleaseCurrencyRow(frame) end
            end,
        })
        return math.max(totalHeight, yOffset) + GetLayout().minBottomSpacing
    end

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

        -- Shared scroll child stays visible across tabs; use main frame tab + shown (same idea as StorageUI).
        local function IsCurrencyTabActive()
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            return mf and mf:IsShown() and mf.currentTab == "currency"
        end
        
        -- NOTE: Uses CurrencyUIEvents as 'self' key to avoid overwriting other modules' handlers.
        -- Loading / cache: redraw only when Currency tab is active; tab switch runs DrawCurrencyTab via PopulateContent.
        WarbandNexus.RegisterMessage(CurrencyUIEvents, E.CURRENCY_LOADING_STARTED, function()
            if parent and IsCurrencyTabActive() then
                WarbandNexus:DrawCurrencyTab(parent)
            end
        end)
        
        WarbandNexus.RegisterMessage(CurrencyUIEvents, E.CURRENCY_CACHE_READY, function()
            if parent and IsCurrencyTabActive() then
                WarbandNexus:DrawCurrencyTab(parent)
            end
        end)
        
        WarbandNexus.RegisterMessage(CurrencyUIEvents, E.CURRENCY_CACHE_CLEARED, function()
            if parent and IsCurrencyTabActive() then
                WarbandNexus:DrawCurrencyTab(parent)
            end
        end)
        
        -- WN_CURRENCY_UPDATED: handled by UI.lua SchedulePopulateContent (debounced).
        -- Registering here caused double rebuild (immediate + debounced 100ms later).
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
    HideEmptyStateCard(parent, "currency")
    
    -- CRITICAL: Clear all old frames (REPUTATION STYLE) - Keep only persistent elements
    local children = {parent:GetChildren()}
    for _, child in pairs(children) do
        -- Keep only persistent UI elements (badge)
        if child ~= parent.dbVersionBadge then
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
    
    local width = parent:GetWidth() - 20
    local fixedHeader = WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.fixedHeader
    local headerYOffset = 8
    
    -- Check if module is enabled (early check)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.currencies ~= false

    -- ===== TITLE CARD (in fixedHeader - non-scrolling) =====
    local headerParent = fixedHeader or parent
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    local CreateCard = ns.UI_CreateCard
    local titleCard = CreateCard(headerParent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("currency"))
    
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local titleTextContent = "|cff" .. hexColor .. ((ns.L and ns.L["CURRENCY_TITLE"]) or "Currency Tracker") .. "|r"
    local subtitleTextContent = (ns.L and ns.L["CURRENCY_SUBTITLE"]) or "Track all currencies across your characters"
    
    local textContainer = ns.UI.Factory:CreateContainer(titleCard, 200, 40)
    local titleText = FontManager:CreateFontString(textContainer, "header", "OVERLAY")
    titleText:SetText(titleTextContent)
    titleText:SetJustifyH("LEFT")
    local subtitleText = FontManager:CreateFontString(textContainer, "subtitle", "OVERLAY")
    subtitleText:SetText(subtitleTextContent)
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetJustifyH("LEFT")
    titleText:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)
    titleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", textContainer, "CENTER", 0, -4)
    subtitleText:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)
    
    local showZeroBtn = CreateThemedButton(titleCard, showZero and ((ns.L and ns.L["CURRENCY_HIDE_EMPTY"]) or "Hide Empty") or ((ns.L and ns.L["CURRENCY_SHOW_EMPTY"]) or "Show Empty"), 100)
    showZeroBtn:SetPoint("RIGHT", titleCard, "RIGHT", -15, 0)
    if not moduleEnabled then showZeroBtn:Hide() end
    showZeroBtn:SetScript("OnClick", function(btn)
        showZero = not showZero
        self.db.profile.currencyShowZero = showZero
        btn.text:SetText(showZero and ((ns.L and ns.L["CURRENCY_HIDE_EMPTY"]) or "Hide Empty") or ((ns.L and ns.L["CURRENCY_SHOW_EMPTY"]) or "Show Empty"))
        self:RefreshUI()
    end)
    titleCard:Show()
    
    headerYOffset = headerYOffset + GetLayout().afterHeader
    
    -- If module is disabled, show disabled state card (in scroll area)
    if not moduleEnabled then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["CURRENCY_DISABLED_TITLE"]) or "Currency Tracking")
        return 8 + cardHeight
    end
    
    -- ===== LOADING STATE =====
    if ns.CurrencyLoadingState and ns.CurrencyLoadingState.isLoading then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local UI_CreateLoadingStateCard = ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(parent, 8, ns.CurrencyLoadingState, (ns.L and ns.L["CURRENCY_LOADING_TITLE"]) or "Loading Currency Data")
            return newYOffset
        end
    end
    
    -- Search Box (in fixedHeader - non-scrolling)
    local CreateSearchBox = ns.UI_CreateSearchBox
    local currencySearchText = SearchStateManager:GetQuery("currency")
    
    local searchBox = CreateSearchBox(headerParent, width, (ns.L and ns.L["CURRENCY_SEARCH"]) or "Search currencies...", function(text)
        SearchStateManager:SetSearchQuery("currency", text)
        if parent.resultsContainer then
            SearchResultsRenderer:PrepareContainer(parent.resultsContainer)
            self:DrawCurrencyList(parent.resultsContainer, width)
        end
    end, 0.4, currencySearchText)
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    headerYOffset = headerYOffset + 32 + GetLayout().afterElement
    
    -- Set fixedHeader height so scroll area starts below it
    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    
    -- Results container starts at top of scrollChild (scroll area)
    local container
    if parent.resultsContainer then
        container = parent.resultsContainer
        container:SetParent(parent)
        HideEmptyStateCard(container, "currency")
        SearchResultsRenderer:PrepareContainer(container)
    else
        container = ns.UI.Factory:CreateContainer(parent)
        parent.resultsContainer = container
    end
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", SIDE_MARGIN, -8)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -SIDE_MARGIN, -8)
    container:SetWidth(width)
    container:SetHeight(1)
    container:Show()
    
    local listHeight = self:DrawCurrencyList(container, width)
    container:SetHeight(math.max(listHeight, 1))
    
    return 8 + listHeight
end
