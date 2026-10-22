--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs.
-- Satellite slices: SharedWidgets_Icons/Collapsible/Search/RowPool/Factory (ops-027–029); Pixel/CharRow load before this file.
-- Split 2026-10: SharedWidgets_PlansLayout/TabLayout/TitleCard/TryCountPopup/StateCards load right after this file.
    LuaLS: reserve ---@ on ns.UI.Factory public methods and WarbandNexus: exports only.
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
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
local PixelRound = ns.PixelRound
local SnapRuleTexture = ns.UI_SnapRuleTexture
local ResetPixelScale = ns.ResetPixelScale
assert(GetPixelScale and PixelSnap, "SharedWidgets: SharedWidgets_Pixel must load first")

-- Theme palettes + ThemeAPI: Modules/UI/SharedWidgets_Theme.lua
-- Layout constants: Modules/UI/SharedWidgets_Layout.lua
assert(ns.UITheme and ns.UITheme.COLORS and ns.UI_SPACING, 'SharedWidgets: Theme + Layout satellites must load first')
local ThemeAPI = ns.UITheme.ThemeAPI
local COLORS = ns.UITheme.COLORS
local SURFACE_VARIANTS = ns.UITheme.SURFACE_VARIANTS
local GetColors = ns.UITheme.GetColors
local CalculateThemeColors = ns.UITheme.CalculateThemeColors
local GetThemeColors = ns.UITheme.GetThemeColors
local DEFAULT_THEME = ns.UITheme.DEFAULT_THEME
local UI_SPACING = ns.UI_SPACING
local UI_LAYOUT = UI_SPACING
local IsLightModeEnabled = ns.UI_IsLightMode
local IsClassicModeEnabled = ns.UI_IsClassicMode
local AdjustRGBForLightOutline = ns.UI_AdjustRGBForLightOutline

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

--- Main / settings nav rail tab button height (single source for UIPanelButtonTemplate rows).
---@return number
function ns.UI_GetNavRailTabHeight()
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    return shell.NAV_RAIL_TAB_HEIGHT or 38
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

--- Fixed grey `|cff` markup that no text role matches in dark mode: dark/classic keep the literal
--- (frozen baseline), light resolves the role so the label stays readable on pale cards (2026-10-22).
---@param darkHex string `|cffrrggbb` used today in dark mode
---@param role string "Bright" | "Normal" | "Muted" | "Dim"
---@return string
function ns.UI_GetThemedGreyHex(darkHex, role)
    if IsLightModeEnabled() then
        return ThemeAPI.GetTextRoleHex(role)
    end
    return darkHex
end

--- Collection list row status: gold `common-icon-checkmark` when collected (canonical WN check).
function ns.UI_ApplyCollectionRowStatusIcon(statusIcon, isCollected)
    if not statusIcon then return end
    statusIcon:Show()
    if isCollected then
        local g = COLORS and COLORS.gold
        ns.UI_SetIcon(statusIcon, "status_ok", { vertexColor = g or { 1, 0.82, 0, 1 } })
    else
        -- status_pending is mono: white (dark) / black (light) at alpha 0.35.
        ns.UI_SetIcon(statusIcon, "status_pending", { alpha = 0.35 })
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
        complete = "Interface\\RaidFrame\\ReadyCheck-Ready", -- file fallback; atlas via UI_ICONS.status_ok
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
    local usedAtlas = false
    if iconKey == "complete" and not opts.texCoord then
        -- Registry atlas (common-icon-checkmark); file path above stays the fallback.
        usedAtlas = ns.UI_SetIcon(tex, "status_ok") and true or false
    end
    if not usedAtlas then
        tex:SetTexture(path)
    end
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

-- Plans header actions / card grid / To-Do layout helpers: SharedWidgets_PlansLayout.lua

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
        local c = ThemeAPI.GetControlChromeBackdrop()
        return c[1], c[2], c[3], c[4] or bgAlpha
    elseif bgType == "controlChromeHover" then
        local c = ThemeAPI.GetControlChromeHoverBackdrop()
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

