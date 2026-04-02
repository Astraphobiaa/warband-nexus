--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local FontManager = ns.FontManager

-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

--============================================================================
-- PIXEL PERFECT HELPERS
--============================================================================

-- Cached pixel scale (calculated once per UI load, reused everywhere)
-- Cache for pixel scale (automatically invalidated on scale changes)
local mult = nil

-- Calculate exact pixel size for 1px borders.
-- Uses GetPhysicalScreenSize (reliable since BfA 8.0) and GetEffectiveScale
-- to produce the size of one physical pixel in UIParent coordinate space.
-- NOTE: Defined before event handler to avoid forward-reference errors
local function GetPixelScale(frame)
    local physH = 1080
    if GetPhysicalScreenSize then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then physH = h end
    else
        local resolution = GetCVar("gxWindowedResolution") or "1920x1080"
        local _, h = string.match(resolution, "(%d+)x(%d+)")
        h = tonumber(h)
        if h and h > 0 then physH = h end
    end

    local scaleTarget = frame or UIParent
    local effectiveScale = scaleTarget and scaleTarget.GetEffectiveScale and scaleTarget:GetEffectiveScale() or 1
    if not effectiveScale or effectiveScale <= 0 then effectiveScale = 1 end

    -- Fast path: cache only UIParent scale (most common callsite)
    if not frame or frame == UIParent then
        if mult then return mult end
        mult = 768.0 / (physH * effectiveScale)
        return mult
    end

    -- Frame-specific pixel scale (for custom-scaled frames)
    return 768.0 / (physH * effectiveScale)
end

-- Reset pixel scale cache (manual invalidation if needed)
local function ResetPixelScale()
    mult = nil
end

-- Snap a coordinate value to the nearest physical pixel
-- This prevents sub-pixel positioning that causes blur/jitter
local function PixelSnap(value)
    if not value then return 0 end
    local pixelScale = GetPixelScale()
    -- Formula: Round to nearest pixel boundary
    return math.floor(value / pixelScale + 0.5) * pixelScale
end

-- Event frame to handle UI scale and display changes
local scaleHandler = CreateFrame("Frame")
scaleHandler:RegisterEvent("UI_SCALE_CHANGED")
scaleHandler:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleHandler:SetScript("OnEvent", function(self, event)
    mult = nil  -- Invalidate pixel scale cache
    -- Defer border refresh to next frame to allow scale to settle
    C_Timer.After(0, function()
        if ns.UI_UpdateBorderColor and ns.BORDER_REGISTRY then
            for i = 1, #ns.BORDER_REGISTRY do
                local frame = ns.BORDER_REGISTRY[i]
                if frame and frame.BorderTop then
                    local pixelScale = GetPixelScale(frame)
                    frame.BorderTop:SetHeight(pixelScale)
                    frame.BorderBottom:SetHeight(pixelScale)
                    frame.BorderLeft:ClearAllPoints()
                    frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
                    frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                    frame.BorderLeft:SetWidth(pixelScale)
                    frame.BorderRight:ClearAllPoints()
                    frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
                    frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                    frame.BorderRight:SetWidth(pixelScale)
                end
            end
        end
    end)
end)

--============================================================================
-- COLOR CONSTANTS
--============================================================================

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

-- Master COLORS table (created once, updated in-place — zero allocation on refresh)
local COLORS = {
    bg = {0.06, 0.06, 0.08, 0.98},
    bgLight = {0.10, 0.10, 0.12, 1},
    bgCard = {0.08, 0.08, 0.10, 1},
    border = {0.20, 0.20, 0.25, 1},
    borderLight = {0.30, 0.30, 0.38, 1},
    accent = {0.40, 0.20, 0.58, 1},
    accentDark = {0.28, 0.14, 0.41, 1},
    tabActive = {0.20, 0.12, 0.30, 1},
    tabHover = {0.24, 0.14, 0.35, 1},
    tabInactive = {0.08, 0.08, 0.10, 1},
    gold = {1.00, 0.82, 0.00, 1},
    green = {0.30, 0.90, 0.30, 1},
    red = {0.95, 0.30, 0.30, 1},
    textBright = {1, 1, 1, 1},
    textNormal = {0.85, 0.85, 0.85, 1},
    textDim = {0.55, 0.55, 0.55, 1},
    white = {1, 1, 1, 1},
}

-- Update COLORS in-place from theme (zero allocation)
local function UpdateColorsFromTheme()
    local theme = GetThemeColors()
    COLORS.border[1], COLORS.border[2], COLORS.border[3] = theme.border[1], theme.border[2], theme.border[3]
    COLORS.accent[1], COLORS.accent[2], COLORS.accent[3] = theme.accent[1], theme.accent[2], theme.accent[3]
    COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3] = theme.accentDark[1], theme.accentDark[2], theme.accentDark[3]
    COLORS.tabActive[1], COLORS.tabActive[2], COLORS.tabActive[3] = theme.tabActive[1], theme.tabActive[2], theme.tabActive[3]
    COLORS.tabHover[1], COLORS.tabHover[2], COLORS.tabHover[3] = theme.tabHover[1], theme.tabHover[2], theme.tabHover[3]
end

-- Apply theme colors on initial load
UpdateColorsFromTheme()
ns.UI_COLORS = COLORS -- Export immediately

--============================================================================
-- PLAN UI COLORS (factory-standardized for Plans, WN Plan, Collections achievement UIs)
--============================================================================
ns.PLAN_UI_COLORS = {
    completed = "|cff44ff44",       -- criteria completed (green tick)
    incomplete = "|cffffffff",      -- criteria incomplete
    progressLabel = "|cffffcc00",   -- "Progress:"
    progressFull = "|cff00ff00",    -- 100% progress line
    infoLabel = "|cff88ff88",       -- "Information:", "Description:", "Reward:"
    sourceLabel = "|cff99ccff",     -- "Source:", "Drop:", "Quest:", "Location:"
    tracked = "|cff44ff44",
    notTracked = "|cffffcc00",
    body = "|cffffffff",
    descDim = "|cff888888",         -- card subtitle / secondary text
    completedRgb = {0.27, 1, 0.27},
    incompleteRgb = {1, 1, 1},
}

-- Backward-compatible accessor (returns current COLORS table reference)
local function GetColors()
    return COLORS
end

--============================================================================
-- SPACING CONSTANTS (Standardized across all tabs)
--============================================================================

-- Unified spacing constants (UPPER_CASE standard)
local UI_SPACING = {
    -- Horizontal indentation (levels)
    BASE_INDENT = 15,          -- Base indent unit (15px per level)
    SUBROW_EXTRA_INDENT = 10,  -- Extra indent for sub-rows (total Level 2 = 40px)
    -- Usage: Level 0 = 0px, Level 1 = BASE_INDENT (15px), Level 2 = BASE_INDENT * 2 + SUBROW_EXTRA_INDENT (40px)
    
    -- Margins
    SIDE_MARGIN = 10,          -- Left/right content margin
    TOP_MARGIN = 8,            -- Top content margin
    
    -- Vertical spacing (between elements)
    HEADER_SPACING = 40,       -- Space after headers
    SUBHEADER_SPACING = 40,    -- Space after sub-headers
    ROW_SPACING = 26,          -- Space after rows (26px height + 0px gap for tight layout)
    SECTION_SPACING = 8,       -- Space between sections (expansion/type spacing, smaller than HEADER_SPACING)
    EMPTY_STATE_SPACING = 100, -- Empty state message spacing
    MIN_BOTTOM_SPACING = 20,   -- Minimum bottom padding
    SCROLL_CONTENT_TOP_PADDING = 12,    -- Padding above scroll content (so rows/headers don't touch border)
    SCROLL_CONTENT_BOTTOM_PADDING = 12, -- Padding below scroll content
    SCROLL_BASE_STEP = 28,              -- Base scroll speed in pixels per wheel tick
    SCROLL_SPEED_DEFAULT = 1.0,          -- Default speed multiplier (profile.scrollSpeed)
    AFTER_HEADER = 75,         -- Space after main header
    AFTER_ELEMENT = 8,         -- Space after generic element
    CARD_GAP = 8,              -- Gap between cards
    
    -- Row dimensions
    ROW_HEIGHT = 26,           -- Standard row height
    CHAR_ROW_HEIGHT = 36,      -- Character row height (+20% from 30)
    HEADER_HEIGHT = 32,        -- Collapsible header height
    
    -- Icon standardization
    HEADER_ICON_SIZE = 24,     -- Header icon size (reduced from 28 for better balance)
    ROW_ICON_SIZE = 20,        -- Row icon size (reduced from 22 for better balance)
    ICON_VERTICAL_ALIGN = 0,   -- CENTER vertical alignment offset
    
    -- Row colors (alternating backgrounds)
    ROW_COLOR_EVEN = {0.08, 0.08, 0.10, 1},  -- Even rows (slightly lighter)
    ROW_COLOR_ODD = {0.06, 0.06, 0.08, 1},   -- Odd rows (slightly darker)
    
    -- Backward compatibility aliases (camelCase)
    afterHeader = 75,
    betweenSections = 8,
    betweenRows = 0,
    headerSpacing = 40,
    afterElement = 8,
    cardGap = 8,
    rowHeight = 26,
    charRowHeight = 36,
    headerHeight = 32,
    rowSpacing = 26,
    sideMargin = 10,
    topMargin = 8,
    subHeaderSpacing = 40,
    emptyStateSpacing = 100,
    minBottomSpacing = 20,
    headerIconSize = 24,
    rowIconSize = 20,
    iconVerticalAlign = 0,
    -- Standard scroll bar: Button (top) | Bar | Button (bottom); same everywhere
    SCROLL_BAR_BUTTON_SIZE = 16,
    SCROLL_BAR_WIDTH = 16,
    SCROLLBAR_COLUMN_WIDTH = 22,  -- Width of the column that holds scrollbar (list + detail)
    SCROLL_BASE_STEP = 28,
    SCROLL_SPEED_DEFAULT = 1.0,
}

-- Export to namespace (both names for compatibility)
ns.UI_SPACING = UI_SPACING
ns.UI_LAYOUT = UI_SPACING  -- Alias for backward compatibility

-- Keep old reference
local UI_LAYOUT = UI_SPACING

--============================================================================
-- BUTTON SIZE CONSTANTS
--============================================================================

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

-- Refresh COLORS table from database (in-place, zero allocation)
local function RefreshColors()
    -- Update theme-derived colors in-place
    UpdateColorsFromTheme()
    -- Ensure namespace reference is current
    ns.UI_COLORS = COLORS
    
    -- Safety check (use namespace reference)
    if not ns.BORDER_REGISTRY then
        ns.BORDER_REGISTRY = {}
        return
    end
    
    local accentColor = COLORS.accent
    local accentDarkColor = COLORS.accentDark
    local borderColor = COLORS.border
    local bgColor = COLORS.bg
    local updated = 0
    
    -- Update ALL registered frames (ApplyVisuals 4-texture system)
    for i = #ns.BORDER_REGISTRY, 1, -1 do
        local frame = ns.BORDER_REGISTRY[i]
        
        -- Check if frame still exists and has border textures
        if not frame or not frame.BorderTop then
            table.remove(ns.BORDER_REGISTRY, i)
        else
            -- Get target color based on border type
            local targetColor = (frame._borderType == "accent") and accentColor or borderColor
            local alpha = frame._borderAlpha or 0.6
            
            -- Update 4-texture borders
            frame.BorderTop:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            frame.BorderBottom:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            frame.BorderLeft:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            frame.BorderRight:SetVertexColor(targetColor[1], targetColor[2], targetColor[3], alpha)
            
            -- Update backdrop color (for headers and other frames with backgrounds)
            if frame.SetBackdropColor and frame._bgType then
                local bgTargetColor = (frame._bgType == "accentDark") and accentDarkColor or bgColor
                local bgAlpha = frame._bgAlpha or 1
                frame:SetBackdropColor(bgTargetColor[1], bgTargetColor[2], bgTargetColor[3], bgAlpha)
            end
            
            -- Update thumb texture if exists (scrollbar thumb)
            if frame._thumbTexture then
                frame._thumbTexture:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.9)
            end
            
            -- Update icon texture if exists (scrollbar button icons)
            if frame._iconTexture then
                frame._iconTexture:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 1)
            end
            
            updated = updated + 1
        end
    end
    
    -- Notify NotificationManager about color change
    if WarbandNexus and WarbandNexus.RefreshNotificationColors then
        WarbandNexus:RefreshNotificationColors()
    end
    
    -- Update all accent-colored FontStrings (BEFORE RefreshUI to avoid reload issues)
    if ns.FontManager and ns.FontManager.RefreshAccentColors then
        ns.FontManager:RefreshAccentColors()
    end
    
    -- Update main tab buttons (activeBar highlight and glow) if main frame exists
    if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
        local f = WarbandNexus.UI.mainFrame
        
        if f.tabButtons then
            for tabKey, btn in pairs(f.tabButtons) do
                local isActive = f.currentTab == tabKey
                
                -- Update activeBar (bottom highlight line)
                if btn.activeBar then
                    btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
                end
                
                -- Update glow
                if btn.glow then
                    btn.glow:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], isActive and 0.25 or 0.15)
                end
            end
        end
        
        -- Refresh content to update dynamic elements (moved AFTER RefreshAccentColors)
        if f:IsShown() and WarbandNexus.RefreshUI then
            WarbandNexus:RefreshUI()
        end
    end
end

-- Quality colors (hex)
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

-- Export to namespace
ns.UI_COLORS = COLORS
ns.UI_QUALITY_COLORS = QUALITY_COLORS

--============================================================================
-- FACTORY PATTERN (Service-Oriented Architecture)
--============================================================================
--[[
    Phase 1: Foundation - Factory Pattern Implementation
    
    The Factory pattern centralizes UI component creation and provides:
    - Standardized access to Layout and Theme constants
    - Type-safe widget creation methods
    - Eliminates load-order issues from file-level caching
    
    Architecture:
    - ns.UI.Factory: Main factory object for creating widgets
    - ns.UI.Layout: Runtime-accessible layout constants (replaces UI_SPACING)
    - ns.UI.Theme: Runtime-accessible theme colors (replaces COLORS)
    
    Migration Strategy:
    - New code: Use ns.UI.Factory methods
    - Legacy code: Backward compatible via ns.UI_* exports
]]

-- Initialize Factory namespace
ns.UI = ns.UI or {}
ns.UI.Factory = {}

-- Runtime-accessible constants (fixes scope/load-order bugs)
ns.UI.Layout = UI_SPACING  -- Direct reference (no copy, always current)
ns.UI.Theme = COLORS       -- Direct reference (no copy, always current)

--============================================================================
-- VISUAL SYSTEM (Pixel Perfect 4-Texture Borders)
--============================================================================

-- Registry for all frames with ApplyVisuals (for live color updates)
-- MUST be initialized before any ApplyVisuals calls
-- Store in namespace to persist across all contexts (fixes nil errors)
ns.BORDER_REGISTRY = ns.BORDER_REGISTRY or {}
local BORDER_REGISTRY = ns.BORDER_REGISTRY

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
        -- Heuristic: accentDark backgrounds are warmer/brighter
        local isBgAccent = (bgColor[1] > 0.15 or bgColor[2] > 0.10)
        frame._bgType = isBgAccent and "accentDark" or "bg"
        frame._bgAlpha = bgColor[4] or 1
    else
        frame._bgType = "bg"
        frame._bgAlpha = 1
    end
    
    -- Register frame to namespace registry (prevent duplicates)
    if not frame._borderRegistered then
        frame._borderRegistered = true
        table.insert(ns.BORDER_REGISTRY, frame)
    end
end

-- Export to namespace
ns.UI_ApplyVisuals = ApplyVisuals
ns.UI_ResetPixelScale = ResetPixelScale

--- Apply detail container styling (bg + accent border) using the shared 4-texture border system.
--- Use for Collections right panel (viewer/detail), or any "detail" panel that should match.
---@param frame Frame
function ns.UI_ApplyDetailContainerVisuals(frame)
    if not frame then return end
    local colors = GetColors and GetColors() or COLORS or ns.UI_COLORS
    if not colors or not colors.accent then return end
    ApplyVisuals(frame, {0.08, 0.08, 0.10, 0.95}, {colors.accent[1], colors.accent[2], colors.accent[3], 0.6})
end

-- ResetPixelScale on UI_SCALE_CHANGED is handled by EventManager.OnUIScaleChanged

--[[
    Update border color for an existing frame (Factory Method)
    @param self table - Factory object
    @param frame frame - Frame with borders already created by ApplyVisuals
    @param borderColor table - Border color {r,g,b,a}
]]
function ns.UI.Factory:UpdateBorderColor(frame, borderColor)
    if not frame or not frame.BorderTop then return end
    
    local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
    frame.BorderTop:SetVertexColor(r, g, b, a)
    frame.BorderBottom:SetVertexColor(r, g, b, a)
    frame.BorderLeft:SetVertexColor(r, g, b, a)
    frame.BorderRight:SetVertexColor(r, g, b, a)
end

--[[
    Apply native highlight effect to a frame (Factory Method)
    Uses WoW's built-in SetHighlightTexture - NO manual texture creation
    
    @param self table - Factory object
    @param frame frame - Frame to apply highlight to
    @param color table - RGB color array (default: soft blue {0.4, 0.6, 0.9})
    @param alpha number - Alpha transparency (default: 0.15)
    
    Technical Details:
    - Uses native SetHighlightTexture (zero texture overhead)
    - NO OnEnter/OnLeave scripts needed (native handles it)
    - ADD blend mode for glow effect
    - Pixel snapping enabled to prevent ghosting
    - Works on all frame types (Button, Frame, etc.)
]]
function ns.UI.Factory:ApplyHighlight(frame, color, alpha)
    if not frame or not frame.SetHighlightTexture then return end
    
    -- Default: Soft blue glow
    color = color or {0.4, 0.6, 0.9}
    alpha = alpha or 0.15
    
    -- Set highlight texture (native WoW API)
    frame:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    
    -- Configure highlight properties
    local hl = frame:GetHighlightTexture()
    if hl then
        hl:SetBlendMode("ADD")  -- Glow effect over content
        hl:SetVertexColor(color[1], color[2], color[3], alpha)
        hl:SetDrawLayer("HIGHLIGHT")  -- Top layer
        hl:SetSnapToPixelGrid(true)  -- Prevent ghosting during scrolling
        hl:SetTexelSnappingBias(0)
    end
end

-- Legacy wrapper for UpdateBorderColor
local function UpdateBorderColor(frame, borderColor)
    return ns.UI.Factory:UpdateBorderColor(frame, borderColor)
end

-- Export to namespace
ns.UI_UpdateBorderColor = UpdateBorderColor

--============================================================================
-- COMMON UI FRAME WRAPPERS (Reusable Components)
--============================================================================

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
    local titleText = FontManager:CreateFontString(frame, "body", "OVERLAY")
    titleText:SetPoint("LEFT", icon, "RIGHT", 10, 5)
    titleText:SetPoint("RIGHT", -10, 5)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffcc00" .. title .. "|r")
    
    -- Description
    local descText = FontManager:CreateFontString(frame, "small", "OVERLAY")
    descText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -15)
    descText:SetPoint("RIGHT", -10, 0)
    descText:SetJustifyH("LEFT")
    descText:SetTextColor(1, 1, 1)  -- White
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
    
    local margin = sideMargin or 10
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", margin, -yOffset)
    container:SetPoint("TOPRIGHT", -margin, 0)
    container:SetHeight(1)  -- Minimal initial height, will be set by content renderer
    
    return container
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
    
    local text = FontManager:CreateFontString(bar, "small", "OVERLAY")
    text:SetPoint("LEFT", 10, 0)
    text:SetTextColor(1, 1, 1)  -- White
    
    return bar, text
