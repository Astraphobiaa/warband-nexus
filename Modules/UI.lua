--[[
    Warband Nexus - UI Module
    Main window shell, tab routing, and debounced WN_* refresh listeners.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- UIShell table early so UI_MainShell / UI_TabHost satellites can attach (bind filled before stubs).
ns.UIShell = ns.UIShell or {}
ns.UIShell._uiChildEnumScratch = ns.UIShell._uiChildEnumScratch or {}
ns.UIShell._uiRegionEnumScratch = ns.UIShell._uiRegionEnumScratch or {}

-- FontManager is lazy-loaded to prevent initialization errors
local FontManager  -- Will be set on first access
local L = ns.L

local issecretvalue = issecretvalue

-- Unique AceEvent handler identity for UI.lua
-- AceEvent uses events[eventname][self] = handler, so each module needs a unique
-- 'self' table to prevent overwriting other modules' handlers for the same event.
local UIEvents = {}

local function SyncMainWindowVisibilityState(visible)
    ns._wnMainWindowVisible = visible == true
    local C = ns.Constants
    local ev = C and C.EVENTS and C.EVENTS.MAIN_WINDOW_VISIBILITY_CHANGED
    if ev and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(ev, { visible = visible == true })
    end
end

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

--- SavedVars may use strict booleans or legacy `1`; match Settings checkboxes reliably.
local function ProfileFlagOn(v)
    return v == true or v == 1
end

--- Main-tab perf timings: debugMode + profilerPersist.tabPerfMonitor (not trace-window alone).
local function IsTabPerfMonitorEnabled()
    local p = WarbandNexus.db and WarbandNexus.db.profile
    if not p or not ProfileFlagOn(p.debugMode) then return false end
    local pp = p.profilerPersist
    return pp and ProfileFlagOn(pp.tabPerfMonitor) or false
end

ns.IsTabPerfMonitorEnabled = IsTabPerfMonitorEnabled

--- Log partial tab refresh
function ns.EmitPartialTabRefreshPerf(mainTab, fromKey, toKey, bodyMs, wallStart)
    if not IsTabPerfMonitorEnabled() then return end
    if not mainTab or not toKey then return end
    bodyMs = bodyMs or 0
    local P = ns.Profiler
    if not P or not P.ScheduleTabSwitchPerfTrace then return end
    P:ScheduleTabSwitchPerfTrace({
        fromTab = tostring(mainTab) .. ":" .. tostring(fromKey or "?"),
        toTab = tostring(mainTab) .. ":" .. tostring(toKey),
        poolMs = 0,
        populateMs = bodyMs,
        wallStart = wallStart or GetTime(),
        gen = nil,
    })
end

-- Lazy-load FontManager (prevent race conditions)
local function GetFontManager()
    if not FontManager then
        FontManager = ns.FontManager
        if not FontManager then
            error("FontManager not available in namespace!")
        end
    end
    return FontManager
end

-- Import shared UI components from SharedWidgets
local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local ReleasePooledRowsInSubtree = ns.UI_ReleasePooledRowsInSubtree
local ReleaseCharacterRowsFromSubtree = ns.UI_ReleaseCharacterRowsFromSubtree
local ReleaseReputationRowsFromSubtree = ns.UI_ReleaseReputationRowsFromSubtree
local ReleaseCurrencyRowsFromSubtree = ns.UI_ReleaseCurrencyRowsFromSubtree
local CreateThemedButton = ns.UI_CreateThemedButton
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor

--- Canonical tab order: `ns.UI_MAIN_TAB_ORDER` in SharedWidgets.lua â€” must precede timers that reference it (Lua local scope).
--- Canonical tab order (deferred tab label pass iterates this list).
local MAIN_TAB_ORDER = ns.UI_MAIN_TAB_ORDER or {
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

--- Horizontal `top` nav: first-tab inset (must match anchoring inside `UpdateTabVisibility`).
local MAIN_TAB_STRIP_EDGE_INSET = 10

--- Main-window chrome: packaged **`Media/icon.tga`** (`ns.WARBAND_ADDON_MEDIA_ICON`). Extension-less paths broke minimap/Easy Access on some builds.
function ns.UI_ApplyMainWindowTitleIcon(tex)
    if not tex then return end
    tex:SetBlendMode("BLEND")
    tex:SetVertexColor(1, 1, 1, 1)
    tex:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")
    if tex.SetDesaturated then
        tex:SetDesaturated(false)
    end
end

--- Header utility glyphs from packaged SVG-derived TGAs (`Media/Icon-*.tga`).
function ns.UI_SetMainChromeIcon(tex, iconKey, vertexColor)
    if not tex or not iconKey or not ns.UI_SetWnIconTexture then return false end
    return ns.UI_SetWnIconTexture(tex, iconKey, { vertexColor = vertexColor or { 1, 1, 1, 1 } })
end

--- Re-apply muted/desaturated header utility icons after theme refresh.
function ns.UI_RefreshHeaderUtilityIcons(mainFrame)
    if not mainFrame then return end
    local apply = ns.UI_ApplyHeaderUtilityIconStyle
    if not apply then return end
    if mainFrame.reloadDebugBtn and mainFrame.reloadDebugBtn._wnUtilityIcon then
        apply(mainFrame.reloadDebugBtn._wnUtilityIcon, false)
    end
    if mainFrame.patreonBtn and mainFrame.patreonBtn._wnUtilityIcon then
        apply(mainFrame.patreonBtn._wnUtilityIcon, false)
    end
    if mainFrame.discordBtn and mainFrame.discordBtn._wnUtilityIcon then
        apply(mainFrame.discordBtn._wnUtilityIcon, false)
    end
    if mainFrame.statusIcon then
        if ns.UI_IsLightMode and ns.UI_IsLightMode() then
            apply(mainFrame.statusIcon, false)
        else
            mainFrame.statusIcon:SetDesaturated(false)
            mainFrame.statusIcon:SetVertexColor(0.35, 1, 0.45, 1)
        end
    end
end

--- Re-paint main shell chrome from live `ns.UI_COLORS` (theme / light mode / accent refresh).
local function RefreshMainShellChrome(mainFrame)
    if not mainFrame then return end
    local C = ns.UI_COLORS
    if not C then return end
    local accent = C.accent or { 0.4, 0.2, 0.58, 1 }
    local shellBg = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor()) or C.bg
    if ns.UI_ApplyMainWindowShellFill then
        ns.UI_ApplyMainWindowShellFill(mainFrame, shellBg)
    end
    if ns.UI_RaiseMainWindowShellBorderOverlay then
        ns.UI_RaiseMainWindowShellBorderOverlay(mainFrame)
    end
    local headerBg = (ns.UI_GetMainHeaderChromeColor and ns.UI_GetMainHeaderChromeColor())
        or C.surfaceHeaderChrome or C.bgLight
    local headerBorder = (ns.UI_GetMainHeaderBorderColor and ns.UI_GetMainHeaderBorderColor())
        or { accent[1], accent[2], accent[3], 0.8 }
    local isClassicChrome = (ns.UI_IsClassicMode and ns.UI_IsClassicMode())
        or (ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome())
    if mainFrame.header then
        if isClassicChrome and ns.UI_ApplyClassicInteriorFlatFill then
            ns.UI_ApplyClassicInteriorFlatFill(mainFrame.header, { 0, 0, 0, 0 })
        elseif ApplyVisuals then
            ApplyVisuals(mainFrame.header, headerBg, headerBorder)
        end
    end
    local railBg = (ns.UI_GetNavRailSurfaceBackdrop and ns.UI_GetNavRailSurfaceBackdrop()) or shellBg
    if mainFrame.navRail then
        if isClassicChrome and ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(mainFrame.navRail)
        elseif ns.UI_ApplyBorderlessSurface then
            local railOpts = { bgType = "bg" }
            ns.UI_ApplyBorderlessSurface(mainFrame.navRail, railBg, railOpts)
        end
    end
    local divColor = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor())
        or headerBorder
    if mainFrame._wnNavRailDivider then
        if isClassicChrome then
            mainFrame._wnNavRailDivider:Hide()
        else
            mainFrame._wnNavRailDivider:Show()
            local divColor = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor())
                or headerBorder
            mainFrame._wnNavRailDivider:SetColorTexture(divColor[1], divColor[2], divColor[3], divColor[4] or 1)
        end
    end
    if mainFrame._wnNavRailDividerClassic then
        if isClassicChrome then
            mainFrame._wnNavRailDividerClassic:Show()
        else
            mainFrame._wnNavRailDividerClassic:Hide()
        end
    end
    if mainFrame._wnNavRailFooterSep then
        if isClassicChrome then
            mainFrame._wnNavRailFooterSep:Hide()
        else
            mainFrame._wnNavRailFooterSep:SetColorTexture(divColor[1], divColor[2], divColor[3], divColor[4] or 1)
            mainFrame._wnNavRailFooterSep:Show()
        end
    end
    if mainFrame._wnNavRailSettingsAboutSep then
        if isClassicChrome then
            mainFrame._wnNavRailSettingsAboutSep:Hide()
        else
            mainFrame._wnNavRailSettingsAboutSep:SetColorTexture(divColor[1], divColor[2], divColor[3], divColor[4] or 1)
            mainFrame._wnNavRailSettingsAboutSep:Show()
        end
    end
    if mainFrame.tabButtons then
        for _, btn in pairs(mainFrame.tabButtons) do
            local sep = btn and btn._wnRailSepAbove
            if sep and sep.SetColorTexture then
                sep:SetColorTexture(divColor[1], divColor[2], divColor[3], divColor[4] or 1)
            end
        end
    end
    if isClassicChrome then
        if mainFrame.content and mainFrame.content.SetBackdropColor then
            mainFrame.content:SetBackdropColor(0, 0, 0, 0)
        end
        if mainFrame.viewportBorder then
            if mainFrame.viewportBorder.SetBackdropColor then
                mainFrame.viewportBorder:SetBackdropColor(0, 0, 0, 0)
            end
            local underlay = mainFrame.viewportBorder._wnViewportAtlasUnderlay
            if underlay and underlay.Hide then
                underlay:Hide()
            end
        end
        local sc = mainFrame.scrollChild
        if sc then
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
        if ns.UI_SyncMainScrollBarColumns then
            ns.UI_SyncMainScrollBarColumns(mainFrame)
        end
    else
        if mainFrame.content and mainFrame.content.SetBackdropColor then
            mainFrame.content:SetBackdropColor(shellBg[1], shellBg[2], shellBg[3], shellBg[4] or 0.98)
        end
        if mainFrame.viewportBorder and mainFrame.viewportBorder.SetBackdropColor then
            mainFrame.viewportBorder:SetBackdropColor(shellBg[1], shellBg[2], shellBg[3], shellBg[4] or 0.98)
        end
    end
    if mainFrame.footerTop then
        local footDiv = (ns.UI_GetFooterDividerColor and ns.UI_GetFooterDividerColor()) or divColor
        mainFrame.footerTop:SetColorTexture(footDiv[1], footDiv[2], footDiv[3], footDiv[4] or 0.28)
    end
    if mainFrame.footerLeftText then
        ns.UI_SetTextColorRole(mainFrame.footerLeftText, "Dim", 0.92)
    end
    if mainFrame.footerVersionText then
        ns.UI_SetTextColorRole(mainFrame.footerVersionText, "Muted", 0.95)
    end
    if mainFrame.trackingIconBack and mainFrame.trackingIconBack.SetBackdrop then
        pcall(mainFrame.trackingIconBack.SetBackdrop, mainFrame.trackingIconBack, nil)
    end
    local closeIdle = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop()
    local utilBorder = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor()) or headerBorder
    if closeIdle and ns.UI_ApplyVisuals then
        if mainFrame.closeBtn and ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(mainFrame.closeBtn) then
            ns.UI_ApplyVisuals(mainFrame.closeBtn, closeIdle, utilBorder)
        end
        if mainFrame.reloadDebugBtn and ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(mainFrame.reloadDebugBtn) then
            local hover = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or closeIdle
            ns.UI_ApplyVisuals(mainFrame.reloadDebugBtn, hover, utilBorder)
        end
        if mainFrame.patreonBtn and ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(mainFrame.patreonBtn) then
            ns.UI_ApplyVisuals(mainFrame.patreonBtn, closeIdle, utilBorder)
        end
        if mainFrame.discordBtn and ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(mainFrame.discordBtn) then
            ns.UI_ApplyVisuals(mainFrame.discordBtn, closeIdle, utilBorder)
        end
    end
    if ns.UI_ApplyMainShellLayout then
        ns.UI_ApplyMainShellLayout(mainFrame)
    end
end
ns.UI_RefreshMainShellChrome = RefreshMainShellChrome

local ApplyMainNavGoldenShellLayout

