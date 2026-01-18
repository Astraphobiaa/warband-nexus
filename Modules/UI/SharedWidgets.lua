--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--============================================================================
-- COLOR CONSTANTS
--============================================================================

-- Calculate all theme variations from a master color
local function CalculateThemeColors(masterR, masterG, masterB)
    -- Helper: Desaturate color
    local function Desaturate(r, g, b, amount)
        local gray = (r + g + b) / 3
        return r + (gray - r) * amount, 
               g + (gray - g) * amount, 
               b + (gray - b) * amount
    end
    
    -- Helper: Adjust brightness
    local function AdjustBrightness(r, g, b, factor)
        return math.min(1, r * factor),
               math.min(1, g * factor),
               math.min(1, b * factor)
    end
    
    -- Calculate variations and wrap in arrays
    local darkR, darkG, darkB = AdjustBrightness(masterR, masterG, masterB, 0.7)
    local borderR, borderG, borderB = Desaturate(masterR * 0.5, masterG * 0.5, masterB * 0.5, 0.6)
    local activeR, activeG, activeB = AdjustBrightness(masterR, masterG, masterB, 0.5)
    local hoverR, hoverG, hoverB = AdjustBrightness(masterR, masterG, masterB, 0.6)
    
    return {
        accent = {masterR, masterG, masterB},
        accentDark = {darkR, darkG, darkB},
        border = {borderR, borderG, borderB},
        tabActive = {activeR, activeG, activeB},
        tabHover = {hoverR, hoverG, hoverB},
    }
end

-- Get theme colors from database (with fallbacks)
local function GetThemeColors()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local themeColors = db and db.themeColors or {}
    
    return {
        accent = themeColors.accent or {0.40, 0.20, 0.58},
        accentDark = themeColors.accentDark or {0.28, 0.14, 0.41},
        border = themeColors.border or {0.20, 0.20, 0.25},
        tabActive = themeColors.tabActive or {0.20, 0.12, 0.30},
        tabHover = themeColors.tabHover or {0.24, 0.14, 0.35},
    }
end

-- Modern Color Palette (Dynamic - updates from database)
local function GetColors()
    local theme = GetThemeColors()
    
    return {
        bg = {0.06, 0.06, 0.08, 0.98},
        bgLight = {0.10, 0.10, 0.12, 1},
        bgCard = {0.08, 0.08, 0.10, 1},
        border = {theme.border[1], theme.border[2], theme.border[3], 1},
        borderLight = {0.30, 0.30, 0.38, 1},
        accent = {theme.accent[1], theme.accent[2], theme.accent[3], 1},
        accentDark = {theme.accentDark[1], theme.accentDark[2], theme.accentDark[3], 1},
        tabActive = {theme.tabActive[1], theme.tabActive[2], theme.tabActive[3], 1},
        tabHover = {theme.tabHover[1], theme.tabHover[2], theme.tabHover[3], 1},
        tabInactive = {0.08, 0.08, 0.10, 1},
        gold = {1.00, 0.82, 0.00, 1},
        green = {0.30, 0.90, 0.30, 1},
        red = {0.95, 0.30, 0.30, 1},
        textBright = {1, 1, 1, 1},
        textNormal = {0.85, 0.85, 0.85, 1},
        textDim = {0.55, 0.55, 0.55, 1},
    }
end

-- Create initial COLORS table
local COLORS = GetColors()

