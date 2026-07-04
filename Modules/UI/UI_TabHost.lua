--[[ UI tab host ]]
local ADDON_NAME, ns = ...
local S = assert(ns.UIShell, "UI_TabHost: load Modules/UI.lua first")
local B = assert(ns.UIShell._bind, "UI_TabHost: UIShell._bind missing")
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
local _uiChildEnumScratch = B._uiChildEnumScratch
local _uiRegionEnumScratch = B._uiRegionEnumScratch
local TAB_DRAW_PERF_TRACE = B.TAB_DRAW_PERF_TRACE
local WarbandNexus = ns.WarbandNexus


local function PopulateContentBody(self, forceRepaint)
    local mainFrame = S.getMainFrame()
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

    -- A populate is happening: whatever arrived while hidden is now being painted.
    if mainFrame._shellRefreshState then
        mainFrame._shellRefreshState.dirtyWhileHidden = false
    end

    local populateWallStart = GetTime()

    if mainFrame.SyncMainHeaderDebugReloadLayout then
        mainFrame:SyncMainHeaderDebugReloadLayout()
    end

    -- Live resize + debounced commit: shell only; tab body relayout runs once on resize_commit (LayoutCoordinator).
    if ns.UI_IsMainFrameResizeSession and ns.UI_IsMainFrameResizeSession(mainFrame) then
        if ns.UI_EnsureMainScrollLayout then
            ns.UI_EnsureMainScrollLayout()
        end
        return
    end

    -- Persisted lastTab can point at a tab whose module is disabled (hidden nav button).
    -- Clamp before tab-switch detection so highlight and scroll body stay aligned.
    if mainFrame.currentTab ~= "settings" and mainFrame.currentTab ~= "about" and not IsTabModuleEnabled(mainFrame.currentTab) then
        mainFrame.currentTab = "chars"
        local p = WarbandNexus.db and WarbandNexus.db.profile
        if p then
            p.lastTab = "chars"
        end
    end

    local pendingPerfGen = IsTabPerfMonitorEnabled() and mainFrame._wnPerfTabSwitchPendingLog or nil

    if ShouldSkipRedundantShellPopulate(mainFrame, forceRepaint == true) then
        _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_coalesceSkip")
        local Pco = ns.Profiler
        if Pco and Pco.AppendTraceAnomaly then
            Pco:AppendTraceAnomaly(format(
                "[Trace] populate coalesced tab=%s gen=%s (%.2fs since switch)",
                tostring(mainFrame.currentTab),
                tostring(mainFrame._tabSwitchGen),
                (GetTime() - (mainFrame._wnLastMainTabSwitchAt or GetTime()))))
        end
        if pendingPerfGen then
            debugprofilestop()
            mainFrame._wnPerfMainTabSwitch = nil
            mainFrame._wnPerfTabSwitchPendingLog = nil
        end
        _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_coalesceSkip")
        return
    end

    local prevPopTab = mainFrame._prevPopulatedTab
    local isTabSwitch = (prevPopTab ~= mainFrame.currentTab)
    if mainFrame.currentTab ~= "professions" and WarbandNexus.HideProfessionColumnPicker then
        WarbandNexus:HideProfessionColumnPicker()
    end
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
            local Pgs = ns.Profiler
            if Pgs and Pgs.AppendTraceAnomaly then
                Pgs:AppendTraceAnomaly("[Trace] gear populate unchanged (sig skip)")
            end
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

    -- GearUI FinishGearOpenTrace emits one summary line (verbose phases gated in GearUI).

    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_teardownUI")
    mainFrame._pveMinScrollWidth = nil
    mainFrame._pvpMinScrollWidth = nil
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
    
    -- Reset scrollChild height to prevent layout corruption across tabs
    scrollChild:SetHeight(1)  -- Reset to minimal height, will expand as content is added
    
    if ns.TeardownPlansScrollChildBrowseArtifacts then
        ns.TeardownPlansScrollChildBrowseArtifacts(scrollChild)
    end

    local wasPreCleared = isTabSwitch and mainFrame._contentPreCleared
    mainFrame._contentPreCleared = nil

    if wasPreCleared then
        PurgeScrollChildLeaksAfterFastDetach(scrollChild)
    elseif not wasPreCleared then
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
            elseif isTabSwitch and child._wnKeepOnTabSwitch then
                DetachKeptScrollChildOnMainTabSwitch(child)
            elseif child._wnProfColumnHeaderStrip or not child._wnKeepOnTabSwitch then
                if child._wnProfColumnHeaderStrip then
                    child._wnKeepOnTabSwitch = nil
                end
                child:Hide()
                child:SetParent(recycleBin)
            end
        end
    end
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_teardownUI")

    if ns.UI_ParkScrollChildSharedHosts then
        ns.UI_ParkScrollChildSharedHosts(scrollChild, mainFrame.currentTab)
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

    local tab = mainFrame.currentTab
    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_drawTab/" .. tostring(tab))
    -- Draw based on current tab
    local height
    local isTracked = ns.CharacterService and ns.CharacterService:IsCharacterTracked(self)
    local trackedOnlyTabs = {
        items = true, pve = true, reputations = true,
        currency = true, professions = true, gear = true, collections = true,
        plans = true, stats = true,
    }

    -- Dev-only: wall time for scroll-heavy mains (WN-PERF checklist). Complements tab-switch clickâ†’populate log + `Pop_drawTab`.
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
    elseif tab == "pvp" then
        height = self:DrawPvPTab(scrollChild)
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
        height = self:DrawGearTab(scrollChild)
    elseif tab == "collections" then
        local cui = ns.CollectionsUI
        if cui and cui.CollectionsSubTabTrace then
            cui.CollectionsSubTabTrace("PopulateContent_DrawCollectionsTab", {
                forceRepaint = forceRepaint and true or false,
                isTabSwitch = isTabSwitch and true or false,
            })
        end
        height = self:DrawCollectionsTab(scrollChild)
    elseif tab == "plans" then
        height = self:DrawPlansTab(scrollChild)
    elseif tab == "settings" then
        if self.DrawSettingsTab then
            height = self:DrawSettingsTab(scrollChild)
        else
            height = 200
        end
    elseif tab == "about" then
        if self.DrawAboutTab then
            height = self:DrawAboutTab(scrollChild)
        else
            height = 200
        end
    else
        height = self:DrawCharacterList(scrollChild)
    end
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_drawTab/" .. tostring(tab))
    height = tonumber(height) or 0
    -- DrawTab wall time: verbose detail only (main tab switch uses ScheduleTabSwitchPerfTrace).
    if drawPerfT0 and not pendingPerfGen then
        local ms = (GetTime() - drawPerfT0) * 1000
        local Pdraw = ns.Profiler
        local minMs = (Pdraw and Pdraw.TRACE_DRAW_TAB_MIN_MS) or 5
        local anomalyMs = (Pdraw and Pdraw.TRACE_ANOMALY_MS) or 16.67
        if ms >= minMs and Pdraw then
            if Pdraw.IsTraceVerbose and Pdraw:IsTraceVerbose() then
                Pdraw:AppendTraceVerbose(format("[Perf] DrawTab %s %.1fms", tab, ms))
            elseif ms >= anomalyMs and Pdraw.EmitPerfSummary then
                Pdraw:EmitPerfSummary("Perf", ms, format("DrawTab %s", tostring(tab)), { force = false })
            end
        end
    end
    scrollChild._preparedByPopulate = nil

    _wnProfSliceStart(ns.Profiler.CAT.UI, "Pop_postLayout")
    -- Set scrollChild height based on content + bottom padding
    local CONTENT_BOTTOM_PADDING = (ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12
    local contentBottom = height + CONTENT_BOTTOM_PADDING
    if tab == "professions" and scrollChild._wnProfEstimatedScrollBody then
        contentBottom = math.max(contentBottom, scrollChild._wnProfEstimatedScrollBody + CONTENT_BOTTOM_PADDING)
    end
    -- Gear tab: extend scrollChild to viewport so the gear card can fill downward (see DrawPaperDollCard fill).
    local viewportH = mainFrame.scroll and mainFrame.scroll:GetHeight() or 0
    -- First layout frame: GetHeight() can be 0 while anchors are valid â€” derive from geometry so scrollChild fills the viewport.
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
    local isClassicTab = ns.UI_IsClassicMode and ns.UI_IsClassicMode()
    if not isClassicTab and tab ~= "items" and tab ~= "gear" and ns.UI_EnsureScrollChildViewportFill then
        ns.UI_EnsureScrollChildViewportFill(scrollChild)
    end
    if not isClassicTab and tab ~= "items" and tab ~= "gear" and ns.UI_RefreshScrollAnnexLayout then
        ns.UI_RefreshScrollAnnexLayout(scrollChild)
    end

    -- When content is shorter than the viewport, paint a viewport-tone band below short content.
    if not isClassicTab then
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
    elseif scrollChild._wnScrollBottomFill and scrollChild._wnScrollBottomFill.Hide then
        scrollChild._wnScrollBottomFill:Hide()
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
    
    -- Tab switch: open at top; restore prior scroll offset for Settings when returning.
    if mainFrame.isMainTabSwitch and mainFrame.scroll then
        local saved = (tab == "settings" and mainFrame._tabScrollPositions)
            and mainFrame._tabScrollPositions.settings
        if saved then
            mainFrame.scroll:SetVerticalScroll(saved.v or 0)
            mainFrame.scroll:SetHorizontalScroll(saved.h or 0)
            if mainFrame.hScroll and mainFrame.hScroll.SetValue then
                mainFrame.hScroll:SetValue(saved.h or 0)
            end
        else
            mainFrame.scroll:SetVerticalScroll(0)
            mainFrame.scroll:SetHorizontalScroll(0)
            if mainFrame.hScroll and mainFrame.hScroll.SetValue then
                mainFrame.hScroll:SetValue(0)
            end
        end
    end

    if mainFrame._virtualScrollUpdate then
        mainFrame._virtualScrollUpdate()
    end

    UpdateScrollLayout(mainFrame)

    self:UpdateTabCountBadges()
    _wnProfSliceStop(ns.Profiler.CAT.UI, "Pop_postLayout")

    -- Dev-only: one-line main tab switch timing (~2 frames after populate for settle).
    if pendingPerfGen and IsTabPerfMonitorEnabled() then
        local perf = mainFrame._wnPerfMainTabSwitch
        local ok = perf and perf.gen == pendingPerfGen and perf.msClickToPoolEnd and perf.gen == mainFrame._tabSwitchGen
            and mainFrame.currentTab == perf.toTab
        if ok then
            local msPopulate = debugprofilestop()
            local P = ns.Profiler
            if P and P.ScheduleTabSwitchPerfTrace then
                P:ScheduleTabSwitchPerfTrace({
                    fromTab = perf.fromTab,
                    toTab = perf.toTab,
                    poolMs = perf.msClickToPoolEnd,
                    populateMs = msPopulate,
                    wallStart = perf.wallStart,
                    gen = perf.gen,
                })
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

    MarkShellPopulateCompleted(mainFrame)

    -- Dev-only: unusually long PopulateContent (true infinite loops cannot be broken from Lua; this flags pathological hangs).
    if IsDebugModeEnabled and IsDebugModeEnabled() and populateWallStart then
        local wallMs = (GetTime() - populateWallStart) * 1000
        if wallMs > 400 then
            local Pslow = ns.Profiler
            if Pslow and Pslow.AppendTraceAnomaly then
                Pslow:AppendTraceAnomaly(format(
                    "[Trace] PopulateContent slow %.0fms tab=%s",
                    wallMs,
                    tostring(mainFrame.currentTab)))
            end
        end
    end
end

function WarbandNexus:PopulateContent(forceRepaint)
    local P = ns.Profiler
    if P and P.enabled then
        local lab = P.SliceLabel and P:SliceLabel(P.CAT.UI, "PopulateContent")
        if lab then
            return P:Wrap(lab, PopulateContentBody, self, forceRepaint)
        end
    end
    return PopulateContentBody(self, forceRepaint)
end

ns.UIShell.PopulateContentBody = PopulateContentBody