--- Anchor header / nav / content / footer to MAIN_SHELL interior rect (all theme modes).
local function ApplyMainShellLayout(f)
    if not f then return end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local insetL, insetR, insetT, insetB = 0, 0, 0, 0
    if ns.UI_GetMainShellFrameInsets then
        insetL, insetR, insetT, insetB = ns.UI_GetMainShellFrameInsets()
    else
        insetL = shell.FRAME_CONTENT_INSET or 0
        insetR = insetL
        insetT = insetL
        insetB = shell.FRAME_CONTENT_INSET_BOTTOM or insetL
    end
    f._wnShellInsetL = insetL
    f._wnShellInsetR = insetR
    f._wnShellInsetT = insetT
    f._wnShellInsetB = insetB

    local headerNavGap = shell.HEADER_TO_NAV_GAP or 4
    local isClassicShellLayout = (ns.UI_IsClassicMode and ns.UI_IsClassicMode())
        or (ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome())
    if isClassicShellLayout then
        headerNavGap = 0
    end
    local MAIN_FOOTER_H = shell.FOOTER_HEIGHT or 26
    local FOOTER_BOTTOM_OFFSET = shell.FOOTER_BOTTOM_OFFSET or 4
    local CONTENT_GAP_ABOVE_FOOTER = shell.CONTENT_GAP_ABOVE_FOOTER or 0
    local contentBottomOffset = FOOTER_BOTTOM_OFFSET + MAIN_FOOTER_H + CONTENT_GAP_ABOVE_FOOTER + insetB
    f._wnContentBottomOffset = contentBottomOffset

    if f.header then
        f.header:ClearAllPoints()
        f.header:SetPoint("TOPLEFT", f, "TOPLEFT", insetL, -insetT)
        f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -insetR, -insetT)
    end

    local RAIL_CONTENT_GAP = shell.NAV_RAIL_CONTENT_GAP or 10
    local bodyBandAnchor = f.header or f
    local bodyBandGap = -headerNavGap
    if f._wnMainNavLayout == "rail" and f.navRail then
        f.navRail:ClearAllPoints()
        f.navRail:SetPoint("TOPLEFT", bodyBandAnchor, "BOTTOMLEFT", 0, bodyBandGap)
        f.navRail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", insetL, contentBottomOffset)
        ApplyMainNavGoldenShellLayout(f)
    elseif f.nav and f._wnMainNavLayout ~= "rail" then
        f.nav:ClearAllPoints()
        f.nav:SetPoint("TOPLEFT", bodyBandAnchor, "BOTTOMLEFT", 0, bodyBandGap)
        f.nav:SetPoint("TOPRIGHT", bodyBandAnchor, "BOTTOMRIGHT", 0, bodyBandGap)
    end

    if f.content then
        f.content:ClearAllPoints()
        if f._wnMainNavLayout == "rail" and f.navRail then
            f.content:SetPoint("TOPLEFT", f.navRail, "TOPRIGHT", RAIL_CONTENT_GAP, 0)
            f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR, contentBottomOffset)
        elseif f.nav then
            local bodyPad = shell.CONTENT_PAD_X or 8
            f.content:SetPoint("TOPLEFT", f.nav, "BOTTOMLEFT", bodyPad, -bodyPad)
            f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -insetR - bodyPad, contentBottomOffset)
        end
    end

    if f.footerBar then
        local footerLaneReserve = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
            or (((ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26) + 2)
        f.footerBar:ClearAllPoints()
        f.footerBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", insetL + 8, insetB + (FOOTER_BOTTOM_OFFSET or 4))
        f.footerBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(insetR + footerLaneReserve), insetB + (FOOTER_BOTTOM_OFFSET or 4))
    end

    if f.resizeGrip then
        local gripInsetX = shell.RESIZE_GRIP_INSET_X or 4
        local gripInsetY = shell.RESIZE_GRIP_INSET_Y or 4
        f.resizeGrip:ClearAllPoints()
        f.resizeGrip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(insetR + gripInsetX), insetB + gripInsetY)
    end
end
ns.UI_ApplyMainShellLayout = ApplyMainShellLayout
---@deprecated use UI_ApplyMainShellLayout
ns.UI_ApplyMainShellInsetLayout = ApplyMainShellLayout

--- Golden-ratio rail width + strip/button sync (text rail below header).
function ApplyMainNavGoldenShellLayout(f)
    if not f or f._wnMainNavLayout ~= "rail" or not f.navRail then return end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local insetL, insetR = 0, 0
    if ns.UI_GetMainShellFrameInsets then
        insetL, insetR = ns.UI_GetMainShellFrameInsets()
    else
        local inset = shell.FRAME_CONTENT_INSET or 6
        insetL, insetR = inset, inset
    end
    local innerW = math.max(360, (f:GetWidth() or 800) - insetL - insetR)
    local railW = (ns.UI_ComputeGoldenRailWidth and ns.UI_ComputeGoldenRailWidth(innerW, shell))
        or shell.NAV_RAIL_WIDTH or 168
    f.navRail:SetWidth(railW)
    f._wnGoldenRailWidth = railW

    local pad = shell.NAV_RAIL_PAD or 6
    local stripW = math.max(80, railW - pad * 2)
    if f.navRailStrip then
        f.navRailStrip:SetWidth(stripW)
    end
    if f.tabButtons then
        for ti = 1, #MAIN_TAB_ORDER do
            local btn = f.tabButtons[MAIN_TAB_ORDER[ti]]
            if btn and btn._wnRailTextMode then
                btn:SetWidth(stripW)
            end
        end
    end
    if f.navSettingsBtn and f.navSettingsBtn._wnRailTextMode then
        f.navSettingsBtn:SetWidth(stripW)
    end
    if f.navAboutBtn and f.navAboutBtn._wnRailTextMode then
        f.navAboutBtn:SetWidth(stripW)
    end
end

---Expand hit target and show tooltip on main nav tab buttons (rail + top strip).
---@param btn Button
---@param tooltipTitle string|nil
---@param tooltipHint string|nil
local function WireMainNavTabButtonUX(btn, tooltipTitle, tooltipHint)
    if not btn then return end
    if btn.RegisterForClicks then
        btn:RegisterForClicks("LeftButtonUp")
    end
    if btn.SetHitRectInsets then
        btn:SetHitRectInsets(-3, -3, -2, -2)
    end
    if not tooltipTitle or tooltipTitle == "" then return end
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipTitle, 1, 1, 1)
        if tooltipHint and tooltipHint ~= "" then
            GameTooltip:AddLine(tooltipHint, 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function RefreshMainNavRailStrip(f)
    if not f or f._wnMainNavLayout ~= "rail" then return end
    ApplyMainNavGoldenShellLayout(f)
    local scroll = f.navRailScroll
    local strip = f.navRailStrip
    if not scroll or not strip or not f.tabButtons then return end

    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local vGap = f._wnNavTabVGap or shell.NAV_RAIL_TAB_V_GAP or 4
    local topInset = f._wnNavRailTopInset or shell.NAV_RAIL_TOP_INSET or 6
    local tabH = shell.NAV_RAIL_TAB_HEIGHT or 34
    local pad = shell.NAV_RAIL_PAD or 6
    local railW = f._wnGoldenRailWidth or (f.navRail and f.navRail:GetWidth()) or shell.NAV_RAIL_WIDTH or 168
    local stripW = math.max(80, railW - pad * 2)

    local h = topInset
    local prevShown = nil
    for ti = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[ti]
        local btn = f.tabButtons[key]
        if btn and btn:IsShown() then
            if btn._wnRailTextMode then
                btn:SetWidth(stripW)
            end
            if prevShown then
                local sepH = shell.NAV_RAIL_TAB_SEP_HEIGHT or 1
                h = h + vGap + sepH
            end
            h = h + (btn:GetHeight() or tabH)
            prevShown = true
        end
    end
    h = h + topInset
    local scrollBottomGap = shell.NAV_RAIL_SCROLL_BOTTOM_GAP or 6
    h = h + scrollBottomGap

    local viewH = scroll:GetHeight()
    if (not viewH) or viewH <= 0 then
        viewH = 1
    end
    strip:SetWidth(stripW)
    strip:SetHeight(math.max(h, viewH))

    local maxScroll = strip:GetHeight() - viewH
    if maxScroll < 0 then
        maxScroll = 0
    end
    local cur = scroll:GetVerticalScroll() or 0
    if cur > maxScroll then
        scroll:SetVerticalScroll(maxScroll)
    end
end

local function RefreshMainNavTabStrip(f)
    if not f or f._wnMainNavLayout ~= "top" then return end
    local scroll = f.tabNavScroll
    local strip = f.tabNavStrip
    if not scroll or not strip or not f.tabButtons then return end

    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local TAB_GAP_H = shell.TAB_GAP or 5
    local navH = (f.nav and f.nav:GetHeight()) or shell.NAV_BAR_HEIGHT or 36
    strip:SetHeight(navH)

    local w = MAIN_TAB_STRIP_EDGE_INSET
    local prevShown = nil
    for ti = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[ti]
        local btn = f.tabButtons[key]
        if btn and btn:IsShown() then
            if prevShown then
                w = w + TAB_GAP_H
            end
            w = w + (btn:GetWidth() or shell.DEFAULT_TAB_WIDTH or 108)
            prevShown = true
        end
    end
    w = w + MAIN_TAB_STRIP_EDGE_INSET

    local viewW = scroll:GetWidth()
    if (not viewW) or viewW <= 0 then
        viewW = 1
    end
    --- At least viewport width keeps left-anchored tabs stable in a wide shell.
    strip:SetWidth(math.max(w, viewW))

    local maxScroll = strip:GetWidth() - viewW
    if maxScroll < 0 then
        maxScroll = 0
    end
    local cur = scroll:GetHorizontalScroll() or 0
    if cur > maxScroll then
        scroll:SetHorizontalScroll(maxScroll)
    end
end

local function RefreshMainNavLayout(f)
    if not f then return end
    if f._wnMainNavLayout == "rail" then
        RefreshMainNavRailStrip(f)
    else
        RefreshMainNavTabStrip(f)
    end
end

local function ScrollMainNavEnsureTabVisible(f, tabKey)
    if not f or not tabKey then return end

    if f._wnMainNavLayout == "rail" then
        local scroll = f.navRailScroll
        local btn = f.tabButtons and f.tabButtons[tabKey]
        if not scroll or not btn or not btn:IsShown() then return end

        local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
        local vGap = f._wnNavTabVGap or shell.NAV_RAIL_TAB_V_GAP or 4
        local topInset = f._wnNavRailTopInset or shell.NAV_RAIL_TOP_INSET or 6
        local tabH = shell.NAV_RAIL_TAB_HEIGHT or 28
        local pad = 6
        local y = topInset
        for ti = 1, #MAIN_TAB_ORDER do
            local k = MAIN_TAB_ORDER[ti]
            local b = f.tabButtons[k]
            if b and b:IsShown() then
                if k == tabKey then
                    break
                end
                y = y + (b:GetHeight() or tabH) + vGap
            end
        end

        local btnH = btn:GetHeight() or tabH
        local viewH = scroll:GetHeight() or 0
        local vs = scroll:GetVerticalScroll() or 0
        if y - pad < vs then
            vs = y - pad
        end
        if y + btnH + pad > vs + viewH then
            vs = y + btnH + pad - viewH
        end

        local strip = f.navRailStrip
        local stripH = (strip and strip:GetHeight()) or viewH
        local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()
            or math.max(stripH - viewH, 0)
        if vs < 0 then vs = 0 end
        if vs > range then vs = range end
        scroll:SetVerticalScroll(vs)
        return
    end

    if f._wnMainNavLayout ~= "top" then return end
    local scroll = f.tabNavScroll
    local btn = f.tabButtons and f.tabButtons[tabKey]
    if not scroll or not btn or not btn:IsShown() then return end

    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local TAB_GAP = shell.TAB_GAP or 5
    local pad = 8
    local x = MAIN_TAB_STRIP_EDGE_INSET
    for ti = 1, #MAIN_TAB_ORDER do
        local k = MAIN_TAB_ORDER[ti]
        local b = f.tabButtons[k]
        if b and b:IsShown() then
            if k == tabKey then
                break
            end
            x = x + b:GetWidth() + TAB_GAP
        end
    end

    local btnW = btn:GetWidth() or 0
    local viewW = scroll:GetWidth() or 0
    local hs = scroll:GetHorizontalScroll() or 0
    if x - pad < hs then
        hs = x - pad
    end
    if x + btnW + pad > hs + viewW then
        hs = x + btnW + pad - viewW
    end

    local stripW = (f.tabNavStrip and f.tabNavStrip:GetWidth()) or viewW
    local range = scroll.GetHorizontalScrollRange and scroll:GetHorizontalScrollRange()
        or math.max(stripW - viewW, 0)
    if hs < 0 then hs = 0 end
    if hs > range then hs = range end
    scroll:SetHorizontalScroll(hs)
end

ns.UI_RefreshMainNavTabStrip = RefreshMainNavLayout
ns.UI_ScrollMainNavEnsureTabVisible = ScrollMainNavEnsureTabVisible

--- Wall-time DrawTab trace (GetTime) when debug+verbose tab perf monitor is on; aligns with WN-PERF heavy-tab inventory.
local TAB_DRAW_PERF_TRACE = {
    chars = true,
    items = true,
    gear = true,
    currency = true,
    reputations = true,
    pve = true,
    professions = true,
    collections = true,
    plans = true,
    stats = true,
}

local format = string.format
local wipe = wipe
local debugprofilestart = debugprofilestart
local debugprofilestop = debugprofilestop

-- Reused buffers for frame child/region enumeration (one WoW API call per pack; avoids fresh tables each PopulateContent).
local _uiChildEnumScratch = ns.UIShell._uiChildEnumScratch
local _uiRegionEnumScratch = ns.UIShell._uiRegionEnumScratch
local function PackVariadicInto(dest, ...)
    wipe(dest)
    local n = select("#", ...)
    for i = 1, n do
        dest[i] = select(i, ...)
    end
    return n
end

-- Post-combat UI: single PLAYER_REGEN_ENABLED + one next-tick flush. Coalesces PopulateContent defer
-- and RefreshUI defer (previously two listeners could both call RefreshUI on the same regen edge).
local postCombatUIFrame = nil
local postCombatUITimer = nil

local function FlushPostCombatUI()
    if mainFrame and mainFrame:IsShown() and WarbandNexus.RefreshUI then
        WarbandNexus:RefreshUI()
    end
end

-- Coalesce event-driven PopulateContent with staged main-tab switch paint (see RunDebouncedPopulateTimerBody).
local SHELL_TAB_SWITCH_POPULATE_QUIET = 0.45

local function ShouldSkipRedundantShellPopulate(mf, forceRepaint)
    if forceRepaint or not mf then return false end
    local sh = mf._shellRefreshState
    if sh and sh.dirtyWhileHidden then return false end
    -- Tab switch paint while sync was still running may be partial â€” allow follow-up event populate.
    if mf._wnLoadingCompleteAtTabSwitch ~= true then return false end
    if not mf._wnLastMainTabSwitchAt or not mf._wnLastMainTabSwitchKey then return false end
    if mf._wnLastMainTabSwitchKey ~= mf.currentTab then return false end
    if mf._wnTabSwitchPopulateDoneGen ~= mf._tabSwitchGen then return false end
    if (GetTime() - mf._wnLastMainTabSwitchAt) >= SHELL_TAB_SWITCH_POPULATE_QUIET then return false end
    return true
end

local function ShouldSkipSyncCompletePopulate(mf)
    if not mf or not mf:IsShown() then return true end
    -- Loading was still in flight at tab switch: first paint may be partial â€” allow sync transition refresh.
    if mf._wnLoadingCompleteAtTabSwitch ~= true then return false end
    if mf._wnTabSwitchPopulateDoneGen ~= mf._tabSwitchGen then return false end
    if not mf._wnLastMainTabSwitchAt or mf._wnLastMainTabSwitchKey ~= mf.currentTab then return false end
    if (GetTime() - mf._wnLastMainTabSwitchAt) >= SHELL_TAB_SWITCH_POPULATE_QUIET then return false end
    return true
end

local function MarkShellPopulateCompleted(mf)
    if not mf then return end
    mf._wnTabSwitchPopulateDoneGen = mf._tabSwitchGen
    local sh = mf._shellRefreshState
    if sh then
        sh.lastEventPopulateTime = GetTime()
    end
end

local function ArmPostCombatUIRefresh()
    if not InCombatLockdown or not InCombatLockdown() then return end
    if not postCombatUIFrame then
        -- Intentionally raw: invisible PLAYER_REGEN_ENABLED listener only (no layout role).
        postCombatUIFrame = CreateFrame("Frame", nil, UIParent)
        postCombatUIFrame:Hide()
        postCombatUIFrame:SetScript("OnEvent", function(self, event)
            if event ~= "PLAYER_REGEN_ENABLED" then return end
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            self._wnPostCombatRegenArmed = nil
            if postCombatUITimer and postCombatUITimer.Cancel then
                postCombatUITimer:Cancel()
                postCombatUITimer = nil
            end
            if C_Timer and C_Timer.NewTimer then
                postCombatUITimer = C_Timer.NewTimer(0, function()
                    postCombatUITimer = nil
                    FlushPostCombatUI()
                end)
            elseif C_Timer and C_Timer.After then
                C_Timer.After(0, FlushPostCombatUI)
            else
                FlushPostCombatUI()
            end
        end)
    end
    if not postCombatUIFrame._wnPostCombatRegenArmed then
        postCombatUIFrame._wnPostCombatRegenArmed = true
        postCombatUIFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- Main window sizing: authoritative numbers live on `ns.UI_LAYOUT.MAIN_WINDOW` (SharedWidgets.lua).
local function GetMainWindowGeometryBounds()
    local screen = WarbandNexus:API_GetScreenInfo()
    local mw = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_WINDOW) or {}
    local minW, minH = WarbandNexus:API_GetMainWindowContentMinimums()
    local cw = mw.CLAMP_SCREEN_WIDTH_PCT or 0.95
    local ch = mw.CLAMP_SCREEN_HEIGHT_PCT or 0.95
    return minW, minH, math.floor(screen.width * cw), math.floor(screen.height * ch)
end

-- Window geometry helpers
local function GetWindowProfile()
    if not WarbandNexus.db or not WarbandNexus.db.profile then return nil end
    return WarbandNexus.db.profile
end

local function GetWindowDimensions()
    local minW, minH, maxW, maxH = GetMainWindowGeometryBounds()

    local profile = GetWindowProfile()
    if profile and profile.windowWidth then
        local savedWidth = profile.windowWidth
        local savedHeight = profile.windowHeight

        savedWidth = math.max(minW, math.min(savedWidth, maxW))
        savedHeight = math.max(minH, math.min(savedHeight, maxH))

        return savedWidth, savedHeight
    end

    local defaultWidth, defaultHeight =
        WarbandNexus:API_CalculateOptimalWindowSize(minW, minH)

    return defaultWidth, defaultHeight
end

--- Offsets (x, y) for `SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)` after layout settles.
--- Uses `Region:GetLeft` / `:GetTop`; same numeric space as that anchor chain (WoW anchors are UI-scale / widget-scale aware â€” see wiki `ScriptRegionResizing:SetPoint` Details).
--- This path does not multiply by `GetEffectiveScale`; conversions belong only next to APIs in pixel space (`GetCursorPosition` in drag), not alongside GetLeft/GetTop.
local function GetUIParentBOTTOMLEFTAnchorOffsets(frame)
    if not frame then return nil, nil end
    local left = frame:GetLeft()
    local top = frame:GetTop()
    if left == nil or top == nil then return nil, nil end
    return left, top
end

-- Save window position and size to DB.
-- Always uses absolute TOPLEFT/BOTTOMLEFT coordinates via GetLeft()/GetTop()
-- to avoid anchor point confusion after StartMoving/StopMovingOrSizing.
local function SaveWindowGeometry(frame)
    if not frame then return end
    local profile = GetWindowProfile()
    if not profile then return end
    
    -- Save size
    profile.windowWidth = frame:GetWidth()
    profile.windowHeight = frame:GetHeight()
    
    -- Save TOPLEFT offsets vs UIParent BOTTOMLEFT (anchor-independent reads).
    local left, top = GetUIParentBOTTOMLEFTAnchorOffsets(frame)
    if left and top then
        if not profile.windowPosition then
            profile.windowPosition = {}
        end
        profile.windowPosition.point = "TOPLEFT"
        profile.windowPosition.relativePoint = "BOTTOMLEFT"
        profile.windowPosition.x = left
        profile.windowPosition.y = top
    end
end

-- Restore window position from DB (returns true if restored, false for first-time)
local function RestoreWindowPosition(frame)
    local profile = GetWindowProfile()
    if not profile or not profile.windowPosition then return false end

    local pos = profile.windowPosition
    if not pos.x or not pos.y then return false end

    -- Validate position is on-screen (clamp to visible area)
    local screen = WarbandNexus:API_GetScreenInfo()
    local frameScale = frame:GetEffectiveScale() or 1
    local parentScale = UIParent:GetEffectiveScale() or 1
    if frameScale <= 0 then frameScale = 1 end
    if parentScale <= 0 then parentScale = 1 end
    
    -- Get screen dimensions in the frame's coordinate space
    -- screen.width/height are in UIParent's coordinate space.
    local screenWidthInFrameCoords = (screen.width * parentScale) / frameScale
    local screenHeightInFrameCoords = (screen.height * parentScale) / frameScale
    
    local frameW = frame:GetWidth() or 0
    local frameH = frame:GetHeight() or 0
    
    local x = math.max(0, math.min(pos.x, screenWidthInFrameCoords - frameW * 0.25))
    local y = math.max(frameH * 0.25, math.min(pos.y, screenHeightInFrameCoords))

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    return true
end

-- Custom drag: preserves the clicked point under the cursor (no StartMoving teleport).
-- StartMoving() uses the frame's anchor as handle, causing the window to "jump"
-- when clicking anywhere except TOPLEFT. This uses GetCursorPosition + OnUpdate instead.
local function StartCustomDrag(frame)
    if not frame or InCombatLockdown() then return end

    local cx, cy = GetCursorPosition()

    local left = frame:GetLeft()
    local top = frame:GetTop()
    if left == nil or top == nil then return end

    local frameScale = frame:GetEffectiveScale()
    if not frameScale or frameScale <= 0 then frameScale = 1 end

    local leftPx = left * frameScale
    local topPx = top * frameScale

    frame._dragOffsetX = cx - leftPx
    frame._dragOffsetY = cy - topPx
    frame._isCustomDragging = true

    frame:SetScript("OnUpdate", function(self)
        if not self._isCustomDragging then
            self:SetScript("OnUpdate", nil)
            return
        end
        local x, y = GetCursorPosition()
        local newLeftPx = x - self._dragOffsetX
        local newTopPx = y - self._dragOffsetY
        
        -- Convert physical pixels back to the frame's coordinate space
        local newLeft = newLeftPx / frameScale
        local newTop = newTopPx / frameScale
        
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", newLeft, newTop)
    end)
end

local function StopCustomDrag(frame)
    if not frame then return end
    frame._isCustomDragging = false
    frame._dragOffsetX = nil
    frame._dragOffsetY = nil
    frame:SetScript("OnUpdate", nil)
end

-- Re-anchor with TOPLEFT to UIParent BOTTOMLEFT using current GetLeft/GetTop.
-- Keeps a single anchor family after arbitrary drag/resize internals.
-- Defined before StartCustomResize (resize OnUpdate calls this).
local function NormalizeFramePosition(frame)
    if not frame or not frame.GetLeft or not frame.GetTop then return end
    local left, top = GetUIParentBOTTOMLEFTAnchorOffsets(frame)
    if left == nil or top == nil then return end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

--- Scale-aware BOTTOMRIGHT resize: keeps TOPLEFT anchor stable (avoids StartSizing cursor jump on scaled frames).
local function StartCustomResize(frame)
    if not frame or (InCombatLockdown and InCombatLockdown()) then return end
    NormalizeFramePosition(frame)
    local scale = frame:GetEffectiveScale()
    if not scale or scale <= 0 then scale = 1 end
    local cx, cy = GetCursorPosition()
    frame._resizeScale = scale
    frame._resizeStartCX = cx
    frame._resizeStartCY = cy
    frame._resizeOrigW = frame:GetWidth() or 0
    frame._resizeOrigH = frame:GetHeight() or 0
    frame._resizeActive = true
    frame._resizeCommitPending = nil
    frame._wnResizeLiveGen = (frame._wnResizeLiveGen or 0) + 1
    if frame.scrollChild and frame.scrollChild.GetWidth then
        frame._wnResizeFreezeScrollChildW = frame.scrollChild:GetWidth()
    end
    if ns.UI_CloseCharacterTabFlyoutMenus then
        ns.UI_CloseCharacterTabFlyoutMenus()
    end
    local LC = ns.UI_LayoutCoordinator
    if LC and LC.CancelAllTabLiveRelayoutTimers then
        LC:CancelAllTabLiveRelayoutTimers()
    end
    frame:SetScript("OnUpdate", function(self)
        if not self._resizeActive then
            self:SetScript("OnUpdate", nil)
            return
        end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            local finish = self._wnResizeFinishOnRelease
            if finish then
                finish()
            else
                StopCustomResize(self)
            end
            return
        end
        local x, y = GetCursorPosition()
        local sc = self._resizeScale or 1
        local dw = (x - (self._resizeStartCX or x)) / sc
        local dh = ((self._resizeStartCY or y) - y) / sc
        local minW, minH, maxW, maxH = GetMainWindowGeometryBounds()
        local nw = math.min(maxW, math.max(minW, (self._resizeOrigW or 0) + dw))
        local nh = math.min(maxH, math.max(minH, (self._resizeOrigH or 0) + dh))
        self:SetSize(nw, nh)
    end)
end

local function StopCustomResize(frame)
    if not frame then return end
    frame._resizeActive = false
    frame._resizeCommitPending = true
    frame._wnResizeLiveGen = (frame._wnResizeLiveGen or 0) + 1
    frame._resizeStartCX = nil
    frame._resizeStartCY = nil
    frame._resizeOrigW = nil
    frame._resizeOrigH = nil
    frame._resizeScale = nil
    frame:SetScript("OnUpdate", nil)
end

-- Reset window to default center position and size
local function ResetWindowGeometry(frame)
    if not frame then return end

    local minW, minH = WarbandNexus:API_GetMainWindowContentMinimums()
    local defaultWidth, defaultHeight =
        WarbandNexus:API_CalculateOptimalWindowSize(minW, minH)
    
    frame:ClearAllPoints()
    frame:SetPoint("CENTER")
    frame:SetSize(defaultWidth, defaultHeight)
    
    -- Clear saved position/size
    local profile = GetWindowProfile()
    if profile then
        profile.windowWidth = defaultWidth
        profile.windowHeight = defaultHeight
        profile.windowPosition = nil
    end
    
    UpdateScrollLayout(frame)
    WarbandNexus:PopulateContent()
end

--- Per-tab minimum scroll content width (viewport can be narrower; horizontal scroll instead of squeeze).
local tabMinScrollWidthFns = {}

---@param tabId string
---@param fn fun(): number|nil
function ns.UI_RegisterTabMinScrollWidth(tabId, fn)
    if tabId and type(fn) == "function" then
        tabMinScrollWidthFns[tabId] = fn
    end
end

-- Compute scrollChild logical width for the current tab.
-- Tabs with wide inline layouts enforce a minimum so horizontal scrollbar appears instead of squashed chrome.
local function ComputeScrollChildWidth(frame)
    if not frame or not frame.scroll then return 0 end
    local w = frame.scroll:GetWidth()
    local tab = frame.currentTab
    local regFn = tab and tabMinScrollWidthFns[tab]
    if regFn then
        local tabMin = regFn()
        if tabMin and tabMin > 0 then
            w = math.max(w, tabMin)
        end
    end
    if tab == "gear" then
        local gearMin = (ns.GearUI_GetGearTabMinScrollWidth and ns.GearUI_GetGearTabMinScrollWidth())
            or ns.MIN_GEAR_CARD_W
        if gearMin and gearMin > 0 then
            w = math.max(w, gearMin)
        end
    elseif tab == "professions" and ns.ComputeProfessionsGridWidth then
        local profW = ns.ComputeProfessionsGridWidth()
        if profW > 0 then w = math.max(w, profW) end
    elseif tab == "pve" then
        local painted = frame._pveMinScrollWidth
        if type(painted) == "number" and painted > 0 then
            w = math.max(w, painted)
        elseif ns.ComputePvEMinScrollWidth then
            local pveW = ns.ComputePvEMinScrollWidth(WarbandNexus)
            if pveW > 0 then w = math.max(w, pveW) end
        end
    elseif tab == "chars" then
        local minW = frame._charsMinScrollWidth
        if (not minW or minW < 1) and ns.UI_ComputeCharactersMinScrollWidth then
            local addon = WarbandNexus
            local guildW = addon and addon._charListMaxGuildWidth
            minW = ns.UI_ComputeCharactersMinScrollWidth(addon, guildW)
        end
        if minW and minW > 0 then
            w = math.max(w, minW)
        end
    elseif tab == "stats" and ns.ComputeStatisticsMinScrollWidth then
        local stW = ns.ComputeStatisticsMinScrollWidth()
        if stW > 0 then w = math.max(w, stW) end
    end
    return w
end

--- Live viewport width for LayoutCoordinator tab adapters (`scroll:GetWidth()`, not tab-min scrollChild).
local function GetScrollViewportWidth(frame)
    if ns.UI_GetMainScrollContentWidth then
        local w = ns.UI_GetMainScrollContentWidth(frame)
        if w and w > 0 then return w end
    end
    if frame and frame.scroll and frame.scroll.GetWidth then
        return frame.scroll:GetWidth() or 0
    end
    return 0
end

-- Update scrollChild and frozen column header widths in one call.
local function UpdateScrollLayout(frame)
    if not frame or not frame.scrollChild or not frame.scroll then return end
    if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(frame) then
        return
    end
    local w = ComputeScrollChildWidth(frame)
    frame.scrollChild:SetWidth(w)
    if frame.columnHeaderInner and frame.columnHeaderClip and frame.columnHeaderClip:GetHeight() > 1 then
        frame.columnHeaderInner:SetWidth(w)
    end
    if frame.currentTab == "professions" and ns.UI_RelayoutProfessionRowWidths and frame.scrollChild then
        ns.UI_RelayoutProfessionRowWidths(frame.scrollChild)
    end
    if ns.UI_SyncMainScrollBarColumns then
        ns.UI_SyncMainScrollBarColumns(frame)
    end
end

--- Re-anchor fixedHeader children (title cards, toolbars) after viewport width changes.
local function RefreshFixedHeaderChrome(frame)
    if not frame or not frame.fixedHeader then return end
    local fh = frame.fixedHeader
    local fhW = fh:GetWidth()
    if not fhW or fhW < 1 then return end
    local side = 12
    if ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(frame)
        if m and m.sideMargin then side = m.sideMargin end
    end
    local n = 0
    if fh.GetNumChildren then
        n = fh:GetNumChildren() or 0
    end
    for i = 1, n do
        local child = select(i, fh:GetChildren())
        if child and child.IsShown and child:IsShown() and child.GetPoint then
            local p1, rel1, rp1, x1, y1 = child:GetPoint(1)
            local p2, rel2, rp2, x2, y2 = child:GetPoint(2)
            if p1 == "TOPLEFT" and p2 == "TOPRIGHT" then
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", fh, "TOPLEFT", side, y1 or 0)
                child:SetPoint("TOPRIGHT", fh, "TOPRIGHT", -side, y2 or y1 or 0)
            elseif p1 == "TOPLEFT" and rel1 == fh and rp1 == "TOPLEFT" and x1 then
                child:ClearAllPoints()
                child:SetPoint("TOPLEFT", fh, "TOPLEFT", side, y1 or 0)
                if p2 == "TOPRIGHT" then
                    child:SetPoint("TOPRIGHT", fh, "TOPRIGHT", -side, y2 or y1 or 0)
                end
            end
        end
    end
end

ns.UI_RefreshFixedHeaderChrome = RefreshFixedHeaderChrome

--- Resize bounds honor `profile.mainWindowDensity`; clamps current footprint into [min,max] after prefs change.
function WarbandNexus:UI_ClampMainFrameResizeBoundsFromProfile()
    local mf = mainFrame or (self.UI and self.UI.mainFrame)
    if not mf then return end
    local minW, minH, maxW, maxH = GetMainWindowGeometryBounds()
    mf:SetResizeBounds(minW, minH, maxW, maxH)
    local cw, ch = mf:GetWidth() or minW, mf:GetHeight() or minH
    local nw = math.min(maxW, math.max(minW, cw))
    local nh = math.min(maxH, math.max(minH, ch))
    mf:SetSize(nw, nh)
    if ns.UI_ApplyMainShellLayout then
        ns.UI_ApplyMainShellLayout(mf)
    end
    UpdateScrollLayout(mf)
    ApplyMainNavGoldenShellLayout(mf)
    RefreshFixedHeaderChrome(mf)
    local LC = ns.UI_LayoutCoordinator
    if LC and LC.ForceMainFrameMetrics and mf:IsShown() then
        LC:ForceMainFrameMetrics(mf, "display_changed")
    end
end

local mainFrame = nil

--- True when `owner` belongs to Warband Nexus UI (GameTooltip placement hook; View-layer only).
function ns.IsWarbandNexusUIFrame(owner)
    if not owner then return false end
    local root = mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
    local cur = owner
    for _ = 1, 20 do
        if not cur then break end
        if root and cur == root then return true end
        local n = (type(cur.GetName) == "function") and cur:GetName() or nil
        if n and type(n) == "string" and not (issecretvalue and issecretvalue(n))
            and n:find("WarbandNexus", 1, true) then
            return true
        end
        if type(cur.GetParent) == "function" then
            cur = cur:GetParent()
        else
            break
        end
    end
    return false
end

-- REMOVED: local currentTab - now using mainFrame.currentTab (fixes tab switching bug)
local currentItemsSubTab = "inventory" -- Default: Bags (current character); Warband sub-tab shows account-wide tree (former Storage tab).
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- Hidden frame that collects orphaned non-pooled UI elements.
-- WoW frames are NEVER garbage collected â€” SetParent(nil) leaves them permanently
-- in memory with a nil parent. The recycleBin gives them a valid hidden parent
-- so they at least have proper frame hierarchy (see WN_FACTORY block on `WarbandNexusRecycleBin`).
local recycleBin = CreateFrame("Frame", "WarbandNexusRecycleBin", UIParent)
recycleBin:Hide()
recycleBin:SetSize(1, 1)
recycleBin:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -9999, 9999)
ns.UI_RecycleBin = recycleBin

--- Park tab-persistent scroll chrome when leaving a main tab.
--- `_wnKeepOnTabSwitch` skips same-tab PopulateContent teardown only; cross-tab switches must Hide().
local function DetachKeptScrollChildOnMainTabSwitch(child)
    if not child or not child.Hide then return end
    child:Hide()
    if recycleBin then
        child:SetParent(recycleBin)
    end
end

--- Fast tab-switch detach can race deferred Items/PvE timers that re-parent keep frames; purge any leak.
local function PurgeScrollChildLeaksAfterFastDetach(scrollChild)
    if not scrollChild then return end
    local nc = PackVariadicInto(_uiChildEnumScratch, scrollChild:GetChildren())
    for i = 1, nc do
        local child = _uiChildEnumScratch[i]
        if child.isPersistentRowElement then
            child:Hide()
        else
            if child._wnProfColumnHeaderStrip then
                child._wnKeepOnTabSwitch = nil
            end
            DetachKeptScrollChildOnMainTabSwitch(child)
        end
    end
end

--- Main tabs that own `scrollChild.resultsContainer` (Bank/Items, Currency, Reputation).
local SCROLL_RESULTS_HOST_TABS = {
    items = true,
    currency = true,
    reputations = true,
}

local function ParkScrollChildSharedHostFrame(frame, clearKeepFlag)
    if not frame or not frame.Hide then return end
    if clearKeepFlag then
        frame._wnKeepOnTabSwitch = nil
    end
    DetachKeptScrollChildOnMainTabSwitch(frame)
end

--- Hide + recycleBin shared scroll hosts that do not belong on `activeTab` (Gear/Bank overlap fix).
function ns.UI_ParkScrollChildSharedHosts(scrollChild, activeTab)
    if not scrollChild or not activeTab then return end

    if not SCROLL_RESULTS_HOST_TABS[activeTab] then
        if WarbandNexus.AbortStorageChunkedPaint then
            WarbandNexus:AbortStorageChunkedPaint()
        end
        ParkScrollChildSharedHostFrame(scrollChild.resultsContainer, false)
    end

    if activeTab ~= "currency" and activeTab ~= "reputations" then
        ParkScrollChildSharedHostFrame(scrollChild._wnResultsAnnexSheet, false)
    end

    if activeTab ~= "gear" then
        ParkScrollChildSharedHostFrame(scrollChild._gearLoadingHost, false)
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame then
            WarbandNexus.UI.mainFrame._gearContentVeil = nil
        end
        if ns._gearPlayerModel then ns._gearPlayerModel:Hide() end
        if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
        if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
        if ns._gearModelBorder then ns._gearModelBorder:Hide() end
        if ns._gearIlvlFrame then ns._gearIlvlFrame:Hide() end
        if ns._gearNameWrapper then ns._gearNameWrapper:Hide() end
    end

    if activeTab ~= "pve" then
        ParkScrollChildSharedHostFrame(scrollChild._pveColHeaderRow, true)
        local shells = scrollChild._pveSectionShells
        if shells then
            for i = 1, #shells do
                local sh = shells[i]
                if sh then
                    ParkScrollChildSharedHostFrame(sh.header, false)
                    ParkScrollChildSharedHostFrame(sh.body, false)
                end
            end
        end
    end

    if activeTab ~= "professions" then
        if ns.UI_HideProfessionColumnHeaderStrip then
            ns.UI_HideProfessionColumnHeaderStrip(scrollChild)
        elseif scrollChild._wnProfColHeaderRow then
            scrollChild._wnProfColHeaderRow._wnKeepOnTabSwitch = nil
            ParkScrollChildSharedHostFrame(scrollChild._wnProfColHeaderRow, false)
        end
    end
end

-- Async pool drain after main-tab fast detach (spreads ReleasePooledRowsInSubtree off the switch hitch).
ns.UIShell._recycleBinDrainGen = 0
local RECYCLE_BIN_DRAIN_MS_BUDGET = 6
local RECYCLE_BIN_DRAIN_MAX_SUBTREES = 2

local function ScheduleRecycleBinPoolDrain(pendingCount)
    if not pendingCount or pendingCount < 1 then return end
    ns.UIShell._recycleBinDrainGen = (ns.UIShell._recycleBinDrainGen or 0) + 1
    local drainGen = ns.UIShell._recycleBinDrainGen
    local remaining = pendingCount

    local function drainSlice()
        if drainGen ~= ns.UIShell._recycleBinDrainGen or remaining <= 0 or not recycleBin then return end
        local t0 = debugprofilestop()
        local nc = PackVariadicInto(_uiChildEnumScratch, recycleBin:GetChildren())
        local drained = 0
        for i = 1, nc do
            local child = _uiChildEnumScratch[i]
            if child and not child._wnPoolDrained then
                if ReleasePooledRowsInSubtree then
                    ReleasePooledRowsInSubtree(child)
                end
                child._wnPoolDrained = true
                drained = drained + 1
                remaining = remaining - 1
                if drained >= RECYCLE_BIN_DRAIN_MAX_SUBTREES or remaining <= 0 then
                    break
                end
                if debugprofilestop() - t0 >= RECYCLE_BIN_DRAIN_MS_BUDGET then
                    break
                end
            end
        end
        if remaining <= 0 or drainGen ~= ns.UIShell._recycleBinDrainGen then return end
        local more = false
        local nc2 = PackVariadicInto(_uiChildEnumScratch, recycleBin:GetChildren())
        for i = 1, nc2 do
            local child = _uiChildEnumScratch[i]
            if child and not child._wnPoolDrained then
                more = true
                break
            end
        end
        if more and C_Timer and C_Timer.After then
            C_Timer.After(0, drainSlice)
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, drainSlice)
    else
        drainSlice()
    end
end

local function CancelShellGearAsyncTimers(st)
    if not st then return end
    if st.gearItemInfoCoalesceTimer and st.gearItemInfoCoalesceTimer.Cancel then
        st.gearItemInfoCoalesceTimer:Cancel()
    end
    st.gearItemInfoCoalesceTimer = nil
    st.gearItemInfoCoalesceGen = (st.gearItemInfoCoalesceGen or 0) + 1
    if st.gearStorageRecRefreshTimer and st.gearStorageRecRefreshTimer.Cancel then
        st.gearStorageRecRefreshTimer:Cancel()
    end
    st.gearStorageRecRefreshTimer = nil
    st.gearStorageRecRefreshEquipOnly = false
end

--- Invalidate staged/chunk paint for a tab we are leaving (paint-gen bumps; no GearUI edits).
local function CancelLeavingTabStagedPaint(tabKey, mf)
    if not tabKey or not mf then return end
    if WarbandNexus.AbortTabOperations then
        WarbandNexus:AbortTabOperations(tabKey)
    end
    if tabKey == "gear" then
        ns._gearTabDrawGen = (ns._gearTabDrawGen or 0) + 1
        ns._gearTabPopulateQuietUntil = nil
        mf._gearDeferChainActive = nil
        mf._wnGearSplitPaperDollNext = nil
        ns._gearStorageDeferAwaiting = nil
        ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
        CancelShellGearAsyncTimers(mf._shellRefreshState)
    elseif tabKey == "plans" then
        ns._plansBrowsePaintGen = (ns._plansBrowsePaintGen or 0) + 1
        ns._plansAchPopulateGen = (ns._plansAchPopulateGen or 0) + 1
        ns._plansCategoryBodyGen = (ns._plansCategoryBodyGen or 0) + 1
    end
end

ns.UI_CancelLeavingTabStagedPaint = CancelLeavingTabStagedPaint

--- Items / Warband aggregate: sync scrollChild width from scroll viewport before reading content width.
ns.UI_EnsureMainScrollLayout = function()
    if mainFrame and not (ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mainFrame)) then
        UpdateScrollLayout(mainFrame)
    end
end

-- Namespace exports for state management (used by sub-modules)
ns.UI_GetItemsSubTab = function() return currentItemsSubTab end
ns.UI_SetItemsSubTab = function(val)
    if val == "storage" then
        val = "warband"
    end
    local previousSub = currentItemsSubTab
    -- Bank > Warband aggregate uses `storageExpandAllActive` + GetStorageTreeExpandState (not expandedGroups).
    if val ~= "warband" and val ~= "guild" and WarbandNexus then
        WarbandNexus.storageExpandAllActive = false
    end
    -- Entering Warband or Guild Bank from another Bank sub-tab: reset expand-all + session tree.
    if WarbandNexus and previousSub ~= val and (val == "warband" or val == "guild") then
        WarbandNexus.storageExpandAllActive = false
        if WarbandNexus.ResetStorageTreeExpandState then
            WarbandNexus:ResetStorageTreeExpandState()
        end
    end
    currentItemsSubTab = val
    -- No longer syncing BankFrame tabs (read-only mode)
end
ns.UI_GetExpandedGroups = function() return expandedGroups end

--- Reset collapsible section trees to default collapsed at login (session persistence until logout).
function ns.UI_ResetSessionSectionExpandState()
    -- Section expand/collapse states persist per profile: whatever the user
    -- left open stays open across sessions. Only the transient "expand all"
    -- sweep flags reset here; the Bank aggregate tree stays session-only
    -- (derived search view, keys change between sessions).
    local addon = WarbandNexus
    if not addon then return end
    addon.itemsExpandAllActive = false
    addon.storageExpandAllActive = false
    addon.pveExpandAllActive = false
    addon.currencyExpandAllActive = false
    addon.achievementsExpandAllActive = false
    if addon.ResetStorageTreeExpandState then
        addon:ResetStorageTreeExpandState()
    end
    local p = addon.db and addon.db.profile
    if p then
        -- Attach the group expand table to the profile so To-Do / Items group
        -- headers keep their state across reloads and sessions.
        p.expandedGroups = p.expandedGroups or {}
        expandedGroups = p.expandedGroups
    end
