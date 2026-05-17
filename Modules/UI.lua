--[[
    Warband Nexus - UI Module
    Modern, clean UI design
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
-- CRITICAL: FontManager is lazy-loaded to prevent initialization errors
local FontManager  -- Will be set on first access
local L = ns.L

local issecretvalue = issecretvalue

-- Unique AceEvent handler identity for UI.lua
-- AceEvent uses events[eventname][self] = handler, so each module needs a unique
-- 'self' table to prevent overwriting other modules' handlers for the same event.
local UIEvents = {}

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

--- SavedVars may use strict booleans or legacy `1`; match Settings checkboxes reliably.
local function ProfileFlagOn(v)
    return v == true or v == 1
end

--- Main-tab perf timings: Debug + Verbose both on (any legacy truthy). `/wn debug` alone does not spam chat.
local function IsTabPerfMonitorEnabled()
    local p = WarbandNexus.db and WarbandNexus.db.profile
    return p and ProfileFlagOn(p.debugMode) and ProfileFlagOn(p.debugVerbose)
end

ns.IsTabPerfMonitorEnabled = IsTabPerfMonitorEnabled

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

--- Canonical tab order: `ns.UI_MAIN_TAB_ORDER` in SharedWidgets.lua — must precede timers that reference it (Lua local scope).
--- QA smoke: open each entry once after /reload (`ShowMainWindow` deferred tab label pass uses this index).
local MAIN_TAB_ORDER = ns.UI_MAIN_TAB_ORDER or {
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

--- Golden-ratio rail width + strip/button sync (text rail below header).
local function ApplyMainNavGoldenShellLayout(f)
    if not f or f._wnMainNavLayout ~= "rail" or not f.navRail then return end
    local shell = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local inset = shell.FRAME_CONTENT_INSET or 6
    local innerW = math.max(360, (f:GetWidth() or 800) - inset * 2)
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
ns.UI_RefreshMainNavLayout = RefreshMainNavLayout
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
local _uiChildEnumScratch = {}
local _uiRegionEnumScratch = {}
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
--- Uses `Region:GetLeft` / `:GetTop`; same numeric space as that anchor chain (WoW anchors are UI-scale / widget-scale aware — see wiki `ScriptRegionResizing:SetPoint` Details).
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

-- Compute scrollChild logical width for the current tab.
-- Tabs with wide inline layouts enforce a minimum so horizontal scrollbar appears instead of squashed chrome.
local function ComputeScrollChildWidth(frame)
    if not frame or not frame.scroll then return 0 end
    local w = frame.scroll:GetWidth()
    local tab = frame.currentTab
    if tab == "gear" and ns.MIN_GEAR_CARD_W and ns.MIN_GEAR_CARD_W > 0 then
        w = math.max(w, ns.MIN_GEAR_CARD_W)
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

-- Update scrollChild and frozen column header widths in one call.
local function UpdateScrollLayout(frame)
    if not frame or not frame.scrollChild or not frame.scroll then return end
    if ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(frame) then
        return
    end
    local w = ComputeScrollChildWidth(frame)
    frame.scrollChild:SetWidth(w)
    if frame.columnHeaderInner and frame.columnHeaderClip and frame.columnHeaderClip:GetHeight() > 1 then
        frame.columnHeaderInner:SetWidth(w)
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
    UpdateScrollLayout(mf)
    ApplyMainNavGoldenShellLayout(mf)
    RefreshFixedHeaderChrome(mf)
    local LC = ns.UI_LayoutCoordinator
    if LC and LC.ForceMainFrameMetrics and mf:IsShown() then
        LC:ForceMainFrameMetrics(mf, "display_changed")
    end
end

local mainFrame = nil
-- REMOVED: local currentTab - now using mainFrame.currentTab (fixes tab switching bug)
local currentItemsSubTab = "inventory" -- Default: Bags (current character); Warband sub-tab shows account-wide tree (former Storage tab).
local expandedGroups = {} -- Persisted expand/collapse state for item groups

-- Hidden frame that collects orphaned non-pooled UI elements.
-- WoW frames are NEVER garbage collected — SetParent(nil) leaves them permanently
-- in memory with a nil parent. The recycleBin gives them a valid hidden parent
-- so they at least have proper frame hierarchy (see WN_FACTORY block on `WarbandNexusRecycleBin`).
local recycleBin = CreateFrame("Frame", "WarbandNexusRecycleBin", UIParent)
recycleBin:Hide()
recycleBin:SetSize(1, 1)
recycleBin:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -9999, 9999)
ns.UI_RecycleBin = recycleBin

--- Items / Warband aggregate: sync scrollChild width from scroll viewport before reading content width.
ns.UI_EnsureMainScrollLayout = function()
    if mainFrame and not (ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(mainFrame)) then
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
    if val ~= "warband" and WarbandNexus then
        WarbandNexus.storageExpandAllActive = false
    end
    -- Entering Warband from another Bank sub-tab: reset expand-all + session tree state, then open both
    -- major section bodies (Personal Items + Warband Bank) so counts match visible rows without an extra click.
    -- Nested char/type keys stay default-collapsed until expand-all or explicit toggle (ItemsUI.lua).
    if val == "warband" and WarbandNexus and previousSub ~= "warband" then
        WarbandNexus.storageExpandAllActive = false
        if WarbandNexus.ResetStorageTreeExpandState then
            WarbandNexus:ResetStorageTreeExpandState()
        end
        if WarbandNexus.GetStorageTreeExpandState then
            local st = WarbandNexus:GetStorageTreeExpandState()
            st.warband = true
            st.personal = true
        end
    end
    currentItemsSubTab = val
    -- No longer syncing BankFrame tabs (read-only mode)
end
ns.UI_GetExpandedGroups = function() return expandedGroups end
ns.UI_GetExpandAllActive = function() return WarbandNexus.itemsExpandAllActive end

--============================================================================
-- UI-SPECIFIC HELPERS
--============================================================================
-- (Shared helpers are now imported from SharedWidgets at top of file)

--============================================================================
-- MAIN FUNCTIONS
--============================================================================

-- Clear all search state on main tab change
local SEARCH_TAB_IDS = { "items", "gear", "currency", "reputation", "plans_mount", "plans_pet", "plans_toy", "plans_transmog", "plans_illusion", "plans_title", "plans_achievement" }

local function ClearAllSearchBoxes()
    local SSM = ns.SearchStateManager
    if SSM and SSM.ClearSearch then
        for i = 1, #SEARCH_TAB_IDS do
            SSM:ClearSearch(SEARCH_TAB_IDS[i])
        end
    end
    -- Clear My Plans active search
    ns._plansActiveSearch = nil
    ns._gearSearchText = nil
end

---Session-only main tab (hide/show same login). Cleared on /reload.
---@param tabKey string|nil
local function RememberSessionMainTab(tabKey)
    if tabKey and tabKey ~= "" then
        ns._wnSessionLastTab = tabKey
    end
end

---After /reload first open is always Characters; same-session reopen uses last tab.
---@return string
local function ResolveMainWindowOpenTab()
    if ns._wnOpenCharsTabOnNextShow then
        ns._wnOpenCharsTabOnNextShow = nil
        return "chars"
    end
    if ns._wnSessionLastTab then
        return ns._wnSessionLastTab
    end
    local p = WarbandNexus.db and WarbandNexus.db.profile
    return (p and p.lastTab) or "chars"
end

-- Intentionally raw: /reload sets next main open to Characters (ENTERING_WORLD flag).
local reloadMainTabFrame = CreateFrame("Frame")
reloadMainTabFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
reloadMainTabFrame:SetScript("OnEvent", function(_, event, isInitialLogin, isReloadingUi)
    if isReloadingUi then
        ns._wnOpenCharsTabOnNextShow = true
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
    -- Modal-first behavior: if Settings is open, close it first.
    local settingsPanel = _G.WarbandNexusSettingsPanel
    if settingsPanel and settingsPanel:IsShown() then
        settingsPanel:Hide()
        return
    end
    if mainFrame and mainFrame:IsShown() then
        RememberSessionMainTab(mainFrame.currentTab)
        mainFrame:Hide()
        self.mainFrame = nil  -- Clear reference
    else
        self:ShowMainWindow()
    end
end

-- Open: /reload -> Characters; same session hide/show -> last tab (session), else db.profile.lastTab.
function WarbandNexus:ShowMainWindow()
    -- TAINT PROTECTION: Prevent UI manipulation during combat
    if InCombatLockdown() then
        self:Print("|cffff6600" .. ((ns.L and ns.L["COMBAT_LOCKDOWN_MSG"]) or "Cannot open window during combat. Please try again after combat ends.") .. "|r")
        return
    end
    
    -- CRITICAL: Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not ready. Please wait a moment and try again.")
        -- Try again after 1 second
        C_Timer.After(1.0, function()
            if WarbandNexus and WarbandNexus.ShowMainWindow then
                WarbandNexus:ShowMainWindow()
            end
        end)
        return
    end
    
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
    
    mainFrame.currentTab = ResolveMainWindowOpenTab()
    -- Former main tab "storage" is merged into Items > Warband (account-wide tree).
    if mainFrame.currentTab == "storage" then
        mainFrame.currentTab = "items"
        if WarbandNexus.db.profile then
            WarbandNexus.db.profile.lastTab = "items"
        end
        if ns.UI_SetItemsSubTab then
            ns.UI_SetItemsSubTab("warband")
        end
    end
    RememberSessionMainTab(mainFrame.currentTab)
    mainFrame.isMainTabSwitch = true  -- First open = main tab switch

    -- Show before PopulateContent: while hidden, scroll:GetWidth() is often 0 → blank/black To-Do (and other tabs).
    -- Same pointer action that opened the window (LDB/minimap) can release over the nav row → spurious tab click.
    mainFrame._wnMainTabInputGraceUntil = GetTime() + 0.2
    mainFrame:Show()
    ApplyMainNavGoldenShellLayout(mainFrame)
    UpdateScrollLayout(mainFrame)
    RefreshFixedHeaderChrome(mainFrame)
    RefreshMainNavLayout(mainFrame)
    if mainFrame.currentTab then
        ScrollMainNavEnsureTabVisible(mainFrame, mainFrame.currentTab)
    end
    local LC = ns.UI_LayoutCoordinator
    if LC and LC.ForceMainFrameMetrics then
        C_Timer.After(0, function()
            if mainFrame and mainFrame:IsShown() then
                LC:ForceMainFrameMetrics(mainFrame, "display_changed")
            end
        end)
    end
    -- One-shot collectible tooltip precache after the user actually opens the UI (avoids background work on login-only sessions).
    if not ns._wnTooltipPrecacheDone and not ns._wnTooltipPrecachePending then
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
    self:PopulateContent()
    mainFrame.isMainTabSwitch = false  -- Reset flag
    -- Ensure frame is always anchored TOPLEFT when visible so drag never "teleports"
    -- (StartMoving uses current anchor; CENTER would make the window jump to cursor-as-center).
    NormalizeFramePosition(mainFrame)

    -- Loading overlay is standalone — no action needed here
    
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
        mainFrame:Hide()
        if WarbandNexus.mainFrame then
            WarbandNexus.mainFrame = nil
        end
    end
end

--============================================================================
-- TAB BUTTON STATE (must be defined before CreateMainWindow so tab OnClick closure can see it)
--============================================================================
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
    local ac = (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.4, 1 }

    local prevBtn = nil
    local railHost = (f._wnMainNavLayout == "rail") and (f.navRailStrip or f.navRail)

    for i = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[i]
        local btn = f.tabButtons[key]
        if btn then
            local show = IsTabModuleEnabled(key)
            btn:SetShown(show)
            if btn._wnRailSepAbove then
                btn._wnRailSepAbove:SetShown(show and prevBtn ~= nil)
            end
            if show then
                if railHost then
                    if prevBtn then
                        local sep = btn._wnRailSepAbove
                        if not sep then
                            sep = railHost:CreateTexture(nil, "ARTWORK")
                            btn._wnRailSepAbove = sep
                        end
                        sep:SetColorTexture(ac[1], ac[2], ac[3], sepA)
                        sep:SetHeight(sepH)
                        sep:ClearAllPoints()
                        sep:SetPoint("LEFT", railHost, "LEFT", railPad, 0)
                        sep:SetPoint("RIGHT", railHost, "RIGHT", -railPad, 0)
                        local gapAbove = math.floor(vGap * 0.5)
                        local gapBelow = vGap - gapAbove
                        sep:SetPoint("TOP", prevBtn, "BOTTOM", 0, -gapAbove)
                        sep:Show()
                        btn:SetPoint("TOP", sep, "BOTTOM", 0, -gapBelow)
                    else
                        btn:SetPoint("TOP", railHost, "TOP", 0, -topInset)
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
            local railBorderA = shell.NAV_RAIL_BORDER_ALPHA or 0.18
            local railActiveA = shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.28
            if key == f.currentTab then
                btn.active = true
                if btn.label and (btn._wnRailTextMode or not btn._wnRailCompact) then
                    btn.label:SetTextColor(1, 1, 1)
                    local font, size = btn.label:GetFont()
                    if font and size then
                        btn.label:SetFont(font, size, "OUTLINE")
                    elseif fm then
                        fm:ApplyFont(btn.label, "body")
                        font, size = btn.label:GetFont()
                        if font and size then btn.label:SetFont(font, size, "OUTLINE") end
                    end
                end
                if btn.activeBar then btn.activeBar:SetAlpha(1) end
                if btn.tabIcon then btn.tabIcon:SetVertexColor(1, 1, 1, 1) end
                if UpdateBorderColor and not railFlat then
                    UpdateBorderColor(btn, { accentColor[1], accentColor[2], accentColor[3], 1 })
                elseif railFlat and ns.UI_HideFrameBorderQuartet then
                    ns.UI_HideFrameBorderQuartet(btn)
                end
                if btn.SetBackdropColor then
                    if railFlat then
                        local railA = shell.NAV_RAIL_ACTIVE_BG_ALPHA or 0.52
                        btn:SetBackdropColor(accentColor[1] * railA, accentColor[2] * railA, accentColor[3] * railA, 0.98)
                    else
                        btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
                    end
                end
                if ns.UI_ApplyRailTabActiveVisuals then
                    ns.UI_ApplyRailTabActiveVisuals(btn, true, accentColor)
                end
            else
                btn.active = false
                if btn.label and (btn._wnRailTextMode or not btn._wnRailCompact) then
                    if railFlat then
                        btn.label:SetTextColor(0.92, 0.92, 0.94)
                    else
                        btn.label:SetTextColor(0.7, 0.7, 0.7)
                    end
                    local font, size = btn.label:GetFont()
                    if font and size then
                        btn.label:SetFont(font, size, "")
                    elseif fm then
                        fm:ApplyFont(btn.label, "body")
                    end
                end
                if btn.activeBar then btn.activeBar:SetAlpha(0) end
                if btn.tabIcon then
                    if railFlat then
                        btn.tabIcon:SetVertexColor(0.88, 0.88, 0.92, 1)
                    else
                        btn.tabIcon:SetVertexColor(0.72, 0.74, 0.78, 0.92)
                    end
                end
                if UpdateBorderColor and not railFlat then
                    UpdateBorderColor(btn, { accentColor[1], accentColor[2], accentColor[3], 0.6 })
                elseif railFlat and ns.UI_HideFrameBorderQuartet then
                    ns.UI_HideFrameBorderQuartet(btn)
                end
                if btn.SetBackdropColor then
                    if railFlat then
                        btn:SetBackdropColor(0.08, 0.08, 0.10, 0.4)
                    else
                        btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
                    end
                end
                if ns.UI_ApplyRailTabActiveVisuals then
                    ns.UI_ApplyRailTabActiveVisuals(btn, false, accentColor)
                end
            end
        end
    end
end

ns.UI_UpdateMainFrameTabButtonStates = UpdateTabButtonStates

--============================================================================
--============================================================================
--[[ WN_FACTORY — Main window raw `CreateFrame` inventory (this file loads after SharedWidgets).
  Main vertical scroll + scrollbar column + horizontal bar already use `ns.UI.Factory`.

  Intentionally raw (keep unless product calls for a redesign):
  - `WarbandNexusFrame` root: global name for zombie cleanup, `BackdropTemplate`, drag/resize, WindowManager strata.
  - `postCombatUIFrame`, `reloadMainTabFrame`, `UIEvents._itemInfoFrame`, loading-overlay `eventFrame`:
    invisible event hosts (no tab layout).
  - `WarbandNexusRecycleBin`: long-lived orphan reparent bucket.
  - Resize corner strip: Blizzard size-grabber textures on a capturing `Frame` (not Factory button).
  - Header utility buttons (close/reload/settings/info/Patreon/Discord): custom atlas + tooltips +
    copy-to-clipboard `EditBox` popups (`FULLSCREEN_DIALOG`).
  - `trackingChip` + nested `BackdropTemplate` hosts: compact tracking strip.
  - `CreateTabButton` inner `Button`: main nav tabs (custom width math + atlas + `ApplyHighlight`).
  - `WarbandNexusLoadingOverlay`: standalone init bar (named, draggable, polling lifecycle).

  Factory candidates (later PRs; match anchors/levels exactly):
  - Layout shells: `header`, `nav`, `content`, `viewportBorder`, `fixedHeader`, `columnHeaderClip` /
    `columnHeaderInner`, `scrollChild`, `hScrollContainer`, footer bar, `scrollChild._wnScrollBottomFill`.
  - Header buttons: `ns.UI.Factory:CreateButton(..., true)` + existing `ApplyVisuals`/atlas (parity with Vault/Gear).
]]
function WarbandNexus:CreateMainWindow()
    -- ZOMBIE FRAME CLEANUP: Check for orphaned frames from failed initialization
    -- If a frame exists in global namespace but we don't have a reference, it's a zombie
    local existingGlobalFrame = _G["WarbandNexusFrame"]
    if existingGlobalFrame then
        -- Check if we already have a valid reference to this frame
        if mainFrame and mainFrame == existingGlobalFrame then
            -- Frame is valid and already created, just return it
            return mainFrame
        else
            -- Zombie frame detected - cleanup and recreate
            existingGlobalFrame:Hide()
            existingGlobalFrame:ClearAllPoints()
            if recycleBin then existingGlobalFrame:SetParent(recycleBin) else existingGlobalFrame:SetParent(nil) end
            
            -- Try to properly release the frame
            if existingGlobalFrame.UnregisterAllEvents then
                pcall(function() existingGlobalFrame:UnregisterAllEvents() end)
            end
            
            -- Clear global reference to allow new frame creation
            _G["WarbandNexusFrame"] = nil
        end
    end
    
    -- CRITICAL: Lazy-load and verify FontManager
    local fm = GetFontManager()
    if not fm or not fm.CreateFontString then
        -- Log error instead of throwing (prevent addon from breaking)
        if self.ErrorLog then
            self.ErrorLog:LogError("CreateMainWindow", "FontManager not initialized", {
                fontManagerExists = ns.FontManager ~= nil,
                createFontStringExists = ns.FontManager and ns.FontManager.CreateFontString ~= nil,
            })
        end
        DebugPrint("|cffff0000[WN UI]|r ERROR: FontManager not initialized. Cannot create UI.")
        return nil
    end
    
    -- Update local reference (for rest of function)
    FontManager = fm
    
    -- Calculate window dimensions dynamically
    local windowWidth, windowHeight = GetWindowDimensions()

    local minW, minH, maxWidth, maxHeight = GetMainWindowGeometryBounds()

    -- Intentionally raw: global `WarbandNexusFrame` — flat shell fill only (no `BackdropTemplate` side gutters).
    local f = CreateFrame("Frame", "WarbandNexusFrame", UIParent)
    f:Hide()  -- CRITICAL: Hide immediately to prevent position flash (frame inherits UIParent visibility)
    f:SetSize(windowWidth, windowHeight)
    f:SetMovable(true)
    f:SetResizable(true)
    -- Dynamic bounds based on screen
    f:SetResizeBounds(minW, minH, maxWidth, maxHeight)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        StartCustomDrag(self)
    end)
    f:SetScript("OnDragStop", function(self)
        StopCustomDrag(self)
        SaveWindowGeometry(self)
    end)
    -- MEDIUM: plays nice with Blizzard UI and other addons (DIALOG was always on top of HIGH/MEDIUM).
    if ns.WindowManager and ns.WindowManager.ApplyStrata then
        ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.MAIN)
    else
        f:SetFrameStrata("MEDIUM")
        f:SetFrameLevel(50)
    end
    if f.SetToplevel then
        f:SetToplevel(true)
    end
    f:SetClampedToScreen(true)
    if f.SetClipsChildren then
        f:SetClipsChildren(true)
    end
    
    -- Apply user-configured UI scale (scales entire addon window + children)
    local uiScale = (WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.uiScale) or 1.0
    uiScale = math.max(0.6, math.min(1.5, uiScale))
    f:SetScale(uiScale)
    
    -- Restore saved position, or center on first use
    if not RestoreWindowPosition(f) then
        f:SetPoint("CENTER")
    end
    
    -- NOTE: Master OnHide is set later (after tab system creation) to consolidate all cleanup
    
    -- Shell: full-bleed panel fill (MAIN_SHELL) — no backdrop insets.
    local COLORS = ns.UI_COLORS
    local shellBg = COLORS and COLORS.bg or { 0.04, 0.04, 0.05, 0.98 }
    if ns.UI_ApplyMainWindowShellFill then
        ns.UI_ApplyMainWindowShellFill(f, shellBg)
    elseif ns.UI_ApplyMainWindowShellBackdrop then
        ns.UI_ApplyMainWindowShellBackdrop(f, shellBg)
    end
    
    -- OnSizeChanged: shell + tab live relayout via LayoutCoordinator (commit on resize mouse-up).
    f:SetScript("OnSizeChanged", function(self, width, height)
        local LC = ns.UI_LayoutCoordinator
        if LC and LC.OnMainFrameResizeLive then
            LC:OnMainFrameResizeLive(self, width, height)
        else
            UpdateScrollLayout(self)
            RefreshMainNavLayout(self)
            if self.currentTab then
                ScrollMainNavEnsureTabVisible(self, self.currentTab)
            end
        end
    end)
    
    -- Intentionally raw: Blizzard chat size-grabber art on a `Frame` mouse sink (not UIPanel resize template).
    local shellLayoutEarly = (ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL) or {}
    local resizeGripSize = shellLayoutEarly.RESIZE_GRIP_SIZE or 18
    local resizeBtn = CreateFrame("Frame", nil, f)
    resizeBtn:SetSize(resizeGripSize, resizeGripSize)
    resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(shellLayoutEarly.RESIZE_GRIP_INSET_X or 4), shellLayoutEarly.RESIZE_GRIP_INSET_Y or 4)
    resizeBtn:EnableMouse(true)
    resizeBtn:SetFrameLevel((f:GetFrameLevel() or 0) + (shellLayoutEarly.RESIZE_GRIP_FRAMELEVEL_BOOST or 80))
    f.resizeGrip = resizeBtn
    
    local resizeNormal = resizeBtn:CreateTexture(nil, "ARTWORK")
    resizeNormal:SetAllPoints()
    resizeNormal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    
    local resizeHighlight = resizeBtn:CreateTexture(nil, "HIGHLIGHT")
    resizeHighlight:SetAllPoints()
    resizeHighlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    
    local isResizing = false
    resizeBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            isResizing = true
            resizeNormal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
            StartCustomResize(f)
        end
    end)
    local function FinishMainFrameResizeMouseUp()
        if not isResizing then return end
        isResizing = false
        resizeNormal:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        StopCustomResize(f)
        SaveWindowGeometry(f)
        NormalizeFramePosition(f)
    end
    f._wnResizeFinishOnRelease = FinishMainFrameResizeMouseUp
    local LCResize = ns.UI_LayoutCoordinator
    if LCResize and LCResize.HookMainFrameResizeCommitOnMouseUp then
        LCResize:HookMainFrameResizeCommitOnMouseUp(f, resizeBtn, FinishMainFrameResizeMouseUp)
    else
        resizeBtn:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" then
                FinishMainFrameResizeMouseUp()
                UpdateScrollLayout(f)
                RefreshMainNavLayout(f)
                if f.currentTab then
                    ScrollMainNavEnsureTabVisible(f, f.currentTab)
                end
                if f.scroll and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
                    ns.UI.Factory:UpdateHorizontalScrollBarVisibility(f.scroll)
                end
                WarbandNexus:PopulateContent()
            end
        end)
    end
    
    -- Intentionally raw: `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED` listener only.
    local scaleFrame = CreateFrame("Frame")
    scaleFrame:RegisterEvent("UI_SCALE_CHANGED")
    scaleFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
    scaleFrame:SetScript("OnEvent", function()
        C_Timer.After(0, function()
            if not f then return end
            local LC = ns.UI_LayoutCoordinator
            if LC and LC.OnDisplayMetricsChanged then
                LC:OnDisplayMetricsChanged(f)
            elseif WarbandNexus.UI_ClampMainFrameResizeBoundsFromProfile then
                WarbandNexus:UI_ClampMainFrameResizeBoundsFromProfile()
            end
        end)
    end)

    local MAIN_SHELL_LAYOUT = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    local frameChromeInset = MAIN_SHELL_LAYOUT.FRAME_CONTENT_INSET or 0
    local frameChromeInsetBottom = MAIN_SHELL_LAYOUT.FRAME_CONTENT_INSET_BOTTOM
        or MAIN_SHELL_LAYOUT.FRAME_CONTENT_INSET
        or 0
    local headerNavGap = MAIN_SHELL_LAYOUT.HEADER_TO_NAV_GAP or 4
    local headerUtilityRight = MAIN_SHELL_LAYOUT.HEADER_UTILITY_CLUSTER_RIGHT_INSET or 18

    -- Factory candidate: `Factory:CreateContainer` host — keep anchors + `EnableMouse` for drag.
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(MAIN_SHELL_LAYOUT.HEADER_BAR_HEIGHT or 40)
    header:EnableMouse(true)
    f.header = header  -- Store reference for color updates
    f._wnHeaderUtilityRightInset = headerUtilityRight
    
    -- Header dragging via RegisterForDrag (fires only on actual drag, not plain click).
    -- Custom drag preserves click offset so the clicked point stays under the cursor.
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        StartCustomDrag(f)
    end)
    header:SetScript("OnDragStop", function()
        StopCustomDrag(f)
        NormalizeFramePosition(f)
        SaveWindowGeometry(f)
    end)
    
    -- Apply header visuals (accent dark background, accent border)
    if ApplyVisuals then
        local COLORS = ns.UI_COLORS
        ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    -- Addon `Media` branding (see `ns.UI_ApplyMainWindowTitleIcon`). `SetFrameLevel` exists on Frame only, not Texture;
    -- host frame keeps the icon above sibling header art without calling a nil Texture method.
    local iconHolder = CreateFrame("Frame", nil, header)
    iconHolder:SetSize(24, 24)
    iconHolder:SetPoint("LEFT", 15, 0)
    iconHolder:SetFrameLevel((header:GetFrameLevel() or 0) + 8)
    local icon = iconHolder:CreateTexture(nil, "OVERLAY", nil, 1)
    icon:SetAllPoints(iconHolder)
    ns.UI_ApplyMainWindowTitleIcon(icon)
    f.addonTitleIcon = icon

    -- Title (WHITE); RIGHT edge clamps against `trackingChip` after chip width is finalized.
    local title = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    title:SetPoint("LEFT", iconHolder, "RIGHT", 8, 0)
    title:SetText((ns.L and ns.L["ADDON_NAME"]) or "Warband Nexus")
    title:SetTextColor(1, 1, 1)  -- Always white
    f.title = title  -- Store reference
    
    -- Close button (Factory pattern with atlas icon)
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -headerUtilityRight, 0)
    
    -- Apply custom visuals
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    -- Close icon using WoW atlas
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    
    -- Hover effects
    closeBtn:SetScript("OnEnter", function(self)
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1})
        end
    end)
    
    closeBtn:SetScript("OnLeave", function(self)
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
        end
    end)
    f.closeBtn = closeBtn

    -- Debug-only: quick /reload (WoW has no Lua hot-reload; saves typing during addon dev)
    local reloadDebugBtn = CreateFrame("Button", nil, header)
    reloadDebugBtn:SetSize(28, 28)
    reloadDebugBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    if ns.UI_ApplyVisuals then
        ns.UI_ApplyVisuals(reloadDebugBtn, {0.12, 0.14, 0.18, 0.92}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75})
    end
    local reloadIcon = reloadDebugBtn:CreateTexture(nil, "ARTWORK")
    reloadIcon:SetSize(16, 16)
    reloadIcon:SetPoint("CENTER")
    do
        local picked = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local atlases = { "StreamCinematic-Restart-button", "common-icon-rotateleft" }
            for ai = 1, #atlases do
                local ok, info = pcall(C_Texture.GetAtlasInfo, atlases[ai])
                if ok and info then
                    reloadIcon:SetAtlas(atlases[ai])
                    picked = true
                    break
                end
            end
        end
        if not picked then
            reloadIcon:SetTexture("Interface\\COMMON\\StreamRestart")
        end
    end
    reloadIcon:SetVertexColor(0.75, 0.92, 1)
    reloadDebugBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    reloadDebugBtn:SetScript("OnEnter", function(self)
        reloadIcon:SetVertexColor(1, 1, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.18, 0.22, 0.28, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["DEBUG_RELOAD_UI_BTN"]) or "Reload UI", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["DEBUG_RELOAD_UI_TOOLTIP"]) or "Reload the entire interface (/reload). WoW cannot hot-reload addon Lua; use this after saving files.", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    reloadDebugBtn:SetScript("OnLeave", function(self)
        reloadIcon:SetVertexColor(0.75, 0.92, 1)
        if ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.12, 0.14, 0.18, 0.92}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75})
        end
        GameTooltip:Hide()
    end)
    f.reloadDebugBtn = reloadDebugBtn

    -- Utility buttons in header (left of Close) so nav row is tabs-only and never overlaps when minimized
    local DISCORD_URL = "https://discord.gg/warbandnexus"
    local PATREON_URL = "https://patreon.com/warbandnexus?utm_medium=unknown&utm_source=join_link&utm_campaign=creatorshare_creator&utm_content=copyLink"
    local discordCopyFrame, discordCopyBox, patreonCopyFrame, patreonCopyBox
    local settingsBtn = CreateFrame("Button", nil, header)
    settingsBtn:SetSize(28, 28)
    settingsBtn:SetPoint("RIGHT", reloadDebugBtn, "LEFT", -6, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() WarbandNexus:OpenOptions() end)
    f.settingsBtn = settingsBtn

    local infoBtn = CreateFrame("Button", nil, header)
    infoBtn:SetSize(28, 28)
    infoBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -6, 0)
    infoBtn:SetNormalTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
    infoBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    infoBtn:SetScript("OnClick", function() WarbandNexus:ShowInfoDialog() end)
    infoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["HEADER_INFO_TOOLTIP"]) or "Addon guide & credits", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["HEADER_INFO_TOOLTIP_HINT"]) or "Features, supporters, and contributors at the top", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Patreon (`Media/donateicon.png`); sits between Info and Discord.
    local patreonBtn = CreateFrame("Button", nil, header)
    patreonBtn:SetSize(30, 30)
    patreonBtn:SetPoint("RIGHT", infoBtn, "LEFT", -6, 0)
    local patreonIcon = patreonBtn:CreateTexture(nil, "ARTWORK")
    patreonIcon:SetAllPoints()
    patreonIcon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\donateicon.png")
    patreonIcon:SetTexCoord(0, 1, 0, 1)
    patreonIcon:SetVertexColor(1, 1, 1, 1)
    patreonCopyFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    patreonCopyFrame:SetSize(440, 28)
    patreonCopyFrame:SetPoint("TOPRIGHT", patreonBtn, "BOTTOMRIGHT", 0, -4)
    patreonCopyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    patreonCopyFrame:SetFrameLevel(500)
    patreonCopyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    patreonCopyFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    patreonCopyFrame:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    patreonCopyFrame:Hide()
    patreonCopyBox = CreateFrame("EditBox", nil, patreonCopyFrame)
    patreonCopyBox:SetPoint("TOPLEFT", 6, -4)
    patreonCopyBox:SetPoint("BOTTOMRIGHT", -6, 4)
    patreonCopyBox:SetAutoFocus(false)
    patreonCopyBox:SetFontObject(ChatFontNormal)
    if ns.FontManager then
        local p = ns.FontManager:GetFontFace()
        local s = ns.FontManager:GetFontSize("body")
        local f = ns.FontManager:GetAAFlags()
        pcall(patreonCopyBox.SetFont, patreonCopyBox, p, s, f)
    end
    patreonCopyBox:SetText(PATREON_URL)
    patreonCopyBox:SetCursorPosition(0)
    patreonCopyBox:SetScript("OnEscapePressed", function() patreonCopyFrame:Hide() end)
    patreonCopyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    patreonCopyBox:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.1, function() patreonCopyFrame:Hide() end)
        end
    end)
    patreonBtn:SetScript("OnEnter", function()
        patreonIcon:SetAlpha(0.75)
        GameTooltip:SetOwner(patreonBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["PATREON_TOOLTIP"]) or "Warband Nexus on Patreon", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["CLICK_TO_COPY_LINK"]) or "Click to copy link", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    patreonBtn:SetScript("OnLeave", function()
        patreonIcon:SetAlpha(1.0)
        GameTooltip:Hide()
    end)
    patreonBtn:SetScript("OnClick", function()
        if patreonCopyFrame:IsShown() then
            patreonCopyFrame:Hide()
            return
        end
        if discordCopyFrame and discordCopyFrame:IsShown() then
            discordCopyFrame:Hide()
        end
        patreonCopyBox:SetText(PATREON_URL)
        patreonCopyFrame:Show()
        patreonCopyBox:SetFocus()
        patreonCopyBox:HighlightText()
    end)
    f.patreonBtn = patreonBtn

    -- Discord (`Media/discord.tga`); Tracking chip attaches to Discord's left edge.
    local discordBtn = CreateFrame("Button", nil, header)
    discordBtn:SetSize(30, 30)
    discordBtn:SetPoint("RIGHT", patreonBtn, "LEFT", -6, 0)
    local discordIcon = discordBtn:CreateTexture(nil, "ARTWORK")
    discordIcon:SetAllPoints()
    discordIcon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\discord.tga")
    discordIcon:SetTexCoord(0, 1, 0, 1)
    discordIcon:SetVertexColor(1, 1, 1, 1)
    discordCopyFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    discordCopyFrame:SetSize(240, 28)
    discordCopyFrame:SetPoint("TOPRIGHT", discordBtn, "BOTTOMRIGHT", 0, -4)
    discordCopyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    discordCopyFrame:SetFrameLevel(500)
    discordCopyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    discordCopyFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
    discordCopyFrame:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8)
    discordCopyFrame:Hide()
    discordCopyBox = CreateFrame("EditBox", nil, discordCopyFrame)
    discordCopyBox:SetPoint("TOPLEFT", 6, -4)
    discordCopyBox:SetPoint("BOTTOMRIGHT", -6, 4)
    discordCopyBox:SetAutoFocus(false)
    discordCopyBox:SetFontObject(ChatFontNormal) -- required initial FontObject
    if ns.FontManager then
        local p = ns.FontManager:GetFontFace()
        local s = ns.FontManager:GetFontSize("body")
        local f = ns.FontManager:GetAAFlags()
        pcall(discordCopyBox.SetFont, discordCopyBox, p, s, f)
    end
    discordCopyBox:SetText(DISCORD_URL)
    discordCopyBox:SetCursorPosition(0)
    discordCopyBox:SetScript("OnEscapePressed", function() discordCopyFrame:Hide() end)
    discordCopyBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    discordCopyBox:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.1, function() discordCopyFrame:Hide() end)
        end
    end)
    discordBtn:SetScript("OnEnter", function(self)
        discordIcon:SetAlpha(0.75)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["DISCORD_TOOLTIP"]) or "Warband Nexus Discord", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["CLICK_TO_COPY"]) or "Click to copy invite link", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    discordBtn:SetScript("OnLeave", function()
        discordIcon:SetAlpha(1.0)
        GameTooltip:Hide()
    end)
    discordBtn:SetScript("OnClick", function()
        if discordCopyFrame:IsShown() then
            discordCopyFrame:Hide()
            return
        end
        if patreonCopyFrame and patreonCopyFrame:IsShown() then
            patreonCopyFrame:Hide()
        end
        discordCopyBox:SetText(DISCORD_URL)
        discordCopyFrame:Show()
        discordCopyBox:SetFocus()
        discordCopyBox:HighlightText()
    end)

    -- Tracking status: compact chip (accent rail + icon + single-line label), immediately left of Discord
    -- Match header accentDark family — avoid flat black (0.06…) which clashes with the title bar
    local trackingChip = CreateFrame("Frame", nil, header, "BackdropTemplate")
    trackingChip:SetHeight(30)
    trackingChip:SetPoint("RIGHT", discordBtn, "LEFT", -8, 0)
    local COL_TRACK = ns.UI_COLORS
    local baseDark = (COL_TRACK and COL_TRACK.accentDark) or {0.28, 0.14, 0.41}
    local chipLift = 0.06
    local chipBg = {
        math.min(1, baseDark[1] + chipLift),
        math.min(1, baseDark[2] + chipLift),
        math.min(1, baseDark[3] + chipLift),
        0.88,
    }
    if ApplyVisuals and COL_TRACK then
        ApplyVisuals(trackingChip, chipBg, {COL_TRACK.accent[1], COL_TRACK.accent[2], COL_TRACK.accent[3], 0.24})
    end

    local trackingAccent = trackingChip:CreateTexture(nil, "ARTWORK", nil, 1)
    trackingAccent:SetWidth(3)
    trackingAccent:SetPoint("TOPLEFT", trackingChip, "TOPLEFT", 0, -1)
    trackingAccent:SetPoint("BOTTOMLEFT", trackingChip, "BOTTOMLEFT", 0, 1)
    trackingAccent:SetColorTexture(0.22, 0.9, 0.42, 1)
    f.trackingStatusAccent = trackingAccent

    local trackingStatusBtn = CreateFrame("Button", nil, trackingChip)
    trackingStatusBtn:SetAllPoints(trackingChip)
    trackingStatusBtn:EnableMouse(true)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
        ns.UI.Factory:ApplyHighlight(trackingStatusBtn)
    end
    f.statusBadge = trackingStatusBtn
    f.trackingChip = trackingChip

    local iconBack = CreateFrame("Frame", nil, trackingChip, "BackdropTemplate")
    iconBack:SetSize(20, 20)
    iconBack:SetPoint("LEFT", trackingAccent, "RIGHT", 6, 0)
    iconBack:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    iconBack:SetBackdropColor(
        math.min(1, baseDark[1] + chipLift * 0.35),
        math.min(1, baseDark[2] + chipLift * 0.35),
        math.min(1, baseDark[3] + chipLift * 0.35),
        0.5
    )

    local trackingIcon = iconBack:CreateTexture(nil, "ARTWORK")
    trackingIcon:SetSize(14, 14)
    trackingIcon:SetPoint("CENTER", iconBack, "CENTER", 0, 0)
    local ok = pcall(trackingIcon.SetAtlas, trackingIcon, "common-icon-checkmark", false)
    if not ok then
        trackingIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
    end
    trackingIcon:SetVertexColor(0.35, 1, 0.45)
    f.statusIcon = trackingIcon

    local statusText = FontManager:CreateFontString(trackingStatusBtn, FontManager:GetFontRole("mainShellTrackingStatus"), "OVERLAY")
    statusText:SetPoint("LEFT", iconBack, "RIGHT", 8, 0)
    statusText:SetPoint("RIGHT", trackingChip, "RIGHT", -8, 0)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("MIDDLE")
    statusText:SetWordWrap(false)
    statusText:SetNonSpaceWrap(false)
    f.statusText = statusText
    trackingChip:SetWidth(112)

    title:SetPoint("RIGHT", trackingChip, "LEFT", -12, 0)
    title:SetJustifyH("LEFT")
    if title.SetWordWrap then title:SetWordWrap(false) end
    if ns.WindowManager then
        ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.MAIN, function()
            if WarbandNexus.HideMainWindow then
                WarbandNexus:HideMainWindow()
            else
                RememberSessionMainTab(f.currentTab)
                f:Hide()
            end
        end)
        ns.WindowManager:InstallESCHandler(f)
    end
    
    -- Footer gutter (above bottom chrome strip): must exist before rail height + content anchors.
    local MAIN_FOOTER_H = 26
    local FOOTER_BOTTOM_OFFSET = MAIN_SHELL_LAYOUT.FOOTER_BOTTOM_OFFSET or 4
    local CONTENT_GAP_ABOVE_FOOTER = MAIN_SHELL_LAYOUT.CONTENT_GAP_ABOVE_FOOTER or 0
    local CONTENT_BOTTOM_OFFSET = FOOTER_BOTTOM_OFFSET + MAIN_FOOTER_H + CONTENT_GAP_ABOVE_FOOTER

    local function GetProfileMainNavLayout()
        local p = WarbandNexus.db and WarbandNexus.db.profile
        local v = p and p.mainNavLayout
        if v == "rail" or v == "top" then return v end
        local st = MAIN_SHELL_LAYOUT.NAV_LAYOUT_MODE
        if st == "rail" or st == "top" then return st end
        return "rail"
    end

    local navLayoutMode = GetProfileMainNavLayout()
    f._wnMainNavLayout = navLayoutMode
    local frameInnerW = math.max(360, (f:GetWidth() or 800) - frameChromeInset * 2)
    local railW = (navLayoutMode == "rail" and ns.UI_ComputeGoldenRailWidth)
        and ns.UI_ComputeGoldenRailWidth(frameInnerW, MAIN_SHELL_LAYOUT)
        or (MAIN_SHELL_LAYOUT.NAV_RAIL_WIDTH or 168)
    local RAIL_TAB_H = MAIN_SHELL_LAYOUT.NAV_RAIL_TAB_HEIGHT or 34
    local RAIL_TOP_INSET = MAIN_SHELL_LAYOUT.NAV_RAIL_TOP_INSET or 8
    local RAIL_TAB_V_GAP = MAIN_SHELL_LAYOUT.NAV_RAIL_TAB_V_GAP or 3
    local RAIL_CONTENT_GAP = MAIN_SHELL_LAYOUT.NAV_RAIL_CONTENT_GAP or 10
    local RAIL_PAD = MAIN_SHELL_LAYOUT.NAV_RAIL_PAD or 6
    f._wnNavRailTopInset = RAIL_TOP_INSET
    f._wnNavTabVGap = RAIL_TAB_V_GAP

    local navRail = nil
    local navRailScroll = nil
    local navRailStrip = nil
    -- Full-width title bar at the top of the shell (above rail + content). Top Y = 0 avoids a dead band above the header.
    header:SetPoint("TOPLEFT", f, "TOPLEFT", frameChromeInset, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -frameChromeInset, 0)

    if navLayoutMode == "rail" then
        navRail = CreateFrame("Frame", nil, f)
        navRail:SetWidth(railW)
        navRail:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -headerNavGap)
        navRail:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, CONTENT_BOTTOM_OFFSET)
        do
            local C = ns.UI_COLORS
            local railBg = C and C.bg or { 0.04, 0.04, 0.05, 0.98 }
            if ns.UI_ApplyBorderlessSurface then
                ns.UI_ApplyBorderlessSurface(navRail, { railBg[1], railBg[2], railBg[3], railBg[4] or 0.98 })
            elseif ApplyVisuals then
                ApplyVisuals(navRail, { railBg[1], railBg[2], railBg[3], railBg[4] or 0.98 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.12 })
                if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(navRail) end
            end
        end
        local railDivider = navRail:CreateTexture(nil, "OVERLAY")
        local ac = COLORS.accent or { 0.6, 0.4, 1 }
        local divA = MAIN_SHELL_LAYOUT.NAV_RAIL_DIVIDER_ALPHA or 0.55
        railDivider:SetColorTexture(ac[1], ac[2], ac[3], divA)
        railDivider:SetWidth(1)
        railDivider:SetPoint("TOPRIGHT", navRail, "TOPRIGHT", 0, -4)
        railDivider:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", 0, 4)
        f._wnNavRailDivider = railDivider
        f.navRail = navRail
        f._wnGoldenRailWidth = railW
        if navRail.SetClipsChildren then
            navRail:SetClipsChildren(true)
        end

        local railPad = RAIL_PAD
        navRailScroll = CreateFrame("ScrollFrame", nil, navRail)
        navRailScroll:SetPoint("TOPLEFT", navRail, "TOPLEFT", railPad, -railPad)
        navRailScroll:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", -railPad, railPad)
        navRailScroll:EnableMouseWheel(true)
        navRailScroll:SetScript("OnMouseWheel", function(scrollSelf, delta)
            local rng = scrollSelf.GetVerticalScrollRange and scrollSelf:GetVerticalScrollRange() or 0
            if rng <= 0 then return end
            local step = math.max(RAIL_TAB_H + RAIL_TAB_V_GAP, 24)
            local cur = scrollSelf:GetVerticalScroll() or 0
            local nxt = cur + (delta > 0 and -step or step)
            if nxt < 0 then nxt = 0 end
            if nxt > rng then nxt = rng end
            scrollSelf:SetVerticalScroll(nxt)
        end)

        navRailStrip = CreateFrame("Frame", nil, navRailScroll)
        navRailStrip:SetWidth(math.max(80, railW - (railPad * 2)))
        navRailStrip:SetHeight(1)
        navRailScroll:SetScrollChild(navRailStrip)

        navRailScroll:SetScript("OnSizeChanged", function()
            RefreshMainNavRailStrip(f)
            if f.currentTab then
                ScrollMainNavEnsureTabVisible(f, f.currentTab)
            end
        end)
        navRailStrip:SetScript("OnSizeChanged", function()
            RefreshMainNavRailStrip(f)
        end)

        f.navRailScroll = navRailScroll
        f.navRailStrip = navRailStrip
    else
        f.navRail = nil
        f.navRailScroll = nil
        f.navRailStrip = nil
    end

    -- Horizontal strip host (`top`) or discarded placeholder (`rail`; tabs attach to navRail).
    local nav = CreateFrame("Frame", nil, f)
    if navLayoutMode == "rail" then
        nav:SetHeight(1)
        nav:Hide()
    else
        nav:SetHeight(MAIN_SHELL_LAYOUT.NAV_BAR_HEIGHT or 36)
        nav:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -headerNavGap)
        nav:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -headerNavGap)
    end
    f.nav = nav
    f.tabNavScroll = nil
    f.tabNavStrip = nil
    if navLayoutMode ~= "rail" then
        local tabNavScroll = CreateFrame("ScrollFrame", nil, nav)
        tabNavScroll:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
        tabNavScroll:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", 0, 0)
        tabNavScroll:EnableMouseWheel(true)
        tabNavScroll:SetScript("OnMouseWheel", function(scrollSelf, delta)
            local rng = scrollSelf.GetHorizontalScrollRange and scrollSelf:GetHorizontalScrollRange() or 0
            if rng <= 0 then return end
            local step = math.max(48, math.floor((scrollSelf:GetWidth() or 400) * 0.22))
            local cur = scrollSelf:GetHorizontalScroll() or 0
            local nxt = cur + (delta > 0 and -step or step)
            if nxt < 0 then nxt = 0 end
            if nxt > rng then nxt = rng end
            scrollSelf:SetHorizontalScroll(nxt)
        end)

        local navBarStripH = nav:GetHeight() or MAIN_SHELL_LAYOUT.NAV_BAR_HEIGHT or 36
        local tabNavStrip = CreateFrame("Frame", nil, tabNavScroll)
        tabNavStrip:SetHeight(navBarStripH)
        tabNavScroll:SetScrollChild(tabNavStrip)

        tabNavScroll:SetScript("OnSizeChanged", function()
            RefreshMainNavLayout(f)
        end)
        tabNavStrip:SetScript("OnSizeChanged", function()
            RefreshMainNavLayout(f)
        end)

        f.tabNavScroll = tabNavScroll
        f.tabNavStrip = tabNavStrip
    end
    -- Default tab set here; overridden by ShowMainWindow with persisted lastTab
    f.currentTab = "chars"
    f.tabButtons = {}
    f._tabScrollPositions = {}
    
    -- Tab sizing (defaults from MAIN_SHELL; narrow windows rely on horizontal scroll / padding)
    local DEFAULT_TAB_WIDTH = MAIN_SHELL_LAYOUT.DEFAULT_TAB_WIDTH or 108
    local TAB_HEIGHT = MAIN_SHELL_LAYOUT.TAB_HEIGHT or 34
    local TAB_PAD = MAIN_SHELL_LAYOUT.TAB_PAD or 24
    local TAB_GAP = MAIN_SHELL_LAYOUT.TAB_GAP or 5
    local railLayout = navLayoutMode == "rail"
    local railInnerBtnW = railLayout and math.max(80, railW - (RAIL_PAD * 2)) or 0
    local RAIL_LABEL_PAD = MAIN_SHELL_LAYOUT.NAV_RAIL_LABEL_PAD_H or 6
    local RAIL_ICON_INSET = MAIN_SHELL_LAYOUT.NAV_RAIL_ICON_INSET or 8
    
        local function CreateTabButton(parent, text, key)
        -- Main nav tabs: icon + label (`rail` and `top`).
        local btn = CreateFrame("Button", nil, parent)
        local shellIco = MAIN_SHELL_LAYOUT
        local iconSz = railLayout and (shellIco.RAIL_TAB_ICON_SIZE or 22) or (shellIco.TAB_ICON_SIZE or 18)
        local iconInsetL = railLayout and RAIL_ICON_INSET or (shellIco.TAB_ICON_LEFT_INSET or 8)
        local iconGap = shellIco.TAB_ICON_GAP or 6
        local iconRight = shellIco.TAB_ICON_RIGHT_MARGIN or 8
        local iconBlock = iconInsetL + iconSz + iconGap

        if railLayout then
            btn:SetSize(railInnerBtnW, RAIL_TAB_H)
        else
            btn:SetSize(DEFAULT_TAB_WIDTH, TAB_HEIGHT)
        end
        btn.key = key
        btn._wnRailTextMode = railLayout or nil

        -- Background (rail: flat; top: standard chrome)
        if railLayout then
            if ns.UI_ApplyBorderlessSurface then
                ns.UI_ApplyBorderlessSurface(btn, { 0.08, 0.08, 0.10, 0.45 })
            elseif ApplyVisuals then
                ApplyVisuals(btn, { 0.08, 0.08, 0.10, 0.45 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.1 })
                if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(btn) end
            end
        elseif ApplyVisuals then
            ApplyVisuals(btn, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
        end
        
        -- Apply highlight effect (safe check for Factory)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end
        
        -- Active indicator strip: bottom (`top`) or leading edge (`rail`)
        local accentColorLine = COLORS.accent
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetColorTexture(accentColorLine[1], accentColorLine[2], accentColorLine[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar
        if railLayout then
            activeBar:SetWidth(3)
            activeBar:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, -3)
            activeBar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 3)
        else
            activeBar:SetHeight(3)
            activeBar:SetPoint("BOTTOMLEFT", 8, 4)
            activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        end

        -- Left nav glyph (WOW atlas bundle)
        local tabIcon = btn:CreateTexture(nil, "ARTWORK")
        tabIcon:SetSize(iconSz, iconSz)
        tabIcon:SetPoint("LEFT", btn, "LEFT", iconInsetL, 0)
        if tabIcon.SetSnapToPixelGrid then tabIcon:SetSnapToPixelGrid(false) end
        if tabIcon.SetTexelSnappingBias then tabIcon:SetTexelSnappingBias(0) end
        btn.tabIcon = tabIcon
        if ns.UI_ApplyMainNavTabGlyph then
            ns.UI_ApplyMainNavTabGlyph(tabIcon, key)
        else
            local atlasNm = ns.UI_GetTabIcon and ns.UI_GetTabIcon(key) or nil
            local atlasOk = atlasNm and type(atlasNm) == "string" and pcall(tabIcon.SetAtlas, tabIcon, atlasNm, false)
            if not atlasOk then
                tabIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                tabIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end

        local label = FontManager:CreateFontString(btn, FontManager:GetFontRole("mainNavTabLabel"), "OVERLAY")
        local countReserve = shellIco.TAB_COUNT_RESERVE or 28
        if railLayout then
            label:SetPoint("LEFT", tabIcon, "RIGHT", iconGap, 0)
            label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText(text)
            label:SetTextColor(1, 1, 1)
        else
            label:SetPoint("LEFT", tabIcon, "RIGHT", iconGap, 1)
            label:SetPoint("RIGHT", btn, "RIGHT", -(iconRight + countReserve), 1)
            label:SetJustifyH("LEFT")
            label:SetText(text)
        end
        btn.label = label

        -- Row count badge (dimmed)
        local countLabel = FontManager:CreateFontString(btn, FontManager:GetFontRole("mainNavTabCount"), "OVERLAY")
        countLabel:SetJustifyH("RIGHT")
        countLabel:SetTextColor(0.5, 0.5, 0.5, 0.8)
        countLabel:SetText("")
        countLabel:Hide()
        btn.countLabel = countLabel
        if railLayout then
            countLabel:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        else
            countLabel:SetPoint("RIGHT", btn, "RIGHT", -iconRight, 1)
        end

        if not railLayout then
            local tw = label:GetStringWidth() or 0
            local reserve = iconBlock + tw + iconRight + countReserve + 4
            if tw + TAB_PAD > DEFAULT_TAB_WIDTH or reserve > DEFAULT_TAB_WIDTH then
                btn:SetWidth(math.max(DEFAULT_TAB_WIDTH, reserve))
            end
        end

        btn:SetScript("OnClick", function(self)
            -- Skip if this tab is already selected (avoid redundant refresh)
            if f.currentTab == self.key then return end
            -- Brief post-open window: ignore nav clicks so the opening click cannot land on another tab (gear → chars).
            if GetTime() < (f._wnMainTabInputGraceUntil or 0) then
                if f._wnBypassMainTabInputGraceOnce then
                    f._wnBypassMainTabInputGraceOnce = nil
                else
                    return
                end
            end

            -- Invalidate any in-flight tab-switch timers (rapid clicks); paired with checks inside C_Timer callbacks.
            f._tabSwitchGen = (f._tabSwitchGen or 0) + 1
            local tabSwitchGen = f._tabSwitchGen
            local targetTab = self.key

            -- Drop pending event-driven populates from before this click; absorb follow-up message bursts
            -- (~100ms debounce) that would otherwise run a redundant same-tab PopulateContent right after paint.
            if f.AbortPendingPopulateDebounce then
                f:AbortPendingPopulateDebounce()
            end
            -- Suppress redundant debounced PopulateContent on the destination tab shortly after main-tab paint
            -- (debounce 100ms + event latency can fire after a wall-clock "until" window; use switch-relative time).
            f._wnLastMainTabSwitchAt = GetTime()
            f._wnLastMainTabSwitchKey = targetTab

            local previousTab = f.currentTab

            -- Dev-only: main tab switch timings (debugprofilestop ms); see IsTabPerfMonitorEnabled (see pool/populate hooks below).
            if IsTabPerfMonitorEnabled() then
                f._wnPerfMainTabSwitch = {
                    gen = tabSwitchGen,
                    fromTab = previousTab,
                    toTab = targetTab,
                }
                debugprofilestart()
            else
                f._wnPerfMainTabSwitch = nil
            end

            -- Save scroll position of the tab we're leaving
            if previousTab and f.scroll then
                if not f._tabScrollPositions then f._tabScrollPositions = {} end
                f._tabScrollPositions[previousTab] = {
                    v = f.scroll:GetVerticalScroll() or 0,
                    h = f.scroll:GetHorizontalScroll() or 0,
                }
            end

            f.currentTab = self.key

            -- PERFORMANCE: Update tab bar visuals immediately so user sees switch without waiting for content
            UpdateTabButtonStates(f)
            ScrollMainNavEnsureTabVisible(f, targetTab)

            -- Persist selected tab (profile + session: session drives same-login hide/show)
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = self.key
            end
            RememberSessionMainTab(self.key)

            -- Clear session-only collection metadata when leaving Plans (free RAM, avoid bloat)
            if previousTab == "plans" and WarbandNexus.ClearCollectionMetadataCache then
                WarbandNexus:ClearCollectionMetadataCache()
            end
            
            -- ABORT PROTOCOL: Cancel all async operations from previous tab
            -- This prevents race conditions when user switches tabs rapidly
            if WarbandNexus.AbortTabOperations then
                WarbandNexus:AbortTabOperations(previousTab)
            end
            
            -- Flag that this is a MAIN tab switch (not a sub-tab or refresh)
            f.isMainTabSwitch = true
            
            -- Clear all search boxes when switching main tabs
            ClearAllSearchBoxes()
            
            -- Close any open plan dialogs when switching tabs (if function exists)
            if WarbandNexus.CloseAllPlanDialogs then
                WarbandNexus:CloseAllPlanDialogs()
            end
            -- PERFORMANCE: Frame 1 — pool release + detach old tab content; Frame 2 — PopulateContent.
            -- "click->pool" in tab perf logs is dominated by ReleasePooledRowsInSubtree on the previous tab's
            -- scrollChild (Items/Reputations/etc. pooled rows), not Gear character-dropdown entry pooling.
            -- Keeps teardown and full redraw off the same frame (reduces hitch on heavy tabs).
            -- When leaving Gear, defer pool release one extra idle tick so the first PopulateContent of the
            -- destination tab is not stacked on the same scheduler turn as Gear's pooled subtree teardown.
            -- Characters -> Gear: one extra idle tick before pool so the first Gear PopulateContent is not on
            -- the same turn as the tab-switch callback that only schedules work (matches staged Gear UI paint).
            C_Timer.After(0, function()
                if tabSwitchGen ~= f._tabSwitchGen then
                    local pStale = f._wnPerfMainTabSwitch
                    if pStale and pStale.gen == tabSwitchGen then
                        f._wnPerfMainTabSwitch = nil
                        debugprofilestop()
                    end
                    return
                end
                if f.currentTab ~= targetTab then
                    local pStale = f._wnPerfMainTabSwitch
                    if pStale and pStale.gen == tabSwitchGen then
                        f._wnPerfMainTabSwitch = nil
                        debugprofilestop()
                    end
                    return
                end
                local function runPoolReleaseOnly()
                    local scrollChild = f.scrollChild
                    if scrollChild then
                        local nc = PackVariadicInto(_uiChildEnumScratch, scrollChild:GetChildren())
                        for i = 1, nc do
                            local child = _uiChildEnumScratch[i]
                            if ReleasePooledRowsInSubtree then
                                ReleasePooledRowsInSubtree(child)
                            end
                            if child.isPersistentRowElement then
                                child:Hide()
                            elseif not child._wnKeepOnTabSwitch then
                                child:Hide()
                                child:SetParent(recycleBin)
                            end
                        end
                        f._contentPreCleared = true
                    end
                end

                local function schedulePopulateAfterPoolPerf()
                    local pAfterPool = f._wnPerfMainTabSwitch
                    if pAfterPool and pAfterPool.gen == tabSwitchGen and f.currentTab == targetTab then
                        if IsTabPerfMonitorEnabled() then
                            pAfterPool.msClickToPoolEnd = debugprofilestop()
                            debugprofilestart()
                        else
                            f._wnPerfMainTabSwitch = nil
                            debugprofilestop()
                        end
                    end
                    C_Timer.After(0, function()
                        if tabSwitchGen ~= f._tabSwitchGen then
                            local pStale = f._wnPerfMainTabSwitch
                            if pStale and pStale.gen == tabSwitchGen and pStale.msClickToPoolEnd then
                                f._wnPerfMainTabSwitch = nil
                                f._wnPerfTabSwitchPendingLog = nil
                                debugprofilestop()
                            end
                            return
                        end
                        if f.currentTab ~= targetTab then
                            local pStale = f._wnPerfMainTabSwitch
                            if pStale and pStale.gen == tabSwitchGen and pStale.msClickToPoolEnd then
                                f._wnPerfMainTabSwitch = nil
                                f._wnPerfTabSwitchPendingLog = nil
                                debugprofilestop()
                            end
                            return
                        end
                        local pBeforePop = f._wnPerfMainTabSwitch
                        if pBeforePop and pBeforePop.gen == tabSwitchGen and pBeforePop.msClickToPoolEnd then
                            if IsTabPerfMonitorEnabled() then
                                f._wnPerfTabSwitchPendingLog = tabSwitchGen
                            else
                                f._wnPerfMainTabSwitch = nil
                                debugprofilestop()
                            end
                        end
                        WarbandNexus:PopulateContent()
                        f.isMainTabSwitch = false
                    end)
                end

                local function runPoolReleaseAndSchedulePopulate()
                    runPoolReleaseOnly()
                    schedulePopulateAfterPoolPerf()
                end

                if previousTab == "gear" and targetTab ~= "gear" then
                    C_Timer.After(0, function()
                        if tabSwitchGen ~= f._tabSwitchGen then
                            local pStale = f._wnPerfMainTabSwitch
                            if pStale and pStale.gen == tabSwitchGen then
                                f._wnPerfMainTabSwitch = nil
                                debugprofilestop()
                            end
                            return
                        end
                        if f.currentTab ~= targetTab then
                            local pStale = f._wnPerfMainTabSwitch
                            if pStale and pStale.gen == tabSwitchGen then
                                f._wnPerfMainTabSwitch = nil
                                debugprofilestop()
                            end
                            return
                        end
                        local P = ns.Profiler
                        if P and P.enabled and P.StartSlice and P.StopSlice then
                            P:StartSlice(P.CAT.UI, "Pop_tabPoolLeaveGear_deferred")
                        end
                        runPoolReleaseOnly()
                        if P and P.enabled and P.StartSlice and P.StopSlice then
                            P:StopSlice(P.CAT.UI, "Pop_tabPoolLeaveGear_deferred")
                        end
                        schedulePopulateAfterPoolPerf()
                    end)
                elseif previousTab == "chars" and targetTab == "gear" then
                    -- Extra idle tick before pool+PopulateContent: entering Gear after Characters
                    -- avoids stacking chars subtree pool release on the same scheduler turn as the first Gear draw.
                    C_Timer.After(0, function()
                        if tabSwitchGen ~= f._tabSwitchGen then
                            local pStale = f._wnPerfMainTabSwitch
                            if pStale and pStale.gen == tabSwitchGen then
                                f._wnPerfMainTabSwitch = nil
                                debugprofilestop()
                            end
                            return
                        end
                        if f.currentTab ~= targetTab then
                            local pStale = f._wnPerfMainTabSwitch
                            if pStale and pStale.gen == tabSwitchGen then
                                f._wnPerfMainTabSwitch = nil
                                debugprofilestop()
                            end
                            return
                        end
                        local P = ns.Profiler
                        if P and P.enabled and P.StartSlice and P.StopSlice then
                            P:StartSlice(P.CAT.UI, "Pop_tabPool_charsToGear_deferred")
                        end
                        runPoolReleaseAndSchedulePopulate()
                        if P and P.enabled and P.StartSlice and P.StopSlice then
                            P:StopSlice(P.CAT.UI, "Pop_tabPool_charsToGear_deferred")
                        end
                    end)
                else
                    runPoolReleaseAndSchedulePopulate()
                end
            end)
        end)

        return btn
    end
    
    -- Tab labels keyed by MAIN_TAB_ORDER (single source of truth)
    local TAB_LABELS = {
        chars       = (ns.L and ns.L["TAB_CHARACTERS"]) or "Characters",
        items       = (ns.L and ns.L["TAB_ITEMS"]) or "Items",
        gear        = (ns.L and ns.L["TAB_GEAR"]) or "Gear",
        currency    = (ns.L and ns.L["TAB_CURRENCIES"]) or "Currencies",
        reputations = (ns.L and ns.L["TAB_REPUTATIONS"]) or "Reputations",
        pve         = (ns.L and ns.L["TAB_PVE"]) or "PvE",
        professions = (ns.L and ns.L["TAB_PROFESSIONS"]) or "Professions",
        collections = (ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections",
        plans       = (ns.L and ns.L["TAB_PLANS"]) or "To-Do",
        stats       = (ns.L and ns.L["TAB_STATISTICS"]) or "Statistics",
    }
    
    -- Create tabs: horizontal strip (`top`) or compact vertical rail (`rail` + vertical scroll).
    local navHostForTabs = (navLayoutMode == "rail" and navRailStrip) or f.tabNavStrip or nav
    local prevBtn = nil
    for i = 1, #MAIN_TAB_ORDER do
        local key = MAIN_TAB_ORDER[i]
        local btn = CreateTabButton(navHostForTabs, TAB_LABELS[key], key)
        if prevBtn then
            if railLayout then
                btn:SetPoint("TOP", prevBtn, "BOTTOM", 0, -RAIL_TAB_V_GAP)
            else
                btn:SetPoint("LEFT", prevBtn, "RIGHT", TAB_GAP, 0)
            end
        else
            if railLayout then
                btn:SetPoint("TOP", navHostForTabs, "TOP", 0, -RAIL_TOP_INSET)
            else
                btn:SetPoint("LEFT", navHostForTabs, "LEFT", 10, 0)
            end
        end
        f.tabButtons[key] = btn
        prevBtn = btn
    end
    
    UpdateTabVisibility(f)
    if railLayout then
        ApplyMainNavGoldenShellLayout(f)
        RefreshMainNavRailStrip(f)
    else
        RefreshMainNavTabStrip(f)
    end

    -- Function to update tab colors dynamically
    f.UpdateTabColors = function()
        local freshColors = ns.UI_COLORS
        local accentColor = freshColors.accent
        for ti = 1, #MAIN_TAB_ORDER do
            local btn = f.tabButtons[MAIN_TAB_ORDER[ti]]
            if btn then
                if btn.activeBar then
                    btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
                end

                -- Update colors based on active state (same as Plans tabs)
                if btn.active then
                    btn:SetBackdropColor(accentColor[1] * 0.3, accentColor[2] * 0.3, accentColor[3] * 0.3, 1)
                    btn:SetBackdropBorderColor(accentColor[1], accentColor[2], accentColor[3], 1)
                else
                    btn:SetBackdropColor(0.12, 0.12, 0.15, 1)
                    btn:SetBackdropBorderColor(accentColor[1] * 0.8, accentColor[2] * 0.8, accentColor[3] * 0.8, 1)
                end
            end
        end
    end
    
    -- Footer strip (text + version): MAIN_FOOTER_H + CONTENT_BOTTOM_OFFSET defined above rail shell.

    -- ===== CONTENT AREA =====
    -- Factory candidate: `Factory:CreateContainer` — inherits `BackdropTemplate` mixin immediately below for panel BG tint.
    local content = CreateFrame("Frame", nil, f)
    if navLayoutMode == "rail" and navRail then
        content:SetPoint("TOPLEFT", navRail, "TOPRIGHT", RAIL_CONTENT_GAP, 0)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, CONTENT_BOTTOM_OFFSET)
    else
        content:SetPoint("TOPLEFT", nav, "BOTTOMLEFT", 8, -8)
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, CONTENT_BOTTOM_OFFSET)
    end
    f.content = content
    if content.SetClipsChildren then
        content:SetClipsChildren(true)
    end

    -- Background only on content (no border); border will be on viewport frame so scrollbars sit outside it
    if not content.SetBackdrop then
        Mixin(content, BackdropTemplateMixin)
    end
    content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    do
        local bc = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
            or (ns.UI_COLORS and ns.UI_COLORS.bg)
            or { 0.042, 0.042, 0.055, 0.98 }
        content:SetBackdropColor(bc[1], bc[2], bc[3], bc[4] or 0.98)
    end

    -- Scroll layout: MAIN_SCROLL tokens + scrollbar column (WN-UI-layout: reserve v-bar column).
    -- Keep defaults aligned with `ns.UI_GetMainScrollLayoutHints` (Plans Tracker + popups parity).
    local LAYOUT = ns.UI_LAYOUT or ns.UI_SPACING or {}
    local scrollHints = ns.UI_GetMainScrollLayoutHints and ns.UI_GetMainScrollLayoutHints() or {}
    local MSC = LAYOUT.MAIN_SCROLL or {}
    local SCROLL_COLUMN_W = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
    local SCROLL_GAP = MSC.SCROLL_GAP or scrollHints.scrollGap or 2
    local SCROLL_INSET_TOP = MSC.CONTENT_PAD_TOP or LAYOUT.SCROLL_CONTENT_TOP_PADDING or 10
    local H_ROW_H = SCROLL_COLUMN_W
    local H_BAR_BOTTOM = MSC.H_BAR_BOTTOM_OFFSET or 6
    local SCROLL_INSET_BOTTOM = H_BAR_BOTTOM + H_ROW_H + SCROLL_GAP
    local SCROLL_INSET_LEFT = MSC.SCROLL_INSET_LEFT or 4
    --- Same total as Tracker / Recipe Companion: `scrollbarColumnWidth + MAIN_SCROLL.SCROLL_GAP` via SharedWidgets helper.
    local SCROLL_INSET_RIGHT = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
        or (SCROLL_COLUMN_W + SCROLL_GAP)
    local BORDER_INSET = MSC.VIEWPORT_BORDER_INSET or 1

    -- Factory candidate: `Factory:CreateContainer` — viewport rim (scroll insets anchor to this).
    local viewportBorder = CreateFrame("Frame", nil, content)
    viewportBorder:SetPoint("TOPLEFT", content, "TOPLEFT", SCROLL_INSET_LEFT, -SCROLL_INSET_TOP)
    viewportBorder:SetPoint("TOPRIGHT", content, "TOPRIGHT", -SCROLL_INSET_RIGHT, -SCROLL_INSET_TOP)
    viewportBorder:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", SCROLL_INSET_LEFT, SCROLL_INSET_BOTTOM)
    viewportBorder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -SCROLL_INSET_RIGHT, SCROLL_INSET_BOTTOM)
    viewportBorder:SetFrameLevel(content:GetFrameLevel() + 1)
    if not viewportBorder.SetBackdrop then
        Mixin(viewportBorder, BackdropTemplateMixin)
    end
    viewportBorder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    do
        local vp = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
            or (ns.UI_COLORS and ns.UI_COLORS.bg)
            or { 0.042, 0.042, 0.055, 0.98 }
        viewportBorder:SetBackdropColor(vp[1], vp[2], vp[3], vp[4] or 0.98)
    end
    if ns.UI_ApplyViewportAtlasUnderlay then
        ns.UI_ApplyViewportAtlasUnderlay(viewportBorder)
    end
    if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(viewportBorder) end
    f.viewportBorder = viewportBorder

    -- Factory candidate: `Factory:CreateContainer` — non-scroll title/search host.
    local fixedHeader = CreateFrame("Frame", nil, content)
    fixedHeader:SetPoint("TOPLEFT", content, "TOPLEFT", SCROLL_INSET_LEFT, 0)
    fixedHeader:SetPoint("TOPRIGHT", content, "TOPRIGHT", -SCROLL_INSET_RIGHT, 0)
    fixedHeader:SetHeight(1)
    fixedHeader:SetFrameLevel(viewportBorder:GetFrameLevel() + 1)
    f.fixedHeader = fixedHeader

    -- Factory candidate: clip host for frozen column headers (`SetClipsChildren`).
    local columnHeaderClip = CreateFrame("Frame", nil, content)
    columnHeaderClip:SetClipsChildren(true)
    columnHeaderClip:SetPoint("TOPLEFT", fixedHeader, "BOTTOMLEFT", 0, 0)
    columnHeaderClip:SetPoint("TOPRIGHT", fixedHeader, "BOTTOMRIGHT", 0, 0)
    columnHeaderClip:SetHeight(1)
    columnHeaderClip:SetFrameLevel(viewportBorder:GetFrameLevel() + 5)
    f.columnHeaderClip = columnHeaderClip

    local columnHeaderBg = columnHeaderClip:CreateTexture(nil, "BACKGROUND")
    columnHeaderBg:SetAllPoints()
    columnHeaderBg:SetColorTexture(0, 0, 0, 0)

    -- Factory candidate: scroll-synced inner width host (`SetHorizontalScroll` hook anchors this).
    local columnHeaderInner = CreateFrame("Frame", nil, columnHeaderClip)
    columnHeaderInner:SetPoint("TOPLEFT", 0, 0)
    columnHeaderInner:SetPoint("BOTTOMLEFT", 0, 0)
    columnHeaderInner:SetWidth(1)
    f.columnHeaderInner = columnHeaderInner

    local scroll = ns.UI.Factory:CreateScrollFrame(content, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", fixedHeader, "BOTTOMLEFT", 0, 0)
    scroll:SetPoint("TOPRIGHT", fixedHeader, "BOTTOMRIGHT", 0, 0)
    scroll:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", SCROLL_INSET_LEFT, SCROLL_INSET_BOTTOM)
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -SCROLL_INSET_RIGHT, SCROLL_INSET_BOTTOM)
    scroll:SetFrameLevel(viewportBorder:GetFrameLevel() + 1)
    f.scroll = scroll

    -- Vertical bar column: outside viewport border, same vertical range as scroll; button-to-button alignment
    local scrollBarColumn = ns.UI.Factory:CreateScrollBarColumn(content, SCROLL_COLUMN_W, SCROLL_INSET_TOP, SCROLL_INSET_BOTTOM)
    scrollBarColumn:SetFrameLevel(viewportBorder:GetFrameLevel() + 2)
    f.scrollBarColumn = scrollBarColumn
    if scroll.ScrollBar and ns.UI.Factory.PositionScrollBarInContainer then
        ns.UI.Factory:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
    end

    -- Factory candidate: scroll child is a dumb host; only bottom-fill band (`scrollChild._wnScrollBottomFill`) matters for Factory parity.
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    -- Horizontal bar: strip height tracks vertical scrollbar column width (`H_ROW_H`); viewport gap (`SCROLL_GAP`) matches main scroll chrome.
    -- Factory candidate: `Factory:CreateContainer` — bar strip host only (`CreateHorizontalScrollBar` does the knob).
    local hScrollContainer = CreateFrame("Frame", nil, content)
    hScrollContainer:SetPoint("LEFT", content, "LEFT", SCROLL_INSET_LEFT, 0)
    hScrollContainer:SetPoint("RIGHT", content, "RIGHT", -SCROLL_INSET_RIGHT, 0)
    hScrollContainer:SetPoint("BOTTOM", content, "BOTTOM", 0, H_BAR_BOTTOM)
    hScrollContainer:SetHeight(H_ROW_H)
    hScrollContainer:SetFrameLevel(viewportBorder:GetFrameLevel() + 2)
    f.hScrollContainer = hScrollContainer

    if ns.UI.Factory and ns.UI.Factory.CreateHorizontalScrollBar then
        local hScroll = ns.UI.Factory:CreateHorizontalScrollBar(scroll, hScrollContainer, true)
        if hScroll and hScroll.PositionInContainer then
            hScroll:PositionInContainer(hScrollContainer, 0)
            f.hScroll = hScroll
        end
    end

    -- Sync column header horizontal offset with main scroll frame.
    -- Every call to SetHorizontalScroll (scrollbar drag, Shift+wheel, button click,
    -- tab-switch restore) automatically repositions the frozen column header.
    local origSetHScroll = scroll.SetHorizontalScroll
    scroll.SetHorizontalScroll = function(self, value)
        origSetHScroll(self, value)
        if f.columnHeaderInner and f.columnHeaderClip then
            f.columnHeaderInner:ClearAllPoints()
            f.columnHeaderInner:SetPoint("TOPLEFT", f.columnHeaderClip, "TOPLEFT", -(value or 0), 0)
            f.columnHeaderInner:SetPoint("BOTTOMLEFT", f.columnHeaderClip, "BOTTOMLEFT", -(value or 0), 0)
        end
    end

    -- Pixel-snap scroll: snap every scroll offset to the nearest physical pixel boundary.
    -- Without this, scrollChild sits at sub-pixel positions (e.g., 123.456) causing ALL
    -- child frames to render with anti-aliasing — visible as wobbling/jittering borders.
    local origOnScroll = scroll:GetScript("OnVerticalScroll")
    local isSnappingScroll = false
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        if not (ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(f)) then
            if f.currentTab == "chars" and ns.UI_CloseCharacterTabFlyoutMenus then
                ns.UI_CloseCharacterTabFlyoutMenus()
            end
        end
        local PixelSnap = ns.PixelSnap
        if PixelSnap and not isSnappingScroll then
            local snapped = PixelSnap(offset)
            if math.abs(snapped - offset) > 0.001 then
                isSnappingScroll = true
                self:SetVerticalScroll(snapped)
                isSnappingScroll = false
                return
            end
        end
        if origOnScroll then origOnScroll(self, offset) end
        -- Characters corner-drag: live adapter relayouts visible rows; full VLM cull causes flicker.
        local skipVirtualOnScroll = f.currentTab == "chars"
            and ns.UI_IsMainFrameResizing
            and ns.UI_IsMainFrameResizing(f)
        if f._virtualScrollUpdate and not skipVirtualOnScroll then
            f._virtualScrollUpdate()
        end
    end)

    -- Clip children to viewport so rows outside the visible area never bleed through
    scroll:SetClipsChildren(true)

    -- Note: scrollChild width is managed in PopulateContent() for consistency
    
    -- Store reference in WarbandNexus for cross-module access
    if not WarbandNexus.UI then
        WarbandNexus.UI = {}
    end
    WarbandNexus.UI.mainFrame = f
    
    -- ===== EVENT-DRIVEN UI UPDATES (DB-First Pattern) =====
    -- UI automatically refreshes when DB data changes.
    -- All listeners use SchedulePopulateContent() to coalesce rapid events
    -- (e.g., bank open fires WN_ITEMS_UPDATED + WN_BAGS_UPDATED + WN_ITEM_METADATA_READY
    -- within milliseconds -- without coalescing this causes 3+ PopulateContent calls).
    local Constants = ns.Constants
    
    local pendingPopulateTimer = nil
    local pendingPopulateSkipCooldown = false
    local populateDebounceGen = 0  -- Invalidates deferred callbacks after hide or superseding schedule (esp. C_Timer.After fallback)
    local POPULATE_DEBOUNCE = 0.1  -- 100ms coalesce window (resets on each new message = last event wins)
    local lastEventPopulateTime = 0
    local POPULATE_COOLDOWN = 0.8  -- Skip event-driven rebuild if one ran within 800ms
    -- This prevents duplicate rebuilds from WN_ITEMS_UPDATED (~0.5s) + WN_BAGS_UPDATED (~1.0s)
    -- firing for the same loot event. Does NOT affect direct PopulateContent calls (tab switch, resize).
    -- Profession events (concentration, knowledge, recipe) use skipCooldown so updates always show.
    -- GET_ITEM_INFO_RECEIVED / metadata warm-up can storm while the client resolves many links; throttle gear repaints.
    local MAIN_TAB_DEBOUNCED_QUIET = 0.45  -- Same-tab debounced populate after main-tab switch (see _wnLastMainTabSwitch*)
    local GEAR_ASYNC_ITEM_REPAINT_INTERVAL = 0.55
    local gearAsyncItemRepaintNext = 0
    -- Blizzard can fire GET_ITEM_INFO_RECEIVED many times per frame burst; never sync-redraw per event.
    local gearItemInfoCoalesceGen = 0
    local gearItemInfoCoalesceTimer = nil
    -- Coalesce Invalidate+Resolve+Redraw from rapid GEAR_UPDATED (e.g. paired ring swaps) into one pass per window.
    local GEAR_STORAGE_REC_REFRESH_DEBOUNCE = 0.06
    local gearStorageRecRefreshTimer = nil
    local gearStorageRecRefreshEquipOnly = false
    -- Bag/item DB merges: avoid full Gear tab teardown; refresh storage recommendations + paperdoll icons only.
    local GEAR_TAB_INV_NARROW_DEBOUNCE = 0.08
    local gearTabInvNarrowTimer = nil

    local function TryRunGearTabInventoryNarrowRefresh()
        if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
        if not WarbandNexus.IsStillOnTab or not WarbandNexus:IsStillOnTab("gear") then return end
        if WarbandNexus.IsGearStorageRecommendationsEnabled
            and not WarbandNexus:IsGearStorageRecommendationsEnabled() then
            if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                WarbandNexus:TryRefreshAllGearEquipSlotIcons()
            end
            return
        end
        local canon = f._gearPopulateCanonKey
        if not canon or not WarbandNexus.InvalidateGearStorageFindingsCacheForCanon then return end
        if WarbandNexus.ShouldSkipGearStorageNarrowInvalidateForRapidRescan
            and WarbandNexus:ShouldSkipGearStorageNarrowInvalidateForRapidRescan(canon) then
            local gen = ns._gearTabDrawGen or 0
            if WarbandNexus.RedrawGearStorageRecommendationsOnly then
                ns._gearStorageAllowEquipSigInvBypass = true
                WarbandNexus:RedrawGearStorageRecommendationsOnly(canon, gen, true)
                ns._gearStorageAllowEquipSigInvBypass = false
            end
            if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                WarbandNexus:TryRefreshAllGearEquipSlotIcons()
            end
            return
        end
        WarbandNexus:InvalidateGearStorageFindingsCacheForCanon(canon)
        local gen = ns._gearTabDrawGen or 0
        if WarbandNexus.IsGearStorageScanInFlightForCanon
            and WarbandNexus:IsGearStorageScanInFlightForCanon(canon) then
            -- Invalidate queued for ProcessDeferredGearStorageUpdates after the in-flight scan finishes.
        elseif WarbandNexus.ScheduleGearStorageFindingsResolve then
            WarbandNexus:ScheduleGearStorageFindingsResolve(canon, gen, function()
                C_Timer.After(0, function()
                    if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
                    local c2 = f._gearPopulateCanonKey
                    if not c2 then return end
                    if WarbandNexus.RedrawGearStorageRecommendationsOnly then
                        ns._gearStorageAllowEquipSigInvBypass = true
                        local ok = WarbandNexus:RedrawGearStorageRecommendationsOnly(c2, ns._gearTabDrawGen or 0, true)
                        ns._gearStorageAllowEquipSigInvBypass = false
                        if not ok then
                            SchedulePopulateContent(true)
                        end
                    else
                        SchedulePopulateContent(true)
                    end
                end)
            end)
        else
            SchedulePopulateContent(true)
            return
        end
        if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
            WarbandNexus:TryRefreshAllGearEquipSlotIcons()
        end
    end

    local function ScheduleGearTabInventoryNarrowRefresh()
        if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
        if gearTabInvNarrowTimer and gearTabInvNarrowTimer.Cancel then
            gearTabInvNarrowTimer:Cancel()
        end
        gearTabInvNarrowTimer = nil
        if C_Timer and C_Timer.NewTimer then
            gearTabInvNarrowTimer = C_Timer.NewTimer(GEAR_TAB_INV_NARROW_DEBOUNCE, function()
                gearTabInvNarrowTimer = nil
                TryRunGearTabInventoryNarrowRefresh()
            end)
        else
            TryRunGearTabInventoryNarrowRefresh()
        end
    end
    
    local function RunDebouncedPopulateTimerBody(myGen)
        pendingPopulateTimer = nil
        if myGen ~= populateDebounceGen then return end
        if not f or not f:IsShown() then return end
        if ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(f) then
            f._wnDeferredPopulateAfterResize = true
            return
        end
        -- Read once up-front: gear+defer gate used to clear this before evaluating skipCooldown,
        -- which dropped GET_ITEM_INFO_RECEIVED / ITEM_METADATA repaints for the entire storage defer window.
        local useSkip = pendingPopulateSkipCooldown
        pendingPopulateSkipCooldown = false
        if f.currentTab == "gear" and ns._gearStorageDeferAwaiting then
            local ac = ns._gearStorageDeferAwaitCanon
            local fc = f._gearPopulateCanonKey
            if ac and fc and ac == fc then
                local allowEquipRefresh = false
                if WarbandNexus.GetGearPopulateSignature then
                    local sigNow = WarbandNexus:GetGearPopulateSignature()
                    if sigNow and f._gearPopulateContentSig and sigNow ~= f._gearPopulateContentSig then
                        allowEquipRefresh = true
                    end
                end
                -- skipCooldown: item cache warm-up must repaint (icons + storage) even while storage scan defers.
                if not allowEquipRefresh and not useSkip then
                    return
                end
            end
        end
        if f._wnLastMainTabSwitchAt and f._wnLastMainTabSwitchKey == f.currentTab
            and (GetTime() - f._wnLastMainTabSwitchAt) < MAIN_TAB_DEBOUNCED_QUIET then
            return
        end
        local now = GetTime()
        if not useSkip and (now - lastEventPopulateTime) < POPULATE_COOLDOWN then
            return
        end
        lastEventPopulateTime = now
        local P = ns.Profiler
        local mlab = P and P.enabled and P.SliceLabel and P:SliceLabel(P.CAT.MSG, "EventPopulate_debounced")
        if mlab then P:Start(mlab) end
        WarbandNexus:PopulateContent()
        if mlab then P:Stop(mlab) end
    end

    local function SchedulePopulateContent(skipCooldown)
        if not f or not f:IsShown() then return end
        if skipCooldown then
            pendingPopulateSkipCooldown = true
        end
        if pendingPopulateTimer and pendingPopulateTimer.Cancel then
            pendingPopulateTimer:Cancel()
            pendingPopulateTimer = nil
        end
        populateDebounceGen = populateDebounceGen + 1
        local myGen = populateDebounceGen
        if C_Timer and C_Timer.NewTimer then
            pendingPopulateTimer = C_Timer.NewTimer(POPULATE_DEBOUNCE, function()
                RunDebouncedPopulateTimerBody(myGen)
            end)
            return
        end
        local afterHandle = C_Timer.After(POPULATE_DEBOUNCE, function()
            RunDebouncedPopulateTimerBody(myGen)
        end)
        if type(afterHandle) == "table" and afterHandle.Cancel then
            pendingPopulateTimer = afterHandle
        else
            pendingPopulateTimer = true
        end
    end

    function f:CancelPendingPopulateDebounce()
        populateDebounceGen = populateDebounceGen + 1
        if pendingPopulateTimer and pendingPopulateTimer.Cancel then
            pendingPopulateTimer:Cancel()
        end
        pendingPopulateTimer = nil
        pendingPopulateSkipCooldown = false
        lastEventPopulateTime = GetTime()
        if gearStorageRecRefreshTimer and gearStorageRecRefreshTimer.Cancel then
            gearStorageRecRefreshTimer:Cancel()
        end
        gearStorageRecRefreshTimer = nil
        if gearTabInvNarrowTimer and gearTabInvNarrowTimer.Cancel then
            gearTabInvNarrowTimer:Cancel()
        end
        gearTabInvNarrowTimer = nil
    end

    --- Kill only the pending debounce timer (no lastEventPopulateTime bump). Used on main-tab switch so
    --- stale WN_* coalescers from the previous tab cannot fire after we've already invalidated gen.
    function f:AbortPendingPopulateDebounce()
        populateDebounceGen = populateDebounceGen + 1
        if pendingPopulateTimer and pendingPopulateTimer.Cancel then
            pendingPopulateTimer:Cancel()
        end
        pendingPopulateTimer = nil
        pendingPopulateSkipCooldown = false
        if gearStorageRecRefreshTimer and gearStorageRecRefreshTimer.Cancel then
            gearStorageRecRefreshTimer:Cancel()
        end
        gearStorageRecRefreshTimer = nil
        if gearTabInvNarrowTimer and gearTabInvNarrowTimer.Cancel then
            gearTabInvNarrowTimer:Cancel()
        end
        gearTabInvNarrowTimer = nil
    end

    if ns.UI_LayoutCoordinator then
        ns.UI_LayoutCoordinator:RegisterShellCallbacks({
            updateScrollLayout = UpdateScrollLayout,
            applyGoldenRailLayout = ApplyMainNavGoldenShellLayout,
            refreshFixedHeaderChrome = RefreshFixedHeaderChrome,
            refreshNavTabStrip = RefreshMainNavLayout,
            scrollNavEnsureTabVisible = ScrollMainNavEnsureTabVisible,
            computeScrollContentWidth = ComputeScrollChildWidth,
            clampResizeBounds = function()
                if WarbandNexus.UI_ClampMainFrameResizeBoundsFromProfile then
                    WarbandNexus:UI_ClampMainFrameResizeBoundsFromProfile()
                end
            end,
            scheduleGeometryCommit = function(skipCooldown)
                SchedulePopulateContent(skipCooldown ~= false)
            end,
            schedulePopulateContent = SchedulePopulateContent,
        })
    end

    --- Coalesce rapid item-cache resolution events on the Gear tab (GET_ITEM_INFO_RECEIVED / metadata).
    local function ThrottledScheduleGearAsyncRepaint()
        if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
        local now = GetTime()
        if now < gearAsyncItemRepaintNext then return end
        gearAsyncItemRepaintNext = now + GEAR_ASYNC_ITEM_REPAINT_INTERVAL
        -- Narrow refresh: storage recommendations + paperdoll icons (avoid full Gear tab teardown on cache storms).
        ScheduleGearTabInventoryNarrowRefresh()
    end
    
    -- NOTE: All RegisterMessage calls use UIEvents as the 'self' key to avoid
    -- overwriting other modules' handlers for the same AceEvent message.
    -- AceEvent allows only ONE handler per (event, self) pair.
    -- Must bypass POPULATE_COOLDOWN: after login/alt switch, ITEMS_UPDATED etc. can set lastEventPopulateTime
    -- and this refresh would be dropped — leaving Character tab layout stale or visually broken.
    -- Gear tab rebuilds 3D paperdoll + full card — avoid skipCooldown (full populate every ~0.1s) on
    -- rapid WN_CHARACTER_UPDATED (e.g. item level ticks at 0.3s, DataService) or models appear to "flicker".
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_UPDATED, function(_, payload)
        if not f or not f:IsShown() then return end
        local tab = f.currentTab
        if tab ~= "chars" and tab ~= "stats" and tab ~= "gear" then return end
        -- Characters tab: avoid skipCooldown here — ilvl/zone/gold batching fires this often and full
        -- PopulateContent every ~100ms feels like a constant refresh (virtual rows make it more noticeable).
        if tab == "chars" then
            SchedulePopulateContent()
        elseif tab == "stats" then
            SchedulePopulateContent(true)
        elseif tab == "gear" then
            if payload and payload.dataType == "itemLevel" and payload.charKey
                and WarbandNexus.TryRefreshGearTabItemLevelOnly
                and WarbandNexus:TryRefreshGearTabItemLevelOnly(payload.charKey) then
                return
            end
            if f._gearCharUpdSuppressUntil and GetTime() < f._gearCharUpdSuppressUntil then
                return
            end
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ITEMS_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "gear") then
            -- Bank > Warband aggregate can sit on this tab while cache finishes; 800ms POPULATE_COOLDOWN
            -- otherwise drops the follow-up populate and the list looks empty until a tab switch.
            if f.currentTab == "items" and ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband" then
                SchedulePopulateContent(true)
            elseif f.currentTab == "gear" then
                ScheduleGearTabInventoryNarrowRefresh()
            else
                SchedulePopulateContent()
            end
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.GEAR_UPDATED, function(_, payload)
        if f and f:IsShown() and f.currentTab == "gear" then
            -- ScanEquippedGear always reports the logged-in character. If the Gear tab is showing
            -- another roster entry (offline alt), a full PopulateContent here only bumps drawGen,
            -- aborts in-flight storage Find, and leaves recommendations / loading veil stuck.
            local gearCanon = f._gearPopulateCanonKey
            if gearCanon and payload and payload.charKey then
                local U = ns.Utilities
                local pCanon = U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(payload.charKey) or payload.charKey
                local gCanon = U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(gearCanon) or gearCanon
                if pCanon and gCanon and pCanon ~= gCanon then
                    return
                end
            end
            local function runGearStorageRecRefreshNow()
                local equipOnly = gearStorageRecRefreshEquipOnly == true
                gearStorageRecRefreshEquipOnly = false
                gearStorageRecRefreshTimer = nil
                if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
                local gearCanon = f._gearPopulateCanonKey
                if not gearCanon then return end
                local gen = ns._gearTabDrawGen or 0
                if equipOnly then
                    if WarbandNexus.NotifyGearStorageEquipChanged then
                        WarbandNexus:NotifyGearStorageEquipChanged(gearCanon)
                    end
                    if WarbandNexus.IsGearStorageScanInFlightForCanon
                        and WarbandNexus:IsGearStorageScanInFlightForCanon(gearCanon) then
                        return
                    end
                    if WarbandNexus.TryRedrawGearStorageRecAfterEquipChange
                        and WarbandNexus:TryRedrawGearStorageRecAfterEquipChange(gearCanon, gen) then
                        return
                    end
                end
                if WarbandNexus.InvalidateGearStorageFindingsCacheForCanon then
                    WarbandNexus:InvalidateGearStorageFindingsCacheForCanon(gearCanon)
                end
                if WarbandNexus.IsGearStorageScanInFlightForCanon
                    and WarbandNexus:IsGearStorageScanInFlightForCanon(gearCanon) then
                    return
                end
                if WarbandNexus.ScheduleGearStorageFindingsResolve then
                    WarbandNexus:ScheduleGearStorageFindingsResolve(gearCanon, gen, function()
                        C_Timer.After(0, function()
                            if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
                            if WarbandNexus.RedrawGearStorageRecommendationsOnly then
                                ns._gearStorageAllowEquipSigInvBypass = true
                                WarbandNexus:RedrawGearStorageRecommendationsOnly(gearCanon, ns._gearTabDrawGen or 0, true)
                                ns._gearStorageAllowEquipSigInvBypass = false
                            end
                        end)
                    end)
                elseif WarbandNexus.TryGearStorageRedrawOnly then
                    WarbandNexus:TryGearStorageRedrawOnly()
                end
            end
            local function refreshStorageRec(equipOnly)
                gearStorageRecRefreshEquipOnly = equipOnly == true
                if gearStorageRecRefreshTimer and gearStorageRecRefreshTimer.Cancel then
                    gearStorageRecRefreshTimer:Cancel()
                end
                gearStorageRecRefreshTimer = nil
                local h = C_Timer.NewTimer(GEAR_STORAGE_REC_REFRESH_DEBOUNCE, runGearStorageRecRefreshNow)
                if type(h) == "table" and h.Cancel then
                    gearStorageRecRefreshTimer = h
                else
                    runGearStorageRecRefreshNow()
                end
            end
            local function redrawStorageRecAfterEquipOnly()
                local gearCanon = f._gearPopulateCanonKey
                local gen = ns._gearTabDrawGen or 0
                if gearCanon and WarbandNexus.TryRedrawGearStorageRecAfterEquipChange then
                    if WarbandNexus:TryRedrawGearStorageRecAfterEquipChange(gearCanon, gen) then
                        return
                    end
                end
                refreshStorageRec(true)
            end
            local recEnabled = WarbandNexus.IsGearStorageRecommendationsEnabled
                and WarbandNexus:IsGearStorageRecommendationsEnabled()
            local function trySlotRefresh(pl)
                if WarbandNexus.TryRefreshGearEquipSlotsOnly and WarbandNexus:TryRefreshGearEquipSlotsOnly(pl) then
                    if recEnabled then
                        redrawStorageRecAfterEquipOnly()
                    end
                    return true
                end
                if f._gearDeferChainActive and WarbandNexus.TryRefreshGearEquipSlotsOnly then
                    C_Timer.After(0.15, function()
                        if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
                        if WarbandNexus:TryRefreshGearEquipSlotsOnly(pl) then
                            if recEnabled then
                                redrawStorageRecAfterEquipOnly()
                            end
                        else
                            SchedulePopulateContent(true)
                        end
                    end)
                    return true
                end
                return false
            end
            if trySlotRefresh(payload) then
                return
            end
            SchedulePopulateContent(true)
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PVE_UPDATED, function()
        if not f or not f:IsShown() then return end
        -- PvE tab + Characters tab (mythic key column reads character row; mirror updates from PvECacheService)
        if f.currentTab == "pve" then
            -- Vault data arrives asynchronously via WEEKLY_REWARDS_UPDATE.
            -- Reset cooldown so this event is never silently dropped.
            lastEventPopulateTime = 0
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            lastEventPopulateTime = 0
            SchedulePopulateContent(true)
        end
    end)
    
    -- REMOVED: WARBAND_CURRENCIES_UPDATED — no SendMessage exists for this string; dead handler.

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "gear" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "currency" then
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            -- Total Gold / WoW Token card reads token price; refresh without 800ms cooldown drop.
            SchedulePopulateContent(true)
        else
            WarbandNexus:UpdateTabCountBadges("currency")
        end
    end)

    -- Reputation tab content: ReputationUI.lua registers DrawReputationTab for many WN_REPUTATION_* events.
    -- Tab badge count: refresh cheaply when cache updates without full PopulateContent if user is elsewhere.
    -- ReputationUI.lua redraws the tab on these when active; only refresh the tab button badge when elsewhere.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.REPUTATION_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab ~= "reputations" then
            WarbandNexus:UpdateTabCountBadges("reputations")
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.REPUTATION_CACHE_READY, function()
        if not f or not f:IsShown() then return end
        if f.currentTab ~= "reputations" then
            WarbandNexus:UpdateTabCountBadges("reputations")
        end
    end)
    
    -- WN_REPUTATION_* refresh: ReputationUI.lua registers DrawReputationTab (avoid double PopulateContent here)
    
    -- Plans / To-Do list must redraw immediately after add/remove (800ms POPULATE_COOLDOWN would drop the refresh).
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PLANS_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "plans" then
            SchedulePopulateContent(true)
        end
    end)
    
    -- Collection scan complete (plans/collections tab): skip cooldown so scan results show immediately
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function()
        if not f or not f:IsShown() then return end
        local tab = f.currentTab
        if tab ~= "plans" and tab ~= "collections" then return end
        SchedulePopulateContent(true)
    end)
    
    -- Profession tab: skip cooldown so concentration/knowledge/recipe updates always refresh (no stale data)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CONCENTRATION_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "professions" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.KNOWLEDGE_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "professions" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            SchedulePopulateContent()
        end
    end)
    
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.RECIPE_DATA_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CRAFTING_ORDERS_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_DATA_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    -- Profession equipment (slots 20/21/22): refresh when chars or professions tab visible so equipped gear updates in real time
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_COOLDOWNS_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "professions" then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.PROFESSION_EQUIPMENT_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "professions" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            SchedulePopulateContent()
        end
    end)
    
    -- BAGS_UPDATED also feeds the gear-tab recommendation scan (cross-character bag items
    -- are candidates) so newly looted BoEs surface without a manual reopen.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.BAGS_UPDATED, function()
        if f and f:IsShown() and (f.currentTab == "items" or f.currentTab == "gear") then
            if f.currentTab == "items" and ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband" then
                SchedulePopulateContent(true)
            elseif f.currentTab == "gear" then
                ScheduleGearTabInventoryNarrowRefresh()
            else
                SchedulePopulateContent()
            end
        end
    end)

    -- Money: chars Total Gold card, gear-tab affordability (gold-only upgrades).
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.MONEY_UPDATED, function()
        if not f or not f:IsShown() then return end
        if f.currentTab == "chars" or f.currentTab == "gear" then
            SchedulePopulateContent(true)
        end
    end)

    -- Currency variants: gear upgrade panel + currency tab depend on full currency state.
    local function refreshCurrency()
        if not f or not f:IsShown() then return end
        if f.currentTab == "gear" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "currency" then
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            -- Token card on Characters: coalesce with standard cooldown (was skipCooldown → rapid rebuilds).
            SchedulePopulateContent()
        else
            WarbandNexus:UpdateTabCountBadges("currency")
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCIES_UPDATED, refreshCurrency)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_GAINED, refreshCurrency)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CURRENCY_CACHE_READY, refreshCurrency)

    -- Collections: obtained/scan results + achievement tracking flips need to redraw cards.
    -- Plans tab also reads obtained state for try-counter rows; Statistics tab shows collection counts.
    local function refreshCollection()
        if not f or not f:IsShown() then return end
        if f.currentTab == "collections" or f.currentTab == "plans" or f.currentTab == "stats" then
            SchedulePopulateContent(true)
        elseif f.currentTab == "chars" then
            WarbandNexus:UpdateTabCountBadges("collections")
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTIBLE_OBTAINED, refreshCollection)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.COLLECTION_UPDATED, refreshCollection)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ACHIEVEMENT_TRACKING_UPDATED, refreshCollection)

    -- Vault: any vault data delta (slot completion, reward available, plan completion) must
    -- propagate to PvE tab (vault card) and chars-tab vault badge.
    local function refreshVault()
        if not f or not f:IsShown() then return end
        if f.currentTab == "pve" then
            lastEventPopulateTime = 0
            SchedulePopulateContent()
        elseif f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_CHECKPOINT_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_SLOT_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_PLAN_COMPLETED, refreshVault)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.VAULT_REWARD_AVAILABLE, refreshVault)

    -- Tracking toggle changes the visible character roster on every tab that lists chars.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_TRACKING_CHANGED, function()
        if not f or not f:IsShown() then return end
        ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
        SchedulePopulateContent(true)
    end)

    -- Pure UI state (sub-tab switches, expand/collapse, column pickers, theme accent): coalesced rebuild.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, function(_, payload)
        if not f or not f:IsShown() then return end
        local tab = payload and payload.tab
        if tab and f.currentTab ~= tab then return end
        local skipCooldown = true
        if payload and payload.skipCooldown == false then
            skipCooldown = false
        end
        -- Bypass POPULATE_DEBOUNCE for explicit UI gestures (e.g. Storage section expand/collapse).
        if payload and payload.instantPopulate then
            if pendingPopulateTimer then
                if pendingPopulateTimer.Cancel then
                    pendingPopulateTimer:Cancel()
                end
            end
            pendingPopulateTimer = nil
            populateDebounceGen = populateDebounceGen + 1
            pendingPopulateSkipCooldown = false
            if not f or not f:IsShown() then return end
            lastEventPopulateTime = GetTime()
            local P = ns.Profiler
            local mlab = P and P.enabled and P.SliceLabel and P:SliceLabel(P.CAT.MSG, "UI_MAIN_REFRESH_instant")
            if mlab then P:Start(mlab) end
            WarbandNexus:PopulateContent()
            if mlab then P:Stop(mlab) end
            return
        end
        SchedulePopulateContent(skipCooldown)
    end)

    -- Gold management edits + bank money log: chars tab gold cards / popup.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.GOLD_MANAGEMENT_CHANGED, function()
        if f and f:IsShown() and f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.CHARACTER_BANK_MONEY_LOG_UPDATED, function()
        if f and f:IsShown() and f.currentTab == "chars" then
            SchedulePopulateContent(true)
        end
    end)

    -- Item metadata async warm-up: cross-character SV links are often cold on login.
    -- Gear tab storage recommendations rely on link-based ilvl (e.g. WuE 253 vs template 233);
    -- when the warm-up completes, re-scan so previously-skipped candidates surface.
    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.ITEM_METADATA_READY, function()
        if f and f:IsShown() and f.currentTab == "gear" then
            if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                WarbandNexus:TryRefreshAllGearEquipSlotIcons()
            end
            if WarbandNexus.IsGearStorageRecommendationsEnabled
                and WarbandNexus:IsGearStorageRecommendationsEnabled() then
                -- Do not call TryGearStorageRedrawOnly first: a strict cache hit would skip the
                -- Invalidate + narrow refresh pipeline while SV items just gained resolved ilvl data.
                -- ItemsCacheService no longer bumps `_gearStorageInvGen` per metadata batch; this path
                -- soft-invalidates stash findings and coalesces a single ScheduleResolve (debounced).
                ScheduleGearTabInventoryNarrowRefresh()
            end
        end
    end)

    -- Blizzard fires GET_ITEM_INFO_RECEIVED whenever a cold-cache hyperlink finishes
    -- async resolution. ResolveStorageItemIlvl bails out (returns 0) on cold links,
    -- so we must re-run the gear scan once the client cache warms — otherwise the
    -- recommendation list stays empty for the entire session.
    if not UIEvents._itemInfoFrame then
        -- Intentionally raw: `GET_ITEM_INFO_RECEIVED` coalesce host — no visuals (WN_FACTORY inventory).
        local infoFrame = CreateFrame("Frame")
        UIEvents._itemInfoFrame = infoFrame
        infoFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        infoFrame:SetScript("OnEvent", function(_, _, itemID, success)
            if not success then return end
            if not f or not f:IsShown() then return end
            if f.currentTab ~= "gear" then return end
            gearItemInfoCoalesceGen = gearItemInfoCoalesceGen + 1
            local myGen = gearItemInfoCoalesceGen
            if gearItemInfoCoalesceTimer and gearItemInfoCoalesceTimer.Cancel then
                gearItemInfoCoalesceTimer:Cancel()
                gearItemInfoCoalesceTimer = nil
            end
            local function runGearItemInfoBatch()
                gearItemInfoCoalesceTimer = nil
                if myGen ~= gearItemInfoCoalesceGen then return end
                if not f or not f:IsShown() or f.currentTab ~= "gear" then return end
                local recOn = WarbandNexus.IsGearStorageRecommendationsEnabled
                    and WarbandNexus:IsGearStorageRecommendationsEnabled()
                local gearCanon = f._gearPopulateCanonKey
                if recOn then
                    local invInvalidated = false
                    if gearCanon and WarbandNexus.InvalidateGearStorageFindingsCacheForCanon then
                        invInvalidated = WarbandNexus:InvalidateGearStorageFindingsCacheForCanon(gearCanon) == true
                    end
                    if not invInvalidated then
                        ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
                    end
                end
                if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                    WarbandNexus:TryRefreshAllGearEquipSlotIcons()
                end
                if recOn and gearCanon and WarbandNexus.IsGearStorageScanInFlightForCanon
                    and WarbandNexus:IsGearStorageScanInFlightForCanon(gearCanon) then
                    return
                end
                if recOn and WarbandNexus.TryGearStorageRedrawOnly and WarbandNexus:TryGearStorageRedrawOnly() then
                    return
                end
                if recOn then
                    ThrottledScheduleGearAsyncRepaint()
                end
            end
            if C_Timer and C_Timer.NewTimer then
                gearItemInfoCoalesceTimer = C_Timer.NewTimer(0.08, runGearItemInfoBatch)
            else
                C_Timer.After(0.08, runGearItemInfoBatch)
            end
        end)
    end

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.MODULE_TOGGLED, function(_, moduleName, enabled)
        if not f or not f:IsShown() or not f.tabButtons then return end
        -- Map module name to tab key (currencies -> currency; others same)
        local tabKey = (moduleName == "currencies") and "currency" or moduleName
        UpdateTabVisibility(f)
        if f.currentTab then
            ScrollMainNavEnsureTabVisible(f, f.currentTab)
        end
        -- Only leave the tab when the module is turned off (enabling must not bounce to Characters).
        if enabled == false and f.currentTab == tabKey then
            f.currentTab = "chars"
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = "chars"
            end
            UpdateTabButtonStates(f)
            ScrollMainNavEnsureTabVisible(f, f.currentTab)
            SchedulePopulateContent()
        elseif f.currentTab == "items" and ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab() == "warband"
            and (moduleName == "items" or moduleName == "storage") then
            SchedulePopulateContent(true)
        end
    end)

    WarbandNexus.RegisterMessage(UIEvents, Constants.EVENTS.FONT_CHANGED, function()
        if f and f:IsShown() then
            SchedulePopulateContent()
        end
    end)

    -- Loading bar is now a standalone floating frame (see CreateLoadingOverlay below)

    -- Footer: left disclaimer / hints, right add-on version (TOC metadata).
    do
        -- Factory candidate: `Factory:CreateContainer` — thin footer lane (scrollbar reserve on right edge).
        local footerBar = CreateFrame("Frame", nil, f)
        footerBar:SetHeight(MAIN_FOOTER_H)
        local footerLaneReserve = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
            or (((ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26) + 2)
        footerBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 5)
        footerBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -footerLaneReserve, 5)
        footerBar:SetFrameLevel((f:GetFrameLevel() or 0) + 4)
        footerBar:EnableMouse(false)
        f.footerBar = footerBar

        local footerTop = footerBar:CreateTexture(nil, "ARTWORK")
        footerTop:SetHeight(1)
        footerTop:SetPoint("TOPLEFT", footerBar, "TOPLEFT", 0, 0)
        footerTop:SetPoint("TOPRIGHT", footerBar, "TOPRIGHT", 0, 0)
        if COLORS then
            footerTop:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.28)
        else
            footerTop:SetColorTexture(0.45, 0.25, 0.75, 0.35)
        end

        local metaVer = nil
        if C_AddOns and C_AddOns.GetAddOnMetadata then
            metaVer = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")
        end
        if (not metaVer or metaVer == "") and GetAddOnMetadata then
            metaVer = GetAddOnMetadata(ADDON_NAME, "Version")
        end
        if not metaVer or metaVer == "" then
            metaVer = "?"
        end

        local footerVersion = FontManager:CreateFontString(footerBar, "small", "OVERLAY")
        footerVersion:SetPoint("RIGHT", footerBar, "RIGHT", -8, 0)
        footerVersion:SetJustifyH("RIGHT")
        footerVersion:SetTextColor(0.72, 0.74, 0.8, 0.95)
        local verFmt = (L and L["MAIN_FOOTER_VERSION_FMT"]) or "v%s"
        footerVersion:SetText(string.format(verFmt, metaVer))
        f.footerVersionText = footerVersion

        local footerLeft = FontManager:CreateFontString(footerBar, "small", "OVERLAY")
        footerLeft:SetPoint("LEFT", footerBar, "LEFT", 8, 0)
        footerLeft:SetPoint("RIGHT", footerVersion, "LEFT", -14, 0)
        footerLeft:SetJustifyH("LEFT")
        footerLeft:SetWordWrap(false)
        footerLeft:SetNonSpaceWrap(true)
        footerLeft:SetTextColor(0.5, 0.52, 0.56, 0.92)
        footerLeft:SetText((L and L["MAIN_FOOTER_LEFT"]) or "Crafted with care, for everyone who plays.")
        f.footerLeftText = footerLeft

        if f.resizeGrip then
            local grip = f.resizeGrip
            local gripSize = MAIN_SHELL_LAYOUT.RESIZE_GRIP_SIZE or 18
            local gripInsetX = MAIN_SHELL_LAYOUT.RESIZE_GRIP_INSET_X or 4
            local gripInsetY = MAIN_SHELL_LAYOUT.RESIZE_GRIP_INSET_Y or 4
            grip:SetSize(gripSize, gripSize)
            grip:ClearAllPoints()
            grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -gripInsetX, gripInsetY)
            grip:SetFrameLevel((f:GetFrameLevel() or 0) + (MAIN_SHELL_LAYOUT.RESIZE_GRIP_FRAMELEVEL_BOOST or 80))
        end
    end
    
    -- Master OnHide: cleanup when addon window closes
    f:SetScript("OnHide", function(self)
        if pendingPopulateTimer then
            if pendingPopulateTimer.Cancel then
                pendingPopulateTimer:Cancel()
            end
        end
        pendingPopulateTimer = nil
        pendingPopulateSkipCooldown = false
        populateDebounceGen = populateDebounceGen + 1
        if gearStorageRecRefreshTimer and gearStorageRecRefreshTimer.Cancel then
            gearStorageRecRefreshTimer:Cancel()
        end
        gearStorageRecRefreshTimer = nil
        StopCustomDrag(self)
        SaveWindowGeometry(self)
        if ns.HideGearCharacterDropdown then
            ns.HideGearCharacterDropdown()
        end
        if WarbandNexus.CloseAllPlanDialogs then
            WarbandNexus:CloseAllPlanDialogs()
        end
        ClearAllSearchBoxes()
        -- Close Settings window if open (child follows parent)
        local settingsFrame = _G["WarbandNexusSettingsFrame"]
        if settingsFrame and settingsFrame:IsShown() then
            settingsFrame:Hide()
        end
        -- Free session-only metadata caches (bounded FIFO, but no reason to keep in memory while closed)
        if WarbandNexus.ClearCurrencyMetadataCache then WarbandNexus:ClearCurrencyMetadataCache() end
        if WarbandNexus.ClearReputationMetadataCache then WarbandNexus:ClearReputationMetadataCache() end
        if WarbandNexus.ClearItemMetadataCache then WarbandNexus:ClearItemMetadataCache() end
        if WarbandNexus.ClearCollectionMetadataCache then WarbandNexus:ClearCollectionMetadataCache() end
    end)

    --- Show/hide header Reload button when debug mode is on (boolean or legacy SavedVars `1`; matches ProfileFlagOn / Settings toggles).
    function f:SyncMainHeaderDebugReloadLayout()
        local reloadBtn = self.reloadDebugBtn
        local settBtn = self.settingsBtn
        local clsBtn = self.closeBtn
        if not reloadBtn or not settBtn or not clsBtn then return end
        local p = WarbandNexus.db and WarbandNexus.db.profile
        local show = p and ProfileFlagOn(p.debugMode)
        reloadBtn:SetShown(show)
        settBtn:ClearAllPoints()
        if show then
            settBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -6, 0)
        else
            settBtn:SetPoint("RIGHT", clsBtn, "LEFT", -6, 0)
        end
    end
    f:SyncMainHeaderDebugReloadLayout()
    
    -- Frame is already hidden (Hide() called immediately after CreateFrame)
    return f
