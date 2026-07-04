--[[
    Warband Nexus - SharedWidgets theme palettes + ThemeAPI (ops Phase 6)
    SURFACE_VARIANTS, COLORS, UpdateColorsFromTheme, semantic color getters.
    Loaded before Modules/UI/SharedWidgets.lua.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local format = string.format

-- Theme color/backdrop getters live on one table to stay under the Lua 5.1
-- 200-locals-per-chunk ceiling (WN-CODE-lua-local-limit).
local ThemeAPI = {}

-- COLOR CONSTANTS

-- Calculate all theme variations from a master color
local function CalculateThemeColors(masterR, masterG, masterB)
    -- Helper: Desaturate color
    local function Desaturate(r, g, b, amount)
        local gray = (r + g + b) / 3
        return r + (gray - r) * amount, 
               g + (gray - g) * amount, 
               b + (gray - b) * amount
    end
    
    -- Helper: Adjust brightness
    local function AdjustBrightness(r, g, b, factor)
        return math.min(1, r * factor),
               math.min(1, g * factor),
               math.min(1, b * factor)
    end
    
    -- Calculate variations and wrap in arrays
    local darkR, darkG, darkB = AdjustBrightness(masterR, masterG, masterB, 0.7)
    local borderR, borderG, borderB = Desaturate(masterR * 0.5, masterG * 0.5, masterB * 0.5, 0.6)
    local activeR, activeG, activeB = AdjustBrightness(masterR, masterG, masterB, 0.5)
    local hoverR, hoverG, hoverB = AdjustBrightness(masterR, masterG, masterB, 0.6)
    
    return {
        accent = {masterR, masterG, masterB},
        accentDark = {darkR, darkG, darkB},
        border = {borderR, borderG, borderB},
        tabActive = {activeR, activeG, activeB},
        tabHover = {hoverR, hoverG, hoverB},
    }
end

-- Default theme fallbacks (used when DB is unavailable or corrupted)
local DEFAULT_THEME = {
    accent = {0.40, 0.20, 0.58},
    accentDark = {0.28, 0.14, 0.41},
    border = {0.20, 0.20, 0.25},
    tabActive = {0.20, 0.12, 0.30},
    tabHover = {0.24, 0.14, 0.35},
}

-- Safely extract a color array with validation (guards against corrupted DB entries)
local function SafeColorArray(tbl, key, fallback)
    local c = tbl and tbl[key]
    if type(c) == "table" and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number" then
        return c
    end
    return fallback
end

-- Get theme colors from database (with validated fallbacks)
local function GetThemeColors()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local themeColors = db and db.themeColors
    
    return {
        accent = SafeColorArray(themeColors, "accent", DEFAULT_THEME.accent),
        accentDark = SafeColorArray(themeColors, "accentDark", DEFAULT_THEME.accentDark),
        border = SafeColorArray(themeColors, "border", DEFAULT_THEME.border),
        tabActive = SafeColorArray(themeColors, "tabActive", DEFAULT_THEME.tabActive),
        tabHover = SafeColorArray(themeColors, "tabHover", DEFAULT_THEME.tabHover),
    }
end

--- Master accent RGB (0–1) for theme drawing: class color when available, else validated fallback from profile theme.
--- @param fallbackAccent table|nil rgb triple from profile.themeColors.accent
--- @return number r, number g, number b
function ns.ResolveAccentColor(fallbackAccent)
    local fr = fallbackAccent and fallbackAccent[1]
    local fg = fallbackAccent and fallbackAccent[2]
    local fb = fallbackAccent and fallbackAccent[3]
    if type(fr) ~= "number" or type(fg) ~= "number" or type(fb) ~= "number" then
        fr, fg, fb = DEFAULT_THEME.accent[1], DEFAULT_THEME.accent[2], DEFAULT_THEME.accent[3]
    end

    local _, classFile = UnitClass("player")
    if not classFile or classFile == "" then
        return fr, fg, fb
    end

    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, cc = pcall(C_ClassColor.GetClassColor, classFile)
        if ok and cc then
            if cc.GetRGB then
                local r, g, b = cc:GetRGB()
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    return r, g, b
                end
            elseif type(cc.r) == "number" and type(cc.g) == "number" and type(cc.b) == "number" then
                return cc.r, cc.g, cc.b
            end
        end
    end

    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if rc and type(rc.r) == "number" and type(rc.g) == "number" and type(rc.b) == "number" then
        return rc.r, rc.g, rc.b
    end

    return fr, fg, fb
end

-- Master COLORS table (created once, updated in-place — zero allocation on refresh)
-- Panel surfaces: keep bg / bgCard / list rows on one family so scroll canvas, cards, and
-- rows do not read as mismatched "black vs charcoal" (Plans, Currency, etc.).
local COLORS = {
    --- Surface ladder (borderless UX): wide steps so OLED/SDR both read zones without borders.
    bg = {0.042, 0.042, 0.055, 0.98},
    surfaceViewport = {0.068, 0.068, 0.086, 0.98},
    bgLight = {0.108, 0.108, 0.132, 0.98},
    bgCard = {0.118, 0.118, 0.145, 0.98},
    surfaceHeaderChrome = {0.098, 0.098, 0.122, 0.97},
    surfaceRowEven = {0.112, 0.112, 0.138, 0.96},
    surfaceRowOdd = {0.090, 0.090, 0.112, 0.96},
    border = {0.20, 0.20, 0.25, 1},
    borderLight = {0.30, 0.30, 0.38, 1},
    accent = {0.40, 0.20, 0.58, 1},
    accentDark = {0.28, 0.14, 0.41, 1},
    tabActive = {0.20, 0.12, 0.30, 1},
    tabHover = {0.24, 0.14, 0.35, 1},
    tabInactive = {0.05, 0.05, 0.065, 1},
    gold = {1.00, 0.82, 0.00, 1},
    green = {0.30, 0.90, 0.30, 1},
    red = {0.95, 0.30, 0.30, 1},
    textBright = {1, 1, 1, 1},
    textNormal = {0.85, 0.85, 0.85, 1},
    textMuted = {0.70, 0.70, 0.72, 1},
    textDim = {0.55, 0.55, 0.55, 1},
    white = {1, 1, 1, 1},
}

-- Light/dark/classic appearance (profile.themeMode): same surface/text KEYS, swapped values.
-- Live refresh: `ns.UI_RefreshColors` updates BORDER_REGISTRY, nav chrome, open main tabs,
-- tooltips, and floating windows. Money/quality |cff escapes keep their colors (v1 limitation).
local SURFACE_VARIANTS = {
    dark = {
        bg = {0.042, 0.042, 0.055, 0.98},
        surfaceViewport = {0.068, 0.068, 0.086, 0.98},
        bgLight = {0.108, 0.108, 0.132, 0.98},
        bgCard = {0.118, 0.118, 0.145, 0.98},
        surfaceHeaderChrome = {0.098, 0.098, 0.122, 0.97},
        surfaceRowEven = {0.112, 0.112, 0.138, 0.96},
        surfaceRowOdd = {0.090, 0.090, 0.112, 0.96},
        borderLight = {0.30, 0.30, 0.38, 1},
        tabInactive = {0.05, 0.05, 0.065, 1},
        gold = {1.00, 0.82, 0.00, 1},
        green = {0.30, 0.90, 0.30, 1},
        textBright = {1, 1, 1, 1},
        textNormal = {0.85, 0.85, 0.85, 1},
        textMuted = {0.70, 0.70, 0.72, 1},
        textDim = {0.55, 0.55, 0.55, 1},
    },
    light = {
        -- Inverted ladder: near-white shell/viewport, warm stone cards (readable ink + OUTLINE).
        bg = {0.970, 0.965, 0.955, 0.99},
        surfaceViewport = {0.985, 0.982, 0.975, 0.99},
        bgLight = {0.935, 0.930, 0.920, 0.99},
        bgCard = {0.878, 0.872, 0.858, 0.99},
        surfaceHeaderChrome = {0.905, 0.900, 0.890, 0.99},
        surfaceRowEven = {0.915, 0.910, 0.900, 0.98},
        surfaceRowOdd = {0.855, 0.850, 0.838, 0.98},
        borderLight = {0.72, 0.70, 0.68, 1},
        tabInactive = {0.945, 0.940, 0.932, 1},
        tabActive = {0.910, 0.905, 0.895, 0.98},
        tabHover = {0.925, 0.920, 0.912, 0.98},
        gold = {0.95, 0.78, 0.32, 1},
        green = {0.55, 0.88, 0.45, 1},
        -- Charcoal ink ladder (THEME-TOKENS.md); no outline on role ink — colored accents only.
        textBright = {0.12, 0.12, 0.14, 1},
        textNormal = {0.24, 0.24, 0.28, 1},
        textMuted = {0.38, 0.38, 0.42, 1},
        textDim = {0.50, 0.50, 0.54, 1},
    },
    classic = ns.UI_CLASSIC_SURFACE_VARIANT or {
        bg = { 0.065, 0.065, 0.075, 1 },
        surfaceViewport = { 0.075, 0.075, 0.085, 1 },
        bgLight = { 0.085, 0.085, 0.095, 1 },
        bgCard = { 0.095, 0.095, 0.105, 1 },
        surfaceHeaderChrome = { 0.080, 0.080, 0.090, 1 },
        surfaceRowEven = { 0.088, 0.088, 0.098, 0.96 },
        surfaceRowOdd = { 0.072, 0.072, 0.082, 0.96 },
        borderLight = { 0.55, 0.48, 0.35, 1 },
        tabInactive = { 0.055, 0.055, 0.065, 1 },
        tabActive = { 0.095, 0.095, 0.110, 0.98 },
        tabHover = { 0.105, 0.105, 0.120, 0.98 },
        gold = { 1.00, 0.82, 0.00, 1 },
        green = { 0.35, 0.85, 0.35, 1 },
        textBright = { 1.00, 0.97, 0.85, 1 },
        textNormal = { 0.92, 0.88, 0.78, 1 },
        textMuted = { 0.78, 0.72, 0.62, 1 },
        textDim = { 0.62, 0.58, 0.50, 1 },
    },
}

local function TextLuminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

--- UI chrome family: Modern (custom WN chrome) vs Classic (Blizzard templates).
---@return "modern"|"classic"
local function GetUiTheme()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not db then
        return "modern"
    end
    if db.uiTheme == "classic" then
        return "classic"
    end
    if db.uiTheme == "modern" then
        return "modern"
    end
    -- Legacy: themeMode held "classic" before uiTheme split.
    if db.themeMode == "classic" then
        return "classic"
    end
    return "modern"
end
ns.UI_GetUiTheme = GetUiTheme

local function IsModernUiTheme()
    return GetUiTheme() == "modern"
end
ns.UI_IsModernUiTheme = IsModernUiTheme

--- Modern-only surface palette key ("dark" | "light").
---@return "dark"|"light"
local function GetModernColorMode()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if db then
        if db.modernColorMode == "light" or db.themeMode == "light" then
            return "light"
        end
    end
    return "dark"
end
ns.UI_GetModernColorMode = GetModernColorMode

--- Surface variant key for COLORS / SURFACE_VARIANTS (includes classic when active).
local function GetThemeMode()
    if GetUiTheme() == "classic" then
        return "classic"
    end
    return GetModernColorMode()
end
ns.UI_GetThemeMode = GetThemeMode

local function IsLightModeEnabled()
    return GetUiTheme() == "modern" and GetModernColorMode() == "light"
end
ns.UI_IsLightMode = IsLightModeEnabled

local function IsClassicModeEnabled()
    return GetUiTheme() == "classic"
end
ns.UI_IsClassicMode = IsClassicModeEnabled
ns.UI_ShouldUseBlizzardChrome = IsClassicModeEnabled

--- Achromatic theme ink (Bright–Dim roles): no WoW OUTLINE in light mode.
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return boolean
local function IsInkNearBlack(r, g, b)
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return false
    end
    local lum = TextLuminance(r, g, b)
    local maxC = math.max(r, g, b)
    local minC = math.min(r, g, b)
    local sat = (maxC > 0) and ((maxC - minC) / maxC) or 0
    if sat >= 0.25 then
        return false
    end
    return lum <= 0.52
end
ns.UI_IsInkNearBlack = IsInkNearBlack

--- True when light theme applies WoW OUTLINE to a specific ink (colored / saturated only).
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return boolean
local function IsLightOutlineActiveForInk(r, g, b)
    if not IsLightModeEnabled() then
        return false
    end
    return not IsInkNearBlack(r, g, b)
end
ns.UI_IsLightOutlineActive = IsLightOutlineActiveForInk

--- Lift only very dark saturated ink that will carry OUTLINE on light stone.
---@param r number
---@param g number
---@param b number
---@return number nr, number ng, number nb
local function AdjustRGBForLightOutline(r, g, b)
    if not IsLightModeEnabled() then
        return r, g, b
    end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return r or 1, g or 1, b or 1
    end
    if IsInkNearBlack(r, g, b) then
        return r, g, b
    end

    local minLum = 0.36
    local lum = TextLuminance(r, g, b)
    if lum < minLum then
        local scale = minLum / math.max(lum, 0.015)
        r = math.min(1, r * scale)
        g = math.min(1, g * scale)
        b = math.min(1, b * scale)
    end

    return r, g, b
end
ns.UI_AdjustRGBForLightOutline = AdjustRGBForLightOutline

--- Accent title ink with outline-safe tuning.
---@return number r, number g, number b, number a
function ThemeAPI.GetAccentTextRGBA()
    local ac = COLORS.accent or { 0.45, 0.35, 0.72, 1 }
    local r, g, b = AdjustRGBForLightOutline(ac[1], ac[2], ac[3])
    return r, g, b, ac[4] or 1
end
ns.UI_GetAccentTextRGBA = ThemeAPI.GetAccentTextRGBA

--- Role RGBA at call time (COLORS rows are outline-adjusted in ThemeAPI.UpdateColorsFromTheme).
---@param role string|nil
---@return number r, number g, number b, number a
function ThemeAPI.ResolveTextRoleRGBA(role)
    role = role or "Normal"
    local c = COLORS["text" .. role] or COLORS.textNormal
    return c[1], c[2], c[3], c[4] or 1
end
ns.UI_ResolveTextRoleRGBA = ThemeAPI.ResolveTextRoleRGBA

--- Nav rail shell fill — dark: original `bg` tier; light: viewport tier for contrast with content.
---@return table rgba
function ThemeAPI.GetNavRailSurfaceBackdrop()
    local c = COLORS
    if IsClassicModeEnabled() then
        local row = c.surfaceRowOdd or c.bgLight or c.bg
        return { row[1], row[2], row[3], row[4] or 0.96 }
    end
    if IsLightModeEnabled() then
        local shell = c.bg or c.surfaceViewport or c.bgLight
        return { shell[1], shell[2], shell[3], shell[4] or 0.99 }
    end
    local bg = c.bg or { 0.042, 0.042, 0.055, 0.98 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }
end
ns.UI_GetNavRailSurfaceBackdrop = ThemeAPI.GetNavRailSurfaceBackdrop

--- Flat nav-rail idle backdrop (settings + main shell category buttons).
---@return table rgba
function ThemeAPI.GetNavRailIdleBackdrop()
    local c = COLORS
    if IsLightModeEnabled() then
        local row = c.surfaceRowOdd or c.bgLight or c.bg or { 0.91, 0.91, 0.92, 1 }
        return { row[1], row[2], row[3], 0.72 }
    end
    local row = c.surfaceRowOdd or c.surfaceViewport or c.bg or { 0.15, 0.15, 0.174, 1 }
    return { row[1], row[2], row[3], 0.55 }
end
ns.UI_GetNavRailIdleBackdrop = ThemeAPI.GetNavRailIdleBackdrop

--- Theme accent border RGBA — same strength in light and dark (no borderLight dilution).
---@param alpha number|nil
---@return table rgba
function ThemeAPI.GetAccentBorderRGBA(alpha)
    local ac = COLORS.accent or { 0.40, 0.20, 0.58, 1 }
    return { ac[1], ac[2], ac[3], alpha or 0.8 }
end
ns.UI_GetAccentBorderRGBA = ThemeAPI.GetAccentBorderRGBA

--- Nav rail divider / footer rule — full theme accent (no grey dilution).
---@return table rgba
function ThemeAPI.GetNavRailDividerColor()
    return ThemeAPI.GetAccentBorderRGBA(1)
end
ns.UI_GetNavRailDividerColor = ThemeAPI.GetNavRailDividerColor

--- Main window title bar — dark: original accentDark header; light: elevated surface chrome.
---@return table rgba
function ThemeAPI.GetMainHeaderChromeColor()
    local c = COLORS
    if IsClassicModeEnabled() then
        -- Title band sits inside dialog chrome — no separate floating accentDark bar.
        return { 0, 0, 0, 0 }
    end
    if IsLightModeEnabled() then
        local surf = c.surfaceHeaderChrome or c.bgLight or c.bg
        return { surf[1], surf[2], surf[3], surf[4] or 0.97 }
    end
    local ad = c.accentDark or { 0.28, 0.14, 0.41, 1 }
    return { ad[1], ad[2], ad[3], 1 }
end
ns.UI_GetMainHeaderChromeColor = ThemeAPI.GetMainHeaderChromeColor

--- Main window title bar border — theme accent (class color or profile accent).
---@return table rgba
function ThemeAPI.GetMainHeaderBorderColor()
    return ThemeAPI.GetAccentBorderRGBA(0.8)
end
ns.UI_GetMainHeaderBorderColor = ThemeAPI.GetMainHeaderBorderColor

--- Floating window title band (To-Do List, Recipe Companion, Profession Info).
---@return table rgba
function ThemeAPI.GetFloatingWindowHeaderBackdrop()
    return ThemeAPI.GetMainHeaderChromeColor()
end
ns.UI_GetFloatingWindowHeaderBackdrop = ThemeAPI.GetFloatingWindowHeaderBackdrop

---@return table rgba
function ThemeAPI.GetFloatingWindowHeaderBorder()
    return ThemeAPI.GetMainHeaderBorderColor()
end
ns.UI_GetFloatingWindowHeaderBorder = ThemeAPI.GetFloatingWindowHeaderBorder

--- Paint a companion / tracker header with theme-aware chrome.
---@param header Frame|nil
function ns.UI_ApplyFloatingWindowHeaderChrome(header)
    if not header then return end
    if IsClassicModeEnabled() and ns.UI_ApplyClassicInteriorFlatFill then
        ns.UI_ApplyClassicInteriorFlatFill(header, { 0, 0, 0, 0 })
        return
    end
    if not ApplyVisuals then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(header) then return end
    local bg = ThemeAPI.GetFloatingWindowHeaderBackdrop()
    local border = ThemeAPI.GetFloatingWindowHeaderBorder()
    ApplyVisuals(header, bg, border)
end

--- Footer hairline above version strip.
---@return table rgba
function ThemeAPI.GetFooterDividerColor()
    local div = ThemeAPI.GetNavRailDividerColor()
    return { div[1], div[2], div[3], 0.28 }
end
ns.UI_GetFooterDividerColor = ThemeAPI.GetFooterDividerColor

--- Blend two RGBA tables (t toward `b`).
---@param a table rgba
---@param b table rgba
---@param t number 0..1
---@return table rgba
function ThemeAPI.BlendColors(a, b, t)
    local inv = 1 - t
    return {
        a[1] * inv + b[1] * t,
        a[2] * inv + b[2] * t,
        a[3] * inv + b[3] * t,
        (a[4] or 1) * inv + (b[4] or 1) * t,
    }
end
ns.UI_BlendColors = ThemeAPI.BlendColors

--- Active rail tab backdrop alpha multiplier on accent RGB (dark mode only).
---@return number
function ThemeAPI.GetNavRailActiveBgAlpha()
    return 0.38
end
ns.UI_GetNavRailActiveBgAlpha = ThemeAPI.GetNavRailActiveBgAlpha

--- Active flat-rail tab fill — accent-tinted wash (light + dark).
---@return table rgba
function ThemeAPI.GetNavRailActiveBackdrop()
    local ac = COLORS.accent or { 0.40, 0.20, 0.58, 1 }
    if IsLightModeEnabled() then
        local base = COLORS.tabActive or COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        local tint = ThemeAPI.BlendColors(base, ac, 0.32)
        return { tint[1], tint[2], tint[3], tint[4] or 0.98 }
    end
    local railA = ThemeAPI.GetNavRailActiveBgAlpha()
    return { ac[1] * railA, ac[2] * railA, ac[3] * railA, 0.98 }
end
ns.UI_GetNavRailActiveBackdrop = ThemeAPI.GetNavRailActiveBackdrop

--- Horizontal tab strip inactive fill (non-rail layout).
---@return table rgba
function ThemeAPI.GetNavTabInactiveBackdrop()
    local c = COLORS
    local row = c.surfaceRowOdd or c.bgLight or c.bg
    return { row[1], row[2], row[3], row[4] or 1 }
end
ns.UI_GetNavTabInactiveBackdrop = ThemeAPI.GetNavTabInactiveBackdrop

--- Muted nav icon vertex for idle flat-rail buttons (dark mode only; light uses full-color atlas).
---@return number r, number g, number b, number a
function ThemeAPI.GetNavRailIconIdleVertex()
    return 0.72, 0.74, 0.78, 1
end
ns.UI_GetNavRailIconIdleVertex = ThemeAPI.GetNavRailIconIdleVertex

--- Muted nav icon vertex for horizontal inactive tabs.
---@return number r, number g, number b, number a
function ThemeAPI.GetNavTabIconMutedVertex()
    if IsLightModeEnabled() then
        return 0.44, 0.44, 0.48, 1
    end
    return 0.66, 0.68, 0.72, 0.92
end
ns.UI_GetNavTabIconMutedVertex = ThemeAPI.GetNavTabIconMutedVertex

--- Active nav-rail icon vertex (dark mode: white on accent wash; light: full-color atlas).
---@return number r, number g, number b, number a
function ThemeAPI.GetNavRailIconActiveVertex()
    if IsLightModeEnabled() then
        return 1, 1, 1, 1
    end
    return 1, 1, 1, 1
end
ns.UI_GetNavRailIconActiveVertex = ThemeAPI.GetNavRailIconActiveVertex

--- Nav rail / horizontal tab icon — full-color atlas; no desaturate or monochrome tint.
---@param tex Texture|nil
---@param isActive boolean
---@param opts table|nil `{ packaged = bool, rail = bool }`
function ns.UI_ApplyNavTabIconStyle(tex, isActive, opts)
    if not tex then return end
    opts = type(opts) == "table" and opts or {}
    if tex.SetBlendMode then
        tex:SetBlendMode("BLEND")
    end
    if tex.SetDesaturated then
        tex:SetDesaturated(false)
    end
    if IsLightModeEnabled() then
        tex:SetVertexColor(1, 1, 1, 1)
        return
    end
    local r, g, b, a
    if isActive then
        r, g, b, a = 1, 1, 1, 1
    elseif opts.rail or tex._wnNavRailIcon then
        r, g, b, a = ThemeAPI.GetNavRailIconIdleVertex()
    else
        r, g, b, a = ThemeAPI.GetNavTabIconMutedVertex()
    end
    tex:SetVertexColor(r, g, b, a)
end

--- Header utility glyphs (Discord, donate, reload, tracking) — full color; subtle idle tint in dark only.
---@param tex Texture|nil
---@param isHover boolean|nil
function ns.UI_ApplyHeaderUtilityIconStyle(tex, isHover)
    if not tex then return end
    if tex.SetBlendMode then
        tex:SetBlendMode("BLEND")
    end
    if tex.SetDesaturated then
        tex:SetDesaturated(false)
    end
    if isHover or IsLightModeEnabled() then
        tex:SetVertexColor(1, 1, 1, 1)
    else
        tex:SetVertexColor(0.88, 0.92, 1, 1)
    end
end

--- Main / settings nav buttons: neutral ADD highlight in light mode (default Factory blue reads as teal wash).
---@param btn Button|nil
function ns.UI_ApplyNavButtonHighlight(btn)
    if not btn or not ns.UI.Factory or not ns.UI.Factory.ApplyHighlight then return end
    if btn._wnBlizzardButton then
        if ns.UI_NormalizeBlizzardButtonChrome then
            ns.UI_NormalizeBlizzardButtonChrome(btn)
        end
        return
    end
    if IsLightModeEnabled() then
        ns.UI.Factory:ApplyHighlight(btn, { 0.45, 0.45, 0.50 }, 0.10)
    else
        ns.UI.Factory:ApplyHighlight(btn)
    end
end

--- Settings dropdown / control chrome idle fill.
---@return table rgba
function ThemeAPI.GetControlChromeBackdrop()
    local c = COLORS
    local bg = c.bgCard or c.bgLight or c.bg
    return { bg[1], bg[2], bg[3], bg[4] or 1 }
end
ns.UI_GetControlChromeBackdrop = ThemeAPI.GetControlChromeBackdrop

--- Progress bar empty track (light cream cards need a darker trough).
---@return table rgba
function ThemeAPI.GetProgressBarTrackBackdrop()
    if IsLightModeEnabled() then
        local odd = COLORS.surfaceRowOdd or { 0.78, 0.76, 0.72, 1 }
        return { odd[1], odd[2], odd[3], 0.98 }
    end
    local odd = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
    return { odd[1], odd[2], odd[3], (odd[4] or 1) * 0.55 }
end
ns.UI_GetProgressBarTrackBackdrop = ThemeAPI.GetProgressBarTrackBackdrop

--- Plan / panel card border in light mode (warm stroke + accent hint).
---@return table rgba
function ThemeAPI.GetPanelCardBorder()
    return ThemeAPI.GetAccentBorderRGBA(0.8)
end
ns.UI_GetPanelCardBorder = ThemeAPI.GetPanelCardBorder

--- Tracking status chip on main header (after control chrome helpers — Lua 5.1 forward ref).
---@return table rgba bg, table rgba border
function ThemeAPI.GetTrackingChipBackdrop()
    local bg = ThemeAPI.GetControlChromeBackdrop()
    local border = ThemeAPI.GetNavRailDividerColor()
    return bg, border
end
ns.UI_GetTrackingChipBackdrop = ThemeAPI.GetTrackingChipBackdrop

--- Row / list hover highlight for `Factory:ApplyHighlight` (theme-aware defaults).
---@return table rgb, number alpha
function ThemeAPI.GetRowHoverHighlight()
    if IsLightModeEnabled() then
        local base = COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        local ac = COLORS.accent or { 0.4, 0.2, 0.58 }
        local tint = ThemeAPI.BlendColors(base, ac, 0.28)
        return { tint[1], tint[2], tint[3] }, 0.20
    end
    if IsClassicModeEnabled() then
        return { 1, 1, 1 }, 0.055
    end
    return { 0.4, 0.6, 0.9 }, 0.15
end
ns.UI_GetRowHoverHighlight = ThemeAPI.GetRowHoverHighlight

--- Selected / online row wash (collection selBg, logged-in character row).
---@return table rgba
function ThemeAPI.GetRowSelectionTint()
    local ac = COLORS.accent or { 0.4, 0.2, 0.58, 1 }
    if IsLightModeEnabled() then
        local base = COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        return ThemeAPI.BlendColors(base, ac, 0.30)
    end
    return { ac[1] * 0.22, ac[2] * 0.22, ac[3] * 0.22, 1 }
end
ns.UI_GetRowSelectionTint = ThemeAPI.GetRowSelectionTint

--- Settings dropdown / control chrome hover fill.
---@return table rgba
function ThemeAPI.GetControlChromeHoverBackdrop()
    local c = COLORS
    if IsLightModeEnabled() then
        local base = c.surfaceRowEven or c.bgLight or c.bg
        local ac = c.accent or { 0.4, 0.2, 0.58 }
        return ThemeAPI.BlendColors(base, ac, 0.10)
    end
    local bg = c.surfaceRowEven or c.bgLight or c.bg
    return { bg[1], bg[2], bg[3], bg[4] or 1 }
end
ns.UI_GetControlChromeHoverBackdrop = ThemeAPI.GetControlChromeHoverBackdrop

--- Dropdown menu row idle fill.
---@return table rgba
function ThemeAPI.GetDropdownRowBackdrop(isCurrent)
    local c = COLORS
    if isCurrent then
        if IsLightModeEnabled() then
            return ThemeAPI.GetRowSelectionTint()
        end
        local row = c.surfaceRowEven or c.bgLight or c.bg
        return { row[1], row[2], row[3], row[4] or 1 }
    end
    local row = c.surfaceRowOdd or c.bg or { 0.07, 0.07, 0.09, 1 }
    return { row[1], row[2], row[3], row[4] or 1 }
end
ns.UI_GetDropdownRowBackdrop = ThemeAPI.GetDropdownRowBackdrop

--- Floating dropdown menu shell (Settings dropdown popups).
---@return table rgba
function ThemeAPI.GetDropdownMenuBackdrop()
    local c = COLORS
    local bg = c.bg or { 0.042, 0.042, 0.055, 0.98 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }
end
ns.UI_GetDropdownMenuBackdrop = ThemeAPI.GetDropdownMenuBackdrop

--- Nested card / detail panel inside a settings section.
---@return table rgba
function ThemeAPI.GetNestedCardBackdrop()
    local c = COLORS
    local card = c.bgCard or c.bgLight or c.bg
    return { card[1], card[2], card[3], (card[4] or 1) * 0.92 }
end
ns.UI_GetNestedCardBackdrop = ThemeAPI.GetNestedCardBackdrop

--- Accent-tinted control fill (keybind capture, selected anchor chip).
---@return table rgba
function ThemeAPI.GetAccentListeningBackdrop()
    local chrome = ThemeAPI.GetControlChromeHoverBackdrop()
    local ac = COLORS.accent or { 0.6, 0.4, 1 }
    local mix = IsLightModeEnabled() and 0.22 or 0.35
    return {
        chrome[1] + (ac[1] - chrome[1]) * mix,
        chrome[2] + (ac[2] - chrome[2]) * mix,
        chrome[3] + (ac[3] - chrome[3]) * mix,
        chrome[4] or 1,
    }
end
ns.UI_GetAccentListeningBackdrop = ThemeAPI.GetAccentListeningBackdrop

--- Floating window / popup shell fill (Vault, EA menus, changelog card fallback).
---@return table rgba
function ThemeAPI.GetExternalShellBackdrop()
    local c = COLORS
    local bg = c.bg or { 0.042, 0.042, 0.055, 0.98 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }
end
ns.UI_GetExternalShellBackdrop = ThemeAPI.GetExternalShellBackdrop

--- Modal scrim behind popups (lighter in light mode).
---@return table rgba
function ThemeAPI.GetOverlayDimColor()
    if IsLightModeEnabled() then
        return { 0.12, 0.12, 0.14, 0.42 }
    end
    return { 0, 0, 0, 0.7 }
end
ns.UI_GetOverlayDimColor = ThemeAPI.GetOverlayDimColor

--- Small chrome buttons (close, compact actions).
---@return table rgba
function ThemeAPI.GetCloseButtonBackdrop()
    local c = COLORS
    local row = c.surfaceRowEven or c.bgCard or c.bgLight or c.bg
    return { row[1], row[2], row[3], (row[4] or 1) * 0.92 }
end
ns.UI_GetCloseButtonBackdrop = ThemeAPI.GetCloseButtonBackdrop

--- Semantic positive choice card (tracking yes / tracked).
---@param hover boolean|nil
---@return table rgba bg, table rgba border
function ThemeAPI.GetSemanticPositiveCard(hover)
    if IsLightModeEnabled() then
        if hover then
            return { 0.72, 0.92, 0.78, 1 }, { 0.28, 0.62, 0.38, 1 }
        end
        return { 0.82, 0.96, 0.86, 1 }, { 0.22, 0.55, 0.32, 1 }
    end
    if hover then
        return { 0.15, 0.4, 0.25, 1 }, { 0.3, 0.8, 0.4, 1 }
    end
    return { 0.1, 0.3, 0.2, 1 }, { 0.2, 0.6, 0.3, 1 }
end
ns.UI_GetSemanticPositiveCard = ThemeAPI.GetSemanticPositiveCard

--- Semantic negative choice card (tracking no / untracked).
---@param hover boolean|nil
---@return table rgba bg, table rgba border
function ThemeAPI.GetSemanticNegativeCard(hover)
    if IsLightModeEnabled() then
        if hover then
            return { 0.94, 0.78, 0.78, 1 }, { 0.72, 0.28, 0.28, 1 }
        end
        return { 0.98, 0.86, 0.86, 1 }, { 0.62, 0.22, 0.22, 1 }
    end
    if hover then
        return { 0.4, 0.15, 0.15, 1 }, { 1, 0.3, 0.3, 1 }
    end
    return { 0.3, 0.1, 0.1, 1 }, { 0.8, 0.2, 0.2, 1 }
end
ns.UI_GetSemanticNegativeCard = ThemeAPI.GetSemanticNegativeCard

-- Update COLORS in-place from theme (zero allocation)
function ThemeAPI.UpdateColorsFromTheme()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local themeFromDb = GetThemeColors()
    local theme = themeFromDb
    if IsClassicModeEnabled() then
        theme = ns.UI_CLASSIC_ACCENT_THEME or themeFromDb
    elseif db and db.useClassColorAccent then
        local r, g, b = ns.ResolveAccentColor(themeFromDb.accent)
        theme = CalculateThemeColors(r, g, b)
    end
    COLORS.border[1], COLORS.border[2], COLORS.border[3] = theme.border[1], theme.border[2], theme.border[3]
    COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] = theme.accent[1], theme.accent[2], theme.accent[3]
    COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3] = theme.accentDark[1], theme.accentDark[2], theme.accentDark[3]
    COLORS.tabActive[1], COLORS.tabActive[2], COLORS.tabActive[3] = theme.tabActive[1], theme.tabActive[2], theme.tabActive[3]
    COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3] = theme.tabHover[1], theme.tabHover[2], theme.tabHover[3]

    -- Surface/text variant swap (in-place so cached references stay live)
    local variantKey = GetThemeMode()
    local variant = SURFACE_VARIANTS[variantKey] or SURFACE_VARIANTS.dark
    for key, src in pairs(variant) do
        local dst = COLORS[key]
        if dst then
            dst[1], dst[2], dst[3] = src[1], src[2], src[3]
            if src[4] ~= nil then dst[4] = src[4] end
        end
    end
    -- Light mode: derived tab fills fight pale surfaces — blend heavily toward viewport tier.
    if IsLightModeEnabled() then
        local bgL = COLORS.surfaceViewport or COLORS.bgLight or COLORS.bg
        for _, key in ipairs({ "tabActive", "tabHover" }) do
            local c = COLORS[key]
            local mix = (key == "tabActive") and 0.18 or 0.14
            local surf = 1 - mix
            c[1] = c[1] * mix + bgL[1] * surf
            c[2] = c[2] * mix + bgL[2] * surf
            c[3] = c[3] * mix + bgL[3] * surf
        end
    end
end

-- Role-colored FontStrings (live refresh via `ThemeAPI.RefreshRoleTextColors` / `UI_RefreshColors`).
ns.TEXT_COLOR_REGISTRY = ns.TEXT_COLOR_REGISTRY or {}
local TEXT_COLOR_REGISTRY = ns.TEXT_COLOR_REGISTRY

--- Role-based text color from the live palette (theme/light-mode aware at call time).
--- Roles: "Bright" | "Normal" | "Muted" | "Dim".
---@param fs FontString
---@param role string
---@param alpha number|nil
function ns.UI_SetTextColorRole(fs, role, alpha)
    if not fs or not fs.SetTextColor then return end
    local r, g, b, a = ThemeAPI.ResolveTextRoleRGBA(role)
    fs._wnTextRole = role
    fs._wnTextRoleAlpha = alpha
    fs._wnColoredInk = false
    if not fs._wnTextRoleRegistered then
        fs._wnTextRoleRegistered = true
        table.insert(TEXT_COLOR_REGISTRY, fs)
    end
    if fs._wnBypassInkHook then
        fs:SetTextColor(r, g, b, alpha or a)
    else
        fs._wnBypassInkHook = true
        fs:SetTextColor(r, g, b, alpha or a)
        fs._wnBypassInkHook = false
    end
    ns.UI_SyncFontStringInkOutline(fs)
end

--- Set arbitrary ink; light mode adds OUTLINE only when ink is not near-black.
---@param fs FontString|EditBox
---@param r number
---@param g number
---@param b number
---@param alpha number|nil
function ns.UI_SetInkColor(fs, r, g, b, alpha)
    if not fs or not fs.SetTextColor then return end
    fs._wnTextRole = nil
    fs._wnTextRoleAlpha = nil
    fs._wnColoredInk = not IsInkNearBlack(r, g, b)
    fs._wnBypassInkHook = true
    fs:SetTextColor(r, g, b, alpha or 1)
    fs._wnBypassInkHook = false
    ns.UI_SyncFontStringInkOutline(fs)
end

--- True when `|cff…` / `|cAARRGGBB` segments include non–near-black ink.
---@param text string|nil
---@return boolean
function ns.UI_TextHasColoredMarkup(text)
    if not text or text == "" then return false end
    if issecretvalue and issecretvalue(text) then return false end
    local pos = 1
    while true do
        local s, e, hex6 = text:find("|c[fF][fF](%x%x%x%x%x%x)", pos)
        if not s then
            s, e, hex6 = text:find("|c(%x%x%x%x%x%x%x%x)", pos)
            if s and hex6 then
                local lead = hex6:sub(1, 2):lower()
                if lead == "ff" then
                    hex6 = hex6:sub(3, 8)
                else
                    hex6 = hex6:sub(3, 8)
                end
            else
                break
            end
        end
        local r = tonumber(hex6:sub(1, 2), 16)
        local g = tonumber(hex6:sub(3, 4), 16)
        local b = tonumber(hex6:sub(5, 6), 16)
        if r and g and b then
            if not IsInkNearBlack(r / 255, g / 255, b / 255) then
                return true
            end
        end
        pos = e + 1
    end
    return false
end

--- Whether a FontString needs OUTLINE in light mode (not achromatic near-black).
---@param fs FontString|EditBox|nil
---@param text string|nil
---@return boolean
function ThemeAPI.FontStringRequiresColoredOutline(fs, text)
    if not fs then return false end
    if not IsLightModeEnabled() then return false end
    if fs._colorType == "accent" then return true end
    if text == nil and fs.GetText then
        local ok, t = pcall(fs.GetText, fs)
        if ok then text = t end
    end
    if text and text ~= "" and not (issecretvalue and issecretvalue(text)) then
        if ns.UI_TextHasColoredMarkup(text) then
            return true
        end
    end
    if fs.GetTextColor then
        local ok, r, g, b = pcall(fs.GetTextColor, fs)
        if ok and r and g and b and not IsInkNearBlack(r, g, b) then
            return true
        end
    end
    return false
end
ns.UI_FontStringRequiresColoredOutline = ThemeAPI.FontStringRequiresColoredOutline

--- Recompute `_wnColoredInk` and refresh SetFont flags (light mode outline gate).
---@param fs FontString|EditBox|nil
---@param text string|nil
function ns.UI_SyncFontStringInkOutline(fs, text)
    if not fs or fs._wnInkSyncLock then return end
    if not IsLightModeEnabled() then
        return
    end
    fs._wnInkSyncLock = true
    fs._wnColoredInk = ThemeAPI.FontStringRequiresColoredOutline(fs, text) == true
    if FontManager and FontManager.RefreshInkAwareFont then
        FontManager:RefreshInkAwareFont(fs)
    end
    fs._wnInkSyncLock = nil
