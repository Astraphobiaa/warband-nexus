--[[
    Warband Nexus - Window Factory
    
    Unified external window/dialog system with modern UI conventions.
    
    Provides:
    - Standardized dialog/popup creation
    - Duplicate prevention
    - Draggable headers
    - Click outside to close
    - ESC key to close
    - Modern styling with borders
    - Close button with icon
    
    Extracted from SharedWidgets.lua (174 lines)
    Location: Lines 2189-2362
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
-- Import dependencies from namespace
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local FontManager = ns.FontManager
local CreateIcon = ns.UI_CreateIcon

--============================================================================
-- RUNTIME DEPENDENCY VALIDATION
--============================================================================

local function ValidateDependencies()
    local missing = {}
    
    if not COLORS then table.insert(missing, "UI_COLORS") end
    if not ApplyVisuals then table.insert(missing, "UI_ApplyVisuals") end
    if not FontManager then table.insert(missing, "FontManager") end
    if not CreateIcon then table.insert(missing, "UI_CreateIcon") end
    
    if #missing > 0 then
        DebugPrint("|cffff0000[WN WindowFactory ERROR]|r Missing dependencies: " .. table.concat(missing, ", "))
        DebugPrint("|cffff0000[WN WindowFactory ERROR]|r Ensure SharedWidgets.lua loads before WindowFactory.lua in .toc")
        return false
    end
    
    return true
end

-- Defer validation to first use (allows SharedWidgets to complete loading)
-- Dependencies checked at runtime in CreateExternalWindow function

--============================================================================
-- EXTERNAL WINDOW SYSTEM
--============================================================================

---Creates a standardized external window/dialog with modern UI features
---@param config table Configuration table
---@field name string Unique dialog name (required)
---@field title string Dialog title (required)
---@field icon string Icon path/atlas (required)
---@field width number|nil Width in pixels (default 400)
---@field height number|nil Height in pixels (default 300)
---@field iconIsAtlas boolean|nil If true, icon is an atlas name (default false)
---@field onClose function|nil Callback when dialog closes
---@field preventDuplicates boolean|nil Prevent multiple instances (default true)
---@return Frame|nil dialog Main dialog frame
---@return Frame|nil contentFrame Frame where you add your content
---@return Frame|nil header Header frame (for custom additions)
local function CreateExternalWindow(config)
    -- Runtime dependency check (deferred to first use)
    if not COLORS or not ApplyVisuals or not FontManager or not CreateIcon then
        DebugPrint("|cffff0000[WN WindowFactory ERROR]|r Missing dependencies - SharedWidgets not loaded")
        return nil
    end
    
    -- Validate config
    if not config or not config.name or not config.title or not config.icon then
        error("CreateExternalWindow: name, title, and icon are required")
        return nil
    end
    
    local globalName = "WarbandNexus_" .. config.name
    local width = config.width or 400
    local height = config.height or 300
    local preventDuplicates = (config.preventDuplicates ~= false) -- default true
    
    -- Prevent duplicates
    if preventDuplicates then
        if _G[globalName] and _G[globalName]:IsShown() then
            return nil -- Already open
        end
    end
    
    -- Create dialog frame
    local dialog = CreateFrame("Frame", globalName, UIParent)
    dialog:SetSize(width, height)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(100)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(dialog, {0.05, 0.05, 0.07, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    
    -- Header bar
    local header = CreateFrame("Frame", nil, dialog)
    header:SetHeight(45)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    
    -- Apply header border
    if ApplyVisuals then
        ApplyVisuals(header, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
    end
    
    -- Make header draggable
    header:EnableMouse(true)
    header:SetMovable(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)
    
    -- Icon (support both texture and atlas)
    local iconIsAtlas = config.iconIsAtlas or false
    local iconFrame = CreateIcon(header, config.icon, 28, iconIsAtlas, nil, true)
    iconFrame:SetPoint("LEFT", 12, 0)
    iconFrame:Show()  -- CRITICAL: Show the header icon!
    
    -- Title
    local titleText = FontManager:CreateFontString(header, "title", "OVERLAY")
    titleText:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    titleText:SetText("|cffffffff" .. config.title .. "|r")
    
    -- Close button (X) - Modern styled
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply border and background to close button
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 1}, {0.5, 0.1, 0.1, 1})
    end
    
    -- Close button icon using atlas (communities-icon-redx)
    local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER", 0, 0)
    -- Use WoW's communities close button atlas
    local success = pcall(function()
        closeIcon:SetAtlas("communities-icon-redx", false)
    end)
    if not success then
        -- Fallback to X character if atlas fails
        local closeBtnText = FontManager:CreateFontString(closeBtn, "title", "OVERLAY")
        closeBtnText:SetPoint("CENTER", 0, 0)
        closeBtnText:SetText("|cffffffff×|r")  -- Multiplication sign (U+00D7)
    end
    
    -- Close function
    local function CloseDialog()
        if config.onClose then
            config.onClose()
        end
        dialog:Hide()
        dialog:SetParent(nil)
        _G[globalName] = nil
    end
    
    closeBtn:SetScript("OnClick", CloseDialog)
    
    -- Content frame (where users add their content)
    local contentFrame = CreateFrame("Frame", nil, dialog)
    contentFrame:SetPoint("TOPLEFT", 8, -53) -- Below header
    contentFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    
    -- Click outside to close (using OnUpdate to detect clicks)
    local clickOutsideFrame = CreateFrame("Frame", nil, UIParent)
    clickOutsideFrame:SetAllPoints()
    clickOutsideFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    clickOutsideFrame:SetFrameLevel(99) -- Just below dialog
    clickOutsideFrame:EnableMouse(true)
    clickOutsideFrame:SetScript("OnMouseDown", function()
        CloseDialog()
    end)
    
    -- Hide click outside frame when dialog is hidden
    dialog:SetScript("OnHide", function()
        clickOutsideFrame:Hide()
        if config.onClose then
            config.onClose()
        end
    end)
    
    dialog:SetScript("OnShow", function()
        clickOutsideFrame:Show()
    end)
    
    -- Close on Escape
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseDialog()
        end
    end)
    dialog:SetPropagateKeyboardInput(true)
    
    -- Store close function
    dialog.Close = CloseDialog
    
    return dialog, contentFrame, header
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_CreateExternalWindow = CreateExternalWindow

-- Module loaded - verbose logging removed