end

--============================================================================
-- POPULATE CONTENT
--============================================================================
local function PopulateContentBody(self)
    if not mainFrame then return end

    local _wnProf = ns.Profiler
    if _wnProf then
        _wnProf._populateContentTab = mainFrame.currentTab
    end
    local _wnProfGearBlock = _wnProf and _wnProf.gearOnlyRecording and mainFrame.currentTab ~= "gear"
    local _wnProfOn = _wnProf and _wnProf.enabled and not _wnProfGearBlock
    local function _wnProfSliceStart(cat, name)
        if _wnProfOn and _wnProf.StartSlice then _wnProf:StartSlice(cat, name) end
    end
    local function _wnProfSliceStop(cat, name)
        if _wnProfOn and _wnProf.StopSlice then _wnProf:StopSlice(cat, name) end
    end

    -- Combat: avoid heavy pooled teardown + full tab rebuild while the secure state is active.
    -- Opening the frame from scratch is already blocked in ShowMainWindow/ToggleMainWindow; this path covers
    -- "window was open before combat" + message-driven refreshes (WN_* coalesced timers).
    if InCombatLockdown and InCombatLockdown() and mainFrame:IsShown() then
        ArmPostCombatUIRefresh()
        return
    end

    local populateWallStart = GetTime()

    if mainFrame.SyncMainHeaderDebugReloadLayout then
        mainFrame:SyncMainHeaderDebugReloadLayout()
    end

    -- Live resize: shell stretches via anchors; tab content redraw runs once on resize commit (LayoutCoordinator).
    if ns.UI_IsMainFrameResizing and ns.UI_IsMainFrameResizing(mainFrame) then
        if ns.UI_EnsureMainScrollLayout then
            ns.UI_EnsureMainScrollLayout()
        end
        return
    end

    -- Persisted lastTab can point at a tab whose module is disabled (hidden nav button).
    -- Clamp before tab-switch detection so highlight and scroll body stay aligned.
    if not IsTabModuleEnabled(mainFrame.currentTab) then
        mainFrame.currentTab = "chars"
        local p = WarbandNexus.db and WarbandNexus.db.profile
        if p then
            p.lastTab = "chars"
        end
    end

    local pendingPerfGen = IsTabPerfMonitorEnabled() and mainFrame._wnPerfTabSwitchPendingLog or nil

    local prevPopTab = mainFrame._prevPopulatedTab
    local isTabSwitch = (prevPopTab ~= mainFrame.currentTab)
    local scrollChild = mainFrame.scrollChild

    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_clearVLM")
    if ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mainFrame)
    end
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_clearVLM")

    if not scrollChild then
        if pendingPerfGen then
            debugprofilestop()
            mainFrame._wnPerfMainTabSwitch = nil
            mainFrame._wnPerfTabSwitchPendingLog = nil
        end
        mainFrame._prevPopulatedTab = mainFrame.currentTab
        return
    end

    -- Gear same-tab echo: identical populate signature before teardown (WN-PERF heavy tab first paint).
    if mainFrame.currentTab == "gear" and not isTabSwitch and WarbandNexus.GetGearPopulateSignature then
        local sigNow
        _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_gearSigCompute")
        sigNow = WarbandNexus:GetGearPopulateSignature()
        _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_gearSigCompute")
        if sigNow and mainFrame._gearPopulateContentSig and sigNow == mainFrame._gearPopulateContentSig then
            _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_gearSigSkip")
            self:UpdateStatus()
            scrollChild:SetWidth(ComputeScrollChildWidth(mainFrame))
            _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_gearSigSkip")
            if pendingPerfGen then
                debugprofilestop()
                mainFrame._wnPerfMainTabSwitch = nil
                mainFrame._wnPerfTabSwitchPendingLog = nil
            end
            mainFrame._prevPopulatedTab = mainFrame.currentTab
            return
        end
    end

    mainFrame._prevPopulatedTab = mainFrame.currentTab

    -- Gear prefix timing: anchor after gear sig gate so we do not attribute Pop_clearVLM / Pop_gearSigCompute
    -- to "before DrawGearTab". Uses debugprofilestop deltas only (no debugprofilestart — avoids resetting the
    -- global profile clock while Profiler slices run). Same-tab roster changes typically hit full teardown here;
    -- tab-switch path often sets _contentPreCleared and skips subtree release (lighter first paint).
    local gearPopulatePrefixT0
    do
        local P = ns.Profiler
        if mainFrame.currentTab == "gear" and P and P.AppendUserTraceLine
            and ((P.IsUserTraceWindowShown and P:IsUserTraceWindowShown()) or IsTabPerfMonitorEnabled()) then
            gearPopulatePrefixT0 = debugprofilestop()
        end
    end

    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_teardownUI")
    mainFrame._pveMinScrollWidth = nil
    -- Clear fixed header area and reset to minimal height
    local fixedHeader = mainFrame.fixedHeader
    if fixedHeader then
        local nch = PackVariadicInto(_uiChildEnumScratch, fixedHeader:GetChildren())
        for i = 1, nch do
            _uiChildEnumScratch[i]:Hide()
            _uiChildEnumScratch[i]:SetParent(recycleBin)
        end
        local nrg = PackVariadicInto(_uiRegionEnumScratch, fixedHeader:GetRegions())
        for i = 1, nrg do
            _uiRegionEnumScratch[i]:Hide()
        end
        fixedHeader:SetHeight(1)
    end

    -- Reset column header overlay to collapsed state.
    -- Child frames (colHeaderBar etc.) go to recycleBin; their textures/fontstrings
    -- travel with them. columnHeaderInner is repositioned to origin for the next tab.
    local columnHeaderClip = mainFrame.columnHeaderClip
    local columnHeaderInner = mainFrame.columnHeaderInner
    if columnHeaderClip then
        columnHeaderClip:SetHeight(1)
    end
    if columnHeaderInner then
        local nch2 = PackVariadicInto(_uiChildEnumScratch, columnHeaderInner:GetChildren())
        for i = 1, nch2 do
            _uiChildEnumScratch[i]:Hide()
            _uiChildEnumScratch[i]:SetParent(recycleBin)
        end
        columnHeaderInner:SetWidth(1)
        columnHeaderInner:ClearAllPoints()
        columnHeaderInner:SetPoint("TOPLEFT", columnHeaderClip, "TOPLEFT", 0, 0)
        columnHeaderInner:SetPoint("BOTTOMLEFT", columnHeaderClip, "BOTTOMLEFT", 0, 0)
    end
    
    -- CRITICAL FIX: Reset scrollChild height to prevent layout corruption across tabs
    scrollChild:SetHeight(1)  -- Reset to minimal height, will expand as content is added
    
    local wasPreCleared = isTabSwitch and mainFrame._contentPreCleared
    mainFrame._contentPreCleared = nil

    if not wasPreCleared then
        -- Release nested pooled rows (single DFS per top-level child), then detach tab chrome to recycleBin.
        -- Avoid ReleaseAllPooledChildren(scrollChild): it Hide+ClearAllPoints every direct child (PvE section
        -- shells are huge) and dominated tab-switch hitches.
        local nc3 = PackVariadicInto(_uiChildEnumScratch, scrollChild:GetChildren())
        for i = 1, nc3 do
            local child = _uiChildEnumScratch[i]
            if ReleasePooledRowsInSubtree then
                ReleasePooledRowsInSubtree(child)
            else
                if ReleaseCharacterRowsFromSubtree then
                    ReleaseCharacterRowsFromSubtree(child)
                end
                if ReleaseReputationRowsFromSubtree then
                    ReleaseReputationRowsFromSubtree(child)
                end
                if ReleaseCurrencyRowsFromSubtree then
                    ReleaseCurrencyRowsFromSubtree(child)
                end
            end
            if child._virtualVisibleFrames then
                child._virtualVisibleFrames = nil
            end
            if isTabSwitch then
                child._hasRenderedOnce = nil
            end
            if child.isPersistentRowElement then
                child:Hide()
            elseif not child._wnKeepOnTabSwitch then
                child:Hide()
                child:SetParent(recycleBin)
            end
        end
    end
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_teardownUI")

    -- Hide persistent gear frames when leaving their tab
    if mainFrame.currentTab ~= "gear" then
        if scrollChild._gearLoadingHost then scrollChild._gearLoadingHost:Hide() end
        mainFrame._gearContentVeil = nil
        if ns._gearPlayerModel then ns._gearPlayerModel:Hide() end
        if ns._gearPortraitPanel then ns._gearPortraitPanel:Hide() end
        if ns._gearNoPreviewFrame then ns._gearNoPreviewFrame:Hide() end
        if ns._gearModelBorder then ns._gearModelBorder:Hide() end
        if ns._gearIlvlFrame then ns._gearIlvlFrame:Hide() end
        if ns._gearNameWrapper then ns._gearNameWrapper:Hide() end
    end
    
    -- Update status
    self:UpdateStatus()
    
    -- Tab bar: sync highlight before draw (profiler slice: rail + top layouts both hit this path every populate).
    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_syncTabButtons")
    UpdateTabButtonStates(mainFrame)
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_syncTabButtons")
    
    -- Set scrollChild width once (ComputeScrollChildWidth handles tab-specific minimums)
    scrollChild:SetWidth(ComputeScrollChildWidth(mainFrame))

    -- Bottom annex sheet (Storage / Items / Stats): hide until the active tab redraw anchors it.
    if scrollChild._wnResultsAnnexSheet then
        scrollChild._wnResultsAnnexSheet:Hide()
    end

    -- Mark that pooled rows were already released in PopulateContent.
    -- Tab renderers can skip redundant ReleaseAllPooledChildren() calls in this pass.
    scrollChild._preparedByPopulate = true

    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_drawTab")
    -- Draw based on current tab
    local height
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local trackedOnlyTabs = {
        items = true, pve = true, reputations = true,
        currency = true, professions = true, gear = true, collections = true,
        plans = true, stats = true,
    }

    local tab = mainFrame.currentTab
    -- Dev-only: wall time for scroll-heavy mains (WN-PERF checklist). Complements tab-switch click→populate log + `Pop_drawTab`.
    local drawPerfT0 = (isTracked and IsTabPerfMonitorEnabled() and TAB_DRAW_PERF_TRACE[tab]) and GetTime() or nil
    if not isTracked and trackedOnlyTabs[tab] then
        height = self:DrawTrackingRequiredBanner(scrollChild)
    elseif tab == "chars" then
        height = self:DrawCharacterList(scrollChild)
    elseif tab == "currency" then
        height = self:DrawCurrencyTab(scrollChild)
    elseif tab == "items" then
        height = self:DrawItemList(scrollChild)
    elseif tab == "pve" then
        height = self:DrawPvEProgress(scrollChild)
    elseif tab == "reputations" then
        height = self:DrawReputationTab(scrollChild)
    elseif tab == "stats" then
        height = self:DrawStatistics(scrollChild)
    elseif tab == "professions" then
        local P = ns.Profiler
        if P and P.enabled and P.Wrap and P.SliceLabel then
            local lab = P:SliceLabel(P.CAT.UI, "DrawProfessionsTab")
            height = P:Wrap(lab, WarbandNexus.DrawProfessionsTab, WarbandNexus, scrollChild)
        else
            height = self:DrawProfessionsTab(scrollChild)
        end
    elseif tab == "gear" then
        -- Full-tab loading veil removed: recommendations panel shows its own "Scanning..." state; smoother tab open.
        mainFrame._wnGearPaintShowVeil = false
        local P = ns.Profiler
        if gearPopulatePrefixT0 and P and P.AppendUserTraceLine then
            P:AppendUserTraceLine(string.format(
                "[WN Perf][GearOpen] PopulateContent teardown+hooks before DrawGearTab %.2fms (after gearSig gate; excl. Pop_clearVLM)",
                debugprofilestop() - gearPopulatePrefixT0))
        end
        local tPop = (P and ((P.IsUserTraceWindowShown and P:IsUserTraceWindowShown())
            or (ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled()))) and debugprofilestop() or nil
        height = self:DrawGearTab(scrollChild)
        if tPop and P and P.AppendUserTraceLine then
            P:AppendUserTraceLine(string.format(
                "[WN Perf][GearOpen] PopulateContent DrawGearTab call %.2fms (excludes pool/release before Pop_drawTab)",
                debugprofilestop() - tPop))
        end
    elseif tab == "collections" then
        height = self:DrawCollectionsTab(scrollChild)
    elseif tab == "plans" then
        height = self:DrawPlansTab(scrollChild)
    else
        height = self:DrawCharacterList(scrollChild)
    end
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_drawTab")
    -- GetTime() has limited resolution: sub-ms DrawTab often logs as 0.0ms (noise). Only trace meaningful wall time.
    local TRACE_DRAW_TAB_MIN_MS = 3
    if drawPerfT0 then
        local ms = (GetTime() - drawPerfT0) * 1000
        if ms >= TRACE_DRAW_TAB_MIN_MS then
            local P = ns.Profiler
            if P and P.AppendUserTraceLine then
                P:AppendUserTraceLine(format("[WN Perf] DrawTab %s %.1fms", tab, ms))
            elseif WarbandNexus.Print then
                WarbandNexus:Print(format("|cff9e9e9e[WN Perf] DrawTab %s %.1fms|r", tab, ms))
            else
                DebugPrint(format("[WN Perf] DrawTab %s %.1fms", tab, ms))
            end
        end
    end
    scrollChild._preparedByPopulate = nil

    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_postLayout")
    -- Set scrollChild height based on content + bottom padding
    local CONTENT_BOTTOM_PADDING = (ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12
    local contentBottom = height + CONTENT_BOTTOM_PADDING
    -- Gear tab: extend scrollChild to viewport so the gear card can fill downward (see DrawPaperDollCard fill).
    local viewportH = mainFrame.scroll and mainFrame.scroll:GetHeight() or 0
    -- First layout frame: GetHeight() can be 0 while anchors are valid — derive from geometry so scrollChild fills the viewport.
    if viewportH < 2 and mainFrame.scroll and mainFrame.fixedHeader then
        local fhBot = mainFrame.fixedHeader:GetBottom()
        local sb = mainFrame.scroll:GetBottom()
        if fhBot and sb and fhBot > sb then
            viewportH = fhBot - sb
        end
    end
    local totalScrollH = math.max(contentBottom, viewportH)
    scrollChild:SetHeight(totalScrollH)

    if ns.UI_ConfigureMainScrollViewportForTab then
        ns.UI_ConfigureMainScrollViewportForTab(mainFrame, tab)
    end
    if tab == "gear" and ns.GearUI_RelayoutGearTabViewportFill then
        ns.GearUI_RelayoutGearTabViewportFill(mainFrame)
    end
    if tab ~= "items" and tab ~= "gear" and ns.UI_EnsureScrollChildViewportFill then
        ns.UI_EnsureScrollChildViewportFill(scrollChild)
    end
    if tab ~= "items" and tab ~= "gear" and ns.UI_RefreshScrollAnnexLayout then
        ns.UI_RefreshScrollAnnexLayout(scrollChild)
    end

    -- When content is shorter than the viewport, paint a viewport-tone band below short content.
    do
        local fill = scrollChild._wnScrollBottomFill
        if not fill then
            fill = CreateFrame("Frame", nil, scrollChild)
            fill._wnKeepOnTabSwitch = true
            fill:SetFrameLevel(math.max(0, (scrollChild:GetFrameLevel() or 0) - 5))
            local tex = fill:CreateTexture(nil, "BACKGROUND", nil, -8)
            tex:SetAllPoints()
            fill._wnBottomFillTex = tex
            scrollChild._wnScrollBottomFill = fill
        end
        if fill._wnBottomFillTex then
            local C = ns.UI_COLORS
            local fillBg = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
                or (C and C.bg) or { 0.042, 0.042, 0.055, 0.98 }
            fill._wnBottomFillTex:SetColorTexture(fillBg[1], fillBg[2], fillBg[3], fillBg[4] or 0.98)
        end
        local slack = totalScrollH - contentBottom
        local skipGlobalFill = (tab == "items")
        if not skipGlobalFill and slack > 1 then
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -contentBottom)
            fill:SetPoint("BOTTOMRIGHT", scrollChild, "BOTTOMRIGHT", 0, 0)
            fill:Show()
        else
            fill:ClearAllPoints()
            fill:Hide()
        end
    end

    -- After content height changes, clamp vertical scroll (avoids empty band when range shrinks or layout jumps)
    do
        local sc = mainFrame.scroll
        if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
            local maxV = sc:GetVerticalScrollRange() or 0
            local cur = sc:GetVerticalScroll() or 0
            if cur > maxV then
                sc:SetVerticalScroll(maxV)
            end
        end
    end
    
    -- Update scroll bar visibility (hide if content fits)
    if ns.UI.Factory.UpdateScrollBarVisibility then
        ns.UI.Factory:UpdateScrollBarVisibility(mainFrame.scroll)
    end
    if ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(mainFrame.scroll)
    end
    
    -- Tab switch: always open at top for consistent scroll chrome across pages.
    if mainFrame.isMainTabSwitch and mainFrame.scroll then
        mainFrame.scroll:SetVerticalScroll(0)
        mainFrame.scroll:SetHorizontalScroll(0)
        if mainFrame.hScroll and mainFrame.hScroll.SetValue then
            mainFrame.hScroll:SetValue(0)
        end
    end

    if mainFrame._virtualScrollUpdate then
        mainFrame._virtualScrollUpdate()
    end

    UpdateScrollLayout(mainFrame)

    self:UpdateTabCountBadges()
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_postLayout")

    -- Dev-only: one-line main tab switch timing after deferred PopulateContent (see tab OnClick).
    if pendingPerfGen and IsTabPerfMonitorEnabled() then
        local perf = mainFrame._wnPerfMainTabSwitch
        local ok = perf and perf.gen == pendingPerfGen and perf.msClickToPoolEnd and perf.gen == mainFrame._tabSwitchGen
            and mainFrame.currentTab == perf.toTab
        if ok then
            local msPopulate = debugprofilestop()
            local msg = format(
                "[WN Perf] main tab %s → %s | click→pool=%.2fms pool→populate=%.2fms sum=%.2fms",
                tostring(perf.fromTab),
                tostring(perf.toTab),
                perf.msClickToPoolEnd,
                msPopulate,
                perf.msClickToPoolEnd + msPopulate
            )
            local P = ns.Profiler
            if P and P.AppendUserTraceLine then
                P:AppendUserTraceLine(msg)
            elseif WarbandNexus.Print then
                WarbandNexus:Print("|cff9e9e9e" .. msg .. "|r")
            else
                DebugPrint(msg)
            end
        else
            debugprofilestop()
        end
        mainFrame._wnPerfMainTabSwitch = nil
        mainFrame._wnPerfTabSwitchPendingLog = nil
    elseif pendingPerfGen then
        debugprofilestop()
        mainFrame._wnPerfMainTabSwitch = nil
        mainFrame._wnPerfTabSwitchPendingLog = nil
    end

    -- Dev-only: unusually long PopulateContent (true infinite loops cannot be broken from Lua; this flags pathological hangs).
    if IsDebugModeEnabled and IsDebugModeEnabled() and DebugPrint and populateWallStart then
        local wallMs = (GetTime() - populateWallStart) * 1000
        if wallMs > 400 then
            DebugPrint(format(
                "[WN UI] PopulateContent slow: %.0fms tab=%s (/wn profiler on | trace: Pop_* + DrawTab lines with /wn debug + verbose)",
                wallMs,
                tostring(mainFrame.currentTab)
            ))
        end
    end