end

-- Export to namespace
ns.UI_CreateNoticeFrame = CreateNoticeFrame
ns.UI_CreateResultsContainer = CreateResultsContainer
ns.UI_CreateStatsBar = CreateStatsBar

--============================================================================
-- UI COMPONENT FACTORY (Pixel-Perfect Components with Auto-Border)
--============================================================================
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

--[[
    Create a pixel-perfect icon with border
    @param parent frame - Parent frame
    @param texture string/number - Texture path, atlas name, or fileID
    @param size number - Icon size (default 32)
    @param isAtlas boolean - If true, use SetAtlas instead of SetTexture (default false)
    @param borderColor table - Border color {r,g,b,a} (default accent)
    @param noBorder boolean - If true, skip border (default false)
    @return frame - Icon frame with .texture accessible
]]
local function CreateIcon(parent, texture, size, isAtlas, borderColor, noBorder)
    if not parent then return nil end
    
    size = size or 32
    isAtlas = isAtlas or false
    borderColor = borderColor or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    noBorder = noBorder or false
    
    -- Container frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:Hide()  -- HIDE during setup (prevent flickering)
    frame:SetSize(size, size)
    
    -- Apply pixel-perfect border (unless noBorder is true)
    if not noBorder then
        ApplyVisuals(frame, {0.05, 0.05, 0.07, 0.95}, borderColor)
    end
    
    -- Icon texture (inset by 2*pixelScale if border, otherwise fill frame)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    if noBorder then
        tex:SetAllPoints()
    else
        -- Inset by 2 physical pixels to prevent texture bleeding into border
        local inset = GetPixelScale() * 2
        tex:SetPoint("TOPLEFT", inset, -inset)
        tex:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
    
    -- Set texture or atlas
    if texture then
        if isAtlas then
            -- Use atlas (modern WoW UI system)
            local success = pcall(function()
                tex:SetAtlas(texture, false)  -- false = don't use atlas size
            end)
            if not success then
                -- Atlas failed, fallback to question mark texture
                DebugPrint("|cffff0000[WN CreateIcon]|r Atlas '" .. tostring(texture) .. "' failed, using fallback")
                tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        else
            -- Use texture path or fileID
            if type(texture) == "string" then
                tex:SetTexture(texture)
            else
                tex:SetTexture(texture)  -- FileID (number)
            end
            -- Zoom effect (trim ugly edges) - only for textures, not atlas
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    
    -- Anti-flicker optimization
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    
    -- Store texture reference
    frame.texture = tex
    
    -- Caller will Show() when fully setup
    return frame
end

--[[
    Create a layered paragon reputation icon with glow, bag, and optional checkmark
    @param parent Frame - Parent frame
    @param size number - Icon size (default 18)
    @param hasRewardPending boolean - If true, show checkmark overlay
    @return frame - Icon frame with layered textures
]]
local function CreateParagonIcon(parent, size, hasRewardPending)
    if not parent then return nil end
    
    size = size or 18
    
    -- Container frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    -- Ensure frame level is high enough to show glow
    frame:SetFrameLevel(parent:GetFrameLevel() + 5)
    
    -- Layer order: BACKGROUND < BORDER < ARTWORK < OVERLAY
    -- 1. Glow (BACKGROUND layer - behind everything, only if reward pending)
    -- Blizzard uses sublevel -3 and ADD blend mode for glow effects
    local glowTex = nil
    if hasRewardPending then
        glowTex = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
        -- Make glow larger than frame (200% size) to make it more visible
        local glowSize = size * 2.0
        glowTex:SetSize(glowSize, glowSize)
        glowTex:SetPoint("CENTER", frame, "CENTER", 0, 0)
        local glowSuccess = pcall(function()
            glowTex:SetAtlas("ParagonReputation_Glow", false)
        end)
        if not glowSuccess then
            glowTex:Hide()
        else
            -- Apply blend mode for better visibility (like Blizzard does)
            glowTex:SetBlendMode("ADD")
            -- Ensure full alpha for glow
            glowTex:SetAlpha(1.0)
        end
        glowTex:SetSnapToPixelGrid(false)
        glowTex:SetTexelSnappingBias(0)
    end
    frame.glow = glowTex
    
    -- 2. Bag (ARTWORK layer - main icon)
    local bagTex = frame:CreateTexture(nil, "ARTWORK")
    bagTex:SetAllPoints()
    local bagSuccess = pcall(function()
        bagTex:SetAtlas("ParagonReputation_Bag", false)
    end)
    if not bagSuccess then
        -- Fallback to texture
        bagTex:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
        bagTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    bagTex:SetSnapToPixelGrid(false)
    bagTex:SetTexelSnappingBias(0)
    frame.bag = bagTex
    
    -- 3. Checkmark (OVERLAY layer - on top, only if reward pending)
    -- Use same texture as standalone checkmark for consistency
    if hasRewardPending then
        local checkTex = frame:CreateTexture(nil, "OVERLAY")
        checkTex:SetAllPoints()
        -- Use same texture as the standalone checkmark (ReadyCheck-Ready)
        checkTex:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        checkTex:SetSnapToPixelGrid(false)
        checkTex:SetTexelSnappingBias(0)
        frame.checkmark = checkTex
    end
    
    -- Gray out if no reward pending
    if not hasRewardPending then
        bagTex:SetVertexColor(0.5, 0.5, 0.5, 1)
    end
    
    return frame
end

--[[
    Create a pixel-perfect status bar (progress bar) with optional border.
    @param parent frame - Parent frame
    @param width number - Bar width (default 200)
    @param height number - Bar height (default 14)
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default black)
    @param noBorder boolean - If true, no border (for use inside a bordered wrapper)
    @return frame - StatusBar frame
]]
local function CreateStatusBar(parent, width, height, bgColor, borderColor, noBorder)
    if not parent then return nil end

    width = width or 200
    height = height or 14
    bgColor = bgColor or {0.05, 0.05, 0.07, 0.95}
    borderColor = borderColor or {0, 0, 0, 1}
    noBorder = (noBorder == true)

    local frame = CreateFrame("StatusBar", nil, parent, noBorder and "BackdropTemplate" or nil)
    frame:SetSize(width, height)

    if not noBorder then
        ApplyVisuals(frame, bgColor, borderColor)
    elseif frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.95)
    end

    frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local barTexture = frame:GetStatusBarTexture()
    if barTexture then
        barTexture:SetDrawLayer("ARTWORK", 0)
        barTexture:SetSnapToPixelGrid(false)
        barTexture:SetTexelSnappingBias(0)
    end

    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)

    return frame
end

--[[
    Create a pixel-perfect button with border (for rows, cards, etc.)
    @param parent frame - Parent frame
    @param width number - Button width
    @param height number - Button height
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default accent)
    @param noBorder boolean - If true, skip border (default false)
    @return button - Button frame
]]
local function CreateButton(parent, width, height, bgColor, borderColor, noBorder)
    if not parent then return nil end
    
    bgColor = bgColor or {0.05, 0.05, 0.07, 0.95}
    borderColor = borderColor or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    noBorder = noBorder or false
    
    -- Button frame
    local button = CreateFrame("Button", nil, parent)
    if width and height then
        button:SetSize(width, height)
    end
    
    -- Apply pixel-perfect border (unless noBorder is true)
    if not noBorder then
        ApplyVisuals(button, bgColor, borderColor)
    end
    
    return button
end

-- Export factory functions to namespace
ns.UI_CreateIcon = CreateIcon
ns.UI_CreateStatusBar = CreateStatusBar
ns.UI_CreateButton = CreateButton
ns.UI_CreateParagonIcon = CreateParagonIcon

--============================================================================
-- FRAME POOLING SYSTEM (Performance Optimization)
--============================================================================
-- Reuse frames instead of creating new ones on every refresh
-- This dramatically reduces memory churn and GC pressure

local ItemRowPool = {}
local StorageRowPool = {}
local CurrencyRowPool = {}
local CharacterRowPool = {}
local ReputationRowPool = {}

-- Get a character row from pool or create new
local function AcquireCharacterRow(parent)
    local row = table.remove(CharacterRowPool)
    
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "character"
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    row:SetParent(parent)
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return character row to pool
local function ReleaseCharacterRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    
    -- Note: Child elements (favButton, etc.) are kept and reused
    
    table.insert(CharacterRowPool, row)
end

-- Get a reputation row from pool or create new
local function AcquireReputationRow(parent, width, rowHeight)
    local row = table.remove(ReputationRowPool)

    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "reputation"

        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end

    row:SetParent(parent)
    if width and rowHeight then
        row:SetSize(math.max(1, width), math.max(1, rowHeight))
    end
    row:Show()

    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return reputation row to pool
local function ReleaseReputationRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    
    table.insert(ReputationRowPool, row)
end

-- Get a currency row from pool or create new
local function AcquireCurrencyRow(parent, width, rowHeight)
    local row = table.remove(CurrencyRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- No background
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.ROW_ICON_SIZE
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 15, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.nameText:SetPoint("LEFT", 43, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        
        -- Amount text
        row.amountText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.amountText:SetPoint("RIGHT", -10, 0)
        row.amountText:SetWidth(150)
        row.amountText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "currency"  -- Mark as CurrencyRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- CRITICAL: Always set parent when acquiring from pool
    row:SetParent(parent)
    row:SetSize(math.max(1, width or 200), math.max(1, rowHeight or 26))
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return currency row to pool
local function ReleaseCurrencyRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    
    -- Reset icon
    if row.icon then
        row.icon:SetTexture(nil)
        row.icon:SetAlpha(1)
    end
    
    -- Reset texts
    if row.nameText then
        row.nameText:SetText("")
        row.nameText:SetTextColor(1, 1, 1)
    end
    
    if row.amountText then
        row.amountText:SetText("")
        row.amountText:SetTextColor(1, 1, 1)
    end
    
    -- Reset badge text (for Show All mode)
    if row.badgeText then
        row.badgeText:SetText("")
        row.badgeText:Hide()
    end
    
    -- Reset background removed (no backdrop)
    
    table.insert(CurrencyRowPool, row)
end

-- Get an item row from pool or create new
local function AcquireItemRow(parent, width, rowHeight)
    local row = table.remove(ItemRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        -- Anti-flicker optimization
        row.bg:SetSnapToPixelGrid(false)
        row.bg:SetTexelSnappingBias(0)
        
        -- Quantity text (left)
        row.qtyText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.ROW_ICON_SIZE
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 70, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        
        -- Location text
        row.locationText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(0)  -- Auto-width (no truncation)
        row.locationText:SetJustifyH("RIGHT")
        row.locationText:SetWordWrap(false)
        row.locationText:SetNonSpaceWrap(false)
        row.locationText:SetMaxLines(1)

        row.isPooled = true
        row.rowType = "item"  -- Mark as ItemRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- No border for items rows
    row:SetParent(parent)
    row:SetSize(math.max(1, width or 200), math.max(1, rowHeight or 26))
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return item row to pool
local function ReleaseItemRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    
    table.insert(ItemRowPool, row)
end

-- Get storage row from pool (updated to match Items tab style)
local function AcquireStorageRow(parent, width, rowHeight)
    local row = table.remove(StorageRowPool)
    
    if not row then
        -- Create new button with all children (Button for hover effects)
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        -- Anti-flicker optimization
        row.bg:SetSnapToPixelGrid(false)
        row.bg:SetTexelSnappingBias(0)
        
        -- Quantity text (left)
        row.qtyText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.ROW_ICON_SIZE
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 70, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        
        -- Location text
        row.locationText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(0)  -- Auto-width (no truncation)
        row.locationText:SetJustifyH("RIGHT")
        row.locationText:SetWordWrap(false)
        row.locationText:SetNonSpaceWrap(false)
        row.locationText:SetMaxLines(1)
        
        row.isPooled = true
        row.rowType = "storage"  -- Mark as StorageRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- No border for storage rows
    
    row:SetParent(parent)
    row:SetSize(math.max(1, width or 200), math.max(1, rowHeight or 26))
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return storage row to pool
local function ReleaseStorageRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    
    table.insert(StorageRowPool, row)
end

-- Release all pooled children of a frame (and hide non-pooled ones)
local function ReleaseAllPooledChildren(parent)
    local children = {parent:GetChildren()}  -- Reuse table, don't create new one each iteration
    for i, child in pairs(children) do
        if child.isPooled and child.rowType then
            -- Use rowType to determine which pool to release to
            if child.rowType == "item" then
                ReleaseItemRow(child)
            elseif child.rowType == "storage" then
                ReleaseStorageRow(child)
            elseif child.rowType == "currency" then
                ReleaseCurrencyRow(child)
            elseif child.rowType == "character" then
                ReleaseCharacterRow(child)
            elseif child.rowType == "reputation" then
                ReleaseReputationRow(child)
            end
        else
            -- Non-pooled frame (like headers, cards, etc.)
            -- Skip persistent row elements (reorderButtons, deleteBtn, etc.)
            -- These are managed by their parent row and should not be hidden here
            -- ALSO skip emptyStateContainer - it's managed by DrawEmptyState
            if not child.isPersistentRowElement and child ~= parent.emptyStateContainer then
                pcall(function()
                    child:Hide()
                    child:ClearAllPoints()
                end)
            end
            
            -- Clear scripts only for widgets that support them
            -- Use HasScript to check if the widget actually supports the script type
            if child.SetScript and child.HasScript then
                local childType = child:GetObjectType()
                -- Only clear scripts that the widget actually supports
                if child:HasScript("OnClick") then
                    local success = pcall(function() child:SetScript("OnClick", nil) end)
                    if not success then
                        DebugPrint("|cffff0000WN DEBUG: Failed to clear OnClick on", childType, "at index", i, "|r")
                    end
                end
                if child:HasScript("OnEnter") then
                    pcall(function() child:SetScript("OnEnter", nil) end)
                end
                if child:HasScript("OnLeave") then
                    pcall(function() child:SetScript("OnLeave", nil) end)
                end
                if child:HasScript("OnMouseDown") then
                    pcall(function() child:SetScript("OnMouseDown", nil) end)
                end
                if child:HasScript("OnMouseUp") then
                    pcall(function() child:SetScript("OnMouseUp", nil) end)
                end
            end
        end
    end
end

--============================================================================
-- UI HELPER FUNCTIONS
--============================================================================

-- Get quality color as hex string
local function GetQualityHex(quality)
    return QUALITY_COLORS[quality] or "ffffff"
end

-- Get accent color as hex string
local function GetAccentHexColor()
    local c = COLORS.accent
    return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Create a card frame (common UI element)
local function CreateCard(parent, height)
    if not parent then return nil end
    local card = CreateFrame("Frame", nil, parent)
    card:Hide()  -- HIDE during setup (prevent flickering)
    
    card:SetHeight(height or 100)
    
    -- Apply pixel-perfect visuals with accent border (4-texture sandwich method)
    local accentColor = COLORS.accent
    ApplyVisuals(card, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    
    -- Caller will Show() when fully setup
    return card
end

-- Format gold amount with separators and icon (legacy - simple gold display)
local function FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return goldStr .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end

--[[
    Format number with thousand separators (e.g., 1.234.567)
    @param number number - Number to format
    @return string - Formatted number string with dots as thousand separators
]]
local function FormatNumber(number)
    if not number or number == 0 then return "0" end
    
    -- Convert to string and handle negative numbers
    local formatted = tostring(math.floor(number))
    local negative = false
    
    if string.sub(formatted, 1, 1) == "-" then
        negative = true
        formatted = string.sub(formatted, 2)
    end
    
    -- Add thousand separators (dots for Turkish locale)
    local k
    while true do
        formatted, k = string.gsub(formatted, "^(%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    
    -- Re-add negative sign if needed
    if negative then
        formatted = "-" .. formatted
    end
    
    return formatted
end

--[[
    Format all numbers in text with thousand separators (e.g., "Get 50000 kills" -> "Get 50.000 kills")
    @param text string - Text containing numbers
    @return string - Text with all numbers formatted
]]
local function FormatTextNumbers(text)
    if not text or text == "" then return text end
    
    -- Find all numbers (4+ digits) and format them
    -- Pattern matches whole numbers not already formatted (no dots inside)
    local result = text
    
    -- Process numbers in descending order of length to avoid partial replacements
    local numbers = {}
    for num in string.gmatch(text, "%d%d%d%d+") do
        -- Check if number is already formatted (contains dots)
        local alreadyFormatted = false
        local numStart, numEnd = string.find(result, num, 1, true)
        if numStart and numStart > 1 then
            -- Check if there's a dot before this number
            if string.sub(result, numStart - 1, numStart - 1) == "." then
                alreadyFormatted = true
            end
        end
        
        if not alreadyFormatted then
            table.insert(numbers, {value = num, length = #num})
        end
    end
    
    -- Sort by length (descending) to replace longer numbers first
    table.sort(numbers, function(a, b) return a.length > b.length end)
    
    -- Replace each number with its formatted version
    for _, numData in ipairs(numbers) do
        local formatted = FormatNumber(tonumber(numData.value))
        -- Use pattern to match whole number (not part of a longer number)
        result = string.gsub(result, "(%D)" .. numData.value .. "(%D)", "%1" .. formatted .. "%2")
        result = string.gsub(result, "^" .. numData.value .. "(%D)", formatted .. "%1")
        result = string.gsub(result, "(%D)" .. numData.value .. "$", "%1" .. formatted)
        result = string.gsub(result, "^" .. numData.value .. "$", formatted)
    end
    
    return result
end

--[[
    Format money with gold, silver, and copper
    @param copper number - Total copper amount
    @param iconSize number - Icon size (optional, default 14)
    @param showZero boolean - Show zero values (optional, default false)
    @return string - Formatted money string with colors and icons
]]
local function FormatMoney(copper, iconSize, showZero)
    -- Validate and sanitize inputs
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 14
    -- Clamp iconSize to safe range to prevent integer overflow in texture rendering
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end
    showZero = showZero or false
    
    -- Calculate gold, silver, copper with explicit floor operations
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = math.floor(copper % 100)
    
    -- Build formatted string
    local parts = {}
    
    -- Gold (yellow/golden)
    if gold > 0 or showZero then
        -- Add thousand separators for gold (dots for Turkish locale)
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
            if k == 0 then break end
        end
        table.insert(parts, string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:0:0|t", goldStr, iconSize, iconSize))
    end
    
    -- Silver (silver/gray) - Only pad if gold exists
    if silver > 0 or (showZero and gold > 0) then
        local fmt = (gold > 0) and "%02d" or "%d"
        table.insert(parts, string.format("|cffc7c7cf" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:0:0|t", silver, iconSize, iconSize))
    end
    
    -- Copper (bronze/copper) - Only pad if silver or gold exists
    if copperAmount > 0 or showZero or (gold == 0 and silver == 0) then
        local fmt = (gold > 0 or silver > 0) and "%02d" or "%d"
        table.insert(parts, string.format("|cffeda55f" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:0:0|t", copperAmount, iconSize, iconSize))
    end
    
    return table.concat(parts, " ")
end

-- Create collapsible header with expand/collapse button (NO pooling - headers are few)
-- noCategoryIcon: when true, skip category icon (e.g. PvE character headers use favorite star only)
local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture, isAtlas, indentLevel, noCategoryIcon)
    -- Support for nested headers (indentLevel: 0 = root, 1 = child, etc.)
    indentLevel = indentLevel or 0
    local indent = indentLevel * UI_LAYOUT.BASE_INDENT
    
    -- Create new header (no pooling for headers - they're infrequent and context-specific)
    -- Use max(1,...) so layout never gets 0/negative width when parent not yet laid out
    local parentW = (parent and parent:GetWidth()) or 0
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(math.max(1, parentW - 20 - indent), 32)
    
    -- Apply pixel-perfect visuals with accent border
    local accentColor = COLORS.accent
    ApplyVisuals(header, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    
    -- Expand/Collapse icon (atlas-based arrows) - STANDARDIZED SIZE
    local expandIcon = header:CreateTexture(nil, "ARTWORK")
    local expandIconSize = 20  -- Standardized: 20x20px for all headers
    expandIcon:SetSize(expandIconSize, expandIconSize)
    expandIcon:SetPoint("LEFT", 12 + indent, 0)
    
    -- Use WoW's action bar arrow atlases (false = use our SetSize, not atlas default)
    if isExpanded then
        expandIcon:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", false)  -- Collapse: up arrow
    else
        expandIcon:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", false)  -- Expand: down arrow
    end
    -- Dynamic theme color tint
    local iconTint = COLORS.accent
    expandIcon:SetVertexColor(iconTint[1] * 1.5, iconTint[2] * 1.5, iconTint[3] * 1.5)
    -- Anti-flicker optimization
    expandIcon:SetSnapToPixelGrid(false)
    expandIcon:SetTexelSnappingBias(0)
    
    local textAnchor = expandIcon
    local textOffset = 12  -- Increased spacing between icon and text
    
    -- Category icon: skip when noCategoryIcon (e.g. PvE uses favorite star in that slot)
    if noCategoryIcon then
        iconTexture = nil
    elseif not iconTexture or iconTexture == "" then
        iconTexture = isAtlas and "icons_64x64_important" or "Interface\\Icons\\INV_Misc_Coin_01"
    end
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = header:CreateTexture(nil, "ARTWORK")
        local iconSize = (UI_LAYOUT and UI_LAYOUT.HEADER_ICON_SIZE) or 24
        categoryIcon:SetSize(iconSize, iconSize)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
        
        -- Use atlas only (isAtlas=true from Collections); texture path fallback for legacy callers
        if isAtlas then
            local ok = pcall(categoryIcon.SetAtlas, categoryIcon, iconTexture, false)
            if not ok then
                categoryIcon:SetAtlas("icons_64x64_important", false)
            end
            categoryIcon:Show()
        else
            -- iconTexture: string path veya number (fileID); WoW ikisini de kabul eder
            categoryIcon:SetTexture(iconTexture)
            if type(iconTexture) == "string" then
                categoryIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            categoryIcon:Show()
        end
        -- Anti-flicker optimization
        categoryIcon:SetSnapToPixelGrid(false)
        categoryIcon:SetTexelSnappingBias(0)
        
        textAnchor = categoryIcon
        textOffset = 12  -- Increased spacing between icon and text
    end
    
    -- Header text
    local headerText = FontManager:CreateFontString(header, "body", "OVERLAY")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetText(text)
    headerText:SetTextColor(1, 1, 1)  -- White
    
    -- Click handler
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        -- Update icon atlas (false = maintain our standardized size)
        if isExpanded then
            expandIcon:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", false)  -- Collapse: up arrow
        else
            expandIcon:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", false)  -- Expand: down arrow
        end
        onToggle(isExpanded)
    end)
    
    -- Apply highlight effect
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(header)
    end
    
    return header, expandIcon, categoryIcon, headerText
end

-- Get item type name from class ID
local function GetItemTypeName(classID)
    local typeName = GetItemClassInfo(classID)
    return typeName or "Other"
end

-- Get item class ID from item ID
local function GetItemClassID(itemID)
    if not itemID then return 15 end -- Miscellaneous
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID or 15
end

-- Get icon texture for item type
local function GetTypeIcon(classID)
    local icons = {
        [0] = "Interface\\Icons\\INV_Potion_51",          -- Consumable (Potion)
        [1] = "Interface\\Icons\\INV_Box_02",             -- Container
        [2] = "Interface\\Icons\\INV_Sword_27",           -- Weapon
        [3] = "Interface\\Icons\\INV_Misc_Gem_01",        -- Gem
        [4] = "Interface\\Icons\\INV_Chest_Cloth_07",     -- Armor
        [5] = "Interface\\Icons\\INV_Enchant_DustArcane", -- Reagent
        [6] = "Interface\\Icons\\INV_Ammo_Arrow_02",      -- Projectile
        [7] = "Interface\\Icons\\Trade_Engineering",      -- Trade Goods
        [8] = "Interface\\Icons\\INV_Misc_EnchantedScroll", -- Item Enhancement
        [9] = "Interface\\Icons\\INV_Scroll_04",          -- Recipe
        [12] = "Interface\\Icons\\INV_Misc_Key_03",       -- Quest (Key icon)
        [15] = "Interface\\Icons\\INV_Misc_Gear_01",      -- Miscellaneous
        [16] = "Interface\\Icons\\INV_Inscription_Tradeskill01", -- Glyph
        [17] = "Interface\\Icons\\PetJournalPortrait",    -- Battlepet
        [18] = "Interface\\Icons\\WoW_Token01",           -- WoW Token
    }
    return icons[classID] or "Interface\\Icons\\INV_Misc_Gear_01"
end

--============================================================================
-- CHARACTER ICON HELPERS (Faction, Race, Class)
--============================================================================

--[[
    Get faction icon texture path
    @param faction string - "Alliance", "Horde", or "Neutral"
    @return string - Texture path
]]
local function GetFactionIcon(faction)
    if faction == "Alliance" then
        return "Interface\\FriendsFrame\\PlusManz-Alliance"
    elseif faction == "Horde" then
        return "Interface\\FriendsFrame\\PlusManz-Horde"
    else
        -- Neutral (Pandaren starting zone or unknown)
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    end
end

--[[
    Get race-gender icon atlas name
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female)
    @return string - Atlas name
]]
local function GetRaceGenderAtlas(raceFile, gender)
    if not raceFile then
        return "shop-icon-housing-characters-up"
    end
    
    -- Map race file names to atlas names
    local raceMap = {
        ["BloodElf"] = "bloodelf",
        ["DarkIronDwarf"] = "darkirondwarf",
        ["Dracthyr"] = "dracthyrvisage",  -- Dracthyr uses visage form
        ["Draenei"] = "draenei",
        ["Dwarf"] = "dwarf",
        ["Earthen"] = "earthen",
        ["Haranir"] = "haranir",
        ["Harronir"] = "haranir",  -- API returns raceFile "Harronir" (clientFileString)
        ["Gnome"] = "gnome",
        ["Goblin"] = "goblin",
        ["HighmountainTauren"] = "highmountain",
        ["Human"] = "human",
        ["KulTiran"] = "kultiran",
        ["LightforgedDraenei"] = "lightforged",
        ["MagharOrc"] = "magharorc",
        ["Mechagnome"] = "mechagnome",
        ["Nightborne"] = "nightborne",
        ["NightElf"] = "nightelf",
        ["Orc"] = "orc",
        ["Pandaren"] = "pandaren",
        ["Tauren"] = "tauren",
        ["Troll"] = "troll",
        ["Scourge"] = "undead",  -- Undead is "Scourge" in API
        ["Worgen"] = "worgen",
        ["ZandalariTroll"] = "zandalari",
        ["VoidElf"] = "voidelf",
        ["Vulpera"] = "vulpera",
    }
    
    local atlasRace = raceMap[raceFile]
    if not atlasRace then
        return "shop-icon-housing-characters-up"  -- Fallback
    end
    
    local genderStr = (gender == 3) and "female" or "male"
    
    return string.format("raceicon128-%s-%s", atlasRace, genderStr)
end

--[[
    Get race icon - NOW RETURNS ATLAS (not texture path)
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @return string - Atlas name
]]
local function GetRaceIcon(raceFile, gender)
    -- NEW: Use atlas system with gender support
    return GetRaceGenderAtlas(raceFile, gender or 2)  -- Default to male if not provided
end

--[[
    Create faction icon on a frame
    @param parent frame - Parent frame
    @param faction string - "Alliance", "Horde", "Neutral"
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateFactionIcon(parent, faction, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetFactionIcon(faction))
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

--[[
    Create race icon on a frame (NEW: Auto-uses race-gender atlases)
    @param parent frame - Parent frame
    @param raceFile string - English race name
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateRaceIcon(parent, raceFile, gender, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 28, size or 28)
    icon:SetPoint(point, x, y)
    
    -- Always use atlas system
    local atlasName = GetRaceIcon(raceFile, gender)  -- GetRaceIcon now returns atlas name
    icon:SetAtlas(atlasName, false)  -- false = don't use atlas size (we set it manually)
    
    -- Circular mask to hide grey corners on race atlas icons
    local mask = parent:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    icon._mask = mask  -- Store reference for cleanup
    
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return icon
end

-- Export to namespace
ns.UI_GetFactionIcon = GetFactionIcon
ns.UI_GetRaceIcon = GetRaceIcon
ns.UI_GetRaceGenderAtlas = GetRaceGenderAtlas
ns.UI_CreateFactionIcon = CreateFactionIcon
ns.UI_CreateRaceIcon = CreateRaceIcon

-- ============================================================================
-- HEADER ICON SYSTEM (Standardized icon+border for all tab headers)
-- ============================================================================

-- Centralized icon mapping for all tabs
local TAB_HEADER_ICONS = {
    characters = "poi-town",
    items = "Banker",
    storage = "VignetteLoot",
    plans = "poi-islands-table",
    currency = "Auctioneer",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    statistics = "racing",
    collections = "PetJournalPortrait",
}

-- Centralized size configuration
local HEADER_ICON_SIZE = 41      -- Icon size
local HEADER_BORDER_SIZE = 51    -- Border size
local HEADER_ICON_XOFFSET = 18   -- X position
local HEADER_ICON_YOFFSET = 0    -- Y position

-- Export icon mapping for external use
ns.UI_GetTabIcon = function(tabName)
    return TAB_HEADER_ICONS[tabName] or "shop-icon-housing-characters-up"
end

-- Export size configuration
ns.UI_GetHeaderIconSize = function()
    return HEADER_ICON_SIZE, HEADER_BORDER_SIZE, HEADER_ICON_XOFFSET, HEADER_ICON_YOFFSET
end

--[[
    Create a standardized header icon with character-style ring border
    This creates the same icon+border style used in "Your Characters" and "Current Character"
    Border color adapts to theme accent color
    @param parent frame - Parent frame (typically a card/header)
    @param atlasName string - Atlas name for the inner icon (e.g., "charactercreate-gendericon-female-selected")
    @param size number - Icon size (default: from HEADER_ICON_SIZE)
    @param borderSize number - Border size (default: from HEADER_BORDER_SIZE)
    @param point string - Anchor point (default: "LEFT")
    @param x number - X offset (default: from HEADER_ICON_XOFFSET)
    @param y number - Y offset (default: from HEADER_ICON_YOFFSET)
    @return table - {icon=texture, border=texture} for further manipulation if needed
]]
local function CreateHeaderIcon(parent, atlasName, size, borderSize, point, x, y)
    size = size or HEADER_ICON_SIZE
    borderSize = borderSize or HEADER_BORDER_SIZE
    point = point or "LEFT"
    x = x or HEADER_ICON_XOFFSET
    y = y or HEADER_ICON_YOFFSET
    
    -- Create container frame for border
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size + 4, size + 4)  -- Slightly larger for border
    container:SetPoint(point, x, y)
    
    -- Apply border with theme color
    ApplyVisuals(container, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Inner icon (inset by 2px for border)
    local icon = container:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetAtlas(atlasName, false)
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return {
        icon = icon,
        border = container  -- Return container as "border" for positioning compatibility
    }
end

-- Export header icon system
ns.UI_CreateHeaderIcon = CreateHeaderIcon

-- ============================================================================
-- CURRENT CHARACTER ICON (Global, easily customizable)
-- ============================================================================

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
ns.UI_GetCurrentCharacterIcon = GetCurrentCharacterIcon

-- ============================================================================
-- CHARACTER-SPECIFIC ICON (Used in headers across multiple tabs)
-- ============================================================================

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
    -- Legacy (all old expansions)
    if headerName:find("Legacy") then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    -- Midnight (12.0) — gece/shadow teması (client'ta var olan path)
    elseif headerName:find("Midnight") then
        return "Interface\\Icons\\Spell_Shadow_Teleport"
    -- Season headers (order matters: Season 1 before generic "Season"); hepsi oyunda var olan path
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
    -- Bilinmeyen header: para birimi ile alakalı genel ikon (soru işareti asla kullanılmaz)
    return "Interface\\Icons\\INV_Misc_Coin_01"
end

-- Export
ns.UI_GetCurrencyHeaderIcon = GetCurrencyHeaderIcon

--[[
    Get class icon texture path (clean, frameless icons)
    @param classFile string - English class name (e.g., "WARRIOR", "MAGE")
    @return string - Texture path
]]
local function GetClassIcon(classFile)
    -- Use class crest icons (clean, no frame)
    local classIcons = {
        ["WARRIOR"] = "Interface\\Icons\\ClassIcon_Warrior",
        ["PALADIN"] = "Interface\\Icons\\ClassIcon_Paladin",
        ["HUNTER"] = "Interface\\Icons\\ClassIcon_Hunter",
        ["ROGUE"] = "Interface\\Icons\\ClassIcon_Rogue",
        ["PRIEST"] = "Interface\\Icons\\ClassIcon_Priest",
        ["DEATHKNIGHT"] = "Interface\\Icons\\ClassIcon_DeathKnight",
        ["SHAMAN"] = "Interface\\Icons\\ClassIcon_Shaman",
        ["MAGE"] = "Interface\\Icons\\ClassIcon_Mage",
        ["WARLOCK"] = "Interface\\Icons\\ClassIcon_Warlock",
        ["MONK"] = "Interface\\Icons\\ClassIcon_Monk",
        ["DRUID"] = "Interface\\Icons\\ClassIcon_Druid",
        ["DEMONHUNTER"] = "Interface\\Icons\\ClassIcon_DemonHunter",
        ["EVOKER"] = "Interface\\Icons\\ClassIcon_Evoker",
    }
    
    return classIcons[classFile] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--[[
    Create class icon on a frame
    @param parent frame - Parent frame
    @param classFile string - English class name (e.g., "WARRIOR")
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateClassIcon(parent, classFile, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetClassIcon(classFile))
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

-- Exports
ns.UI_GetClassIcon = GetClassIcon
ns.UI_CreateClassIcon = CreateClassIcon

--============================================================================
-- FAVORITE ICON HELPERS
--============================================================================

-- Constants
local FAVORITE_ICON_ATLAS = "transmog-icon-favorite"
local FAVORITE_COLOR_ACTIVE = {1, 0.84, 0}  -- Gold
local FAVORITE_COLOR_INACTIVE = {0.5, 0.5, 0.5}  -- Gray

--[[
    Get favorite icon atlas name
    @return string - Atlas name
]]
local function GetFavoriteIconTexture()
    return FAVORITE_ICON_ATLAS
end

--[[
    Apply favorite icon styling
    @param texture texture - Texture object to style
    @param isFavorite boolean - Whether character is favorited
]]
local function StyleFavoriteIcon(texture, isFavorite)
    texture:SetAtlas(FAVORITE_ICON_ATLAS)
    if isFavorite then
        texture:SetDesaturated(false)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_ACTIVE))
    else
        texture:SetDesaturated(true)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_INACTIVE))
    end
end

--[[
    Create complete favorite button with click handler
    @param parent frame - Parent frame
    @param charKey string - Character key (name-realm)
    @param isFavorite boolean - Current favorite status
    @param size number - Button size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @param onToggle function - Callback(charKey) returns new status
    @return button - Created button
]]
local function CreateFavoriteButton(parent, charKey, isFavorite, size, point, x, y, onToggle)
    local iconSize = size * 0.65  -- 65% of button size
    local yOffset = y
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)  -- Keep button hitbox same size
    btn:SetPoint(point, x, yOffset)
    
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER", 0, 0)
    StyleFavoriteIcon(icon, isFavorite)
    
    btn.icon = icon
    btn.charKey = charKey
    btn.isFavorite = isFavorite
    
    btn:SetScript("OnClick", function(self)
        local newStatus = onToggle(self.charKey)
        self.isFavorite = newStatus
        StyleFavoriteIcon(self.icon, newStatus)
    end)
    
    -- Add SetChecked method (mimic CheckButton) for compatibility
    function btn:SetChecked(checked)
        self.isFavorite = checked
        StyleFavoriteIcon(self.icon, checked)
    end
    
    return btn
end

-- Exports
ns.UI_GetFavoriteIconTexture = GetFavoriteIconTexture
ns.UI_StyleFavoriteIcon = StyleFavoriteIcon
ns.UI_CreateFavoriteButton = CreateFavoriteButton

--============================================================================
-- ONLINE INDICATOR HELPERS
--============================================================================

-- Constants
local ONLINE_ICON_TEXTURE = "Interface\\FriendsFrame\\StatusIcon-Online"
local ONLINE_ICON_SIZE = 16

--[[
    Get online indicator texture path
    @return string - Texture path
]]
local function GetOnlineIconTexture()
    return ONLINE_ICON_TEXTURE
end

--[[
    Create online indicator (simple texture, no interaction)
    @param parent frame - Parent frame
    @param size number - Icon size (optional, defaults to 16)
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateOnlineIndicator(parent, size, point, x, y)
    local indicator = parent:CreateTexture(nil, "ARTWORK")
    indicator:SetSize(size or ONLINE_ICON_SIZE, size or ONLINE_ICON_SIZE)
    indicator:SetPoint(point, x, y)
    indicator:SetTexture(ONLINE_ICON_TEXTURE)
    return indicator
end

-- Exports
ns.UI_GetOnlineIconTexture = GetOnlineIconTexture
ns.UI_CreateOnlineIndicator = CreateOnlineIndicator
ns.UI_ONLINE_ICON_SIZE = ONLINE_ICON_SIZE

--============================================================================
-- CHARACTER ROW COLUMN CONFIGURATION
--============================================================================

-- Define column structure (single source of truth)
local CHAR_ROW_COLUMNS = {
    favorite = {
        width = 33,    -- Icon size increased 15% (29 → 33)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 38,    -- 33 + 5
    },
    faction = {
        width = 33,    -- Icon size increased 15% (29 → 33)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 38,    -- 33 + 5
    },
    race = {
        width = 33,    -- Icon size increased 15% (29 → 33)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 38,    -- 33 + 5
    },
    class = {
        width = 33,    -- Icon size increased 15% (29 → 33)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 38,    -- 33 + 5
    },
    name = {
        width = 100,   -- Character name only (realm shown below)
        spacing = 15,  -- Standardized to 15px
        total = 115,   -- 100 + 15
    },
    guild = {
        width = 130,   -- Guild name (single line, right after name)
        spacing = 15,
        total = 145,
    },
    level = {
        width = 82,    -- Level + "Zzz XX.XX%" on two lines (no truncation)
        spacing = 15,  -- Standardized to 15px
        total = 97,    -- 82 + 15
    },
    itemLevel = {
        width = 75,    -- "iLvl 639" centered
        spacing = 15,  -- Standardized to 15px
        total = 90,    -- 75 + 15
    },
    gold = {
        width = 190,   -- "9,999,999g 99s 99c" with icons (increased for icon overflow)
        spacing = 15,  -- Standardized to 15px
        total = 205,   -- 190 + 15
    },
    professions = {
        width = 150,   -- 3 icons × 39px (117) + 2 gaps × 5px (10) + padding = 150px
        spacing = 0,   -- No spacing, tight fit
        total = 150,   -- 150 + 0
    },
    mythicKey = {
        width = 120,   -- Increased from 100 to 120 for more room (text was truncating)
        spacing = 15,  -- Standardized to 15px
        total = 135,   -- 120 + 15
    },
    reorder = {
        width = 44,    -- Two 18px arrow buttons + gap (RIGHT-anchored, compact)
        spacing = 6,
        total = 50,
    },
    lastSeen = {
        width = 60,    -- "Online" / "2d ago" text (RIGHT-anchored, compact)
        spacing = 6,
        total = 66,
    },
    delete = {
        width = 24,    -- Delete icon only (RIGHT-anchored, compact)
        spacing = 6,
        total = 30,
    },
}

--[[
    Calculate column offset from left
    @param columnKey string - Column key (e.g., "name", "level")
    @return number - X offset from left
]]
local function GetColumnOffset(columnKey)
    local offset = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "guild", "level", "itemLevel", "gold", "professions", "mythicKey", "reorder", "lastSeen", "delete"}
    
    for _, key in ipairs(order) do
        if key == columnKey then
            return offset
        end
        offset = offset + CHAR_ROW_COLUMNS[key].total
    end
    
    return offset
end

--[[
    Calculate total width needed for all character row columns
    @return number - Total width (base padding + all columns + right padding)
]]
local function GetCharRowTotalWidth()
    local width = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "guild", "level", "itemLevel", "gold", "professions", "mythicKey", "reorder", "lastSeen", "delete"}
    
    for _, key in ipairs(order) do
        width = width + CHAR_ROW_COLUMNS[key].total
    end
    
    width = width + 10  -- Right padding
    return width
end

--[[
    Create column divider at specified offset
    @param parent frame - Parent frame
    @param xOffset number - X position for divider
    @return texture - Created divider texture
]]
local function CreateCharRowColumnDivider(parent, xOffset)
    local divider = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    divider:SetColorTexture(0.3, 0.3, 0.35, 0.4)
    divider:SetSize(1, 38)
    divider:SetPoint("LEFT", xOffset, 0)
    return divider
end

--============================================================================
-- CHARACTER LIST SORT DROPDOWN (Reusable Icon Button)
--============================================================================

local activeSortDropdownMenu = nil

local function CreateCharacterSortDropdown(parent, sortOptions, dbSortTable, onSortChanged)
    -- Symmetric Filter button: fixed size, icon + text centered as a group
    local buttonHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local btnWidth = 90
    local btn = ns.UI.Factory:CreateButton(parent, btnWidth, buttonHeight, false)

    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
    end

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("RIGHT", btn, "CENTER", -23, 0)  -- icon left of center; text centered
    icon:SetAtlas("uitools-icon-filter")
    icon:SetVertexColor(0.8, 0.8, 0.8)

    local text = btn:CreateFontString(nil, "OVERLAY")
    if ns.FontManager then
        ns.FontManager:ApplyFont(text, "body")
    else
        text:SetFontObject("GameFontNormal")
    end
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText((ns.L and ns.L["FILTER_LABEL"]) or "Filter")
    text:SetTextColor(0.9, 0.9, 0.9)
    icon:SetPoint("RIGHT", text, "LEFT", -6, 0)

    btn:SetScript("OnEnter", function(self)
        icon:SetVertexColor(1, 1, 1)
        text:SetTextColor(1, 1, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.15, 0.15, 0.15, 0.8}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.8})
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((ns.L and ns.L["SORT_BY_LABEL"]) or "Sort By:")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        icon:SetVertexColor(0.8, 0.8, 0.8)
        text:SetTextColor(0.9, 0.9, 0.9)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
        end
        GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function(self)
        if activeSortDropdownMenu and activeSortDropdownMenu:IsShown() then
            activeSortDropdownMenu:Hide()
            activeSortDropdownMenu = nil
            if self._sortClickCatcher then
                self._sortClickCatcher:Hide()
            end
            return
        end
        if activeSortDropdownMenu then
            activeSortDropdownMenu:Hide()
            activeSortDropdownMenu = nil
        end

        local itemCount = #sortOptions
        local itemHeight = 26
        local sideMargin = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or 10
        local radioArea = 8 + 16 + 6  -- left pad + radio width + gap
        local minMenuWidth = math.max(btn:GetWidth(), 120)
        local maxLabelW = 0
        do
            local measure = self:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(measure, "body") else measure:SetFontObject("GameFontNormal") end
            for j = 1, itemCount do
                local label = sortOptions[j].label or ""
                measure:SetText(label)
                local w = measure:GetStringWidth()
                if w and w > maxLabelW then maxLabelW = w end
            end
            measure:SetText("")
        end
        local menuWidth = math.max(minMenuWidth, math.ceil(maxLabelW) + sideMargin * 2 + radioArea + 16)
        local contentHeight = itemCount * itemHeight
        local padding = (UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8
        local menuHeight = contentHeight + padding

        local menu = ns.UI.Factory:CreateContainer(UIParent, menuWidth, menuHeight, true)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        menu:SetClampedToScreen(true)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(menu, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.6, ns.UI_COLORS.accent[2] * 0.6, ns.UI_COLORS.accent[3] * 0.6, 0.8})
        end
        activeSortDropdownMenu = menu

        local currentKey = dbSortTable.key or "manual"
        local btnContentWidth = menuWidth - sideMargin * 2

        for i = 1, itemCount do
            local opt = sortOptions[i]
            local optionBtn = ns.UI.Factory:CreateButton(menu, btnContentWidth, itemHeight, true)
            optionBtn:SetPoint("TOPLEFT", sideMargin, -(i - 1) * itemHeight - 4)

            local isSelected = (currentKey == opt.key)
            local radio = (ns.UI_CreateThemedRadioButton and ns.UI_CreateThemedRadioButton(optionBtn, isSelected)) or nil
            local textX = 10
            if radio then
                radio:SetPoint("LEFT", 8, 0)
                if radio.innerDot then
                    radio.innerDot:SetShown(isSelected)
                end
                textX = 8 + 16 + 6  -- left of radio + radio width + gap
            end

            local optionText = optionBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then
                ns.FontManager:ApplyFont(optionText, "body")
            else
                optionText:SetFontObject("GameFontNormal")
            end
            if radio then
                optionText:SetPoint("LEFT", radio, "RIGHT", 6, 0)
            else
                optionText:SetPoint("LEFT", textX, 0)
            end
            optionText:SetJustifyH("LEFT")
            optionText:SetText(opt.label)
            if isSelected then
                optionText:SetTextColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3])
            else
                optionText:SetTextColor(1, 1, 1)
            end

            if ns.UI_ApplyVisuals then
                ns.UI_ApplyVisuals(optionBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0})
            end
            if ns.UI.Factory.ApplyHighlight then
                ns.UI.Factory:ApplyHighlight(optionBtn)
            end

            optionBtn:SetScript("OnClick", function()
                dbSortTable.key = opt.key
                menu:Hide()
                activeSortDropdownMenu = nil
                if self._sortClickCatcher then
                    self._sortClickCatcher:Hide()
                end
                if onSortChanged then onSortChanged() end
            end)
        end

        menu:Show()

        local clickCatcher = btn._sortClickCatcher
        if not clickCatcher then
            clickCatcher = CreateFrame("Frame", nil, UIParent)
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(menu:GetFrameLevel() - 1)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                if activeSortDropdownMenu then
                    activeSortDropdownMenu:Hide()
                    activeSortDropdownMenu = nil
                end
                clickCatcher:Hide()
            end)
            btn._sortClickCatcher = clickCatcher
        end
        clickCatcher:Show()

        local origHide = menu:GetScript("OnHide")
        menu:SetScript("OnHide", function(m)
            if clickCatcher then clickCatcher:Hide() end
            activeSortDropdownMenu = nil
            if origHide then origHide(m) end
        end)
    end)

    return btn
end

-- Exports
ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowTotalWidth = GetCharRowTotalWidth
ns.UI_CreateCharRowColumnDivider = CreateCharRowColumnDivider
ns.UI_CreateCharacterSortDropdown = CreateCharacterSortDropdown

--============================================================================
-- DRAW EMPTY STATE (Shared by Items and Storage tabs)
--============================================================================

local function DrawEmptyState(addon, parent, startY, isSearch, searchText)
    -- Validate parent frame
    if not parent or not parent.CreateTexture then
        return startY or 0
    end
    
    local yOffset = startY + 50
    
    -- Reuse existing container or create new one
    local container = parent.emptyStateContainer
    if not container then
        container = CreateFrame("Frame", nil, parent)
        container:SetAllPoints(parent)
        parent.emptyStateContainer = container
        
        -- Create icon
        container.icon = container:CreateTexture(nil, "ARTWORK")
        container.icon:SetSize(48, 48)
        container.icon:SetDesaturated(true)
        container.icon:SetAlpha(0.4)
        
        -- Create title
        container.title = FontManager:CreateFontString(container, "title", "OVERLAY")
        
        -- Create description
        container.desc = FontManager:CreateFontString(container, "body", "OVERLAY")
        container.desc:SetTextColor(1, 1, 1)
    end
    
    -- Update icon position and texture
    container.icon:ClearAllPoints()
    container.icon:SetPoint("TOP", 0, -yOffset)
    container.icon:SetTexture(isSearch and "Interface\\Icons\\INV_Misc_Spyglass_02" or "Interface\\Icons\\INV_Misc_Bag_10_Blue")
    yOffset = yOffset + 60
    
    -- Update title position and text
    container.title:ClearAllPoints()
    container.title:SetPoint("TOP", 0, -yOffset)
    container.title:SetText(isSearch and ("|cff666666" .. ((ns.L and ns.L["NO_RESULTS"]) or "No results") .. "|r") or ("|cff666666" .. ((ns.L and ns.L["NO_ITEMS_CACHED_TITLE"]) or "No items cached") .. "|r"))
    yOffset = yOffset + 30
    
    -- Update description position and text
    container.desc:ClearAllPoints()
    container.desc:SetPoint("TOP", 0, -yOffset)
    local displayText = searchText or ""
    
    -- Smart message based on context
    local emptyMessage
    if isSearch then
        -- Use custom message if provided, otherwise generic
        if displayText and displayText ~= "" then
            emptyMessage = string.format((ns.L and ns.L["NO_ITEMS_MATCH"]) or "No items match '%s'", displayText)
        else
            emptyMessage = (ns.L and ns.L["NO_ITEMS_MATCH_GENERIC"]) or "No items match your search"
        end
    else
        -- Check which tab we're on (look at global state)
        local currentSubTab = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "personal"
        if currentSubTab == "warband" then
            emptyMessage = (ns.L and ns.L["ITEMS_WARBAND_BANK_HINT"]) or "Open Warband Bank to scan items (auto-scanned on first visit)"
        else
            emptyMessage = (ns.L and ns.L["ITEMS_SCAN_HINT"]) or "Items are scanned automatically. Try /reload if nothing appears."
        end
    end
    container.desc:SetText(emptyMessage)
    
    -- Show container
    container:Show()
    
    return yOffset + 50
end

--============================================================================
-- DRAW SECTION EMPTY STATE (Collapsed section empty message)
--============================================================================

---Draw empty state for a collapsed section
---@param parent Frame Parent frame
---@param message string Empty state message
---@param yOffset number Current Y offset
---@param height number Height of empty state
---@param width number Width of empty state
---@return number newYOffset
local function DrawSectionEmptyState(parent, message, yOffset, height, width)
    if not parent then
        return yOffset
    end
    
    local emptyText = parent:CreateFontString(nil, "OVERLAY")
    FontManager:ApplyFont(emptyText, "body")
    emptyText:SetPoint("TOP", parent, "TOP", 0, -yOffset)
    emptyText:SetText("|cff999999" .. message .. "|r")
    emptyText:SetWidth(width or 300)
    emptyText:SetJustifyH("CENTER")
    
    return yOffset + (height or 30)
end

--============================================================================
-- SEARCH BOX (Reusable component for Items and Storage tabs)
--============================================================================

--[[
    Creates a search box with icon, placeholder, and throttled callback
    
    @param parent - Parent frame
    @param width - Search box width
    @param placeholder - Placeholder text (e.g., "Search items...")
    @param onTextChanged - Callback function(searchText) - called after throttle
    @param throttleDelay - Delay in seconds before callback (default 0.3)
    @param initialValue - Initial text value (optional, for restoring state)
    
    @return searchContainer frame, clearFunction
]]
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
    -- Use FontManager for consistent font styling (SAFE version)
    FontManager:SafeSetFont(searchBox, "body")
    
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    -- Set initial value if provided
    if initialText and initialText ~= "" then
        searchBox:SetText(initialText)
    end
    
    -- Placeholder text
    local placeholderText = FontManager:CreateFontString(searchBox, "body", "ARTWORK")
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder or ((ns.L and ns.L["SEARCH_PLACEHOLDER"]) or "Search..."))
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

    -- Select all text on click/focus
    searchBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    
    -- Clear function
    local function ClearSearch()
        searchBox:SetText("")
        placeholderText:Show()
    end
    
    return container, ClearSearch
end

--============================================================================
-- SHARED UI CONSTANTS
--============================================================================

local UI_CONSTANTS = {
    BUTTON_HEIGHT = 32,  -- Standardized to match search boxes and header elements
    BORDER_SIZE = 1,
    BUTTON_BORDER_COLOR = function() return COLORS.accent end,
    BUTTON_BG_COLOR = {0.1, 0.1, 0.1, 1},
}

ns.UI_CONSTANTS = UI_CONSTANTS

--============================================================================
-- SHARED BUTTON WIDGET
--============================================================================

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
    
    -- Apply border with theme color
    ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Apply highlight effect
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(btn)
    end
    
    local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText
    
    -- Auto-fit: expand button width if text is wider than the button
    local textWidth = btnText:GetStringWidth() or 0
    local padding = 20  -- 10px each side
    if textWidth + padding > btn:GetWidth() then
        btn:SetWidth(textWidth + padding)
    end
    
    return btn
end

--============================================================================
-- SHARED CHECKBOX WIDGET
--============================================================================

--============================================================================
-- SHARED TOGGLE INDICATOR (unified base for checkbox & radio)
--============================================================================

-- Shared visual constants for all toggle indicators
local TOGGLE_SIZE = 16
local TOGGLE_DOT_SIZE = 6
local TOGGLE_DOT_COLOR = {1, 0.82, 0, 1}  -- yellow/gold = active
local TOGGLE_BG = {0.08, 0.08, 0.10, 1}
local TOGGLE_BORDER = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8}
local TOGGLE_BORDER_HOVER = {COLORS.accent[1] * 1.3, COLORS.accent[2] * 1.3, COLORS.accent[3] * 1.3, 1}

local function ApplyToggleVisuals(frame)
    frame:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    ApplyVisuals(frame, TOGGLE_BG, TOGGLE_BORDER)

    local dot = frame:CreateTexture(nil, "ARTWORK")
    dot:SetSize(TOGGLE_DOT_SIZE, TOGGLE_DOT_SIZE)
    dot:SetPoint("CENTER")
    dot:SetColorTexture(unpack(TOGGLE_DOT_COLOR))

    frame.innerDot = dot
    frame.checkTexture = dot  -- alias so .checkTexture API keeps working

    frame.defaultBorderColor = {unpack(TOGGLE_BORDER)}
    frame.hoverBorderColor   = {unpack(TOGGLE_BORDER_HOVER)}

    return dot
end

--[[
    Create a themed checkbox (CheckButton with toggle behavior)
    @param parent - Parent frame
    @param initialState - Initial checked state (boolean)
    @return checkbox - Created checkbox
]]
local function CreateThemedCheckbox(parent, initialState)
    if not parent then
        DebugPrint("WarbandNexus DEBUG: CreateThemedCheckbox called with nil parent!")
        return nil
    end

    local checkbox = CreateFrame("CheckButton", nil, parent)
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
        if UpdateBorderColor then UpdateBorderColor(self, self.hoverBorderColor) end
    end)

    checkbox:SetScript("OnLeave", function(self)
        if UpdateBorderColor then UpdateBorderColor(self, self.defaultBorderColor) end
    end)

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
        DebugPrint("WarbandNexus DEBUG: CreateThemedRadioButton called with nil parent!")
        return nil
    end

    local radioButton = CreateFrame("Frame", nil, parent)
    local dot = ApplyToggleVisuals(radioButton)
    dot:SetShown(isSelected or false)

    return radioButton
end

--============================================================================
-- TABLE ROW FACTORY
--============================================================================

--[[
    Create a generic table row with configurable columns
    @param parent - Parent frame
    @param width - Row width
    @param height - Row height (default 32)
    @param columns - Array of column definitions: { {width=100, align="LEFT"}, ... }
    @return row - Created row frame with column anchors
]]
local function CreateTableRow(parent, width, height, columns)
    if not parent then return nil end
    
    height = height or 32
    
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    row:EnableMouse(true)
    
    -- Store column anchors for content placement
    row.columns = {}
    
    if columns then
        local xOffset = 0
        for i, col in ipairs(columns) do
            row.columns[i] = {
                x = xOffset,
                width = col.width,
                align = col.align or "LEFT"
            }
            xOffset = xOffset + col.width
        end
    end
    
    return row
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_CreateCard = CreateCard
-- FormatGold, FormatNumber, FormatTextNumbers, FormatMoney
-- are exported by FormatHelpers.lua (authoritative source, loads after SharedWidgets)
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_DrawSectionEmptyState = DrawSectionEmptyState
ns.UI_CreateSearchBox = CreateSearchBox
ns.UI_RefreshColors = RefreshColors
ns.UI_CalculateThemeColors = CalculateThemeColors

-- Frame pooling exports
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow
ns.UI_AcquireCurrencyRow = AcquireCurrencyRow
ns.UI_ReleaseCurrencyRow = ReleaseCurrencyRow
ns.UI_AcquireCharacterRow = AcquireCharacterRow
ns.UI_ReleaseCharacterRow = ReleaseCharacterRow
ns.UI_CharacterRowPool = CharacterRowPool  -- Export pool for overflow checking
ns.UI_AcquireReputationRow = AcquireReputationRow
ns.UI_ReleaseReputationRow = ReleaseReputationRow
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren

-- Shared widget exports
ns.UI_CreateThemedButton = CreateThemedButton
ns.UI_CreateThemedCheckbox = CreateThemedCheckbox
ns.UI_CreateThemedRadioButton = CreateThemedRadioButton
ns.UI_TOGGLE_SIZE = TOGGLE_SIZE

-- Table factory exports
ns.UI_CreateTableRow = CreateTableRow

-- ============================================================================
-- CREATE EXTERNAL WINDOW (Unified Dialog System)
-- ============================================================================
--[[
    Creates a standardized external window/dialog with:
    - Duplicate prevention
    - Click outside to close
    - Draggable header
    - Modern styling with borders
    - Close button
    
    Parameters:
    - config = {
        name = "UniqueDialogName" (required),
        title = "Dialog Title" (required),
        icon = "Interface\\Icons\\..." (required),
        width = 500 (default 400),
        height = 400 (default 300),
        onClose = function() end (optional),
        preventDuplicates = true (default true)
    }
    
    Returns:
    - dialog: Main dialog frame
    - contentFrame: Frame where you add your content
    - header: Header frame (for custom additions)
]]
local function CreateExternalWindow(config)
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
    
    local COLORS = ns.UI_COLORS
    
    -- Create dialog frame
    local dialog = CreateFrame("Frame", globalName, UIParent)
    dialog:SetSize(width, height)
    dialog:SetPoint("CENTER")

    -- WindowManager: standardized strata/level
    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(dialog, ns.WindowManager.PRIORITY.POPUP)
    else
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(200)
    end
    
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
    
    -- Make header draggable (combat-safe)
    if ns.WindowManager then
        ns.WindowManager:InstallDragHandler(header, dialog)
    else
        header:EnableMouse(true)
        header:SetMovable(true)
        header:RegisterForDrag("LeftButton")
        header:SetScript("OnDragStart", function()
            if not InCombatLockdown() then dialog:StartMoving() end
        end)
        header:SetScript("OnDragStop", function()
            dialog:StopMovingOrSizing()
        end)
    end
    
    -- Icon (support both texture and atlas)
    local iconIsAtlas = config.iconIsAtlas or false
    local iconFrame = CreateIcon(header, config.icon, 28, iconIsAtlas, nil, true)
    iconFrame:SetPoint("LEFT", 12, 0)
    iconFrame:Show()  -- CRITICAL: Show the header icon!
    
    -- Title
    local titleText = FontManager:CreateFontString(header, "title", "OVERLAY")
    titleText:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    titleText:SetText("|cffffffff" .. config.title .. "|r")
    
    -- Close button (X) - Factory pattern with atlas icon
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply custom visuals (dark background, accent border)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    -- Hover effects
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)
    
    -- Close function (onClose called once here only; OnHide must not call it again)
    local function CloseDialog()
        local bin = ns.UI_RecycleBin
        local overlay = dialog._clickOutsideFrame
        if overlay then
            overlay:Hide()
            overlay:SetScript("OnMouseDown", nil)
            if bin then overlay:SetParent(bin) else overlay:SetParent(nil) end
            dialog._clickOutsideFrame = nil
        end
        if config.onClose then
            config.onClose()
        end
        dialog:Hide()
        if bin then dialog:SetParent(bin) else dialog:SetParent(nil) end
        _G[globalName] = nil
    end
    
    closeBtn:SetScript("OnClick", CloseDialog)
    
    -- Content frame (where users add their content)
    local contentFrame = CreateFrame("Frame", nil, dialog)
    contentFrame:SetPoint("TOPLEFT", 8, -53) -- Below header
    contentFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    
    -- Click-outside overlay (released in CloseDialog to avoid frame buildup)
    local clickOutsideFrame = CreateFrame("Frame", nil, UIParent)
    dialog._clickOutsideFrame = clickOutsideFrame
    clickOutsideFrame:SetAllPoints()
    clickOutsideFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    clickOutsideFrame:SetFrameLevel(dialog:GetFrameLevel() - 1) -- Just below dialog
    clickOutsideFrame:EnableMouse(true)
    clickOutsideFrame:SetScript("OnMouseDown", function()
        CloseDialog()
    end)
    
    -- OnHide: only hide overlay (do NOT call onClose — CloseDialog already did)
    dialog:SetScript("OnHide", function()
        if dialog._clickOutsideFrame then
            dialog._clickOutsideFrame:Hide()
        end
    end)
    
    dialog:SetScript("OnShow", function()
        clickOutsideFrame:Show()
    end)
    
    -- Store close function
    dialog.Close = CloseDialog

    -- WindowManager: register popup + ESC handler + combat hide
    if ns.WindowManager then
        ns.WindowManager:Register(dialog, ns.WindowManager.PRIORITY.POPUP, CloseDialog)
        ns.WindowManager:InstallESCHandler(dialog)
    else
        dialog:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(false) end
                CloseDialog()
            else
                if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
            end
        end)
        if not InCombatLockdown() then dialog:SetPropagateKeyboardInput(true) end
    end

    return dialog, contentFrame, header
end

ns.UI_CreateExternalWindow = CreateExternalWindow

--============================================================================
-- TOOLTIP API
--============================================================================

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

--============================================================================
-- TRY COUNT ROW (Factory — same click path as popup everywhere)
--============================================================================

---@class WnTryCountClickableOptions
---@field height number|nil default 18
---@field fontCategory string|nil default "small"
---@field justifyH string|nil "LEFT" or "RIGHT" (default RIGHT)
---@field frameLevelOffset number|nil added to parent frame level (default 10)
---@field showTooltip boolean|nil default true

---Creates a full-width (caller anchors) or fixed-size try-count button; left/right mouse opens WNTryCount popup.
---@param parent Frame
---@param options WnTryCountClickableOptions|nil
---@return Frame row with .text (FontString) and :WnUpdateTryCount(type, id, displayName)
function ns.UI.Factory:CreateTryCountClickable(parent, options)
    options = options or {}
    local height = options.height or 18
    local fontCategory = options.fontCategory or "small"
    local justify = options.justifyH or "RIGHT"
    local showTooltip = options.showTooltip ~= false
    local levelOff = options.frameLevelOffset or 10

    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(height)
    row:EnableMouse(true)
    if parent and parent.GetFrameStrata then
        row:SetFrameStrata(parent:GetFrameStrata())
        row:SetFrameLevel((parent:GetFrameLevel() or 0) + levelOff)
    end
    if row.RegisterForClicks then
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    local fs = FontManager:CreateFontString(row, fontCategory, "OVERLAY")
    if justify == "LEFT" then
        fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    else
        fs:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    end
    fs:SetJustifyH(justify)
    fs:SetWordWrap(false)
    fs:EnableMouse(false)
    row.text = fs

    row._wnTryType = nil
    row._wnTryID = nil
    row._wnTryName = nil

    if showTooltip then
        row:SetScript("OnEnter", function(self)
            if not self:IsShown() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText((ns.L and ns.L["SET_TRY_COUNT"]) or "Set Try Count", 1, 1, 1)
            GameTooltip:AddLine((ns.L and ns.L["TRY_COUNT_CLICK_HINT"]) or "Click to edit attempt count.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row:SetScript("OnClick", nil)
    row:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" and btn ~= "RightButton" then return end
        local t, id, name = self._wnTryType, self._wnTryID, self._wnTryName
        if not t or not id or not ns.UI_ShowTryCountPopup then return end
        ns.UI_ShowTryCountPopup(t, id, name)
    end)

    function row:WnUpdateTryCount(collectibleType, collectibleID, displayName)
        self._wnTryType = collectibleType
        self._wnTryID = collectibleID
        self._wnTryName = displayName
        if not collectibleType or not collectibleID or not WarbandNexus or not WarbandNexus.ShouldShowTryCountInUI then
            self:Hide()
            return
        end
        if not WarbandNexus:ShouldShowTryCountInUI(collectibleType, collectibleID) then
            self:Hide()
            return
        end
        local count = (WarbandNexus.GetTryCount and WarbandNexus:GetTryCount(collectibleType, collectibleID)) or 0
        local triesLabel = (ns.L and ns.L["TRIES"]) or "Tries"
        self.text:SetText("|cffaaddff" .. triesLabel .. ":|r |cffffffff" .. tostring(count) .. "|r")
        self:Show()
    end

    row:Hide()
    return row
end

-- Collections detail header: action slot (+ try row) + Wowhead (eye always flush right) — same geometry for Mounts / Pets / Toy Box.
ns.CollectionsDetailHeaderLayout = {
    WOWHEAD_SIZE = 18,
    ACTION_SLOT_W = 74,
    ACTION_SLOT_H = 28,
    TRY_GAP = 4,
    TRY_ROW_H = 18,
    WOWHEAD_GAP = 10,
}

---Right column: [action slot][Wowhead] with optional try row aligned to the action slot only (not full column width).
---@param parent Frame
---@param opts { withTryRow: boolean|nil } withTryRow defaults true
---@return { root: Frame, actionSlot: Frame, wowheadBtn: Button, tryCountRow: Frame|nil }
function ns.UI.Factory:CreateCollectionsDetailRightColumn(parent, opts)
    opts = opts or {}
    local withTryRow = opts.withTryRow ~= false
    local L = ns.CollectionsDetailHeaderLayout
    local w = L.WOWHEAD_SIZE + L.WOWHEAD_GAP + L.ACTION_SLOT_W
    local h = L.ACTION_SLOT_H
    if withTryRow then
        h = h + L.TRY_GAP + L.TRY_ROW_H
    end

    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(w, h)

    local actionSlot = CreateFrame("Frame", nil, root)
    actionSlot:SetSize(L.ACTION_SLOT_W, L.ACTION_SLOT_H)
    actionSlot:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(L.WOWHEAD_SIZE + L.WOWHEAD_GAP), 0)

    local wowheadBtn = CreateFrame("Button", nil, root)
    wowheadBtn:SetSize(L.WOWHEAD_SIZE, L.WOWHEAD_SIZE)
    local vOff = math.max(0, (L.ACTION_SLOT_H - L.WOWHEAD_SIZE) / 2)
    wowheadBtn:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -vOff)
    wowheadBtn:SetNormalAtlas("socialqueuing-icon-eye")
    wowheadBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    wowheadBtn:SetFrameLevel((root:GetFrameLevel() or 0) + 8)
    wowheadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Wowhead", 1, 0.82, 0)
        GameTooltip:AddLine("Click to copy link", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    wowheadBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    wowheadBtn:Hide()

    local tryCountRow = nil
    if withTryRow then
        tryCountRow = self:CreateTryCountClickable(root, {
            height = L.TRY_ROW_H,
            frameLevelOffset = 10,
            justifyH = "RIGHT",
        })
        if tryCountRow then
            tryCountRow:SetPoint("TOPLEFT", actionSlot, "BOTTOMLEFT", 0, -L.TRY_GAP)
            tryCountRow:SetPoint("TOPRIGHT", actionSlot, "BOTTOMRIGHT", 0, -L.TRY_GAP)
        end
    end

    return {
        root = root,
        actionSlot = actionSlot,
        wowheadBtn = wowheadBtn,
        tryCountRow = tryCountRow,
    }
end

--============================================================================
-- TRY COUNT POPUP (Plans / Collections / Tracker)
--============================================================================

local tryCountPopupFrame = nil

---@param collectibleType string mount|pet|toy|illusion
---@param collectibleID number
---@param displayName string|nil shown under header
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

        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetHeight(32)
        header:SetPoint("TOPLEFT", 2, -2)
        header:SetPoint("TOPRIGHT", -2, -2)
        ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })

        local headerTitle = FontManager:CreateFontString(header, "title", "OVERLAY")
        headerTitle:SetPoint("CENTER")
        headerTitle:SetText((ns.L and ns.L["SET_TRY_COUNT"]) or "Set Try Count")
        headerTitle:SetTextColor(1, 1, 1)
        f.headerTitle = headerTitle

        local nameLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        nameLabel:SetPoint("TOP", header, "BOTTOM", 0, -12)
        nameLabel:SetJustifyH("CENTER")
        nameLabel:SetTextColor(0.9, 0.9, 0.9)
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
        editBox:SetFont(FontManager:GetFontFace(), FontManager:GetFontSize("body"), "")
        editBox:SetTextColor(1, 1, 1)
        editBox:SetJustifyH("CENTER")
        f.editBox = editBox

        local btnWidth, btnHeight = 90, 26

        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(btnWidth, btnHeight)
        saveBtn:SetPoint("TOPRIGHT", editBoxBg, "BOTTOM", -4, -10)
        ApplyVisuals(saveBtn, { 0.08, 0.08, 0.10, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        local saveBtnText = FontManager:CreateFontString(saveBtn, "body", "OVERLAY")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText((ns.L and ns.L["SAVE"]) or "Save")
        saveBtnText:SetTextColor(1, 1, 1)
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
        local cancelBtnText = FontManager:CreateFontString(cancelBtn, "body", "OVERLAY")
        cancelBtnText:SetPoint("CENTER")
        cancelBtnText:SetText(_G.CANCEL or "Cancel")
        cancelBtnText:SetTextColor(0.8, 0.8, 0.8)
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
        local count = tonumber(popup.editBox:GetText())
        if count and count >= 0 and WarbandNexus and WarbandNexus.SetTryCount and popup._wnTryType and popup._wnTryID then
            WarbandNexus:SetTryCount(popup._wnTryType, popup._wnTryID, count)
            if WarbandNexus.RefreshUI then WarbandNexus:RefreshUI() end
            if WarbandNexus and WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "try_count_set" })
            end
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

