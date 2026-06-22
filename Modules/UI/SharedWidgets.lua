--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs.
-- Satellite slices: SharedWidgets_Icons/Collapsible/Search/RowPool/Factory (ops-027–029); Pixel/CharRow load before this file.
    LuaLS: reserve ---@ on ns.UI.Factory public methods and WarbandNexus: exports only.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS

local issecretvalue = issecretvalue

local FontManager = ns.FontManager

-- Factory namespace must exist before plan-slot icon helpers (defined mid-file).
ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

--- Semantic UI role → category (FontManager.FONT_ROLE / single theme source)
local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

-- Pixel helpers: Modules/UI/SharedWidgets_Pixel.lua (ns.GetPixelScale / PixelSnap / ResetPixelScale)
local GetPixelScale = ns.GetPixelScale
local PixelSnap = ns.PixelSnap
local ResetPixelScale = ns.ResetPixelScale
assert(GetPixelScale and PixelSnap, "SharedWidgets: SharedWidgets_Pixel must load first")

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

-- Light/dark appearance (profile.themeMode): same surface/text KEYS, swapped values.
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
}

local function TextLuminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

local function GetThemeMode()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if db and db.themeMode == "light" then
        return "light"
    end
    return "dark"
end
ns.UI_GetThemeMode = GetThemeMode

local function IsLightModeEnabled()
    return GetThemeMode() == "light"
end
ns.UI_IsLightMode = IsLightModeEnabled

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
local function GetAccentTextRGBA()
    local ac = COLORS.accent or { 0.45, 0.35, 0.72, 1 }
    local r, g, b = AdjustRGBForLightOutline(ac[1], ac[2], ac[3])
    return r, g, b, ac[4] or 1
end
ns.UI_GetAccentTextRGBA = GetAccentTextRGBA

--- Role RGBA at call time (COLORS rows are outline-adjusted in UpdateColorsFromTheme).
---@param role string|nil
---@return number r, number g, number b, number a
local function ResolveTextRoleRGBA(role)
    role = role or "Normal"
    local c = COLORS["text" .. role] or COLORS.textNormal
    return c[1], c[2], c[3], c[4] or 1
end
ns.UI_ResolveTextRoleRGBA = ResolveTextRoleRGBA

--- Nav rail shell fill — dark: original `bg` tier; light: viewport tier for contrast with content.
---@return table rgba
local function GetNavRailSurfaceBackdrop()
    local c = COLORS
    if IsLightModeEnabled() then
        local shell = c.bg or c.surfaceViewport or c.bgLight
        return { shell[1], shell[2], shell[3], shell[4] or 0.99 }
    end
    local bg = c.bg or { 0.042, 0.042, 0.055, 0.98 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }
end
ns.UI_GetNavRailSurfaceBackdrop = GetNavRailSurfaceBackdrop

--- Flat nav-rail idle backdrop (settings + main shell category buttons).
---@return table rgba
local function GetNavRailIdleBackdrop()
    local c = COLORS
    if IsLightModeEnabled() then
        local row = c.surfaceRowOdd or c.bgLight or c.bg or { 0.91, 0.91, 0.92, 1 }
        return { row[1], row[2], row[3], 0.72 }
    end
    local row = c.surfaceRowOdd or c.surfaceViewport or c.bg or { 0.15, 0.15, 0.174, 1 }
    return { row[1], row[2], row[3], 0.55 }
end
ns.UI_GetNavRailIdleBackdrop = GetNavRailIdleBackdrop

--- Theme accent border RGBA — same strength in light and dark (no borderLight dilution).
---@param alpha number|nil
---@return table rgba
local function GetAccentBorderRGBA(alpha)
    local ac = COLORS.accent or { 0.40, 0.20, 0.58, 1 }
    return { ac[1], ac[2], ac[3], alpha or 0.8 }
end
ns.UI_GetAccentBorderRGBA = GetAccentBorderRGBA

--- Nav rail divider / footer rule — full theme accent (no grey dilution).
---@return table rgba
local function GetNavRailDividerColor()
    return GetAccentBorderRGBA(1)
end
ns.UI_GetNavRailDividerColor = GetNavRailDividerColor

--- Main window title bar — dark: original accentDark header; light: elevated surface chrome.
---@return table rgba
local function GetMainHeaderChromeColor()
    local c = COLORS
    if IsLightModeEnabled() then
        local surf = c.surfaceHeaderChrome or c.bgLight or c.bg
        return { surf[1], surf[2], surf[3], surf[4] or 0.97 }
    end
    local ad = c.accentDark or { 0.28, 0.14, 0.41, 1 }
    return { ad[1], ad[2], ad[3], 1 }
end
ns.UI_GetMainHeaderChromeColor = GetMainHeaderChromeColor

--- Main window title bar border — theme accent (class color or profile accent).
---@return table rgba
local function GetMainHeaderBorderColor()
    return GetAccentBorderRGBA(0.8)
end
ns.UI_GetMainHeaderBorderColor = GetMainHeaderBorderColor

--- Floating window title band (To-Do List, Recipe Companion, Profession Info).
---@return table rgba
local function GetFloatingWindowHeaderBackdrop()
    return GetMainHeaderChromeColor()
end
ns.UI_GetFloatingWindowHeaderBackdrop = GetFloatingWindowHeaderBackdrop

---@return table rgba
local function GetFloatingWindowHeaderBorder()
    return GetMainHeaderBorderColor()
end
ns.UI_GetFloatingWindowHeaderBorder = GetFloatingWindowHeaderBorder

--- Paint a companion / tracker header with theme-aware chrome.
---@param header Frame|nil
function ns.UI_ApplyFloatingWindowHeaderChrome(header)
    if not header or not ApplyVisuals then return end
    local bg = GetFloatingWindowHeaderBackdrop()
    local border = GetFloatingWindowHeaderBorder()
    ApplyVisuals(header, bg, border)
end

--- Footer hairline above version strip.
---@return table rgba
local function GetFooterDividerColor()
    local div = GetNavRailDividerColor()
    return { div[1], div[2], div[3], 0.28 }
end
ns.UI_GetFooterDividerColor = GetFooterDividerColor

--- Blend two RGBA tables (t toward `b`).
---@param a table rgba
---@param b table rgba
---@param t number 0..1
---@return table rgba
local function BlendColors(a, b, t)
    local inv = 1 - t
    return {
        a[1] * inv + b[1] * t,
        a[2] * inv + b[2] * t,
        a[3] * inv + b[3] * t,
        (a[4] or 1) * inv + (b[4] or 1) * t,
    }
end
ns.UI_BlendColors = BlendColors

--- Active rail tab backdrop alpha multiplier on accent RGB (dark mode only).
---@return number
local function GetNavRailActiveBgAlpha()
    return 0.38
end
ns.UI_GetNavRailActiveBgAlpha = GetNavRailActiveBgAlpha

--- Active flat-rail tab fill — accent-tinted wash (light + dark).
---@return table rgba
local function GetNavRailActiveBackdrop()
    local ac = COLORS.accent or { 0.40, 0.20, 0.58, 1 }
    if IsLightModeEnabled() then
        local base = COLORS.tabActive or COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        local tint = BlendColors(base, ac, 0.32)
        return { tint[1], tint[2], tint[3], tint[4] or 0.98 }
    end
    local railA = GetNavRailActiveBgAlpha()
    return { ac[1] * railA, ac[2] * railA, ac[3] * railA, 0.98 }
end
ns.UI_GetNavRailActiveBackdrop = GetNavRailActiveBackdrop

--- Horizontal tab strip inactive fill (non-rail layout).
---@return table rgba
local function GetNavTabInactiveBackdrop()
    local c = COLORS
    local row = c.surfaceRowOdd or c.bgLight or c.bg
    return { row[1], row[2], row[3], row[4] or 1 }
end
ns.UI_GetNavTabInactiveBackdrop = GetNavTabInactiveBackdrop

--- Muted nav icon vertex for idle flat-rail buttons (dark mode only; light uses full-color atlas).
---@return number r, number g, number b, number a
local function GetNavRailIconIdleVertex()
    return 0.72, 0.74, 0.78, 1
end
ns.UI_GetNavRailIconIdleVertex = GetNavRailIconIdleVertex

--- Muted nav icon vertex for horizontal inactive tabs.
---@return number r, number g, number b, number a
local function GetNavTabIconMutedVertex()
    if IsLightModeEnabled() then
        return 0.44, 0.44, 0.48, 1
    end
    return 0.66, 0.68, 0.72, 0.92
end
ns.UI_GetNavTabIconMutedVertex = GetNavTabIconMutedVertex

--- Active nav-rail icon vertex (dark mode: white on accent wash; light: full-color atlas).
---@return number r, number g, number b, number a
local function GetNavRailIconActiveVertex()
    if IsLightModeEnabled() then
        return 1, 1, 1, 1
    end
    return 1, 1, 1, 1
end
ns.UI_GetNavRailIconActiveVertex = GetNavRailIconActiveVertex

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
        r, g, b, a = GetNavRailIconIdleVertex()
    else
        r, g, b, a = GetNavTabIconMutedVertex()
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
    if IsLightModeEnabled() then
        ns.UI.Factory:ApplyHighlight(btn, { 0.45, 0.45, 0.50 }, 0.10)
    else
        ns.UI.Factory:ApplyHighlight(btn)
    end
end

--- Settings dropdown / control chrome idle fill.
---@return table rgba
local function GetControlChromeBackdrop()
    local c = COLORS
    local bg = c.bgCard or c.bgLight or c.bg
    return { bg[1], bg[2], bg[3], bg[4] or 1 }
end
ns.UI_GetControlChromeBackdrop = GetControlChromeBackdrop

--- Item / plan icon well (light: visible stone tray; dark: near-black inset).
---@return table rgba
local function GetIconWellBackdrop()
    if IsLightModeEnabled() then
        -- Darker inset tray so item art reads on stone cards (well ~= card fill).
        return { 0.66, 0.65, 0.63, 1 }
    end
    return { 0.05, 0.05, 0.07, 0.95 }
end
ns.UI_GetIconWellBackdrop = GetIconWellBackdrop

--- Border stroke for icon wells.
---@return table rgba
local function GetIconWellBorder()
    return GetAccentBorderRGBA(0.6)
end
ns.UI_GetIconWellBorder = GetIconWellBorder

--- Progress bar empty track (light cream cards need a darker trough).
---@return table rgba
local function GetProgressBarTrackBackdrop()
    if IsLightModeEnabled() then
        local odd = COLORS.surfaceRowOdd or { 0.78, 0.76, 0.72, 1 }
        return { odd[1], odd[2], odd[3], 0.98 }
    end
    local odd = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
    return { odd[1], odd[2], odd[3], (odd[4] or 1) * 0.55 }
end
ns.UI_GetProgressBarTrackBackdrop = GetProgressBarTrackBackdrop

--- Plan / panel card border in light mode (warm stroke + accent hint).
---@return table rgba
local function GetPanelCardBorder()
    return GetAccentBorderRGBA(0.8)
end
ns.UI_GetPanelCardBorder = GetPanelCardBorder

--- Tracking status chip on main header (after control chrome helpers — Lua 5.1 forward ref).
---@return table rgba bg, table rgba border
local function GetTrackingChipBackdrop()
    local bg = GetControlChromeBackdrop()
    local border = GetNavRailDividerColor()
    return bg, border
end
ns.UI_GetTrackingChipBackdrop = GetTrackingChipBackdrop

--- Row / list hover highlight for `Factory:ApplyHighlight` (theme-aware defaults).
---@return table rgb, number alpha
local function GetRowHoverHighlight()
    if IsLightModeEnabled() then
        local base = COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        local ac = COLORS.accent or { 0.4, 0.2, 0.58 }
        local tint = BlendColors(base, ac, 0.28)
        return { tint[1], tint[2], tint[3] }, 0.20
    end
    return { 0.4, 0.6, 0.9 }, 0.15
end
ns.UI_GetRowHoverHighlight = GetRowHoverHighlight

--- Selected / online row wash (collection selBg, logged-in character row).
---@return table rgba
local function GetRowSelectionTint()
    local ac = COLORS.accent or { 0.4, 0.2, 0.58, 1 }
    if IsLightModeEnabled() then
        local base = COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        return BlendColors(base, ac, 0.30)
    end
    return { ac[1] * 0.22, ac[2] * 0.22, ac[3] * 0.22, 1 }
end
ns.UI_GetRowSelectionTint = GetRowSelectionTint

--- Settings dropdown / control chrome hover fill.
---@return table rgba
local function GetControlChromeHoverBackdrop()
    local c = COLORS
    if IsLightModeEnabled() then
        local base = c.surfaceRowEven or c.bgLight or c.bg
        local ac = c.accent or { 0.4, 0.2, 0.58 }
        return BlendColors(base, ac, 0.10)
    end
    local bg = c.surfaceRowEven or c.bgLight or c.bg
    return { bg[1], bg[2], bg[3], bg[4] or 1 }
end
ns.UI_GetControlChromeHoverBackdrop = GetControlChromeHoverBackdrop

--- Dropdown menu row idle fill.
---@return table rgba
local function GetDropdownRowBackdrop(isCurrent)
    local c = COLORS
    if isCurrent then
        if IsLightModeEnabled() then
            return GetRowSelectionTint()
        end
        local row = c.surfaceRowEven or c.bgLight or c.bg
        return { row[1], row[2], row[3], row[4] or 1 }
    end
    local row = c.surfaceRowOdd or c.bg or { 0.07, 0.07, 0.09, 1 }
    return { row[1], row[2], row[3], row[4] or 1 }
end
ns.UI_GetDropdownRowBackdrop = GetDropdownRowBackdrop

--- Floating dropdown menu shell (Settings dropdown popups).
---@return table rgba
local function GetDropdownMenuBackdrop()
    local c = COLORS
    local bg = c.bg or { 0.042, 0.042, 0.055, 0.98 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }
end
ns.UI_GetDropdownMenuBackdrop = GetDropdownMenuBackdrop

--- Nested card / detail panel inside a settings section.
---@return table rgba
local function GetNestedCardBackdrop()
    local c = COLORS
    local card = c.bgCard or c.bgLight or c.bg
    return { card[1], card[2], card[3], (card[4] or 1) * 0.92 }
end
ns.UI_GetNestedCardBackdrop = GetNestedCardBackdrop

--- Accent-tinted control fill (keybind capture, selected anchor chip).
---@return table rgba
local function GetAccentListeningBackdrop()
    local chrome = GetControlChromeHoverBackdrop()
    local ac = COLORS.accent or { 0.6, 0.4, 1 }
    local mix = IsLightModeEnabled() and 0.22 or 0.35
    return {
        chrome[1] + (ac[1] - chrome[1]) * mix,
        chrome[2] + (ac[2] - chrome[2]) * mix,
        chrome[3] + (ac[3] - chrome[3]) * mix,
        chrome[4] or 1,
    }
end
ns.UI_GetAccentListeningBackdrop = GetAccentListeningBackdrop

--- Floating window / popup shell fill (Vault, EA menus, changelog card fallback).
---@return table rgba
local function GetExternalShellBackdrop()
    local c = COLORS
    local bg = c.bg or { 0.042, 0.042, 0.055, 0.98 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }
end
ns.UI_GetExternalShellBackdrop = GetExternalShellBackdrop

--- Modal scrim behind popups (lighter in light mode).
---@return table rgba
local function GetOverlayDimColor()
    if IsLightModeEnabled() then
        return { 0.12, 0.12, 0.14, 0.42 }
    end
    return { 0, 0, 0, 0.7 }
end
ns.UI_GetOverlayDimColor = GetOverlayDimColor

--- Small chrome buttons (close, compact actions).
---@return table rgba
local function GetCloseButtonBackdrop()
    local c = COLORS
    local row = c.surfaceRowEven or c.bgCard or c.bgLight or c.bg
    return { row[1], row[2], row[3], (row[4] or 1) * 0.92 }
end
ns.UI_GetCloseButtonBackdrop = GetCloseButtonBackdrop

--- Semantic positive choice card (tracking yes / tracked).
---@param hover boolean|nil
---@return table rgba bg, table rgba border
local function GetSemanticPositiveCard(hover)
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
ns.UI_GetSemanticPositiveCard = GetSemanticPositiveCard

--- Semantic negative choice card (tracking no / untracked).
---@param hover boolean|nil
---@return table rgba bg, table rgba border
local function GetSemanticNegativeCard(hover)
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
ns.UI_GetSemanticNegativeCard = GetSemanticNegativeCard

-- Update COLORS in-place from theme (zero allocation)
local function UpdateColorsFromTheme()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local themeFromDb = GetThemeColors()
    local theme = themeFromDb
    if db and db.useClassColorAccent then
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
    local variant = SURFACE_VARIANTS[variantKey]
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

-- Role-colored FontStrings (live refresh via `RefreshRoleTextColors` / `UI_RefreshColors`).
ns.TEXT_COLOR_REGISTRY = ns.TEXT_COLOR_REGISTRY or {}
local TEXT_COLOR_REGISTRY = ns.TEXT_COLOR_REGISTRY

--- Role-based text color from the live palette (theme/light-mode aware at call time).
--- Roles: "Bright" | "Normal" | "Muted" | "Dim".
---@param fs FontString
---@param role string
---@param alpha number|nil
function ns.UI_SetTextColorRole(fs, role, alpha)
    if not fs or not fs.SetTextColor then return end
    local r, g, b, a = ResolveTextRoleRGBA(role)
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
local function FontStringRequiresColoredOutline(fs, text)
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
ns.UI_FontStringRequiresColoredOutline = FontStringRequiresColoredOutline

--- Recompute `_wnColoredInk` and refresh SetFont flags (light mode outline gate).
---@param fs FontString|EditBox|nil
---@param text string|nil
function ns.UI_SyncFontStringInkOutline(fs, text)
    if not fs or fs._wnInkSyncLock then return end
    if not IsLightModeEnabled() then
        return
    end
    fs._wnInkSyncLock = true
    fs._wnColoredInk = FontStringRequiresColoredOutline(fs, text) == true
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

local function RefreshRoleTextColors()
    for i = #TEXT_COLOR_REGISTRY, 1, -1 do
        local fs = TEXT_COLOR_REGISTRY[i]
        if not fs or not fs.SetTextColor then
            table.remove(TEXT_COLOR_REGISTRY, i)
        elseif fs._wnTextRole then
            ns.UI_SetTextColorRole(fs, fs._wnTextRole, fs._wnTextRoleAlpha)
        end
    end
end
ns.UI_RefreshRoleTextColors = RefreshRoleTextColors

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
local function GetSemanticGoldColor()
    local g = COLORS.gold
    local r, gr, b = AdjustRGBForLightOutline(g[1], g[2], g[3])
    return r, gr, b, g[4] or 1
end
ns.UI_GetSemanticGoldColor = GetSemanticGoldColor

--- `|cffrrggbb` prefix for inline gold stat text (theme/light-mode aware).
---@return string
local function GetSemanticGoldHex()
    local r, g, b = GetSemanticGoldColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticGoldHex = GetSemanticGoldHex

--- Theme-aware semantic green RGBA (upgrade arrows, recommendation deltas).
---@return number r, number g, number b, number a
local function GetSemanticGreenColor()
    if IsLightModeEnabled() then
        local g = COLORS.green or { 0.55, 0.88, 0.45, 1 }
        return g[1], g[2], g[3], g[4] or 1
    end
    local g = COLORS.green or { 0.30, 0.90, 0.30, 1 }
    return g[1], g[2], g[3], g[4] or 1
end
ns.UI_GetSemanticGreenColor = GetSemanticGreenColor

--- `|cffrrggbb` for semantic green (inline |cff tokens).
---@return string
local function GetSemanticGreenHex()
    local r, g, b = GetSemanticGreenColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticGreenHex = GetSemanticGreenHex

--- Slightly brighter green for target values (still readable on light surfaces).
---@return string
local function GetSemanticGreenBrightHex()
    local r, g, b = GetSemanticGreenColor()
    if IsLightModeEnabled() then
        return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    end
    return format("|cff%02x%02x%02x", math.min(255, (r + 0.35) * 255), math.min(255, (g + 0.08) * 255), math.min(255, (b + 0.35) * 255))
end
ns.UI_GetSemanticGreenBrightHex = GetSemanticGreenBrightHex

--- Completed / collected plan card border (semantic positive).
---@return table rgba
local function GetSemanticCompletedBorder()
    local _, border = GetSemanticPositiveCard(false)
    return border
end
ns.UI_GetSemanticCompletedBorder = GetSemanticCompletedBorder

--- `|cffrrggbb` prefix for a text role ("Bright" | "Normal" | "Muted" | "Dim").
---@param role string
---@return string
local function GetTextRoleHex(role)
    local r, g, b = ResolveTextRoleRGBA(role)
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetTextRoleHex = GetTextRoleHex

--- Alias for primary label markup (`|cff` prefix).
---@return string
local function GetBrightHex()
    return GetTextRoleHex("Bright")
end
ns.UI_GetBrightHex = GetBrightHex

--- Border stroke for ApplyVisuals / BORDER_REGISTRY (theme border ladder).
---@return table rgba
local function GetBorderStrokeColor()
    return COLORS.border or COLORS.borderLight
end
ns.UI_GetBorderStrokeColor = GetBorderStrokeColor