local SHELL_BG_OPACITY_MIN = 0.2
local SHELL_BG_OPACITY_MAX = 1.0

local function GetShellBackgroundOpacity()
    local addon = _G.WarbandNexus or ns.WarbandNexus
    local raw = addon and addon.db and addon.db.profile and addon.db.profile.shellBackgroundOpacity
    if type(raw) ~= "number" then
        return SHELL_BG_OPACITY_MAX
    end
    return math.max(SHELL_BG_OPACITY_MIN, math.min(SHELL_BG_OPACITY_MAX, raw))
end

--- Flat shell fill alpha from the opacity slider (0.2-1.0). At 100% the fill is fully opaque.
---@return number
local function ResolveShellBackgroundFillAlpha()
    return GetShellBackgroundOpacity()
end

--- Anchor flat shell fill inside classic dialog insets (no bleed under border tile).
---@param frame Frame
---@param tex Texture
local function SyncMainShellFlatFillAnchors(frame, tex)
    if not frame or not tex then return end
    tex:ClearAllPoints()
    if IsClassicModeEnabled() and ns.UI_GetMainShellFrameInsets then
        local insetL, insetR, insetT, insetB = ns.UI_GetMainShellFrameInsets()
        tex:SetPoint("TOPLEFT", frame, "TOPLEFT", insetL, -insetT)
        tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -insetR, insetB)
    else
        tex:SetAllPoints(frame)
    end
end

-- Refresh COLORS table from database (in-place, zero allocation)
local function RefreshColors()
    -- Update theme-derived colors in-place
    ThemeAPI.UpdateColorsFromTheme()
    ThemeAPI.SyncSemanticColorAliases()
    ThemeAPI.SyncPlanUIColors()
    if ns.VaultButton and ns.VaultButton.SyncEasyAccessThemeInk then
        ns.VaultButton.SyncEasyAccessThemeInk()
    end
    -- Ensure namespace reference is current
    ns.UI_COLORS = COLORS

    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local sc = mf and mf.scrollChild
    if sc and not IsClassicModeEnabled() then
        if ns.UI_EnsureScrollChildViewportFill then
            ns.UI_EnsureScrollChildViewportFill(sc)
        end
        if ns.UI_RefreshScrollAnnexLayout then
            ns.UI_RefreshScrollAnnexLayout(sc)
        end
    elseif sc and IsClassicModeEnabled() then
        if sc._wnViewportCanvasFill and sc._wnViewportCanvasFill.Hide then
            sc._wnViewportCanvasFill:Hide()
        end
        if sc._wnScrollBottomFill and sc._wnScrollBottomFill.Hide then
            sc._wnScrollBottomFill:Hide()
        end
        if sc._wnResultsAnnexSheet and sc._wnResultsAnnexSheet.Hide then
            sc._wnResultsAnnexSheet:Hide()
        end
    end
    
    -- Safety check (use namespace reference)
    if not ns.BORDER_REGISTRY then
        ns.BORDER_REGISTRY = {}
        return
    end
    
    local accentColor = COLORS.accent
    local accentDarkColor = COLORS.accentDark
    local borderColor = ThemeAPI.GetBorderStrokeColor()
    local bgColor = COLORS.bg
    local updated = 0
    
    -- Update ALL registered frames (ApplyVisuals 4-texture system)
    for i = #ns.BORDER_REGISTRY, 1, -1 do
        local frame = ns.BORDER_REGISTRY[i]
        
        -- Discarded section chrome (SectionPool) can never show again: drop it (2026-10-22).
        if not frame or (ns.UI_IsDiscardedRegion and ns.UI_IsDiscardedRegion(frame)) then
            table.remove(ns.BORDER_REGISTRY, i)
        elseif frame._wnBlizzardChrome and IsClassicModeEnabled() then
            if frame._wnClassicThinBorder and frame.SetBackdropColor and frame._wnThinBorderBg then
                local b = frame._wnThinBorderBg
                frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
                local bc = (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.border)
                    or COLORS.borderLight or borderColor
                if frame.SetBackdropBorderColor and bc then
                    frame:SetBackdropBorderColor(bc[1], bc[2], bc[3], 1)
                end
            elseif frame._wnSectionHeaderPanelBg and frame.SetBackdropColor then
                local b = frame._wnSectionHeaderPanelBg
                frame:SetBackdropColor(b[1], b[2], b[3], b[4] or 1)
                if frame.SetBackdropBorderColor then
                    frame:SetBackdropBorderColor(1, 1, 1, 1)
                end
            end
            updated = updated + 1
        elseif frame.BorderTop then
            -- 4-texture border (includes main shell accent frame).
            local targetColor
            local alpha = frame._borderAlpha or 0.6
            if frame._borderType == "sectionHeader" then
                local sr, sg, sb, sa = ThemeAPI.GetSectionHeaderBorderRGBA()
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
                local fillAlpha = ResolveShellBackgroundFillAlpha()
                frame._wnShellFill:SetColorTexture(shellBg[1], shellBg[2], shellBg[3], fillAlpha)
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
            if frame._wnBlizzardChrome and IsClassicModeEnabled() then
                updated = updated + 1
            else
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
            end
        elseif not frame.BorderTop then
            table.remove(ns.BORDER_REGISTRY, i)
        end
    end

    if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
        local itemsHdr = WarbandNexus.UI.mainFrame._itemsFixedHeaderCache
        if itemsHdr and ns.UI_ApplySearchBoxChrome then
            if itemsHdr.searchBox then
                ns.UI_ApplySearchBoxChrome(itemsHdr.searchBox.searchFrame or itemsHdr.searchBox, { editBoxHost = true })
            end
            if itemsHdr.statsBar then
                ns.UI_ApplySearchBoxChrome(itemsHdr.statsBar)
            end
        end
    end

    -- Defined below this chunk position; reach it through ns so this is not a nil global.
    if ns.UI_RefreshAccentStripes then
        ns.UI_RefreshAccentStripes()
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
    if ns.UI_RefreshThemeDividers then
        ns.UI_RefreshThemeDividers()
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
    -- Money log popup was only repainted on the font path; theme/accent toggles left it stale (2026-10-22).
    if ns.CharacterBankMoneyLogPopup and ns.CharacterBankMoneyLogPopup.RefreshTheme then
        ns.CharacterBankMoneyLogPopup.RefreshTheme()
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

