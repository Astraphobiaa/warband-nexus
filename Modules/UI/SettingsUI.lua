--[[
    Warband Nexus - Settings UI
    Standardized grid-based settings with event-driven architecture
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager

-- LibDBIcon reference for minimap lock
local LDBI = LibStub("LibDBIcon-1.0", true)

-- Import SharedWidgets
local COLORS = ns.UI_COLORS or {accent = {0.40, 0.20, 0.58, 1}, accentDark = {0.28, 0.14, 0.41, 1}, border = {0.20, 0.20, 0.25, 1}, bg = {0.06, 0.06, 0.08, 0.98}, bgCard = {0.08, 0.08, 0.10, 1}, textBright = {1,1,1,1}, textNormal = {0.85,0.85,0.85,1}, textDim = {0.55,0.55,0.55,1}, white = {1,1,1,1}}
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateSection = ns.UI_CreateSection

--============================================================================
-- CONSTANTS
--============================================================================

-- Import UI spacing constants
local UI_SPACING = ns.UI_SPACING or {
    TOP_MARGIN = 8,
    SECTION_SPACING = 8,
    SIDE_MARGIN = 10,
    MIN_BOTTOM_SPACING = 20,
    AFTER_ELEMENT = 8,
}

local MIN_ITEM_WIDTH = 180  -- Minimum width for grid items
local GRID_SPACING = UI_SPACING.SIDE_MARGIN  -- Horizontal spacing between grid items
local ROW_HEIGHT = 32       -- Height per grid row (settings rows are intentionally larger)
local SECTION_SPACING = UI_SPACING.SECTION_SPACING  -- Spacing between sections
local CONTENT_PADDING_TOP = 40  -- Title height (from CreateSection standard, settings-specific)
local CONTENT_PADDING_BOTTOM = UI_SPACING.MIN_BOTTOM_SPACING  -- Bottom padding within section

--============================================================================
-- GRID LAYOUT SYSTEM
--============================================================================

---Apply disabled visual state to a checkbox + label pair
---@param checkbox CheckButton The checkbox widget
---@param label FontString The label widget
---@param disabled boolean Whether to disable (true) or enable (false)
local function SetCheckboxDisabled(checkbox, label, disabled)
    if disabled then
        checkbox:Disable()
        checkbox:SetAlpha(0.35)
        label:SetTextColor(0.4, 0.4, 0.4, 0.6)
    else
        checkbox:Enable()
        checkbox:SetAlpha(1.0)
        label:SetTextColor(1, 1, 1, 1)
    end
end

---Create grid-based checkbox layout (RESPONSIVE - auto-adjusts columns)
---Supports hierarchical parent-child dependencies via option.parentKey.
---When a parent checkbox is unchecked, all descendants are recursively
---disabled and non-clickable. Supports multi-level chains (e.g. A → B → C).
---@param parent Frame Parent container
---@param options table Array of {key, label, tooltip, get, set, parentKey?}
---@param yOffset number Starting Y offset
---@param explicitWidth number Optional explicit width (bypasses GetWidth)
---@return number newYOffset, table widgets (keyed by option.key → {checkbox, label})
local function CreateCheckboxGrid(parent, options, yOffset, explicitWidth)
    -- Calculate dynamic columns based on parent width
    local containerWidth = explicitWidth or parent:GetWidth() or 620
    -- Single option → always full width (prevents label truncation for long labels)
    local minCols = (#options <= 1) and 1 or 2
    local itemsPerRow = math.max(minCols, math.floor((containerWidth + GRID_SPACING) / (MIN_ITEM_WIDTH + GRID_SPACING)))
    local itemWidth = (containerWidth - (GRID_SPACING * (itemsPerRow - 1))) / itemsPerRow
    
    local row = 0
    local col = 0
    local widgets = {}       -- key → {checkbox, label}
    local childKeys = {}     -- parentKey → {childKey1, childKey2, ...}
    local parentKeyMap = {}  -- childKey → parentKey
    
    for i, option in ipairs(options) do
        -- Create checkbox
        local checkbox = CreateThemedCheckbox(parent)
        checkbox:SetSize(24, 24)
        
        -- Position in grid
        local xPos = col * (itemWidth + GRID_SPACING)
        checkbox:SetPoint("TOPLEFT", xPos, yOffset + (row * -ROW_HEIGHT))
        
        -- Set initial value
        if option.get then
            checkbox:SetChecked(option.get())
            if checkbox.checkTexture then
                checkbox.checkTexture:SetShown(option.get())
            end
        end
        
        -- Label (to the right of checkbox)
        local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
        label:SetPoint("LEFT", checkbox, "RIGHT", UI_SPACING.AFTER_ELEMENT, 0)
        label:SetWidth(itemWidth - 32)  -- Subtract checkbox + spacing
        label:SetJustifyH("LEFT")
        label:SetText(option.label)
        label:SetTextColor(1, 1, 1, 1)
        
        -- Store widget reference
        if option.key then
            widgets[option.key] = { checkbox = checkbox, label = label }
        end
        
        -- Build dependency tree
        if option.parentKey and option.key then
            parentKeyMap[option.key] = option.parentKey
            childKeys[option.parentKey] = childKeys[option.parentKey] or {}
            table.insert(childKeys[option.parentKey], option.key)
        end
        
        -- Tooltip on hover
        if option.tooltip then
            checkbox:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(option.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)
            
            label:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(option.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            label:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        
        -- Move to next grid position
        col = col + 1
        if col >= itemsPerRow then
            col = 0
            row = row + 1
        end
    end
    
    -- Check if a key has any ancestor that is unchecked (recursive)
    local function IsAnyAncestorUnchecked(key)
        local pKey = parentKeyMap[key]
        if not pKey or not widgets[pKey] then return false end
        if not widgets[pKey].checkbox:GetChecked() then return true end
        return IsAnyAncestorUnchecked(pKey)
    end
    
    -- Recursively cascade enable/disable to all descendants of a key
    local function CascadeDescendants(key, forceDisable)
        local kids = childKeys[key]
        if not kids then return end
        for _, childKey in ipairs(kids) do
            local w = widgets[childKey]
            if w then
                if forceDisable then
                    -- Parent chain is broken → disable regardless of own state
                    SetCheckboxDisabled(w.checkbox, w.label, true)
                    CascadeDescendants(childKey, true)
                else
                    -- Parent chain is active → enable this child
                    SetCheckboxDisabled(w.checkbox, w.label, false)
                    -- Continue cascade: grandchildren depend on whether THIS child is checked
                    local childUnchecked = not w.checkbox:GetChecked()
                    CascadeDescendants(childKey, childUnchecked)
                end
            end
        end
    end
    
    -- Set OnClick handlers (needs CascadeDescendants to be defined)
    for i, option in ipairs(options) do
        if option.key and widgets[option.key] then
            local cb = widgets[option.key].checkbox
            cb:SetScript("OnClick", function(self)
                local isChecked = self:GetChecked()
                if option.set then
                    option.set(isChecked)
                end
                
                if self.checkTexture then
                    self.checkTexture:SetShown(isChecked)
                end
                
                -- Recursive cascade to all descendants
                if option.key then
                    CascadeDescendants(option.key, not isChecked)
                end
                
                -- Notify external dependents (sliders, buttons, etc.)
                if widgets._onParentToggle then
                    widgets._onParentToggle(option.key, isChecked)
                end
            end)
        end
    end
    
    -- Apply initial disabled state: walk the tree top-down
    -- Process root options first, then cascade
    for _, option in ipairs(options) do
        if option.key and not option.parentKey then
            -- Root node: cascade if unchecked
            if not widgets[option.key].checkbox:GetChecked() then
                CascadeDescendants(option.key, true)
            else
                CascadeDescendants(option.key, false)
            end
        end
    end
    -- Also handle children whose parent is in the same grid but not a root
    -- (already handled by recursive cascade from roots above)
    
    -- Calculate total height used
    local totalRows = math.ceil(#options / itemsPerRow)
    return yOffset - (totalRows * ROW_HEIGHT) - 15, widgets  -- Reduced spacing
end

---Create button grid (RESPONSIVE - auto-adjusts columns)
---@param parent Frame Parent container
---@param buttons table Array of {label, tooltip, func, color (optional {r,g,b})}
---@param yOffset number Starting Y offset
---@param explicitWidth number Optional explicit width
---@param minButtonWidth number Optional minimum button width (default: MIN_ITEM_WIDTH)
---@return number New Y offset after grid
local function CreateButtonGrid(parent, buttons, yOffset, explicitWidth, minButtonWidth)
    -- Calculate dynamic columns
    local containerWidth = explicitWidth or parent:GetWidth() or 620
    local minWidth = minButtonWidth or MIN_ITEM_WIDTH  -- Use custom min width if provided
    local itemsPerRow = math.max(2, math.floor((containerWidth + GRID_SPACING) / (minWidth + GRID_SPACING)))
    local buttonWidth = (containerWidth - (GRID_SPACING * (itemsPerRow - 1))) / itemsPerRow
    local buttonHeight = 36
    
    local row = 0
    local col = 0
    
    for i, btnData in ipairs(buttons) do
        -- Create button
        local button = ns.UI.Factory:CreateButton(parent)
        button:SetSize(buttonWidth, buttonHeight)
        
        -- Position in grid
        local xPos = col * (buttonWidth + GRID_SPACING)
        button:SetPoint("TOPLEFT", xPos, yOffset + (row * -(buttonHeight + UI_SPACING.AFTER_ELEMENT)))
        button:Enable()
        
        -- Use button's own color if provided, otherwise use theme accent
        local btnColor = btnData.color or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]}
        
        if ApplyVisuals then
            ApplyVisuals(button, {0.08, 0.08, 0.10, 1}, {btnColor[1], btnColor[2], btnColor[3], 0.8})
        end
        
        -- Button text
        local buttonText = FontManager:CreateFontString(button, "body", "OVERLAY")
        buttonText:SetPoint("CENTER")
        buttonText:SetText(btnData.label)
        buttonText:SetTextColor(btnColor[1], btnColor[2], btnColor[3])
        
        -- OnClick
        button:SetScript("OnClick", function()
            if btnData.func then
                btnData.func()
            end
        end)
        
        -- Hover effects
        button:SetScript("OnEnter", function(self)
            if ApplyVisuals then
                ApplyVisuals(button, {0.12, 0.12, 0.14, 1}, {btnColor[1], btnColor[2], btnColor[3], 1})
            end
            buttonText:SetTextColor(1, 1, 1)
            
            if btnData.tooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(btnData.tooltip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        
        button:SetScript("OnLeave", function(self)
            if ApplyVisuals then
                ApplyVisuals(button, {0.08, 0.08, 0.10, 1}, {btnColor[1], btnColor[2], btnColor[3], 0.8})
            end
            buttonText:SetTextColor(btnColor[1], btnColor[2], btnColor[3])
            GameTooltip:Hide()
        end)
        
        -- Move to next grid position
        col = col + 1
        if col >= itemsPerRow then
            col = 0
            row = row + 1
        end
    end
    
    -- Calculate total height used
    local totalRows = math.ceil(#buttons / itemsPerRow)
    return yOffset - (totalRows * (buttonHeight + UI_SPACING.AFTER_ELEMENT)) - 15
end

--============================================================================
-- WIDGET BUILDERS
--============================================================================

---Create dropdown widget
local function CreateDropdownWidget(parent, option, yOffset)
    -- Label
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    local optionName = type(option.name) == "function" and option.name() or option.name
    label:SetText(optionName)
    label:SetTextColor(1, 1, 1, 1)
    
    -- Tooltip
    if option.desc then
        label:SetScript("OnEnter", function(self)
            local desc = type(option.desc) == "function" and option.desc() or option.desc
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(desc, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    -- Dropdown button
    local dropdown = ns.UI.Factory:CreateButton(parent)
    dropdown:SetHeight(32)
    dropdown:SetPoint("TOPLEFT", 0, yOffset - 25)
    dropdown:SetPoint("TOPRIGHT", 0, yOffset - 25)
    
    if ApplyVisuals then
        ApplyVisuals(dropdown, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    -- Current value text (use GameFontNormal so font name doesn't disappear when addon font changes)
    local valueText = dropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    valueText:SetPoint("LEFT", 12, 0)
    valueText:SetPoint("RIGHT", -32, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetTextColor(1, 1, 1, 1)
    
    -- Arrow icon
    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -12, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetTexCoord(0, 1, 0, 1)
    
    -- Get values function
    local function GetValues()
        if not option.values then return nil end
        return type(option.values) == "function" and option.values() or option.values
    end
    
    -- Update display (resilient: fallback so font names don't disappear after refresh)
    local function UpdateDisplay()
        local values = GetValues()
        if not values then
            valueText:SetText((ns.L and ns.L["NO_OPTIONS"]) or "No Options")
            return
        end
        
        if option.get then
            local currentValue = option.get()
            local display = (currentValue and values[currentValue])
                or (currentValue and type(currentValue) == "string" and currentValue:match("[^\\/]+$"))  -- filename from path
                or (currentValue and tostring(currentValue))
                or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            valueText:SetText(display)
        else
            valueText:SetText((ns.L and ns.L["NONE_LABEL"]) or "None")
        end
    end
    
    UpdateDisplay()
    
    -- Dropdown menu
    local activeMenu = nil
    
    dropdown:SetScript("OnClick", function(self)
        local values = GetValues()
        if not values then return end
        
        -- Toggle
        if activeMenu and activeMenu:IsShown() then
            activeMenu:Hide()
            activeMenu = nil
            return
        end
        
        if activeMenu then
            activeMenu:Hide()
            activeMenu = nil
        end
        
        -- Count items
        local itemCount = 0
        for _ in pairs(values) do
            itemCount = itemCount + 1
        end
        
        local contentHeight = math.min(itemCount * 26, 300)
        local menuWidth = dropdown:GetWidth()
        
        -- Sort options first (needed for sizing)
        local sortedOptions = {}
        for value, displayText in pairs(values) do
            table.insert(sortedOptions, {value = value, text = displayText})
        end
        table.sort(sortedOptions, function(a, b) return a.text < b.text end)
        
        local itemHeight = 28
        local menuPad = 6
        local scrollBarW = 22
        local contentHeight = math.min(#sortedOptions * itemHeight, 300)
        local needsScroll = (#sortedOptions * itemHeight) > 300
        local menuWidth = dropdown:GetWidth()
        
        -- Reuse existing menu if available
        local menu = dropdown._dropdownMenu
        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            if ApplyVisuals then
                ApplyVisuals(menu, {0.06, 0.06, 0.08, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
            end
            dropdown._dropdownMenu = menu
        end
        
        -- Update menu size and position
        menu:SetSize(menuWidth, contentHeight + menuPad * 2)
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        
        -- Clear existing children (scrollFrame and buttons)
        local children = { menu:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide()
            child:SetParent(nil)
        end
        
        activeMenu = menu
        
        -- ScrollFrame (leave space for scroll bar only if content overflows)
        local rightInset = needsScroll and scrollBarW or menuPad
        local scrollFrame = ns.UI.Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", menuPad, -menuPad)
        scrollFrame:SetPoint("BOTTOMRIGHT", -rightInset, menuPad)
        scrollFrame:EnableMouseWheel(true)
        
        local btnWidth = menuWidth - menuPad - rightInset
        
        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(btnWidth)
        scrollChild:SetHeight(#sortedOptions * itemHeight)
        scrollFrame:SetScrollChild(scrollChild)
        
        -- Update scroll bar visibility
        if ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
        end
        
        -- Create option buttons (standardized: ApplyVisuals, consistent height, highlight current)
        local currentValue = option.get and option.get()
        local yPos = 0
        for _, data in ipairs(sortedOptions) do
            local btn = CreateFrame("Button", nil, scrollChild, "BackdropTemplate")
            btn:SetSize(btnWidth, itemHeight)
            btn:SetPoint("TOPLEFT", 0, -yPos)
            
            local isCurrent = (currentValue == data.value)
            local bgColor = isCurrent and {0.12, 0.12, 0.16, 1} or {0.07, 0.07, 0.09, 1}
            local borderColor = isCurrent and {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8} or {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4}
            
            if ApplyVisuals then
                ApplyVisuals(btn, bgColor, borderColor)
            end
            
            -- Use GameFontNormal so font preview doesn't break when addon font changes
            local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btnText:SetPoint("LEFT", 10, 0)
            btnText:SetPoint("RIGHT", -10, 0)
            btnText:SetJustifyH("LEFT")
            btnText:SetText(data.text)
            
            if isCurrent then
                btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            else
                btnText:SetTextColor(0.9, 0.9, 0.9)
            end
            
            -- Hover
            btn:SetScript("OnEnter", function(self)
                if self.SetBackdropColor then self:SetBackdropColor(0.15, 0.15, 0.18, 1) end
                if ns.UI_UpdateBorderColor then ns.UI_UpdateBorderColor(self, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9}) end
            end)
            btn:SetScript("OnLeave", function(self)
                if self.SetBackdropColor then self:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4]) end
                if ns.UI_UpdateBorderColor then ns.UI_UpdateBorderColor(self, borderColor) end
            end)
            
            btn:SetScript("OnClick", function()
                if option.set then
                    option.set(nil, data.value)
                    UpdateDisplay()
                end
                menu:Hide()
                activeMenu = nil
            end)
            
            yPos = yPos + itemHeight
        end
        
        menu:Show()
        
        -- Close on ESC
        menu:SetPropagateKeyboardInput(false)
        menu:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if dropdown._clickCatcher then
                    dropdown._clickCatcher:Hide()
                    dropdown._clickCatcher = nil
                end
                self:Hide()
                activeMenu = nil
            end
        end)
        
        -- Phase 4.5: Replace OnUpdate polling with click-catcher frame
        -- Create click-catcher (full-screen invisible frame)
        local clickCatcher = dropdown._clickCatcher
        if not clickCatcher then
            clickCatcher = CreateFrame("Frame", nil, UIParent)
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(menu:GetFrameLevel() - 1)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                menu:Hide()
                activeMenu = nil
                clickCatcher:Hide()
            end)
            dropdown._clickCatcher = clickCatcher
        end
        
        -- Show click-catcher when menu is shown
        clickCatcher:Show()
        
        -- Ensure click-catcher is hidden when menu is hidden
        local originalOnHide = menu:GetScript("OnHide")
        menu:SetScript("OnHide", function(self)
            if clickCatcher then
                clickCatcher:Hide()
            end
            if originalOnHide then
                originalOnHide(self)
            end
        end)
    end)
    
    return yOffset - 75
end

---Create slider widget
---@param parent Frame Parent container
---@param option table Slider option config
---@param yOffset number Starting Y offset
---@param sliderTrackingTable table Optional table to track slider for theme refresh
---@return number New Y offset
local function CreateSliderWidget(parent, option, yOffset, sliderTrackingTable)
    -- Label with value
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    label:SetTextColor(1, 1, 1, 1)
    
    local optionName = type(option.name) == "function" and option.name() or option.name
    local function UpdateLabel()
        local currentValue = option.get and option.get() or (option.min or 0)
        local displayValue = (option.valueFormat and option.valueFormat(currentValue)) or string.format("%.1f", currentValue)
        label:SetText(string.format("%s: |cff00ccff%s|r", optionName, displayValue))
    end
    
    UpdateLabel()
    
    -- Slider
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetHeight(20)
    slider:SetPoint("TOPLEFT", 0, yOffset - 25)
    slider:SetPoint("TOPRIGHT", 0, yOffset - 25)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(option.min or 0, option.max or 1)
    slider:SetValueStep(option.step or 0.1)
    
    -- Backdrop with border (more visible)
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        tileSize = 1,
        edgeSize = 2,
        insets = { left = 1, right = 1, top = 1, bottom = 1 }
    })
    slider:SetBackdropColor(0.1, 0.1, 0.12, 1)
    slider:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)  -- Accent color border
    
    -- Thumb (smaller, fits within bar)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 18)  -- Smaller thumb (was 16x24)
    thumb:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    slider:SetThumbTexture(thumb)
    
    -- Track slider for theme refresh (if tracking table provided)
    if sliderTrackingTable then
        table.insert(sliderTrackingTable, slider)
    end
    
    -- Set value
    if option.get then
        slider:SetValue(option.get())
    end
    
    -- OnValueChanged
    slider:SetScript("OnValueChanged", function(self, value)
        -- Round to step precision
        local step = option.step or 0.1
        value = math.floor(value / step + 0.5) * step
        
        if math.abs(self:GetValue() - value) > 0.001 then
            self:SetValue(value)
            return
        end
        
        if option.set then
            option.set(nil, value)  -- AceConfig pattern: (info, value)
            UpdateLabel()
        end
    end)
    
    -- Tooltip
    if option.desc then
        slider:SetScript("OnEnter", function(self)
            local desc = type(option.desc) == "function" and option.desc() or option.desc
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(desc, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    
    return yOffset - 65
end

--============================================================================
-- SECTION BUILDERS
--============================================================================

-- Track subtitle elements for theme refresh
local subtitleElements = {}
local sliderElements = {}

-- Helper: Refresh subtitle colors after theme change
local function RefreshSubtitles()
    for _, subtitle in ipairs(subtitleElements) do
        if subtitle and subtitle:IsShown() then
            subtitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        end
    end
    for _, slider in ipairs(sliderElements) do
        if slider and slider:IsShown() then
            local thumb = slider:GetThumbTexture()
            if thumb then
                thumb:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            end
            if slider.SetBackdropBorderColor then
                -- Border also uses accent color
                slider:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            end
        end
    end
end

local function BuildSettings(parent, containerWidth)
    -- Clear existing
    for _, child in pairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Clear tracking tables
    wipe(subtitleElements)
    wipe(sliderElements)
    
    -- Ensure we have a valid width
    local effectiveWidth = containerWidth or parent:GetWidth() or 620
    
    local yOffset = 0  -- Start at 0, sections handle their own top spacing
    
    --========================================================================
    -- GENERAL SETTINGS
    --========================================================================
    
    local generalSection = CreateSection(parent, (ns.L and ns.L["GENERAL_SETTINGS"]) or "General Settings", effectiveWidth)
    generalSection:SetPoint("TOPLEFT", 0, yOffset)
    generalSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- General options grid
    local generalOptions = {
        {
            key = "showItemCount",
            label = (ns.L and ns.L["SHOW_ITEM_COUNT"]) or "Show Item Count",
            tooltip = (ns.L and ns.L["SHOW_ITEM_COUNT_TOOLTIP"]) or "Display stack counts on items in storage view",
            get = function() return WarbandNexus.db.profile.showItemCount end,
            set = function(value) WarbandNexus.db.profile.showItemCount = value end,
        },
        {
            key = "showWeeklyPlanner",
            label = (ns.L and ns.L["SHOW_WEEKLY_PLANNER"]) or "Weekly Planner (Characters)",
            tooltip = (ns.L and ns.L["SHOW_WEEKLY_PLANNER_TOOLTIP"]) or "Show or hide the Weekly Planner section inside the Characters tab",
            get = function() return WarbandNexus.db.profile.showWeeklyPlanner end,
            set = function(value)
                WarbandNexus.db.profile.showWeeklyPlanner = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end,
        },
        {
            key = "minimapLock",
            label = (ns.L and ns.L["LOCK_MINIMAP_ICON"]) or "Lock Minimap Button",
            tooltip = (ns.L and ns.L["LOCK_MINIMAP_TOOLTIP"]) or "Lock the minimap button in place so it cannot be dragged",
            get = function() return WarbandNexus.db.profile.minimap.lock end,
            set = function(value)
                WarbandNexus.db.profile.minimap.lock = value
                -- Apply lock immediately via LDBI (only lock dragging, keep clicks enabled)
                if LDBI then
                    local button = LDBI:GetMinimapButton(ADDON_NAME)
                    if button then
                        if value then
                            -- Lock position (disable dragging only)
                            button:SetMovable(false)
                            button:RegisterForDrag()  -- Clear drag registration
                        else
                            -- Unlock position (enable dragging)
                            button:SetMovable(true)
                            button:RegisterForDrag("LeftButton")
                        end
                    end
                end
            end,
        },
    }
    
    local generalGridYOffset = CreateCheckboxGrid(generalSection.content, generalOptions, 0, effectiveWidth - 30)
    
    -- Current Language (label + tooltip) - Below checkboxes
    local langLabel = FontManager:CreateFontString(generalSection.content, "body", "OVERLAY")
    langLabel:SetPoint("TOPLEFT", 0, generalGridYOffset - 15)
    local currentLangLabel = (ns.L and ns.L["CURRENT_LANGUAGE"]) or "Current Language:"
    langLabel:SetText(currentLangLabel .. " " .. (GetLocale() or "enUS"))
    langLabel:SetTextColor(1, 1, 1, 1)
    
    langLabel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local langTooltip = (ns.L and ns.L["LANGUAGE_TOOLTIP"]) or "Addon uses your WoW game client's language automatically. To change, update your Battle.net settings."
        GameTooltip:SetText(langTooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    langLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Scroll speed slider (below language label) – scale multiplier
    local scrollSpeedYOffset = generalGridYOffset - 45
    scrollSpeedYOffset = CreateSliderWidget(generalSection.content, {
        name = (ns.L and ns.L["SCROLL_SPEED"]) or "Scroll Speed",
        desc = (ns.L and ns.L["SCROLL_SPEED_TOOLTIP"]) or "Multiplier for scroll speed (1.0x = 28 px per step)",
        min = 0.5,
        max = 2.0,
        step = 0.1,
        get = function() return WarbandNexus.db.profile.scrollSpeed or 1.0 end,
        set = function(_, value)
            -- Round to 1 decimal to avoid floating-point drift
            WarbandNexus.db.profile.scrollSpeed = math.floor(value * 10 + 0.5) / 10
        end,
        valueFormat = function(v) return string.format("%.1fx", v) end,
    }, scrollSpeedYOffset, sliderElements)
    
    -- Calculate section height (content height + title + bottom padding)
    local contentHeight = math.abs(scrollSpeedYOffset) + 10
    generalSection:SetHeight(contentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    generalSection.content:SetHeight(contentHeight)
    
    -- Move to next section
    yOffset = yOffset - generalSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- MODULE MANAGEMENT
    --========================================================================
    
    local moduleSection = CreateSection(parent, (ns.L and ns.L["MODULE_MANAGEMENT"]) or "Module Management", effectiveWidth)
    moduleSection:SetPoint("TOPLEFT", 0, yOffset)
    moduleSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- Description label
    local moduleDesc = FontManager:CreateFontString(moduleSection.content, "body", "OVERLAY")
    moduleDesc:SetPoint("TOPLEFT", 0, 0)
    moduleDesc:SetWidth(effectiveWidth - 30)
    moduleDesc:SetJustifyH("LEFT")
    moduleDesc:SetText((ns.L and ns.L["MODULE_MANAGEMENT_DESC"]) or "Enable or disable specific data collection modules. Disabling a module will stop its data updates and hide its tab from the UI.")
    moduleDesc:SetTextColor(COLORS.textDim[1], COLORS.textDim[2], COLORS.textDim[3])
    
    local moduleGridYOffset = -25
    
    local moduleOptions = {
        {
            key = "currencies",
            label = (ns.L and ns.L["MODULE_CURRENCIES"]) or "Currencies",
            tooltip = (ns.L and ns.L["MODULE_CURRENCIES_DESC"]) or "Track account-wide and character-specific currencies (Gold, Honor, Conquest, etc.)",
            get = function() return WarbandNexus.db.profile.modulesEnabled.currencies ~= false end,
            set = function(value)
                WarbandNexus.db.profile.modulesEnabled.currencies = value
                WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "currencies", value)
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "reputations",
            label = (ns.L and ns.L["MODULE_REPUTATIONS"]) or "Reputations",
            tooltip = (ns.L and ns.L["MODULE_REPUTATIONS_DESC"]) or "Track reputation progress with factions, renown levels, and paragon rewards",
            get = function() return WarbandNexus.db.profile.modulesEnabled.reputations ~= false end,
            set = function(value)
                WarbandNexus.db.profile.modulesEnabled.reputations = value
                WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "reputations", value)
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "items",
            label = (ns.L and ns.L["MODULE_ITEMS"]) or "Items",
            tooltip = (ns.L and ns.L["MODULE_ITEMS_DESC"]) or "Track Warband Bank items, search functionality, and item categories",
            get = function() return WarbandNexus.db.profile.modulesEnabled.items ~= false end,
            set = function(value)
                WarbandNexus.db.profile.modulesEnabled.items = value
                WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "items", value)
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "storage",
            label = (ns.L and ns.L["MODULE_STORAGE"]) or "Storage",
            tooltip = (ns.L and ns.L["MODULE_STORAGE_DESC"]) or "Track character bags, personal bank, and Warband Bank storage",
            get = function() return WarbandNexus.db.profile.modulesEnabled.storage ~= false end,
            set = function(value)
                WarbandNexus.db.profile.modulesEnabled.storage = value
                WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "storage", value)
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "pve",
            label = (ns.L and ns.L["MODULE_PVE"]) or "PvE",
            tooltip = (ns.L and ns.L["MODULE_PVE_DESC"]) or "Track Mythic+ dungeons, raid progress, and Weekly Vault rewards",
            get = function() return WarbandNexus.db.profile.modulesEnabled.pve ~= false end,
            set = function(value)
                if WarbandNexus.SetPvEModuleEnabled then
                    WarbandNexus:SetPvEModuleEnabled(value)
                else
                    WarbandNexus.db.profile.modulesEnabled.pve = value
                    WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "pve", value)
                end
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "plans",
            label = (ns.L and ns.L["MODULE_PLANS"]) or "Plans",
            tooltip = (ns.L and ns.L["MODULE_PLANS_DESC"]) or "Track personal goals for mounts, pets, toys, achievements, and custom tasks",
            get = function() return WarbandNexus.db.profile.modulesEnabled.plans ~= false end,
            set = function(value)
                if WarbandNexus.SetPlansModuleEnabled then
                    WarbandNexus:SetPlansModuleEnabled(value)
                else
                    WarbandNexus.db.profile.modulesEnabled.plans = value
                    WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "plans", value)
                end
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "professions",
            label = (ns.L and ns.L["MODULE_PROFESSIONS"]) or "Professions",
            tooltip = (ns.L and ns.L["MODULE_PROFESSIONS_DESC"]) or "Track profession skills, concentration, knowledge, and recipe companion window",
            get = function() return WarbandNexus.db.profile.modulesEnabled.professions ~= false end,
            set = function(value)
                if WarbandNexus.SetProfessionModuleEnabled then
                    WarbandNexus:SetProfessionModuleEnabled(value)
                else
                    WarbandNexus.db.profile.modulesEnabled.professions = value
                    WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "professions", value)
                end
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
    }
    
    moduleGridYOffset = CreateCheckboxGrid(moduleSection.content, moduleOptions, moduleGridYOffset, effectiveWidth - 30)
    
    -- Calculate section height
    local moduleContentHeight = math.abs(moduleGridYOffset)
    moduleSection:SetHeight(moduleContentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    moduleSection.content:SetHeight(moduleContentHeight)
    
    -- Move to next section
    yOffset = yOffset - moduleSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- TAB FILTERING
    --========================================================================
    
    local tabSection = CreateSection(parent, (ns.L and ns.L["TAB_FILTERING"]) or "Tab Filtering", effectiveWidth)
    tabSection:SetPoint("TOPLEFT", 0, yOffset)
    tabSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    local tabGridYOffset = 0
    
    -- WARBAND BANK GROUP
    local warbandLabel = FontManager:CreateFontString(tabSection.content, "subtitle", "OVERLAY")
    warbandLabel:SetPoint("TOPLEFT", 0, tabGridYOffset)
    warbandLabel:SetText((ns.L and ns.L["ITEMS_WARBAND_BANK"]) or "Warband Bank")
    warbandLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, warbandLabel)
    tabGridYOffset = tabGridYOffset - 25  -- Consistent subtitle → checkbox spacing
    
    local warbandOptions = {}
    local tabFmt = (ns.L and ns.L["TAB_FORMAT"]) or "Tab %d"
    local ignoreTabFmt = (ns.L and ns.L["IGNORE_WARBAND_TAB_FORMAT"]) or "Ignore Warband Bank Tab %d from automatic scanning"
    for i = 1, 5 do
        table.insert(warbandOptions, {
            key = "tab" .. i,
            label = string.format(tabFmt, i),
            tooltip = string.format(ignoreTabFmt, i),
            get = function() return WarbandNexus.db.profile.ignoredTabs[i] end,
            set = function(value) WarbandNexus.db.profile.ignoredTabs[i] = value end,
        })
    end
    
    tabGridYOffset = CreateCheckboxGrid(tabSection.content, warbandOptions, tabGridYOffset, effectiveWidth - 30)
    tabGridYOffset = tabGridYOffset - 10  -- Space between groups
    
    -- PERSONAL BANK GROUP
    local personalLabel = FontManager:CreateFontString(tabSection.content, "subtitle", "OVERLAY")
    personalLabel:SetPoint("TOPLEFT", 0, tabGridYOffset)
    personalLabel:SetText((ns.L and ns.L["ITEMS_PLAYER_BANK"]) or "Personal Bank")
    personalLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, personalLabel)
    tabGridYOffset = tabGridYOffset - 25  -- Consistent subtitle → checkbox spacing
    
    local personalBankOptions = {}
    local bankLbl = (ns.L and ns.L["BANK_LABEL"]) or "Bank"
    local bagFmt = (ns.L and ns.L["BAG_FORMAT"]) or "Bag %d"
    local ignoreScanFmt = (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) or "Ignore %s from automatic scanning"
    local personalBankLabels = {bankLbl, string.format(bagFmt, 6), string.format(bagFmt, 7), string.format(bagFmt, 8), string.format(bagFmt, 9), string.format(bagFmt, 10), string.format(bagFmt, 11)}
    for i, bagID in ipairs(ns.PERSONAL_BANK_BAGS) do
        local label = personalBankLabels[i] or string.format(bagFmt, bagID)
        table.insert(personalBankOptions, {
            key = "pbank" .. bagID,
            label = label,
            tooltip = string.format(ignoreScanFmt, label),
            get = function()
                if not WarbandNexus.db.profile.ignoredPersonalBankBags then
                    WarbandNexus.db.profile.ignoredPersonalBankBags = {}
                end
                return WarbandNexus.db.profile.ignoredPersonalBankBags[bagID]
            end,
            set = function(value)
                if not WarbandNexus.db.profile.ignoredPersonalBankBags then
                    WarbandNexus.db.profile.ignoredPersonalBankBags = {}
                end
                WarbandNexus.db.profile.ignoredPersonalBankBags[bagID] = value
            end,
        })
    end
    
    tabGridYOffset = CreateCheckboxGrid(tabSection.content, personalBankOptions, tabGridYOffset, effectiveWidth - 30)
    tabGridYOffset = tabGridYOffset - 10  -- Space between groups
    
    -- INVENTORY GROUP
    local inventoryLabel = FontManager:CreateFontString(tabSection.content, "subtitle", "OVERLAY")
    inventoryLabel:SetPoint("TOPLEFT", 0, tabGridYOffset)
    inventoryLabel:SetText((ns.L and ns.L["CHARACTER_INVENTORY"]) or "Inventory")
    inventoryLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, inventoryLabel)
    tabGridYOffset = tabGridYOffset - 25  -- Consistent subtitle → checkbox spacing
    
    local inventoryOptions = {}
    local backpackLabel = (ns.L and ns.L["BACKPACK_LABEL"]) or "Backpack"
    local reagentLabel = (ns.L and ns.L["REAGENT_LABEL"]) or "Reagent"
    local invBagFmt = (ns.L and ns.L["BAG_FORMAT"]) or "Bag %d"
    local invIgnoreFmt = (ns.L and ns.L["IGNORE_SCAN_FORMAT"]) or "Ignore %s from automatic scanning"
    local inventoryLabels = {backpackLabel, string.format(invBagFmt, 1), string.format(invBagFmt, 2), string.format(invBagFmt, 3), string.format(invBagFmt, 4), reagentLabel}
    for i, bagID in ipairs(ns.INVENTORY_BAGS) do
        local label = inventoryLabels[i] or string.format(invBagFmt, bagID)
        table.insert(inventoryOptions, {
            key = "inv" .. bagID,
            label = label,
            tooltip = string.format(invIgnoreFmt, label),
            get = function()
                if not WarbandNexus.db.profile.ignoredInventoryBags then
                    WarbandNexus.db.profile.ignoredInventoryBags = {}
                end
                return WarbandNexus.db.profile.ignoredInventoryBags[bagID]
            end,
            set = function(value)
                if not WarbandNexus.db.profile.ignoredInventoryBags then
                    WarbandNexus.db.profile.ignoredInventoryBags = {}
                end
                WarbandNexus.db.profile.ignoredInventoryBags[bagID] = value
            end,
        })
    end
    
    tabGridYOffset = CreateCheckboxGrid(tabSection.content, inventoryOptions, tabGridYOffset, effectiveWidth - 30)
    
    -- Calculate section height
    local contentHeight = math.abs(tabGridYOffset)
    tabSection:SetHeight(contentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    tabSection.content:SetHeight(contentHeight)
    
    -- Move to next section
    yOffset = yOffset - tabSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- NOTIFICATIONS
    --========================================================================
    
    local notifSection = CreateSection(parent, (ns.L and ns.L["NOTIFICATIONS_LABEL"]) or "Notifications", effectiveWidth)
    notifSection:SetPoint("TOPLEFT", 0, yOffset)
    notifSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    local notifOptions = {
        {
            key = "enabled",
            label = (ns.L and ns.L["ENABLE_NOTIFICATIONS"]) or "Enable All Notifications",
            tooltip = (ns.L and ns.L["ENABLE_NOTIFICATIONS_TOOLTIP"]) or "Master toggle — disables all popup notifications, chat alerts, and visual effects below",
            get = function() return WarbandNexus.db.profile.notifications.enabled end,
            set = function(value)
                WarbandNexus.db.profile.notifications.enabled = value
                -- Master toggle affects Blizzard message suppression/restoration
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        {
            key = "vault",
            parentKey = "enabled",
            label = (ns.L and ns.L["VAULT_REMINDER"]) or "Weekly Vault Reminder",
            tooltip = (ns.L and ns.L["VAULT_REMINDER_TOOLTIP"]) or "Show a reminder popup on login when you have unclaimed Great Vault rewards",
            get = function() return WarbandNexus.db.profile.notifications.showVaultReminder end,
            set = function(value) WarbandNexus.db.profile.notifications.showVaultReminder = value end,
        },
        {
            key = "loot",
            parentKey = "enabled",
            label = (ns.L and ns.L["LOOT_ALERTS"]) or "New Collectible Popup",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TOOLTIP"]) or "Show a popup when a NEW mount, pet, toy, or achievement enters your collection. Also controls the try counter and screen flash below.",
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showLootNotifications = value end,
        },
        {
            key = "hideBlizzAchievement",
            parentKey = "enabled",
            label = (ns.L and ns.L["HIDE_BLIZZARD_ACHIEVEMENT"]) or "Replace Achievement Popup",
            tooltip = (ns.L and ns.L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"]) or "Replace Blizzard's default achievement popup with the Warband Nexus notification style",
            get = function() return WarbandNexus.db.profile.notifications.hideBlizzardAchievementAlert end,
            set = function(value)
                WarbandNexus.db.profile.notifications.hideBlizzardAchievementAlert = value
                if WarbandNexus.ApplyBlizzardAchievementAlertSuppression then
                    WarbandNexus:ApplyBlizzardAchievementAlertSuppression()
                end
            end,
        },
        {
            key = "reputation",
            parentKey = "enabled",
            label = (ns.L and ns.L["REPUTATION_GAINS"]) or "Rep Gains in Chat",
            tooltip = (ns.L and ns.L["REPUTATION_GAINS_TOOLTIP"]) or "Display reputation gain messages in chat when you earn faction standing",
            get = function() return WarbandNexus.db.profile.notifications.showReputationGains end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showReputationGains = value
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        {
            key = "currency",
            parentKey = "enabled",
            label = (ns.L and ns.L["CURRENCY_GAINS"]) or "Currency Gains in Chat",
            tooltip = (ns.L and ns.L["CURRENCY_GAINS_TOOLTIP"]) or "Display currency gain messages in chat when you earn currencies",
            get = function() return WarbandNexus.db.profile.notifications.showCurrencyGains end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showCurrencyGains = value
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        {
            key = "autoTryCounter",
            parentKey = "loot",
            label = (ns.L and ns.L["AUTO_TRY_COUNTER"]) or "Auto-Track Drop Attempts",
            tooltip = (ns.L and ns.L["AUTO_TRY_COUNTER_TOOLTIP"]) or "Automatically count failed drop attempts when looting NPCs, rares, bosses, fishing, or containers. Shows total attempt count in the popup when the collectible finally drops.",
            get = function() return WarbandNexus.db.profile.notifications.autoTryCounter end,
            set = function(value) WarbandNexus.db.profile.notifications.autoTryCounter = value end,
        },
        {
            key = "screenFlash",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["SCREEN_FLASH_EFFECT"]) or "Flash on Rare Drop",
            tooltip = (ns.L and ns.L["SCREEN_FLASH_EFFECT_TOOLTIP"]) or "Play a screen flash animation when you finally obtain a collectible after multiple farming attempts",
            get = function() return WarbandNexus.db.profile.notifications.screenFlashEffect end,
            set = function(value) WarbandNexus.db.profile.notifications.screenFlashEffect = value end,
        },
    }
    
    local notifGridYOffset, notifWidgets = CreateCheckboxGrid(notifSection.content, notifOptions, 0, effectiveWidth - 30)
    
    -- Track external dependents (sliders, buttons) that should disable when notifications are OFF
    local notifExternalDependents = {}
    notifWidgets._onParentToggle = function(key, isEnabled)
        if key == "enabled" then
            for _, dep in ipairs(notifExternalDependents) do
                if dep.type == "slider" then
                    if isEnabled then
                        dep.widget:Enable()
                        dep.widget:SetAlpha(1.0)
                        if dep.label then dep.label:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]) end
                        if dep.valueLabel then dep.valueLabel:SetTextColor(1, 1, 1, 1) end
                    else
                        dep.widget:Disable()
                        dep.widget:SetAlpha(0.35)
                        if dep.label then dep.label:SetTextColor(0.4, 0.4, 0.4, 0.6) end
                        if dep.valueLabel then dep.valueLabel:SetTextColor(0.4, 0.4, 0.4, 0.6) end
                    end
                elseif dep.type == "button" then
                    if isEnabled then
                        dep.widget:Enable()
                        dep.widget:SetAlpha(1.0)
                    else
                        dep.widget:Disable()
                        dep.widget:SetAlpha(0.35)
                    end
                elseif dep.type == "label" then
                    if isEnabled then
                        dep.widget:SetTextColor(dep.color[1], dep.color[2], dep.color[3], dep.color[4] or 1)
                    else
                        dep.widget:SetTextColor(0.4, 0.4, 0.4, 0.6)
                    end
                end
            end
        end
    end
    
    -- ---- Popup Duration Slider (custom slider system) ----
    notifGridYOffset = notifGridYOffset - 15
    local durationLabel = FontManager:CreateFontString(notifSection.content, "subtitle", "OVERLAY")
    durationLabel:SetPoint("TOPLEFT", 0, notifGridYOffset)
    durationLabel:SetText((ns.L and ns.L["POPUP_DURATION"]) or "Popup Duration")
    durationLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, durationLabel)
    notifGridYOffset = notifGridYOffset - 20
    
    local durationSlider = nil  -- Will capture from sliderElements
    local sliderCountBefore = #sliderElements
    notifGridYOffset = CreateSliderWidget(notifSection.content, {
        name = (ns.L and ns.L["DURATION_LABEL"]) or "Duration",
        min = 3,
        max = 15,
        step = 1,
        valueFormat = function(v) return tostring(math.floor(v + 0.5)) .. "s" end,
        get = function() return WarbandNexus.db.profile.notifications.popupDuration or 5 end,
        set = function(_, value)
            value = math.floor(value + 0.5)
            WarbandNexus.db.profile.notifications.popupDuration = value
        end,
    }, notifGridYOffset, sliderElements)
    -- Capture the just-created slider for dependency tracking
    if #sliderElements > sliderCountBefore then
        durationSlider = sliderElements[#sliderElements]
    end
    
    -- ---- Popup Position Controls ----
    notifGridYOffset = notifGridYOffset - 10
    local posLabel = FontManager:CreateFontString(notifSection.content, "subtitle", "OVERLAY")
    posLabel:SetPoint("TOPLEFT", 0, notifGridYOffset)
    posLabel:SetText((ns.L and ns.L["POPUP_POSITION"]) or "Popup Position")
    posLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, posLabel)
    notifGridYOffset = notifGridYOffset - 22
    
    -- Position description (updates dynamically)
    local anchorDesc = FontManager:CreateFontString(notifSection.content, "body", "OVERLAY")
    anchorDesc:SetPoint("TOPLEFT", 0, notifGridYOffset)
    anchorDesc:SetPoint("TOPRIGHT", -10, notifGridYOffset)
    anchorDesc:SetJustifyH("LEFT")
    anchorDesc:SetTextColor(0.7, 0.7, 0.7, 1)
    
    local function UpdateAnchorDesc()
        local db = WarbandNexus.db.profile.notifications
        local pt = db.popupPoint or "TOP"
        local x = db.popupX or 0
        local y = db.popupY or -100
        local anchorFormat = (ns.L and ns.L["ANCHOR_FORMAT"]) or "Anchor: %s  |  X: %d  |  Y: %d"
        anchorDesc:SetText(string.format(anchorFormat, pt, x, y))
    end
    UpdateAnchorDesc()
    notifGridYOffset = notifGridYOffset - 18
    
    -- Buttons row: Set Position, Reset, Test
    local btnWidth = math.floor((effectiveWidth - 30) / 3)
    
    -- "Set Position" button (shows draggable ghost frame)
    local setPosBtn = ns.UI.Factory:CreateButton(notifSection.content)
    setPosBtn:SetSize(btnWidth, 30)
    setPosBtn:SetPoint("TOPLEFT", 0, notifGridYOffset)
    setPosBtn:Enable()
    local setPosBtnText = setPosBtn:GetFontString() or FontManager:CreateFontString(setPosBtn, "body", "OVERLAY")
    setPosBtnText:SetPoint("CENTER")
    setPosBtnText:SetText((ns.L and ns.L["SET_POSITION"]) or "Set Position")
    setPosBtn:SetFontString(setPosBtnText)
    setPosBtn:SetScript("OnClick", function()
        -- Toggle ghost frame
        if WarbandNexus._positionGhost then
            WarbandNexus._positionGhost:Hide()
            WarbandNexus._positionGhost = nil
            return
        end
        
        -- Reuse existing ghost frame if it exists
        local ghost = WarbandNexus._positionGhost
        if not ghost then
            ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            ghost:SetSize(400, 88)
            ghost:SetFrameStrata("DIALOG")
            ghost:SetFrameLevel(2000)
            ghost:SetMovable(true)
            ghost:EnableMouse(true)
            ghost:RegisterForDrag("LeftButton")
            ghost:SetClampedToScreen(true)
            
            ghost:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 2,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            ghost:SetBackdropColor(0.1, 0.6, 0.1, 0.7)
            ghost:SetBackdropBorderColor(0, 1, 0, 1)
            
            local ghostText = FontManager:CreateFontString(ghost, "title", "OVERLAY")
            ghostText:SetPoint("CENTER")
            ghostText:SetText((ns.L and ns.L["DRAG_TO_POSITION"]) or "Drag to position\nRight-click to confirm")
            ghostText:SetTextColor(1, 1, 1, 1)
        end
        
        -- Start at currently saved position
        local db = WarbandNexus.db.profile.notifications
        local curPoint = db.popupPoint or "TOP"
        local curX = db.popupX or 0
        local curY = db.popupY or -100
        ghost:SetPoint(curPoint, UIParent, curPoint, curX, curY)
        
        ghost:SetScript("OnDragStart", function(self) self:StartMoving() end)
        ghost:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            
            -- Calculate the best anchor point based on where the ghost ended up
            local screenW = UIParent:GetWidth()
            local screenH = UIParent:GetHeight()
            local left = self:GetLeft()
            local top = self:GetTop()
            local w = self:GetWidth()
            local h = self:GetHeight()
            local centerX = left + (w / 2)
            local centerY = top - (h / 2)
            
            -- Determine anchor point by screen region
            local anchorPoint, offsetX, offsetY
            local isTop = centerY > (screenH * 0.6)
            local isBottom = centerY < (screenH * 0.4)
            
            if isTop then
                -- Anchor to TOP: offset = how far below the top edge
                anchorPoint = "TOP"
                offsetX = math.floor(centerX - (screenW / 2))
                offsetY = math.floor(top - screenH)
            elseif isBottom then
                -- Anchor to BOTTOM: offset = how far above the bottom edge
                local bottom = top - h
                anchorPoint = "BOTTOM"
                offsetX = math.floor(centerX - (screenW / 2))
                offsetY = math.floor(bottom)
            else
                -- Anchor to CENTER
                anchorPoint = "CENTER"
                offsetX = math.floor(centerX - (screenW / 2))
                offsetY = math.floor(centerY - (screenH / 2))
            end
            
            db.popupPoint = anchorPoint
            db.popupX = offsetX
            db.popupY = offsetY
            UpdateAnchorDesc()
        end)
        ghost:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                self:Hide()
                WarbandNexus._positionGhost = nil
                WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Popup position saved!") .. "|r")
            end
        end)
        
        ghost:Show()
        WarbandNexus._positionGhost = ghost
        WarbandNexus:Print("|cffffcc00" .. ((ns.L and ns.L["DRAG_POSITION_MSG"]) or "Drag the green frame to set popup position. Right-click to confirm.") .. "|r")
    end)
    
    -- "Reset" button (restore default: TOP, 0, -100)
    local resetBtn = ns.UI.Factory:CreateButton(notifSection.content)
    resetBtn:SetSize(btnWidth, 30)
    resetBtn:SetPoint("LEFT", setPosBtn, "RIGHT", 5, 0)
    resetBtn:Enable()
    local resetBtnText = resetBtn:GetFontString() or FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetBtnText:SetPoint("CENTER")
    resetBtnText:SetText((ns.L and ns.L["RESET_DEFAULT"]) or "Reset Default")
    resetBtn:SetFontString(resetBtnText)
    resetBtn:SetScript("OnClick", function()
        local db = WarbandNexus.db.profile.notifications
        db.popupPoint = "TOP"
        db.popupX = 0
        db.popupY = -100
        UpdateAnchorDesc()
        WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_RESET_MSG"]) or "Popup position reset to default (Top Center)") .. "|r")
    end)
    
    -- "Test" button
    local testBtn = ns.UI.Factory:CreateButton(notifSection.content)
    testBtn:SetSize(btnWidth, 30)
    testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 5, 0)
    testBtn:Enable()
    local testBtnText = testBtn:GetFontString() or FontManager:CreateFontString(testBtn, "body", "OVERLAY")
    testBtnText:SetPoint("CENTER")
    testBtnText:SetText((ns.L and ns.L["TEST_POPUP"]) or "Test Popup")
    testBtn:SetFontString(testBtnText)
    testBtn:SetScript("OnClick", function()
        if WarbandNexus.Notify then
            WarbandNexus:Notify("achievement", (ns.L and ns.L["TEST_NOTIFICATION_TITLE"]) or "Test Notification", nil, {
                action = (ns.L and ns.L["TEST_NOTIFICATION_MSG"]) or "Position test",
            })
        end
    end)
    notifGridYOffset = notifGridYOffset - 40
    
    -- Register all notification external dependents for parent toggle cascade
    table.insert(notifExternalDependents, { type = "label", widget = durationLabel, color = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]} })
    if durationSlider then
        table.insert(notifExternalDependents, { type = "slider", widget = durationSlider, label = durationLabel })
    end
    table.insert(notifExternalDependents, { type = "label", widget = posLabel, color = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]} })
    table.insert(notifExternalDependents, { type = "label", widget = anchorDesc, color = {0.7, 0.7, 0.7} })
    table.insert(notifExternalDependents, { type = "button", widget = setPosBtn })
    table.insert(notifExternalDependents, { type = "button", widget = resetBtn })
    table.insert(notifExternalDependents, { type = "button", widget = testBtn })
    
    -- Apply initial disabled state if notifications are OFF
    local notifInitialEnabled = WarbandNexus.db.profile.notifications.enabled
    if not notifInitialEnabled then
        for _, dep in ipairs(notifExternalDependents) do
            if dep.type == "slider" then
                dep.widget:Disable()
                dep.widget:SetAlpha(0.35)
                if dep.label then dep.label:SetTextColor(0.4, 0.4, 0.4, 0.6) end
            elseif dep.type == "button" then
                dep.widget:Disable()
                dep.widget:SetAlpha(0.35)
            elseif dep.type == "label" then
                dep.widget:SetTextColor(0.4, 0.4, 0.4, 0.6)
            end
        end
    end
    
    -- Calculate section height
    local contentHeight = math.abs(notifGridYOffset)
    notifSection:SetHeight(contentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    notifSection.content:SetHeight(contentHeight)
    
    -- Move to next section
    yOffset = yOffset - notifSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- THEME & APPEARANCE
    --========================================================================
    
    local themeSection = CreateSection(parent, (ns.L and ns.L["THEME_APPEARANCE"]) or "Theme & Appearance", effectiveWidth)
    themeSection:SetPoint("TOPLEFT", 0, yOffset)
    themeSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    local themeYOffset = 0
    
    -- Color Picker Button
    local colorPickerLabel = FontManager:CreateFontString(themeSection.content, "subtitle", "OVERLAY")
    colorPickerLabel:SetPoint("TOPLEFT", 0, themeYOffset)
    colorPickerLabel:SetText((ns.L and ns.L["CUSTOM_COLOR"]) or "Custom Color")
    colorPickerLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, colorPickerLabel)
    themeYOffset = themeYOffset - 25
    
    -- Simple button to open color picker
    local colorPickerBtn = ns.UI.Factory:CreateButton(themeSection.content)
    colorPickerBtn:SetSize(240, 40)
    colorPickerBtn:SetPoint("TOPLEFT", 0, themeYOffset)
    colorPickerBtn:Enable()
    
    if ApplyVisuals then
        ApplyVisuals(colorPickerBtn, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Button text
    local btnText = FontManager:CreateFontString(colorPickerBtn, "body", "OVERLAY")
    btnText:SetPoint("CENTER")
    btnText:SetText((ns.L and ns.L["OPEN_COLOR_PICKER"]) or "Open Color Picker")
    btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    
    -- Click handler - Opens WoW's native color picker
    -- Apply color only when user closes picker (not while dragging) to avoid performance loss
    colorPickerBtn:SetScript("OnClick", function(self)
        local currentColor = WarbandNexus.db.profile.themeColors.accent
        local r, g, b = currentColor[1], currentColor[2], currentColor[3]
        local pendingR, pendingG, pendingB = r, g, b
        local cancelled = false
        
        local function ApplyPending()
            local colors = ns.UI_CalculateThemeColors(pendingR, pendingG, pendingB)
            WarbandNexus.db.profile.themeColors = colors
            if ns.UI_RefreshColors then
                ns.UI_RefreshColors()
            end
            RefreshSubtitles()
        end
        
        local info = {
            swatchFunc = function()
                -- Only store; apply on close (no live refresh while dragging)
                if ColorPickerFrame then
                    pendingR, pendingG, pendingB = ColorPickerFrame:GetColorRGB()
                end
            end,
            hasOpacity = false,
            opacity = 1.0,
            r = r,
            g = g,
            b = b,
            cancelFunc = function(previousValues)
                cancelled = true
                if previousValues then
                    pendingR, pendingG, pendingB = previousValues.r, previousValues.g, previousValues.b
                end
            end,
        }
        
        -- TAINT FIX: Install color picker preview hooks lazily (first open)
        -- This handles live preview + cancel/revert automatically via Config.lua hooks
        if ns.InstallColorPickerPreviewHook then
            ns.InstallColorPickerPreviewHook()
        end
        
        if not ColorPickerFrame then return end
        
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetFrameLevel(500)
        
        -- TAINT FIX: Do NOT use SetScript("OnHide") on ColorPickerFrame.
        -- That REPLACES Blizzard's handler with tainted addon code, propagating taint.
        -- Instead, use the info table's cancelFunc callback for cancel detection,
        -- and a short-lived ticker to detect when the picker closes for confirmation.
        if ColorPickerFrame.SetupColorPickerAndShow then
            -- TWW 10.2.5+ color picker: uses info table callbacks
            info.cancelFunc = function(previousValues)
                cancelled = true
                if previousValues then
                    pendingR, pendingG, pendingB = previousValues.r, previousValues.g, previousValues.b
                end
                ApplyPending()
            end
            info.swatchFunc = function()
                if ColorPickerFrame then
                    pendingR, pendingG, pendingB = ColorPickerFrame:GetColorRGB()
                end
            end
            
            ColorPickerFrame:SetupColorPickerAndShow(info)
            
            -- Poll-based closure detection instead of hooking OnHide
            -- Avoids taint from modifying Blizzard frame script handlers
            local closeTicker = C_Timer.NewTicker(0.1, function(ticker)
                if not ColorPickerFrame:IsShown() then
                    ticker:Cancel()
                    if not cancelled then
                        ApplyPending()
                    end
                end
            end)
        else
            -- Legacy color picker (pre-10.2.5 fallback)
            ColorPickerFrame.func = info.swatchFunc
            ColorPickerFrame.opacityFunc = info.swatchFunc
            ColorPickerFrame.cancelFunc = function()
                info.cancelFunc({r = r, g = g, b = b})
            end
            ColorPickerFrame.hasOpacity = info.hasOpacity
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame.previousValues = {r = r, g = g, b = b}
            ColorPickerFrame:Show()
        end
        
        ColorPickerFrame:Raise()
    end)
    
    -- Hover effects
    colorPickerBtn:SetScript("OnEnter", function(self)
        if ApplyVisuals then
            ApplyVisuals(colorPickerBtn, {0.12, 0.12, 0.14, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
        end
        btnText:SetTextColor(1, 1, 1)
        
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText((ns.L and ns.L["COLOR_PICKER_TOOLTIP"]) or "Open WoW's native color picker wheel to choose a custom theme color", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    
    colorPickerBtn:SetScript("OnLeave", function(self)
        if ApplyVisuals then
            ApplyVisuals(colorPickerBtn, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
        btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        GameTooltip:Hide()
    end)
    
    themeYOffset = themeYOffset - 50  -- Space after button
    
    -- Preset Theme Buttons
    local presetLabel = FontManager:CreateFontString(themeSection.content, "subtitle", "OVERLAY")
    presetLabel:SetPoint("TOPLEFT", 0, themeYOffset)
    presetLabel:SetText((ns.L and ns.L["PRESET_THEMES"]) or "Preset Themes")
    presetLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, presetLabel)
    themeYOffset = themeYOffset - 25
    
    -- Theme preset buttons (with colors)
    local themeButtons = {
        {
            label = (ns.L and ns.L["COLOR_PURPLE"]) or "Purple",
            tooltip = (ns.L and ns.L["COLOR_PURPLE_DESC"]) or "Classic purple theme (default)",
            color = {0.40, 0.20, 0.58},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_BLUE"]) or "Blue",
            tooltip = (ns.L and ns.L["COLOR_BLUE_DESC"]) or "Cool blue theme",
            color = {0.30, 0.65, 1.0},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.30, 0.65, 1.0)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_GREEN"]) or "Green",
            tooltip = (ns.L and ns.L["COLOR_GREEN_DESC"]) or "Nature green theme",
            color = {0.32, 0.79, 0.40},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.32, 0.79, 0.40)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_RED"]) or "Red",
            tooltip = (ns.L and ns.L["COLOR_RED_DESC"]) or "Fiery red theme",
            color = {1.0, 0.34, 0.34},
            func = function()
                local colors = ns.UI_CalculateThemeColors(1.0, 0.34, 0.34)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_ORANGE"]) or "Orange",
            tooltip = (ns.L and ns.L["COLOR_ORANGE_DESC"]) or "Warm orange theme",
            color = {1.0, 0.65, 0.30},
            func = function()
                local colors = ns.UI_CalculateThemeColors(1.0, 0.65, 0.30)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = (ns.L and ns.L["COLOR_CYAN"]) or "Cyan",
            tooltip = (ns.L and ns.L["COLOR_CYAN_DESC"]) or "Bright cyan theme",
            color = {0.00, 0.80, 1.00},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.00, 0.80, 1.00)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
    }
    
    -- Use content width (section width - 30px for left/right insets)
    themeYOffset = CreateButtonGrid(themeSection.content, themeButtons, themeYOffset, effectiveWidth - 30, 120)
    themeYOffset = themeYOffset - 10  -- Space after preset buttons
    
    -- Font Family Dropdown
    themeYOffset = CreateDropdownWidget(themeSection.content, {
        name = (ns.L and ns.L["FONT_FAMILY"]) or "Font Family",
        desc = (ns.L and ns.L["FONT_FAMILY_TOOLTIP"]) or "Choose the font used throughout the addon UI",
        values = function()
            return (ns.GetFilteredFontOptions and ns.GetFilteredFontOptions()) or {
                ["Friz Quadrata TT"] = "Friz Quadrata TT",
                ["Arial Narrow"] = "Arial Narrow",
                ["Skurri"] = "Skurri",
                ["Morpheus"] = "Morpheus",
                ["Action Man"] = "Action Man",
                ["Continuum Medium"] = "Continuum Medium",
                ["Expressway"] = "Expressway",
            }
        end,
        get = function() return WarbandNexus.db.profile.fonts.fontFace end,
        set = function(_, value)
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM and LSM.IsValid and LSM.MediaType and not LSM:IsValid(LSM.MediaType.FONT, value) then
                value = "Friz Quadrata TT"
            end
            WarbandNexus.db.profile.fonts.fontFace = value
            if ns.FontManager and ns.FontManager.RefreshAllFonts then
                ns.FontManager:RefreshAllFonts()
            end
            -- Defer RefreshUI after font warm-up completes (0.3s accounts for warm-up + GPU rasterization)
            C_Timer.After(0.3, function()
                if WarbandNexus and WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
                -- Rebuild settings window if open (after font fully applied)
                C_Timer.After(0.1, function()
                    if settingsFrame and settingsFrame:IsShown() then
                        settingsFrame:Hide()
                        settingsFrame = nil
                        if WarbandNexus and WarbandNexus.ShowSettings then
                            WarbandNexus:ShowSettings()
                        end
                    end
                end)
            end)
        end,
    }, themeYOffset)
    
    -- Font scale warning text (created first so slider callback can reference it)
    -- Positioned below where the slider will be (slider takes ~65px height)
    local warningYPos = themeYOffset - 65 - 5
    local warningText = FontManager:CreateFontString(themeSection.content, "small", "OVERLAY")
    warningText:SetPoint("TOPLEFT", 0, warningYPos)
    warningText:SetWidth(effectiveWidth - 30)
    warningText:SetJustifyH("LEFT")
    warningText:SetText("|cffff8800" .. ((ns.L and ns.L["FONT_SCALE_WARNING"]) or "Warning: Higher font scale may cause text overflow in some UI elements.") .. "|r")
    
    -- Set initial visibility based on current scale
    local currentScale = WarbandNexus.db.profile.fonts.scaleCustom or 1.0
    if currentScale > 1.0 then
        warningText:Show()
    else
        warningText:Hide()
    end
    
    -- Font scale slider
    themeYOffset = CreateSliderWidget(themeSection.content, {
        name = (ns.L and ns.L["FONT_SCALE"]) or "Font Scale",
        desc = (ns.L and ns.L["FONT_SCALE_TOOLTIP"]) or "Adjust font size across all UI elements",
        min = 0.8,
        max = 1.5,
        step = 0.1,
        get = function() return WarbandNexus.db.profile.fonts.scaleCustom or 1.0 end,
        set = function(_, value)
            WarbandNexus.db.profile.fonts.scaleCustom = value
            WarbandNexus.db.profile.fonts.useCustomScale = true
            -- Update warning visibility immediately (no rebuild needed)
            if value > 1.0 then
                warningText:Show()
            else
                warningText:Hide()
            end
            if ns.FontManager and ns.FontManager.RefreshAllFonts then
                ns.FontManager:RefreshAllFonts()
            end
        end,
    }, themeYOffset, sliderElements)  -- Pass sliderElements for tracking
    
    -- Account for warning text height in layout
    themeYOffset = themeYOffset - 20
    
    -- Resolution Normalization toggle (below Font Scale)
    themeYOffset = themeYOffset - 10
    themeYOffset = CreateCheckboxGrid(themeSection.content, {
        {
            key = "usePixelNormalization",
            label = (ns.L and ns.L["RESOLUTION_NORMALIZATION"]) or "Auto-Scale for Resolution",
            tooltip = (ns.L and ns.L["RESOLUTION_NORMALIZATION_TOOLTIP"]) or "Automatically adjust font sizes based on your screen resolution and UI scale so text appears the same physical size across different monitors",
            get = function() return WarbandNexus.db.profile.fonts.usePixelNormalization end,
            set = function(value)
                WarbandNexus.db.profile.fonts.usePixelNormalization = value
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
                -- Rebuild settings window if open (after font change)
                C_Timer.After(0.1, function()
                    if settingsFrame and settingsFrame:IsShown() then
                        settingsFrame:Hide()
                        settingsFrame = nil
                        WarbandNexus:ShowSettings()
                    end
                end)
            end,
        },
    }, themeYOffset, effectiveWidth - 30)
    
    local themeSectionHeight = math.abs(themeYOffset)
    themeSection:SetHeight(themeSectionHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    themeSection.content:SetHeight(themeSectionHeight)
    
    -- Move to next section
    yOffset = yOffset - themeSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- ADVANCED
    --========================================================================
    
    local advSection = CreateSection(parent, (ns.L and ns.L["ADVANCED_SECTION"]) or "Advanced", effectiveWidth)
    advSection:SetPoint("TOPLEFT", 0, yOffset)
    advSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- Debug Mode checkbox
    local debugOptions = {
        {
            key = "debug",
            label = (ns.L and ns.L["DEBUG_MODE"]) or "Debug Logging",
            tooltip = (ns.L and ns.L["DEBUG_MODE_DESC"]) or "Output verbose debug messages to chat for troubleshooting",
            get = function() return WarbandNexus.db.profile.debugMode end,
            set = function(value) WarbandNexus.db.profile.debugMode = value end,
        },
    }
    
    local advGridYOffset = CreateCheckboxGrid(advSection.content, debugOptions, 0, effectiveWidth - 30)
    
    -- Calculate section height
    local contentHeight = math.abs(advGridYOffset)
    advSection:SetHeight(contentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    advSection.content:SetHeight(contentHeight)
    
    -- Set total parent height
    local totalHeight = math.abs(yOffset)
    parent:SetHeight(totalHeight + 20)
end

--============================================================================
-- MAIN WINDOW
--============================================================================

local settingsFrame = nil

function WarbandNexus:ShowSettings()
    -- Prevent duplicates
    if settingsFrame and settingsFrame:IsShown() then
        return
    end
    
    -- Main frame
    local f = CreateFrame("Frame", "WarbandNexusSettingsFrame", UIParent)
    f:SetSize(700, 650)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:SetClampedToScreen(true)
    f:SetResizeBounds(600, 500, 1000, 800)
    
    if ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
    end
    
    settingsFrame = f
    
    -- Add to UISpecialFrames (with duplicate guard)
    -- Remove any existing entry first
    for i = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[i] == "WarbandNexusSettingsFrame" then
            table.remove(UISpecialFrames, i)
        end
    end
    tinsert(UISpecialFrames, "WarbandNexusSettingsFrame")
    
    -- Explicit ESC handler as fallback
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    
    -- Header
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(40)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        -- Re-anchor to current visual position to prevent teleport after Alt-Tab
        local left, top = f:GetLeft(), f:GetTop()
        if left and top then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        f:StartMoving()
    end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    
    if ApplyVisuals then
        ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    
    -- Title
    local title = FontManager:CreateFontString(header, "title", "OVERLAY")
    title:SetPoint("LEFT", icon, "RIGHT", UI_SPACING.AFTER_ELEMENT, 0)
    title:SetText((ns.L and ns.L["WARBAND_NEXUS_SETTINGS"]) or "Warband Nexus Settings")
    title:SetTextColor(1, 1, 1)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -UI_SPACING.SIDE_MARGIN, 0)
    
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        settingsFrame = nil
    end)
    
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)
    
    -- Resize grip
    local resizer = CreateFrame("Button", nil, f)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if scrollChild and scrollFrame then
            local newScrollWidth = scrollFrame:GetWidth() or 620
            scrollChild:SetWidth(newScrollWidth)
            BuildSettings(scrollChild, newScrollWidth)
            if ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
            end
        end
    end)
    
    -- Content area
    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:ClearAllPoints()
    contentArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -UI_SPACING.TOP_MARGIN)
    contentArea:SetPoint("BOTTOMRIGHT", -UI_SPACING.SIDE_MARGIN, UI_SPACING.TOP_MARGIN)
    
    -- ScrollFrame
    local scrollFrame = ns.UI.Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", UI_SPACING.SIDE_MARGIN, -UI_SPACING.TOP_MARGIN)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, UI_SPACING.TOP_MARGIN)
    scrollFrame:EnableMouseWheel(true)
    
    -- Scroll child
    local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
    local scrollWidth = scrollFrame:GetWidth() or 660
    scrollChild:SetWidth(scrollWidth)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Resize: only update scroll width during drag; full rebuild on mouse release (no continuous render)
    f:SetScript("OnSizeChanged", function(self, width, height)
        local newScrollWidth = scrollFrame:GetWidth() or 620
        scrollChild:SetWidth(newScrollWidth)
    end)
    
    -- Mouse wheel scrolling (uses dynamic scroll speed)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = current - (delta * step)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
    end)
    
    -- Build content with explicit width (delayed to ensure frame is rendered)
    C_Timer.After(0.05, function()
        if not scrollFrame or not scrollChild then return end
        
        local initialWidth = scrollFrame:GetWidth() or 620
        scrollChild:SetWidth(initialWidth)
        BuildSettings(scrollChild, initialWidth)
        lastWidth = initialWidth  -- Track initial width
        
        -- Final adjustment after content is built
        C_Timer.After(0.1, function()
            if scrollFrame and scrollChild then
                local newScrollWidth = scrollFrame:GetWidth() or 620
                scrollChild:SetWidth(newScrollWidth)
                
                -- Rebuild with correct width if it changed significantly
                if math.abs(newScrollWidth - initialWidth) > 10 then
                    BuildSettings(scrollChild, newScrollWidth)
                    lastWidth = newScrollWidth
                end
                
                if ns.UI.Factory.UpdateScrollBarVisibility then
                    ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
                end
            end
        end)
    end)
    
    f:Show()
    settingsFrame = f
end

-- Export
ns.ShowSettings = function() WarbandNexus:ShowSettings() end