--- Six-digit RRGGBB for `|cff` concatenation (no prefix).
---@param role string
---@return string
local function GetTextRoleHexRaw(role)
    local r, g, b = ResolveTextRoleRGBA(role)
    return format("%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetTextRoleHexRaw = GetTextRoleHexRaw

--- Live RGBA for a text role (tooltip lines, GameTooltip hints).
---@param role string
---@return number r, number g, number b, number a
local function GetTextRoleRGB(role)
    return ResolveTextRoleRGBA(role)
end
ns.UI_GetTextRoleRGB = GetTextRoleRGB

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
local function GetTooltipShellBackdrop()
    local c = COLORS
    local bg = c.bgCard or c.bgLight or c.bg
    local border = GetAccentBorderRGBA(0.55)
    return { bg[1], bg[2], bg[3], bg[4] or 0.98 }, border
end
ns.UI_GetTooltipShellBackdrop = GetTooltipShellBackdrop

--- Custom tooltip title (achievement/plan names): semantic gold in light, WoW gold in dark.
---@return number r, number g, number b, number a
local function GetTooltipTitleColor()
    if IsLightModeEnabled() then
        return GetSemanticGoldColor()
    end
    return 1, 0.82, 0, 1
end
ns.UI_GetTooltipTitleColor = GetTooltipTitleColor

--- Tooltip label column (Points:, Source:, etc.).
---@return number r, number g, number b, number a
local function GetTooltipLabelColor()
    return GetTextRoleRGB("Muted")
end
ns.UI_GetTooltipLabelColor = GetTooltipLabelColor

--- Tooltip body / description lines.
---@return number r, number g, number b, number a
local function GetTooltipBodyColor()
    return GetTextRoleRGB("Normal")
end
ns.UI_GetTooltipBodyColor = GetTooltipBodyColor

--- Tooltip secondary note lines.
---@return number r, number g, number b, number a
local function GetTooltipDescColor()
    return GetTextRoleRGB("Muted")
end
ns.UI_GetTooltipDescColor = GetTooltipDescColor

--- Remap Blizzard GameTooltip / C_TooltipInfo line RGB for custom tooltip surfaces (light mode only).
--- Preserves saturated quality/stat hues; near-white/grey/gold become theme text roles.
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@return number r, number g, number b
local function RemapGameTooltipLineColor(r, g, b)
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
            return GetTextRoleRGB("Bright")
        end
        return GetTextRoleRGB("Muted")
    end

    if r >= 0.72 and g >= 0.58 and b <= 0.48 and r >= g and g >= b then
        return GetSemanticGoldColor()
    end

    if lum >= 0.45 and lum < 0.78 and sat < 0.12 then
        return GetTextRoleRGB("Dim")
    end

    return r, g, b
end
ns.UI_RemapGameTooltipLineColor = RemapGameTooltipLineColor

--- Stack/count column on item and storage rows (yellow in dark; amber on light).
---@return string `|cffrrggbb` prefix (no closing `|r`)
local function GetStackCountHex()
    if IsLightModeEnabled() then
        local r, g, b = GetSemanticGoldColor()
        return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
    end
    return "|cffffcc00"
end
ns.UI_GetStackCountHex = GetStackCountHex

---@param count number|nil
---@return string
local function FormatStackCountMarkup(count)
    local n = count or 1
    local formatted = (ns.UI_FormatNumber and ns.UI_FormatNumber(n)) or tostring(n)
    return GetStackCountHex() .. formatted .. "|r"
end
ns.UI_FormatStackCountMarkup = FormatStackCountMarkup

--- Secondary info lines (item ID, source hints) — theme-aware blue.
---@return number r, number g, number b, number a
local function GetSemanticInfoColor()
    if IsLightModeEnabled() then
        local r, g, b = AdjustRGBForLightOutline(0.08, 0.34, 0.58)
        return r, g, b, 1
    end
    return 0.4, 0.8, 1, 1
end
ns.UI_GetSemanticInfoColor = GetSemanticInfoColor

--- `|cffrrggbb` prefix for semantic info / source labels.
---@return string
local function GetSemanticInfoHex()
    local r, g, b = GetSemanticInfoColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticInfoHex = GetSemanticInfoHex

--- Collection stat accent — battle pets (theme-aware magenta).
---@return number r, number g, number b, number a
local function GetSemanticPetColor()
    if IsLightModeEnabled() then
        local r, g, b = AdjustRGBForLightOutline(0.62, 0.14, 0.42)
        return r, g, b, 1
    end
    return 1, 0.41, 0.71, 1
end
ns.UI_GetSemanticPetColor = GetSemanticPetColor

---@return string
local function GetSemanticPetHex()
    local r, g, b = GetSemanticPetColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticPetHex = GetSemanticPetHex

--- Collection stat accent — toys (theme-aware purple).
---@return number r, number g, number b, number a
local function GetSemanticToyColor()
    if IsLightModeEnabled() then
        local r, g, b = AdjustRGBForLightOutline(0.48, 0.18, 0.58)
        return r, g, b, 1
    end
    return 1, 0.4, 1, 1
end
ns.UI_GetSemanticToyColor = GetSemanticToyColor

---@return string
local function GetSemanticToyHex()
    local r, g, b = GetSemanticToyColor()
    return format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetSemanticToyHex = GetSemanticToyHex

--- Section / collapsible header accent border (border ladder + subtle accent, not full chroma wash).
---@return number r, number g, number b, number a
local function GetSectionHeaderBorderRGBA()
    local ac = COLORS.accent or { 0.4, 0.2, 0.58 }
    return ac[1], ac[2], ac[3], 0.45
end
ns.UI_GetSectionHeaderBorderRGBA = GetSectionHeaderBorderRGBA

--- Horizontal sub-tab strip: inactive border RGBA (theme accent stroke).
---@param accent table|nil rgb triple
---@return number r, number g, number b, number a
local function GetSubTabInactiveBorderRGBA(accent)
    local ac = accent or COLORS.accent or { 0.40, 0.20, 0.58 }
    local a = IsLightModeEnabled() and 0.85 or 0.65
    return ac[1], ac[2], ac[3], a
end
ns.UI_GetSubTabInactiveBorderRGBA = GetSubTabInactiveBorderRGBA

--- Search / filter / stats strip chrome: transparent fill + accent border only.
---@return table rgba bg, table rgba border
local function GetSearchBoxChromeColors()
    local ac = COLORS.accent or { 0.40, 0.20, 0.58 }
    local br, bgr, bb, ba = GetSubTabInactiveBorderRGBA(ac)
    return { 0, 0, 0, 0 }, { br, bgr, bb, ba }
end
ns.UI_GetSearchBoxChromeColors = GetSearchBoxChromeColors

--- Apply search/stats toolbar chrome with live theme refresh hooks (border accent only).
---@param frame Frame
local function ApplySearchBoxChrome(frame)
    if not frame then return end
    frame._wnSearchChromeBorderOnly = true
    if ns.UI_ApplyAccentControlChrome then
        ns.UI_ApplyAccentControlChrome(frame, {
            edgeSize = 2,
            showRail = false,
            bg = { 0, 0, 0, 0 },
        })
        frame._bgAlpha = 0
    elseif ApplyVisuals then
        local bg, border = GetSearchBoxChromeColors()
        ApplyVisuals(frame, bg, border)
        frame._borderType = "accent"
        frame._bgType = "searchChrome"
        frame._borderAlpha = border[4]
        frame._bgAlpha = 0
    end
end
ns.UI_ApplySearchBoxChrome = ApplySearchBoxChrome

--- Horizontal sub-tab strip: active fill RGBA.
---@param accent table|nil rgb triple
---@return number r, number g, number b, number a
local function GetSubTabActiveBackdropRGBA(accent)
    local a = accent or COLORS.accent
    if IsLightModeEnabled() then
        local base = COLORS.surfaceRowEven or COLORS.bgLight or COLORS.bg
        local tint = BlendColors(base, a, 0.20)
        return tint[1], tint[2], tint[3], tint[4] or 0.98
    end
    return a[1] * 0.3, a[2] * 0.3, a[3] * 0.3, 1
end
ns.UI_GetSubTabActiveBackdropRGBA = GetSubTabActiveBackdropRGBA

--- Semantic negative (withdraw, deficits) — darker on light surfaces.
---@return number r, number g, number b, number a
local function GetSemanticRedColor()
    if IsLightModeEnabled() then
        return 0.78, 0.18, 0.18, 1
    end
    local r = COLORS.red
    return r[1], r[2], r[3], r[4] or 1
end
ns.UI_GetSemanticRedColor = GetSemanticRedColor

--- Semantic caution / withdraw-orange (money log withdraw column).
---@return number r, number g, number b, number a
local function GetSemanticOrangeColor()
    if IsLightModeEnabled() then
        return 0.72, 0.38, 0.06, 1
    end
    return 1, 0.65, 0.25, 1
end
ns.UI_GetSemanticOrangeColor = GetSemanticOrangeColor

--- Items tab stats bar segment colors (semantic by sub-tab; readable in light mode).
---@param context string "warband" | "guild" | "inventory" | "personal"
---@return string six-digit RRGGBB (no `|cff`)
local function GetItemsContextStatHex(context)
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
ns.UI_GetItemsContextStatHex = GetItemsContextStatHex

--- Floating toast / dialog text shadow (lighter in light mode).
---@param strength number|nil multiplier on alpha (default 1)
---@return number r, number g, number b, number a
local function GetTextShadowRGBA(strength)
    local s = strength or 1
    if IsLightModeEnabled() then
        return 0.15, 0.15, 0.18, 0.28 * s
    end
    return 0, 0, 0, 0.9 * s
end
ns.UI_GetTextShadowRGBA = GetTextShadowRGBA

-- Apply theme colors on initial load
UpdateColorsFromTheme()

--- Wire semantic aliases to live color rows (called after any in-place COLORS mutation).
local function SyncSemanticColorAliases()
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

local function SyncThemeSurfaceColors()
    UpdateColorsFromTheme()
    SyncSemanticColorAliases()
end
ns.UI_SyncThemeSurfaceColors = SyncThemeSurfaceColors

SyncSemanticColorAliases()
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

local function SyncPlanUIColors()
    local p = ns.PLAN_UI_COLORS
    if not p then return end
    local brightHex = GetTextRoleHex("Bright")
    local mutedHex = GetTextRoleHex("Muted")
    local dimHex = GetTextRoleHex("Dim")
    local goldHex = ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex() or "|cffffcc00"
    local greenHex = ns.UI_RGBToHex and ns.UI_RGBToHex(GetSemanticGreenColor()) or "|cff44ff44"
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
SyncPlanUIColors()

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

-- SPACING CONSTANTS (Standardized across all tabs)

-- Unified spacing constants (UPPER_CASE standard)
local UI_SPACING = {
    -- Horizontal indentation (levels)
    BASE_INDENT = 15,          -- Base indent unit (15px per level)
    SUBROW_EXTRA_INDENT = 10,  -- Extra indent for sub-rows (total Level 2 = 40px)
    -- Usage: Level 0 = 0px, Level 1 = BASE_INDENT (15px), Level 2 = BASE_INDENT * 2 + SUBROW_EXTRA_INDENT (40px)
    
    -- Margins (aligned with MAIN_SHELL.CONTENT_PAD_*)
    SIDE_MARGIN = 12,          -- Left/right content margin
    TOP_MARGIN = 10,           -- Top content margin
    
    -- Vertical spacing (between elements)
    HEADER_SPACING = 44,       -- After CreateCollapsibleHeader (SECTION_COLLAPSE_HEADER_HEIGHT + SECTION_SPACING)
    SUBHEADER_SPACING = 44,    -- Same as HEADER_SPACING for nested collapsible headers
    ROW_SPACING = 26,          -- Space after rows (26px height + 0px gap for tight layout)
    SECTION_SPACING = 12,      -- Space between sections (matches MAIN_SHELL.CONTENT_SECTION_GAP)
    EMPTY_STATE_SPACING = 100, -- Empty state message spacing
    MIN_BOTTOM_SPACING = 20,   -- Minimum bottom padding
    SCROLL_CONTENT_TOP_PADDING = 12,    -- Padding above scroll content (so rows/headers don't touch border)
    SCROLL_CONTENT_BOTTOM_PADDING = 12, -- Padding below scroll content
    SCROLL_BASE_STEP = 28,              -- Base scroll speed in pixels per wheel tick
    SCROLL_SPEED_DEFAULT = 1.0,          -- Default speed multiplier (profile.scrollSpeed)
    AFTER_HEADER = 75,         -- Space after main header
    AFTER_ELEMENT = 8,         -- Space after generic element
    CARD_GAP = 10,             -- Gap between cards
    
    -- Row dimensions
    ROW_HEIGHT = 26,           -- Standard row height
    --- Bank/storage aggregate leaf rows (ItemsUI DrawStorageResults): taller than ROW_HEIGHT so body-font descenders are not covered by the next row's bg.
    STORAGE_ROW_HEIGHT = 30,
    CHAR_ROW_HEIGHT = 36,      -- Character row height (+20% from 30)
    HEADER_HEIGHT = 32,        -- Legacy row strip (Collections virtual rows); collapsible + Factory section headers use SECTION_COLLAPSE_HEADER_HEIGHT
    SECTION_COLLAPSE_HEADER_HEIGHT = 36, -- CreateCollapsibleHeader + Factory `CreateSectionHeader` default (compact; was 44)
    --- Stripe + chevron inset tokens: `CreateCollapsibleHeader` / `Factory:CreateSectionHeader` (Phase 2 alignment)
    SECTION_HEADER_STRIPE_WIDTH = 3,
    SECTION_HEADER_STRIPE_V_INSET = 4,
    SECTION_HEADER_COLLAPSE_CHEVRON_LEFT = 12,
    SECTION_HEADER_FACTORY_CHEVRON_LEFT = 10,
    SECTION_HEADER_CATEGORY_ICON_GAP = 8,
    SECTION_HEADER_TITLE_AFTER_ICON = 12,
    --- `CreateSection` settings / card chrome (replaces magic 15 / -12 / -40)
    SECTION_CARD_PADDING_X = 15,
    SECTION_CARD_TITLE_TOP = -12,
    SECTION_CARD_BODY_TOP_WITH_TITLE = -40,
    SECTION_CARD_BODY_TOP_NO_TITLE = -15,

    --- Standard tab title card (`CreateStandardTabTitleCard`): Characters + Items/Bank chrome
    TITLE_CARD_DEFAULT_HEIGHT = 64,
    --- Fixed square tile (glyph centered inside; never stretch with card height).
    TITLE_CARD_ICON_TILE_OUTER = 44,
    --- Uniform inset inside the square tile (TOPLEFT/BOTTOMRIGHT anchors; keeps glyph square).
    TITLE_CARD_ICON_GLYPH_PAD = 4,
    --- @deprecated use TITLE_CARD_ICON_GLYPH_PAD + tile anchors; kept for opts.glyphSize callers.
    TITLE_CARD_ICON_GLYPH_SIZE = 38,
    TITLE_CARD_ICON_SIZE = 44,
    TITLE_CARD_ICON_PAD = 5,
    TITLE_CARD_ICON_INSET = 12,
    --- Horizontal padding inside title card (icon left + text right when no toolbar).
    TITLE_CARD_CONTENT_PAD_H = 12,
    --- Icon block inset from card left (defaults to TITLE_CARD_CONTENT_PAD_H).
    TITLE_CARD_ICON_SIDE_INSET = 12,
    TITLE_CARD_TOOLBAR_EDGE_INSET = 12,
    TITLE_CARD_ICON_BORDER_ALPHA = 0.45,
    TITLE_CARD_UNDERLINE_ALPHA = 0.5,
    TITLE_CARD_RING_TEXT_GAP = 8,
    TITLE_CARD_TEXT_PAD_V = 8,
    TITLE_CARD_TEXT_STACK_GAP = 3,
    --- Legacy alias: icon block center X from card left (`contentPad + iconSize/2`).
    TITLE_CARD_RING_CENTER_X = 12 + 22,
    --- Vertical gap below a collapsible band before the next sibling (`CharactersUI` section stacks)
    SECTION_STACK_GAP_UNDER_HEADER = 12,

    -- Icon standardization
    HEADER_ICON_SIZE = 24,     -- Header icon size (reduced from 28 for better balance)
    ROW_ICON_SIZE = 20,        -- Row icon size (reduced from 22 for better balance)
    ICON_VERTICAL_ALIGN = 0,   -- CENTER vertical alignment offset

    --- Collapse/expand chevron: one `Button` + single inner texture (`_wnCollapseTex`), same size everywhere.
    COLLAPSE_EXPAND_BUTTON_SIZE = 22,
    --- Section headers (`CreateCollapsibleHeader`): slightly larger than generic collapse controls.
    SECTION_COLLAPSE_CHEVRON_SIZE = 26,
    COLLAPSE_EXPAND_ATLAS_EXPANDED = "UI-HUD-ActionBar-PageUpArrow-Mouseover",
    COLLAPSE_EXPAND_ATLAS_COLLAPSED = "UI-HUD-ActionBar-PageDownArrow-Mouseover",

    --- Storage / Bank item rows: location label inset from row edge (scrollbar + padding)
    LIST_ROW_LOCATION_RIGHT_INSET = 28,
    --- Max width for "Bag N" / "Tab N" / localized bank strings; name column ends at `LEFT` of this.
    LIST_ROW_LOCATION_MAX_WIDTH = 120,
    
    --- Row striping (synced from COLORS.surfaceRow* in SyncSemanticColorAliases).
    ROW_COLOR_EVEN = {0.112, 0.112, 0.138, 0.96},
    ROW_COLOR_ODD = {0.090, 0.090, 0.112, 0.96},
    
    -- Backward compatibility aliases (camelCase)
    betweenSections = 8,
    betweenRows = 0,
    --- Vertical gap between sibling **data rows** only (never section/category headers or card grids).
    dataRowGap = 4,
    --- Plans ▸ Achievements expandable rows: vertical gap below each row (betweenRows is 0 for tight lists).
    achievementRowGapBelow = 8,
    headerSpacing = 44,
    afterElement = 8,
    cardGap = 8,
    rowHeight = 26,
    storageRowHeight = 30,
    charRowHeight = 36,
    headerHeight = 32,
    rowSpacing = 26,
    sideMargin = 12,
    topMargin = 0,
    --- Tab chrome rhythm (fixedHeader + scroll body); use helpers below — do not hardcode 75/8.
    TAB_CHROME_BLOCK_GAP = 8,
    TAB_TITLE_TO_BODY_GAP = 6,
    TAB_CHROME_SCROLL_TOP = 8,
    TAB_CHROME_CONTENT_BOTTOM_PAD = 12,
    afterHeader = 72,
    subHeaderSpacing = 44,
    emptyStateSpacing = 100,
    minBottomSpacing = 20,
    headerIconSize = 24,
    rowIconSize = 20,
    iconVerticalAlign = 0,
    -- Standard scroll bar: Button (top) | Bar | Button (bottom); same everywhere
    SCROLL_BAR_BUTTON_SIZE = 16,
    SCROLL_BAR_WIDTH = 16,
    -- Slightly wider column so vertical + horizontal scroll controls are easier to notice
    SCROLLBAR_COLUMN_WIDTH = 26,
    -- Must match SCROLL_BAR_BUTTON_SIZE so track + thumb are not taller than arrow buttons
    HORIZONTAL_SCROLL_BAR_HEIGHT = 16,

    --- Title card toolbar: inset from RIGHT edge for the rightmost control (sort, timer, primary button)
    TITLE_CARD_CONTROL_RIGHT_INSET = 0,
    TITLE_CARD_ICON_BORDER_ALPHA = 0.55,
    --- Horizontal gap between adjacent controls on a title card toolbar row
    HEADER_TOOLBAR_CONTROL_GAP = 8,
    --- Sort-style dropdown menus: height of one option row (matches ROW_HEIGHT)
    DROPDOWN_MENU_ROW_HEIGHT = 26,
    --- Shared dropdown scroll menus: fixed viewport row cap before scrollbar appears.
    DROPDOWN_MAX_VISIBLE_ROWS = 6,
    DROPDOWN_MENU_EDGE = 4,
    DROPDOWN_INSET_TOP = 4,
    DROPDOWN_INSET_BOTTOM = 4,
    DROPDOWN_SCROLL_GAP = 2,
    --- Pixel slack before dropdown scroll frames treat content as overflowing (font/anchor rounding).
    DROPDOWN_SCROLL_FIT_SLACK = 8,

    titleCardControlRightInset = 0,
    headerToolbarControlGap = 8,
    dropdownMenuRowHeight = 26,

    --- Main addon window geometry (UIParent layout units): resize clamps + sensible defaults per `API_GetScreenInfo().category`.
    --- Wide tabs use scrollChild minimum widths (`ComputeScrollChildWidth`, StatisticsUI row wrap) rather than inflated window mins.
    MAIN_WINDOW = {
        --- Upper bound when clamping saved or live window dimensions (historically 95% viewport).
        CLAMP_SCREEN_WIDTH_PCT = 0.95,
        CLAMP_SCREEN_HEIGHT_PCT = 0.95,
        --- Envelope caps inside optimal-size calculation (`API_CalculateOptimalWindowSize`).
        OPTIMAL_MAX_SCREEN_WIDTH_PCT = 0.90,
        OPTIMAL_MAX_SCREEN_HEIGHT_PCT = 0.90,
        DEFAULT_HEIGHT_SCREEN_PCT = 0.70,
        --- If numeric for category, replaces aspect-ratio-based default width pct in `API_CalculateOptimalWindowSize`.
        --- `small`: use most of usable width on laptops (`physWidth < 1600`).
        DEFAULT_WIDTH_SCREEN_PCT_BY_CATEGORY = {
            small = 0.88,
        },
        --- Min resize / default-floor width and height (`SetResizeBounds`). Scroll handles overflow for wider tab chrome.
        MIN_WIDTH_HEIGHT_BY_CATEGORY = {
            small = { w = 680, h = 460 },
            normal = { w = 840, h = 520 },
            ultrawide = { w = 860, h = 520 },
            large = { w = 960, h = 560 },
            xlarge = { w = 1024, h = 580 },
        },
        --- Used when MAIN_WINDOW or category row is unavailable (preload / recovery).
        FALLBACK_MIN_CONTENT_WIDTH = 840,
        FALLBACK_MIN_CONTENT_HEIGHT = 520,

        --- `profile.mainWindowDensity == "compact"`: tighter mins + modest default-size shrink (`API_*` wrappers).
        COMPACT_MIN_DIMENSION_MULT = 0.92,
        COMPACT_ABS_MIN_WIDTH = 620,
        COMPACT_ABS_MIN_HEIGHT = 410,
        COMPACT_OPTIMAL_WIDTH_MULT = 0.95,
        COMPACT_OPTIMAL_HEIGHT_MULT = 0.93,
    },

    --- Main window scroll viewport chrome (anchors in `Modules/UI.lua` CreateMainWindow).
    --- Right inset intentionally larger: reserves `SCROLLBAR_COLUMN_WIDTH` + `SCROLL_GAP` (WN-UI-layout: content never under v-scroll).
    MAIN_SCROLL = {
        --- LayoutCoordinator: ignore sub-pixel resize noise; corner-drag uses live shell-only + commit populate.
        LIVE_RELAYOUT_MIN_SIZE_DELTA_PX = 2,
        RESIZE_COMMIT_DEBOUNCE_SEC = 0.15,
        COLLECTIONS_LIVE_RELAYOUT_DEBOUNCE_SEC = 0.12,
        ITEMS_LIVE_RELAYOUT_DEBOUNCE_SEC = 0.12,
        VIEWPORT_BORDER_INSET = 0,
        VIEWPORT_BORDER_ALPHA = 0.52,
        SCROLL_GAP = 2,
        SCROLL_INSET_LEFT = 4,
        CONTENT_PAD_X = 12,
        CONTENT_PAD_TOP = 0,
        --- Strip from content bottom to horizontal scroll lane (row height added in UI.lua).
        H_BAR_BOTTOM_OFFSET = 2,
        --- DrawStatistics wide layout wants three ~220px cards abreast (+ margins/spacing aligned with StatisticsUI.lua).
        STATISTICS_MIN_SCROLL_CHILD_WIDTH_FOR_THREE_CARDS = 740,
    },

    --- Main shell chrome sizing (tabs / header row). Layout anchors stay in `Modules/UI.lua`.
    MAIN_SHELL = {
        HEADER_BAR_HEIGHT = 40, -- also Characters tab stacked Total Gold / Token text column (`CharactersTotalGoldTokenStackTextHeight`)
        NAV_BAR_HEIGHT = 36, -- also Plans Tracker top chrome (`HEADER_HEIGHT` in `PlansTrackerWindow.lua`)
        --- Inset from root shell edge to body chrome (`CreateMainWindow`). Horizontal 0 = no side gutters on `BackdropTemplate`-less fill.
        FRAME_CONTENT_INSET = 0,
        FRAME_CONTENT_INSET_BOTTOM = 4,
        --- Corner resize grip (main window bottom-right; sits above footer chrome).
        RESIZE_GRIP_SIZE = 18,
        RESIZE_GRIP_INSET_X = 4,
        RESIZE_GRIP_INSET_Y = 4,
        RESIZE_GRIP_FRAMELEVEL_BOOST = 80,
        --- PvE tab: debounced PopulateContent after non-drag viewport width changes (Collections-style).
        --- Vertical gap between header bottom and nav row top (`CreateMainWindow`).
        HEADER_TO_NAV_GAP = 4,
        --- Gap below shell header before tab title card (fixedHeader top inset).
        TAB_CHROME_TITLE_TOP_GAP = 10,
        --- Main header utility cluster inset from frame right (larger = buttons shift left).
        HEADER_UTILITY_CLUSTER_RIGHT_INSET = 18,
        DEFAULT_TAB_WIDTH = 108,
        TAB_HEIGHT = 34, -- also Plans Tracker category strip (`CATEGORY_BAR_HEIGHT` in `PlansTrackerWindow.lua`)
        TAB_PAD = 24,
        TAB_GAP = 5,
        --- Main window nav: vertical text rail (left); Settings pinned bottom-left of rail (`top`: right of tab strip).
        NAV_LAYOUT_MODE = "rail",

        --- Left text rail: ~16% of body width, clamped (readable labels; content keeps majority).
        GOLDEN_RATIO = 1.6180339887,
        NAV_RAIL_WIDTH_RATIO = 0.17,
        NAV_RAIL_WIDTH_MIN = 148,
        NAV_RAIL_WIDTH_MAX = 192,
        NAV_RAIL_CONTENT_GAP = 10,
        NAV_RAIL_PAD = 6,
        NAV_RAIL_TOP_INSET = 8,
        NAV_RAIL_TAB_V_GAP = 4,
        NAV_RAIL_TAB_HEIGHT = 38,
        NAV_RAIL_LABEL_PAD_H = 6,
        RAIL_TAB_ICON_SIZE = 22,
        NAV_RAIL_BORDER_ALPHA = 0.28,
        NAV_RAIL_DIVIDER_ALPHA = 1,
        NAV_RAIL_TAB_SEP_HEIGHT = 1,
        NAV_RAIL_TAB_SEP_ALPHA = 1,
        --- Root `WarbandNexusFrame` outer border (accent quartet; 1px — matches ApplyVisuals card borders).
        MAIN_SHELL_FRAME_BORDER_ALPHA = 1,
        MAIN_SHELL_FRAME_BORDER_WIDTH = 1,
        --- Gap between last scrolled tab and footer rule; footer rule to Settings row.
        NAV_RAIL_SCROLL_BOTTOM_GAP = 6,
        NAV_RAIL_SETTINGS_SEP_GAP = 4,
        NAV_RAIL_FOOTER_BTN_GAP = 4,
        NAV_RAIL_SETTINGS_BOTTOM_PAD = 6,
        --- In-content settings category column (right of main rail).
        SETTINGS_NAV_WIDTH = 160,
        SETTINGS_NAV_GAP = 10,
        SETTINGS_NAV_PAD = 4,
        NAV_RAIL_ACTIVE_BG_ALPHA = 0.38,
        NAV_RAIL_ACTIVE_GLOW_ALPHA = 0.42,
        NAV_RAIL_ACTIVE_GLOW_INNER_ALPHA = 0.28,
        NAV_RAIL_ACTIVE_GLOW_EXPAND = 2,
        --- Fallback when width helper unavailable.
        NAV_RAIL_WIDTH = 160,
        CONTENT_PAD_X = 12,
        CONTENT_PAD_TOP = 0,
        CONTENT_GAP_ABOVE_FOOTER = 0,
        FOOTER_BOTTOM_OFFSET = 4,
        CONTENT_SECTION_GAP = 12,
        SURFACE_HAIRLINE_ALPHA = 0.40,
        CARD_TOP_HIGHLIGHT_ALPHA = 0.30,
        CARD_BOTTOM_SHADE_ALPHA = 0.22,

        --- Nav tab glyphs: Blizzard atlases first (`UI_ApplyMainNavTabGlyph`); packaged `Media/*.tga` only if SetAtlas fails.
        TAB_ICON_SIZE = 18,
        TAB_ICON_LEFT_INSET = 8,
        TAB_ICON_GAP = 6,
        TAB_ICON_RIGHT_MARGIN = 8,
        --- Horizontal strip reserved for optional "(N)" tab counts (currency/rep).
        TAB_COUNT_RESERVE = 28,
        --- Reserved for layouts that want fixed pill widths; default `top` nav uses dynamic width (`Modules/UI.lua`).
        TOP_TAB_UNIFORM_WIDTH = 112,
        --- `WindowFactory` external dialogs (`CreateExternalWindow`): inner side padding vs main shell.
        EXTERNAL_DIALOG_SIDE_INSET = 8,
        --- Header band height for external dialogs (distinct from compact main `HEADER_BAR_HEIGHT`).
        EXTERNAL_DIALOG_HEADER_HEIGHT = 45,
        --- `InformationDialog` header height (supports 32px logo row vs main chrome).
        INFO_DIALOG_HEADER_HEIGHT = 50,
        --- `UI_ShowTryCountPopup`: compact caption band below window chrome (Plans/Collections).
        TRY_COUNT_POPUP_HEADER_HEIGHT = 32,
        --- `RecipeCompanionWindow`: draggable title band (narrower than `HEADER_BAR_HEIGHT`).
        RECIPE_COMPANION_HEADER_HEIGHT = 32,
        --- Root shell: flat fill only (no tooltip 9-slice edge).
        MAIN_FRAME_BACKDROP = {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        },
        NAV_RAIL_ICON_INSET = 8,

        --- Main scroll viewport inner rim (`viewportBorder`): atlas/tile UNDER the 1px border quartet.
        --- When `sliceData` exists on the chosen atlas, `TextureBase:SetTextureSliceMargins` is applied (nine-slice); effect is subtle at low alpha.
        VIEWPORT_UNDERLAY_EDGE_INSET = 1,
        VIEWPORT_UNDERLAY_VERTEX_ALPHA = 0.52,
        VIEWPORT_UNDERLAY_FALLBACK_TEXTURE = "Interface\\Tooltips\\UI-Tooltip-Background",
        --- First atlas with `GetAtlasInfo` (+ optional `sliceData`) wins; reorder to adjust look (no per-row cost).
        VIEWPORT_ATLAS_CANDIDATES = {
            "collections-background-pearl",
            "collections-background-parchment",
            "auctionhouse-background-index",
        },
        --- Collapsible / Factory section headers + `CreateSection` card shells: shared atlas probe as viewport, lower alpha.
        SECTION_HEADER_UNDERLAY_EDGE_INSET = 1,
        SECTION_HEADER_UNDERLAY_VERTEX_ALPHA = 0.36,
        --- Omit or `{}` to reuse `VIEWPORT_ATLAS_CANDIDATES`.
    },
}

-- Export to namespace (both names for compatibility)
ns.UI_SPACING = UI_SPACING
ns.UI_LAYOUT = UI_SPACING  -- Alias for backward compatibility

-- Keep old reference
local UI_LAYOUT = UI_SPACING

--- Read-only inset hints mirroring main window scroll chrome (`Modules/UI.lua` CreateMainWindow).
---@return table hints
function ns.UI_GetMainScrollLayoutHints()
    local L = ns.UI_LAYOUT or {}
    local ms = L.MAIN_SCROLL or {}
    return {
        scrollInsetLeft = ms.SCROLL_INSET_LEFT or 4,
        scrollGap = ms.SCROLL_GAP or 2,
        viewportBorderInset = ms.VIEWPORT_BORDER_INSET or 1,
        scrollbarColumnWidth = L.SCROLLBAR_COLUMN_WIDTH or 26,
        horizontalLaneBottomOffset = ms.H_BAR_BOTTOM_OFFSET or 2,
        statisticsMinScrollChildWidth = ms.STATISTICS_MIN_SCROLL_CHILD_WIDTH_FOR_THREE_CARDS or 740,
    }
end

--- Vertical scrollbar column lane width (buttons + thumb). Matches `SCROLLBAR_COLUMN_WIDTH` / main window scroll chrome.
---@return number width
function ns.UI_GetScrollbarColumnWidth()
    local h = ns.UI_GetMainScrollLayoutHints and ns.UI_GetMainScrollLayoutHints() or {}
    return (type(h.scrollbarColumnWidth) == "number" and h.scrollbarColumnWidth > 0) and h.scrollbarColumnWidth or 26
end

--- Horizontal space reserved beside content for vertical scrollbar lane: `scrollbarColumnWidth + MAIN_SCROLL.SCROLL_GAP`.
--- Matches `SCROLL_INSET_RIGHT` in `Modules/UI.lua` CreateMainWindow.
---@return number reserve
function ns.UI_GetVerticalScrollbarLaneReserve()
    local h = ns.UI_GetMainScrollLayoutHints and ns.UI_GetMainScrollLayoutHints() or {}
    local col = (type(h.scrollbarColumnWidth) == "number" and h.scrollbarColumnWidth > 0) and h.scrollbarColumnWidth or 26
    local gap = (type(h.scrollGap) == "number" and h.scrollGap >= 0) and h.scrollGap or 2
    return col + gap
end

-- PACKAGED UI ICONS (Media/*.tga — vertex-tinted stroke art)

local WN_ICON_PATHS = nil

--- Packaged WN action icons: white when idle, yellow when active; disabled = monochrome alpha (never grey RGB).
ns.WN_ICON_VERTEX_WHITE = { 1, 1, 1, 1 }
ns.WN_ICON_VERTEX_YELLOW = { 1, 0.88, 0.08, 1 }
ns.WN_ICON_VERTEX_RED = { 1, 0.28, 0.22, 1 }
ns.WN_ICON_VERTEX_IDLE_LIGHT = { 0.06, 0.06, 0.08, 1 }

function ns.UI_GetMonochromeIconVertex(alpha)
    alpha = alpha or 1
    if IsLightModeEnabled() then
        return { 0.06, 0.06, 0.08, alpha }
    end
    return { 1, 1, 1, alpha }
end

--- Collection list row status: gold `common-icon-checkmark` when collected (canonical WN check).
function ns.UI_ApplyCollectionRowStatusIcon(statusIcon, isCollected)
    if not statusIcon then return end
    statusIcon:SetDesaturated(false)
    statusIcon:Show()
    if isCollected then
        local ok = pcall(statusIcon.SetAtlas, statusIcon, "common-icon-checkmark", false)
        if not ok then
            statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        end
        local g = COLORS and COLORS.gold
        if g then
            statusIcon:SetVertexColor(g[1], g[2], g[3], g[4] or 1)
        else
            statusIcon:SetVertexColor(1, 0.82, 0, 1)
        end
    else
        local ok = pcall(statusIcon.SetAtlas, statusIcon, "Objective-Nub", false)
        if not ok then
            statusIcon:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        end
        local vc = ns.UI_GetMonochromeIconVertex(0.35)
        statusIcon:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 0.35)
    end
end

function ns.UI_WnIconVertexForState(active, disabled)
    if disabled then
        return ns.UI_GetMonochromeIconVertex(0.35)
    end
    if active then
        return ns.WN_ICON_VERTEX_YELLOW
    end
    if IsLightModeEnabled() then
        return ns.WN_ICON_VERTEX_IDLE_LIGHT
    end
    return ns.WN_ICON_VERTEX_WHITE
end

--- Vertex tint: todo/alert/track/pin — active=yellow, idle=white/black; delete/block=red; disabled=monochrome alpha.
function ns.UI_WnIconVertexForKey(iconKey, active, disabled)
    if disabled then
        return ns.UI_GetMonochromeIconVertex(0.35)
    end
    if iconKey == "delete" or iconKey == "block" then
        return ns.WN_ICON_VERTEX_RED
    end
    if iconKey == "complete" then
        return { 0.35, 0.95, 0.45, 1 }
    end
    if active then
        return ns.WN_ICON_VERTEX_YELLOW
    end
    if IsLightModeEnabled() then
        return ns.WN_ICON_VERTEX_IDLE_LIGHT
    end
    return ns.WN_ICON_VERTEX_WHITE
end

--- Apply WN packaged icon with canonical active/idle/disabled coloring (never desaturate idle white).
function ns.UI_ApplyWnActionIcon(tex, iconKey, active, disabled)
    if not tex or not iconKey then return false end
    disabled = disabled == true
    active = active == true and not disabled
    local vc = ns.UI_WnIconVertexForKey(iconKey, active, disabled)
    return ns.UI_SetWnIconTexture(tex, iconKey, {
        vertexColor = vc,
        desaturate = disabled,
    })
end

local function GetWnIconPaths()
    if WN_ICON_PATHS then return WN_ICON_PATHS end
    local C = ns.Constants
    WN_ICON_PATHS = {
        todo = (C and C.WN_ICON_TODO) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Todo.tga",
        reminder = (C and C.WN_ICON_REMINDER) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Reminder.tga",
        alert = (C and C.WN_ICON_REMINDER) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Reminder.tga",
        pin = (C and C.WN_ICON_PIN) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Pin.tga",
        track = (C and C.WN_ICON_PIN) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Pin.tga",
        block = (C and C.WN_ICON_BLOCK) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Block.tga",
        delete = (C and C.WN_ICON_BLOCK) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Block.tga",
        chevron_up = (C and C.WN_ICON_CHEVRON_UP) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-ChevronUp.tga",
        chevron_down = (C and C.WN_ICON_CHEVRON_DOWN) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-ChevronDown.tga",
        link = (C and C.WN_ICON_LINK) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Link.tga",
        close = (C and C.WN_ICON_CLOSE) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Close.tga",
        discord = (C and C.WN_ICON_DISCORD) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Discord.tga",
        donate = (C and C.WN_ICON_DONATE) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Donate.tga",
        credits = (C and C.WN_ICON_CREDITS) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Credits.tga",
        tracking = (C and C.WN_ICON_TRACKING) or "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Tracking.tga",
        complete = "Interface\\RaidFrame\\ReadyCheck-Ready",
    }
    return WN_ICON_PATHS
end

--- Apply a packaged WN icon texture. `iconKey`: todo | alert | reminder | track | pin | delete | block | complete | chevron_* | link
--- opts: vertexColor {r,g,b,a?}, desaturate bool, texCoord {l,r,t,b} (optional)
function ns.UI_SetWnIconTexture(tex, iconKey, opts)
    if not tex or not iconKey then return false end
    opts = type(opts) == "table" and opts or {}
    local paths = GetWnIconPaths()
    local path = paths[iconKey]
    if not path then return false end
    tex:SetTexture(path)
    local tc = opts.texCoord
    if tc and #tc >= 4 then
        tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        tex:SetTexCoord(0, 1, 0, 1)
    end
    if opts.desaturate then
        tex:SetDesaturated(true)
    else
        tex:SetDesaturated(false)
    end
    local vc = opts.vertexColor
    if vc then
        tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
    else
        tex:SetVertexColor(1, 1, 1, 1)
    end
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    return true
end

--- Anchor a header control on the right rail; vertically centers on `iconFrame` when provided.
function ns.UI_PlansAnchorHeaderAction(control, headerFrame, fromRight, width, yOffset, iconFrame)
    if not control or not headerFrame then return end
    width = width or (control.GetWidth and control:GetWidth()) or 24
    fromRight = fromRight or 6
    control:ClearAllPoints()
    control:SetPoint("RIGHT", headerFrame, "RIGHT", -fromRight, yOffset or 0)
    if iconFrame then
        control:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
    end
end

--- After header actions are placed, shrink the title to the remaining width (`fromRight` = final rightOffset).
function ns.UI_PlansSyncTitleRightInset(row, fromRight)
    if not row or not row.titleText or not row.headerFrame then return end
    fromRight = fromRight or 6
    local titleText = row.titleText
    local data = row.data
    -- Unified To-Do header: title is chained after icon/type; only shrink the right edge for actions.
    if data and data.todoUnifiedHeader then
        row._todoSummaryRightInset = fromRight
        titleText:ClearAllPoints()
        local titleGap = row._todoTitleGap or 6
        local titleAnchor = row._todoTitleAnchor or row.typeBadge or row.iconFrame
        if row._todoMetaRowCentered and row.iconFrame then
            if titleAnchor then
                titleText:SetPoint("LEFT", titleAnchor, "RIGHT", titleGap, 0)
            else
                titleText:SetPoint("LEFT", row.headerFrame, "LEFT", row._todoIconLeft or 40, 0)
            end
            titleText:SetPoint("TOP", row.iconFrame, "TOP", 0, 0)
            if not row.pointsSubText then
                titleText:SetPoint("BOTTOM", row.iconFrame, "BOTTOM", 0, 0)
            end
            titleText:SetJustifyV("MIDDLE")
        elseif row._todoTitleTopLayout then
            if titleAnchor then
                titleText:SetPoint("TOPLEFT", titleAnchor, "TOPRIGHT", titleGap, 0)
            else
                titleText:SetPoint("TOPLEFT", row.headerFrame, "TOPLEFT", row._todoIconLeft or 40, 0)
            end
        elseif titleAnchor then
            titleText:SetPoint("LEFT", titleAnchor, "RIGHT", titleGap, 0)
            if row.iconFrame then
                titleText:SetPoint("TOP", row.iconFrame, "TOP", 0, 0)
                titleText:SetPoint("BOTTOM", row.iconFrame, "BOTTOM", 0, 0)
            end
        else
            titleText:SetPoint("LEFT", row.headerFrame, "LEFT", row._todoIconLeft or 40, 0)
        end
        if row.metaRightText then
            titleText:SetPoint("RIGHT", row.metaRightText, "LEFT", -titleGap, 0)
        else
            titleText:SetPoint("RIGHT", row.headerFrame, "RIGHT", -fromRight, 0)
        end
        if row.pointsSubText then
            row.pointsSubText:ClearAllPoints()
            row.pointsSubText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
            row.pointsSubText:SetPoint("RIGHT", titleText, "RIGHT", 0, 0)
            if row.iconFrame and row._todoMetaRowCentered then
                titleText:SetPoint("TOP", row.iconFrame, "TOP", 0, 0)
                titleText:SetJustifyV("TOP")
            end
        end
        local summaryAnchor = row._todoSummaryAnchor or row.iconFrame
        local summaryRight = row._todoSummaryRightInset or fromRight
        local nLines = row.summaryTexts and #row.summaryTexts or (row.summaryText and 1 or 0)
        local layout = ns.UI_PlansTodoSummaryLayout and ns.UI_PlansTodoSummaryLayout(
            row.headerFrame and row.headerFrame:GetHeight(),
            nLines,
            row.pointsSubText ~= nil
        )
        local function anchorSummaryLine(fs, slotIndex)
            fs:ClearAllPoints()
            if summaryAnchor then
                fs:SetPoint("LEFT", summaryAnchor, "LEFT", 0, 0)
            elseif row.iconFrame then
                fs:SetPoint("LEFT", row.iconFrame, "LEFT", 0, 0)
            end
            if row.iconFrame and layout then
                local yOff = -(layout.startFromIconBottom + slotIndex * (layout.lineH + layout.lineGap))
                fs:SetPoint("TOPLEFT", row.iconFrame, "BOTTOMLEFT", 0, yOff)
            end
            fs:SetPoint("RIGHT", row.headerFrame, "RIGHT", -summaryRight, 0)
        end
        if row.summaryTexts then
            for si = 1, #row.summaryTexts do
                local st = row.summaryTexts[si]
                if st then
                    anchorSummaryLine(st, si - 1)
                end
            end
        elseif row.summaryText then
            anchorSummaryLine(row.summaryText, 0)
        end
        if row.metaRightText then
            row.metaRightText:ClearAllPoints()
            row.metaRightText:SetPoint("RIGHT", row.headerFrame, "RIGHT", -fromRight, 0)
            if row.iconFrame then
                row.metaRightText:SetPoint("CENTER", row.iconFrame, "CENTER", 0, 0)
            end
        end
        if row._todoActionControls then
            for ai = 1, #row._todoActionControls do
                local ctrl = row._todoActionControls[ai]
                local ro = row._todoActionOffsets and row._todoActionOffsets[ai]
                if ctrl and ro then
                    ns.UI_PlansAnchorHeaderAction(ctrl, row.headerFrame, ro, nil, 0, row.iconFrame)
                end
            end
        end
        if row.expandBtn and row._todoChevronBottomRight then
            local chevIn = (ns.UI_PLANS_CARD_METRICS and ns.UI_PLANS_CARD_METRICS.todoChevronInset) or 6
            row.expandBtn:ClearAllPoints()
            row.expandBtn:SetPoint("BOTTOMRIGHT", row.headerFrame, "BOTTOMRIGHT", -chevIn, chevIn)
        end
        return
    end
    local titleAnchorFrame, titleAnchorGap = 4, 4
    if data and data.score and not data.scoreBelow and row.scoreText then
        titleAnchorFrame = row.scoreText
    elseif row.typeBadge then
        titleAnchorFrame = row.typeBadge
    elseif row.iconFrame then
        titleAnchorFrame = row.iconFrame
    end
    titleText:ClearAllPoints()
    if titleAnchorFrame then
        titleText:SetPoint("LEFT", titleAnchorFrame, "RIGHT", titleAnchorGap, 0)
    else
        titleText:SetPoint("LEFT", row.headerFrame, "LEFT", 40, 0)
    end
    titleText:SetPoint("RIGHT", row.headerFrame, "RIGHT", -fromRight, 0)
    if row.SyncHeaderToTitle then
        row:SyncHeaderToTitle()
    end
end

--- Chain header controls right-to-left with uniform gap; each control vertically centered on `headerFrame`.
function ns.UI_PlansChainHeaderActions(headerFrame, controls, opts)
    if not headerFrame or not controls or #controls == 0 then return end
    opts = type(opts) == "table" and opts or {}
    local gap = opts.gap or 8
    local fromRight = opts.fromRight or 6
    local prev
    for ci = 1, #controls do
        local ctrl = controls[ci]
        if ctrl then
            ctrl:ClearAllPoints()
            if prev then
                ctrl:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
            else
                ctrl:SetPoint("RIGHT", headerFrame, "RIGHT", -fromRight, 0)
            end
            prev = ctrl
        end
    end
end

--- Gap between sibling data rows (not headers/sections). See `UI_LAYOUT.dataRowGap`.
function ns.UI_DataRowGap()
    local layout = ns.UI_LAYOUT or {}
    return layout.dataRowGap or 4
end

--- Measured inner width for list chrome (headers/sections) inside a scroll child or results container.
function ns.UI_ResolveListContentWidth(scrollChild, fallbackWidth, extraPad)
    extraPad = extraPad or 0
    local pw = scrollChild and scrollChild.GetWidth and scrollChild:GetWidth()
    if pw and pw > 1 then
        return math.max(80, math.floor(pw - extraPad))
    end
    return fallbackWidth or 260
end

--- Flush section header to wrap edges (no extra side inset — parent scroll/results already has tab margin).
function ns.UI_AnchorSectionHeaderInWrap(header, wrap, stackW)
    if not header or not wrap then return end
    local w = stackW
    if not w or w < 1 then
        w = wrap.GetWidth and wrap:GetWidth()
    end
    w = math.max(1, w or 1)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
    if header.SetWidth then
        header:SetWidth(w)
    end
end

--- Clamp virtual-list row paint width so TOPRIGHT anchors stay inside the list body.
function ns.UI_ClampRowPaintWidth(rowParent, xOffset, requestedWidth, rightPad)
    local pw = rowParent and rowParent.GetWidth and rowParent:GetWidth()
    if not pw or pw < 1 then
        return requestedWidth
    end
    return math.max(1, math.min(requestedWidth or pw, pw - (xOffset or 0) - (rightPad or 4)))
end


-- PLANS TAB (To-Do List expandable rows + Browse grid cards): single source of truth
local PLANS_GRID_SPACING = UI_SPACING.CARD_GAP or 8

--- @class PlansCardMetrics
local PLANS_ICON_SCALE = 1.25
local function PlansMetric(n)
    return math.max(1, math.floor((n or 0) * PLANS_ICON_SCALE + 0.5))
end

--- Header action buttons (delete / reminder / track) on plan cards and To-Do rows — single size source.
function ns.UI_PlansHeaderActionSize()
    local PCM = ns.UI_PLANS_CARD_METRICS or {}
    return PCM.todoTypeBadgeSize or PlansMetric(24) or 24
end

ns.UI_PLANS_CARD_METRICS = {
    gridSpacing = PLANS_GRID_SPACING,
    --- CreateExpandableRow rowData (main To-Do tab + tracker): keep in sync with PlansUI rowData
    todoIconSize = PlansMetric(41),
    todoTypeBadgeSize = PlansMetric(24),
    todoExpandableMinHeight = PlansMetric(63),
    todoExpandableHeightCap = PlansMetric(71),
    --- Fixed collapsed header: [icon][type atlas][title][tries]; summary under item icon.
    todoUnifiedHeaderHeight = 92,
    todoUnifiedSlotLines = 2,
    todoUnifiedIconSize = 40,
    todoTypeBadgeSize = 28,
    todoIconRowTop = 8,
    todoMetaGap = 8,
    todoTitleGap = 8,
    todoSummaryGap = 4,
    todoSummaryBandTopGap = 12,
    todoSummaryBandBottomPad = 10,
    todoSummaryRowH = 16,
    todoSummaryLineGap = 3,
    todoPointsRowH = 14,
    todoBottomPad = 8,
    todoMetaRightReserve = 88,
    todoChevronInset = 6,
    --- Browse mounts/pets/etc. grid: same icon/badge feel as To-Do; fixed card height for two-column grid
    browseCardHeight = PlansMetric(126),
    --- Vertical gap between To-Do List cards (Currency/Reputation row-gap parity).
    todoListCardGap = 10,
    browseCardPadH = 10,
    plansActionIconInset = 3,
    browseIconTopInset = PlansMetric(10),
    browseIconLeftInset = PlansMetric(10),
    browseIconContainerSize = PlansMetric(45),
    browseRightRailW = PlansMetric(52),
    plansChevronSize = PlansMetric(18),
}

--- Horizontal inset for To-Do tab search bar and card grids (must match).
function ns.UI_PlansContentPadH()
    local PCM = ns.UI_PLANS_CARD_METRICS
    if PCM and PCM.browseCardPadH then
        return PCM.browseCardPadH
    end
    local L = ns.UI_LAYOUT
    return (L and (L.SIDE_MARGIN or L.sideMargin)) or 10
end

--- Plans / Collections browse grid: card width, spacing, horizontal pad (clamp-safe).
function ns.UI_PlansCardGridLayout(contentInnerWidth, columns, opts)
    columns = columns or 2
    opts = opts or {}
    local PCM = ns.UI_PLANS_CARD_METRICS
    local padH = opts.padH
    if padH == nil then
        padH = ns.UI_PlansContentPadH and ns.UI_PlansContentPadH() or ((PCM and PCM.browseCardPadH) or 10)
    end
    local sp = (PCM and PCM.todoListCardGap) or (PCM and PCM.gridSpacing) or PLANS_GRID_SPACING
    local w = math.max(200, (contentInnerWidth or 400) - 2 * padH)
    local cardW = math.max(100, (w - (columns - 1) * sp) / columns)
    return cardW, sp, padH
end

--- Half-width column for Plans 2-column grids (`width` = scroll body inner width; use `UI_ResolveMainTabBodyWidth`).
function ns.UI_PlansCardGridColumnWidth(contentInnerWidth)
    local cardW = ns.UI_PlansCardGridLayout(contentInnerWidth, 2)
    return cardW
end

--- Collapsed unified To-Do / browse card height from summary line count (0–2 typical).
function ns.UI_PlansTodoCollapsedHeight(summaryLineCount)
    local m = ns.UI_PLANS_CARD_METRICS or {}
    summaryLineCount = tonumber(summaryLineCount) or 0
    if summaryLineCount < 0 then summaryLineCount = 0 end
    local top = m.todoIconRowTop or 8
    local icon = m.todoUnifiedIconSize or 40
    local bandGap = m.todoSummaryBandTopGap or 12
    local lineH = m.todoSummaryRowH or 16
    local lineGap = m.todoSummaryLineGap or 3
    local pad = m.todoSummaryBandBottomPad or m.todoBottomPad or 10
    if summaryLineCount == 0 then
        return top + icon + pad
    end
    local summaryH = summaryLineCount * lineH + (summaryLineCount - 1) * lineGap
    return top + icon + bandGap + summaryH + pad
end

--- Safe achievement/collectible points label (locale format + secret guard).
function ns.UI_FormatPlanPoints(points)
    if points == nil then return nil end
    if issecretvalue and issecretvalue(points) then return nil end
    local pts = tonumber(points)
    if not pts or pts <= 0 then return nil end
    local ptsFmt = (ns.L and ns.L["POINTS_FORMAT"]) or "%d Points"
    if type(ptsFmt) ~= "string" or ptsFmt == "" or ptsFmt == "POINTS_FORMAT" then
        ptsFmt = "%d Points"
    end
    local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffd700"
    local ok, out = pcall(format, goldHex .. ptsFmt .. "|r", pts)
    if ok and out and out ~= "" then return out end
    return goldHex .. tostring(pts) .. " " .. ((ns.L and ns.L["POINTS_LABEL"]) or "Points") .. "|r"
end

--- Resolve live achievement points when plan row has none cached.
function ns.UI_ResolveAchievementPlanPoints(plan, cachedEntry)
    local pts = plan and tonumber(plan.points) or 0
    if pts > 0 then return pts end
    if cachedEntry then
        pts = tonumber(cachedEntry.points) or 0
        if pts > 0 then return pts end
    end
    if plan and plan.achievementID and GetAchievementInfo then
        local ok, _, _, ap = pcall(GetAchievementInfo, plan.achievementID)
        if ok and ap ~= nil and not (issecretvalue and issecretvalue(ap)) then
            pts = tonumber(ap) or 0
        end
    end
    return pts > 0 and pts or 0
end

--- Vertical layout for Drop/Location/Requirements lines in the band below the portrait icon.
function ns.UI_PlansTodoSummaryLayout(rowHeight, lineCount, hasPointsRow)
    local m = ns.UI_PLANS_CARD_METRICS or {}
    lineCount = tonumber(lineCount) or 0
    if lineCount < 1 then return nil end
    if not rowHeight then
        rowHeight = ns.UI_PlansTodoFixedCollapsedHeight(hasPointsRow)
    end
    local iconTop = m.todoIconRowTop or 8
    local iconSz = m.todoUnifiedIconSize or 40
    local lineH = m.todoSummaryRowH or 16
    local lineGap = m.todoSummaryLineGap or 3
    local bottomPad = m.todoSummaryBandBottomPad or m.todoBottomPad or 10
    local bandMinGap = m.todoSummaryBandTopGap or 12
    local iconBottom = iconTop + iconSz
    local blockH = lineCount * lineH + (lineCount - 1) * lineGap
    local bandTop = iconBottom + bandMinGap
    local bandBottom = rowHeight - bottomPad
    local bandH = math.max(blockH, bandBottom - bandTop)
    return {
        startFromIconBottom = bandMinGap + (bandH - blockH) * 0.5,
        lineH = lineH,
        lineGap = lineGap,
    }
end

--- All unified To-Do / browse cards share one collapsed height (title + optional points row + summary slots).
function ns.UI_PlansTodoFixedCollapsedHeight(hasPointsRow)
    local m = ns.UI_PLANS_CARD_METRICS or {}
    local slots = m.todoUnifiedSlotLines or 2
    local base = ns.UI_PlansTodoCollapsedHeight(slots)
    if hasPointsRow then
        local gap = m.todoSummaryGap or 4
        local ptsH = m.todoPointsRowH or 14
        return base + ptsH + gap
    end
    return base
end

--- Collapsed expandable header height (To-Do List + tracker rows).
--- Unified layout uses a fixed height so mount/achievement cards align in the grid.
function ns.UI_PlansTodoExpandableHeaderHeight(panelWidth, summaryLineCount)
    if summaryLineCount ~= nil then
        return ns.UI_PlansTodoCollapsedHeight(summaryLineCount)
    end
    local m = ns.UI_PLANS_CARD_METRICS
    if m and m.todoUnifiedHeaderHeight then
        return m.todoUnifiedHeaderHeight
    end
    local minH = m and m.todoExpandableMinHeight or 60
    local cap = m and m.todoExpandableHeightCap or 68
    local w = panelWidth or 400
    return math.max(minH, math.min(cap, math.floor(w * 0.10)))
end

-- BUTTON SIZE CONSTANTS

-- Standardized button sizes for "+" buttons and "Added" indicators
local BUTTON_SIZES = {
    -- Row buttons (achievement rows, list rows) - Original size
    ROW = {width = 70, height = 28},
    -- Card buttons (browse cards, grid items) - Square format
    CARD = {width = 24, height = 24},
}

-- Standardized card action button layout constants
local CARD_BUTTON_LAYOUT = {
    -- Top-right action buttons (delete, complete)
    ACTION_SIZE = 20,           -- Width/height of action buttons (delete X, green tick)
    ACTION_MARGIN = 8,          -- Margin from card edge
    ACTION_GAP = 4,             -- Gap between adjacent action buttons
    -- Bottom-right add/added button
    ADD_WIDTH = 60,
    ADD_HEIGHT = 32,
    ADD_MARGIN_X = 10,          -- Right margin from card edge
    ADD_MARGIN_Y = 8,           -- Bottom margin from card edge
    -- Source text right padding (must leave room for add button)
    SOURCE_RIGHT_PAD = 80,      -- Right margin for source text (add button width + margins)
}

-- Export to namespace
ns.UI_BUTTON_SIZES = BUTTON_SIZES
ns.UI_CARD_BUTTON_LAYOUT = CARD_BUTTON_LAYOUT

-- My Plans cards: distance from card's right edge to Wowhead button's right edge.
-- Matches TOPRIGHT action row: delete + alert (+ complete for custom) from PlansUI.
function ns.GetPlanCardWowheadRightInset(planType)
    local CBL = ns.UI_CARD_BUTTON_LAYOUT or { ACTION_SIZE = 20, ACTION_MARGIN = 8, ACTION_GAP = 4 }
    local sz, m, g = CBL.ACTION_SIZE, CBL.ACTION_MARGIN, CBL.ACTION_GAP
    if planType == "custom" then
        return m + (sz + g) * 2 + sz + g
    end
    return m + (sz + g) + sz + g
end

ns.PLAN_CARD_WOWHEAD_SIZE = 18
ns.PLAN_CARD_NAME_TO_WOWHEAD_GAP = 6

--- Match an ApplyVisuals bg snapshot to a live COLORS surface key (light-mode refresh).
local function InferSurfaceTierFromColor(bgColor)
    if not bgColor then return "bg" end
    local tiers = { "bgCard", "bgLight", "surfaceViewport", "surfaceHeaderChrome",
        "surfaceRowEven", "surfaceRowOdd", "bg" }
    for ti = 1, #tiers do
        local key = tiers[ti]
        local ref = COLORS[key]
        if ref then
            if math.abs(ref[1] - bgColor[1]) < 0.025
                and math.abs(ref[2] - bgColor[2]) < 0.025
                and math.abs(ref[3] - bgColor[3]) < 0.025 then
                return key
            end
        end
    end
    return "bg"
end

--- Registry bg type for flat surfaces (avoids luminance heuristic painting light gray as accentDark).
local function ResolveBorderlessBgRegistryType(bgColor, opts)
    opts = type(opts) == "table" and opts or {}
    if opts.surfaceTier then
        return "surfaceTier", opts.surfaceTier
    end
    if opts.bgType then
        return opts.bgType, nil
    end
    if not bgColor then
        return "bg", nil
    end
    if IsLightModeEnabled() then
        return "surfaceTier", InferSurfaceTierFromColor(bgColor)
    end
    local ad = COLORS and COLORS.accentDark
    if ad then
        if math.abs(bgColor[1] - ad[1]) < 0.05
            and math.abs(bgColor[2] - ad[2]) < 0.05
            and math.abs(bgColor[3] - ad[3]) < 0.05 then
            return "accentDark", nil
        end
    end
    return "bg", nil
end

local function ResolveRegistryBackdrop(frame, accentDarkColor, bgColor)
    local bgType = frame._bgType
    local bgAlpha = frame._bgAlpha or 1
    if bgType == "searchChrome" then
        return 0, 0, 0, 0
    elseif bgType == "controlChrome" then
        local c = GetControlChromeBackdrop()
        return c[1], c[2], c[3], c[4] or bgAlpha
    elseif bgType == "controlChromeHover" then
        local c = GetControlChromeHoverBackdrop()
        return c[1], c[2], c[3], c[4] or bgAlpha
    elseif bgType == "externalShell" and ns.UI_GetExternalShellBackdrop then
        local c = ns.UI_GetExternalShellBackdrop()
        return c[1], c[2], c[3], c[4] or bgAlpha
    elseif bgType == "surfaceTier" and frame._surfaceTier then
        local c = COLORS[frame._surfaceTier] or bgColor
        return c[1], c[2], c[3], c[4] or bgAlpha
    elseif bgType == "accentDark" then
        return accentDarkColor[1], accentDarkColor[2], accentDarkColor[3], bgAlpha
    end
    return bgColor[1], bgColor[2], bgColor[3], bgAlpha
end

-- Refresh COLORS table from database (in-place, zero allocation)
local function RefreshColors()
    -- Update theme-derived colors in-place
    UpdateColorsFromTheme()
    SyncSemanticColorAliases()
    SyncPlanUIColors()
    if ns.VaultButton and ns.VaultButton.SyncEasyAccessThemeInk then
        ns.VaultButton.SyncEasyAccessThemeInk()
    end
    -- Ensure namespace reference is current
    ns.UI_COLORS = COLORS

    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local sc = mf and mf.scrollChild
    if sc and ns.UI_EnsureScrollChildViewportFill then
        ns.UI_EnsureScrollChildViewportFill(sc)
    end
    if sc and ns.UI_RefreshScrollAnnexLayout then
        ns.UI_RefreshScrollAnnexLayout(sc)
    end
    
    -- Safety check (use namespace reference)
    if not ns.BORDER_REGISTRY then
        ns.BORDER_REGISTRY = {}
        return
    end
    
    local accentColor = COLORS.accent
    local accentDarkColor = COLORS.accentDark
    local borderColor = GetBorderStrokeColor()
    local bgColor = COLORS.bg
    local updated = 0
    
    -- Update ALL registered frames (ApplyVisuals 4-texture system)
    for i = #ns.BORDER_REGISTRY, 1, -1 do
        local frame = ns.BORDER_REGISTRY[i]
        
        if not frame then
            table.remove(ns.BORDER_REGISTRY, i)
        elseif frame.BorderTop then
            -- 4-texture border (includes main shell accent frame).
            local targetColor
            local alpha = frame._borderAlpha or 0.6
            if frame._borderType == "sectionHeader" then
                local sr, sg, sb, sa = GetSectionHeaderBorderRGBA()
                targetColor = { sr, sg, sb }
                alpha = sa or alpha
            else
                targetColor = (frame._borderType == "accent") and accentColor or borderColor
            end

            frame.BorderTop:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            frame.BorderBottom:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            frame.BorderLeft:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            frame.BorderRight:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)

            if frame._wnShellFill then
                local shellBg = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
                    or bgColor
                frame._wnShellFill:SetColorTexture(shellBg[1], shellBg[2], shellBg[3], shellBg[4] or 0.98)
            end

            if frame._wnViewportAtlasUnderlay and ns.UI_RefreshViewportAtlasUnderlayTint then
                ns.UI_RefreshViewportAtlasUnderlayTint(frame)
            end

            if frame._wnSectionChromeUnderlay and ns.UI_RefreshSectionChromeUnderlayTint then
                ns.UI_RefreshSectionChromeUnderlayTint(frame)
            end

            if frame.SetBackdropColor and frame._bgType then
                local br, bg, bb, ba = ResolveRegistryBackdrop(frame, accentDarkColor, bgColor)
                frame:SetBackdropColor(br, bg, bb, ba)
            end

            if frame._thumbTexture then
                frame._thumbTexture:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.9)
            end

            if frame._iconTexture then
                frame._iconTexture:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 1)
            end

            updated = updated + 1
        elseif frame._wnMainShellBackdrop and frame.SetBackdropBorderColor and frame.SetBackdropColor then
            -- Native BackdropTemplate shell (WarbandNexus root): tinted border + bg, no BorderTop quartet.
            local targetColor = (frame._borderType == "accent") and accentColor or borderColor
            local alpha = frame._borderAlpha or 0.9
            frame:SetBackdropBorderColor(targetColor[1], targetColor[2], targetColor[3], alpha)

            local br, bg, bb, ba = ResolveRegistryBackdrop(frame, accentDarkColor, bgColor)
            frame:SetBackdropColor(br, bg, bb, ba)

            if frame._wnAccentLeftRail then
                if frame._wnSearchChromeBorderOnly then
                    frame._wnAccentLeftRail:Hide()
                elseif frame._wnAccentLeftRail.SetColorTexture then
                    local railA = IsLightModeEnabled() and 0.98 or 0.92
                    frame._wnAccentLeftRail:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], railA)
                end
            end

            if frame._thumbTexture then
                frame._thumbTexture:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.9)
            end
            if frame._iconTexture then
                frame._iconTexture:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 1)
            end

            updated = updated + 1
        elseif not frame.BorderTop then
            table.remove(ns.BORDER_REGISTRY, i)
        end
    end

    if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
        local itemsHdr = WarbandNexus.UI.mainFrame._itemsFixedHeaderCache
        if itemsHdr and ns.UI_ApplySearchBoxChrome then
            if itemsHdr.searchBox then
                ns.UI_ApplySearchBoxChrome(itemsHdr.searchBox.searchFrame or itemsHdr.searchBox)
            end
            if itemsHdr.statsBar then
                ns.UI_ApplySearchBoxChrome(itemsHdr.statsBar)
            end
        end
    end

    if RefreshAccentStripes then
        RefreshAccentStripes()
    end
    
    -- Notify NotificationManager about color change
    if WarbandNexus and WarbandNexus.RefreshNotificationColors then
        WarbandNexus:RefreshNotificationColors()
    end
    
    -- Typography + registered role/accent FontStrings (before main-window redraw).
    if ns.FontManager and ns.FontManager.RefreshThemeTypography then
        ns.FontManager:RefreshThemeTypography()
    elseif ns.FontManager and ns.FontManager.RefreshAccentColors then
        ns.FontManager:RefreshAccentColors()
        if ns.UI_RefreshRoleTextColors then
            ns.UI_RefreshRoleTextColors()
        end
    end
    if ns.UI_RefreshToggleChrome then
        ns.UI_RefreshToggleChrome()
    end
    if ns.UI_RefreshRegisteredHighlights then
        ns.UI_RefreshRegisteredHighlights()
    end
    if ns.UI_RefreshScrollChrome then
        ns.UI_RefreshScrollChrome()
    end
    
    -- Main window chrome: title icon atlas, nav strip metrics, tab backdrops/outline (exported from `Modules/UI.lua`).
    if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
        local f = WarbandNexus.UI.mainFrame

        if ns.UI_ApplyMainWindowTitleIcon and f.addonTitleIcon then
            ns.UI_ApplyMainWindowTitleIcon(f.addonTitleIcon)
        end
        if ns.UI_RefreshMainNavTabStrip then
            ns.UI_RefreshMainNavTabStrip(f)
        end
        if ns.UI_UpdateMainFrameTabButtonStates then
            ns.UI_UpdateMainFrameTabButtonStates(f)
        elseif f.tabButtons and ns.UI_MAIN_TAB_ORDER then
            local order = ns.UI_MAIN_TAB_ORDER
            for ti = 1, #order do
                local tabKey = order[ti]
                local btn = f.tabButtons[tabKey]
                if btn then
                    local isActive = f.currentTab == tabKey

                    if btn.activeBar then
                        btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
                    end

                    if btn.glow then
                        btn.glow:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], isActive and 0.25 or 0.15)
                    end
                end
            end
        end
        if ns.UI_RefreshMainShellChrome then
            ns.UI_RefreshMainShellChrome(f)
        end
        if ns.UI_RefreshHeaderUtilityIcons then
            ns.UI_RefreshHeaderUtilityIcons(f)
        end
        if ns.UI_ScrollMainNavEnsureTabVisible and f.currentTab then
            ns.UI_ScrollMainNavEnsureTabVisible(f, f.currentTab)
        end

        -- Refresh content to update dynamic elements (moved AFTER RefreshAccentColors)
        if f:IsShown() and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end
    end

    -- Custom tooltip chrome (singleton).
    local tip = _G.WarbandNexusTooltip
    if tip and tip.UpdateTheme then
        tip:UpdateTheme()
    elseif ns.TooltipService and ns.TooltipService.RepositionIfVisible then
        ns.TooltipService:RepositionIfVisible()
    end

    -- Embedded settings category nav (without full tab rebuild).
    if ns.SettingsUI and ns.SettingsUI.RefreshThemeChrome then
        ns.SettingsUI.RefreshThemeChrome()
    end

    -- Floating companion windows.
    if ns.PlansTrackerWindow and ns.PlansTrackerWindow.RefreshTheme then
        ns.PlansTrackerWindow.RefreshTheme()
    end
    if ns.RecipeCompanionWindow then
        local rc = _G.WarbandNexus_RecipeCompanion
        if rc and rc:IsShown() then
            if ns.RecipeCompanionWindow.RefreshTheme then
                ns.RecipeCompanionWindow.RefreshTheme()
            elseif ns.RecipeCompanionWindow.Refresh then
                ns.RecipeCompanionWindow.Refresh()
            end
        end
    end
    if ns.ProfessionInfoWindow and ns.ProfessionInfoWindow.RefreshTheme then
        ns.ProfessionInfoWindow.RefreshTheme()
    end
    if ns.CharacterTrackingDialog and ns.CharacterTrackingDialog.RefreshTheme then
        ns.CharacterTrackingDialog.RefreshTheme()
    end
    if ns.GoldManagementPopup and ns.GoldManagementPopup.RefreshTheme then
        ns.GoldManagementPopup.RefreshTheme()
    end
    if ns.ReminderSetAlertDialog and ns.ReminderSetAlertDialog.RefreshTheme then
        ns.ReminderSetAlertDialog.RefreshTheme()
    end
    if WarbandNexus and WarbandNexus.RefreshVaultEasyAccessTheme then
        WarbandNexus:RefreshVaultEasyAccessTheme()
    end
    if WarbandNexus and WarbandNexus.RefreshWhatsNewTheme and _G.WarbandNexusUpdateBackdrop
        and _G.WarbandNexusUpdateBackdrop:IsShown() then
        WarbandNexus:RefreshWhatsNewTheme()
    end
    if ns.UI_RefreshSeasonProgressBindings then
        ns.UI_RefreshSeasonProgressBindings()
    end
end

--- Live font refresh for floating / external windows (FONT_CHANGED and theme chrome).
function ns.UI_RefreshExternalFloatingWindows()
    if ns.PlansTrackerWindow and ns.PlansTrackerWindow.RefreshTheme then
        ns.PlansTrackerWindow.RefreshTheme()
    end
    if ns.RecipeCompanionWindow then
        local rc = _G.WarbandNexus_RecipeCompanion
        if rc and rc:IsShown() then
            if ns.RecipeCompanionWindow.RefreshTheme then
                ns.RecipeCompanionWindow.RefreshTheme()
            elseif ns.RecipeCompanionWindow.Refresh then
                ns.RecipeCompanionWindow.Refresh()
            end
        end
    end
    if ns.ProfessionInfoWindow and ns.ProfessionInfoWindow.RefreshTheme then
        ns.ProfessionInfoWindow.RefreshTheme()
    end
    if ns.CharacterTrackingDialog and ns.CharacterTrackingDialog.RefreshTheme then
        ns.CharacterTrackingDialog.RefreshTheme()
    end
    if ns.GoldManagementPopup and ns.GoldManagementPopup.RefreshTheme then
        ns.GoldManagementPopup.RefreshTheme()
    end
    if ns.ReminderSetAlertDialog and ns.ReminderSetAlertDialog.RefreshTheme then
        ns.ReminderSetAlertDialog.RefreshTheme()
    end
    if ns.CharacterBankMoneyLogPopup and ns.CharacterBankMoneyLogPopup.RefreshTheme then
        ns.CharacterBankMoneyLogPopup.RefreshTheme()
    end
    if ns.UI_RefreshSeasonProgressBindings then
        ns.UI_RefreshSeasonProgressBindings()
    end
    if ns.WarbandNexus and ns.WarbandNexus.RefreshVaultEasyAccessTheme then
        ns.WarbandNexus:RefreshVaultEasyAccessTheme()
    end
    if ns.WarbandNexus and ns.WarbandNexus.RefreshWhatsNewTheme and _G.WarbandNexusUpdateBackdrop
        and _G.WarbandNexusUpdateBackdrop:IsShown() then
        ns.WarbandNexus:RefreshWhatsNewTheme()
    end
end

-- Quality colors (hex) — semantic WoW tiers; light-mode variants keep hue but darken for pale surfaces.
local QUALITY_COLORS = {
    [0] = "9d9d9d", -- Poor (Gray)
    [1] = "ffffff", -- Common (White)
    [2] = "1eff00", -- Uncommon (Green)
    [3] = "0070dd", -- Rare (Blue)
    [4] = "a335ee", -- Epic (Purple)
    [5] = "ff8000", -- Legendary (Orange)
    [6] = "e6cc80", -- Artifact (Gold)
    [7] = "00ccff", -- Heirloom (Cyan)
}

local QUALITY_COLORS_LIGHT = {
    [0] = "6d6d6d",
    [1] = "333333",
    [2] = "1a8f00",
    [3] = "0058b0",
    [4] = "7a28b8",
    [5] = "cc6600",
    [6] = "9a7b3a",
    [7] = "0088aa",
}

-- Export to namespace
ns.UI_COLORS = COLORS

--- Must be above ns.UI_FormatUpgradeTrackMarkup (Lua 5.1: local visible only after this line).
local function GetQualityHex(quality)
    if IsLightModeEnabled() then
        return QUALITY_COLORS_LIGHT[quality] or QUALITY_COLORS_LIGHT[1]
    end
    return QUALITY_COLORS[quality] or "ffffff"
end
ns.UI_GetQualityHex = GetQualityHex

--- PvE upgrade track tier -> |cffRRGGBB| hex (6 digits only; never prefix alpha `ff` — |cff supplies opacity).
ns.GEAR_UPGRADE_TRACK_TIER_HEX = {
    Adventurer = "9d9d9d",
    Explorer   = "9d9d9d",
    Custodial  = "9d9d9d",
    Veteran    = "1eff00",
    Champion   = "0070dd",
    Hero       = "a335ee",
    Myth       = "ff8000",
}

local function NormalizeColorMarkupHex(hex)
    if not hex or hex == "" then return "ffffff" end
    if issecretvalue and issecretvalue(hex) then return "ffffff" end
    hex = tostring(hex):gsub("^#", ""):lower()
    if #hex == 8 and hex:sub(1, 2) == "ff" then
        hex = hex:sub(3, 8)
    elseif #hex > 6 then
        hex = hex:sub(-6)
    end
    return hex
end

---@return string|nil six-digit RRGGBB
function ns.UI_GetUpgradeTrackTierHex(englishName)
    if not englishName or englishName == "" then return nil end
    if issecretvalue and issecretvalue(englishName) then return nil end
    local trimmed = englishName:match("^%s*(.-)%s*$") or englishName
    return ns.GEAR_UPGRADE_TRACK_TIER_HEX and ns.GEAR_UPGRADE_TRACK_TIER_HEX[trimmed] or nil
end

--- Safe |cff…|r for upgrade-track labels (gear slots, crest rows).
---@return string
function ns.UI_FormatUpgradeTrackMarkup(englishName, displayText, fallbackQuality)
    if not displayText or displayText == "" then return "" end
    if issecretvalue and issecretvalue(displayText) then return displayText end
    local hex = ns.UI_GetUpgradeTrackTierHex(englishName)
    if not hex and fallbackQuality ~= nil then
        hex = GetQualityHex(fallbackQuality)
    end
    hex = NormalizeColorMarkupHex(hex or "ffffff")
    return "|cff" .. hex .. displayText .. "|r"
end

-- Factory: ns.UI.Factory, ns.UI.Layout, ns.UI.Theme (runtime refs to UI_SPACING / COLORS).

-- Factory namespace (also initialized at file top for mid-file Factory methods).
ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

-- Runtime-accessible constants (fixes scope/load-order bugs)
ns.UI.Layout = UI_SPACING  -- Direct reference (no copy, always current)
ns.UI.Theme = COLORS       -- Direct reference (no copy, always current)

-- VISUAL SYSTEM (Pixel Perfect 4-Texture Borders)

-- Registry for all frames with ApplyVisuals (for live color updates)
-- MUST be initialized before any ApplyVisuals calls
-- Store in namespace to persist across all contexts (fixes nil errors)
ns.BORDER_REGISTRY = ns.BORDER_REGISTRY or {}
local BORDER_REGISTRY = ns.BORDER_REGISTRY
ns.ACCENT_STRIPE_REGISTRY = ns.ACCENT_STRIPE_REGISTRY or {}
local ACCENT_STRIPE_REGISTRY = ns.ACCENT_STRIPE_REGISTRY

local function RegisterAccentStripe(tex)
    if not tex or not tex.SetColorTexture then return end
    if not tex._wnStripeRegistered then
        tex._wnStripeRegistered = true
        ACCENT_STRIPE_REGISTRY[#ACCENT_STRIPE_REGISTRY + 1] = tex
    end
end
ns.UI_RegisterAccentStripe = RegisterAccentStripe

local function RefreshAccentStripes()
    local ac = COLORS.accent or { 0.40, 0.20, 0.58 }
    local a = IsLightModeEnabled() and 0.98 or 0.92
    for i = #ACCENT_STRIPE_REGISTRY, 1, -1 do
        local tex = ACCENT_STRIPE_REGISTRY[i]
        if not tex or not tex.SetColorTexture then
            table.remove(ACCENT_STRIPE_REGISTRY, i)
        else
            tex:SetColorTexture(ac[1], ac[2], ac[3], a)
        end
    end
end
ns.UI_RefreshAccentStripes = RefreshAccentStripes

--- Accent-bordered control shell (search, stats strip): BackdropTemplate edge + left rail.
---@param frame Frame
---@param opts table|nil `{ edgeSize, borderAlpha, showRail, railWidth, bg }`
function ns.UI_ApplyAccentControlChrome(frame, opts)
    if not frame then return end
    opts = type(opts) == "table" and opts or {}
    local ac = COLORS.accent or { 0.40, 0.20, 0.58 }
    local ar, ag, ab, aa
    if opts.bg then
        ar, ag, ab, aa = opts.bg[1], opts.bg[2], opts.bg[3], opts.bg[4] or 1
    else
        ar, ag, ab, aa = GetSubTabActiveBackdropRGBA(ac)
    end
    local edge = opts.edgeSize or 2
    local borderA = opts.borderAlpha or 0.72

    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = edge,
        insets = { left = edge, right = edge, top = edge, bottom = edge },
    })
    frame:SetBackdropColor(ar, ag, ab, aa or 0.98)
    frame:SetBackdropBorderColor(ac[1], ac[2], ac[3], borderA)
    frame._wnMainShellBackdrop = true
    frame._borderType = "accent"
    frame._borderAlpha = borderA
    frame._bgType = "searchChrome"

    if not frame._borderRegistered then
        frame._borderRegistered = true
        BORDER_REGISTRY[#BORDER_REGISTRY + 1] = frame
    end

    if opts.showRail == false then
        if frame._wnAccentLeftRail then frame._wnAccentLeftRail:Hide() end
        return
    end

    local railW = opts.railWidth or 3
    if not frame._wnAccentLeftRail then
        frame._wnAccentLeftRail = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    end
    local rail = frame._wnAccentLeftRail
    rail:ClearAllPoints()
    rail:SetWidth(railW)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", edge, -edge)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", edge, edge)
    local railA = IsLightModeEnabled() and 0.98 or 0.92
    rail:SetColorTexture(ac[1], ac[2], ac[3], railA)
    rail:Show()
    RegisterAccentStripe(rail)
end

local MAIN_SHELL_BORDER_QUARTET_KEYS = { "BorderTop", "BorderBottom", "BorderLeft", "BorderRight" }

-- Apply background and 1px borders to any frame (4-texture sandwich method)
-- Border sits INSIDE the frame, on top of backdrop, below content
local function ApplyVisuals(frame, bgColor, borderColor)
    if not frame then return end
    
    -- Ensure registry exists (defensive, use namespace)
    if not ns.BORDER_REGISTRY then
        ns.BORDER_REGISTRY = {}
    end
    
    -- Ensure frame has backdrop capability
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    
    -- Set background (NO edgeFile to prevent conflicts)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8"
    })
    
    -- Apply background color
    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end
    
    -- Create 4-texture border system (Create Once) - SANDWICH METHOD
    -- Borders are INSIDE the frame, using BORDER layer (between backdrop and content)
    if not frame.BorderTop then
        local pixelScale = GetPixelScale(frame)  -- Pixel-perfect 1px thickness for this frame scale
        
        -- Top border (INSIDE frame, at the top edge)
        frame.BorderTop = frame:CreateTexture(nil, "BORDER")
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(pixelScale)  -- Pixel-perfect 1px
        -- Disable auto-snapping to prevent thickness fluctuation during resize/scroll
        frame.BorderTop:SetSnapToPixelGrid(false)
        frame.BorderTop:SetTexelSnappingBias(0)
        frame.BorderTop:SetDrawLayer("BORDER", 0)
        
        -- Bottom border (INSIDE frame, at the bottom edge)
        frame.BorderBottom = frame:CreateTexture(nil, "BORDER")
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(pixelScale)  -- Pixel-perfect 1px
        -- Disable auto-snapping to prevent thickness fluctuation during resize/scroll
        frame.BorderBottom:SetSnapToPixelGrid(false)
        frame.BorderBottom:SetTexelSnappingBias(0)
        frame.BorderBottom:SetDrawLayer("BORDER", 0)
        
        -- Left border (INSIDE frame, full height — overlaps corners, same color = invisible)
        frame.BorderLeft = frame:CreateTexture(nil, "BORDER")
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderLeft:SetWidth(pixelScale)
        frame.BorderLeft:SetSnapToPixelGrid(false)
        frame.BorderLeft:SetTexelSnappingBias(0)
        frame.BorderLeft:SetDrawLayer("BORDER", 0)
        
        -- Right border (INSIDE frame, full height — overlaps corners, same color = invisible)
        frame.BorderRight = frame:CreateTexture(nil, "BORDER")
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderRight:SetWidth(pixelScale)
        frame.BorderRight:SetSnapToPixelGrid(false)
        frame.BorderRight:SetTexelSnappingBias(0)
        frame.BorderRight:SetDrawLayer("BORDER", 0)
        
        -- Apply border color (only on creation)
        if borderColor then
            local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
            frame.BorderTop:SetVertexColor(r, g, b, a)
            frame.BorderBottom:SetVertexColor(r, g, b, a)
            frame.BorderLeft:SetVertexColor(r, g, b, a)
            frame.BorderRight:SetVertexColor(r, g, b, a)
        end
    elseif frame.BorderTop and borderColor then
        -- Border already exists (e.g. from CreateContainer); update to new color (e.g. accent)
        local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
        frame.BorderTop:SetVertexColor(r, g, b, a)
        frame.BorderBottom:SetVertexColor(r, g, b, a)
        frame.BorderLeft:SetVertexColor(r, g, b, a)
        frame.BorderRight:SetVertexColor(r, g, b, a)
    end
    
    -- Always register frame for live updates (even if no border color initially)
    -- Detect border type from initial color
    if borderColor then
        -- Heuristic: Accent colors are typically warmer/brighter (r or g > 0.3)
        -- Border colors are typically cooler/darker (all channels < 0.3)
        local isAccent = (borderColor[1] > 0.3 or borderColor[2] > 0.3)
        frame._borderType = isAccent and "accent" or "border"
        frame._borderAlpha = borderColor[4] or 1
    else
        -- Default to border type if no color specified
        frame._borderType = "border"
        frame._borderAlpha = 0.6
    end
    
    -- Store background type for live updates (detect from bgColor)
    if bgColor then
        frame._bgAlpha = bgColor[4] or 1
        local bgType, tier = ResolveBorderlessBgRegistryType(bgColor, nil)
        frame._bgType = bgType
        frame._surfaceTier = tier
    else
        frame._bgType = "bg"
        frame._bgAlpha = 1
        frame._surfaceTier = nil
    end
    
    -- Register frame to namespace registry (prevent duplicates)
    if not frame._borderRegistered then
        frame._borderRegistered = true
        table.insert(ns.BORDER_REGISTRY, frame)
    end
end

--- Accent border quartet on root shell (OVERLAY so children do not cover the outer edge).
local function ApplyMainWindowShellBorderQuartet(frame, borderColor)
    if not frame or not borderColor then return end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local borderW = shell.MAIN_SHELL_FRAME_BORDER_WIDTH or 2
    local pixelScale = GetPixelScale(frame)
    if borderW < pixelScale then borderW = pixelScale end
    local borderLayer = "OVERLAY"
    local borderSubLevel = 7
    if not frame.BorderTop then
        frame.BorderTop = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(borderW)
        frame.BorderTop:SetSnapToPixelGrid(false)
        frame.BorderTop:SetTexelSnappingBias(0)

        frame.BorderBottom = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(borderW)

        frame.BorderLeft = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderLeft:SetWidth(borderW)

        frame.BorderRight = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderRight:SetWidth(borderW)
    else
        frame.BorderTop:SetHeight(borderW)
        frame.BorderBottom:SetHeight(borderW)
        frame.BorderLeft:SetWidth(borderW)
        frame.BorderRight:SetWidth(borderW)
    end
    local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
    frame.BorderTop:SetVertexColor(r, g, b, a)
    frame.BorderBottom:SetVertexColor(r, g, b, a)
    frame.BorderLeft:SetVertexColor(r, g, b, a)
    frame.BorderRight:SetVertexColor(r, g, b, a)
    frame.BorderTop:Show()
    frame.BorderBottom:Show()
    frame.BorderLeft:Show()
    frame.BorderRight:Show()
    frame._borderType = "accent"
    frame._borderAlpha = a
    if not frame._borderRegistered then
        frame._borderRegistered = true
        table.insert(ns.BORDER_REGISTRY, frame)
    end
end

--- Top-most accent border on root shells (header/content must not paint over the outer edge).
local SHELL_BORDER_OVERLAY_LEVEL_BOOST = 500

local function EnsureShellBorderOverlay(frame, borderColor)
    if not frame or not borderColor then return end
    local overlay = frame._wnShellBorderOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, frame)
        overlay:SetAllPoints(frame)
        overlay:EnableMouse(false)
        frame._wnShellBorderOverlay = overlay
    end
    overlay:SetFrameLevel((frame:GetFrameLevel() or 0) + SHELL_BORDER_OVERLAY_LEVEL_BOOST)
    ApplyMainWindowShellBorderQuartet(overlay, borderColor)
    overlay:Show()
end

local function RaiseMainWindowShellBorderOverlay(frame)
    if not frame or not frame._wnShellBorderOverlay then return end
    frame._wnShellBorderOverlay:SetFrameLevel((frame:GetFrameLevel() or 0) + SHELL_BORDER_OVERLAY_LEVEL_BOOST)
end

ns.UI_EnsureShellBorderOverlay = EnsureShellBorderOverlay
ns.UI_RaiseMainWindowShellBorderOverlay = RaiseMainWindowShellBorderOverlay

--- Hide 1px border quartet on a frame (flat chrome).
local function HideFrameBorderQuartet(frame)
    if not frame then return end
    for bi = 1, #MAIN_SHELL_BORDER_QUARTET_KEYS do
        local tex = frame[MAIN_SHELL_BORDER_QUARTET_KEYS[bi]]
        if tex and tex.Hide then
            tex:Hide()
        end
    end
end

--- Flat panel: WHITE8x8 fill only, no nested border textures.
---@param frame Frame
---@param bgColor table|nil
---@param opts table|nil `{ surfaceTier, bgType }`
local function ApplyBorderlessSurface(frame, bgColor, opts)
    if not frame then return end
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end
    HideFrameBorderQuartet(frame)
    frame._wnBorderlessSurface = true
    frame._wnMainShellBackdrop = true
    if bgColor then
        local bgType, tier = ResolveBorderlessBgRegistryType(bgColor, opts)
        if tier then
            frame._bgType = "surfaceTier"
            frame._surfaceTier = tier
        else
            frame._bgType = bgType
            frame._surfaceTier = nil
        end
        frame._bgAlpha = bgColor[4] or 1
    else
        frame._bgType = "bg"
        frame._surfaceTier = nil
        frame._bgAlpha = 1
    end
    if not frame._borderRegistered then
        frame._borderRegistered = true
        table.insert(ns.BORDER_REGISTRY, frame)
    end
end

ns.UI_ResolveSurfaceTierColor = ResolveSurfaceTierColor
ns.UI_ApplyBorderlessSurface = ApplyBorderlessSurface
ns.UI_HideFrameBorderQuartet = HideFrameBorderQuartet

--- Resolve a surface tier color (borderless depth ladder).
---@return table rgba
local function ResolveSurfaceTierColor(tier)
    local C = COLORS or {}
    if tier == "viewport" then
        return C.surfaceViewport or C.bg or { 0.078, 0.078, 0.096, 0.98 }
    elseif tier == "card" or tier == "elevated" then
        return C.bgCard or C.bgLight or C.bg or { 0.09, 0.09, 0.11, 0.98 }
    elseif tier == "section" or tier == "headerChrome" then
        return C.surfaceHeaderChrome or C.bgLight or C.bg or { 0.092, 0.092, 0.112, 0.97 }
    elseif tier == "rowEven" then
        return C.surfaceRowEven or UI_SPACING and UI_SPACING.ROW_COLOR_EVEN or { 0.084, 0.084, 0.104, 0.96 }
    elseif tier == "rowOdd" then
        return C.surfaceRowOdd or UI_SPACING and UI_SPACING.ROW_COLOR_ODD or { 0.073, 0.073, 0.091, 0.96 }
    end
    return C.bg or { 0.065, 0.065, 0.082, 0.98 }
end

--- Root shell only (`WarbandNexusFrame`): full-bleed color fill — no `BackdropTemplate` / backdrop insets (avoids side gutters).
local function ApplyMainWindowShellFill(frame, bgColor, borderColor)
    if not frame then return end
    local c = bgColor or (COLORS and COLORS.bg) or { 0.042, 0.042, 0.055, 0.98 }
    local tex = frame._wnShellFill
    if not tex then
        tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._wnShellFill = tex
        tex:SetAllPoints()
    end
    tex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.98)
    tex:Show()
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local borderA = shell.MAIN_SHELL_FRAME_BORDER_ALPHA or 1
    local border = borderColor or GetAccentBorderRGBA(borderA)
    HideFrameBorderQuartet(frame)
    EnsureShellBorderOverlay(frame, border)
    frame._wnMainShellBackdrop = true
    frame._wnBorderlessSurface = true
    frame._bgType = "bg"
    frame._bgAlpha = c[4] or 0.98
end

ns.UI_ApplyMainWindowShellBorderQuartet = ApplyMainWindowShellBorderQuartet

--- Legacy name: routes to flat fill (no `BackdropTemplate`).
local function ApplyMainWindowShellBackdrop(frame, bgColor, borderColor)
    ApplyMainWindowShellFill(frame, bgColor, borderColor)
end

-- Export to namespace
ns.UI_ApplyVisuals = ApplyVisuals
ns.UI_ApplyMainWindowShellFill = ApplyMainWindowShellFill
ns.UI_ApplyMainWindowShellBackdrop = ApplyMainWindowShellBackdrop

--- Compact rail width for main shell body (below header): ratio of inner width, clamped.
---@return number railWidth
function ns.UI_ComputeGoldenRailWidth(innerBodyWidth, shell)
    shell = shell or (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local ratio = shell.NAV_RAIL_WIDTH_RATIO or 0.17
    local minW = shell.NAV_RAIL_WIDTH_MIN or 148
    local maxW = shell.NAV_RAIL_WIDTH_MAX or 192
    local usable = math.max(360, tonumber(innerBodyWidth) or 800)
    local railW = math.floor(usable * ratio + 0.5)
    if railW < minW then railW = minW end
    if railW > maxW then railW = maxW end
    return railW
end

--- Unified scroll-area metrics for tab painters (header, results, cards).
---@return table|nil metrics { contentWidth, sideMargin, topMargin, sectionGap }
function ns.UI_GetMainTabLayoutMetrics(mainFrame)
    if not mainFrame then return nil end
    local layout = ns.UI_LAYOUT or {}
    local shell = layout.MAIN_SHELL or {}
    local scroll = layout.MAIN_SCROLL or {}
    local side = shell.CONTENT_PAD_X or scroll.CONTENT_PAD_X or layout.SIDE_MARGIN or 12
    local titleTopGap = shell.TAB_CHROME_TITLE_TOP_GAP or layout.TAB_CHROME_TITLE_TOP_GAP or 0
    local top = (shell.CONTENT_PAD_TOP or scroll.CONTENT_PAD_TOP or layout.topMargin or 0) + titleTopGap
    local gap = shell.CONTENT_SECTION_GAP or layout.SECTION_SPACING or 10
    local contentW = (ns.UI_GetMainScrollContentWidth and ns.UI_GetMainScrollContentWidth(mainFrame)) or 600
    local titleH = layout.TITLE_CARD_DEFAULT_HEIGHT or 64
    local blockGap = layout.TAB_CHROME_BLOCK_GAP or 8
    local scrollTop = layout.TAB_CHROME_SCROLL_TOP or 8
    local bottomPad = layout.TAB_CHROME_CONTENT_BOTTOM_PAD or 12
    return {
        contentWidth = contentW,
        bodyWidth = math.max(200, contentW - side * 2),
        sideMargin = side,
        topMargin = top,
        sectionGap = gap,
        cardGap = layout.CARD_GAP or 10,
        titleCardHeight = titleH,
        blockGap = blockGap,
        scrollTop = scrollTop,
        contentBottomPad = bottomPad,
        goldenRatio = shell.GOLDEN_RATIO or 1.6180339887,
    }
end

--- Top inset inside Items resultsContainer before list or empty card (parity across Bags / Warband / Guild).
---@return number
function ns.UI_ItemsResultsTopGap(baseYOffset)
    local layout = ns.UI_LAYOUT or {}
    return (baseYOffset or 0) + (layout.SECTION_SPACING or 8)
end

--- Symmetric horizontal inset for tab body (MAIN_SHELL.CONTENT_PAD_X / SIDE_MARGIN).
---@return number
function ns.UI_GetTabSideMargin()
    local layout = ns.UI_LAYOUT or {}
    local shell = layout.MAIN_SHELL or {}
    local scroll = layout.MAIN_SCROLL or {}
    return shell.CONTENT_PAD_X or scroll.CONTENT_PAD_X or layout.SIDE_MARGIN or layout.sideMargin or 12
end

--- Scroll viewport width (between scroll chrome). Replaces legacy full-width guesses.
---@return number contentWidth
---@return table|nil metrics
function ns.UI_ResolveMainTabContentWidth(mainFrame, parent)
    if mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.contentWidth and m.contentWidth > 0 then
            return m.contentWidth, m
        end
    end
    if mainFrame and ns.UI_GetMainScrollContentWidth then
        local vw = ns.UI_GetMainScrollContentWidth(mainFrame)
        if vw and vw > 0 then
            return vw, nil
        end
    end
    if parent and parent.GetWidth then
        local pw = parent:GetWidth()
        if pw and pw > 0 then
            return pw, nil
        end
    end
    return 600, nil
end

--- Inner body width after symmetric side insets (`bodyWidth` in metrics). Replaces `parent:GetWidth() - 20`.
---@return number bodyWidth
---@return table|nil metrics
function ns.UI_ResolveMainTabBodyWidth(mainFrame, parent)
    if mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.bodyWidth and m.bodyWidth > 0 then
            return m.bodyWidth, m
        end
        if m and m.contentWidth and m.contentWidth > 0 then
            local side = m.sideMargin or ns.UI_GetTabSideMargin()
            return math.max(200, m.contentWidth - side * 2), m
        end
    end
    local side = ns.UI_GetTabSideMargin()
    local contentW = (ns.UI_ResolveMainTabContentWidth(mainFrame, parent))
    return math.max(200, contentW - side * 2), nil
end

--- List paint width inside `resultsContainer` (incremental redraw / Draw*List).
---@return number
function ns.UI_ResolveResultsContainerPaintWidth(mainFrame, resultsContainer)
    if resultsContainer and resultsContainer.GetWidth then
        local rw = resultsContainer:GetWidth()
        if rw and rw > 1 then
            return rw
        end
    end
    local scrollChild = mainFrame and mainFrame.scrollChild
    return ns.UI_ResolveMainTabBodyWidth(mainFrame, scrollChild)
end

--- Begin fixedHeader layout pass for a tab (unified top inset + side margins).
---@return table|nil chrome { mainFrame, headerParent, metrics, yOffset, side }
function ns.UI_BeginTabChromeLayout(mainFrame)
    if not mainFrame then return nil end
    local headerParent = mainFrame.fixedHeader
    if not headerParent then return nil end
    local metrics = ns.UI_GetMainTabLayoutMetrics(mainFrame)
    if not metrics then return nil end
    return {
        mainFrame = mainFrame,
        headerParent = headerParent,
        metrics = metrics,
        yOffset = metrics.topMargin or 0,
        side = metrics.sideMargin or 12,
    }
end

--- Anchor a title card on the fixedHeader chrome row.
function ns.UI_AnchorTabTitleCard(titleCard, chrome)
    if not titleCard or not chrome or not chrome.headerParent then return end
    local y = chrome.yOffset or 0
    local side = chrome.side or 12
    titleCard:ClearAllPoints()
    titleCard:SetPoint("TOPLEFT", chrome.headerParent, "TOPLEFT", side, -y)
    titleCard:SetPoint("TOPRIGHT", chrome.headerParent, "TOPRIGHT", -side, -y)
end

--- Advance chrome Y after a fixedHeader block (title card, sub-tab bar, search row, …).
---@return number
function ns.UI_AdvanceTabChromeYOffset(yOffset, blockHeight, gapAfter)
    local sp = UI_SPACING or {}
    gapAfter = gapAfter or sp.TAB_CHROME_BLOCK_GAP or 8
    return (yOffset or 0) + (blockHeight or 0) + gapAfter
end

--- Commit fixedHeader height after laying out chrome blocks.
---@return number
function ns.UI_CommitTabFixedHeader(mainFrame, yOffset)
    if mainFrame and mainFrame.fixedHeader then
        mainFrame.fixedHeader:SetHeight(math.max(1, yOffset or 1))
        local fh = mainFrame.fixedHeader
        if fh._wnHairlinebottom and fh._wnHairlinebottom.Hide then
            fh._wnHairlinebottom:Hide()
        end
    end
    return yOffset or 0
end

--- Re-anchor main-window scrollbar lanes (matches CreateMainWindow in Modules/UI.lua).
function ns.UI_SyncMainScrollBarColumns(mainFrame)
    if not mainFrame or not mainFrame.scroll then return end
    local content = mainFrame.content
    local col = mainFrame.scrollBarColumn
    if not content or not col then return end

    local layout = ns.UI_LAYOUT or {}
    local ms = layout.MAIN_SCROLL or {}
    local hints = ns.UI_GetMainScrollLayoutHints and ns.UI_GetMainScrollLayoutHints() or {}
    local colW = (col.GetWidth and col:GetWidth()) or hints.scrollbarColumnWidth or 26
    local scrollGap = hints.scrollGap or ms.SCROLL_GAP or 2
    local scrollInsetTop = ms.CONTENT_PAD_TOP or layout.SCROLL_CONTENT_TOP_PADDING or 10
    local hBarBottom = hints.horizontalLaneBottomOffset or ms.H_BAR_BOTTOM_OFFSET or 6
    local scrollInsetBottom = hBarBottom + colW + scrollGap
    local scrollInsetLeft = hints.scrollInsetLeft or ms.SCROLL_INSET_LEFT or 4
    local scrollInsetRight = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
        or (colW + scrollGap)
    local hRowH = colW

    col:ClearAllPoints()
    col:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -scrollInsetTop)
    col:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, scrollInsetBottom)
    col:SetWidth(colW)
    if mainFrame.scroll.ScrollBar and ns.UI.Factory and ns.UI.Factory.PositionScrollBarInContainer then
        ns.UI.Factory:PositionScrollBarInContainer(mainFrame.scroll.ScrollBar, col, 0)
    end

    local hCont = mainFrame.hScrollContainer
    if hCont then
        hCont:ClearAllPoints()
        hCont:SetPoint("LEFT", content, "LEFT", scrollInsetLeft, 0)
        hCont:SetPoint("RIGHT", content, "RIGHT", -scrollInsetRight, 0)
        hCont:SetPoint("BOTTOM", content, "BOTTOM", 0, hBarBottom)
        hCont:SetHeight(hRowH)
        if mainFrame.hScroll and mainFrame.hScroll.PositionInContainer then
            mainFrame.hScroll:PositionInContainer(hCont, 0)
        end
    end
end

--- First Y offset inside scrollChild for tab body content (below fixedHeader).
---@return number
function ns.UI_GetTabScrollContentStartY()
    local sp = UI_SPACING or {}
    return sp.TAB_CHROME_SCROLL_TOP or 8
end

--- Scroll child bottom padding (PopulateContent post-layout).
---@return number
function ns.UI_GetTabScrollContentBottomPad()
    local sp = UI_SPACING or {}
    return sp.TAB_CHROME_CONTENT_BOTTOM_PAD or 12
end

--- Scroll body height between fixedHeader and footer (viewport minus top/bottom chrome insets).
---@return number
function ns.UI_GetMainTabScrollBodyHeight(mainFrame)
    if not mainFrame or not mainFrame.scroll then return 0 end
    local viewportH = mainFrame.scroll:GetHeight() or 0
    if viewportH < 2 and mainFrame.fixedHeader then
        local fhBot = mainFrame.fixedHeader:GetBottom()
        local sb = mainFrame.scroll:GetBottom()
        if fhBot and sb and fhBot > sb then
            viewportH = fhBot - sb
        end
    end
    local scrollTop = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    local bottomPad = (ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12
    return math.max(0, viewportH - scrollTop - bottomPad)
end

--- Rail tab active / idle visuals (subtle outer glow on selected tab).
function ns.UI_ApplyRailTabActiveVisuals(btn, isActive, accentColor)
    if not btn or not btn._wnRailTextMode then return end
    local ac = accentColor or (COLORS and COLORS.accent) or { 0.6, 0.4, 1 }
    local glow = btn._wnRailActiveGlow
    local glowInner = btn._wnRailActiveGlowInner
    if glow then glow:Hide() end
    if glowInner then glowInner:Hide() end
    if isActive then
        if not btn._wnRailActiveStripe then
            btn._wnRailActiveStripe = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        end
        local stripe = btn._wnRailActiveStripe
        stripe:SetWidth(3)
        stripe:ClearAllPoints()
        stripe:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -2)
        stripe:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 2)
        local sa = IsLightModeEnabled() and 0.98 or 0.92
        stripe:SetColorTexture(ac[1], ac[2], ac[3], sa)
        stripe:Show()
        if ns.UI_RegisterAccentStripe then
            ns.UI_RegisterAccentStripe(stripe)
        end
    elseif btn._wnRailActiveStripe then
        btn._wnRailActiveStripe:Hide()
    end
end

--- Scroll viewport width for active main tab (after golden rail + insets).
---@return number
--- Shell / content / scroll canvas background (unified panel tone).
---@return table {r,g,b,a}
function ns.UI_GetMainPanelBackgroundColor()
    local C = COLORS or ns.UI_COLORS
    return (C and (C.surfaceViewport or C.bg)) or { 0.130, 0.130, 0.155, 0.98 }
end

--- Live viewport width for responsive tab layout (scroll frame, not frozen scrollChild).
--- Prefer over `scrollChild:GetWidth()` during corner-drag resize sessions.
function ns.UI_GetMainTabViewportWidth(mainFrame)
    return (ns.UI_GetMainScrollContentWidth and ns.UI_GetMainScrollContentWidth(mainFrame)) or 0
end

function ns.UI_GetMainScrollContentWidth(mainFrame)
    if not mainFrame then return 0 end
    if mainFrame.scroll and mainFrame.scroll.GetWidth then
        local w = mainFrame.scroll:GetWidth()
        if w and w > 0 then return w end
    end
    if mainFrame.scrollChild and mainFrame.scrollChild.GetWidth then
        local w = mainFrame.scrollChild:GetWidth()
        if w and w > 0 then return w end
    end
    if mainFrame.content and mainFrame.content.GetWidth then
        local layout = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
        local gap = layout.NAV_RAIL_CONTENT_GAP or 10
        local reserve = 32 + gap
        return math.max(200, (mainFrame.content:GetWidth() or 0) - reserve)
    end
    return 600
end

--- Shader nineslice margins on a long-lived Texture/TextureBase (`TextureBase:SetTextureSliceMargins`, 10.2.0+, warcraft.wiki.gg).
--- Do not call per pooled list row — prefer Blizzard atlas slice metadata or one chrome texture per shell.
---@return boolean ok
function ns.UI_SetTextureSliceMarginsSafe(tex, left, top, right, bottom)
    if not tex then return false end
    local fn = tex.SetTextureSliceMargins
    if type(fn) ~= "function" then return false end
    return select(1, pcall(fn, tex, left, top, right, bottom))
end

--- Undo `SetTextureSliceMargins` when reusing a pooled texture (`TextureBase:ClearTextureSlice`).
---@return boolean ok
function ns.UI_ClearTextureSliceSafe(tex)
    if not tex then return false end
    local fn = tex.ClearTextureSlice
    if type(fn) ~= "function" then return false end
    return select(1, pcall(fn, tex))
end

--- Shared atlas/tile mid-layer (viewport + section chrome); one texture per frame.
local function WnApplyAtlasChromeUnderlayCore(frame, texKey, nameKey, inset, candidates, fallbackTex)
    if not frame or not texKey or not nameKey then return end

    local tex = frame[texKey]
    if not tex then
        tex = frame:CreateTexture(nil, "BORDER")
        frame[texKey] = tex
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
        tex:SetDrawLayer("BORDER", -8)
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -inset, inset)

    local C_tex = C_Texture
    local atlasOk = false

    if type(candidates) == "table" and C_tex and type(C_tex.GetAtlasInfo) == "function" then
        local nCand = #candidates
        for ci = 1, nCand do
            local name = candidates[ci]
            if type(name) == "string" and name ~= "" then
                local okMeta, meta = pcall(C_tex.GetAtlasInfo, C_tex, name)
                if okMeta and type(meta) == "table" and (meta.file or meta.width or meta.filename) then
                    ns.UI_ClearTextureSliceSafe(tex)
                    local okAtlas = pcall(function()
                        tex:SetAtlas(name, false)
                    end)
                    if okAtlas then
                        local fnHx = tex.SetHorizTile
                        if type(fnHx) == "function" then
                            pcall(fnHx, tex, false)
                        end
                        local fnVx = tex.SetVertTile
                        if type(fnVx) == "function" then
                            pcall(fnVx, tex, false)
                        end
                        local sd = meta.sliceData
                        if type(sd) == "table" then
                            local ml, mt, mr, mb = sd.marginLeft, sd.marginTop, sd.marginRight, sd.marginBottom
                            if type(ml) == "number" and type(mt) == "number" and type(mr) == "number" and type(mb) == "number" then
                                ns.UI_SetTextureSliceMarginsSafe(tex, ml, mt, mr, mb)
                            else
                                ns.UI_ClearTextureSliceSafe(tex)
                            end
                        else
                            ns.UI_ClearTextureSliceSafe(tex)
                        end
                        frame[nameKey] = name
                        atlasOk = true
                        break
                    end
                    ns.UI_ClearTextureSliceSafe(tex)
                end
            end
        end
    end

    if not atlasOk then
        frame[nameKey] = nil
        ns.UI_ClearTextureSliceSafe(tex)
        tex:SetTexture(fallbackTex or "Interface\\Tooltips\\UI-Tooltip-Background")
        local fnH = tex.SetHorizTile
        if type(fnH) == "function" then
            pcall(fnH, tex, true)
        end
        local fnV = tex.SetVertTile
        if type(fnV) == "function" then
            pcall(fnV, tex, true)
        end
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function WnRefreshAtlasChromeUnderlayTint(frame, texKey, alphaShellKey)
    local tex = frame and texKey and frame[texKey]
    if not tex or not alphaShellKey then return end

    if IsLightModeEnabled() then
        tex:Hide()
        return
    end
    tex:Show()

    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local shell = layout.MAIN_SHELL or {}
    local baseA = tonumber(shell[alphaShellKey])
    if not baseA or baseA < 0 then
        baseA = (alphaShellKey == "SECTION_HEADER_UNDERLAY_VERTEX_ALPHA") and 0.34 or 0.44
    end

    local bgcol = COLORS and COLORS.bg or { 0.04, 0.04, 0.05, 1 }
    local accent = COLORS and COLORS.accent or { 0.25, 0.55, 0.98 }

    local accentMix = IsLightModeEnabled() and 0.012 or 0.06
    local brighten = IsLightModeEnabled() and 1.0 or 1.04
    local r = bgcol[1] * brighten + accent[1] * accentMix
    local g = bgcol[2] * brighten + accent[2] * accentMix
    local b = bgcol[3] * brighten + accent[3] * accentMix
    if r > 1 then r = 1 end
    if g > 1 then g = 1 end
    if b > 1 then b = 1 end

    tex:SetVertexColor(r, g, b, baseA > 1 and 1 or baseA)
end

--- Theme tint for `UI_ApplyViewportAtlasUnderlay` mid-layer (`ns.UI_RefreshColors`).
function ns.UI_RefreshViewportAtlasUnderlayTint(frame)
    WnRefreshAtlasChromeUnderlayTint(frame, "_wnViewportAtlasUnderlay", "VIEWPORT_UNDERLAY_VERTEX_ALPHA")
end

--- Theme tint for section / card atlas underlay (`ns.UI_RefreshColors`).
function ns.UI_RefreshSectionChromeUnderlayTint(frame)
    WnRefreshAtlasChromeUnderlayTint(frame, "_wnSectionChromeUnderlay", "SECTION_HEADER_UNDERLAY_VERTEX_ALPHA")
end

--- Main viewport mid-layer atlas/tile (`viewportBorder`): `C_Texture.GetAtlasInfo` + `sliceData` -> SetTextureSliceMargins (TextureBase wiki); fallback tooltip tile + tint.
function ns.UI_ApplyViewportAtlasUnderlay(frame)
    if not frame then return end

    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local shell = layout.MAIN_SHELL or {}
    local inset = tonumber(shell.VIEWPORT_UNDERLAY_EDGE_INSET) or 1
    if inset < 0 then inset = 0 end

    WnApplyAtlasChromeUnderlayCore(
        frame,
        "_wnViewportAtlasUnderlay",
        "_wnViewportAtlasUnderlayName",
        inset,
        shell.VIEWPORT_ATLAS_CANDIDATES,
        shell.VIEWPORT_UNDERLAY_FALLBACK_TEXTURE or "Interface\\Tooltips\\UI-Tooltip-Background"
    )
    ns.UI_RefreshViewportAtlasUnderlayTint(frame)
end

--- Collapsible headers, Factory section headers, `CreateSection` cards: same probe as viewport + lower alpha (`MAIN_SHELL`).
function ns.UI_ApplySectionChromeUnderlay(frame)
    if not frame then return end

    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local shell = layout.MAIN_SHELL or {}
    local inset = tonumber(shell.SECTION_HEADER_UNDERLAY_EDGE_INSET) or 1
    if inset < 0 then inset = 0 end

    local cand = shell.SECTION_HEADER_ATLAS_CANDIDATES
    if type(cand) ~= "table" or #cand < 1 then
        cand = shell.VIEWPORT_ATLAS_CANDIDATES
    end

    WnApplyAtlasChromeUnderlayCore(
        frame,
        "_wnSectionChromeUnderlay",
        "_wnSectionChromeUnderlayName",
        inset,
        cand,
        shell.VIEWPORT_UNDERLAY_FALLBACK_TEXTURE or "Interface\\Tooltips\\UI-Tooltip-Background"
    )
    ns.UI_RefreshSectionChromeUnderlayTint(frame)
end

--- Raised surface + accent border (Plans / To-Do card parity via `ApplyVisuals`).
local function ApplyStandardCardElevatedChrome(frame)
    if not frame or not COLORS or not ApplyVisuals then return end
    local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
    ApplyVisuals(frame, bg, GetAccentBorderRGBA(0.55))
    frame._wnBorderlessSurface = nil
    if frame._wnCardTopHighlight and frame._wnCardTopHighlight.Hide then
        frame._wnCardTopHighlight:Hide()
    end
    if frame._wnCardBottomShade and frame._wnCardBottomShade.Hide then
        frame._wnCardBottomShade:Hide()
    end
end

--- Tab title row (fixedHeader): viewport fill in light + accent border (dark: elevated card).
local function ApplyStandardTitleCardChrome(frame)
    if not frame or not COLORS or not ApplyVisuals then return end
    if IsLightModeEnabled() then
        local bg = COLORS.surfaceViewport or COLORS.bg
        ApplyVisuals(frame, bg, GetAccentBorderRGBA(0.55))
    else
        ApplyStandardCardElevatedChrome(frame)
        return
    end
    frame._wnBorderlessSurface = nil
    if frame._wnCardTopHighlight and frame._wnCardTopHighlight.Hide then
        frame._wnCardTopHighlight:Hide()
    end
    if frame._wnCardBottomShade and frame._wnCardBottomShade.Hide then
        frame._wnCardBottomShade:Hide()
    end
end
ns.UI_ApplyStandardTitleCardChrome = ApplyStandardTitleCardChrome

ns.UI_ApplyStandardCardElevatedChrome = ApplyStandardCardElevatedChrome

--- Apply detail container styling (bg + accent border) using the shared 4-texture border system.
--- Use for Collections right panel (viewer/detail), or any "detail" panel that should match.
function ns.UI_ApplyDetailContainerVisuals(frame)
    if not frame then return end
    local colors = GetColors and GetColors() or COLORS or ns.UI_COLORS
    if not colors or not colors.accent then return end
    local bg = colors.bgCard or colors.bgLight or colors.bg
    ApplyVisuals(frame, { bg[1], bg[2], bg[3], (bg[4] or 1) * 0.95 }, GetAccentBorderRGBA(0.55))
end

-- ResetPixelScale on UI_SCALE_CHANGED is handled by EventManager.OnUIScaleChanged


-- COMMON UI FRAME WRAPPERS (Reusable Components)

--[[
    Create a notice/error frame with icon, title, and description
    @param parent frame - Parent frame
    @param title string - Notice title (e.g., "Currency Transfer Limitation")
    @param description string - Notice description text
    @param iconType string - Icon type: "alert", "info", "warning" (optional, defaults to "info")
    @param width number - Frame width (optional, uses parent width - 20)
    @param height number - Frame height (optional, defaults to 60)
    @return frame - Created notice frame
]]
local function CreateNoticeFrame(parent, title, description, iconType, width, height)
    if not parent or not title or not description then return nil end
    
    local parentWidth = parent:GetWidth() or 800
    local frameWidth = width or (parentWidth - 20)
    local frameHeight = height or 60
    
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(frameWidth, frameHeight)
    
    -- Icon selection
    local iconTextures = {
        alert = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
        info = "Interface\\FriendsFrame\\InformationIcon",
        warning = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    }
    local iconTexture = iconTextures[iconType] or iconTextures.info
    
    -- Icon
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(iconTexture)
    
    -- Title
    local titleText = FontManager:CreateFontString(frame, UIFontRole("noticeTitle"), "OVERLAY")
    titleText:SetPoint("LEFT", icon, "RIGHT", 10, 5)
    titleText:SetPoint("RIGHT", -10, 5)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffcc00" .. title .. "|r")
    
    -- Description
    local descText = FontManager:CreateFontString(frame, UIFontRole("noticeBody"), "OVERLAY")
    descText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -15)
    descText:SetPoint("RIGHT", -10, 0)
    descText:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(descText, "Bright") -- White
    descText:SetText(description)
    
    return frame
end

--[[
    Create a results container for search/browse results
    @param parent frame - Parent frame
    @param yOffset number - Vertical offset from parent top
    @param sideMargin number - Side margin (optional, defaults to 10)
    @return frame - Created results container
]]
local function CreateResultsContainer(parent, yOffset, sideMargin)
    if not parent then return nil end
    
    local margin = sideMargin or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", margin, -yOffset)
    container:SetPoint("TOPRIGHT", -margin, 0)
    container:SetHeight(1)  -- Minimal initial height, will be set by content renderer
    
    return container
end

--- Fills the band from `resultsContainer` bottom to `scrollParent` bottom (same tone as scroll chrome).
--- Use when list height is intrinsic but the scroll viewport is taller (avoids a dead strip above the footer).
function ns.UI_AnnexResultsToScrollBottom(resultsContainer, scrollParent, sideMargin, bottomInset)
    if not resultsContainer or not scrollParent then return end
    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mf and mf.currentTab == "items" then return end
    sideMargin = sideMargin or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12
    bottomInset = bottomInset or 8
    local key = "_wnResultsAnnexSheet"
    local annex = scrollParent[key]
    if not annex then
        annex = CreateFrame("Frame", nil, scrollParent)
        scrollParent[key] = annex
        annex._wnKeepOnTabSwitch = true
        annex:EnableMouse(false)
        local tex = annex:CreateTexture(nil, "BACKGROUND", nil, -6)
        tex:SetAllPoints()
        annex._wnAnnexTex = tex
    end
    annex._wnAnnexAnchorFrame = resultsContainer
    annex._wnAnnexSideMargin = sideMargin
    annex._wnAnnexBottomInset = bottomInset
    if annex._wnAnnexTex and ns.UI_RefreshScrollAnnexChrome then
        ns.UI_RefreshScrollAnnexChrome(annex)
    end
    annex:SetFrameLevel(math.max(0, (resultsContainer:GetFrameLevel() or 0) - 3))
    annex:ClearAllPoints()
    annex:SetPoint("TOPLEFT", resultsContainer, "BOTTOMLEFT", 0, 0)
    annex:SetPoint("TOPRIGHT", resultsContainer, "BOTTOMRIGHT", 0, 0)
    annex:SetPoint("BOTTOMLEFT", scrollParent, "BOTTOMLEFT", sideMargin, bottomInset)
    annex:SetPoint("BOTTOMRIGHT", scrollParent, "BOTTOMRIGHT", -sideMargin, bottomInset)
    annex:Show()
end

--- Full scrollChild canvas fill (viewport tone) so short tabs do not show a dead black band above the footer.
function ns.UI_EnsureScrollChildViewportFill(scrollChild)
    if not scrollChild then return end
    local fill = scrollChild._wnViewportCanvasFill
    if not fill then
        fill = scrollChild:CreateTexture(nil, "BACKGROUND", nil, -8)
        scrollChild._wnViewportCanvasFill = fill
    end
    fill:ClearAllPoints()
    fill:SetAllPoints(scrollChild)
    local c = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
        or ResolveSurfaceTierColor("viewport")
    fill:SetColorTexture(c[1], c[2], c[3], c[4] or 0.98)
    fill:Show()
end

--- Characters / list tabs: scrollChild fills viewport between title chrome and footer.
function ns.UI_SyncMainTabScrollChrome(mainFrame, scrollChild, tabBodyHeight)
    if not mainFrame or not scrollChild or not mainFrame.scroll then return end
    local bottomPad = (ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12
    local scrollTop = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    local bodyH = scrollTop + (tabBodyHeight or 0)
    local viewportH = mainFrame.scroll:GetHeight() or 0
    if viewportH < 2 and mainFrame.fixedHeader then
        local fhBot = mainFrame.fixedHeader:GetBottom()
        local sb = mainFrame.scroll:GetBottom()
        if fhBot and sb and fhBot > sb then
            viewportH = fhBot - sb
        end
    end
    scrollChild:SetHeight(math.max(bodyH + bottomPad, viewportH))
    local Factory = ns.UI and ns.UI.Factory
    if Factory and Factory.UpdateScrollBarVisibility then
        Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    if Factory and Factory.UpdateHorizontalScrollBarVisibility then
        Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
    end
    local sc = mainFrame.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
    if mainFrame._virtualScrollUpdate then
        mainFrame._virtualScrollUpdate()
    end
end

--- Tint annex sheet to match viewport (visible on OLED).
function ns.UI_RefreshScrollAnnexChrome(annex)
    if not annex or not annex._wnAnnexTex then return end
    local c = ResolveSurfaceTierColor("viewport")
    annex._wnAnnexTex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.98)
end

--- Re-anchor annex after PopulateContent sets scrollChild height.
function ns.UI_RefreshScrollAnnexLayout(scrollParent)
    if not scrollParent then return end
    local annex = scrollParent._wnResultsAnnexSheet
    local anchor = annex and annex._wnAnnexAnchorFrame
    if not annex or not anchor or not annex:IsShown() then return end
    local sideMargin = annex._wnAnnexSideMargin or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12
    local bottomInset = annex._wnAnnexBottomInset or 8
    annex:ClearAllPoints()
    annex:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    annex:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    annex:SetPoint("BOTTOMLEFT", scrollParent, "BOTTOMLEFT", sideMargin, bottomInset)
    annex:SetPoint("BOTTOMRIGHT", scrollParent, "BOTTOMRIGHT", -sideMargin, bottomInset)
    if ns.UI_RefreshScrollAnnexChrome then
        ns.UI_RefreshScrollAnnexChrome(annex)
    end
end

--[[
    Create a stats bar with text display
    @param parent frame - Parent frame
    @param height number - Bar height (optional, defaults to 24)
    @return frame, fontString - Created stats bar and text element
]]
local function CreateStatsBar(parent, height)
    if not parent then return nil end
    
    local barHeight = height or 24
    
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(barHeight)

    local chrome = (ns.UI_ResolveSurfaceTierColor and ns.UI_ResolveSurfaceTierColor("headerChrome"))
        or COLORS.surfaceHeaderChrome or COLORS.bgLight or COLORS.bg
    if ns.UI_ApplySearchBoxChrome then
        ns.UI_ApplySearchBoxChrome(bar)
    elseif ApplyVisuals then
        ApplyVisuals(bar, chrome, { 0, 0, 0, 0 })
    elseif ns.UI_ApplyBorderlessSurface then
        ns.UI_ApplyBorderlessSurface(bar, chrome)
    end
    
    local text = FontManager:CreateBarOverlayFontString(bar, "OVERLAY")
    if not text then
        text = FontManager:CreateFontString(bar, UIFontRole("statsBarText"), "OVERLAY")
        if ns.UI_ApplyFontStyleForRole then
            ns.UI_ApplyFontStyleForRole(text, "small", { barOverlay = true })
        end
    end
    text:SetPoint("LEFT", 10, 0)
    ns.UI_SetTextColorRole(text, "Bright") -- White
    
    return bar, text
end

-- Export to namespace
ns.UI_CreateNoticeFrame = CreateNoticeFrame
ns.UI_CreateResultsContainer = CreateResultsContainer
ns.UI_CreateStatsBar = CreateStatsBar

-- UI COMPONENT FACTORY (Pixel-Perfect Components with Auto-Border)
--[[
    These factory functions create standard UI components with automatic:
    - Pixel-perfect borders (4-texture sandwich method)
    - Anti-flicker optimization
    - Consistent styling
    
    Usage:
    Instead of:
        local icon = CreateFrame("Frame", nil, parent)
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(12345)
        -- Missing: border, anti-flicker, pixel perfect
    
    Use:
        local iconFrame = ns.UI_CreateIcon(parent, 12345, 32)
        -- Automatically includes: frame, texture, border, anti-flicker, pixel perfect!
]]


-- UI HELPER FUNCTIONS

-- Get accent color as hex string
local function GetAccentHexColor()
    local c = COLORS.accent
    return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- PROFESSION CRAFTING QUALITY ATLASES (Midnight — R1 / R2 / R3 chat icons)
-- Required atlases: Professions-ChatIcon-Quality-12-Tier1 | Tier2 | Tier3
-- Recipe Companion + Gear tab; tier reflects actual enchant rank.

local PROFESSION_QUALITY_ATLAS_MIDNIGHT_12 = {
    [1] = "Professions-ChatIcon-Quality-12-Tier1",
    [2] = "Professions-ChatIcon-Quality-12-Tier2",
    [3] = "Professions-ChatIcon-Quality-12-Tier3",
}

local PROFESSION_QUALITY_ATLAS_MAX_TIER = 3

local function ProfessionQualityRankForTierColumn(tierIdx)
    local t = tonumber(tierIdx) or 1
    if t < 1 then t = 1 end
    if t > PROFESSION_QUALITY_ATLAS_MAX_TIER then t = PROFESSION_QUALITY_ATLAS_MAX_TIER end
    return t
end

--- Try SetAtlas (plain id, then composite :w:w for some clients).
--- Do not call SetTexCoord after SetAtlas — it breaks atlas UVs and shows a wrong/grey glyph.
local function TrySetProfessionQualityAtlasOnTexture(tex, atlas, w)
    if not atlas or atlas == "" then return false end
    local width = tonumber(w) or 18
    local modes = { false, true }
    local ign = _G.TextureKitConstants and TextureKitConstants.IgnoreAtlasSize
    if ign ~= nil then
        modes[#modes + 1] = ign
    end
    for mi = 1, #modes do
        local useAtlasSize = modes[mi]
        local ok = pcall(function()
            tex:SetAtlas(atlas, useAtlasSize)
            tex:SetSize(width, width)
            tex:SetVertexColor(1, 1, 1, 1)
            tex:Show()
        end)
        if ok then
            return true
        end
    end
    return false
end

local function ApplyProfessionCraftingQualityAtlasToTexture(tex, tierIdx, size)
    if not tex or not tex.SetAtlas then return false end
    local r = ProfessionQualityRankForTierColumn(tierIdx)
    local w = tonumber(size) or 18
    local base = PROFESSION_QUALITY_ATLAS_MIDNIGHT_12[r] or PROFESSION_QUALITY_ATLAS_MIDNIGHT_12[1]
    local composite = string.format("%s:%d:%d", base, w, w)
    if TrySetProfessionQualityAtlasOnTexture(tex, base, w) then return true end
    if TrySetProfessionQualityAtlasOnTexture(tex, composite, w) then return true end
    return false
end

local function GetProfessionCraftingQualityAtlasNameForTier(tierIdx)
    local r = ProfessionQualityRankForTierColumn(tierIdx)
    return PROFESSION_QUALITY_ATLAS_MIDNIGHT_12[r] or PROFESSION_QUALITY_ATLAS_MIDNIGHT_12[1]
end

-- Create a card frame (common UI element)
local function CreateCard(parent, height)
    if not parent then return nil end
    local card = CreateFrame("Frame", nil, parent)
    card:Hide()  -- HIDE during setup (prevent flickering)
    
    card:SetHeight(height or 100)
    
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(card)
    elseif ApplyVisuals then
        local ac = COLORS.accent
        local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
        ApplyVisuals(card, bg, { ac[1], ac[2], ac[3], 0.7 })
    end
    
    -- Caller will Show() when fully setup
    return card
end

-- Forward mouse wheel to the nearest ancestor ScrollFrame (vertical; Shift+wheel horizontal when in range).
-- Full-width header Buttons and tooltip hit-frames sit above scroll content and otherwise eat wheel events.
local function ForwardMouseWheelToScrollAncestor(frame, delta)
    if not frame or not delta then return end
    local ancestor = frame
    while ancestor do
        local ot = ancestor.GetObjectType and ancestor:GetObjectType()
        if ot == "ScrollFrame" and ancestor.GetVerticalScrollRange and ancestor.SetVerticalScroll then
            local addon = _G.WarbandNexus or ns.WarbandNexus
            local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
            local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
            local step = math.floor(base * speed + 0.5)
            if IsShiftKeyDown and IsShiftKeyDown() and ancestor.GetHorizontalScrollRange and ancestor.SetHorizontalScroll then
                local maxH = ancestor:GetHorizontalScrollRange() or 0
                if maxH > 0 then
                    local currentH = ancestor:GetHorizontalScroll() or 0
                    local newH = math.max(0, math.min(maxH, currentH - (delta * step)))
                    ancestor:SetHorizontalScroll(newH)
                    if ancestor.HorizontalScrollBar then
                        ancestor.HorizontalScrollBar:SetValue(newH)
                    end
                    return
                end
            end
            local current = ancestor:GetVerticalScroll() or 0
            local maxScroll = ancestor:GetVerticalScrollRange() or 0
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * step)))
            newScroll = PixelSnap(newScroll)
            ancestor:SetVerticalScroll(newScroll)
            return
        end
        ancestor = ancestor:GetParent()
    end
end


-- Create collapsible header with expand/collapse button (NO pooling - headers are few)
-- noCategoryIcon: when true, skip category icon (e.g. PvE character headers use favorite star only)
-- visualOpts (optional): { sectionPreset = "accent"|"gold"|"danger" }
--- Section header. When `visualOpts.animatedContent` is provided (frame or getter), expand/collapse
--- resizes that body frame instantly and calls optional layout hooks.
--- Optional `visualOpts.sectionOnUpdate = function(drawH)` after each height apply (wrapper reflow).
--- Optional `visualOpts.persistToggle = function(isExpanded)` runs immediately on click (after arrow).
--- Optional `visualOpts.sectionOnComplete = function(isExpanded)` after height + onToggle sequence.
--- Optional `visualOpts.applyToggleBeforeCollapseAnimate` / `deferOnToggleUntilComplete` (virtual lists).
--- Without animatedContent, the header toggles the arrow and calls onToggle only.
--- Build visual options for CreateCollapsibleHeader (shared by tabs).
--- config:
---  - bodyGetter / animatedContent / frame
---  - persistToggle / persistFn(exp)
---  - wrapFrame + headerHeight (wrapper resize on layout)
---  - onUpdate(drawH), onComplete(exp), refreshFn(exp)
---  - updateVisibleFn + scheduleVisibleUpdate
---  - hideOnCollapse, showOnExpand, hideBodyBeforeCollapseAnimate


-- HEADER ICON SYSTEM (Standardized icon+border for all tab headers)

-- Centralized icon mapping for all tabs (keys match `Modules/UI.lua` MAIN_TAB_ORDER + legacy aliases).
local TAB_HEADER_ICONS = {
    chars = "warbands-icon",
    characters = "warbands-icon",
    items = "Banker",
    storage = "Quartermaster",
    plans = "poi-workorders",
    currency = "AzeriteReady",
    --- Overridden below for reputations vs reputation key
    reputations = "MajorFactions_MapIcons_Centaur64",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    stats = "racing",
    statistics = "racing",
    collections = "dragon-rostrum",
    professions = "Vehicle-HammerGold",
    gear = "VignetteEventElite",
    settings = "mechagon-projects",
    about = "Campaign-QuestLog-Legendaryicon",
    qol = "Soulbinds_Tree_Conduit_Icon_Utility",
}

--- Blizzard `Interface\\Icons\\...` fallback when atlases reject (broken/missing art in some patches).
local TAB_NAV_TEXTURE_FALLBACK = {
    chars = "Interface\\Icons\\Achievement_Character_Human_Male",
    items = "Interface\\Icons\\INV_Misc_Bag_08",
    gear = "Interface\\Icons\\INV_Chest_Chain_06",
    currency = "Interface\\Icons\\INV_Misc_Coin_02",
    reputations = "Interface\\Icons\\Achievement_Reputation_01",
    pve = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
    professions = "Interface\\Icons\\Trade_Engineering",
    collections = "Interface\\Icons\\INV_Misc_Head_Dragon_Nexus",
    plans = "Interface\\Icons\\INV_Misc_Map_01",
    stats = "Interface\\Icons\\Achievement_General_StayClassy",
    settings = "Interface\\Icons\\Trade_Engineering",
    about = "Interface\\AddOns\\WarbandNexus\\Media\\Icon-Credits.tga",
}


local function NormalizeMainNavTabMediaKey(tabKey)
    if not tabKey then return nil end
    local k = tabKey
    if k == "statistics" then return "stats" end
    if k == "reputation" then return "reputations" end
    if k == "characters" then return "chars" end
    if k == "storage" then return "items" end
    return k
end

-- Tab title header icon (CreateHeaderIcon)
local HEADER_ICON_SIZE = 44
local HEADER_ICON_PAD = 5
local HEADER_ICON_INSET = 12

-- Export icon mapping for external use
ns.UI_GetTabIcon = function(tabName)
    local key = tabName
    -- Main window uses `reputations`; some cards use `reputation`.
    if key == "reputation" or key == "reputations" then
        local ok, fg = pcall(UnitFactionGroup, "player")
        if ok and fg == "Alliance" then
            return "AllianceAssaultsMapBanner"
        end
        if ok and fg == "Horde" then
            return "HordeAssaultsMapBanner"
        end
        return TAB_HEADER_ICONS.reputations or "MajorFactions_MapIcons_Centaur64"
    end
    if key == "statistics" then
        key = "stats"
    end
    if key == "characters" then
        key = "chars"
    end
    return TAB_HEADER_ICONS[key]
        or TAB_HEADER_ICONS[tabName]
        or "shop-icon-housing-characters-up"
end

--- Title card glyph: atlas/tab icon in a square tile (never override atlas UV with icon crop).
---@return boolean usedAtlas
function ns.UI_ApplyTitleCardGlyph(tex, tabKey, atlasName)
    if not tex then return false end
    if atlasName and atlasName ~= "" then
        if pcall(tex.SetAtlas, tex, atlasName, false) or pcall(tex.SetAtlas, tex, atlasName, true) then
            return true
        end
    end
    if tabKey and ns.UI_ApplyMainNavTabGlyph then
        ns.UI_ApplyMainNavTabGlyph(tex, tabKey)
        return false
    end
    if not pcall(tex.SetAtlas, tex, "shop-icon-housing-characters-up", false) then
        tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if ns.UI_ApplyFileIconTexCoord then
            ns.UI_ApplyFileIconTexCoord(tex)
        else
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
    end
    return false
end

--- Main nav strip / rail: Blizzard atlas (`UI_GetTabIcon`) then built-in texture paths (packaged TGAs optional).
---@return boolean usedPackaged Unused; kept for call-site compatibility (always false when Media lacks matching files).
function ns.UI_ApplyMainNavTabGlyph(tex, tabKey)
    if not tex or not tabKey then return false end

    local atlasNm = ns.UI_GetTabIcon(tabKey)
    if atlasNm and type(atlasNm) == "string" then
        if pcall(tex.SetAtlas, tex, atlasNm, false) then
            return false
        end
        if pcall(tex.SetAtlas, tex, atlasNm, true) then
            return false
        end
    end

    local canon = NormalizeMainNavTabMediaKey(tabKey)
    local iconPath = canon and TAB_NAV_TEXTURE_FALLBACK[canon]
    if type(iconPath) == "string" and iconPath ~= "" then
        tex:SetTexture(iconPath)
        if ns.UI_ApplyFileIconTexCoord then
            ns.UI_ApplyFileIconTexCoord(tex)
        else
            tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        return false
    end

    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    if ns.UI_ApplyFileIconTexCoord then
        ns.UI_ApplyFileIconTexCoord(tex)
    else
        tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    return false
end

ns.UI_GetCharKey = function(char)
    if not char then return nil end
    if not ns.Utilities then return char._key end
    if ns.Utilities.ResolveCharacterRowKey then
        local rk = ns.Utilities:ResolveCharacterRowKey(char)
        if rk then return rk end
    end
    if char._key and ns.Utilities.GetCanonicalCharacterKey
        and not (issecretvalue and issecretvalue(char._key)) then
        local ck = ns.Utilities:GetCanonicalCharacterKey(char._key)
        if ck then return ck end
    end
    local g = char.guid
    if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
        return g
    end
    local n, r = char.name, char.realm
    if ns.Utilities.GetCharacterKey and n and r
        and not (issecretvalue and (issecretvalue(n) or issecretvalue(r))) then
        return ns.Utilities:GetCharacterKey(n, r)
    end
    if char._key and not (issecretvalue and issecretvalue(char._key)) then
        return char._key
    end
    return nil
end

--- Canonical subsidiary storage key (currency/PvE/gear caches). Mirrors VaultButton_Data.GetCurrentCharKey.
---@param optionalCharKey string|nil
---@return string|nil
function ns.UI_GetSubsidiaryCharKey(optionalCharKey)
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey and WarbandNexus then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, optionalCharKey)
        if k then return k end
    end
    if optionalCharKey and optionalCharKey ~= ""
        and not (issecretvalue and issecretvalue(optionalCharKey)) then
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(optionalCharKey) or optionalCharKey
        end
        return optionalCharKey
    end
    if ns.Utilities and ns.Utilities.GetCharacterStorageKey and WarbandNexus then
        local raw = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        if raw and ns.Utilities.GetCanonicalCharacterKey then
            return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
        end
        return raw
    end
    return nil
end

---@return number centerX Icon block center offset from parent LEFT (for CENTER anchor).
function ns.UI_GetTitleCardIconCenterX(iconSize, pad, inset)
    iconSize = iconSize or HEADER_ICON_SIZE or 44
    pad = pad or HEADER_ICON_PAD or 5
    inset = inset or HEADER_ICON_INSET or 14
    return inset + pad + (iconSize * 0.5)
end

--[[
    Tab title icon: fixed square tile + centered glyph (does not stretch with card height).
    @param parent Frame
    @param atlasName string|nil
    @param options table|nil { tabKey, tileOuter, glyphSize }
    @return table { icon, border } — border is the outer host frame (layout anchor)
]]
local function CreateHeaderIcon(parent, atlasName, options)
    if type(atlasName) == "table" and options == nil then
        options = atlasName
        atlasName = options.atlasName
    end
    options = type(options) == "table" and options or {}
    local sp = UI_SPACING or {}
    local tileOuter = options.tileOuter or sp.TITLE_CARD_ICON_TILE_OUTER or 44

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(tileOuter, tileOuter)
    container:EnableMouse(false)

    local icon = container:CreateTexture(nil, "ARTWORK")
    local inset = options.glyphInset or sp.TITLE_CARD_ICON_GLYPH_PAD or 4
    icon:SetPoint("TOPLEFT", container, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -inset, inset)
    if icon.SetSnapToPixelGrid then icon:SetSnapToPixelGrid(false) end
    if icon.SetTexelSnappingBias then icon:SetTexelSnappingBias(0) end

    if ns.UI_ApplyTitleCardGlyph then
        ns.UI_ApplyTitleCardGlyph(icon, options.tabKey, atlasName)
    end
    icon:SetVertexColor(1, 1, 1, 1)

    return {
        icon = icon,
        border = container,
        tileOuter = tileOuter,
        glyphSize = tileOuter - (inset * 2),
    }
end

--- Items / Gear: open result lists on content tone (no viewport rim box or scroll fill band).
function ns.UI_ConfigureMainScrollViewportForTab(mainFrame, tab)
    if not mainFrame then return end
    local vp = mainFrame.viewportBorder
    local sc = mainFrame.scrollChild
    local borderless = (tab == "items" or tab == "gear")
    if not vp then return end

    if borderless then
        vp:SetBackdropColor(0, 0, 0, 0)
        if vp._wnViewportAtlasUnderlay and vp._wnViewportAtlasUnderlay.Hide then
            vp._wnViewportAtlasUnderlay:Hide()
        end
        if sc and sc._wnViewportCanvasFill and sc._wnViewportCanvasFill.Hide then
            sc._wnViewportCanvasFill:Hide()
        end
        if sc and sc._wnResultsAnnexSheet and sc._wnResultsAnnexSheet.Hide then
            sc._wnResultsAnnexSheet:Hide()
        end
        if sc and sc._wnScrollBottomFill and sc._wnScrollBottomFill.Hide then
            sc._wnScrollBottomFill:Hide()
        end
    else
        local vpColor = ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor()
            or (COLORS and COLORS.bg) or { 0.042, 0.042, 0.055, 0.98 }
        vp:SetBackdropColor(vpColor[1], vpColor[2], vpColor[3], vpColor[4] or 0.98)
        if ns.UI_ApplyViewportAtlasUnderlay and not vp._wnViewportAtlasUnderlay then
            ns.UI_ApplyViewportAtlasUnderlay(vp)
        elseif vp._wnViewportAtlasUnderlay and vp._wnViewportAtlasUnderlay.Show then
            vp._wnViewportAtlasUnderlay:Show()
            if ns.UI_RefreshViewportAtlasUnderlayTint then
                ns.UI_RefreshViewportAtlasUnderlayTint(vp)
            end
        end
    end
end

--- Accent rule under title icon + text block.
local function ApplyTitleCardUnderline(titleCard, leftAnchor, rightAnchor, sp)
    if not titleCard or not leftAnchor or not rightAnchor then return end
    sp = sp or UI_SPACING or {}
    local ac = COLORS and COLORS.accent or { 0.5, 0.4, 0.7 }
    local ruleA = sp.TITLE_CARD_UNDERLINE_ALPHA or 0.5
    local rule = titleCard._wnTitleUnderline
    if not rule then
        rule = titleCard:CreateTexture(nil, "ARTWORK")
        titleCard._wnTitleUnderline = rule
    end
    rule:SetColorTexture(ac[1], ac[2], ac[3], ruleA)
    rule:SetHeight(1)
    rule:ClearAllPoints()
    rule:SetPoint("BOTTOMLEFT", leftAnchor, "BOTTOMLEFT", 0, -5)
    rule:SetPoint("BOTTOMRIGHT", rightAnchor, "BOTTOMRIGHT", 0, -5)
    rule:Show()
end

-- Export header icon system
ns.UI_CreateHeaderIcon = CreateHeaderIcon

--[[
    Characters-tab standard title row: accent card, ring icon centered at x=35 from left,
    stacked title (header) + subtitle (subtitle font), text block anchored from icon.
    @param headerParent Frame — typically fixedHeader
    @param opts table:
      cardHeight (number, default 70)
      textContainerWidth (number, default 200)
      atlasName (string|nil) — explicit atlas; if nil, tabKey + GetTabIcon
      tabKey (string|nil)
      titleText (string) — colored title (|cff...|r)
      subtitleText (string|nil)
      textRightInset (number|nil) — if set, text container also anchors RIGHT on card (room for header controls)
      skipApplyVisuals (boolean) — skip ApplyVisuals on card (rare)
    @return titleCard, headerIcon, textContainer, titleFs, subtitleFs
]]
--- Vertically center title + subtitle as a block inside the title card text column.
function ns.UI_LayoutTitleCardTextStack(textContainer, titleFs, subtitleFs, textW)
    if not textContainer or not titleFs then return end
    local sp = UI_SPACING or {}
    local gap = sp.TITLE_CARD_TEXT_STACK_GAP or 3
    local stack = textContainer._wnTextStack
    if not stack then
        stack = CreateFrame("Frame", nil, textContainer)
        stack:EnableMouse(false)
        textContainer._wnTextStack = stack
    end
    stack:ClearAllPoints()
    stack:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    stack:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
    stack:SetPoint("CENTER", textContainer, "CENTER", 0, 0)
    if textW then
        stack:SetWidth(textW)
    end

    titleFs:ClearAllPoints()
    titleFs:SetPoint("TOPLEFT", stack, "TOPLEFT", 0, 0)
    titleFs:SetPoint("TOPRIGHT", stack, "TOPRIGHT", 0, 0)

    local hasSub = false
    if subtitleFs then
        local subText = subtitleFs:GetText()
        hasSub = subText and not (issecretvalue and issecretvalue(subText)) and subText ~= ""
        subtitleFs:ClearAllPoints()
        if hasSub then
            subtitleFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -gap)
            subtitleFs:SetPoint("TOPRIGHT", stack, "TOPRIGHT", 0, 0)
            subtitleFs:Show()
        else
            subtitleFs:Hide()
        end
    end

    local titleH = titleFs:GetStringHeight() or 0
    if titleH <= 0 then titleH = 14 end
    local subH = 0
    if hasSub and subtitleFs then
        subH = subtitleFs:GetStringHeight() or 0
        if subH <= 0 then subH = 12 end
    end
    stack:SetHeight(titleH + (hasSub and (gap + subH) or 0))
end

local function CreateStandardTabTitleCard(headerParent, opts)
    if not headerParent or type(opts) ~= "table" then return nil end
    local sp = UI_SPACING or {}
    local cardH = opts.cardHeight or sp.TITLE_CARD_DEFAULT_HEIGHT or 64
    local textW = opts.textContainerWidth or 200
    local tileOuter = opts.tileOuter or sp.TITLE_CARD_ICON_TILE_OUTER or 44
    local contentPadH = opts.contentPadH or sp.TITLE_CARD_CONTENT_PAD_H or sp.TITLE_CARD_ICON_SIDE_INSET or 12
    local iconSideInset = opts.iconSideInset
    if iconSideInset == nil then
        iconSideInset = contentPadH
    end
    local ringGap = opts.textGap or sp.TITLE_CARD_RING_TEXT_GAP or 8
    local textPadV = sp.TITLE_CARD_TEXT_PAD_V or 8
    local iconTopInset = math.max(0, math.floor((cardH - tileOuter) * 0.5))

    local titleCard = CreateFrame("Frame", nil, headerParent)
    titleCard:Hide()
    titleCard:SetHeight(cardH)
    if not opts.skipApplyVisuals then
        if ApplyStandardTitleCardChrome then
            ApplyStandardTitleCardChrome(titleCard)
        elseif ApplyStandardCardElevatedChrome then
            ApplyStandardCardElevatedChrome(titleCard)
        end
    end
    local atlas = opts.atlasName
    if (not atlas or atlas == "") and opts.tabKey and ns.UI_GetTabIcon then
        atlas = ns.UI_GetTabIcon(opts.tabKey)
    end
    local headerIcon = CreateHeaderIcon(titleCard, atlas, {
        tabKey = opts.tabKey,
        tileOuter = tileOuter,
        glyphInset = opts.glyphInset or sp.TITLE_CARD_ICON_GLYPH_PAD,
    })
    headerIcon.border:ClearAllPoints()
    headerIcon.border:SetPoint("TOPLEFT", titleCard, "TOPLEFT", iconSideInset, -iconTopInset)

    local textContainer = ns.UI.Factory:CreateContainer(titleCard, textW, math.max(36, cardH - textPadV * 2))
    local textStack = CreateFrame("Frame", nil, textContainer)
    textStack:EnableMouse(false)
    textContainer._wnTextStack = textStack

    local titleFs = FontManager:CreateFontString(textStack, UIFontRole("tabTitlePrimary"), "OVERLAY")
    titleFs:SetText(opts.titleText or "")
    titleFs:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(titleFs, "Bright")

    local subtitleFs = FontManager:CreateFontString(textStack, UIFontRole("tabSubtitle"), "OVERLAY")
    subtitleFs:SetText(opts.subtitleText or "")
    ns.UI_SetTextColorRole(subtitleFs, "Normal")
    subtitleFs:SetJustifyH("LEFT")
    subtitleFs:SetWordWrap(false)
    subtitleFs:SetNonSpaceWrap(false)
    if subtitleFs.SetMaxLines then subtitleFs:SetMaxLines(1) end

    local rin = opts.textRightInset
    textContainer:ClearAllPoints()
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", ringGap, 0)
    local textRightPad = (type(rin) == "number" and rin > 0) and rin or contentPadH
    textContainer:SetPoint("RIGHT", titleCard, "RIGHT", -textRightPad, 0)
    textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
    textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
    textContainer._wnTitleContentPadH = contentPadH

    ns.UI_LayoutTitleCardTextStack(textContainer, titleFs, subtitleFs, textW)
    textContainer._wnTitleFs = titleFs
    textContainer._wnSubtitleFs = subtitleFs

    if opts.showUnderline == true then
        ApplyTitleCardUnderline(titleCard, headerIcon.border, textContainer, sp)
    elseif titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end

    return titleCard, headerIcon, textContainer, titleFs, subtitleFs
end

--- Hide accent rule on a title card (e.g. cached headers rebuilt before underline removal).
function ns.UI_HideTitleCardUnderline(titleCard)
    if titleCard and titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end
end

ns.UI_CreateStandardTabTitleCard = CreateStandardTabTitleCard

--- Reapply icon + text layout after reparenting a cached title card (Collections, Storage).
function ns.UI_ReanchorStandardTabTitleLayout(headerIcon, titleCard, textContainer, cardHeight, textRightInset)
    if not headerIcon or not headerIcon.border or not titleCard then return end
    local sp = UI_SPACING or {}
    cardHeight = cardHeight or sp.TITLE_CARD_DEFAULT_HEIGHT or 64
    local tileOuter = sp.TITLE_CARD_ICON_TILE_OUTER or 44
    local contentPadH = sp.TITLE_CARD_CONTENT_PAD_H or sp.TITLE_CARD_ICON_SIDE_INSET or 12
    local iconSideInset = sp.TITLE_CARD_ICON_SIDE_INSET or contentPadH
    local ringGap = sp.TITLE_CARD_RING_TEXT_GAP or 8
    local textPadV = sp.TITLE_CARD_TEXT_PAD_V or 8
    local iconTopInset = math.max(0, math.floor((cardHeight - tileOuter) * 0.5))
    headerIcon.border:ClearAllPoints()
    headerIcon.border:SetPoint("TOPLEFT", titleCard, "TOPLEFT", iconSideInset, -iconTopInset)
    if textContainer then
        textContainer:ClearAllPoints()
        textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", ringGap, 0)
        local textRightPad = (type(textRightInset) == "number" and textRightInset > 0)
            and textRightInset
            or (textContainer._wnTitleContentPadH or contentPadH)
        textContainer:SetPoint("RIGHT", titleCard, "RIGHT", -textRightPad, 0)
        textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
        textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
        if textContainer._wnTitleFs and ns.UI_LayoutTitleCardTextStack then
            ns.UI_LayoutTitleCardTextStack(textContainer, textContainer._wnTitleFs, textContainer._wnSubtitleFs)
        end
    end
    if titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end
end

-- CURRENT CHARACTER ICON (Global, easily customizable)

--[[
    Get the atlas name for "Current Character" icon
    This is a global setting that applies to all "Current Character" displays
    Change this function to customize the icon globally
    @return string - Atlas name for the current character icon
]]
local function GetCurrentCharacterIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all "Current Character" icons
    -- Default: "charactercreate-gendericon-female-selected" (generic character icon)
    -- Alternatives: 
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    --   "Banker" (banker icon)
    return "charactercreate-gendericon-female-selected"
end

-- Export

-- CHARACTER-SPECIFIC ICON (Used in headers across multiple tabs)

--[[
    Get the atlas name for "Character-Specific" contexts
    This icon is used for headers and sections that represent character-specific data
    
    Used in:
    - Characters tab ÔåÆ "Characters" header
    - Storage tab ÔåÆ "Personal Banks" header
    - Reputations tab ÔåÆ "Character-Based Reputations" header
    
    @return string - Atlas name for character-specific icon
]]
local function GetCharacterSpecificIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all character-specific headers
    -- Current: "honorsystem-icon-prestige-9" (honor prestige badge, character-specific indicator)
    -- Alternatives:
    --   "charactercreate-gendericon-female-selected" (generic character)
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    return "honorsystem-icon-prestige-9"
end

-- Export
ns.UI_GetCharacterSpecificIcon = GetCharacterSpecificIcon

--[[
    Get currency header icon texture path
    
    Returns appropriate icon for currency category headers. Never returns nil so that
    the UI never shows a question mark — unknown headers get a generic currency icon.
    Blizzard API does not provide icons for headers, so we use manual mapping.
    
    @param headerName string - Header name (e.g., "Legacy", "Midnight", "Season 1")
    @return string - Texture path (always non-nil)
]]
local function GetCurrencyHeaderIcon(headerName)
    if not headerName or headerName == "" then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    end
    if issecretvalue and issecretvalue(headerName) then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    end
    -- Legacy (all old expansions)
    if headerName:find("Legacy") then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    -- Midnight (12.0) — night/shadow theme (path that exists in the client)
    elseif headerName:find("Midnight") then
        return "Interface\\Icons\\Spell_Shadow_Teleport"
    -- Season headers (order matters: Season 1 before generic "Season"); all paths exist in-game
    elseif headerName:find("Season 1") or headerName:find("Season1") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    elseif headerName:find("Season 2") or headerName:find("Season2") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    elseif headerName:find("Season 3") or headerName:find("Season3") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    elseif headerName:find("Season") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    -- Expansions
    elseif headerName:find("War Within") then
        return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
    elseif headerName:find("Dragonflight") then
        return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
    elseif headerName:find("Shadowlands") then
        return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
    elseif headerName:find("Battle for Azeroth") then
        return "Interface\\Icons\\INV_Sword_39"
    elseif headerName:find("Legion") then
        return "Interface\\Icons\\Spell_Shadow_Twilight"
    elseif headerName:find("Warlords of Draenor") or headerName:find("Draenor") then
        return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
    elseif headerName:find("Mists of Pandaria") or headerName:find("Pandaria") then
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    elseif headerName:find("Cataclysm") then
        return "Interface\\Icons\\Spell_Fire_Flameshock"
    elseif headerName:find("Wrath") or headerName:find("Lich King") then
        return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
    elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
        return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
    elseif headerName:find("PvP") or headerName:find("Player vs") then
        return "Interface\\Icons\\Achievement_BG_returnXflags_def_WSG"
    elseif headerName:find("Dungeon") or headerName:find("Raid") then
        return "Interface\\Icons\\achievement_boss_archaedas"
    elseif headerName:find("Miscellaneous") then
        return "Interface\\Icons\\INV_Misc_Gear_01"
    end
    -- Unknown header: generic currency-related icon (never use a question mark)
    return "Interface\\Icons\\INV_Misc_Coin_01"
end

-- Export
ns.UI_GetCurrencyHeaderIcon = GetCurrencyHeaderIcon

--[[
    Get class icon texture path (clean, frameless icons)
    @param classFile string - English class name (e.g., "WARRIOR", "MAGE")
    @return string - Texture path
]]

-- Character row column layout: Modules/UI/SharedWidgets_CharRow.lua (loaded before this file).

--- Title-card toolbar: horizontal anchor from `anchorTo` (RIGHT/LEFT); vertical centers with anchor target.
function ns.UI_AnchorTitleCardToolbarControl(btn, _titleCard, anchorTo, anchorPoint, offsetX)
    if not btn or not anchorTo then return end
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", anchorTo, anchorPoint or "RIGHT", offsetX or 0, 0)
end

--- Characters-reference toolbar metrics (64px card, 32px controls, 8px gaps, 0 edge inset).
---@return table metrics { btnH, squareBtn, gap, edgeInset, filterW, trailingGap }
function ns.UI_GetTitleCardToolbarMetrics()
    local sp = UI_SPACING or {}
    local btnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    return {
        btnH = btnH,
        squareBtn = btnH,
        gap = sp.HEADER_TOOLBAR_CONTROL_GAP or 8,
        edgeInset = sp.TITLE_CARD_TOOLBAR_EDGE_INSET or 0,
        filterW = 96,
        trailingGap = 10,
    }
end

--- Reserve width for title/subtitle text (right-to-left control chain on title card).
---@return number
function ns.UI_ComputeTitleToolbarReserve(widths, opts)
    local m = ns.UI_GetTitleCardToolbarMetrics()
    opts = opts or {}
    local total = m.edgeInset
    local n = widths and #widths or 0
    for i = 1, n do
        total = total + (widths[i] or 0)
        if i < n then
            total = total + m.gap
        end
    end
    if n > 0 then
        total = total + (opts.extraTrailingGap or m.trailingGap)
    end
    return total
end

--- Title-card toolbar reserve for Characters (Filter + custom section + gaps + right inset).
---@return number
local function ComputeCharactersTitleToolbarReserve()
    local m = ns.UI_GetTitleCardToolbarMetrics()
    return ns.UI_ComputeTitleToolbarReserve({ m.filterW, m.squareBtn })
end

-- Character sort/filter flyouts: SharedWidgets_CharacterFilter.lua (loaded after this file)


--- Hide legacy title-card expand/collapse-all controls (toolbar toggle removed).
function ns.UI_HideTitleCardExpandCollapseControls(ownerFrame)
    if not ownerFrame then return end
    if ownerFrame._wnExpandCollapseToggleBtn then ownerFrame._wnExpandCollapseToggleBtn:Hide() end
    if ownerFrame._wnExpandCollapseCollapseBtn then ownerFrame._wnExpandCollapseCollapseBtn:Hide() end
    if ownerFrame._wnExpandCollapseExpandBtn then ownerFrame._wnExpandCollapseExpandBtn:Hide() end
    if ownerFrame._wnCharactersExpandCollapseToggleBtn then ownerFrame._wnCharactersExpandCollapseToggleBtn:Hide() end
end

-- Exports (char row layout: SharedWidgets_CharRow.lua)
ns.UI_ComputeCharactersTitleToolbarReserve = ComputeCharactersTitleToolbarReserve
-- UI_GetTitleCardToolbarMetrics / UI_ComputeTitleToolbarReserve exported above

-- Empty state cards: SharedWidgets_EmptyState.lua
-- Search box: Modules/UI/SearchBoxComponent.lua (loads after SharedWidgets; owns ns.UI_CreateSearchBox).

-- SHARED UI CONSTANTS

local UI_CONSTANTS = {
    BUTTON_HEIGHT = 32,  -- Standardized to match search boxes and header elements
    SEARCH_BOX_HEIGHT = 32,
    --- Pause after last keystroke before search redraw (all tabs; SearchBoxComponent + Collections).
    SEARCH_DEBOUNCE_SEC = 0.45,
    BUTTON_WIDTH_DEFAULT = 80,
    BORDER_SIZE = 1,
    BUTTON_BORDER_COLOR = function() return COLORS.accent end,
    BUTTON_BG_COLOR = {0.1, 0.1, 0.1, 1},
}

ns.UI_CONSTANTS = UI_CONSTANTS

--- Match header toolbar buttons / sort triggers to BUTTON_HEIGHT (single call site for tab headers).
function ns.UI_ApplyHeaderToolbarControlHeight(frame)
    if not frame or not frame.SetHeight then return end
    frame:SetHeight(UI_CONSTANTS.BUTTON_HEIGHT)
end

-- SHARED BUTTON WIDGET

--[[
    Create a themed button with consistent styling
    @param parent - Parent frame
    @param text - Button text
    @param width - Button width
    @return button - Created button
]]
local function CreateThemedButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 100, UI_CONSTANTS.BUTTON_HEIGHT)

    local idleBg = GetControlChromeBackdrop()
    ApplyVisuals(btn, idleBg, GetAccentBorderRGBA(0.6))

    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(btn)
    end

    local btnText = FontManager:CreateFontString(btn, UIFontRole("searchButtonText"), "OVERLAY")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText
    ns.UI_SetTextColorRole(btnText, "Bright")

    btn:SetScript("OnEnter", function(self)
        ApplyVisuals(self, GetControlChromeHoverBackdrop(), GetAccentBorderRGBA(0.8))
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyVisuals(self, GetControlChromeBackdrop(), GetAccentBorderRGBA(0.6))
    end)

    local textWidth = btnText:GetStringWidth() or 0
    local padding = 20
    if textWidth + padding > btn:GetWidth() then
        btn:SetWidth(textWidth + padding)
    end

    return btn
end

-- SHARED CHECKBOX WIDGET

-- SHARED TOGGLE INDICATOR (unified base for checkbox & radio)

-- Shared visual constants for all toggle indicators
local TOGGLE_SIZE = 16
local TOGGLE_DOT_SIZE = 6

ns.TOGGLE_REGISTRY = ns.TOGGLE_REGISTRY or {}
local TOGGLE_REGISTRY = ns.TOGGLE_REGISTRY

local function GetToggleDotColor()
    local g = COLORS and COLORS.gold
    if g then
        return g[1], g[2], g[3], g[4] or 1
    end
    return 1, 0.82, 0, 1
end

local function RefreshToggleChrome()
    for i = #TOGGLE_REGISTRY, 1, -1 do
        local frame = TOGGLE_REGISTRY[i]
        if not frame then
            table.remove(TOGGLE_REGISTRY, i)
        else
            local dot = frame.innerDot or frame.checkTexture
            if dot and dot.SetColorTexture then
                local r, g, b, a = GetToggleDotColor()
                dot:SetColorTexture(r, g, b, a)
            end
            local ac = COLORS and COLORS.accent
            if ac and frame.defaultBorderColor then
                frame.defaultBorderColor[1] = ac[1]
                frame.defaultBorderColor[2] = ac[2]
                frame.defaultBorderColor[3] = ac[3]
                frame.hoverBorderColor[1] = math.min(1, ac[1] * 1.15)
                frame.hoverBorderColor[2] = math.min(1, ac[2] * 1.15)
                frame.hoverBorderColor[3] = math.min(1, ac[3] * 1.15)
            end
        end
    end
end
ns.UI_RefreshToggleChrome = RefreshToggleChrome

--- Border uses **current** COLORS.accent (not load-time snapshot — avoids default purple theme leaking).
local function ApplyToggleVisuals(frame)
    frame:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    local ac = COLORS and COLORS.accent or { 0.5, 0.5, 0.5 }
    local borderCol = { ac[1], ac[2], ac[3], 0.8 }
    local toggleBg = GetControlChromeBackdrop()
    ApplyVisuals(frame, toggleBg, borderCol)
    -- ApplyVisuals heuristic can classify dark accents as "border"; toggles must always track accent refresh.
    frame._borderType = "accent"
    frame._borderAlpha = borderCol[4] or 0.8
    frame._bgType = "controlChrome"

    local dot = frame:CreateTexture(nil, "OVERLAY")
    dot:SetDrawLayer("OVERLAY", 7)
    dot:SetSize(TOGGLE_DOT_SIZE, TOGGLE_DOT_SIZE)
    -- TOPLEFT inset avoids subpixel CENTER rounding (right-column toggles looked shifted vs border).
    local inset = math.floor((TOGGLE_SIZE - TOGGLE_DOT_SIZE) / 2 + 0.5)
    dot:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    local dr, dg, db, da = GetToggleDotColor()
    dot:SetColorTexture(dr, dg, db, da)

    frame.innerDot = dot
    frame.checkTexture = dot  -- alias so .checkTexture API keeps working

    frame.defaultBorderColor = { borderCol[1], borderCol[2], borderCol[3], borderCol[4] }
    frame.hoverBorderColor = {
        math.min(1, ac[1] * 1.15),
        math.min(1, ac[2] * 1.15),
        math.min(1, ac[3] * 1.15),
        1,
    }

    if not frame._wnToggleRegistered then
        frame._wnToggleRegistered = true
        table.insert(TOGGLE_REGISTRY, frame)
    end

    return dot
end

local function ThemedToggleBorderHover(frame, hover)
    local updateBorder = ns.UI_UpdateBorderColor
    if not frame or not updateBorder then return end
    local ac = COLORS and COLORS.accent or { 0.5, 0.5, 0.5 }
    if hover then
        updateBorder(frame, {
            math.min(1, ac[1] * 1.15),
            math.min(1, ac[2] * 1.15),
            math.min(1, ac[3] * 1.15),
            1,
        })
    else
        updateBorder(frame, { ac[1], ac[2], ac[3], 0.8 })
    end
end

--[[
    Create a themed checkbox (CheckButton with toggle behavior)
    @param parent - Parent frame
    @param initialState - Initial checked state (boolean)
    @return checkbox - Created checkbox
]]
local function CreateThemedCheckbox(parent, initialState)
    if not parent then
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("WarbandNexus DEBUG: CreateThemedCheckbox called with nil parent!")
        end
        return nil
    end

    local checkbox = CreateFrame("CheckButton", nil, parent)
    -- Strip inherited CheckButton artwork (Midnight often paints default checked atlas → magenta/purple over custom dot).
    pcall(function()
        checkbox:SetNormalTexture("")
        checkbox:SetPushedTexture("")
        checkbox:SetHighlightTexture("")
        checkbox:SetDisabledTexture("")
        checkbox:SetCheckedTexture("")
    end)
    local dot = ApplyToggleVisuals(checkbox)

    if initialState then
        dot:Show()
        checkbox:SetChecked(true)
    else
        dot:Hide()
        checkbox:SetChecked(false)
    end

    checkbox:SetScript("OnClick", function(self)
        self.innerDot:SetShown(self:GetChecked())
    end)

    checkbox:SetScript("OnEnter", function(self)
        ThemedToggleBorderHover(self, true)
    end)

    checkbox:SetScript("OnLeave", function(self)
        ThemedToggleBorderHover(self, false)
    end)

    checkbox:RegisterForClicks("LeftButtonUp")

    return checkbox
end

--[[
    Create a themed radio button (visual-only Frame, selection managed by caller)
    @param parent - Parent frame
    @param isSelected - Initial selected state (boolean)
    @return radioButton - Created radio button frame with innerDot reference
]]
local function CreateThemedRadioButton(parent, isSelected)
    if not parent then
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint("WarbandNexus DEBUG: CreateThemedRadioButton called with nil parent!")
        end
        return nil
    end

    local radioButton = CreateFrame("Frame", nil, parent)
    local dot = ApplyToggleVisuals(radioButton)
    dot:SetShown(isSelected or false)

    return radioButton
end

-- VERTICAL SECTION CHAIN (parent-relative X + BOTTOM→TOP stack; Storage / VLM parity)

--- Anchor `frame` below `prevAnchorFrame` so section height changes stack siblings correctly.
--- Horizontal position is **parent-relative** (`desiredLeftFromParent`), cancelling the anchor's own indent.
--- @param gapBelowPrev number|nil pixels below previous anchor bottom; defaults to SECTION_SPACING when prev exists
--- @param fallbackYOffsetFromTop number|nil used only when `prevAnchorFrame` is nil (TOPLEFT from parent top)
local function ChainSectionFrameBelow(parent, frame, prevAnchorFrame, desiredLeftFromParent, gapBelowPrev, fallbackYOffsetFromTop)
    if not parent or not frame then return end
    desiredLeftFromParent = desiredLeftFromParent or 0
    frame:ClearAllPoints()
    if prevAnchorFrame then
        local layout = ns.UI_LAYOUT or {}
        local g = (gapBelowPrev ~= nil) and gapBelowPrev or (layout.SECTION_SPACING or 8)
        if g < 0 then g = 0 end
        local ancL = prevAnchorFrame:GetLeft()
        local parL = parent:GetLeft()
        local anchorLeftFromParent = (ancL and parL) and (ancL - parL) or 0
        local xOff = desiredLeftFromParent - anchorLeftFromParent
        frame:SetPoint("TOPLEFT", prevAnchorFrame, "BOTTOMLEFT", xOff, -g)
    else
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", desiredLeftFromParent, -(fallbackYOffsetFromTop or 0))
    end
end

-- GAME TOOLTIP + CLASS COLOR HELPERS (Collections Recent, etc.)

local strupper = string.upper

--- GameTooltip owner: horizontal flip so narrow columns (e.g. Collections Recent) open toward screen center.
--- Does not call `GameTooltip_SetDefaultAnchor` (that path grows from owner top-right and often covers the next column).
--- Call with `GameTooltip:ClearLines()` already done if you replace prior contents.
function ns.UI_SetGameTooltipSmartOwner(frame, xOffset, yOffset)
    if not frame or not GameTooltip then return end
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    local left = frame.GetLeft and frame:GetLeft()
    local right = frame.GetRight and frame:GetRight()
    if not left or not right then
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT", xOffset, yOffset)
        return
    end
    local mid = (left + right) / 2
    local sw = GetScreenWidth and GetScreenWidth() or 1920
    if mid > sw * 0.52 then
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT", xOffset, yOffset)
    else
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT", xOffset, yOffset)
    end
end

--- English class token (WARRIOR, MAGE, …) from a `db.global.characters` entry.
---@return string|nil
local function ResolveClassFileTokenFromCharData(charData)
    if type(charData) ~= "table" then return nil end
    local cf = charData.classFile
    if type(cf) == "string" and cf ~= "" then
        return strupper(cf)
    end
    local cid = charData.classID
    if type(cid) == "number" and cid > 0 and GetClassInfo then
        local ok, _, file = pcall(GetClassInfo, cid)
        if ok and type(file) == "string" and file ~= "" then
            return strupper(file)
        end
    end
    local localized = charData.class
    if type(localized) ~= "string" or localized == "" then
        return nil
    end
    local up = strupper(localized)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[up] then
        return up
    end
    if not GetNumClasses or not GetClassInfo then
        return nil
    end
    local want = localized:lower()
    local n = GetNumClasses()
    if type(n) ~= "number" or n < 1 then return nil end
    for i = 1, n do
        local ok, cname, cfile = pcall(GetClassInfo, i)
        if ok and type(cname) == "string" and type(cfile) == "string" and cname ~= "" and cfile ~= "" then
            if cname:lower() == want then
                return strupper(cfile)
            end
        end
    end
    return nil
end

--- Blizzard class RGB (0-1); neutral gray when unknown.
---@param classFile string|nil
---@return number r, number g, number b
local function GetClassColorRaw(classFile)
    if not classFile or classFile == "" then
        return 0.8, 0.8, 0.8
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
    if rc and type(rc.r) == "number" then
        return rc.r, rc.g, rc.b
    end
    return 0.8, 0.8, 0.8
end
ns.UI_GetClassColorRaw = GetClassColorRaw

--- Class RGB for list/card surfaces (raw Blizzard class color; readability via FontManager OUTLINE).
---@param classFile string|nil
---@return number r, number g, number b
local function GetClassColorForSurface(classFile)
    local r, g, b = GetClassColorRaw(classFile)
    return AdjustRGBForLightOutline(r, g, b)
end
ns.UI_GetClassColorForSurface = GetClassColorForSurface

--- Six-digit RRGGBB for class text on list/card surfaces.
---@param classFile string|nil
---@return string
local function GetClassColorHexForSurface(classFile)
    local r, g, b = GetClassColorForSurface(classFile)
    return format("%02x%02x%02x", r * 255, g * 255, b * 255)
end
ns.UI_GetClassColorHexForSurface = GetClassColorHexForSurface

--- `|cff` wrapped character name (surface-safe class hue).
---@param name string
---@param classFile string|nil
---@return string
function ns.UI_FormatClassColoredName(name, classFile)
    if not name or name == "" or (issecretvalue and issecretvalue(name)) then
        local muted = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cff888888"
        return muted .. ((ns.L and ns.L["UNKNOWN"]) or "Unknown") .. "|r"
    end
    local hex = GetClassColorHexForSurface(classFile)
    return "|cff" .. hex .. name .. "|r"
end

--- Vertical class stripe (3px); text readability is FontManager OUTLINE, not bar stroke.
---@return Texture barTex
function ns.UI_CreateClassColorStripe(parent, relFrame, x, y, barW, barH, classFile)
    barW = barW or 3
    barH = barH or 20
    local r, g, b = GetClassColorRaw(classFile)
    local anchor = relFrame or parent
    local bar = parent:CreateTexture(nil, "ARTWORK")
    bar:SetSize(barW, barH)
    bar:SetPoint("LEFT", anchor, "TOPLEFT", x or 15, y or 0)
    bar:SetColorTexture(r, g, b, 1)
    return bar
end

--- `|cffrrggbb` prefix for `displayName` using `db.global.characters` (case-insensitive name; `classFile`, `classID`, or localized `class`).
---@return string
function ns.UI_GetClassColorHexForWarbandCharacter(displayName)
    if not displayName or displayName == "" or (issecretvalue and issecretvalue(displayName)) then
        return "|cffaaaaaa"
    end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local chars = db and db.characters
    if type(chars) ~= "table" then
        return "|cffaaaaaa"
    end
    local wantLower = displayName:lower()
    for _, charData in pairs(chars) do
        if type(charData) == "table" and charData.name and not (issecretvalue and issecretvalue(charData.name)) then
            if charData.name:lower() == wantLower then
                local token = ResolveClassFileTokenFromCharData(charData)
                if token then
                    return "|cff" .. GetClassColorHexForSurface(token)
                end
                break
            end
        end
    end
    return "|cffaaaaaa"
end

-- NAMESPACE EXPORTS

-- ns.UI_GetQualityHex assigned with GetQualityHex (early export — before FormatUpgradeTrackMarkup)
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_ApplyProfessionCraftingQualityAtlasToTexture = ApplyProfessionCraftingQualityAtlasToTexture
ns.UI_GetProfessionCraftingQualityAtlasNameForTier = GetProfessionCraftingQualityAtlasNameForTier
ns.UI_CreateCard = CreateCard
-- Money/number text formatting: Modules/UI/FormatHelpers.lua (loads before this file; ns.UI_Format*)
ns.UI_ChainSectionFrameBelow = ChainSectionFrameBelow
ns.UI_ForwardMouseWheelToScrollAncestor = ForwardMouseWheelToScrollAncestor
ns.UI_RefreshColors = RefreshColors
ns.UI_CalculateThemeColors = CalculateThemeColors

-- Frame pooling exports are owned by FramePoolFactory.lua (loads after SharedWidgets).
-- Keep a single authoritative export source to avoid load-order dependent overrides.

-- Shared widget exports
ns.UI_CreateThemedButton = CreateThemedButton
ns.UI_CreateThemedCheckbox = CreateThemedCheckbox
ns.UI_CreateThemedRadioButton = CreateThemedRadioButton
ns.UI_TOGGLE_SIZE = TOGGLE_SIZE

-- Modal / external dialogs: authoritative shell in Modules/UI/WindowFactory.lua (`ns.UI_CreateExternalWindow`).

-- TOOLTIP API

-- Expose tooltip service API for use in UI modules
ns.UI_ShowTooltip = function(frame, data)
    if WarbandNexus and WarbandNexus.Tooltip then
        WarbandNexus.Tooltip:Show(frame, data)
    end
end

ns.UI_HideTooltip = function()
    if WarbandNexus and WarbandNexus.Tooltip then
        WarbandNexus.Tooltip:Hide()
    end
end


-- TRY COUNT POPUP (Plans / Collections / Tracker)

local tryCountPopupFrame = nil

function ns.UI_ShowTryCountPopup(collectibleType, collectibleID, displayName)
    if not collectibleType or not collectibleID then return end
    local COLORS = ns.UI_COLORS or { accent = { 0.40, 0.20, 0.58 }, accentDark = { 0.28, 0.14, 0.41 }, bg = { 0.06, 0.06, 0.08 }, border = { 0.20, 0.20, 0.25 } }

    if not tryCountPopupFrame then
        local f = CreateFrame("Frame", "WNTryCountPopup", UIParent, "BackdropTemplate")
        f:SetSize(300, 160)
        f:SetPoint("CENTER")
        f:EnableMouse(true)
        f:SetMovable(true)

        if ns.WindowManager then
            ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:InstallESCHandler(f)
            ns.WindowManager:InstallDragHandler(f, f)
        else
            f:SetFrameStrata("FULLSCREEN_DIALOG")
            f:SetFrameLevel(200)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
        end

        ApplyVisuals(f, { 0.04, 0.04, 0.06, 0.98 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9 })

        local tryShell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
        local tryInset = tryShell.FRAME_CONTENT_INSET or 2
        local tryHdrH = tryShell.TRY_COUNT_POPUP_HEADER_HEIGHT or 32
        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetHeight(tryHdrH)
        header:SetPoint("TOPLEFT", tryInset, -tryInset)
        header:SetPoint("TOPRIGHT", -tryInset, -tryInset)
        ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })

        local headerTitle = FontManager:CreateFontString(header, UIFontRole("tryPopupHeader"), "OVERLAY")
        headerTitle:SetPoint("CENTER")
        headerTitle:SetText((ns.L and ns.L["SET_TRY_COUNT"]) or "Set Try Count")
        ns.UI_SetTextColorRole(headerTitle, "Bright")
        f.headerTitle = headerTitle

        local nameLabel = FontManager:CreateFontString(f, UIFontRole("tryPopupBody"), "OVERLAY")
        nameLabel:SetPoint("TOP", header, "BOTTOM", 0, -12)
        nameLabel:SetJustifyH("CENTER")
        ns.UI_SetTextColorRole(nameLabel, "Bright")
        f.nameLabel = nameLabel

        local editBoxBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
        editBoxBg:SetSize(120, 28)
        editBoxBg:SetPoint("TOP", nameLabel, "BOTTOM", 0, -10)
        ApplyVisuals(editBoxBg, { 0.02, 0.02, 0.03, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5 })

        local editBox = CreateFrame("EditBox", nil, editBoxBg)
        editBox:SetPoint("TOPLEFT", 8, -4)
        editBox:SetPoint("BOTTOMRIGHT", -8, 4)
        editBox:SetAutoFocus(false)
        editBox:SetNumeric(true)
        editBox:SetMaxLetters(6)
        editBox:SetFontObject(ChatFontNormal) -- required initial FontObject (WoW crashes without one)
        if FontManager and FontManager.ApplyFontToEditBox then
            FontManager:ApplyFontToEditBox(editBox, "body")
            FontManager:RegisterManagedEditBox(editBox, "body")
        end
        ns.UI_SetTextColorRole(editBox, "Bright")
        editBox:SetJustifyH("CENTER")
        f.editBox = editBox

        local btnWidth, btnHeight = 90, 26

        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(btnWidth, btnHeight)
        saveBtn:SetPoint("TOPRIGHT", editBoxBg, "BOTTOM", -4, -10)
        ApplyVisuals(saveBtn, { 0.08, 0.08, 0.10, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        local saveBtnText = FontManager:CreateFontString(saveBtn, UIFontRole("dialogButtonLabel"), "OVERLAY")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText((ns.L and ns.L["SAVE"]) or "Save")
        ns.UI_SetTextColorRole(saveBtnText, "Bright")
        saveBtn:SetScript("OnEnter", function(self)
            ApplyVisuals(self, { 0.12, 0.12, 0.14, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
        end)
        saveBtn:SetScript("OnLeave", function(self)
            ApplyVisuals(self, { 0.08, 0.08, 0.10, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end)
        f.saveBtn = saveBtn

        local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        cancelBtn:SetSize(btnWidth, btnHeight)
        cancelBtn:SetPoint("TOPLEFT", editBoxBg, "BOTTOM", 4, -10)
        ApplyVisuals(cancelBtn, { 0.08, 0.08, 0.10, 1 }, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
        local cancelBtnText = FontManager:CreateFontString(cancelBtn, UIFontRole("dialogButtonLabel"), "OVERLAY")
        cancelBtnText:SetPoint("CENTER")
        cancelBtnText:SetText(_G.CANCEL or "Cancel")
        ns.UI_SetTextColorRole(cancelBtnText, "Normal")
        cancelBtn:SetScript("OnEnter", function(self)
            ApplyVisuals(self, { 0.12, 0.12, 0.14, 1 }, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8 })
        end)
        cancelBtn:SetScript("OnLeave", function(self)
            ApplyVisuals(self, { 0.08, 0.08, 0.10, 1 }, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
        end)
        cancelBtn:SetScript("OnClick", function() f:Hide() end)

        editBox:SetScript("OnEnterPressed", function()
            f.saveBtn:Click()
        end)
        editBox:SetScript("OnEscapePressed", function()
            f:Hide()
        end)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                self:Hide()
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)

        tryCountPopupFrame = f
        if ns.UI_RegisterScaledFrame then
            ns.UI_RegisterScaledFrame(f)
        elseif ns.UI_ApplyAddonUIScale then
            ns.UI_ApplyAddonUIScale(f)
        end
    end

    local popup = tryCountPopupFrame
    popup.nameLabel:SetText(displayName or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"))

    local currentCount = 0
    if WarbandNexus and WarbandNexus.GetTryCount then
        currentCount = WarbandNexus:GetTryCount(collectibleType, collectibleID) or 0
    end
    popup.editBox:SetText(tostring(currentCount))

    popup._wnTryType = collectibleType
    popup._wnTryID = collectibleID

    popup.saveBtn:SetScript("OnClick", function()
        local rawCount = popup.editBox:GetText()
        if issecretvalue and issecretvalue(rawCount) then
            popup:Hide()
            return
        end
        local count = tonumber(rawCount)
        if count and count >= 0 and WarbandNexus and WarbandNexus.SetTryCount and popup._wnTryType and popup._wnTryID then
            WarbandNexus:SetTryCount(popup._wnTryType, popup._wnTryID, count)
        end
        popup:Hide()
    end)

    popup:Show()
    if popup.Raise then popup:Raise() end
    if not InCombatLockdown() and popup.editBox then
        local txt = tostring(currentCount)
        popup.editBox:SetFocus()
        local len = string.len(txt)
        popup.editBox:SetCursorPosition(len)
    end
end

--- Opens the try-count editor immediately (never use MenuUtil here: on Midnight the context menu often
--- registers success but shows nothing, which prevented the popup from ever opening.)
function ns.UI_OpenTryCountFromContext(_anchorFrame, collectibleType, collectibleID, displayName)
    if not collectibleType or not collectibleID or not ns.UI_ShowTryCountPopup then return end
    ns.UI_ShowTryCountPopup(collectibleType, collectibleID, displayName)
end

ns.SafeColorArray = SafeColorArray

-- SETTINGS UI HELPERS

--[[
    Create a bordered section/group container
    @param parent Frame - Parent frame
    @param title string - Section title (optional)
    @param width number - Section width
    @return Frame - Section container
]]
local function CreateSection(parent, title, width)
    local COLORS = GetColors()
    local sp = UI_SPACING
    local px = sp.SECTION_CARD_PADDING_X or 15
    local titleTop = sp.SECTION_CARD_TITLE_TOP or -12
    local bodyWithTitle = sp.SECTION_CARD_BODY_TOP_WITH_TITLE or -40
    local bodyNoTitle = sp.SECTION_CARD_BODY_TOP_NO_TITLE or -15
    
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetSize(width or 640, 1)  -- Height will be calculated
    
    -- Use ApplyVisuals for centralized border management
    local surf = COLORS.surfaceElevated or COLORS.bgLight
    ApplyVisuals(section, {surf[1], surf[2], surf[3], 0.35}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})

    if ns.UI_ApplySectionChromeUnderlay then
        ns.UI_ApplySectionChromeUnderlay(section)
    end
    
    -- Title (if provided) - inside card
    if title then
        local titleText = FontManager:CreateFontString(section, UIFontRole("settingsSectionTitle"), "OVERLAY", "accent")
        titleText:SetPoint("TOPLEFT", px, titleTop)
        titleText:SetText(title)
        if ns.UI_GetAccentTextRGBA then
            local ar, ag, ab, aa = ns.UI_GetAccentTextRGBA()
            if ns.UI_SetInkColor then
                ns.UI_SetInkColor(titleText, ar, ag, ab, aa)
            else
                titleText:SetTextColor(ar, ag, ab, aa)
            end
        end
        section.titleText = titleText
    end
    
    -- Content container (inset from border with proper padding)
    local content = CreateFrame("Frame", nil, section)
    local bodyTop = title and bodyWithTitle or bodyNoTitle
    content:SetPoint("TOPLEFT", px, bodyTop)
    content:SetPoint("TOPRIGHT", -px, bodyTop)
    section.content = content
    
    return section
end

--[[
    Create Card Header Layout with Icon and Text
    Standardized layout: Icon + Label + Value (all centered in card)
    @param parent Frame - Parent card frame
    @param iconTexture string - Icon texture path or atlas name
    @param iconSize number - Icon size in pixels
    @param isAtlas boolean - True if texture is atlas
    @param labelText string - Header label text
    @param valueText string - Value text (can be empty)
    @param labelFont string - Font category for label (default "subtitle")
    @param valueFont string - Font category for value (default "body")
    @return table - {icon, label, value, container}
]]
local function CreateCardHeaderLayout(parent, iconTexture, iconSize, isAtlas, labelText, valueText, labelFont, valueFont)
    labelFont = labelFont or FontManager:GetFontRole("cardHeaderLabel")
    valueFont = valueFont or FontManager:GetFontRole("cardHeaderValue")
    
    -- Create icon (centered vertically at left side)
    local iconFrame = ns.UI_CreateIcon(parent, iconTexture, iconSize, isAtlas, nil, true)
    iconFrame:SetPoint("CENTER", parent, "LEFT", 15 + (iconSize/2), 0)
    iconFrame:Show()
    
    -- Create container for text group
    local textContainer = CreateFrame("Frame", nil, parent)
    textContainer:SetSize(200, 40)
    
    -- Create label (centered in container)
    local label = FontManager:CreateFontString(textContainer, labelFont, "OVERLAY")
    label:SetText(labelText)
    ns.UI_SetTextColorRole(label, "Bright")
    label:SetJustifyH("LEFT")
    
    -- Create value (if provided)
    -- Texts are clamped to the container's RIGHT edge with wrapping off: long
    -- values (large gold amounts) used to grow past the container and overlap
    -- neighboring card content at intermediate widths.
    local value
    if valueText and valueText ~= "" then
        value = FontManager:CreateFontString(textContainer, valueFont, "OVERLAY")
        value:SetText(valueText)
        value:SetJustifyH("LEFT")
        value:SetWordWrap(false)
        if type(valueText) ~= "string" or (issecretvalue and issecretvalue(valueText))
            or not valueText:find("|cff", 1, true) then
            ns.UI_SetTextColorRole(value, "Normal")
        end

        -- Position texts centered in container
        label:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
        label:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        label:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
        value:SetPoint("TOP", textContainer, "CENTER", 0, -4)    -- Value below center
        value:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        value:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
    else
        -- Single text, center it
        label:SetPoint("CENTER", textContainer, "CENTER", 0, 0)
        label:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        label:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)
    end
    label:SetWordWrap(false)
    
    -- Position container: LEFT from icon, CENTER vertically to CARD
    textContainer:SetPoint("LEFT", iconFrame, "RIGHT", 12, 0)
    textContainer:SetPoint("CENTER", parent, "CENTER", 0, 0)  -- Center to card!
    
    return {
        icon = iconFrame,
        label = label,
        value = value,
        container = textContainer
    }
end

-- DISABLED MODULE STATE CARD

-- Creates a centered card showing module disabled state with Warband logo
-- @param parent: Parent frame to attach to
-- @param yOffset: Y offset from top
-- @param moduleName: Display name of the module (e.g., "Currency", "Reputation")
-- @return height: Total height consumed
local function CreateDisabledModuleCard(parent, yOffset, moduleName)
    local COLORS = ns.UI_COLORS
    local FontManager = ns.FontManager
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    
    -- Calculate parent height dynamically
    local parentHeight = parent:GetHeight() or 600
    
    -- Create card frame that fills entire content area (full width and height)
    local card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    card:SetPoint("BOTTOMRIGHT", -SIDE_MARGIN, SIDE_MARGIN)
    
    ApplyStandardCardElevatedChrome(card)
    local borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.72 }
    
    -- Content container (vertically centered)
    local contentContainer = CreateFrame("Frame", nil, card)
    contentContainer:SetSize(400, 200)
    contentContainer:SetPoint("CENTER", card, "CENTER", 0, 0)
    
    -- Icon container frame for proper layering
    local iconContainer = CreateFrame("Frame", nil, contentContainer)
    iconContainer:SetSize(80, 80)
    iconContainer:SetPoint("TOP", contentContainer, "TOP", 0, 0)
    
    -- Warband Logo (large, centered)
    local iconSize = 80
    local icon = iconContainer:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetAllPoints(iconContainer)
    icon:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")
    icon:SetTexCoord(0, 1, 0, 1)
    
    -- Icon border frame (thin 1px accent ring) - behind the icon
    local iconBorder = CreateFrame("Frame", nil, contentContainer, BackdropTemplateMixin and "BackdropTemplate")
    iconBorder:SetSize(iconSize + 4, iconSize + 4)
    iconBorder:SetPoint("CENTER", iconContainer, "CENTER", 0, 0)
    iconBorder:SetFrameLevel(iconContainer:GetFrameLevel() - 1)
    ApplyVisuals(iconBorder, nil, borderColor)  -- Just border, no background
    
    -- "Module Disabled" title
    local title = FontManager:CreateFontString(contentContainer, UIFontRole("moduleDisabledTitle"), "OVERLAY")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -24)
    title:SetText("|cffcccccc" .. ((ns.L and ns.L["MODULE_DISABLED"]) or "Module Disabled") .. "|r")
    
    -- Description with colored module name
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local description = FontManager:CreateFontString(contentContainer, UIFontRole("moduleDisabledBody"), "OVERLAY")
    description:SetPoint("TOP", title, "BOTTOM", 0, -16)
    description:SetWidth(380)
    description:SetJustifyH("CENTER")
    local settingsStr = GetTextRoleHex("Bright") .. ((ns.L and ns.L["BTN_SETTINGS"]) or SETTINGS or "Settings") .. "|r"
    local moduleStr = "|cff" .. hexColor .. moduleName .. "|r"
    local mutedHex = GetTextRoleHex("Muted")
    description:SetText(
        mutedHex .. format((ns.L and ns.L["MODULE_DISABLED_DESC_FORMAT"]) or "Enable it in %s to use %s.", settingsStr, moduleStr) .. "|r"
    )
    
    card:Show()
    
    -- Return full height to parent
    return parentHeight - yOffset
end

-- RESET TIMER WIDGET

-- Creates a standardized reset timer with clock icon
-- @param parent: Parent frame to attach to
-- @param anchorPoint: Anchor point string (e.g., "RIGHT", "TOPRIGHT")
-- @param xOffset: X offset from anchor
-- @param yOffset: Y offset from anchor (default 0)
-- @param getSecondsFunc: Function that returns seconds until reset
-- @return table: { icon, text, container, Update }
local function CreateResetTimer(parent, anchorPoint, xOffset, yOffset, getSecondsFunc)
    local FontManager = ns.FontManager
    yOffset = yOffset or 0
    
    -- Container frame for icon + text (sized to fit content)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(150, 20)  -- Wider to accommodate icon + text
    container:SetPoint(anchorPoint, parent, anchorPoint, xOffset, yOffset)
    
    -- Reset text (positioned at RIGHT of container)
    local text = FontManager:CreateFontString(container, UIFontRole("resetTimerText"), "OVERLAY")
    text:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    local gr, gg, gb, ga = 0.3, 0.9, 0.3, 1
    if ns.UI_GetSemanticGreenColor then
        gr, gg, gb, ga = ns.UI_GetSemanticGreenColor()
    else
        local gc = COLORS.green or { gr, gg, gb, ga }
        gr, gg, gb, ga = gc[1], gc[2], gc[3], gc[4] or 1
    end
    text:SetTextColor(gr, gg, gb, ga)
    
    -- Clock icon (16x16) - positioned to the LEFT of text
    local icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetAtlas("characterupdate_clock-icon", true)
    icon:SetPoint("RIGHT", text, "LEFT", -4, 0)  -- 4px spacing from text
    
    -- Update function (uses shared Utilities:FormatTimeCompact)
    local function Update()
        if getSecondsFunc then
            local seconds = getSecondsFunc()
            text:SetText(((ns.L and ns.L["RESET_PREFIX"]) or "Reset:") .. " " .. ns.Utilities:FormatTimeCompact(seconds))
        end
    end
    
    -- Initial update
    Update()
    
    -- Auto-update every 60 seconds with a ticker (avoid per-frame polling).
    local function StartTicker()
        if container._resetTicker then return end
        container._resetTicker = C_Timer.NewTicker(60, Update)
    end

    container:SetScript("OnShow", StartTicker)
    container:SetScript("OnHide", function(self)
        if self._resetTicker then
            self._resetTicker:Cancel()
            self._resetTicker = nil
        end
    end)
    StartTicker()
    
    return {
        icon = icon,
        text = text,
        container = container,
        Update = Update
    }
end

-- Export reset timer helper
ns.UI_CreateResetTimer = CreateResetTimer

-- Export disabled state helper
ns.UI_CreateDisabledModuleCard = CreateDisabledModuleCard

-- Export Settings UI helpers
ns.UI_CreateSection = CreateSection

-- DB VERSION BADGE (Debug Logging)

---Creates a small badge showing which DB/cache is being used by this tab
---@return Frame Badge frame
local function CreateDBVersionBadge(parent, dataSource, anchorPoint, xOffset, yOffset)
    local FontManager = ns.FontManager
    anchorPoint = anchorPoint or "TOPRIGHT"
    xOffset = xOffset or -10
    yOffset = yOffset or -10
    
    -- Container frame
    local badge = CreateFrame("Frame", nil, parent)
    badge:SetSize(200, 20)
    badge:SetPoint(anchorPoint, parent, anchorPoint, xOffset, yOffset)
    badge:SetFrameStrata("HIGH")
    
    -- Badge text
    local text = FontManager:CreateFontString(badge, UIFontRole("versionBadge"), "OVERLAY")
    text:SetPoint("RIGHT", badge, "RIGHT", 0, 0)
    text:SetJustifyH("RIGHT")
    text:SetWidth(200)
    
    -- Color based on source type
    local color = "|cff999999" -- Gray for unknown
    if dataSource:find("Cache") then
        color = "|cff00ff00" -- Green for cache services (modern)
    elseif dataSource:find("LEGACY") or dataSource:find("db%.global") then
        color = "|cffffaa00" -- Orange for direct DB access (legacy)
    end
    
    text:SetText(color .. ((ns.L and ns.L["DB_LABEL"]) or "DB:") .. " " .. dataSource .. "|r")
    
    -- Tooltip on hover
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if ns.UI_GameTooltipAddRoleLine then
            ns.UI_GameTooltipAddRoleLine(GameTooltip, (ns.L and ns.L["DATA_SOURCE_TITLE"]) or "Data Source Information", "Bright")
        else
            GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_TITLE"]) or "Data Source Information", 1, 1, 1)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_USING"]) or "This tab is using:", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(dataSource, 1, 1, 0)
        GameTooltip:AddLine(" ")
        
        if dataSource:find("Cache") then
            GameTooltip:AddLine("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t " .. ((ns.L and ns.L["DATA_SOURCE_MODERN"]) or "Modern cache service (event-driven)"), 0, 1, 0)
        elseif dataSource:find("LEGACY") then
            GameTooltip:AddLine("|cffffaa00⚠|r " .. ((ns.L and ns.L["DATA_SOURCE_LEGACY"]) or "Legacy direct DB access"), 1, 0.67, 0)
            GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_NEEDS_MIGRATION"]) or "Needs migration to cache service", 0.7, 0.7, 0.7)
        end
        
        -- Show current DB version
        local WarbandNexus = ns.WarbandNexus
        if WarbandNexus and WarbandNexus.db then
            local dbVersion = WarbandNexus.db.global.dataVersion or 1
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(((ns.L and ns.L["GLOBAL_DB_VERSION"]) or "Global DB Version:") .. " " .. dbVersion, 0.5, 0.5, 1)
        end
        
        GameTooltip:Show()
    end)
    badge:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return badge
end

-- Exports MUST live in this file: both functions are file-locals here. The structure
-- split moved these export lines into SharedWidgets_Factory.lua, where the names
-- resolved to nil globals — every tab using the badge/header layout errored on draw.
ns.UI_CreateCardHeaderLayout = CreateCardHeaderLayout
ns.UI_CreateDBVersionBadge = CreateDBVersionBadge

-- NOTE: CreateEditBox implementation moved to line 4816 (Factory pattern wrapper)
-- This duplicate implementation was removed to avoid confusion

-- LOADING STATE WIDGETS (Standardized Progress Indicator)

---Create standardized loading state card with animated spinner and progress bar
---@return number newYOffset - New Y offset after card
function UI_CreateLoadingStateCard(parent, yOffset, loadingState, title)
    if not loadingState or not loadingState.isLoading then
        return yOffset
    end
    
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    local CARD_H = 108
    local loadingCard = CreateCard(parent, CARD_H)
    ApplyStandardCardElevatedChrome(loadingCard)
    loadingCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    loadingCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Animated spinner
    local spinnerFrame = ns.UI_CreateIcon(loadingCard, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
    spinnerFrame:SetPoint("LEFT", 20, 0)
    spinnerFrame:Show()
    local spinner = spinnerFrame.texture
    
    -- Animate rotation on spinner only (avoid clobbering loadingCard OnUpdate); stop when hidden.
    local rotation = 0
    spinnerFrame:SetScript("OnUpdate", function(_, elapsed)
        rotation = rotation + (elapsed * 270)
        if spinner then
            spinner:SetRotation(math.rad(rotation))
        end
    end)
    loadingCard:HookScript("OnHide", function()
        spinnerFrame:SetScript("OnUpdate", nil)
        loadingCard:SetScript("OnUpdate", nil)
    end)
    
    -- Loading title
    local FontManager = ns.FontManager
    local loadingText = FontManager:CreateFontString(loadingCard, UIFontRole("loadingCardTitle"), "OVERLAY")
    loadingText:SetPoint("LEFT", spinner, "RIGHT", 15, 10)
    loadingText:SetText("|cff00ccff" .. (title or ((ns.L and ns.L["LOADING"]) or "Loading...")) .. "|r")
    
    -- Progress indicator
    local progressText = FontManager:CreateFontString(loadingCard, UIFontRole("loadingCardProgress"), "OVERLAY")
    progressText:SetPoint("LEFT", spinner, "RIGHT", 15, -8)

    local BAR_W = 200
    if parent and parent.GetWidth then
        local pw = parent:GetWidth() or 0
        local w = pw - (SIDE_MARGIN * 2) - 20 - 40 - 15 - 20
        BAR_W = math.min(280, math.max(120, w))
    end
    local barBg = loadingCard:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, 5)
    barBg:SetPoint("TOPLEFT", progressText, "BOTTOMLEFT", 0, -6)
    local barTrack = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
    barBg:SetColorTexture(barTrack[1], barTrack[2], barTrack[3], barTrack[4] or 1)
    local barFill = loadingCard:CreateTexture(nil, "OVERLAY")
    barFill:SetHeight(5)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    barFill:SetWidth(1)
    local acc = COLORS and COLORS.accent or {0.2, 0.6, 1}
    barFill:SetColorTexture(acc[1], acc[2], acc[3], 0.9)
    
    local function ReadLoadingPercent(state)
        if not state then return 0 end
        local lp = state.loadingProgress
        local sp = state.scanProgress
        local v = lp or sp or 0
        if type(v) ~= "number" then return 0 end
        if v ~= v then return 0 end
        return math.min(100, math.max(0, math.floor(v + 0.5)))
    end
    
    local function ApplyProgressVisual()
        local currentStage = loadingState.currentStage or ((ns.L and ns.L["PREPARING"]) or "Preparing")
        local progress = ReadLoadingPercent(loadingState)
        progressText:SetText(string.format("|cff888888%s - %d%%|r", currentStage, progress))
        local bw = barBg:GetWidth()
        if bw and bw > 0 then
            barFill:SetWidth(math.max(1, bw * (progress / 100)))
        end
    end
    ApplyProgressVisual()
    
    -- Hint text
    local hintText = FontManager:CreateFontString(loadingCard, UIFontRole("loadingCardHint"), "OVERLAY")
    hintText:SetPoint("TOPLEFT", barBg, "BOTTOMLEFT", 0, -6)
    hintText:SetPoint("RIGHT", loadingCard, "RIGHT", -16, 0)
    ns.UI_SetTextColorRole(hintText, "Muted")
    hintText:SetText((ns.L and ns.L["PLEASE_WAIT"]) or "Please wait...")
    
    loadingCard:SetScript("OnUpdate", function()
        if not loadingState.isLoading then
            loadingCard:SetScript("OnUpdate", nil)
            return
        end
        ApplyProgressVisual()
    end)
    
    loadingCard:Show()
    
    return yOffset + CARD_H + 8
end

---Create standardized error state card
---@return number newYOffset - New Y offset after card
function UI_CreateErrorStateCard(parent, yOffset, errorMessage)
    if not errorMessage or errorMessage == "" then
        return yOffset
    end
    
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    local errorCard = CreateCard(parent, 60)
    ApplyStandardCardElevatedChrome(errorCard)
    errorCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    errorCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Warning icon
    local warningIconFrame = ns.UI_CreateIcon(errorCard, "services-icon-warning", 24, true, nil, true)
    warningIconFrame:SetPoint("LEFT", 20, 0)
    warningIconFrame:Show()
    
    -- Error message
    local FontManager = ns.FontManager
    local errorText = FontManager:CreateFontString(errorCard, UIFontRole("errorCardBody"), "OVERLAY")
    errorText:SetPoint("LEFT", warningIconFrame, "RIGHT", 10, 0)
    local warnR, warnG, warnB, warnA = GetSemanticGoldColor()
    errorText:SetTextColor(warnR, warnG, warnB, warnA)
    errorText:SetText(ns.UI_GetSemanticGoldHex() .. errorMessage .. "|r")
    
    errorCard:Show()
    
    return yOffset + 70
end

---Create inline loading spinner (for small widgets like gold display)
---@return Frame spinnerFrame - Spinner frame for cleanup
function UI_CreateInlineLoadingSpinner(parent, anchorFrame, anchorPoint, xOffset, yOffset, size)
    size = size or 16
    
    local spinnerFrame = ns.UI_CreateIcon(parent, "auctionhouse-ui-loadingspinner", size, true, nil, true)
    spinnerFrame:SetPoint(anchorPoint, anchorFrame, anchorPoint, xOffset, yOffset)
    spinnerFrame:Show()
    
    -- Animate rotation
    local rotation = 0
    spinnerFrame:SetScript("OnUpdate", function(_, elapsed)
        rotation = rotation + (elapsed * 270)
        if spinnerFrame and spinnerFrame.texture then
            spinnerFrame.texture:SetRotation(math.rad(rotation))
        end
    end)
    
    return spinnerFrame
end

--- Create a persistent loading state panel that fills its parent.
--- Reusable: call panel:ShowLoading(title, progress, stage) / panel:HideLoading().
--- Visual style matches UI_CreateLoadingStateCard for consistency.
---@return Frame panel - Panel with :ShowLoading() / :HideLoading()
local function UI_CreateLoadingStatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetAllPoints(parent)
    ApplyStandardCardElevatedChrome(panel)
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    panel:Hide()

    -- Spinner (same atlas as transient card)
    local spinnerFrame = ns.UI_CreateIcon(panel, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
    spinnerFrame:SetPoint("CENTER", 0, 20)
    spinnerFrame:Show()
    local spinnerTex = spinnerFrame.texture
    panel._spinnerTex = spinnerTex

    local rotation = 0
    panel:SetScript("OnUpdate", function(_, elapsed)
        rotation = rotation + (elapsed * 270)
        if spinnerTex then spinnerTex:SetRotation(math.rad(rotation)) end
    end)

    -- Title
    local FM = ns.FontManager
    local titleText = FM:CreateFontString(panel, FM:GetFontRole("loadingPanelTitle"), "OVERLAY")
    titleText:SetPoint("TOP", spinnerFrame, "BOTTOM", 0, -10)
    titleText:SetJustifyH("CENTER")
    panel._titleText = titleText

    -- Progress text (stage + %)
    local progressText = FM:CreateFontString(panel, FM:GetFontRole("loadingPanelProgress"), "OVERLAY")
    progressText:SetPoint("TOP", titleText, "BOTTOM", 0, -6)
    progressText:SetJustifyH("CENTER")
    ns.UI_SetTextColorRole(progressText, "Dim")
    panel._progressText = progressText

    -- Progress bar
    local BAR_W = 200
    local barBg = panel:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, 4)
    barBg:SetPoint("TOP", progressText, "BOTTOM", 0, -8)
    local panelBarTrack = COLORS.surfaceRowOdd or COLORS.bgLight or COLORS.bg
    barBg:SetColorTexture(panelBarTrack[1], panelBarTrack[2], panelBarTrack[3], panelBarTrack[4] or 1)
    panel._barBg = barBg

    local barFill = panel:CreateTexture(nil, "OVERLAY")
    barFill:SetHeight(4)
    barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    barFill:SetWidth(1)
    barFill:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    panel._barFill = barFill

    function panel:ShowLoading(title, progress, stage)
        local t = title or ((ns.L and ns.L["LOADING"]) or "Loading...")
        self._titleText:SetText("|cff00ccff" .. t .. "|r")
        local pct = math.min(100, math.max(0, progress or 0))
        local s = stage or ""
        if s ~= "" then
            self._progressText:SetText(string.format("%s - %d%%", s, pct))
        else
            self._progressText:SetText(string.format("%d%%", pct))
        end
        local barWidth = self._barBg:GetWidth()
        if barWidth and barWidth > 0 then
            self._barFill:SetWidth(math.max(1, barWidth * (pct / 100)))
        end
        self:Show()
    end

    function panel:HideLoading()
        self:Hide()
    end

    return panel
end

-- Export to namespace
ns.UI_CreateLoadingStateCard = UI_CreateLoadingStateCard
ns.UI_CreateErrorStateCard = UI_CreateErrorStateCard
ns.UI_CreateInlineLoadingSpinner = UI_CreateInlineLoadingSpinner
ns.UI_CreateLoadingStatePanel = UI_CreateLoadingStatePanel