--- Accent-bordered control shell (search, stats strip): standard border quartet + left rail.
---@param frame Frame
---@param opts table|nil `{ borderAlpha, showRail, railWidth, bg }`
function ns.UI_ApplyAccentControlChrome(frame, opts)
    if not frame then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then
        return
    end
    if IsClassicModeEnabled() then
        if ns.UI.Factory and ns.UI.Factory.ApplyToolbarChrome then
            ns.UI.Factory:ApplyToolbarChrome(frame, opts)
        elseif ns.UI_ApplyClassicPaneBackdrop then
            local bg = (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.surfaceHeaderChrome)
                or (COLORS and COLORS.surfaceHeaderChrome)
            ns.UI_ApplyClassicPaneBackdrop(frame, bg)
        end
        return
    end
    opts = type(opts) == "table" and opts or {}
    local ac = COLORS.accent or { 0.40, 0.20, 0.58 }
    local ar, ag, ab, aa
    if opts.bg then
        ar, ag, ab, aa = opts.bg[1], opts.bg[2], opts.bg[3], opts.bg[4] or 1
    else
        ar, ag, ab, aa = ThemeAPI.GetSubTabActiveBackdropRGBA(ac)
    end
    local borderA = opts.borderAlpha or 0.72

    -- Same border as every card/button: ApplyVisuals quartet at UI_GetBorderThickness
    -- (whole physical pixels), not a backdrop edge with its own fixed edgeSize.
    frame._wnMainShellBackdrop = nil
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(frame, { ar, ag, ab, aa or 0.98 }, { ac[1], ac[2], ac[3], borderA })
    end
    -- A flat-chrome pass may have hidden the quartet on this reused frame.
    if frame.BorderTop then
        frame.BorderTop:Show(); frame.BorderBottom:Show()
        frame.BorderLeft:Show(); frame.BorderRight:Show()
    end
    frame._borderType = "accent"
    frame._borderAlpha = borderA
    frame._bgType = "searchChrome"
    local edge = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(frame)) or 1

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

    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then
        return
    end

    -- Classic mode: 1px stroke (modern ApplyVisuals quartet parity) — not dialog-box on short frames.
    if IsClassicModeEnabled() and ns.UI_ApplyClassicThinBorderChrome then
        ns.UI_ApplyClassicThinBorderChrome(frame, bgColor)
        if not frame._borderRegistered and ns.BORDER_REGISTRY then
            frame._borderRegistered = true
            table.insert(ns.BORDER_REGISTRY, frame)
        end
        frame._borderType = "border"
        frame._bgType = "bg"
        return
    end
    
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
        -- 1 UI unit in whole physical pixels (crisp; same visual weight on every display)
        local pixelScale = (ns.UI_GetBorderThickness and ns.UI_GetBorderThickness(frame)) or GetPixelScale(frame)
        
        -- Top border (INSIDE frame, at the top edge)
        frame.BorderTop = frame:CreateTexture(nil, "BORDER")
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(pixelScale)  -- Pixel-perfect 1px
        -- Exactly 1 physical px + grid snap = constant 1px during resize/scroll
        -- (unsnapped, a sub-pixel offset smears it across 2px and it flickers).
        SnapRuleTexture(frame.BorderTop)
        frame.BorderTop:SetDrawLayer("BORDER", 0)
        
        -- Bottom border (INSIDE frame, at the bottom edge)
        frame.BorderBottom = frame:CreateTexture(nil, "BORDER")
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(pixelScale)  -- Pixel-perfect 1px
        SnapRuleTexture(frame.BorderBottom)
        frame.BorderBottom:SetDrawLayer("BORDER", 0)
        
        -- Left border (INSIDE frame, full height — overlaps corners, same color = invisible)
        frame.BorderLeft = frame:CreateTexture(nil, "BORDER")
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderLeft:SetWidth(pixelScale)
        SnapRuleTexture(frame.BorderLeft)
        frame.BorderLeft:SetDrawLayer("BORDER", 0)
        
        -- Right border (INSIDE frame, full height — overlaps corners, same color = invisible)
        frame.BorderRight = frame:CreateTexture(nil, "BORDER")
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderRight:SetWidth(pixelScale)
        SnapRuleTexture(frame.BorderRight)
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
    -- Whole physical pixels (min 1) so the snapped edges never alternate thickness.
    local borderW = PixelRound(shell.MAIN_SHELL_FRAME_BORDER_WIDTH or 2, frame, 1)
    local borderLayer = "OVERLAY"
    local borderSubLevel = 7
    if not frame.BorderTop then
        frame.BorderTop = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(borderW)
        SnapRuleTexture(frame.BorderTop)

        frame.BorderBottom = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(borderW)
        SnapRuleTexture(frame.BorderBottom)

        frame.BorderLeft = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderLeft:SetWidth(borderW)
        SnapRuleTexture(frame.BorderLeft)

        frame.BorderRight = frame:CreateTexture(nil, borderLayer, nil, borderSubLevel)
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderRight:SetWidth(borderW)
        SnapRuleTexture(frame.BorderRight)
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

--- Classic chrome opt-out: SharedWidgets_ClassicTheme.lua owns the canonical implementation.
if not ns.UI_CanApplyCustomChrome then
    function ns.UI_CanApplyCustomChrome(frame)
        if not frame then return false end
        if frame._wnBlizzardButton or frame._wnBlizzardChrome or frame._wnBlizzardScroll
            or frame._wnBlizzardEditBox or frame._wnBlizzardSlider or frame._wnClassicIconWell then
            return false
        end
        if frame._wnSkipCustomChrome then
            return false
        end
        return true
    end
end

--- Flat panel: WHITE8x8 fill only, no nested border textures.
---@param frame Frame
---@param bgColor table|nil
---@param opts table|nil `{ surfaceTier, bgType }`
local function ApplyBorderlessSurface(frame, bgColor, opts)
    if not frame then return end

    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then
        return
    end

    if IsClassicModeEnabled() and ns.UI_ApplyClassicInteriorFlatFill then
        ns.UI_ApplyClassicInteriorFlatFill(frame, bgColor or { 0, 0, 0, 0 })
        if not frame._borderRegistered and ns.BORDER_REGISTRY then
            frame._borderRegistered = true
            table.insert(ns.BORDER_REGISTRY, frame)
        end
        return
    end

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
ns.UI_ResolveSurfaceTierColor = ResolveSurfaceTierColor

