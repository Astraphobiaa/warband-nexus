--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
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

--- Semantic UI role → category (FontManager.FONT_ROLE / tek tema kaynağı)
local function UIFontRole(roleKey)
    return FontManager:GetFontRole(roleKey)
end

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

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
                if frame and frame.BorderTop and not frame._wnMainShellBackdrop and not frame._wnBorderlessSurface then
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
    textDim = {0.55, 0.55, 0.55, 1},
    white = {1, 1, 1, 1},
}

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
end

-- Apply theme colors on initial load
UpdateColorsFromTheme()

--- Wire semantic aliases to live color rows (called after any in-place COLORS mutation).
local function SyncSemanticColorAliases()
    COLORS.surface = COLORS.bg
    COLORS.surfaceElevated = COLORS.bgLight
    COLORS.surfaceCard = COLORS.bgCard
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
    --- Glyph fills icon tile (no inner border frame on title cards).
    TITLE_CARD_ICON_GLYPH_SIZE = 38,
    TITLE_CARD_ICON_SIZE = 44,
    TITLE_CARD_ICON_PAD = 5,
    TITLE_CARD_ICON_INSET = 12,
    --- Title card: icon block flush to card LEFT (0 = edge-aligned inside card).
    TITLE_CARD_ICON_SIDE_INSET = 0,
    TITLE_CARD_TOOLBAR_EDGE_INSET = 10,
    TITLE_CARD_ICON_BORDER_ALPHA = 0.45,
    TITLE_CARD_UNDERLINE_ALPHA = 0.5,
    TITLE_CARD_RING_TEXT_GAP = 12,
    TITLE_CARD_TEXT_PAD_V = 8,
    --- Legacy alias: icon block center X from card left (`inset + pad + iconSize/2`).
    TITLE_CARD_RING_CENTER_X = 12 + 5 + 22,
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
        --- Main window nav: vertical text rail (left); horizontal `top` remains in Settings.
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
        NAV_RAIL_DIVIDER_ALPHA = 0.55,
        NAV_RAIL_TAB_SEP_HEIGHT = 1,
        NAV_RAIL_TAB_SEP_ALPHA = 0.4,
        NAV_RAIL_ACTIVE_BG_ALPHA = 0.52,
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
        SECTION_HEADER_UNDERLAY_VERTEX_ALPHA = 0.42,
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

