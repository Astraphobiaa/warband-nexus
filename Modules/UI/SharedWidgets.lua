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

-- Get storage row from pool
local function AcquireStorageRow(parent, width)
    local row = table.remove(StorageRowPool)
    
    if not row then
        row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        row:SetBackdrop({bgFile = "Interface\\BUTTONS\\WHITE8X8"})
        
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(28, 28)
        row.icon:SetPoint("LEFT", 5, 0)
        
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        
        row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.countText:SetPoint("RIGHT", -10, 0)
        
        row.isPooled = true
    end
    
    row:SetParent(parent)
    row:SetSize(width, 36)
    row:Show()
    return row
end

-- Return storage row to pool
local function ReleaseStorageRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    table.insert(StorageRowPool, row)
end

-- Release all pooled children of a frame
local function ReleaseAllPooledChildren(parent)
    for _, child in pairs({parent:GetChildren()}) do
        if child.isPooled then
            if child.nameText and child.locationText then
                ReleaseItemRow(child)
            elseif child.countText then
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
    
    -- Expand/Collapse button
    local expandBtn = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    expandBtn:SetPoint("LEFT", 10, 0)
    expandBtn:SetText(isExpanded and "[-]" or "[+]")
    expandBtn:SetTextColor(0.4, 0.2, 0.58)
    
    local textAnchor = expandBtn
    local textOffset = 10
    
    -- Optional icon
    if iconTexture then
        local icon = header:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", expandBtn, "RIGHT", 10, 0)
        icon:SetTexture(iconTexture)
        textAnchor = icon
        textOffset = 6
    end
    
    -- Header text
    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetText(text)
    headerText:SetTextColor(1, 1, 1)
    
    -- Click handler
    header:SetScript("OnClick", function()
        onToggle(key)
    end)
    
    -- Hover effect
    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.15, 0.18, 1)
    end)
    
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.1, 0.12, 1)
    end)
    
    return header, expandBtn
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
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_CreateCard = CreateCard
ns.UI_FormatGold = FormatGold
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_DrawEmptyState = DrawEmptyState

-- Frame pooling exports
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren
