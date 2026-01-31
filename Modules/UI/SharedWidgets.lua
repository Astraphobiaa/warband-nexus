--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

--============================================================================
-- PIXEL PERFECT HELPERS
--============================================================================

-- Cached pixel scale (calculated once per UI load, reused everywhere)
-- Cache for pixel scale (automatically invalidated on scale changes)
local mult = nil

-- Event frame to handle UI scale and display changes
local scaleHandler = CreateFrame("Frame")
scaleHandler:RegisterEvent("UI_SCALE_CHANGED")
scaleHandler:RegisterEvent("DISPLAY_SIZE_CHANGED")
scaleHandler:SetScript("OnEvent", function(self, event)
    mult = nil  -- Invalidate cache
end)

-- Calculate exact pixel size for 1px borders
-- Uses GAME RESOLUTION (not physical monitor pixels)
local function GetPixelScale()
    if mult then return mult end
    
    -- Get game's render resolution (NOT physical screen size)
    local resolution = GetCVar("gxWindowedResolution") or GetCVar("gxFullscreenResolution") or "1920x1080"
    local width, height = string.match(resolution, "(%d+)x(%d+)")
    height = tonumber(height) or 1080
    
    -- Get UI Scale
    local uiScale = UIParent:GetScale()
    if not uiScale or uiScale == 0 then uiScale = 1 end
    
    -- Formula: (768 / GameHeight) / UIScale
    -- 768 is WoW's base UI coordinate system height
    mult = (768.0 / height) / uiScale
    
    return mult
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

-- Get theme colors from database (with fallbacks)
local function GetThemeColors()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local themeColors = db and db.themeColors or {}
    
    return {
        accent = themeColors.accent or {0.40, 0.20, 0.58},
        accentDark = themeColors.accentDark or {0.28, 0.14, 0.41},
        border = themeColors.border or {0.20, 0.20, 0.25},
        tabActive = themeColors.tabActive or {0.20, 0.12, 0.30},
        tabHover = themeColors.tabHover or {0.24, 0.14, 0.35},
    }
end

-- Modern Color Palette (Dynamic - updates from database)
local function GetColors()
    local theme = GetThemeColors()
    
    return {
        bg = {0.06, 0.06, 0.08, 0.98},
        bgLight = {0.10, 0.10, 0.12, 1},
        bgCard = {0.08, 0.08, 0.10, 1},
        border = {theme.border[1], theme.border[2], theme.border[3], 1},
        borderLight = {0.30, 0.30, 0.38, 1},
        accent = {theme.accent[1], theme.accent[2], theme.accent[3], 1},
        accentDark = {theme.accentDark[1], theme.accentDark[2], theme.accentDark[3], 1},
        tabActive = {theme.tabActive[1], theme.tabActive[2], theme.tabActive[3], 1},
        tabHover = {theme.tabHover[1], theme.tabHover[2], theme.tabHover[3], 1},
        tabInactive = {0.08, 0.08, 0.10, 1},
        gold = {1.00, 0.82, 0.00, 1},
        green = {0.30, 0.90, 0.30, 1},
        red = {0.95, 0.30, 0.30, 1},
        textBright = {1, 1, 1, 1},  -- Pure white for all text
        textNormal = {0.85, 0.85, 0.85, 1},
        textDim = {0.55, 0.55, 0.55, 1},
        white = {1, 1, 1, 1},  -- Global white color constant
    }
end

-- Create initial COLORS table
local COLORS = GetColors()
ns.UI_COLORS = COLORS -- Export immediately

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

-- Export to namespace
ns.UI_BUTTON_SIZES = BUTTON_SIZES

-- Refresh COLORS table from database
local function RefreshColors()
    -- Immediate update
    local newColors = GetColors()
    for k, v in pairs(newColors) do
        COLORS[k] = v
    end
    -- Also update the namespace reference
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

-- Apply background and 1px borders to any frame (ElvUI Sandwich Method)
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
        local pixelScale = GetPixelScale()  -- Pixel-perfect 1px thickness
        
        -- Top border (INSIDE frame, at the top edge)
        frame.BorderTop = frame:CreateTexture(nil, "BORDER")
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(pixelScale)  -- Pixel-perfect 1px
        -- CRITICAL: Allow sub-pixel smoothing (do NOT snap to grid)
        frame.BorderTop:SetSnapToPixelGrid(false)
        frame.BorderTop:SetTexelSnappingBias(0)
        frame.BorderTop:SetDrawLayer("BORDER", 0)
        
        -- Bottom border (INSIDE frame, at the bottom edge)
        frame.BorderBottom = frame:CreateTexture(nil, "BORDER")
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(pixelScale)  -- Pixel-perfect 1px
        -- CRITICAL: Allow sub-pixel smoothing (do NOT snap to grid)
        frame.BorderBottom:SetSnapToPixelGrid(false)
        frame.BorderBottom:SetTexelSnappingBias(0)
        frame.BorderBottom:SetDrawLayer("BORDER", 0)
        
        -- Left border (INSIDE frame, at the left edge, between top and bottom)
        frame.BorderLeft = frame:CreateTexture(nil, "BORDER")
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -pixelScale)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, pixelScale)
        frame.BorderLeft:SetWidth(pixelScale)  -- Pixel-perfect 1px
        -- CRITICAL: Allow sub-pixel smoothing (do NOT snap to grid)
        frame.BorderLeft:SetSnapToPixelGrid(false)
        frame.BorderLeft:SetTexelSnappingBias(0)
        frame.BorderLeft:SetDrawLayer("BORDER", 0)
        
        -- Right border (INSIDE frame, at the right edge, between top and bottom)
        frame.BorderRight = frame:CreateTexture(nil, "BORDER")
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -pixelScale)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, pixelScale)
        frame.BorderRight:SetWidth(pixelScale)  -- Pixel-perfect 1px
        -- CRITICAL: Allow sub-pixel smoothing (do NOT snap to grid)
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
    
    -- Register frame to namespace registry
    table.insert(ns.BORDER_REGISTRY, frame)
end

-- Export to namespace
ns.UI_ApplyVisuals = ApplyVisuals
ns.UI_ResetPixelScale = ResetPixelScale

-- Auto-reset pixel scale cache when UI scale changes
-- This ensures borders remain 1px after user changes UI scale via /reload
local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:SetScript("OnEvent", function(self, event)
    if event == "UI_SCALE_CHANGED" then
        ResetPixelScale()
        -- Note: Borders will update on next frame creation, existing frames keep current scale
    end
end)

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
    - Pixel-perfect borders (ElvUI sandwich method)
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
            tex:SetAtlas(texture, false)  -- false = don't use atlas size
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
    Create a pixel-perfect status bar (progress bar) with border
    @param parent frame - Parent frame
    @param width number - Bar width (default 200)
    @param height number - Bar height (default 14)
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default black)
    @return frame - StatusBar frame
]]
local function CreateStatusBar(parent, width, height, bgColor, borderColor)
    if not parent then return nil end
    
    width = width or 200
    height = height or 14
    bgColor = bgColor or {0.05, 0.05, 0.07, 0.95}
    borderColor = borderColor or {0, 0, 0, 1}
    
    -- Container frame
    local frame = CreateFrame("StatusBar", nil, parent)
    frame:SetSize(width, height)
    
    -- Apply pixel-perfect border
    ApplyVisuals(frame, bgColor, borderColor)
    
    -- Status bar texture (solid fill, inset by 1px to not overlap border)
    frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local barTexture = frame:GetStatusBarTexture()
    barTexture:SetDrawLayer("ARTWORK", 0)
    
    -- Anti-flicker optimization on bar texture
    barTexture:SetSnapToPixelGrid(false)
    barTexture:SetTexelSnappingBias(0)
    
    -- Default values
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