-- Export PixelScale functions (used by FontManager for resolution normalization)
ns.GetPixelScale = GetPixelScale
ns.PixelSnap = PixelSnap
ns.ResetPixelScale = ResetPixelScale
ns.SafeColorArray = SafeColorArray

--============================================================================
-- SETTINGS UI HELPERS
--============================================================================

--[[
    Create a bordered section/group container
    @param parent Frame - Parent frame
    @param title string - Section title (optional)
    @param width number - Section width
    @return Frame - Section container
]]
local function CreateSection(parent, title, width)
    local COLORS = GetColors()
    
    local section = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    section:SetSize(width or 640, 1)  -- Height will be calculated
    
    -- Use ApplyVisuals for centralized border management
    ApplyVisuals(section, {COLORS.bgLight[1], COLORS.bgLight[2], COLORS.bgLight[3], 0.3}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    
    -- Title (if provided) - inside card
    if title then
        local titleText = FontManager:CreateFontString(section, "header", "OVERLAY", "accent")
        titleText:SetPoint("TOPLEFT", 15, -12)  -- Inside card
        titleText:SetText(title)
        titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        section.titleText = titleText
    end
    
    -- Content container (inset from border with proper padding)
    local content = CreateFrame("Frame", nil, section)
    content:SetPoint("TOPLEFT", 15, title and -40 or -15)
    content:SetPoint("TOPRIGHT", -15, title and -40 or -15)
    section.content = content
    
    return section
end

--[[
    Create a simple border frame
    @param parent Frame - Parent frame
    @param inset number - Border inset (optional, default 0)
    @return Frame - Border frame
]]
--[[
    DEPRECATED: CreateBorder - Use ApplyVisuals instead
    
    CreateBorder was the old backdrop-based border system.
    ApplyVisuals is the new 4-texture sandwich method.
    
    This function is kept for backwards compatibility but simply wraps ApplyVisuals.
    All new code should use ApplyVisuals directly.
]]
local function CreateBorder(parent, inset, borderType)
    -- Legacy wrapper - redirect to ApplyVisuals
    local COLORS = GetColors()
    borderType = borderType or "border"
    
    local targetColor = (borderType == "accent") and COLORS.accent or COLORS.border
    local alpha = (borderType == "accent") and 0.8 or 0.6
    
    -- Apply modern border system
    ApplyVisuals(parent, nil, {targetColor[1], targetColor[2], targetColor[3], alpha})
    
    return parent
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
    labelFont = labelFont or "subtitle"
    valueFont = valueFont or "body"
    
    -- Create icon (centered vertically at left side)
    local iconFrame = CreateIcon(parent, iconTexture, iconSize, isAtlas, nil, true)
    iconFrame:SetPoint("CENTER", parent, "LEFT", 15 + (iconSize/2), 0)
    iconFrame:Show()
    
    -- Create container for text group
    local textContainer = CreateFrame("Frame", nil, parent)
    textContainer:SetSize(200, 40)
    
    -- Create label (centered in container)
    local label = FontManager:CreateFontString(textContainer, labelFont, "OVERLAY")
    label:SetText(labelText)
    label:SetTextColor(1, 1, 1)
    label:SetJustifyH("LEFT")
    
    -- Create value (if provided)
    local value
    if valueText and valueText ~= "" then
        value = FontManager:CreateFontString(textContainer, valueFont, "OVERLAY")
        value:SetText(valueText)
        value:SetJustifyH("LEFT")
        
        -- Position texts centered in container
        label:SetPoint("BOTTOM", textContainer, "CENTER", 0, 0)  -- Label at center
        label:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
        value:SetPoint("TOP", textContainer, "CENTER", 0, -4)    -- Value below center
        value:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    else
        -- Single text, center it
        label:SetPoint("CENTER", textContainer, "CENTER", 0, 0)
        label:SetPoint("LEFT", textContainer, "LEFT", 0, 0)
    end
    
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

--============================================================================
-- DISABLED MODULE STATE CARD
--============================================================================

-- Creates a centered card showing module disabled state with Warband logo
-- @param parent: Parent frame to attach to
-- @param yOffset: Y offset from top
-- @param moduleName: Display name of the module (e.g., "Currency", "Reputation")
-- @return height: Total height consumed
local function CreateDisabledModuleCard(parent, yOffset, moduleName)
    local COLORS = ns.UI_COLORS
    local FontManager = ns.FontManager
    local SIDE_MARGIN = 10
    
    -- Calculate parent height dynamically
    local parentHeight = parent:GetHeight() or 600
    
    -- Create card frame that fills entire content area (full width and height)
    local card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    card:SetPoint("BOTTOMRIGHT", -SIDE_MARGIN, SIDE_MARGIN)
    
    -- Apply 1px border using ApplyVisuals (4-texture sandwich method)
    local bgColor = {0.1, 0.1, 0.12, 1}  -- Card background
    local borderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4}  -- Thin accent border
    ApplyVisuals(card, bgColor, borderColor)
    
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
    icon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    icon:SetTexCoord(0, 1, 0, 1)
    
    -- Icon border frame (thin 1px accent ring) - behind the icon
    local iconBorder = CreateFrame("Frame", nil, contentContainer, BackdropTemplateMixin and "BackdropTemplate")
    iconBorder:SetSize(iconSize + 4, iconSize + 4)
    iconBorder:SetPoint("CENTER", iconContainer, "CENTER", 0, 0)
    iconBorder:SetFrameLevel(iconContainer:GetFrameLevel() - 1)
    ApplyVisuals(iconBorder, nil, borderColor)  -- Just border, no background
    
    -- "Module Disabled" title
    local title = FontManager:CreateFontString(contentContainer, "header", "OVERLAY")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -24)
    title:SetText("|cffcccccc" .. ((ns.L and ns.L["MODULE_DISABLED"]) or "Module Disabled") .. "|r")
    
    -- Description with colored module name
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local description = FontManager:CreateFontString(contentContainer, "body", "OVERLAY")
    description:SetPoint("TOP", title, "BOTTOM", 0, -16)
    description:SetWidth(380)
    description:SetJustifyH("CENTER")
    local settingsStr = "|cffffffff" .. ((ns.L and ns.L["BTN_SETTINGS"]) or SETTINGS or "Settings") .. "|r"
    local moduleStr = "|cff" .. hexColor .. moduleName .. "|r"
    description:SetText(
        "|cff999999" .. format((ns.L and ns.L["MODULE_DISABLED_DESC_FORMAT"]) or "Enable it in %s to use %s.", settingsStr, moduleStr) .. "|r"
    )
    
    card:Show()
    
    -- Return full height to parent
    return parentHeight - yOffset
