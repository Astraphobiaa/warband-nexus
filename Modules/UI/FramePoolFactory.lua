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

local wipe = wipe
local tinsert = table.insert
local tremove = table.remove

--- Pack one WoW API multi-return (e.g. GetChildren) into a reused array; single API invocation.
local _poolChildScratch = {}
local function PackVariadicInto(dest, ...)
    wipe(dest)
    local n = select("#", ...)
    for i = 1, n do
        dest[i] = select(i, ...)
    end
    return n
end

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled
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

--- Iterative stack walk (avoids deep recursion); reused across subtree releases.
local _poolSubtreeStack = {}

-- True while row is queued in its pool table (not yet acquired). Prevents double-insert when
-- ReleaseAllPooledChildren runs twice on the same parent (e.g. PopulateContent + DrawCharacterList),
-- which used to duplicate pool entries and hand the same frame to two layout slots.
local function MarkRowOutOfPool(row)
    if row then row._wnInFramePool = nil end
end

--============================================================================
-- CHARACTER ROW POOLING
--============================================================================

---Get a character row from pool or create new
---@param parent Frame Parent container
---@return Frame row Pooled or new character row
local function AcquireCharacterRow(parent)
    local row = tremove(CharacterRowPool)
    if row then
        MarkRowOutOfPool(row)
    end

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
    if row._wnInFramePool then return end

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

    row._wnInFramePool = true
    tinsert(CharacterRowPool, row)
end

--- Release pooled character rows under a subtree before recycling section wrappers
--- (PopulateContent only visits direct scrollChild children; nested rows must be freed explicitly).
local function ReleaseCharacterRowsFromSubtree(root)
    if not root then return end
    local stack = _poolSubtreeStack
    wipe(stack)
    stack[1] = root
    local sp = 1
    while sp > 0 do
        local f = stack[sp]
        stack[sp] = nil
        sp = sp - 1
        if f then
            local n = PackVariadicInto(_poolChildScratch, f:GetChildren())
            for j = 1, n do
                local ch = _poolChildScratch[j]
                if ch and ch.isPooled and ch.rowType == "character" then
                    ReleaseCharacterRow(ch)
                elseif ch then
                    sp = sp + 1
                    stack[sp] = ch
                end
            end
        end
    end
end

--============================================================================
-- REPUTATION ROW POOLING
--============================================================================