--- Root shell only (`WarbandNexusFrame`): full-bleed color fill — no `BackdropTemplate` / backdrop insets (avoids side gutters).
local function ApplyMainWindowShellFill(frame, bgColor, borderColor)
    if not frame then return end

    if IsClassicModeEnabled() and ns.UI_ApplyBlizzardDialogBackdrop then
        local c = bgColor
            or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bgCard)
            or (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
            or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.bg)
            or (COLORS and COLORS.bg)
            or { 0.065, 0.065, 0.075, 1 }
        local fillAlpha = ResolveShellBackgroundFillAlpha()
        local tex = frame._wnShellFill
        if not tex then
            tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
            frame._wnShellFill = tex
        end
        SyncMainShellFlatFillAnchors(frame, tex)
        tex:SetColorTexture(c[1], c[2], c[3], fillAlpha)
        tex:Show()

        local chrome = frame._wnClassicShellChrome
        if not chrome then
            chrome = CreateFrame("Frame", nil, frame)
            frame._wnClassicShellChrome = chrome
            chrome:SetAllPoints()
            chrome:SetFrameLevel(math.max(1, (frame:GetFrameLevel() or 0) + 1))
        end
        chrome:Show()
        -- Border chrome only: Blizzard dialog bg tile is semi-transparent; flat fill carries opacity.
        ns.UI_ApplyBlizzardDialogBackdrop(chrome, { 1, 1, 1, 0 })
        if frame._wnShellBorderOverlay and frame._wnShellBorderOverlay.Hide then
            frame._wnShellBorderOverlay:Hide()
        end
        if frame.SetBackdrop then
            pcall(frame.SetBackdrop, frame, nil)
        end
        frame._bgType = "bg"
        frame._bgAlpha = fillAlpha
        frame._wnMainShellBackdrop = true
        frame._wnBorderlessSurface = true
        if not frame._borderRegistered and ns.BORDER_REGISTRY then
            frame._borderRegistered = true
            table.insert(ns.BORDER_REGISTRY, frame)
        end
        return
    end

    if frame._wnClassicShellChrome and frame._wnClassicShellChrome.Hide then
        frame._wnClassicShellChrome:Hide()
    end

    local c = bgColor or (COLORS and COLORS.bg) or { 0.042, 0.042, 0.055, 1 }
    local fillAlpha = ResolveShellBackgroundFillAlpha()
    local tex = frame._wnShellFill
    if not tex then
        tex = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._wnShellFill = tex
    end
    SyncMainShellFlatFillAnchors(frame, tex)
    tex:SetColorTexture(c[1], c[2], c[3], fillAlpha)
    tex:Show()
    if frame.SetBackdrop then
        pcall(frame.SetBackdrop, frame, nil)
    end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local borderA = shell.MAIN_SHELL_FRAME_BORDER_ALPHA or 1
    local border = borderColor or ThemeAPI.GetAccentBorderRGBA(borderA)
    HideFrameBorderQuartet(frame)
    EnsureShellBorderOverlay(frame, border)
    frame._wnMainShellBackdrop = true
    frame._wnBorderlessSurface = true
    frame._bgType = "bg"
    frame._bgAlpha = fillAlpha
