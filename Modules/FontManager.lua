--[[
    Warband Nexus - Font Manager
    Centralized font management with resolution-aware scaling
    Provides consistent font rendering across all resolutions and UI scales

    TYPOGRAPHY STANDARD (use only these roles via CreateFontString(parent, role, layer)):
    - header   : Section titles, tab labels, main card headings (largest)
    - title    : Card titles, dialog titles
    - subtitle : Secondary headings, section descriptions
    - body     : Default text, labels, list content
    - small    : Captions, hints, metadata, secondary info (smallest)
    Alias: "smalltext" -> "small"
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
local ValidateFontForLocale  -- forward declaration (defined after SafeSetFont, used by both SafeSetFont and ApplyFont)

--============================================================================
-- CONFIGURATION
--============================================================================

-- Available font families (WoW built-in fonts + custom fonts)
local FONT_OPTIONS = {
    ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata (Default)",
    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
    ["Fonts\\skurri.TTF"] = "Skurri",
    ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
    -- Custom fonts (Latin-only, don't support CJK/Cyrillic)
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\ActionMan.ttf"] = "Action Man",
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\ContinuumMedium.ttf"] = "Continuum Medium",
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\Expressway.ttf"] = "Expressway",
}

-- Fonts that are Latin-only (don't support CJK/Cyrillic)
local LATIN_ONLY_FONTS = {
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\ActionMan.ttf"] = true,
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\ContinuumMedium.ttf"] = true,
    ["Interface\\AddOns\\WarbandNexus\\Fonts\\Expressway.ttf"] = true,
}

-- Check if current locale requires non-Latin font support
local function IsNonLatinLocale()
    local locale = GetLocale()
    return locale == "zhCN" or locale == "zhTW" or locale == "koKR" or locale == "ruRU"
end

-- Get filtered font options for current locale
local function GetFilteredFontOptions()
    if not IsNonLatinLocale() then
        return FONT_OPTIONS  -- All fonts available for Latin locales
    end
    
    local filtered = {}
    for path, name in pairs(FONT_OPTIONS) do
        if not LATIN_ONLY_FONTS[path] then
            filtered[path] = name
        end
    end
    return filtered
end

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
-- CRITICAL: Safe fallback if DB not initialized yet (prevents ghost window bug)
local function GetScaleMultiplier()
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        DebugPrint("|cffffff00[WN FontManager]|r WARNING: Database not ready, using default scale (1.0)")
        return 1.0
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
    if not db then 
        return 1.0 
    end
    
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
    CRITICAL: Safe fallback if DB not ready (prevents ghost window bug)
    @param category string - Font category ("header", "title", "subtitle", "body", "small")
    @return number - Final font size in pixels
]]
function FontManager:GetFontSize(category)
    category = (category == "smalltext") and "small" or (category or "body")
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        DebugPrint("|cffffff00[WN FontManager]|r WARNING: Database not ready, using default font size")
        local defaults = {
            header = 16,
            title = 14,
            subtitle = 12,
            body = 12,
            small = 10,
        }
        return defaults[category] or 12
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
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
    CRITICAL: Safe fallback if DB not ready (prevents ghost window bug)
    @return string - Font flags ("", "OUTLINE", or "THICKOUTLINE")
]]
function FontManager:GetAAFlags()
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        return "OUTLINE"  -- Safe default
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
    if not db then return "OUTLINE" end
    
    return AA_OPTIONS[db.antiAliasing] or "OUTLINE"
end

--[[
    Get font face path from user settings
    CRITICAL: Safe fallback if DB not ready (prevents ghost window bug)
    @return string - Font file path
]]
function FontManager:GetFontFace()
    -- GUARD: Check if namespace and DB exist (race condition protection)
    if not ns or not ns.db then
        return "Fonts\\FRIZQT__.TTF"  -- Safe default
    end
    
    local db = ns.db.profile and ns.db.profile.fonts
    if not db then return "Fonts\\FRIZQT__.TTF" end
    
    local fontFace = db.fontFace or "Fonts\\FRIZQT__.TTF"
    
    -- Locale validation: if non-Latin locale and Latin-only font selected, use default
    if IsNonLatinLocale() and LATIN_ONLY_FONTS[fontFace] then
        -- Auto-correct saved font to default for non-Latin locales
        DebugPrint("|cffffff00[WN FontManager]|r Latin-only font '" .. fontFace .. "' not supported for locale '" .. GetLocale() .. "', using default font")
        fontFace = "Fonts\\FRIZQT__.TTF"
        -- Optionally save the corrected value back to DB (but don't do it here to avoid DB writes during rendering)
    end
    
    return fontFace
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
    
    local fontPath = FontManager:GetFontFace()
    local fontSize = FontManager:GetFontSize(sizeCategory or "body")
    local flags = FontManager:GetAAFlags()
    
    -- Validate all parameters
    if type(fontPath) ~= "string" or fontPath == "" then
        fontPath = "Fonts\\FRIZQT__.TTF"
    end
    
    -- Locale validation: if non-Latin locale and Latin-only font selected, use default
    if IsNonLatinLocale() and LATIN_ONLY_FONTS[fontPath] then
        fontPath = "Fonts\\FRIZQT__.TTF"
    end
    
    if type(fontSize) ~= "number" or fontSize <= 0 then
        fontSize = 12
    end
    if type(flags) ~= "string" then
        flags = "OUTLINE"
    end
    
    -- Check SetFont return value (returns false for invalid fonts, not a Lua error)
    local ok = false
    local success = pcall(function()
        ok = fontString:SetFont(fontPath, fontSize, flags)
    end)
    
    if not success or not ok then
        -- Fallback to default font
        pcall(function()
            fontString:SetFont("Fonts\\FRIZQT__.TTF", fontSize, flags)
        end)
        return false
    end
    
    -- Validate font rendered correctly (post-set validation for locale compatibility)
    ValidateFontForLocale(fontString, fontPath)
    
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
    Validate font rendered correctly (detect missing glyphs for non-Latin locales)
    @param fontString FontString - The font string to validate
    @param fontPath string - Font file path
    @return boolean - true if font is valid, false if fallback was applied
]]
ValidateFontForLocale = function(fontString, fontPath)
    if not IsNonLatinLocale() then return true end
    if not LATIN_ONLY_FONTS[fontPath] then return true end
    
    -- This font is Latin-only on a non-Latin locale - force default
    local defaultFont = "Fonts\\FRIZQT__.TTF"
    local _, size, flags = fontString:GetFont()
    local ok = false
    local success = pcall(function()
        ok = fontString:SetFont(defaultFont, size, flags)
    end)
    
    if success and ok then
        DebugPrint("|cffffff00[WN FontManager]|r Latin-only font '" .. fontPath .. "' not supported for locale '" .. GetLocale() .. "', using default font")
        return false
    end
    
    return true
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
    
    -- Extra safety: check if the FontString is still valid (parent not garbage collected)
    if not fontString.SetFont or not fontString.GetText then
        return
    end
    
    category = category or "body"
    if category == "smalltext" then category = "small" end
    
    local fontFace = self:GetFontFace()
    local fontSize = self:GetFontSize(category)
    local flags = self:GetAAFlags()
    
    -- Validate before calling SetFont (WoW is strict about types)
    if type(fontFace) ~= "string" or fontFace == "" then
        fontFace = "Fonts\\FRIZQT__.TTF"
    end
    
    -- Locale validation: if non-Latin locale and Latin-only font selected, use default
    if IsNonLatinLocale() and LATIN_ONLY_FONTS[fontFace] then
        DebugPrint("|cffffff00[WN FontManager]|r Latin-only font '" .. fontFace .. "' not supported for locale '" .. GetLocale() .. "', using default font")
        fontFace = "Fonts\\FRIZQT__.TTF"
    end
    
    if type(fontSize) ~= "number" or fontSize <= 0 then
        fontSize = 12
    end
    
    if type(flags) ~= "string" then
        flags = "OUTLINE"
    end
    
    -- Save existing text before font change (for re-render)
    local existingText = fontString:GetText()
    
    -- CRITICAL: Check SetFont return value, not just pcall
    -- SetFont returns false (not a Lua error) when font file is invalid/missing
    -- pcall won't catch this, the FontString just silently stops rendering
    local ok = false
    local success, err = pcall(function()
        ok = fontString:SetFont(fontFace, fontSize, flags)
    end)
    
    if not success or not ok then
        -- Font load failed - fall back to default WoW font
        DebugPrint("|cffff0000[WN FontManager]|r Font load failed for: " .. tostring(fontFace))
        
        local fallbackOk = false
        local fallbackSuccess = pcall(function()
            fallbackOk = fontString:SetFont("Fonts\\FRIZQT__.TTF", fontSize, flags)
        end)
        
        if not fallbackSuccess or not fallbackOk then
            -- Last resort: Use GameFontNormal template
            DebugPrint("|cffff0000[WN FontManager]|r Fallback also failed, using GameFontNormal")
            if fontString.SetFontObject then
                fontString:SetFontObject("GameFontNormal")
            end
        end
    else
        -- Validate font rendered correctly (post-set validation for locale compatibility)
        ValidateFontForLocale(fontString, fontFace)
    end
    
    -- CRITICAL: Force re-render by re-setting existing text
    -- After SetFont, WoW sometimes doesn't re-layout the FontString until text changes
    if existingText and existingText ~= "" then
        fontString:SetText(existingText)
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
    
    -- STEP 1: Validate the new font is loadable before applying to all FontStrings
    -- Create a temporary test to verify the font loads correctly
    local fontFace = self:GetFontFace()
    local testFontValid = true
    if type(fontFace) ~= "string" or fontFace == "" then
        testFontValid = false
    end
    
    -- STEP 2: Update ALL registered FontStrings with new settings
    local updated, removed = 0, 0
    for i = #FONT_REGISTRY, 1, -1 do
        local fs = FONT_REGISTRY[i]
        
        -- Check if FontString still exists and is valid
        if not fs or not fs.SetFont or not fs.GetText then
            table.remove(FONT_REGISTRY, i)
            removed = removed + 1
        else
            local category = fs._fontCategory or "body"
            self:ApplyFont(fs, category)
            updated = updated + 1
        end
    end
    
    DebugPrint(string.format("|cff00aaff[WN FontManager]|r RefreshAllFonts: updated %d, removed %d dead entries", updated, removed))
    
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
ns.GetFilteredFontOptions = GetFilteredFontOptions

