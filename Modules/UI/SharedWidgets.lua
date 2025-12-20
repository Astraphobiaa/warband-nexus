--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
]]

local ADDON_NAME, ns = ...

--============================================================================
-- COLOR CONSTANTS
--============================================================================

-- Modern Color Palette
local COLORS = {
    bg = {0.06, 0.06, 0.08, 0.98},
    bgLight = {0.10, 0.10, 0.12, 1},
    bgCard = {0.08, 0.08, 0.10, 1},
    border = {0.20, 0.20, 0.25, 1},
    borderLight = {0.30, 0.30, 0.38, 1},
    accent = {0.40, 0.20, 0.58, 1},      -- Deep Epic Purple
    accentDark = {0.32, 0.16, 0.46, 1},  -- Darker Purple
    gold = {1.00, 0.82, 0.00, 1},
    green = {0.30, 0.90, 0.30, 1},
    red = {0.95, 0.30, 0.30, 1},
    textBright = {1, 1, 1, 1},
    textNormal = {0.85, 0.85, 0.85, 1},
    textDim = {0.55, 0.55, 0.55, 1},
}

-- Quality colors (hex)
local QUALITY_COLORS = {
    [0] = "9d9d9d", -- Poor (Gray)
    [1] = "ffffff", -- Common (White)
    [2] = "1eff00", -- Uncommon (Green)
    [3] = "0070dd", -- Rare (Blue)
    [4] = "a335ee", -- Epic (Purple)
    [5] = "ff8000", -- Legendary (Orange)
    [6] = "e6cc80", -- Artifact (Gold)
    [7] = "00ccff", -- Heirloom (Cyan)
}

-- Export to namespace
ns.UI_COLORS = COLORS
ns.UI_QUALITY_COLORS = QUALITY_COLORS

--============================================================================
-- LAYOUT CONSTANTS (Unified spacing across all tabs)
--============================================================================

local UI_LAYOUT = {
    ROW_HEIGHT = 26,
    ROW_SPACING = 28,      -- Space between item/currency rows
    HEADER_SPACING = 38,   -- Space after headers (character, expansion, category)
    SECTION_SPACING = 25,  -- Space between major sections
}

-- Export to namespace
ns.UI_LAYOUT = UI_LAYOUT

--============================================================================
-- FRAME POOLING SYSTEM (Performance Optimization)
--============================================================================
-- Reuse frames instead of creating new ones on every refresh
-- This dramatically reduces memory churn and GC pressure

local ItemRowPool = {}
local StorageRowPool = {}

-- Get an item row from pool or create new
local function AcquireItemRow(parent, width, rowHeight)
    local row = table.remove(ItemRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        
        -- Quantity text (left)
        row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 70, 0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(60)
        row.locationText:SetJustifyH("RIGHT")

        row.isPooled = true
        row.rowType = "item"  -- Mark as ItemRow
    end

    row:SetParent(parent)
    row:SetSize(width, rowHeight)
    row:Show()
    return row
end

-- Return item row to pool
local function ReleaseItemRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    
    table.insert(ItemRowPool, row)
end

-- Get storage row from pool (updated to match Items tab style)
local function AcquireStorageRow(parent, width, rowHeight)
    local row = table.remove(StorageRowPool)
    
    if not row then
        -- Create new button with all children (Button for hover effects)
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0.05, 0.05, 0.07, 1)
        
        -- Quantity text (left)
        row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 70, 0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(60)
        row.locationText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "storage"  -- Mark as StorageRow
    end
    
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:Show()
    return row
end

-- Return storage row to pool
local function ReleaseStorageRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    
    table.insert(StorageRowPool, row)
end

-- Release all pooled children of a frame
local function ReleaseAllPooledChildren(parent)
    for _, child in pairs({parent:GetChildren()}) do
        if child.isPooled and child.rowType then
            -- Use rowType to determine which pool to release to
            if child.rowType == "item" then
                ReleaseItemRow(child)
            elseif child.rowType == "storage" then
                ReleaseStorageRow(child)
            end
        end
    end
