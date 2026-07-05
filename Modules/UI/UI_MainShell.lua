--[[ UI main window shell ]]
local ADDON_NAME, ns = ...
local S = assert(ns.UIShell, "UI_MainShell: load Modules/UI.lua first")
local B = assert(ns.UIShell._bind, "UI_MainShell: UIShell._bind missing")
local ApplyMainNavGoldenShellLayout = B.ApplyMainNavGoldenShellLayout
local ApplyMainShellLayout = B.ApplyMainShellLayout
local ApplyVisuals = B.ApplyVisuals
local ArmPostCombatUIRefresh = B.ArmPostCombatUIRefresh
local CancelLeavingTabStagedPaint = B.CancelLeavingTabStagedPaint
local CancelShellGearAsyncTimers = B.CancelShellGearAsyncTimers
local ClearAllSearchBoxes = B.ClearAllSearchBoxes
local ComputeScrollChildWidth = B.ComputeScrollChildWidth
local DebugPrint = B.DebugPrint
local DetachKeptScrollChildOnMainTabSwitch = B.DetachKeptScrollChildOnMainTabSwitch
local GetFontManager = B.GetFontManager
local GetMainWindowGeometryBounds = B.GetMainWindowGeometryBounds
local GetWindowDimensions = B.GetWindowDimensions
local IsDebugModeEnabled = B.IsDebugModeEnabled
local IsTabModuleEnabled = B.IsTabModuleEnabled
local IsTabPerfMonitorEnabled = B.IsTabPerfMonitorEnabled
local MAIN_TAB_ORDER = B.MAIN_TAB_ORDER
local SHELL_TAB_SWITCH_POPULATE_QUIET = B.SHELL_TAB_SWITCH_POPULATE_QUIET or 0.45
local MarkShellPopulateCompleted = B.MarkShellPopulateCompleted
local NormalizeFramePosition = B.NormalizeFramePosition
local PackVariadicInto = B.PackVariadicInto
local ProfileFlagOn = B.ProfileFlagOn
local PurgeScrollChildLeaksAfterFastDetach = B.PurgeScrollChildLeaksAfterFastDetach
local RefreshMainNavLayout = B.RefreshMainNavLayout
local RefreshMainNavRailStrip = B.RefreshMainNavRailStrip
local RefreshMainNavTabStrip = B.RefreshMainNavTabStrip
local ReleaseCharacterRowsFromSubtree = B.ReleaseCharacterRowsFromSubtree
local ReleaseCurrencyRowsFromSubtree = B.ReleaseCurrencyRowsFromSubtree
local ReleasePooledRowsInSubtree = B.ReleasePooledRowsInSubtree
local ReleaseReputationRowsFromSubtree = B.ReleaseReputationRowsFromSubtree
local RememberSessionMainTab = B.RememberSessionMainTab
local RestoreWindowPosition = B.RestoreWindowPosition
local SaveWindowGeometry = B.SaveWindowGeometry
local ScheduleRecycleBinPoolDrain = B.ScheduleRecycleBinPoolDrain
local ScrollMainNavEnsureTabVisible = B.ScrollMainNavEnsureTabVisible
local ShouldSkipRedundantShellPopulate = B.ShouldSkipRedundantShellPopulate
local StartCustomDrag = B.StartCustomDrag
local StartCustomResize = B.StartCustomResize
local StopCustomDrag = B.StopCustomDrag
local StopCustomResize = B.StopCustomResize
local UpdateScrollLayout = B.UpdateScrollLayout
local UpdateTabButtonStates = B.UpdateTabButtonStates
local UpdateTabVisibility = B.UpdateTabVisibility
local WireMainNavTabButtonUX = B.WireMainNavTabButtonUX
local debugprofilestart = B.debugprofilestart
local debugprofilestop = B.debugprofilestop
local format = B.format
local recycleBin = B.recycleBin
local UIEvents = B.UIEvents
local L = B.L
local _uiChildEnumScratch = B._uiChildEnumScratch
local _uiRegionEnumScratch = B._uiRegionEnumScratch
local WarbandNexus = ns.WarbandNexus