--[[
    Create a two-line button (character row style)
    Includes space for icon, main text, and sub text
    @param parent frame - Parent frame
    @param width number - Button width
    @param height number - Button height (default 38)
    @return button - Button with .icon, .mainText, .subText
]]
local function CreateTwoLineButton(parent, width, height)
    if not parent then return nil end
    
    height = height or 38
    
    -- Create button with border
    local button = CreateButton(parent, width, height)
    
    -- Icon (left side, inset by 5px from border)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(28, 28)
    button.icon:SetPoint("LEFT", 10, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Anti-flicker
    button.icon:SetSnapToPixelGrid(false)
    button.icon:SetTexelSnappingBias(0)
    
    -- Main text (upper line)
    button.mainText = FontManager:CreateFontString(button, "body", "OVERLAY")
    button.mainText:SetPoint("LEFT", button.icon, "RIGHT", 8, 6)
    button.mainText:SetJustifyH("LEFT")
    button.mainText:SetTextColor(1, 1, 1)
    
    -- Sub text (lower line, smaller)
    button.subText = FontManager:CreateFontString(button, "small", "OVERLAY")
    button.subText:SetPoint("LEFT", button.icon, "RIGHT", 8, -6)
    button.subText:SetJustifyH("LEFT")
    button.subText:SetTextColor(0.7, 0.7, 0.7)
    
    return button
end

--[[
    Create a reputation progress bar with dynamic fill and colors
    Handles Paragon, Renown, and Classic reputation systems
    @param parent frame - Parent frame (usually a row)
    @param width number - Bar width (default 200)
    @param height number - Bar height (default 14)
    @param currentValue number - Current reputation value
    @param maxValue number - Max reputation value
    @param isParagon boolean - If true, use paragon styling
    @param isMaxed boolean - If true, fill bar 100% and use green color
    @param standingID number - Standing ID for color (optional)
    @return bgFrame, fillTexture - Background frame and fill texture
]]
local function CreateReputationProgressBar(parent, width, height, currentValue, maxValue, isParagon, isMaxed, standingID)
    if not parent then return nil, nil end
    
    width = width or 200
    height = height or 14
    currentValue = currentValue or 0
    maxValue = maxValue or 1
    
    -- Background frame - set high frame level to ensure border and text are on top
    local bgFrame = CreateFrame("Frame", nil, parent)
    bgFrame:SetSize(width, height)
    bgFrame:SetFrameLevel(parent:GetFrameLevel() + 10)  -- High frame level for proper layering
    
    -- Border is 1px, so inset content by 1px on all sides for symmetry
    local borderInset = 1
    local contentWidth = width - (borderInset * 2)
    local contentHeight = height - (borderInset * 2)
    
    -- Background texture (dark) - inset by 1px to sit inside border
    local bgTexture = bgFrame:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", borderInset, -borderInset)
    bgTexture:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", -borderInset, borderInset)
    bgTexture:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    bgTexture:SetSnapToPixelGrid(false)
    bgTexture:SetTexelSnappingBias(0)
    
    -- Calculate progress (handle maxValue = 0 case)
    local progress = 0
    if maxValue > 0 then
        progress = currentValue / maxValue
        progress = math.min(1, math.max(0, progress))
    elseif maxValue == 0 and currentValue == 0 then
        -- Empty reputation with 0/0 - show as 0% progress
        progress = 0
    end
    
    -- If maxed and not paragon, fill 100%
    if isMaxed and not isParagon then
        progress = 1
    end
    
    -- Only create fill if there's progress
    -- Fill bar should be 1px inset from border (borderInset + 1 = 2px from frame edge)
    local fillInset = borderInset + 1  -- 2px total inset (1px border + 1px gap)
    local fillWidth = contentWidth - 2  -- Subtract 2px (1px on each side) for gap
    local fillHeight = contentHeight - 2  -- Subtract 2px (1px on each side) for gap
    
    local fillTexture = nil
    -- Always create fill if there's any value or if maxed (even if currentValue is 0, show empty bar)
    if (currentValue > 0 or isMaxed or maxValue > 0) then
        fillTexture = bgFrame:CreateTexture(nil, "ARTWORK")
        fillTexture:SetPoint("LEFT", bgFrame, "LEFT", fillInset, 0)
        fillTexture:SetPoint("TOP", bgFrame, "TOP", 0, -fillInset)
        fillTexture:SetPoint("BOTTOM", bgFrame, "BOTTOM", 0, fillInset)
        fillTexture:SetWidth(fillWidth * progress)
        fillTexture:SetSnapToPixelGrid(false)
        fillTexture:SetTexelSnappingBias(0)
        
        -- Color based on type
        if isMaxed and not isParagon then
            -- Maxed: Green
            fillTexture:SetColorTexture(0, 0.8, 0, 1)
        elseif isParagon then
            -- Paragon: Pink
            fillTexture:SetColorTexture(1, 0.4, 1, 1)
        elseif standingID then
            -- Use standing color
            local function GetStandingColor(standingID)
                local colors = {
                    [1] = {0.8, 0.13, 0.13}, -- Hated
                    [2] = {0.8, 0.13, 0.13}, -- Hostile
                    [3] = {0.75, 0.27, 0}, -- Unfriendly
                    [4] = {0.9, 0.7, 0}, -- Neutral
                    [5] = {0, 0.6, 0.1}, -- Friendly
                    [6] = {0, 0.6, 0.1}, -- Honored
                    [7] = {0, 0.6, 0.1}, -- Revered
                    [8] = {0, 0.6, 0.1}, -- Exalted
                }
                local color = colors[standingID] or {0.9, 0.7, 0}
                return color[1], color[2], color[3]
            end
            local r, g, b = GetStandingColor(standingID)
            fillTexture:SetColorTexture(r, g, b, 1)
        else
            -- Default: Gold (for Renown/Friendship)
            fillTexture:SetColorTexture(1, 0.82, 0, 1)
        end
    end
    
    -- Add border in BORDER layer (behind fill bar) for proper hierarchy
    -- Layer order: BACKGROUND < BORDER < ARTWORK < OVERLAY
    -- Border should be behind fill bar, so use BORDER layer
    local COLORS = ns.UI_COLORS or {accent = {0.4, 0.6, 1}}
    local accentColor = COLORS.accent or {0.4, 0.6, 1}
    
    -- Create borders in BORDER layer (behind ARTWORK fill bar)
    local borderColor = {accentColor[1], accentColor[2], accentColor[3], 0.6}
    local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
    
    -- Top border (BORDER layer - behind fill bar)
    if not bgFrame.BorderTop then
        bgFrame.BorderTop = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderTop:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", 0, 0)
        bgFrame.BorderTop:SetPoint("TOPRIGHT", bgFrame, "TOPRIGHT", 0, 0)
        bgFrame.BorderTop:SetHeight(1)
        bgFrame.BorderTop:SetSnapToPixelGrid(false)
        bgFrame.BorderTop:SetTexelSnappingBias(0)
        bgFrame.BorderTop:SetDrawLayer("BORDER", 0)
        bgFrame.BorderTop:SetVertexColor(r, g, b, a)
    end
    
    -- Bottom border
    if not bgFrame.BorderBottom then
        bgFrame.BorderBottom = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderBottom:SetPoint("BOTTOMLEFT", bgFrame, "BOTTOMLEFT", 0, 0)
        bgFrame.BorderBottom:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", 0, 0)
        bgFrame.BorderBottom:SetHeight(1)
        bgFrame.BorderBottom:SetSnapToPixelGrid(false)
        bgFrame.BorderBottom:SetTexelSnappingBias(0)
        bgFrame.BorderBottom:SetDrawLayer("BORDER", 0)
        bgFrame.BorderBottom:SetVertexColor(r, g, b, a)
    end
    
    -- Left border
    if not bgFrame.BorderLeft then
        bgFrame.BorderLeft = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderLeft:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", 0, -1)
        bgFrame.BorderLeft:SetPoint("BOTTOMLEFT", bgFrame, "BOTTOMLEFT", 0, 1)
        bgFrame.BorderLeft:SetWidth(1)
        bgFrame.BorderLeft:SetSnapToPixelGrid(false)
        bgFrame.BorderLeft:SetTexelSnappingBias(0)
        bgFrame.BorderLeft:SetDrawLayer("BORDER", 0)
        bgFrame.BorderLeft:SetVertexColor(r, g, b, a)
    end
    
    -- Right border
    if not bgFrame.BorderRight then
        bgFrame.BorderRight = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderRight:SetPoint("TOPRIGHT", bgFrame, "TOPRIGHT", 0, -1)
        bgFrame.BorderRight:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", 0, 1)
        bgFrame.BorderRight:SetWidth(1)
        bgFrame.BorderRight:SetSnapToPixelGrid(false)
        bgFrame.BorderRight:SetTexelSnappingBias(0)
        bgFrame.BorderRight:SetDrawLayer("BORDER", 0)
        bgFrame.BorderRight:SetVertexColor(r, g, b, a)
    end
    
    return bgFrame, fillTexture
end

-- Export factory functions to namespace
ns.UI_CreateIcon = CreateIcon
ns.UI_CreateStatusBar = CreateStatusBar
ns.UI_CreateButton = CreateButton
ns.UI_CreateTwoLineButton = CreateTwoLineButton
ns.UI_CreateReputationProgressBar = CreateReputationProgressBar
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
local function AcquireReputationRow(parent)
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
        local iconSize = UI_LAYOUT.rowIconSize
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
    row:SetSize(width, rowHeight or 26)
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
        local iconSize = UI_LAYOUT.rowIconSize
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
        
        -- Location text
        row.locationText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(72)  -- Increased by 20% (60 * 1.2 = 72)
        row.locationText:SetJustifyH("RIGHT")

        row.isPooled = true
        row.rowType = "item"  -- Mark as ItemRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- No border for items rows
    row:SetParent(parent)
    row:SetSize(width, rowHeight)
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
        
        -- Background texture removed (naked frame)
        
        -- Quantity text (left)
        row.qtyText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.rowIconSize
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
        
        -- Location text
        row.locationText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(72)  -- Increased by 20% (60 * 1.2 = 72)
        row.locationText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.isPooled = true
        row.rowType = "storage"  -- Mark as StorageRow
        
        -- Apply highlight effect (only on initial creation)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(row)
        end
    end
    
    -- No border for storage rows
    
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
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
                        print("|cffff0000WN DEBUG: Failed to clear OnClick on", childType, "at index", i, "|r")
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
    local card = CreateFrame("Frame", nil, parent)
    card:Hide()  -- HIDE during setup (prevent flickering)
    
    card:SetHeight(height or 100)
    
    -- Apply pixel-perfect visuals with accent border (ElvUI sandwich method)
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

--[[
    Format money compact (short version, only highest denomination)
    @param copper number - Total copper amount
    @param iconSize number - Icon size (optional, default 14)
    @return string - Compact formatted money string
]]
local function FormatMoneyCompact(copper, iconSize)
    -- Validate and sanitize inputs
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 14
    -- Clamp iconSize to safe range to prevent integer overflow in texture rendering
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end
    
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = math.floor(copper % 100)
    
    -- Show only the highest denomination
    if gold > 0 then
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t", goldStr, iconSize, iconSize)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t", silver, iconSize, iconSize)
    else
        return string.format("|cffeda55f%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t", copperAmount, iconSize, iconSize)
    end