end

function WarbandNexus:PopulateContent()
    local P = ns.Profiler
    if P and P.enabled then
        local lab = P.SliceLabel and P:SliceLabel(P.CAT.UI, "PopulateContent")
        if lab then
            return P:Wrap(lab, PopulateContentBody, self)
        end
    end
    return PopulateContentBody(self)
end

--============================================================================
-- TAB COUNT BADGES
--============================================================================
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

--============================================================================
-- TRACKING REQUIRED BANNER
--============================================================================
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
    title:SetTextColor(1, 0.55, 0.45)
    title:SetText((ns.L and ns.L["TRACKING_TAB_LOCKED_TITLE"]) or "Character is not tracked")

    local desc = GetFontManager():CreateFontString(card, GetFontManager():GetFontRole("trackingRequiredBannerBody"), "OVERLAY")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetPoint("TOPRIGHT", card, "TOPRIGHT", -14, -8)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.88, 0.88, 0.88)
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

--============================================================================
-- UPDATE STATUS
--============================================================================
function WarbandNexus:UpdateStatus()
    if not mainFrame then return end

    local isOpen = self.bankIsOpen
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)

    local icon = mainFrame.statusIcon
    local badge = mainFrame.statusBadge
    local accent = mainFrame.trackingStatusAccent
    local chip = mainFrame.trackingChip
    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    local trackingDialogKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey
            and ns.CharacterService:ResolveCharactersTableKey(self))
        or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self))
        or charKey

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
                GameTooltip:SetText(tooltipText or "", 1, 1, 1)
                if tooltipHint then
                    GameTooltip:AddLine(tooltipHint, 0.7, 0.7, 0.7, true)
                end
                GameTooltip:Show()
            end)
            badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

    if mainFrame.statusText then
        if isOpen then
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_BANK"]) or "Bank is Active"))
            mainFrame.statusText:SetTextColor(0.75, 0.95, 0.82)
        elseif isTracked then
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_TRACKING"]) or "Tracking"))
            mainFrame.statusText:SetTextColor(0.82, 0.98, 0.88)
        else
            mainFrame.statusText:SetText(BadgeOneLine((ns.L and ns.L["TRACKING_BADGE_UNTRACKED"]) or "Not Tracking"))
            mainFrame.statusText:SetTextColor(1, 0.72, 0.58)
        end
    end

    if accent then
        if isOpen or isTracked then
            accent:SetColorTexture(0.18, 0.88, 0.48, 1)
        else
            accent:SetColorTexture(0.95, 0.42, 0.22, 1)
        end
    end

    if isOpen then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            icon:SetVertexColor(0.45, 1, 0.55)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["BANK_IS_ACTIVE"]) or "Bank is Active", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    elseif isTracked then
        if icon then
            pcall(icon.SetAtlas, icon, "common-icon-checkmark", false)
            icon:SetVertexColor(0.45, 1, 0.55)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_ACTIVE_DESC"]) or "Data collection and updates are active.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to change tracking.")
    else
        if icon then
            local ok = pcall(icon.SetAtlas, icon, "common-icon-redx", false)
            if not ok then
                icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
            end
            icon:SetVertexColor(1, 0.55, 0.42)
            icon:Show()
        end
        SetClickAndTooltip((ns.L and ns.L["TRACKING_NOT_ENABLED_TOOLTIP"]) or "Character tracking is disabled.", (ns.L and ns.L["TRACKING_BADGE_CLICK_HINT"]) or "Click to enable tracking.")
    end

    SizeTrackingChip()