end

--============================================================================
-- RESET TIMER WIDGET
--============================================================================

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
    local text = FontManager:CreateFontString(container, "body", "OVERLAY")
    text:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    text:SetTextColor(0.3, 0.9, 0.3)  -- Green color
    
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
    
    -- Auto-update every 60 seconds
    container.timeSinceUpdate = 0
    container:SetScript("OnUpdate", function(self, elapsed)
        self.timeSinceUpdate = self.timeSinceUpdate + elapsed
        if self.timeSinceUpdate >= 60 then
            self.timeSinceUpdate = 0
            Update()
        end
    end)
    
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

--============================================================================
-- EMPTY STATE CARD (Standardized "no data" state for all tabs)
--============================================================================

-- Per-tab empty state configuration
-- Uses the same atlas icons as TAB_HEADER_ICONS but larger and desaturated
local EMPTY_STATE_CONFIG = {
    characters = {
        atlas = "poi-town",
        titleKey = "EMPTY_CHARACTERS_TITLE",
        descKey = "EMPTY_CHARACTERS_DESC",
        titleFallback = "No Characters Found",
        descFallback = "Log in to your characters to start tracking them.\nCharacter data is collected automatically on each login.",
    },
    items = {
        atlas = "Banker",
        titleKey = "EMPTY_ITEMS_TITLE",
        descKey = "EMPTY_ITEMS_DESC",
        titleFallback = "No Items Cached",
        descFallback = "Open your Warband Bank or Personal Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_inventory = {
        atlas = "Backpack",
        titleKey = "EMPTY_INVENTORY_TITLE",
        descKey = "EMPTY_INVENTORY_DESC",
        titleFallback = "No Items in Inventory",
        descFallback = "Your inventory bags are empty.",
    },
    items_personal = {
        atlas = "Banker",
        titleKey = "EMPTY_PERSONAL_BANK_TITLE",
        descKey = "EMPTY_PERSONAL_BANK_DESC",
        titleFallback = "No Items in Personal Bank",
        descFallback = "Open your Personal Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_warband = {
        atlas = "Mobile-WarbandIcon",
        titleKey = "EMPTY_WARBAND_BANK_TITLE",
        descKey = "EMPTY_WARBAND_BANK_DESC",
        titleFallback = "No Items in Warband Bank",
        descFallback = "Open your Warband Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_guild = {
        atlas = "communities-icon-chat",
        titleKey = "EMPTY_GUILD_BANK_TITLE",
        descKey = "EMPTY_GUILD_BANK_DESC",
        titleFallback = "No Items in Guild Bank",
        descFallback = "Open your Guild Bank to scan items.\nItems are cached automatically on first visit.",
    },
    storage = {
        atlas = "VignetteLoot",
        titleKey = "EMPTY_STORAGE_TITLE",
        descKey = "EMPTY_STORAGE_DESC",
        titleFallback = "No Storage Data",
        descFallback = "Items are scanned when you open banks or bags.\nVisit a bank to start tracking your storage.",
    },
    plans = {
        atlas = "poi-islands-table",
        titleKey = "EMPTY_PLANS_TITLE",
        descKey = "EMPTY_PLANS_DESC",
        titleFallback = "No Plans Yet",
        descFallback = "Browse Mounts, Pets, Toys, or Achievements above\nto add collection goals and track your progress.",
    },
    reputation = {
        atlas = "MajorFactions_MapIcons_Centaur64",
        titleKey = "EMPTY_REPUTATION_TITLE",
        descKey = "EMPTY_REPUTATION_DESC",
        titleFallback = "No Reputation Data",
        descFallback = "Reputations are scanned automatically on login.\nLog in to a character to start tracking faction standings.",
    },
    currency = {
        atlas = "Auctioneer",
        titleKey = "EMPTY_CURRENCY_TITLE",
        descKey = "EMPTY_CURRENCY_DESC",
        titleFallback = "No Currency Data",
        descFallback = "Currencies are tracked automatically across your characters.\nLog in to a character to start tracking currencies.",
    },
    pve = {
        atlas = "Tormentors-Boss",
        titleKey = "EMPTY_PVE_TITLE",
        descKey = "EMPTY_PVE_DESC",
        titleFallback = "No PvE Data",
        descFallback = "PvE progress is tracked when you log into your characters.\nGreat Vault, Mythic+, and Raid lockouts will appear here.",
    },
    statistics = {
        atlas = "racing",
        titleKey = "EMPTY_STATISTICS_TITLE",
        descKey = "EMPTY_STATISTICS_DESC",
        titleFallback = "No Statistics Available",
        descFallback = "Statistics are gathered from your tracked characters.\nLog in to a character to start collecting data.",
    },
    collections = {
        atlas = "PetJournalPortrait",
        titleKey = "COLLECTIONS_COMING_SOON_TITLE",
        descKey = "COLLECTIONS_COMING_SOON_DESC",
        titleFallback = "Coming Soon",
        descFallback = "Collection overview (mounts, pets, toys, transmog) will be available here.",
    },
}