end

-- Create collapsible header with expand/collapse button (NO pooling - headers are few)
local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture, isAtlas, indentLevel)
    -- Support for nested headers (indentLevel: 0 = root, 1 = child, etc.)
    indentLevel = indentLevel or 0
    local indent = indentLevel * UI_LAYOUT.BASE_INDENT
    
    -- Create new header (no pooling for headers - they're infrequent and context-specific)
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(parent:GetWidth() - 20 - indent, 32)
    
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
    
    -- Optional icon (supports both texture paths and atlas names)
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = header:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.headerIconSize
        categoryIcon:SetSize(iconSize, iconSize)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
        
        -- Use atlas if specified, otherwise texture path
        if isAtlas then
            categoryIcon:SetAtlas(iconTexture, false)
        else
            categoryIcon:SetTexture(iconTexture)
            -- Add texture coordinate padding for cleaner edges (only for textures, not atlas)
            categoryIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
    
    return header, expandIcon, categoryIcon
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
    
    Returns appropriate icon for currency category headers (Legacy, expansions, etc.)
    Note: Blizzard API does not provide icons for headers, so we use manual mapping
    
    @param headerName string - Header name (e.g., "Legacy", "War Within", "Season 3")
    @return string|nil - Texture path or nil if no icon
]]
local function GetCurrencyHeaderIcon(headerName)
    -- Legacy (all old expansions)
    if headerName:find("Legacy") then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    -- Current content
    elseif headerName:find("Season 3") or headerName:find("Season3") then
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
    return nil
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
local FAVORITE_ICON_TEXTURE = "Interface\\COMMON\\FavoritesIcon"
local FAVORITE_COLOR_ACTIVE = {1, 0.84, 0}  -- Gold
local FAVORITE_COLOR_INACTIVE = {0.5, 0.5, 0.5}  -- Gray

--[[
    Get favorite icon texture path (always same texture, color changes)
    @return string - Texture path
]]
local function GetFavoriteIconTexture()
    return FAVORITE_ICON_TEXTURE
end

--[[
    Apply favorite icon styling
    @param texture texture - Texture object to style
    @param isFavorite boolean - Whether character is favorited
]]
local function StyleFavoriteIcon(texture, isFavorite)
    texture:SetTexture(FAVORITE_ICON_TEXTURE)
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
    -- Make favorite icon 15% larger and shift 2px down
    local iconSize = size * 1.15
    local yOffset = y - 2  -- Negative moves down in WoW
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)  -- Keep button hitbox same size
    btn:SetPoint(point, x, yOffset)
    
    local icon = btn:CreateTexture(nil, "ARTWORK")
    -- Center the larger icon within the button
    local sizeDiff = (iconSize - size) / 2
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
    level = {
        width = 40,    -- Optimized: "80" centered
        spacing = 15,  -- Standardized to 15px
        total = 55,    -- 40 + 15
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
        width = 230,   -- 5 icons × 39px (195) + 4 gaps × 5px (20) + extra padding = 230px
        spacing = 0,   -- No spacing, tight fit
        total = 230,   -- 230 + 0
    },
    mythicKey = {
        width = 120,   -- Increased from 100 to 120 for more room (text was truncating)
        spacing = 15,  -- Standardized to 15px
        total = 135,   -- 120 + 15
    },
    reorder = {
        width = 60,    -- Move Up/Down buttons (widened for better visibility)
        spacing = 10,  -- Reduced spacing for right-aligned columns
        total = 70,    -- 60 + 10
    },
    lastSeen = {
        width = 80,    -- Widened for text display
        spacing = 10,  -- Reduced spacing for right-aligned columns
        total = 90,    -- 80 + 10
    },
    delete = {
        width = 40,    -- Delete button
        spacing = 10,  -- Reduced spacing for right-aligned columns
        total = 50,    -- 40 + 10
    },
}

--[[
    Calculate column offset from left
    @param columnKey string - Column key (e.g., "name", "level")
    @return number - X offset from left
]]
local function GetColumnOffset(columnKey)
    local offset = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "level", "itemLevel", "gold", "professions", "mythicKey", "reorder", "lastSeen", "delete"}
    
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
    local order = {"favorite", "faction", "race", "class", "name", "level", "itemLevel", "gold", "professions", "mythicKey", "reorder", "lastSeen", "delete"}
    
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

-- Exports
ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowTotalWidth = GetCharRowTotalWidth
ns.UI_CreateCharRowColumnDivider = CreateCharRowColumnDivider

--============================================================================
-- SORTABLE TABLE HEADER (Reusable for any table with sorting)
--============================================================================