end

-- REMOVED: UpdateFooter — empty stub with no callers.

--============================================================================
-- DRAW ITEM LIST
--============================================================================
-- Track which bank type is selected in Items tab
-- DEFAULT: Personal Bank (priority over Warband)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

-- REMOVED: WarbandNexus:SetItemsSubTab / GetItemsSubTab — unused; ns.UI_SetItemsSubTab / ns.UI_GetItemsSubTab are the live API.

-- Track expanded state for each category (persists across refreshes)
-- Uses shared state declared above; do not redeclare here (avoids shadowing).

--============================================================================
-- TAB DRAWING FUNCTIONS (All moved to separate modules)
--============================================================================
-- DrawCharacterList moved to Modules/UI/CharactersUI.lua
-- DrawItemList moved to Modules/UI/ItemsUI.lua
-- DrawEmptyState moved to Modules/UI/ItemsUI.lua
-- DrawStorageTab / DrawStorageResults / SyncStorageResultsLayoutFromTail live in this file (Items + Warband tree).
-- DrawPvEProgress moved to Modules/UI/PvEUI.lua
-- DrawStatistics moved to Modules/UI/StatisticsUI.lua


--============================================================================
-- REFRESH
--============================================================================

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
    
    -- CRITICAL FIX: Always execute the refresh immediately (no throttle on user actions)
    -- This ensures rows are always drawn when headers are toggled or tabs are switched
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
    newScale = math.max(0.6, math.min(1.5, newScale or 1.0))

    -- Persist geometry before SetScale so width/height/anchor offsets snapshot pre-change layout.
    SaveWindowGeometry(mainFrame)

    mainFrame:SetScale(newScale)

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
    if IsDebugModeEnabled and IsDebugModeEnabled() then
    end
    -- Show custom settings UI (renders AceConfig with themed widgets)
    if self.ShowSettings then
        self:ShowSettings()
    elseif ns.ShowSettings then
        ns.ShowSettings()
    else
        -- No settings UI available (ShowSettings should always exist)
        self:Print("|cff9370DB[Warband Nexus]|r " .. ((ns.L and ns.L["SETTINGS_UI_UNAVAILABLE"]) or "Settings UI not available. Try /wn to open the main window."))
    end