end

ns.UI_GetShellBackgroundOpacity = GetShellBackgroundOpacity
ns.UI_ApplyMainWindowShellBorderQuartet = ApplyMainWindowShellBorderQuartet

--- Legacy name: routes to flat fill (no `BackdropTemplate`).
local function ApplyMainWindowShellBackdrop(frame, bgColor, borderColor)
    ApplyMainWindowShellFill(frame, bgColor, borderColor)
end

-- Export to namespace
ns.UI_ApplyVisuals = ApplyVisuals
ns.UI_ApplyMainWindowShellFill = ApplyMainWindowShellFill
ns.UI_ApplyMainWindowShellBackdrop = ApplyMainWindowShellBackdrop

-- Sub-tab bar + main tab layout metrics / scroll column sync: SharedWidgets_TabLayout.lua

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
                local okMeta, meta = pcall(C_tex.GetAtlasInfo, name)
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
    if not frame or not COLORS then return end
    if IsClassicModeEnabled() then
        if ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(frame)
        elseif ns.UI_ApplyBlizzardPanelBackdrop then
            local cardBg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
            ns.UI_ApplyBlizzardPanelBackdrop(frame, cardBg)
        end
        frame._wnBorderlessSurface = nil
        if frame._wnCardTopHighlight and frame._wnCardTopHighlight.Hide then
            frame._wnCardTopHighlight:Hide()
        end
        if frame._wnCardBottomShade and frame._wnCardBottomShade.Hide then
            frame._wnCardBottomShade:Hide()
        end
        return
    end
    if not ApplyVisuals then return end
    local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
    ApplyVisuals(frame, bg, ThemeAPI.GetAccentBorderRGBA(0.55))
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
    if not frame or not COLORS then return end
    if IsClassicModeEnabled() then
        if ns.UI_ApplyClassicOpaqueCardSurface then
            ns.UI_ApplyClassicOpaqueCardSurface(frame)
        elseif ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(frame)
        end
        frame._wnStandardTabTitleCard = true
        frame._wnBorderlessSurface = false
        if frame._wnCardTopHighlight and frame._wnCardTopHighlight.Hide then
            frame._wnCardTopHighlight:Hide()
        end
        if frame._wnCardBottomShade and frame._wnCardBottomShade.Hide then
            frame._wnCardBottomShade:Hide()
        end
        return
    end
    if not ApplyVisuals then return end
    if IsLightModeEnabled() then
        local bg = COLORS.surfaceViewport or COLORS.bg
        ApplyVisuals(frame, bg, ThemeAPI.GetAccentBorderRGBA(0.55))
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

--- Opaque interior under tooltip chrome (dialog-box bg tile is semi-transparent; see ApplyMainWindowShellFill).
---@param frame Frame|nil
---@param bgColor table|nil rgba
local function ApplyTooltipShellInteriorFill(frame, bgColor)
    if not frame then return end
    local c = bgColor
    if not c and ThemeAPI.GetTooltipShellBackdrop then
        c = select(1, ThemeAPI.GetTooltipShellBackdrop())
    end
    if ns.UI_ApplyClassicCardInteriorOpaqueFill then
        ns.UI_ApplyClassicCardInteriorOpaqueFill(frame, c)
    end
    frame._wnTooltipShellFill = true
end

--- Custom tooltip card shell — always paints a visible backdrop (classic panel or elevated card).
---@param frame Frame|nil
local function ApplyTooltipShellChrome(frame)
    if not frame then return end
    local bg, border = ThemeAPI.GetTooltipShellBackdrop()
    local opaqueBg = { bg[1], bg[2], bg[3], 1 }
    if IsClassicModeEnabled() and ns.UI_ApplyClassicCardPanelChrome then
        ns.UI_ApplyClassicCardPanelChrome(frame)
        ApplyTooltipShellInteriorFill(frame, opaqueBg)
        frame._wnBorderlessSurface = nil
        frame._wnTooltipShell = true
        return
    end
    if ApplyVisuals then
        ApplyVisuals(frame, opaqueBg, border)
        frame._wnBorderlessSurface = nil
    end
    frame._wnTooltipShell = true