--[[
    Creates a sortable table header with clickable columns
    
    @param parent - Parent frame
    @param columns - Array of column definitions:
        {
            {key="name", label="CHARACTER", align="LEFT", offset=12},
            {key="level", label="LEVEL", align="LEFT", offset=200},
            {key="gold", label="GOLD", align="RIGHT", offset=-120},
            {key="lastSeen", label="LAST SEEN", align="RIGHT", offset=-20}
        }
    @param width - Total header width
    @param onSortChanged - Callback: function(sortKey, isAscending)
    @param defaultSortKey - Initial sort column (optional)
    @param defaultAscending - Initial sort direction (optional, default true)
    
    @return header frame, getCurrentSort function
]]
local function CreateSortableTableHeader(parent, columns, width, onSortChanged, defaultSortKey, defaultAscending)
    -- State
    local currentSortKey = defaultSortKey or (columns[1] and columns[1].key)
    local isAscending = (defaultAscending ~= false) -- Default true

    -- Create header frame with backdrop (like collapsible headers)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, 28)
    
    -- Backdrop removed (naked frame)
    
    -- Column buttons
    local columnButtons = {}
    
    for i, col in ipairs(columns) do
        -- Create clickable button (no backdrop = no box!)
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width or 100, 28)
        
        if col.align == "LEFT" then
            btn:SetPoint("LEFT", col.offset or 0, 0)
        elseif col.align == "RIGHT" then
            btn:SetPoint("RIGHT", col.offset or 0, 0)
        else
            btn:SetPoint("CENTER", col.offset or 0, 0)
        end
        
        -- Label text (position based on alignment)
        btn.label = FontManager:CreateFontString(btn, "body", "OVERLAY")  -- Normal size font
        if col.align == "LEFT" then
            btn.label:SetPoint("LEFT", 5, 0)  -- Small padding
            btn.label:SetJustifyH("LEFT")
        elseif col.align == "RIGHT" then
            btn.label:SetPoint("RIGHT", -17, 0) -- Space for arrow on right
            btn.label:SetJustifyH("RIGHT")
        else
            btn.label:SetPoint("CENTER", -6, 0)
            btn.label:SetJustifyH("CENTER")
        end
        btn.label:SetText(col.label)
        btn.label:SetTextColor(1, 1, 1)  -- White text for all labels
        
        -- Sort arrow (^ ascending, v descending, - sortable)
        btn.arrow = FontManager:CreateFontString(btn, "body", "OVERLAY") -- Bigger font!
        if col.align == "RIGHT" then
            btn.arrow:SetPoint("RIGHT", 0, 0)
        else
            btn.arrow:SetPoint("LEFT", btn.label, "RIGHT", 4, 0)
        end
        btn.arrow:SetText("Ôùå") -- Default: sortable indicator
        btn.arrow:SetTextColor(1, 1, 1, 0.3) -- White with low alpha for inactive
        
        -- Update arrow visibility
        local function UpdateArrow()
            if currentSortKey == col.key then
                btn.arrow:SetText(isAscending and "Ôû▓" or "Ôû╝")
                btn.arrow:SetTextColor(0.6, 0.4, 0.8, 1) -- Brighter purple for active
                btn.label:SetTextColor(1, 1, 1) -- White for active column
            else
                btn.arrow:SetText("Ôùå") -- Sortable hint (diamond)
                btn.arrow:SetTextColor(1, 1, 1, 0.3) -- White with low alpha for inactive
                btn.label:SetTextColor(1, 1, 1) -- White
            end
        end
        
        UpdateArrow()
        
        -- Hover effect
        btn:SetScript("OnEnter", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(1, 1, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(1, 1, 1)  -- White
            end
        end)
        
        -- Click handler
        btn:SetScript("OnClick", function()
            if currentSortKey == col.key then
                -- Same column - toggle direction
                isAscending = not isAscending
            else
                -- New column - default to ascending
                currentSortKey = col.key
                isAscending = true
            end
            
            -- Update all arrows
            for _, otherBtn in pairs(columnButtons) do
                if otherBtn.updateArrow then
                    otherBtn.updateArrow()
                end
            end
            
            -- Notify parent
            if onSortChanged then
                onSortChanged(currentSortKey, isAscending)
            end
        end)
        
        btn.updateArrow = UpdateArrow
        columnButtons[i] = btn
    end
    
    -- Function to get current sort state
    local function GetCurrentSort()
        return currentSortKey, isAscending
    end
    
    return header, GetCurrentSort
end

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
    container.title:SetText(isSearch and "|cff666666No results|r" or "|cff666666No items cached|r")
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
            emptyMessage = "No items match '" .. displayText .. "'"
        else
            emptyMessage = "No items match your search"
        end
    else
        -- Check which tab we're on (look at global state)
        local currentSubTab = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "personal"
        if currentSubTab == "warband" then
            emptyMessage = "Open Warband Bank to scan items (auto-scanned on first visit)"
        else
            emptyMessage = "Items are scanned automatically. Try /reload if nothing appears."
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
-- CURRENCY TRANSFER POPUP
--============================================================================

--[[
    Create a currency transfer popup dialog
    @param currencyData table - Currency information
    @param currentCharacterKey string - Current character key
    @param onConfirm function - Callback(targetCharKey, amount)
    @return frame - Popup frame
]]
local function CreateCurrencyTransferPopup(currencyData, currentCharacterKey, onConfirm)
    -- Create backdrop overlay
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")  -- Highest strata
    overlay:SetFrameLevel(1000)
    overlay:SetAllPoints()
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)
    
    -- Create popup frame
    local popup = CreateFrame("Frame", nil, overlay)
    popup:SetSize(400, 380)  -- Increased height for instructions
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(overlay:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    
    -- Title
    local title = FontManager:CreateFontString(popup, "title", "OVERLAY")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cff6a0dadTransfer Currency|r")
    
    -- Get WarbandNexus and current character info
    local WarbandNexus = ns.WarbandNexus
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- From Character (current/online)
    local fromText = FontManager:CreateFontString(popup, "small", "OVERLAY")
    fromText:SetPoint("TOP", 0, -38)
    fromText:SetText(string.format("|cff888888From:|r |cff00ff00%s|r |cff888888(Online)|r", currentPlayerName))
    
    -- Currency Icon
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", 0, -65)
    if currencyData.iconFileID then
        icon:SetTexture(currencyData.iconFileID)
    end
    
    -- Currency Name
    local nameText = FontManager:CreateFontString(popup, "body", "OVERLAY")
    nameText:SetPoint("TOP", 0, -105)
    nameText:SetText(currencyData.name or "Unknown Currency")
    nameText:SetTextColor(1, 0.82, 0)
    
    -- Available Amount
    local availableText = FontManager:CreateFontString(popup, "small", "OVERLAY")
    availableText:SetPoint("TOP", 0, -125)
    availableText:SetText(string.format("|cff888888Available:|r |cffffffff%d|r", currencyData.quantity or 0))
    
    -- Amount Input Label
    local amountLabel = FontManager:CreateFontString(popup, "body", "OVERLAY")
    amountLabel:SetPoint("TOPLEFT", 30, -155)
    amountLabel:SetText("Amount:")
    
    -- Amount Input Box
    local amountBox = CreateFrame("EditBox", nil, popup)
    amountBox:SetSize(100, 28)
    amountBox:SetPoint("LEFT", amountLabel, "RIGHT", 10, 0)
    
    -- Use FontManager for consistent font styling
    local fontPath = FontManager:GetFontFace()
    local fontSize = FontManager:GetFontSize("body")
    local aa = FontManager:GetAAFlags()
    if fontPath and fontSize then
        amountBox:SetFont(fontPath, fontSize, aa)
    end
    
    amountBox:SetTextInsets(8, 8, 0, 0)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    amountBox:SetMaxLetters(10)
    amountBox:SetText("1")
    
    -- Max Button
    local maxBtn = CreateThemedButton(popup, "Max", 70)
    maxBtn:SetPoint("LEFT", amountBox, "RIGHT", 5, 0)
    maxBtn:SetScript("OnClick", function()
        amountBox:SetText(tostring(currencyData.quantity or 0))
    end)
    
    -- Confirm Button (create early so it can be referenced)
    local confirmBtn = CreateThemedButton(popup, "Open & Guide", 120)
    confirmBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    confirmBtn:Disable() -- Initially disabled until character selected
    
    -- Cancel Button
    local cancelBtn = CreateThemedButton(popup, "Cancel", 90)
    cancelBtn:SetPoint("RIGHT", confirmBtn, "LEFT", -5, 0)
    cancelBtn:SetScript("OnClick", function()
        overlay:Hide()
    end)
    
    -- Info note at bottom
    local infoNote = FontManager:CreateFontString(popup, "small", "OVERLAY")
    infoNote:SetPoint("BOTTOM", 0, 50)
    infoNote:SetWidth(360)
    infoNote:SetText("|cff00ff00Ô£ô|r Currency window will be opened automatically.\n|cff888888You'll need to manually right-click the currency to transfer.|r")
    infoNote:SetJustifyH("CENTER")
    infoNote:SetWordWrap(true)
    
    -- Target Character Label
    local targetLabel = FontManager:CreateFontString(popup, "body", "OVERLAY")
    targetLabel:SetPoint("TOPLEFT", 30, -195)
    targetLabel:SetText("To Character:")
    
    -- Get WarbandNexus addon reference
    local WarbandNexus = ns.WarbandNexus
    
    -- Build character list (exclude current character)
    local characterList = {}
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global.characters then
        for charKey, charData in pairs(WarbandNexus.db.global.characters) do
            -- Filter: Skip untracked characters
            if charKey ~= currentCharacterKey and charData.name and charData.isTracked ~= false then
                table.insert(characterList, {
                    key = charKey,
                    name = charData.name,
                    realm = charData.realm or "",
                    class = charData.class or "UNKNOWN",
                    level = charData.level or 0,
                })
            end
        end
        
        -- Sort by name
        table.sort(characterList, function(a, b) return a.name < b.name end)
    end
    
    -- Selected character
    local selectedTargetKey = nil
    local selectedCharData = nil
    
    -- Character selection dropdown container
    local charDropdown = CreateFrame("Frame", nil, popup)
    charDropdown:SetSize(320, 28)
    charDropdown:SetPoint("TOPLEFT", 30, -215)
    charDropdown:EnableMouse(true)
    
    local charText = FontManager:CreateFontString(charDropdown, "body", "OVERLAY")
    charText:SetPoint("LEFT", 10, 0)
    charText:SetText("|cff888888Select character...|r")
    charText:SetJustifyH("LEFT")
    
    -- Dropdown arrow icon
    local arrowIcon = charDropdown:CreateTexture(nil, "ARTWORK")
    arrowIcon:SetSize(16, 16)
    arrowIcon:SetPoint("RIGHT", -5, 0)
    arrowIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    
    -- Character list frame (dropdown menu)
    local charListFrame = CreateFrame("Frame", nil, popup)
    charListFrame:SetSize(320, math.min(#characterList * 28 + 4, 200))  -- Max 200px height
    charListFrame:SetPoint("TOPLEFT", charDropdown, "BOTTOMLEFT", 0, -2)
    charListFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    charListFrame:SetFrameLevel(popup:GetFrameLevel() + 20)
    charListFrame:Hide()  -- Initially hidden
    
    -- Scroll frame for character list (if many characters)
    local scrollFrame = CreateFrame("ScrollFrame", nil, charListFrame)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(316, #characterList * 28)
    
    -- Create character buttons
    for i, charData in ipairs(characterList) do
        local charBtn = CreateFrame("Button", nil, scrollChild)
        charBtn:SetSize(316, 26)
        charBtn:SetPoint("TOPLEFT", 0, -(i-1) * 28)
        
        -- Class color
        local classColor = RAID_CLASS_COLORS[charData.class] or {r=1, g=1, b=1}
        
        local btnText = FontManager:CreateFontString(charBtn, "body", "OVERLAY")
        btnText:SetPoint("LEFT", 8, 0)
        btnText:SetText(string.format("|c%s%s|r |cff888888(%d - %s)|r", 
            string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            charData.name,
            charData.level,
            charData.realm
        ))
        btnText:SetJustifyH("LEFT")
        
        -- Hover effects removed (no backdrop)
        charBtn:SetScript("OnClick", function(self)
            selectedTargetKey = charData.key
            selectedCharData = charData
            charText:SetText(string.format("|c%s%s|r", 
                string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
                charData.name
            ))
            charListFrame:Hide()
            confirmBtn:Enable()  -- Enable confirm button
        end)
    end
    
    -- Toggle dropdown
    charDropdown:SetScript("OnMouseDown", function(self)
        if charListFrame:IsShown() then
            charListFrame:Hide()
        else
            charListFrame:Show()
        end
    end)
    
    -- Set confirm button click handler (now that we have all variables)
    confirmBtn:SetScript("OnClick", function()
        local amount = tonumber(amountBox:GetText()) or 0
        if amount > 0 and amount <= (currencyData.quantity or 0) and selectedTargetKey and selectedCharData then
            -- STEP 1: Open Currency Frame (SAFE - No Taint)
            -- TWW (11.x) uses different frame name
            if not CharacterFrame or not CharacterFrame:IsShown() then
                ToggleCharacter("PaperDollFrame")
            end
            
            -- Switch to currency tab
            C_Timer.After(0.1, function()
                if CharacterFrame and CharacterFrame:IsShown() then
                    -- Click the Token (Currency) tab
                    if CharacterFrameTab4 then
                        CharacterFrameTab4:Click()
                    end
                end
            end)
            
            -- STEP 2: Try to expand currency categories (SAFE)
            C_Timer.After(0.3, function()
                -- Expand all currency categories so user can see target currency
                for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
                    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
                    if info and info.isHeader and not info.isHeaderExpanded then
                        C_CurrencyInfo.ExpandCurrencyList(i, true)
                    end
                end
            end)
            
            -- STEP 3: Show instructions in chat
            local WarbandNexus = ns.WarbandNexus
            if WarbandNexus then
                WarbandNexus:Print("|cff00ff00=== Currency Transfer Instructions ===|r")
                WarbandNexus:Print(string.format("|cffffaa00Currency:|r %s", currencyData.name))
                WarbandNexus:Print(string.format("|cffffaa00Amount:|r %d", amount))
                WarbandNexus:Print(string.format("|cffffaa00From:|r %s |cff888888(current character)|r", currentPlayerName))
                WarbandNexus:Print(string.format("|cffffaa00To:|r |cff00ff00%s|r", selectedCharData.name))
                WarbandNexus:Print(" ")
                WarbandNexus:Print("|cff00aaffNext steps:|r")
                WarbandNexus:Print("|cff00ff001.|r Find |cffffffff" .. currencyData.name .. "|r in the Currency window")
                WarbandNexus:Print("|cff00ff002.|r |cffff8800Right-click|r on it")
                WarbandNexus:Print("|cff00ff003.|r Select |cffffffff'Transfer to Warband'|r")
                WarbandNexus:Print("|cff00ff004.|r Choose |cff00ff00" .. selectedCharData.name .. "|r")
                WarbandNexus:Print("|cff00ff005.|r Enter amount: |cffffffff" .. amount .. "|r")
                WarbandNexus:Print(" ")
                WarbandNexus:Print("|cff00ff00Ô£ô|r Currency window is now open!")
                WarbandNexus:Print("|cff888888(Blizzard security prevents automatic transfer)|r")
            end
            
            overlay:Hide()
        end
    end)
    
    -- Store reference for cleanup
    overlay.popup = popup
    
    -- Show overlay
    overlay:Show()
    
    return overlay
end

--============================================================================
-- SHARED UI CONSTANTS
--============================================================================

local UI_CONSTANTS = {
    BUTTON_HEIGHT = 28,
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
    
    return btn
end

--============================================================================
-- SHARED CHECKBOX WIDGET
--============================================================================

--[[
    Create a themed checkbox with consistent styling
    @param parent - Parent frame
    @param initialState - Initial checked state (boolean)
    @return checkbox - Created checkbox
]]
local function CreateThemedCheckbox(parent, initialState)
    if not parent then
        print("WarbandNexus DEBUG: CreateThemedCheckbox called with nil parent!")
        return nil
    end
    
    local checkbox = CreateFrame("CheckButton", nil, parent)
    checkbox:SetSize(18, 18)  -- Increased from default for better visibility
    
    -- Apply border (default state)
    ApplyVisuals(checkbox, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Store border reference for hover effect
    checkbox.defaultBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    checkbox.hoverBorderColor = {COLORS.accent[1] * 1.3, COLORS.accent[2] * 1.3, COLORS.accent[3] * 1.3, 0.9}
    
    -- Green tick texture (brighter for better contrast)
    local checkTexture = checkbox:CreateTexture(nil, "OVERLAY")
    checkTexture:SetSize(16, 16)
    checkTexture:SetPoint("CENTER")
    checkTexture:SetTexture("Interface\\BUTTONS\\UI-CheckBox-Check")
    checkTexture:SetVertexColor(0.3, 0.95, 0.3, 1) -- Brighter green for better contrast
    checkbox.checkTexture = checkTexture
    
    if initialState then
        checkTexture:Show()
        checkbox:SetChecked(true)
    else
        checkTexture:Hide()
        checkbox:SetChecked(false)
    end
    
    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self.checkTexture:Show()
        else
            self.checkTexture:Hide()
        end
    end)
    
    -- Add hover effect
    checkbox:SetScript("OnEnter", function(self)
        if UpdateBorderColor then
            UpdateBorderColor(self, self.hoverBorderColor)
        end
    end)
    
    checkbox:SetScript("OnLeave", function(self)
        if UpdateBorderColor then
            UpdateBorderColor(self, self.defaultBorderColor)
        end
    end)
    
    return checkbox
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
-- EXPANDABLE ROW FACTORY
--============================================================================

--[[
    Create an expandable row for achievements/collections
    @param parent - Parent frame
    @param width - Row width
    @param rowHeight - Collapsed row height (default 32)
    @param data - Row data { icon, score, title, information, criteria }
    @param isExpanded - Initial expanded state
    @param onToggle - Callback function(isExpanded)
    @return row - Created expandable row frame
]]
local function CreateExpandableRow(parent, width, rowHeight, data, isExpanded, onToggle)
    if not parent then return nil end
    
    rowHeight = rowHeight or 34
    local COLORS = GetColors()
    
    -- Main container (will grow/shrink but header stays at top)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)
    row:SetHeight(rowHeight) -- Initial height
    
    -- Store state
    row.isExpanded = isExpanded or false
    row.data = data
    row.rowHeight = rowHeight
    row.onToggle = onToggle
    
    -- Alternating row color (set by caller based on index)
    row.bgColor = {0.08, 0.08, 0.10, 1}
    
    -- Header frame (FIXED HEIGHT, always visible at top) - Button for hover support
    local headerFrame = CreateFrame("Button", nil, row)
    headerFrame:SetPoint("TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", 0, 0)
    headerFrame:SetHeight(rowHeight)
    row.headerFrame = headerFrame
    
    -- Apply background and gradient border to header
    if ApplyVisuals then
        -- Gradient border: brighter at top, darker at bottom
        local borderColor = {
            COLORS.accent[1] * 0.8,
            COLORS.accent[2] * 0.8,
            COLORS.accent[3] * 0.8,
            0.4
        }
        ApplyVisuals(headerFrame, row.bgColor, borderColor)
    end
    
    -- Apply highlight effect
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(headerFrame)
    else
        -- Fallback: simple border
        if headerFrame.SetBackdrop then
            headerFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                tileSize = 1,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            headerFrame:SetBackdropColor(row.bgColor[1], row.bgColor[2], row.bgColor[3], row.bgColor[4])
            headerFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.5)
        end
    end
    
    -- Toggle function (header stays fixed, only details expand below)
    local function ToggleExpand()
        row.isExpanded = not row.isExpanded
        
        if row.isExpanded then
            -- Use atlas for up arrow (collapse)
            if row.expandBtnNormalTex then
                row.expandBtnNormalTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
            end
            if row.expandBtnHighlightTex then
                row.expandBtnHighlightTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
            end
            
            -- Create details frame if not exists (positioned BELOW header)
            if not row.detailsFrame then
                local detailsFrame = CreateFrame("Frame", nil, row)
                detailsFrame:SetPoint("TOPLEFT", row.headerFrame, "BOTTOMLEFT", 0, -1) -- -1 for seamless connection
                detailsFrame:SetPoint("TOPRIGHT", row.headerFrame, "BOTTOMRIGHT", 0, -1)
                
                -- Background and border for expanded section (darker gradient border)
                local detailsBgColor = {row.bgColor[1] * 0.7, row.bgColor[2] * 0.7, row.bgColor[3] * 0.7, 1}
                local detailsBorderColor = {
                    COLORS.accent[1] * 0.4,
                    COLORS.accent[2] * 0.4,
                    COLORS.accent[3] * 0.4,
                    0.6
                }
                
                if ApplyVisuals then
                    ApplyVisuals(detailsFrame, detailsBgColor, detailsBorderColor)
                else
                    -- Fallback
                    if detailsFrame.SetBackdrop then
                        detailsFrame:SetBackdrop({
                            bgFile = "Interface\\Buttons\\WHITE8X8",
                            edgeFile = "Interface\\Buttons\\WHITE8X8",
                            tile = false,
                            edgeSize = 1,
                            insets = { left = 0, right = 0, top = 0, bottom = 0 }
                        })
                        detailsFrame:SetBackdropColor(detailsBgColor[1], detailsBgColor[2], detailsBgColor[3], detailsBgColor[4])
                        detailsFrame:SetBackdropBorderColor(detailsBorderColor[1], detailsBorderColor[2], detailsBorderColor[3], detailsBorderColor[4])
                    end
                end
                
                -- Divider line between header and details
                local divider = detailsFrame:CreateTexture(nil, "OVERLAY")
                divider:SetTexture("Interface\\Buttons\\WHITE8X8")
                divider:SetHeight(1)
                divider:SetPoint("TOPLEFT", 0, 0)
                divider:SetPoint("TOPRIGHT", 0, 0)
                divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
                
                local yOffset = -8
                local leftMargin = 48
                local rightMargin = 16
                local sectionSpacing = 6
                
                -- Information Section (inline: "Description: text...")
                if data.information and data.information ~= "" then
                    -- Combined header + text in one line
                    local infoText = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
                    infoText:SetPoint("TOPLEFT", leftMargin, yOffset)
                    infoText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
                    infoText:SetJustifyH("LEFT")
                    infoText:SetText("|cff88cc88Description:|r |cffdddddd" .. data.information .. "|r")
                    infoText:SetWordWrap(true)
                    infoText:SetSpacing(2)
                    
                    local textHeight = infoText:GetStringHeight()
                    yOffset = yOffset - textHeight - sectionSpacing - 4
                end
                
                -- Criteria Section (Blizzard-style multi-column centered layout)
                if data.criteria and data.criteria ~= "" then
                    -- Split criteria into lines
                    local criteriaLines = {}
                    local progressLine = nil
                    local firstLine = true
                    for line in string.gmatch(data.criteria, "[^\n]+") do
                        if firstLine then
                            -- First line is the progress (e.g., "5 of 15 (33%)")
                            progressLine = line
                            firstLine = false
                        else
                            table.insert(criteriaLines, line)
                        end
                    end
                    
                    -- Section header with inline progress: "Requirements: 0 of 15 (0%)"
                    local headerText = "|cffffcc00Requirements:|r"
                    if progressLine then
                        headerText = headerText .. " " .. progressLine
                    end
                    
                    local criteriaHeader = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
                    criteriaHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
                    criteriaHeader:SetPoint("TOPRIGHT", -rightMargin, yOffset)
                    criteriaHeader:SetJustifyH("LEFT")
                    criteriaHeader:SetText(headerText)
                    
                    yOffset = yOffset - 20
                    
                    -- Create 3-column symmetric layout
                    if #criteriaLines > 0 then
                        local columnsPerRow = 3
                        -- Use row width instead of detailsFrame width (which might be 0)
                        local availableWidth = row:GetWidth() - leftMargin - rightMargin
                        local columnWidth = availableWidth / columnsPerRow
                        local currentRow = {}
                        
                        for i, line in ipairs(criteriaLines) do
                            table.insert(currentRow, line)
                            
                            -- When row is full OR last item, render the row
                            if #currentRow == columnsPerRow or i == #criteriaLines then
                                -- Create separate FontString for each column
                                for colIndex, criteriaText in ipairs(currentRow) do
                                    local xOffset = leftMargin + (colIndex - 1) * columnWidth
                                    
                                    local colLabel = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
                                    colLabel:SetPoint("TOPLEFT", xOffset, yOffset)
                                    colLabel:SetWidth(columnWidth)
                                    colLabel:SetJustifyH("LEFT")  -- Left align within column (bullets will align)
                                    colLabel:SetText("|cffeeeeee" .. criteriaText .. "|r")
                                    colLabel:SetWordWrap(false)
                                end
                                
                                yOffset = yOffset - 16
                                currentRow = {}
                            end
                        end
                        
                        yOffset = yOffset - sectionSpacing
                    end
                end
                
                -- Set height based on content (WoW-like: tight)
                local detailsHeight = math.abs(yOffset) + 8
                detailsFrame:SetHeight(detailsHeight)
                
                row.detailsFrame = detailsFrame
            end
            
            -- Show details and resize row
            row.detailsFrame:Show()
            local totalHeight = rowHeight + row.detailsFrame:GetHeight()
            row:SetHeight(totalHeight)
        else
            -- Use atlas for down arrow (expand)
            if row.expandBtnNormalTex then
                row.expandBtnNormalTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
            end
            if row.expandBtnHighlightTex then
                row.expandBtnHighlightTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
            end
            
            -- Hide details and collapse row
            if row.detailsFrame then
                row.detailsFrame:Hide()
            end
            row:SetHeight(rowHeight)
        end
        
        -- Callback
        if row.onToggle then
            row.onToggle(row.isExpanded)
        end
    end
    
    -- Expand/Collapse button (inside header) - Using atlas arrows
    local expandBtn = CreateFrame("Button", nil, headerFrame)
    expandBtn:SetSize(20, 20)
    expandBtn:SetPoint("LEFT", 6, 0)
    
    -- Create textures and set atlas
    local normalTex = expandBtn:CreateTexture(nil, "ARTWORK")
    normalTex:SetAllPoints()
    if isExpanded then
        normalTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
    else
        normalTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
    end
    expandBtn:SetNormalTexture(normalTex)
    
    local highlightTex = expandBtn:CreateTexture(nil, "HIGHLIGHT")
    highlightTex:SetAllPoints()
    if isExpanded then
        highlightTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
    else
        highlightTex:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Mouseover", true)
    end
    highlightTex:SetAlpha(0.3)
    expandBtn:SetHighlightTexture(highlightTex)
    
    -- Store texture references for toggle updates
    row.expandBtnNormalTex = normalTex
    row.expandBtnHighlightTex = highlightTex
    
    expandBtn:SetScript("OnClick", function()
        ToggleExpand()
    end)
    row.expandBtn = expandBtn
    
    -- Make entire header clickable for expand/collapse
    headerFrame:EnableMouse(true)
    headerFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            ToggleExpand()
        end
    end)
    
    -- Item Icon (after expand button) - WoW-like smaller
    if data.icon then
        local iconFrame = CreateIcon(headerFrame, data.icon, 28, false, nil, true)
        iconFrame:SetPoint("LEFT", 32, 0)
        iconFrame:Show()  -- CRITICAL: Show the row icon!
        row.iconFrame = iconFrame
    end
    
    -- Score (for achievements) or Type badge - WoW-like compact
    if data.score then
        local scoreText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
        scoreText:SetPoint("LEFT", 68, 0)
        scoreText:SetWidth(60)
        scoreText:SetJustifyH("LEFT")
        scoreText:SetText("|cffffd700" .. data.score .. " pts|r")
        row.scoreText = scoreText
    end
    
    -- Title - WoW-like normal font
    local titleText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
    titleText:SetPoint("LEFT", data.score and 134 or 68, 0)
    titleText:SetPoint("RIGHT", -90, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffffff" .. (data.title or "Unknown") .. "|r")
    titleText:SetWordWrap(false)
    row.titleText = titleText
    
    -- Expanded details container (created on demand)
    row.detailsFrame = nil
    
    -- Initialize expanded state (without triggering callbacks)
    if isExpanded then
        row.isExpanded = true
        -- Update textures to collapsed state (up arrow)
        if row.expandBtnNormalTex then
            row.expandBtnNormalTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
        end
        if row.expandBtnHighlightTex then
            row.expandBtnHighlightTex:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Mouseover", true)
        end
        
        -- Manually create and show details without calling ToggleExpand
        -- (to avoid triggering onToggle callback during initialization)
        -- CRITICAL: Details anchored BELOW header, not at row top
        local detailsFrame = CreateFrame("Frame", nil, row)
        detailsFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -1)
        detailsFrame:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -1)
        
        -- Background and border for expanded section
        local detailsBgColor = {row.bgColor[1] * 0.7, row.bgColor[2] * 0.7, row.bgColor[3] * 0.7, 1}
        local detailsBorderColor = {
            COLORS.accent[1] * 0.4,
            COLORS.accent[2] * 0.4,
            COLORS.accent[3] * 0.4,
            0.6
        }
        
        if ApplyVisuals then
            ApplyVisuals(detailsFrame, detailsBgColor, detailsBorderColor)
        else
            if detailsFrame.SetBackdrop then
                detailsFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    tile = false,
                    edgeSize = 1,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 }
                })
                detailsFrame:SetBackdropColor(detailsBgColor[1], detailsBgColor[2], detailsBgColor[3], detailsBgColor[4])
                detailsFrame:SetBackdropBorderColor(detailsBorderColor[1], detailsBorderColor[2], detailsBorderColor[3], detailsBorderColor[4])
            end
        end
        
        -- Divider line between header and details
        local divider = detailsFrame:CreateTexture(nil, "OVERLAY")
        divider:SetTexture("Interface\\Buttons\\WHITE8X8")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", 0, 0)
        divider:SetPoint("TOPRIGHT", 0, 0)
        divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
        
        local yOffset = -8
        local leftMargin = 48
        local rightMargin = 16
        local sectionSpacing = 6
        
        -- Information Section (inline: "Description: text...")
        if data.information and data.information ~= "" then
            -- Combined header + text in one line
            local infoText = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
            infoText:SetPoint("TOPLEFT", leftMargin, yOffset)
            infoText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
            infoText:SetJustifyH("LEFT")
            infoText:SetText("|cff88cc88Description:|r |cffdddddd" .. data.information .. "|r")
            infoText:SetWordWrap(true)
            infoText:SetSpacing(2)
            
            local textHeight = infoText:GetStringHeight()
            yOffset = yOffset - textHeight - sectionSpacing - 4
        end
        
        -- Criteria Section (Blizzard-style multi-column centered layout)
        if data.criteria and data.criteria ~= "" then
            -- Split criteria into lines
            local criteriaLines = {}
            local progressLine = nil
            local firstLine = true
            for line in string.gmatch(data.criteria, "[^\n]+") do
                if firstLine then
                    -- First line is the progress (e.g., "5 of 15 (33%)")
                    progressLine = line
                    firstLine = false
                else
                    table.insert(criteriaLines, line)
                end
            end
            
            -- Section header with inline progress: "Requirements: 0 of 15 (0%)"
            local headerText = "|cffffcc00Requirements:|r"
            if progressLine then
                headerText = headerText .. " " .. progressLine
            end
            
            local criteriaHeader = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
            criteriaHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
            criteriaHeader:SetPoint("TOPRIGHT", -rightMargin, yOffset)
            criteriaHeader:SetJustifyH("LEFT")
            criteriaHeader:SetText(headerText)
            
            yOffset = yOffset - 20
            
            -- Create 3-column symmetric layout
            if #criteriaLines > 0 then
                local columnsPerRow = 3
                -- Use row width instead of detailsFrame width
                local availableWidth = row:GetWidth() - leftMargin - rightMargin
                local columnWidth = availableWidth / columnsPerRow
                local currentRow = {}
                
                for i, line in ipairs(criteriaLines) do
                    table.insert(currentRow, line)
                    
                    -- When row is full OR last item, render the row
                    if #currentRow == columnsPerRow or i == #criteriaLines then
                        -- Create separate FontString for each column
                        for colIndex, criteriaText in ipairs(currentRow) do
                            local xOffset = leftMargin + (colIndex - 1) * columnWidth
                            
                            local colLabel = FontManager:CreateFontString(detailsFrame, "body", "OVERLAY")
                            colLabel:SetPoint("TOPLEFT", xOffset, yOffset)
                            colLabel:SetWidth(columnWidth)
                            colLabel:SetJustifyH("LEFT")  -- Left align within column (bullets will align)
                            colLabel:SetText("|cffeeeeee" .. criteriaText .. "|r")
                            colLabel:SetWordWrap(false)
                        end
                        
                        yOffset = yOffset - 16
                        currentRow = {}
                    end
                end
                
                yOffset = yOffset - sectionSpacing
            end
        end
        
        local detailsHeight = math.abs(yOffset) + 8
        detailsFrame:SetHeight(detailsHeight)
        
        row.detailsFrame = detailsFrame
        detailsFrame:Show()
        
        local totalHeight = rowHeight + detailsFrame:GetHeight()
        row:SetHeight(totalHeight)
    end
    
    return row