end
ns.UI_ResetSessionSectionExpandState = ns.UI_ResetSessionSectionExpandState

-- UI-SPECIFIC HELPERS
-- (Shared helpers are now imported from SharedWidgets at top of file)

-- MAIN FUNCTIONS

-- Clear all search state on main tab change (delegates to SearchBoxComponent).
local function ClearAllSearchBoxes()
    if ns.UI_ClearAllSearchQueries then
        ns.UI_ClearAllSearchQueries()
    end
end

---Session-only main tab (hide/show same login). Cleared on /reload.
---@param tabKey string|nil
local function RememberSessionMainTab(tabKey)
    if tabKey and tabKey ~= "" and tabKey ~= "settings" and tabKey ~= "about" then
        ns._wnSessionLastTab = tabKey
    end
end

---Normalize caller tab keys (Easy Access / legacy aliases).
---@param tabKey string|nil
---@return string|nil
local function NormalizeRequestedMainTab(tabKey)
    if not tabKey or tabKey == "" then return nil end
    if tabKey == "storage" then return "items" end
    return tabKey
end

---First login (no explicit tab): Characters once. Reload/session: lastTab; hide/show: session tab.
---@param requestedTabKey string|nil explicit tab (Easy Access left-click, minimap shortcuts)
---@return string
local function ResolveMainWindowOpenTab(requestedTabKey)
    local explicit = NormalizeRequestedMainTab(requestedTabKey)
    if explicit then
        return explicit
    end
    if ns._wnOpenCharsTabOnFirstLogin then
        ns._wnOpenCharsTabOnFirstLogin = nil
        return "chars"
    end
    if ns._wnSessionLastTab and ns._wnSessionLastTab ~= "settings" and ns._wnSessionLastTab ~= "about" then
        return ns._wnSessionLastTab
    end
    local p = WarbandNexus.db and WarbandNexus.db.profile
    local lt = p and p.lastTab
    if lt == "settings" or lt == "about" then lt = nil end
    if lt == "storage" then lt = "items" end
    return lt or "chars"
end

---Apply resolved tab to mainFrame (legacy "storage" -> Items > Warband).
---@param f Frame
---@param requestedTabKey string|nil
---@param resolvedTab string
local function ApplyMainFrameOpenTab(f, requestedTabKey, resolvedTab)
    if requestedTabKey == "storage" then
        f.currentTab = "items"
        if WarbandNexus.db and WarbandNexus.db.profile then
            WarbandNexus.db.profile.lastTab = "items"
        end
        if ns.UI_SetItemsSubTab then
            ns.UI_SetItemsSubTab("warband")
        end
        return
    end
    f.currentTab = resolvedTab
end

-- Intentionally raw: first login -> Characters on first generic open; /reload keeps db.profile.lastTab.
local mainTabWorldFrame = CreateFrame("Frame")
mainTabWorldFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainTabWorldFrame:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if isInitialLogin then
        ns._wnOpenCharsTabOnFirstLogin = true
    end
    if isReloadingUi then
        ns._wnSessionLastTab = nil
    end
end)

function WarbandNexus:ToggleMainWindow()
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    if ns and ns._wnSuppressToggleMainOnce then
        return
    end
    if mainFrame and mainFrame:IsShown() then
        RememberSessionMainTab(mainFrame.currentTab)
        -- Window object is a singleton; "closed" is IsShown() == false, the ref stays valid.
        mainFrame:Hide()
        SyncMainWindowVisibilityState(false)
    else
        self:ShowMainWindow()
    end
end

--- Shell layout before tab body paint (Easy Access / minimap / `/wn` open paths).
---@param f Frame
---@param targetTab string|nil
local function ApplyMainWindowShowChrome(f, targetTab)
    if f.tabButtons and ns.UI_UpdateMainFrameTabButtonStates then
        ns.UI_UpdateMainFrameTabButtonStates(f)
    end
    f:Show()
    ApplyMainNavGoldenShellLayout(f)
    UpdateScrollLayout(f)
    RefreshFixedHeaderChrome(f)
    RefreshMainNavLayout(f)
    if targetTab then
        ScrollMainNavEnsureTabVisible(f, targetTab)
    end
    local LC = ns.UI_LayoutCoordinator
    if LC and LC.ForceMainFrameMetrics then
        C_Timer.After(0, function()
            if f and f:IsShown() then
                LC:ForceMainFrameMetrics(f, "display_changed")
            end
        end)
    end
end

--- One-shot collectible tooltip precache after first main-window show this session.
local function ScheduleMainWindowTooltipPrecache()
    if ns._wnTooltipPrecacheDone or ns._wnTooltipPrecachePending then return end
    ns._wnTooltipPrecachePending = true
    C_Timer.After(1.5, function()
        ns._wnTooltipPrecachePending = nil
        if ns._wnTooltipPrecacheDone then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() then return end
        ns._wnTooltipPrecacheDone = true
        if WarbandNexus.Tooltip and WarbandNexus.Tooltip.PreCacheCollectibleItems then
            WarbandNexus.Tooltip:PreCacheCollectibleItems()
        end
    end)
end

--- Staged PopulateContent (matches nav ActivateMainTab: pool release frame, populate next).
---@param f Frame
---@param targetTab string
local function ScheduleDeferredShowMainPopulate(f, targetTab)
    f.isMainTabSwitch = true
    C_Timer.After(0, function()
        if not f or not f:IsShown() or f.currentTab ~= targetTab then return end
        C_Timer.After(0, function()
            if not f or not f:IsShown() or f.currentTab ~= targetTab then return end
            WarbandNexus:PopulateContent(true)
            f.isMainTabSwitch = false
        end)
    end)
end

--- Open main window. Optional tab: Easy Access / scripted shortcuts (chars, pve, â€¦). Nil = first-login chars, else session/lastTab.
---@param requestedTabKey string|nil
function WarbandNexus:ShowMainWindow(requestedTabKey)
    -- TAINT PROTECTION: Prevent UI manipulation during combat
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    
    -- Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not ready. Please wait a moment and try again.")
        -- Try again after 1 second
        ns._wnPendingShowMainTab = requestedTabKey
        C_Timer.After(1.0, function()
            if WarbandNexus and WarbandNexus.ShowMainWindow then
                local pending = ns._wnPendingShowMainTab
                ns._wnPendingShowMainTab = nil
                WarbandNexus:ShowMainWindow(pending)
            end
        end)
        return
    end
    ns._wnPendingShowMainTab = nil
    
    if not mainFrame then
        mainFrame = self:CreateMainWindow()
        
        -- GUARD: Check if CreateMainWindow succeeded
        if not mainFrame then
            DebugPrint("|cffff0000[WN UI]|r ERROR: Failed to create main window. See /wn help.")
            return
        end
    end
    
    -- Store reference for external access (FontManager, etc.)
    self.mainFrame = mainFrame

    local profile = self.db and self.db.profile
    if profile and ProfileFlagOn(profile.debugMode) and ProfileFlagOn(profile.debugVerbose) and not ns._wnVerboseHintShown then
        ns._wnVerboseHintShown = true
        self:Print("|cff888888[WN]|r Debug verbose ON â€” cache logs go to |cff00ccff/wn profiler trace|r, not chat. |cff00ccff/wn debug verbose off|r or Settings to silence.")
    end

    local resolvedTab = ResolveMainWindowOpenTab(requestedTabKey)
    local prevTab = mainFrame.currentTab
    ApplyMainFrameOpenTab(mainFrame, requestedTabKey, resolvedTab)
    local targetTab = mainFrame.currentTab
    RememberSessionMainTab(targetTab)

    -- Tab change: reuse nav staged pool teardown + deferred PopulateContent (Easy Access left-click, minimap shortcuts).
    if prevTab ~= targetTab and mainFrame.ActivateMainTab then
        if requestedTabKey ~= nil and requestedTabKey ~= "" then
            mainFrame._wnBypassMainTabInputGraceOnce = true
        end
        mainFrame.currentTab = prevTab
        local persistLast = requestedTabKey ~= nil and targetTab ~= "settings" and targetTab ~= "about"
        mainFrame.ActivateMainTab(targetTab, { persistLastTab = persistLast })
        -- ActivateMainTab before show chrome (grace is set at end of ActivateMainTab, not here).
        ApplyMainWindowShowChrome(mainFrame, targetTab)
        if mainFrame.currentTab ~= targetTab then
            mainFrame.currentTab = targetTab
            if ns.UI_UpdateMainFrameTabButtonStates then
                ns.UI_UpdateMainFrameTabButtonStates(mainFrame)
            end
            ScheduleDeferredShowMainPopulate(mainFrame, targetTab)
        end
        ScheduleMainWindowTooltipPrecache()
        NormalizeFramePosition(mainFrame)
    else
        -- Same tab or first paint: show shell immediately, defer heavy PopulateContent (WN-PERF first paint).
        ApplyMainWindowShowChrome(mainFrame, targetTab)
        ScheduleMainWindowTooltipPrecache()
        ScheduleDeferredShowMainPopulate(mainFrame, targetTab)
        NormalizeFramePosition(mainFrame)
    end

    SyncMainWindowVisibilityState(true)

    -- Loading overlay is standalone â€” no action needed here
    
    -- SAFETY: Deferred tab label re-render (catches font loading race conditions)
    -- On first open after locale switch, fonts may not be fully loaded yet.
    -- Re-applying after 0.1s ensures labels render correctly once fonts are ready.
    if not mainFrame._tabLabelsVerified then
        mainFrame._tabLabelsVerified = true
        C_Timer.After(0.1, function()
            if mainFrame and mainFrame:IsShown() and mainFrame.tabButtons then
                local fm = GetFontManager()
                local anyFixed = false
                for ti = 1, #MAIN_TAB_ORDER do
                    local btn = mainFrame.tabButtons[MAIN_TAB_ORDER[ti]]
                    if btn and btn.label and (btn._wnRailTextMode or not btn._wnRailCompact) then
                        local font, size = btn.label:GetFont()
                        if not font or not size then
                            if fm then fm:ApplyFont(btn.label, "body") end
                            anyFixed = true
                        end
                        local text = btn.label:GetText()
                        if text and not (issecretvalue and issecretvalue(text)) then
                            btn.label:SetText(text)
                        end
                    end
                end
                -- Only rebuild content if fonts actually needed fixing
                if anyFixed then
                    UpdateTabButtonStates(mainFrame)
                    self:PopulateContent()
                end
            end
        end)
    end
end

-- Bank open -> Opens Items tab with correct sub-tab based on NPC type
-- User must manually open via /wn or minimap button

function WarbandNexus:HideMainWindow()
    if mainFrame then
        RememberSessionMainTab(mainFrame.currentTab)
        -- Window object is a singleton; "closed" is IsShown() == false, the ref stays valid.
        mainFrame:Hide()
        SyncMainWindowVisibilityState(false)
    end
end

-- TAB BUTTON STATE (must be defined before CreateMainWindow so tab OnClick closure can see it)
-- Tab key -> profile modulesEnabled key (tabs without entry are always shown: chars, stats)
local TAB_TO_MODULE = {
    items = "items",
    pve = "pve",
    reputations = "reputations",
    currency = "currencies",
    professions = "professions",
    gear = "gear",
    collections = "collections",
    plans = "plans",
}

local function IsTabModuleEnabled(key)
    local moduleKey = TAB_TO_MODULE[key]
    if not moduleKey then return true end
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not db or not db.modulesEnabled then return true end
    return db.modulesEnabled[moduleKey] ~= false
end

local function UpdateTabVisibility(f)
    if not f or not f.tabButtons or not f.tabButtons.chars then return end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local TAB_GAP_H = shell.TAB_GAP or 5
    local vGap = f._wnNavTabVGap or shell.NAV_RAIL_TAB_V_GAP or 4
    local topInset = f._wnNavRailTopInset or shell.NAV_RAIL_TOP_INSET or 6
    local railPad = shell.NAV_RAIL_PAD or 6
    local sepH = shell.NAV_RAIL_TAB_SEP_HEIGHT or 1
    local sepA = shell.NAV_RAIL_TAB_SEP_ALPHA or 0.4
    local sepColor = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor())
        or (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.4, 1, sepA }

    local useClassicRail = ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
    local railTabH = (ns.UI_GetNavRailTabHeight and ns.UI_GetNavRailTabHeight()) or (shell.NAV_RAIL_TAB_HEIGHT or 38)

    local prevBtn = nil
    local railHost = (f._wnMainNavLayout == "rail") and (f.navRailStrip or f.navRail)

    for i = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[i]
        local btn = f.tabButtons[key]
        if btn then
            local show = IsTabModuleEnabled(key)
            btn:SetShown(show)
            if btn._wnRailSepAbove then
                if useClassicRail then
                    btn._wnRailSepAbove:Hide()
                else
                    btn._wnRailSepAbove:SetShown(show and prevBtn ~= nil)
                end
            end
            if show then
                if railHost then
                    if prevBtn then
                        if useClassicRail then
                            btn:ClearAllPoints()
                            btn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -vGap)
                            btn:SetPoint("LEFT", railHost, "LEFT", 0, 0)
                            btn:SetPoint("RIGHT", railHost, "RIGHT", 0, 0)
                            if btn._wnBlizzardButton then
                                btn:SetHeight(railTabH)
                            end
                        else
                        local sep = btn._wnRailSepAbove
                        if not sep then
                            sep = railHost:CreateTexture(nil, "ARTWORK")
                            btn._wnRailSepAbove = sep
                        end
                        sep:SetColorTexture(sepColor[1], sepColor[2], sepColor[3], sepColor[4] or 1)
                        sep:SetHeight(sepH)
                        sep:ClearAllPoints()
                        sep:SetPoint("LEFT", railHost, "LEFT", railPad, 0)
                        sep:SetPoint("RIGHT", railHost, "RIGHT", -railPad, 0)
                        local gapAbove = math.floor(vGap * 0.5)
                        local gapBelow = vGap - gapAbove
                        sep:SetPoint("TOP", prevBtn, "BOTTOM", 0, -gapAbove)
                        sep:Show()
                        btn:SetPoint("TOP", sep, "BOTTOM", 0, -gapBelow)
                        end
                    else
                        btn:ClearAllPoints()
                        btn:SetPoint("TOP", railHost, "TOP", 0, -topInset)
                        if useClassicRail then
                            btn:SetPoint("LEFT", railHost, "LEFT", 0, 0)
                            btn:SetPoint("RIGHT", railHost, "RIGHT", 0, 0)
                            if btn._wnBlizzardButton then
                                btn:SetHeight(railTabH)
                            end
                        end
                    end
                else
                    local strip = f.tabNavStrip or f.nav
                    if prevBtn then
                        btn:SetPoint("LEFT", prevBtn, "RIGHT", TAB_GAP_H, 0)
                    else
                        btn:SetPoint("LEFT", strip, "LEFT", MAIN_TAB_STRIP_EDGE_INSET, 0)
                    end
                end
                prevBtn = btn
            end
        end
    end
    RefreshMainNavLayout(f)