-- Creates a standardized empty state card for any tab
-- Centered vertically in parent with icon, title, and description
-- @param parent: Parent frame to attach to
-- @param tabName: string - Tab identifier (e.g., "characters", "items", "pve")
-- @param yOffset: number - Y offset from top (default 0)
-- @return Frame - The empty state frame (shown automatically)
-- @return number - Total height consumed
local function CreateEmptyStateCard(parent, tabName, yOffset)
    yOffset = yOffset or 0
    local COLORS = ns.UI_COLORS
    local FontManager = ns.FontManager
    local SIDE_MARGIN = 10

    -- Get config for this tab
    local config = EMPTY_STATE_CONFIG[tabName]
    if not config then
        config = {
            atlas = "shop-icon-housing-characters-up",
            titleKey = "NO_DATA",
            descKey = nil,
            titleFallback = "No Data",
            descFallback = "No data available.",
        }
    end

    -- Reuse existing empty state card on parent
    local cacheKey = "emptyStateCard_" .. tabName
    local card = parent[cacheKey]
    if card then
        card:Show()
        return card, card:GetHeight()
    end

    -- Walk up the parent chain to find the actual ScrollFrame viewport
    -- parent may be a resultsContainer nested inside the scrollChild, so parent:GetParent() alone is unreliable
    local visibleHeight = 600  -- safe fallback
    local current = parent
    for i = 1, 5 do
        current = current and current:GetParent()
        if not current then break end
        if current.GetObjectType and current:GetObjectType() == "ScrollFrame" then
            local h = current:GetHeight()
            if h and h > 0 then visibleHeight = h end
            break
        end
    end
    local cardHeight = math.max(visibleHeight - yOffset - SIDE_MARGIN, 200)

    -- Create transparent container that fills the result area (no background, no border)
    card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", 0, -yOffset)
    card:SetPoint("TOPRIGHT", 0, -yOffset)
    card:SetHeight(cardHeight)
    parent[cacheKey] = card

    -- Content container (truly centered in card)
    local contentContainer = CreateFrame("Frame", nil, card)
    contentContainer:SetSize(400, 200)
    contentContainer:SetPoint("CENTER", card, "CENTER", 0, 0)

    -- Icon (large, pure)
    local iconSize = 64
    local iconContainer = CreateFrame("Frame", nil, contentContainer)
    iconContainer:SetSize(iconSize, iconSize)
    iconContainer:SetPoint("TOP", contentContainer, "TOP", 0, 0)

    local icon = iconContainer:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetAllPoints(iconContainer)
    icon:SetAtlas(config.atlas)
    icon:SetAlpha(0.6)

    -- Title
    local title = FontManager:CreateFontString(contentContainer, "header", "OVERLAY")
    title:SetPoint("TOP", iconContainer, "BOTTOM", 0, -20)
    local titleText = (ns.L and ns.L[config.titleKey]) or config.titleFallback
    title:SetText("|cff888888" .. titleText .. "|r")

    -- Description
    local desc = FontManager:CreateFontString(contentContainer, "body", "OVERLAY")
    desc:SetPoint("TOP", title, "BOTTOM", 0, -12)
    desc:SetWidth(380)
    desc:SetJustifyH("CENTER")
    local descText = (ns.L and config.descKey and ns.L[config.descKey]) or config.descFallback
    desc:SetText("|cff666666" .. descText .. "|r")

    card:Show()
    return card, yOffset + cardHeight + SIDE_MARGIN
end

-- Hide empty state card for a specific tab
-- @param parent: Parent frame
-- @param tabName: string - Tab identifier
local function HideEmptyStateCard(parent, tabName)
    if not parent then return end
    local cacheKey = "emptyStateCard_" .. tabName
    if parent[cacheKey] then
        parent[cacheKey]:Hide()
    end
end

-- Export empty state helpers
ns.UI_CreateEmptyStateCard = CreateEmptyStateCard
ns.UI_HideEmptyStateCard = HideEmptyStateCard
ns.UI_EMPTY_STATE_CONFIG = EMPTY_STATE_CONFIG

-- Export Settings UI helpers
ns.UI_CreateSection = CreateSection
ns.UI_CreateBorder = CreateBorder

--============================================================================
-- DB VERSION BADGE (Debug Logging)
--============================================================================

---Creates a small badge showing which DB/cache is being used by this tab
---@param parent Frame Parent frame (tab content)
---@param dataSource string Description of data source (e.g., "CurrencyCache v1.0.0", "db.global.currencies [LEGACY]")
---@param anchorPoint string Anchor point (default "TOPRIGHT")
---@param xOffset number X offset from anchor (default -10)
---@param yOffset number Y offset from anchor (default -10)
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
    local text = FontManager:CreateFontString(badge, "small", "OVERLAY")
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
        GameTooltip:AddLine((ns.L and ns.L["DATA_SOURCE_TITLE"]) or "Data Source Information", 1, 1, 1)
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

-- Export DB version badge
ns.UI_CreateDBVersionBadge = CreateDBVersionBadge
ns.UI_CreateCardHeaderLayout = CreateCardHeaderLayout

--============================================================================
-- FACTORY METHODS (Standardized Frame Creation)
--============================================================================

-- NOTE: CreateContainer implementation moved to line 4789 (Factory pattern wrapper)
-- NOTE: CreateButton implementation moved to line 4809 (Factory pattern wrapper)
-- These duplicate implementations were removed to avoid confusion

--- Create a scroll frame with styled vertical scroll bar (Button | Bar | Button).
--- Bar and buttons are created but not positioned; caller must call PositionScrollBarInContainer(scrollFrame.ScrollBar, container, inset).
--- Use CreateScrollBarColumn(parent, width, topInset, bottomInset) to get a container, or your own frame (e.g. Collections list/detail columns).
---@param parent Frame Parent frame
---@param template string|nil Optional template (default: "UIPanelScrollFrameTemplate")
---@param customStyle boolean|nil If true, applies custom scroll bar styling (default: true)
---@return ScrollFrame scrollFrame The created scroll frame
function ns.UI.Factory:CreateScrollFrame(parent, template, customStyle)
    if not parent then
        DebugPrint("|cffff4444[WN Factory ERROR]|r CreateScrollFrame: parent is nil")
        return nil
    end
    
    -- Default to UIPanelScrollFrameTemplate if no template provided
    template = template or "UIPanelScrollFrameTemplate"
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, template)
    
    -- Apply modern custom scroll bar styling (default: true)
    if customStyle ~= false and scrollFrame.ScrollBar then
        local scrollBar = scrollFrame.ScrollBar
        local function GetScrollStep()
            local addon = _G.WarbandNexus or ns.WarbandNexus
            local base = ns.UI_LAYOUT.SCROLL_BASE_STEP or 28
            local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or ns.UI_LAYOUT.SCROLL_SPEED_DEFAULT or 1.0
            return math.floor(base * speed + 0.5)
        end
        
        -- Hide default up/down buttons (modern minimalist look)
        if scrollBar.ScrollUpButton then
            scrollBar.ScrollUpButton:Hide()
            scrollBar.ScrollUpButton:SetSize(0.1, 0.1)
        end
        if scrollBar.ScrollDownButton then
            scrollBar.ScrollDownButton:Hide()
            scrollBar.ScrollDownButton:SetSize(0.1, 0.1)
        end
        
        -- Create custom track (background) with visible border
        if not scrollBar.CustomTrack then
            scrollBar.CustomTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
            scrollBar.CustomTrack:SetAllPoints(scrollBar)
            scrollBar.CustomTrack:SetColorTexture(0.08, 0.08, 0.10, 0.9)  -- Dark background
        end
        
        -- Create pixel-perfect borders for track
        local pixelScale = GetPixelScale()
        
        if not scrollBar.BorderLeft then
            scrollBar.BorderLeft = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderLeft:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            scrollBar.BorderLeft:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
            scrollBar.BorderLeft:SetWidth(pixelScale)
            scrollBar.BorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        if not scrollBar.BorderRight then
            scrollBar.BorderRight = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderRight:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
            scrollBar.BorderRight:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
            scrollBar.BorderRight:SetWidth(pixelScale)
            scrollBar.BorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        if not scrollBar.BorderTop then
            scrollBar.BorderTop = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderTop:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
            scrollBar.BorderTop:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
            scrollBar.BorderTop:SetHeight(pixelScale)
            scrollBar.BorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        if not scrollBar.BorderBottom then
            scrollBar.BorderBottom = scrollBar:CreateTexture(nil, "BORDER")
            scrollBar.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
            scrollBar.BorderBottom:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
            scrollBar.BorderBottom:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
            scrollBar.BorderBottom:SetHeight(pixelScale)
            scrollBar.BorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
        end
        
        -- Register scrollBar for theme refresh
        if scrollBar.BorderTop and scrollBar.BorderBottom and scrollBar.BorderLeft and scrollBar.BorderRight then
            scrollBar._borderType = "accent"
            scrollBar._borderAlpha = 0.6
            table.insert(ns.BORDER_REGISTRY, scrollBar)
        end
        
        -- Create custom thumb (draggable part) with modern styling
        if scrollBar.ThumbTexture then
            -- Main thumb background
            scrollBar.ThumbTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
            scrollBar.ThumbTexture:SetSize(14, 60)  -- Match scroll bar width (14px for thumb inside 16px bar)
            
            -- Store reference for theme refresh
            scrollBar._thumbTexture = scrollBar.ThumbTexture
            
            -- Hover effects (these still use COLORS directly for immediate feedback)
            scrollBar:SetScript("OnEnter", function(self)
                if self.ThumbTexture then
                    local currentColors = GetColors()
                    self.ThumbTexture:SetColorTexture(
                        currentColors.accent[1] * 1.2,
                        currentColors.accent[2] * 1.2,
                        currentColors.accent[3] * 1.2,
                        1
                    )
                end
            end)
            
            scrollBar:SetScript("OnLeave", function(self)
                if self.ThumbTexture then
                    local currentColors = GetColors()
                    self.ThumbTexture:SetColorTexture(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 0.9)
                end
            end)
        end
        
        local btnSize = UI_SPACING.SCROLL_BAR_BUTTON_SIZE or 16
        local barWidth = UI_SPACING.SCROLL_BAR_WIDTH or 16
        -- Create scroll up button (top) — standard Button | Bar | Button layout
        if not scrollBar.ScrollUpBtn then
            scrollBar.ScrollUpBtn = CreateFrame("Button", nil, scrollFrame:GetParent())
            scrollBar.ScrollUpBtn:SetSize(btnSize, btnSize)
            -- Position via PositionScrollBarInContainer(scrollBar, container, inset) only

            -- Background
            local upBg = scrollBar.ScrollUpBtn:CreateTexture(nil, "BACKGROUND")
            upBg:SetAllPoints()
            upBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
            scrollBar.ScrollUpBtn.bg = upBg
            
            -- Pixel-perfect borders (matching scroll bar)
            local pixelScale = GetPixelScale()
            
            local upBorderTop = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderTop:SetPoint("TOPLEFT", 0, 0)
            upBorderTop:SetPoint("TOPRIGHT", 0, 0)
            upBorderTop:SetHeight(pixelScale)
            upBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local upBorderBottom = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
            upBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
            upBorderBottom:SetHeight(pixelScale)
            upBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local upBorderLeft = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderLeft:SetPoint("TOPLEFT", 0, 0)
            upBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
            upBorderLeft:SetWidth(pixelScale)
            upBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local upBorderRight = scrollBar.ScrollUpBtn:CreateTexture(nil, "BORDER")
            upBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
            upBorderRight:SetPoint("TOPRIGHT", 0, 0)
            upBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
            upBorderRight:SetWidth(pixelScale)
            upBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            -- Store border textures for registry
            scrollBar.ScrollUpBtn.BorderTop = upBorderTop
            scrollBar.ScrollUpBtn.BorderBottom = upBorderBottom
            scrollBar.ScrollUpBtn.BorderLeft = upBorderLeft
            scrollBar.ScrollUpBtn.BorderRight = upBorderRight
            
            -- Register for theme refresh
            scrollBar.ScrollUpBtn._borderType = "accent"
            scrollBar.ScrollUpBtn._borderAlpha = 0.6
            table.insert(ns.BORDER_REGISTRY, scrollBar.ScrollUpBtn)
            
            -- Arrow icon
            local upIcon = scrollBar.ScrollUpBtn:CreateTexture(nil, "ARTWORK")
            upIcon:SetSize(12, 12)
            upIcon:SetPoint("CENTER")
            upIcon:SetAtlas("common-icon-offscreen", false)
            upIcon:SetRotation(-math.pi / 2)
            upIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            scrollBar.ScrollUpBtn.icon = upIcon
            scrollBar.ScrollUpBtn._iconTexture = upIcon  -- Store for theme refresh
            
            -- Click handler (pixel-snapped)
            scrollBar.ScrollUpBtn:SetScript("OnClick", function()
                local step = GetScrollStep()
                local current = scrollFrame:GetVerticalScroll()
                local val = math.max(0, current - step)
                local PS = ns.PixelSnap
                if PS then val = PS(val) end
                scrollFrame:SetVerticalScroll(val)
            end)
            
            -- Hover effects
            scrollBar.ScrollUpBtn:SetScript("OnEnter", function(self)
                local currentColors = GetColors()
                self.bg:SetColorTexture(currentColors.accent[1] * 0.3, currentColors.accent[2] * 0.3, currentColors.accent[3] * 0.3, 1)
                self.icon:SetVertexColor(currentColors.accent[1] * 1.3, currentColors.accent[2] * 1.3, currentColors.accent[3] * 1.3, 1)
            end)
            
            scrollBar.ScrollUpBtn:SetScript("OnLeave", function(self)
                local currentColors = GetColors()
                self.bg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
                self.icon:SetVertexColor(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 1)
            end)
        end
        
        -- Create scroll down button (bottom)
        if not scrollBar.ScrollDownBtn then
            scrollBar.ScrollDownBtn = CreateFrame("Button", nil, scrollFrame:GetParent())
            scrollBar.ScrollDownBtn:SetSize(btnSize, btnSize)
            -- Position via PositionScrollBarInContainer(scrollBar, container, inset) only

            -- Background
            local downBg = scrollBar.ScrollDownBtn:CreateTexture(nil, "BACKGROUND")
            downBg:SetAllPoints()
            downBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
            scrollBar.ScrollDownBtn.bg = downBg
            
            -- Pixel-perfect borders (matching scroll bar)
            local pixelScale = GetPixelScale()
            
            local downBorderTop = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderTop:SetPoint("TOPLEFT", 0, 0)
            downBorderTop:SetPoint("TOPRIGHT", 0, 0)
            downBorderTop:SetHeight(pixelScale)
            downBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local downBorderBottom = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
            downBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
            downBorderBottom:SetHeight(pixelScale)
            downBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local downBorderLeft = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderLeft:SetPoint("TOPLEFT", 0, 0)
            downBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
            downBorderLeft:SetWidth(pixelScale)
            downBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            local downBorderRight = scrollBar.ScrollDownBtn:CreateTexture(nil, "BORDER")
            downBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
            downBorderRight:SetPoint("TOPRIGHT", 0, 0)
            downBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
            downBorderRight:SetWidth(pixelScale)
            downBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
            
            -- Store border textures for registry
            scrollBar.ScrollDownBtn.BorderTop = downBorderTop
            scrollBar.ScrollDownBtn.BorderBottom = downBorderBottom
            scrollBar.ScrollDownBtn.BorderLeft = downBorderLeft
            scrollBar.ScrollDownBtn.BorderRight = downBorderRight
            
            -- Register for theme refresh
            scrollBar.ScrollDownBtn._borderType = "accent"
            scrollBar.ScrollDownBtn._borderAlpha = 0.6
            table.insert(ns.BORDER_REGISTRY, scrollBar.ScrollDownBtn)
            
            -- Arrow icon
            local downIcon = scrollBar.ScrollDownBtn:CreateTexture(nil, "ARTWORK")
            downIcon:SetSize(12, 12)
            downIcon:SetPoint("CENTER")
            downIcon:SetAtlas("common-icon-offscreen", false)
            downIcon:SetRotation(math.pi / 2)
            downIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            scrollBar.ScrollDownBtn.icon = downIcon
            scrollBar.ScrollDownBtn._iconTexture = downIcon  -- Store for theme refresh
            
            -- Click handler (pixel-snapped)
            scrollBar.ScrollDownBtn:SetScript("OnClick", function()
                local step = GetScrollStep()
                local current = scrollFrame:GetVerticalScroll()
                local maxScroll = scrollFrame:GetVerticalScrollRange()
                local val = math.min(maxScroll, current + step)
                local PS = ns.PixelSnap
                if PS then val = PS(val) end
                scrollFrame:SetVerticalScroll(val)
            end)
            
            -- Hover effects
            scrollBar.ScrollDownBtn:SetScript("OnEnter", function(self)
                local currentColors = GetColors()
                self.bg:SetColorTexture(currentColors.accent[1] * 0.3, currentColors.accent[2] * 0.3, currentColors.accent[3] * 0.3, 1)
                self.icon:SetVertexColor(currentColors.accent[1] * 1.3, currentColors.accent[2] * 1.3, currentColors.accent[3] * 1.3, 1)
            end)
            
            scrollBar.ScrollDownBtn:SetScript("OnLeave", function(self)
                local currentColors = GetColors()
                self.bg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
                self.icon:SetVertexColor(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 1)
            end)
        end

        -- Bar/buttons are positioned only via PositionScrollBarInContainer(scrollFrame.ScrollBar, container, inset).
        -- Hide until positioned so they do not appear at (0,0).
        scrollBar:Hide()
        if scrollBar.ScrollUpBtn then scrollBar.ScrollUpBtn:Hide() end
        if scrollBar.ScrollDownBtn then scrollBar.ScrollDownBtn:Hide() end

        -- When scroll bar is reparented (e.g. into scrollBarContainer), Blizzard's OnValueChanged
        -- calls GetParent():SetVerticalScroll() which fails. Keep explicit reference and override.
        scrollBar._scrollFrame = scrollFrame
        scrollBar:SetScript("OnValueChanged", function(self, value)
            if self._scrollFrame and self._scrollFrame.SetVerticalScroll then
                self._scrollFrame:SetVerticalScroll(value)
            end
        end)
    end
    
    -- Debug log (only first call)
    if not self._scrollLogged then
        DebugPrint("|cff9370DB[WN Factory]|r CreateScrollFrame initialized with modern scroll bar")
        self._scrollLogged = true
    end
    
    -- Auto-hide scroll bar when content fits (call after content is populated).
    -- When bar is in an external container (reparented), always show bar and buttons so the column does not flicker.
    scrollFrame.UpdateScrollBarVisibility = function(self)
        if not self.ScrollBar then return end
        local bar = self.ScrollBar
        local barInExternalContainer = (bar.GetParent and bar:GetParent() ~= self)

        if barInExternalContainer then
            bar:Show()
            if bar.ScrollUpBtn then bar.ScrollUpBtn:Show() end
            if bar.ScrollDownBtn then bar.ScrollDownBtn:Show() end
            return
        end

        local scrollChild = self:GetScrollChild()
        if not scrollChild then return end
        local contentHeight = scrollChild:GetHeight() or 0
        local frameHeight = self:GetHeight() or 0

        if contentHeight > frameHeight + 1 then
            bar:Show()
            if bar.ScrollUpBtn then bar.ScrollUpBtn:Show() end
            if bar.ScrollDownBtn then bar.ScrollDownBtn:Show() end
        else
            bar:Hide()
            if bar.ScrollUpBtn then bar.ScrollUpBtn:Hide() end
            if bar.ScrollDownBtn then bar.ScrollDownBtn:Hide() end
        end
    end
    
    -- Smooth scroll: base step * speed multiplier from profile
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local addon = _G.WarbandNexus or ns.WarbandNexus
        local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
        local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
        local step = math.floor(base * speed + 0.5)
        -- Shift+Wheel routes to horizontal when available; default wheel keeps vertical behavior.
        if IsShiftKeyDown and IsShiftKeyDown() and self.GetHorizontalScrollRange and self.SetHorizontalScroll then
            local maxH = self:GetHorizontalScrollRange() or 0
            if maxH > 0 then
                local currentH = self:GetHorizontalScroll() or 0
                local newH = math.max(0, math.min(maxH, currentH - (delta * step)))
                self:SetHorizontalScroll(newH)
                if self.HorizontalScrollBar then
                    self.HorizontalScrollBar:SetValue(newH)
                end
                return
            end
        end

        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = math.max(0, math.min(maxScroll, current - (delta * step)))
        local PS = ns.PixelSnap
        if PS then newScroll = PS(newScroll) end
        self:SetVerticalScroll(newScroll)
    end)
    
    return scrollFrame