end

--============================================================================
-- CATEGORY SECTION FACTORY
--============================================================================

--[[
    Create a category section with header and item rows
    @param parent - Parent frame
    @param width - Section width
    @param categoryName - Category display name
    @param categoryKey - Unique key for expand state
    @param items - Array of items to display
    @param isExpanded - Initial expanded state
    @param onToggle - Callback function(isExpanded)
    @param createRowFunc - Function to create item rows: function(parent, item, index)
    @return section - Created section frame with header and rows
]]
local function CreateCategorySection(parent, width, categoryName, categoryKey, items, isExpanded, onToggle, createRowFunc)
    if not parent or not categoryName then return nil end
    
    local section = CreateFrame("Frame", nil, parent)
    section:SetWidth(width)
    
    -- Store state
    section.categoryKey = categoryKey
    section.items = items or {}
    section.isExpanded = isExpanded
    section.createRowFunc = createRowFunc
    
    -- Create collapsible header
    local header = CreateCollapsibleHeader(
        section,
        string.format("%s (%d)", categoryName, #section.items),
        categoryKey,
        isExpanded,
        onToggle,
        nil -- icon (optional)
    )
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetWidth(width)
    section.header = header
    
    -- Rows container
    local rowsContainer = CreateFrame("Frame", nil, section)
    rowsContainer:SetPoint("TOPLEFT", 0, -UI_LAYOUT.HEADER_HEIGHT)
    rowsContainer:SetWidth(width)
    section.rowsContainer = rowsContainer
    
    -- Calculate total height
    local totalHeight = UI_LAYOUT.HEADER_HEIGHT
    if isExpanded and #section.items > 0 then
        -- Rows will be added by caller
        totalHeight = totalHeight + (#section.items * (UI_LAYOUT.rowHeight or 32))
    end
    section:SetHeight(totalHeight)
    
    return section
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_CreateCard = CreateCard
ns.UI_FormatGold = FormatGold
ns.UI_FormatNumber = FormatNumber
ns.UI_FormatTextNumbers = FormatTextNumbers
ns.UI_FormatMoney = FormatMoney
ns.UI_FormatMoneyCompact = FormatMoneyCompact
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_CreateSortableTableHeader = CreateSortableTableHeader
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

-- Table factory exports
ns.UI_CreateTableRow = CreateTableRow
ns.UI_CreateExpandableRow = CreateExpandableRow
ns.UI_CreateCategorySection = CreateCategorySection

-- Currency transfer popup export
ns.UI_CreateCurrencyTransferPopup = CreateCurrencyTransferPopup

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
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(100)
    
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
    
    -- Make header draggable
    header:EnableMouse(true)
    header:SetMovable(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)
    
    -- Icon (support both texture and atlas)
    local iconIsAtlas = config.iconIsAtlas or false
    local iconFrame = CreateIcon(header, config.icon, 28, iconIsAtlas, nil, true)
    iconFrame:SetPoint("LEFT", 12, 0)
    iconFrame:Show()  -- CRITICAL: Show the header icon!
    
    -- Title
    local titleText = FontManager:CreateFontString(header, "title", "OVERLAY")
    titleText:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    titleText:SetText("|cffffffff" .. config.title .. "|r")
    
    -- Close button (X) - Modern styled
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply border and background to close button
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 1}, {0.5, 0.1, 0.1, 1})
    end
    
    -- Close button icon using atlas (communities-icon-redx)
    local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER", 0, 0)
    -- Use WoW's communities close button atlas
    local success = pcall(function()
        closeIcon:SetAtlas("communities-icon-redx", false)
    end)
    if not success then
        -- Fallback to X character if atlas fails
        local closeBtnText = FontManager:CreateFontString(closeBtn, "title", "OVERLAY")
        closeBtnText:SetPoint("CENTER", 0, 0)
        closeBtnText:SetText("|cffffffff×|r")  -- Multiplication sign (U+00D7)
    end
    
    -- Close function
    local function CloseDialog()
        if config.onClose then
            config.onClose()
        end
        dialog:Hide()
        dialog:SetParent(nil)
        _G[globalName] = nil
    end
    
    closeBtn:SetScript("OnClick", CloseDialog)
    
    -- Content frame (where users add their content)
    local contentFrame = CreateFrame("Frame", nil, dialog)
    contentFrame:SetPoint("TOPLEFT", 8, -53) -- Below header
    contentFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    
    -- Click outside to close (using OnUpdate to detect clicks)
    local clickOutsideFrame = CreateFrame("Frame", nil, UIParent)
    clickOutsideFrame:SetAllPoints()
    clickOutsideFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    clickOutsideFrame:SetFrameLevel(99) -- Just below dialog
    clickOutsideFrame:EnableMouse(true)
    clickOutsideFrame:SetScript("OnMouseDown", function()
        CloseDialog()
    end)
    
    -- Hide click outside frame when dialog is hidden
    dialog:SetScript("OnHide", function()
        clickOutsideFrame:Hide()
        if config.onClose then
            config.onClose()
        end
    end)
    
    dialog:SetScript("OnShow", function()
        clickOutsideFrame:Show()
    end)
    
    -- Close on Escape
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseDialog()
        end
    end)
    dialog:SetPropagateKeyboardInput(true)
    
    -- Store close function
    dialog.Close = CloseDialog
    
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
-- DYNAMIC CARD LAYOUT MANAGER
--============================================================================
-- Add dynamic card layout manager at the end of the file
-- This will handle card positioning when cards expand/collapse