end

local function UpdateTabButtonStates(f)
    if not f or not f.tabButtons or not f.currentTab then return end
    local freshColors = ns.UI_COLORS
    local accentColor = freshColors and freshColors.accent
    if not accentColor then return end
    local fm = GetFontManager()
    for i = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[i]
        local btn = f.tabButtons[key]
        if not btn or not btn:IsShown() then
            -- Skip unknown or hidden (module-disabled) tabs
        else
            local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
            local railFlat = btn._wnRailTextMode
            local railActiveA = (ns.UI_GetNavRailActiveBgAlpha and ns.UI_GetNavRailActiveBgAlpha())
                or shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.28
            if key == f.currentTab then
                btn.active = true
                if btn.label and (btn._wnRailTextMode or not btn._wnRailCompact) then
                    ns.UI_SetTextColorRole(btn.label, "Bright")
                    if ns.UI_SetNavLabelFontStyle then
                        ns.UI_SetNavLabelFontStyle(btn.label, true)
                    end
                end
                if btn.activeBar and not btn._wnBlizzardButton then btn.activeBar:SetAlpha(1) end
                if ns.UI_ApplyClassicNavTabActiveState then ns.UI_ApplyClassicNavTabActiveState(btn, true) end
                if btn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                    ns.UI_ApplyNavTabIconStyle(btn.tabIcon, true, { packaged = btn.tabIcon._wnNavPackagedIcon, rail = btn._wnRailTextMode })
                end
                if not btn._wnBlizzardButton then
                if UpdateBorderColor and not railFlat then
                    UpdateBorderColor(btn, { accentColor[1], accentColor[2], accentColor[3], 1 })
                elseif railFlat and ns.UI_HideFrameBorderQuartet then
                    ns.UI_HideFrameBorderQuartet(btn)
                end
                if btn.SetBackdropColor then
                    if railFlat then
                        local activeBg = ns.UI_GetNavRailActiveBackdrop and ns.UI_GetNavRailActiveBackdrop()
                        if activeBg then
                            btn:SetBackdropColor(activeBg[1], activeBg[2], activeBg[3], activeBg[4] or 0.98)
                        else
                            local railA = (ns.UI_GetNavRailActiveBgAlpha and ns.UI_GetNavRailActiveBgAlpha())
                                or shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.38
                            btn:SetBackdropColor(accentColor[1] * railA, accentColor[2] * railA, accentColor[3] * railA, 0.98)
                        end
                    else
                        btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
                    end
                end
                end
                if ns.UI_ApplyRailTabActiveVisuals then
                    ns.UI_ApplyRailTabActiveVisuals(btn, true, accentColor)
                end
            else
                btn.active = false
                if btn.label and (btn._wnRailTextMode or not btn._wnRailCompact) then
                    if railFlat then
                        ns.UI_SetTextColorRole(btn.label, "Bright")
                    else
                        ns.UI_SetTextColorRole(btn.label, "Muted")
                    end
                    if ns.UI_SetNavLabelFontStyle then
                        ns.UI_SetNavLabelFontStyle(btn.label, false)
                    end
                end
                if btn.activeBar and not btn._wnBlizzardButton then btn.activeBar:SetAlpha(0) end
                if ns.UI_ApplyClassicNavTabActiveState then ns.UI_ApplyClassicNavTabActiveState(btn, false) end
                if btn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                    ns.UI_ApplyNavTabIconStyle(btn.tabIcon, false, { packaged = btn.tabIcon._wnNavPackagedIcon, rail = btn._wnRailTextMode })
                end
                if not btn._wnBlizzardButton then
                if UpdateBorderColor and not railFlat then
                    UpdateBorderColor(btn, { accentColor[1], accentColor[2], accentColor[3], 0.6 })
                elseif railFlat and ns.UI_HideFrameBorderQuartet then
                    ns.UI_HideFrameBorderQuartet(btn)
                end
                if btn.SetBackdropColor then
                    if railFlat then
                        local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.4 }
                        btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 0.4)
                    else
                        local idle = ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop() or { 0.12, 0.12, 0.15, 1 }
                        btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 1)
                    end
                end
                end
                if ns.UI_ApplyRailTabActiveVisuals then
                    ns.UI_ApplyRailTabActiveVisuals(btn, false, accentColor)
                end
            end
        end
    end

    local settingsBtn = f.navSettingsBtn
    if settingsBtn and settingsBtn:IsShown() then
        local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
        local railFlat = settingsBtn._wnRailTextMode
        local isActive = (f.currentTab == "settings")
        if isActive then
            settingsBtn.active = true
            if settingsBtn.label and (settingsBtn._wnRailTextMode or not settingsBtn._wnRailCompact) then
                ns.UI_SetTextColorRole(settingsBtn.label, "Bright")
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(settingsBtn.label, true)
                end
            end
            if settingsBtn.activeBar and not settingsBtn._wnBlizzardButton then settingsBtn.activeBar:SetAlpha(1) end
            if ns.UI_ApplyClassicNavTabActiveState then ns.UI_ApplyClassicNavTabActiveState(settingsBtn, true) end
            if settingsBtn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                ns.UI_ApplyNavTabIconStyle(settingsBtn.tabIcon, true, { packaged = settingsBtn.tabIcon._wnNavPackagedIcon, rail = settingsBtn._wnRailTextMode })
            end
            if not settingsBtn._wnBlizzardButton then
            if railFlat and ns.UI_HideFrameBorderQuartet then
                ns.UI_HideFrameBorderQuartet(settingsBtn)
            end
            if settingsBtn.SetBackdropColor then
                local activeBg = ns.UI_GetNavRailActiveBackdrop and ns.UI_GetNavRailActiveBackdrop()
                if activeBg then
                    settingsBtn:SetBackdropColor(activeBg[1], activeBg[2], activeBg[3], activeBg[4] or 0.98)
                else
                    local railA = (ns.UI_GetNavRailActiveBgAlpha and ns.UI_GetNavRailActiveBgAlpha())
                        or shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.38
                    settingsBtn:SetBackdropColor(accentColor[1] * railA, accentColor[2] * railA, accentColor[3] * railA, 0.98)
                end
            end
            end
            if ns.UI_ApplyRailTabActiveVisuals then
                ns.UI_ApplyRailTabActiveVisuals(settingsBtn, true, accentColor)
            end
        else
            settingsBtn.active = false
            if settingsBtn.label and (settingsBtn._wnRailTextMode or not settingsBtn._wnRailCompact) then
                if railFlat then
                    ns.UI_SetTextColorRole(settingsBtn.label, "Bright")
                else
                    ns.UI_SetTextColorRole(settingsBtn.label, "Muted")
                end
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(settingsBtn.label, false)
                end
            end
            if settingsBtn.activeBar and not settingsBtn._wnBlizzardButton then settingsBtn.activeBar:SetAlpha(0) end
            if ns.UI_ApplyClassicNavTabActiveState then ns.UI_ApplyClassicNavTabActiveState(settingsBtn, false) end
            if settingsBtn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                ns.UI_ApplyNavTabIconStyle(settingsBtn.tabIcon, false, { packaged = settingsBtn.tabIcon._wnNavPackagedIcon, rail = settingsBtn._wnRailTextMode })
            end
            if not settingsBtn._wnBlizzardButton then
            if railFlat and ns.UI_HideFrameBorderQuartet then
                ns.UI_HideFrameBorderQuartet(settingsBtn)
            end
            if settingsBtn.SetBackdropColor then
                if railFlat then
                    local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.4 }
                    settingsBtn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 0.4)
                else
                    local idle = ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop() or { 0.12, 0.12, 0.15, 1 }
                    settingsBtn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 1)
                end
            end
            end
            if ns.UI_ApplyRailTabActiveVisuals then
                ns.UI_ApplyRailTabActiveVisuals(settingsBtn, false, accentColor)
            end
        end
    end

    local aboutBtn = f.navAboutBtn
    if aboutBtn and aboutBtn:IsShown() then
        local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
        local railFlat = aboutBtn._wnRailTextMode
        local isAboutActive = (f.currentTab == "about")
        if isAboutActive then
            aboutBtn.active = true
            if aboutBtn.label and (aboutBtn._wnRailTextMode or not aboutBtn._wnRailCompact) then
                ns.UI_SetTextColorRole(aboutBtn.label, "Bright")
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(aboutBtn.label, true)
                end
            end
            if aboutBtn.activeBar and not aboutBtn._wnBlizzardButton then aboutBtn.activeBar:SetAlpha(1) end
            if ns.UI_ApplyClassicNavTabActiveState then ns.UI_ApplyClassicNavTabActiveState(aboutBtn, true) end
            if aboutBtn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                ns.UI_ApplyNavTabIconStyle(aboutBtn.tabIcon, true, { packaged = aboutBtn.tabIcon._wnNavPackagedIcon, rail = aboutBtn._wnRailTextMode })
            end
            if not aboutBtn._wnBlizzardButton then
            if railFlat and ns.UI_HideFrameBorderQuartet then
                ns.UI_HideFrameBorderQuartet(aboutBtn)
            end
            if aboutBtn.SetBackdropColor then
                local activeBg = ns.UI_GetNavRailActiveBackdrop and ns.UI_GetNavRailActiveBackdrop()
                if activeBg then
                    aboutBtn:SetBackdropColor(activeBg[1], activeBg[2], activeBg[3], activeBg[4] or 0.98)
                else
                    local railA = (ns.UI_GetNavRailActiveBgAlpha and ns.UI_GetNavRailActiveBgAlpha())
                        or shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.38
                    aboutBtn:SetBackdropColor(accentColor[1] * railA, accentColor[2] * railA, accentColor[3] * railA, 0.98)
                end
            end
            end
            if ns.UI_ApplyRailTabActiveVisuals then
                ns.UI_ApplyRailTabActiveVisuals(aboutBtn, true, accentColor)
            end
        else
            aboutBtn.active = false
            if aboutBtn.label and (aboutBtn._wnRailTextMode or not aboutBtn._wnRailCompact) then
                if railFlat then
                    ns.UI_SetTextColorRole(aboutBtn.label, "Bright")
                else
                    ns.UI_SetTextColorRole(aboutBtn.label, "Muted")
                end
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(aboutBtn.label, false)
                end
            end
            if aboutBtn.activeBar and not aboutBtn._wnBlizzardButton then aboutBtn.activeBar:SetAlpha(0) end
            if ns.UI_ApplyClassicNavTabActiveState then ns.UI_ApplyClassicNavTabActiveState(aboutBtn, false) end
            if aboutBtn.tabIcon and ns.UI_ApplyNavTabIconStyle then
                ns.UI_ApplyNavTabIconStyle(aboutBtn.tabIcon, false, { packaged = aboutBtn.tabIcon._wnNavPackagedIcon, rail = aboutBtn._wnRailTextMode })
            end
            if not aboutBtn._wnBlizzardButton then
            if railFlat and ns.UI_HideFrameBorderQuartet then
                ns.UI_HideFrameBorderQuartet(aboutBtn)
            end
            if aboutBtn.SetBackdropColor then
                if railFlat then
                    local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.4 }
                    aboutBtn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 0.4)
                else
                    local idle = ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop() or { 0.12, 0.12, 0.15, 1 }
                    aboutBtn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 1)
                end
            end
            end
            if ns.UI_ApplyRailTabActiveVisuals then
                ns.UI_ApplyRailTabActiveVisuals(aboutBtn, false, accentColor)
            end
        end
    end

end

ns.UI_UpdateMainFrameTabButtonStates = UpdateTabButtonStates

--[[ WN_FACTORY â€” Main window raw `CreateFrame` inventory (this file loads after SharedWidgets).
  Main vertical scroll + scrollbar column + horizontal bar already use `ns.UI.Factory`.

  Intentionally raw (keep unless product calls for a redesign):
  - `WarbandNexusFrame` root: global name for zombie cleanup, `BackdropTemplate`, drag/resize, WindowManager strata.
  - `postCombatUIFrame`, `reloadMainTabFrame`, `UIEvents._itemInfoFrame`, loading-overlay `eventFrame`:
    invisible event hosts (no tab layout).
  - `WarbandNexusRecycleBin`: long-lived orphan reparent bucket.
  - Resize corner strip: Blizzard size-grabber textures on a capturing `Frame` (not Factory button).
  - Header utility buttons (close/discord/donate/credits/tracking): packaged Icon-*.tga (SVG source) + tooltips +
    copy-to-clipboard `EditBox` popups (`FULLSCREEN_DIALOG`).
  - `trackingChip` + nested `BackdropTemplate` hosts: compact tracking strip.
  - `CreateTabButton` inner `Button`: main nav tabs (custom width math + atlas + `ApplyHighlight`).
  - `WarbandNexusLoadingOverlay`: standalone init bar (named, draggable, polling lifecycle).

  Factory candidates (later PRs; match anchors/levels exactly):
  - Layout shells: `header`, `nav`, `content`, `viewportBorder`, `fixedHeader`, `columnHeaderClip` /
    `columnHeaderInner`, `scrollChild`, `hScrollContainer`, footer bar, `scrollChild._wnScrollBottomFill`.
  - Header buttons: `ns.UI.Factory:CreateButton(..., true)` + existing `ApplyVisuals`/atlas (parity with Vault/Gear).
]]