function ns.UIShell.CreateMainWindow(self)
    local mainFrame = S.getMainFrame()
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
    
    -- Lazy-load and verify FontManager
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

    -- Intentionally raw: global `WarbandNexusFrame` â€” flat shell fill only (no `BackdropTemplate` side gutters).
    local f = CreateFrame("Frame", "WarbandNexusFrame", UIParent)
    f:Hide()  -- Hide immediately to prevent position flash (frame inherits UIParent visibility)
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
    
    -- Apply user-configured UI scale (main shell + registered external windows)
    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(f)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(f)
    end
    
    -- Restore saved position, or center on first use
    if not RestoreWindowPosition(f) then
        f:SetPoint("CENTER")
    end
    
    -- NOTE: Master OnHide is set later (after tab system creation) to consolidate all cleanup
    
    -- Shell: full-bleed panel fill (MAIN_SHELL) â€” no backdrop insets.
    local COLORS = ns.UI_COLORS
    local shellBg = COLORS and COLORS.bg or { 0.04, 0.04, 0.05, 0.98 }
    if ns.UI_ApplyMainWindowShellFill then
        ns.UI_ApplyMainWindowShellFill(f, shellBg)
    elseif ns.UI_ApplyMainWindowShellBackdrop then
        ns.UI_ApplyMainWindowShellBackdrop(f, shellBg)
    end
    
    -- OnSizeChanged: shell + tab live relayout via LayoutCoordinator (commit on resize mouse-up).
    f:SetScript("OnSizeChanged", function(self, width, height)
        if ns.UI_ApplyMainShellLayout then
            ns.UI_ApplyMainShellLayout(self)
        end
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
    local shellInsetL, shellInsetR = 0, 0
    if ns.UI_GetMainShellFrameInsets then
        shellInsetL, shellInsetR = ns.UI_GetMainShellFrameInsets()
    else
        shellInsetL = MAIN_SHELL_LAYOUT.FRAME_CONTENT_INSET or 0
        shellInsetR = shellInsetL
    end
    local headerNavGap = MAIN_SHELL_LAYOUT.HEADER_TO_NAV_GAP or 4
    local headerUtilityRight = MAIN_SHELL_LAYOUT.HEADER_UTILITY_CLUSTER_RIGHT_INSET or 18

    -- Factory candidate: `Factory:CreateContainer` host â€” keep anchors + `EnableMouse` for drag.
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
    
    -- Apply header visuals (dark: accentDark bar â€” original; light: surface chrome; classic: transparent band inside dialog)
    do
        local headerBg = (ns.UI_GetMainHeaderChromeColor and ns.UI_GetMainHeaderChromeColor())
            or { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 }
        local headerBorder = (ns.UI_GetMainHeaderBorderColor and ns.UI_GetMainHeaderBorderColor())
            or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
        if ns.UI_IsClassicMode and ns.UI_IsClassicMode() and ns.UI_ApplyClassicInteriorFlatFill then
            ns.UI_ApplyClassicInteriorFlatFill(header, { 0, 0, 0, 0 })
        elseif ApplyVisuals then
            ApplyVisuals(header, headerBg, headerBorder)
        end
    end

    -- Addon `Media` branding (see `ns.UI_ApplyMainWindowTitleIcon`). `SetFrameLevel` exists on Frame only, not Texture;
    -- host frame keeps the icon above sibling header art without calling a nil Texture method.
    local iconHolder = CreateFrame("Frame", nil, header)
    iconHolder:SetSize(34, 34)
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
    ns.UI_SetTextColorRole(title, "Bright") -- Always white
    f.title = title  -- Store reference
    
    -- Close button (Blizzard UIPanelCloseButton in classic; custom chrome otherwise)
    local function BuildCloseButton()
        if f.closeBtn then
            f.closeBtn:Hide()
            f.closeBtn:ClearAllPoints()
            f.closeBtn:SetParent(nil)
            f.closeBtn = nil
        end
        local closeBtn
        if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
            closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
            closeBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -headerUtilityRight, -2)
            closeBtn._wnBlizzardButton = true
        else
            closeBtn = CreateFrame("Button", nil, header)
            closeBtn:SetSize(28, 28)
            closeBtn:SetPoint("RIGHT", -headerUtilityRight, 0)

            if ns.UI_ApplyVisuals then
                local closeIdle = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop() or { 0.15, 0.15, 0.15, 0.9 }
                ns.UI_ApplyVisuals(closeBtn, closeIdle, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
            end

            local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
            closeIcon:SetSize(16, 16)
            closeIcon:SetPoint("CENTER")
            closeIcon:SetAtlas("uitools-icon-close")
            closeIcon:SetVertexColor(0.9, 0.3, 0.3)

            closeBtn:SetScript("OnEnter", function(self)
                closeIcon:SetVertexColor(1, 0.2, 0.2)
                if ns.UI_ApplyVisuals and ns.UI_GetSemanticNegativeCard then
                    local bg, border = ns.UI_GetSemanticNegativeCard(true)
                    ns.UI_ApplyVisuals(closeBtn, bg, border)
                end
            end)

            closeBtn:SetScript("OnLeave", function(self)
                closeIcon:SetVertexColor(0.9, 0.3, 0.3)
                if ns.UI_ApplyVisuals then
                    local closeIdle = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop() or { 0.15, 0.15, 0.15, 0.9 }
                    ns.UI_ApplyVisuals(closeBtn, closeIdle, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
                end
            end)
        end

        closeBtn:SetScript("OnClick", function() f:Hide() end)
        f.closeBtn = closeBtn
        if f.reloadDebugBtn then
            f.reloadDebugBtn:ClearAllPoints()
            f.reloadDebugBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
        end
    end
    BuildCloseButton()
    f._wnRebuildCloseButton = BuildCloseButton
    local closeBtn = f.closeBtn

    -- Debug-only: quick /reload (WoW has no Lua hot-reload; saves typing during addon dev)
    local reloadDebugBtn = CreateFrame("Button", nil, header)
    reloadDebugBtn:SetSize(28, 28)
    reloadDebugBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    reloadDebugBtn._wnSkipCustomChrome = true
    if ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(reloadDebugBtn) and ns.UI_ApplyVisuals then
        local chromeHover = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.12, 0.14, 0.18, 0.92 }
        ns.UI_ApplyVisuals(reloadDebugBtn, chromeHover, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75 })
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
    reloadDebugBtn._wnUtilityIcon = reloadIcon
    if ns.UI_ApplyHeaderUtilityIconStyle then
        ns.UI_ApplyHeaderUtilityIconStyle(reloadIcon, false)
    end
    reloadDebugBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    reloadDebugBtn:SetScript("OnEnter", function(self)
        if ns.UI_ApplyHeaderUtilityIconStyle then
            ns.UI_ApplyHeaderUtilityIconStyle(reloadIcon, true)
        else
            reloadIcon:SetVertexColor(1, 1, 1)
        end
        if ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(self) and ns.UI_ApplyVisuals then
            ns.UI_ApplyVisuals(self, {0.18, 0.22, 0.28, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1})
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["DEBUG_RELOAD_UI_BTN"]) or "Reload UI", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["DEBUG_RELOAD_UI_TOOLTIP"]) or "Reload the entire interface (/reload). WoW cannot hot-reload addon Lua; use this after saving files.", 0.65, 0.65, 0.65, true)
        GameTooltip:Show()
    end)
    reloadDebugBtn:SetScript("OnLeave", function(self)
        if ns.UI_ApplyHeaderUtilityIconStyle then
            ns.UI_ApplyHeaderUtilityIconStyle(reloadIcon, false)
        else
            reloadIcon:SetVertexColor(0.75, 0.92, 1)
        end
        if ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(self) and ns.UI_ApplyVisuals then
            local chromeHover = ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop() or { 0.12, 0.14, 0.18, 0.92 }
            ns.UI_ApplyVisuals(self, chromeHover, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75 })
        end
        GameTooltip:Hide()
    end)
    f.reloadDebugBtn = reloadDebugBtn

    -- Utility buttons in header (left of Close) so nav row is tabs-only and never overlaps when minimized
    local DISCORD_URL = "https://discord.gg/warbandnexus"
    local PATREON_URL = "https://patreon.com/warbandnexus?utm_medium=unknown&utm_source=join_link&utm_campaign=creatorshare_creator&utm_content=copyLink"
    local discordCopyFrame, discordCopyBox, patreonCopyFrame, patreonCopyBox
    local patreonBtn = CreateFrame("Button", nil, header)
    patreonBtn:SetSize(30, 30)
    patreonBtn:SetPoint("RIGHT", reloadDebugBtn, "LEFT", -6, 0)
    patreonBtn._wnSkipCustomChrome = true
    if ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(patreonBtn) and ns.UI_ApplyVisuals then
        local closeIdle = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop() or { 0.15, 0.15, 0.15, 0.9 }
        ns.UI_ApplyVisuals(patreonBtn, closeIdle, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end
    local patreonIcon = patreonBtn:CreateTexture(nil, "ARTWORK")
    patreonIcon:SetAllPoints()
    patreonIcon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\donateicon.png")
    patreonIcon:SetTexCoord(0, 1, 0, 1)
    patreonIcon:SetVertexColor(1, 1, 1, 1)
    patreonBtn._wnUtilityIcon = patreonIcon
    if ns.UI_ApplyHeaderUtilityIconStyle then
        ns.UI_ApplyHeaderUtilityIconStyle(patreonIcon, false)
    end
    patreonCopyFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    patreonCopyFrame:SetSize(440, 28)
    patreonCopyFrame:SetPoint("TOPRIGHT", patreonBtn, "BOTTOMRIGHT", 0, -4)
    patreonCopyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    patreonCopyFrame:SetFrameLevel(500)
    if ns.UI_ApplyHeaderCopyUrlShell then
        ns.UI_ApplyHeaderCopyUrlShell(patreonCopyFrame)
    end
    patreonCopyFrame:Hide()
    patreonCopyBox = CreateFrame("EditBox", nil, patreonCopyFrame)
    patreonCopyBox:SetPoint("TOPLEFT", 6, -4)
    patreonCopyBox:SetPoint("BOTTOMRIGHT", -6, 4)
    patreonCopyBox:SetAutoFocus(false)
    patreonCopyBox:SetFontObject(ChatFontNormal)
    if ns.FontManager then
        ns.FontManager:RegisterManagedEditBox(patreonCopyBox)
        ns.FontManager:ApplyFontToEditBox(patreonCopyBox)
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
        if ns.UI_ApplyHeaderUtilityIconStyle then
            ns.UI_ApplyHeaderUtilityIconStyle(patreonIcon, true)
        else
            patreonIcon:SetAlpha(0.75)
        end
        GameTooltip:SetOwner(patreonBtn, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["PATREON_TOOLTIP"]) or "Warband Nexus on Patreon", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["CLICK_TO_COPY_LINK"]) or "Click to copy link", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    patreonBtn:SetScript("OnLeave", function()
        if ns.UI_ApplyHeaderUtilityIconStyle then
            ns.UI_ApplyHeaderUtilityIconStyle(patreonIcon, false)
        else
            patreonIcon:SetAlpha(1.0)
        end
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

    local discordBtn = CreateFrame("Button", nil, header)
    f.discordBtn = discordBtn
    discordBtn:SetSize(30, 30)
    discordBtn:SetPoint("RIGHT", patreonBtn, "LEFT", -6, 0)
    discordBtn._wnSkipCustomChrome = true
    if ns.UI_CanApplyCustomChrome and ns.UI_CanApplyCustomChrome(discordBtn) and ns.UI_ApplyVisuals then
        local closeIdle = ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop() or { 0.15, 0.15, 0.15, 0.9 }
        ns.UI_ApplyVisuals(discordBtn, closeIdle, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end
    local discordIcon = discordBtn:CreateTexture(nil, "ARTWORK")
    discordIcon:SetAllPoints()
    discordIcon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\discord.tga")
    discordIcon:SetTexCoord(0, 1, 0, 1)
    discordIcon:SetVertexColor(1, 1, 1, 1)
    discordBtn._wnUtilityIcon = discordIcon
    if ns.UI_ApplyHeaderUtilityIconStyle then
        ns.UI_ApplyHeaderUtilityIconStyle(discordIcon, false)
    end
    discordCopyFrame = CreateFrame("Frame", nil, header, "BackdropTemplate")
    discordCopyFrame:SetSize(240, 28)
    discordCopyFrame:SetPoint("TOPRIGHT", discordBtn, "BOTTOMRIGHT", 0, -4)
    discordCopyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    discordCopyFrame:SetFrameLevel(500)
    if ns.UI_ApplyHeaderCopyUrlShell then
        ns.UI_ApplyHeaderCopyUrlShell(discordCopyFrame)
    end
    discordCopyFrame:Hide()
    discordCopyBox = CreateFrame("EditBox", nil, discordCopyFrame)
    discordCopyBox:SetPoint("TOPLEFT", 6, -4)
    discordCopyBox:SetPoint("BOTTOMRIGHT", -6, 4)
    discordCopyBox:SetAutoFocus(false)
    discordCopyBox:SetFontObject(ChatFontNormal) -- required initial FontObject
    if ns.FontManager then
        ns.FontManager:RegisterManagedEditBox(discordCopyBox)
        ns.FontManager:ApplyFontToEditBox(discordCopyBox)
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
        if ns.UI_ApplyHeaderUtilityIconStyle then
            ns.UI_ApplyHeaderUtilityIconStyle(discordIcon, true)
        else
            discordIcon:SetAlpha(0.75)
        end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((ns.L and ns.L["DISCORD_TOOLTIP"]) or "Warband Nexus Discord", 1, 1, 1)
        GameTooltip:AddLine((ns.L and ns.L["CLICK_TO_COPY"]) or "Click to copy invite link", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    discordBtn:SetScript("OnLeave", function()
        if ns.UI_ApplyHeaderUtilityIconStyle then
            ns.UI_ApplyHeaderUtilityIconStyle(discordIcon, false)
        else
            discordIcon:SetAlpha(1.0)
        end
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
    local trackingChip = CreateFrame("Frame", nil, header)
    trackingChip:SetHeight(30)
    trackingChip:SetPoint("RIGHT", discordBtn, "LEFT", -8, 0)

    local trackingAccent = trackingChip:CreateTexture(nil, "ARTWORK", nil, 1)
    trackingAccent:SetWidth(3)
    trackingAccent:SetPoint("TOPLEFT", trackingChip, "TOPLEFT", 0, 0)
    trackingAccent:SetPoint("BOTTOMLEFT", trackingChip, "BOTTOMLEFT", 0, 0)
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

    local iconBack = CreateFrame("Frame", nil, trackingChip)
    iconBack:SetSize(20, 20)
    iconBack:SetPoint("LEFT", trackingAccent, "RIGHT", 6, 0)
    f.trackingIconBack = iconBack

    local trackingIcon = iconBack:CreateTexture(nil, "ARTWORK")
    trackingIcon:SetSize(14, 14)
    trackingIcon:SetPoint("CENTER", iconBack, "CENTER", 0, 0)
    local ok = pcall(trackingIcon.SetAtlas, trackingIcon, "common-icon-checkmark", false)
    if not ok then
        trackingIcon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
    end
    trackingIcon:SetVertexColor(0.35, 1, 0.45)
    if ns.UI_ApplyHeaderUtilityIconStyle and ns.UI_IsLightMode and ns.UI_IsLightMode() then
        ns.UI_ApplyHeaderUtilityIconStyle(trackingIcon, false)
    end
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
    local frameInnerW = math.max(360, (f:GetWidth() or 800) - shellInsetL - shellInsetR)
    local railW = (navLayoutMode == "rail" and ns.UI_ComputeGoldenRailWidth)
        and ns.UI_ComputeGoldenRailWidth(frameInnerW, MAIN_SHELL_LAYOUT)
        or (MAIN_SHELL_LAYOUT.NAV_RAIL_WIDTH or 168)
    local RAIL_TAB_H = (ns.UI_GetNavRailTabHeight and ns.UI_GetNavRailTabHeight())
        or MAIN_SHELL_LAYOUT.NAV_RAIL_TAB_HEIGHT or 38
    local RAIL_TOP_INSET = MAIN_SHELL_LAYOUT.NAV_RAIL_TOP_INSET or 8
    local RAIL_TAB_V_GAP = MAIN_SHELL_LAYOUT.NAV_RAIL_TAB_V_GAP or 3
    local RAIL_CONTENT_GAP = MAIN_SHELL_LAYOUT.NAV_RAIL_CONTENT_GAP or 10
    local RAIL_PAD = MAIN_SHELL_LAYOUT.NAV_RAIL_PAD or 6
    f._wnNavRailTopInset = RAIL_TOP_INSET
    f._wnNavTabVGap = RAIL_TAB_V_GAP

    local navRail = nil
    local navRailScroll = nil
    local navRailStrip = nil

    if navLayoutMode == "rail" then
        navRail = CreateFrame("Frame", nil, f)
        navRail:SetWidth(railW)
        do
            local railBg = (ns.UI_GetNavRailSurfaceBackdrop and ns.UI_GetNavRailSurfaceBackdrop())
                or (ns.UI_COLORS and ns.UI_COLORS.surfaceViewport)
                or { 0.13, 0.13, 0.155, 0.98 }
            if ns.UI_IsClassicMode and ns.UI_IsClassicMode() and ns.UI_ApplyClassicTransparentInterior then
                ns.UI_ApplyClassicTransparentInterior(navRail)
            elseif ns.UI_ApplyBorderlessSurface then
                local railOpts = { bgType = "bg" }
                ns.UI_ApplyBorderlessSurface(navRail, { railBg[1], railBg[2], railBg[3], railBg[4] or 0.98 }, railOpts)
            elseif ApplyVisuals then
                ApplyVisuals(navRail, { railBg[1], railBg[2], railBg[3], railBg[4] or 0.98 }, { COLORS.borderLight[1], COLORS.borderLight[2], COLORS.borderLight[3], 0.12 })
                if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(navRail) end
            end
        end
        local railDivider = navRail:CreateTexture(nil, "OVERLAY")
        local div = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor()) or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 }
        railDivider:SetColorTexture(div[1], div[2], div[3], div[4] or 1)
        railDivider:SetWidth(1)
        railDivider:SetPoint("TOPRIGHT", navRail, "TOPRIGHT", 0, 0)
        railDivider:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", 0, 0)
        if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
            railDivider:Hide()
        end
        f._wnNavRailDivider = railDivider
        if ns.UI_CreateClassicVerticalRailDivider then
            local railDividerClassic = ns.UI_CreateClassicVerticalRailDivider(navRail)
            railDividerClassic:SetPoint("TOPRIGHT", navRail, "TOPRIGHT", 0, 0)
            railDividerClassic:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", 0, 0)
            if not (ns.UI_IsClassicMode and ns.UI_IsClassicMode()) then
                railDividerClassic:Hide()
            end
            f._wnNavRailDividerClassic = railDividerClassic
        end
        f.navRail = navRail
        f._wnGoldenRailWidth = railW
        if navRail.SetClipsChildren then
            navRail:SetClipsChildren(true)
        end

        local railPad = RAIL_PAD
        local sepH = MAIN_SHELL_LAYOUT.NAV_RAIL_TAB_SEP_HEIGHT or 1
        local sepGap = MAIN_SHELL_LAYOUT.NAV_RAIL_SETTINGS_SEP_GAP or 4
        local settingsBottomPad = MAIN_SHELL_LAYOUT.NAV_RAIL_SETTINGS_BOTTOM_PAD or railPad
        local footerBtnGap = MAIN_SHELL_LAYOUT.NAV_RAIL_FOOTER_BTN_GAP or 4
        local railFooterH = sepH + sepGap + RAIL_TAB_H + footerBtnGap + RAIL_TAB_H + settingsBottomPad
        f._wnNavRailFooterH = railFooterH
        local navRailFooter = CreateFrame("Frame", nil, navRail)
        navRailFooter:SetHeight(railFooterH)
        navRailFooter:SetPoint("BOTTOMLEFT", navRail, "BOTTOMLEFT", 0, 0)
        navRailFooter:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", 0, 0)
        f.navRailFooter = navRailFooter

        local railFooterSep = navRailFooter:CreateTexture(nil, "ARTWORK")
        railFooterSep:SetHeight(sepH)
        railFooterSep:SetPoint("TOPLEFT", navRailFooter, "TOPLEFT", railPad, 0)
        railFooterSep:SetPoint("TOPRIGHT", navRailFooter, "TOPRIGHT", -railPad, 0)
        local sepDiv = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor()) or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 }
        railFooterSep:SetColorTexture(sepDiv[1], sepDiv[2], sepDiv[3], sepDiv[4] or 1)
        if isClassicShell and railFooterSep.Hide then
            railFooterSep:Hide()
        end
        f._wnNavRailFooterSep = railFooterSep

        navRailScroll = CreateFrame("ScrollFrame", nil, navRail)
        navRailScroll:SetPoint("TOPLEFT", navRail, "TOPLEFT", railPad, 0)
        navRailScroll:SetPoint("BOTTOMRIGHT", navRail, "BOTTOMRIGHT", -railPad, railPad + railFooterH)
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

    ---Shared main-window tab switch (nav tabs + rail Settings).
    ---@param targetTab string
    ---@param opts table|nil `{ persistLastTab = boolean }`
    local function ActivateMainTab(targetTab, opts)
        opts = opts or {}
        if not targetTab or f.currentTab == targetTab then return end
        if GetTime() < (f._wnMainTabInputGraceUntil or 0) then
            if f._wnBypassMainTabInputGraceOnce then
                f._wnBypassMainTabInputGraceOnce = nil
            else
                return
            end
        end

        if f.currentTab == "settings" then
            if WarbandNexus.StopSettingsKeybindCapture then
                WarbandNexus:StopSettingsKeybindCapture()
            end
            if ns._wnSettingsOpenDropdownMenu and ns._wnSettingsOpenDropdownMenu.Hide then
                ns._wnSettingsOpenDropdownMenu:Hide()
            end
            if ns._wnSettingsDropdownClickCatcher and ns._wnSettingsDropdownClickCatcher.Hide then
                ns._wnSettingsDropdownClickCatcher:Hide()
            end
        end
        if targetTab == "settings" then
            f._wnTabBeforeSettings = f.currentTab
        end

        f._tabSwitchGen = (f._tabSwitchGen or 0) + 1
        local tabSwitchGen = f._tabSwitchGen

        if f.AbortPendingPopulateDebounce then
            f:AbortPendingPopulateDebounce()
        end
        f._wnLastMainTabSwitchAt = GetTime()
        f._wnLastMainTabSwitchKey = targetTab

        local previousTab = f.currentTab

        if IsTabPerfMonitorEnabled() then
            f._wnPerfMainTabSwitch = {
                gen = tabSwitchGen,
                fromTab = previousTab,
                toTab = targetTab,
                wallStart = GetTime(),
            }
            debugprofilestart()
        else
            f._wnPerfMainTabSwitch = nil
        end

        if previousTab and f.scroll then
            if not f._tabScrollPositions then f._tabScrollPositions = {} end
            f._tabScrollPositions[previousTab] = {
                v = f.scroll:GetVerticalScroll() or 0,
                h = f.scroll:GetHorizontalScroll() or 0,
            }
        end

        f.currentTab = targetTab
        do
            local LT = ns.LoadingTracker
            f._wnLoadingCompleteAtTabSwitch = (LT and LT.IsComplete and LT:IsComplete()) and true or false
        end
        f._wnMainTabInputGraceUntil = GetTime() + 0.2
        UpdateTabButtonStates(f)
        if targetTab ~= "settings" then
            ScrollMainNavEnsureTabVisible(f, targetTab)
        end

        if opts.persistLastTab ~= false and targetTab ~= "settings" and targetTab ~= "about" then
            if WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.lastTab = targetTab
            end
            RememberSessionMainTab(targetTab)
        end

        if previousTab == "plans" and WarbandNexus.ClearCollectionMetadataCache then
            WarbandNexus:ClearCollectionMetadataCache()
        end

        ns.UIShell._recycleBinDrainGen = (ns.UIShell._recycleBinDrainGen or 0) + 1
        CancelLeavingTabStagedPaint(previousTab, f)

        f.isMainTabSwitch = true
        ClearAllSearchBoxes()

        if WarbandNexus.CloseAllPlanDialogs then
            WarbandNexus:CloseAllPlanDialogs()
        end

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
                local pendingDrain = 0
                local scrollChild = f.scrollChild
                if scrollChild then
                    if ns.UI_HideEphemeralScrollRegions then
                        ns.UI_HideEphemeralScrollRegions(scrollChild)
                    end
                    local nc = PackVariadicInto(_uiChildEnumScratch, scrollChild:GetChildren())
                    for i = 1, nc do
                        local child = _uiChildEnumScratch[i]
                        if child.isPersistentRowElement then
                            child:Hide()
                        elseif child._wnKeepOnTabSwitch then
                            DetachKeptScrollChildOnMainTabSwitch(child)
                        elseif child._wnProfColumnHeaderStrip then
                            child._wnKeepOnTabSwitch = nil
                            child:Hide()
                            child:SetParent(recycleBin)
                            child._wnPoolDrained = nil
                            pendingDrain = pendingDrain + 1
                        else
                            child:Hide()
                            child:SetParent(recycleBin)
                            child._wnPoolDrained = nil
                            pendingDrain = pendingDrain + 1
                        end
                    end
                    if pendingDrain > 0 then
                        ScheduleRecycleBinPoolDrain(pendingDrain)
                    end
                    if ns.UI_ParkScrollChildSharedHosts then
                        ns.UI_ParkScrollChildSharedHosts(scrollChild, targetTab)
                    end
                    f._contentPreCleared = true
                end
                return pendingDrain
            end

            local function finalizeTabSwitchPopulate()
                if tabSwitchGen ~= f._tabSwitchGen then
                    local pStale = f._wnPerfMainTabSwitch
                    if pStale and pStale.gen == tabSwitchGen and pStale.msClickToPoolEnd then
                        local Pst = ns.Profiler
                        if IsTabPerfMonitorEnabled() and Pst and Pst.AppendTraceAnomaly then
                            Pst:AppendTraceAnomaly(format(
                                "[Trace] tab switch stale gen=%s (superseded before populate)",
                                tostring(tabSwitchGen)))
                        end
                        f._wnPerfMainTabSwitch = nil
                        f._wnPerfTabSwitchPendingLog = nil
                        debugprofilestop()
                    end
                    return false
                end
                if f.currentTab ~= targetTab then
                    local pStale = f._wnPerfMainTabSwitch
                    if pStale and pStale.gen == tabSwitchGen and pStale.msClickToPoolEnd then
                        local Pst = ns.Profiler
                        if IsTabPerfMonitorEnabled() and Pst and Pst.AppendTraceAnomaly then
                            Pst:AppendTraceAnomaly(format(
                                "[Trace] tab switch aborted gen=%s (left %s before populate)",
                                tostring(tabSwitchGen), tostring(targetTab)))
                        end
                        f._wnPerfMainTabSwitch = nil
                        f._wnPerfTabSwitchPendingLog = nil
                        debugprofilestop()
                    end
                    return false
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
                WarbandNexus:PopulateContent(true)
                f.isMainTabSwitch = false
                return true
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
                    finalizeTabSwitchPopulate()
                end)
            end

            local function runPoolReleaseAndSchedulePopulate()
                runPoolReleaseOnly()
                schedulePopulateAfterPoolPerf()
            end

            runPoolReleaseAndSchedulePopulate()
        end)
    end
    f.ActivateMainTab = ActivateMainTab
    
        local function CreateTabButton(parent, text, key)
        -- Main nav tabs: icon + label (`rail` and `top`).
        local useClassicTab = ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
        local btn = useClassicTab
            and CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
            or CreateFrame("Button", nil, parent)
        if useClassicTab then
            btn._wnBlizzardButton = true
            if ns.UI_NormalizeBlizzardButtonChrome then
                ns.UI_NormalizeBlizzardButtonChrome(btn)
            end
        end
        local shellIco = MAIN_SHELL_LAYOUT
        local iconSz = railLayout and (shellIco.RAIL_TAB_ICON_SIZE or 22) or (shellIco.TAB_ICON_SIZE or 18)
        local iconInsetL = railLayout and RAIL_ICON_INSET or (shellIco.TAB_ICON_LEFT_INSET or 8)
        local iconGap = shellIco.TAB_ICON_GAP or 6
        local iconRight = shellIco.TAB_ICON_RIGHT_MARGIN or 8
        local iconBlock = iconInsetL + iconSz + iconGap

        if railLayout then
            btn:SetSize(railInnerBtnW, RAIL_TAB_H)
            if useClassicTab then
                btn:SetHeight(RAIL_TAB_H)
            end
        else
            btn:SetSize(DEFAULT_TAB_WIDTH, TAB_HEIGHT)
        end
        btn.key = key
        btn._wnRailTextMode = railLayout or nil

        -- Background (rail: flat; top: standard chrome). Classic: UIPanelButtonTemplate only.
        if not useClassicTab then
            if railLayout then
                if ns.UI_ApplyBorderlessSurface then
                    local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.45 }
                    ns.UI_ApplyBorderlessSurface(btn, idle)
                elseif ApplyVisuals then
                    local idle = ns.UI_GetNavRailIdleBackdrop and ns.UI_GetNavRailIdleBackdrop() or { 0.08, 0.08, 0.10, 0.45 }
                    ApplyVisuals(btn, idle, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.1 })
                    if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(btn) end
                end
            elseif ApplyVisuals then
                local idle = ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop() or { 0.12, 0.12, 0.15, 1 }
                ApplyVisuals(btn, idle, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
            end

            -- Apply highlight effect (safe check for Factory)
            if ns.UI_ApplyNavButtonHighlight then
                ns.UI_ApplyNavButtonHighlight(btn)
            elseif ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
                ns.UI.Factory:ApplyHighlight(btn)
            end
        end
        
        -- Active indicator strip: bottom (`top`) or leading edge (`rail`); hidden for Blizzard template tabs.
        local accentColorLine = COLORS.accent
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetColorTexture(accentColorLine[1], accentColorLine[2], accentColorLine[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar
        if useClassicTab then
            activeBar:Hide()
        elseif railLayout then
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
        local usedPackagedIcon = false
        if key == "about" and ns.UI_SetWnIconTexture then
            usedPackagedIcon = ns.UI_SetWnIconTexture(tabIcon, "credits", { 0.88, 0.88, 0.92, 1 })
        end
        if not usedPackagedIcon and ns.UI_ApplyMainNavTabGlyph then
            ns.UI_ApplyMainNavTabGlyph(tabIcon, key)
        elseif not usedPackagedIcon then
            local atlasNm = ns.UI_GetTabIcon and ns.UI_GetTabIcon(key) or nil
            local atlasOk = atlasNm and type(atlasNm) == "string" and pcall(tabIcon.SetAtlas, tabIcon, atlasNm, false)
            if not atlasOk then
                tabIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                tabIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        end
        tabIcon._wnNavPackagedIcon = usedPackagedIcon or nil
        tabIcon._wnNavRailIcon = railLayout or nil
        if ns.UI_ApplyNavTabIconStyle then
            ns.UI_ApplyNavTabIconStyle(tabIcon, false, { packaged = usedPackagedIcon, rail = railLayout })
        end

        local label = FontManager:CreateFontString(btn, FontManager:GetFontRole("mainNavTabLabel"), "OVERLAY")
        label._wnNavLabel = true
        local countReserve = shellIco.TAB_COUNT_RESERVE or 28
        if railLayout then
            label:SetPoint("LEFT", tabIcon, "RIGHT", iconGap, 0)
            label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText(text)
            ns.UI_SetTextColorRole(label, "Bright")
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
        ns.UI_SetTextColorRole(countLabel, "Dim", 0.8)
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
            ActivateMainTab(self.key, { persistLastTab = true })
        end)

        if railLayout then
            WireMainNavTabButtonUX(btn, text, nil)
        end

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
        pvp         = (ns.L and ns.L["TAB_PVP"]) or "PvP",
        professions = (ns.L and ns.L["TAB_PROFESSIONS"]) or "Professions",
        collections = (ns.L and ns.L["TAB_COLLECTIONS"]) or "Collections",
        plans       = (ns.L and ns.L["TAB_PLANS"]) or "To-Do",
        stats       = (ns.L and ns.L["TAB_STATISTICS"]) or "Statistics",
        about       = (ns.L and ns.L["SETTINGS_PANEL_ABOUT"]) or "About",
    }
    
    local function BuildMainNavTabStrip()
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

    local settingsLabel = (ns.L and ns.L["BTN_SETTINGS"]) or "Settings"
    local settingsTooltip = (ns.L and ns.L["NAV_SETTINGS_TOOLTIP"]) or "Warband Nexus options and preferences"
    if railLayout and f.navRailFooter then
        local sepH = MAIN_SHELL_LAYOUT.NAV_RAIL_TAB_SEP_HEIGHT or 1
        local sepGap = MAIN_SHELL_LAYOUT.NAV_RAIL_SETTINGS_SEP_GAP or 4
        local settingsBottomPad = MAIN_SHELL_LAYOUT.NAV_RAIL_SETTINGS_BOTTOM_PAD or RAIL_PAD
        local footerBtnGap = MAIN_SHELL_LAYOUT.NAV_RAIL_FOOTER_BTN_GAP or 4
        local footerClassic = ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()
        local settingsBtn = CreateTabButton(f.navRailFooter, settingsLabel, "settings")
        settingsBtn:ClearAllPoints()
        settingsBtn:SetPoint("TOPLEFT", f.navRailFooter, "TOPLEFT", RAIL_PAD, -(sepH + sepGap))
        settingsBtn:SetPoint("TOPRIGHT", f.navRailFooter, "TOPRIGHT", -RAIL_PAD, 0)
        settingsBtn:SetHeight(RAIL_TAB_H)
        f.navSettingsBtn = settingsBtn
        settingsBtn:SetScript("OnClick", function()
            if ns.SettingsUI and ns.SettingsUI.SetActivePanel then
                ns.SettingsUI.SetActivePanel("general")
            end
            ActivateMainTab("settings", { persistLastTab = false })
        end)
        WireMainNavTabButtonUX(settingsBtn, settingsTooltip, (ns.L and ns.L["SETTINGS_TAB_SUBTITLE"]) or nil)
        f.tabButtons.settings = settingsBtn

        local settingsAboutSep = f.navRailFooter:CreateTexture(nil, "ARTWORK")
        settingsAboutSep:SetHeight(sepH)
        settingsAboutSep:SetPoint("LEFT", f.navRailFooter, "LEFT", RAIL_PAD, 0)
        settingsAboutSep:SetPoint("RIGHT", f.navRailFooter, "RIGHT", -RAIL_PAD, 0)
        local gapAbove = math.floor(footerBtnGap * 0.5)
        local gapBelow = footerBtnGap - gapAbove
        settingsAboutSep:SetPoint("TOP", settingsBtn, "BOTTOM", 0, -gapAbove)
        do
            local sepCol = (ns.UI_GetNavRailDividerColor and ns.UI_GetNavRailDividerColor())
                or (ns.UI_COLORS and ns.UI_COLORS.accent) or { 0.6, 0.4, 1, 1 }
            settingsAboutSep:SetColorTexture(sepCol[1], sepCol[2], sepCol[3], sepCol[4] or 1)
        end
        if footerClassic then
            settingsAboutSep:Hide()
        end
        f._wnNavRailSettingsAboutSep = settingsAboutSep

        local aboutLabel = TAB_LABELS.about
        local aboutTooltip = (ns.L and ns.L["SETTINGS_PANEL_ABOUT_DESC"]) or "Credits, contributors, and a guide to every tab."
        local aboutBtn = CreateTabButton(f.navRailFooter, aboutLabel, "about")
        aboutBtn:ClearAllPoints()
        if footerClassic then
            aboutBtn:SetPoint("TOPLEFT", settingsBtn, "BOTTOMLEFT", 0, -footerBtnGap)
            aboutBtn:SetPoint("TOPRIGHT", settingsBtn, "BOTTOMRIGHT", 0, 0)
        else
            aboutBtn:SetPoint("TOPLEFT", settingsAboutSep, "BOTTOMLEFT", 0, -gapBelow)
            aboutBtn:SetPoint("TOPRIGHT", settingsAboutSep, "BOTTOMRIGHT", 0, 0)
        end
        aboutBtn:SetHeight(RAIL_TAB_H)
        f.navAboutBtn = aboutBtn
        f.tabButtons.about = aboutBtn
        aboutBtn:SetScript("OnClick", function()
            ActivateMainTab("about", { persistLastTab = false })
        end)
        WireMainNavTabButtonUX(aboutBtn, aboutTooltip, nil)
    elseif navLayoutMode == "top" then
        local navBarH = nav:GetHeight() or MAIN_SHELL_LAYOUT.NAV_BAR_HEIGHT or 36
        local settingsBtn = CreateTabButton(nav, settingsLabel, "settings")
        settingsBtn:SetHeight(navBarH)
        settingsBtn:SetPoint("TOPRIGHT", nav, "TOPRIGHT", -MAIN_TAB_STRIP_EDGE_INSET, 0)
        settingsBtn:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -MAIN_TAB_STRIP_EDGE_INSET, 0)
        f.navSettingsBtn = settingsBtn
        if f.tabNavScroll then
            f.tabNavScroll:ClearAllPoints()
            f.tabNavScroll:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, 0)
            f.tabNavScroll:SetPoint("BOTTOMRIGHT", settingsBtn, "BOTTOMLEFT", -8, 0)
        end
        settingsBtn:SetScript("OnClick", function()
            ActivateMainTab("settings", { persistLastTab = false })
        end)
        WireMainNavTabButtonUX(settingsBtn, settingsTooltip, nil)
    end
    end

    local function DestroyMainNavTabStrip()
        if f.tabButtons then
            for _, btn in pairs(f.tabButtons) do
                if btn then
                    btn:Hide()
                    btn:ClearAllPoints()
                    btn:SetParent(nil)
                end
            end
        end
        f.tabButtons = {}
        f.navSettingsBtn = nil
        f.navAboutBtn = nil
        if f._wnNavRailSettingsAboutSep then
            f._wnNavRailSettingsAboutSep:Hide()
            f._wnNavRailSettingsAboutSep = nil
        end
    end

    BuildMainNavTabStrip()
    f._wnRebuildNavButtons = function()
        local activeTab = f.currentTab
        DestroyMainNavTabStrip()
        BuildMainNavTabStrip()
        f.currentTab = activeTab
        UpdateTabVisibility(f)
        if railLayout then
            ApplyMainNavGoldenShellLayout(f)
            RefreshMainNavRailStrip(f)
        else
            RefreshMainNavTabStrip(f)
        end
        if ns.UI_UpdateMainFrameTabButtonStates then
            ns.UI_UpdateMainFrameTabButtonStates(f)
        end
    end
    ns.UI_RebuildMainNavButtons = function(mainFrame)
        if mainFrame and mainFrame._wnRebuildNavButtons then
            mainFrame._wnRebuildNavButtons()
        end
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
                    local idle = ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop() or { 0.12, 0.12, 0.15, 1 }
                    btn:SetBackdropColor(idle[1], idle[2], idle[3], idle[4] or 1)
                    btn:SetBackdropBorderColor(accentColor[1] * 0.8, accentColor[2] * 0.8, accentColor[3] * 0.8, 1)
                end
            end
        end
    end
    
    -- Footer strip (text + version); shell layout via ApplyMainShellLayout.

    -- Factory candidate: `Factory:CreateContainer` â€” inherits `BackdropTemplate` mixin immediately below for panel BG tint.
    local content = CreateFrame("Frame", nil, f)
    f.content = content
    if content.SetClipsChildren then
        content:SetClipsChildren(true)
    end

    local isClassicShell = ns.UI_IsClassicMode and ns.UI_IsClassicMode()

    -- Background only on content (no border); border will be on viewport frame so scrollbars sit outside it
    if not content.SetBackdrop then
        Mixin(content, BackdropTemplateMixin)
    end
    if isClassicShell and ns.UI_ApplyClassicTransparentInterior then
        ns.UI_ApplyClassicTransparentInterior(content)
    else
        content:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        do
            local bc = (ns.UI_GetMainPanelBackgroundColor and ns.UI_GetMainPanelBackgroundColor())
                or (ns.UI_COLORS and ns.UI_COLORS.bg)
                or { 0.042, 0.042, 0.055, 0.98 }
            content:SetBackdropColor(bc[1], bc[2], bc[3], bc[4] or 0.98)
        end
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

    -- Factory candidate: `Factory:CreateContainer` â€” viewport rim (scroll insets anchor to this).
    local viewportBorder = CreateFrame("Frame", nil, content)
    viewportBorder:SetPoint("TOPLEFT", content, "TOPLEFT", SCROLL_INSET_LEFT, -SCROLL_INSET_TOP)
    viewportBorder:SetPoint("TOPRIGHT", content, "TOPRIGHT", -SCROLL_INSET_RIGHT, -SCROLL_INSET_TOP)
    viewportBorder:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", SCROLL_INSET_LEFT, SCROLL_INSET_BOTTOM)
    viewportBorder:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -SCROLL_INSET_RIGHT, SCROLL_INSET_BOTTOM)
    viewportBorder:SetFrameLevel(content:GetFrameLevel() + 1)
    if not viewportBorder.SetBackdrop then
        Mixin(viewportBorder, BackdropTemplateMixin)
    end
    if isClassicShell and ns.UI_ApplyClassicTransparentInterior then
        ns.UI_ApplyClassicTransparentInterior(viewportBorder)
    else
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
    end
    if ns.UI_HideFrameBorderQuartet then ns.UI_HideFrameBorderQuartet(viewportBorder) end
    f.viewportBorder = viewportBorder

    -- Factory candidate: `Factory:CreateContainer` â€” non-scroll title/search host.
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
    local scrollBarColumn = ns.UI.Factory.CreateBareScrollBarColumn and ns.UI.Factory:CreateBareScrollBarColumn(content, SCROLL_COLUMN_W)
        or ns.UI.Factory:CreateScrollBarColumn(content, SCROLL_COLUMN_W, 0, 0)
    scrollBarColumn:SetFrameLevel(viewportBorder:GetFrameLevel() + 2)
    f.scrollBarColumn = scrollBarColumn
    if ns.UI.Factory.EnsureScrollBarColumnSync then
        ns.UI.Factory:EnsureScrollBarColumnSync(scroll, scrollBarColumn, { width = SCROLL_COLUMN_W, gap = SCROLL_GAP })
    elseif scroll.ScrollBar and ns.UI.Factory.SyncScrollBarColumnToViewport then
        ns.UI.Factory:SyncScrollBarColumnToViewport(scroll, scrollBarColumn, { width = SCROLL_COLUMN_W, gap = SCROLL_GAP })
    elseif scroll.ScrollBar and ns.UI.Factory.PositionScrollBarInContainer then
        ns.UI.Factory:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
    end
    scroll._wnKeepScrollLane = true

    -- Factory candidate: scroll child is a dumb host; only bottom-fill band (`scrollChild._wnScrollBottomFill`) matters for Factory parity.
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(1)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)
    f.scrollChild = scrollChild

    -- Horizontal bar: strip height tracks vertical scrollbar column width (`H_ROW_H`); viewport gap (`SCROLL_GAP`) matches main scroll chrome.
    -- Factory candidate: `Factory:CreateContainer` â€” bar strip host only (`CreateHorizontalScrollBar` does the knob).
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
        if f.currentTab == "professions" then
            if ns.UI_RelayoutProfessionRowWidths and f.scrollChild
                and not f.scrollChild._wnProfSectionStackRelayoutLock then
                ns.UI_RelayoutProfessionRowWidths(f.scrollChild)
            end
            if ns.UI_DebounceProfessionRowGradientRefresh then
                ns.UI_DebounceProfessionRowGradientRefresh(f)
            end
        end
    end

    -- Pixel-snap scroll: snap every scroll offset to the nearest physical pixel boundary.
    -- Without this, scrollChild sits at sub-pixel positions (e.g., 123.456) causing ALL
    -- child frames to render with anti-aliasing â€” visible as wobbling/jittering borders.
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
            and ns.UI_IsMainFrameResizeSession
            and ns.UI_IsMainFrameResizeSession(f)
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
    S.setMainFrame(f)
    mainFrame = f
    
    -- UI automatically refreshes when DB data changes.
    -- All listeners use SchedulePopulateContent() to coalesce rapid events
    -- (e.g., bank open fires WN_ITEMS_UPDATED + WN_BAGS_UPDATED + WN_ITEM_METADATA_READY
    -- within milliseconds -- without coalescing this causes 3+ PopulateContent calls).
    local Constants = ns.Constants
    
    local shellRefresh = {
        pendingPopulateTimer = nil,
        pendingPopulateSkipCooldown = false,
        pendingPopulateTab = nil,
        bypassQuietForSync = false,
        populateDebounceGen = 0,
        lastEventPopulateTime = 0,
        gearItemInfoCoalesceGen = 0,
        gearItemInfoCoalesceTimer = nil,
        gearStorageRecRefreshTimer = nil,
        gearStorageRecRefreshEquipOnly = false,
        dirtyWhileHidden = false,
    }
    -- PopulateContentBody (file scope) clears dirtyWhileHidden through this reference.
    f._shellRefreshState = shellRefresh
    local POPULATE_DEBOUNCE = 0.1  -- 100ms coalesce window (resets on each new message = last event wins)
    local POPULATE_COOLDOWN = 0.8  -- Skip event-driven rebuild if one ran within 800ms
    -- This prevents duplicate rebuilds from WN_ITEMS_UPDATED (~0.5s) + WN_BAGS_UPDATED (~1.0s)
    -- firing for the same loot event. Does NOT affect direct PopulateContent calls (tab switch, resize).
    -- Profession storms use skipCooldown only while the trade skill window is open (UI_RefreshRouter).
    -- GET_ITEM_INFO_RECEIVED / metadata warm-up can storm while the client resolves many links; throttle gear repaints.
    local MAIN_TAB_DEBOUNCED_QUIET = SHELL_TAB_SWITCH_POPULATE_QUIET
    local GEAR_ASYNC_ITEM_REPAINT_INTERVAL = 0.55
    local gearAsyncItemRepaintNext = 0
    -- Blizzard can fire GET_ITEM_INFO_RECEIVED many times per frame burst; never sync-redraw per event.
    -- Coalesce Invalidate+Resolve+Redraw from rapid GEAR_UPDATED (e.g. paired ring swaps) into one pass per window.
    local GEAR_STORAGE_REC_REFRESH_DEBOUNCE = 0.06
    -- Bag/item DB merges: avoid full Gear tab teardown; refresh storage recommendations + paperdoll icons only.
    local GEAR_TAB_INV_NARROW_DEBOUNCE = 0.08
    local gearTabInvNarrowTimer = nil

    local function IsGearTabPopulateQuiet()
        local untilT = ns._gearTabPopulateQuietUntil
        return untilT and GetTime() < untilT
    end

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
        if not IsGearTabPopulateQuiet() and not ns._gearStorageYieldCo
            and not (f._gearDeferChainActive == true) then
            if WarbandNexus.TryRefreshAllGearEquipSlotIcons then
                WarbandNexus:TryRefreshAllGearEquipSlotIcons()
            end
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
        shellRefresh.pendingPopulateTimer = nil
        if myGen ~= shellRefresh.populateDebounceGen then return end
        if not f or not f:IsShown() then return end
        local scheduledTab = shellRefresh.pendingPopulateTab
        shellRefresh.pendingPopulateTab = nil
        if scheduledTab and f.currentTab ~= scheduledTab then
            return
        end
        if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(f) then
            f._wnDeferredPopulateAfterResize = true
            return
        end
        -- Read once up-front: gear+defer gate used to clear this before evaluating skipCooldown,
        -- which dropped GET_ITEM_INFO_RECEIVED / ITEM_METADATA repaints for the entire storage defer window.
        local useSkip = shellRefresh.pendingPopulateSkipCooldown
        shellRefresh.pendingPopulateSkipCooldown = false
        local bypassQuiet = shellRefresh.bypassQuietForSync == true
        shellRefresh.bypassQuietForSync = false
        if f.currentTab == "gear" and IsGearTabPopulateQuiet() and not useSkip then
            return
        end
        if f.currentTab == "gear" and (ns._gearStorageDeferAwaiting or f._gearDeferChainActive) then
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
            elseif not useSkip then
                return
            end
        end
        if not bypassQuiet and f._wnLastMainTabSwitchAt and f._wnLastMainTabSwitchKey == f.currentTab
            and (GetTime() - f._wnLastMainTabSwitchAt) < MAIN_TAB_DEBOUNCED_QUIET then
            local remain = MAIN_TAB_DEBOUNCED_QUIET - (GetTime() - f._wnLastMainTabSwitchAt) + 0.02
            shellRefresh.pendingPopulateTab = f.currentTab
            if useSkip then
                shellRefresh.pendingPopulateSkipCooldown = true
            end
            shellRefresh.pendingPopulateTimer = C_Timer.NewTimer(remain, function()
                RunDebouncedPopulateTimerBody(myGen)
            end)
            return
        end
        local now = GetTime()
        if not useSkip and (now - shellRefresh.lastEventPopulateTime) < POPULATE_COOLDOWN then
            -- Trailing edge: re-arm for the cooldown remainder instead of silently dropping
            -- the last event of a burst. A newer SchedulePopulateContent bumps the gen and
            -- obsoletes this timer, so coalescing behavior is unchanged.
            local remain = POPULATE_COOLDOWN - (now - shellRefresh.lastEventPopulateTime) + 0.02
            shellRefresh.pendingPopulateTab = f.currentTab
            shellRefresh.pendingPopulateTimer = C_Timer.NewTimer(remain, function()
                RunDebouncedPopulateTimerBody(myGen)
            end)
            return
        end
        shellRefresh.lastEventPopulateTime = now
        local P = ns.Profiler
        local mlab = P and P.enabled and P.SliceLabel and P:SliceLabel(P.CAT.MSG, "EventPopulate_debounced")
        if mlab then P:Start(mlab) end
        WarbandNexus:PopulateContent(bypassQuiet == true)
        if mlab then P:Stop(mlab) end
    end

    local function SchedulePopulateContent(skipCooldown, opts)
        if not f or not f:IsShown() then return end
        if skipCooldown then
            shellRefresh.pendingPopulateSkipCooldown = true
        end
        if opts and opts.bypassQuietForSync then
            shellRefresh.bypassQuietForSync = true
        end
        shellRefresh.pendingPopulateTab = f.currentTab
        if shellRefresh.pendingPopulateTimer and shellRefresh.pendingPopulateTimer.Cancel then
            shellRefresh.pendingPopulateTimer:Cancel()
            shellRefresh.pendingPopulateTimer = nil
        end
        shellRefresh.populateDebounceGen = shellRefresh.populateDebounceGen + 1
        local myGen = shellRefresh.populateDebounceGen
        if C_Timer and C_Timer.NewTimer then
            shellRefresh.pendingPopulateTimer = C_Timer.NewTimer(POPULATE_DEBOUNCE, function()
                RunDebouncedPopulateTimerBody(myGen)
            end)
            return
        end
        local afterHandle = C_Timer.After(POPULATE_DEBOUNCE, function()
            RunDebouncedPopulateTimerBody(myGen)
        end)
        if type(afterHandle) == "table" and afterHandle.Cancel then
            shellRefresh.pendingPopulateTimer = afterHandle
        else
            shellRefresh.pendingPopulateTimer = true
        end
    end

    function f:CancelPendingPopulateDebounce()
        shellRefresh.populateDebounceGen = shellRefresh.populateDebounceGen + 1
        if shellRefresh.pendingPopulateTimer and shellRefresh.pendingPopulateTimer.Cancel then
            shellRefresh.pendingPopulateTimer:Cancel()
        end
        shellRefresh.pendingPopulateTimer = nil
        shellRefresh.pendingPopulateSkipCooldown = false
        shellRefresh.pendingPopulateTab = nil
        shellRefresh.bypassQuietForSync = false
        shellRefresh.lastEventPopulateTime = GetTime()
        CancelShellGearAsyncTimers(shellRefresh)
        if gearTabInvNarrowTimer and gearTabInvNarrowTimer.Cancel then
            gearTabInvNarrowTimer:Cancel()
        end
        gearTabInvNarrowTimer = nil
    end

    --- Kill only the pending debounce timer (no shellRefresh.lastEventPopulateTime bump). Used on main-tab switch so
    --- stale WN_* coalescers from the previous tab cannot fire after we've already invalidated gen.
    function f:AbortPendingPopulateDebounce()
        shellRefresh.populateDebounceGen = shellRefresh.populateDebounceGen + 1
        if shellRefresh.pendingPopulateTimer and shellRefresh.pendingPopulateTimer.Cancel then
            shellRefresh.pendingPopulateTimer:Cancel()
        end
        shellRefresh.pendingPopulateTimer = nil
        shellRefresh.pendingPopulateSkipCooldown = false
        shellRefresh.pendingPopulateTab = nil
        shellRefresh.bypassQuietForSync = false
        CancelShellGearAsyncTimers(shellRefresh)
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
            computeScrollContentWidth = GetScrollViewportWidth,
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
    
    if ns.UI_RefreshRouter and ns.UI_RefreshRouter.RegisterMainShellListeners then
        ns.UI_RefreshRouter.RegisterMainShellListeners({
            addon = WarbandNexus,
            frame = f,
            eventsSelf = UIEvents,
            constants = Constants,
            state = shellRefresh,
            schedulePopulate = SchedulePopulateContent,
            scheduleGearInvNarrow = ScheduleGearTabInventoryNarrowRefresh,
            throttledGearAsyncRepaint = ThrottledScheduleGearAsyncRepaint,
            isGearTabQuiet = IsGearTabPopulateQuiet,
            gearStorageRecRefreshDebounce = GEAR_STORAGE_REC_REFRESH_DEBOUNCE,
            updateTabVisibility = UpdateTabVisibility,
            scrollNavEnsureTabVisible = ScrollMainNavEnsureTabVisible,
            updateTabButtonStates = UpdateTabButtonStates,
        })
    end

    if ns.UI_RefreshRouter and ns.UI_RefreshRouter.RegisterShellLifecycleHooks then
        ns.UI_RefreshRouter.RegisterShellLifecycleHooks({
            addon = WarbandNexus,
            frame = f,
            state = shellRefresh,
            schedulePopulate = SchedulePopulateContent,
            syncDebugHeader = true,
        })
    end

    -- Loading bar is now a standalone floating frame (see CreateLoadingOverlay below)

    -- Footer: left disclaimer / hints, right add-on version (TOC metadata).
    do
        -- Factory candidate: `Factory:CreateContainer` â€” thin footer lane (scrollbar reserve on right edge).
        local footerBar = CreateFrame("Frame", nil, f)
        footerBar:SetHeight(MAIN_SHELL_LAYOUT.FOOTER_HEIGHT or 26)
        footerBar:SetFrameLevel((f:GetFrameLevel() or 0) + 4)
        footerBar:EnableMouse(false)
        f.footerBar = footerBar

        local footerTop = footerBar:CreateTexture(nil, "ARTWORK")
        footerTop:SetHeight(1)
        footerTop:SetPoint("TOPLEFT", footerBar, "TOPLEFT", 0, 0)
        footerTop:SetPoint("TOPRIGHT", footerBar, "TOPRIGHT", 0, 0)
        if COLORS then
            local footDiv = (ns.UI_GetFooterDividerColor and ns.UI_GetFooterDividerColor())
                or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.28 }
            footerTop:SetColorTexture(footDiv[1], footDiv[2], footDiv[3], footDiv[4] or 0.28)
        else
            footerTop:SetColorTexture(0.45, 0.25, 0.75, 0.35)
        end
        f.footerTop = footerTop

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
        ns.UI_SetTextColorRole(footerVersion, "Muted", 0.95)
        local verFmt = (L and L["MAIN_FOOTER_VERSION_FMT"]) or "v%s"
        footerVersion:SetText(string.format(verFmt, metaVer))
        f.footerVersionText = footerVersion

        local footerLeft = FontManager:CreateFontString(footerBar, "small", "OVERLAY")
        footerLeft:SetPoint("LEFT", footerBar, "LEFT", 8, 0)
        footerLeft:SetPoint("RIGHT", footerVersion, "LEFT", -14, 0)
        footerLeft:SetJustifyH("LEFT")
        footerLeft:SetWordWrap(false)
        footerLeft:SetNonSpaceWrap(true)
        ns.UI_SetTextColorRole(footerLeft, "Dim", 0.92)
        footerLeft:SetText((L and L["MAIN_FOOTER_LEFT"]) or "Crafted with care, for everyone who plays.")
        f.footerLeftText = footerLeft

        if f.resizeGrip then
            local grip = f.resizeGrip
            local gripSize = MAIN_SHELL_LAYOUT.RESIZE_GRIP_SIZE or 18
            grip:SetSize(gripSize, gripSize)
            grip:SetFrameLevel((f:GetFrameLevel() or 0) + (MAIN_SHELL_LAYOUT.RESIZE_GRIP_FRAMELEVEL_BOOST or 80))
        end
    end

    ApplyMainShellLayout(f)
    
    ns._wnMainWindowVisible = f:IsShown()

    -- Master OnHide: cleanup when addon window closes
    f:SetScript("OnHide", function(self)
        ns._wnMainWindowVisible = false
        if shellRefresh.pendingPopulateTimer then
            if shellRefresh.pendingPopulateTimer.Cancel then
                shellRefresh.pendingPopulateTimer:Cancel()
            end
        end
        shellRefresh.pendingPopulateTimer = nil
        shellRefresh.pendingPopulateSkipCooldown = false
        shellRefresh.pendingPopulateTab = nil
        shellRefresh.bypassQuietForSync = false
        shellRefresh.populateDebounceGen = shellRefresh.populateDebounceGen + 1
        CancelShellGearAsyncTimers(shellRefresh)
        ns.UIShell._recycleBinDrainGen = (ns.UIShell._recycleBinDrainGen or 0) + 1
        StopCustomDrag(self)
        SaveWindowGeometry(self)
        if ns.HideGearCharacterDropdown then
            ns.HideGearCharacterDropdown()
        end
        if WarbandNexus.CloseAllPlanDialogs then
            WarbandNexus:CloseAllPlanDialogs()
        end
        ClearAllSearchBoxes()
        if WarbandNexus.StopSettingsKeybindCapture then
            WarbandNexus:StopSettingsKeybindCapture()
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
        local patreonBtn = self.patreonBtn
        local clsBtn = self.closeBtn
        if not patreonBtn or not clsBtn then return end
        local p = WarbandNexus.db and WarbandNexus.db.profile
        local show = p and ProfileFlagOn(p.debugMode)
        if reloadBtn then reloadBtn:SetShown(show) end
        patreonBtn:ClearAllPoints()
        if show and reloadBtn then
            patreonBtn:SetPoint("RIGHT", reloadBtn, "LEFT", -6, 0)
        else
            patreonBtn:SetPoint("RIGHT", clsBtn, "LEFT", -6, 0)
        end
    end
    f:SyncMainHeaderDebugReloadLayout()

    if ns.UI_RaiseMainWindowShellBorderOverlay then
        ns.UI_RaiseMainWindowShellBorderOverlay(f)
    end

    -- Frame is already hidden (Hide() called immediately after CreateFrame)
    return f
end