--[[
    Dynamic Card Layout Manager
    Handles card positioning in a grid layout, automatically adjusting when cards expand/collapse
]]
local CardLayoutManager = {}
CardLayoutManager.instances = {}  -- Track layout instances per parent

--[[
    Create a new card layout manager for a parent container
    @param parent Frame - Parent container
    @param columns number - Number of columns (default 2)
    @param cardSpacing number - Spacing between cards (default 8)
    @param startYOffset number - Starting Y offset (default 0)
    @return table - Layout manager instance
]]
function CardLayoutManager:Create(parent, columns, cardSpacing, startYOffset)
    columns = columns or 2
    cardSpacing = cardSpacing or 8
    startYOffset = startYOffset or 0
    
    local instance = {
        parent = parent,
        columns = columns,
        cardSpacing = cardSpacing,
        cards = {},  -- Array of {card, col, rowIndex}
        currentYOffsets = {},  -- Track Y offset for each column
        startYOffset = startYOffset,
    }
    
    -- Initialize column offsets
    for col = 0, columns - 1 do
        instance.currentYOffsets[col] = startYOffset
    end
    
    -- Store instance
    local instanceKey = tostring(parent)
    self.instances[instanceKey] = instance
    
    return instance
end

--[[
    Add a card to the layout
    @param instance table - Layout instance
    @param card Frame - Card frame
    @param col number - Column index (0-based)
    @param baseHeight number - Base height of card (before expansion)
    @return number - Y offset where card was placed
]]
function CardLayoutManager:AddCard(instance, card, col, baseHeight)
    col = col or 0
    baseHeight = baseHeight or 130
    
    -- Get current Y offset for this column
    local yOffset = instance.currentYOffsets[col] or instance.startYOffset
    
    -- Calculate X offset
    local cardWidth = (instance.parent:GetWidth() - (instance.columns - 1) * instance.cardSpacing - 20) / instance.columns
    local xOffset = 10 + col * (cardWidth + instance.cardSpacing)
    
    -- Position card
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", xOffset, -yOffset)
    
    -- Store card info
    local cardInfo = {
        card = card,
        col = col,
        baseHeight = baseHeight,
        currentHeight = baseHeight,
        yOffset = yOffset,
        rowIndex = #instance.cards,
    }
    table.insert(instance.cards, cardInfo)
    
    -- Update column Y offset
    instance.currentYOffsets[col] = yOffset + baseHeight + instance.cardSpacing
    
    -- Store layout reference on card
    card._layoutManager = instance
    card._layoutInfo = cardInfo
    
    return yOffset
