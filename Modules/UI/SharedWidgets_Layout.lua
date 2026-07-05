--[[
    Warband Nexus - SharedWidgets layout/spacing constants (ops Phase 6)
    UI_SPACING / UI_LAYOUT / MAIN_SHELL tokens. Loaded before SharedWidgets.lua.
]]

local ADDON_NAME, ns = ...

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
    
    --- Row striping (synced from COLORS.surfaceRow* in ThemeAPI.SyncSemanticColorAliases).
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
    --- In-tab horizontal sub-tabs (Collections browse, To-Do categories, Items bank).
    SUB_TAB = {
        BTN_HEIGHT = 40,
        BTN_SPACING = 8,
        ICON_SIZE = 28,
        ICON_LEFT = 10,
        ICON_TEXT_GAP = 8,
        TEXT_RIGHT = 10,
        DEFAULT_WIDTH = 150,
        ACTIVE_BAR_HEIGHT = 3,
        ACTIVE_BAR_INSET = 8,
        ACTIVE_BAR_BOTTOM = 4,
    },
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
        --- Inset from root shell edge to interior chrome (`CreateMainWindow` / `UI_ApplyMainShellLayout`).
        --- Dark/light: 0 full-bleed. Classic layout uses `UI_GetMainShellFrameInsets()` dialog tile insets instead.
        FRAME_CONTENT_INSET = 0,
        FRAME_CONTENT_INSET_BOTTOM = 4,
        INTERIOR_INSET_LEFT = 0,
        INTERIOR_INSET_RIGHT = 0,
        INTERIOR_INSET_TOP = 0,
        INTERIOR_INSET_BOTTOM = 4,
        --- Classic Blizzard dialog backdrop tile insets (same values as `UI_CLASSIC_DIALOG_BACKDROP.insets`; used by classic layout via `UI_GetMainShellFrameInsets`).
        CLASSIC_DIALOG_INSET_LEFT = 11,
        CLASSIC_DIALOG_INSET_RIGHT = 12,
        CLASSIC_DIALOG_INSET_TOP = 12,
        CLASSIC_DIALOG_INSET_BOTTOM = 11,
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
        NAV_RAIL_TOP_INSET = 0,
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
        FOOTER_HEIGHT = 26,
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
        --- Floating To-Do List tracker title band (compact; not main-shell NAV_BAR_HEIGHT).
        PLANS_TRACKER_HEADER_HEIGHT = 28,
        --- Scroll viewport rim: keep first/last cards off content-area top/bottom edges.
        PLANS_TRACKER_VIEWPORT_PAD_TOP = 16,
        PLANS_TRACKER_VIEWPORT_PAD_BOTTOM = 16,
        --- Inside scroll child (clip rect): extra breathing room when scrolled to ends.
        PLANS_TRACKER_SCROLL_CONTENT_PAD_TOP = 10,
        PLANS_TRACKER_SCROLL_CONTENT_PAD_BOTTOM = 10,
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

ns.UI_SPACING = UI_SPACING
ns.UI_LAYOUT = UI_SPACING