end

--============================================================================
-- UI HELPER FUNCTIONS
--============================================================================

-- Get quality color as hex string
local function GetQualityHex(quality)
    return QUALITY_COLORS[quality] or "ffffff"
end

-- Create a card frame (common UI element)
local function CreateCard(parent, height)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetHeight(height or 100)
    card:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    card:SetBackdropColor(unpack(COLORS.bgCard))
    card:SetBackdropBorderColor(unpack(COLORS.border))
    return card
end

-- Format gold amount with separators and icon
local function FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return goldStr .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end

-- Create collapsible header with expand/collapse button
local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture)
    local header = CreateFrame("Button", nil, parent, "BackdropTemplate")
    header:SetSize(parent:GetWidth() - 20, 32)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    header:SetBackdropColor(0.1, 0.1, 0.12, 1)
    header:SetBackdropBorderColor(0.4, 0.2, 0.58, 0.5)
    
    -- Expand/Collapse icon (texture-based)
    local expandIcon = header:CreateTexture(nil, "ARTWORK")
    expandIcon:SetSize(16, 16)
    expandIcon:SetPoint("LEFT", 12, 0)
    
    -- Use WoW's built-in plus/minus button textures
    if isExpanded then
        expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
    expandIcon:SetVertexColor(0.8, 0.6, 1)  -- Purple tint to match theme
    
    local textAnchor = expandIcon
    local textOffset = 8
    
    -- Optional icon
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = header:CreateTexture(nil, "ARTWORK")
        categoryIcon:SetSize(28, 28)  -- Bigger icon size (same as favorite star in rows)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
        categoryIcon:SetTexture(iconTexture)
        textAnchor = categoryIcon
        textOffset = 8
    end
    
    -- Header text
    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetText(text)
    headerText:SetTextColor(0.8, 0.8, 0.8)
    
    -- Click handler
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        -- Update icon texture
        if isExpanded then
            expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        else
            expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        end
        onToggle(isExpanded)
    end)
    
    -- Hover effect
    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.18, 1)
    end)
    
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.12, 1)
    end)
    
    return header, expandIcon, categoryIcon
end

-- Get item type name from class ID
local function GetItemTypeName(classID)
    local typeName = GetItemClassInfo(classID)
    return typeName or "Other"
end

-- Get item class ID from item ID
local function GetItemClassID(itemID)
    if not itemID then return 15 end -- Miscellaneous
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID or 15
end

-- Get icon texture for item type
local function GetTypeIcon(classID)
    local icons = {
        [0] = "Interface\\Icons\\INV_Potion_51",          -- Consumable (Potion)
        [1] = "Interface\\Icons\\INV_Box_02",             -- Container
        [2] = "Interface\\Icons\\INV_Sword_27",           -- Weapon
        [3] = "Interface\\Icons\\INV_Misc_Gem_01",        -- Gem
        [4] = "Interface\\Icons\\INV_Chest_Cloth_07",     -- Armor
        [5] = "Interface\\Icons\\INV_Enchant_DustArcane", -- Reagent
        [6] = "Interface\\Icons\\INV_Ammo_Arrow_02",      -- Projectile
        [7] = "Interface\\Icons\\Trade_Engineering",      -- Trade Goods
        [8] = "Interface\\Icons\\INV_Misc_EnchantedScroll", -- Item Enhancement
        [9] = "Interface\\Icons\\INV_Scroll_04",          -- Recipe
        [12] = "Interface\\Icons\\INV_Misc_Key_03",       -- Quest (Key icon)
        [15] = "Interface\\Icons\\INV_Misc_Gear_01",      -- Miscellaneous
        [16] = "Interface\\Icons\\INV_Inscription_Tradeskill01", -- Glyph
        [17] = "Interface\\Icons\\PetJournalPortrait",    -- Battlepet
        [18] = "Interface\\Icons\\WoW_Token01",           -- WoW Token
    }
    return icons[classID] or "Interface\\Icons\\INV_Misc_Gear_01"