end

--[[
    Update layout when a card's height changes
    @param card Frame - Card that changed height
    @param newHeight number - New height of the card
]]
function CardLayoutManager:UpdateCardHeight(card, newHeight)
    local instance = card._layoutManager
    local cardInfo = card._layoutInfo
    
    if not instance or not cardInfo then
        return
    end
    
    -- Update stored height
    cardInfo.currentHeight = newHeight
    
    -- Recalculate all positions to handle cross-column scenarios
    self:RecalculateAllPositions(instance)
end

--[[
    Get final Y offset (for return value)
    @param instance table - Layout instance
    @return number - Maximum Y offset across all columns
]]
function CardLayoutManager:GetFinalYOffset(instance)
    local maxY = instance.startYOffset
    for col = 0, instance.columns - 1 do
        local colY = instance.currentYOffsets[col] or instance.startYOffset
        if colY > maxY then
            maxY = colY
        end
    end
    return maxY
end

--[[
    Recalculate all card positions from scratch
    Handles expanded cards, window resize, and cross-column scenarios
    @param instance table - Layout instance
]]
function CardLayoutManager:RecalculateAllPositions(instance)
    if not instance or not instance.parent then
        return
    end
    
    -- Recalculate card width based on current parent width
    local cardWidth = (instance.parent:GetWidth() - (instance.columns - 1) * instance.cardSpacing - 20) / instance.columns
    
    -- Reset column Y offsets
    for col = 0, instance.columns - 1 do
        instance.currentYOffsets[col] = instance.startYOffset
    end
    
    -- Sort cards by their original row index to maintain order
    local sortedCards = {}
    for i, cardInfo in ipairs(instance.cards) do
        table.insert(sortedCards, cardInfo)
    end
    table.sort(sortedCards, function(a, b)
        return a.rowIndex < b.rowIndex
    end)
    
    -- Reposition all cards, maintaining column assignment but recalculating Y positions
    for i, cardInfo in ipairs(sortedCards) do
        local col = cardInfo.col
        local currentHeight = cardInfo.currentHeight or cardInfo.baseHeight
        
        -- Get current Y offset for this column
        local yOffset = instance.currentYOffsets[col] or instance.startYOffset
        
        -- Handle full-width cards (weekly vault, daily quest header, etc.)
        if cardInfo.isFullWidth then
            -- Full width card: span both columns
            cardInfo.card:ClearAllPoints()
            cardInfo.card:SetPoint("TOPLEFT", instance.parent, "TOPLEFT", 10, -yOffset)
            cardInfo.card:SetPoint("TOPRIGHT", instance.parent, "TOPRIGHT", -10, -yOffset)
            -- Update both columns to same Y offset
            instance.currentYOffsets[0] = yOffset + currentHeight + instance.cardSpacing
            instance.currentYOffsets[1] = yOffset + currentHeight + instance.cardSpacing
        else
            -- Regular card: single column
            local xOffset = 10 + col * (cardWidth + instance.cardSpacing)
            
            -- Update card position
            cardInfo.card:ClearAllPoints()
            cardInfo.card:SetPoint("TOPLEFT", xOffset, -yOffset)
            cardInfo.card:SetWidth(cardWidth)
            
            -- Update column Y offset for next card
            instance.currentYOffsets[col] = yOffset + currentHeight + instance.cardSpacing
        end
        
        -- Update stored Y offset
        cardInfo.yOffset = yOffset
    end