end
ns.UI_ApplyTooltipShellChrome = ApplyTooltipShellChrome

--- Apply detail container styling (bg + accent border) using the shared 4-texture border system.
--- Use for Collections right panel (viewer/detail), or any "detail" panel that should match.
function ns.UI_ApplyDetailContainerVisuals(frame)
    if not frame then return end
    if IsClassicModeEnabled() and ns.UI_ApplyClassicCardPanelChrome then
        ns.UI_ApplyClassicCardPanelChrome(frame)
        return
    end
    local colors = GetColors and GetColors() or COLORS or ns.UI_COLORS
    if not colors or not colors.accent then return end
    local bg = colors.bgCard or colors.bgLight or colors.bg
    ApplyVisuals(frame, { bg[1], bg[2], bg[3], (bg[4] or 1) * 0.95 }, ThemeAPI.GetAccentBorderRGBA(0.55))
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
    if IsClassicModeEnabled() then
        local annex = scrollParent._wnResultsAnnexSheet
        if annex and annex.Hide then
            annex:Hide()
        end
        return
    end
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
    if IsClassicModeEnabled() or (ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()) then
        if fill and fill.Hide then
            fill:Hide()
        end
        return
    end
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
    if ns.UI_SyncMainScrollBarColumns then
        ns.UI_SyncMainScrollBarColumns(mainFrame)
    end
    local Factory = ns.UI and ns.UI.Factory
    if Factory and Factory.UpdateScrollBarVisibility then
        Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    if Factory and Factory.UpdateHorizontalScrollBarVisibility then
        Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
    end
    if Factory and Factory.DeferScrollBarVisibility then
        Factory:DeferScrollBarVisibility(mainFrame.scroll)
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
    if IsClassicModeEnabled() then
        annex:Hide()
        return
    end
    local c = ResolveSurfaceTierColor("viewport")
    annex._wnAnnexTex:SetColorTexture(c[1], c[2], c[3], c[4] or 0.98)
end

--- Re-anchor annex after PopulateContent sets scrollChild height.
function ns.UI_RefreshScrollAnnexLayout(scrollParent)
    if not scrollParent then return end
    if IsClassicModeEnabled() then
        local annex = scrollParent._wnResultsAnnexSheet
        if annex and annex.Hide then
            annex:Hide()
        end
        return
    end
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
    
    if IsClassicModeEnabled() and ns.UI_ApplyClassicCardPanelChrome then
        ns.UI_ApplyClassicCardPanelChrome(card)
    elseif IsClassicModeEnabled() and ns.UI_ApplyBlizzardPanelBackdrop then
        local cardBg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
        ns.UI_ApplyBlizzardPanelBackdrop(card, cardBg)
    elseif ns.UI_ApplyStandardCardElevatedChrome then
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
            newScroll = PixelSnap(newScroll, ancestor)
            pcall(ancestor.SetVerticalScroll, ancestor, newScroll)
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


-- Header icon system / standard tab title card / title toolbar: SharedWidgets_TitleCard.lua

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
    if IsClassicModeEnabled() then
        local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(width or 100, UI_CONSTANTS.BUTTON_HEIGHT)
        btn:SetText(text or "")
        btn._wnBlizzardButton = true
        if ns.UI_NormalizeBlizzardButtonChrome then
            ns.UI_NormalizeBlizzardButtonChrome(btn)
        end
        return btn
    end

    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 100, UI_CONSTANTS.BUTTON_HEIGHT)

    local idleBg = ThemeAPI.GetControlChromeBackdrop()
    ApplyVisuals(btn, idleBg, ThemeAPI.GetAccentBorderRGBA(0.6))

    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(btn)
    end

    local btnText = FontManager:CreateFontString(btn, UIFontRole("searchButtonText"), "OVERLAY")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText
    ns.UI_SetTextColorRole(btnText, "Bright")

    btn:SetScript("OnEnter", function(self)
        ApplyVisuals(self, ThemeAPI.GetControlChromeHoverBackdrop(), ThemeAPI.GetAccentBorderRGBA(0.8))
    end)
    btn:SetScript("OnLeave", function(self)
        ApplyVisuals(self, ThemeAPI.GetControlChromeBackdrop(), ThemeAPI.GetAccentBorderRGBA(0.6))
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
    local toggleBg = ThemeAPI.GetControlChromeBackdrop()
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

    if IsClassicModeEnabled() then
        local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        if initialState then
            checkbox:SetChecked(true)
        else
            checkbox:SetChecked(false)
        end
        checkbox._wnBlizzardCheckbox = true
        return checkbox
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

    if IsClassicModeEnabled() then
        local radioButton = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
        -- Indicator only: the option row button owns the click; keep template art untouched.
        radioButton:EnableMouse(false)
        radioButton:SetChecked(isSelected and true or false)
        if radioButton.text then
            radioButton.text:SetText("")
        end
        radioButton._wnSkipCustomChrome = true
        -- innerDot/checkTexture proxy keeps the Frame+dot caller API (SetShown/Show/Hide).
        local dot = {}
        dot.SetShown = function(_, shown) radioButton:SetChecked(shown and true or false) end
        dot.Show = function() radioButton:SetChecked(true) end
        dot.Hide = function() radioButton:SetChecked(false) end
        radioButton.innerDot = dot
        radioButton.checkTexture = dot
        return radioButton
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
    if not name or (issecretvalue and issecretvalue(name)) or name == "" then
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

-- Lowercase character name -> class token (`false` = stored without a resolvable class), built once
-- per roster (2026-10-22): the lookup used to lowercase every stored name on every call, and the
-- achievement rows call it per visible completed row on each paint. Dropped on roster messages and
-- when db.global.characters is replaced. Tokens (not hex) are cached so theme switches stay live.
ns.UI_WarbandClassTokenCache = { map = nil, src = nil }

function ns.UI_InvalidateWarbandClassTokenCache()
    ns.UI_WarbandClassTokenCache.map = nil
end

if WarbandNexus and WarbandNexus.RegisterMessage and E then
    local classTokenCacheListener = {}
    WarbandNexus.RegisterMessage(classTokenCacheListener, E.CHARACTER_UPDATED, ns.UI_InvalidateWarbandClassTokenCache)
    WarbandNexus.RegisterMessage(classTokenCacheListener, E.CHARACTER_TRACKING_CHANGED, ns.UI_InvalidateWarbandClassTokenCache)
end

--- `|cffrrggbb` prefix for `displayName` using `db.global.characters` (case-insensitive name; `classFile`, `classID`, or localized `class`).
---@return string
function ns.UI_GetClassColorHexForWarbandCharacter(displayName)
    if not displayName or (issecretvalue and issecretvalue(displayName)) or displayName == "" then
        return "|cffaaaaaa"
    end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local chars = db and db.characters
    if type(chars) ~= "table" then
        return "|cffaaaaaa"
    end
    local cache = ns.UI_WarbandClassTokenCache
    local map = cache.map
    if not map or cache.src ~= chars then
        map = {}
        for _, charData in pairs(chars) do
            local name
            if type(charData) == "table" then name = charData.name end
            if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then
                local lower = name:lower()
                -- First stored match wins, as the linear scan did.
                if map[lower] == nil then
                    map[lower] = ResolveClassFileTokenFromCharData(charData) or false
                end
            end
        end
        cache.map = map
        cache.src = chars
    end
    local token = map[displayName:lower()]
    if token then
        return "|cff" .. GetClassColorHexForSurface(token)
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


-- Try count popup (Plans / Collections / Tracker): SharedWidgets_TryCountPopup.lua

-- Settings sections / module, reset-timer, DB badge and loading state cards: SharedWidgets_StateCards.lua

