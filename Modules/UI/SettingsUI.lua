--[[
    Warband Nexus - Settings UI
    Clean implementation - reads AceConfig options, renders with custom UI
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager

-- Import SharedWidgets
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateSection = ns.UI_CreateSection

--============================================================================
-- LOCAL STATE
--============================================================================

local settingsFrame = nil
local CONTAINER_WIDTH = 620  -- Fixed width for all widgets

--============================================================================
-- WIDGET BUILDERS
--============================================================================

--[[
    Create toggle (checkbox) widget
    @param parent Frame
    @param option AceConfig option table
    @param yOffset number (negative)
    @return number - height used (negative)
]]
local function CreateToggleWidget(parent, option, yOffset)
    local COLORS = ns.UI_COLORS
    
    -- Get dynamic values
    local optionName = type(option.name) == "function" and option.name() or option.name
    local optionDesc = type(option.desc) == "function" and option.desc() or option.desc
    
    -- Checkbox (no indent - aligned to left edge)
    local checkbox = CreateThemedCheckbox(parent)
    checkbox:SetPoint("TOPLEFT", 0, yOffset)
    checkbox:SetSize(24, 24)
    checkbox:Enable()  -- Explicitly enable
    checkbox:SetHitRectInsets(0, 0, 0, 0)  -- Full clickable area
    
    -- Set initial value
    if option.get then
        local value = option.get()
        checkbox:SetChecked(value)
        if checkbox.checkTexture then
            if value then
                checkbox.checkTexture:Show()
            else
                checkbox.checkTexture:Hide()
            end
        end
    end
    
    -- OnClick handler
    checkbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if option.set then
            option.set(nil, isChecked)
        end
        
        -- Update visual
        if self.checkTexture then
            if isChecked then
                self.checkTexture:Show()
            else
                self.checkTexture:Hide()
            end
        end
    end)
    
    -- Label (white, next to checkbox) - extends to parent width
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("LEFT", checkbox, "RIGHT", 10, 0)
    label:SetPoint("RIGHT", 0, 0)  -- Extend to parent edge
    label:SetJustifyH("LEFT")
    label:SetText(optionName)
    label:SetTextColor(1, 1, 1, 1)  -- White
    
    -- Description (gray, below label)
    if optionDesc and optionDesc ~= "" then
        local desc = FontManager:CreateFontString(parent, "small", "OVERLAY")
        desc:SetPoint("TOPLEFT", checkbox, "BOTTOMLEFT", 34, -5)
        desc:SetPoint("RIGHT", 0, 0)  -- Extend to parent edge
        desc:SetJustifyH("LEFT")
        desc:SetWordWrap(true)
        desc:SetText(optionDesc)
        desc:SetTextColor(COLORS.textDim[1], COLORS.textDim[2], COLORS.textDim[3], 0.7)
        
        local descHeight = desc:GetStringHeight()
        return -(34 + descHeight + 10)
    end
    
    return -40
end

--[[
    Create select (dropdown) widget
    @param parent Frame
    @param option AceConfig option table
    @param yOffset number (negative)
    @return number - height used (negative)
]]
local function CreateSelectWidget(parent, option, yOffset)
    local COLORS = ns.UI_COLORS
    
    -- Get dynamic values
    local optionName = type(option.name) == "function" and option.name() or option.name
    
    local function GetValues()
        if not option.values then return nil end
        return type(option.values) == "function" and option.values() or option.values
    end
    
    -- Label (no indent - aligned to left edge)
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    label:SetText(optionName)
    label:SetTextColor(1, 1, 1, 1)  -- White
    
    -- Dropdown button (using Factory pattern)
    local dropdown = ns.UI.Factory:CreateButton(parent)
    dropdown:SetHeight(32)
    dropdown:SetPoint("TOPLEFT", 0, yOffset - 25)
    dropdown:SetPoint("TOPRIGHT", 0, yOffset - 25)
    
    if ApplyVisuals then
        ApplyVisuals(dropdown, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    -- Current value text (centered padding for symmetry)
    local valueText = FontManager:CreateFontString(dropdown, "body", "OVERLAY")
    valueText:SetPoint("LEFT", 12, 0)
    valueText:SetPoint("RIGHT", -32, 0)
    valueText:SetJustifyH("LEFT")
    
    -- Arrow icon (no unicode)
    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(16, 16)
    arrow:SetPoint("RIGHT", -12, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetTexCoord(0, 1, 0, 1)
    
    -- Update display
    local function UpdateDisplay()
        local values = GetValues()
        
        if not values then
            valueText:SetText("No Options")
            return
        end
        
        if option.get then
            local currentValue = option.get()
            if currentValue and values[currentValue] then
                valueText:SetText(values[currentValue])
            elseif currentValue then
                valueText:SetText(tostring(currentValue))
            else
                valueText:SetText("None")
            end
        else
            valueText:SetText("None")
        end
    end
    
    UpdateDisplay()
    
    -- Dropdown menu (shared activeMenu state)
    local activeMenu = nil
    
    dropdown:SetScript("OnClick", function(self)
        local values = GetValues()
        if not values then return end
        
        -- Toggle: If already open, close it
        if activeMenu and activeMenu:IsShown() then
            activeMenu:Hide()
            activeMenu = nil
            return
        end
        
        -- Close any other active menu
        if activeMenu then
            activeMenu:Hide()
            activeMenu = nil
        end
        
        -- Count items
        local itemCount = 0
        for _ in pairs(values) do
            itemCount = itemCount + 1
        end
        
        -- Calculate menu size (match dropdown width exactly)
        local contentHeight = math.min(itemCount * 26, 300)
        
        -- Menu width should match dropdown button width exactly
        local menuWidth = dropdown:GetWidth()
        
        -- Create menu (using Factory pattern)
        local menu = ns.UI.Factory:CreateContainer(UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetSize(menuWidth, contentHeight + 10)  -- +10 for padding
        
        -- Position directly below dropdown (aligned edges)
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        menu:SetClampedToScreen(true)  -- Prevent overflow outside screen
        
        if ApplyVisuals then
            ApplyVisuals(menu, {0.10, 0.10, 0.12, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
        end
        
        activeMenu = menu
        
        -- ScrollFrame with mouse wheel support (using Factory pattern with custom styling)
        -- Leave space on the right for scroll bar system (22px for bar + gap)
        local scrollFrame = ns.UI.Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", 5, -5)
        scrollFrame:SetPoint("BOTTOMRIGHT", -27, 5)  -- Leave 22px for scroll bar + 5px original margin = 27px
        scrollFrame:EnableMouseWheel(true)
        
        local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
        scrollChild:SetWidth(scrollFrame:GetWidth())  -- Match scroll frame width (scroll bar is outside)
        scrollFrame:SetScrollChild(scrollChild)
        
        -- Mouse wheel scrolling
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local newScroll = current - (delta * 20)
            newScroll = math.max(0, math.min(newScroll, maxScroll))
            self:SetVerticalScroll(newScroll)
        end)
        
        -- Count and sort
        local sortedOptions = {}
        for value, displayText in pairs(values) do
            table.insert(sortedOptions, {value = value, text = displayText})
        end
        table.sort(sortedOptions, function(a, b) return a.text < b.text end)
        
        scrollChild:SetHeight(#sortedOptions * 26)
        
        -- Update scroll bar visibility (hide if content fits)
        if ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
        end
        
        -- Create buttons
        local yPos = 0
        local btnWidth = menuWidth - 10  -- Match scroll child padding
        for _, data in ipairs(sortedOptions) do
            local btn = ns.UI.Factory:CreateButton(scrollChild, btnWidth, 24)
            btn:SetPoint("TOPLEFT", 0, yPos)
            
            local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
            btnText:SetPoint("LEFT", 12, 0)
            btnText:SetText(data.text)
            
            -- Highlight current
            local currentValue = option.get and option.get()
            if currentValue == data.value then
                btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            end
            
            btn:SetScript("OnClick", function()
                if option.set then
                    option.set(nil, data.value)
                    UpdateDisplay()
                end
                menu:Hide()
                activeMenu = nil
            end)
            
            yPos = yPos - 26
        end
        
        menu:Show()
        
        -- Close on ESC key
        menu:SetPropagateKeyboardInput(false)
        menu:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                activeMenu = nil
            end
        end)
        
        -- Close on click outside (delayed check)
        C_Timer.After(0.05, function()
            if menu and menu:IsShown() then
                menu:SetScript("OnUpdate", function(self, elapsed)
                    -- Close if clicking outside both menu and dropdown
                    if not MouseIsOver(self) and not MouseIsOver(dropdown) then
                        if GetMouseButtonClicked() or IsMouseButtonDown() then
                            self:Hide()
                            activeMenu = nil
                            self:SetScript("OnUpdate", nil)
                        end
                    end
                end)
            end
        end)
    end)
    
    return -75
end

--[[
    Create range (slider) widget
    @param parent Frame
    @param option AceConfig option table
    @param yOffset number (negative)
    @return number - height used (negative)
]]
local function CreateSliderWidget(parent, option, yOffset)
    local COLORS = ns.UI_COLORS
    
    -- Get dynamic values
    local optionName = type(option.name) == "function" and option.name() or option.name
    
    -- Label with value (no indent - aligned to left edge)
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOPLEFT", 0, yOffset)
    label:SetTextColor(1, 1, 1, 1)  -- White
    
    local function UpdateLabel()
        local currentValue = option.get and option.get() or (option.min or 0)
        -- Round to 1 decimal place for cleaner display (1.0, 1.1, 1.2)
        label:SetText(string.format("%s: |cff00ccff%.1f|r", optionName, currentValue))
    end
    
    UpdateLabel()
    
    -- Slider (full width like dropdown)
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetHeight(20)
    slider:SetPoint("TOPLEFT", 0, yOffset - 25)
    slider:SetPoint("TOPRIGHT", 0, yOffset - 25)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(option.min or 0, option.max or 1)
    slider:SetValueStep(option.step or 0.1)  -- Default to 0.1 for cleaner steps
    
    -- Background
    local bg = slider:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.12, 1)
    
    -- Thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 24)
    thumb:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    slider:SetThumbTexture(thumb)
    
    -- Set value
    if option.get then
        slider:SetValue(option.get())
    end
    
    -- OnValueChanged
    slider:SetScript("OnValueChanged", function(self, value)
        -- Round value to step precision (0.1) to prevent float drift
        local step = option.step or 0.1
        value = math.floor(value / step + 0.5) * step
        
        -- Update slider if value was rounded
        if math.abs(self:GetValue() - value) > 0.001 then
            self:SetValue(value)
            return  -- SetValue will trigger OnValueChanged again
        end
        
        if option.set then
            option.set(nil, value)
            UpdateLabel()
            
            -- Real-time overflow detection for font scale slider
            if option.name and (option.name == "Font Scale" or option.name:match("Font Scale")) then
                -- Throttled overflow check (300ms delay to avoid spam)
                if self._overflowCheckTimer then
                    self._overflowCheckTimer:Cancel()
                end
                self._overflowCheckTimer = C_Timer.NewTimer(0.3, function()
                    if ns.OverflowMonitor then
                        local hasOverflow = ns.OverflowMonitor:CheckAll()
                        
                        if hasOverflow then
                            StaticPopupDialogs["WN_OVERFLOW_WARNING"].text = 
                                "|cffffcc00Font Overflow Detected|r\n\n" ..
                                "Some text elements are overflowing at this scale.\n\n" ..
                                string.format("Current scale: |cff00ccff%.1fx|r\n\n", value) ..
                                "Try reducing the font scale to fix this issue."
                            
                            StaticPopup_Show("WN_OVERFLOW_WARNING")
                        end
                    end
                end)
            end
        end
    end)
    
    return -65
end

--[[
    Create color picker widget
    @param parent Frame
    @param option AceConfig option table
    @param yOffset number (negative)
    @return number - height used (negative)
]]
local function CreateColorWidget(parent, option, yOffset)
    local COLORS = ns.UI_COLORS
    
    -- Get dynamic values
    local optionName = type(option.name) == "function" and option.name() or option.name
    
    -- Label (centered)
    local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    label:SetPoint("TOP", parent, "TOP", 0, yOffset)
    label:SetText(optionName)
    label:SetTextColor(1, 1, 1, 1)  -- White
    
    -- Color button (centered below label)
    local colorButton = CreateFrame("Button", nil, parent)
    colorButton:SetSize(150, 32)
    colorButton:SetPoint("TOP", label, "BOTTOM", 0, -10)
    
    if ApplyVisuals then
        ApplyVisuals(colorButton, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    -- Color display
    local colorTexture = colorButton:CreateTexture(nil, "ARTWORK")
    colorTexture:SetPoint("TOPLEFT", 3, -3)
    colorTexture:SetPoint("BOTTOMRIGHT", -3, 3)
    
    -- Update color
    local function UpdateColor()
        if option.get then
            local r, g, b, a = option.get()
            colorTexture:SetColorTexture(r or 1, g or 1, b or 1, a or 1)
        end
    end
    
    UpdateColor()
    
    -- OnClick - open color picker
    colorButton:SetScript("OnClick", function(self)
        local r, g, b, a
        if option.get then
            r, g, b, a = option.get()
        else
            r, g, b, a = 1, 1, 1, 1
        end
        
        -- Store original color for cancel/restore
        local originalR, originalG, originalB = r, g, b
        local originalA = a
        local colorWasChanged = false
        
        -- Modern ColorPicker API (War Within)
        local info = {
            r = r or 1,
            g = g or 1,
            b = b or 1,
            opacity = option.hasAlpha and (a or 1) or nil,
            hasOpacity = option.hasAlpha,
            
            -- Live preview - update UI as user drags
            swatchFunc = function()
                colorWasChanged = true
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = option.hasAlpha and ColorPickerFrame:GetColorAlpha() or 1
                
                -- Update button preview
                if colorTexture then
                    colorTexture:SetColorTexture(newR, newG, newB, newA)
                end
                
                -- LIVE UPDATE: Trigger full refresh for preview
                if option.set then
                    if option.hasAlpha then
                        option.set(nil, newR, newG, newB, newA)
                    else
                        option.set(nil, newR, newG, newB)
                    end
                end
            end,
            
            -- Cancel - restore original color
            cancelFunc = function()
                colorWasChanged = false
                if option.set then
                    if option.hasAlpha then
                        option.set(nil, originalR, originalG, originalB, originalA)
                    else
                        option.set(nil, originalR, originalG, originalB)
                    end
                    UpdateColor()
                end
            end,
        }
        
        -- Ensure ColorPicker is above settings window
        ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ColorPickerFrame:SetFrameLevel(400)
        
        ColorPickerFrame:SetupColorPickerAndShow(info)
        
        -- Hook OnHide - cleanup
        ColorPickerFrame:HookScript("OnHide", function()
            colorWasChanged = false
        end)
    end)
    
    return -75
end

--[[
    Create description widget
    @param parent Frame
    @param option AceConfig option table
    @param yOffset number (negative)
    @return number - height used (negative)
]]
local function CreateDescriptionWidget(parent, option, yOffset)
    local COLORS = ns.UI_COLORS
    
    -- Get dynamic values
    local content = type(option.name) == "function" and option.name() or option.name
    
    -- Text (no indent - aligned to left edge) - full parent width
    local text = FontManager:CreateFontString(parent, "body", "OVERLAY")
    text:SetPoint("TOPLEFT", 0, yOffset)
    text:SetPoint("TOPRIGHT", 0, yOffset)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(content)
    text:SetTextColor(COLORS.textDim[1], COLORS.textDim[2], COLORS.textDim[3], 0.7)
    
    local textHeight = text:GetStringHeight()
    return -(textHeight + 15)
end

--============================================================================
-- SECTION BUILDER
--============================================================================

--[[
    Build settings UI from AceConfig options
    @param parent Frame - scrollChild
]]
local function BuildSettings(parent)
    -- Clear existing
    for _, child in pairs({parent:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    
    -- Get options from addon
    local addon = LibStub("AceAddon-3.0"):GetAddon(ADDON_NAME)
    if not addon or not addon.options then
        return
    end
    
    local options = addon.options
    
    -- Handle lazy-load
    if type(options) == "function" then
        options = options()
    end
    
    if not options or not options.args then
        return
    end
    
    -- Sort by order
    local sortedArgs = {}
    for key, option in pairs(options.args) do
        table.insert(sortedArgs, {key = key, option = option})
    end
    table.sort(sortedArgs, function(a, b)
        return (a.option.order or 0) < (b.option.order or 0)
    end)
    
    -- Group by sections (headers)
    local sections = {}
    local currentSection = nil
    
    for _, data in ipairs(sortedArgs) do
        local option = data.option
        
        -- Skip disabled
        if option.disabled and type(option.disabled) == "function" and option.disabled() then
            -- Skip
        elseif option.type == "header" then
            -- New section
            local headerName = type(option.name) == "function" and option.name() or option.name
            currentSection = {
                title = headerName,
                items = {}
            }
            table.insert(sections, currentSection)
        elseif currentSection then
            -- Add to section
            table.insert(currentSection.items, {key = data.key, option = option})
        end
    end
    
    -- Render sections
    local yOffset = 10
    local totalHeight = 10
    
    for _, section in ipairs(sections) do
        if #section.items > 0 then
            -- Create section frame (full width of parent)
            local parentWidth = parent:GetWidth() or 660
            local sectionFrame = CreateSection(parent, section.title, parentWidth)
            sectionFrame:SetPoint("TOPLEFT", 0, -yOffset)
            sectionFrame:SetPoint("TOPRIGHT", 0, -yOffset)
            
            -- Render widgets
            local contentYOffset = 0
            
            for _, item in ipairs(section.items) do
                local option = item.option
                local heightUsed = 0
                
                if option.type == "toggle" then
                    heightUsed = CreateToggleWidget(sectionFrame.content, option, contentYOffset)
                elseif option.type == "select" then
                    heightUsed = CreateSelectWidget(sectionFrame.content, option, contentYOffset)
                elseif option.type == "range" then
                    heightUsed = CreateSliderWidget(sectionFrame.content, option, contentYOffset)
                elseif option.type == "color" then
                    heightUsed = CreateColorWidget(sectionFrame.content, option, contentYOffset)
                elseif option.type == "description" then
                    heightUsed = CreateDescriptionWidget(sectionFrame.content, option, contentYOffset)
                end
                
                contentYOffset = contentYOffset + heightUsed
            end
            
            -- Set heights
            local contentHeight = math.abs(contentYOffset)
            local sectionHeight = contentHeight + 60  -- Title + padding
            sectionFrame:SetHeight(sectionHeight)
            sectionFrame.content:SetHeight(contentHeight + 10)
            
            -- Update offsets
            yOffset = yOffset + sectionHeight + 15
            totalHeight = totalHeight + sectionHeight + 15
        end
    end
    
    -- Set total height
    totalHeight = totalHeight + 20
    parent:SetHeight(totalHeight)
end

--============================================================================
-- MAIN WINDOW
--============================================================================

--[[
    Show settings window
]]
function WarbandNexus:ShowSettings()
    -- Prevent duplicates
    if settingsFrame and settingsFrame:IsShown() then
        return
    end
    
    local COLORS = ns.UI_COLORS
    
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
    tinsert(UISpecialFrames, "WarbandNexusSettingsFrame")
    
    -- Header
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(40)
    header:SetPoint("TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", -2, -2)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    
    if ApplyVisuals then
        ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Store references for refresh
    f.header = header
    
    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    
    -- Title (WHITE - never changes with theme)
    local title = FontManager:CreateFontString(header, "title", "OVERLAY")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Warband Nexus Settings")
    title:SetTextColor(1, 1, 1)  -- Always white
    
    -- Close button (Factory pattern with atlas icon)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply custom visuals
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        settingsFrame = nil
    end)
    
    -- Hover effects
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
        -- Update scrollChild width and scroll bar visibility on resize
        if scrollChild and scrollFrame then
            scrollChild:SetWidth(scrollFrame:GetWidth())
            if ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
            end
        end
    end)
    
    -- Content area
    local contentArea = CreateFrame("Frame", nil, f)
    contentArea:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    contentArea:SetPoint("BOTTOMRIGHT", -2, 2)
    
    -- ScrollFrame with custom styled scroll bar (Factory pattern)
    local scrollFrame = ns.UI.Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 8)  -- Leave space for scroll bar
    scrollFrame:EnableMouseWheel(true)
    
    -- Scroll child
    local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
    local scrollWidth = scrollFrame:GetWidth() or 660
    scrollChild:SetWidth(scrollWidth)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Update scrollChild width when frame is resized
    f:SetScript("OnSizeChanged", function(self, width, height)
        local newScrollWidth = scrollFrame:GetWidth() or 660
        scrollChild:SetWidth(newScrollWidth)
    end)
    
    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = current - (delta * 40)
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
    end)
    
    -- Build content
    BuildSettings(scrollChild)
    
    -- Update scrollChild width and scroll bar visibility after rendering
    C_Timer.After(0.1, function()
        if scrollFrame and scrollChild then
            local newScrollWidth = scrollFrame:GetWidth() or 660
            scrollChild:SetWidth(newScrollWidth)
            
            -- Update scroll bar visibility based on content height
            if ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
            end
        end
    end)
    
    f:Show()
    settingsFrame = f
end

-- Export
ns.ShowSettings = function() WarbandNexus:ShowSettings() end