end

--- After SetText / SetTextColor: apply light-mode outline when ink or markup is colored.
---@param fs FontString|EditBox|nil
---@param text string|nil
function ns.UI_ApplyFontStringPresentation(fs, text)
    ns.UI_SyncFontStringInkOutline(fs, text)
end

--- Preferred SetText entry — always runs ink/outline sync in light mode.
---@param fs FontString|nil
---@param text string|nil
function ns.UI_SetFontStringText(fs, text)
    if not fs or not fs.SetText then return end
    fs:SetText(text or "")
end

function ThemeAPI.RefreshRoleTextColors()
    for i = #TEXT_COLOR_REGISTRY, 1, -1 do
        local fs = TEXT_COLOR_REGISTRY[i]
        if not fs or not fs.SetTextColor then
            table.remove(TEXT_COLOR_REGISTRY, i)
        elseif fs._wnTextRole then
            ns.UI_SetTextColorRole(fs, fs._wnTextRole, fs._wnTextRoleAlpha)
        end
    end
end
ns.UI_RefreshRoleTextColors = ThemeAPI.RefreshRoleTextColors

--- Main nav / settings category label font — ink-aware outline (light: none on role ink).
---@param fs FontString
---@param isActive boolean
function ns.UI_SetNavLabelFontStyle(fs, isActive)
    if not fs or not fs.SetFont then return end
    if not FontManager then return end
    local category = FontManager:GetFontRole("mainNavTabLabel")
    local fontFace = FontManager:GetFontFace()
    local fontSize = FontManager:GetFontSize(category)
    local navOpts = { navLabel = true, navActive = isActive == true }
    local flags = FontManager:GetAAFlags(category, navOpts) or "OUTLINE"
    if type(fontFace) ~= "string" or fontFace == "" then
        fontFace = "Fonts\\FRIZQT__.TTF"
    end
    if type(fontSize) ~= "number" or fontSize <= 0 then
        fontSize = 12
    end
    pcall(fs.SetFont, fs, fontFace, fontSize, flags)
    if FontManager.ApplyReadableEdge then
        FontManager:ApplyReadableEdge(fs, category, navOpts)
    end
end

--- Portrait / model overlay labels: outline via font flags (no shadow stack).
---@param fs FontString|nil
function ns.UI_ApplyOverlayLabelShadow(fs)
    if not fs or not fs.SetShadowOffset then return end
    fs:SetShadowOffset(0, 0)
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end
    if FontManager and FontManager.ApplyFont and fs._fontCategory then
        FontManager:ApplyFont(fs, fs._fontCategory)
    end
end

--- Theme-aware semantic gold RGBA (money amounts, iLvl labels in light mode).
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticGoldColor()
    local g = COLORS.gold
    local r, gr, b = AdjustRGBForLightOutline(g[1], g[2], g[3])
    return r, gr, b, g[4] or 1
end
ns.UI_GetSemanticGoldColor = ThemeAPI.GetSemanticGoldColor

--- `|cffrrggbb` prefix for inline gold stat text (theme/light-mode aware).
---@return string
function ThemeAPI.GetSemanticGoldHex()
    local r, g, b = ThemeAPI.GetSemanticGoldColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticGoldHex = ThemeAPI.GetSemanticGoldHex

--- Theme-aware semantic green RGBA (upgrade arrows, recommendation deltas).
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticGreenColor()
    if IsLightModeEnabled() then
        local g = COLORS.green or { 0.55, 0.88, 0.45, 1 }
        return g[1], g[2], g[3], g[4] or 1
    end
    local g = COLORS.green or { 0.30, 0.90, 0.30, 1 }
    return g[1], g[2], g[3], g[4] or 1
end
ns.UI_GetSemanticGreenColor = ThemeAPI.GetSemanticGreenColor

--- `|cffrrggbb` for semantic green (inline |cff tokens).
---@return string
function ThemeAPI.GetSemanticGreenHex()
    local r, g, b = ThemeAPI.GetSemanticGreenColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticGreenHex = ThemeAPI.GetSemanticGreenHex

--- Slightly brighter green for target values (still readable on light surfaces).
---@return string
function ThemeAPI.GetSemanticGreenBrightHex()
    local r, g, b = ThemeAPI.GetSemanticGreenColor()
    if IsLightModeEnabled() then
        return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    end
    return format("|cff%02x%02x%02x", math.min(255, (r + 0.35) * 255), math.min(255, (g + 0.08) * 255), math.min(255, (b + 0.35) * 255))
end
ns.UI_GetSemanticGreenBrightHex = ThemeAPI.GetSemanticGreenBrightHex

--- Completed / collected plan card border (semantic positive).
---@return table rgba
function ThemeAPI.GetSemanticCompletedBorder()
    local _, border = ThemeAPI.GetSemanticPositiveCard(false)
    return border
end
ns.UI_GetSemanticCompletedBorder = ThemeAPI.GetSemanticCompletedBorder

--- `|cffrrggbb` prefix for a text role ("Bright" | "Normal" | "Muted" | "Dim").
---@param role string
---@return string
function ThemeAPI.GetTextRoleHex(role)
    local r, g, b = ThemeAPI.ResolveTextRoleRGBA(role)
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetTextRoleHex = ThemeAPI.GetTextRoleHex

--- Alias for primary label markup (`|cff` prefix).
---@return string
function ThemeAPI.GetBrightHex()
    return ThemeAPI.GetTextRoleHex("Bright")
end
ns.UI_GetBrightHex = ThemeAPI.GetBrightHex

--- Border stroke for ApplyVisuals / BORDER_REGISTRY (theme border ladder).
---@return table rgba
function ThemeAPI.GetBorderStrokeColor()
    return COLORS.border or COLORS.borderLight
end
ns.UI_GetBorderStrokeColor = ThemeAPI.GetBorderStrokeColor

--- Six-digit RRGGBB for `|cff` concatenation (no prefix).
---@param role string
---@return string
function ThemeAPI.GetTextRoleHexRaw(role)
    local r, g, b = ThemeAPI.ResolveTextRoleRGBA(role)
    return format("%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetTextRoleHexRaw = ThemeAPI.GetTextRoleHexRaw

--- Live RGBA for a text role (tooltip lines, GameTooltip hints).
---@param role string
---@return number r, number g, number b, number a
function ThemeAPI.GetTextRoleRGB(role)
    return ThemeAPI.ResolveTextRoleRGBA(role)
end
ns.UI_GetTextRoleRGB = ThemeAPI.GetTextRoleRGB

--- GameTooltip line — Blizzard tooltip keeps dark chrome; white/grey ink (not theme role ladder).
---@param tooltip GameTooltip
---@param text string
---@param role string|nil
---@param wrap boolean|nil
function ns.UI_GameTooltipAddRoleLine(tooltip, text, role, wrap)
    if not tooltip or not tooltip.AddLine then return end
    role = role or "Bright"
    local r, g, b = 1, 1, 1
    if role == "Normal" or role == "Muted" or role == "Dim" then
        r, g, b = 0.85, 0.85, 0.85
    end
    tooltip:AddLine(text, r, g, b, wrap == true)
end

--- GameTooltip title — dark tooltip shell (not light-mode panel ink).
---@param tooltip GameTooltip
---@param text string
---@param role string|nil
function ns.UI_GameTooltipSetRoleText(tooltip, text, role)
    if not tooltip or not tooltip.SetText then return end
    role = role or "Bright"
    local r, g, b = 1, 1, 1
    if role == "Normal" or role == "Muted" or role == "Dim" then
        r, g, b = 0.85, 0.85, 0.85
    end
    tooltip:SetText(text, r, g, b)
end

--- Tooltip card shell — matches elevated tab cards (`bgCard` + accent border via ApplyVisuals).
---@return table rgba bg, table rgba border
function ThemeAPI.GetTooltipShellBackdrop()
    local c = COLORS
    local bg = c.bgCard or c.bgLight or c.bg
    local border = ThemeAPI.GetAccentBorderRGBA(0.55)
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }, border
end
ns.UI_GetTooltipShellBackdrop = ThemeAPI.GetTooltipShellBackdrop

--- Custom tooltip title (achievement/plan names): semantic gold in light, WoW gold in dark.
---@return number r, number g, number b, number a
function ThemeAPI.GetTooltipTitleColor()
    if IsLightModeEnabled() then
        return ThemeAPI.GetSemanticGoldColor()
    end
    return 1, 0.82, 0, 1
end
ns.UI_GetTooltipTitleColor = ThemeAPI.GetTooltipTitleColor

--- Tooltip label column (Points:, Source:, etc.).
---@return number r, number g, number b, number a
function ThemeAPI.GetTooltipLabelColor()
    return ThemeAPI.GetTextRoleRGB("Muted")
end
ns.UI_GetTooltipLabelColor = ThemeAPI.GetTooltipLabelColor

--- Tooltip body / description lines.
---@return number r, number g, number b, number a
function ThemeAPI.GetTooltipBodyColor()
    return ThemeAPI.GetTextRoleRGB("Normal")
end
ns.UI_GetTooltipBodyColor = ThemeAPI.GetTooltipBodyColor

--- Tooltip secondary note lines.
---@return number r, number g, number b, number a
function ThemeAPI.GetTooltipDescColor()
    return ThemeAPI.GetTextRoleRGB("Muted")
end
ns.UI_GetTooltipDescColor = ThemeAPI.GetTooltipDescColor

--- Remap Blizzard GameTooltip / C_TooltipInfo line RGB for custom tooltip surfaces (light mode only).
--- Preserves saturated quality/stat hues; near-white/grey/gold become theme text roles.
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return number r, number g, number b
function ThemeAPI.RemapGameTooltipLineColor(r, g, b)
    if not IsLightModeEnabled() then
        return tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    end
    r, g, b = tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1
    local lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    local maxC = math.max(r, g, b)
    local minC = math.min(r, g, b)
    local sat = (maxC > 0) and ((maxC - minC) / maxC) or 0

    if lum >= 0.78 and sat < 0.18 then
        if lum >= 0.88 then
            return ThemeAPI.GetTextRoleRGB("Bright")
        end
        return ThemeAPI.GetTextRoleRGB("Muted")
    end

    if r >= 0.72 and g >= 0.58 and b <= 0.48 and r >= g and g >= b then
        return ThemeAPI.GetSemanticGoldColor()
    end

    if lum >= 0.45 and lum < 0.78 and sat < 0.12 then
        return ThemeAPI.GetTextRoleRGB("Dim")
    end

    return r, g, b
end
ns.UI_RemapGameTooltipLineColor = ThemeAPI.RemapGameTooltipLineColor

--- Stack/count column on item and storage rows (yellow in dark; amber on light).
---@return string `|cffrrggbb` prefix (no closing `|r`)
function ThemeAPI.GetStackCountHex()
    if IsLightModeEnabled() then
        local r, g, b = ThemeAPI.GetSemanticGoldColor()
        return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    end
    return "|cffffcc00"
end
ns.UI_GetStackCountHex = ThemeAPI.GetStackCountHex

---@param count number|nil
---@return string
function ThemeAPI.FormatStackCountMarkup(count)
    local n = count or 1
    local formatted = (ns.UI_FormatNumber and ns.UI_FormatNumber(n)) or tostring(n)
    return ThemeAPI.GetStackCountHex() .. formatted .. "|r"
end
ns.UI_FormatStackCountMarkup = ThemeAPI.FormatStackCountMarkup

--- Secondary info lines (item ID, source hints) — theme-aware blue.
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticInfoColor()
    if IsLightModeEnabled() then
        local r, g, b = AdjustRGBForLightOutline(0.08, 0.34, 0.58)
        return r, g, b, 1
    end
    return 0.4, 0.8, 1, 1
end
ns.UI_GetSemanticInfoColor = ThemeAPI.GetSemanticInfoColor

--- `|cffrrggbb` prefix for semantic info / source labels.
---@return string
function ThemeAPI.GetSemanticInfoHex()
    local r, g, b = ThemeAPI.GetSemanticInfoColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticInfoHex = ThemeAPI.GetSemanticInfoHex

--- Collection stat accent — battle pets (theme-aware magenta).
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticPetColor()
    if IsLightModeEnabled() then
        local r, g, b = AdjustRGBForLightOutline(0.62, 0.14, 0.42)
        return r, g, b, 1
    end
    return 1, 0.41, 0.71, 1
end
ns.UI_GetSemanticPetColor = ThemeAPI.GetSemanticPetColor

---@return string
function ThemeAPI.GetSemanticPetHex()
    local r, g, b = ThemeAPI.GetSemanticPetColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticPetHex = ThemeAPI.GetSemanticPetHex

--- Collection stat accent — toys (theme-aware purple).
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticToyColor()
    if IsLightModeEnabled() then
        local r, g, b = AdjustRGBForLightOutline(0.48, 0.18, 0.58)
        return r, g, b, 1
    end
    return 1, 0.4, 1, 1
end
ns.UI_GetSemanticToyColor = ThemeAPI.GetSemanticToyColor

---@return string
function ThemeAPI.GetSemanticToyHex()
    local r, g, b = ThemeAPI.GetSemanticToyColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticToyHex = ThemeAPI.GetSemanticToyHex

--- Section / collapsible header accent border (border ladder + subtle accent, not full chroma wash).
---@return number r, number g, number b, number a
function ThemeAPI.GetSectionHeaderBorderRGBA()
    local ac = COLORS.accent or { 0.4, 0.2, 0.58 }
    return ac[1], ac[2], ac[3], 0.45
end
ns.UI_GetSectionHeaderBorderRGBA = ThemeAPI.GetSectionHeaderBorderRGBA

--- Horizontal sub-tab strip: inactive border RGBA (theme accent stroke).
---@param accent table|nil rgb triple
---@return number r, number g, number b, number a
function ThemeAPI.GetSubTabInactiveBorderRGBA(accent)
    local ac = accent or COLORS.accent or { 0.40, 0.20, 0.58 }
    local a = IsLightModeEnabled() and 0.85 or 0.65
    return ac[1], ac[2], ac[3], a
end
ns.UI_GetSubTabInactiveBorderRGBA = ThemeAPI.GetSubTabInactiveBorderRGBA

--- Search / filter / stats strip chrome: transparent fill + accent border only.
---@return table rgba bg, table rgba border
function ThemeAPI.GetSearchBoxChromeColors()
    local ac = COLORS.accent or { 0.40, 0.20, 0.58 }
    local br, bgr, bb, ba = ThemeAPI.GetSubTabInactiveBorderRGBA(ac)
    return { 0, 0, 0, 0 }, { br, bgr, bb, ba }
end
ns.UI_GetSearchBoxChromeColors = ThemeAPI.GetSearchBoxChromeColors

--- Apply search/stats toolbar chrome with live theme refresh hooks (border accent only).
---@param frame Frame
---@param opts table|nil `{ editBoxHost = true }` classic: transparent shell when child uses InputBoxTemplate
function ThemeAPI.ApplySearchBoxChrome(frame, opts)
    if not frame then return end
    if type(opts) == "table" and opts.editBoxHost then
        frame._wnSearchEditBoxHost = true
    end
    frame._wnSearchChromeBorderOnly = true
    if IsClassicModeEnabled() then
        if frame._wnSearchEditBoxHost and ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(frame)
        elseif ns.UI_ApplyClassicPaneBackdrop then
            local bg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
                or (COLORS and (COLORS.surfaceHeaderChrome or COLORS.bgCard))
            ns.UI_ApplyClassicPaneBackdrop(frame, bg)
        elseif ns.UI_ApplyClassicThinBorderChrome then
            local bg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
                or (COLORS and (COLORS.surfaceHeaderChrome or COLORS.bgCard))
            ns.UI_ApplyClassicThinBorderChrome(frame, bg)
        elseif ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(frame)
        end
        if not frame._borderRegistered and ns.BORDER_REGISTRY then
            frame._borderRegistered = true
            table.insert(ns.BORDER_REGISTRY, frame)
        end
        frame._borderType = "border"
        frame._bgType = "searchChrome"
        return
    end
    if ns.UI_ApplyAccentControlChrome then
        ns.UI_ApplyAccentControlChrome(frame, {
            edgeSize = 2,
            showRail = false,
            bg = { 0, 0, 0, 0 },
        })
        frame._bgAlpha = 0
    elseif ApplyVisuals then
        local bg, border = ThemeAPI.GetSearchBoxChromeColors()
        ApplyVisuals(frame, bg, border)
        frame._borderType = "accent"
        frame._bgType = "searchChrome"
        frame._borderAlpha = border[4]
        frame._bgAlpha = 0
    end
end
ns.UI_ApplySearchBoxChrome = ThemeAPI.ApplySearchBoxChrome

--- Horizontal sub-tab strip: active fill RGBA.
---@param accent table|nil rgb triple
---@return number r, number g, number b, number a
function ThemeAPI.GetSubTabActiveBackdropRGBA(accent)
    local a = accent or COLORS.accent
    if IsLightModeEnabled() then
        local base = COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        local tint = ThemeAPI.BlendColors(base, a, 0.20)
        return tint[1], tint[2], tint[3], tint[4] or 0.98
    end
    return a[1] * 0.3, a[2] * 0.3, a[3] * 0.3, 1
end
ns.UI_GetSubTabActiveBackdropRGBA = ThemeAPI.GetSubTabActiveBackdropRGBA

--- Semantic negative (withdraw, deficits) — darker on light surfaces.
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticRedColor()
    if IsLightModeEnabled() then
        return 0.78, 0.18, 0.18, 1
    end
    local r = COLORS.red
    return r[1], r[2], r[3], r[4] or 1
end
ns.UI_GetSemanticRedColor = ThemeAPI.GetSemanticRedColor

--- Semantic caution / withdraw-orange (money log withdraw column).
---@return number r, number g, number b, number a
function ThemeAPI.GetSemanticOrangeColor()
    if IsLightModeEnabled() then
        return 0.72, 0.38, 0.06, 1
    end
    return 1, 0.65, 0.25, 1
end
ns.UI_GetSemanticOrangeColor = ThemeAPI.GetSemanticOrangeColor

--- Items tab stats bar segment colors (semantic by sub-tab; readable in light mode).
---@param context string "warband" | "guild" | "inventory" | "personal"
---@return string six-digit RRGGBB (no `|cff`)
function ThemeAPI.GetItemsContextStatHex(context)
    if IsLightModeEnabled() then
        local ac = COLORS.accent or { 0.45, 0.35, 0.72 }
        return format("%02x%02x%02x", ac[1] * 255, ac[2] * 255, ac[3] * 255)
    end
    if context == "warband" then return "a335ee"
    elseif context == "guild" then return "00ff00"
    elseif context == "inventory" then return "88ccff"
    elseif context == "personal" then return "88ff88"
    end
    return "ffffff"
end
ns.UI_GetItemsContextStatHex = ThemeAPI.GetItemsContextStatHex

--- Floating toast / dialog text shadow (lighter in light mode).
---@param strength number|nil multiplier on alpha (default 1)
---@return number r, number g, number b, number a
function ThemeAPI.GetTextShadowRGBA(strength)
    local s = strength or 1
    if IsLightModeEnabled() then
        return 0.15, 0.15, 0.18, 0.28 * s
    end
    return 0, 0, 0, 0.9 * s
end
ns.UI_GetTextShadowRGBA = ThemeAPI.GetTextShadowRGBA

-- Apply theme colors on initial load
ThemeAPI.UpdateColorsFromTheme()

--- Wire semantic aliases to live color rows (called after any in-place COLORS mutation).
function ThemeAPI.SyncSemanticColorAliases()
    COLORS.surface = COLORS.bg
    COLORS.surfaceElevated = COLORS.bgLight
    COLORS.surfaceCard = COLORS.bgCard
    COLORS.contentViewport = COLORS.surfaceViewport
    COLORS.textPrimary = COLORS.textBright
    COLORS.textSecondary = COLORS.textNormal
    COLORS.textTertiary = COLORS.textDim
    COLORS.chromeBorder = COLORS.border
    local even = COLORS.surfaceRowEven
    local odd = COLORS.surfaceRowOdd
    if even and UI_SPACING and UI_SPACING.ROW_COLOR_EVEN then
        for i = 1, 4 do UI_SPACING.ROW_COLOR_EVEN[i] = even[i] end
    end
    if odd and UI_SPACING and UI_SPACING.ROW_COLOR_ODD then
        for i = 1, 4 do UI_SPACING.ROW_COLOR_ODD[i] = odd[i] end
    end
end

function ThemeAPI.SyncThemeSurfaceColors()
    ThemeAPI.UpdateColorsFromTheme()
    ThemeAPI.SyncSemanticColorAliases()
end
ns.UI_SyncThemeSurfaceColors = ThemeAPI.SyncThemeSurfaceColors

ThemeAPI.SyncSemanticColorAliases()
ns.UI_COLORS = COLORS -- Export immediately

--- Canonical main window tab sequence (indexed hot paths avoid pairs() on nav refresh).
--- Keep in sync with `Modules/UI.lua` smoke MAIN_TAB_ORDER.
ns.UI_MAIN_TAB_ORDER = ns.UI_MAIN_TAB_ORDER or {
    "chars",
    "items",
    "gear",
    "currency",
    "reputations",
    "pve",
    "pvp",
    "professions",
    "collections",
    "plans",
    "stats",
}

-- PLAN UI COLORS (factory-standardized for Plans, WN Plan, Collections achievement UIs)
-- Semantic tiers: title/body/label/metric — accent is chrome-only (borders), never ink.
ns.PLAN_UI_COLORS = {
    title = "|cffeeeeee",
    body = "|cffeeeeee",
    label = "|cffaaaaaa",
    completed = "|cff44ff44",
    incomplete = "|cffeeeeee",
    progressLabel = "|cffaaaaaa",
    progressFull = "|cff00ff00",
    infoLabel = "|cffaaaaaa",
    sourceLabel = "|cffaaaaaa",
    tracked = "|cff44ff44",
    notTracked = "|cff888888",
    metric = "|cffffcc00",
    descDim = "|cff888888",
    completedRgb = {0.27, 1, 0.27},
    incompleteRgb = {1, 1, 1},
}

function ThemeAPI.SyncPlanUIColors()
    local p = ns.PLAN_UI_COLORS
    if not p then return end
    local brightHex = ThemeAPI.GetTextRoleHex("Bright")
    local mutedHex = ThemeAPI.GetTextRoleHex("Muted")
    local dimHex = ThemeAPI.GetTextRoleHex("Dim")
    local goldHex = ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex() or "|cffffcc00"
    local greenHex = ns.UI_RGBToHex and ns.UI_RGBToHex(ThemeAPI.GetSemanticGreenColor()) or "|cff44ff44"
    p.title = brightHex
    p.incomplete = brightHex
    p.body = brightHex
    p.label = mutedHex
    p.progressLabel = mutedHex
    p.infoLabel = mutedHex
    p.sourceLabel = mutedHex
    p.descDim = dimHex
    p.notTracked = dimHex
    p.metric = goldHex
    p.completed = greenHex
    p.tracked = greenHex
    p.progressFull = greenHex
    if IsLightModeEnabled() then
        p.completedRgb = { COLORS.green[1], COLORS.green[2], COLORS.green[3] }
        local tb = COLORS.textBright
        p.incompleteRgb = { tb[1], tb[2], tb[3] }
    else
        p.completedRgb = { 0.27, 1, 0.27 }
        p.incompleteRgb = { 1, 1, 1 }
    end
end
ThemeAPI.SyncPlanUIColors()

--- Live plan card markup color (`ns.PLAN_UI_COLORS` key).
---@param key string
---@param fallback string|nil
---@return string
function ns.UI_GetPlanUIColor(key, fallback)
    local P = ns.PLAN_UI_COLORS
    return (P and P[key]) or fallback or ""
end

-- Backward-compatible accessor (returns current COLORS table reference)
local function GetColors()
    return COLORS
end

ns.UITheme = ns.UITheme or {}
ns.UITheme.ThemeAPI = ThemeAPI
ns.UITheme.COLORS = COLORS
ns.UITheme.SURFACE_VARIANTS = SURFACE_VARIANTS
ns.UITheme.GetColors = GetColors
ns.UITheme.CalculateThemeColors = CalculateThemeColors
ns.UITheme.GetThemeColors = GetThemeColors
ns.UITheme.DEFAULT_THEME = DEFAULT_THEME
ns.UI_COLORS = COLORS
