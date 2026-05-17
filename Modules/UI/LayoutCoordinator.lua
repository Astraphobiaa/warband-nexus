--[[
    Warband Nexus - Main window layout coordinator
    Central resize/reposition pipeline for WarbandNexusFrame and tab adapters.

    Responsive contract (main window):
    - Viewport width: `scroll:GetWidth()` via `GetScrollContentWidth` / `UI_GetMainTabViewportWidth`.
      Use for live drag relayout (gold cards, row paint width, explicit SetWidth).
    - Scroll child width: `ComputeScrollChildWidth` (tab minimums). Frozen in `_wnResizeFreezeScrollChildW`
      during corner-drag so column rails do not jitter; horizontal scroll when viewport < min.
    - `resize_live`: shell/nav rail only; Characters tab content frozen until commit (`PopulateContent`).
    - `resize_commit`: unfreeze scroll child, `OnViewportLayoutCommit` or full PopulateContent.
    - Tab painters: prefer `UI_GetMainTabLayoutMetrics` (`contentWidth`, `bodyWidth`, `sideMargin`);
      avoid `scrollChild:GetWidth()` for live sizing while a resize session is active.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local LayoutCoordinator = {}
ns.UI_LayoutCoordinator = LayoutCoordinator

local function GetLayoutScrollTokens()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SCROLL
    return ms or {}
end

local function GetResizeTokens()
    local ms = GetLayoutScrollTokens()
    return {
        commitDebounce = ms.RESIZE_COMMIT_DEBOUNCE_SEC or 0.15,
        liveMinDelta = ms.LIVE_RELAYOUT_MIN_SIZE_DELTA_PX or 2,
        collectionsLiveDebounce = ms.COLLECTIONS_LIVE_RELAYOUT_DEBOUNCE_SEC or 0.12,
        itemsLiveDebounce = ms.ITEMS_LIVE_RELAYOUT_DEBOUNCE_SEC or 0.12,
    }
end

LayoutCoordinator._shell = {}
LayoutCoordinator._tabAdapters = {}
LayoutCoordinator._scrollChildHooks = {}
LayoutCoordinator._satelliteFrames = {}

local liveDebounceTimers = {}
local commitDebounceTimer = nil
local commitDebounceGen = 0
local lastLiveW, lastLiveH = 0, 0

--- True while corner-drag resizing or until debounced resize commit finishes (ElvUI-style: no tab redraw mid-drag).
local function IsMainFrameResizeSession(frame)
    return frame and (frame._resizeActive or frame._resizeCommitPending)
end

function ns.UI_IsMainFrameResizing(frame)
    return IsMainFrameResizeSession(frame)
end

local function CancelTimer(handle)
    if handle and handle.Cancel then
        handle:Cancel()
    end
end

local function ProfilerSlice(name, fn)
    local P = ns.Profiler
    local cat = (P and P.CAT and P.CAT.UI) or "UI"
    if P and P.enabled and P.Wrap and P.SliceLabel then
        local lab = P:SliceLabel(cat, name)
        return P:Wrap(lab, fn)
    end
    return fn()
end

function LayoutCoordinator:RegisterShellCallbacks(callbacks)
    if not callbacks then return end
    local sh = self._shell
    for k, v in pairs(callbacks) do
        sh[k] = v
    end
end

---@param tabId string
---@param adapter table|nil { OnViewportWidthChanged = fn(scrollChild, contentWidth, frame) -> handled?, OnViewportLayoutCommit = fn(...) -> handled? }
function LayoutCoordinator:RegisterTabAdapter(tabId, adapter)
    if not tabId then return end
    self._tabAdapters[tabId] = adapter
end

function LayoutCoordinator:GetTabAdapter(tabId)
    return tabId and self._tabAdapters[tabId]
end

function LayoutCoordinator:RegisterScrollChildRelayout(scrollChild, fn)
    if not scrollChild or not fn then return end
    self._scrollChildHooks[scrollChild] = fn
end

function LayoutCoordinator:UnregisterScrollChildRelayout(scrollChild)
    if scrollChild then
        self._scrollChildHooks[scrollChild] = nil
    end
end

--- Satellite / external windows (Faz 5): lightweight live width sync.
---@param frame Frame
---@param config table|nil { onLive = fn(frame,w,h), onCommit = fn(frame,w,h) }
function LayoutCoordinator:RegisterSatelliteFrame(frame, config)
    if not frame then return end
    self._satelliteFrames[frame] = config or {}
    if frame._wnSatelliteLayoutHooked then return end
    frame._wnSatelliteLayoutHooked = true
    frame:SetScript("OnSizeChanged", function(self, w, h)
        LayoutCoordinator:OnSatelliteMetricsChanged(self, w, h, false)
    end)
end

function LayoutCoordinator:OnSatelliteMetricsChanged(frame, w, h, isCommit)
    local cfg = self._satelliteFrames[frame]
    if not cfg then return end
    if isCommit and cfg.onCommit then
        cfg.onCommit(frame, w, h)
    elseif cfg.onLive then
        cfg.onLive(frame, w, h)
    end
end

function LayoutCoordinator:GetScrollContentWidth(frame)
    local sh = self._shell
    if sh.computeScrollContentWidth then
        return sh.computeScrollContentWidth(frame) or 0
    end
    if frame and frame.scroll then
        return frame.scroll:GetWidth() or 0
    end
    return 0
end

function LayoutCoordinator:RelayoutResultsContainer(resultsContainer, scrollParent, sideMargin, bottomInset)
    if not resultsContainer or not scrollParent then return end
    if WarbandNexus and WarbandNexus.SyncStorageResultsLayoutFromTail then
        WarbandNexus:SyncStorageResultsLayoutFromTail(resultsContainer)
    end
    if ns.UI_AnnexResultsToScrollBottom then
        ns.UI_AnnexResultsToScrollBottom(resultsContainer, scrollParent, sideMargin or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12, bottomInset or 8)
    end
end

--- During drag: resize outer shell + nav rail only. Do NOT change scrollChild width (row/right-column jitter).
local function ApplyShellChromeLive(frame)
    local sh = LayoutCoordinator._shell
    if not frame then return end
    if sh.applyGoldenRailLayout then
        sh.applyGoldenRailLayout(frame)
    end
    if IsMainFrameResizeSession(frame) then
        return
    end
    if sh.updateScrollLayout then
        sh.updateScrollLayout(frame)
    end
    if frame.scroll and ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(frame.scroll)
    end
end

local function ApplyShellChromeFull(frame, _reason)
    local sh = LayoutCoordinator._shell
    if not frame then return end

    if sh.applyGoldenRailLayout then
        sh.applyGoldenRailLayout(frame)
    end
    if sh.refreshFixedHeaderChrome then
        sh.refreshFixedHeaderChrome(frame)
    end

    if frame._wnMainShellBackdrop then
        if ns.UI_HideFrameBorderQuartet then
            ns.UI_HideFrameBorderQuartet(frame)
        end
    elseif frame.BorderTop and ns.GetPixelScale then
        local pixelScale = ns.GetPixelScale(frame) or 1
        frame.BorderTop:SetHeight(pixelScale)
        frame.BorderBottom:SetHeight(pixelScale)
        frame.BorderLeft:SetWidth(pixelScale)
        frame.BorderRight:SetWidth(pixelScale)
    end

    if sh.updateScrollLayout then
        sh.updateScrollLayout(frame)
    end
    if sh.refreshNavTabStrip then
        sh.refreshNavTabStrip(frame)
    end
    if frame.currentTab and sh.scrollNavEnsureTabVisible then
        sh.scrollNavEnsureTabVisible(frame, frame.currentTab)
    end
    if frame.scroll and ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(frame.scroll)
    end
end

local function RunTabLiveAdapter(frame, contentWidth)
    if not frame or not frame.scrollChild then return end
    -- Characters: no gold/rows/VLM relayout while corner-drag (commit -> PopulateContent).
    if frame.currentTab == "chars" and IsMainFrameResizeSession(frame) then
        return
    end
    local tab = frame.currentTab
    local adapter = LayoutCoordinator:GetTabAdapter(tab)
    if adapter and adapter.OnViewportWidthChanged then
        local handled = adapter.OnViewportWidthChanged(frame.scrollChild, contentWidth, frame)
        if handled then return end
    end
    local hook = LayoutCoordinator._scrollChildHooks[frame.scrollChild]
    if hook then
        hook(frame.scrollChild, contentWidth, frame)
    end
end

local function RunTabCommitAdapter(frame, contentWidth)
    if not frame or not frame.scrollChild then return false end
    local tab = frame.currentTab
    local adapter = LayoutCoordinator:GetTabAdapter(tab)
    if adapter and adapter.OnViewportLayoutCommit then
        return adapter.OnViewportLayoutCommit(frame.scrollChild, contentWidth, frame) == true
    end
    return false
end

local function ScheduleCommitPopulate(frame)
    local sh = LayoutCoordinator._shell
    if not frame or not frame:IsShown() then return end
    if sh.scheduleGeometryCommit then
        sh.scheduleGeometryCommit(true)
        return
    end
    if sh.schedulePopulateContent then
        sh.schedulePopulateContent(true)
        return
    end
    if WarbandNexus and WarbandNexus.PopulateContent then
        WarbandNexus:PopulateContent()
    end
end

function LayoutCoordinator:CancelAllTabLiveRelayoutTimers()
    for key, handle in pairs(liveDebounceTimers) do
        CancelTimer(handle)
        liveDebounceTimers[key] = nil
    end
end

function LayoutCoordinator:ResetLiveMetricsTracking()
    lastLiveW, lastLiveH = 0, 0
end

--- Bypass live resize delta gate (corner drag release, first paint after Show).
function LayoutCoordinator:ForceMainFrameMetrics(frame, reason)
    if not frame then return end
    self:ResetLiveMetricsTracking()
    self:OnMainFrameMetricsChanged(frame, reason or "resize_live")
end

function LayoutCoordinator:OnMainFrameMetricsChanged(frame, reason)
    if not frame then return end
    reason = reason or "resize_live"
    local tokens = GetResizeTokens()
    local skipLiveDelta = (reason == "resize_commit" or reason == "display_changed" or reason == "ui_scale_addon")

    if not skipLiveDelta and (reason == "resize_live" or reason == "drag_stop") then
        local w = frame:GetWidth() or 0
        local h = frame:GetHeight() or 0
        local dw = w - lastLiveW
        local dh = h - lastLiveH
        if lastLiveW > 0 and lastLiveH > 0
            and dw < tokens.liveMinDelta and dw > -tokens.liveMinDelta
            and dh < tokens.liveMinDelta and dh > -tokens.liveMinDelta then
            return
        end
        lastLiveW, lastLiveH = w, h
    elseif skipLiveDelta then
        lastLiveW = frame:GetWidth() or 0
        lastLiveH = frame:GetHeight() or 0
    end

    ProfilerSlice("Lay_" .. reason, function()
        if reason == "resize_commit" or reason == "display_changed" or reason == "ui_scale_addon" then
            if ns.ResetPixelScale then
                ns.ResetPixelScale()
            end
        end

        local contentWidth = LayoutCoordinator:GetScrollContentWidth(frame)
        if contentWidth < 1 and (reason == "resize_live" or reason == "drag_stop" or reason == "resize_commit") then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if frame and frame:IsShown() then
                        LayoutCoordinator:ForceMainFrameMetrics(frame, reason)
                    end
                end)
            end
            if reason ~= "resize_commit" and reason ~= "display_changed" and reason ~= "ui_scale_addon" then
                return
            end
            contentWidth = LayoutCoordinator:GetScrollContentWidth(frame)
            if contentWidth < 1 then
                return
            end
        end

        if reason == "resize_live" or reason == "drag_stop" then
            if IsMainFrameResizeSession(frame) then
                ApplyShellChromeLive(frame)
                RunTabLiveAdapter(frame, contentWidth)
            else
                ApplyShellChromeFull(frame, reason)
                RunTabLiveAdapter(frame, contentWidth)
            end
            return
        end

        if reason == "resize_commit" or reason == "display_changed" or reason == "ui_scale_addon" then
            frame._resizeCommitPending = nil
            frame._wnResizeFreezeScrollChildW = nil
            ApplyShellChromeFull(frame, reason)
            local handled = RunTabCommitAdapter(frame, contentWidth)
            if not handled then
                ScheduleCommitPopulate(frame)
            end
            local sh = LayoutCoordinator._shell
            if frame._wnDeferredPopulateAfterResize and sh.schedulePopulateContent then
                frame._wnDeferredPopulateAfterResize = nil
                sh.schedulePopulateContent(true)
            end
        end
    end)
end

function LayoutCoordinator:OnMainFrameResizeLive(frame, width, height)
    local PixelSnap = ns.PixelSnap
    if PixelSnap and width and height then
        width = PixelSnap(width)
        height = PixelSnap(height)
        if frame and frame.GetWidth then
            -- size already applied by WoW; snap tracking only
        end
    end
    self:OnMainFrameMetricsChanged(frame, "resize_live")
end

function LayoutCoordinator:OnMainFrameResizeCommit(frame)
    self:ResetLiveMetricsTracking()
    self:CancelAllTabLiveRelayoutTimers()
    self:OnMainFrameMetricsChanged(frame, "resize_commit")
end

function LayoutCoordinator:OnMainFrameDragStop(frame)
    self:OnMainFrameMetricsChanged(frame, "drag_stop")
end

function LayoutCoordinator:OnDisplayMetricsChanged(frame)
    if not frame then
        frame = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    end
    if not frame then return end
    local sh = self._shell
    if sh.clampResizeBounds then
        sh.clampResizeBounds()
    elseif WarbandNexus and WarbandNexus.UI_ClampMainFrameResizeBoundsFromProfile then
        WarbandNexus:UI_ClampMainFrameResizeBoundsFromProfile()
    end
    if frame:IsShown() then
        self:OnMainFrameMetricsChanged(frame, "display_changed")
    end
end

function LayoutCoordinator:OnAddonUIScaleChanged(frame)
    if not frame then return end
    self:OnMainFrameMetricsChanged(frame, "ui_scale_addon")
end

function LayoutCoordinator:HookMainFrameResizeCommitOnMouseUp(frame, resizeBtn, onCommitExtra)
    if not frame or not resizeBtn then return end
    local tokens = GetResizeTokens()
    resizeBtn:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        CancelTimer(commitDebounceTimer)
        commitDebounceGen = commitDebounceGen + 1
        local myGen = commitDebounceGen
        if C_Timer and C_Timer.NewTimer then
            commitDebounceTimer = C_Timer.NewTimer(tokens.commitDebounce, function()
                if myGen ~= commitDebounceGen then return end
                commitDebounceTimer = nil
                if onCommitExtra then onCommitExtra() end
                LayoutCoordinator:OnMainFrameResizeCommit(frame)
            end)
        else
            if onCommitExtra then onCommitExtra() end
            LayoutCoordinator:OnMainFrameResizeCommit(frame)
        end
    end)
end

function LayoutCoordinator:ScheduleTabLiveRelayout(key, delaySec, fn)
    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if IsMainFrameResizeSession(mf) then
        return
    end
    CancelTimer(liveDebounceTimers[key])
    if not fn then return end
    if C_Timer and C_Timer.NewTimer then
        liveDebounceTimers[key] = C_Timer.NewTimer(delaySec, function()
            liveDebounceTimers[key] = nil
            fn()
        end)
    else
        fn()
    end
end

function ns.UI_RelayoutResultsContainer(resultsContainer, scrollParent, sideMargin, bottomInset)
    LayoutCoordinator:RelayoutResultsContainer(resultsContainer, scrollParent, sideMargin, bottomInset)
end
