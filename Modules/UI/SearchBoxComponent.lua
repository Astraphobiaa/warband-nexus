--[[
    Warband Nexus - Search Box Component
    
    Reusable search box with icon, placeholder, and throttled callback.
    
    Features:
    - Search icon with opacity
    - Placeholder text
    - Throttled text change callback (default 0.3s)
    - ESC to clear, Enter to defocus
    - Pixel-perfect border styling
    - Initial value support (for state restoration)
    
    Extracted from SharedWidgets.lua (113 lines)
    Location: Lines 1787-1914
]]

local ADDON_NAME, ns = ...

-- Import dependencies from namespace
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local FontManager = ns.FontManager

--============================================================================
-- RUNTIME DEPENDENCY VALIDATION
--============================================================================

local function ValidateDependencies()
    local missing = {}
    
    if not COLORS then table.insert(missing, "UI_COLORS") end
    if not ApplyVisuals then table.insert(missing, "UI_ApplyVisuals") end
    if not FontManager then table.insert(missing, "FontManager") end
    
    if #missing > 0 then
        print("|cffff0000[WN SearchBox ERROR]|r Missing dependencies: " .. table.concat(missing, ", "))
        print("|cffff0000[WN SearchBox ERROR]|r Ensure SharedWidgets.lua loads before SearchBoxComponent.lua in .toc")
        return false
    end
    
    return true
end

-- Defer validation to first use (allows SharedWidgets to complete loading)

--============================================================================
-- SEARCH BOX COMPONENT
--============================================================================

---Creates a search box with icon, placeholder, and throttled callback
---@param parent Frame Parent frame
---@param width number Search box width
---@param placeholder string Placeholder text (e.g., "Search items...")
---@param onTextChanged function Callback function(searchText) - called after throttle
---@param throttleDelay number|nil Delay in seconds before callback (default 0.3)
---@param initialValue string|nil Initial text value (optional, for restoring state)
---@return Frame container Search box container frame
---@return function clearFunction Function to clear the search box
local function CreateSearchBox(parent, width, placeholder, onTextChanged, throttleDelay, initialValue)
    local delay = throttleDelay or 0.3
    local throttleTimer = nil
    local initialText = initialValue or ""
    
    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 32)
    
    -- Background frame with pixel-perfect border
    local searchFrame = CreateFrame("Frame", nil, container)
    container.searchFrame = searchFrame  -- Store reference for color updates
    searchFrame:SetAllPoints()
    
    -- Apply pixel-perfect visuals with accent border
    local accentColor = COLORS.accent
    ApplyVisuals(searchFrame, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    
    -- Search icon
    local searchIcon = searchFrame:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(16, 16)
    searchIcon:SetPoint("LEFT", 10, 0)
    searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    searchIcon:SetAlpha(0.5)
    -- Anti-flicker optimization
    searchIcon:SetSnapToPixelGrid(false)
    searchIcon:SetTexelSnappingBias(0)
    
    -- EditBox
    local searchBox = CreateFrame("EditBox", nil, searchFrame)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", -10, 0)
    searchBox:SetHeight(20)
    
    -- Use FontManager for consistent font styling
    local fontPath = FontManager:GetFontFace()
    local fontSize = FontManager:GetFontSize("body")
    local aa = FontManager:GetAAFlags()
    if fontPath and fontSize then
        searchBox:SetFont(fontPath, fontSize, aa)
    end
    
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    -- Set initial value if provided
    if initialText and initialText ~= "" then
        searchBox:SetText(initialText)
    end
    
    -- Placeholder text
    local placeholderText = FontManager:CreateFontString(searchBox, "body", "ARTWORK")
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder or "Search...")
    placeholderText:SetTextColor(1, 1, 1, 0.4)  -- White with transparency
    
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
    
    -- Focus handlers removed (no backdrop)
    
    -- Clear function
    local function ClearSearch()
        searchBox:SetText("")
        placeholderText:Show()
    end
    
    return container, ClearSearch
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_CreateSearchBox = CreateSearchBox

print("|cff00ff00[WN SearchBox]|r Module loaded successfully (113 lines, throttled search component)")