-- Shell/tab satellites (before UI_MainShell / UI_TabHost)

ns.UIShell._bind = {
    ApplyMainNavGoldenShellLayout = ApplyMainNavGoldenShellLayout,
    ApplyMainShellLayout = ApplyMainShellLayout,
    ApplyVisuals = ApplyVisuals,
    ArmPostCombatUIRefresh = ArmPostCombatUIRefresh,
    CancelLeavingTabStagedPaint = CancelLeavingTabStagedPaint,
    CancelShellGearAsyncTimers = CancelShellGearAsyncTimers,
    ClearAllSearchBoxes = ClearAllSearchBoxes,
    ComputeScrollChildWidth = ComputeScrollChildWidth,
    DebugPrint = DebugPrint,
    DetachKeptScrollChildOnMainTabSwitch = DetachKeptScrollChildOnMainTabSwitch,
    GetFontManager = GetFontManager,
    GetMainWindowGeometryBounds = GetMainWindowGeometryBounds,
    GetWindowDimensions = GetWindowDimensions,
    IsDebugModeEnabled = IsDebugModeEnabled,
    IsTabModuleEnabled = IsTabModuleEnabled,
    IsTabPerfMonitorEnabled = IsTabPerfMonitorEnabled,
    MAIN_TAB_ORDER = MAIN_TAB_ORDER,
    SHELL_TAB_SWITCH_POPULATE_QUIET = SHELL_TAB_SWITCH_POPULATE_QUIET,
    MarkShellPopulateCompleted = MarkShellPopulateCompleted,
    NormalizeFramePosition = NormalizeFramePosition,
    PackVariadicInto = PackVariadicInto,
    ProfileFlagOn = ProfileFlagOn,
    PurgeScrollChildLeaksAfterFastDetach = PurgeScrollChildLeaksAfterFastDetach,
    RefreshMainNavLayout = RefreshMainNavLayout,
    RefreshMainNavRailStrip = RefreshMainNavRailStrip,
    RefreshMainNavTabStrip = RefreshMainNavTabStrip,
    ReleaseCharacterRowsFromSubtree = ReleaseCharacterRowsFromSubtree,
    ReleaseCurrencyRowsFromSubtree = ReleaseCurrencyRowsFromSubtree,
    ReleasePooledRowsInSubtree = ReleasePooledRowsInSubtree,
    ReleaseReputationRowsFromSubtree = ReleaseReputationRowsFromSubtree,
    RememberSessionMainTab = RememberSessionMainTab,
    RestoreWindowPosition = RestoreWindowPosition,
    SaveWindowGeometry = SaveWindowGeometry,
    ScheduleRecycleBinPoolDrain = ScheduleRecycleBinPoolDrain,
    ScrollMainNavEnsureTabVisible = ScrollMainNavEnsureTabVisible,
    ShouldSkipRedundantShellPopulate = ShouldSkipRedundantShellPopulate,
    StartCustomDrag = StartCustomDrag,
    StartCustomResize = StartCustomResize,
    StopCustomDrag = StopCustomDrag,
    StopCustomResize = StopCustomResize,
    UpdateScrollLayout = UpdateScrollLayout,
    UpdateTabButtonStates = UpdateTabButtonStates,
    UpdateTabVisibility = UpdateTabVisibility,
    WireMainNavTabButtonUX = WireMainNavTabButtonUX,
    debugprofilestart = debugprofilestart,
    debugprofilestop = debugprofilestop,
    format = format,
    recycleBin = recycleBin,
    UIEvents = UIEvents,
    L = L,
    COLORS = COLORS,
    _uiChildEnumScratch = _uiChildEnumScratch,
    _uiRegionEnumScratch = _uiRegionEnumScratch,
    TAB_DRAW_PERF_TRACE = TAB_DRAW_PERF_TRACE,
}


function ns.UIShell.getMainFrame()
    return mainFrame
end
function ns.UIShell.setMainFrame(f)
    mainFrame = f
end

function WarbandNexus:CreateMainWindow()
    if ns.UIShell and ns.UIShell.CreateMainWindow then
        return ns.UIShell.CreateMainWindow(self)
    end
end

-- POPULATE CONTENT
-- PopulateContent: Modules/UI/UI_TabHost.lua
function WarbandNexus:PopulateContent(forceRepaint)
    if ns.UIShell and ns.UIShell.PopulateContent then
        return ns.UIShell.PopulateContent(self, forceRepaint)
    end
end

-- TAB COUNT BADGES
--- Update tab count badges next to nav labels.
---@param whichTab? string|nil If "currency" or "reputations", only refresh that badge (lighter than full counts pass).
function WarbandNexus:UpdateTabCountBadges(whichTab)
    if not mainFrame or not mainFrame.tabButtons then return end

    local counts = {}
    local needCurrency = (whichTab == nil or whichTab == "currency")
    local needReputations = (whichTab == nil or whichTab == "reputations")

    if needCurrency and ns.CurrencyCacheService and ns.CurrencyCacheService.GetAllCachedCurrencyIDs then
        local ids = ns.CurrencyCacheService:GetAllCachedCurrencyIDs()
        if ids then counts.currency = #ids end
    end

    if needReputations and ns.ReputationCacheService and ns.ReputationCacheService.GetCachedFactionCount then
        local ok, n = pcall(ns.ReputationCacheService.GetCachedFactionCount, ns.ReputationCacheService)
        if ok and type(n) == "number" then counts.reputations = n end
    end

    if whichTab then
        local btn = mainFrame.tabButtons[whichTab]
        local cl = btn and btn.countLabel
        if cl then
            local c = counts[whichTab]
            if c and c > 0 then
                cl:SetText("(" .. c .. ")")
                cl:Show()
            else
                cl:SetText("")
                cl:Hide()
            end
        end
        return
    end

    for ti = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[ti]
        local btn = mainFrame.tabButtons[key]
        local cl = btn and btn.countLabel
        if cl then
            local c = counts[key]
            if c and c > 0 then
                cl:SetText("(" .. c .. ")")
                cl:Show()
            else
                cl:SetText("")
                cl:Hide()
            end
        end
    end
end

-- TRACKING REQUIRED BANNER
function WarbandNexus:DrawTrackingRequiredBanner(parent)
    local card = CreateCard(parent, 170)
    card:SetPoint("TOPLEFT", 10, -20)
    card:SetPoint("TOPRIGHT", -10, -20)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 34)
    icon:SetPoint("TOPLEFT", 14, -14)
    local ok = pcall(icon.SetAtlas, icon, "common-icon-redx", false)
    if not ok then
        icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
    end
    icon:SetVertexColor(1, 0.4, 0.4)

    local title = GetFontManager():CreateFontString(card, GetFontManager():GetFontRole("trackingRequiredBannerTitle"), "OVERLAY")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
    title:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -2)
    title:SetJustifyH("LEFT")
    if ns.UI_GetSemanticOrangeColor then
        local wr, wg, wb = ns.UI_GetSemanticOrangeColor()
        title:SetTextColor(wr, wg, wb)
    else
        title:SetTextColor(1, 0.55, 0.45)
    end
    title:SetText((ns.L and ns.L["TRACKING_TAB_LOCKED_TITLE"]) or "Character is not tracked")

    local desc = GetFontManager():CreateFontString(card, GetFontManager():GetFontRole("trackingRequiredBannerBody"), "OVERLAY")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -8)
    desc:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(desc, "Normal")
    desc:SetText((ns.L and ns.L["TRACKING_TAB_LOCKED_DESC"]) or "This tab works only for tracked characters.\nEnable tracking from the Characters page using the tracking icon.")

    local openCharsBtn = CreateThemedButton(card, (ns.L and ns.L["OPEN_CHARACTERS_TAB"]) or "Open Characters", 170)
    openCharsBtn:SetPoint("BOTTOMLEFT", 14, 12)
    openCharsBtn:SetScript("OnClick", function()
        if mainFrame and mainFrame.tabButtons and mainFrame.tabButtons.chars then
            mainFrame.currentTab = "chars"
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = "chars"
            end
            UpdateTabButtonStates(mainFrame)
            WarbandNexus:PopulateContent()
        end
    end)

    return 200
end

-- UPDATE STATUS
function WarbandNexus:UpdateStatus()
    if not mainFrame then return end

    local isOpen = self.bankIsOpen
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)

    local icon = mainFrame.statusIcon
    local badge = mainFrame.statusBadge
    local accent = mainFrame.trackingStatusAccent
    local chip = mainFrame.trackingChip
    local charKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
            and ns.CharacterService:ResolveCharactersTableKey(self))
        or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self))
    local trackingDialogKey = charKey

    local function BadgeOneLine(s)
        if not s or s == "" then return s end
        if issecretvalue and issecretvalue(s) then return "" end
        return (s:gsub("\n+", " "))
    end

    local function SizeTrackingChip()
        if not chip or not mainFrame.statusText then return end
        local tw = mainFrame.statusText:GetStringWidth() or 0
        -- 3px rail + 6 + 20 icon tile + 8 gap + text + right pad
        local w = 3 + 6 + 20 + 8 + tw + 10
        chip:SetWidth(math.max(96, math.min(280, w)))
    end

    local function SetClickAndTooltip(tooltipText, tooltipHint)
        if badge then
            badge:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                if trackingDialogKey and ns.CharacterService and ns.CharacterService.ShowCharacterTrackingConfirmation then
                    ns.CharacterService:ShowCharacterTrackingConfirmation(WarbandNexus, trackingDialogKey)
                end
            end)
            badge:SetScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
                local tr, tg, tb = 1, 1, 1
                if ns.UI_GetTooltipTitleColor then tr, tg, tb = ns.UI_GetTooltipTitleColor() end
                GameTooltip:SetText(tooltipText or "", tr, tg, tb)
                if tooltipHint then
                    local hr, hg, hb = 0.7, 0.7, 0.7
                    if ns.UI_GetTooltipDescColor then hr, hg, hb = ns.UI_GetTooltipDescColor() end
                    GameTooltip:AddLine(tooltipHint, hr, hg, hb, true)
                end
                GameTooltip:Show()
            end)
            badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    local function StatusAccentRGB(kind)
        if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
            local classicGreen = (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.green)
                or (ns.UI_CLASSIC_SURFACE_VARIANT and ns.UI_CLASSIC_SURFACE_VARIANT.green)
                or { 0.35, 0.85, 0.35 }
            local classicGold = (ns.UI_CLASSIC_ACCENT_THEME and ns.UI_CLASSIC_ACCENT_THEME.accent)
                or { 0.85, 0.68, 0.20 }
            if kind == "positive" then
                return classicGreen[1], classicGreen[2], classicGreen[3]
            end
            return classicGold[1], classicGold[2], classicGold[3]
        end
        if ns.UI_IsLightMode and ns.UI_IsLightMode() then
            if kind == "positive" then
                return ns.UI_GetSemanticGreenColor and ns.UI_GetSemanticGreenColor() or 0.14, 0.52, 0.24
            end
            return ns.UI_GetSemanticRedColor and ns.UI_GetSemanticRedColor() or 0.78, 0.18, 0.18
        end
        if kind == "positive" then
            return 0.18, 0.88, 0.48
        end
        return 0.95, 0.42, 0.22
    end

    local function StatusTextRGB(kind)
        if ns.UI_IsLightMode and ns.UI_IsLightMode() then
            if kind == "bank" or kind == "tracked" then
                return ns.UI_GetSemanticGreenColor and ns.UI_GetSemanticGreenColor() or 0.14, 0.52, 0.24
            end
            return ns.UI_GetSemanticOrangeColor and ns.UI_GetSemanticOrangeColor() or 0.72, 0.38, 0.06
        end
        if kind == "bank" then
            return 0.75, 0.95, 0.82
        elseif kind == "tracked" then
            return 0.82, 0.98, 0.88
        end
        return 1, 0.72, 0.58
    end

    local function StatusIconRGB(kind)
        if ns.UI_IsLightMode and ns.UI_IsLightMode() then
            if kind == "positive" then
                return ns.UI_GetSemanticGreenColor and ns.UI_GetSemanticGreenColor() or 0.14, 0.52, 0.24
            end
            return ns.UI_GetSemanticRedColor and ns.UI_GetSemanticRedColor() or 0.78, 0.18, 0.18
        end
        if kind == "positive" then
            return 0.45, 1, 0.55
        end
        return 1, 0.55, 0.42
    end

    if mainFrame.statusText then
        if isOpen then
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_BANK"]) or "Bank is Active"))
            local r, g, b = StatusTextRGB("bank")
            mainFrame.statusText:SetTextColor(r, g, b)
        elseif isTracked then
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_TRACKING"]) or "Tracking"))
            local r, g, b = StatusTextRGB("tracked")
            mainFrame.statusText:SetTextColor(r, g, b)
        else
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_UNTRACKED"]) or "Not Tracking"))
            local r, g, b = StatusTextRGB("untracked")
            mainFrame.statusText:SetTextColor(r, g, b)
        end
    end

    if accent then
        if isOpen or isTracked then
            local r, g, b = StatusAccentRGB("positive")
            accent:SetColorTexture(r, g, b, 1)
        else
            local r, g, b = StatusAccentRGB("negative")
            accent:SetColorTexture(r, g, b, 1)
        end
    end

    if isOpen then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            local r, g, b = StatusIconRGB("positive")
            icon:SetVertexColor(r, g, b)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["BANK_IS_ACTIVE"]) or "Bank is Active", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    elseif isTracked then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            local r, g, b = StatusIconRGB("positive")
            icon:SetVertexColor(r, g, b)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_ACTIVE_DESC"]) or "Data collection and updates are active.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    else
        if icon then
            local ok = pcall(icon.SetAtlas, icon, "common-icon-redx", false)
            if not ok then
                icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
            end
            local r, g, b = StatusIconRGB("negative")
            icon:SetVertexColor(r, g, b)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_NOT_ENABLED_TOOLTIP"]) or "Character tracking is disabled.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to enable tracking.")
    end

    SizeTrackingChip()
end

-- REMOVED: UpdateFooter â€” empty stub with no callers.

-- DRAW ITEM LIST
-- Track which bank type is selected in Items tab
-- DEFAULT: Personal Bank (priority over Warband)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

-- REMOVED: WarbandNexus:SetItemsSubTab / GetItemsSubTab â€” unused; ns.UI_SetItemsSubTab / ns.UI_GetItemsSubTab are the live API.

