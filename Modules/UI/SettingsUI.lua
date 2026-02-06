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
local COLORS = ns.UI_COLORS
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
}

local MIN_ITEM_WIDTH = 180  -- Minimum width for grid items
local GRID_SPACING = 10     -- Horizontal spacing between grid items
local ROW_HEIGHT = 32       -- Height per grid row
local SECTION_SPACING = 5   -- Compact spacing between sections (reduced from 8)
local CONTENT_PADDING_TOP = 40  -- Title height (from CreateSection standard)
local CONTENT_PADDING_BOTTOM = 15  -- Bottom padding within section

--============================================================================
-- GRID LAYOUT SYSTEM
--============================================================================

---Create grid-based checkbox layout (RESPONSIVE - auto-adjusts columns)
---@param parent Frame Parent container
---@param options table Array of {key, label, tooltip, get, set}
---@param yOffset number Starting Y offset
---@param explicitWidth number Optional explicit width (bypasses GetWidth)
---@return number New Y offset after grid
local function CreateCheckboxGrid(parent, options, yOffset, explicitWidth)
    -- Calculate dynamic columns based on parent width
    local containerWidth = explicitWidth or parent:GetWidth() or 620
    local itemsPerRow = math.max(2, math.floor((containerWidth + GRID_SPACING) / (MIN_ITEM_WIDTH + GRID_SPACING)))
    local itemWidth = (containerWidth - (GRID_SPACING * (itemsPerRow - 1))) / itemsPerRow
    
    local row = 0
    local col = 0
    
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
        
        -- OnClick handler
        checkbox:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            if option.set then
                option.set(isChecked)
            end
            
            if self.checkTexture then
                self.checkTexture:SetShown(isChecked)
            end
        end)
        
        -- Label (to the right of checkbox)
        local label = FontManager:CreateFontString(parent, "body", "OVERLAY")
        label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
        label:SetWidth(itemWidth - 32)  -- Subtract checkbox + spacing
        label:SetJustifyH("LEFT")
        label:SetText(option.label)
        label:SetTextColor(1, 1, 1, 1)
        
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
    
    -- Calculate total height used
    local totalRows = math.ceil(#options / itemsPerRow)
    return yOffset - (totalRows * ROW_HEIGHT) - 15  -- Reduced spacing
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
        button:SetPoint("TOPLEFT", xPos, yOffset + (row * -(buttonHeight + 8)))
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
    return yOffset - (totalRows * (buttonHeight + 8)) - 15
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
    
    -- Current value text
    local valueText = FontManager:CreateFontString(dropdown, "body", "OVERLAY")
    valueText:SetPoint("LEFT", 12, 0)
    valueText:SetPoint("RIGHT", -32, 0)
    valueText:SetJustifyH("LEFT")
    
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
        
        -- Create menu
        local menu = ns.UI.Factory:CreateContainer(UIParent)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetSize(menuWidth, contentHeight + 10)
        menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
        menu:SetClampedToScreen(true)
        
        if ApplyVisuals then
            ApplyVisuals(menu, {0.10, 0.10, 0.12, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
        end
        
        activeMenu = menu
        
        -- ScrollFrame
        local scrollFrame = ns.UI.Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", 5, -5)
        scrollFrame:SetPoint("BOTTOMRIGHT", -27, 5)
        scrollFrame:EnableMouseWheel(true)
        
        local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
        scrollChild:SetWidth(scrollFrame:GetWidth())
        scrollFrame:SetScrollChild(scrollChild)
        
        -- Mouse wheel scrolling
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local newScroll = current - (delta * 20)
            newScroll = math.max(0, math.min(newScroll, maxScroll))
            self:SetVerticalScroll(newScroll)
        end)
        
        -- Sort options
        local sortedOptions = {}
        for value, displayText in pairs(values) do
            table.insert(sortedOptions, {value = value, text = displayText})
        end
        table.sort(sortedOptions, function(a, b) return a.text < b.text end)
        
        scrollChild:SetHeight(#sortedOptions * 26)
        
        -- Update scroll bar visibility
        if ns.UI.Factory.UpdateScrollBarVisibility then
            ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
        end
        
        -- Create buttons
        local yPos = 0
        local btnWidth = menuWidth - 10
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
                    option.set(nil, data.value)  -- AceConfig pattern: (info, value)
                    UpdateDisplay()
                end
                menu:Hide()
                activeMenu = nil
            end)
            
            yPos = yPos - 26
        end
        
        menu:Show()
        
        -- Close on ESC
        menu:SetPropagateKeyboardInput(false)
        menu:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
                activeMenu = nil
            end
        end)
        
        -- Close on click outside
        C_Timer.After(0.05, function()
            if menu and menu:IsShown() then
                menu:SetScript("OnUpdate", function(self, elapsed)
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
        label:SetText(string.format("%s: |cff00ccff%.1f|r", optionName, currentValue))
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
    
    local generalSection = CreateSection(parent, "General Settings", effectiveWidth)
    generalSection:SetPoint("TOPLEFT", 0, yOffset)
    generalSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- General options grid
    local generalOptions = {
        {
            key = "showItemCount",
            label = "Show Item Count",
            tooltip = "Display stack counts on items in storage view",
            get = function() return WarbandNexus.db.profile.showItemCount end,
            set = function(value) WarbandNexus.db.profile.showItemCount = value end,
        },
        {
            key = "showWeeklyPlanner",
            label = "Show Weekly Planner",
            tooltip = "Display the Weekly Planner section in the Characters tab",
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
            label = "Lock Minimap Icon",
            tooltip = "Lock the minimap icon in place (prevents dragging)",
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
            key = "autoScan",
            label = "Auto-Scan Items",
            tooltip = "Automatically scan and cache items when you open banks or bags",
            get = function() return WarbandNexus.db.profile.autoScan end,
            set = function(value) WarbandNexus.db.profile.autoScan = value end,
        },
        {
            key = "autoSaveChanges",
            label = "Live Sync",
            tooltip = "Keep item cache updated in real-time while banks are open",
            get = function() return WarbandNexus.db.profile.autoSaveChanges ~= false end,
            set = function(value) WarbandNexus.db.profile.autoSaveChanges = value end,
        },
        {
            key = "showItemLevel",
            label = "Show Item Level",
            tooltip = "Display item level badges on equipment in the item list",
            get = function() return WarbandNexus.db.profile.showItemLevel end,
            set = function(value)
                WarbandNexus.db.profile.showItemLevel = value
                if WarbandNexus.RefreshUI then
                    WarbandNexus:RefreshUI()
                end
            end,
        },
    }
    
    local generalGridYOffset = CreateCheckboxGrid(generalSection.content, generalOptions, 0, effectiveWidth - 30)
    
    -- Current Language (label + tooltip) - Below checkboxes
    local langLabel = FontManager:CreateFontString(generalSection.content, "body", "OVERLAY")
    langLabel:SetPoint("TOPLEFT", 0, generalGridYOffset - 15)
    langLabel:SetText("Current Language: " .. (GetLocale() or "enUS"))
    langLabel:SetTextColor(1, 1, 1, 1)
    
    langLabel:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Addon uses your WoW game client's language automatically. To change, update your Battle.net settings.", 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    langLabel:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    -- Calculate section height (content height + title + bottom padding)
    local contentHeight = math.abs(generalGridYOffset) + 30
    generalSection:SetHeight(contentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    generalSection.content:SetHeight(contentHeight)
    
    -- Move to next section
    yOffset = yOffset - generalSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- TAB FILTERING
    --========================================================================
    
    local tabSection = CreateSection(parent, "Tab Filtering", effectiveWidth)
    tabSection:SetPoint("TOPLEFT", 0, yOffset)
    tabSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    local tabGridYOffset = 0
    
    -- WARBAND BANK GROUP
    local warbandLabel = FontManager:CreateFontString(tabSection.content, "subtitle", "OVERLAY")
    warbandLabel:SetPoint("TOPLEFT", 0, tabGridYOffset)
    warbandLabel:SetText("Warband Bank")
    warbandLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, warbandLabel)
    tabGridYOffset = tabGridYOffset - 25  -- Consistent subtitle → checkbox spacing
    
    local warbandOptions = {}
    for i = 1, 5 do
        table.insert(warbandOptions, {
            key = "tab" .. i,
            label = "Tab " .. i,
            tooltip = "Ignore Warband Bank Tab " .. i .. " from automatic scanning",
            get = function() return WarbandNexus.db.profile.ignoredTabs[i] end,
            set = function(value) WarbandNexus.db.profile.ignoredTabs[i] = value end,
        })
    end
    
    tabGridYOffset = CreateCheckboxGrid(tabSection.content, warbandOptions, tabGridYOffset, effectiveWidth - 30)
    tabGridYOffset = tabGridYOffset - 10  -- Space between groups
    
    -- PERSONAL BANK GROUP
    local personalLabel = FontManager:CreateFontString(tabSection.content, "subtitle", "OVERLAY")
    personalLabel:SetPoint("TOPLEFT", 0, tabGridYOffset)
    personalLabel:SetText("Personal Bank")
    personalLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, personalLabel)
    tabGridYOffset = tabGridYOffset - 25  -- Consistent subtitle → checkbox spacing
    
    local personalBankOptions = {}
    local personalBankLabels = {"Bank", "Bag 6", "Bag 7", "Bag 8", "Bag 9", "Bag 10", "Bag 11"}
    for i, bagID in ipairs(ns.PERSONAL_BANK_BAGS) do
        local label = personalBankLabels[i] or ("Bag " .. bagID)
        table.insert(personalBankOptions, {
            key = "pbank" .. bagID,
            label = label,
            tooltip = "Ignore " .. label .. " from automatic scanning",
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
    inventoryLabel:SetText("Inventory")
    inventoryLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, inventoryLabel)
    tabGridYOffset = tabGridYOffset - 25  -- Consistent subtitle → checkbox spacing
    
    local inventoryOptions = {}
    local inventoryLabels = {"Backpack", "Bag 1", "Bag 2", "Bag 3", "Bag 4", "Reagent"}
    for i, bagID in ipairs(ns.INVENTORY_BAGS) do
        local label = inventoryLabels[i] or ("Bag " .. bagID)
        table.insert(inventoryOptions, {
            key = "inv" .. bagID,
            label = label,
            tooltip = "Ignore " .. label .. " from automatic scanning",
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
    
    local notifSection = CreateSection(parent, "Notifications", effectiveWidth)
    notifSection:SetPoint("TOPLEFT", 0, yOffset)
    notifSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    local notifOptions = {
        {
            key = "enabled",
            label = "Enable Notifications",
            tooltip = "Master toggle for all notification pop-ups",
            get = function() return WarbandNexus.db.profile.notifications.enabled end,
            set = function(value) WarbandNexus.db.profile.notifications.enabled = value end,
        },
        {
            key = "vault",
            label = "Vault Reminder",
            tooltip = "Show reminder when you have unclaimed Weekly Vault rewards",
            get = function() return WarbandNexus.db.profile.notifications.showVaultReminder end,
            set = function(value) WarbandNexus.db.profile.notifications.showVaultReminder = value end,
        },
        {
            key = "loot",
            label = "Loot Alerts",
            tooltip = "Show notification when a NEW mount, pet, or toy enters your bag",
            get = function() return WarbandNexus.db.profile.notifications.showLootNotifications end,
            set = function(value) WarbandNexus.db.profile.notifications.showLootNotifications = value end,
        },
        {
            key = "reputation",
            label = "Reputation Gains",
            tooltip = "Show chat messages when you gain reputation with factions",
            get = function() return WarbandNexus.db.profile.notifications.showReputationGains end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showReputationGains = value
                if WarbandNexus.UpdateChatFilter then
                    local repEnabled = value
                    local currEnabled = WarbandNexus.db.profile.notifications.showCurrencyGains
                    WarbandNexus:UpdateChatFilter(repEnabled, currEnabled)
                end
            end,
        },
        {
            key = "currency",
            label = "Currency Gains",
            tooltip = "Show chat messages when you gain currencies",
            get = function() return WarbandNexus.db.profile.notifications.showCurrencyGains end,
            set = function(value)
                WarbandNexus.db.profile.notifications.showCurrencyGains = value
                if WarbandNexus.UpdateChatFilter then
                    local repEnabled = WarbandNexus.db.profile.notifications.showReputationGains
                    local currEnabled = value
                    WarbandNexus:UpdateChatFilter(repEnabled, currEnabled)
                end
            end,
        },
    }
    
    local notifGridYOffset = CreateCheckboxGrid(notifSection.content, notifOptions, 0, effectiveWidth - 30)
    
    -- Calculate section height
    local contentHeight = math.abs(notifGridYOffset)
    notifSection:SetHeight(contentHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    notifSection.content:SetHeight(contentHeight)
    
    -- Move to next section
    yOffset = yOffset - notifSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- THEME & APPEARANCE
    --========================================================================
    
    local themeSection = CreateSection(parent, "Theme & Appearance", effectiveWidth)
    themeSection:SetPoint("TOPLEFT", 0, yOffset)
    themeSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    local themeYOffset = 0
    
    -- Color Picker Button
    local colorPickerLabel = FontManager:CreateFontString(themeSection.content, "subtitle", "OVERLAY")
    colorPickerLabel:SetPoint("TOPLEFT", 0, themeYOffset)
    colorPickerLabel:SetText("Custom Color")
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
    btnText:SetText("Open Color Picker")
    btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    
    -- Click handler - Opens WoW's native color picker
    colorPickerBtn:SetScript("OnClick", function(self)
        local currentColor = WarbandNexus.db.profile.themeColors.accent
        local r, g, b = currentColor[1], currentColor[2], currentColor[3]
        
        -- TWW (11.0+) uses new ColorPickerFrame API
        local info = {
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local colors = ns.UI_CalculateThemeColors(newR, newG, newB)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then
                    ns.UI_RefreshColors()
                end
                RefreshSubtitles()  -- Update subtitles and sliders
            end,
            hasOpacity = false,
            opacity = 1.0,
            r = r,
            g = g,
            b = b,
            cancelFunc = function(previousValues)
                if previousValues then
                    local colors = ns.UI_CalculateThemeColors(previousValues.r, previousValues.g, previousValues.b)
                    WarbandNexus.db.profile.themeColors = colors
                    if ns.UI_RefreshColors then
                        ns.UI_RefreshColors()
                    end
                    RefreshSubtitles()  -- Update subtitles and sliders
                end
            end,
        }
        
        -- Ensure ColorPickerFrame is on top
        if ColorPickerFrame then
            ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ColorPickerFrame:SetFrameLevel(500)
        end
        
        -- TWW API check
        if ColorPickerFrame.SetupColorPickerAndShow then
            -- TWW (11.0+)
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            -- Legacy (pre-11.0)
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
        
        -- Raise again after show
        if ColorPickerFrame then
            ColorPickerFrame:Raise()
        end
    end)
    
    -- Hover effects
    colorPickerBtn:SetScript("OnEnter", function(self)
        if ApplyVisuals then
            ApplyVisuals(colorPickerBtn, {0.12, 0.12, 0.14, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
        end
        btnText:SetTextColor(1, 1, 1)
        
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Open WoW's native color picker wheel to choose a custom theme color", 1, 1, 1, 1, true)
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
    presetLabel:SetText("Preset Themes")
    presetLabel:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
    table.insert(subtitleElements, presetLabel)
    themeYOffset = themeYOffset - 25
    
    -- Theme preset buttons (with colors)
    local themeButtons = {
        {
            label = "Purple",
            tooltip = "Classic purple theme (default)",
            color = {0.40, 0.20, 0.58},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.40, 0.20, 0.58)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = "Blue",
            tooltip = "Cool blue theme",
            color = {0.30, 0.65, 1.0},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.30, 0.65, 1.0)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = "Green",
            tooltip = "Nature green theme",
            color = {0.32, 0.79, 0.40},
            func = function()
                local colors = ns.UI_CalculateThemeColors(0.32, 0.79, 0.40)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = "Red",
            tooltip = "Fiery red theme",
            color = {1.0, 0.34, 0.34},
            func = function()
                local colors = ns.UI_CalculateThemeColors(1.0, 0.34, 0.34)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = "Orange",
            tooltip = "Warm orange theme",
            color = {1.0, 0.65, 0.30},
            func = function()
                local colors = ns.UI_CalculateThemeColors(1.0, 0.65, 0.30)
                WarbandNexus.db.profile.themeColors = colors
                if ns.UI_RefreshColors then ns.UI_RefreshColors() end
                RefreshSubtitles()
            end,
        },
        {
            label = "Cyan",
            tooltip = "Bright cyan theme",
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
        name = "Font Family",
        desc = "Choose the font used throughout the addon UI",
        values = {
            ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata",
            ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
            ["Fonts\\skurri.TTF"] = "Skurri",
            ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
            ["Interface\\AddOns\\WarbandNexus\\Fonts\\ActionMan.ttf"] = "Action Man",
            ["Interface\\AddOns\\WarbandNexus\\Fonts\\ContinuumMedium.ttf"] = "Continuum Medium",
            ["Interface\\AddOns\\WarbandNexus\\Fonts\\DieDieDie.ttf"] = "Die Die Die",
            ["Interface\\AddOns\\WarbandNexus\\Fonts\\Expressway.ttf"] = "Expressway",
            ["Interface\\AddOns\\WarbandNexus\\Fonts\\Homespun.ttf"] = "Homespun",
        },
        get = function() return WarbandNexus.db.profile.fonts.fontFace end,
        set = function(_, value)
            WarbandNexus.db.profile.fonts.fontFace = value
            if ns.FontManager and ns.FontManager.RefreshAllFonts then
                ns.FontManager:RefreshAllFonts()
            end
            if WarbandNexus.RefreshUI then
                WarbandNexus:RefreshUI()
            end
        end,
    }, themeYOffset)
    
    -- Font scale slider
    themeYOffset = CreateSliderWidget(themeSection.content, {
        name = "Font Scale",
        desc = "Adjust font size across all UI elements",
        min = 0.8,
        max = 1.5,
        step = 0.1,
        get = function() return WarbandNexus.db.profile.fonts.scaleCustom or 1.0 end,
        set = function(_, value)
            WarbandNexus.db.profile.fonts.scaleCustom = value
            WarbandNexus.db.profile.fonts.useCustomScale = true
            if ns.FontManager and ns.FontManager.RefreshAllFonts then
                ns.FontManager:RefreshAllFonts()
            end
        end,
    }, themeYOffset, sliderElements)  -- Pass sliderElements for tracking
    
    local themeSectionHeight = math.abs(themeYOffset)
    themeSection:SetHeight(themeSectionHeight + CONTENT_PADDING_TOP + CONTENT_PADDING_BOTTOM)
    themeSection.content:SetHeight(themeSectionHeight)
    
    -- Move to next section
    yOffset = yOffset - themeSection:GetHeight() - SECTION_SPACING
    
    --========================================================================
    -- ADVANCED
    --========================================================================
    
    local advSection = CreateSection(parent, "Advanced", effectiveWidth)
    advSection:SetPoint("TOPLEFT", 0, yOffset)
    advSection:SetPoint("TOPRIGHT", 0, yOffset)
    
    -- Debug Mode checkbox
    local debugOptions = {
        {
            key = "debug",
            label = "Debug Mode",
            tooltip = "Enable verbose logging for debugging purposes",
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
    
    -- Icon
    local icon = header:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 15, 0)
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    
    -- Title
    local title = FontManager:CreateFontString(header, "title", "OVERLAY")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Warband Nexus Settings")
    title:SetTextColor(1, 1, 1)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
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
    
    -- ScrollFrame
    local scrollFrame = ns.UI.Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 8)
    scrollFrame:EnableMouseWheel(true)
    
    -- Scroll child
    local scrollChild = ns.UI.Factory:CreateContainer(scrollFrame)
    local scrollWidth = scrollFrame:GetWidth() or 660
    scrollChild:SetWidth(scrollWidth)
    scrollFrame:SetScrollChild(scrollChild)
    
    -- Update scrollChild width when frame is resized (THROTTLED - no rebuild)
    local lastResizeTime = 0
    local lastWidth = 0
    f:SetScript("OnSizeChanged", function(self, width, height)
        local now = GetTime()
        local newScrollWidth = scrollFrame:GetWidth() or 620
        
        -- Throttle: Only rebuild if enough time passed AND width changed significantly
        if now - lastResizeTime > 0.3 and math.abs(newScrollWidth - lastWidth) > 20 then
            scrollChild:SetWidth(newScrollWidth)
            BuildSettings(scrollChild, newScrollWidth)
            
            if ns.UI.Factory.UpdateScrollBarVisibility then
                ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
            end
            
            lastResizeTime = now
            lastWidth = newScrollWidth
        end
    end)
    
    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = current - (delta * 40)
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