end

--- Create a frame for the vertical scroll bar column (same pattern as Collections: list | bar column | details).
--- Caller anchors this to the right of the scroll content, then calls PositionScrollBarInContainer(scrollFrame.ScrollBar, container, inset).
---@param parent Frame Parent (e.g. content area)
---@param width number Width of the column (e.g. SCROLLBAR_COLUMN_WIDTH or 22)
---@param topInset number|nil Inset from parent top (default 0)
---@param bottomInset number|nil Inset from parent bottom (default 0)
---@return Frame container The frame to pass to PositionScrollBarInContainer
function ns.UI.Factory:CreateScrollBarColumn(parent, width, topInset, bottomInset)
    if not parent then return nil end
    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local w = width or layout.SCROLLBAR_COLUMN_WIDTH or 22
    local top = (topInset == nil) and 0 or topInset
    local bottom = (bottomInset == nil) and 0 or bottomInset
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -top)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, bottom)
    container:SetWidth(w)
    container:SetFrameLevel((parent:GetFrameLevel() or 0) + 2)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

--- Standard layout when scroll bar is placed in an external container (e.g. list | gap | scrollbar | gap | details).
--- Ensures Button (top) | Bar | Button (bottom) with same dimensions everywhere (SCROLL_BAR_BUTTON_SIZE, SCROLL_BAR_WIDTH).
---@param scrollBar table Slider (ScrollBar from CreateScrollFrame)
---@param scrollBarContainer Frame Container to reparent bar and buttons into
---@param inset number|nil Optional top/bottom inset (default 2)
function ns.UI.Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, inset)
    if not scrollBar or not scrollBarContainer then return end
    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local btnSize = layout.SCROLL_BAR_BUTTON_SIZE or 16
    local barWidth = layout.SCROLL_BAR_WIDTH or 16
    local gap = (inset == nil) and 2 or inset

    local containerLevel = scrollBarContainer:GetFrameLevel()
    scrollBar:SetParent(scrollBarContainer)
    scrollBar:SetFrameLevel(containerLevel + 1)
    scrollBar:Show()

    -- Buttons fully inside container (no -gap/+gap) so they are never clipped by adjacent panels
    if scrollBar.ScrollUpBtn then
        scrollBar.ScrollUpBtn:SetParent(scrollBarContainer)
        scrollBar.ScrollUpBtn:SetFrameLevel(containerLevel + 3)
        scrollBar.ScrollUpBtn:ClearAllPoints()
        scrollBar.ScrollUpBtn:SetSize(btnSize, btnSize)
        scrollBar.ScrollUpBtn:SetPoint("TOP", scrollBarContainer, "TOP", 0, 0)
        scrollBar.ScrollUpBtn:Show()
    end
    if scrollBar.ScrollDownBtn then
        scrollBar.ScrollDownBtn:SetParent(scrollBarContainer)
        scrollBar.ScrollDownBtn:SetFrameLevel(containerLevel + 3)
        scrollBar.ScrollDownBtn:ClearAllPoints()
        scrollBar.ScrollDownBtn:SetSize(btnSize, btnSize)
        scrollBar.ScrollDownBtn:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, 0)
        scrollBar.ScrollDownBtn:Show()
    end
    scrollBar:ClearAllPoints()
    if scrollBar.ScrollUpBtn and scrollBar.ScrollDownBtn then
        scrollBar:SetPoint("TOP", scrollBar.ScrollUpBtn, "BOTTOM", 0, 0)
        scrollBar:SetPoint("BOTTOM", scrollBar.ScrollDownBtn, "TOP", 0, 0)
    else
        scrollBar:SetPoint("TOP", scrollBarContainer, "TOP", 0, 0)
        scrollBar:SetPoint("BOTTOM", scrollBarContainer, "BOTTOM", 0, 0)
    end
    -- Fixed width (never stretch): bar and buttons stay barWidth/btnSize so all windows look identical
    scrollBar:SetWidth(barWidth)
    scrollBar:SetPoint("CENTER", scrollBarContainer, "CENTER", 0, 0)
end

---Update scroll bar visibility based on content height (call after content changes)
---@param scrollFrame ScrollFrame The scroll frame to update
function ns.UI.Factory:UpdateScrollBarVisibility(scrollFrame)
    if scrollFrame and scrollFrame.UpdateScrollBarVisibility then
        scrollFrame:UpdateScrollBarVisibility()
    end
end

---Create a horizontal scrollbar matching the vertical scrollbar style.
---Usage: attach to an existing ScrollFrame and call UpdateHorizontalScrollBarVisibility after content width changes.
---@param scrollFrame ScrollFrame Target scroll frame (SetHorizontalScroll target)
---@param parent Frame Parent frame for the horizontal bar and buttons
---@param customStyle boolean|nil If true, applies custom modern styling (default: true)
---@return Slider|nil hBar The created horizontal slider
function ns.UI.Factory:CreateHorizontalScrollBar(scrollFrame, parent, customStyle)
    if not scrollFrame or not parent then return nil end
    if customStyle == false then return nil end

    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local btnSize = layout.SCROLL_BAR_BUTTON_SIZE or 16
    local barHeight = layout.SCROLL_BAR_WIDTH or 16

    local function GetScrollStep()
        local addon = _G.WarbandNexus or ns.WarbandNexus
        local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
        local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
        return math.floor(base * speed + 0.5)
    end

    local hBar = CreateFrame("Slider", nil, parent)
    hBar:SetOrientation("HORIZONTAL")
    hBar:SetMinMaxValues(0, 0)
    hBar:SetValueStep(1)
    hBar:SetObeyStepOnDrag(true)
    hBar:SetHeight(barHeight)
    hBar:Hide()

    -- Track background
    hBar.CustomTrack = hBar:CreateTexture(nil, "BACKGROUND")
    hBar.CustomTrack:SetAllPoints(hBar)
    hBar.CustomTrack:SetColorTexture(0.08, 0.08, 0.10, 0.9)

    -- Pixel borders
    local pixelScale = GetPixelScale()
    hBar.BorderLeft = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderLeft:SetPoint("TOPLEFT", hBar, "TOPLEFT", 0, 0)
    hBar.BorderLeft:SetPoint("BOTTOMLEFT", hBar, "BOTTOMLEFT", 0, 0)
    hBar.BorderLeft:SetWidth(pixelScale)
    hBar.BorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar.BorderRight = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderRight:SetPoint("TOPRIGHT", hBar, "TOPRIGHT", 0, 0)
    hBar.BorderRight:SetPoint("BOTTOMRIGHT", hBar, "BOTTOMRIGHT", 0, 0)
    hBar.BorderRight:SetWidth(pixelScale)
    hBar.BorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar.BorderTop = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderTop:SetPoint("TOPLEFT", hBar, "TOPLEFT", 0, 0)
    hBar.BorderTop:SetPoint("TOPRIGHT", hBar, "TOPRIGHT", 0, 0)
    hBar.BorderTop:SetHeight(pixelScale)
    hBar.BorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar.BorderBottom = hBar:CreateTexture(nil, "BORDER")
    hBar.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    hBar.BorderBottom:SetPoint("BOTTOMLEFT", hBar, "BOTTOMLEFT", 0, 0)
    hBar.BorderBottom:SetPoint("BOTTOMRIGHT", hBar, "BOTTOMRIGHT", 0, 0)
    hBar.BorderBottom:SetHeight(pixelScale)
    hBar.BorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)

    hBar._borderType = "accent"
    hBar._borderAlpha = 0.6
    table.insert(ns.BORDER_REGISTRY, hBar)

    -- Thumb: same thickness as vertical (14px); width 60
    hBar.ThumbTexture = hBar:CreateTexture(nil, "ARTWORK")
    hBar.ThumbTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    hBar.ThumbTexture:SetSize(60, 14)
    hBar:SetThumbTexture(hBar.ThumbTexture)
    hBar._thumbTexture = hBar.ThumbTexture

    -- Left button
    hBar.ScrollLeftBtn = CreateFrame("Button", nil, parent)
    hBar.ScrollLeftBtn:SetSize(btnSize, btnSize)
    hBar.ScrollLeftBtn:Hide()
    local leftBg = hBar.ScrollLeftBtn:CreateTexture(nil, "BACKGROUND")
    leftBg:SetAllPoints()
    leftBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
    hBar.ScrollLeftBtn.bg = leftBg
    local leftBorderTop = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderTop:SetPoint("TOPLEFT", 0, 0)
    leftBorderTop:SetPoint("TOPRIGHT", 0, 0)
    leftBorderTop:SetHeight(pixelScale)
    leftBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local leftBorderBottom = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    leftBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    leftBorderBottom:SetHeight(pixelScale)
    leftBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local leftBorderLeft = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderLeft:SetPoint("TOPLEFT", 0, 0)
    leftBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    leftBorderLeft:SetWidth(pixelScale)
    leftBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local leftBorderRight = hBar.ScrollLeftBtn:CreateTexture(nil, "BORDER")
    leftBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    leftBorderRight:SetPoint("TOPRIGHT", 0, 0)
    leftBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    leftBorderRight:SetWidth(pixelScale)
    leftBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    hBar.ScrollLeftBtn.BorderTop = leftBorderTop
    hBar.ScrollLeftBtn.BorderBottom = leftBorderBottom
    hBar.ScrollLeftBtn.BorderLeft = leftBorderLeft
    hBar.ScrollLeftBtn.BorderRight = leftBorderRight
    hBar.ScrollLeftBtn._borderType = "accent"
    hBar.ScrollLeftBtn._borderAlpha = 0.6
    table.insert(ns.BORDER_REGISTRY, hBar.ScrollLeftBtn)
    -- Icon: common-icon-offscreen (default left); accent color
    local leftIcon = hBar.ScrollLeftBtn:CreateTexture(nil, "ARTWORK")
    leftIcon:SetSize(12, 12)
    leftIcon:SetPoint("CENTER")
    leftIcon:SetAtlas("common-icon-offscreen", false)
    leftIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    hBar.ScrollLeftBtn.icon = leftIcon
    hBar.ScrollLeftBtn._iconTexture = leftIcon

    -- Right button
    hBar.ScrollRightBtn = CreateFrame("Button", nil, parent)
    hBar.ScrollRightBtn:SetSize(btnSize, btnSize)
    hBar.ScrollRightBtn:Hide()
    local rightBg = hBar.ScrollRightBtn:CreateTexture(nil, "BACKGROUND")
    rightBg:SetAllPoints()
    rightBg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
    hBar.ScrollRightBtn.bg = rightBg
    local rightBorderTop = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderTop:SetPoint("TOPLEFT", 0, 0)
    rightBorderTop:SetPoint("TOPRIGHT", 0, 0)
    rightBorderTop:SetHeight(pixelScale)
    rightBorderTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local rightBorderBottom = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderBottom:SetPoint("BOTTOMLEFT", 0, 0)
    rightBorderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
    rightBorderBottom:SetHeight(pixelScale)
    rightBorderBottom:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local rightBorderLeft = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderLeft:SetPoint("TOPLEFT", 0, 0)
    rightBorderLeft:SetPoint("BOTTOMLEFT", 0, 0)
    rightBorderLeft:SetWidth(pixelScale)
    rightBorderLeft:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    local rightBorderRight = hBar.ScrollRightBtn:CreateTexture(nil, "BORDER")
    rightBorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
    rightBorderRight:SetPoint("TOPRIGHT", 0, 0)
    rightBorderRight:SetPoint("BOTTOMRIGHT", 0, 0)
    rightBorderRight:SetWidth(pixelScale)
    rightBorderRight:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6)
    hBar.ScrollRightBtn.BorderTop = rightBorderTop
    hBar.ScrollRightBtn.BorderBottom = rightBorderBottom
    hBar.ScrollRightBtn.BorderLeft = rightBorderLeft
    hBar.ScrollRightBtn.BorderRight = rightBorderRight
    hBar.ScrollRightBtn._borderType = "accent"
    hBar.ScrollRightBtn._borderAlpha = 0.6
    table.insert(ns.BORDER_REGISTRY, hBar.ScrollRightBtn)
    -- Icon: common-icon-offscreen rotated 180° (right)
    local rightIcon = hBar.ScrollRightBtn:CreateTexture(nil, "ARTWORK")
    rightIcon:SetSize(12, 12)
    rightIcon:SetPoint("CENTER")
    rightIcon:SetAtlas("common-icon-offscreen", false)
    rightIcon:SetRotation(math.pi)
    rightIcon:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
    hBar.ScrollRightBtn.icon = rightIcon
    hBar.ScrollRightBtn._iconTexture = rightIcon

    local function ButtonHoverOn(self)
        local currentColors = GetColors()
        self.bg:SetColorTexture(currentColors.accent[1] * 0.3, currentColors.accent[2] * 0.3, currentColors.accent[3] * 0.3, 1)
        self.icon:SetVertexColor(currentColors.accent[1] * 1.3, currentColors.accent[2] * 1.3, currentColors.accent[3] * 1.3, 1)
    end
    local function ButtonHoverOff(self)
        local currentColors = GetColors()
        self.bg:SetColorTexture(0.08, 0.08, 0.10, 0.9)
        self.icon:SetVertexColor(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 1)
    end
    hBar.ScrollLeftBtn:SetScript("OnEnter", ButtonHoverOn)
    hBar.ScrollLeftBtn:SetScript("OnLeave", ButtonHoverOff)
    hBar.ScrollRightBtn:SetScript("OnEnter", ButtonHoverOn)
    hBar.ScrollRightBtn:SetScript("OnLeave", ButtonHoverOff)

    hBar:SetScript("OnEnter", function(self)
        if self.ThumbTexture then
            local currentColors = GetColors()
            self.ThumbTexture:SetColorTexture(currentColors.accent[1] * 1.2, currentColors.accent[2] * 1.2, currentColors.accent[3] * 1.2, 1)
        end
    end)
    hBar:SetScript("OnLeave", function(self)
        if self.ThumbTexture then
            local currentColors = GetColors()
            self.ThumbTexture:SetColorTexture(currentColors.accent[1], currentColors.accent[2], currentColors.accent[3], 0.9)
        end
    end)

    hBar._scrollFrame = scrollFrame
    hBar:SetScript("OnValueChanged", function(self, value)
        if self._scrollFrame and self._scrollFrame.SetHorizontalScroll then
            self._scrollFrame:SetHorizontalScroll(value)
        end
    end)

    hBar.ScrollLeftBtn:SetScript("OnClick", function()
        local current = scrollFrame:GetHorizontalScroll() or 0
        scrollFrame:SetHorizontalScroll(math.max(0, current - GetScrollStep()))
        hBar:SetValue(scrollFrame:GetHorizontalScroll() or 0)
    end)
    hBar.ScrollRightBtn:SetScript("OnClick", function()
        local current = scrollFrame:GetHorizontalScroll() or 0
        local getRange = scrollFrame.GetHorizontalScrollRange
        local maxScroll = 0
        if getRange then
            maxScroll = math.max(0, getRange(scrollFrame) or 0)
        end
        scrollFrame:SetHorizontalScroll(math.min(maxScroll, current + GetScrollStep()))
        hBar:SetValue(scrollFrame:GetHorizontalScroll() or 0)
    end)

    -- Position helpers
    hBar.PositionInContainer = function(self, container, inset)
        if not container then return end
        local gap = (inset == nil) and 0 or inset
        local level = container:GetFrameLevel()

        self:SetParent(container)
        self:SetFrameLevel(level + 1)
        self:ClearAllPoints()
        self:SetPoint("LEFT", container, "LEFT", btnSize + gap, 0)
        self:SetPoint("RIGHT", container, "RIGHT", -(btnSize + gap), 0)
        self:SetPoint("CENTER", container, "CENTER", 0, 0)

        if self.ScrollLeftBtn then
            self.ScrollLeftBtn:SetParent(container)
            self.ScrollLeftBtn:SetFrameLevel(level + 3)
            self.ScrollLeftBtn:ClearAllPoints()
            self.ScrollLeftBtn:SetPoint("LEFT", container, "LEFT", 0, 0)
            self.ScrollLeftBtn:SetPoint("CENTER", container, "CENTER", 0, 0)
        end
        if self.ScrollRightBtn then
            self.ScrollRightBtn:SetParent(container)
            self.ScrollRightBtn:SetFrameLevel(level + 3)
            self.ScrollRightBtn:ClearAllPoints()
            self.ScrollRightBtn:SetPoint("RIGHT", container, "RIGHT", 0, 0)
            self.ScrollRightBtn:SetPoint("CENTER", container, "CENTER", 0, 0)
        end
    end

    scrollFrame.HorizontalScrollBar = hBar

    scrollFrame.UpdateHorizontalScrollBarVisibility = function(self)
        local bar = self.HorizontalScrollBar
        if not bar then return end
        local child = self:GetScrollChild()
        if not child then return end

        local contentWidth = child:GetWidth() or 0
        local frameWidth = self:GetWidth() or 0
        local maxScroll = math.max(0, contentWidth - frameWidth)
        bar:SetMinMaxValues(0, maxScroll)

        if maxScroll > 1 then
            bar:Show()
            if bar.ScrollLeftBtn then bar.ScrollLeftBtn:Show() end
            if bar.ScrollRightBtn then bar.ScrollRightBtn:Show() end
            local current = self:GetHorizontalScroll() or 0
            if current > maxScroll then
                current = maxScroll
                self:SetHorizontalScroll(current)
            end
            bar:SetValue(current)
        else
            self:SetHorizontalScroll(0)
            bar:SetValue(0)
            bar:Hide()
            if bar.ScrollLeftBtn then bar.ScrollLeftBtn:Hide() end
            if bar.ScrollRightBtn then bar.ScrollRightBtn:Hide() end
        end
    end

    return hBar
