--[[
    Warband Nexus - Currency Tab
    Display all currencies across characters with Blizzard API headers
    
    Hierarchy is built by CurrencyCacheService v2.0 via collapse/expand detection.
    DB stores a tree: root headers -> sub-headers -> currencies.
    UI renders the tree directly â€” no hardcoded expansion/season name patterns.
    Merged per-currency rows use WarbandNexus:GetCurrenciesForUI() (same snapshot as Gear / PvE).
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

local DebugPrint = ns.DebugPrint

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

---Read per-character quantity from merged snapshot row (entry.chars may use SV row key and/or Name-Realm).
local function GetCurrencyCharQuantityFromSnapshot(currData, charKey)
    if not currData then return 0 end
    if currData.isAccountWide then
        return currData.value or 0
    end
    local ch = currData.chars
    if not ch or not charKey or charKey == "" then return 0 end
    local function read(k)
        if not k then return nil end
        local s = ch[k]
        if s == nil then return nil end
        if type(s) == "number" then return s end
        if type(s) == "table" then return s.quantity or 0 end
        return 0
    end
    local q = read(charKey)
    if q ~= nil then return q end
    local U = ns.Utilities
    if U and U.GetCanonicalCharacterKey then
        local ck = U:GetCanonicalCharacterKey(charKey)
        if ck and ck ~= charKey then
            q = read(ck)
            if q ~= nil then return q end
        end
    end
    return 0
end

---Sum quantities across tracked roster keys and find the character with the highest amount.
---Iterates the character list (not raw pairs on currData.chars) to avoid GUID + Name-Realm double-count.
---@return number totalAmount
---@return number bestAmount
---@return string|nil bestCharKey
---@return boolean anyCharHasIt
local function SummarizeCurrencyAcrossTrackedChars(currData, characters, charLookup)
    local totalAmount = 0
    local bestAmount = 0
    local bestCharKey = nil
    local anyCharHasIt = false

    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
        if charKey and charLookup[charKey] then
            local amount = GetCurrencyCharQuantityFromSnapshot(currData, charKey)
            if amount > 0 then
                anyCharHasIt = true
            end
            totalAmount = totalAmount + amount
            if amount > bestAmount then
                bestAmount = amount
                bestCharKey = charKey
            end
        end
    end

    if not bestCharKey then
        for ci = 1, #characters do
            local char = characters[ci]
            local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
            if charKey and charLookup[charKey] then
                bestCharKey = charKey
                break
            end
        end
    end

    return totalAmount, bestAmount, bestCharKey, anyCharHasIt
end

---Logged-in character row key for warband split display (GUID / roster key aliases).
local function ResolveSessionCharacterKey(charLookup, characters)
    local sessionKey = ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey()
    if sessionKey and charLookup[sessionKey] then
        return sessionKey, charLookup[sessionKey]
    end
    local U = ns.Utilities
    local storage = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus)
    if storage and charLookup[storage] then
        return storage, charLookup[storage]
    end
    if storage and U and U.GetCanonicalCharacterKey then
        local canon = U:GetCanonicalCharacterKey(storage)
        if canon and charLookup[canon] then
            return canon, charLookup[canon]
        end
    end
    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
        if charKey and charLookup[charKey] then
            return charKey, charLookup[charKey]
        end
    end
    return nil, nil
end

---Warband transferable row: session amount / warband total (session part may use cap colors).
local function FormatWarbandAmountSplit(sessionAmount, totalQuantity, maxQuantity)
    local bright = ThemeTextHex("Bright")
    local muted = ThemeTextHex("Muted")
    local session = sessionAmount or 0
    local total = totalQuantity or 0
    local suffix = muted .. " / " .. bright .. FormatNumber(total) .. "|r"
    if maxQuantity and maxQuantity > 0 then
        local isCapped = session >= maxQuantity
        local color = isCapped and SemanticColorHex(COLORS.red) or SemanticColorHex(COLORS.green)
        return color .. FormatNumber(session) .. "|r" .. suffix
    end
    return bright .. FormatNumber(session) .. "|r" .. suffix
end

-- HEADER HIERARCHY
-- CurrencyCacheService v2.0 stores a proper tree in db.headers using the
-- Blizzard API collapse/expand technique.  No client-side inference needed.

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatGold = ns.UI_FormatGold
local FormatNumber = ns.UI_FormatNumber
local DrawEmptyState = ns.UI_DrawEmptyState
local DrawSectionEmptyState = ns.UI_DrawSectionEmptyState
local AcquireCurrencyRow = ns.UI_AcquireCurrencyRow
local ReleaseCurrencyRowsFromSubtree = ns.UI_ReleaseCurrencyRowsFromSubtree
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren
local UnbindSeasonProgressAmount = ns.UI_UnbindSeasonProgressAmount
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateNoticeFrame = ns.UI_CreateNoticeFrame
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard

local COLORS = ns.UI_COLORS

local function ThemeTextHex(role)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    if role == "Dim" then return "|cff888888" end
    if role == "Muted" then return "|cffaaaaaa" end
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function SemanticColorHex(color)
    if not color then return ThemeTextHex("Bright") end
    return format("|cff%02x%02x%02x", (color[1] or 1) * 255, (color[2] or 1) * 255, (color[3] or 1) * 255)
end

local function FormatParenBadge(innerColoredText)
    local muted = ThemeTextHex("Muted")
    return muted .. "(|r" .. innerColoredText .. muted .. ")|r"
end

-- Performance: Local function references
local format = string.format
local floor = math.floor
local pairs = pairs
local next = next

-- Import shared UI constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or 8
local ROW_HEIGHT = GetLayout().ROW_HEIGHT or 26
local ROW_SPACING = GetLayout().ROW_SPACING or 26
local SECTION_COLLAPSE_HEADER_HEIGHT = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
local HEADER_SPACING = GetLayout().HEADER_SPACING or 44
local SUBHEADER_SPACING = GetLayout().SUBHEADER_SPACING or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15

--- List row geometry: anchor chain (name â†” badge â†” amount) so columns never overlap (WN-UI-layout).
local CURRENCY_LIST_ROW = {
    TEXT_LEFT = 43,
    COL_GAP = 6,
    AMOUNT_RIGHT_PAD = 10,
    AMOUNT_MIN_W = 94,
    AMOUNT_MAX_W = 230,
    BADGE_MAX_W = 200,
    BADGE_MIN_W = 48,
    NAME_MIN_FOR_BADGE = 72,
}

-- CURRENCY FORMATTING & HELPERS

---Format currency quantity with cap indicator
---@param quantity number Current amount
---@param maxQuantity number Maximum amount (0 = no cap)
---@return string Formatted text with color
local function FormatCurrencyAmount(quantity, maxQuantity)
    if maxQuantity > 0 then
        local isCapped = quantity >= maxQuantity
        local color = isCapped and SemanticColorHex(COLORS.red) or SemanticColorHex(COLORS.green)
        return format("%s%s / %s|r", color, FormatNumber(quantity), FormatNumber(maxQuantity))
    else
        return format("%s%s|r", ThemeTextHex("Bright"), FormatNumber(quantity))
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

-- EVENT-DRIVEN UI REFRESH
-- Event registration is now handled in DrawCurrencyTab (REPUTATION STYLE)

-- CURRENCY ROW RENDERING (EXACT StorageUI style)

---Populate a currency row frame with display data (shared by CreateCurrencyRow and virtual list createRowFn)
---@param row Frame Row frame from AcquireCurrencyRow
---@param currency table Currency data
---@param currencyID number Currency ID
---@param rowIndex number Row index for alternating colors
---@param rowWidth number Row width
---@param hideMax boolean Unused (kept for API compatibility)
local function PopulateCurrencyRowFrame(row, currency, currencyID, rowIndex, rowWidth, hideMax)
    row:SetSize(rowWidth, ROW_HEIGHT)
    if ns.UI.Factory and ns.UI.Factory.ApplyRowBackground then
        ns.UI.Factory:ApplyRowBackground(row, rowIndex)
    end

    if row.keyBadge then
        row.keyBadge:Hide()
    end

    -- Pooled row reuse: drop stale Shift watcher before rebinding or plain SetText
    if UnbindSeasonProgressAmount and row.amountText then
        UnbindSeasonProgressAmount(row.amountText)
    end

    local hasQuantity = (currency.quantity or 0) > 0
    if currency.warbandAmountSplit and (currency.totalQuantity or 0) > 0 then
        hasQuantity = true
    end
    
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

    -- Anchor chain: amount (fixed width from right) -> badge (optional) -> name (fills remainder).
    -- Avoids SetWidth-only math drifting from FontString intrinsic size / pooled anchors.
    local L = CURRENCY_LIST_ROW
    local rw = math.max(120, rowWidth or 0)
    local gap = L.COL_GAP
    local padR = L.AMOUNT_RIGHT_PAD
    local showBadge = currency.characterName and true or false
    local showWarbandSplit = currency.warbandAmountSplit and true or false

    local amountFrac = showBadge and 0.26 or 0.24
    if showWarbandSplit then
        amountFrac = showBadge and 0.34 or 0.30
    end
    local amountW = math.min(L.AMOUNT_MAX_W, math.max(L.AMOUNT_MIN_W, floor(rw * amountFrac)))

    if row.nameText.SetWordWrap then row.nameText:SetWordWrap(false) end
    if row.nameText.SetNonSpaceWrap then row.nameText:SetNonSpaceWrap(false) end
    if row.nameText.SetMaxLines then row.nameText:SetMaxLines(1) end

    row.amountText:ClearAllPoints()
    row.amountText:SetJustifyH("RIGHT")
    row.amountText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -padR, 0)
    row.amountText:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -padR, 0)
    row.amountText:SetWidth(amountW)

    row.nameText:ClearAllPoints()
    row.nameText:SetJustifyH("LEFT")
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", L.TEXT_LEFT, 0)
    row.nameText:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", L.TEXT_LEFT, 0)

    if showBadge then
        if not row.badgeText then
            row.badgeText = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.badgeText:SetJustifyH("LEFT")
            if row.badgeText.SetWordWrap then row.badgeText:SetWordWrap(false) end
            if row.badgeText.SetNonSpaceWrap then row.badgeText:SetNonSpaceWrap(false) end
            if row.badgeText.SetMaxLines then row.badgeText:SetMaxLines(1) end
        end
        local amountBlockStart = rw - padR - amountW
        local spaceNameBadge = amountBlockStart - gap - L.TEXT_LEFT - gap
        local badgeMax = spaceNameBadge - L.NAME_MIN_FOR_BADGE
        if badgeMax < L.BADGE_MIN_W then
            badgeMax = math.max(24, spaceNameBadge - 40)
        else
            badgeMax = math.min(L.BADGE_MAX_W, math.max(L.BADGE_MIN_W, badgeMax))
        end
        row.badgeText:ClearAllPoints()
        row.badgeText:SetJustifyH("LEFT")
        row.badgeText:SetPoint("TOPRIGHT", row.amountText, "TOPLEFT", -gap, 0)
        row.badgeText:SetPoint("BOTTOMRIGHT", row.amountText, "BOTTOMLEFT", -gap, 0)
        row.badgeText:SetWidth(badgeMax)
        row.nameText:SetPoint("TOPRIGHT", row.badgeText, "TOPLEFT", -gap, 0)
        row.nameText:SetPoint("BOTTOMRIGHT", row.badgeText, "BOTTOMLEFT", -gap, 0)
    else
        if row.badgeText then
            row.badgeText:Hide()
        end
        row.nameText:SetPoint("TOPRIGHT", row.amountText, "TOPLEFT", -gap, 0)
        row.nameText:SetPoint("BOTTOMRIGHT", row.amountText, "BOTTOMLEFT", -gap, 0)
    end
    
    -- Name only (no character suffix)
    local displayName = currency.name or ((ns.L and ns.L["CURRENCY_UNKNOWN"]) or "Unknown Currency")
    row.nameText:SetText(displayName)
    if hasQuantity then
        ns.UI_SetTextColorRole(row.nameText, "Bright")
    else
        ns.UI_SetTextColorRole(row.nameText, "Dim", zeroAlpha)
    end
    
    -- Character badge (Character-Specific section)
    if showBadge then
        row.badgeText:SetText(currency.characterName)
        if hasQuantity then
            ns.UI_SetTextColorRole(row.badgeText, "Bright")
        else
            ns.UI_SetTextColorRole(row.badgeText, "Dim", zeroAlpha)
        end
        row.badgeText:Show()
    end
    
    -- Amount: Gear-style season/cap line when live DB+API data exists (Dawncrests, Coffer Key Shards, â€¦)
    local amountLine
    local usedSeasonProgressLine = false
    local curKey = currency.viewCharKey
    if (not curKey) and ns.UI_GetSubsidiaryCharKey then
        curKey = ns.UI_GetSubsidiaryCharKey()
    end
    if currency.warbandAmountSplit then
        local totalQ = currency.totalQuantity or 0
        if curKey and WarbandNexus.GetCurrencyData and ns.UI_BindSeasonProgressAmount then
            local cd = WarbandNexus:GetCurrencyData(currencyID, curKey)
            if cd then
                ns.UI_BindSeasonProgressAmount(row.amountText, cd, { warbandTotal = totalQ })
                usedSeasonProgressLine = true
                local rawAmt = row.amountText:GetText()
                amountLine = ""
                if rawAmt and not (issecretvalue and issecretvalue(rawAmt)) then
                    amountLine = rawAmt
                end
            end
        end
        if not amountLine then
            amountLine = FormatWarbandAmountSplit(currency.quantity or 0, totalQ, currency.maxQuantity or 0)
            row.amountText:SetText(amountLine)
        end
    elseif curKey and WarbandNexus.GetCurrencyData and ns.UI_BindSeasonProgressAmount then
        local cd = WarbandNexus:GetCurrencyData(currencyID, curKey)
        if cd then
            -- Shift-aware: default = current only (cap-colored); Shift = expanded current\194\183earned/cap.
            ns.UI_BindSeasonProgressAmount(row.amountText, cd)
            usedSeasonProgressLine = true
            local rawAmt = row.amountText:GetText()
            amountLine = ""
            if rawAmt and not (issecretvalue and issecretvalue(rawAmt)) then
                amountLine = rawAmt
            end
        end
    end
    if not amountLine then
        local maxQuantity = currency.maxQuantity or 0
        amountLine = FormatCurrencyAmount(currency.quantity or 0, maxQuantity)
        row.amountText:SetText(amountLine)
    end
    -- Season/cap lines embed |cff colors; do not dim with SetTextColor or capped red (e.g. 0 / 600) washes out.
    if usedSeasonProgressLine or hasQuantity then
        ns.UI_SetTextColorRole(row.amountText, "Bright")
    else
        ns.UI_SetTextColorRole(row.amountText, "Dim", zeroAlpha)
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
        if (not tipKey) and ns.UI_GetSubsidiaryCharKey then
            tipKey = ns.UI_GetSubsidiaryCharKey()
        end
        ShowTooltip(self, {
            type = "currency",
            currencyID = currencyID,
            charKey = tipKey,
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

-- AGGREGATE CURRENCIES (for Show All mode)

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
    
    local globalCurrencies = self:GetCurrenciesForUI()
    -- Use actual SavedVariables row key (guid or Name-Realm) so currency DB lookups stay aligned.
    local charLookup = {}
    for ci = 1, #characters do
        local char = characters[ci]
        local charKey = ns.UI_GetCharKey and ns.UI_GetCharKey(char)
        if charKey then charLookup[charKey] = char end
    end
    
    -- Recursive function to process header tree
    local function ProcessHeader(header)
        local warbandHeaderCurrencies = {}
        local charHeaderCurrencies = {}
        
        -- Process direct currencies
        local hdrCurrencies = header.currencies or {}
        for hci = 1, #hdrCurrencies do
            local currencyID = hdrCurrencies[hci]
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
                    local totalAmount, bestAmount, bestCharKey, anyCharHasIt =
                        SummarizeCurrencyAcrossTrackedChars(currData, characters, charLookup)

                    if currData.isAccountWide or currData.isAccountTransferable then
                        local sessionKey, sessionChar = ResolveSessionCharacterKey(charLookup, characters)
                        local sessionAmount = sessionKey
                            and GetCurrencyCharQuantityFromSnapshot(currData, sessionKey) or 0
                        local displayTotal = totalAmount
                        if currData.isAccountWide then
                            displayTotal = currData.value or totalAmount
                        end

                        if showZero or sessionAmount > 0 or displayTotal > 0 or anyCharHasIt then
                            table.insert(warbandHeaderCurrencies, {
                                id = currencyID,
                                data = currData,
                                quantity = sessionAmount,
                                sessionAmount = sessionAmount,
                                totalQuantity = displayTotal,
                                sessionCharacter = sessionChar,
                                sessionCharacterKey = sessionKey,
                            })
                        end
                    else
                        -- Character-Specific: total across roster; badge names who holds the highest stack.
                        if (showZero or totalAmount > 0 or anyCharHasIt) and bestCharKey and charLookup[bestCharKey] then
                            table.insert(charHeaderCurrencies, {
                                id = currencyID,
                                data = currData,
                                quantity = totalAmount,
                                bestAmount = bestAmount,
                                bestCharacter = charLookup[bestCharKey],
                                bestCharacterKey = bestCharKey,
                            })
                        end
                    end
                end
            end
        end
        
        -- Recursively process children
        local processedWarbandChildren = {}
        local processedCharChildren = {}
        
        local hdrChildren = header.children or {}
        for chi = 1, #hdrChildren do
            local child = hdrChildren[chi]
            local warbandChild, charChild = ProcessHeader(child)
            if warbandChild then
                table.insert(processedWarbandChildren, warbandChild)
            end
            if charChild then
                table.insert(processedCharChildren, charChild)
            end
        end
        
        local function CountCurrenciesRecursive(hdr)
            local count = 0
            local hc = hdr.currencies or {}
            for i = 1, #hc do
                local curr = hc[i]
                if type(curr) == "table" and curr.data then
                    count = count + 1
                end
            end
            local hch = hdr.children or {}
            for i = 1, #hch do
                count = count + CountCurrenciesRecursive(hch[i])
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
            for wi = 1, #processedWarbandChildren do
                totalCount = totalCount + CountCurrenciesRecursive(processedWarbandChildren[wi])
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
            for ci = 1, #processedCharChildren do
                totalCount = totalCount + CountCurrenciesRecursive(processedCharChildren[ci])
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
        for hi = 1, #currencyHeaders do
            local header = currencyHeaders[hi]
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

    return result
end

--- Leaf currency count for SearchStateManager (matches rendered header tree, not chars x currencies pre-scan).
local function CountAggregatedCurrencyLeaves(headers)
    if not headers then return 0 end
    local n = 0
    for i = 1, #headers do
        local h = headers[i]
        local currencies = h.currencies or {}
        n = n + #currencies
        n = n + CountAggregatedCurrencyLeaves(h.children)
    end
    return n
end

-- MAIN DRAW FUNCTION

function WarbandNexus:DrawCurrencyList(container, width)
    if not container then return 0 end

    -- Hide empty state container (will be shown again if needed)
    HideEmptyStateCard(container, "currency")

    local mfForVirtual = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfForVirtual and ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
    end

    -- PERFORMANCE: Release pooled frames (safe - doesn't touch emptyStateContainer)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end

    -- Clean up old non-virtual children (headers, notice frames) from previous render.
    -- VLM handles its own _isVirtualRow frames; we only need to recycle stale headers.
    -- Nested currency rows live under collapsible section bodies (not direct children of container);
    -- release them to the pool before reparenting wrappers â€” matches ReputationUI / PopulateContent.
    local recycleBin = ns.UI_RecycleBin
    local oldChildren = {container:GetChildren()}
    for i = 1, #oldChildren do
        if ReleaseCurrencyRowsFromSubtree then
            ReleaseCurrencyRowsFromSubtree(oldChildren[i])
        end
    end
    for i = 1, #oldChildren do
        local child = oldChildren[i]
        if not child._isVirtualRow then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end
    local oldRegions = {container:GetRegions()}
    for i = 1, #oldRegions do
        local region = oldRegions[i]
        if region:GetObjectType() == "FontString" then
            region:Hide()
        end
    end

    local parent = container
    local globalRowIdx = 0

    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    -- Get search text from SearchStateManager
    local currencySearchText = SearchStateManager:GetQuery("currency")
    
    -- Get all characters (filter tracked only)
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    if allCharacters then
        for ai = 1, #allCharacters do
            local char = allCharacters[ai]
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
    
    -- Get current online character (aliases: roster row key vs session keys can differ)
    local sessionCharKeys = {}
    local function addSessionKey(k)
        if not k or k == "" then return end
        for j = 1, #sessionCharKeys do
            if sessionCharKeys[j] == k then return end
        end
        sessionCharKeys[#sessionCharKeys + 1] = k
    end
    do
        local subKey = ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey()
        addSessionKey(subKey)
        local U = ns.Utilities
        addSessionKey(U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus))
        local storage = U and U.GetCharacterStorageKey and U:GetCharacterStorageKey(WarbandNexus)
        addSessionKey(storage)
        if storage and U and U.GetCanonicalCharacterKey then
            addSessionKey(U:GetCanonicalCharacterKey(storage))
        end
    end
    local currentCharKey = sessionCharKeys[1]
    local function isCharKeyCurrentSession(k)
        if not k then return false end
        for i = 1, #sessionCharKeys do
            if k == sessionCharKeys[i] then return true end
        end
        local U = ns.Utilities
        if U and U.GetCanonicalCharacterKey then
            local c1 = U:GetCanonicalCharacterKey(k) or k
            for i = 1, #sessionCharKeys do
                local c2 = U:GetCanonicalCharacterKey(sessionCharKeys[i]) or sessionCharKeys[i]
                if c1 == c2 then return true end
            end
        end
        return false
    end
    
    -- Expanded state management
    local expanded = self.db.profile.currencyExpanded or {}
    
    local function IsExpanded(key, default)
        if self.db.profile.currencyExpandOverride == "all_collapsed" then
            return false
        end
        if self.currencyExpandAllActive then return true end
        if expanded[key] == nil then return default or false end
        return expanded[key]
    end
    
    local function PersistExpand(key, isExpanded)
        if self.db.profile.currencyExpandOverride then
            self.db.profile.currencyExpandOverride = nil
        end
        if not self.db.profile.currencyExpanded then
            self.db.profile.currencyExpanded = {}
        end
        self.db.profile.currencyExpanded[key] = isExpanded
    end
    
    -- Get headers from Direct DB (tree built by CurrencyCacheService v2.0)
    local globalHeaders = {}
    if self.db.global.currencyData and self.db.global.currencyData.headers then
        globalHeaders = self.db.global.currencyData.headers
    end
    
    -- Single aggregate pass drives empty-state + tree (avoids redundant chars x currencies pre-scan).
    local aggregated = AggregateCurrencies(self, characters, globalHeaders, currencySearchText, showZero)
    local hasAnyData = #aggregated.warbandTransferable > 0 or #aggregated.characterSpecific > 0

    if not hasAnyData then
        -- Check if this is a search result or general "no data" state
        if currencySearchText and currencySearchText ~= "" then
            -- Search-related empty state: use SearchResultsRenderer
            local height = SearchResultsRenderer:RenderEmptyState(self, parent, currencySearchText, "currency")
            SearchStateManager:UpdateResults("currency", 0)
            return height
        else
            -- General "no data" empty state: use standardized factory
            if ns.UI_ShowTabEmptyStateCard then
                local height = ns.UI_ShowTabEmptyStateCard(parent, "currency", 0, { fillParent = true })
                SearchStateManager:UpdateResults("currency", 0)
                return height
            end
            local yOffset = 100
            local _, height = CreateEmptyStateCard(parent, "currency", yOffset, { fillParent = true })
            SearchStateManager:UpdateResults("currency", 0)
            return yOffset + height
        end
    end
    
    -- Blizzard currency header tree: same stacking contract as ReputationUI category headers
    -- (wrap width = contentW âˆ’ BASE_INDENT, horizontal chain offset = BASE_INDENT per level).
    local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
    local Factory = ns.UI.Factory
    local COLLAPSE_H_CUR = SECTION_COLLAPSE_HEADER_HEIGHT
    local rowGap = (ns.UI_DataRowGap and ns.UI_DataRowGap()) or (GetLayout().dataRowGap) or 4
    local topChainTail = nil

    local function MeasureChildrenHeight(frame)
        if not frame then return 0.1 end
        local top = frame:GetTop()
        if not top then
            return math.max(0.1, frame._wnSectionFullH or frame:GetHeight() or 0.1)
        end
        local lowest = top
        local children = {frame:GetChildren()}
        for i = 1, #children do
            local child = children[i]
            if child and child:IsShown() then
                local bottom = child:GetBottom()
                if bottom and bottom < lowest then
                    lowest = bottom
                end
            end
        end
        return math.max(0.1, top - lowest)
    end

    local function SyncScrollMetrics()
        local totalH = MeasureChildrenHeight(parent)
        parent:SetHeight(math.max(1, totalH))
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        local scrollChild = parent and parent:GetParent()
        if not (mf and scrollChild and mf.scroll and scrollChild == mf.scrollChild) then
            return
        end
        local targetTabBodyH = 8 + totalH
        local targetScrollChildH = math.max(targetTabBodyH + 8, mf.scroll:GetHeight())
        scrollChild:SetHeight(targetScrollChildH)
        if Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(mf.scroll)
        end
        if Factory and Factory.UpdateHorizontalScrollBarVisibility then
            Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
        end
        if mf._virtualScrollUpdate then
            mf._virtualScrollUpdate()
        end
    end

    local function CreateWrap(parentFrame, wrapWidth)
        local wrap = Factory and Factory.CreateContainer and Factory:CreateContainer(parentFrame) or nil
        if not wrap then return nil end
        wrap:SetWidth(math.max(1, wrapWidth))
        wrap:SetHeight(COLLAPSE_H_CUR + 0.1)
        if wrap.SetClipsChildren then
            wrap:SetClipsChildren(true)
        end
        return wrap
    end

    local function CreateBody(wrap, bodyWidth)
        local body = Factory and Factory.CreateContainer and Factory:CreateContainer(wrap) or nil
        if not body then return nil end
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, -COLLAPSE_H_CUR)
        body:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, -COLLAPSE_H_CUR)
        body:SetWidth(math.max(1, bodyWidth))
        body:SetHeight(0.1)
        if body.SetClipsChildren then
            body:SetClipsChildren(true)
        end
        body:Hide()
        return body
    end

    local function FinalizeBodyHeight(body)
        if not body then return 0.1 end
        local fullH = MeasureChildrenHeight(body)
        body._wnSectionFullH = fullH
        return fullH
    end

    local function ChainTopFrame(frame, gap)
        if not frame then return end
        ChainSectionFrameBelow(parent, frame, topChainTail, 0, gap, topChainTail and nil or 0)
        topChainTail = frame
    end

    local function BuildCurrencyCategoryTree(rootCtx, headerDataList, keyPrefix, defaultExpanded, bodyFrame, contentW, makeDisplayData)
        if not bodyFrame then return end

        --- Walk parent category bodies/wraps up to the major section so sibling headers
        --- reflow when a nested row (e.g. Season 1) collapses (same idea as ReputationUI nested sections).
        local function ReflowAncestors(ctx)
            if not ctx or not ctx.body or not ctx.wrap then return end
            local bodyH = FinalizeBodyHeight(ctx.body)
            if ctx.body:IsShown() then
                ctx.body:SetHeight(math.max(0.1, bodyH))
                ctx.wrap:SetHeight(COLLAPSE_H_CUR + ctx.body:GetHeight())
            else
                ctx.wrap:SetHeight(COLLAPSE_H_CUR + 0.1)
            end
            ReflowAncestors(ctx.parentCtx)
        end

        local function AppendRows(targetBody, rows, rowWidth)
            if not targetBody or not rows then return nil end
            local localTail = nil
            for i = 1, #rows do
                local curr = rows[i]
                globalRowIdx = globalRowIdx + 1
                local row = AcquireCurrencyRow(targetBody, rowWidth, ROW_HEIGHT)
                if localTail then
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", localTail, "BOTTOMLEFT", 0, -rowGap)
                else
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", targetBody, "TOPLEFT", 0, 0)
                end
                local displayData = makeDisplayData(curr)
                PopulateCurrencyRowFrame(row, displayData, curr.id, globalRowIdx, rowWidth, true)
                row:Show()
                localTail = row
            end
            return localTail
        end

        --- Child category wraps must chain below direct currency rows in the same body;
        --- otherwise the first child header uses TOP anchor and overlaps rows (Hide/Show Empty).
        local function RenderTree(headers, renderBody, contentW, chainAfter, parentCtx)
            if not headers then return end
            local localTail = chainAfter
            for i = 1, #headers do
                local headerData = headers[i]
                local totalCount = headerData and headerData.count or 0
                if totalCount > 0 then
                    local innerW = math.max(1, contentW - BASE_INDENT)
                    local wrap = CreateWrap(renderBody, innerW)
                    if wrap then
                        ChainSectionFrameBelow(renderBody, wrap, localTail, BASE_INDENT, localTail and SECTION_SPACING or nil, localTail and nil or SECTION_SPACING)
                        localTail = wrap

                        local headerKey = keyPrefix .. (headerData.name or tostring(i))
                        local expandedNow = IsExpanded(headerKey, defaultExpanded)
                        local headerBody = CreateBody(wrap, innerW)
                        local nodeCtx = { body = headerBody, wrap = wrap, parentCtx = parentCtx }
                        local GetCurrencyHeaderIcon = ns.UI_GetCurrencyHeaderIcon
                        local headerIcon = GetCurrencyHeaderIcon and GetCurrencyHeaderIcon(headerData.name) or nil

                        local header = CreateCollapsibleHeader(
                            wrap,
                            (headerData.name or "") .. " (" .. FormatNumber(totalCount) .. ")",
                            headerKey,
                            expandedNow,
                            function() end,
                            headerIcon,
                            nil,
                            nil,
                            nil,
                            {
                                animatedContent = function() return headerBody end,
                                persistToggle = function(exp)
                                    PersistExpand(headerKey, exp)
                                end,
                                -- Resize wrap + reflow ancestors; SyncScrollMetrics deferred to sectionOnComplete.
                                sectionOnUpdate = function(drawH)
                                    wrap:SetHeight(COLLAPSE_H_CUR + math.max(0.1, drawH or 0))
                                    ReflowAncestors(nodeCtx.parentCtx)
                                end,
                                sectionOnComplete = function(exp)
                                    if not exp then
                                        headerBody:Hide()
                                        headerBody:SetHeight(0.1)
                                    end
                                    headerBody._wnSectionFullH = FinalizeBodyHeight(headerBody)
                                    wrap:SetHeight(COLLAPSE_H_CUR + (exp and headerBody._wnSectionFullH or 0.1))
                                    ReflowAncestors(nodeCtx.parentCtx)
                                    SyncScrollMetrics()
                                end,
                            }
                        )
                        header:ClearAllPoints()
                        header:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
                        header:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, 0)
                        header:SetHeight(COLLAPSE_H_CUR)

                        local rowTail = AppendRows(headerBody, headerData.currencies or {}, innerW)
                        local childHeaders = headerData.children or {}
                        if #childHeaders > 0 then
                            RenderTree(childHeaders, headerBody, innerW, rowTail, nodeCtx)
                        end

                        local fullH = FinalizeBodyHeight(headerBody)
                        if expandedNow then
                            headerBody:Show()
                            headerBody:SetHeight(math.max(0.1, fullH))
                            wrap:SetHeight(COLLAPSE_H_CUR + headerBody:GetHeight())
                        else
                            headerBody:Hide()
                            headerBody:SetHeight(0.1)
                            wrap:SetHeight(COLLAPSE_H_CUR + 0.1)
                        end
                    end
                end
            end
        end

        RenderTree(headerDataList, bodyFrame, contentW, nil, rootCtx)
    end

    -- Section 1: Warband Transferable
    if #aggregated.warbandTransferable > 0 then
        local sectionKey = "currency-warband"
        local sectionExpanded = IsExpanded(sectionKey, false)
        local sectionWrap = CreateWrap(parent, width)
        local sectionBody = CreateBody(sectionWrap, width)
        if sectionWrap and sectionBody then
            ChainTopFrame(sectionWrap, topChainTail and SECTION_SPACING or nil)
            local sectionHeader, _, warbandIcon = CreateCollapsibleHeader(
                sectionWrap,
                (ns.L and ns.L["CURRENCY_WARBAND_TRANSFERABLE"]) or "All Warband Transferable",
                sectionKey,
                sectionExpanded,
                function() end,
                "dummy",
                nil,
                nil,
                nil,
                {
                    animatedContent = function() return sectionBody end,
                    persistToggle = function(exp)
                        PersistExpand(sectionKey, exp)
                    end,
                    sectionOnUpdate = function(drawH)
                        sectionWrap:SetHeight(COLLAPSE_H_CUR + math.max(0.1, drawH or 0))
                        SyncScrollMetrics()
                    end,
                    sectionOnComplete = function(exp)
                        if not exp then
                            sectionBody:Hide()
                            sectionBody:SetHeight(0.1)
                        end
                        sectionBody._wnSectionFullH = FinalizeBodyHeight(sectionBody)
                        sectionWrap:SetHeight(COLLAPSE_H_CUR + (exp and sectionBody._wnSectionFullH or 0.1))
                        SyncScrollMetrics()
                    end,
                }
            )
            sectionHeader:ClearAllPoints()
            sectionHeader:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
            sectionHeader:SetPoint("TOPRIGHT", sectionWrap, "TOPRIGHT", 0, 0)
            sectionHeader:SetHeight(COLLAPSE_H_CUR)
            if warbandIcon then
                warbandIcon:SetTexture(nil)
                warbandIcon:SetAtlas("warbands-icon")
                warbandIcon:SetSize(27, 36)
            end

            local roots = {}
            for i = 1, #aggregated.warbandTransferable do
                local node = aggregated.warbandTransferable[i]
                if (node.depth or 0) == 0 then
                    roots[#roots + 1] = node
                end
            end
            local sectionCtx = { body = sectionBody, wrap = sectionWrap }
            BuildCurrencyCategoryTree(sectionCtx, roots, "all-warband-", false, sectionBody, width, function(curr)
                local displayData = {}
                for k, v in pairs(curr.data or {}) do displayData[k] = v end
                local sessionChar = curr.sessionCharacter or {}
                local classFile = sessionChar.classFile
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or { r = 1, g = 1, b = 1 }
                local sessionRealm = ns.Utilities and ns.Utilities.FormatRealmName
                    and ns.Utilities:FormatRealmName(sessionChar.realm) or (sessionChar.realm or "")
                local charName = format("|c%s%s  -  %s|r",
                    format("%02x%02x%02x%02x", 255, classColor.r * 255, classColor.g * 255, classColor.b * 255),
                    sessionChar.name or "",
                    sessionRealm)
                displayData.characterName = FormatParenBadge(charName)
                displayData.quantity = curr.sessionAmount or curr.quantity or 0
                displayData.totalQuantity = curr.totalQuantity or 0
                displayData.warbandAmountSplit = true
                displayData.viewCharKey = curr.sessionCharacterKey or currentCharKey
                return displayData
            end)

            local sectionFullH = FinalizeBodyHeight(sectionBody)
            sectionBody._wnSectionFullH = sectionFullH
            if sectionExpanded then
                sectionBody:Show()
                sectionBody:SetHeight(math.max(0.1, sectionFullH))
                sectionWrap:SetHeight(COLLAPSE_H_CUR + sectionBody:GetHeight())
            else
                sectionBody:Hide()
                sectionBody:SetHeight(0.1)
                sectionWrap:SetHeight(COLLAPSE_H_CUR + 0.1)
            end
        end
    end

    -- Section 2: Character-Specific
    if #aggregated.characterSpecific > 0 then
        local sectionKey = "currency-char-specific"
        local sectionExpanded = IsExpanded(sectionKey, false)
        local sectionWrap = CreateWrap(parent, width)
        local sectionBody = CreateBody(sectionWrap, width)
        if sectionWrap and sectionBody then
            ChainTopFrame(sectionWrap, topChainTail and SECTION_SPACING or nil)
            local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon
            local sectionHeader = CreateCollapsibleHeader(
                sectionWrap,
                (ns.L and ns.L["CURRENCY_CHARACTER_SPECIFIC"]) or "Character-Specific Currencies",
                sectionKey,
                sectionExpanded,
                function() end,
                GetCharacterSpecificIcon and GetCharacterSpecificIcon() or nil,
                true,
                nil,
                nil,
                {
                    animatedContent = function() return sectionBody end,
                    persistToggle = function(exp)
                        PersistExpand(sectionKey, exp)
                    end,
                    sectionOnUpdate = function(drawH)
                        sectionWrap:SetHeight(COLLAPSE_H_CUR + math.max(0.1, drawH or 0))
                        SyncScrollMetrics()
                    end,
                    sectionOnComplete = function(exp)
                        if not exp then
                            sectionBody:Hide()
                            sectionBody:SetHeight(0.1)
                        end
                        sectionBody._wnSectionFullH = FinalizeBodyHeight(sectionBody)
                        sectionWrap:SetHeight(COLLAPSE_H_CUR + (exp and sectionBody._wnSectionFullH or 0.1))
                        SyncScrollMetrics()
                    end,
                }
            )
            sectionHeader:ClearAllPoints()
            sectionHeader:SetPoint("TOPLEFT", sectionWrap, "TOPLEFT", 0, 0)
            sectionHeader:SetPoint("TOPRIGHT", sectionWrap, "TOPRIGHT", 0, 0)
            sectionHeader:SetHeight(COLLAPSE_H_CUR)

            local roots = {}
            for i = 1, #aggregated.characterSpecific do
                local node = aggregated.characterSpecific[i]
                if (node.depth or 0) == 0 then
                    roots[#roots + 1] = node
                end
            end
            local sectionCtx = { body = sectionBody, wrap = sectionWrap }
            BuildCurrencyCategoryTree(sectionCtx, roots, "all-char-", false, sectionBody, width, function(curr)
                local displayData = {}
                for k, v in pairs(curr.data or {}) do displayData[k] = v end
                local bestCharacter = curr.bestCharacter or {}
                local classFile = bestCharacter.classFile
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] or { r = 1, g = 1, b = 1 }
                local bestRealm = ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(bestCharacter.realm) or (bestCharacter.realm or "")
                local charName = format("|c%s%s  -  %s|r",
                    format("%02x%02x%02x%02x", 255, classColor.r * 255, classColor.g * 255, classColor.b * 255),
                    bestCharacter.name or "",
                    bestRealm)
                displayData.characterName = FormatParenBadge(charName)
                displayData.quantity = curr.quantity
                displayData.viewCharKey = curr.bestCharacterKey
                return displayData
            end)

            local sectionFullH = FinalizeBodyHeight(sectionBody)
            sectionBody._wnSectionFullH = sectionFullH
            if sectionExpanded then
                sectionBody:Show()
                sectionBody:SetHeight(math.max(0.1, sectionFullH))
                sectionWrap:SetHeight(COLLAPSE_H_CUR + sectionBody:GetHeight())
            else
                sectionBody:Hide()
                sectionBody:SetHeight(0.1)
                sectionWrap:SetHeight(COLLAPSE_H_CUR + 0.1)
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
            if ns.UI_ShowTabEmptyStateCard then
                local height = ns.UI_ShowTabEmptyStateCard(parent, "currency", 0, { fillParent = true })
                SearchStateManager:UpdateResults("currency", 0)
                return height
            end
            local yOffset = 100
            local _, height = CreateEmptyStateCard(parent, "currency", yOffset, { fillParent = true })
            SearchStateManager:UpdateResults("currency", 0)
            return yOffset + height
        end
    end
    
    local noticeFrame = CreateNoticeFrame(
        parent,
        (ns.L and ns.L["CURRENCY_TRANSFER_NOTICE_TITLE"]) or "Currency Transfer Limitation",
        (ns.L and ns.L["CURRENCY_TRANSFER_NOTICE_DESC"]) or "Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies.",
        "alert",
        width - 20,
        60
    )
    ChainTopFrame(noticeFrame, SECTION_SPACING * 2)
    
    -- Update SearchStateManager with result count (leaf rows in rendered header tree).
    local totalCurrencies = CountAggregatedCurrencyLeaves(aggregated.warbandTransferable)
        + CountAggregatedCurrencyLeaves(aggregated.characterSpecific)
    SearchStateManager:UpdateResults("currency", totalCurrencies)

    SyncScrollMetrics()
    local finalHeight = MeasureChildrenHeight(parent) + (GetLayout().minBottomSpacing or 0)
    parent:SetHeight(math.max(1, finalHeight))
    return finalHeight
end

--- Redraw Currency scroll results only. Skips PopulateContent â€” matches Items/Storage partial redraw.
local function ApplyCurrencyResultsHeight(mainFrame, scrollChild, resultsContainer, listHeight, _animate, _fromResultsH, _fromScrollChildH)
    if not mainFrame or not scrollChild or not resultsContainer then return end
    local targetResultsH = math.max(listHeight or 1, 1)
    local CONTENT_BOTTOM_PADDING = 8
    local targetTabBodyH = 8 + (listHeight or 0)
    local targetScrollChildH = math.max(targetTabBodyH + CONTENT_BOTTOM_PADDING, mainFrame.scroll:GetHeight())

    local Factory = ns.UI.Factory
    resultsContainer:SetHeight(targetResultsH)
    scrollChild:SetHeight(targetScrollChildH)
    if Factory and Factory.UpdateScrollBarVisibility then
        Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    if Factory and Factory.UpdateHorizontalScrollBarVisibility then
        Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
    end
end

function WarbandNexus:RedrawCurrencyResultsOnly(animateHeight)
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "currency" then return end
    local scrollChild = mf.scrollChild
    if not scrollChild then return end
    local rc = scrollChild.resultsContainer
    if not rc or rc:GetParent() ~= scrollChild then return end
    local width = (ns.UI_ResolveResultsContainerPaintWidth and ns.UI_ResolveResultsContainerPaintWidth(mf, rc))
        or math.max(1, (scrollChild:GetWidth() or 0) - (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin() or 12) * 2)
    if width < 1 then return end

    if SearchResultsRenderer and SearchResultsRenderer.PrepareContainer then
        SearchResultsRenderer:PrepareContainer(rc)
    end

    local oldResultsH = rc:GetHeight() or 1
    local oldScrollChildH = scrollChild:GetHeight() or mf.scroll:GetHeight()
    local listHeight = self:DrawCurrencyList(rc, width)
    ApplyCurrencyResultsHeight(mf, scrollChild, rc, listHeight, animateHeight == true, oldResultsH, oldScrollChildH)

    local sc = mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
end

-- CURRENCY TAB WRAPPER (Fixes focus issue)

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
    
    -- Clear all old frames (REPUTATION STYLE) - Keep only persistent elements
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
    
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local contentWidth = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local bodyWidth = (metrics and metrics.bodyWidth)
        or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, contentWidth - (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin() or 12) * 2)
    local fixedHeader = mf and mf.fixedHeader
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local headerYOffset = (chrome and chrome.yOffset) or (metrics and metrics.topMargin) or 0
    
    -- Check if module is enabled (early check)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.currencies ~= false

    local headerParent = fixedHeader or parent
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    local COLORS = ns.UI_COLORS
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local subtitle = (ns.L and ns.L["CURRENCY_SUBTITLE"]) or "Track all currencies across your characters"
    local shiftHintText = (ns.L and ns.L["SHIFT_HINT_SEASON_PROGRESS"]) or "Hold Shift for season progress"
    subtitle = subtitle .. "  " .. ThemeTextHex("Dim") .. "\194\183|r  " .. ThemeTextHex("Muted") .. shiftHintText .. "|r"
    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local currencyToolbarReserve = (ns.UI_ComputeTitleToolbarReserve and ns.UI_ComputeTitleToolbarReserve({
        tm.actionW or 100,
    })) or 118
    local titleCard, _, _, _, _ = ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "currency",
        titleText = "|cff" .. hexColor .. ((ns.L and ns.L["CURRENCY_TITLE"]) or "Currency Tracker") .. "|r",
        subtitleText = subtitle,
        textRightInset = currencyToolbarReserve,
    })
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    end
    
    local showZeroBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
        preset = "action",
        autoWidth = true,
        text = showZero and ((ns.L and ns.L["CURRENCY_HIDE_EMPTY"]) or "Hide Empty") or ((ns.L and ns.L["CURRENCY_SHOW_EMPTY"]) or "Show Empty"),
    })
    if showZeroBtn then
        ns.UI_AnchorTitleToolbarControlRight(titleCard, showZeroBtn)
        if not moduleEnabled then showZeroBtn:Hide() end
        showZeroBtn:SetScript("OnClick", function(btn)
            showZero = not showZero
            self.db.profile.currencyShowZero = showZero
            if btn._toolbarLabel then
                btn._toolbarLabel:SetText(showZero and ((ns.L and ns.L["CURRENCY_HIDE_EMPTY"]) or "Hide Empty") or ((ns.L and ns.L["CURRENCY_SHOW_EMPTY"]) or "Show Empty"))
            end
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, {
                tab = "currency",
                skipCooldown = true,
                instantPopulate = true,
            })
        end)
    end

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    titleCard:Show()
    
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
    end
    
    -- If module is disabled, show disabled state card (in scroll area)
    if not moduleEnabled then
        if ns.UI_HideTitleCardExpandCollapseControls then
            ns.UI_HideTitleCardExpandCollapseControls(parent)
        end
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, 8, (ns.L and ns.L["CURRENCY_DISABLED_TITLE"]) or "Currency Tracking")
        return 8 + cardHeight
    end
    
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
    
    local searchBox = CreateSearchBox(headerParent, contentWidth, (ns.L and ns.L["CURRENCY_SEARCH"]) or "Search currencies...", function(text)
        SearchStateManager:SetSearchQuery("currency", text)
        if parent.resultsContainer then
            SearchResultsRenderer:PrepareContainer(parent.resultsContainer)
            self:RedrawCurrencyResultsOnly(false)
        end
    end, nil, currencySearchText, "currency")
    
    searchBox:SetPoint("TOPLEFT", SIDE_MARGIN, -headerYOffset)
    searchBox:SetPoint("TOPRIGHT", -SIDE_MARGIN, -headerYOffset)
    
    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
    headerYOffset = headerYOffset + searchH + GetLayout().afterElement
    
    -- Set fixedHeader height so scroll area starts below it
    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif fixedHeader then
        fixedHeader:SetHeight(headerYOffset)
    end
    
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
    container:SetWidth(bodyWidth)
    container:SetHeight(1)
    container:Show()
    
    local listHeight = self:DrawCurrencyList(container, bodyWidth)
    ApplyCurrencyResultsHeight(WarbandNexus.UI and WarbandNexus.UI.mainFrame, parent, container, listHeight, false)
    
    return 8 + listHeight
end

if ns.UI_RegisterTabViewportResize then
    ns.UI_RegisterTabViewportResize("currency", {
        mode = ns.UI_VIEWPORT_RESIZE_MODE and ns.UI_VIEWPORT_RESIZE_MODE.RESULTS_CONTAINER,
        tabKey = "currency",
        freezeWhileResizing = true,
        results = { bottomInset = 8 },
    })
end