end

--============================================================================
-- SORTABLE TABLE HEADER (Reusable for any table with sorting)
--============================================================================

--[[
    Creates a sortable table header with clickable columns
    
    @param parent - Parent frame
    @param columns - Array of column definitions:
        {
            {key="name", label="CHARACTER", align="LEFT", offset=12},
            {key="level", label="LEVEL", align="LEFT", offset=200},
            {key="gold", label="GOLD", align="RIGHT", offset=-120},
            {key="lastSeen", label="LAST SEEN", align="RIGHT", offset=-20}
        }
    @param width - Total header width
    @param onSortChanged - Callback: function(sortKey, isAscending)
    @param defaultSortKey - Initial sort column (optional)
    @param defaultAscending - Initial sort direction (optional, default true)
    
    @return header frame, getCurrentSort function
]]
local function CreateSortableTableHeader(parent, columns, width, onSortChanged, defaultSortKey, defaultAscending)
    -- State
    local currentSortKey = defaultSortKey or (columns[1] and columns[1].key)
    local isAscending = (defaultAscending ~= false) -- Default true

    -- Create header frame with backdrop (like collapsible headers)
    local header = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    header:SetSize(width, 28)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    header:SetBackdropColor(0.1, 0.1, 0.12, 1)  -- Darker background
    header:SetBackdropBorderColor(0.4, 0.2, 0.58, 0.5)  -- Purple border (same as collapsible headers)
    
    -- Column buttons
    local columnButtons = {}
    
    for i, col in ipairs(columns) do
        -- Create clickable button (no backdrop = no box!)
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width or 100, 28)
        
        if col.align == "LEFT" then
            btn:SetPoint("LEFT", col.offset or 0, 0)
        elseif col.align == "RIGHT" then
            btn:SetPoint("RIGHT", col.offset or 0, 0)
        else
            btn:SetPoint("CENTER", col.offset or 0, 0)
        end
        
        -- Label text (position based on alignment)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")  -- Normal size font
        if col.align == "LEFT" then
            btn.label:SetPoint("LEFT", 5, 0)  -- Small padding
            btn.label:SetJustifyH("LEFT")
        elseif col.align == "RIGHT" then
            btn.label:SetPoint("RIGHT", -17, 0) -- Space for arrow on right
            btn.label:SetJustifyH("RIGHT")
        else
            btn.label:SetPoint("CENTER", -6, 0)
            btn.label:SetJustifyH("CENTER")
        end
        btn.label:SetText(col.label)
        btn.label:SetTextColor(0.8, 0.8, 0.8)  -- Brighter text
        
        -- Sort arrow (^ ascending, v descending, - sortable)
        btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- Bigger font!
        if col.align == "RIGHT" then
            btn.arrow:SetPoint("RIGHT", 0, 0)
        else
            btn.arrow:SetPoint("LEFT", btn.label, "RIGHT", 4, 0)
        end
        btn.arrow:SetText("◆") -- Default: sortable indicator
        btn.arrow:SetTextColor(0.4, 0.4, 0.4, 0.6) -- Dim gray
        
        -- Update arrow visibility
        local function UpdateArrow()
            if currentSortKey == col.key then
                btn.arrow:SetText(isAscending and "▲" or "▼")
                btn.arrow:SetTextColor(0.6, 0.4, 0.8, 1) -- Brighter purple
                btn.label:SetTextColor(1, 1, 1) -- Highlight active column
            else
                btn.arrow:SetText("◆") -- Sortable hint (diamond)
                btn.arrow:SetTextColor(0.4, 0.4, 0.4, 0.6) -- Dim
                btn.label:SetTextColor(0.8, 0.8, 0.8)
            end
        end
        
        UpdateArrow()
        
        -- Hover effect
        btn:SetScript("OnEnter", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(1, 1, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(0.8, 0.8, 0.8)
            end
        end)
        
        -- Click handler
        btn:SetScript("OnClick", function()
            if currentSortKey == col.key then
                -- Same column - toggle direction
                isAscending = not isAscending
            else
                -- New column - default to ascending
                currentSortKey = col.key
                isAscending = true
            end
            
            -- Update all arrows
            for _, otherBtn in pairs(columnButtons) do
                if otherBtn.updateArrow then
                    otherBtn.updateArrow()
                end
            end
            
            -- Notify parent
            if onSortChanged then
                onSortChanged(currentSortKey, isAscending)
            end
        end)
        
        btn.updateArrow = UpdateArrow
        columnButtons[i] = btn
    end
    
    -- Function to get current sort state
    local function GetCurrentSort()
        return currentSortKey, isAscending
    end
    
    return header, GetCurrentSort
end

--============================================================================
-- DRAW EMPTY STATE (Shared by Items and Storage tabs)
--============================================================================

local function DrawEmptyState(addon, parent, startY, isSearch, searchText)
    local yOffset = startY + 50
    
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", 0, -yOffset)
    icon:SetTexture(isSearch and "Interface\\Icons\\INV_Misc_Spyglass_02" or "Interface\\Icons\\INV_Misc_Bag_10_Blue")
    icon:SetDesaturated(true)
    icon:SetAlpha(0.4)
    yOffset = yOffset + 60
    
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -yOffset)
    title:SetText(isSearch and "|cff666666No results|r" or "|cff666666No items cached|r")
    yOffset = yOffset + 30
    
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOP", 0, -yOffset)
    desc:SetTextColor(0.5, 0.5, 0.5)
    local displayText = searchText or ""
    desc:SetText(isSearch and ("No items match '" .. displayText .. "'") or "Open your Warband Bank to scan items")
    
    return yOffset + 50