end

--[[
    Refresh layout when parent frame is resized
    Recalculates both X and Y positions for all cards
    @param instance table - Layout instance
]]
function CardLayoutManager:RefreshLayout(instance)
    if not instance or not instance.parent then
        return
    end
    
    -- Use RecalculateAllPositions to handle both X and Y repositioning
    self:RecalculateAllPositions(instance)
end

-- Export
ns.UI_CardLayoutManager = CardLayoutManager

-- Export PixelScale functions (used by FontManager for resolution normalization)
ns.GetPixelScale = GetPixelScale
ns.PixelSnap = PixelSnap
ns.ResetPixelScale = ResetPixelScale

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
    ApplyVisuals is the new 4-texture sandwich method (ElvUI style).
    
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
    
    -- Apply 1px border using ApplyVisuals (ElvUI sandwich method)
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
    title:SetText("|cffccccccModule Disabled|r")
    
    -- Description with colored module name
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    
    local description = FontManager:CreateFontString(contentContainer, "body", "OVERLAY")
    description:SetPoint("TOP", title, "BOTTOM", 0, -16)
    description:SetWidth(380)
    description:SetJustifyH("CENTER")
    description:SetText(
        "|cff999999Enable it in |r|cffffffffSettings|r |cff999999to use |r|cff" .. hexColor .. moduleName .. "|r|cff999999.|r"
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
    
    -- Format time helper
    local function FormatResetTime(seconds)
        if not seconds or seconds <= 0 then return "Soon" end
        local days = math.floor(seconds / 86400)
        local hours = math.floor((seconds % 86400) / 3600)
        local mins = math.floor((seconds % 3600) / 60)
        
        if days > 0 then 
            return string.format("%dd %dh", days, hours)
        elseif hours > 0 then 
            return string.format("%dh %dm", hours, mins)
        else 
            return string.format("%dm", mins)
        end
    end
    
    -- Update function
    local function Update()
        if getSecondsFunc then
            local seconds = getSecondsFunc()
            text:SetText("Reset: " .. FormatResetTime(seconds))
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
    
    text:SetText(color .. "DB: " .. dataSource .. "|r")
    
    -- Tooltip on hover
    badge:EnableMouse(true)
    badge:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Data Source Information", 1, 1, 1)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This tab is using:", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(dataSource, 1, 1, 0)
        GameTooltip:AddLine(" ")
        
        if dataSource:find("Cache") then
            GameTooltip:AddLine("|cff00ff00✓|r Modern cache service (event-driven)", 0, 1, 0)
        elseif dataSource:find("LEGACY") then
            GameTooltip:AddLine("|cffffaa00⚠|r Legacy direct DB access", 1, 0.67, 0)
            GameTooltip:AddLine("Needs migration to cache service", 0.7, 0.7, 0.7)
        end
        
        -- Show current DB version
        local WarbandNexus = ns.WarbandNexus
        if WarbandNexus and WarbandNexus.db then
            local dbVersion = WarbandNexus.db.global.dataVersion or 1
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Global DB Version: " .. dbVersion, 0.5, 0.5, 1)
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

--- Create a scroll frame
--- Replaces manual CreateFrame("ScrollFrame", ...) calls
---@param parent Frame Parent frame
---@param template string|nil Optional template (e.g., "UIPanelScrollFrameTemplate")
---@return ScrollFrame scrollFrame The created scroll frame
function ns.UI.Factory:CreateScrollFrame(parent, template)
    if not parent then
        print("|cffff4444[WN Factory ERROR]|r CreateScrollFrame: parent is nil")
        return nil
    end
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, template)
    
    -- Debug log (only first call)
    if not self._scrollLogged then
        print("|cff9370DB[WN Factory]|r CreateScrollFrame initialized (no more logs)")
        self._scrollLogged = true
    end
    
    return scrollFrame
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
    
    local loadingCard = CreateCard(parent, 90)
    loadingCard:SetPoint("TOPLEFT", 10, -yOffset)
    loadingCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
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
    loadingText:SetText("|cff00ccff" .. (title or "Loading...") .. "|r")
    
    -- Progress indicator
    local progressText = FontManager:CreateFontString(loadingCard, "body", "OVERLAY")
    progressText:SetPoint("LEFT", spinner, "RIGHT", 15, -8)
    
    local currentStage = loadingState.currentStage or "Preparing"
    local progress = loadingState.loadingProgress or 0
    progressText:SetText(string.format("|cff888888%s - %d%%|r", currentStage, math.min(100, progress)))
    
    -- Hint text
    local hintText = FontManager:CreateFontString(loadingCard, "small", "OVERLAY")
    hintText:SetPoint("LEFT", spinner, "RIGHT", 15, -25)
    hintText:SetTextColor(0.6, 0.6, 0.6)
    hintText:SetText("Please wait...")
    
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
    
    local errorCard = CreateCard(parent, 60)
    errorCard:SetPoint("TOPLEFT", 10, -yOffset)
    errorCard:SetPoint("TOPRIGHT", -10, -yOffset)
    
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

-- Export to namespace
ns.UI_CreateLoadingStateCard = UI_CreateLoadingStateCard
ns.UI_CreateErrorStateCard = UI_CreateErrorStateCard

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
    editBox:SetFontObject(ChatFontNormal)
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

-- Load message
print("|cff00ff00[WN Factory]|r Factory methods loaded (CreateContainer, CreateButton, CreateScrollFrame, CreateEditBox)")
print("|cff9370DB[WN Factory]|r Loading state widgets initialized (LoadingStateCard, ErrorStateCard)")
print("|cff00ccff[WN Factory]|r Factory pattern bridge initialized (ns.UI.Factory.*)")