end

-- ===== STANDALONE LOADING OVERLAY =====
-- Floating bar that appears on screen during init, independent of the addon window.
-- Uses lightweight polling (0.5s ticker) to track LoadingTracker state.
-- AceEvent message hooks don't work from standalone contexts (plain tables
-- can't register as AceEvent receivers), so polling is the reliable approach.
--
-- LIFECYCLE: Ticker runs for up to MAX_POLL_LIFETIME seconds after PLAYER_LOGIN.
-- This covers both the initial login (tracked chars: ~15s) and the delayed
-- post-confirmation flow (user clicks "Tracked" at T+2.5s+: adds ~5s of ops).
-- Ticker is NOT cancelled on first completion — new operations can be registered
-- after the user confirms tracking, and the bar will reappear automatically.
do
    local loadingOverlay
    local pollTicker
    local completedShown = false
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
        bar:SetBackdropColor(0.06, 0.06, 0.09, 1)
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
        loadText:SetTextColor(0.3, 0.9, 0.4, 1)
        loadText:SetWordWrap(false)
        bar.loadingText = loadText

        local progText
        if ns.FontManager then
            progText = ns.FontManager:CreateFontString(bar, ns.FontManager:GetFontRole("loadingBarSecondaryText"), "OVERLAY")
        else
            progText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        progText:SetPoint("RIGHT", -8, 0)
        progText:SetTextColor(0.3, 0.9, 0.4, 1)
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

        if LT:IsComplete() then
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

        -- Pending labels (GetPendingLabels returns ephemeral reused table — copy only what we display)
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
    -- This ensures the overlay detects both initial-login ops AND
    -- post-confirmation ops (user clicks "Tracked" after the dialog).
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