end

--============================================================================
-- SEARCH BOX (Reusable component for Items and Storage tabs)
--============================================================================

--[[
    Creates a search box with icon, placeholder, and throttled callback
    
    @param parent - Parent frame
    @param width - Search box width
    @param placeholder - Placeholder text (e.g., "Search items...")
    @param onTextChanged - Callback function(searchText) - called after throttle
    @param throttleDelay - Delay in seconds before callback (default 0.3)
    @param initialValue - Initial text value (optional, for restoring state)
    
    @return searchContainer frame, clearFunction
]]
local function CreateSearchBox(parent, width, placeholder, onTextChanged, throttleDelay, initialValue)
    local delay = throttleDelay or 0.3
    local throttleTimer = nil
    local initialText = initialValue or ""
    
    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 32)
    
    -- Background frame with border
    local searchFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    searchFrame:SetAllPoints()
    searchFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    searchFrame:SetBackdropColor(0.08, 0.08, 0.10, 1)
    searchFrame:SetBackdropBorderColor(0.4, 0.2, 0.58, 0.5)
    
    -- Search icon
    local searchIcon = searchFrame:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(16, 16)
    searchIcon:SetPoint("LEFT", 10, 0)
    searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    searchIcon:SetAlpha(0.5)
    
    -- EditBox
    local searchBox = CreateFrame("EditBox", nil, searchFrame)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", -10, 0)
    searchBox:SetHeight(20)
    searchBox:SetFontObject("GameFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    -- Set initial value if provided
    if initialText and initialText ~= "" then
        searchBox:SetText(initialText)
    end
    
    -- Placeholder text
    local placeholderText = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder or "Search...")
    placeholderText:SetTextColor(0.5, 0.5, 0.5)
    
    -- Show/hide placeholder based on initial text
    if initialText and initialText ~= "" then
        placeholderText:Hide()
    else
        placeholderText:Show()
    end
    
    -- OnTextChanged handler with throttle
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        
        local text = self:GetText()
        local newSearchText = ""
        
        if text and text ~= "" then
            placeholderText:Hide()
            newSearchText = text:lower()
        else
            placeholderText:Show()
            newSearchText = ""
        end
        
        -- Cancel previous throttle
        if throttleTimer then
            throttleTimer:Cancel()
        end
        
        -- Throttle callback - refresh after delay (live search)
        throttleTimer = C_Timer.NewTimer(delay, function()
            if onTextChanged then
                onTextChanged(newSearchText)
            end
            throttleTimer = nil
        end)
    end)
    
    -- Escape to clear
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    
    -- Enter to defocus
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    -- Focus border highlight
    searchBox:SetScript("OnEditFocusGained", function(self)
        searchFrame:SetBackdropBorderColor(0.4, 0.2, 0.58, 1)
    end)
    
    searchBox:SetScript("OnEditFocusLost", function(self)
        searchFrame:SetBackdropBorderColor(0.4, 0.2, 0.58, 0.5)
    end)
    
    -- Clear function
    local function ClearSearch()
        searchBox:SetText("")
        placeholderText:Show()
    end
    
    return container, ClearSearch