end

---Update horizontal scrollbar visibility based on content width (call after content changes)
---@param scrollFrame ScrollFrame The scroll frame to update
function ns.UI.Factory:UpdateHorizontalScrollBarVisibility(scrollFrame)
    if scrollFrame and scrollFrame.UpdateHorizontalScrollBarVisibility then
        scrollFrame:UpdateHorizontalScrollBarVisibility()
    end
end

---Return current scroll step (pixels per step) computed from base * speed multiplier.
---@return number
function ns.UI_GetScrollStep()
    local addon = _G.WarbandNexus or ns.WarbandNexus
    local base = (ns.UI_LAYOUT or {}).SCROLL_BASE_STEP or 28
    local speed = (addon and addon.db and addon.db.profile and addon.db.profile.scrollSpeed) or (ns.UI_LAYOUT or {}).SCROLL_SPEED_DEFAULT or 1.0
    return math.floor(base * speed + 0.5)
end

-- NOTE: CreateEditBox implementation moved to line 4816 (Factory pattern wrapper)
-- This duplicate implementation was removed to avoid confusion

-- ============================================================================
-- LOADING STATE WIDGETS (Standardized Progress Indicator)
-- ============================================================================

---Create standardized loading state card with animated spinner and progress bar
---@param parent Frame - Parent frame
---@param yOffset number - Y offset from top
---@param loadingState table - Loading state object with {isLoading, loadingProgress, currentStage, error}
---@param title string - Loading title (e.g., "Loading PvE Data")
---@return number newYOffset - New Y offset after card
function UI_CreateLoadingStateCard(parent, yOffset, loadingState, title)
    if not loadingState or not loadingState.isLoading then
        return yOffset
    end
    
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    local loadingCard = CreateCard(parent, 90)
    loadingCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    loadingCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Animated spinner
    local spinnerFrame = CreateIcon(loadingCard, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
    spinnerFrame:SetPoint("LEFT", 20, 0)
    spinnerFrame:Show()
    local spinner = spinnerFrame.texture
    
    -- Animate rotation
    local rotation = 0
    loadingCard:SetScript("OnUpdate", function(self, elapsed)
        rotation = rotation + (elapsed * 270)
        spinner:SetRotation(math.rad(rotation))
    end)
    
    -- Loading title
    local FontManager = ns.FontManager
    local loadingText = FontManager:CreateFontString(loadingCard, "title", "OVERLAY")
    loadingText:SetPoint("LEFT", spinner, "RIGHT", 15, 10)
    loadingText:SetText("|cff00ccff" .. (title or ((ns.L and ns.L["LOADING"]) or "Loading...")) .. "|r")
    
    -- Progress indicator
    local progressText = FontManager:CreateFontString(loadingCard, "body", "OVERLAY")
    progressText:SetPoint("LEFT", spinner, "RIGHT", 15, -8)
    
    local currentStage = loadingState.currentStage or ((ns.L and ns.L["PREPARING"]) or "Preparing")
    local progress = loadingState.loadingProgress or 0
    progressText:SetText(string.format("|cff888888%s - %d%%|r", currentStage, math.min(100, progress)))
    
    -- Hint text
    local hintText = FontManager:CreateFontString(loadingCard, "small", "OVERLAY")
    hintText:SetPoint("LEFT", spinner, "RIGHT", 15, -25)
    hintText:SetTextColor(0.6, 0.6, 0.6)
    hintText:SetText((ns.L and ns.L["PLEASE_WAIT"]) or "Please wait...")
    
    loadingCard:Show()
    
    return yOffset + 100
end

---Create standardized error state card
---@param parent Frame - Parent frame
---@param yOffset number - Y offset from top
---@param errorMessage string - Error message to display
---@return number newYOffset - New Y offset after card
function UI_CreateErrorStateCard(parent, yOffset, errorMessage)
    if not errorMessage or errorMessage == "" then
        return yOffset
    end
    
    local SIDE_MARGIN = UI_SPACING.SIDE_MARGIN
    local errorCard = CreateCard(parent, 60)
    errorCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    errorCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Warning icon
    local warningIconFrame = CreateIcon(errorCard, "services-icon-warning", 24, true, nil, true)
    warningIconFrame:SetPoint("LEFT", 20, 0)
    warningIconFrame:Show()
    
    -- Error message
    local FontManager = ns.FontManager
    local errorText = FontManager:CreateFontString(errorCard, "body", "OVERLAY")
    errorText:SetPoint("LEFT", warningIconFrame, "RIGHT", 10, 0)
    errorText:SetTextColor(1, 0.7, 0)
    errorText:SetText("|cffffcc00" .. errorMessage .. "|r")
    
    errorCard:Show()
    
    return yOffset + 70
end

---Create inline loading spinner (for small widgets like gold display)
---@param parent Frame - Parent frame
---@param anchorFrame Frame - Frame to anchor spinner next to
---@param anchorPoint string - Anchor point (e.g., "LEFT", "RIGHT")
---@param xOffset number - X offset from anchor
---@param yOffset number - Y offset from anchor
---@param size number - Spinner size (optional, default 16)
---@return Frame spinnerFrame - Spinner frame for cleanup
function UI_CreateInlineLoadingSpinner(parent, anchorFrame, anchorPoint, xOffset, yOffset, size)
    size = size or 16
    
    local spinnerFrame = CreateIcon(parent, "auctionhouse-ui-loadingspinner", size, true, nil, true)
    spinnerFrame:SetPoint(anchorPoint, anchorFrame, anchorPoint, xOffset, yOffset)
    spinnerFrame:Show()
    
    -- Animate rotation
    local rotation = 0
    parent:SetScript("OnUpdate", function(self, elapsed)
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
---@param parent Frame - Parent container to fill
---@return Frame panel - Panel with :ShowLoading() / :HideLoading()
local function UI_CreateLoadingStatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetAllPoints(parent)
    ApplyVisuals(panel, {0.06, 0.06, 0.08, 0.98}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.4})
    panel:SetFrameLevel(parent:GetFrameLevel() + 10)
    panel:Hide()

    -- Spinner (same atlas as transient card)
    local spinnerFrame = CreateIcon(panel, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
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
    local titleText = FM:CreateFontString(panel, "title", "OVERLAY")
    titleText:SetPoint("TOP", spinnerFrame, "BOTTOM", 0, -10)
    titleText:SetJustifyH("CENTER")
    panel._titleText = titleText

    -- Progress text (stage + %)
    local progressText = FM:CreateFontString(panel, "body", "OVERLAY")
    progressText:SetPoint("TOP", titleText, "BOTTOM", 0, -6)
    progressText:SetJustifyH("CENTER")
    progressText:SetTextColor(0.55, 0.55, 0.55)
    panel._progressText = progressText

    -- Progress bar
    local BAR_W = 200
    local barBg = panel:CreateTexture(nil, "ARTWORK")
    barBg:SetSize(BAR_W, 4)
    barBg:SetPoint("TOP", progressText, "BOTTOM", 0, -8)
    barBg:SetColorTexture(0.15, 0.15, 0.18, 1)
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

--============================================================================
-- FACTORY PATTERN BRIDGE (ns.UI.Factory.* → Local Functions)
--============================================================================
-- Bridge ns.UI.Factory calls to internal functions
-- Ensures PlansUI and other modules can use Factory pattern

--- Create a basic frame container (NO BORDERS by default)
---@param parent Frame - Parent frame
---@param width number - Container width (optional)
---@param height number - Container height (optional)
---@param withBorder boolean - If true, apply border (default: false)
---@return Frame container
function ns.UI.Factory:CreateContainer(parent, width, height, withBorder)
    if not parent then return nil end
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 100, height or 100)
    
    -- ONLY apply border if explicitly requested
    if withBorder then
        ApplyVisuals(container, {0.08, 0.08, 0.10, 1}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    return container
end

--- Create a button with theme
---@param parent Frame - Parent frame
---@param width number - Button width
---@param height number - Button height
---@param noBorder boolean|nil - If true, skip border (default false)
---@return Button button
function ns.UI.Factory:CreateButton(parent, width, height, noBorder)
    return CreateButton(parent, width, height, nil, nil, noBorder)
end

--- Create an EditBox
---@param parent Frame - Parent frame
---@return EditBox editbox
function ns.UI.Factory:CreateEditBox(parent)
    if not parent then return nil end
    
    local editBox = CreateFrame("EditBox", nil, parent)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal) -- required initial FontObject (WoW crashes without one)
    if ns.FontManager then
        local path = ns.FontManager:GetFontFace()
        local size = ns.FontManager:GetFontSize("body")
        local flags = ns.FontManager:GetAAFlags()
        pcall(editBox.SetFont, editBox, path, size, flags)
    end
    editBox:SetMaxLetters(256)
    editBox:SetTextInsets(5, 5, 0, 0)
    
    -- Scripts for better UX
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    return editBox
end

--- Apply alternating row background color to any frame.
--- Central helper that replaces inline ROW_COLOR_EVEN/ODD logic across all tabs.
--- Works with both newly created rows and pooled/reused rows.
---@param row Frame - The row frame to apply background to
---@param rowIndex number - Row index for even/odd alternation (1-based)
function ns.UI.Factory:ApplyRowBackground(row, rowIndex)
    if not row then return end
    local bgColor = (rowIndex % 2 == 0) and UI_SPACING.ROW_COLOR_EVEN or UI_SPACING.ROW_COLOR_ODD
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    row.bgColor = bgColor
end


--- Create a data row with alternating background color.
--- Standard pattern for creating new rows with proper positioning and alternating bg.
--- For pooled/reused rows, use Factory:ApplyRowBackground() instead.
---@param parent Frame - Parent frame (scrollChild)
---@param yOffset number - Current vertical offset
---@param rowIndex number - Row index for even/odd alternation (1-based)
---@param height number|nil - Row height (defaults to UI_SPACING.ROW_HEIGHT = 26)
---@return Frame row, number newYOffset
function ns.UI.Factory:CreateDataRow(parent, yOffset, rowIndex, height)
    if not parent then return nil, yOffset end

    local h = height or UI_SPACING.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    row:Show()

    self:ApplyRowBackground(row, rowIndex)

    return row, yOffset + h
end

--- Create a collapsible section header with border, arrow, title, hover.
--- Uses ApplyVisuals for consistent border rendering (same as CharactersUI/PlansUI headers).
---@param parent Frame - Parent frame (scrollChild)
---@param yOffset number - Current vertical offset
---@param isCollapsed boolean - Current collapse state
---@param titleStr string - Formatted title string (with color codes)
---@param rightStr string|nil - Optional right-aligned text
---@param onToggle function - Callback when header is clicked
---@param height number|nil - Header height (defaults to UI_SPACING.HEADER_HEIGHT = 32)
---@param leftIndent number|nil - Left indent in pixels (for sub-headers, e.g. 15 or 30)
---@return number newYOffset
function ns.UI.Factory:CreateSectionHeader(parent, yOffset, isCollapsed, titleStr, rightStr, onToggle, height, leftIndent)
    if not parent then return yOffset end

    local h = height or UI_SPACING.HEADER_HEIGHT
    local indent = leftIndent or 0
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(h)
    header:SetPoint("TOPLEFT", indent, -yOffset)
    header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    -- Draw above virtual-scroll row frames so nothing shows through behind header
    header:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    header:Show()

    -- Opaque background (1.0) so row text does not show through behind header
    ApplyVisuals(header, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})

    -- Collapse/expand arrow
    local collapseBtn = ns.UI.Factory:CreateButton(header, 16, 16, true)
    collapseBtn:SetPoint("LEFT", UI_SPACING.SIDE_MARGIN - 2, 0)
    local arrowTex = collapseBtn:CreateTexture(nil, "ARTWORK")
    arrowTex:SetAllPoints()
    if isCollapsed then
        arrowTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
    else
        arrowTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
    end

    -- Title text
    local title = FontManager:CreateFontString(header, "body", "OVERLAY")
    title:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)

    -- Right-side text (optional)
    if rightStr then
        local rightLabel = FontManager:CreateFontString(header, "body", "OVERLAY")
        rightLabel:SetPoint("RIGHT", header, "RIGHT", -UI_SPACING.SIDE_MARGIN, 0)
        rightLabel:SetJustifyH("RIGHT")
        rightLabel:SetText(rightStr)
        title:SetPoint("RIGHT", rightLabel, "LEFT", -6, 0)
    end

    title:SetText(titleStr)

    -- Click handlers
    header:SetScript("OnClick", onToggle)
    collapseBtn:SetScript("OnClick", onToggle)

    -- Hover highlight
    header:SetScript("OnEnter", function()
        if header.SetBackdropColor then
            header:SetBackdropColor(0.12, 0.12, 0.15, 1)
        end
    end)
    header:SetScript("OnLeave", function()
        if header.SetBackdropColor then
            header:SetBackdropColor(0.08, 0.08, 0.10, 1)
        end
    end)

    return yOffset + h
end

--- Collection list row: status icon (check/cross) + item icon + label. Same layout for Mounts, Pets, Achievements.
--- Caller sets position (virtual scroll). Use ApplyCollectionListRowContent to set content and selection.
---@param parent Frame - Parent (e.g. scrollChild)
---@param height number|nil - Row height (defaults to UI_SPACING.ROW_HEIGHT)
---@return Frame row
function ns.UI.Factory:CreateCollectionListRow(parent, height)
    if not parent then return nil end
    local h = height or UI_SPACING.ROW_HEIGHT
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(h)
    row:EnableMouse(true)

    local pad = UI_SPACING.SIDE_MARGIN or 10
    local gap = 4
    local statusSize = 16
    local iconSize = UI_SPACING.ROW_ICON_SIZE or 20

    local statusIcon = row:CreateTexture(nil, "ARTWORK")
    statusIcon:SetSize(statusSize, statusSize)
    statusIcon:SetPoint("LEFT", pad, 0)
    row.statusIcon = statusIcon

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local label = FontManager:CreateFontString(row, "body", "OVERLAY")
    label:SetPoint("LEFT", icon, "RIGHT", gap, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    return row
end

local COLLECTION_ROW_ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local COLLECTION_ROW_ICON_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

--- Apply content and selection to a collection list row (from CreateCollectionListRow). Use for virtual scroll.
---@param row Frame - Row from CreateCollectionListRow
---@param rowIndex number - For alternating background (1-based)
---@param iconPath string - Texture path for item icon
---@param labelText string - Formatted label (e.g. "|cff33e533Name|r" or "|cffffffffName|r (10 pts)")
---@param isCollected boolean - True = check icon, false = cross icon
---@param isSelected boolean - Show selection highlight
---@param onClick function|nil - OnMouseDown script
function ns.UI.Factory:ApplyCollectionListRowContent(row, rowIndex, iconPath, labelText, isCollected, isSelected, onClick)
    if not row then return end
    self:ApplyRowBackground(row, rowIndex or 1)
    if row.statusIcon then
        row.statusIcon:SetTexture(isCollected and COLLECTION_ROW_ICON_READY or COLLECTION_ROW_ICON_NOT_READY)
        row.statusIcon:Show()
    end
    if row.icon then
        local iconTex = (iconPath and iconPath ~= "") and iconPath or "Interface\\Icons\\Achievement_General"
        row.icon:SetTexture(iconTex)
        row.icon:Show()
    end
    if row.label then row.label:SetText(labelText or "") end
    row:SetScript("OnMouseDown", onClick)
    if not row.selBg then
        row.selBg = row:CreateTexture(nil, "BORDER")
        row.selBg:SetAllPoints()
    end
    if isSelected then
        local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
        row.selBg:SetColorTexture(r, g, b, 0.25)
        row.selBg:Show()
    else
        row.selBg:Hide()
    end
end

--============================================================================
-- WOWHEAD URL COPY POPUP
--============================================================================

local wowheadCopyFrame = nil

---Show a small popup with a Wowhead URL for the user to copy (Ctrl+C).
---@param entityType string "mount"|"pet"|"toy"|"achievement"|"item"|"quest"|"spell"|"npc"|"currency"|"illusion"|"title"
---@param id number
---@param anchorFrame Frame|nil Optional frame to anchor near (defaults to UIParent center)
function ns.UI.Factory:ShowWowheadCopyURL(entityType, id, anchorFrame)
    if not ns.Utilities or not ns.Utilities.GetWowheadURL then return end
    local url = ns.Utilities:GetWowheadURL(entityType, id)
    if not url then return end

    if not wowheadCopyFrame then
        local f = CreateFrame("Frame", "WarbandNexus_WowheadCopy", UIParent, "BackdropTemplate")
        f:SetSize(360, 60)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(500)
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
        local COLORS = ns.UI_COLORS or { accent = {0.5, 0.4, 0.7} }
        f:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText("|cffffcc00Wowhead|r  |cff888888Ctrl+C|r")
        f._title = title

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", -2, -2)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        editBox:SetSize(336, 22)
        editBox:SetPoint("BOTTOMLEFT", 12, 8)
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(512)
        if FontManager then
            local path = FontManager:GetFontFace()
            local size = FontManager:GetFontSize("body")
            local flags = FontManager:GetAAFlags()
            pcall(editBox.SetFont, editBox, path, size, flags)
        end
        editBox:SetScript("OnEscapePressed", function() f:Hide() end)
        editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        editBox:SetScript("OnChar", function(self) self:SetText(f._url or ""); self:HighlightText() end)
        f._editBox = editBox

        wowheadCopyFrame = f
    end

    wowheadCopyFrame._url = url
    wowheadCopyFrame._editBox:SetText(url)

    if anchorFrame and anchorFrame.GetCenter then
        wowheadCopyFrame:ClearAllPoints()
        wowheadCopyFrame:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -4)
    else
        wowheadCopyFrame:ClearAllPoints()
        wowheadCopyFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end

    wowheadCopyFrame:Show()
    wowheadCopyFrame._editBox:SetFocus()
    wowheadCopyFrame._editBox:HighlightText()
end

-- Load message
-- Factory loaded - verbose logging hidden (debug mode only)