--============================================================================
-- PACKAGED UI ICONS (Media/*.tga — vertex-tinted stroke art)
--============================================================================

local WN_ICON_PATHS = nil

--- Packaged WN action icons: white when idle, yellow when active, grey only when disabled (completed / locked).
ns.WN_ICON_VERTEX_WHITE = { 1, 1, 1, 1 }
ns.WN_ICON_VERTEX_YELLOW = { 1, 0.88, 0.08, 1 }
ns.WN_ICON_VERTEX_RED = { 1, 0.28, 0.22, 1 }
ns.WN_ICON_VERTEX_DISABLED = { 0.45, 0.48, 0.52, 0.75 }

function ns.UI_WnIconVertexForState(active, disabled)
    if disabled then
        return ns.WN_ICON_VERTEX_DISABLED
    end
    if active then
        return ns.WN_ICON_VERTEX_YELLOW
    end
    return ns.WN_ICON_VERTEX_WHITE
end

--- Vertex tint: todo/alert/track/pin — active=yellow, idle=white; delete/block=red; disabled=grey.
function ns.UI_WnIconVertexForKey(iconKey, active, disabled)
    if disabled then
        return ns.WN_ICON_VERTEX_DISABLED
    end
    if iconKey == "delete" or iconKey == "block" then
        return ns.WN_ICON_VERTEX_RED
    end
    if active then
        return ns.WN_ICON_VERTEX_YELLOW
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
    }
    return WN_ICON_PATHS
end

--- Apply a packaged WN icon texture. `iconKey`: todo | alert | reminder | track | pin | delete | block | chevron_* | link
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

--- Anchor a square header action on the right edge, vertically centered on `headerFrame` (y=0).
function ns.UI_PlansAnchorHeaderAction(control, headerFrame, fromRight, width)
    if not control or not headerFrame then return end
    width = width or (control.GetWidth and control:GetWidth()) or 24
    fromRight = fromRight or 6
    control:ClearAllPoints()
    control:SetPoint("RIGHT", headerFrame, "RIGHT", -fromRight, 0)
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

--- Scroll stride for one data row: paint height + row-only gap.
function ns.UI_DataRowStride(rowPaintHeight)
    local layout = ns.UI_LAYOUT or {}
    local h = rowPaintHeight or layout.rowHeight or 26
    return h + (layout.dataRowGap or 4)
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
---@param header Frame
---@param wrap Frame
---@param stackW number|nil explicit width; else wrap:GetWidth()
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

--- Square icon action button (reminder / track / delete / todo / link).
function ns.UI_CreateIconActionButton(parent, size, iconKey, opts)
    if not parent or not iconKey then return nil end
    opts = type(opts) == "table" and opts or {}
    size = size or 24
    local btn = ns.UI.Factory and ns.UI.Factory.CreateButton and ns.UI.Factory:CreateButton(parent, size, size, true)
    if not btn then
        btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(size, size)
    end
    local tex = btn._wnIconTex
    if not tex then
        tex = btn:CreateTexture(nil, "OVERLAY")
        btn._wnIconTex = tex
    end
    tex:ClearAllPoints()
    local PCM = ns.UI_PLANS_CARD_METRICS
    local pad = opts.iconInset or (PCM and PCM.plansActionIconInset) or math.max(3, math.floor(size * 0.14))
    local iconSz = math.max(12, size - pad * 2)
    tex:SetSize(iconSz, iconSz)
    tex:SetPoint("CENTER", btn, "CENTER", 0, 0)
    local disabled = opts.disabled == true
    local active = opts.active == true and not disabled
    btn._wnIconKey = iconKey
    btn._wnIconActive = active
    btn._wnIconDisabled = disabled
    function btn:WnRefreshIconAction(refActive, refDisabled)
        refDisabled = refDisabled == true
        refActive = refActive == true and not refDisabled
        self._wnIconActive = refActive
        self._wnIconDisabled = refDisabled
        local t = self._wnIconTex
        if t and ns.UI_ApplyWnActionIcon then
            ns.UI_ApplyWnActionIcon(t, self._wnIconKey or iconKey, refActive, refDisabled)
        end
    end
    btn:WnRefreshIconAction(active, disabled)
    if opts.frameLevelOffset and btn.SetFrameLevel then
        btn:SetFrameLevel(parent:GetFrameLevel() + opts.frameLevelOffset)
    end
    if opts.onClick then
        btn:RegisterForClicks("LeftButtonUp")
        btn:SetScript("OnClick", opts.onClick)
    end
    if opts.tooltipTitle and ns.TooltipService and ns.TooltipService.Show then
        btn:SetScript("OnEnter", function(self)
            ns.TooltipService:Show(self, {
                type = "custom",
                title = opts.tooltipTitle,
                icon = false,
                anchor = opts.tooltipAnchor or "ANCHOR_RIGHT",
                lines = opts.tooltipLines or {},
            })
        end)
        btn:SetScript("OnLeave", function()
            if ns.TooltipService.Hide then ns.TooltipService:Hide() end
        end)
    end
    return btn
end

--============================================================================
-- COLLAPSE / EXPAND CHEVRON (shared control — single Button, one texture, state = packaged icon)
--============================================================================

local function WnCollapseExpandApply(tex, isExpanded)
    if not tex then return end
    local key = isExpanded and "chevron_up" or "chevron_down"
    if not ns.UI_SetWnIconTexture(tex, key, nil) then
        local sp = UI_SPACING
        local up = sp.COLLAPSE_EXPAND_ATLAS_EXPANDED
        local down = sp.COLLAPSE_EXPAND_ATLAS_COLLAPSED
        tex:SetAtlas(isExpanded and up or down, false)
    end
end

function ns.UI_CollapseExpandSetState(btn, isExpanded)
    if not btn or not btn._wnCollapseTex then return end
    WnCollapseExpandApply(btn._wnCollapseTex, isExpanded)
    local c = btn._wnCollapseVertexColor
    if c then
        btn._wnCollapseTex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
end

---@param parent Frame
---@param isExpanded boolean When true, section is expanded (up chevron = collapse affordance).
---@param opts table|nil `{ enableMouse = false|true, vertexColor = {r,g,b,a?} }`
---@return Button btn Child has `_wnCollapseTex` (Texture). Mouse defaults to enabled; pass `enableMouse = false` when the parent header handles clicks.
function ns.UI_CreateCollapseExpandControl(parent, isExpanded, opts)
    opts = type(opts) == "table" and opts or {}
    local sz = tonumber(opts.size) or UI_SPACING.COLLAPSE_EXPAND_BUTTON_SIZE or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(sz, sz)
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    btn._wnCollapseTex = tex
    WnCollapseExpandApply(tex, isExpanded)
    local vc = opts.vertexColor
    if vc then
        btn._wnCollapseVertexColor = { vc[1], vc[2], vc[3], vc[4] or 1 }
        tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
    else
        tex:SetVertexColor(1, 1, 1, 1)
    end
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    if opts.enableMouse == false then
        btn:EnableMouse(false)
    else
        btn:EnableMouse(true)
        if btn.RegisterForClicks then
            btn:RegisterForClicks("LeftButtonUp")
        end
    end
    return btn
end

--============================================================================
-- PLANS TAB (To-Do List expandable rows + Browse grid cards): single source of truth
--============================================================================
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
    --- Browse mounts/pets/etc. grid: same icon/badge feel as To-Do; fixed card height for two-column grid
    browseCardHeight = PlansMetric(126),
    --- Vertical gap between To-Do List cards (Currency/Reputation row-gap parity).
    todoListCardGap = 10,
    browseCardPadH = 12,
    plansActionIconInset = 3,
    browseIconTopInset = PlansMetric(10),
    browseIconLeftInset = PlansMetric(10),
    browseIconContainerSize = PlansMetric(45),
    browseRightRailW = PlansMetric(52),
    plansChevronSize = PlansMetric(18),
}

--- Plans / Collections browse grid: card width, spacing, horizontal pad (clamp-safe).
function ns.UI_PlansCardGridLayout(contentInnerWidth, columns)
    columns = columns or 2
    local PCM = ns.UI_PLANS_CARD_METRICS
    local padH = (PCM and PCM.browseCardPadH) or 12
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

--- Collapsed expandable header height (To-Do List + tracker rows); scales slightly with panel width.
function ns.UI_PlansTodoExpandableHeaderHeight(panelWidth)
    local m = ns.UI_PLANS_CARD_METRICS
    local minH = m and m.todoExpandableMinHeight or 60
    local cap = m and m.todoExpandableHeightCap or 68
    local w = panelWidth or 400
    return math.max(minH, math.min(cap, math.floor(w * 0.10)))
end

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
    SyncSemanticColorAliases()
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
    local borderColor = COLORS.border
    local bgColor = COLORS.bg
    local updated = 0
    
    -- Update ALL registered frames (ApplyVisuals 4-texture system)
    for i = #ns.BORDER_REGISTRY, 1, -1 do
        local frame = ns.BORDER_REGISTRY[i]
        
        if not frame then
            table.remove(ns.BORDER_REGISTRY, i)
        elseif frame._wnMainShellBackdrop and frame.SetBackdropBorderColor and frame.SetBackdropColor then
            -- Native BackdropTemplate shell (WarbandNexus root): tinted border + bg, no BorderTop quartet.
            local targetColor = (frame._borderType == "accent") and accentColor or borderColor
            local alpha = frame._borderAlpha or 0.9
            frame:SetBackdropBorderColor(targetColor[1], targetColor[2], targetColor[3], alpha)

            local bgTargetColor = (frame._bgType == "accentDark") and accentDarkColor or bgColor
            local bgAlpha = frame._bgAlpha or 1
            frame:SetBackdropColor(bgTargetColor[1], bgTargetColor[2], bgTargetColor[3], bgAlpha)

            if frame._thumbTexture then
                frame._thumbTexture:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.9)
            end
            if frame._iconTexture then
                frame._iconTexture:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 1)
            end

            updated = updated + 1
        elseif not frame.BorderTop then
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

            if frame._wnViewportAtlasUnderlay and ns.UI_RefreshViewportAtlasUnderlayTint then
                ns.UI_RefreshViewportAtlasUnderlayTint(frame)
            end

            if frame._wnSectionChromeUnderlay and ns.UI_RefreshSectionChromeUnderlayTint then
                ns.UI_RefreshSectionChromeUnderlayTint(frame)
            end
            
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
    
    -- Update all accent-colored FontStrings (before main-window redraw to avoid reload issues)
    if ns.FontManager and ns.FontManager.RefreshAccentColors then
        ns.FontManager:RefreshAccentColors()
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
        if ns.UI_ScrollMainNavEnsureTabVisible and f.currentTab then
            ns.UI_ScrollMainNavEnsureTabVisible(f, f.currentTab)
        end

        -- Refresh content to update dynamic elements (moved AFTER RefreshAccentColors)
        if f:IsShown() and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
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

--- PvE upgrade track tier -> |cffRRGGBB| hex (6 digits only; never prefix alpha `ff` — |cff supplies opacity).
ns.GEAR_UPGRADE_TRACK_TIER_HEX = {
    Adventurer = "9d9d9d",
    Explorer   = "9d9d9d",
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

---@param englishName string|nil Adventurer, Veteran, Champion, Hero, Myth, …
---@return string|nil six-digit RRGGBB
function ns.UI_GetUpgradeTrackTierHex(englishName)
    if not englishName or englishName == "" then return nil end
    if issecretvalue and issecretvalue(englishName) then return nil end
    local trimmed = englishName:match("^%s*(.-)%s*$") or englishName
    return ns.GEAR_UPGRADE_TRACK_TIER_HEX and ns.GEAR_UPGRADE_TRACK_TIER_HEX[trimmed] or nil
end

--- Safe |cff…|r for upgrade-track labels (gear slots, crest rows).
---@param englishName string|nil
---@param displayText string
---@param fallbackQuality number|nil item quality when track name unknown
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

-- Factory namespace (also initialized at file top for mid-file Factory methods).
ns.UI = ns.UI or {}
ns.UI.Factory = ns.UI.Factory or {}

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

--- Pixel border quartet on root shell (accent on all four sides; complements SetBackdrop edgeFile).
local function ApplyMainWindowShellBorderQuartet(frame, borderColor)
    if not frame or not borderColor then return end
    local pixelScale = GetPixelScale(frame)
    if not frame.BorderTop then
        frame.BorderTop = frame:CreateTexture(nil, "BORDER", nil, 7)
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(pixelScale)
        frame.BorderTop:SetSnapToPixelGrid(false)
        frame.BorderTop:SetTexelSnappingBias(0)

        frame.BorderBottom = frame:CreateTexture(nil, "BORDER", nil, 7)
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(pixelScale)

        frame.BorderLeft = frame:CreateTexture(nil, "BORDER", nil, 7)
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderLeft:SetWidth(pixelScale)

        frame.BorderRight = frame:CreateTexture(nil, "BORDER", nil, 7)
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderRight:SetWidth(pixelScale)
    else
        frame.BorderTop:SetHeight(pixelScale)
        frame.BorderBottom:SetHeight(pixelScale)
        frame.BorderLeft:SetWidth(pixelScale)
        frame.BorderRight:SetWidth(pixelScale)
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
local function ApplyBorderlessSurface(frame, bgColor)
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
end

ns.UI_ApplyBorderlessSurface = ApplyBorderlessSurface
ns.UI_HideFrameBorderQuartet = HideFrameBorderQuartet

--- Resolve a surface tier color (borderless depth ladder).
---@param tier string|nil "canvas"|"viewport"|"card"|"section"|"rowEven"|"rowOdd"|"elevated"
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

--- Flat fill for a semantic surface tier (no 1px border quartet).
---@param frame Frame
---@param tier string|nil
function ns.UI_ApplySurfaceTier(frame, tier)
    if not frame then return end
    local rgba = ResolveSurfaceTierColor(tier)
    ApplyBorderlessSurface(frame, rgba)
    frame._wnSurfaceTier = tier or "canvas"
end

--- 1px accent/neutral separator on a frame edge (replaces box borders for zone splits).
---@param frame Frame
---@param edge string|nil "bottom"|"top"
---@param useAccent boolean|nil
function ns.UI_EnsureChromeHairline(frame, edge, useAccent)
    if not frame then return end
    edge = edge or "bottom"
    local key = "_wnHairline" .. edge
    local line = frame[key]
    if not line then
        line = frame:CreateTexture(nil, "ARTWORK", nil, 7)
        frame[key] = line
    end
    local shell = (UI_SPACING and UI_SPACING.MAIN_SHELL) or {}
    local alpha = shell.SURFACE_HAIRLINE_ALPHA or 0.24
    local ac = COLORS and COLORS.accent or { 0.4, 0.2, 0.58 }
    if useAccent == false then
        line:SetColorTexture(1, 1, 1, alpha * 0.35)
    else
        line:SetColorTexture(ac[1], ac[2], ac[3], alpha)
    end
    line:SetHeight(1)
    line:ClearAllPoints()
    if edge == "top" then
        line:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        line:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    else
        line:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    end
    line:Show()
end

--- Root shell only (`WarbandNexusFrame`): full-bleed color fill — no `BackdropTemplate` / backdrop insets (avoids side gutters).
local function ApplyMainWindowShellFill(frame, bgColor, _borderColor)
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
    HideFrameBorderQuartet(frame)
    frame._wnMainShellBackdrop = true
    frame._wnBorderlessSurface = true
    frame._bgType = "bg"
    frame._bgAlpha = c[4] or 0.98
end

--- Legacy name: routes to flat fill (no `BackdropTemplate`).
local function ApplyMainWindowShellBackdrop(frame, bgColor, borderColor)
    ApplyMainWindowShellFill(frame, bgColor, borderColor)
end

-- Export to namespace
ns.UI_ApplyVisuals = ApplyVisuals
ns.UI_ApplyMainWindowShellFill = ApplyMainWindowShellFill
ns.UI_ApplyMainWindowShellBackdrop = ApplyMainWindowShellBackdrop
ns.UI_ResetPixelScale = ResetPixelScale

--- Compact rail width for main shell body (below header): ratio of inner width, clamped.
---@param innerBodyWidth number Usable width below header (frame width minus chrome insets).
---@param shell table|nil MAIN_SHELL layout slice
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
---@param mainFrame Frame|nil
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
---@param baseYOffset number|nil
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
---@param mainFrame Frame|nil
---@param parent Frame|nil scrollChild fallback when metrics unavailable
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
---@param mainFrame Frame|nil
---@param parent Frame|nil
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
---@param mainFrame Frame|nil
---@param resultsContainer Frame|nil
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
---@param mainFrame Frame|nil
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
---@param yOffset number
---@param blockHeight number|nil
---@param gapAfter number|nil
---@return number
function ns.UI_AdvanceTabChromeYOffset(yOffset, blockHeight, gapAfter)
    local sp = UI_SPACING or {}
    gapAfter = gapAfter or sp.TAB_CHROME_BLOCK_GAP or 8
    return (yOffset or 0) + (blockHeight or 0) + gapAfter
end

--- Commit fixedHeader height after laying out chrome blocks.
---@param mainFrame Frame|nil
---@param yOffset number
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
---@param mainFrame Frame|nil
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
---@param btn Button
---@param isActive boolean
---@param accentColor table|nil {r,g,b}
function ns.UI_ApplyRailTabActiveVisuals(btn, isActive, accentColor)
    if not btn or not btn._wnRailTextMode then return end
    local shell = (UI_SPACING and UI_SPACING.MAIN_SHELL) or {}
    local ac = accentColor or (COLORS and COLORS.accent) or { 0.6, 0.4, 1 }
    local glow = btn._wnRailActiveGlow
    local glowInner = btn._wnRailActiveGlowInner
    if isActive then
        -- Text rail already paints a flat active backdrop on the button; stacked halos read as dual-tone (e.g. Gear tab).
        if glow then glow:Hide() end
        if glowInner then glowInner:Hide() end
    else
        if glow then glow:Hide() end
        if glowInner then glowInner:Hide() end
    end
end

--- Scroll viewport width for active main tab (after golden rail + insets).
---@param mainFrame Frame|nil
---@return number
--- Shell / content / scroll canvas background (unified panel tone).
---@return table {r,g,b,a}
function ns.UI_GetMainPanelBackgroundColor()
    local C = COLORS or ns.UI_COLORS
    return (C and C.bg) or { 0.042, 0.042, 0.055, 0.98 }
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
---@param frame Frame
---@param texKey string
---@param nameKey string
---@param inset number
---@param candidates string[]|nil
---@param fallbackTex string|nil
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

---@param frame Frame
---@param texKey string
---@param alphaShellKey string
local function WnRefreshAtlasChromeUnderlayTint(frame, texKey, alphaShellKey)
    local tex = frame and texKey and frame[texKey]
    if not tex or not alphaShellKey then return end

    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local shell = layout.MAIN_SHELL or {}
    local baseA = tonumber(shell[alphaShellKey])
    if not baseA or baseA < 0 then
        baseA = (alphaShellKey == "SECTION_HEADER_UNDERLAY_VERTEX_ALPHA") and 0.34 or 0.44
    end

    local bgcol = COLORS and COLORS.bg or { 0.04, 0.04, 0.05, 1 }
    local accent = COLORS and COLORS.accent or { 0.25, 0.55, 0.98 }

    local r = bgcol[1] * 1.08 + accent[1] * 0.10
    local g = bgcol[2] * 1.08 + accent[2] * 0.10
    local b = bgcol[3] * 1.08 + accent[3] * 0.10
    if r > 1 then r = 1 end
    if g > 1 then g = 1 end
    if b > 1 then b = 1 end

    tex:SetVertexColor(r, g, b, baseA > 1 and 1 or baseA)
end

--- Theme tint for `UI_ApplyViewportAtlasUnderlay` mid-layer (`ns.UI_RefreshColors`).
---@param frame Frame
function ns.UI_RefreshViewportAtlasUnderlayTint(frame)
    WnRefreshAtlasChromeUnderlayTint(frame, "_wnViewportAtlasUnderlay", "VIEWPORT_UNDERLAY_VERTEX_ALPHA")
end

--- Theme tint for section / card atlas underlay (`ns.UI_RefreshColors`).
---@param frame Frame
function ns.UI_RefreshSectionChromeUnderlayTint(frame)
    WnRefreshAtlasChromeUnderlayTint(frame, "_wnSectionChromeUnderlay", "SECTION_HEADER_UNDERLAY_VERTEX_ALPHA")
end

--- Main viewport mid-layer atlas/tile (`viewportBorder`): `C_Texture.GetAtlasInfo` + `sliceData` -> SetTextureSliceMargins (TextureBase wiki); fallback tooltip tile + tint.
---@param frame Frame
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
---@param frame Frame
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
    local ac = COLORS.accent
    local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
    ApplyVisuals(frame, bg, { ac[1], ac[2], ac[3], 0.7 })
    frame._wnBorderlessSurface = nil
    if frame._wnCardTopHighlight and frame._wnCardTopHighlight.Hide then
        frame._wnCardTopHighlight:Hide()
    end
    if frame._wnCardBottomShade and frame._wnCardBottomShade.Hide then
        frame._wnCardBottomShade:Hide()
    end
end

ns.UI_ApplyStandardCardElevatedChrome = ApplyStandardCardElevatedChrome

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
    if not frame or not borderColor then return end

    if frame._wnMainShellBackdrop and frame.SetBackdropBorderColor then
        local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
        frame:SetBackdropBorderColor(r, g, b, a)
        return
    end

    if not frame.BorderTop then return end
    
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
    
    local margin = sideMargin or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", margin, -yOffset)
    container:SetPoint("TOPRIGHT", -margin, 0)
    container:SetHeight(1)  -- Minimal initial height, will be set by content renderer
    
    return container
end

--- Fills the band from `resultsContainer` bottom to `scrollParent` bottom (same tone as scroll chrome).
--- Use when list height is intrinsic but the scroll viewport is taller (avoids a dead strip above the footer).
---@param resultsContainer Frame
---@param scrollParent Frame
---@param sideMargin number|nil
---@param bottomInset number|nil
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
---@param scrollChild Frame
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
---@param mainFrame Frame|nil
---@param scrollChild Frame|nil
---@param tabBodyHeight number|nil content extent below scroll top inset
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
---@param annex Frame|nil
function ns.UI_RefreshScrollAnnexChrome(annex)
    if not annex or not annex._wnAnnexTex then return end
    local c = ResolveSurfaceTierColor("viewport")
    annex._wnAnnexTex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.98)
end

--- Re-anchor annex after PopulateContent sets scrollChild height.
---@param scrollParent Frame
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
    
    local text = FontManager:CreateFontString(bar, UIFontRole("statsBarText"), "OVERLAY")
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
                if IsDebugModeEnabled and IsDebugModeEnabled() then
                    local texName = texture
                    if texName ~= nil and not (issecretvalue and issecretvalue(texName)) then
                        DebugPrint("|cffff0000[WN CreateIcon]|r Atlas '" .. tostring(texName) .. "' failed, using fallback")
                    end
                end
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
    button:EnableMouse(true)
    
    if not noBorder then
        ApplyVisuals(button, bgColor, borderColor)
    else
        -- Icon-only hit target: no opaque panel (row delete / header assign / reorder arrows).
        if button.SetBackdrop then
            pcall(button.SetBackdrop, button, nil)
        end
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
    if row.SetClipsChildren then
        row:SetClipsChildren(true)
    end
    
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
        row.nameText = FontManager:CreateFontString(row, UIFontRole("listRowLabel"), "OVERLAY")
        row.nameText:SetPoint("LEFT", 43, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        
        -- Amount text
        row.amountText = FontManager:CreateFontString(row, UIFontRole("listRowValue"), "OVERLAY")
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
        row.qtyText = FontManager:CreateFontString(row, UIFontRole("listRowQty"), "OVERLAY")
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
        
        -- Name text (pinned between icon column and location column)
        row.nameText = FontManager:CreateFontString(row, UIFontRole("listRowLabel"), "OVERLAY")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)

        -- Location text (inset from scrollbar; keep in sync with FramePoolFactory AcquireItemRow)
        row.locationText = FontManager:CreateFontString(row, UIFontRole("listRowLocation"), "OVERLAY")
        local locInset = (UI_SPACING and UI_SPACING.LIST_ROW_LOCATION_RIGHT_INSET) or 28
        local locMaxW = (UI_SPACING and UI_SPACING.LIST_ROW_LOCATION_MAX_WIDTH) or 120
        row.locationText:SetPoint("RIGHT", row, "RIGHT", -locInset, 0)
        row.locationText:SetWidth(locMaxW)
        row.locationText:SetJustifyH("RIGHT")
        row.locationText:SetWordWrap(false)
        row.locationText:SetNonSpaceWrap(false)
        row.locationText:SetMaxLines(1)
        row.nameText:SetPoint("RIGHT", row.locationText, "LEFT", -10, 0)

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
        row.qtyText = FontManager:CreateFontString(row, UIFontRole("listRowQty"), "OVERLAY")
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
        
        -- Name text (pinned between icon column and location column)
        row.nameText = FontManager:CreateFontString(row, UIFontRole("listRowLabel"), "OVERLAY")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)

        -- Location text (inset from scrollbar; keep in sync with FramePoolFactory AcquireStorageRow)
        row.locationText = FontManager:CreateFontString(row, UIFontRole("listRowLocation"), "OVERLAY")
        local locInsetS = (UI_SPACING and UI_SPACING.LIST_ROW_LOCATION_RIGHT_INSET) or 28
        local locMaxWS = (UI_SPACING and UI_SPACING.LIST_ROW_LOCATION_MAX_WIDTH) or 120
        row.locationText:SetPoint("RIGHT", row, "RIGHT", -locInsetS, 0)
        row.locationText:SetWidth(locMaxWS)
        row.locationText:SetJustifyH("RIGHT")
        row.locationText:SetWordWrap(false)
        row.locationText:SetNonSpaceWrap(false)
        row.locationText:SetMaxLines(1)
        row.nameText:SetPoint("RIGHT", row.locationText, "LEFT", -10, 0)

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
                -- Only clear scripts that the widget actually supports
                if child:HasScript("OnClick") then
                    local success = pcall(function() child:SetScript("OnClick", nil) end)
                    if not success and IsDebugModeEnabled and IsDebugModeEnabled() then
                        local childType = child:GetObjectType()
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

--============================================================================
-- PROFESSION CRAFTING QUALITY ATLASES (Midnight — R1 / R2 / R3 chat icons)
-- Required atlases: Professions-ChatIcon-Quality-12-Tier1 | Tier2 | Tier3
-- Recipe Companion + Gear tab; tier reflects actual enchant rank.
--============================================================================

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

--- Characters tab row: horizontal class tint (Gear model–style: class×0.5, no additive white).
--- @param gradientWidthPx number|nil  Width from row left edge (px). When set, gradient ends at identity text block; else ~17.5% row width fallback.
--- Call after ApplyRowBackground / ApplyOnlineCharacterHighlight so row.bg exists for blend target.
local ROW_CLASS_GRADIENT_WIDTH_FRAC = 0.175
local function ApplyCharacterRowClassGradientAccent(row, classFile, gradientWidthPx)
    if not row then return end
    local cc = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not cc then
        if row._wnClassGradientTex then
            row._wnClassGradientTex:Hide()
        end
        return
    end

    local r, g, b = cc.r, cc.g, cc.b
    local br, bgc, bb = 0.08, 0.08, 0.10
    if row.bg and row.bg.GetVertexColor then
        br, bgc, bb = row.bg:GetVertexColor()
    end

    local rw = row:GetWidth() or row._wnRowPaintWidth or 200
    local rh = row:GetHeight() or 46
    local w
    if type(gradientWidthPx) == "number" and gradientWidthPx > 1 then
        w = math.max(8, math.min(rw, gradientWidthPx))
    else
        w = math.max(6, rw * ROW_CLASS_GRADIENT_WIDTH_FRAC)
    end

    local tex = row._wnClassGradientTex
    if not tex then
        -- ARTWORK stays visible on pooled Button rows during scroll (BORDER can drop out with highlight).
        tex = row:CreateTexture(nil, "ARTWORK")
        row._wnClassGradientTex = tex
    end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    tex:SetSize(w, rh)
    tex:SetTexture("Interface\\Buttons\\WHITE8x8")
    tex:SetVertexColor(1, 1, 1, 1)
    if tex.SetDrawLayer then
        tex:SetDrawLayer("ARTWORK", 0)
    end
    if row.GetFrameLevel and tex.SetFrameLevel then
        tex:SetFrameLevel(row:GetFrameLevel() + 1)
    end

    local ok = false
    if tex.SetGradient and CreateColor then
        -- Class tint: closer to RAID_CLASS_COLORS (readable hue); right stop still alpha 0.
        local tR = math.min(1, r * 0.58)
        local tG = math.min(1, g * 0.58)
        local tB = math.min(1, b * 0.58)
        local cL = CreateColor(tR, tG, tB, 0.42)
        local cR = CreateColor(br, bgc, bb, 0)
        ok = pcall(function()
            tex:SetGradient("HORIZONTAL", cL, cR)
        end)
        if not ok and Enum and Enum.GradientOrientation and Enum.GradientOrientation.Horizontal then
            ok = pcall(function()
                tex:SetGradient(Enum.GradientOrientation.Horizontal, cL, cR)
            end)
        end
    end
    if not ok then
        tex:SetColorTexture(
            math.min(1, r * 0.34 + br * 0.66),
            math.min(1, g * 0.34 + bgc * 0.66),
            math.min(1, b * 0.34 + bb * 0.66),
            0.32
        )
    end
    tex:Show()
end

ns.UI_ApplyCharacterRowClassGradientAccent = ApplyCharacterRowClassGradientAccent

--============================================================================
-- STRETCH ROW VIEWPORT RELAYOUT (shared across tabs)
-- Tabs register row lists on scrollChild; LayoutCoordinator live resize calls tab adapters
-- that delegate here. Characters virtual lists use VirtualListModule instead.
--============================================================================

--- Refresh `_wnGradientRefresh` on visible rows (Characters / Professions / PvE chrome).
function ns.UI_RefreshRegisteredRowGradients(rows)
    if not rows then return end
    for ri = 1, #rows do
        local row = rows[ri]
        if row and row:IsShown() and row._wnGradientRefresh then
            pcall(row._wnGradientRefresh)
        end
    end
end

--- Re-anchor collapsible section bodies under their headers (full scroll width).
---@param scrollChild Frame
---@param opts table|nil sections array, sideMargin, anchorKey (default `_wnAnchorHeader`)
function ns.UI_RelayoutStretchSectionBodies(scrollChild, opts)
    opts = opts or {}
    local sections = opts.sections
    if not sections and scrollChild then
        sections = scrollChild._wnStretchSectionList
    end
    if not sections then return end
    local side = opts.sideMargin
    if side == nil then
        side = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 10
    end
    local anchorKey = opts.anchorKey or "_wnAnchorHeader"
    for si = 1, #sections do
        local cf = sections[si]
        local hdr = cf and cf[anchorKey]
        if cf and hdr then
            cf:ClearAllPoints()
            cf:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", -side, 0)
            cf:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", side, 0)
            cf:SetHeight(math.max(0.1, cf._wnSectionFullH or 0.1))
        end
    end
end

--- Stretch TOPLEFT/TOPRIGHT rows to parent width; refresh stripes + class gradients.
--- opts: rows | rowsKey, sections, rowHeight, yOffsetKey, rowLeftPad, rowRightPad, sideMargin, refreshGradients
function ns.UI_RelayoutStretchRows(scrollChild, opts)
    if not scrollChild then return end
    opts = opts or {}
    if opts.sections or scrollChild._wnStretchSectionList then
        ns.UI_RelayoutStretchSectionBodies(scrollChild, opts)
    end
    local rows = opts.rows
    if not rows then
        local key = opts.rowsKey or "_wnStretchRowList"
        rows = scrollChild[key]
    end
    if not rows then return end
    local rowH = opts.rowHeight
    local yKey = opts.yOffsetKey or "_wnYOffset"
    local leftPad = opts.rowLeftPad or 0
    local rightPad = opts.rowRightPad or 0
    local refreshGradients = opts.refreshGradients ~= false
    for ri = 1, #rows do
        local row = rows[ri]
        if row and row:IsShown() then
            local parent = row:GetParent()
            if parent then
                local yOff = row[yKey] or 0
                row:ClearAllPoints()
                if rowH and row.SetHeight then
                    row:SetHeight(rowH)
                end
                row:SetPoint("TOPLEFT", parent, "TOPLEFT", leftPad, -yOff)
                row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightPad, -yOff)
                local rowW = row:GetWidth()
                if (not rowW or rowW < 2) and parent.GetWidth then
                    rowW = parent:GetWidth()
                end
                if rowW and rowW >= 2 then
                    row._wnRowPaintWidth = rowW
                end
                if row.bg and row.bg.SetAllPoints then
                    row.bg:SetAllPoints()
                end
                if refreshGradients and row._wnGradientRefresh then
                    if rowW and rowW >= 2 then
                        pcall(row._wnGradientRefresh)
                    elseif C_Timer and C_Timer.After then
                        local rowRef = row
                        C_Timer.After(0, function()
                            if rowRef and rowRef:IsShown() and rowRef._wnGradientRefresh then
                                pcall(row._wnGradientRefresh)
                            end
                        end)
                    end
                end
            end
        end
    end
end

--- Viewport resize profiles for `UI_RegisterTabViewportResize` (LayoutCoordinator adapters).
ns.UI_VIEWPORT_RESIZE_MODE = {
    STRETCH_ROWS = "stretch_rows",
    RESULTS_CONTAINER = "results",
    CUSTOM = "custom",
}

local function ResolveTabSideMargin(mf, fallback)
    local side = fallback
    if side == nil then
        side = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    end
    if mf and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mf)
        if m and m.sideMargin then
            side = m.sideMargin
        end
    end
    return side
end

--- Results-annex tabs (Currency, Reputation): widen `resultsContainer` on viewport change.
---@return boolean handled
function ns.UI_RelayoutResultsViewport(scrollChild, contentWidth, mf, opts)
    opts = opts or {}
    if not scrollChild or not contentWidth or contentWidth < 1 then
        return false
    end
    local getContainer = opts.getContainer
    local rc = (getContainer and getContainer(scrollChild)) or scrollChild.resultsContainer
    if not rc then
        return false
    end
    local side = ResolveTabSideMargin(mf, opts.sideMargin)
    rc:SetWidth(math.max(1, contentWidth - side * 2))
    if ns.UI_RelayoutResultsContainer then
        ns.UI_RelayoutResultsContainer(rc, scrollChild, side, opts.bottomInset or 8)
    end
    return true
end

--- Register a tab with the standard viewport resize contract (live + commit via LayoutCoordinator).
--- Profile:
---   mode          UI_VIEWPORT_RESIZE_MODE.* (default CUSTOM)
---   tabKey        mf.currentTab value (default tabId)
---   freezeWhileResizing  skip live body work during corner-drag (Items/PvE/Chars pattern)
---   stretch       opts table | fn(scrollChild, contentWidth, mf) -> opts for UI_RelayoutStretchRows
---   results       { getContainer?, sideMargin?, bottomInset? }
---   onLive        fn -> boolean|nil handled (CUSTOM or pre-hook)
---   onLiveAfter   fn after stretch/results live pass
---   onCommit      fn -> boolean|nil; false/nil = allow PopulateContent on commit
---   refreshHeader run UI_RefreshFixedHeaderChrome on commit
function ns.UI_RegisterTabViewportResize(tabId, profile)
    local LC = ns.UI_LayoutCoordinator
    if not LC or not tabId or not profile then
        return
    end
    local mode = profile.mode or ns.UI_VIEWPORT_RESIZE_MODE.CUSTOM
    local tabKey = profile.tabKey or tabId

    local function TabIsActive(mf)
        return mf and mf.currentTab == tabKey
    end

    local function ResolveStretchOpts(scrollChild, contentWidth, mf)
        local stretch = profile.stretch
        if type(stretch) == "function" then
            return stretch(scrollChild, contentWidth, mf)
        end
        return stretch
    end

    local function RunStretchLive(scrollChild, contentWidth, mf)
        if profile.onLive then
            profile.onLive(scrollChild, contentWidth, mf)
        end
        local opts = ResolveStretchOpts(scrollChild, contentWidth, mf)
        if opts then
            ns.UI_RelayoutStretchRows(scrollChild, opts)
        end
        if profile.onLiveAfter then
            profile.onLiveAfter(scrollChild, contentWidth, mf)
        end
        return true
    end

    local function RunResultsLive(scrollChild, contentWidth, mf)
        if profile.onLive then
            profile.onLive(scrollChild, contentWidth, mf)
        end
        local handled = ns.UI_RelayoutResultsViewport(scrollChild, contentWidth, mf, profile.results)
        if profile.onLiveAfter then
            profile.onLiveAfter(scrollChild, contentWidth, mf)
        end
        return handled
    end

    LC:RegisterTabAdapter(tabId, {
        OnViewportWidthChanged = function(scrollChild, contentWidth, mf)
            if not TabIsActive(mf) then
                return false
            end
            if profile.freezeWhileResizing and ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(mf) then
                return true
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.STRETCH_ROWS then
                return RunStretchLive(scrollChild, contentWidth, mf)
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.RESULTS_CONTAINER then
                return RunResultsLive(scrollChild, contentWidth, mf)
            end
            if profile.onLive then
                return profile.onLive(scrollChild, contentWidth, mf) == true
            end
            return false
        end,
        OnViewportLayoutCommit = function(scrollChild, contentWidth, mf)
            if not TabIsActive(mf) then
                return false
            end
            if profile.onCommit then
                local commitHandled = profile.onCommit(scrollChild, contentWidth, mf)
                if commitHandled ~= nil then
                    return commitHandled == true
                end
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.RESULTS_CONTAINER then
                return RunResultsLive(scrollChild, contentWidth, mf)
            end
            if mode == ns.UI_VIEWPORT_RESIZE_MODE.STRETCH_ROWS and profile.stretchCommitLive ~= false then
                RunStretchLive(scrollChild, contentWidth, mf)
            end
            if profile.refreshHeader and ns.UI_RefreshFixedHeaderChrome then
                ns.UI_RefreshFixedHeaderChrome(mf)
            end
            return profile.handledCommit == true
        end,
    })
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
local function BuildCollapsibleSectionOpts(config)
    if type(config) ~= "table" then return nil end

    local bodyGetter = config.bodyGetter or config.animatedContent or config.frame
    if type(bodyGetter) ~= "function" then
        local bodyFrame = bodyGetter
        bodyGetter = function() return bodyFrame end
    end
    if not bodyGetter then return nil end

    local minBodyHeight = config.minBodyHeight or 0.1
    local updateVisibleFn = config.updateVisibleFn
    local scheduleVisibleUpdate = config.scheduleVisibleUpdate ~= false
    local updateScheduled = false
    local function NotifyVisibleUpdate()
        if type(updateVisibleFn) ~= "function" then return end
        if not scheduleVisibleUpdate then
            updateVisibleFn()
            return
        end
        if updateScheduled then return end
        updateScheduled = true
        C_Timer.After(0, function()
            updateScheduled = false
            if type(updateVisibleFn) == "function" then
                updateVisibleFn()
            end
        end)
    end

    local persistFn = config.persistToggle or config.persistFn
    local onUpdateExtra = config.onUpdate
    local onCompleteExtra = config.onComplete
    local refreshFn = config.refreshFn
    local hideOnCollapse = config.hideOnCollapse == true
    local showOnExpand = config.showOnExpand == true
    local hideBodyBeforeCollapseAnimate = config.hideBodyBeforeCollapseAnimate == true

    return {
        animatedContent = bodyGetter,
        persistToggle = function(exp)
            if type(persistFn) == "function" then
                persistFn(exp)
            end
        end,
        applyToggleBeforeCollapseAnimate = config.applyToggleBeforeCollapseAnimate == true,
        deferOnToggleUntilComplete = config.deferOnToggleUntilComplete == true,
        hideBodyBeforeCollapseAnimate = hideBodyBeforeCollapseAnimate,
        minBodyHeight = minBodyHeight,
        sectionOnUpdate = function(drawH)
            if config.wrapFrame and config.headerHeight then
                config.wrapFrame:SetHeight(config.headerHeight + math.max(minBodyHeight, drawH or 0))
            end
            if type(onUpdateExtra) == "function" then
                onUpdateExtra(drawH)
            end
            NotifyVisibleUpdate()
        end,
        sectionOnComplete = function(exp)
            local body = bodyGetter()
            if body then
                if exp and showOnExpand then
                    body:Show()
                    body:SetAlpha(1)
                elseif not exp and hideOnCollapse then
                    body:Hide()
                    body:SetHeight(minBodyHeight)
                end
            end
            if type(onCompleteExtra) == "function" then
                onCompleteExtra(exp)
            end
            if type(refreshFn) == "function" then
                refreshFn(exp)
            end
            NotifyVisibleUpdate()
        end,
    }
end

local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture, isAtlas, indentLevel, noCategoryIcon, visualOpts)
    visualOpts = (type(visualOpts) == "table") and visualOpts or nil
    -- Support for nested headers (indentLevel: 0 = root, 1 = child, etc.)
    indentLevel = indentLevel or 0
    local indent = indentLevel * UI_LAYOUT.BASE_INDENT
    
    -- Create new header (no pooling for headers - they're infrequent and context-specific)
    -- Use max(1,...) so layout never gets 0/negative width when parent not yet laid out
    local parentW = (parent and parent:GetWidth()) or 0
    local sectionH = (visualOpts and type(visualOpts.sectionHeaderHeight) == "number" and visualOpts.sectionHeaderHeight)
        or (UI_LAYOUT and UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT)
        or 36
    local suppressSectionChrome = visualOpts and visualOpts.suppressSectionChrome == true
    local sideInset = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or (UI_LAYOUT and UI_LAYOUT.SIDE_MARGIN) or 12
    local useFullParentWidth = visualOpts and visualOpts.useFullParentWidth == true
    local stackWidth = visualOpts and tonumber(visualOpts.sectionStackWidth)
    local header = CreateFrame("Button", nil, parent)
    local headerW
    if stackWidth and stackWidth > 0 then
        headerW = math.max(1, stackWidth - indent)
    elseif useFullParentWidth then
        headerW = math.max(1, parentW - indent)
    else
        headerW = math.max(1, parentW - (sideInset * 2) - indent)
    end
    header:SetSize(headerW, sectionH)
    header:EnableMouse(true)
    if header.RegisterForClicks then
        header:RegisterForClicks("LeftButtonUp")
    end

    local accentColor = COLORS.accent
    local br, bg, bb, ba = accentColor[1], accentColor[2], accentColor[3], 0.5
    local sr, sg, sb, sa = accentColor[1], accentColor[2], accentColor[3], 0.9
    local preset = visualOpts and visualOpts.sectionPreset
    if preset == "gold" then
        br, bg, bb = 1, 0.82, 0.2
        sr, sg, sb = 1, 0.82, 0.2
    elseif preset == "danger" then
        br, bg, bb = 0.8, 0.25, 0.25
        sr, sg, sb = 0.8, 0.25, 0.25
    end
    local ly = UI_LAYOUT or UI_SPACING
    local stripeW = (ly and ly.SECTION_HEADER_STRIPE_WIDTH) or 3
    local stripeVInset = (ly and ly.SECTION_HEADER_STRIPE_V_INSET) or 4
    local chevLeft = (ly and ly.SECTION_HEADER_COLLAPSE_CHEVRON_LEFT) or 12
    local catIconGap = (ly and ly.SECTION_HEADER_CATEGORY_ICON_GAP) or 8
    local titleAfterIcon = (ly and ly.SECTION_HEADER_TITLE_AFTER_ICON) or 12

    if not suppressSectionChrome then
        if preset == "gold" or preset == "danger" then
            ApplyVisuals(header, {0.06, 0.06, 0.08, 0.95}, {br, bg, bb, ba})
        else
            local surf = COLORS.surfaceElevated or COLORS.bgLight
            ApplyVisuals(header, {surf[1], surf[2], surf[3], 0.96}, {br, bg, bb, ba})
        end

        local stripe = header:CreateTexture(nil, "ARTWORK", nil, 2)
        stripe:SetSize(stripeW, math.max(4, sectionH - stripeVInset - stripeVInset))
        stripe:SetPoint("LEFT", 4, 0)
        stripe:SetColorTexture(sr, sg, sb, sa)
        header._wnSectionStripe = stripe
        if header._wnHairlinebottom and header._wnHairlinebottom.Hide then
            header._wnHairlinebottom:Hide()
        end
        -- Soft join into first row (same accent; lower alpha than header border).
        if not header._wnSectionRowJoin then
            local join = header:CreateTexture(nil, "BORDER", nil, 1)
            join:SetHeight(1)
            join:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", stripeW + 8, 1)
            join:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, 1)
            header._wnSectionRowJoin = join
        end
        header._wnSectionRowJoin:SetColorTexture(br, bg, bb, 0.28)
        header._wnSectionRowJoin:Show()
    else
        header._wnSectionStripe = nil
        if header._wnSectionRowJoin then header._wnSectionRowJoin:Hide() end
    end
    
    -- Expand/collapse: shared Button + single texture (parent header handles click)
    local iconTint = COLORS.accent
    local chevSz = (ly and ly.SECTION_COLLAPSE_CHEVRON_SIZE) or (UI_SPACING and UI_SPACING.COLLAPSE_EXPAND_BUTTON_SIZE) or 22
    local expandIcon = ns.UI_CreateCollapseExpandControl(header, isExpanded, {
        enableMouse = false,
        size = chevSz,
        vertexColor = { iconTint[1] * 1.5, iconTint[2] * 1.5, iconTint[3] * 1.5, 1 },
    })
    expandIcon:SetPoint("LEFT", chevLeft + indent, 0)

    local textAnchor = expandIcon
    local textOffset = titleAfterIcon
    
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
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", catIconGap, 0)
        
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
        textOffset = titleAfterIcon
    end
    
    -- Header text (title font — matches Characters tab section labels)
    local headerText = FontManager:CreateFontString(header, UIFontRole("sectionCollapsibleTitle"), "OVERLAY")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetJustifyH("LEFT")
    headerText:SetText(text)
    if preset == "danger" then
        headerText:SetTextColor(0.7, 0.7, 0.7)
    else
        headerText:SetTextColor(1, 1, 1)
    end
    if suppressSectionChrome then
        headerText:SetText("")
        headerText:Hide()
    end
    
    -- Click handler: optional animatedContent body resizes instantly; then onToggle / callbacks.
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        ns.UI_CollapseExpandSetState(expandIcon, isExpanded)

        local persistToggleFn = visualOpts and visualOpts.persistToggle
        if persistToggleFn then
            persistToggleFn(isExpanded)
        end

        local animContent = visualOpts and visualOpts.animatedContent
        local deferToggleUntilComplete = visualOpts and visualOpts.deferOnToggleUntilComplete == true
        local sectionOnUpdate = visualOpts and visualOpts.sectionOnUpdate
        local sectionOnCompleteFn = visualOpts and visualOpts.sectionOnComplete
        local function callSectionOnComplete(expandedState)
            if type(sectionOnCompleteFn) == "function" then
                sectionOnCompleteFn(expandedState)
            end
        end
        if type(animContent) == "function" then animContent = animContent() end
        if animContent then
            local fullH = animContent._wnSectionFullH
            if not fullH or fullH <= 0 then
                fullH = animContent:GetHeight()
                if fullH and fullH > 0 then animContent._wnSectionFullH = fullH end
            end

            local toggleBeforeCollapse = visualOpts and visualOpts.applyToggleBeforeCollapseAnimate == true
            if not isExpanded then
                if toggleBeforeCollapse then
                    onToggle(isExpanded)
                end
                if visualOpts and visualOpts.hideBodyBeforeCollapseAnimate then
                    animContent:Hide()
                end
                local drawEnd = (visualOpts and visualOpts.minBodyHeight) or 0.1
                animContent:SetHeight(drawEnd)
                if sectionOnUpdate then sectionOnUpdate(drawEnd) end
                if not toggleBeforeCollapse then
                    onToggle(isExpanded)
                end
                callSectionOnComplete(isExpanded)
            else
                animContent:Show()
                animContent:SetAlpha(1)
                local target = animContent._wnSectionFullH or math.max(0.1, animContent:GetHeight() or 0.1)
                target = math.max(0.1, target)
                if deferToggleUntilComplete then
                    animContent:SetHeight(target)
                    if sectionOnUpdate then sectionOnUpdate(target) end
                    onToggle(isExpanded)
                    callSectionOnComplete(isExpanded)
                else
                    -- onToggle first so callers can populate _wnSectionFullH / row heights before we read target.
                    onToggle(isExpanded)
                    local fullH2 = animContent._wnSectionFullH
                    if not fullH2 or fullH2 <= 0 then
                        fullH2 = animContent:GetHeight()
                        if fullH2 and fullH2 > 0 then
                            animContent._wnSectionFullH = fullH2
                        end
                    end
                    target = math.max(0.1, fullH2 or math.max(0.1, animContent:GetHeight() or 0.1))
                    animContent:SetHeight(target)
                    if sectionOnUpdate then sectionOnUpdate(target) end
                    callSectionOnComplete(isExpanded)
                end
            end
        else
            onToggle(isExpanded)
        end
    end)
    
    -- Apply highlight effect
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(header)
    end

    header:EnableMouseWheel(true)
    header:SetScript("OnMouseWheel", function(self, d)
        ForwardMouseWheelToScrollAncestor(self, d)
    end)
    
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

    local raceMap = Constants and Constants.RACE_FILE_TO_ATLAS_PREFIX
    local atlasRace = raceMap and raceMap[raceFile]
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
}

ns.UI_MAIN_TAB_NAV_MEDIA = TAB_NAV_TEXTURE_FALLBACK

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

--- Main nav strip / rail: Blizzard atlas (`UI_GetTabIcon`) then built-in texture paths (packaged TGAs optional).
---@param tex Texture
---@param tabKey string
---@return boolean usedPackaged Unused; kept for call-site compatibility (always false when Media lacks matching files).
--- Title card glyph: atlas/tab icon with uniform inset crop (consistent visual weight per tab).
---@param tex Texture
---@param tabKey string|nil
---@param atlasName string|nil
function ns.UI_ApplyTitleCardGlyph(tex, tabKey, atlasName)
    if not tex then return end
    local applied = false
    if atlasName and atlasName ~= "" then
        applied = pcall(tex.SetAtlas, tex, atlasName, false) or pcall(tex.SetAtlas, tex, atlasName, true)
    end
    if not applied and tabKey and ns.UI_ApplyMainNavTabGlyph then
        ns.UI_ApplyMainNavTabGlyph(tex, tabKey)
    elseif not applied then
        if not pcall(tex.SetAtlas, tex, "shop-icon-housing-characters-up", false) then
            tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end
    end
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

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
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        return false
    end

    tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return false
end

ns.UI_GetCharKey = function(char)
    if char and char._key then return char._key end
    if not ns.Utilities then return nil end
    if char and ns.Utilities.ResolveCharacterRowKey then
        local rk = ns.Utilities:ResolveCharacterRowKey(char)
        if rk then return rk end
    end
    if ns.Utilities.GetCharacterKey then
        return ns.Utilities:GetCharacterKey(char and char.name or "Unknown", char and char.realm or "Unknown")
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

-- Export size configuration (legacy callers: size, outerSize, inset, 0).
ns.UI_GetHeaderIconSize = function()
    local outer = HEADER_ICON_SIZE + (HEADER_ICON_PAD * 2)
    return HEADER_ICON_SIZE, outer, HEADER_ICON_INSET, 0
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
    local glyphSize = options.glyphSize or sp.TITLE_CARD_ICON_GLYPH_SIZE or 30

    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(tileOuter, tileOuter)
    container:EnableMouse(false)

    local icon = container:CreateTexture(nil, "ARTWORK")
    local glyphPad = sp.TITLE_CARD_ICON_GLYPH_PAD or 3
    local glyphSz = options.glyphSize or glyphSize
    if not glyphSz or glyphSz <= 0 then
        glyphSz = math.max(28, tileOuter - (glyphPad * 2))
    end
    icon:SetSize(glyphSz, glyphSz)
    icon:SetPoint("CENTER", container, "CENTER", 0, 0)
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
        glyphSize = glyphSz,
    }
end

--- Items / Gear: open result lists on content tone (no viewport rim box or scroll fill band).
---@param mainFrame Frame|nil
---@param tab string|nil
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
local function CreateStandardTabTitleCard(headerParent, opts)
    if not headerParent or type(opts) ~= "table" then return nil end
    local sp = UI_SPACING or {}
    local cardH = opts.cardHeight or sp.TITLE_CARD_DEFAULT_HEIGHT or 64
    local textW = opts.textContainerWidth or 200
    local tileOuter = opts.tileOuter or sp.TITLE_CARD_ICON_TILE_OUTER or 44
    local glyphSize = opts.glyphSize or sp.TITLE_CARD_ICON_GLYPH_SIZE or 30
    local iconSideInset = opts.iconSideInset
    if iconSideInset == nil then
        iconSideInset = sp.TITLE_CARD_ICON_SIDE_INSET or 0
    end
    local ringGap = sp.TITLE_CARD_RING_TEXT_GAP or 12
    local textPadV = sp.TITLE_CARD_TEXT_PAD_V or 8
    local iconTopInset = math.max(0, math.floor((cardH - tileOuter) * 0.5))

    local titleCard = CreateCard(headerParent, cardH)
    if not opts.skipApplyVisuals then
        ApplyStandardCardElevatedChrome(titleCard)
    end
    local atlas = opts.atlasName
    if (not atlas or atlas == "") and opts.tabKey and ns.UI_GetTabIcon then
        atlas = ns.UI_GetTabIcon(opts.tabKey)
    end
    local headerIcon = CreateHeaderIcon(titleCard, atlas, {
        tabKey = opts.tabKey,
        tileOuter = tileOuter,
        glyphSize = glyphSize,
    })
    headerIcon.border:ClearAllPoints()
    headerIcon.border:SetPoint("TOPLEFT", titleCard, "TOPLEFT", iconSideInset, -iconTopInset)

    local textContainer = ns.UI.Factory:CreateContainer(titleCard, textW, math.max(36, cardH - textPadV * 2))
    local titleFs = FontManager:CreateFontString(textContainer, UIFontRole("tabTitlePrimary"), "OVERLAY")
    titleFs:SetText(opts.titleText or "")
    titleFs:SetJustifyH("LEFT")
    titleFs:SetPoint("TOPLEFT", textContainer, "TOPLEFT", 0, -2)
    titleFs:SetPoint("RIGHT", textContainer, "RIGHT", 0, 0)

    local subtitleFs = FontManager:CreateFontString(textContainer, UIFontRole("tabSubtitle"), "OVERLAY")
    subtitleFs:SetText(opts.subtitleText or "")
    subtitleFs:SetTextColor(0.88, 0.88, 0.90)
    subtitleFs:SetJustifyH("LEFT")
    subtitleFs:SetWordWrap(false)
    subtitleFs:SetNonSpaceWrap(false)
    if subtitleFs.SetMaxLines then subtitleFs:SetMaxLines(1) end
    subtitleFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -3)
    subtitleFs:SetPoint("TOPRIGHT", textContainer, "TOPRIGHT", 0, 0)

    local rin = opts.textRightInset
    textContainer:ClearAllPoints()
    textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", ringGap, 0)
    if type(rin) == "number" and rin > 0 then
        textContainer:SetPoint("RIGHT", titleCard, "RIGHT", -rin, 0)
        textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
        textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
    else
        textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
        textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
    end

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
    local iconSideInset = sp.TITLE_CARD_ICON_SIDE_INSET or 0
    local ringGap = sp.TITLE_CARD_RING_TEXT_GAP or 12
    local textPadV = sp.TITLE_CARD_TEXT_PAD_V or 8
    local iconTopInset = math.max(0, math.floor((cardHeight - tileOuter) * 0.5))
    headerIcon.border:ClearAllPoints()
    headerIcon.border:SetPoint("TOPLEFT", titleCard, "TOPLEFT", iconSideInset, -iconTopInset)
    if textContainer then
        textContainer:ClearAllPoints()
        textContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", ringGap, 0)
        if type(textRightInset) == "number" and textRightInset > 0 then
            textContainer:SetPoint("RIGHT", titleCard, "RIGHT", -textRightInset, 0)
        end
        textContainer:SetPoint("TOP", titleCard, "TOP", 0, -textPadV)
        textContainer:SetPoint("BOTTOM", titleCard, "BOTTOM", 0, textPadV)
    end
    if titleCard._wnTitleUnderline then
        titleCard._wnTitleUnderline:Hide()
    end
end

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
    if issecretvalue and issecretvalue(headerName) then
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
    headerAssign = {
        width = 22,    -- Custom section / folder menu (Characters tab)
        spacing = 4,
        total = 26,
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
    local order = {"favorite", "faction", "race", "class", "name", "guild", "level", "itemLevel", "gold", "professions", "mythicKey", "reorder", "lastSeen", "headerAssign", "delete"}
    
    for oi = 1, #order do
        local key = order[oi]
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
    local order = {"favorite", "faction", "race", "class", "name", "guild", "level", "itemLevel", "gold", "professions", "mythicKey", "reorder", "lastSeen", "headerAssign", "delete"}
    
    for oi = 1, #order do
        width = width + CHAR_ROW_COLUMNS[order[oi]].total
    end
    
    width = width + 10  -- Right padding
    return width
end

--- Row minimum width when guild column is wider than `CHAR_ROW_COLUMNS.guild` (Characters tab measure pass).
---@param guildColW number|nil measured guild column width (defaults to layout guild.width)
---@return number
local function GetCharRowTotalWidthForGuild(guildColW)
    local base = GetCharRowTotalWidth()
    local gCol = CHAR_ROW_COLUMNS.guild or {}
    local gTot = gCol.total or 145
    local actual = (guildColW or gCol.width or 130) + (gCol.spacing or 15)
    return base + math.max(0, actual - gTot)
end

local CHAR_ROW_RIGHT_MARGIN = 6
local CHAR_ROW_RIGHT_GAP = 6

--- Fixed-width right block for character rows (delete / header / last seen / reorder).
---@return number
local function GetCharRowRightRailWidth()
    local c = CHAR_ROW_COLUMNS
    return CHAR_ROW_RIGHT_MARGIN
        + (c.delete and c.delete.width or 24)
        + CHAR_ROW_RIGHT_GAP
        + (c.headerAssign and c.headerAssign.total or 26)
        + CHAR_ROW_RIGHT_GAP
        + (c.lastSeen and c.lastSeen.width or 60)
        + CHAR_ROW_RIGHT_GAP
        + (c.reorder and c.reorder.width or 44)
        + CHAR_ROW_RIGHT_MARGIN
end

--- Width of level + itemLevel + gold + professions + mythicKey column run (left of right rail).
---@return number
local function GetCharRowMiddleBlockWidth()
    local c = CHAR_ROW_COLUMNS
    return (c.level and c.level.total or 97)
        + (c.itemLevel and c.itemLevel.total or 90)
        + (c.gold and c.gold.total or 205)
        + (c.professions and c.professions.total or 150)
        + (c.mythicKey and c.mythicKey.total or 135)
end

--- Guild column width capped once per list layout (stable while row width changes).
---@param listRowW number
---@param measuredGuildW number|nil
---@return number
local function ComputeCharRowGuildColumnWidth(listRowW, measuredGuildW)
    local guildOffset = GetColumnOffset("guild")
    local railW = GetCharRowRightRailWidth()
    local middleW = GetCharRowMiddleBlockWidth()
    local maxGuild = (listRowW or 800) - guildOffset - middleW - railW - 4
    local gCol = CHAR_ROW_COLUMNS.guild or {}
    local measured = measuredGuildW or gCol.width or 130
    return math.min(measured, math.max(60, maxGuild))
end

--- Minimum scroll width for Characters rows (fixed column grid; horizontal scroll when viewport is narrower).
---@param _addon table|nil
---@param guildColW number|nil measured guild column width from DrawCharacterList
---@return number
local function ComputeCharactersMinScrollWidth(_addon, guildColW)
    if GetCharRowTotalWidthForGuild then
        return math.max(720, GetCharRowTotalWidthForGuild(guildColW))
    end
    if GetCharRowTotalWidth then
        return math.max(720, GetCharRowTotalWidth())
    end
    return 1100
end

--- Characters row paint width: at least the fixed column grid; grows with viewport (no empty band on the right).
--- Horizontal scroll still uses `ComputeCharactersMinScrollWidth` on scrollChild when viewport is narrower.
---@param mainFrame Frame|nil
---@param scrollParent Frame|nil
---@param metrics table|nil
---@param guildColW number|nil
---@return number
local function ResolveCharactersTabRowWidth(mainFrame, scrollParent, metrics, guildColW)
    local minW = ComputeCharactersMinScrollWidth(WarbandNexus, guildColW)
    local viewportW = minW
    if metrics and metrics.bodyWidth and metrics.bodyWidth > 0 then
        viewportW = metrics.bodyWidth
    elseif mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.bodyWidth and m.bodyWidth > 0 then
            viewportW = m.bodyWidth
        end
    elseif scrollParent and scrollParent.GetWidth then
        viewportW = scrollParent:GetWidth() or minW
    end
    return math.max(minW, viewportW)
end

--- Live corner-drag row width: viewport body only (no jump to min scroll-child width while frozen).
---@param mainFrame Frame|nil
---@param scrollParent Frame|nil
---@param metrics table|nil
---@param guildColW number|nil
---@return number
function ns.UI_ResolveCharactersTabRowWidthForLive(mainFrame, scrollParent, metrics, guildColW)
    local viewportW = 200
    if metrics and metrics.bodyWidth and metrics.bodyWidth > 0 then
        viewportW = metrics.bodyWidth
    elseif mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.bodyWidth and m.bodyWidth > 0 then
            viewportW = m.bodyWidth
        end
    elseif scrollParent and scrollParent.GetWidth then
        viewportW = scrollParent:GetWidth() or 200
    else
        viewportW = 200
    end
    return math.max(200, viewportW)
end

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
---@param widths number[]|nil control widths outermost (card edge) to innermost
---@param opts table|nil `{ extraTrailingGap = number }`
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

--- Title-card toolbar reserve for Characters (Filter + section + expand + gaps + right inset).
---@return number
local function ComputeCharactersTitleToolbarReserve()
    local m = ns.UI_GetTitleCardToolbarMetrics()
    return ns.UI_ComputeTitleToolbarReserve({ m.filterW, m.squareBtn, m.squareBtn })
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
local activePickMenu = nil

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
        local itemHeight = (UI_SPACING and UI_SPACING.DROPDOWN_MENU_ROW_HEIGHT) or (UI_SPACING and UI_SPACING.ROW_HEIGHT) or 26
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

        -- Nil/unknown keys: highlight first menu option (per-tab default differs, e.g. Characters = default order).
        local rawKey = dbSortTable and dbSortTable.key
        local currentKey = nil
        if type(rawKey) == "string" and rawKey ~= "" then
            for j = 1, itemCount do
                if sortOptions[j].key == rawKey then
                    currentKey = rawKey
                    break
                end
            end
        end
        if not currentKey and sortOptions[1] and sortOptions[1].key then
            currentKey = sortOptions[1].key
        end
        if not currentKey then
            currentKey = "manual"
        end
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

--============================================================================
-- CHARACTERS / PROFESSIONS: Filter + sort + section view (nested flyouts)
--============================================================================

---@param ownerBtn Button|nil
local function WnCloseFullAdvFilter(ownerBtn)
    if ownerBtn then
        if ownerBtn._wnAdvSub and ownerBtn._wnAdvSub.Hide then
            ownerBtn._wnAdvSub:Hide()
        end
        ownerBtn._wnAdvSub = nil
        if ownerBtn._wnAdvRoot and ownerBtn._wnAdvRoot.Hide then
            ownerBtn._wnAdvRoot:Hide()
        end
        ownerBtn._wnAdvRoot = nil
        if ownerBtn._sortClickCatcher then ownerBtn._sortClickCatcher:Hide() end
    end
    if activeSortDropdownMenu and activeSortDropdownMenu.Hide then
        activeSortDropdownMenu:Hide()
    end
    activeSortDropdownMenu = nil
end

--- Close Filter flyouts and row pick menus (resize / scroll / tab rebuild).
function ns.UI_CloseCharacterTabFlyoutMenus()
    WnCloseFullAdvFilter(nil)
    if activePickMenu and activePickMenu.Hide then
        activePickMenu:Hide()
    end
    activePickMenu = nil
end

--- Characters / Professions title card: sort modes + section filter + optional delete custom header.
--- opts: sortOptions, dbSortTable, dbSectionFilter, getCustomSections(), onRefresh(), onDeleteSection(groupId, groupName)
---@return Button|nil
local function CreateCharacterTabAdvancedFilterButton(parent, opts)
    if not parent or not opts or not ns.UI or not ns.UI.Factory or not ns.UI.Factory.CreateButton then
        return nil
    end
    local sortOptions = opts.sortOptions
    local dbSortTable = opts.dbSortTable
    local dbSectionFilter = opts.dbSectionFilter
    local getCustomSections = opts.getCustomSections
    local onRefresh = opts.onRefresh
    local onDeleteSection = opts.onDeleteSection
    if not sortOptions or not dbSortTable or not dbSectionFilter or not onRefresh then
        return nil
    end

    local buttonHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local btnWidth = 96
    local btn = ns.UI.Factory:CreateButton(parent, btnWidth, buttonHeight, false)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.6})
    end
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetAtlas("uitools-icon-filter")
    icon:SetVertexColor(0.8, 0.8, 0.8)
    local text = btn:CreateFontString(nil, "OVERLAY")
    if ns.FontManager then ns.FontManager:ApplyFont(text, "body") else text:SetFontObject("GameFontNormal") end
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetText((ns.L and ns.L["FILTER_LABEL"]) or "Filter")
    text:SetTextColor(0.9, 0.9, 0.9)
    icon:SetPoint("RIGHT", text, "LEFT", -6, 0)

    local itemHeight = (UI_SPACING and UI_SPACING.DROPDOWN_MENU_ROW_HEIGHT) or (UI_SPACING and UI_SPACING.ROW_HEIGHT) or 26
    local sideMargin = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or 10
    local radioArea = 8 + 16 + 6

    local function measureMaxLabelWidth(labels)
        local maxW = 0
        local measure = btn:CreateFontString(nil, "OVERLAY")
        if ns.FontManager then ns.FontManager:ApplyFont(measure, "body") else measure:SetFontObject("GameFontNormal") end
        for i = 1, #labels do
            measure:SetText(labels[i] or "")
            local w = measure:GetStringWidth()
            if w and w > maxW then maxW = w end
        end
        measure:SetText("")
        return maxW
    end

    local function openFlyoutFrom(anchorMenu, rows, anchorYOffset)
        if btn._wnAdvSub and btn._wnAdvSub.Hide then
            btn._wnAdvSub:Hide()
        end
        btn._wnAdvSub = nil
        if not rows or #rows == 0 then return end
        local labels = {}
        for i = 1, #rows do labels[i] = rows[i].label or "" end
        local mw = math.max(160, math.ceil(measureMaxLabelWidth(labels)) + sideMargin * 2 + radioArea + 16)
        local mh = #rows * itemHeight + ((UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8)
        local sub = ns.UI.Factory:CreateContainer(UIParent, mw, mh, true)
        sub:SetFrameStrata("FULLSCREEN_DIALOG")
        sub:SetFrameLevel((anchorMenu and anchorMenu:GetFrameLevel() or 300) + 5)
        sub:SetPoint("TOPLEFT", anchorMenu, "TOPRIGHT", 4, anchorYOffset or 0)
        sub:SetClampedToScreen(true)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(sub, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.55, ns.UI_COLORS.accent[2] * 0.55, ns.UI_COLORS.accent[3] * 0.55, 0.85})
        end
        btn._wnAdvSub = sub
        local bw = mw - sideMargin * 2
        for i = 1, #rows do
            local row = rows[i]
            local optionBtn = ns.UI.Factory:CreateButton(sub, bw, itemHeight, true)
            optionBtn:SetPoint("TOPLEFT", sideMargin, -(i - 1) * itemHeight - 4)
            local isSel = row.selected == true
            local radio = (ns.UI_CreateThemedRadioButton and ns.UI_CreateThemedRadioButton(optionBtn, isSel)) or nil
            local optionText = optionBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(optionText, "body") else optionText:SetFontObject("GameFontNormal") end
            if radio then
                radio:SetPoint("LEFT", 8, 0)
                if radio.innerDot then radio.innerDot:SetShown(isSel) end
                optionText:SetPoint("LEFT", radio, "RIGHT", 6, 0)
            else
                optionText:SetPoint("LEFT", 10, 0)
            end
            optionText:SetJustifyH("LEFT")
            optionText:SetText(row.label or "")
            if isSel then
                optionText:SetTextColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3])
            else
                optionText:SetTextColor(1, 1, 1)
            end
            if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(optionBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0}) end
            if ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(optionBtn) end
            optionBtn:SetScript("OnClick", function()
                if row.onPick then row.onPick() end
                WnCloseFullAdvFilter(btn)
                onRefresh()
            end)
        end
        sub:Show()
        return sub
    end

    btn:SetScript("OnEnter", function(self)
        icon:SetVertexColor(1, 1, 1)
        text:SetTextColor(1, 1, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.15, 0.15, 0.15, 0.8}, {ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3], 0.8})
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((ns.L and ns.L["FILTER_MENU_TOOLTIP"]) or "Sort and filter which sections are visible.", 1, 1, 1)
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
        if self._wnAdvRoot and self._wnAdvRoot:IsShown() then
            WnCloseFullAdvFilter(self)
            return
        end
        if activeSortDropdownMenu and activeSortDropdownMenu:IsShown() then
            activeSortDropdownMenu:Hide()
            activeSortDropdownMenu = nil
        end
        WnCloseFullAdvFilter(self)

        local L = ns.L
        local rootLabels = {
            (L and L["FILTER_SUBMENU_SORT"]) or "Sort…",
            (L and L["FILTER_SUBMENU_VIEW"]) or "Show section…",
        }
        local rw = math.max(btn:GetWidth(), math.ceil(measureMaxLabelWidth(rootLabels)) + sideMargin * 2 + 24)
        local rootRowCount = 2
        local rh = rootRowCount * itemHeight + ((UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8)
        local root = ns.UI.Factory:CreateContainer(UIParent, rw, rh, true)
        root._wnAdvRoot = true
        root:SetFrameStrata("FULLSCREEN_DIALOG")
        root:SetFrameLevel(300)
        root:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        root:SetClampedToScreen(true)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(root, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.6, ns.UI_COLORS.accent[2] * 0.6, ns.UI_COLORS.accent[3] * 0.6, 0.8})
        end
        activeSortDropdownMenu = root
        btn._wnAdvRoot = root

        local bw = rw - sideMargin * 2
        local function makeRootRow(index, label, onActivate)
            local rowBtn = ns.UI.Factory:CreateButton(root, bw, itemHeight, true)
            rowBtn:SetPoint("TOPLEFT", sideMargin, -(index - 1) * itemHeight - 4)
            if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(rowBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0}) end
            if ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(rowBtn) end
            local fs = rowBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(fs, "body") else fs:SetFontObject("GameFontNormal") end
            fs:SetPoint("LEFT", 10, 0)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(1, 1, 1)
            fs:SetText(label)
            rowBtn:SetScript("OnClick", function()
                onActivate(rowBtn)
            end)
            return rowBtn
        end

        makeRootRow(1, rootLabels[1], function()
            local rawKey = dbSortTable and dbSortTable.key
            local rows = {}
            for si = 1, #sortOptions do
                local opt = sortOptions[si]
                rows[#rows + 1] = {
                    label = opt.label,
                    selected = (rawKey == opt.key),
                    onPick = function()
                        dbSortTable.key = opt.key
                    end,
                }
            end
            openFlyoutFrom(root, rows, 0)
        end)

        makeRootRow(2, rootLabels[2], function()
            local cur = dbSectionFilter.sectionKey or "all"
            local rows = {
                {
                    label = (L and L["SECTION_FILTER_ALL"]) or "All sections",
                    selected = (cur == "all"),
                    onPick = function() dbSectionFilter.sectionKey = "all" end,
                },
                {
                    label = (L and L["SECTION_FILTER_FAVORITES"]) or "Favorites only",
                    selected = (cur == "favorites"),
                    onPick = function() dbSectionFilter.sectionKey = "favorites" end,
                },
                {
                    label = (L and L["SECTION_FILTER_REGULAR"]) or "Characters (ungrouped) only",
                    selected = (cur == "regular"),
                    onPick = function() dbSectionFilter.sectionKey = "regular" end,
                },
            }
            local customs = getCustomSections and getCustomSections() or {}
            for ci = 1, #customs do
                local g = customs[ci]
                local gid = g.id
                local lk = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
                local gname = g.name or gid
                rows[#rows + 1] = {
                    label = gname,
                    selected = (cur == lk),
                    onPick = function() dbSectionFilter.sectionKey = lk end,
                }
            end
            rows[#rows + 1] = {
                label = (L and L["SECTION_FILTER_UNTRACKED"]) or "Untracked only",
                selected = (cur == "untracked"),
                onPick = function() dbSectionFilter.sectionKey = "untracked" end,
            }
            openFlyoutFrom(root, rows, 0)
        end)

        root:Show()

        local clickCatcher = btn._sortClickCatcher
        if not clickCatcher then
            clickCatcher = CreateFrame("Frame", nil, UIParent)
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel((root:GetFrameLevel() or 300) - 2)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                WnCloseFullAdvFilter(btn)
            end)
            btn._sortClickCatcher = clickCatcher
        end
        clickCatcher:Show()

        local origHide = root:GetScript("OnHide")
        root:SetScript("OnHide", function(m)
            WnCloseFullAdvFilter(btn)
            if origHide then origHide(m) end
        end)
    end)

    return btn
end

--- Shared vertical pick menu (Factory rows). Row: { label, onPick?, noRadio?, selected?, isHeader? }
local function WnShowLabeledPickMenu(anchorFrame, rows, onDone)
    if not anchorFrame or type(rows) ~= "table" or #rows < 1 then return end
    local itemHeight = (UI_SPACING and UI_SPACING.DROPDOWN_MENU_ROW_HEIGHT) or 26
    local sideMargin = 10
    local labels = {}
    for i = 1, #rows do
        if rows[i].label then
            labels[#labels + 1] = rows[i].label
        end
    end
    if #labels < 1 then return end
    local mw = math.max(220, 40 + sideMargin * 2 + (function()
        local maxW = 0
        local measure = anchorFrame:CreateFontString(nil, "OVERLAY")
        if ns.FontManager then ns.FontManager:ApplyFont(measure, "body") else measure:SetFontObject("GameFontNormal") end
        for j = 1, #labels do
            measure:SetText(labels[j])
            local w = measure:GetStringWidth()
            if w and w > maxW then maxW = w end
        end
        measure:SetText("")
        return math.ceil(maxW)
    end)())
    local totalH = 8
    for i = 1, #rows do
        totalH = totalH + (rows[i].isHeader and (itemHeight - 6) or itemHeight)
    end
    if activePickMenu and activePickMenu.Hide then
        activePickMenu:Hide()
    end
    local catcher = CreateFrame("Frame", nil, UIParent)
    local menu = ns.UI.Factory:CreateContainer(UIParent, mw, totalH, true)
    activePickMenu = menu
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(320)
    menu:SetPoint("TOPLEFT", anchorFrame, "BOTTOMRIGHT", 4, -2)
    menu:SetClampedToScreen(true)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(menu, {0.08, 0.08, 0.10, 0.98}, {ns.UI_COLORS.accent[1] * 0.55, ns.UI_COLORS.accent[2] * 0.55, ns.UI_COLORS.accent[3] * 0.55, 0.85})
    end
    local bw = mw - sideMargin * 2
    local y = 4
    for i = 1, #rows do
        local r = rows[i]
        if r.isHeader then
            local bar = CreateFrame("Frame", nil, menu)
            bar:SetSize(bw, itemHeight - 6)
            bar:SetPoint("TOPLEFT", sideMargin, -y)
            local fs = bar:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(fs, "tabSubtitle") else fs:SetFontObject("GameFontNormalSmall") end
            fs:SetPoint("LEFT", 0, 0)
            fs:SetWidth(bw)
            fs:SetJustifyH("LEFT")
            fs:SetText(r.label or "")
            fs:SetTextColor(0.58, 0.62, 0.72)
            y = y + (itemHeight - 6)
        else
            local optionBtn = ns.UI.Factory:CreateButton(menu, bw, itemHeight, true)
            optionBtn:SetPoint("TOPLEFT", sideMargin, -y)
            local radio = nil
            if not r.noRadio then
                radio = (ns.UI_CreateThemedRadioButton and ns.UI_CreateThemedRadioButton(optionBtn, r.selected)) or nil
            end
            local optionText = optionBtn:CreateFontString(nil, "OVERLAY")
            if ns.FontManager then ns.FontManager:ApplyFont(optionText, "body") else optionText:SetFontObject("GameFontNormal") end
            if radio then
                radio:SetPoint("LEFT", 8, 0)
                if radio.innerDot then radio.innerDot:SetShown(r.selected) end
                optionText:SetPoint("LEFT", radio, "RIGHT", 6, 0)
            else
                optionText:SetPoint("LEFT", 10, 0)
            end
            optionText:SetJustifyH("LEFT")
            optionText:SetText(r.label or "")
            if r.disabled then
                optionText:SetTextColor(0.45, 0.45, 0.48)
                optionBtn:EnableMouse(false)
            elseif r.selected then
                optionText:SetTextColor(ns.UI_COLORS.accent[1], ns.UI_COLORS.accent[2], ns.UI_COLORS.accent[3])
            else
                optionText:SetTextColor(1, 1, 1)
            end
            if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(optionBtn, {0.08, 0.08, 0.10, 0}, {0, 0, 0, 0}) end
            if ns.UI.Factory.ApplyHighlight and not r.disabled then ns.UI.Factory:ApplyHighlight(optionBtn) end
            if not r.disabled and r.onPick then
                optionBtn:SetScript("OnClick", function()
                    menu:Hide()
                    if catcher then catcher:Hide() end
                    r.onPick()
                    if onDone then onDone() end
                end)
            else
                optionBtn:SetScript("OnClick", nil)
            end
            y = y + itemHeight
        end
    end
    catcher:SetAllPoints()
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:SetFrameLevel(menu:GetFrameLevel() - 1)
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", function()
        menu:Hide()
        catcher:Hide()
    end)
    catcher:Show()
    menu:SetScript("OnHide", function()
        catcher:Hide()
        if activePickMenu == menu then
            activePickMenu = nil
        end
    end)
    menu:Show()
end

--- Popup: move character to / from a custom section (tracked non-favorites).
function ns.UI_ShowCharacterSectionAssignMenu(anchorFrame, charKey, profile, onDone)
    if not anchorFrame or not charKey or not profile or not ns.CharacterService then return end
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    local L = ns.L
    local rows = {}
    local assignedGroupId = profile.characterGroupAssignments and profile.characterGroupAssignments[charKey]
    if assignedGroupId then
        rows[#rows + 1] = {
            label = (L and L["CUSTOM_HEADER_REMOVE_ASSIGN"]) or "Remove from custom header",
            selected = false,
            noRadio = true,
            onPick = function()
                ns.CharacterService:SetCharacterCustomSection(_G.WarbandNexus or ns.WarbandNexus, charKey, nil)
            end,
        }
    end
    local groups = profile.characterCustomGroups or {}
    for i = 1, #groups do
        local g = groups[i]
        rows[#rows + 1] = {
            label = g.name or g.id,
            selected = (profile.characterGroupAssignments[charKey] == g.id),
            onPick = function()
                ns.CharacterService:SetCharacterCustomSection(_G.WarbandNexus or ns.WarbandNexus, charKey, g.id)
            end,
        }
    end
    WnShowLabeledPickMenu(anchorFrame, rows, onDone)
end

--- Title-bar menu: new/delete custom headers + optional gold header highlight for one section (visual only).
function ns.UI_ShowCharacterSectionsToolbarMenu(anchorFrame, profile)
    if not anchorFrame or not profile or not ns.CharacterService then return end
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    local L = ns.L
    local addon = _G.WarbandNexus or ns.WarbandNexus
    local rows = {}
    rows[#rows + 1] = { isHeader = true, label = (L and L["CUSTOM_HEADER_MENU_SECTION_HEADERS"]) or "Custom headers" }
    rows[#rows + 1] = {
        label = (L and L["CUSTOM_HEADER_MENU_NEW"]) or "New custom section…",
        noRadio = true,
        onPick = function()
            local function openNewHeaderDialog()
                local a = _G.WarbandNexus or ns.WarbandNexus
                if a and a.OpenCustomCharacterHeaderDialog then
                    a:OpenCustomCharacterHeaderDialog()
                end
            end
            -- Defer one tick so pick menu + click catcher finish hiding before the modal opens.
            if C_Timer and C_Timer.After then
                C_Timer.After(0, openNewHeaderDialog)
            else
                openNewHeaderDialog()
            end
        end,
    }
    local groups = profile.characterCustomGroups or {}
    if #groups == 0 then
        rows[#rows + 1] = {
            label = (L and L["CUSTOM_HEADER_MENU_NONE_YET"]) or "No sections yet - use New custom section above.",
            noRadio = true,
            disabled = true,
        }
    else
        rows[#rows + 1] = { isHeader = true, label = (L and L["CUSTOM_HEADER_MENU_DELETE_GROUP"]) or "Delete a section" }
        for i = 1, #groups do
            local g = groups[i]
            rows[#rows + 1] = {
                label = string.format((L and L["CUSTOM_HEADER_MENU_DELETE_FMT"]) or "Delete: %s", g.name or g.id),
                noRadio = true,
                onPick = function()
                    if addon and addon.ConfirmDeleteCustomCharacterHeader then
                        addon:ConfirmDeleteCustomCharacterHeader(g.id, g.name)
                    end
                end,
            }
        end
    end
    WnShowLabeledPickMenu(anchorFrame, rows, nil)
end

local function WnFormatRealmDisplay(raw)
    if not raw or raw == "" then return "" end
    if issecretvalue and issecretvalue(raw) then return "" end
    if ns.Utilities and ns.Utilities.FormatRealmName then
        return ns.Utilities:FormatRealmName(raw) or raw
    end
    return raw
end

local function WnSafeCharLine(char)
    local n = char and char.name
    local rlm = char and char.realm
    if n and issecretvalue and issecretvalue(n) then n = "?" end
    if rlm and issecretvalue and issecretvalue(rlm) then rlm = "" end
    n = n or "?"
    if rlm and rlm ~= "" then
        return n .. " - " .. WnFormatRealmDisplay(rlm)
    end
    return n
end

local function WnPickerTextLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

--- Plain-text blob for search (name + realm + level). Player names may include non-ASCII; do not strip them.
local function WnPlainSearchBlob(char)
    local n = char and char.name
    local rlm = char and char.realm or ""
    if n and issecretvalue and issecretvalue(n) then n = "" end
    if rlm and issecretvalue and issecretvalue(rlm) then rlm = "" end
    n = n or ""
    local rPretty = WnFormatRealmDisplay(rlm)
    local lv = tonumber(char and char.level) or 0
    return WnPickerTextLower(n .. " " .. tostring(rlm) .. " " .. tostring(rPretty) .. " " .. tostring(lv))
end

local function WnPickerLineMatchesChar(char, filterLower)
    if not filterLower or filterLower == "" then return true end
    local blob = WnPlainSearchBlob(char)
    if blob == "" then return false end
    return blob:find(filterLower, 1, true) ~= nil
end

--- Class-colored character name only (roster name column).
local function WnColoredCharacterName(char)
    local n = char and char.name
    if n and issecretvalue and issecretvalue(n) then n = "?" end
    n = n or "?"
    local cc = RAID_CLASS_COLORS and char.classFile and RAID_CLASS_COLORS[char.classFile]
    local r, g, b = 1, 1, 1
    if cc then
        r = cc.r or 1
        g = cc.g or 1
        b = cc.b or 1
    end
    local hx = string.format("%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
    return string.format("|cff%s%s|r", hx, n)
end

local function WnRosterLevelStr(char)
    local lv = tonumber(char and char.level)
    if not lv or lv < 1 then
        return "?"
    end
    return tostring(lv)
end

local function WnRosterRealmColored(char)
    local rlm = char and char.realm or ""
    if rlm and issecretvalue and issecretvalue(rlm) then rlm = "" end
    local rShow = WnFormatRealmDisplay(rlm)
    if rShow == "" then
        return ""
    end
    return "|cffffffff" .. rShow .. "|r"
end

--- Build members / non-member buckets for one custom header (same rules as legacy pick menu).
local function WnBuildCustomHeaderManageBuckets(addon, profile, charactersList, groupId)
    local members, candidates = {}, {}
    if not addon or not profile or not charactersList or not groupId or not ns.CharacterService then
        return members, candidates
    end
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    for i = 1, #charactersList do
        local ch = charactersList[i]
        local ck = ns.UI_GetCharKey(ch)
        if ck and (ch.isTracked ~= false) and not ns.CharacterService:IsFavoriteCharacter(addon, ck) then
            local gid = ns.CharacterService:GetCharacterCustomSectionId(addon, ck)
            if gid == groupId then
                members[#members + 1] = { char = ch, key = ck }
            else
                candidates[#candidates + 1] = { char = ch, key = ck }
            end
        end
    end
    table.sort(members, function(a, b)
        return WnSafeCharLine(a.char) < WnSafeCharLine(b.char)
    end)
    table.sort(candidates, function(a, b)
        return WnSafeCharLine(a.char) < WnSafeCharLine(b.char)
    end)
    return members, candidates
end

--- Roster picker: `groupId` nil = new section (all eligible, checkboxes). Set = manage (members + bulk add).
function ns.UI_CreateCustomHeaderRosterPicker(parent, width, addon, profile, charactersList, groupId)
    if not parent or not addon or not profile or not charactersList or not ns.UI or not ns.UI.Factory or not ns.CharacterService then
        return nil
    end
    local Factory = ns.UI.Factory
    local L = ns.L
    local UI_SPACING = ns.UI_SPACING
    local itemPad = (UI_SPACING and UI_SPACING.AFTER_ELEMENT) or 8
    local filterAreaH = 38
    local scrollBarW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local ROW = 32
    local SECTION_BAR_H = 28
    local SECTION_AFTER = 10
    -- Same left gutter as checkbox rows; same right padding in both blocks so columns line up.
    local ROSTER_CONTENT_LEFT = 36
    local ROSTER_ROW_RIGHT_PAD = 10
    ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)

    local root = CreateFrame("Frame", nil, parent)
    if width and width > 60 then
        root:SetWidth(width)
    end
    root:SetHeight(80)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(root, { 0.06, 0.06, 0.08, 0.98 }, { (ns.UI_COLORS.accent[1] or 0.5) * 0.35, (ns.UI_COLORS.accent[2] or 0.35) * 0.35, (ns.UI_COLORS.accent[3] or 0.5) * 0.35, 0.5 })
    end

    local filterLabel = FontManager:CreateFontString(root, "small", "OVERLAY")
    filterLabel:SetPoint("TOPLEFT", root, "TOPLEFT", 8, -6)
    filterLabel:SetText((L and L["CUSTOM_HEADER_PICKER_FILTER_LABEL"]) or "Search")
    filterLabel:SetTextColor(0.65, 0.68, 0.74)

    local filterBg = Factory:CreateContainer(root, 100, filterAreaH - 6, true)
    filterBg:SetPoint("TOPLEFT", filterLabel, "BOTTOMLEFT", 0, -4)
    filterBg:SetPoint("TOPRIGHT", root, "TOPRIGHT", -8, -16)
    local filterEb = Factory:CreateEditBox(filterBg)
    if filterEb.SetPoint then
        filterEb:SetPoint("TOPLEFT", filterBg, "TOPLEFT", 8, -6)
        filterEb:SetPoint("BOTTOMRIGHT", filterBg, "BOTTOMRIGHT", -8, 4)
    end
    filterEb:SetMaxLetters(48)

    local listHost = CreateFrame("Frame", nil, root)
    listHost:SetPoint("TOPLEFT", filterBg, "BOTTOMLEFT", 0, -itemPad)
    listHost:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -4, 4)

    local scrollFrame = Factory:CreateScrollFrame(listHost, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", listHost, "BOTTOMRIGHT", -scrollBarW, 0)
    scrollFrame:EnableMouseWheel(true)
    local scrollBarColumn = Factory:CreateScrollBarColumn(listHost, scrollBarW, 0, 0)
    if scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)

    local selected = {}
    local pendingAdd = {}
    local pendingRemove = {}
    local bin = ns.UI_RecycleBin

    local function rosterPickMapOn(map, key)
        if not map or not key then return false end
        return map[key] and true or false
    end

    local function syncRosterCheckboxVisual(toggle, on)
        if not toggle then return end
        local v = on and true or false
        if toggle.SetChecked then toggle:SetChecked(v) end
        if toggle.innerDot then toggle.innerDot:SetShown(v) end
    end

    local function effWidth()
        local w = root:GetWidth()
        if not w or w < 80 then
            w = width or 400
        end
        return w
    end

    local function collectEligible()
        local list = {}
        for i = 1, #charactersList do
            local ch = charactersList[i]
            local ck = ns.UI_GetCharKey(ch)
            if ck and (ch.isTracked ~= false) and not ns.CharacterService:IsFavoriteCharacter(addon, ck) then
                list[#list + 1] = { char = ch, key = ck }
            end
        end
        table.sort(list, function(a, b)
            return WnSafeCharLine(a.char) < WnSafeCharLine(b.char)
        end)
        return list
    end

    local function recycleScrollChildren()
        local ch = { scrollChild:GetChildren() }
        for i = 1, #ch do
            ch[i]:Hide()
            if bin then ch[i]:SetParent(bin) else ch[i]:SetParent(nil) end
        end
    end

    local function rebuild()
        recycleScrollChildren()
        local filterRaw = filterEb:GetText()
        if type(filterRaw) ~= "string" then filterRaw = "" end
        if issecretvalue and issecretvalue(filterRaw) then filterRaw = "" end
        local filterLower = WnPickerTextLower(filterRaw:match("^%s*(.-)%s*$") or "")

        local bw = effWidth() - 16 - scrollBarW
        if bw < 120 then bw = 120 end
        scrollChild:SetWidth(bw)
        local y = 0
        local LVL_COL_W = 44
        local COL_GAP = 8

        local function layoutRosterColumns(leftPad, rightReserve)
            local contentRight = bw - rightReserve
            local avail = contentRight - leftPad
            local realmW = math.floor(avail * 0.38)
            if realmW < 100 then realmW = 100 end
            local cap = math.min(230, math.floor(bw * 0.44))
            if realmW > cap then realmW = cap end
            local nameW = avail - LVL_COL_W - COL_GAP * 2 - realmW
            if nameW < 88 then
                nameW = 88
                realmW = math.max(72, avail - LVL_COL_W - COL_GAP * 2 - nameW)
            end
            local nameLeft = leftPad
            local lvX = nameLeft + nameW + COL_GAP
            local realmX = lvX + LVL_COL_W + COL_GAP
            return nameLeft, nameW, lvX, realmX, realmW, contentRight
        end

        local function paintRosterRowColumns(row, char, leftPad, rightReserve)
            local nameL, nameW, lvX, realmX, _, contentRight = layoutRosterColumns(leftPad, rightReserve)
            local nm = row:CreateFontString(nil, "OVERLAY")
            if FontManager.ApplyFont then FontManager:ApplyFont(nm, "body") else nm:SetFontObject("GameFontNormal") end
            nm:SetPoint("LEFT", row, "LEFT", nameL, 0)
            nm:SetWidth(nameW)
            nm:SetJustifyH("LEFT")
            if nm.SetMaxLines then nm:SetMaxLines(1) end
            if nm.SetWordWrap then nm:SetWordWrap(false) end
            nm:SetText(WnColoredCharacterName(char))

            local lv = row:CreateFontString(nil, "OVERLAY")
            if FontManager.ApplyFont then FontManager:ApplyFont(lv, "body") else lv:SetFontObject("GameFontNormal") end
            lv:SetPoint("LEFT", row, "LEFT", lvX, 0)
            lv:SetWidth(LVL_COL_W)
            lv:SetJustifyH("CENTER")
            lv:SetText("|cffffffff" .. WnRosterLevelStr(char) .. "|r")

            local rf = row:CreateFontString(nil, "OVERLAY")
            if FontManager.ApplyFont then FontManager:ApplyFont(rf, "body") else rf:SetFontObject("GameFontNormal") end
            rf:SetPoint("LEFT", row, "LEFT", realmX, 0)
            rf:SetWidth(math.max(48, contentRight - realmX))
            rf:SetJustifyH("LEFT")
            if rf.SetMaxLines then rf:SetMaxLines(1) end
            if rf.SetWordWrap then rf:SetWordWrap(false) end
            rf:SetText(WnRosterRealmColored(char))
        end

        local function addPlaceholderLine(text, extraH, textLeftPad)
            local h = ROW + (extraH or 0)
            local wrap = CreateFrame("Frame", nil, scrollChild)
            wrap:SetSize(bw, h)
            wrap:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            local padL = (type(textLeftPad) == "number" and textLeftPad >= 0) and textLeftPad or 10
            local fs = FontManager:CreateFontString(wrap, "body", "OVERLAY")
            fs:SetPoint("LEFT", padL, 0)
            fs:SetPoint("RIGHT", wrap, "RIGHT", -10, 0)
            fs:SetJustifyH("LEFT")
            fs:SetTextColor(0.45, 0.45, 0.48)
            fs:SetText(text)
            y = y + h + 4
        end

        local function addColumnHeaderRow(leftPad, rightReserve)
            local nameL, nameW, lvX, realmX, _, contentRight = layoutRosterColumns(leftPad, rightReserve)
            local hdrH = 20
            local hf = CreateFrame("Frame", nil, scrollChild)
            hf:SetSize(bw, hdrH)
            hf:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            local c1 = FontManager:CreateFontString(hf, "small", "OVERLAY")
            c1:SetPoint("LEFT", hf, "LEFT", nameL, 0)
            c1:SetWidth(nameW)
            c1:SetJustifyH("LEFT")
            c1:SetTextColor(0.52, 0.55, 0.6)
            c1:SetText((L and L["CUSTOM_HEADER_COL_CHARACTER"]) or "Character")
            local c2 = FontManager:CreateFontString(hf, "small", "OVERLAY")
            c2:SetPoint("LEFT", hf, "LEFT", lvX, 0)
            c2:SetWidth(LVL_COL_W)
            c2:SetJustifyH("CENTER")
            c2:SetTextColor(1, 1, 1)
            c2:SetText((L and L["CUSTOM_HEADER_COL_LEVEL"]) or "Level")
            local c3 = FontManager:CreateFontString(hf, "small", "OVERLAY")
            c3:SetPoint("LEFT", hf, "LEFT", realmX, 0)
            c3:SetWidth(math.max(48, contentRight - realmX))
            c3:SetJustifyH("LEFT")
            c3:SetTextColor(1, 1, 1)
            c3:SetText((L and L["CUSTOM_HEADER_COL_REALM"]) or "Realm")
            y = y + hdrH + 4
        end

        local function addSectionTitle(txt)
            local bar = CreateFrame("Frame", nil, scrollChild)
            bar:SetSize(bw, SECTION_BAR_H)
            bar:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
            if ns.UI_ApplyVisuals then
                ns.UI_ApplyVisuals(bar, { 0.10, 0.10, 0.12, 0.82 }, { 0, 0, 0, 0 })
            end
            local fs = FontManager:CreateFontString(bar, "tabSubtitle", "OVERLAY")
            fs:SetPoint("LEFT", 10, 0)
            fs:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(txt)
            fs:SetTextColor(0.72, 0.76, 0.84)
            y = y + SECTION_BAR_H + SECTION_AFTER
        end

        if not groupId then
            local all = collectEligible()
            addColumnHeaderRow(ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
            local shown = 0
            for i = 1, #all do
                local entry = all[i]
                if WnPickerLineMatchesChar(entry.char, filterLower) then
                    shown = shown + 1
                    local ck = entry.key
                    local row = Factory:CreateButton(scrollChild, bw, ROW, true)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(row, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 }) end
                    if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
                    local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, rosterPickMapOn(selected, ck))
                    if cb then
                        cb:SetPoint("LEFT", 8, 0)
                        syncRosterCheckboxVisual(cb, rosterPickMapOn(selected, ck))
                        cb:SetScript("OnClick", function(self)
                            local v = self:GetChecked() and true or false
                            syncRosterCheckboxVisual(self, v)
                            selected[ck] = v and true or nil
                        end)
                    end
                    paintRosterRowColumns(row, entry.char, ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
                    row:SetScript("OnClick", function()
                        if not cb then return end
                        local v = not (cb:GetChecked() and true or false)
                        syncRosterCheckboxVisual(cb, v)
                        selected[ck] = v and true or nil
                    end)
                    y = y + ROW
                end
            end
            if shown == 0 then
                addPlaceholderLine((L and L["CUSTOM_HEADER_PICKER_EMPTY"]) or "No matching characters.", 0, ROSTER_CONTENT_LEFT)
            end
        else
            local members, candidates = WnBuildCustomHeaderManageBuckets(addon, profile, charactersList, groupId)
            addSectionTitle((L and L["CUSTOM_HEADER_MENU_IN_HEADER"]) or "In this section")
            addColumnHeaderRow(ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
            local memShown = 0
            for i = 1, #members do
                local entry = members[i]
                if WnPickerLineMatchesChar(entry.char, filterLower) then
                    memShown = memShown + 1
                    local row = Factory:CreateButton(scrollChild, bw, ROW, true)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(row, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 }) end
                    if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
                    local ck = entry.key
                    local memChecked = not rosterPickMapOn(pendingRemove, ck)
                    local rmCb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, memChecked)
                    if rmCb then
                        rmCb:SetPoint("LEFT", 8, 0)
                        syncRosterCheckboxVisual(rmCb, memChecked)
                        rmCb:SetScript("OnClick", function(self)
                            local v = self:GetChecked() and true or false
                            syncRosterCheckboxVisual(self, v)
                            if v then
                                pendingRemove[ck] = nil
                            else
                                pendingRemove[ck] = true
                            end
                        end)
                    end
                    paintRosterRowColumns(row, entry.char, ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
                    row:SetScript("OnClick", function()
                        if not rmCb then return end
                        local v = not (rmCb:GetChecked() and true or false)
                        syncRosterCheckboxVisual(rmCb, v)
                        if v then
                            pendingRemove[ck] = nil
                        else
                            pendingRemove[ck] = true
                        end
                    end)
                    y = y + ROW
                end
            end
            if memShown == 0 then
                addPlaceholderLine((L and L["CUSTOM_HEADER_MENU_NO_MEMBERS"]) or "No characters yet.", 2, ROSTER_CONTENT_LEFT)
            end
            y = y + 4
            addSectionTitle((L and L["CUSTOM_HEADER_MENU_ADD_TO_HEADER"]) or "Add characters")
            addColumnHeaderRow(ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
            local candShown = 0
            for i = 1, #candidates do
                local entry = candidates[i]
                if WnPickerLineMatchesChar(entry.char, filterLower) then
                    candShown = candShown + 1
                    local ck = entry.key
                    local row = Factory:CreateButton(scrollChild, bw, ROW, true)
                    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -y)
                    if ns.UI_ApplyVisuals then ns.UI_ApplyVisuals(row, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 }) end
                    if Factory.ApplyHighlight then Factory:ApplyHighlight(row) end
                    local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, rosterPickMapOn(pendingAdd, ck))
                    if cb then
                        cb:SetPoint("LEFT", 8, 0)
                        syncRosterCheckboxVisual(cb, rosterPickMapOn(pendingAdd, ck))
                        cb:SetScript("OnClick", function(self)
                            local v = self:GetChecked() and true or false
                            syncRosterCheckboxVisual(self, v)
                            pendingAdd[ck] = v and true or nil
                        end)
                    end
                    paintRosterRowColumns(row, entry.char, ROSTER_CONTENT_LEFT, ROSTER_ROW_RIGHT_PAD)
                    row:SetScript("OnClick", function()
                        if not cb then return end
                        local v = not (cb:GetChecked() and true or false)
                        syncRosterCheckboxVisual(cb, v)
                        pendingAdd[ck] = v and true or nil
                    end)
                    y = y + ROW
                end
            end
            if candShown == 0 then
                addPlaceholderLine((L and L["CUSTOM_HEADER_MENU_NO_CANDIDATES"]) or "No eligible characters (favorites stay in Favorites).", 0, ROSTER_CONTENT_LEFT)
            end
        end

        scrollChild:SetHeight(math.max(y, 1))
        scrollFrame:SetVerticalScroll(0)
        if Factory.UpdateScrollBarVisibility then Factory:UpdateScrollBarVisibility(scrollFrame) end
    end

    filterEb:SetScript("OnTextChanged", function()
        rebuild()
    end)
    root:SetScript("OnSizeChanged", function()
        rebuild()
    end)
    rebuild()

    return {
        frame = root,
        filterEdit = filterEb,
        Rebuild = rebuild,
        GetSelectedKeys = function()
            local keys = {}
            if groupId then return keys end
            for ck, on in pairs(selected) do
                if on then keys[#keys + 1] = ck end
            end
            return keys
        end,
        ApplyPendingAdds = function()
            if not groupId then return 0 end
            local n = 0
            local function rosterAssignKey(ck)
                if not ck then return ck end
                if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
                    return ns.Utilities:GetCanonicalCharacterKey(ck) or ck
                end
                return ck
            end
            for ck, on in pairs(pendingRemove) do
                if on then
                    local k = rosterAssignKey(ck)
                    if ns.CharacterService:SetCharacterCustomSection(addon, k, nil) then
                        n = n + 1
                    end
                end
            end
            wipe(pendingRemove)
            for ck, on in pairs(pendingAdd) do
                if on then
                    local k = rosterAssignKey(ck)
                    if ns.CharacterService:SetCharacterCustomSection(addon, k, groupId) then
                        n = n + 1
                    end
                end
            end
            wipe(pendingAdd)
            if n > 0 and addon.SendMessage then
                addon:SendMessage(E.CHARACTER_UPDATED, { charKey = nil, dataType = "customSection" })
            end
            rebuild()
            return n
        end,
        ClearSelection = function()
            wipe(selected)
            if groupId then
                wipe(pendingAdd)
                wipe(pendingRemove)
            end
            rebuild()
        end,
    }
end

--- [+] on header row: open same modal window as new section (addon:OpenCustomHeaderRosterWindow).
function ns.UI_ShowCustomHeaderMembersMenu(anchorFrame, groupId, profile, charactersList)
    if not groupId then return end
    local addon = _G.WarbandNexus or ns.WarbandNexus
    if not addon or not addon.OpenCustomHeaderRosterWindow then return end
    local function open()
        addon:OpenCustomHeaderRosterWindow(groupId)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, open)
    else
        open()
    end
end

--============================================================================
-- CUSTOM HEADER DECORATOR (Characters / Professions / PvE single source)
-- Defined in Characters tab (profile.characterCustomGroups), consumed identically
-- in related tabs. Layout: [chevron] [icon] [gold-star] [title] ... [add-btn] [count]
--============================================================================

-- Migrate legacy per-tab field names so a header decorated by an older code path
-- (e.g. ProfessionsUI's `_wnProfSectionGoldStar`/`_wnProfSectionCount`) reuses the
-- same widgets, preventing duplicate stars/counts when re-decorated by the helper.
local function MigrateLegacyCustomHeaderFields(headerFrame)
    if not headerFrame then return end
    if headerFrame._wnProfSectionGoldStar and not headerFrame._wnCustomHeaderGoldStarBtn then
        headerFrame._wnCustomHeaderGoldStarBtn = headerFrame._wnProfSectionGoldStar
        headerFrame._wnProfSectionGoldStar = nil
    end
    if headerFrame._wnProfSectionCount and not headerFrame._wnCustomHeaderCount then
        headerFrame._wnCustomHeaderCount = headerFrame._wnProfSectionCount
        headerFrame._wnProfSectionCount = nil
    end
end

--- Decorate a CreateCollapsibleHeader frame with the unified Custom Header chrome.
--- Idempotent: re-attaches existing widgets on subsequent calls (safe across redraws).
---
--- opts (table):
---   groupId          : string  custom header id (required)
---   memberCount      : number  count badge value (defaults to 0)
---   addon            : table   WarbandNexus addon ref
---   profile          : table   addon.db.profile
---   expandIcon       : Texture chevron from CreateCollapsibleHeader (return #2)
---   iconFrame        : Texture section atlas icon from CreateCollapsibleHeader (return #3)
---   headerText       : FontString title from CreateCollapsibleHeader (return #4)
---   includeAddButton : boolean show the [+] roster manage button (Character tab only)
---   addButtonRoster  : table   character list passed to picker (when includeAddButton)
---   refreshTab       : string  optional tab payload for WN_UI_MAIN_REFRESH_REQUESTED on toggle
---   addBtnSize       : number  optional override for + button size (default 16)
---   allowSectionHighlightToggle : boolean (default true). When false, no gold-star control (PvE/Professions: highlight only on Character tab).
function ns.UI_DecorateCustomHeader(headerFrame, opts)
    if not headerFrame or type(opts) ~= "table" then return end
    local groupId = opts.groupId
    if not groupId or groupId == "" then return end

    MigrateLegacyCustomHeaderFields(headerFrame)

    local addon = opts.addon or _G.WarbandNexus or ns.WarbandNexus
    local profile = opts.profile or (addon and addon.db and addon.db.profile)
    if not profile then return end

    local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(n or 0) end
    local CharacterService = ns.CharacterService

    local headerHeight = headerFrame.GetHeight and headerFrame:GetHeight() or 0
    if headerHeight <= 0 then headerHeight = 36 end
    local addBtnSize = tonumber(opts.addBtnSize) or 16
    local starSize = math.max(16, math.min(22, headerHeight - 10))

    -- Count badge (right edge baseline; siblings re-anchor relative to this).
    local countFs = headerFrame._wnCustomHeaderCount
    if not countFs then
        countFs = FontManager:CreateFontString(headerFrame, "header", "OVERLAY")
        headerFrame._wnCustomHeaderCount = countFs
    end
    countFs:SetJustifyH("RIGHT")
    countFs:SetText("|cffaaaaaa" .. FormatNumber(opts.memberCount or 0) .. "|r")
    countFs:Show()

    -- [+] manage roster button (left of count). Character tab only.
    local addBtn = headerFrame._wnCustomHeaderAddBtn
    if opts.includeAddButton then
        if not addBtn and ns.UI and ns.UI.Factory and ns.UI.Factory.CreateButton then
            addBtn = ns.UI.Factory:CreateButton(headerFrame, addBtnSize, addBtnSize, true)
            headerFrame._wnCustomHeaderAddBtn = addBtn
            addBtn:SetFrameLevel((headerFrame:GetFrameLevel() or 2) + 3)
            local okA = false
            if addBtn.SetNormalAtlas then
                okA = pcall(function()
                    addBtn:SetNormalAtlas("communities-icon-addgroupplus")
                end)
            end
            if not okA then
                local gt = addBtn.GetNormalTexture and addBtn:GetNormalTexture()
                if gt then
                    gt:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
                    gt:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
        end
        if addBtn then
            addBtn:SetSize(addBtnSize, addBtnSize)
            local rosterChars = opts.addButtonRoster
            if (not rosterChars) and addon and addon.GetAllCharacters then
                rosterChars = addon:GetAllCharacters() or {}
            end
            local profileRef = profile
            local localGid = groupId
            addBtn:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_LEFT")
                GameTooltip:SetText((ns.L and ns.L["CUSTOM_HEADER_ROW_ADD_TOOLTIP"]) or "Add characters", 1, 1, 1)
                GameTooltip:AddLine((ns.L and ns.L["CUSTOM_HEADER_ROW_ADD_TOOLTIP_BODY"]) or "Pick tracked characters (non-favorites) to place in this header. Remove them here or via the row note icon.", 0.85, 0.85, 0.9, true)
                GameTooltip:Show()
            end)
            addBtn:SetScript("OnLeave", GameTooltip_Hide)
            addBtn:SetScript("OnClick", function(b)
                if ns.UI_ShowCustomHeaderMembersMenu then
                    ns.UI_ShowCustomHeaderMembersMenu(b, localGid, profileRef, rosterChars)
                end
            end)
            addBtn:Show()
        end
    elseif addBtn then
        addBtn:Hide()
    end

    local allowSectionHighlightToggle = opts.allowSectionHighlightToggle ~= false

    -- Gold-star highlight toggle (left of title, after section icon). Character tab only when allowSectionHighlightToggle.
    local isHighlighted = CharacterService and CharacterService.IsProfileCustomSectionHighlighted
        and CharacterService:IsProfileCustomSectionHighlighted(profile, groupId)
    local goldStar = headerFrame._wnCustomHeaderGoldStarBtn
    if not allowSectionHighlightToggle then
        if goldStar then
            goldStar:Hide()
            goldStar:SetScript("OnClick", nil)
            goldStar:EnableMouse(false)
        end
    elseif not goldStar and ns.UI_CreateFavoriteButton then
        goldStar = ns.UI_CreateFavoriteButton(
            headerFrame,
            groupId,
            isHighlighted,
            starSize,
            "RIGHT",
            -48,
            0,
            function()
                local addonRef = opts.addon or _G.WarbandNexus or ns.WarbandNexus
                if not addonRef or not addonRef.db or not addonRef.db.profile then
                    return false
                end
                local now = CharacterService and CharacterService.ToggleFavoriteCustomHeaderHighlight
                    and CharacterService:ToggleFavoriteCustomHeaderHighlight(addonRef, groupId)
                if now == nil then
                    return false
                end
                if addonRef.SendMessage then
                    if opts.refreshTab and opts.refreshTab ~= "" then
                        addonRef:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = opts.refreshTab, skipCooldown = true })
                    else
                        addonRef:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
                    end
                end
                return now
            end
        )
        headerFrame._wnCustomHeaderGoldStarBtn = goldStar
        if goldStar and goldStar.SetFrameLevel then
            goldStar:SetFrameLevel((headerFrame:GetFrameLevel() or 2) + 4)
        end
    end
    if allowSectionHighlightToggle and goldStar then
        goldStar:EnableMouse(true)
        goldStar.charKey = groupId
        goldStar.isFavorite = isHighlighted and true or false
        if goldStar.icon and ns.UI_StyleFavoriteIcon then
            ns.UI_StyleFavoriteIcon(goldStar.icon, isHighlighted)
        end
        goldStar:SetSize(starSize, starSize)
        if goldStar.icon then
            local iconSz = starSize * 0.65
            goldStar.icon:SetSize(iconSz, iconSz)
        end
        goldStar:SetScript("OnEnter", function(b)
            GameTooltip:SetOwner(b, "ANCHOR_LEFT")
            GameTooltip:SetText((ns.L and ns.L["CUSTOM_HEADER_GOLD_STAR_TITLE"]) or "Gold section highlight", 1, 1, 1)
            GameTooltip:AddLine((ns.L and ns.L["CUSTOM_HEADER_GOLD_STAR_BODY"]) or "Click to give this section the same gold bar style as Favorites. You can highlight several sections. Click again to turn off for this section.", 0.85, 0.85, 0.9, true)
            GameTooltip:Show()
        end)
        goldStar:SetScript("OnLeave", GameTooltip_Hide)
        goldStar:Show()
    end

    -- ===== UNIFIED ANCHOR LAYOUT =====
    -- Right edge:    [add-btn?]  [count]   (count anchored to header right; add-btn left of count)
    -- Left of title: [chevron]   [icon]    [gold-star]   [title]
    local headerSide = (UI_SPACING and UI_SPACING.SIDE_MARGIN) or (UI_LAYOUT and UI_LAYOUT.SIDE_MARGIN) or 12
    countFs:ClearAllPoints()
    if addBtn and addBtn:IsShown() then
        countFs:SetPoint("RIGHT", headerFrame, "RIGHT", -headerSide, 0)
        addBtn:ClearAllPoints()
        addBtn:SetPoint("RIGHT", countFs, "LEFT", -6, 0)
    else
        countFs:SetPoint("RIGHT", headerFrame, "RIGHT", -headerSide, 0)
    end

    if allowSectionHighlightToggle and goldStar then
        goldStar:ClearAllPoints()
        local expandIcon = opts.expandIcon
        local iconFrame = opts.iconFrame
        local headerText = opts.headerText
        if expandIcon and iconFrame then
            iconFrame:ClearAllPoints()
            iconFrame:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
            goldStar:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
            if headerText then
                headerText:ClearAllPoints()
                headerText:SetPoint("LEFT", goldStar, "RIGHT", 12, 0)
                if countFs then
                    headerText:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
                end
                headerText:SetJustifyH("LEFT")
            end
        elseif expandIcon and headerText and countFs then
            -- Chevron + star + title + count (no section atlas icon — same left edge as Characters tab intent)
            goldStar:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
            headerText:ClearAllPoints()
            headerText:SetPoint("LEFT", goldStar, "RIGHT", 12, 0)
            headerText:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
            headerText:SetJustifyH("LEFT")
        elseif addBtn and addBtn:IsShown() then
            goldStar:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
        else
            goldStar:SetPoint("RIGHT", countFs, "LEFT", -6, 0)
        end
    elseif opts.headerText and countFs then
        local ht = opts.headerText
        -- Match CreateCollapsibleHeader: [chevron] +8 + [atlas icon] +12 + title (do not anchor title to chevron only).
        if opts.expandIcon and opts.iconFrame then
            opts.iconFrame:ClearAllPoints()
            opts.iconFrame:SetPoint("LEFT", opts.expandIcon, "RIGHT", 8, 0)
            ht:ClearAllPoints()
            ht:SetPoint("LEFT", opts.iconFrame, "RIGHT", 12, 0)
            ht:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
            ht:SetJustifyH("LEFT")
        elseif opts.expandIcon then
            ht:ClearAllPoints()
            ht:SetPoint("LEFT", opts.expandIcon, "RIGHT", 12, 0)
            ht:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
            ht:SetJustifyH("LEFT")
        else
            ht:SetPoint("RIGHT", countFs, "LEFT", -10, 0)
        end
    end
end

--- Back-compat alias (single roster picker).
function ns.UI_CreateCustomSectionCreatePicker(parent, width, _scrollH, addon, profile, charactersList)
    return ns.UI_CreateCustomHeaderRosterPicker(parent, width, addon, profile, charactersList, nil)
end

-- Title-card toolbar: same glues arrow atlases as Characters tab section toggle.
local TITLE_TOOLBAR_EC_ATLAS_UP = "glues-characterSelect-icon-arrowUp-small-hover"
local TITLE_TOOLBAR_EC_ATLAS_DOWN = "glues-characterSelect-icon-arrowDown-small-hover"

--- Characters-parity title toolbar toggle shell (themed square + `_wnEcIcon`). Persists `ownerFrame._wnExpandCollapseToggleBtn`.
--- Migrates legacy `ownerFrame._wnCharactersExpandCollapseToggleBtn` if present.
---@return Button|nil
function ns.UI_CreateOrAcquireTitleToolbarExpandCollapseToggle(ownerFrame, titleCard)
    if not ownerFrame or not titleCard or not ns.UI.Factory or not ns.UI.Factory.CreateButton then
        return nil
    end
    if ownerFrame._wnCharactersExpandCollapseToggleBtn and not ownerFrame._wnExpandCollapseToggleBtn then
        ownerFrame._wnExpandCollapseToggleBtn = ownerFrame._wnCharactersExpandCollapseToggleBtn
        ownerFrame._wnCharactersExpandCollapseToggleBtn = nil
    end
    local btnH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local COLORS = ns.UI_COLORS or { accent = { 0.6, 0.4, 1 } }
    local accent = COLORS.accent or { 0.6, 0.4, 1 }
    local btn = ownerFrame._wnExpandCollapseToggleBtn
    if not btn then
        btn = ns.UI.Factory:CreateButton(titleCard, btnH, btnH, false)
        ApplyVisuals(btn, { 0.12, 0.12, 0.15, 1 }, { accent[1], accent[2], accent[3], 0.6 })
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
        btn._wnEcIcon = btn:CreateTexture(nil, "OVERLAY")
        btn._wnEcIcon:SetAllPoints(btn)
        if btn.RegisterForClicks then
            btn:RegisterForClicks("LeftButtonUp")
        end
        ownerFrame._wnExpandCollapseToggleBtn = btn
    end
    btn:SetParent(titleCard)
    btn:SetFrameLevel((titleCard:GetFrameLevel() or 0) + 5)
    btn:SetSize(btnH, btnH)
    btn:Show()
    return btn
end

--- `getIsCollapseMode()` → true when the next click should collapse (up arrow).
function ns.UI_ApplyTitleToolbarExpandCollapseToggleAtlas(btn, getIsCollapseMode)
    if not btn or not btn._wnEcIcon then return end
    local cm = getIsCollapseMode and getIsCollapseMode() == true
    btn._wnEcIcon:SetAtlas(cm and TITLE_TOOLBAR_EC_ATLAS_UP or TITLE_TOOLBAR_EC_ATLAS_DOWN, false)
end

--- Single expand/collapse-all toggle on tab title cards (Characters-style button via `CreateOrAcquire` + atlas helper).
--- Legacy `_wnExpandCollapseCollapseBtn` / `_wnExpandCollapseExpandBtn` are hidden if present.
--- @param opts table `{ collapseTooltip, expandTooltip, onCollapseClick, onExpandClick, getIsCollapseMode }`
---        `getIsCollapseMode()` → true when the tree is “fully expanded” (next click should collapse).
function ns.UI_EnsureTitleCardExpandCollapseButtons(ownerFrame, titleCard, anchorFrame, anchorPoint, anchorOffsetX, anchorOffsetY, opts)
    if not ownerFrame or not titleCard or not anchorFrame or not opts then return end

    local legCol = ownerFrame._wnExpandCollapseCollapseBtn
    local legExp = ownerFrame._wnExpandCollapseExpandBtn
    if legCol then legCol:Hide() end
    if legExp then legExp:Hide() end

    local toggle = ns.UI_CreateOrAcquireTitleToolbarExpandCollapseToggle(ownerFrame, titleCard)
    if not toggle then return end
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(toggle, titleCard, anchorFrame, anchorPoint, anchorOffsetX)
        if anchorOffsetY and anchorOffsetY ~= 0 then
            local p, rel, rp, x, y = toggle:GetPoint(1)
            if p then toggle:SetPoint(p, rel, rp, x, (y or 0) + anchorOffsetY) end
        end
    else
        toggle:ClearAllPoints()
        toggle:SetPoint("RIGHT", anchorFrame, anchorPoint, anchorOffsetX or 0, anchorOffsetY or 0)
    end

    local function collapseModeNow()
        if opts.getIsCollapseMode then
            return opts.getIsCollapseMode() == true
        end
        return false
    end

    local function applyAtlas()
        ns.UI_ApplyTitleToolbarExpandCollapseToggleAtlas(toggle, function()
            return collapseModeNow()
        end)
    end
    applyAtlas()

    local collapseTip = opts.collapseTooltip or ""
    local expandTip = opts.expandTooltip or ""

    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText(collapseModeNow() and collapseTip or expandTip, 1, 1, 1)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)

    toggle:SetScript("OnClick", function()
        if collapseModeNow() then
            if opts.onCollapseClick then opts.onCollapseClick() end
        else
            if opts.onExpandClick then opts.onExpandClick() end
        end
        applyAtlas()
    end)
end

-- Exports
ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowTotalWidth = GetCharRowTotalWidth
ns.UI_GetCharRowTotalWidthForGuild = GetCharRowTotalWidthForGuild
ns.UI_GetCharRowRightRailWidth = GetCharRowRightRailWidth
ns.UI_ComputeCharRowGuildColumnWidth = ComputeCharRowGuildColumnWidth
ns.UI_CHAR_ROW_RIGHT_MARGIN = CHAR_ROW_RIGHT_MARGIN
ns.UI_CHAR_ROW_RIGHT_GAP = CHAR_ROW_RIGHT_GAP
ns.UI_ResolveCharactersTabRowWidth = ResolveCharactersTabRowWidth
ns.UI_ComputeCharactersMinScrollWidth = ComputeCharactersMinScrollWidth
ns.UI_ComputeCharactersTitleToolbarReserve = ComputeCharactersTitleToolbarReserve
-- UI_GetTitleCardToolbarMetrics / UI_ComputeTitleToolbarReserve exported above
ns.UI_CreateCharRowColumnDivider = CreateCharRowColumnDivider
ns.UI_CreateCharacterSortDropdown = CreateCharacterSortDropdown
ns.UI_CreateCharacterTabAdvancedFilterButton = CreateCharacterTabAdvancedFilterButton

--============================================================================
-- DRAW EMPTY STATE (Shared by Items and Storage tabs)
--============================================================================

local function DrawEmptyState(addon, parent, startY, isSearch, searchText, tabContext)
    -- Validate parent frame
    if not parent or not parent.CreateTexture then
        return startY or 0
    end
    
    local topGap = (ns.UI_ItemsResultsTopGap and ns.UI_ItemsResultsTopGap(startY)) or ((startY or 0) + 50)
    local yOffset = topGap
    tabContext = tabContext or ""
    
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
        container.title = FontManager:CreateFontString(container, UIFontRole("emptyStateTitle"), "OVERLAY")
        
        -- Create description
        container.desc = FontManager:CreateFontString(container, UIFontRole("emptyStateBody"), "OVERLAY")
        container.desc:SetTextColor(1, 1, 1)
    end
    
    local L = ns.L
    local defaultIcon = "Interface\\Icons\\INV_Misc_Bag_10_Blue"
    local iconTex = defaultIcon
    local titleText
    local emptyMessage
    
    if isSearch then
        iconTex = "Interface\\Icons\\INV_Misc_Spyglass_02"
        titleText = "|cff666666" .. ((L and L["NO_RESULTS"]) or "No results") .. "|r"
        local displayText = searchText or ""
        if displayText and displayText ~= "" then
            emptyMessage = string.format((L and L["NO_ITEMS_MATCH"]) or "No items match '%s'", displayText)
        else
            emptyMessage = (L and L["NO_ITEMS_MATCH_GENERIC"]) or "No items match your search"
        end
    elseif tabContext == "plans_achievement" then
        iconTex = "Interface\\Icons\\Achievement_General"
        titleText = "|cff666666" .. ((L and L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"]) or "No achievements to display") .. "|r"
        emptyMessage = (L and L["PLANS_ACHIEVEMENTS_EMPTY_HINT"]) or "Add achievements to your To-Do from this list, or change Show Planned / Show Completed. Achievements scan in the background; try /reload if the list stays empty."
    else
        iconTex = defaultIcon
        titleText = "|cff666666" .. ((L and L["NO_ITEMS_CACHED_TITLE"]) or "No items cached") .. "|r"
        local currentSubTab = ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() or "personal"
        if currentSubTab == "warband" then
            emptyMessage = (L and L["ITEMS_WARBAND_BANK_HINT"]) or "Open Warband Bank to scan items (auto-scanned on first visit)"
        else
            emptyMessage = (L and L["ITEMS_SCAN_HINT"]) or "Items are scanned automatically. Try /reload if nothing appears."
        end
    end
    
    -- Update icon position and texture
    container.icon:ClearAllPoints()
    container.icon:SetPoint("TOP", 0, -yOffset)
    container.icon:SetTexture(iconTex)
    yOffset = yOffset + 60
    
    -- Update title position and text
    container.title:ClearAllPoints()
    container.title:SetPoint("TOP", 0, -yOffset)
    container.title:SetText(titleText)
    yOffset = yOffset + 30
    
    -- Update description position and text
    container.desc:ClearAllPoints()
    container.desc:SetPoint("TOP", 0, -yOffset)
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
    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
    container:SetSize(width, searchH)
    
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
    local placeholderText = FontManager:CreateFontString(searchBox, UIFontRole("searchPlaceholder"), "ARTWORK")
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
        if issecretvalue and issecretvalue(text) then
            placeholderText:Show()
            newSearchText = ""
        elseif type(text) == "string" and text ~= "" then
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
    SEARCH_BOX_HEIGHT = 32,
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
    
    local btnText = FontManager:CreateFontString(btn, UIFontRole("searchButtonText"), "OVERLAY")
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

--- Border uses **current** COLORS.accent (not load-time snapshot — avoids default purple theme leaking).
local function ApplyToggleVisuals(frame)
    frame:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    local ac = COLORS and COLORS.accent or { 0.5, 0.5, 0.5 }
    local borderCol = { ac[1], ac[2], ac[3], 0.8 }
    ApplyVisuals(frame, TOGGLE_BG, borderCol)
    -- ApplyVisuals heuristic can classify dark accents as "border"; toggles must always track accent refresh.
    frame._borderType = "accent"
    frame._borderAlpha = borderCol[4] or 0.8

    local dot = frame:CreateTexture(nil, "OVERLAY")
    dot:SetDrawLayer("OVERLAY", 7)
    dot:SetSize(TOGGLE_DOT_SIZE, TOGGLE_DOT_SIZE)
    -- TOPLEFT inset avoids subpixel CENTER rounding (right-column toggles looked shifted vs border).
    local inset = math.floor((TOGGLE_SIZE - TOGGLE_DOT_SIZE) / 2 + 0.5)
    dot:SetPoint("TOPLEFT", frame, "TOPLEFT", inset, -inset)
    dot:SetColorTexture(unpack(TOGGLE_DOT_COLOR))

    frame.innerDot = dot
    frame.checkTexture = dot  -- alias so .checkTexture API keeps working

    frame.defaultBorderColor = { borderCol[1], borderCol[2], borderCol[3], borderCol[4] }
    frame.hoverBorderColor = {
        math.min(1, ac[1] * 1.15),
        math.min(1, ac[2] * 1.15),
        math.min(1, ac[3] * 1.15),
        1,
    }

    return dot
end

local function ThemedToggleBorderHover(frame, hover)
    if not frame or not UpdateBorderColor then return end
    local ac = COLORS and COLORS.accent or { 0.5, 0.5, 0.5 }
    if hover then
        UpdateBorderColor(frame, {
            math.min(1, ac[1] * 1.15),
            math.min(1, ac[2] * 1.15),
            math.min(1, ac[3] * 1.15),
            1,
        })
    else
        UpdateBorderColor(frame, { ac[1], ac[2], ac[3], 0.8 })
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
        for ci = 1, #columns do
            local col = columns[ci]
            row.columns[ci] = {
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
-- VERTICAL SECTION CHAIN (parent-relative X + BOTTOM→TOP stack; Storage / VLM parity)
--============================================================================

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

--============================================================================
-- GAME TOOLTIP + CLASS COLOR HELPERS (Collections Recent, etc.)
--============================================================================

local strupper = string.upper

--- GameTooltip owner: horizontal flip so narrow columns (e.g. Collections Recent) open toward screen center.
--- Does not call `GameTooltip_SetDefaultAnchor` (that path grows from owner top-right and often covers the next column).
--- Call with `GameTooltip:ClearLines()` already done if you replace prior contents.
---@param frame Frame
---@param xOffset number|nil
---@param yOffset number|nil
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
---@param charData table
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

--- `|cffrrggbb` prefix for `displayName` using `db.global.characters` (case-insensitive name; `classFile`, `classID`, or localized `class`).
---@param displayName string
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
                    local c
                    if C_ClassColor and C_ClassColor.GetClassColor then
                        local okCol, col = pcall(C_ClassColor.GetClassColor, token)
                        if okCol then c = col end
                    end
                    if c then
                        return format("|cff%02x%02x%02x", (c.r or 0) * 255, (c.g or 0) * 255, (c.b or 0) * 255)
                    end
                    local rc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
                    if rc then
                        return format(
                            "|cff%02x%02x%02x",
                            math.floor((rc.r or 1) * 255),
                            math.floor((rc.g or 1) * 255),
                            math.floor((rc.b or 1) * 255)
                        )
                    end
                end
                break
            end
        end
    end
    return "|cffaaaaaa"
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_ApplyProfessionCraftingQualityAtlasToTexture = ApplyProfessionCraftingQualityAtlasToTexture
ns.UI_GetProfessionCraftingQualityAtlasNameForTier = GetProfessionCraftingQualityAtlasNameForTier
ns.UI_CreateCard = CreateCard
-- Money/number text formatting: Modules/UI/FormatHelpers.lua (loads before this file; ns.UI_Format*)
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_BuildCollapsibleSectionOpts = BuildCollapsibleSectionOpts
ns.UI_ChainSectionFrameBelow = ChainSectionFrameBelow
ns.UI_ForwardMouseWheelToScrollAncestor = ForwardMouseWheelToScrollAncestor
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_DrawSectionEmptyState = DrawSectionEmptyState
ns.UI_CreateSearchBox = CreateSearchBox
ns.UI_RefreshColors = RefreshColors
ns.UI_CalculateThemeColors = CalculateThemeColors

-- Frame pooling exports are owned by FramePoolFactory.lua (loads after SharedWidgets).
-- Keep a single authoritative export source to avoid load-order dependent overrides.

-- Shared widget exports
ns.UI_CreateThemedButton = CreateThemedButton
ns.UI_CreateThemedCheckbox = CreateThemedCheckbox
ns.UI_CreateThemedRadioButton = CreateThemedRadioButton
ns.UI_TOGGLE_SIZE = TOGGLE_SIZE

-- Table factory exports
ns.UI_CreateTableRow = CreateTableRow

-- Modal / external dialogs: authoritative shell in Modules/UI/WindowFactory.lua (`ns.UI_CreateExternalWindow`).

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
---@field popupOnLeftClick boolean|nil default true
---@field popupOnRightClick boolean|nil default true — To-Do list / tracker: set false so only left-click opens editor

---Creates a full-width (caller anchors) or fixed-size try-count button; mouse opens WNTryCount popup per options.
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
    local popupOnLeft = options.popupOnLeftClick ~= false
    local popupOnRight = options.popupOnRightClick ~= false

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
            local hint
            if popupOnLeft and popupOnRight then
                hint = (ns.L and ns.L["TRY_COUNT_CLICK_HINT"]) or "Click to edit attempt count."
            elseif popupOnLeft then
                hint = "Left-click to edit attempt count."
            elseif popupOnRight then
                hint = "Right-click to edit attempt count."
            else
                hint = (ns.L and ns.L["TRY_COUNT_CLICK_HINT"]) or "Click to edit attempt count."
            end
            GameTooltip:AddLine(hint, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    row:SetScript("OnClick", nil)
    row:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" and not popupOnLeft then return end
        if btn == "RightButton" and not popupOnRight then return end
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

--- Blizzard achievement objective tracking: symmetric star (PetJournal-FavoritesIcon) + vertex tint by state.
--- Caller anchors the button from the right. Optional `opts.isDisabled` boolean or `function(): boolean` (e.g. plan complete).
---@return Button|nil
function ns.UI.Factory:CreateAchievementTrackPinButton(parent, achievementID, opts)
    opts = type(opts) == "table" and opts or {}
    if not parent or not achievementID or not WarbandNexus then return nil end
    local sz = tonumber(opts.size) or 28
    local btn = self:CreateButton(parent, sz, sz, true)
    if parent.GetFrameLevel then
        btn:SetFrameLevel((parent:GetFrameLevel() or 0) + (tonumber(opts.frameLevelOffset) or 25))
    end
    btn:RegisterForClicks("LeftButtonUp")
    local tex = btn:CreateTexture(nil, "OVERLAY")
    btn._wnTrackPinTex = tex
    local PCM = ns.UI_PLANS_CARD_METRICS
    local pad = (PCM and PCM.plansActionIconInset) or 3
    local iconSz = math.max(12, sz - pad * 2)
    tex:SetSize(iconSz, iconSz)
    tex:SetPoint("CENTER", btn, "CENTER", 0, 0)

    local function pinDisabled()
        if type(opts.isDisabled) == "function" then
            local ok, v = pcall(opts.isDisabled)
            return ok and v == true
        end
        return opts.isDisabled == true
    end

    local function applyVisual(tracked, disabled)
        tex:SetTexCoord(0, 1, 0, 1)
        local usedWnPin = ns.UI_ApplyWnActionIcon
            and ns.UI_ApplyWnActionIcon(tex, "track", tracked, disabled)
        if not usedWnPin then
            if not (tex.SetAtlas and pcall(tex.SetAtlas, tex, "PetJournal-FavoritesIcon", true)) then
                tex:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
                tex:SetTexCoord(0.12, 0.88, 0.12, 0.88)
            end
            tex:SetDesaturated(disabled)
            local vc = ns.UI_WnIconVertexForState(tracked and not disabled, disabled)
            tex:SetVertexColor(vc[1], vc[2], vc[3], vc[4] or 1)
        end
    end

    function btn:WnRefreshAchievementTrackPin()
        local disabled = pinDisabled()
        local tracked = (WarbandNexus.IsAchievementTracked and WarbandNexus:IsAchievementTracked(achievementID)) == true
        applyVisual(tracked, disabled)
        -- NOTE: (not disabled) and WarbandNexus.ToggleAchievementTracking is a function, never == true — must test type.
        local canToggle = (not disabled) and type(WarbandNexus.ToggleAchievementTracking) == "function"
        btn:EnableMouse(canToggle)
        if canToggle then
            btn:SetScript("OnClick", function()
                WarbandNexus:ToggleAchievementTracking(achievementID)
                btn:WnRefreshAchievementTrackPin()
            end)
        else
            btn:SetScript("OnClick", nil)
        end
    end

    btn:SetScript("OnEnter", function(b)
        if pinDisabled() then return end
        GameTooltip:SetOwner(b, "ANCHOR_TOP")
        GameTooltip:SetText((ns.L and ns.L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:WnRefreshAchievementTrackPin()
    return btn
end

-- Collections detail header: action slot (+ try row) + Wowhead (eye always flush right) — same geometry for Mounts / Pets / Toy Box.
ns.CollectionsDetailHeaderLayout = {
    WOWHEAD_SIZE = 18,
    ACTION_SLOT_W = 74,
    ACTION_SLOT_H = 28,
    TRY_GAP = 4,
    TRY_ROW_H = 18,
    WOWHEAD_GAP = 10,
    -- Plan cards / other tabs: Wowhead eye inset from card top (aligns with Collections detail feel)
    CARD_WOWHEAD_TOP_OFFSET = 10,
}

---Right column: [action slot][Wowhead] with optional try row aligned to the action slot only (not full column width).
---@param parent Frame
---@param opts { withTryRow: boolean|nil, actionSlotWidth: number|nil, actionSlotHeight: number|nil } withTryRow defaults true; actionSlot* override default action cell size (e.g. Achievement: Add + Track).
---@return { root: Frame, actionSlot: Frame, wowheadBtn: Button, tryCountRow: Frame|nil }
function ns.UI.Factory:CreateCollectionsDetailRightColumn(parent, opts)
    opts = opts or {}
    local withTryRow = opts.withTryRow ~= false
    local L = ns.CollectionsDetailHeaderLayout
    local actionSlotW = opts.actionSlotWidth or L.ACTION_SLOT_W
    local actionSlotH = opts.actionSlotHeight or L.ACTION_SLOT_H
    local w = L.WOWHEAD_SIZE + L.WOWHEAD_GAP + actionSlotW
    local h = actionSlotH
    if withTryRow then
        h = h + L.TRY_GAP + L.TRY_ROW_H
    end

    local root = CreateFrame("Frame", nil, parent)
    root:SetSize(w, h)

    local actionSlot = CreateFrame("Frame", nil, root)
    actionSlot:SetSize(actionSlotW, actionSlotH)
    actionSlot:SetPoint("TOPRIGHT", root, "TOPRIGHT", -(L.WOWHEAD_SIZE + L.WOWHEAD_GAP), 0)

    local wowheadBtn = CreateFrame("Button", nil, root)
    wowheadBtn:SetSize(L.WOWHEAD_SIZE, L.WOWHEAD_SIZE)
    local vOff = math.max(0, (actionSlotH - L.WOWHEAD_SIZE) / 2)
    wowheadBtn:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -vOff)
    local whTex = wowheadBtn:CreateTexture(nil, "ARTWORK")
    whTex:SetAllPoints()
    ns.UI_SetWnIconTexture(whTex, "link", { vertexColor = ns.WN_ICON_VERTEX_WHITE })
    wowheadBtn._wnIconTex = whTex
    wowheadBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    wowheadBtn:SetFrameLevel((root:GetFrameLevel() or 0) + 8)
    local loc = ns.L
    wowheadBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine((loc and loc["WOWHEAD_LABEL"]) or "Wowhead", 1, 0.82, 0)
        GameTooltip:AddLine((loc and loc["CLICK_TO_COPY_LINK"]) or "Click to copy link", 0.6, 0.6, 0.6, true)
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
        headerTitle:SetTextColor(1, 1, 1)
        f.headerTitle = headerTitle

        local nameLabel = FontManager:CreateFontString(f, UIFontRole("tryPopupBody"), "OVERLAY")
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
        local saveBtnText = FontManager:CreateFontString(saveBtn, UIFontRole("dialogButtonLabel"), "OVERLAY")
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
        local cancelBtnText = FontManager:CreateFontString(cancelBtn, UIFontRole("dialogButtonLabel"), "OVERLAY")
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
        titleText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
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
    labelFont = labelFont or FontManager:GetFontRole("cardHeaderLabel")
    valueFont = valueFont or FontManager:GetFontRole("cardHeaderValue")
    
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
    local text = FontManager:CreateFontString(container, UIFontRole("resetTimerText"), "OVERLAY")
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
    items_search = {
        atlas = "talents-search",
        titleKey = "NO_RESULTS",
        descKey = "NO_ITEMS_MATCH_GENERIC",
        titleFallback = "No results",
        descFallback = "No items match your search.",
    },
    storage = {
        atlas = "Quartermaster",
        titleKey = "EMPTY_STORAGE_TITLE",
        descKey = "EMPTY_STORAGE_DESC",
        titleFallback = "No Storage Data",
        descFallback = "Items are scanned when you open banks or bags.\nVisit a bank to start tracking your storage.",
    },
    plans = {
        atlas = "poi-workorders",
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
        atlas = "AzeriteReady",
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
    -- Weekly Vault Tracker filter: no character has claimable vault (cached + live check)
    pve_vault = {
        atlas = "Tormentors-Boss",
        titleKey = "PVE_VAULT_TRACKER_EMPTY_TITLE",
        descKey = "PVE_VAULT_TRACKER_EMPTY_DESC",
        titleFallback = "No vault rows yet",
        descFallback = "No tracked character has weekly vault progress saved yet.\nTurn off Weekly Vault Tracker to see full PvE progress.",
    },
    statistics = {
        atlas = "racing",
        titleKey = "EMPTY_STATISTICS_TITLE",
        descKey = "EMPTY_STATISTICS_DESC",
        titleFallback = "No Statistics Available",
        descFallback = "Statistics are gathered from your tracked characters.\nLog in to a character to start collecting data.",
    },
    collections = {
        atlas = "dragon-rostrum",
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
-- @param opts table|nil { fillParent = true } fills parent width (use inside resultsContainer); { sideInset = n }
-- @return Frame - The empty state frame (shown automatically)
-- @return number - Height delta below yOffset (callers use: return yOffset + secondReturn)
local function CreateEmptyStateCard(parent, tabName, yOffset, opts)
    yOffset = yOffset or 0
    opts = opts or {}
    local FontManager = ns.FontManager
    local fillParent = opts.fillParent == true
    local sideInset = opts.sideInset
    if sideInset == nil then
        sideInset = fillParent and 0 or UI_SPACING.SIDE_MARGIN
    end
    local layout = ns.UI_LAYOUT or {}
    local bottomPad = layout.SECTION_SPACING or UI_SPACING.SIDE_MARGIN or 8

    -- Walk up the parent chain to find the actual ScrollFrame viewport
    -- parent may be a resultsContainer nested inside the scrollChild, so parent:GetParent() alone is unreliable
    local function GetScrollViewportHeight(startFrame)
        local visibleHeight = 600  -- safe fallback
        local current = startFrame
        for i = 1, 5 do
            current = current and current:GetParent()
            if not current then break end
            if current.GetObjectType and current:GetObjectType() == "ScrollFrame" then
                local h = current:GetHeight()
                if h and h > 0 then visibleHeight = h end
                break
            end
        end
        return visibleHeight
    end

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

    local atlasForIcon = config.atlas
    if tabName == "reputation" and ns.UI_GetTabIcon then
        local dyn = ns.UI_GetTabIcon("reputation")
        if dyn and dyn ~= "" then
            atlasForIcon = dyn
        end
    end

    -- Reuse existing empty state card on parent
    -- PopulateContent moves scrollChild children to recycleBin each pass — reparent back every show.
    local cacheKey = "emptyStateCard_" .. tabName
    local card = parent[cacheKey]
    if card then
        local visibleHeight = GetScrollViewportHeight(parent)
        local heightTrim = yOffset + sideInset + bottomPad
        if not fillParent then
            heightTrim = heightTrim + sideInset
        end
        local cardHeight = math.max(visibleHeight - heightTrim, 200)
        card:SetParent(parent)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", sideInset, -yOffset)
        card:SetPoint("TOPRIGHT", -sideInset, -yOffset)
        card:SetHeight(cardHeight)
        if fillParent then
            card._wnExcludedFromStorageExtent = true
        end
        ApplyStandardCardElevatedChrome(card)
        card:Show()
        return card, cardHeight + bottomPad
    end

    local visibleHeight = GetScrollViewportHeight(parent)
    local heightTrim = yOffset + sideInset + bottomPad
    if not fillParent then
        heightTrim = heightTrim + sideInset
    end
    local cardHeight = math.max(visibleHeight - heightTrim, 200)

    -- Filled elevated card matching tab title chrome (section atlas underlay)
    card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetPoint("TOPLEFT", sideInset, -yOffset)
    card:SetPoint("TOPRIGHT", -sideInset, -yOffset)
    card:SetHeight(cardHeight)
    parent[cacheKey] = card
    if fillParent then
        card._wnExcludedFromStorageExtent = true
    end
    ApplyStandardCardElevatedChrome(card)

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
    icon:SetAtlas(atlasForIcon)
    icon:SetAlpha(0.6)

    -- Title
    local title = FontManager:CreateFontString(contentContainer, UIFontRole("emptyCardTitle"), "OVERLAY")
    title:SetPoint("TOP", iconContainer, "BOTTOM", 0, -20)
    local titleText = (ns.L and ns.L[config.titleKey]) or config.titleFallback
    title:SetText("|cff888888" .. titleText .. "|r")

    -- Description
    local desc = FontManager:CreateFontString(contentContainer, UIFontRole("emptyCardBody"), "OVERLAY")
    desc:SetPoint("TOP", title, "BOTTOM", 0, -12)
    desc:SetWidth(380)
    desc:SetJustifyH("CENTER")
    local descText = (ns.L and config.descKey and ns.L[config.descKey]) or config.descFallback
    desc:SetText("|cff666666" .. descText .. "|r")

    card:Show()
    -- Second value is delta only (callers do: return yOffset + height)
    return card, cardHeight + bottomPad
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
    
    -- Debug log (only first call; verbose-only so normal debug mode stays readable)
    if not self._scrollLogged then
        if ns.DebugVerbosePrint then
            ns.DebugVerbosePrint("|cff9370DB[WN Factory]|r CreateScrollFrame initialized with modern scroll bar")
        end
        self._scrollLogged = true
    end
    
    -- Auto-hide scroll bar when content fits (call after content is populated).
    -- When bar is in an external container (reparented), always show bar and buttons so the column does not flicker.
    scrollFrame.UpdateScrollBarVisibility = function(self)
        if not self.ScrollBar then return end
        local bar = self.ScrollBar
        local scrollChild = self:GetScrollChild()
        if not scrollChild then return end
        local contentHeight = scrollChild:GetHeight() or 0
        local frameHeight = self:GetHeight() or 0
        local needsScroll = contentHeight > frameHeight + 1

        local barInExternalContainer = (bar.GetParent and bar:GetParent() ~= self)
        local col = self._wnScrollBarColumn
        local host = self._wnScrollHost
        local tl = self._wnScrollAnchorTL
        local brHidden = self._wnScrollAnchorBRHidden
        local brShown = self._wnScrollAnchorBRShown

        if col and host and tl and brHidden and brShown then
            self:ClearAllPoints()
            self:SetPoint(tl.a1 or "TOPLEFT", tl.frame, tl.a2 or "TOPLEFT", tl.x or 0, tl.y or 0)
            if needsScroll then
                col:Show()
                self:SetPoint(brShown.a1 or "BOTTOMRIGHT", brShown.frame, brShown.a2 or "BOTTOMLEFT", brShown.x or -2, brShown.y or 0)
            else
                col:Hide()
                self:SetPoint(brHidden.a1 or "BOTTOMRIGHT", brHidden.frame, brHidden.a2 or "BOTTOMRIGHT", brHidden.x or 0, brHidden.y or 0)
                if self.SetVerticalScroll then
                    self:SetVerticalScroll(0)
                end
            end
        end

        if barInExternalContainer then
            if needsScroll then
                bar:Show()
                if bar.ScrollUpBtn then bar.ScrollUpBtn:Show() end
                if bar.ScrollDownBtn then bar.ScrollDownBtn:Show() end
            else
                bar:Hide()
                if bar.ScrollUpBtn then bar.ScrollUpBtn:Hide() end
                if bar.ScrollDownBtn then bar.ScrollDownBtn:Hide() end
            end
            return
        end

        if needsScroll then
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
---@param width number Width of the column (matches `SCROLLBAR_COLUMN_WIDTH`, default 26)
---@param topInset number|nil Inset from parent top (default 0)
---@param bottomInset number|nil Inset from parent bottom (default 0)
---@return Frame container The frame to pass to PositionScrollBarInContainer
function ns.UI.Factory:CreateScrollBarColumn(parent, width, topInset, bottomInset)
    if not parent then return nil end
    local layout = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local w = width or layout.SCROLLBAR_COLUMN_WIDTH or 26
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
    -- Single height for track + arrows (layout HORIZONTAL_SCROLL_BAR_HEIGHT should match btnSize)
    local barHeight = btnSize

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

    -- Thumb width 60; height inside track (bar and buttons share barHeight)
    local thumbH = math.max(6, math.min(16, barHeight - 4))
    hBar.ThumbTexture = hBar:CreateTexture(nil, "ARTWORK")
    hBar.ThumbTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
    hBar.ThumbTexture:SetSize(60, thumbH)
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
            -- One anchor: center of button on mid-left of strip (avoid LEFT+CENTER conflict with bar height)
            self.ScrollLeftBtn:SetPoint("CENTER", container, "LEFT", btnSize / 2, 0)
        end
        if self.ScrollRightBtn then
            self.ScrollRightBtn:SetParent(container)
            self.ScrollRightBtn:SetFrameLevel(level + 3)
            self.ScrollRightBtn:ClearAllPoints()
            self.ScrollRightBtn:SetPoint("CENTER", container, "RIGHT", -btnSize / 2, 0)
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
---@param loadingState table - Loading state object with {isLoading, loadingProgress or scanProgress, currentStage, error}
---@param title string - Loading title (e.g., "Loading PvE Data")
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
    local spinnerFrame = CreateIcon(loadingCard, "auctionhouse-ui-loadingspinner", 40, true, nil, true)
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
    barBg:SetColorTexture(0.15, 0.15, 0.18, 1)
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
    hintText:SetTextColor(0.6, 0.6, 0.6)
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
    ApplyStandardCardElevatedChrome(errorCard)
    errorCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    errorCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    
    -- Warning icon
    local warningIconFrame = CreateIcon(errorCard, "services-icon-warning", 24, true, nil, true)
    warningIconFrame:SetPoint("LEFT", 20, 0)
    warningIconFrame:Show()
    
    -- Error message
    local FontManager = ns.FontManager
    local errorText = FontManager:CreateFontString(errorCard, UIFontRole("errorCardBody"), "OVERLAY")
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
---@param parent Frame - Parent container to fill
---@return Frame panel - Panel with :ShowLoading() / :HideLoading()
local function UI_CreateLoadingStatePanel(parent)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetAllPoints(parent)
    ApplyStandardCardElevatedChrome(panel)
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
    local titleText = FM:CreateFontString(panel, FM:GetFontRole("loadingPanelTitle"), "OVERLAY")
    titleText:SetPoint("TOP", spinnerFrame, "BOTTOM", 0, -10)
    titleText:SetJustifyH("CENTER")
    panel._titleText = titleText

    -- Progress text (stage + %)
    local progressText = FM:CreateFontString(panel, FM:GetFontRole("loadingPanelProgress"), "OVERLAY")
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
function ns.UI.Factory:CreateContainer(parent, width, height, withBorder, globalName)
    if not parent then return nil end
    
    local container = CreateFrame("Frame", globalName, parent)
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

--- Strip panel backdrop from icon-only row controls (pooled rows may predate transparent noBorder).
function ns.UI.Factory:ApplyIconOnlyButtonChrome(btn)
    if not btn or not btn.SetBackdrop then return end
    pcall(btn.SetBackdrop, btn, nil)
end

--- Create a themed horizontal slider (accent-colored thumb + border).
--- Single source of truth for slider styling; SettingsUI and tracker popups both use this
--- so the look stays consistent and we don't reinvent the widget for each call site.
---@param parent Frame
---@param opts table { min, max, step, value, onChange(function(v)), height(number) }
---@return Slider slider
function ns.UI.Factory:CreateThemedSlider(parent, opts)
    if not parent then return nil end
    opts = opts or {}
    local slider = CreateFrame("Slider", nil, parent, "BackdropTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(opts.height or 20)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 1)
    slider:SetValueStep(opts.step or 0.1)
    slider:SetObeyStepOnDrag(true)

    if slider.SetBackdrop then
        slider:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 1, edgeSize = 2,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        slider:SetBackdropColor(0.1, 0.1, 0.12, 1)
        local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }
        slider:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.6)
    end

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(14, 18)
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.5, 0.4, 0.7 }
    thumb:SetColorTexture(accent[1], accent[2], accent[3], 1)
    slider:SetThumbTexture(thumb)

    if opts.value ~= nil then slider:SetValue(opts.value) end

    if opts.onChange then
        slider:SetScript("OnValueChanged", function(self, value)
            local step = opts.step or 0.1
            value = math.floor(value / step + 0.5) * step
            if math.abs(self:GetValue() - value) > 0.001 then
                self:SetValue(value)
                return
            end
            opts.onChange(value)
        end)
    end

    return slider
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
    local tier = (rowIndex % 2 == 0) and "rowEven" or "rowOdd"
    local bgColor = ResolveSurfaceTierColor(tier)
    if not row.bg then
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
    end
    row.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
    row.bgColor = bgColor
end

---Apply (or clear) the online-character highlight on a character row or header.
---Uses the live theme accent color so it respects user customization.
---@param frame Frame  The row/header frame to highlight.
---@param isOnline boolean  True = this is the currently logged-in character.
function ns.UI.Factory:ApplyOnlineCharacterHighlight(frame, isOnline)
    if not frame then return end
    local ac = COLORS and COLORS.accent or ns.UI_COLORS and ns.UI_COLORS.accent
    if isOnline and ac then
        -- Background: very dark tint of accent (≈15% brightness so text stays readable)
        local r, g, b = ac[1] * 0.55, ac[2] * 0.55, ac[3] * 0.55
        if not frame.bg then
            frame.bg = frame:CreateTexture(nil, "BACKGROUND")
            frame.bg:SetAllPoints()
        end
        frame.bg:SetColorTexture(r * 0.4, g * 0.4, b * 0.4, 1)
        -- Left accent bar: full accent brightness
        if not frame.onlineAccent then
            frame.onlineAccent = frame:CreateTexture(nil, "BORDER")
            frame.onlineAccent:SetWidth(3)
            frame.onlineAccent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            frame.onlineAccent:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        end
        frame.onlineAccent:SetColorTexture(ac[1], ac[2], ac[3], 1)
        frame.onlineAccent:Show()
    else
        if frame.onlineAccent then frame.onlineAccent:Hide() end
        if frame.bg and frame.bgColor then
            local c = frame.bgColor
            frame.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        end
    end
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
---@param height number|nil - Header height (defaults to `SECTION_COLLAPSE_HEADER_HEIGHT`)
---@param leftIndent number|nil - Left indent in pixels (for sub-headers, e.g. 15 or 30)
---@return number newYOffset, Frame header
function ns.UI.Factory:CreateSectionHeader(parent, yOffset, isCollapsed, titleStr, rightStr, onToggle, height, leftIndent)
    if not parent then return yOffset, nil end

    local sp = UI_SPACING
    local h = height or sp.SECTION_COLLAPSE_HEADER_HEIGHT or sp.HEADER_HEIGHT
    local indent = leftIndent or 0
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(h)
    header:SetPoint("TOPLEFT", indent, -yOffset)
    header:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    -- Draw above virtual-scroll row frames so nothing shows through behind header
    header:SetFrameLevel((parent:GetFrameLevel() or 0) + 10)
    header:Show()

    local surf = COLORS.surfaceElevated or COLORS.bgLight
    -- Opaque background (1.0) so row text does not show through behind header
    ApplyVisuals(header, {surf[1], surf[2], surf[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    header._wnSectionHeaderBaseBg = {surf[1], surf[2], surf[3], 1}

    if ns.UI_ApplySectionChromeUnderlay then
        ns.UI_ApplySectionChromeUnderlay(header)
    end

    -- Collapse/expand chevron (same control as tab section headers)
    local collapseBtn = ns.UI_CreateCollapseExpandControl(header, not isCollapsed, { enableMouse = true })
    local chevLeft = sp.SECTION_HEADER_FACTORY_CHEVRON_LEFT or 10
    collapseBtn:SetPoint("LEFT", chevLeft + indent, 0)

    -- Title text
    local title = FontManager:CreateFontString(header, UIFontRole("factorySectionHeaderTitle"), "OVERLAY")
    title:SetPoint("LEFT", collapseBtn, "RIGHT", 4, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetMaxLines(1)

    -- Right-side text (optional)
    if rightStr then
        local rightLabel = FontManager:CreateFontString(header, UIFontRole("factorySectionHeaderRight"), "OVERLAY")
        rightLabel:SetPoint("RIGHT", header, "RIGHT", -sp.SIDE_MARGIN, 0)
        rightLabel:SetJustifyH("RIGHT")
        rightLabel:SetText(rightStr)
        title:SetPoint("RIGHT", rightLabel, "LEFT", -6, 0)
    end

    title:SetText(titleStr)

    -- Click handlers
    header:SetScript("OnClick", onToggle)
    collapseBtn:SetScript("OnClick", onToggle)

    -- Hover highlight (token-driven base from `surfaceElevated`)
    header:SetScript("OnEnter", function()
        if header.SetBackdropColor and header._wnSectionHeaderBaseBg then
            local b = header._wnSectionHeaderBaseBg
            header:SetBackdropColor(
                math.min(1, b[1] * 1.12),
                math.min(1, b[2] * 1.12),
                math.min(1, b[3] * 1.12),
                b[4] or 1
            )
        end
    end)
    header:SetScript("OnLeave", function()
        if header.SetBackdropColor and header._wnSectionHeaderBaseBg then
            local b = header._wnSectionHeaderBaseBg
            header:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
        end
    end)

    return yOffset + h, header
end

local COLLECTION_PLAN_SLOT_SIZE = math.floor(19 * 1.25 + 0.5)

local function SetCollectionPlanSlotTooltip(btn, text)
    if not btn then return end
    if not text or text == "" then
        btn:SetScript("OnEnter", nil)
        btn:SetScript("OnLeave", nil)
        return
    end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("BOTTOMLEFT", self, "TOPRIGHT", 4, 6)
        GameTooltip:SetText(text, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function CreateCollectionPlanSlotButton(row)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:Hide()
    b:SetFrameLevel((row:GetFrameLevel() or 0) + 12)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    b._wnIcon = tex
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

local function EnsureCollectionRowPlanSlotButtons(row)
    if not row then return end
    if row.todoSlotBtn and row.trackSlotBtn then return end
    if row.rowTodoIcon then
        row.rowTodoIcon:Hide()
    end
    if row.rowTrackIcon then
        row.rowTrackIcon:Hide()
    end
    row.todoSlotBtn = row.todoSlotBtn or CreateCollectionPlanSlotButton(row)
    row.trackSlotBtn = row.trackSlotBtn or CreateCollectionPlanSlotButton(row)
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
    local collIconScale = 1.25
    local statusSize = math.floor(16 * collIconScale + 0.5)
    local iconSize = math.floor((UI_SPACING.ROW_ICON_SIZE or 20) * collIconScale + 0.5)

    local statusIcon = row:CreateTexture(nil, "ARTWORK")
    statusIcon:SetSize(statusSize, statusSize)
    statusIcon:SetPoint("LEFT", pad, 0)
    row.statusIcon = statusIcon

    row.todoSlotBtn = CreateCollectionPlanSlotButton(row)
    row.trackSlotBtn = CreateCollectionPlanSlotButton(row)

    local iconBorder = self:CreateContainer(row, iconSize, iconSize, true)
    if iconBorder then
        local bg = { 0.12, 0.12, 0.14, 0.95 }
        local bc = COLORS.border or COLORS.accent or { 0.5, 0.4, 0.7 }
        if ApplyVisuals then
            ApplyVisuals(iconBorder, bg, { bc[1], bc[2], bc[3], 0.72 })
        end
        iconBorder:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
        row._iconBorder = iconBorder
    end
    local iconHost = row._iconBorder or row
    local icon = iconHost:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHost, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconHost, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local label = FontManager:CreateFontString(row, UIFontRole("factoryDataRowLabel"), "OVERLAY")
    label:SetPoint("LEFT", iconHost, "RIGHT", gap, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    row.label = label

    local rightLabel = FontManager:CreateFontString(row, UIFontRole("factoryDataRowRight"), "OVERLAY")
    rightLabel:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
    rightLabel:SetJustifyH("RIGHT")
    rightLabel:SetWordWrap(false)
    rightLabel:Hide()
    row.rightLabel = rightLabel

    return row
end

local COLLECTION_ROW_ICON_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local COLLECTION_ROW_ICON_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"

local function CollectionListRowIconHost(row)
    return row._iconBorder or row.icon
end

local function CollectionRowTextLeftX(row, pad, gap, slotGap)
    local x = pad or 10
    gap = gap or 4
    slotGap = slotGap or 3
    if row.statusIcon and row.statusIcon:IsShown() then
        x = x + (row.statusIcon:GetWidth() or 0) + gap
    end
    if row.todoSlotBtn and row.todoSlotBtn:IsShown() then
        x = x + COLLECTION_PLAN_SLOT_SIZE + slotGap
        if row.trackSlotBtn and row.trackSlotBtn:IsShown() then
            x = x + COLLECTION_PLAN_SLOT_SIZE + slotGap
        end
    end
    local iconHost = CollectionListRowIconHost(row)
    if iconHost and iconHost.GetWidth then
        x = x + (iconHost:GetWidth() or 0) + gap
    end
    return x
end

--- Vertically center label (and optional subtitle) in the row; two-line block height never exceeds item icon.
local function LayoutCollectionListRowText(row, pad, gap, slotGap)
    if not row or not row.label then return end
    pad = pad or 10
    gap = gap or 4
    slotGap = slotGap or 3
    local iconHost = CollectionListRowIconHost(row)
    if not iconHost then return end
    local rowH = row:GetHeight() or (UI_SPACING.ROW_HEIGHT or 32)
    local iconH = iconHost:GetHeight() or 25
    local textX = CollectionRowTextLeftX(row, pad, gap, slotGap)
    local hasSub = row.subtitle and row.subtitle:IsShown() and (row.subtitle:GetText() or "") ~= ""
    row.label:ClearAllPoints()
    if hasSub and row.subtitle then
        row.subtitle:ClearAllPoints()
        local lineGap = 2
        local lh = row.label:GetStringHeight() or 12
        local sh = row.subtitle:GetStringHeight() or 10
        local blockH = lh + lineGap + sh
        if blockH > iconH then
            lineGap = 1
            blockH = lh + lineGap + sh
        end
        if blockH > iconH then
            blockH = iconH
            lineGap = math.max(0, blockH - lh - sh)
        end
        local blockTop = (rowH - blockH) * 0.5
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("TOP")
        row.subtitle:SetJustifyH("LEFT")
        row.subtitle:SetJustifyV("TOP")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -blockTop)
        row.subtitle:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -lineGap)
        if row.rightLabel and row.rightLabel:IsShown() then
            row.subtitle:SetPoint("RIGHT", row.rightLabel, "LEFT", -6, 0)
        else
            row.subtitle:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
        end
    else
        local lh = row.label:GetStringHeight() or 12
        local blockTop = (rowH - lh) * 0.5
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("TOP")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", textX, -blockTop)
    end
    if row.rightLabel and row.rightLabel:IsShown() then
        row.rightLabel:ClearAllPoints()
        row.rightLabel:SetPoint("RIGHT", row, "RIGHT", -(pad + 4), 0)
        row.rightLabel:SetJustifyV("MIDDLE")
        row.label:SetPoint("RIGHT", row.rightLabel, "LEFT", -6, 0)
    else
        row.label:SetPoint("RIGHT", row, "RIGHT", -pad, 0)
    end
end

--- To-Do / Track column beside collected check (Collections + To-Do browse). `planSlotState` nil = hidden (e.g. Recent cards).
--- planSlotState: `onTodo`, `onTrack`, optional `achievementRow`, `achievementCollected`, optional `showTrackSlot`, optional `onTodoClick` / `onTrackClick` (toggle supported by caller), optional `todoTooltip` / `trackTooltip` (hover; non-interactive slots still show tooltip when text set and mouse enabled).
local function ApplyCollectionRowPlanSlotTextures(row, planSlotState, gap, slotGap)
    EnsureCollectionRowPlanSlotButtons(row)
    local todoBtn = row.todoSlotBtn
    local trackBtn = row.trackSlotBtn
    local iconHost = row and CollectionListRowIconHost(row)
    local statusIcon = row and row.statusIcon
    if not todoBtn or not trackBtn or not iconHost or not statusIcon then return end
    gap = gap or 4
    slotGap = slotGap or 3
    if not planSlotState then
        todoBtn:Hide()
        trackBtn:Hide()
        todoBtn:SetScript("OnClick", nil)
        trackBtn:SetScript("OnClick", nil)
        SetCollectionPlanSlotTooltip(todoBtn, nil)
        SetCollectionPlanSlotTooltip(trackBtn, nil)
        todoBtn:EnableMouse(false)
        trackBtn:EnableMouse(false)
        todoBtn:ClearAllPoints()
        trackBtn:ClearAllPoints()
        iconHost:ClearAllPoints()
        iconHost:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
        return
    end
    local onTodo = planSlotState.onTodo == true
    local onTrack = planSlotState.onTrack == true
    local achRow = planSlotState.achievementRow == true
    local achCollected = planSlotState.achievementCollected == true
    local showTrackSlot
    if planSlotState.showTrackSlot == false then
        showTrackSlot = false
    elseif planSlotState.showTrackSlot == true then
        showTrackSlot = true
    else
        showTrackSlot = achRow
    end

    local todoTex = todoBtn._wnIcon
    local trackTex = trackBtn._wnIcon
    if not todoTex or not trackTex then return end

    todoBtn:ClearAllPoints()
    trackBtn:ClearAllPoints()
    todoBtn:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    trackBtn:SetSize(COLLECTION_PLAN_SLOT_SIZE, COLLECTION_PLAN_SLOT_SIZE)
    todoBtn:SetPoint("LEFT", statusIcon, "RIGHT", gap, 0)
    todoBtn:Show()

    local todoDisabled = achCollected == true
    if ns.UI_ApplyWnActionIcon then
        ns.UI_ApplyWnActionIcon(todoTex, "todo", onTodo, todoDisabled)
    else
        ns.UI_SetWnIconTexture(todoTex, "todo", {
            desaturate = todoDisabled,
            vertexColor = ns.UI_WnIconVertexForKey("todo", onTodo, todoDisabled),
        })
    end

    local todoClickable = (type(planSlotState.onTodoClick) == "function") and (onTodo or not achCollected)
    local todoTip = planSlotState.todoTooltip
    local todoTipStr = (type(todoTip) == "string") and todoTip or ""
    local todoMouse = todoClickable or (todoTipStr ~= "")
    todoBtn:EnableMouse(todoMouse)
    if todoClickable then
        todoBtn:SetScript("OnClick", function()
            planSlotState.onTodoClick()
        end)
    else
        todoBtn:SetScript("OnClick", nil)
    end
    SetCollectionPlanSlotTooltip(todoBtn, todoMouse and todoTipStr ~= "" and todoTipStr or nil)

    iconHost:ClearAllPoints()
    if showTrackSlot then
        trackBtn:SetPoint("LEFT", todoBtn, "RIGHT", slotGap, 0)
        trackBtn:Show()
        local trackDisabled = achCollected == true
        if ns.UI_ApplyWnActionIcon then
            ns.UI_ApplyWnActionIcon(trackTex, "track", onTrack, trackDisabled)
        else
            ns.UI_SetWnIconTexture(trackTex, "track", {
                desaturate = trackDisabled,
                vertexColor = ns.UI_WnIconVertexForKey("track", onTrack, trackDisabled),
            })
        end
        local trackClickable = (type(planSlotState.onTrackClick) == "function") and (not achCollected)
        local trackTip = planSlotState.trackTooltip
        local trackTipStr = (type(trackTip) == "string") and trackTip or ""
        local trackMouse = trackClickable or (trackTipStr ~= "")
        trackBtn:EnableMouse(trackMouse)
        if trackClickable then
            trackBtn:SetScript("OnClick", function()
                planSlotState.onTrackClick()
            end)
        else
            trackBtn:SetScript("OnClick", nil)
        end
        SetCollectionPlanSlotTooltip(trackBtn, trackMouse and trackTipStr ~= "" and trackTipStr or nil)
        iconHost:SetPoint("LEFT", trackBtn, "RIGHT", gap, 0)
    else
        trackBtn:Hide()
        trackBtn:SetScript("OnClick", nil)
        SetCollectionPlanSlotTooltip(trackBtn, nil)
        trackBtn:EnableMouse(false)
        iconHost:SetPoint("LEFT", todoBtn, "RIGHT", gap, 0)
    end
end

--- Apply content and selection to a collection list row (from CreateCollectionListRow). Use for virtual scroll.
---@param row Frame - Row from CreateCollectionListRow
---@param rowIndex number - For alternating background (1-based)
---@param iconPath string - Texture path for item icon
---@param labelText string - Formatted label (e.g. "|cff33e533Name|r" or "|cffffffffName|r (10 pts)")
---@param isCollected boolean - True = check icon, false = cross icon
---@param isSelected boolean - Show selection highlight
---@param onClick function|nil - OnMouseDown script
---@param rightAlignedText string|nil Optional right column (e.g. relative time); main label stops before it.
---@param subtitleText string|nil Optional second line (small) under title; row height should be set by caller.
---@param planSlotState table|nil Optional `{ onTodo, onTrack, achievementRow?, achievementCollected?, showTrackSlot?, onTodoClick?, onTrackClick?, todoTooltip?, trackTooltip? }` — `achievementCollected` defaults from `isCollected` when omitted (mount/pet/toy). To-Do/pin grey when completed, on list, or (pin) already tracking.
function ns.UI.Factory:ApplyCollectionListRowContent(row, rowIndex, iconPath, labelText, isCollected, isSelected, onClick, rightAlignedText, subtitleText, planSlotState)
    if not row then return end
    local pad = UI_SPACING.SIDE_MARGIN or 10
    local gap = 4
    local slotGap = 3
    self:ApplyRowBackground(row, rowIndex or 1)
    if row.statusIcon then
        row.statusIcon:SetTexture(isCollected and COLLECTION_ROW_ICON_READY or COLLECTION_ROW_ICON_NOT_READY)
        row.statusIcon:Show()
    end
    if planSlotState and rawget(planSlotState, "achievementCollected") == nil then
        planSlotState.achievementCollected = isCollected == true
    end
    ApplyCollectionRowPlanSlotTextures(row, planSlotState, gap, slotGap)
    if row.icon then
        local iconTex = (iconPath and iconPath ~= "") and iconPath or "Interface\\Icons\\Achievement_General"
        row.icon:SetTexture(iconTex)
        row.icon:Show()
    end
    local hasSub = subtitleText and subtitleText ~= ""
    if row.label then
        row.label:SetText(labelText or "")
        row.label:SetJustifyH("LEFT")
        row.label:SetJustifyV("MIDDLE")
        row.label:SetWordWrap(false)
    end
    if hasSub then
        if not row.subtitle then
            row.subtitle = FontManager:CreateFontString(row, UIFontRole("small"), "OVERLAY")
            row.subtitle:SetJustifyH("LEFT")
            row.subtitle:SetJustifyV("MIDDLE")
            row.subtitle:SetWordWrap(false)
            row.subtitle:SetTextColor(0.65, 0.68, 0.74, 1)
        end
        row.subtitle:SetText(subtitleText)
        row.subtitle:Show()
    elseif row.subtitle then
        row.subtitle:SetText("")
        row.subtitle:Hide()
    end
    if row.rightLabel and rightAlignedText and rightAlignedText ~= "" then
        row.rightLabel:SetText(rightAlignedText)
        row.rightLabel:SetJustifyV("MIDDLE")
        row.rightLabel:Show()
    else
        if row.rightLabel then
            row.rightLabel:SetText("")
            row.rightLabel:Hide()
        end
    end
    if row.label and CollectionListRowIconHost(row) then
        LayoutCollectionListRowText(row, pad, gap, slotGap)
    end
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

        local title = FontManager and FontManager:CreateFontString(f, "small", "OVERLAY") or f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 10, -8)
        title:SetText(
            "|cffffcc00" .. ((ns.L and ns.L["WOWHEAD_LABEL"]) or "Wowhead") .. "|r  |cff888888"
            .. ((ns.L and ns.L["CTRL_C_LABEL"]) or "Ctrl+C") .. "|r"
        )
        f._title = title

        local closeBtn = self:CreateButton(f, 20, 20, true) or CreateFrame("Button", nil, f)
        closeBtn:SetSize(20, 20)
        local closeInset = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL and ns.UI_LAYOUT.MAIN_SHELL.FRAME_CONTENT_INSET) or 2
        closeBtn:SetPoint("TOPRIGHT", -closeInset, -closeInset)
        local closeLbl = FontManager and FontManager:CreateFontString(closeBtn, "body", "OVERLAY") or closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        closeLbl:SetPoint("CENTER")
        closeLbl:SetText("x")
        closeLbl:SetTextColor(0.9, 0.9, 0.9)
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        local editBox = self:CreateEditBox(f) or CreateFrame("EditBox", nil, f)
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