end

--============================================================================
-- SEARCH TEXT GETTERS
--============================================================================

local function GetCurrencySearchText()
    return (ns.currencySearchText or ""):lower()
end

--============================================================================
-- CURRENCY TRANSFER POPUP
--============================================================================

--[[
    Create a currency transfer popup dialog
    @param currencyData table - Currency information
    @param currentCharacterKey string - Current character key
    @param onConfirm function - Callback(targetCharKey, amount)
    @return frame - Popup frame
]]
local function CreateCurrencyTransferPopup(currencyData, currentCharacterKey, onConfirm)
    -- Create backdrop overlay
    local overlay = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")  -- Highest strata
    overlay:SetFrameLevel(1000)
    overlay:SetAllPoints()
    overlay:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
    })
    overlay:SetBackdropColor(0, 0, 0, 0.7)
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)
    
    -- Create popup frame
    local popup = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    popup:SetSize(400, 380)  -- Increased height for instructions
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(overlay:GetFrameLevel() + 10)
    popup:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 2,
    })
    popup:SetBackdropColor(0.08, 0.08, 0.10, 1)
    popup:SetBackdropBorderColor(0.4, 0.2, 0.58, 1)
    popup:EnableMouse(true)
    
    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cff6a0dadTransfer Currency|r")
    
    -- Get WarbandNexus and current character info
    local WarbandNexus = ns.WarbandNexus
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- From Character (current/online)
    local fromText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fromText:SetPoint("TOP", 0, -38)
    fromText:SetText(string.format("|cff888888From:|r |cff00ff00%s|r |cff888888(Online)|r", currentPlayerName))
    
    -- Currency Icon
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", 0, -65)
    if currencyData.iconFileID then
        icon:SetTexture(currencyData.iconFileID)
    end
    
    -- Currency Name
    local nameText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOP", 0, -105)
    nameText:SetText(currencyData.name or "Unknown Currency")
    nameText:SetTextColor(1, 0.82, 0)
    
    -- Available Amount
    local availableText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    availableText:SetPoint("TOP", 0, -125)
    availableText:SetText(string.format("|cff888888Available:|r |cffffffff%d|r", currencyData.quantity or 0))
    
    -- Amount Input Label
    local amountLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amountLabel:SetPoint("TOPLEFT", 30, -155)
    amountLabel:SetText("Amount:")
    
    -- Amount Input Box
    local amountBox = CreateFrame("EditBox", nil, popup, "BackdropTemplate")
    amountBox:SetSize(100, 28)
    amountBox:SetPoint("LEFT", amountLabel, "RIGHT", 10, 0)
    amountBox:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    amountBox:SetBackdropColor(0.05, 0.05, 0.05, 1)
    amountBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    amountBox:SetFontObject("GameFontNormal")
    amountBox:SetTextInsets(8, 8, 0, 0)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    amountBox:SetMaxLetters(10)
    amountBox:SetText("1")
    
    -- Max Button
    local maxBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    maxBtn:SetSize(45, 24)
    maxBtn:SetPoint("LEFT", amountBox, "RIGHT", 5, 0)
    maxBtn:SetText("Max")
    maxBtn:SetScript("OnClick", function()
        amountBox:SetText(tostring(currencyData.quantity or 0))
    end)
    
    -- Confirm Button (create early so it can be referenced)
    local confirmBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    confirmBtn:SetSize(120, 28)
    confirmBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    confirmBtn:SetText("Open & Guide")  -- Changed text
    confirmBtn:Disable() -- Initially disabled until character selected
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 28)
    cancelBtn:SetPoint("RIGHT", confirmBtn, "LEFT", -5, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        overlay:Hide()
    end)
    
    -- Info note at bottom
    local infoNote = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    infoNote:SetPoint("BOTTOM", 0, 50)
    infoNote:SetWidth(360)
    infoNote:SetText("|cff00ff00✓|r Currency window will be opened automatically.\n|cff888888You'll need to manually right-click the currency to transfer.|r")
    infoNote:SetJustifyH("CENTER")
    infoNote:SetWordWrap(true)
    
    -- Target Character Label
    local targetLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLabel:SetPoint("TOPLEFT", 30, -195)
    targetLabel:SetText("To Character:")
    
    -- Get WarbandNexus addon reference
    local WarbandNexus = ns.WarbandNexus
    
    -- Build character list (exclude current character)
    local characterList = {}
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global.characters then
        for charKey, charData in pairs(WarbandNexus.db.global.characters) do
            if charKey ~= currentCharacterKey and charData.name then
                table.insert(characterList, {
                    key = charKey,
                    name = charData.name,
                    realm = charData.realm or "",
                    class = charData.class or "UNKNOWN",
                    level = charData.level or 0,
                })
            end
        end
        
        -- Sort by name
        table.sort(characterList, function(a, b) return a.name < b.name end)
    end
    
    -- Selected character
    local selectedTargetKey = nil
    local selectedCharData = nil
    
    -- Character selection dropdown container
    local charDropdown = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    charDropdown:SetSize(320, 28)
    charDropdown:SetPoint("TOPLEFT", 30, -215)
    charDropdown:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    charDropdown:SetBackdropColor(0.05, 0.05, 0.05, 1)
    charDropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    charDropdown:EnableMouse(true)
    
    local charText = charDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charText:SetPoint("LEFT", 10, 0)
    charText:SetText("|cff888888Select character...|r")
    charText:SetJustifyH("LEFT")
    
    -- Dropdown arrow icon
    local arrowIcon = charDropdown:CreateTexture(nil, "ARTWORK")
    arrowIcon:SetSize(16, 16)
    arrowIcon:SetPoint("RIGHT", -5, 0)
    arrowIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    
    -- Character list frame (dropdown menu)
    local charListFrame = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    charListFrame:SetSize(320, math.min(#characterList * 28 + 4, 200))  -- Max 200px height
    charListFrame:SetPoint("TOPLEFT", charDropdown, "BOTTOMLEFT", 0, -2)
    charListFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    charListFrame:SetFrameLevel(popup:GetFrameLevel() + 20)
    charListFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    charListFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
    charListFrame:SetBackdropBorderColor(0.4, 0.2, 0.58, 1)
    charListFrame:Hide()  -- Initially hidden
    
    -- Scroll frame for character list (if many characters)
    local scrollFrame = CreateFrame("ScrollFrame", nil, charListFrame)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(316, #characterList * 28)
    
    -- Create character buttons
    for i, charData in ipairs(characterList) do
        local charBtn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
        charBtn:SetSize(316, 26)
        charBtn:SetPoint("TOPLEFT", 0, -(i-1) * 28)
        charBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
        })
        charBtn:SetBackdropColor(0, 0, 0, 0)
        
        -- Class color
        local classColor = RAID_CLASS_COLORS[charData.class] or {r=1, g=1, b=1}
        
        local btnText = charBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("LEFT", 8, 0)
        btnText:SetText(string.format("|c%s%s|r |cff888888(%d - %s)|r", 
            string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            charData.name,
            charData.level,
            charData.realm
        ))
        btnText:SetJustifyH("LEFT")
        
        charBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.25, 1)
        end)
        charBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0, 0, 0, 0)
        end)
        charBtn:SetScript("OnClick", function(self)
            selectedTargetKey = charData.key
            selectedCharData = charData
            charText:SetText(string.format("|c%s%s|r", 
                string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
                charData.name
            ))
            charListFrame:Hide()
            confirmBtn:Enable()  -- Enable confirm button
        end)
    end
    
    -- Toggle dropdown
    charDropdown:SetScript("OnMouseDown", function(self)
        if charListFrame:IsShown() then
            charListFrame:Hide()
        else
            charListFrame:Show()
        end
    end)
    
    -- Set confirm button click handler (now that we have all variables)
    confirmBtn:SetScript("OnClick", function()
        local amount = tonumber(amountBox:GetText()) or 0
        if amount > 0 and amount <= (currencyData.quantity or 0) and selectedTargetKey and selectedCharData then
            -- STEP 1: Open Currency Frame (SAFE - No Taint)
            -- TWW (11.x) uses different frame name
            if not CharacterFrame or not CharacterFrame:IsShown() then
                ToggleCharacter("PaperDollFrame")
            end
            
            -- Switch to currency tab
            C_Timer.After(0.1, function()
                if CharacterFrame and CharacterFrame:IsShown() then
                    -- Click the Token (Currency) tab
                    if CharacterFrameTab4 then
                        CharacterFrameTab4:Click()
                    end
                end
            end)
            
            -- STEP 2: Try to expand currency categories (SAFE)
            C_Timer.After(0.3, function()
                -- Expand all currency categories so user can see target currency
                for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
                    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
                    if info and info.isHeader and not info.isHeaderExpanded then
                        C_CurrencyInfo.ExpandCurrencyList(i, true)
                    end
                end
            end)
            
            -- STEP 3: Show instructions in chat
            local WarbandNexus = ns.WarbandNexus
            if WarbandNexus then
                WarbandNexus:Print("|cff00ff00=== Currency Transfer Instructions ===|r")
                WarbandNexus:Print(string.format("|cffffaa00Currency:|r %s", currencyData.name))
                WarbandNexus:Print(string.format("|cffffaa00Amount:|r %d", amount))
                WarbandNexus:Print(string.format("|cffffaa00From:|r %s |cff888888(current character)|r", currentPlayerName))
                WarbandNexus:Print(string.format("|cffffaa00To:|r |cff00ff00%s|r", selectedCharData.name))
                WarbandNexus:Print(" ")
                WarbandNexus:Print("|cff00aaffNext steps:|r")
                WarbandNexus:Print("|cff00ff001.|r Find |cffffffff" .. currencyData.name .. "|r in the Currency window")
                WarbandNexus:Print("|cff00ff002.|r |cffff8800Right-click|r on it")
                WarbandNexus:Print("|cff00ff003.|r Select |cffffffff'Transfer to Warband'|r")
                WarbandNexus:Print("|cff00ff004.|r Choose |cff00ff00" .. selectedCharData.name .. "|r")
                WarbandNexus:Print("|cff00ff005.|r Enter amount: |cffffffff" .. amount .. "|r")
                WarbandNexus:Print(" ")
                WarbandNexus:Print("|cff00ff00✓|r Currency window is now open!")
                WarbandNexus:Print("|cff888888(Blizzard security prevents automatic transfer)|r")
            end
            
            overlay:Hide()
        end
    end)
    
    -- Store reference for cleanup
    overlay.popup = popup
    
    -- Show overlay
    overlay:Show()
    
    return overlay
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_CreateCard = CreateCard
ns.UI_FormatGold = FormatGold
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_CreateSortableTableHeader = CreateSortableTableHeader
ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_CreateSearchBox = CreateSearchBox
ns.UI_GetCurrencySearchText = GetCurrencySearchText

-- Frame pooling exports
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren
