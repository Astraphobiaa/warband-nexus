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

-- Forward declaration: BuildSettings and ShowSettings share this reference.
local settingsFrame = nil
local IGNORED_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, UNKNOWN = true,
}

---Re-enable keyboard after Hide/Show cycles (WoW does not always restore focus).
local function RefreshSettingsKeyboard(frame)
    if not frame or InCombatLockdown() then return end
    if frame.EnableKeyboard then frame:EnableKeyboard(true) end
    if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(true) end
end

---Long setting tooltips: use SetText wrap flag + minimum width so text breaks into lines.
---@param owner Region
---@param text string|nil
local function Settings_ShowWrappedTooltip(owner, text)
    if not owner or not text or type(text) ~= "string" then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    local w = 340
    if owner.GetParent then
        local parent = owner:GetParent()
        if parent and parent.GetWidth then
            local pw = parent:GetWidth()
            if pw and pw > 120 then
                w = math.max(260, math.min(440, pw - 40))
            end
        end
    end
    if GameTooltip.SetMinimumWidth then
        GameTooltip:SetMinimumWidth(w)
    end
    GameTooltip:SetText(text, 1, 1, 1, 1, true)
    GameTooltip:Show()
end

local function GetToggleBindingDisplayText()
    local key = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
                and WarbandNexus.db.profile.toggleKeybind
    if not key or key == "" then
        return (ns.L and ns.L["KEYBINDING_UNBOUND"]) or "Not set"
    end
    return (GetBindingText and GetBindingText(key)) or key
end

local function SaveToggleKeybind(key)
    if not WarbandNexus or not WarbandNexus.db then return false end
    WarbandNexus.db.profile.toggleKeybind = key
    if WarbandNexus.ApplyToggleKeybind then
        WarbandNexus:ApplyToggleKeybind()
    end
    return true
end

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
    -- Responsive fixed-column grid: column count grows with available width.
    -- All items in a given column share the same X anchor → perfect alignment.
    local containerWidth = explicitWidth or parent:GetWidth() or 620

    -- Determine column count based on width (prefer readability over density).
    -- 1-2 columns keeps long labels from looking cramped in Settings.
    local MIN_COL_WIDTH = 260
    local COL_SPACING = 12
    local maxCols = 2
    local numCols = math.floor((containerWidth + COL_SPACING) / (MIN_COL_WIDTH + COL_SPACING))
    numCols = math.max(1, math.min(maxCols, numCols))
    local colWidth = (containerWidth - (COL_SPACING * (numCols - 1))) / numCols

    local ROW_HEIGHT = 36
    local widgets = {}       -- key → {checkbox, label}
    local optionByKey = {}   -- key → option
    local childKeys = {}     -- parentKey → {childKey1, childKey2, ...}
    local parentKeyMap = {}  -- childKey → parentKey

    local totalRows = 0

    for i, option in ipairs(options) do
        local col = (i - 1) % numCols
        local row = math.floor((i - 1) / numCols)
        if row > totalRows then totalRows = row end

        local xPos = col * (colWidth + COL_SPACING)
        local yPos  = yOffset + (row * -ROW_HEIGHT)

        local checkbox = CreateThemedCheckbox(parent)
        checkbox:SetPoint("TOPLEFT", xPos, yPos)

        -- Label (to the right of checkbox)
        local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
        label:SetJustifyH("LEFT")
        label:SetText(option.label)
        label:SetTextColor(1, 1, 1, 1)
        label:SetPoint("LEFT", checkbox, "RIGHT", UI_SPACING.AFTER_ELEMENT, 0)
        -- Constrain label width so it never bleeds into the next column
        label:SetWidth(colWidth - (ns.UI_TOGGLE_SIZE or 16) - UI_SPACING.AFTER_ELEMENT)

        -- Set initial value
        if option.get then
            checkbox:SetChecked(option.get())
            if checkbox.checkTexture then
                checkbox.checkTexture:SetShown(option.get())
            end
        end

        -- Store widget reference
        if option.key then
            widgets[option.key] = { checkbox = checkbox, label = label }
            optionByKey[option.key] = option
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
                Settings_ShowWrappedTooltip(self, option.tooltip)
            end)
            checkbox:SetScript("OnLeave", function() GameTooltip:Hide() end)

            label:SetScript("OnEnter", function(self)
                Settings_ShowWrappedTooltip(self, option.tooltip)
            end)
            label:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    -- Synchronize descendant checkbox state + DB values when a parent is toggled.
    -- This enforces true hierarchical behavior:
    -- parent OFF -> all descendants OFF
    -- parent ON  -> all descendants ON (children can still be manually changed later)
    local function SyncDescendantsCheckedState(key, newState)
        local kids = childKeys[key]
        if not kids then return end

        for _, childKey in ipairs(kids) do
            local w = widgets[childKey]
            local childOption = optionByKey[childKey]
            if w then
                local current = not not w.checkbox:GetChecked()
                if current ~= newState then
                    w.checkbox:SetChecked(newState)
                    if w.checkbox.checkTexture then
                        w.checkbox.checkTexture:SetShown(newState)
                    end
                    if childOption and childOption.set then
                        childOption.set(newState)
                    end
                elseif w.checkbox.checkTexture then
                    -- Keep visual marker in sync even when state already matches.
                    w.checkbox.checkTexture:SetShown(newState)
                end

                SyncDescendantsCheckedState(childKey, newState)
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
                    SyncDescendantsCheckedState(option.key, isChecked)
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

    -- Calculate total height used. totalRows is 0-indexed (last row index).
    -- So total rows = totalRows + 1 (if any options were placed).
    local usedRows = (#options > 0) and (totalRows + 1) or 0

    return yOffset - (usedRows * ROW_HEIGHT) - 15, widgets  -- Reduced spacing
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
                Settings_ShowWrappedTooltip(self, btnData.tooltip)
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
            Settings_ShowWrappedTooltip(self, desc)
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
    
    local valueText = FontManager:CreateFontString(dropdown, "body", "OVERLAY")
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
        
        local menuWidth = dropdown:GetWidth()
        
        -- Build ordered option rows (valueOrder keeps logical order; else sort by display text)
        local sortedOptions = {}
        if option.valueOrder then
            for i = 1, #option.valueOrder do
                local key = option.valueOrder[i]
                local displayText = values[key]
                if displayText ~= nil then
                    sortedOptions[#sortedOptions + 1] = { value = key, text = displayText }
                end
            end
            for value, displayText in pairs(values) do
                local seen
                for j = 1, #sortedOptions do
                    if sortedOptions[j].value == value then
                        seen = true
                        break
                    end
                end
                if not seen then
                    sortedOptions[#sortedOptions + 1] = { value = value, text = displayText }
                end
            end
        else
            for value, displayText in pairs(values) do
                sortedOptions[#sortedOptions + 1] = { value = value, text = displayText }
            end
            table.sort(sortedOptions, function(a, b) return a.text < b.text end)
        end
        
        local itemHeight = 28
        local menuPad = 6
        local scrollBarW = 22
        local contentHeight = math.min(#sortedOptions * itemHeight, 300)
        
        -- Reuse existing menu if available (Factory container for standard compliance)
        local menu = dropdown._dropdownMenu
        if not menu then
            menu = ns.UI.Factory:CreateContainer(UIParent, 200, 300, true)
            if menu then
                menu:SetFrameStrata("FULLSCREEN_DIALOG")
                menu:SetFrameLevel(300)
                menu:SetClampedToScreen(true)
                if ApplyVisuals then
                    ApplyVisuals(menu, {0.06, 0.06, 0.08, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
                end
            end
            dropdown._dropdownMenu = menu
        end
        
        -- Update menu size and position
        menu:SetSize(menuWidth, contentHeight + menuPad * 2)
        if option.menuOpensUpward then
            -- Avoid covering the next settings row (e.g. try-counter route → button below); tall menus are ~300px.
            menu:SetPoint("BOTTOMLEFT", dropdown, "TOPLEFT", 0, 2)
        else
            menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        end
        
        -- Clear existing children (scrollFrame and buttons)
        local bin = ns.UI_RecycleBin
        local children = { menu:GetChildren() }
        for _, child in ipairs(children) do
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
        
        activeMenu = menu
        
        -- ScrollFrame (Collections pattern: bar column + PositionScrollBarInContainer)
        local scrollFrame = ns.UI.Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", menuPad, -menuPad)
        scrollFrame:SetPoint("BOTTOMRIGHT", -scrollBarW, menuPad)
        scrollFrame:EnableMouseWheel(true)

        local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(menu, scrollBarW, menuPad, menuPad)
        if scrollFrame.ScrollBar and ns.UI.Factory.PositionScrollBarInContainer then
            ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end

        local btnWidth = menuWidth - menuPad - scrollBarW
        
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
            local btn = ns.UI.Factory:CreateButton(scrollChild, btnWidth, itemHeight, true)
            if not btn then break end
            btn:SetPoint("TOPLEFT", 0, -yPos)
            
            local isCurrent = (currentValue == data.value)
            local bgColor = isCurrent and {0.12, 0.12, 0.16, 1} or {0.07, 0.07, 0.09, 1}
            local borderColor = isCurrent and {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8} or {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4}
            
            if ApplyVisuals then
                ApplyVisuals(btn, bgColor, borderColor)
            end
            
            local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
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
        
        -- Close on ESC (combat-safe)
        if not InCombatLockdown() then menu:SetPropagateKeyboardInput(false) end
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
            clickCatcher = ns.UI.Factory:CreateContainer(UIParent, 1, 1, false)
            if clickCatcher then
                clickCatcher:SetAllPoints()
                clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                clickCatcher:SetFrameLevel(menu:GetFrameLevel() - 1)
                clickCatcher:EnableMouse(true)
                clickCatcher:SetScript("OnMouseDown", function()
                    menu:Hide()
                    activeMenu = nil
                    clickCatcher:Hide()
                end)
            end
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
    
    -- Label + gap + 32px control + margin before next row
    return yOffset - 82, dropdown, label
end

---Create styled input (EditBox) widget
---@param parent Frame Parent container
---@param option table {name, desc, width, get, set, numeric}
---@param yOffset number Starting Y offset
---@return number newYOffset
---@return EditBox editBox The created EditBox reference
local function CreateInputWidget(parent, option, yOffset)
    -- Label
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    local optionName = type(option.name) == "function" and option.name() or option.name
    label:SetText(optionName)
    label:SetTextColor(1, 1, 1, 1)

    -- Tooltip on label
    if option.desc then
        label:SetScript("OnEnter", function(self)
            local desc = type(option.desc) == "function" and option.desc() or option.desc
            Settings_ShowWrappedTooltip(self, desc)
        end)
        label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- EditBox (Factory for standard compliance)
    local editBox = ns.UI.Factory:CreateEditBox(parent)
    if not editBox then return yOffset - 68, nil end
    editBox:SetHeight(30)
    local boxWidth = option.width or 200
    editBox:SetWidth(boxWidth)
    editBox:SetPoint("TOPLEFT", 0, yOffset - 22)
    editBox:SetTextInsets(10, 10, 0, 0)
    editBox:SetMaxLetters(option.maxLetters or 128)

    if option.numeric then
        editBox:SetNumeric(false) -- We handle numeric validation ourselves
    end

    if ApplyVisuals then
        ApplyVisuals(editBox, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end

    -- Set initial value
    if option.get then
        local val = option.get()
        editBox:SetText(val or "")
    end

    -- On enter pressed or focus lost → commit value
    local function CommitValue()
        if option.set then
            option.set(editBox:GetText())
        end
        editBox:ClearFocus()
    end

    editBox:SetScript("OnEnterPressed", CommitValue)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    editBox:SetScript("OnEditFocusLost", CommitValue)

    -- Hover effect
    editBox:SetScript("OnEnter", function(self)
        if ApplyVisuals then
            ApplyVisuals(self, {0.10, 0.10, 0.12, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
    end)
    editBox:SetScript("OnLeave", function(self)
        if ApplyVisuals then
            ApplyVisuals(self, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
        end
    end)

    return yOffset - 68, editBox
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
            Settings_ShowWrappedTooltip(self, desc)
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
    local bin = ns.UI_RecycleBin
    for _, child in pairs({parent:GetChildren()}) do
        child:Hide()
        if bin then child:SetParent(bin) else child:SetParent(nil) end
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
            key = "showTooltipItemCount",
            label = (ns.L and ns.L["CONFIG_SHOW_ITEMS_TOOLTIP"]) or "Show Items in Tooltips",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"]) or "Display Warband and Character item counts in item tooltips.",
            get = function() return WarbandNexus.db.profile.showTooltipItemCount ~= false end,
            set = function(value) WarbandNexus.db.profile.showTooltipItemCount = value end,
        },
        {
            key = "requestPlayedTimeOnLogin",
            label = (ns.L and ns.L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"]) or "Request played time on login",
            tooltip = (ns.L and ns.L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"]) or "When enabled, the addon requests /played data in the background to update statistics. Chat output from that request is suppressed. When disabled, no automatic request on login.",
            get = function() return WarbandNexus.db.profile.requestPlayedTimeOnLogin ~= false end,
            set = function(value) WarbandNexus.db.profile.requestPlayedTimeOnLogin = value end,
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
            key = "minimapVisible",
            label = (ns.L and ns.L["CONFIG_MINIMAP"]) or "Minimap Button",
            tooltip = (ns.L and ns.L["CONFIG_MINIMAP_DESC"]) or "Show a button on the minimap for quick access.",
            get = function() return not WarbandNexus.db.profile.minimap.hide end,
            set = function(value)
                if WarbandNexus.SetMinimapButtonVisible then
                    WarbandNexus:SetMinimapButtonVisible(value)
                else
                    WarbandNexus.db.profile.minimap.hide = not value
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
        {
            key = "recipeCompanionEnabled",
            label = (ns.L and ns.L["CONFIG_RECIPE_COMPANION"]) or "Recipe Companion",
            tooltip = (ns.L and ns.L["CONFIG_RECIPE_COMPANION_DESC"]) or "Show the Recipe Companion window alongside the Professions UI, displaying reagent availability per character.",
            get = function() return WarbandNexus.db.profile.recipeCompanionEnabled ~= false end,
            set = function(value)
                WarbandNexus.db.profile.recipeCompanionEnabled = value
                if not value and ns.RecipeCompanionWindow then
                    ns.RecipeCompanionWindow.Hide()
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
        local langTooltip = (ns.L and ns.L["LANGUAGE_TOOLTIP"]) or "Addon uses your WoW game client's language automatically. To change, update your Battle.net settings."
        Settings_ShowWrappedTooltip(self, langTooltip)
    end)
    langLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Keybinding row (label + capture button + clear button)
    local keybindTitle = (ns.L and ns.L["KEYBINDING"]) or "Keybinding"
    local keybindLabel = FontManager:CreateFontString(generalSection.content, "body", "OVERLAY")
    keybindLabel:SetPoint("TOPLEFT", 0, generalGridYOffset - 45)
    keybindLabel:SetJustifyH("LEFT")
    keybindLabel:SetText(keybindTitle .. ":")
    keybindLabel:SetTextColor(1, 1, 1, 1)

    local keybindBtn = CreateFrame("Button", nil, generalSection.content, "BackdropTemplate")
    keybindBtn:SetSize(160, 26)
    keybindBtn:SetPoint("LEFT", keybindLabel, "RIGHT", 10, 0)
    if ApplyVisuals then
        ApplyVisuals(keybindBtn, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    local keybindBtnText = FontManager:CreateFontString(keybindBtn, "body", "OVERLAY")
    keybindBtnText:SetPoint("CENTER")
    keybindBtnText:SetText(GetToggleBindingDisplayText())
    keybindBtnText:SetTextColor(1, 1, 1, 1)

    local isListening = false

    local function StopListening()
        isListening = false
        keybindBtn:EnableKeyboard(false)
        keybindBtnText:SetText(GetToggleBindingDisplayText())
        keybindBtnText:SetTextColor(1, 1, 1, 1)
        if ApplyVisuals then
            ApplyVisuals(keybindBtn, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end

    local function StartListening()
        if InCombatLockdown() then return end
        isListening = true
        keybindBtn:EnableKeyboard(true)
        keybindBtnText:SetText((ns.L and ns.L["KEYBINDING_PRESS_KEY"]) or "Press a key...")
        keybindBtnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        if ApplyVisuals then
            ApplyVisuals(keybindBtn, {0.12, 0.08, 0.18, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
        end
    end

    keybindBtn:SetScript("OnClick", function()
        if isListening then
            StopListening()
        else
            StartListening()
        end
    end)

    keybindBtn:SetScript("OnKeyDown", function(_, key)
        if not isListening then return end
        if IGNORED_KEYS[key] then return end

        if key == "ESCAPE" then
            StopListening()
            return
        end

        if InCombatLockdown() then
            if WarbandNexus and WarbandNexus.Print then
                WarbandNexus:Print("|cffff6600" .. ((ns.L and ns.L["KEYBINDING_COMBAT"]) or "Cannot change keybindings in combat.") .. "|r")
            end
            StopListening()
            return
        end

        local prefix = ""
        if IsShiftKeyDown() then prefix = "SHIFT-" end
        if IsControlKeyDown() then prefix = "CTRL-" .. prefix end
        if IsAltKeyDown() then prefix = "ALT-" .. prefix end

        local fullKey = prefix .. key
        SaveToggleKeybind(fullKey)

        if WarbandNexus and WarbandNexus.Print then
            WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["KEYBINDING_SAVED"]) or "Keybinding saved.") .. "|r")
        end

        StopListening()
    end)

    keybindBtn:SetScript("OnEnter", function(self)
        local t = (ns.L and ns.L["KEYBINDING_TOOLTIP"]) or "Click to set a keybinding for toggling Warband Nexus.\nPress ESC to cancel."
        Settings_ShowWrappedTooltip(self, t)
    end)
    keybindBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Clear binding button
    local clearBtn = CreateFrame("Button", nil, generalSection.content, "BackdropTemplate")
    clearBtn:SetSize(24, 24)
    clearBtn:SetPoint("LEFT", keybindBtn, "RIGHT", 6, 0)
    if ApplyVisuals then
        ApplyVisuals(clearBtn, {0.15, 0.08, 0.08, 1}, {0.6, 0.2, 0.2, 0.8})
    end

    local clearIcon = clearBtn:CreateTexture(nil, "ARTWORK")
    clearIcon:SetSize(12, 12)
    clearIcon:SetPoint("CENTER")
    clearIcon:SetAtlas("uitools-icon-close")
    clearIcon:SetVertexColor(0.9, 0.3, 0.3)

    clearBtn:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        SaveToggleKeybind(nil)
        StopListening()
    end)
    clearBtn:SetScript("OnEnter", function(self)
        clearIcon:SetVertexColor(1, 0.2, 0.2)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["KEYBINDING_CLEAR"]) or "Clear keybinding")
    end)
    clearBtn:SetScript("OnLeave", function()
        clearIcon:SetVertexColor(0.9, 0.3, 0.3)
        GameTooltip:Hide()
    end)

    -- Scroll speed slider (below keybinding row) – scale multiplier
    local scrollSpeedYOffset = generalGridYOffset - 80
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
    
    -- UI Scale slider (below scroll speed) – scales entire addon window
    local uiScaleYOffset = CreateSliderWidget(generalSection.content, {
        name = (ns.L and ns.L["UI_SCALE"]) or "UI Scale",
        desc = (ns.L and ns.L["UI_SCALE_TOOLTIP"]) or "Scale the entire addon window. Reduce if the window takes up too much screen space.",
        min = 0.6,
        max = 1.5,
        step = 0.05,
        get = function() return WarbandNexus.db.profile.uiScale or 1.0 end,
        set = function(_, value)
            value = math.floor(value * 20 + 0.5) / 20
            WarbandNexus.db.profile.uiScale = value
            if WarbandNexus.ApplyUIScale then
                WarbandNexus:ApplyUIScale(value)
            end
        end,
        valueFormat = function(v) return string.format("%d%%", v * 100) end,
    }, scrollSpeedYOffset, sliderElements)
    
    -- Calculate section height (content height + title + bottom padding)
    local contentHeight = math.abs(uiScaleYOffset) + 10
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
    
    local moduleGridYOffset = -45
    
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
        {
            key = "gear",
            label = (ns.L and ns.L["MODULE_GEAR"]) or "Gear",
            tooltip = (ns.L and ns.L["MODULE_GEAR_DESC"]) or "Gear management and item level tracking across characters",
            get = function() return WarbandNexus.db.profile.modulesEnabled.gear ~= false end,
            set = function(value)
                WarbandNexus.db.profile.modulesEnabled.gear = value
                WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "gear", value)
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "collections",
            label = (ns.L and ns.L["MODULE_COLLECTIONS"]) or "Collections",
            tooltip = (ns.L and ns.L["MODULE_COLLECTIONS_DESC"]) or "Mounts, pets, toys, transmog, and collection overview",
            get = function() return WarbandNexus.db.profile.modulesEnabled.collections ~= false end,
            set = function(value)
                WarbandNexus.db.profile.modulesEnabled.collections = value
                WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "collections", value)
                if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            end,
        },
        {
            key = "tryCounter",
            label = (ns.L and ns.L["MODULE_TRY_COUNTER"]) or "Try Counter",
            tooltip = (ns.L and ns.L["MODULE_TRY_COUNTER_DESC"]) or "Automatic drop attempt tracking for NPC kills, bosses, fishing, and containers. Disabling stops all try count processing, tooltips, and notifications.",
            get = function() return WarbandNexus.db.profile.modulesEnabled.tryCounter ~= false end,
            set = function(value)
                if WarbandNexus.SetTryCounterModuleEnabled then
                    WarbandNexus:SetTryCounterModuleEnabled(value)
                else
                    WarbandNexus.db.profile.modulesEnabled.tryCounter = value
                    WarbandNexus:SendMessage("WN_MODULE_TOGGLED", "tryCounter", value)
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
            key = "updateNotes",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES"]) or "Show Update Notes",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_UPDATE_NOTES_DESC"]) or "Display the What's New window on next login.",
            get = function() return WarbandNexus.db.profile.notifications.showUpdateNotes end,
            set = function(value) WarbandNexus.db.profile.notifications.showUpdateNotes = value end,
        },
        {
            key = "loginChat",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_SHOW_LOGIN_CHAT"]) or "Login message in chat",
            tooltip = (ns.L and ns.L["CONFIG_SHOW_LOGIN_CHAT_DESC"]) or "Print a short welcome line when notifications are on. Visible in custom chat (e.g. Chattynator); the What's New window is separate.",
            get = function() return WarbandNexus.db.profile.notifications.showLoginChat ~= false end,
            set = function(value) WarbandNexus.db.profile.notifications.showLoginChat = value end,
        },
        {
            key = "hidePlayedTime",
            parentKey = "enabled",
            label = (ns.L and ns.L["CONFIG_HIDE_PLAYED_TIME_CHAT"]) or "Hide Time Played in chat",
            tooltip = (ns.L and ns.L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"]) or "Remove Total time played / Time played this level from chat (system messages). Disable this if you want those lines or /played output.",
            get = function() return WarbandNexus.db.profile.notifications.hidePlayedTimeInChat ~= false end,
            set = function(value)
                WarbandNexus.db.profile.notifications.hidePlayedTimeInChat = value
                if WarbandNexus.UpdateChatFilter then
                    WarbandNexus:UpdateChatFilter()
                end
            end,
        },
        {
            key = "loot",
            parentKey = "enabled",
            label = (ns.L and ns.L["LOOT_ALERTS"]) or "New Collectible Popup",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TOOLTIP"]) or "Master toggle for collectible popups. Disabling this hides all collectible notifications.",
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showLootNotifications = value end,
        },
        {
            key = "lootMount",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_MOUNT"]) or "Mount Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_MOUNT_TOOLTIP"]) or "Show notifications when you collect a new mount.",
            get = function() return WarbandNexus.db.profile.notifications.showMountNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showMountNotifications = value end,
        },
        {
            key = "lootPet",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_PET"]) or "Pet Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_PET_TOOLTIP"]) or "Show notifications when you collect a new pet.",
            get = function() return WarbandNexus.db.profile.notifications.showPetNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showPetNotifications = value end,
        },
        {
            key = "lootToy",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_TOY"]) or "Toy Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TOY_TOOLTIP"]) or "Show notifications when you collect a new toy.",
            get = function() return WarbandNexus.db.profile.notifications.showToyNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showToyNotifications = value end,
        },
        {
            key = "lootTransmog",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_TRANSMOG"]) or "Appearance Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TRANSMOG_TOOLTIP"]) or "Show notifications when you collect a new armor or weapon appearance.",
            get = function() return WarbandNexus.db.profile.notifications.showTransmogNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showTransmogNotifications = value end,
        },
        {
            key = "lootIllusion",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_ILLUSION"]) or "Illusion Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_ILLUSION_TOOLTIP"]) or "Show notifications when you collect a new weapon illusion.",
            get = function() return WarbandNexus.db.profile.notifications.showIllusionNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showIllusionNotifications = value end,
        },
        {
            key = "lootTitle",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_TITLE"]) or "Title Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_TITLE_TOOLTIP"]) or "Show notifications when you earn a new title.",
            get = function() return WarbandNexus.db.profile.notifications.showTitleNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showTitleNotifications = value end,
        },
        {
            key = "lootAchievement",
            parentKey = "loot",
            label = (ns.L and ns.L["LOOT_ALERTS_ACHIEVEMENT"]) or "Achievement Notifications",
            tooltip = (ns.L and ns.L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"]) or "Show notifications when you earn a new achievement.",
            get = function() return WarbandNexus.db.profile.notifications.showAchievementNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showAchievementNotifications = value end,
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
            key = "showCriteriaProgress",
            parentKey = "loot",
            label = (ns.L and ns.L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS"]) or "Criteria Progress Toast",
            tooltip = (ns.L and ns.L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS_TOOLTIP"]) or "Show a small notification when an achievement criteria is completed (Progress X/Y and criteria name).",
            get = function() return WarbandNexus.db.profile.notifications.showCriteriaProgressNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showCriteriaProgressNotifications = value end,
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
            key = "hideTryCounterChat",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["HIDE_TRY_COUNTER_CHAT"]) or "Hide Attempts on Chat",
            tooltip = (ns.L and ns.L["HIDE_TRY_COUNTER_CHAT_TOOLTIP"])
                or "Suppress all try counter messages in chat ([WN-Counter], [WN-Drops], obtained/caught lines). Counting continues normally — only chat output is hidden.",
            get = function() return WarbandNexus.db.profile.notifications.hideTryCounterChat == true end,
            set = function(value) WarbandNexus.db.profile.notifications.hideTryCounterChat = value end,
        },
        {
            key = "tryCounterInstanceEntryDropLines",
            parentKey = "autoTryCounter",
            label = (ns.L and ns.L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES"]) or "Instance entry: list drops in chat",
            tooltip = (ns.L and ns.L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES_TOOLTIP"])
                or "Print [WN-Drops] lines on dungeon/raid entry with difficulty colors vs your current instance, or turn off for a one-line hint only.",
            get = function()
                local v = WarbandNexus.db.profile.notifications.tryCounterInstanceEntryDropLines
                if v == false then return false end
                return true
            end,
            set = function(value) WarbandNexus.db.profile.notifications.tryCounterInstanceEntryDropLines = value end,
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

    -- Try counter: where chat lines go (Loot vs own group vs all tabs)
    notifGridYOffset = notifGridYOffset - 8
    local tcChatRouteDropdown, tcChatRouteLabel
    notifGridYOffset, tcChatRouteDropdown, tcChatRouteLabel = CreateDropdownWidget(notifSection.content, {
        name = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_LABEL"]) or "Try counter chat output",
        desc = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_DESC"])
            or "Default uses the same tabs as Loot messages. “Warband Nexus” is a separate filter you can enable per tab (often listed in the chat tab settings). “All tabs” prints to every standard chat window.",
        -- Open downward: upward menus covered the label and checkbox rows above this control.
        menuOpensUpward = false,
        valueOrder = { "loot", "dedicated", "all_tabs" },
        values = {
            loot = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_LOOT"]) or "1) Same tabs as Loot (default)",
            dedicated = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"]) or "2) Warband Nexus (separate filter)",
            all_tabs = (ns.L and ns.L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"]) or "3) All standard chat tabs",
        },
        get = function()
            return WarbandNexus.db.profile.notifications.tryCounterChatRoute or "loot"
        end,
        set = function(_, value)
            WarbandNexus.db.profile.notifications.tryCounterChatRoute = value
            if ns.ChatOutput and ns.ChatOutput.OnTryCounterChatRouteChanged then
                ns.ChatOutput.OnTryCounterChatRouteChanged(value)
            end
        end,
    }, notifGridYOffset)

    -- Extra gap so the open dropdown list (below the button) does not cover "Add try counter…"
    notifGridYOffset = notifGridYOffset - (14 + 92)
    local addTcChatBtn = ns.UI.Factory:CreateButton(notifSection.content)
    addTcChatBtn:SetSize(math.min(effectiveWidth - 30, 320), 30)
    addTcChatBtn:SetPoint("TOPLEFT", 0, notifGridYOffset)
    local addTcChatBtnText = addTcChatBtn:GetFontString() or FontManager:CreateFontString(addTcChatBtn, "body", "OVERLAY")
    addTcChatBtnText:SetPoint("CENTER")
    addTcChatBtnText:SetText((ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"]) or "Add try counter to selected chat tab")
    addTcChatBtn:SetFontString(addTcChatBtnText)
    if ApplyVisuals then
        ApplyVisuals(addTcChatBtn, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    addTcChatBtn:SetScript("OnEnter", function(self)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"])
            or "Select the chat tab you want, then click. Use with “Warband Nexus (separate filter)” mode so try lines are not tied to Loot.")
    end)
    addTcChatBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    addTcChatBtn:SetScript("OnClick", function()
        if ns.ChatOutput and ns.ChatOutput.AddTryCounterGroupToSelectedChatFrame then
            local ok, err = ns.ChatOutput.AddTryCounterGroupToSelectedChatFrame()
            if ok and WarbandNexus.Print then
                WarbandNexus:Print((ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"]) or "|cff9966ff[Warband Nexus]|r Try counter enabled on the selected chat tab.")
            elseif WarbandNexus.Print then
                WarbandNexus:Print((ns.L and ns.L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"]) or "|cffff6600[Warband Nexus]|r Could not update the chat tab (no chat frame or API blocked).")
            end
        end
    end)
    notifGridYOffset = notifGridYOffset - 40
    
    -- Track external dependents (sliders, buttons) that should disable when notifications are OFF
    local notifExternalDependents = {}

    -- Chat-dependent widgets: disabled when hideTryCounterChat is checked OR autoTryCounter is off
    local tcChatDependents = { tcChatRouteDropdown, tcChatRouteLabel, addTcChatBtn }
    local function ApplyHideTryCounterChatCascade()
        local chatHidden = WarbandNexus.db and WarbandNexus.db.profile
            and WarbandNexus.db.profile.notifications
            and WarbandNexus.db.profile.notifications.hideTryCounterChat
        local autoOff = not (WarbandNexus.db and WarbandNexus.db.profile
            and WarbandNexus.db.profile.notifications
            and WarbandNexus.db.profile.notifications.autoTryCounter)
        local shouldDisable = chatHidden or autoOff
        for _, w in ipairs(tcChatDependents) do
            if w then
                if shouldDisable then
                    if w.Disable then w:Disable() end
                    w:SetAlpha(0.35)
                else
                    if w.Enable then w:Enable() end
                    w:SetAlpha(1.0)
                end
            end
        end
        local entryW = notifWidgets["tryCounterInstanceEntryDropLines"]
        if entryW then
            SetCheckboxDisabled(entryW.checkbox, entryW.label, shouldDisable)
        end
    end

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
        if key == "hideTryCounterChat" or key == "autoTryCounter" then
            ApplyHideTryCounterChatCascade()
        end
    end
    ApplyHideTryCounterChatCascade()
    
    -- ---- Notification Duration ----
    notifGridYOffset = notifGridYOffset - 15
    local durationLabel = FontManager:CreateFontString(notifSection.content, "subtitle", "OVERLAY")
    durationLabel:SetPoint("TOPLEFT", 0, notifGridYOffset)
    durationLabel:SetText((ns.L and ns.L["NOTIFICATION_DURATION"]) or "Notification Duration")
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
    
    -- ---- Notification Position ----
    notifGridYOffset = notifGridYOffset - 10
    local posLabel = FontManager:CreateFontString(notifSection.content, "subtitle", "OVERLAY")
    posLabel:SetPoint("TOPLEFT", 0, notifGridYOffset)
    posLabel:SetText((ns.L and ns.L["NOTIFICATION_POSITION"]) or "Notification Position")
    posLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, posLabel)
    notifGridYOffset = notifGridYOffset - 22

    local anchorFormat = (ns.L and ns.L["ANCHOR_FORMAT"]) or "Anchor: %s  |  X: %d  |  Y: %d"
    local anchorDesc = FontManager:CreateFontString(notifSection.content, "body", "OVERLAY")
    anchorDesc:SetPoint("TOPLEFT", 0, notifGridYOffset)
    anchorDesc:SetPoint("TOPRIGHT", -10, notifGridYOffset)
    anchorDesc:SetJustifyH("LEFT")
    anchorDesc:SetTextColor(0.7, 0.7, 0.7, 1)

    local function UpdateAnchorDesc()
        local db = WarbandNexus.db.profile.notifications
        if db.useAlertFramePosition then
            anchorDesc:SetText((ns.L and ns.L["USE_ALERTFRAME_POSITION_ACTIVE"]) or "Using Blizzard AlertFrame position")
        else
            local pt = db.popupPoint or "TOP"
            local x, y = db.popupX or 0, db.popupY or -100
            local line1 = string.format(anchorFormat, pt, x, y)
            if db.popupPointCompact and (db.popupPointCompact ~= pt or (db.popupXCompact or 0) ~= x or (db.popupYCompact or -100) ~= y) then
                local ptC = db.popupPointCompact or "TOP"
                local xC, yC = db.popupXCompact or 0, db.popupYCompact or -100
                anchorDesc:SetText(line1 .. "\n" .. ((ns.L and ns.L["NOTIFICATION_GHOST_CRITERIA"]) or "Criteria") .. ": " .. string.format(anchorFormat, ptC, xC, yC))
            else
                anchorDesc:SetText(line1)
            end
        end
    end
    UpdateAnchorDesc()
    -- Reserve space for two lines (main + criteria) so buttons never overlap the anchor text
    notifGridYOffset = notifGridYOffset - 44

    -- Forward declaration for shared handlers below.
    local useAlertFrameCheck

    local btnWidth = math.floor((effectiveWidth - 45) / 4)
    local setPosBtn = ns.UI.Factory:CreateButton(notifSection.content)
    setPosBtn:SetSize(btnWidth, 30)
    setPosBtn:SetPoint("TOPLEFT", 0, notifGridYOffset)
    local setPosBtnText = setPosBtn:GetFontString() or FontManager:CreateFontString(setPosBtn, "body", "OVERLAY")
    setPosBtnText:SetPoint("CENTER")
    setPosBtnText:SetText((ns.L and ns.L["SET_POSITION"]) or "Set Position")
    setPosBtn:SetFontString(setPosBtnText)
    local function saveGhostPosition(ghost, forCriteria)
        ghost:StopMovingOrSizing()
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        local left, top = ghost:GetLeft(), ghost:GetTop()
        local w = ghost:GetWidth()
        local centerX = left + (w / 2)
        local centerY = top - (ghost:GetHeight() / 2)
        local anchorPoint, offsetX, offsetY
        if centerY > (screenH * 0.6) then
            anchorPoint = "TOP"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(top - screenH)
        elseif centerY < (screenH * 0.4) then
            anchorPoint = "BOTTOM"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(top - ghost:GetHeight())
        else
            anchorPoint = "CENTER"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(centerY - (screenH / 2))
        end
        local db = WarbandNexus.db.profile.notifications
        if forCriteria then
            db.popupPointCompact = anchorPoint
            db.popupXCompact = offsetX
            db.popupYCompact = offsetY
        else
            db.popupPoint = anchorPoint
            db.popupX = offsetX
            db.popupY = offsetY
        end
        db.useAlertFramePosition = false
        if useAlertFrameCheck then useAlertFrameCheck:SetChecked(false); if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(false) end end
        UpdateAnchorDesc()
    end

    local function saveGhostPositionBoth(ghost)
        ghost:StopMovingOrSizing()
        local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
        local left, top = ghost:GetLeft(), ghost:GetTop()
        local w = ghost:GetWidth()
        local centerX = left + (w / 2)
        local centerY = top - (ghost:GetHeight() / 2)
        local anchorPoint, offsetX, offsetY
        if centerY > (screenH * 0.6) then
            anchorPoint = "TOP"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(top - screenH)
        elseif centerY < (screenH * 0.4) then
            anchorPoint = "BOTTOM"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(top - ghost:GetHeight())
        else
            anchorPoint = "CENTER"
            offsetX = math.floor(centerX - (screenW / 2))
            offsetY = math.floor(centerY - (screenH / 2))
        end
        local db = WarbandNexus.db.profile.notifications
        db.popupPoint = anchorPoint
        db.popupX = offsetX
        db.popupY = offsetY
        db.popupPointCompact = anchorPoint
        db.popupXCompact = offsetX
        db.popupYCompact = offsetY
        db.useAlertFramePosition = false
        if useAlertFrameCheck then useAlertFrameCheck:SetChecked(false); if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(false) end end
        UpdateAnchorDesc()
    end

    local function closePositionGhosts()
        if WarbandNexus._positionGhost then WarbandNexus._positionGhost:Hide() WarbandNexus._positionGhost = nil end
        if WarbandNexus._positionGhostCriteria then WarbandNexus._positionGhostCriteria:Hide() WarbandNexus._positionGhostCriteria = nil end
    end

    setPosBtn:SetScript("OnClick", function()
        if WarbandNexus.db.profile.notifications.useAlertFramePosition then return end
        if WarbandNexus._positionGhost then closePositionGhosts() return end
        local db = WarbandNexus.db.profile.notifications
        local pt = db.popupPoint or "TOP"
        local px, py = db.popupX or 0, db.popupY or -100
        local ptC = db.popupPointCompact or pt
        local pxC, pyC = db.popupXCompact or px, db.popupYCompact or py

        local ghost = ns.UI.Factory:CreateContainer(UIParent, 400, 88, true)
        if ghost then
            ghost:SetFrameStrata("DIALOG")
            ghost:SetFrameLevel(2000)
            ghost:SetMovable(true)
            ghost:EnableMouse(true)
            ghost:RegisterForDrag("LeftButton")
            ghost:SetClampedToScreen(true)
            if ApplyVisuals then ApplyVisuals(ghost, {0.1, 0.6, 0.1, 0.7}, {0, 1, 0, 1}) end
            local ghostText = FontManager:CreateFontString(ghost, "body", "OVERLAY")
            ghostText:SetPoint("CENTER")
            ghostText:SetText((ns.L and ns.L["NOTIFICATION_GHOST_MAIN"]) or "Achievement / notification")
            ghostText:SetTextColor(1, 1, 1, 1)
            ghost:SetPoint(pt, UIParent, pt, px, py)
            ghost:SetScript("OnDragStart", function(self) self:StartMoving() end)
            ghost:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
            ghost:SetScript("OnMouseDown", function(self, button)
                if button == "RightButton" then
                    saveGhostPosition(self, false)
                    closePositionGhosts()
                    WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
                end
            end)
            ghost:Show()
        end
        WarbandNexus._positionGhost = ghost

        local ghostCriteria = ns.UI.Factory:CreateContainer(UIParent, 260, 64, true)
        if ghostCriteria then
        ghostCriteria:SetFrameStrata("DIALOG")
        ghostCriteria:SetFrameLevel(1999)
        ghostCriteria:SetMovable(true)
        ghostCriteria:EnableMouse(true)
        ghostCriteria:RegisterForDrag("LeftButton")
        ghostCriteria:SetClampedToScreen(true)
        if ApplyVisuals then ApplyVisuals(ghostCriteria, {0.1, 0.35, 0.55, 0.75}, {0.2, 0.6, 1, 1}) end
        local ghostCriteriaText = FontManager:CreateFontString(ghostCriteria, "body", "OVERLAY")
        ghostCriteriaText:SetPoint("CENTER")
        ghostCriteriaText:SetText((ns.L and ns.L["NOTIFICATION_GHOST_CRITERIA"]) or "Criteria progress")
        ghostCriteriaText:SetTextColor(1, 1, 1, 1)
        ghostCriteria:SetPoint(ptC, UIParent, ptC, pxC, pyC)
        ghostCriteria:SetScript("OnDragStart", function(self) self:StartMoving() end)
        ghostCriteria:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        ghostCriteria:SetScript("OnMouseDown", function(self, button)
            if button == "RightButton" then
                saveGhostPosition(self, true)
                closePositionGhosts()
                WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
            end
        end)
        ghostCriteria:Show()
        end
        WarbandNexus._positionGhostCriteria = ghostCriteria

        WarbandNexus:Print("|cffffcc00" .. ((ns.L and ns.L["DRAG_POSITION_MSG"]) or "Drag green = notification, blue = criteria. Right-click on one to save and close.") .. "|r")
    end)

    local setBothPosBtn = ns.UI.Factory:CreateButton(notifSection.content)
    setBothPosBtn:SetSize(btnWidth, 30)
    setBothPosBtn:SetPoint("LEFT", setPosBtn, "RIGHT", 5, 0)
    local setBothPosBtnText = setBothPosBtn:GetFontString() or FontManager:CreateFontString(setBothPosBtn, "body", "OVERLAY")
    setBothPosBtnText:SetPoint("CENTER")
    setBothPosBtnText:SetText((ns.L and ns.L["SET_BOTH_POSITION"]) or "Set Both Position")
    setBothPosBtn:SetFontString(setBothPosBtnText)
    setBothPosBtn:SetScript("OnClick", function()
        if WarbandNexus.db.profile.notifications.useAlertFramePosition then return end
        if WarbandNexus._positionGhost or WarbandNexus._positionGhostCriteria then closePositionGhosts() return end
        local db = WarbandNexus.db.profile.notifications
        local pt = db.popupPoint or "TOP"
        local px, py = db.popupX or 0, db.popupY or -100
        local ghost = ns.UI.Factory:CreateContainer(UIParent, 400, 88, true)
        if ghost then
            ghost:SetFrameStrata("DIALOG")
            ghost:SetFrameLevel(2000)
            ghost:SetMovable(true)
            ghost:EnableMouse(true)
            ghost:RegisterForDrag("LeftButton")
            ghost:SetClampedToScreen(true)
            if ApplyVisuals then ApplyVisuals(ghost, {0.1, 0.6, 0.1, 0.7}, {0, 1, 0, 1}) end
            local ghostText = FontManager:CreateFontString(ghost, "body", "OVERLAY")
            ghostText:SetPoint("CENTER")
            ghostText:SetText((ns.L and ns.L["DRAG_TO_POSITION"]) or "Drag to position\nRight-click to confirm")
            ghostText:SetTextColor(1, 1, 1, 1)
            ghost:SetPoint(pt, UIParent, pt, px, py)
            ghost:SetScript("OnDragStart", function(self) self:StartMoving() end)
            ghost:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
            ghost:SetScript("OnMouseDown", function(self, button)
                if button == "RightButton" then
                    saveGhostPositionBoth(self)
                    closePositionGhosts()
                    WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_SAVED_MSG"]) or "Position saved!") .. "|r")
                end
            end)
            ghost:Show()
        end
        WarbandNexus._positionGhost = ghost
        WarbandNexus:Print("|cffffcc00" .. ((ns.L and ns.L["DRAG_BOTH_POSITION_MSG"]) or "Drag to position. Right-click to save same position for notification and criteria.") .. "|r")
    end)

    local resetBtn = ns.UI.Factory:CreateButton(notifSection.content)
    resetBtn:SetSize(btnWidth, 30)
    resetBtn:SetPoint("LEFT", setBothPosBtn, "RIGHT", 5, 0)
    local resetBtnText = resetBtn:GetFontString() or FontManager:CreateFontString(resetBtn, "body", "OVERLAY")
    resetBtnText:SetPoint("CENTER")
    resetBtnText:SetText((ns.L and ns.L["RESET_POSITION"]) or "Reset Position")
    resetBtn:SetFontString(resetBtnText)
    resetBtn:SetScript("OnClick", function()
        if WarbandNexus.db.profile.notifications.useAlertFramePosition then return end
        local db = WarbandNexus.db.profile.notifications
        db.popupPoint = "TOP"
        db.popupX = 0
        db.popupY = -100
        db.popupPointCompact = "TOP"
        db.popupXCompact = 0
        db.popupYCompact = -100
        db.useAlertFramePosition = false
        if useAlertFrameCheck then useAlertFrameCheck:SetChecked(false); if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(false) end end
        UpdateAnchorDesc()
        WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["POSITION_RESET_MSG"]) or "Position reset to default.") .. "|r")
    end)

    local testBtn = ns.UI.Factory:CreateButton(notifSection.content)
    testBtn:SetSize(btnWidth, 30)
    testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 5, 0)
    local testBtnText = testBtn:GetFontString() or FontManager:CreateFontString(testBtn, "body", "OVERLAY")
    testBtnText:SetPoint("CENTER")
    testBtnText:SetText((ns.L and ns.L["TEST_NOTIFICATION"]) or "Test Notification")
    testBtn:SetFontString(testBtnText)
    testBtn:SetScript("OnClick", function()
        if WarbandNexus.Notify then
            -- Always use current DB position (Notify reads from db at show time)
            WarbandNexus:Notify("achievement", (ns.L and ns.L["TEST_NOTIFICATION_TITLE"]) or "Test Notification", nil, { action = (ns.L and ns.L["TEST_NOTIFICATION_MSG"]) or "Position test" })
        end
    end)
    notifGridYOffset = notifGridYOffset - 40

    useAlertFrameCheck = CreateThemedCheckbox(notifSection.content)
    useAlertFrameCheck:SetPoint("TOPLEFT", 0, notifGridYOffset)
    local useAlertFrameLabel = FontManager:CreateFontString(notifSection.content, "body", "OVERLAY")
    useAlertFrameLabel:SetJustifyH("LEFT")
    useAlertFrameLabel:SetText((ns.L and ns.L["USE_ALERTFRAME_POSITION"]) or "Use AlertFrame position")
    useAlertFrameLabel:SetTextColor(1, 1, 1, 1)
    useAlertFrameLabel:SetPoint("LEFT", useAlertFrameCheck, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 8, 0)
    useAlertFrameCheck:SetChecked(WarbandNexus.db.profile.notifications.useAlertFramePosition)
    if useAlertFrameCheck.checkTexture then useAlertFrameCheck.checkTexture:SetShown(WarbandNexus.db.profile.notifications.useAlertFramePosition) end
    useAlertFrameCheck:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        WarbandNexus.db.profile.notifications.useAlertFramePosition = v
        if self.checkTexture then self.checkTexture:SetShown(v) end
        if v then setPosBtn:Disable() setPosBtn:SetAlpha(0.5) setBothPosBtn:Disable() setBothPosBtn:SetAlpha(0.5) resetBtn:Disable() resetBtn:SetAlpha(0.5) else setPosBtn:Enable() setPosBtn:SetAlpha(1) setBothPosBtn:Enable() setBothPosBtn:SetAlpha(1) resetBtn:Enable() resetBtn:SetAlpha(1) end
        UpdateAnchorDesc()
    end)
    if WarbandNexus.db.profile.notifications.useAlertFramePosition then setPosBtn:Disable() setPosBtn:SetAlpha(0.5) setBothPosBtn:Disable() setBothPosBtn:SetAlpha(0.5) resetBtn:Disable() resetBtn:SetAlpha(0.5) else setPosBtn:Enable() setBothPosBtn:Enable() resetBtn:Enable() end
    notifGridYOffset = notifGridYOffset - 30

    table.insert(notifExternalDependents, { type = "label", widget = durationLabel, color = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]} })
    if durationSlider then
        table.insert(notifExternalDependents, { type = "slider", widget = durationSlider, label = durationLabel })
    end
    table.insert(notifExternalDependents, { type = "label", widget = posLabel, color = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]} })
    table.insert(notifExternalDependents, { type = "label", widget = anchorDesc, color = {0.7, 0.7, 0.7} })
    table.insert(notifExternalDependents, { type = "button", widget = setPosBtn })
    table.insert(notifExternalDependents, { type = "button", widget = setBothPosBtn })
    table.insert(notifExternalDependents, { type = "button", widget = resetBtn })
    table.insert(notifExternalDependents, { type = "button", widget = testBtn })
    table.insert(notifExternalDependents, { type = "label", widget = useAlertFrameLabel, color = {1, 1, 1} })
    table.insert(notifExternalDependents, { type = "button", widget = useAlertFrameCheck })
    
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
        
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["COLOR_PICKER_TOOLTIP"]) or "Open WoW's native color picker wheel to choose a custom theme color")
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
                        if ns.WindowManager then
                            ns.WindowManager:Unregister(settingsFrame)
                        end
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

    -- Font anti-aliasing mode
    themeYOffset = CreateDropdownWidget(themeSection.content, {
        name = (ns.L and ns.L["ANTI_ALIASING"]) or "Anti-Aliasing",
        desc = (ns.L and ns.L["ANTI_ALIASING_DESC"]) or "Font edge rendering style (affects readability)",
        values = {
            none = "None (Smooth)",
            OUTLINE = "Outline (Default)",
            THICKOUTLINE = "Thick Outline (Bold)",
        },
        get = function() return WarbandNexus.db.profile.fonts.antiAliasing end,
        set = function(_, value)
            WarbandNexus.db.profile.fonts.antiAliasing = value
            if ns.FontManager and ns.FontManager.RefreshAllFonts then
                ns.FontManager:RefreshAllFonts()
            end
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
            tooltip = (ns.L and ns.L["RESOLUTION_NORMALIZATION_TOOLTIP"]) or "Adjust font sizes for your monitor resolution (4K vs 1080p). WoW UI Scale still scales text with the rest of the interface.",
            get = function() return WarbandNexus.db.profile.fonts.usePixelNormalization end,
            set = function(value)
                WarbandNexus.db.profile.fonts.usePixelNormalization = value
                if ns.FontManager and ns.FontManager.RefreshAllFonts then
                    ns.FontManager:RefreshAllFonts()
                end
                -- Rebuild settings window if open (after font change)
                C_Timer.After(0.1, function()
                    if settingsFrame and settingsFrame:IsShown() then
                        if ns.WindowManager then
                            ns.WindowManager:Unregister(settingsFrame)
                        end
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
    -- TRACK ITEM DB
    --========================================================================
    
    local trackSection = CreateSection(parent, (ns.L and ns.L["TRACK_ITEM_DB"]) or "Track Item DB", effectiveWidth)
    trackSection:SetPoint("TOPLEFT", 0, yOffset)
    trackSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- Collapsible: arrow + title aligned with other sections (15px left padding, same as CreateSection)
    local COLLAPSED_HEIGHT = CONTENT_PADDING_TOP  -- title bar only
    local trackIsCollapsed = true  -- default collapsed
    local HEADER_LEFT_INDENT = 15
    local ARROW_TITLE_GAP = 6
    
    local collapseArrow = trackSection:CreateTexture(nil, "OVERLAY")
    collapseArrow:SetSize(14, 14)
    collapseArrow:SetPoint("TOPLEFT", trackSection, "TOPLEFT", HEADER_LEFT_INDENT, -12)
    collapseArrow:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", false)
    
    local titleText = trackSection.titleText
    titleText:ClearAllPoints()
    titleText:SetPoint("LEFT", collapseArrow, "RIGHT", ARROW_TITLE_GAP, 0)
    titleText:SetPoint("RIGHT", trackSection, "RIGHT", -HEADER_LEFT_INDENT, 0)
    titleText:SetPoint("TOP", collapseArrow, "TOP")
    titleText:SetPoint("BOTTOM", collapseArrow, "BOTTOM")
    
    local collapseBtn = ns.UI.Factory:CreateButton(trackSection, 1, 24, true)
    if collapseBtn then
        collapseBtn:SetPoint("TOPLEFT", collapseArrow, "TOPLEFT")
        collapseBtn:SetPoint("BOTTOMRIGHT", titleText, "BOTTOMRIGHT")
    end
    
    local trackYOffset = 0
    local trackContentWidth = effectiveWidth - 30
    
    --================================================================
    -- SUB-PANEL: Item Tracking
    --================================================================
    
    local manageHeader = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    manageHeader:SetPoint("TOPLEFT", 0, trackYOffset)
    manageHeader:SetText("|cffffcc00" .. ((ns.L and ns.L["MANAGE_ITEMS"]) or "Item Tracking") .. "|r")
    trackYOffset = trackYOffset - 20
    
    -- Build unique item list from CollectibleSourceDB
    local itemRegistry = {}   -- { [key] = { name, type, itemID, repeatable, guaranteed, sources } }
    local dropdownValues = {} -- { [key] = "Display Name" }
    
    local function RegisterDrop(drop, sourceType, sourceID)
        if not drop or not drop.itemID or not drop.name then return end
        local key = (drop.type or "item") .. ":" .. drop.itemID
        if not itemRegistry[key] then
            itemRegistry[key] = {
                name = drop.name,
                type = drop.type or "item",
                itemID = drop.itemID,
                repeatable = drop.repeatable or false,
                guaranteed = drop.guaranteed or false,
                sources = {},
            }
            local typeLabel = ""
            if drop.type == "mount" then typeLabel = "|cff00ccff[Mount]|r "
            elseif drop.type == "pet" then typeLabel = "|cff44ff44[Pet]|r "
            elseif drop.type == "toy" then typeLabel = "|cffff8800[Toy]|r "
            elseif drop.type == "illusion" then typeLabel = "|cffcc66ff[Illusion]|r "
            else typeLabel = "|cff888888[Item]|r " end
            dropdownValues[key] = typeLabel .. drop.name
        end
        local sources = itemRegistry[key].sources
        local found = false
        for _, s in ipairs(sources) do
            if s.sourceType == sourceType and s.sourceID == sourceID then
                found = true
                break
            end
        end
        if not found then
            sources[#sources + 1] = { sourceType = sourceType, sourceID = sourceID }
        end
    end
    
    do
        local db = ns.CollectibleSourceDB
        if db then
            for npcID, npcData in pairs(db.npcs or {}) do
                for i = 1, #npcData do RegisterDrop(npcData[i], "npc", npcID) end
            end
            for objID, objData in pairs(db.objects or {}) do
                for i = 1, #objData do RegisterDrop(objData[i], "object", objID) end
            end
            for zoneID, zoneData in pairs(db.fishing or {}) do
                for i = 1, #zoneData do RegisterDrop(zoneData[i], "fishing", zoneID) end
            end
            for containerID, cData in pairs(db.containers or {}) do
                local drops = cData.drops or cData
                if type(drops) == "table" then
                    for i = 1, #drops do RegisterDrop(drops[i], "container", containerID) end
                end
            end
        end
    end
    
    -- Persistent state
    if not ns._trackDBSelected then ns._trackDBSelected = {} end
    
    -- Detail card (subtle background panel for selected item info)
    local detailCard = ns.UI.Factory:CreateContainer(trackSection.content, trackContentWidth, 80, true)
    if detailCard and ApplyVisuals then
        ApplyVisuals(detailCard, {0.10, 0.10, 0.13, 0.7}, {0.25, 0.25, 0.30, 0.5})
    end
    
    -- Detail card children (created once, updated on selection)
    local detailNameText = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailNameText:SetPoint("TOPLEFT", 10, -8)
    detailNameText:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailNameText:SetJustifyH("LEFT")
    detailNameText:SetWordWrap(true)
    
    local detailInfoText = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailInfoText:SetPoint("TOPLEFT", 10, -26)
    detailInfoText:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailInfoText:SetJustifyH("LEFT")
    detailInfoText:SetTextColor(0.60, 0.60, 0.60)
    detailInfoText:SetWordWrap(true)
    
    -- Tracked checkbox (inside detail card)
    local trackedCheckbox = CreateThemedCheckbox(detailCard)
    trackedCheckbox:SetPoint("TOPLEFT", 8, -48)
    
    local trackedLabel = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    trackedLabel:SetPoint("LEFT", trackedCheckbox, "RIGHT", 6, 0)
    trackedLabel:SetText((ns.L and ns.L["TRACKED"]) or "Tracked")
    trackedLabel:SetTextColor(1, 1, 1, 1)
    
    -- Repeatable checkbox (inside detail card, right of Tracked)
    local repeatableCheckbox = CreateThemedCheckbox(detailCard)
    repeatableCheckbox:SetPoint("LEFT", trackedLabel, "RIGHT", 20, 0)
    
    local repeatableLabel = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    repeatableLabel:SetPoint("LEFT", repeatableCheckbox, "RIGHT", 6, 0)
    repeatableLabel:SetText((ns.L and ns.L["REPEATABLE_LABEL"]) or "Repeatable")
    repeatableLabel:SetTextColor(1, 1, 1, 1)
    
    -- Placeholder when nothing is selected
    local detailPlaceholder = FontManager:CreateFontString(detailCard, "body", "OVERLAY")
    detailPlaceholder:SetPoint("TOPLEFT", 10, -8)
    detailPlaceholder:SetPoint("RIGHT", detailCard, "RIGHT", -10, 0)
    detailPlaceholder:SetText("|cff555555" .. ((ns.L and ns.L["SELECT_ITEM_HINT"]) or "Select an item above to view details.") .. "|r")
    detailPlaceholder:SetJustifyH("LEFT")
    
    trackedCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(isChecked) end
        local sel = ns._trackDBSelected
        if not sel or not sel.key then return end
        local info = itemRegistry[sel.key]
        if not info then return end
        for _, src in ipairs(info.sources) do
            WarbandNexus:SetBuiltinTracked(src.sourceType, src.sourceID, info.itemID, isChecked)
        end
        local statusStr = isChecked
            and ("|cff00ff00" .. ((ns.L and ns.L["TRACKED"]) or "Tracked") .. "|r")
            or ("|cffff6600" .. ((ns.L and ns.L["UNTRACKED"]) or "Untracked") .. "|r")
        WarbandNexus:Print(format("|cff9370DB[WN]|r %s → %s", info.name, statusStr))
    end)
    
    repeatableCheckbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if self.checkTexture then self.checkTexture:SetShown(isChecked) end
        local sel = ns._trackDBSelected
        if not sel or not sel.key then return end
        local info = itemRegistry[sel.key]
        if not info then return end
        WarbandNexus:SetBuiltinRepeatable(info.type, info.itemID, isChecked)
        -- Update the info line to reflect the change
        info.repeatable = isChecked
        local repeatStr = isChecked
            and ("|cff00ff00" .. ((ns.L and ns.L["YES"]) or "Yes") .. "|r")
            or ("|cff666666" .. ((ns.L and ns.L["NO"]) or "No") .. "|r")
        WarbandNexus:Print(format("|cff9370DB[WN]|r %s → Repeatable: %s", info.name, repeatStr))
    end)
    
    local function IsItemFullyTracked(info)
        if not info or not info.sources then return true end
        for _, src in ipairs(info.sources) do
            if not WarbandNexus:IsBuiltinTracked(src.sourceType, src.sourceID, info.itemID) then
                return false
            end
        end
        return true
    end
    
    local function UpdateDetailPanel(key)
        local info = itemRegistry[key]
        if not info then
            detailPlaceholder:Show()
            detailNameText:SetText("")
            detailInfoText:SetText("")
            trackedCheckbox:Hide()
            trackedLabel:Hide()
            repeatableCheckbox:Hide()
            repeatableLabel:Hide()
            return
        end
        ns._trackDBSelected = { key = key }
        detailPlaceholder:Hide()
        
        -- Name with type color
        local typeColor = "ffffff"
        if info.type == "mount" then typeColor = "00ccff"
        elseif info.type == "pet" then typeColor = "44ff44"
        elseif info.type == "toy" then typeColor = "ff8800"
        elseif info.type == "illusion" then typeColor = "cc66ff" end
        detailNameText:SetText("|cff" .. typeColor .. info.name .. "|r")
        
        -- Info line (type + source count only, repeatable is now a checkbox)
        local typeName = info.type:sub(1,1):upper() .. info.type:sub(2)
        local srcCount = #info.sources
        local srcLabel = srcCount == 1 and ((ns.L and ns.L["SOURCE_SINGULAR"]) or "source") or ((ns.L and ns.L["SOURCE_PLURAL"]) or "sources")
        detailInfoText:SetText(format("%s  |cff444444·|r  %d %s", typeName, srcCount, srcLabel))
        
        -- Tracked checkbox
        local isTracked = IsItemFullyTracked(info)
        trackedCheckbox:SetChecked(isTracked)
        if trackedCheckbox.checkTexture then trackedCheckbox.checkTexture:SetShown(isTracked) end
        trackedCheckbox:Show()
        trackedLabel:Show()
        
        -- Repeatable checkbox (check override first, then DB default)
        local override = WarbandNexus:GetRepeatableOverride(info.type, info.itemID)
        local isRepeatable = (override ~= nil) and override or info.repeatable
        repeatableCheckbox:SetChecked(isRepeatable)
        if repeatableCheckbox.checkTexture then repeatableCheckbox.checkTexture:SetShown(isRepeatable) end
        repeatableCheckbox:Show()
        repeatableLabel:Show()
    end
    
    -- Dropdown: Select item from DB
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["SELECT_ITEM"]) or "Select Item",
        desc = (ns.L and ns.L["SELECT_ITEM_DESC"]) or "Choose a collectible to manage.",
        values = function() return dropdownValues end,
        get = function()
            return ns._trackDBSelected and ns._trackDBSelected.key or nil
        end,
        set = function(_, val)
            UpdateDetailPanel(val)
        end,
    }, trackYOffset)
    
    -- Position detail card below dropdown (fixed height: always visible as card)
    local DETAIL_CARD_HEIGHT = 78
    detailCard:SetPoint("TOPLEFT", 0, trackYOffset)
    detailCard:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    detailCard:SetHeight(DETAIL_CARD_HEIGHT)
    detailCard:Show()
    
    -- Restore previous selection or show placeholder
    if ns._trackDBSelected and ns._trackDBSelected.key and itemRegistry[ns._trackDBSelected.key] then
        UpdateDetailPanel(ns._trackDBSelected.key)
    else
        detailPlaceholder:Show()
        detailNameText:SetText("")
        detailInfoText:SetText("")
        trackedCheckbox:Hide()
        trackedLabel:Hide()
        repeatableCheckbox:Hide()
        repeatableLabel:Hide()
    end
    trackYOffset = trackYOffset - DETAIL_CARD_HEIGHT - 16
    
    --================================================================
    -- SUB-PANEL: Custom Entries
    --================================================================
    
    -- Divider line
    local trackDivider2 = trackSection.content:CreateTexture(nil, "OVERLAY")
    trackDivider2:SetPoint("TOPLEFT", 0, trackYOffset)
    trackDivider2:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    trackDivider2:SetHeight(1)
    trackDivider2:SetColorTexture(0.30, 0.30, 0.35, 0.5)
    trackYOffset = trackYOffset - 12
    
    -- Sub-header
    local customSectionHeader = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    customSectionHeader:SetPoint("TOPLEFT", 0, trackYOffset)
    customSectionHeader:SetText("|cffffcc00" .. ((ns.L and ns.L["CUSTOM_ENTRIES"]) or "Custom Entries") .. "|r")
    trackYOffset = trackYOffset - 20
    
    -- Custom entries list (no separate "Current:" label — shown inline)
    local customListText = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    customListText:SetPoint("TOPLEFT", 4, trackYOffset)
    customListText:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    customListText:SetJustifyH("LEFT")
    customListText:SetWordWrap(true)
    
    -- Custom entries list builder + remove dropdown value builder
    local removeDropdownValues = {}
    local function RefreshCustomList()
        if not WarbandNexus.db or not WarbandNexus.db.global then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
            wipe(removeDropdownValues)
            return
        end
        local trackDB = WarbandNexus.db.global.trackDB
        if not trackDB or not trackDB.custom then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
            wipe(removeDropdownValues)
            return
        end
        local lines = {}
        wipe(removeDropdownValues)
        for npcID, drops in pairs(trackDB.custom.npcs or {}) do
            for i = 1, #drops do
                local d = drops[i]
                local repStr = d.repeatable and " |cff44cc44(R)|r" or ""
                lines[#lines + 1] = format("|cff00ccff%s|r%s  |cff666666npc:%s|r",
                    d.name or "?", repStr, tostring(npcID))
                local removeKey = "npc:" .. tostring(npcID) .. ":" .. tostring(d.itemID or 0)
                removeDropdownValues[removeKey] = (d.name or "?") .. " (npc:" .. npcID .. ")"
            end
        end
        for objID, drops in pairs(trackDB.custom.objects or {}) do
            for i = 1, #drops do
                local d = drops[i]
                local repStr = d.repeatable and " |cff44cc44(R)|r" or ""
                lines[#lines + 1] = format("|cff00ccff%s|r%s  |cff666666obj:%s|r",
                    d.name or "?", repStr, tostring(objID))
                local removeKey = "object:" .. tostring(objID) .. ":" .. tostring(d.itemID or 0)
                removeDropdownValues[removeKey] = (d.name or "?") .. " (obj:" .. objID .. ")"
            end
        end
        if #lines == 0 then
            customListText:SetText("|cff555555" .. ((ns.L and ns.L["NO_CUSTOM_ENTRIES"]) or "No custom entries.") .. "|r")
        else
            customListText:SetText(table.concat(lines, "\n"))
        end
    end
    RefreshCustomList()
    -- Use a safe minimum height for the custom list (at least 14px per line, min 14px)
    local customListH = customListText:GetStringHeight()
    if not customListH or customListH < 14 then customListH = 14 end
    trackYOffset = trackYOffset - customListH - 12
    
    -- Form state
    if not ns._trackDBForm then ns._trackDBForm = {} end
    
    -- Item ID label
    local itemIDLabel = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    itemIDLabel:SetPoint("TOPLEFT", 0, trackYOffset)
    itemIDLabel:SetText((ns.L and ns.L["ITEM_ID_INPUT"]) or "Item ID")
    itemIDLabel:SetTextColor(1, 1, 1, 1)
    itemIDLabel:SetScript("OnEnter", function(self)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["ITEM_ID_INPUT_DESC"]) or "Enter the item ID to track.")
    end)
    itemIDLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    trackYOffset = trackYOffset - 22
    
    -- Item ID editbox + Lookup button on the SAME row
    local editBoxWidth = math.floor(trackContentWidth * 0.45)
    local lookupBtnWidth = 100
    local inlineGap = 8
    
    local itemIDBox = ns.UI.Factory:CreateEditBox(trackSection.content)
    if itemIDBox then
        itemIDBox:SetHeight(30)
        itemIDBox:SetWidth(editBoxWidth)
        itemIDBox:SetPoint("TOPLEFT", 0, trackYOffset)
        itemIDBox:SetTextInsets(10, 10, 0, 0)
        itemIDBox:SetMaxLetters(20)
        itemIDBox:SetNumeric(false)
        if ApplyVisuals then
            ApplyVisuals(itemIDBox, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
        end
        itemIDBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        itemIDBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    
    -- Lookup result text (positioned below the input row)
    local lookupResultText = FontManager:CreateFontString(trackSection.content, "body", "OVERLAY")
    lookupResultText:SetPoint("TOPLEFT", 0, trackYOffset - 34)
    lookupResultText:SetPoint("RIGHT", trackSection.content, "RIGHT", 0, 0)
    lookupResultText:SetText("")
    lookupResultText:SetWordWrap(true)
    lookupResultText:SetJustifyH("LEFT")
    
    -- Lookup button (inline, right of editbox)
    local lookupBtn = ns.UI.Factory:CreateButton(trackSection.content)
    lookupBtn:SetSize(lookupBtnWidth, 30)
    lookupBtn:SetPoint("LEFT", itemIDBox, "RIGHT", inlineGap, 0)
    local lookupBtnColor = { 0.20, 0.50, 0.70 }
    if ApplyVisuals then
        ApplyVisuals(lookupBtn, {0.08, 0.08, 0.10, 1}, {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 0.8})
    end
    local lookupBtnText = FontManager:CreateFontString(lookupBtn, "body", "OVERLAY")
    lookupBtnText:SetPoint("CENTER")
    lookupBtnText:SetText((ns.L and ns.L["LOOKUP_ITEM"]) or "Lookup")
    lookupBtnText:SetTextColor(lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3])
    lookupBtn:SetScript("OnClick", function()
        local rawID = itemIDBox:GetText()
        local itemID = tonumber(rawID)
        if not itemID then return end
        ns._trackDBForm.itemID = itemID
        ns._trackDBForm.itemName = nil
        ns._trackDBForm.itemIcon = nil
        ns._trackDBForm.itemType = nil
        WarbandNexus:LookupItem(itemID, function(_, name, icon, cType)
            if name then
                ns._trackDBForm.itemName = name
                ns._trackDBForm.itemIcon = icon
                ns._trackDBForm.itemType = cType
                local iconStr = icon and ("|T" .. icon .. ":16|t ") or ""
                lookupResultText:SetText(iconStr .. "|cff00ff00" .. name .. "|r |cff888888(" .. (cType or "item") .. ")|r")
            else
                lookupResultText:SetText("|cffff4444" .. ((ns.L and ns.L["ITEM_LOOKUP_FAILED"]) or "Item not found.") .. "|r")
            end
        end)
    end)
    lookupBtn:SetScript("OnEnter", function(self)
        if ApplyVisuals then
            ApplyVisuals(lookupBtn, {0.12, 0.12, 0.14, 1}, {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 1})
        end
        lookupBtnText:SetTextColor(1, 1, 1)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["LOOKUP_ITEM_DESC"]) or "Resolve item name and type from ID.")
    end)
    lookupBtn:SetScript("OnLeave", function()
        if ApplyVisuals then
            ApplyVisuals(lookupBtn, {0.08, 0.08, 0.10, 1}, {lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3], 0.8})
        end
        lookupBtnText:SetTextColor(lookupBtnColor[1], lookupBtnColor[2], lookupBtnColor[3])
        GameTooltip:Hide()
    end)
    
    -- Advance past: editbox (30) + lookup result line (18) + gap (12)
    trackYOffset = trackYOffset - 30 - 18 - 12
    
    -- Source Type dropdown
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["SOURCE_TYPE"]) or "Source Type",
        desc = (ns.L and ns.L["SOURCE_TYPE_DESC"]) or "NPC or Object.",
        values = { npc = (ns.L and ns.L["SOURCE_TYPE_NPC"]) or "NPC", object = (ns.L and ns.L["SOURCE_TYPE_OBJECT"]) or "Object" },
        get = function() return ns._trackDBForm.sourceType or "npc" end,
        set = function(_, val) ns._trackDBForm.sourceType = val end,
    }, trackYOffset)
    
    -- Source ID input
    local sourceIDBox
    trackYOffset, sourceIDBox = CreateInputWidget(trackSection.content, {
        name = (ns.L and ns.L["SOURCE_ID"]) or "Source ID",
        desc = (ns.L and ns.L["SOURCE_ID_DESC"]) or "NPC ID or Object ID.",
        width = trackContentWidth * 0.45,
        numeric = true,
    }, trackYOffset)
    
    -- Repeatable checkbox
    trackYOffset = CreateCheckboxGrid(trackSection.content, {
        {
            key = "trackDB_repeatable",
            label = (ns.L and ns.L["REPEATABLE_TOGGLE"]) or "Repeatable",
            tooltip = (ns.L and ns.L["REPEATABLE_TOGGLE_DESC"]) or "Whether this drop can be attempted multiple times per lockout.",
            get = function() return ns._trackDBForm.repeatable or false end,
            set = function(val) ns._trackDBForm.repeatable = val end,
        },
    }, trackYOffset, trackContentWidth)
    
    -- [+ Add Entry] + [- Remove Selected] side-by-side
    if not ns._trackDBRemoveKey then ns._trackDBRemoveKey = nil end
    trackYOffset = CreateButtonGrid(trackSection.content, {
        {
            label = (ns.L and ns.L["ADD_ENTRY"]) or "+ Add Entry",
            tooltip = (ns.L and ns.L["ADD_ENTRY_DESC"]) or "Add this custom drop entry.",
            func = function()
                local f = ns._trackDBForm
                local itemID = tonumber(itemIDBox:GetText())
                local sourceID = tonumber(sourceIDBox:GetText())
                if not itemID or not sourceID then
                    WarbandNexus:Print("|cffff4444" .. ((ns.L and ns.L["ENTRY_ADD_FAILED"]) or "Item ID and Source ID are required.") .. "|r")
                    return
                end
                local drop = {
                    type = f.itemType or "item",
                    itemID = itemID,
                    name = f.itemName or ("Item " .. itemID),
                    repeatable = f.repeatable or nil,
                }
                local ok = WarbandNexus:AddCustomDrop(f.sourceType or "npc", sourceID, drop, nil)
                if ok then
                    WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["ENTRY_ADDED"]) or "Custom entry added.") .. "|r")
                    ns._trackDBForm = {}
                    itemIDBox:SetText("")
                    sourceIDBox:SetText("")
                    lookupResultText:SetText("")
                    RefreshCustomList()
                else
                    WarbandNexus:Print("|cffff4444" .. ((ns.L and ns.L["ENTRY_ADD_FAILED"]) or "Failed to add entry.") .. "|r")
                end
            end,
            color = { 0.20, 0.60, 0.40 },
        },
        {
            label = (ns.L and ns.L["REMOVE_BUTTON"]) or "- Remove Selected",
            tooltip = (ns.L and ns.L["REMOVE_BUTTON_DESC"]) or "Remove the selected custom entry.",
            func = function()
                local val = ns._trackDBRemoveKey
                if not val or val == "" then return end
                local sourceType, sourceID, itemID = strsplit(":", val)
                sourceID = tonumber(sourceID)
                itemID = tonumber(itemID)
                if sourceType and sourceID and itemID then
                    local ok = WarbandNexus:RemoveCustomDrop(sourceType, sourceID, itemID)
                    if ok then
                        WarbandNexus:Print("|cff00ff00" .. ((ns.L and ns.L["ENTRY_REMOVED"]) or "Entry removed.") .. "|r")
                        ns._trackDBRemoveKey = nil
                        RefreshCustomList()
                    end
                end
            end,
            color = { 0.60, 0.22, 0.22 },
        },
    }, trackYOffset, trackContentWidth, 160)
    
    -- Remove entry dropdown (select which custom entry to remove)
    trackYOffset = CreateDropdownWidget(trackSection.content, {
        name = (ns.L and ns.L["REMOVE_ENTRY"]) or "Remove Custom Entry",
        desc = (ns.L and ns.L["REMOVE_ENTRY_DESC"]) or "Select a custom entry to remove.",
        values = function() return removeDropdownValues end,
        get = function() return ns._trackDBRemoveKey end,
        set = function(_, val) ns._trackDBRemoveKey = val end,
    }, trackYOffset)
    
    -- Final section height (expanded)
    local trackContentHeight = math.abs(trackYOffset)
    local trackExpandedHeight = trackContentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM
    trackSection.content:SetHeight(trackContentHeight)
    
    -- Default collapsed: hide content, use collapsed height
    trackSection.content:Hide()
    trackSection:SetHeight(COLLAPSED_HEIGHT)
    
    local trackSectionYBase = yOffset  -- yOffset before track section
    yOffset = yOffset - COLLAPSED_HEIGHT - SECTION_SPACING  -- default collapsed offset
    
    --========================================================================
    -- ADVANCED
    --========================================================================
    
    local advSection = CreateSection(parent, (ns.L and ns.L["ADVANCED_SECTION"]) or "Advanced", effectiveWidth)
    advSection:SetPoint("TOPLEFT", 0, yOffset)
    advSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- Debug Mode checkboxes
    local debugOptions = {
        {
            key = "autoOptimize",
            label = (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE"]) or "Auto-Optimize Database",
            tooltip = (ns.L and ns.L["CONFIG_AUTO_OPTIMIZE_DESC"]) or "Automatically optimize the database on login to keep storage efficient.",
            get = function() return WarbandNexus.db.profile.autoOptimize ~= false end,
            set = function(value) WarbandNexus.db.profile.autoOptimize = value end,
        },
        {
            key = "debug",
            label = (ns.L and ns.L["DEBUG_MODE"]) or "Debug Logging",
            tooltip = (ns.L and ns.L["DEBUG_MODE_DESC"]) or "Output verbose debug messages to chat for troubleshooting",
            get = function() return WarbandNexus.db.profile.debugMode end,
            set = function(value) WarbandNexus.db.profile.debugMode = value end,
        },
        {
            key = "debugVerbose",
            parentKey = "debug",
            label = (ns.L and ns.L["CONFIG_DEBUG_VERBOSE"]) or "Debug Verbose (cache/scan/tooltip logs)",
            tooltip = (ns.L and ns.L["CONFIG_DEBUG_VERBOSE_DESC"]) or "When Debug Mode is on, also show currency/reputation cache, bag scan, tooltip and profession logs. Leave off to reduce chat spam.",
            get = function() return WarbandNexus.db.profile.debugVerbose end,
            set = function(value) WarbandNexus.db.profile.debugVerbose = value end,
        },
        {
            key = "debugTryCounterLoot",
            label = (ns.L and ns.L["DEBUG_TRYCOUNTER_LOOT"]) or "Try Counter Loot Debug",
            tooltip = (ns.L and ns.L["DEBUG_TRYCOUNTER_LOOT_DESC"]) or "Log loot flow only (LOOT_OPENED, source resolution, zone fallback). Rep/currency cache logs are suppressed.",
            get = function() return WarbandNexus.db.profile.debugTryCounterLoot end,
            set = function(value) WarbandNexus.db.profile.debugTryCounterLoot = value end,
        },
    }
    
    local advGridYOffset = CreateCheckboxGrid(advSection.content, debugOptions, 0, effectiveWidth - 30)
    
    -- Calculate section height
    local advContentHeight = math.abs(advGridYOffset)
    advSection:SetHeight(advContentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    advSection.content:SetHeight(advContentHeight)
    
    -- Collapsible toggle handler for Track Item DB
    local function ToggleTrackSection()
        trackIsCollapsed = not trackIsCollapsed
        if trackIsCollapsed then
            trackSection.content:Hide()
            trackSection:SetHeight(COLLAPSED_HEIGHT)
            collapseArrow:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", false)
        else
            trackSection.content:Show()
            trackSection:SetHeight(trackExpandedHeight)
            collapseArrow:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", false)
        end
        -- Reposition Advanced section
        local advY = trackSectionYBase - trackSection:GetHeight() - SECTION_SPACING
        advSection:ClearAllPoints()
        advSection:SetPoint("TOPLEFT", 0, advY)
        advSection:SetPoint("TOPRIGHT", 0, advY)
        -- Recalculate total parent height
        local totalY = math.abs(advY) + advSection:GetHeight() + 20
        parent:SetHeight(totalY)
    end
    collapseBtn:SetScript("OnClick", ToggleTrackSection)
    -- Make entire title text area clickable for convenience
    trackSection.titleText:SetScript("OnMouseUp", ToggleTrackSection)
    
    -- Set total parent height (default collapsed state)
    local totalHeight = math.abs(yOffset) + advSection:GetHeight()
    parent:SetHeight(totalHeight + 20)
end

--============================================================================
-- MAIN WINDOW
--============================================================================

function WarbandNexus:ShowSettings()
    -- Combat safety: prevent taint from frame operations during combat
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    
    -- Prevent duplicates: if already shown, bring to front
    if settingsFrame and settingsFrame:IsShown() then
        RefreshSettingsKeyboard(settingsFrame)
        settingsFrame:Raise()
        return
    end
    
    -- Reuse existing hidden frame to prevent orphaned frame leaks.
    -- Previous code created a new frame every time, leaving old hidden frames in memory.
    if settingsFrame then
        RefreshSettingsKeyboard(settingsFrame)
        settingsFrame:Show()
        settingsFrame:Raise()
        return
    end

    -- Forward declarations for resize callbacks.
    local scrollFrame, scrollChild, lastWidth
    
    -- Main frame (created once, reused across open/close cycles; Factory for standard compliance)
    local f = ns.UI.Factory:CreateContainer(UIParent, 700, 650, false)
    if not f then return end
    f:SetSize(700, 650)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    if f.SetToplevel then f:SetToplevel(true) end
    f:SetClampedToScreen(true)
    f:SetResizeBounds(600, 500, 1000, 800)
    
    if ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
    end
    
    settingsFrame = f
    
    -- OnHide: Normalize main window position to prevent anchor drift.
    -- When a FULLSCREEN_DIALOG frame hides, WoW's layout engine can recalculate
    -- sibling frame positions, causing the main window to shift.
    f:SetScript("OnHide", function()
        local mainFrame = _G.WarbandNexusFrame
        if mainFrame and mainFrame:IsShown() then
            local left = mainFrame:GetLeft()
            local top = mainFrame:GetTop()
            if left and top then
                mainFrame:ClearAllPoints()
                mainFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
            end
        end
    end)

    f:SetScript("OnShow", function(self)
        RefreshSettingsKeyboard(self)
    end)
    
    -- ESC: same hierarchy as main window (POPUP closes before MAIN).
    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.POPUP)
        ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.POPUP)
        ns.WindowManager:InstallESCHandler(f)
    else
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(200)
        if not InCombatLockdown() then
            f:EnableKeyboard(true)
            f:SetPropagateKeyboardInput(true)
        end
        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                self:Hide()
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)
    end
    
    -- Header (Factory container)
    local header = ns.UI.Factory:CreateContainer(f, 1, 40, false)
    if not header then return end
    header:SetHeight(40)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:EnableMouse(true)
    if ns.WindowManager and ns.WindowManager.InstallDragHandler then
        ns.WindowManager:InstallDragHandler(header, f)
    else
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
    end
    
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
    title:EnableMouse(true)
    title:SetText((ns.L and ns.L["WARBAND_NEXUS_SETTINGS"]) or "Warband Nexus Settings")
    title:SetTextColor(1, 1, 1)
    title:SetScript("OnEnter", function(self)
        Settings_ShowWrappedTooltip(self, (ns.L and ns.L["SETTINGS_ESC_HINT"])
            or "Press |cff999999ESC|r to close this window.")
    end)
    title:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Close button (Factory)
    local closeBtn = ns.UI.Factory:CreateButton(header, 28, 28, true)
    if not closeBtn then return end
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
        -- Do NOT nil settingsFrame — frame is reused across open/close cycles.
        -- Setting nil here would cause a new frame to be created every time,
        -- leaking orphaned frames into memory.
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
    
    -- Resize grip (Factory button)
    local resizer = ns.UI.Factory:CreateButton(f, 16, 16, true)
    if not resizer then return end
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
    
    -- Content area (Factory container)
    local contentArea = ns.UI.Factory:CreateContainer(f, 1, 1, false)
    if not contentArea then return end
    contentArea:ClearAllPoints()
    contentArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -UI_SPACING.TOP_MARGIN)
    contentArea:SetPoint("BOTTOMRIGHT", -UI_SPACING.SIDE_MARGIN, UI_SPACING.TOP_MARGIN)
    
    -- ScrollFrame (Collections pattern: bar column + PositionScrollBarInContainer)
    local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(contentArea, 22, UI_SPACING.TOP_MARGIN, UI_SPACING.TOP_MARGIN)
    scrollFrame = ns.UI.Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", UI_SPACING.SIDE_MARGIN, -UI_SPACING.TOP_MARGIN)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollBarColumn, "BOTTOMLEFT", 0, UI_SPACING.TOP_MARGIN)
    scrollFrame:EnableMouseWheel(true)
    if scrollFrame.ScrollBar and ns.UI.Factory.PositionScrollBarInContainer then
        ns.UI.Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end

    -- Scroll child
    scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
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
