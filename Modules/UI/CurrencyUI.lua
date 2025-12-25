--[[
    Warband Nexus - Currency Tab
    Display all currencies across characters with Blizzard API headers
    
    EXACT StorageUI pattern:
    - Character → Expansion → Category → Currency rows
    - Season 3 is a CATEGORY under "The War Within" expansion
    - All spacing, fonts, colors match StorageUI
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local FormatGold = ns.UI_FormatGold
local DrawEmptyState = ns.UI_DrawEmptyState
local function GetCOLORS()
    return ns.UI_COLORS
end

-- Performance: Local function references
local format = string.format
local floor = math.floor
local ipairs = ipairs
local pairs = pairs
local next = next

-- Import shared UI constants (EXACT StorageUI spacing)
local UI_LAYOUT = ns.UI_LAYOUT
local ROW_HEIGHT = UI_LAYOUT.ROW_HEIGHT
local ROW_SPACING = UI_LAYOUT.ROW_SPACING
local HEADER_SPACING = UI_LAYOUT.HEADER_SPACING
local SECTION_SPACING = UI_LAYOUT.SECTION_SPACING

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
local function CreateCurrencyRow(parent, currency, currencyID, rowIndex, indent, width, yOffset)
    -- Create new row (NO POOLING - currency rows are dynamic and cause render issues with pooling)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(width - indent, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 10 + indent, -yOffset)
    row:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    
    -- EXACT alternating row colors (StorageUI formula)
    row:SetBackdropColor(rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.09 or 0.06, 1)
    
    local hasQuantity = (currency.quantity or 0) > 0
    
    -- Icon
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 15, 0)
    if currency.iconFileID then
        icon:SetTexture(currency.iconFileID)
    else
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    if not hasQuantity then
        icon:SetAlpha(0.4)
    end
    
    -- Name
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("LEFT", 43, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetWidth(width - indent - 200)
    nameText:SetText(currency.name or "Unknown Currency")
    if hasQuantity then
        nameText:SetTextColor(1, 1, 1)
    else
        nameText:SetTextColor(0.5, 0.5, 0.5)
    end
    
    -- Amount
    local amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amountText:SetPoint("RIGHT", -10, 0)
    amountText:SetWidth(150)
    amountText:SetJustifyH("RIGHT")
    amountText:SetText(FormatCurrencyAmount(currency.quantity or 0, currency.maxQuantity or 0))
    if not hasQuantity then
        amountText:SetTextColor(0.5, 0.5, 0.5)
    end
    
    -- EXACT StorageUI hover effect
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.20, 1)
        
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if currencyID and C_CurrencyInfo then
            GameTooltip:SetCurrencyByID(currencyID)
        else
            GameTooltip:SetText(currency.name or "Currency", 1, 1, 1)
            if currency.maxQuantity and currency.maxQuantity > 0 then
                GameTooltip:AddLine(format("Maximum: %d", currency.maxQuantity), 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:Show()
    end)
    
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.07 or 0.05, rowIndex % 2 == 0 and 0.09 or 0.06, 1)
        GameTooltip:Hide()
    end)
    
    return yOffset + ROW_SPACING
end

--============================================================================
-- MAIN DRAW FUNCTION
--============================================================================

