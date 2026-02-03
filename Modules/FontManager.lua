--[[
    Warband Nexus - Font Manager
    Centralized font management with resolution-aware scaling
    Provides consistent font rendering across all resolutions and UI scales
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
local FontManager = {}

--============================================================================
-- CONFIGURATION
--============================================================================

-- Available font families (WoW built-in fonts)
local FONT_OPTIONS = {
    ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata (Default)",
    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
    ["Fonts\\skurri.TTF"] = "Skurri",
    ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
}

-- Anti-aliasing options
local AA_OPTIONS = {
    none = "",
    OUTLINE = "OUTLINE",
    THICKOUTLINE = "THICKOUTLINE",
}

--============================================================================
-- PRIVATE HELPERS
--============================================================================

-- Get active scale multiplier from user settings
local function GetScaleMultiplier()
    local db = ns.db and ns.db.profile and ns.db.profile.fonts
    if not db then return 1.0 end
    
    return db.scaleCustom or 1.0
end

-- Get pixel scale for resolution normalization
local function GetPixelScale()
    return ns.GetPixelScale and ns.GetPixelScale() or 1.0
end

--============================================================================
-- FONT REGISTRY (for live updates)
--============================================================================

-- Registry of all FontStrings created via FontManager
local FONT_REGISTRY = {}

--============================================================================
-- PUBLIC API
--============================================================================

--[[
    Calculate final font size for a given category
    Applies: base size → user scale → pixel normalization
    @param category string - Font category ("header", "title", "subtitle", "body", "small")
    @return number - Final font size in pixels
]]
function FontManager:GetFontSize(category)
    local db = ns.db and ns.db.profile and ns.db.profile.fonts
    if not db or not db.baseSizes then
        -- Fallback to defaults
        local defaults = {
            header = 16,
            title = 14,
            subtitle = 12,
            body = 12,
            small = 10,
        }
        return defaults[category] or 12
    end
    
    local baseSize = db.baseSizes[category] or 12
    local scaleMultiplier = GetScaleMultiplier()
    local pixelScale = db.usePixelNormalization and GetPixelScale() or 1.0
    
    -- Final calculation: base × userScale × pixelNormalization
    local finalSize = baseSize * scaleMultiplier * pixelScale
    
    -- Clamp to reasonable bounds (8px - 32px)
    return math.max(8, math.min(32, finalSize))
end

--[[
    Get anti-aliasing flags from user settings
    @return string - Font flags ("", "OUTLINE", or "THICKOUTLINE")
]]
function FontManager:GetAAFlags()
    local db = ns.db and ns.db.profile and ns.db.profile.fonts
    if not db then return "OUTLINE" end
    
    return AA_OPTIONS[db.antiAliasing] or "OUTLINE"
end

--[[
    Get font face path from user settings
    @return string - Font file path
]]
function FontManager:GetFontFace()
    local db = ns.db and ns.db.profile and ns.db.profile.fonts
    if not db then return "Fonts\\FRIZQT__.TTF" end
    
    return db.fontFace or "Fonts\\FRIZQT__.TTF"
end

--[[
    SAFE: Apply font to a FontString with error handling
    Prevents errors during early initialization when db might not be ready
    @param fontString FontString - The font string to apply font to
    @param sizeCategory string - Font size category ("header", "title", "subtitle", "body", "small")
    @return boolean - Success/failure
]]
function FontManager:SafeSetFont(fontString, sizeCategory)
    if not fontString or not fontString.SetFont then
        return false
    end
    
    local success, err = pcall(function()
        local fontPath = FontManager:GetFontFace()
        local fontSize = FontManager:GetFontSize(sizeCategory or "body")
        local flags = FontManager:GetAAFlags()
        
        -- Validate all parameters
        if type(fontPath) ~= "string" or fontPath == "" then
            fontPath = "Fonts\\FRIZQT__.TTF"
        end
        if type(fontSize) ~= "number" or fontSize <= 0 then
            fontSize = 12
        end
        if type(flags) ~= "string" then
            flags = "OUTLINE"
        end
        
        fontString:SetFont(fontPath, fontSize, flags)
    end)
    
    if not success then
        -- Fallback to default font
        pcall(function()
            fontString:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        end)
        return false
    end
    
    return true
end

--[[
    Create a new FontString with managed font settings
    Factory method for creating font strings with automatic scaling
    @param parent Frame - Parent frame
    @param category string - Font category ("header", "title", "subtitle", "body", "small")
    @param layer string - Draw layer (default "OVERLAY")
    @param colorType string - Color type ("normal", "accent") for live theme updates (default "normal")
    @return FontString - Configured font string
]]
function FontManager:CreateFontString(parent, category, layer, colorType)
    if not parent then
        return nil
    end
    
    layer = layer or "OVERLAY"
    category = category or "body"
    colorType = colorType or "normal"
    
    local fs = parent:CreateFontString(nil, layer)
    if fs then
        self:ApplyFont(fs, category)
        
        -- Register for live updates (font AND color)
        fs._fontCategory = category
        fs._colorType = colorType
        table.insert(FONT_REGISTRY, fs)
    end
    
    return fs
end

--[[
    Apply font settings to an existing FontString
    Updates font face, size, and anti-aliasing flags
    @param fontString FontString - Target font string
    @param category string - Font category
]]
function FontManager:ApplyFont(fontString, category)
    if not fontString then
        return
    end
    
    category = category or "body"
    
    local fontFace = self:GetFontFace()
    local fontSize = self:GetFontSize(category)
    local flags = self:GetAAFlags()
    
    -- Validate before calling SetFont (WoW is strict about types)
    if type(fontFace) ~= "string" or fontFace == "" then
        fontFace = "Fonts\\FRIZQT__.TTF"
    end
    
    if type(fontSize) ~= "number" or fontSize <= 0 then
        fontSize = 12
    end
    
    if type(flags) ~= "string" then
        flags = "OUTLINE"
    end
    
    -- CRITICAL: Wrap in pcall to catch font loading errors
    local success, err = pcall(function()
        fontString:SetFont(fontFace, fontSize, flags)
    end)
    
    if not success then
        -- Fallback to default WoW font if custom font fails
        DebugPrint("|cffff0000[WN FontManager]|r Font load failed: " .. tostring(err))
        DebugPrint("|cffff9900[WN FontManager]|r Falling back to default font")
        
        -- Try with default font
        local fallbackSuccess = pcall(function()
            fontString:SetFont("Fonts\\FRIZQT__.TTF", fontSize, flags)
        end)
        
        if not fallbackSuccess then
            -- Last resort: Use GameFontNormal template
            DebugPrint("|cffff0000[WN FontManager]|r Fallback failed, using GameFontNormal")
            if fontString.SetFontObject then
                fontString:SetFontObject("GameFontNormal")
            end
        end
    end
end

--[[
    Trigger global UI refresh to apply new font settings
    Called when user changes font settings in Config
]]
function FontManager:RefreshAllFonts()
    -- Clear pixel scale cache
    if ns.ResetPixelScale then
        ns.ResetPixelScale()
    end
    
    -- Update ALL registered FontStrings with new settings
    for i = #FONT_REGISTRY, 1, -1 do
        local fs = FONT_REGISTRY[i]
        
        -- Check if FontString still exists
        if not fs or not fs.SetFont then
            table.remove(FONT_REGISTRY, i)
        else
            local category = fs._fontCategory or "body"
            self:ApplyFont(fs, category)
        end
    end
    
    -- No need to refresh/reopen windows, fonts are updated live!
    
    -- Fire event for overflow detection (Service -> Service communication)
    -- Delayed to allow font rendering to complete
    C_Timer.After(0.2, function()
        if ns.WarbandNexus and ns.WarbandNexus.SendMessage then
            ns.WarbandNexus:SendMessage("WN_FONT_CHANGED")
        end
    end)
end

--[[
    Refresh all FontStrings using accent colors
    Called when user changes theme color
]]
function FontManager:RefreshAccentColors()
    if not ns.UI_COLORS then return end
    
    local accentColor = ns.UI_COLORS.accent
    local updated = 0
    
    -- Update ALL registered FontStrings with accent color
    for i = #FONT_REGISTRY, 1, -1 do
        local fs = FONT_REGISTRY[i]
        
        -- Check if FontString still exists
        if not fs or not fs.SetTextColor then
            table.remove(FONT_REGISTRY, i)
        elseif fs._colorType == "accent" then
            -- Update accent-colored text
            fs:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
            updated = updated + 1
        end
    end
end

--[[
    Get font preview text for settings panel
    Shows calculated sizes for all categories
    @return string - Formatted preview text
]]
function FontManager:GetPreviewText()
    local lines = {}
    local categories = {"header", "title", "subtitle", "body", "small"}
    
    for _, cat in ipairs(categories) do
        local size = self:GetFontSize(cat)
        table.insert(lines, string.format("%s: %dpx", cat:gsub("^%l", string.upper), math.floor(size)))
    end
    
    return table.concat(lines, " | ")
end

-- Export to namespace
ns.FontManager = FontManager