-- Refresh COLORS table from database
local function RefreshColors()
    if WarbandNexus.db.profile.debugMode then
        print("=== RefreshColors CALLED ===")
    end
    
    -- Immediate update
    local newColors = GetColors()
    for k, v in pairs(newColors) do
        COLORS[k] = v
    end
    -- Also update the namespace reference
    ns.UI_COLORS = COLORS
    
    if WarbandNexus.db.profile.debugMode then
        print(string.format("New accent color: R=%.2f, G=%.2f, B=%.2f", COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]))
    end
    
    -- Update main frame border and header if it exists
    if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
        local f = WarbandNexus.UI.mainFrame
        local accentColor = COLORS.accent
        local borderColor = COLORS.border
        
        -- Calculate hex color inline
        local accentHex = string.format("%02x%02x%02x", accentColor[1] * 255, accentColor[2] * 255, accentColor[3] * 255)
        
        if WarbandNexus.db.profile.debugMode then
            print(string.format("Accent hex: %s", accentHex))
            print(string.format("mainFrame exists: %s", tostring(f ~= nil)))
        end
        
        -- Note: Title stays white (not theme-colored)
        
        -- Update main frame border using COLORS.border
        if f.SetBackdropBorderColor then
            f:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        
        -- Update header background
        if f.header and f.header.SetBackdropColor then
            f.header:SetBackdropColor(COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], COLORS.accentDark[4] or 1)
        end
        
        -- Update content area border
        if f.content and f.content.SetBackdropBorderColor then
            f.content:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)
        end
        
        -- Update footer buttons (Scan, Sort, Classic Bank)
        if f.scanBtn and f.scanBtn.SetBackdropBorderColor then
            f.scanBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        if f.sortBtn and f.sortBtn.SetBackdropBorderColor then
            f.sortBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        if f.classicBtn and f.classicBtn.SetBackdropBorderColor then
            f.classicBtn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
        end
        
        -- Update main tab buttons (activeBar highlight)
        if f.tabButtons then
            local accentColor = COLORS.accent
            local tabActiveColor = COLORS.tabActive
            local tabInactiveColor = COLORS.tabInactive
            local tabHoverColor = COLORS.tabHover
            
            for tabKey, btn in pairs(f.tabButtons) do
                local isActive = f.currentTab == tabKey
                
                -- Update background color
                if isActive then
                    btn:SetBackdropColor(tabActiveColor[1], tabActiveColor[2], tabActiveColor[3], 1)
                    btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
                else
                    btn:SetBackdropColor(tabInactiveColor[1], tabInactiveColor[2], tabInactiveColor[3], 1)
                    btn:SetBackdropBorderColor(tabInactiveColor[1] * 1.5, tabInactiveColor[2] * 1.5, tabInactiveColor[3] * 1.5, 0.5)
                end
                
                -- Update activeBar (bottom highlight line)
                if btn.activeBar then
                    btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
                end
                
                -- Update glow
                if btn.glow then
                    btn.glow:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], isActive and 0.25 or 0.15)
                end
            end
        end
        
        -- Update search bar borders
        if f.persistentSearchBoxes then
            for _, searchBox in pairs(f.persistentSearchBoxes) do
                if searchBox and searchBox.searchFrame then
                    local borderColor = COLORS.accent
                    searchBox.searchFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
                end
            end
        end
        
        -- Refresh content to update dynamic elements (without infinite loop)
        if f:IsShown() and WarbandNexus.RefreshUI then
            if WarbandNexus.db.profile.debugMode then
                print("Calling RefreshUI to update content")
            end
            WarbandNexus:RefreshUI()
        end
        
        if WarbandNexus.db.profile.debugMode then
            print("=== RefreshColors COMPLETE ===")
        end
    else
        if WarbandNexus.db.profile.debugMode then
            print("ERROR: mainFrame not found!")
            print(string.format("WarbandNexus exists: %s", tostring(WarbandNexus ~= nil)))
            print(string.format("WarbandNexus.UI exists: %s", tostring(WarbandNexus and WarbandNexus.UI ~= nil)))
        end
    end
    
    -- Notify NotificationManager about color change
    if WarbandNexus and WarbandNexus.RefreshNotificationColors then
        WarbandNexus:RefreshNotificationColors()
    end
end

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
    SECTION_SPACING = 15,  -- Space between major sections (character headers) - reduced from 25
    -- Indent constants for hierarchical content
    CHAR_INDENT = 20,      -- Indent for content under character header
    EXPANSION_INDENT = 20, -- Additional indent for expansion content
    CATEGORY_INDENT = 20,  -- Additional indent for category content
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
local CurrencyRowPool = {}

-- Get a currency row from pool or create new
local function AcquireCurrencyRow(parent, width, rowHeight)
    local row = table.remove(CurrencyRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background
        row:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
        })
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 15, 0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 43, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Amount text
        row.amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.amountText:SetPoint("RIGHT", -10, 0)
        row.amountText:SetWidth(150)
        row.amountText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "currency"  -- Mark as CurrencyRow
    end
    
    -- CRITICAL: Always set parent when acquiring from pool
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    return row
end

-- Return currency row to pool
local function ReleaseCurrencyRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnClick", nil)
    
    -- Reset icon
    if row.icon then
        row.icon:SetTexture(nil)
        row.icon:SetAlpha(1)
    end
    
    -- Reset texts
    if row.nameText then
        row.nameText:SetText("")
        row.nameText:SetTextColor(1, 1, 1)
    end
    
    if row.amountText then
        row.amountText:SetText("")
        row.amountText:SetTextColor(1, 1, 1)
    end
    
    -- Reset background
    row:SetBackdropColor(0, 0, 0, 0)
    
    table.insert(CurrencyRowPool, row)