function WarbandNexus:DrawCurrencyTab(parent)
    -- Clear all old frames (currency rows are NOT pooled)
    for _, child in pairs({parent:GetChildren()}) do
        if child:GetObjectType() ~= "Frame" then  -- Skip non-frame children like FontStrings
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
        end
    end
    
    local yOffset = 8
    local width = parent:GetWidth() - 20
    local indent = 20
    
    -- Get search text
    local currencySearchText = (ns.currencySearchText or ""):lower()
    
    -- Get all characters
    local characters = self:GetAllCharacters()
    if not characters or #characters == 0 then
        DrawEmptyState(parent, "No character data available", yOffset)
        return yOffset + 50
    end
    
    -- Get filter mode and zero toggle
    local filterMode = self.db.profile.currencyFilterMode or "nonfiltered"
    local showZero = self.db.profile.currencyShowZero
    if showZero == nil then showZero = true end
    
    -- Expanded state
    local expanded = self.db.profile.currencyExpanded or {}
    
    -- Get current online character
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    local currentCharKey = currentPlayerName .. "-" .. currentRealm
    
    -- Helper functions for expand/collapse
    local function IsExpanded(key, default)
        if expanded[key] == nil then
            return default or false
        end
        return expanded[key]
    end
    
    local function ToggleExpand(key, isExpanded)
        if not self.db.profile.currencyExpanded then
            self.db.profile.currencyExpanded = {}
        end
        self.db.profile.currencyExpanded[key] = isExpanded
        self:RefreshUI()
    end
    
    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", 10, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
    local titleIcon = titleCard:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(40, 40)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    
    local titleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, 5)
    -- Dynamic theme color for title
    local COLORS = GetCOLORS()
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    titleText:SetText("|cff" .. hexColor .. "Currency Tracker|r")
    
    local subtitleText = titleCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleIcon, "RIGHT", 12, -12)
    subtitleText:SetTextColor(0.6, 0.6, 0.6)
    subtitleText:SetText("Track all currencies across your characters")
    
    -- Filter Mode Toggle Button
    local toggleBtn = CreateFrame("Button", nil, titleCard, "UIPanelButtonTemplate")
    toggleBtn:SetSize(120, 25)
    toggleBtn:SetPoint("RIGHT", -130, 0)
    toggleBtn:SetText(filterMode == "filtered" and "Filtered" or "Non-Filtered")
    toggleBtn:SetScript("OnClick", function(self)
        if filterMode == "filtered" then
            filterMode = "nonfiltered"
            WarbandNexus.db.profile.currencyFilterMode = "nonfiltered"
            self:SetText("Non-Filtered")
        else
            filterMode = "filtered"
            WarbandNexus.db.profile.currencyFilterMode = "filtered"
            self:SetText("Filtered")
        end
        WarbandNexus:RefreshUI()
    end)
    
    -- Show 0 Qty Toggle
    local zeroBtn = CreateFrame("Button", nil, titleCard, "UIPanelButtonTemplate")
    zeroBtn:SetSize(100, 25)
    zeroBtn:SetPoint("RIGHT", -10, 0)
    zeroBtn:SetText(showZero and "Hide 0 Qty" or "Show 0 Qty")
    zeroBtn:SetScript("OnClick", function(self)
        showZero = not showZero
        WarbandNexus.db.profile.currencyShowZero = showZero
        self:SetText(showZero and "Hide 0 Qty" or "Show 0 Qty")
        WarbandNexus:RefreshUI()
    end)
    
    yOffset = yOffset + 78
    
    -- ===== RENDER CHARACTERS =====
    local hasAnyData = false
    local charactersWithCurrencies = {}
    
    -- Collect characters with currencies
    for _, char in ipairs(characters) do
        if char.currencies and next(char.currencies) then
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
            local isOnline = (charKey == currentCharKey)
            
            -- Filter currencies
            local matchingCurrencies = {}
            for currencyID, currency in pairs(char.currencies) do
                local passesZeroFilter = showZero or ((currency.quantity or 0) > 0)
                
                if not currency.isHidden 
                   and passesZeroFilter
                   and CurrencyMatchesSearch(currency, currencySearchText) then
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
        DrawEmptyState(parent, 
            currencySearchText ~= "" and "No currencies match your search" or "No currencies found",
            yOffset)
        return yOffset + 100
    end
    
    -- Draw each character
    for _, charData in ipairs(charactersWithCurrencies) do
        local char = charData.char
        local charKey = charData.key
        local currencies = charData.currencies
        
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
            format("%s%s - |cff888888%d currencies|r", charName, onlineBadge, #currencies),
            charKey_expand,
            charExpanded,
            function(isExpanded) ToggleExpand(charKey_expand, isExpanded) end,
            classIconPath  -- Pass class icon path
        )
        
        -- If we have class icon coordinates, apply them
        if classIcon and coords then
            classIcon:SetTexCoord(unpack(coords))
        end
        
        charHeader:SetPoint("TOPLEFT", 10, -yOffset)
        charHeader:SetWidth(width)
        charHeader:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
        local COLORS = GetCOLORS()
        local borderColor = COLORS.accent
        charHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
        
        yOffset = yOffset + HEADER_SPACING
        
        if charExpanded then
            local charIndent = 20
            
            if filterMode == "nonfiltered" then
                -- ===== NON-FILTERED: Use Blizzard's Currency Headers =====
                local headers = char.currencyHeaders or {}
                
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
                    for _, currencyID in ipairs(warWithinHeader.currencies) do
                        for _, curr in ipairs(currencies) do
                            if curr.id == currencyID then
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
                        for _, currencyID in ipairs(season3Header.currencies) do
                            for _, curr in ipairs(currencies) do
                                if curr.id == currencyID then
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
                        warHeader:SetPoint("TOPLEFT", 10 + charIndent, -yOffset)
                        warHeader:SetWidth(width - charIndent)
                        warHeader:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
                        local COLORS = GetCOLORS()
                        local borderColor = COLORS.accent
                        warHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                        
                        yOffset = yOffset + HEADER_SPACING
                        
                        if warExpanded then
                            local warIndent = charIndent + 20
                            
                            -- First: War Within currencies (non-Season 3)
                            if #warWithinCurrencies > 0 then
                                local rowIdx = 0
                                for _, curr in ipairs(warWithinCurrencies) do
                                    rowIdx = rowIdx + 1
                                    yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, warIndent, width, yOffset)
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
                                s3Header:SetPoint("TOPLEFT", 10 + warIndent, -yOffset)
                                s3Header:SetWidth(width - warIndent)
                                s3Header:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
                                local COLORS = GetCOLORS()
                                local borderColor = COLORS.accent
                                s3Header:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                                
                                yOffset = yOffset + HEADER_SPACING
                                
                                if s3Expanded then
                                    local rowIdx = 0
                                    for _, curr in ipairs(season3Currencies) do
                                        rowIdx = rowIdx + 1
                                        yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, warIndent, width, yOffset)
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Then: All other Blizzard headers (in order)
                for _, headerData in ipairs(processedHeaders) do
                    local headerCurrencies = {}
                    for _, currencyID in ipairs(headerData.currencies) do
                        for _, curr in ipairs(currencies) do
                            if curr.id == currencyID then
                                -- Skip Timerunning currencies
                                if not curr.data.name:lower():find("infinite knowledge") then
                                    table.insert(headerCurrencies, curr)
                                end
                                break
                            end
                        end
                    end
                    
                    if #headerCurrencies > 0 then
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
                        header:SetPoint("TOPLEFT", 10 + charIndent, -yOffset)
                        header:SetWidth(width - charIndent)
                        header:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
                        local COLORS = GetCOLORS()
                        local borderColor = COLORS.accent
                        header:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                        
                        yOffset = yOffset + HEADER_SPACING
                        
                        if headerExpanded then
                            local rowIdx = 0
                            for _, curr in ipairs(headerCurrencies) do
                                rowIdx = rowIdx + 1
                                yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, charIndent, width, yOffset)
                            end
                        end
                    end
                end
            else
                -- ===== FILTERED: Expansion → Season → Category (StorageUI pattern) =====
                -- Group by expansion
                local byExpansion = {}
                for _, curr in ipairs(currencies) do
                    local expansion = curr.data.expansion or "Other"
                    if not byExpansion[expansion] then
                        byExpansion[expansion] = {}
                    end
                    table.insert(byExpansion[expansion], curr)
                end
                
                local expansionOrder = {"The War Within", "Dragonflight", "Shadowlands", "Battle for Azeroth", "Legion", "Warlords of Draenor", "Mists of Pandaria", "Cataclysm", "Wrath of the Lich King", "The Burning Crusade", "Account-Wide", "Other"}
                local expansionIcons = {
                    ["The War Within"] = "Interface\\Icons\\INV_Misc_Gem_Diamond_01",
                    ["Dragonflight"] = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze",
                    ["Shadowlands"] = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
                    ["Battle for Azeroth"] = "Interface\\Icons\\INV_Sword_39",
                    ["Legion"] = "Interface\\Icons\\Spell_Shadow_Twilight",
                    ["Warlords of Draenor"] = "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc",
                    ["Mists of Pandaria"] = "Interface\\Icons\\Achievement_Character_Pandaren_Female",
                    ["Cataclysm"] = "Interface\\Icons\\Spell_Fire_Flameshock",
                    ["Wrath of the Lich King"] = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
                    ["The Burning Crusade"] = "Interface\\Icons\\Spell_Fire_FelFlameStrike",
                    ["Account-Wide"] = "Interface\\Icons\\INV_Misc_Coin_02",
                    ["Other"] = "Interface\\Icons\\INV_Misc_QuestionMark",
                }
                
                -- Process each expansion (StorageUI pattern)
                for _, expansion in ipairs(expansionOrder) do
                    if byExpansion[expansion] then
                        local expKey = charKey .. "-exp-" .. expansion
                        local expExpanded = IsExpanded(expKey, true)
                        
                        if currencySearchText ~= "" then
                            expExpanded = true
                        end
                        
                        -- Expansion header (level 1, like StorageUI's Warband Bank)
                        local expHeader, expBtn = CreateCollapsibleHeader(
                            parent,
                            expansion .. " (" .. #byExpansion[expansion] .. ")",
                            expKey,
                            expExpanded,
                            function(isExpanded) ToggleExpand(expKey, isExpanded) end,
                            expansionIcons[expansion]
                        )
                        expHeader:SetPoint("TOPLEFT", 10 + charIndent, -yOffset)
                        expHeader:SetWidth(width - charIndent)
                        expHeader:SetBackdropColor(0.10, 0.10, 0.12, 0.9)
                        local COLORS = GetCOLORS()
                        local borderColor = COLORS.accent
                        expHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                        
                        yOffset = yOffset + HEADER_SPACING
                        
                        if expExpanded then
                            local expIndent = charIndent + 20
                            
                            -- For "The War Within", add Season 3 sub-header (StorageUI pattern)
                            if expansion == "The War Within" then
                                -- Group currencies by season
                                local season3Currencies = {}
                                local otherCurrencies = {}
                                
                                for _, curr in ipairs(byExpansion[expansion]) do
                                    -- Check if currency is marked as Season 3
                                    if curr.data.season == "Season 3" then
                                        table.insert(season3Currencies, curr)
                                    else
                                        table.insert(otherCurrencies, curr)
                                    end
                                end
                                
                                -- First: Other War Within currencies (not in Season 3)
                                if #otherCurrencies > 0 then
                                    local byCategory = {}
                                    for _, curr in ipairs(otherCurrencies) do
                                        local category = curr.data.category or "Other"
                                        if not byCategory[category] then
                                            byCategory[category] = {}
                                        end
                                        table.insert(byCategory[category], curr)
                                    end
                                    
                                    local categoryOrder = {"Supplies", "Currency", "Profession", "PvP", "Event", "Other"}
                                    
                                    for _, category in ipairs(categoryOrder) do
                                        if byCategory[category] then
                                            local catKey = expKey .. "-cat-" .. category
                                            local catExpanded = IsExpanded(catKey, true)
                                            
                                            if currencySearchText ~= "" then
                                                catExpanded = true
                                            end
                                            
                                            -- Category header (level 2, like StorageUI's type category)
                                            local catHeader, catBtn = CreateCollapsibleHeader(
                                                parent,
                                                category .. " (" .. #byCategory[category] .. ")",
                                                catKey,
                                                catExpanded,
                                                function(isExpanded) ToggleExpand(catKey, isExpanded) end
                                            )
                                            catHeader:SetPoint("TOPLEFT", 10 + expIndent, -yOffset)
                                            catHeader:SetWidth(width - expIndent)
                                            catHeader:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
                                            local COLORS = GetCOLORS()
                                            local borderColor = COLORS.accent
                                            catHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                                            
                                            yOffset = yOffset + HEADER_SPACING
                                            
                                            if catExpanded then
                                                local rowIdx = 0
                                                for _, curr in ipairs(byCategory[category]) do
                                                    rowIdx = rowIdx + 1
                                                    yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, expIndent, width, yOffset)
                                                end
                                            end
                                        end
                                    end
                                end
                                
                                -- Then: Season 3 header (level 2, at the bottom)
                                if #season3Currencies > 0 then
                                    local seasonKey = expKey .. "-season-3"
                                    local seasonExpanded = IsExpanded(seasonKey, true)
                                    
                                    if currencySearchText ~= "" then
                                        seasonExpanded = true
                                    end
                                    
                                    local seasonHeader, seasonBtn = CreateCollapsibleHeader(
                                        parent,
                                        "Season 3 (" .. #season3Currencies .. ")",
                                        seasonKey,
                                        seasonExpanded,
                                        function(isExpanded) ToggleExpand(seasonKey, isExpanded) end
                                    )
                                    seasonHeader:SetPoint("TOPLEFT", 10 + expIndent, -yOffset)
                                    seasonHeader:SetWidth(width - expIndent)
                                    seasonHeader:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
                                    local COLORS = GetCOLORS()
                                    local borderColor = COLORS.accent
                                    seasonHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                                    
                                    yOffset = yOffset + HEADER_SPACING
                                    
                                    if seasonExpanded then
                                        local seasonIndent = expIndent + 20
                                        
                                        -- Group Season 3 currencies by category (level 3)
                                        local byCategory = {}
                                        for _, curr in ipairs(season3Currencies) do
                                            local category = curr.data.category or "Other"
                                            if not byCategory[category] then
                                                byCategory[category] = {}
                                            end
                                            table.insert(byCategory[category], curr)
                                        end
                                        
                                        local categoryOrder = {"Crest", "Upgrade", "Other"}
                                        
                                        for _, category in ipairs(categoryOrder) do
                                            if byCategory[category] then
                                                local catKey = seasonKey .. "-cat-" .. category
                                                local catExpanded = IsExpanded(catKey, true)
                                                
                                                if currencySearchText ~= "" then
                                                    catExpanded = true
                                                end
                                                
                                                -- Category header (level 3, like StorageUI's double-indented type)
                                                local catHeader, catBtn = CreateCollapsibleHeader(
                                                    parent,
                                                    category .. " (" .. #byCategory[category] .. ")",
                                                    catKey,
                                                    catExpanded,
                                                    function(isExpanded) ToggleExpand(catKey, isExpanded) end
                                                )
                                                catHeader:SetPoint("TOPLEFT", 10 + seasonIndent, -yOffset)
                                                catHeader:SetWidth(width - seasonIndent)
                                                catHeader:SetBackdropColor(0.06, 0.06, 0.08, 0.9)
                                                local COLORS = GetCOLORS()
                                                local borderColor = COLORS.accent
                                                catHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                                                
                                                yOffset = yOffset + HEADER_SPACING
                                                
                                                if catExpanded then
                                                    local rowIdx = 0
                                                    for _, curr in ipairs(byCategory[category]) do
                                                        rowIdx = rowIdx + 1
                                                        yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, seasonIndent, width, yOffset)
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            else
                                -- Other expansions: simple Category grouping (level 2)
                                local byCategory = {}
                                for _, curr in ipairs(byExpansion[expansion]) do
                                    local category = curr.data.category or "Other"
                                    if not byCategory[category] then
                                        byCategory[category] = {}
                                    end
                                    table.insert(byCategory[category], curr)
                                end
                                
                                local categoryOrder = {"Crest", "Upgrade", "Supplies", "Currency", "Profession", "PvP", "Event", "Other"}
                                
                                for _, category in ipairs(categoryOrder) do
                                    if byCategory[category] then
                                        local catKey = expKey .. "-cat-" .. category
                                        local catExpanded = IsExpanded(catKey, true)
                                        
                                        if currencySearchText ~= "" then
                                            catExpanded = true
                                        end
                                        
                                        -- Category header (level 2)
                                        local catHeader, catBtn = CreateCollapsibleHeader(
                                            parent,
                                            category .. " (" .. #byCategory[category] .. ")",
                                            catKey,
                                            catExpanded,
                                            function(isExpanded) ToggleExpand(catKey, isExpanded) end
                                        )
                                        catHeader:SetPoint("TOPLEFT", 10 + expIndent, -yOffset)
                                        catHeader:SetWidth(width - expIndent)
                                        catHeader:SetBackdropColor(0.08, 0.08, 0.10, 0.9)
                                        local COLORS = GetCOLORS()
                                        local borderColor = COLORS.accent
                                        catHeader:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 0.8)
                                        
                                        yOffset = yOffset + HEADER_SPACING
                                        
                                        if catExpanded then
                                            local rowIdx = 0
                                            for _, curr in ipairs(byCategory[category]) do
                                                rowIdx = rowIdx + 1
                                                yOffset = CreateCurrencyRow(parent, curr.data, curr.id, rowIdx, expIndent, width, yOffset)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        
        yOffset = yOffset + 5
    end
    
    -- ===== API LIMITATION NOTICE =====
    yOffset = yOffset + 15
    
    local noticeFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    noticeFrame:SetSize(width - 20, 60)
    noticeFrame:SetPoint("TOPLEFT", 10, -yOffset)
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
    noticeSubText:SetTextColor(0.8, 0.8, 0.8)
    noticeSubText:SetText("Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies.")
    
    yOffset = yOffset + 75
    
    return yOffset
end
