--[[
    Warband Nexus - Frame Pooling System
    
    Performance optimization system that reuses UI frames instead of creating new ones
    on every refresh. Dramatically reduces memory churn and GC pressure.
    
    Provides pooling for:
    - Character rows (CharactersUI)
    - Reputation rows (ReputationUI)
    - Currency rows (CurrencyUI)
    - Item rows (ItemsUI)
    - Storage rows (StorageUI)
    
    Extracted from SharedWidgets.lua (428 lines)
    Location: Lines 1089-1517
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
-- Import dependencies
local UI_LAYOUT = ns.UI_LAYOUT
local FontManager = ns.FontManager

--============================================================================
-- FRAME POOL STORAGE
--============================================================================

local ItemRowPool = {}
local StorageRowPool = {}
local CurrencyRowPool = {}
local CharacterRowPool = {}
local ReputationRowPool = {}
local ProfessionRowPool = {}

--============================================================================
-- CHARACTER ROW POOLING
--============================================================================

---Get a character row from pool or create new
---@param parent Frame Parent container
---@return Frame row Pooled or new character row
local function AcquireCharacterRow(parent)
    local row = table.remove(CharacterRowPool)
    
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "character"
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    row:SetParent(parent)
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

---Return character row to pool
---@param row Frame Row to release
local function ReleaseCharacterRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    
    -- Note: Child elements (favButton, etc.) are kept and reused
    
    table.insert(CharacterRowPool, row)
end

--============================================================================
-- REPUTATION ROW POOLING
--============================================================================

---Get a reputation row from pool or create new
---@param parent Frame Parent container
---@return Frame row Pooled or new reputation row
local function AcquireReputationRow(parent)
    local row = table.remove(ReputationRowPool)
    
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "reputation"
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    row:SetParent(parent)
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

---Return reputation row to pool
---@param row Frame Row to release
local function ReleaseReputationRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    
    table.insert(ReputationRowPool, row)
end

--============================================================================
-- PROFESSION ROW POOLING
--============================================================================

---Get a profession row from pool or create new
---@param parent Frame Parent container
---@return Frame row Pooled or new profession row
local function AcquireProfessionRow(parent)
    local row = table.remove(ProfessionRowPool)
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "profession"
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    row:SetParent(parent)
    row:Show()
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    return row
end

---Return profession row to pool
---@param row Frame Row to release
local function ReleaseProfessionRow(row)
    if not row or not row.isPooled then return end
    row:Hide()
    row:ClearAllPoints()
    if row.HasScript and row:HasScript("OnClick") then row:SetScript("OnClick", nil) end
    if row.HasScript and row:HasScript("OnEnter") then row:SetScript("OnEnter", nil) end
    if row.HasScript and row:HasScript("OnLeave") then row:SetScript("OnLeave", nil) end
    table.insert(ProfessionRowPool, row)
end

--============================================================================
-- CURRENCY ROW POOLING
--============================================================================

---Get a currency row from pool or create new
---@param parent Frame Parent container
---@param width number Row width
---@param rowHeight number|nil Row height (default 26)
---@return Frame row Pooled or new currency row
local function AcquireCurrencyRow(parent, width, rowHeight)
    local row = table.remove(CurrencyRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- No background
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.ROW_ICON_SIZE
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 15, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.nameText:SetPoint("LEFT", 43, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Amount text
        row.amountText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.amountText:SetPoint("RIGHT", -10, 0)
        row.amountText:SetWidth(150)
        row.amountText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "currency"  -- Mark as CurrencyRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- CRITICAL: Always set parent when acquiring from pool
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

---Return currency row to pool
---@param row Frame Row to release
local function ReleaseCurrencyRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    
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
    
    -- Reset badge text (for Show All mode)
    if row.badgeText then
        row.badgeText:SetText("")
        row.badgeText:Hide()
    end
    
    -- Reset background removed (no backdrop)
    
    table.insert(CurrencyRowPool, row)
end

--============================================================================
-- ITEM ROW POOLING
--============================================================================

---Get an item row from pool or create new
---@param parent Frame Parent container
---@param width number Row width
---@param rowHeight number Row height
---@return Frame row Pooled or new item row
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
        -- Anti-flicker optimization
        row.bg:SetSnapToPixelGrid(false)
        row.bg:SetTexelSnappingBias(0)
        
        -- Quantity text (left)
        row.qtyText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.ROW_ICON_SIZE
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 70, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(80)
        row.locationText:SetJustifyH("RIGHT")

        row.isPooled = true
        row.rowType = "item"  -- Mark as ItemRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- No border for items rows
    row:SetParent(parent)
    row:SetSize(width, rowHeight)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

---Return item row to pool
---@param row Frame Row to release
local function ReleaseItemRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    
    -- Phase 2.5: Clear stale state on release
    if row.icon then row.icon:SetTexture(nil) end
    if row.nameText then row.nameText:SetText("") end
    if row.qtyText then row.qtyText:SetText("") end
    if row.locationText then row.locationText:SetText("") end
    
    table.insert(ItemRowPool, row)
end

--============================================================================
-- STORAGE ROW POOLING
--============================================================================

---Get storage row from pool (updated to match Items tab style)
---@param parent Frame Parent container
---@param width number Row width
---@param rowHeight number|nil Row height (default 26)
---@return Frame row Pooled or new storage row
local function AcquireStorageRow(parent, width, rowHeight)
    local row = table.remove(StorageRowPool)
    
    if not row then
        -- Create new button with all children (Button for hover effects)
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture removed (naked frame)
        
        -- Quantity text (left)
        row.qtyText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.ROW_ICON_SIZE
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 70, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(80)
        row.locationText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "storage"  -- Mark as StorageRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- No border for storage rows
    
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

---Return storage row to pool
---@param row Frame Row to release
local function ReleaseStorageRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    
    -- Phase 2.5: Clear stale state on release
    if row.icon then row.icon:SetTexture(nil) end
    if row.nameText then row.nameText:SetText("") end
    if row.qtyText then row.qtyText:SetText("") end
    if row.locationText then row.locationText:SetText("") end
    
    table.insert(StorageRowPool, row)
end

--============================================================================
-- GENERIC POOL CLEANUP
--============================================================================

---Release all pooled children of a frame (and hide non-pooled ones)
---@param parent Frame Parent container to clean up
local function ReleaseAllPooledChildren(parent)
    local children = {parent:GetChildren()}  -- Reuse table, don't create new one each iteration
    for i, child in pairs(children) do
        if child.isPooled and child.rowType then
            -- Use rowType to determine which pool to release to
            if child.rowType == "item" then
                ReleaseItemRow(child)
            elseif child.rowType == "storage" then
                ReleaseStorageRow(child)
            elseif child.rowType == "currency" then
                ReleaseCurrencyRow(child)
            elseif child.rowType == "character" then
                ReleaseCharacterRow(child)
            elseif child.rowType == "reputation" then
                ReleaseReputationRow(child)
            elseif child.rowType == "profession" then
                ReleaseProfessionRow(child)
            end
        else
            -- Non-pooled frame (like headers, cards, etc.)
            -- Skip persistent row elements (reorderButtons, deleteBtn, etc.)
            -- These are managed by their parent row and should not be hidden here
            -- ALSO skip emptyStateContainer - it's managed by DrawEmptyState
            if not child.isPersistentRowElement and child ~= parent.emptyStateContainer then
                pcall(function()
                    child:Hide()
                    child:ClearAllPoints()
                end)
            end
            
            -- Clear scripts only for widgets that support them
            -- Use HasScript to check if the widget actually supports the script type
            if child.SetScript and child.HasScript then
                local childType = child:GetObjectType()
                -- Only clear scripts that the widget actually supports
                if child:HasScript("OnClick") then
                    local success = pcall(function() child:SetScript("OnClick", nil) end)
                    if not success then
                        DebugPrint("|cffff0000WN DEBUG: Failed to clear OnClick on", childType, "at index", i, "|r")
                    end
                end
                if child:HasScript("OnEnter") then
                    pcall(function() child:SetScript("OnEnter", nil) end)
                end
                if child:HasScript("OnLeave") then
                    pcall(function() child:SetScript("OnLeave", nil) end)
                end
                if child:HasScript("OnMouseDown") then
                    pcall(function() child:SetScript("OnMouseDown", nil) end)
                end
                if child:HasScript("OnMouseUp") then
                    pcall(function() child:SetScript("OnMouseUp", nil) end)
                end
            end
        end
    end
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export Acquire functions
ns.UI_AcquireCharacterRow = AcquireCharacterRow
ns.UI_AcquireReputationRow = AcquireReputationRow
ns.UI_AcquireProfessionRow = AcquireProfessionRow
ns.UI_AcquireCurrencyRow = AcquireCurrencyRow
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow

-- Export Release functions
ns.UI_ReleaseCharacterRow = ReleaseCharacterRow
ns.UI_ReleaseReputationRow = ReleaseReputationRow
ns.UI_ReleaseProfessionRow = ReleaseProfessionRow
ns.UI_ReleaseCurrencyRow = ReleaseCurrencyRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow

-- Export generic cleanup
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren

-- Module loaded - verbose logging removed