end

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
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
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
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
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

-- Release all pooled children of a frame (and hide non-pooled ones)
local function ReleaseAllPooledChildren(parent)
    for _, child in pairs({parent:GetChildren()}) do
        if child.isPooled and child.rowType then
            -- Use rowType to determine which pool to release to
            if child.rowType == "item" then
                ReleaseItemRow(child)
            elseif child.rowType == "storage" then
                ReleaseStorageRow(child)
            elseif child.rowType == "currency" then
                ReleaseCurrencyRow(child)
            end
        else
            -- Non-pooled frame (like headers) - just hide and clear
            -- Use pcall to safely handle frames that don't support scripts
            pcall(function()
                child:Hide()
                child:ClearAllPoints()
            end)
            
            -- Only set scripts if the frame type supports it (Button, Frame, etc.)
            if child.SetScript and child.GetScript then
                pcall(function()
                    child:SetScript("OnClick", nil)
                    child:SetScript("OnEnter", nil)
                    child:SetScript("OnLeave", nil)
                end)
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

-- Get accent color as hex string
local function GetAccentHexColor()
    local c = COLORS.accent
    return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
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
    -- Use theme accent color for title card borders
    card:SetBackdropBorderColor(unpack(COLORS.accent))
    return card
end

-- Format gold amount with separators and icon (legacy - simple gold display)
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

--[[
    Format money with gold, silver, and copper
    @param copper number - Total copper amount
    @param iconSize number - Icon size (optional, default 14)
    @param showZero boolean - Show zero values (optional, default false)
    @return string - Formatted money string with colors and icons
]]
local function FormatMoney(copper, iconSize, showZero)
    copper = copper or 0
    iconSize = iconSize or 14
    showZero = showZero or false
    
    -- Calculate gold, silver, copper
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = copper % 100
    
    -- Build formatted string
    local parts = {}
    
    -- Gold (yellow/golden)
    if gold > 0 or showZero then
        -- Add thousand separators for gold
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        table.insert(parts, string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t", goldStr, iconSize, iconSize))
    end
    
    -- Silver (silver/gray) - ALWAYS 2 digits for alignment
    if silver > 0 or (showZero and gold > 0) then
        table.insert(parts, string.format("|cffc7c7cf%02d|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t", silver, iconSize, iconSize))
    end
    
    -- Copper (bronze/copper) - ALWAYS 2 digits for alignment
    if copperAmount > 0 or showZero or (gold == 0 and silver == 0) then
        table.insert(parts, string.format("|cffeda55f%02d|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t", copperAmount, iconSize, iconSize))
    end
    
    return table.concat(parts, " ")
end

--[[
    Format money compact (short version, only highest denomination)
    @param copper number - Total copper amount
    @param iconSize number - Icon size (optional, default 14)
    @return string - Compact formatted money string
]]
local function FormatMoneyCompact(copper, iconSize)
    copper = copper or 0
    iconSize = iconSize or 14
    
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = copper % 100
    
    -- Show only the highest denomination
    if gold > 0 then
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t", goldStr, iconSize, iconSize)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t", silver, iconSize, iconSize)
    else
        return string.format("|cffeda55f%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t", copperAmount, iconSize, iconSize)
    end
end

-- Create collapsible header with expand/collapse button (NO pooling - headers are few)
local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture, isAtlas)
    -- Create new header (no pooling for headers - they're infrequent and context-specific)
    local header = CreateFrame("Button", nil, parent, "BackdropTemplate")
    header:SetSize(parent:GetWidth() - 20, 32)
    header:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    header:SetBackdropColor(0.1, 0.1, 0.12, 1)
    local headerBorder = COLORS.accent
    header:SetBackdropBorderColor(headerBorder[1], headerBorder[2], headerBorder[3], 0.5)
    
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
    -- Dynamic theme color tint
    local iconTint = COLORS.accent
    expandIcon:SetVertexColor(iconTint[1] * 1.5, iconTint[2] * 1.5, iconTint[3] * 1.5)
    
    local textAnchor = expandIcon
    local textOffset = 8
    
    -- Optional icon (supports both texture paths and atlas names)
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = header:CreateTexture(nil, "ARTWORK")
        categoryIcon:SetSize(28, 28)  -- Bigger icon size (same as favorite star in rows)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
        
        -- Use atlas if specified, otherwise texture path
        if isAtlas then
            categoryIcon:SetAtlas(iconTexture, false)
        else
            categoryIcon:SetTexture(iconTexture)
        end
        
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
-- CHARACTER ICON HELPERS (Faction, Race, Class)
--============================================================================

--[[
    Get faction icon texture path
    @param faction string - "Alliance", "Horde", or "Neutral"
    @return string - Texture path
]]
local function GetFactionIcon(faction)
    if faction == "Alliance" then
        return "Interface\\FriendsFrame\\PlusManz-Alliance"
    elseif faction == "Horde" then
        return "Interface\\FriendsFrame\\PlusManz-Horde"
    else
        -- Neutral (Pandaren starting zone or unknown)
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    end
end

--[[
    Get race-gender icon atlas name
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female)
    @return string - Atlas name
]]
local function GetRaceGenderAtlas(raceFile, gender)
    if not raceFile then
        return "shop-icon-housing-characters-up"
    end
    
    -- Map race file names to atlas names
    local raceMap = {
        ["BloodElf"] = "bloodelf",
        ["DarkIronDwarf"] = "darkirondwarf",
        ["Dracthyr"] = "dracthyrvisage",  -- Dracthyr uses visage form
        ["Draenei"] = "draenei",
        ["Dwarf"] = "dwarf",
        ["Earthen"] = "earthen",
        ["Gnome"] = "gnome",
        ["Goblin"] = "goblin",
        ["HighmountainTauren"] = "highmountain",
        ["Human"] = "human",
        ["KulTiran"] = "kultiran",
        ["LightforgedDraenei"] = "lightforged",
        ["MagharOrc"] = "magharorc",
        ["Mechagnome"] = "mechagnome",
        ["Nightborne"] = "nightborne",
        ["NightElf"] = "nightelf",
        ["Orc"] = "orc",
        ["Pandaren"] = "pandaren",
        ["Tauren"] = "tauren",
        ["Troll"] = "troll",
        ["Scourge"] = "undead",  -- Undead is "Scourge" in API
        ["Worgen"] = "worgen",
        ["ZandalariTroll"] = "zandalari",
        ["VoidElf"] = "voidelf",
        ["Vulpera"] = "vulpera",
    }
    
    local atlasRace = raceMap[raceFile]
    if not atlasRace then
        return "shop-icon-housing-characters-up"  -- Fallback
    end
    
    local genderStr = (gender == 3) and "female" or "male"
    
    return string.format("raceicon128-%s-%s", atlasRace, genderStr)
end

--[[
    Get race icon - NOW RETURNS ATLAS (not texture path)
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @return string - Atlas name
]]
local function GetRaceIcon(raceFile, gender)
    -- NEW: Use atlas system with gender support
    return GetRaceGenderAtlas(raceFile, gender or 2)  -- Default to male if not provided
end