-- Track expanded state for each category (persists across refreshes)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

-- TAB DRAWING FUNCTIONS (All moved to separate modules)
-- DrawCharacterList moved to Modules/UI/CharactersUI.lua
-- DrawItemList moved to Modules/UI/ItemsUI.lua
-- DrawEmptyState moved to Modules/UI/ItemsUI.lua
-- DrawStorageTab / DrawStorageResults / SyncStorageResultsLayoutFromTail live in this file (Items + Warband tree).
-- DrawPvEProgress moved to Modules/UI/PvEUI.lua
-- DrawStatistics moved to Modules/UI/StatisticsUI.lua

-- REFRESH

-- Refresh throttle constants
local REFRESH_THROTTLE = 0.05 -- Small delay for batching follow-up refreshes

function WarbandNexus:RefreshUI()
    -- Dismiss any open achievement popup before UI rebuild
    if ns.UI_HideAchievementPopup then
        ns.UI_HideAchievementPopup()
    end
    
    if mainFrame and mainFrame.tabButtons then
        UpdateTabVisibility(mainFrame)
    end
    
    -- Combat safety: defer frame operations to avoid taint (shared arm with PopulateContentBody).
    if InCombatLockdown() then
        ArmPostCombatUIRefresh()
        return
    end
    
    -- Prevent recursive calls during populate (safety flag)
    if self.isRefreshing then
        -- Schedule a follow-up refresh instead of executing recursively
        if not self.pendingRefresh then
            self.pendingRefresh = true
            C_Timer.After(REFRESH_THROTTLE, function()
                if WarbandNexus and WarbandNexus.pendingRefresh then
                    WarbandNexus.pendingRefresh = false
                    WarbandNexus:RefreshUI()
                end
            end)
        end
        return
    end
    
    -- Always execute the refresh immediately (no throttle on user actions)
    self.isRefreshing = true
    
    -- Use pcall to ensure isRefreshing flag is always reset even if there's an error
    local success, err = pcall(function()
        if mainFrame and mainFrame:IsShown() then
            self:PopulateContent()
        end
    end)
    
    self.isRefreshing = false
    
    if not success and IsDebugModeEnabled and IsDebugModeEnabled() then
        self:Debug("|cffff0000[RefreshUI] PopulateContent error: " .. tostring(err) .. "|r")
    end
end

--- Apply global UI scale to the main window. Called from SettingsUI when slider changes.
---@param newScale number Scale value (0.6 - 1.5)
function WarbandNexus:ApplyUIScale(newScale)
    if not mainFrame then return end
    if ns.UI_GetAddonUIScale then
        newScale = ns.UI_GetAddonUIScale()
    else
        newScale = math.max(0.6, math.min(1.5, newScale or 1.0))
    end
    if WarbandNexus.db and WarbandNexus.db.profile then
        WarbandNexus.db.profile.uiScale = newScale
    end

    -- Persist geometry before SetScale so width/height/anchor offsets snapshot pre-change layout.
    SaveWindowGeometry(mainFrame)

    if ns.UI_ApplyAddonUIScaleToAll then
        ns.UI_ApplyAddonUIScaleToAll()
    else
        mainFrame:SetScale(newScale)
    end

    -- Re-clamp to screen after scale change (frame may have shifted off-screen)
    NormalizeFramePosition(mainFrame)
    SaveWindowGeometry(mainFrame)

    local LC = ns.UI_LayoutCoordinator
    if LC and LC.OnAddonUIScaleChanged then
        LC:OnAddonUIScaleChanged(mainFrame)
    elseif mainFrame:IsShown() then
        self:PopulateContent()
    end
end

-- REMOVED: RefreshMainWindow() and RefreshMainWindowContent() - duplicate wrappers, use RefreshUI() directly

--[[
    [CONSOLIDATED] RefreshUI duplicate removed (line 1040)
    The implementation at line 997 with throttling and recursive call prevention is kept.
    This duplicate (which closed/reopened the window) has been removed to prevent conflicts.
    The consolidated RefreshUI handles both normal refreshes and font/scale changes.
]]

--[[
    Force refresh of PvE tab if currently visible
    Provides instant refresh for responsive UI
    Moved from Core.lua to UI.lua (proper separation of concerns)
]]
function WarbandNexus:RefreshPvEUI()
    local dbg = IsDebugModeEnabled and IsDebugModeEnabled()
    if dbg then
    end
    if self.UI and self.UI.mainFrame then
        local mainFrame = self.UI.mainFrame
        if mainFrame:IsShown() and mainFrame.currentTab == "pve" then
            -- Instant refresh for responsive UI
            if self.RefreshUI then
                self:RefreshUI()
                if dbg then
                end
            end
        end
    end
end

--[[
    Open addon settings/options UI
    Shows custom settings UI with themed widgets
    Moved from Core.lua to UI.lua (proper separation of concerns)
]]
function WarbandNexus:OpenOptions()
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    if ns.SettingsUI and ns.SettingsUI.SetActivePanel then
        ns.SettingsUI.SetActivePanel("general")
    end
    if self.ShowMainWindow then
        self:ShowMainWindow("settings")
        return
    end
    if mainFrame and mainFrame.ActivateMainTab then
        mainFrame._wnBypassMainTabInputGraceOnce = true
        mainFrame:ActivateMainTab("settings", { persistLastTab = false })
        if mainFrame:IsShown() and ns.UI_UpdateMainFrameTabButtonStates then
            ns.UI_UpdateMainFrameTabButtonStates(mainFrame)
        end
    elseif self.DrawSettingsTab and mainFrame then
        mainFrame.currentTab = "settings"
        self:PopulateContent()
        if ns.UI_UpdateMainFrameTabButtonStates then
            ns.UI_UpdateMainFrameTabButtonStates(mainFrame)
        end
    else
        self:Print("|cff9370DB[Warband Nexus]|r " .. ((ns.L and ns.L["SETTINGS_UI_UNAVAILABLE"]) or "Settings UI not available. Try /wn to open the main window."))
    end
end

-- Floating bar that appears on screen during init, independent of the addon window.
-- Uses lightweight polling (0.5s ticker) to track LoadingTracker state.
-- AceEvent message hooks don't work from standalone contexts (plain tables
-- can't register as AceEvent receivers), so polling is the reliable approach.
--
-- LIFECYCLE: Ticker runs for up to MAX_POLL_LIFETIME seconds after PLAYER_LOGIN.
-- This covers both the initial login (tracked chars: ~15s) and the delayed
-- post-confirmation flow (user clicks "Tracked" at T+2.5s+: adds ~5s of ops).
-- Ticker is NOT cancelled on first completion â€” new operations can be registered
-- after the user confirms tracking, and the bar will reappear automatically.
do
    local loadingOverlay
    local pollTicker
    local completedShown = false
    local wasSyncComplete = false
    local syncCompletePopulateFired = false
    local pollStartTime = 0
    local MAX_POLL_LIFETIME = 180 -- 3 minutes: covers late-confirm edge cases
    local wipe = table.wipe
    local overlayLabelParts = {}

    local function CreateLoadingOverlay()
        if loadingOverlay then return loadingOverlay end

        local C = ns.UI_COLORS
        if not C then return nil end

        -- Intentionally raw: named draggable init bar (`WarbandNexusLoadingOverlay`; see WN_FACTORY block).
        local bar = CreateFrame("Frame", "WarbandNexusLoadingOverlay", UIParent, "BackdropTemplate")
        bar:SetSize(360, 34)
        bar:SetPoint("TOP", UIParent, "TOP", 0, -12)
        bar:SetFrameStrata("HIGH")
        bar:SetFrameLevel(100)
        bar:SetClampedToScreen(true)
        bar:SetMovable(true)
        bar:EnableMouse(true)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", bar.StartMoving)
        bar:SetScript("OnDragStop", bar.StopMovingOrSizing)
        bar:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        local loadBarBg = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop() or { 0.06, 0.06, 0.09, 1 }
        bar:SetBackdropColor(loadBarBg[1], loadBarBg[2], loadBarBg[3], loadBarBg[4] or 1)
        bar:SetBackdropBorderColor(0.2, 0.8, 0.3, 1)
        bar:Hide()

        -- Progress fill
        local fill = bar:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMLEFT", 1, 1)
        fill:SetWidth(1)
        fill:SetColorTexture(0.15, 0.55, 0.2, 0.6)
        bar.progressFill = fill

        -- Spinner
        local spinner = bar:CreateTexture(nil, "OVERLAY")
        spinner:SetSize(14, 14)
        spinner:SetPoint("LEFT", 8, 0)
        spinner:SetTexture("Interface\\COMMON\\StreamCircle")
        spinner:SetVertexColor(0.3, 0.9, 0.4, 0.9)
        bar.spinner = spinner

        local spinGroup = spinner:CreateAnimationGroup()
        local spinAnim = spinGroup:CreateAnimation("Rotation")
        spinAnim:SetDegrees(-360)
        spinAnim:SetDuration(1.2)
        spinGroup:SetLooping("REPEAT")
        bar.spinGroup = spinGroup

        local loadText
        if ns.FontManager then
            loadText = ns.FontManager:CreateFontString(bar, ns.FontManager:GetFontRole("loadingBarPrimaryText"), "OVERLAY")
        else
            loadText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        loadText:SetPoint("LEFT", spinner, "RIGHT", 6, 0)
        loadText:SetPoint("RIGHT", bar, "RIGHT", -55, 0)
        loadText:SetJustifyH("LEFT")
        if ns.UI_SetTextColorRole then
            ns.UI_SetTextColorRole(loadText, "Bright")
        else
            loadText:SetTextColor(0.3, 0.9, 0.4, 1)
        end
        loadText:SetWordWrap(false)
        bar.loadingText = loadText

        local progText
        if ns.FontManager then
            progText = ns.FontManager:CreateFontString(bar, ns.FontManager:GetFontRole("loadingBarSecondaryText"), "OVERLAY")
        else
            progText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        progText:SetPoint("RIGHT", -8, 0)
        if ns.UI_SetTextColorRole then
            ns.UI_SetTextColorRole(progText, "Bright")
        else
            progText:SetTextColor(0.3, 0.9, 0.4, 1)
        end
        bar.progressText = progText

        loadingOverlay = bar
        return bar
    end

    local function UpdateLoadingOverlay()
        local LT = ns.LoadingTracker
        if not LT then return end

        local bar = loadingOverlay
        if not bar then
            bar = CreateLoadingOverlay()
            if not bar then return end
        end

        local done, total = LT:GetProgress()
        local isComplete = LT:IsComplete()

        if not isComplete then
            wasSyncComplete = false
            syncCompletePopulateFired = false
        elseif not wasSyncComplete and total > 0 and not syncCompletePopulateFired then
            local mf = mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if mf and mf:IsShown() then
                if ShouldSkipSyncCompletePopulate(mf) then
                    syncCompletePopulateFired = true
                else
                    local shellSt = mf._shellRefreshState
                    if shellSt then
                        shellSt.bypassQuietForSync = true
                    end
                    local LC = ns.UI_LayoutCoordinator
                    local sh = LC and LC._shell
                    if sh and sh.schedulePopulateContent then
                        sh.schedulePopulateContent(true)
                        syncCompletePopulateFired = true
                    elseif WarbandNexus.PopulateContent then
                        WarbandNexus:PopulateContent(true)
                        syncCompletePopulateFired = true
                    end
                end
            end
            wasSyncComplete = true
        elseif isComplete then
            wasSyncComplete = true
        end

        if isComplete then
            if bar:IsShown() and not completedShown then
                completedShown = true
                bar.loadingText:SetText((ns.L and ns.L["SYNCING_COMPLETE"]) or "Syncing complete!")
                bar.progressText:SetText("")
                bar.progressFill:SetWidth(math.max(1, bar:GetWidth() - 2))
                C_Timer.After(2, function()
                    if bar and LT:IsComplete() then
                        bar.spinGroup:Stop()
                        bar:Hide()
                    end
                    -- Do NOT cancel ticker here: new operations may be registered
                    -- after user confirms tracking. Ticker auto-stops after MAX_POLL_LIFETIME.
                end)
            end
            return
        end

        if total == 0 then
            bar:Hide()
            return
        end

        -- New operations registered after a previous completion cycle
        bar:Show()
        bar.spinGroup:Play()
        completedShown = false

        -- Progress fill width
        local barWidth = bar:GetWidth() - 2
        if barWidth > 0 and total > 0 then
            bar.progressFill:SetWidth(math.max(1, barWidth * (done / total)))
        end

        -- Pending labels (GetPendingLabels returns ephemeral reused table â€” copy only what we display)
        local pending = LT:GetPendingLabels()
        local labelStr = ""
        if #pending > 0 then
            local shown = math.min(#pending, 2)
            wipe(overlayLabelParts)
            for i = 1, shown do
                overlayLabelParts[i] = pending[i]
            end
            labelStr = table.concat(overlayLabelParts, ", ", 1, shown)
            if #pending > shown then
                labelStr = labelStr .. " +" .. (#pending - shown)
            end
        end
        bar.loadingText:SetText(string.format((ns.L and ns.L["SYNCING_LABEL_FORMAT"]) or "WN Syncing : %s", labelStr))
        bar.progressText:SetText(format("%d / %d", done, total))
    end

    -- Start polling after PLAYER_LOGIN.
    -- Ticker runs for up to MAX_POLL_LIFETIME seconds, then auto-cancels.
    -- Intentionally raw: PLAYER_LOGIN latch for overlay polling ticker (WN_FACTORY inventory).
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", function()
        C_Timer.After(1.5, function()
            pollStartTime = GetTime()
            UpdateLoadingOverlay()
            if not pollTicker then
                pollTicker = C_Timer.NewTicker(0.5, function()
                    if GetTime() - pollStartTime > MAX_POLL_LIFETIME then
                        if pollTicker then
                            pollTicker:Cancel()
                            pollTicker = nil
                        end
                        -- Avoid leaving the sync bar visible forever if LoadingTracker never completes (e.g. rare init errors)
                        if loadingOverlay and loadingOverlay:IsShown() then
                            if loadingOverlay.spinGroup then loadingOverlay.spinGroup:Stop() end
                            loadingOverlay:Hide()
                        end
                        return
                    end
                    UpdateLoadingOverlay()
                end)
            end
        end)
    end)
end