---Get a reputation row from pool or create new
---Enhanced to support width/height and proper child element reset for reuse.
---Child elements are lazy-created in ReputationUI and reused across pool cycles.
---@param parent Frame Parent container
---@param width number|nil Row width (default 200)
---@param rowHeight number|nil Row height (default 26)
---@return Frame row Pooled or new reputation row
local function AcquireReputationRow(parent, width, rowHeight)
    local row = tremove(ReputationRowPool)
    if row then
        MarkRowOutOfPool(row)
    end

    if not row then
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.isPooled = true
        row.rowType = "reputation"
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- CRITICAL: Always set parent when acquiring from pool
    row:SetParent(parent)
    row:SetSize(width or 200, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    -- Reset all optional child elements from previous pool use
    -- (Children are lazy-created in CreateReputationRow, here we just hide them)
    if row.collapseBtn then row.collapseBtn:Hide() end
    if row.paragonFrame then row.paragonFrame:Hide() end
    if row.checkFrame then row.checkFrame:Hide() end
    if row.badgeText then row.badgeText:Hide() end
    if row.standingText then row.standingText:Hide() end
    if row.separator then row.separator:Hide() end
    if row.nameText then row.nameText:Hide() end
    -- Progress bar is now lazy-created inline (_progressBar table with .bg frame)
    if row._progressBar and row._progressBar.bg then row._progressBar.bg:Hide() end
    if row.progressText then row.progressText:Hide() end
    
    return row
end

---Return reputation row to pool
---Properly cleans up all child elements to prevent state leaks between reuses.
---@param row Frame Row to release
local function ReleaseReputationRow(row)
    if not row or not row.isPooled then return end
    if row._wnInFramePool then return end

    row:Hide()
    row:ClearAllPoints()
    
    -- Clear all scripts
    if row.HasScript then
        if row:HasScript("OnClick") then row:SetScript("OnClick", nil) end
        if row:HasScript("OnEnter") then row:SetScript("OnEnter", nil) end
        if row:HasScript("OnLeave") then row:SetScript("OnLeave", nil) end
        if row:HasScript("OnMouseDown") then row:SetScript("OnMouseDown", nil) end
    end
    
    -- Hide all lazy-created child elements (they'll be reused on next acquire)
    if row.collapseBtn then
        row.collapseBtn:Hide()
        if row.collapseBtn.HasScript and row.collapseBtn:HasScript("OnClick") then
            row.collapseBtn:SetScript("OnClick", nil)
        end
    end
    if row.paragonFrame then row.paragonFrame:Hide() end
    if row.checkFrame then row.checkFrame:Hide() end
    if row.badgeText then row.badgeText:Hide() end
    if row.standingText then row.standingText:Hide() end
    if row.separator then row.separator:Hide() end
    if row.nameText then row.nameText:Hide() end
    -- Progress bar is now lazy-created inline (_progressBar table with .bg frame)
    if row._progressBar and row._progressBar.bg then row._progressBar.bg:Hide() end
    if row.progressText then row.progressText:Hide() end
    
    -- Reset text content to prevent stale data showing on reuse
    if row.standingText then row.standingText:SetText("") end
    if row.nameText then row.nameText:SetText("") end
    if row.badgeText then row.badgeText:SetText("") end
    if row.progressText then row.progressText:SetText("") end

    row._wnInFramePool = true
    tinsert(ReputationRowPool, row)
end

--- Same pattern as ReleaseCharacterRowsFromSubtree for reputation rows nested under accordions.
local function ReleaseReputationRowsFromSubtree(root)
    if not root then return end
    local stack = _poolSubtreeStack
    wipe(stack)
    stack[1] = root
    local sp = 1
    while sp > 0 do
        local f = stack[sp]
        stack[sp] = nil
        sp = sp - 1
        if f then
            local n = PackVariadicInto(_poolChildScratch, f:GetChildren())
            for j = 1, n do
                local ch = _poolChildScratch[j]
                if ch and ch.isPooled and ch.rowType == "reputation" then
                    ReleaseReputationRow(ch)
                elseif ch then
                    sp = sp + 1
                    stack[sp] = ch
                end
            end
        end
    end
end

--============================================================================
-- PROFESSION ROW POOLING
--============================================================================

---Get a profession row from pool or create new
---@param parent Frame Parent container
---@return Frame row Pooled or new profession row
local function AcquireProfessionRow(parent)
    local row = tremove(ProfessionRowPool)
    if row then
        MarkRowOutOfPool(row)
    end
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
---Resets scripts and hides lazy-created concentration bars to prevent stale visuals on reuse.
---@param row Frame Row to release
local function ReleaseProfessionRow(row)
    if not row or not row.isPooled then return end
    if row._wnInFramePool then return end
    row:Hide()
    row:ClearAllPoints()
    if row.HasScript and row:HasScript("OnClick") then row:SetScript("OnClick", nil) end
    if row.HasScript and row:HasScript("OnEnter") then row:SetScript("OnEnter", nil) end
    if row.HasScript and row:HasScript("OnLeave") then row:SetScript("OnLeave", nil) end

    -- Reset concentration bars and hit-frames from previous use
    local lineKeys = {"l1", "l2"}
    for lk = 1, #lineKeys do
        local lineKey = lineKeys[lk]
        if row[lineKey .. "ConcBar"] then row[lineKey .. "ConcBar"]:Hide() end
        if row[lineKey .. "SkillHit"] then row[lineKey .. "SkillHit"]:Hide() end
        if row[lineKey .. "KnowWarn"] then row[lineKey .. "KnowWarn"]:Hide() end
        if row[lineKey .. "Btn"] then row[lineKey .. "Btn"]:Hide() end
        if row[lineKey .. "InfoBtn"] then row[lineKey .. "InfoBtn"]:Hide() end
        if row[lineKey .. "Icon"] then
            row[lineKey .. "Icon"]:Hide()
            if row[lineKey .. "Icon"].knowledgeBadge then row[lineKey .. "Icon"].knowledgeBadge:Hide() end
            row[lineKey .. "Icon"]:SetScript("OnEnter", nil)
            row[lineKey .. "Icon"]:SetScript("OnLeave", nil)
        end
    end

    row._wnInFramePool = true
    tinsert(ProfessionRowPool, row)
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
    local row = tremove(CurrencyRowPool)
    if row then
        MarkRowOutOfPool(row)
    end

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
    if row._wnInFramePool then return end

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

    row._wnInFramePool = true
    tinsert(CurrencyRowPool, row)
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
    local row = tremove(ItemRowPool)
    if row then
        MarkRowOutOfPool(row)
    end

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
    if row._wnInFramePool then return end

    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    
    -- Phase 2.5: Clear stale state on release
    if row.icon then row.icon:SetTexture(nil) end
    if row.nameText then row.nameText:SetText("") end
    if row.qtyText then row.qtyText:SetText("") end
    if row.locationText then row.locationText:SetText("") end

    row._wnInFramePool = true
    tinsert(ItemRowPool, row)
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
    local row = tremove(StorageRowPool)
    if row then
        MarkRowOutOfPool(row)
    end

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
    if row._wnInFramePool then return end

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

    row._wnInFramePool = true
    tinsert(StorageRowPool, row)
end

--============================================================================
-- GENERIC POOL CLEANUP
--============================================================================

---Release all pooled children of a frame (and hide non-pooled ones)
---@param parent Frame Parent container to clean up
local function ReleaseAllPooledChildren(parent)
    local n = PackVariadicInto(_poolChildScratch, parent:GetChildren())
    for i = 1, n do
        local child = _poolChildScratch[i]
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
                -- Only clear scripts that the widget actually supports
                if child:HasScript("OnClick") then
                    local success = pcall(function() child:SetScript("OnClick", nil) end)
                    if not success and IsDebugModeEnabled and IsDebugModeEnabled() then
                        local childType = child:GetObjectType()
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
ns.UI_ReleaseCharacterRowsFromSubtree = ReleaseCharacterRowsFromSubtree
ns.UI_ReleaseReputationRow = ReleaseReputationRow
ns.UI_ReleaseReputationRowsFromSubtree = ReleaseReputationRowsFromSubtree
ns.UI_ReleaseProfessionRow = ReleaseProfessionRow
ns.UI_ReleaseCurrencyRow = ReleaseCurrencyRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow

-- Export generic cleanup
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren

-- Module loaded - verbose logging removed