--[[
    Create faction icon on a frame
    @param parent frame - Parent frame
    @param faction string - "Alliance", "Horde", "Neutral"
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateFactionIcon(parent, faction, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetFactionIcon(faction))
    return icon
end

--[[
    Create race icon on a frame (NEW: Auto-uses race-gender atlases)
    @param parent frame - Parent frame
    @param raceFile string - English race name
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateRaceIcon(parent, raceFile, gender, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 28, size or 28)
    icon:SetPoint(point, x, y)
    
    -- Always use atlas system
    local atlasName = GetRaceIcon(raceFile, gender)  -- GetRaceIcon now returns atlas name
    icon:SetAtlas(atlasName, false)  -- false = don't use atlas size (we set it manually)
    
    return icon
end

-- Export to namespace
ns.UI_GetFactionIcon = GetFactionIcon
ns.UI_GetRaceIcon = GetRaceIcon
ns.UI_GetRaceGenderAtlas = GetRaceGenderAtlas
ns.UI_CreateFactionIcon = CreateFactionIcon
ns.UI_CreateRaceIcon = CreateRaceIcon

-- ============================================================================
-- HEADER ICON SYSTEM (Standardized icon+border for all tab headers)
-- ============================================================================

-- Centralized icon mapping for all tabs
local TAB_HEADER_ICONS = {
    characters = "poi-town",
    items = "Banker",
    storage = "VignetteLoot",
    plans = "poi-islands-table",
    currency = "Auctioneer",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    statistics = "racing",
}

-- Centralized size configuration
local HEADER_ICON_SIZE = 41      -- Icon size
local HEADER_BORDER_SIZE = 51    -- Border size
local HEADER_ICON_XOFFSET = 18   -- X position
local HEADER_ICON_YOFFSET = 0    -- Y position

-- Export icon mapping for external use
ns.UI_GetTabIcon = function(tabName)
    return TAB_HEADER_ICONS[tabName] or "shop-icon-housing-characters-up"
end

-- Export size configuration
ns.UI_GetHeaderIconSize = function()
    return HEADER_ICON_SIZE, HEADER_BORDER_SIZE, HEADER_ICON_XOFFSET, HEADER_ICON_YOFFSET
end

--[[
    Create a standardized header icon with character-style ring border
    This creates the same icon+border style used in "Your Characters" and "Current Character"
    Border color adapts to theme accent color
    @param parent frame - Parent frame (typically a card/header)
    @param atlasName string - Atlas name for the inner icon (e.g., "charactercreate-gendericon-female-selected")
    @param size number - Icon size (default: from HEADER_ICON_SIZE)
    @param borderSize number - Border size (default: from HEADER_BORDER_SIZE)
    @param point string - Anchor point (default: "LEFT")
    @param x number - X offset (default: from HEADER_ICON_XOFFSET)
    @param y number - Y offset (default: from HEADER_ICON_YOFFSET)
    @return table - {icon=texture, border=texture} for further manipulation if needed
]]
local function CreateHeaderIcon(parent, atlasName, size, borderSize, point, x, y)
    size = size or HEADER_ICON_SIZE
    borderSize = borderSize or HEADER_BORDER_SIZE
    point = point or "LEFT"
    x = x or HEADER_ICON_XOFFSET
    y = y or HEADER_ICON_YOFFSET
    
    -- Inner icon (lower sublayer)
    local icon = parent:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetAtlas(atlasName, false)
    
    -- Border - Search icon frame (atlas, best attempt at coloring)
    local border = parent:CreateTexture(nil, "ARTWORK", nil, 1)
    border:SetSize(borderSize, borderSize)
    border:SetPoint("CENTER", icon, "CENTER", 0, 0)
    border:SetAtlas("search-iconframe-large", false)
    
    -- Apply theme accent color to border (may not work with all atlases)
    local GetCOLORS = ns.UI_GetCOLORS
    if GetCOLORS then
        local COLORS = GetCOLORS()
        local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        border:SetVertexColor(r, g, b, 1.0)
    end
    
    return {
        icon = icon,
        border = border
    }
end

-- Export header icon system
ns.UI_CreateHeaderIcon = CreateHeaderIcon

-- ============================================================================
-- CURRENT CHARACTER ICON (Global, easily customizable)
-- ============================================================================

--[[
    Get the atlas name for "Current Character" icon
    This is a global setting that applies to all "Current Character" displays
    Change this function to customize the icon globally
    @return string - Atlas name for the current character icon
]]
local function GetCurrentCharacterIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all "Current Character" icons
    -- Default: "charactercreate-gendericon-female-selected" (generic character icon)
    -- Alternatives: 
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    --   "Banker" (banker icon)
    return "charactercreate-gendericon-female-selected"
end

-- Export
ns.UI_GetCurrentCharacterIcon = GetCurrentCharacterIcon

-- ============================================================================
-- CHARACTER-SPECIFIC ICON (Used in headers across multiple tabs)
-- ============================================================================

--[[
    Get the atlas name for "Character-Specific" contexts
    This icon is used for headers and sections that represent character-specific data
    
    Used in:
    - Characters tab → "Characters" header
    - Storage tab → "Personal Banks" header
    - Reputations tab → "Character-Based Reputations" header
    
    @return string - Atlas name for character-specific icon
]]
local function GetCharacterSpecificIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all character-specific headers
    -- Current: "honorsystem-icon-prestige-9" (honor prestige badge, character-specific indicator)
    -- Alternatives:
    --   "charactercreate-gendericon-female-selected" (generic character)
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    return "honorsystem-icon-prestige-9"
end

-- Export
ns.UI_GetCharacterSpecificIcon = GetCharacterSpecificIcon

--[[
    Get class icon texture path (clean, frameless icons)
    @param classFile string - English class name (e.g., "WARRIOR", "MAGE")
    @return string - Texture path
]]
local function GetClassIcon(classFile)
    -- Use class crest icons (clean, no frame)
    local classIcons = {
        ["WARRIOR"] = "Interface\\Icons\\ClassIcon_Warrior",
        ["PALADIN"] = "Interface\\Icons\\ClassIcon_Paladin",
        ["HUNTER"] = "Interface\\Icons\\ClassIcon_Hunter",
        ["ROGUE"] = "Interface\\Icons\\ClassIcon_Rogue",
        ["PRIEST"] = "Interface\\Icons\\ClassIcon_Priest",
        ["DEATHKNIGHT"] = "Interface\\Icons\\ClassIcon_DeathKnight",
        ["SHAMAN"] = "Interface\\Icons\\ClassIcon_Shaman",
        ["MAGE"] = "Interface\\Icons\\ClassIcon_Mage",
        ["WARLOCK"] = "Interface\\Icons\\ClassIcon_Warlock",
        ["MONK"] = "Interface\\Icons\\ClassIcon_Monk",
        ["DRUID"] = "Interface\\Icons\\ClassIcon_Druid",
        ["DEMONHUNTER"] = "Interface\\Icons\\ClassIcon_DemonHunter",
        ["EVOKER"] = "Interface\\Icons\\ClassIcon_Evoker",
    }
    
    return classIcons[classFile] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--[[
    Create class icon on a frame
    @param parent frame - Parent frame
    @param classFile string - English class name (e.g., "WARRIOR")
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateClassIcon(parent, classFile, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetClassIcon(classFile))
    return icon
end

-- Exports
ns.UI_GetClassIcon = GetClassIcon
ns.UI_CreateClassIcon = CreateClassIcon

--============================================================================
-- FAVORITE ICON HELPERS
--============================================================================

-- Constants
local FAVORITE_ICON_TEXTURE = "Interface\\COMMON\\FavoritesIcon"
local FAVORITE_COLOR_ACTIVE = {1, 0.84, 0}  -- Gold
local FAVORITE_COLOR_INACTIVE = {0.5, 0.5, 0.5}  -- Gray

--[[
    Get favorite icon texture path (always same texture, color changes)
    @return string - Texture path
]]
local function GetFavoriteIconTexture()
    return FAVORITE_ICON_TEXTURE
end

--[[
    Apply favorite icon styling
    @param texture texture - Texture object to style
    @param isFavorite boolean - Whether character is favorited
]]
local function StyleFavoriteIcon(texture, isFavorite)
    texture:SetTexture(FAVORITE_ICON_TEXTURE)
    if isFavorite then
        texture:SetDesaturated(false)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_ACTIVE))
    else
        texture:SetDesaturated(true)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_INACTIVE))
    end
end

--[[
    Create complete favorite button with click handler
    @param parent frame - Parent frame
    @param charKey string - Character key (name-realm)
    @param isFavorite boolean - Current favorite status
    @param size number - Button size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @param onToggle function - Callback(charKey) returns new status
    @return button - Created button
]]
local function CreateFavoriteButton(parent, charKey, isFavorite, size, point, x, y, onToggle)
    -- Make favorite icon 15% larger and shift 2px down
    local iconSize = size * 1.15
    local yOffset = y - 2  -- Negative moves down in WoW
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)  -- Keep button hitbox same size
    btn:SetPoint(point, x, yOffset)
    
    local icon = btn:CreateTexture(nil, "ARTWORK")
    -- Center the larger icon within the button
    local sizeDiff = (iconSize - size) / 2
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER", 0, 0)
    StyleFavoriteIcon(icon, isFavorite)
    
    btn.icon = icon
    btn.charKey = charKey
    btn.isFavorite = isFavorite
    
    btn:SetScript("OnClick", function(self)
        local newStatus = onToggle(self.charKey)
        self.isFavorite = newStatus
        StyleFavoriteIcon(self.icon, newStatus)
    end)
    
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isFavorite then
            GameTooltip:SetText("|cffffd700Favorite Character|r\nClick to remove from favorites")
        else
            GameTooltip:SetText("Click to add to favorites\n|cff888888Favorites are always shown at the top|r")
        end
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    return btn
end

-- Exports
ns.UI_GetFavoriteIconTexture = GetFavoriteIconTexture
ns.UI_StyleFavoriteIcon = StyleFavoriteIcon
ns.UI_CreateFavoriteButton = CreateFavoriteButton

--============================================================================
-- ONLINE INDICATOR HELPERS
--============================================================================

-- Constants
local ONLINE_ICON_TEXTURE = "Interface\\FriendsFrame\\StatusIcon-Online"
local ONLINE_ICON_SIZE = 16

--[[
    Get online indicator texture path
    @return string - Texture path
]]
local function GetOnlineIconTexture()
    return ONLINE_ICON_TEXTURE
end

--[[
    Create online indicator (simple texture, no interaction)
    @param parent frame - Parent frame
    @param size number - Icon size (optional, defaults to 16)
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateOnlineIndicator(parent, size, point, x, y)
    local indicator = parent:CreateTexture(nil, "ARTWORK")
    indicator:SetSize(size or ONLINE_ICON_SIZE, size or ONLINE_ICON_SIZE)
    indicator:SetPoint(point, x, y)
    indicator:SetTexture(ONLINE_ICON_TEXTURE)
    return indicator
end

-- Exports
ns.UI_GetOnlineIconTexture = GetOnlineIconTexture
ns.UI_CreateOnlineIndicator = CreateOnlineIndicator
ns.UI_ONLINE_ICON_SIZE = ONLINE_ICON_SIZE

--============================================================================
-- CHARACTER ROW COLUMN CONFIGURATION
--============================================================================

-- Define column structure (single source of truth)
local CHAR_ROW_COLUMNS = {
    favorite = {
        width = 24,
        spacing = 4,
        total = 28,  -- width + spacing
    },
    faction = {
        width = 24,
        spacing = 4,
        total = 28,
    },
    race = {
        width = 24,
        spacing = 4,
        total = 28,
    },
    class = {
        width = 24,
        spacing = 6,
        total = 30,
    },
    name = {
        width = 160,
        spacing = 15,
        total = 175,
    },
    level = {
        width = 40,
        spacing = 15,
        total = 55,
    },
    gold = {
        width = 180,  -- Increased for "10,000,000g 00s 00c" (10 million gold max)
        spacing = 15,
        total = 195,
    },
    professions = {
        width = 180,
        spacing = 15,
        total = 195,
    },
    spacer = {
        width = 150,  -- Flexible space between professions and last seen
        spacing = 0,
        total = 150,
    },
    lastSeen = {
        width = 100,
        spacing = 10,
        total = 110,
    },
    delete = {
        width = 30,
        spacing = 10,
        total = 40,
    },
}

--[[
    Calculate column offset from left
    @param columnKey string - Column key (e.g., "name", "level")
    @return number - X offset from left
]]
local function GetColumnOffset(columnKey)
    local offset = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "level", "gold", "professions", "spacer", "lastSeen", "delete"}
    
    for _, key in ipairs(order) do
        if key == columnKey then
            return offset
        end
        offset = offset + CHAR_ROW_COLUMNS[key].total
    end
    
    return offset
end

--[[
    Calculate total width needed for all character row columns
    @return number - Total width (base padding + all columns + right padding)
]]
local function GetCharRowTotalWidth()
    local width = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "level", "gold", "professions", "spacer", "lastSeen", "delete"}
    
    for _, key in ipairs(order) do
        width = width + CHAR_ROW_COLUMNS[key].total
    end
    
    width = width + 10  -- Right padding
    return width
end

--[[
    Create column divider at specified offset
    @param parent frame - Parent frame
    @param xOffset number - X position for divider
    @return texture - Created divider texture
]]
local function CreateCharRowColumnDivider(parent, xOffset)
    local divider = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    divider:SetColorTexture(0.3, 0.3, 0.35, 0.4)
    divider:SetSize(1, 38)
    divider:SetPoint("LEFT", xOffset, 0)
    return divider
end

-- Exports
ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowTotalWidth = GetCharRowTotalWidth
ns.UI_CreateCharRowColumnDivider = CreateCharRowColumnDivider

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
    -- Validate parent frame
    if not parent or not parent.CreateTexture then
        return startY or 0
    end
    
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
    
    -- Background frame with border (dynamic colors)
    local searchFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    container.searchFrame = searchFrame  -- Store reference for color updates
    searchFrame:SetAllPoints()
    searchFrame:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    searchFrame:SetBackdropColor(0.08, 0.08, 0.10, 1)
    local borderColor = COLORS.accent
    searchFrame:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
    
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
    
    -- Focus border highlight (dynamic colors)
    searchBox:SetScript("OnEditFocusGained", function(self)
        local accentColor = COLORS.accent
        searchFrame:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
    end)
    
    searchBox:SetScript("OnEditFocusLost", function(self)
        local accentColor = COLORS.accent
        searchFrame:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 0.5)
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
    local popupBorder = COLORS.accent
    popup:SetBackdropBorderColor(popupBorder[1], popupBorder[2], popupBorder[3], 1)
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
    local listBorder = COLORS.accent
    charListFrame:SetBackdropBorderColor(listBorder[1], listBorder[2], listBorder[3], 1)
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
-- SHARED UI CONSTANTS
--============================================================================

local UI_CONSTANTS = {
    BUTTON_HEIGHT = 28,
    BORDER_SIZE = 1,
    BUTTON_BORDER_COLOR = function() return COLORS.accent end,
    BUTTON_BG_COLOR = {0.1, 0.1, 0.1, 1},
}

ns.UI_CONSTANTS = UI_CONSTANTS

--============================================================================
-- SHARED BUTTON WIDGET
--============================================================================

--[[
    Create a themed button with consistent styling
    @param parent - Parent frame
    @param text - Button text
    @param width - Button width
    @return button - Created button
]]
local function CreateThemedButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width or 100, UI_CONSTANTS.BUTTON_HEIGHT)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = UI_CONSTANTS.BORDER_SIZE,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    btn:SetBackdropColor(unpack(UI_CONSTANTS.BUTTON_BG_COLOR))
    local borderColor = UI_CONSTANTS.BUTTON_BORDER_COLOR()
    btn:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
    
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText
    
    -- Hover effect
    btn:SetScript("OnEnter", function(self)
        local color = UI_CONSTANTS.BUTTON_BORDER_COLOR()
        self:SetBackdropBorderColor(color[1] * 1.2, color[2] * 1.2, color[3] * 1.2, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        local color = UI_CONSTANTS.BUTTON_BORDER_COLOR()
        self:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    end)
    
    return btn
end

--============================================================================
-- SHARED CHECKBOX WIDGET
--============================================================================

--[[
    Create a themed checkbox with consistent styling
    @param parent - Parent frame
    @param initialState - Initial checked state (boolean)
    @return checkbox - Created checkbox
]]
local function CreateThemedCheckbox(parent, initialState)
    local checkbox = CreateFrame("CheckButton", nil, parent, "BackdropTemplate")
    checkbox:SetSize(UI_CONSTANTS.BUTTON_HEIGHT, UI_CONSTANTS.BUTTON_HEIGHT)
    checkbox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = UI_CONSTANTS.BORDER_SIZE,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    checkbox:SetBackdropColor(unpack(UI_CONSTANTS.BUTTON_BG_COLOR))
    local borderColor = UI_CONSTANTS.BUTTON_BORDER_COLOR()
    checkbox:SetBackdropBorderColor(borderColor[1], borderColor[2], borderColor[3], 1)
    
    -- Green tick texture
    local checkTexture = checkbox:CreateTexture(nil, "OVERLAY")
    checkTexture:SetSize(20, 20)
    checkTexture:SetPoint("CENTER")
    checkTexture:SetTexture("Interface\\BUTTONS\\UI-CheckBox-Check")
    checkTexture:SetVertexColor(0, 1, 0, 1) -- Green color
    checkbox.checkTexture = checkTexture
    
    if initialState then
        checkTexture:Show()
        checkbox:SetChecked(true)
    else
        checkTexture:Hide()
        checkbox:SetChecked(false)
    end
    
    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self.checkTexture:Show()
        else
            self.checkTexture:Hide()
        end
    end)
    
    checkbox:SetScript("OnEnter", function(self)
        local color = UI_CONSTANTS.BUTTON_BORDER_COLOR()
        self:SetBackdropBorderColor(color[1] * 1.2, color[2] * 1.2, color[3] * 1.2, 1)
    end)
    checkbox:SetScript("OnLeave", function(self)
        local color = UI_CONSTANTS.BUTTON_BORDER_COLOR()
        self:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    end)
    
    return checkbox
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_CreateCard = CreateCard
ns.UI_FormatGold = FormatGold
ns.UI_FormatMoney = FormatMoney
ns.UI_FormatMoneyCompact = FormatMoneyCompact
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_CreateSortableTableHeader = CreateSortableTableHeader
ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_CreateSearchBox = CreateSearchBox
ns.UI_GetCurrencySearchText = GetCurrencySearchText
ns.UI_RefreshColors = RefreshColors
ns.UI_CalculateThemeColors = CalculateThemeColors

-- Frame pooling exports
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow
ns.UI_AcquireCurrencyRow = AcquireCurrencyRow
ns.UI_ReleaseCurrencyRow = ReleaseCurrencyRow
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren

-- Shared widget exports
ns.UI_CreateThemedButton = CreateThemedButton
ns.UI_CreateThemedCheckbox = CreateThemedCheckbox

-- Currency transfer popup export
ns.UI_CreateCurrencyTransferPopup = CreateCurrencyTransferPopup
