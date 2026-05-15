--[[============================================================================
    PROFILER - Development-only performance measurement system
    
    Measures execution time of operations, detects frame spikes, and provides
    a detailed performance summary via slash commands.
    
    NOTE: This module is for LOCAL DEVELOPMENT ONLY. Do not ship to end users.
    The module is completely inert when disabled (near-zero overhead).
    
    Usage:
        local P = ns.Profiler
        
        -- Method 1: Start/Stop
        P:Start("FetchAllFactions")
        doWork()
        P:Stop("FetchAllFactions")
        
        -- Method 2: Wrap (returns function results)
        local result = P:Wrap("BuildSnapshot", function()
            return doExpensiveWork()
        end)
        
        -- Method 3: WrapAsync (for time-budgeted operations spanning frames)
        P:StartAsync("CollectionCache")
        -- ... across multiple frames ...
        P:StopAsync("CollectionCache")
        
        CollectionService async labels (when profiling):
        EnsureBlizzard_CollectionsLoad, BuildFullCollectionData [async], EnsureCollectionData [async],
        BuildCollectionCache [async], BuildCollectionCache_quiet [async]
    
    Slash commands:
        /wn profiler          - Show performance summary
        /wn profiler on       - Enable profiling (persisted across /reload)
        /wn profiler off      - Disable profiling
        /wn profiler reset    - Clear all recorded data
        /wn profiler frames   - Toggle frame spike detection
        /wn profiler spikes   - Show recent frame spikes
        /wn profiler live     - Toggle live output (print each Start/Stop)
        /wn profiler dev      - Toggle profiler dev mode (dev HUD + dock/position persistence)
        /wn profiler window   - Toggle dev summary window (requires dev mode)
        /wn profiler trace    - Toggle WN_TRACE copy buffer (requires measuring ON)
        /wn profiler dock     - Toggle dock-left layout for dev window
        /wn profiler gearonly on|off - Record only Gear-related slices (UI/Pop_* only on Gear tab populate)
        /wn profiler events on|off [minMs] - Log slow event handlers to WN_TRACE (WN_TRACE_EVT; needs measuring ON)
============================================================================]]

local ADDON_NAME, ns = ...
local tinsert = table.insert
local tremove = table.remove
local issecretvalue = issecretvalue

-- ============================================================================
-- MODULE DEFINITION
-- ============================================================================

local Profiler = {
    enabled = false,
    liveOutput = false,
    frameTracking = false,
    devMode = false,
    entries = {},       -- { [label] = { calls, totalMs, minMs, maxMs, lastMs } }
    activeTimers = {},  -- { [label] = startTimestamp }
    asyncTimers = {},   -- { [label] = { startTime, frameCount } }
    frameSpikes = {},   -- ring buffer of recent spikes { timestamp, frameMs }
    _spikeNextSlot = 1, -- 1..maxSpikes; next write overwrites oldest when full
    _spikeCount = 0,    -- 0..maxSpikes
    maxSpikes = 50,     -- max spikes to keep
    spikeThreshold = 33.33, -- ms (below 30fps)
    _frameStart = 0,
    _frameHandler = nil,
    _devWindow = nil,
    _devWindowScroll = nil,
    _suppressFrameTrackingPrint = false,
    _traceLines = {},
    --- When true, Start/Stop/Wrap/_Record only labels focused on Gear diagnostics (see IsGearFocusedSliceLabel).
    gearOnlyRecording = false,
    --- Log slow Blizzard-facing handlers to WN_TRACE (requires measuring ON); see TraceEventHandler.
    eventTrace = false,
    --- Minimum handler CPU time (debugprofilestop) to emit a WN_TRACE_EVT line.
    eventTraceMinMs = 12,
    --- Last tab passed to PopulateContentBody (used with gearOnlyRecording for UI/Pop_* slices).
    _populateContentTab = nil,
}

ns.Profiler = Profiler

--- Named buckets for slice labels (prefix "Cat/name" in summary).
Profiler.CAT = {
    UI = "UI",
    INIT = "Init",
    SVC = "Svc",
    MSG = "Msg",
    DB = "DB",
}

function ns.IsProfilerDevMode()
    return Profiler.devMode == true
end

---@param category string One of Profiler.CAT.*
---@param name string Short slice name
---@return string
function Profiler:SliceLabel(category, name)
    return tostring(category or "?") .. "/" .. tostring(name or "?")
end

--- Gear-only mode: allow recording for this label (plain substring checks; no patterns on API text).
---@param label string
---@return boolean
function Profiler:IsGearFocusedSliceLabel(label)
    if not label then return false end
    -- Event-trace aggregates (Msg/evt_*) remain visible when gear-only noise filtering is on.
    if string.find(label, "/evt_", 1, true) then return true end
    if string.find(label, "Gear", 1, true) then return true end
    if string.find(label, "gear", 1, true) then return true end
    if self._populateContentTab == "gear" and string.sub(label, 1, 7) == "UI/Pop_" then return true end
    return false
end

---@param category string
---@param name string
function Profiler:StartSlice(category, name)
    self:Start(self:SliceLabel(category, name))
end

---@param category string
---@param name string
function Profiler:StopSlice(category, name)
    self:Stop(self:SliceLabel(category, name))
end

local function GetProfilePersistRoot()
    local db = ns.db or (_G.WarbandNexus and _G.WarbandNexus.db)
    if not db or not db.profile then return nil end
    db.profile.profilerPersist = db.profile.profilerPersist or {}
    return db.profile.profilerPersist
end

function Profiler:SavePersistToProfile()
    local p = GetProfilePersistRoot()
    if not p then return end
    p.measuring = self.enabled and true or false
    p.liveOutput = self.liveOutput and true or false
    p.frameTracking = self.frameTracking and true or false
    p.devMode = self.devMode and true or false
    p.gearOnlyRecording = self.gearOnlyRecording and true or false
    p.eventTrace = self.eventTrace and true or false
    p.eventTraceMinMs = tonumber(self.eventTraceMinMs) or 12
    local w = self._devWindow
    if w then
        p.devWindowVisible = w:IsShown() and true or false
        local pt, _, rel, x, y = w:GetPoint(1)
        p.point = pt or p.point or "CENTER"
        p.relPoint = rel or p.relPoint or "CENTER"
        p.x = x or 0
        p.y = y or 0
        p.width = w:GetWidth() or p.width
        p.height = w:GetHeight() or p.height
        p.docked = self._devDocked and true or false
    end
end

--- Read AceDB profile and apply in-memory profiler flags (call after db exists).
---@param profile table db.profile
function Profiler:ApplyPersistedSettings(profile)
    if not profile then return end
    local p = profile.profilerPersist
    if not p then return end
    self.enabled = p.measuring == true
    self.liveOutput = p.liveOutput == true
    self.frameTracking = p.frameTracking == true
    self.devMode = p.devMode == true
    self.gearOnlyRecording = p.gearOnlyRecording == true
    self.eventTrace = p.eventTrace == true
    self.eventTraceMinMs = tonumber(p.eventTraceMinMs) or 12
    if self.frameTracking then
        self._suppressFrameTrackingPrint = true
        self:SetFrameTracking(true)
        self._suppressFrameTrackingPrint = false
    else
        self._suppressFrameTrackingPrint = true
        self:SetFrameTracking(false)
        self._suppressFrameTrackingPrint = false
    end
end

--- Re-show dev HUD after OnEnable (frame objects do not survive /reload).
function Profiler:RestoreUIAfterAddonEnable()
    if not self.devMode then return end
    local root = GetProfilePersistRoot()
    if not root or not root.devWindowVisible then return end
    self:EnsureDevWindow()
    if self._devWindow then
        self:ApplyDevWindowLayoutFromPersist()
        self._devWindow:Show()
        self:RefreshDevWindowContent()
    end
end

local function ProfilerPrint(...)
    local addon = ns and ns.WarbandNexus
    if addon and addon.Print then
        addon:Print(...)
    elseif _G and _G.print then
        _G.print(...)
    end
end

ns.ProfilerPrint = ProfilerPrint
local print = ProfilerPrint

-- ============================================================================
-- COLOR CONSTANTS
-- ============================================================================

local C_HEADER  = "|cff00ccff"  -- cyan
local C_LABEL   = "|cffffd700"  -- gold
local C_VALUE   = "|cffffffff"  -- white
local C_GOOD    = "|cff00ff00"  -- green
local C_WARN    = "|cffffff00"  -- yellow
local C_BAD     = "|cffff4444"  -- red
local C_DIM     = "|cff808080"  -- gray
local C_ACCENT  = "|cff9370DB"  -- purple (matches addon theme)
local C_R       = "|r"

local PREFIX = C_ACCENT .. "[WN Profiler]" .. C_R .. " "

local TRACE_LOG_MAX = 2000
local TRACE_EDIT_BODY_HEIGHT = 12000

function Profiler:_AppendPerfTraceLine(plainLine)
    if not self.enabled or not plainLine then return end
    if not self._traceLines then
        self._traceLines = {}
    end
    tinsert(self._traceLines, plainLine)
    while #self._traceLines > TRACE_LOG_MAX do
        tremove(self._traceLines, 1)
    end
    if self._traceWindow and self._traceWindow:IsShown() then
        self:_ScheduleTraceEditSync()
    end
end

function Profiler:_ScheduleTraceEditSync()
    if self._traceSyncPending then return end
    self._traceSyncPending = true
    C_Timer.After(0, function()
        self._traceSyncPending = false
        if self._traceWindow and self._traceWindow:IsShown() then
            self:_SyncTraceEditBoxText()
        end
    end)
end

function Profiler:_SyncTraceEditBoxText()
    if self._traceLayoutSyncing then return end
    self._traceLayoutSyncing = true
    local ok, err = pcall(function()
        local eb = self._traceEdit
        local scroll = self._traceScroll
        if not eb or not scroll then return end
        if not self._traceLines then
            self._traceLines = {}
        end
        local lines = self._traceLines
        local text
        if #lines > 0 then
            text = table.concat(lines, "\n")
        else
            text = "(No WN_TRACE lines yet. With measuring ON, switch tabs or open Gear; lines fill here and in chat when this window is closed.)"
        end
        eb:SetText(text)
        local sw = scroll:GetWidth()
        if sw < 60 then sw = 520 end
        local tw = sw - 16
        eb:SetWidth(tw)
        eb:SetHeight(TRACE_EDIT_BODY_HEIGHT)
        if scroll.UpdateScrollChildRect then
            scroll:UpdateScrollChildRect()
        end
        if scroll.GetVerticalScrollRange and scroll.SetVerticalScroll then
            local maxRange = scroll:GetVerticalScrollRange()
            if maxRange and maxRange > 0 then
                scroll:SetVerticalScroll(maxRange)
            else
                scroll:SetVerticalScroll(0)
            end
        end
    end)
    self._traceLayoutSyncing = false
    if not ok then
        print(PREFIX .. C_BAD .. "Trace UI sync failed: " .. tostring(err) .. C_R)
    end
end

function Profiler:EnsureTraceWindow()
    if self._traceWindow then return end
    local f = CreateFrame("Frame", "WarbandNexusProfilerTraceFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(8100)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.93)
    f:SetBackdropBorderColor(0.45, 0.2, 0.65, 1)
    f:SetSize(560, 400)
    f:SetPoint("CENTER", UIParent, "CENTER", 320, -40)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff9370DBWN Perf trace|r")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", 0, -30)
    hint:SetText("|cff808080Plain |cff00ccffWN_TRACE|cff808080 lines while measuring is ON. Select all, then Ctrl+C.|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)

    local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    copyBtn:SetSize(100, 22)
    copyBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -90, -2)
    copyBtn:SetText("Select all")
    copyBtn:SetScript("OnClick", function()
        local eb = Profiler._traceEdit
        if not eb then return end
        eb:SetFocus()
        eb:HighlightText(0, eb:GetNumLetters())
        print(PREFIX .. C_DIM .. "Trace text selected; use Ctrl+C to copy." .. C_R)
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("TOPRIGHT", copyBtn, "TOPLEFT", -6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        wipe(Profiler._traceLines)
        Profiler:_SyncTraceEditBoxText()
    end)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -58)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)

    -- EditBox must be the ScrollFrame's scroll child (AceGUI MultiLineEditBox pattern).
    -- A wrapper Frame as scroll child breaks text rendering on some Midnight builds.
    local eb = CreateFrame("EditBox", "WarbandNexusProfilerTraceEdit", scroll)
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(0.92, 0.92, 0.95)
    eb:EnableMouse(true)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(0)
    eb:SetCountInvisibleLetters(false)
    eb:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, 0)
    eb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -6, 0)
    eb:SetHeight(TRACE_EDIT_BODY_HEIGHT)
    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    scroll:SetScrollChild(eb)

    self._traceWindow = f
    self._traceScroll = scroll
    self._traceEdit = eb

    f:SetScript("OnShow", function()
        Profiler:_SyncTraceEditBoxText()
        C_Timer.After(0, function()
            if Profiler._traceWindow and Profiler._traceWindow:IsShown() then
                Profiler:_SyncTraceEditBoxText()
            end
        end)
    end)
    -- New frames can start "shown" for IsShown(); first slash toggle must open, not hide.
    f:Hide()
end

function Profiler:ToggleTraceWindow()
    if not self.enabled then
        print(PREFIX .. C_WARN .. "Enable measuring first: |cff00ccff/wn profiler on|r" .. C_R)
        return
    end
    self:EnsureTraceWindow()
    local w = self._traceWindow
    if not w then return end
    if w:IsShown() then
        w:Hide()
        print(PREFIX .. "Trace log window hidden." .. C_R)
    else
        w:Show()
        self:_SyncTraceEditBoxText()
        C_Timer.After(0, function()
            if Profiler._traceWindow and Profiler._traceWindow:IsShown() then
                Profiler:_SyncTraceEditBoxText()
            end
        end)
        print(PREFIX .. C_GOOD .. "Trace log window shown (plain text)." .. C_R)
    end
end

--[[ Dev-only HUD: explicit CreateFrame (not SharedWidgets factory) — acceptable for
     local diagnostics only; never shown unless /wn profiler dev + window. ]]
function Profiler:ApplyDevWindowLayoutFromPersist()
    local w = self._devWindow
    local p = GetProfilePersistRoot()
    if not w or not p then return end
    w:ClearAllPoints()
    local width = tonumber(p.width) or 400
    local height = tonumber(p.height) or 260
    if width < 280 then width = 280 end
    if height < 160 then height = 160 end
    w:SetSize(width, height)
    if p.docked then
        self._devDocked = true
        w:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 6, -24)
    else
        self._devDocked = false
        w:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", tonumber(p.x) or 0, tonumber(p.y) or 0)
    end
end

function Profiler:RefreshDevWindowContent()
    local scroll = self._devWindowScroll
    if not scroll then return end
    local lines = {}
    lines[#lines + 1] = "|cff9370DBWarband Nexus Profiler|r (dev HUD)"
    lines[#lines + 1] = string.format(
        "measuring=%s  live=%s  frames=%s  devMode=%s  gearOnly=%s",
        tostring(self.enabled),
        tostring(self.liveOutput),
        tostring(self.frameTracking),
        tostring(self.devMode),
        tostring(self.gearOnlyRecording)
    )
    lines[#lines + 1] = " "
    if not next(self.entries) then
        lines[#lines + 1] = "(no slices yet — enable with |cff00ccff/wn profiler on|r)"
    else
        local sorted = {}
        for label, data in pairs(self.entries) do
            sorted[#sorted + 1] = { label = label, data = data }
        end
        table.sort(sorted, function(a, b)
            return a.data.totalMs > b.data.totalMs
        end)
        local n = math.min(18, #sorted)
        for i = 1, n do
            local e = sorted[i]
            local d = e.data
            local avg = d.calls > 0 and (d.totalMs / d.calls) or 0
            lines[#lines + 1] = string.format(
                "%-28s  n=%d  avg=%.1fms  max=%.1fms  tot=%.0fms",
                #e.label > 28 and (e.label:sub(1, 25) .. "...") or e.label,
                d.calls,
                avg,
                d.maxMs,
                d.totalMs
            )
        end
    end
    scroll:SetText(table.concat(lines, "\n"))
end

function Profiler:EnsureDevWindow()
    if self._devWindow then return end
    local f = CreateFrame("Frame", "WarbandNexusProfilerDevFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(8000)
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.06, 0.92)
    f:SetBackdropBorderColor(0.45, 0.2, 0.65, 1)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Profiler._devDocked = false
        local p = GetProfilePersistRoot()
        if p then p.docked = false end
        Profiler:SavePersistToProfile()
    end)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cff9370DBWN Profiler|r")
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
        local p = GetProfilePersistRoot()
        if p then p.devWindowVisible = false end
        Profiler:SavePersistToProfile()
    end)
    local dockBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    dockBtn:SetSize(90, 22)
    dockBtn:SetPoint("TOPLEFT", 10, -10)
    dockBtn:SetText("Dock L")
    dockBtn:SetScript("OnClick", function()
        Profiler._devDocked = not Profiler._devDocked
        local p = GetProfilePersistRoot()
        if p then p.docked = Profiler._devDocked and true or false end
        Profiler:ApplyDevWindowLayoutFromPersist()
        Profiler:SavePersistToProfile()
    end)
    local refreshBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -6, -2)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        Profiler:RefreshDevWindowContent()
    end)
    local traceBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    traceBtn:SetSize(88, 22)
    traceBtn:SetPoint("TOPRIGHT", refreshBtn, "TOPLEFT", -6, 0)
    traceBtn:SetText("Trace log")
    traceBtn:SetScript("OnClick", function()
        if not Profiler.enabled then
            print(PREFIX .. C_WARN .. "Turn measuring on: |cff00ccff/wn profiler on|r" .. C_R)
            return
        end
        Profiler:EnsureTraceWindow()
        local tw = Profiler._traceWindow
        if not tw then return end
        if tw:IsShown() then
            tw:Hide()
        else
            tw:Show()
            Profiler:_SyncTraceEditBoxText()
        end
    end)
    local scroll = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 10)
    scroll:SetJustifyH("LEFT")
    scroll:SetJustifyV("TOP")
    scroll:SetNonSpaceWrap(false)
    f:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        self._wnProfHudT = (self._wnProfHudT or 0) + elapsed
        if self._wnProfHudT < 1.5 then return end
        self._wnProfHudT = 0
        Profiler:RefreshDevWindowContent()
    end)
    self._devWindow = f
    self._devWindowScroll = scroll
end

-- ============================================================================
-- CORE TIMING API
-- ============================================================================

---Start timing a named operation.
---@param label string Unique operation name
function Profiler:Start(label)
    if not self.enabled then return end
    if self.gearOnlyRecording and not self:IsGearFocusedSliceLabel(label) then return end
    self.activeTimers[label] = debugprofilestop()
    if self.liveOutput then
        print(PREFIX .. C_DIM .. "START " .. C_LABEL .. label .. C_R)
    end
end

---Stop timing a named operation and record the result.
---@param label string Must match a previous Start() call
---@return number|nil elapsedMs Elapsed milliseconds, or nil if not enabled/not started
function Profiler:Stop(label)
    if not self.enabled then return nil end
    if self.gearOnlyRecording and not self:IsGearFocusedSliceLabel(label) then return nil end

    local startTime = self.activeTimers[label]
    if not startTime then return nil end
    self.activeTimers[label] = nil
    
    local elapsed = debugprofilestop() - startTime
    self:_Record(label, elapsed)
    
    if self.liveOutput then
        local color = elapsed > 16.67 and C_BAD or elapsed > 5 and C_WARN or C_GOOD
        print(PREFIX .. C_DIM .. "STOP  " .. C_LABEL .. label .. C_R
            .. "  " .. color .. string.format("%.2fms", elapsed) .. C_R)
    end
    
    return elapsed
end

---Wrap a synchronous function call with profiling.
---@param label string Operation name
---@param func function Function to profile
---@param ... any Arguments to pass to func
---@return any ... All return values from func
function Profiler:Wrap(label, func, ...)
    if not self.enabled then return func(...) end
    if self.gearOnlyRecording and not self:IsGearFocusedSliceLabel(label) then return func(...) end

    self:Start(label)
    -- Pack results to handle multiple return values + nils
    local results = {pcall(func, ...)}
    local elapsed = self:Stop(label)
    
    local ok = table.remove(results, 1)
    if not ok then
        local err = results[1]
        print(PREFIX .. C_BAD .. "ERROR in " .. label .. ": " .. tostring(err) .. C_R)
        error(err, 2)
    end
    
    return unpack(results)
end

---Start timing an async/multi-frame operation.
---@param label string Operation name
function Profiler:StartAsync(label)
    if not self.enabled then return end
    if self.gearOnlyRecording and not self:IsGearFocusedSliceLabel(label) then return end
    self.asyncTimers[label] = {
        startTime = debugprofilestop(),
        frameCount = 0,
        startFrame = GetTime(),
    }
    if self.liveOutput then
        print(PREFIX .. C_DIM .. "ASYNC START " .. C_LABEL .. label .. C_R)
    end
end

---Stop timing an async/multi-frame operation.
---@param label string Must match a previous StartAsync() call
---@return number|nil elapsedMs Wall-clock milliseconds
function Profiler:StopAsync(label)
    if not self.enabled then return nil end
    if self.gearOnlyRecording and not self:IsGearFocusedSliceLabel(label) then return nil end

    local entry = self.asyncTimers[label]
    if not entry then return nil end
    self.asyncTimers[label] = nil
    
    local elapsed = debugprofilestop() - entry.startTime
    local wallSeconds = GetTime() - entry.startFrame
    
    -- Record under a distinct async label
    local asyncLabel = label .. " [async]"
    self:_Record(asyncLabel, elapsed)
    
    -- Store wall-clock separately for display
    local e = self.entries[asyncLabel]
    if e then
        e.lastWallSec = wallSeconds
    end
    
    if self.liveOutput then
        local color = elapsed > 50 and C_BAD or elapsed > 20 and C_WARN or C_GOOD
        print(PREFIX .. C_DIM .. "ASYNC STOP  " .. C_LABEL .. label .. C_R
            .. "  CPU: " .. color .. string.format("%.2fms", elapsed) .. C_R
            .. "  Wall: " .. C_VALUE .. string.format("%.1fs", wallSeconds) .. C_R)
    end
    
    return elapsed
end

-- ============================================================================
-- BLIZZARD EVENT / HANDLER TRACE (dev-only; WN_TRACE buffer)
-- Community payload reference (verify in-game when uncertain):
--   CURRENCY_DISPLAY_UPDATE — https://warcraft.wiki.gg/wiki/CURRENCY_DISPLAY_UPDATE
--   UPDATE_FACTION — https://warcraft.wiki.gg/wiki/UPDATE_FACTION (no payload)
--   MAJOR_FACTION_RENOWN_LEVEL_CHANGED — https://warcraft.wiki.gg/wiki/MAJOR_FACTION_RENOWN_LEVEL_CHANGED
--   CHAT_MSG_COMBAT_FACTION_CHANGE — https://warcraft.wiki.gg/wiki/CHAT_MSG_COMBAT_FACTION_CHANGE (17 args; text/guid may be secret)
-- ============================================================================

--- Format WoW event payloads for logs (no raw text for possible API secrets).
---@return string
function Profiler:FormatEventPayload(...)
    local n = select("#", ...)
    local parts = {}
    -- CHAT_MSG_* combat/chat lines carry up to 17 payload args per Warcraft Wiki (e.g. CHAT_MSG_COMBAT_FACTION_CHANGE).
    local maxArgs = math.min(n, 18)
    for i = 1, maxArgs do
        local v = select(i, ...)
        local t = type(v)
        if t == "number" then
            parts[#parts + 1] = tostring(v)
        elseif t == "boolean" then
            parts[#parts + 1] = v and "1" or "0"
        elseif t == "string" then
            if v == "" then
                parts[#parts + 1] = "s0"
            elseif issecretvalue and issecretvalue(v) then
                parts[#parts + 1] = "<secret>"
            else
                parts[#parts + 1] = "s" .. tostring(#v)
            end
        elseif t == "nil" then
            parts[#parts + 1] = "_"
        else
            parts[#parts + 1] = t
        end
    end
    if n > maxArgs then
        parts[#parts + 1] = "..."
    end
    return table.concat(parts, ",")
end

--- After handling a Blizzard event: if measuring+eventTrace and CPU time >= eventTraceMinMs, append WN_TRACE_EVT.
---@param eventName string
---@param startTime number debugprofilestop() at handler entry
---@param ... any Event payload (varargs)
function Profiler:TraceEventHandler(eventName, startTime, ...)
    if not self.enabled or not self.eventTrace or not startTime then return end
    local elapsed = debugprofilestop() - startTime
    local minMs = tonumber(self.eventTraceMinMs) or 12
    if elapsed < minMs then return end
    local payload = self:FormatEventPayload(...)
    local line = string.format("WN_TRACE_EVT %s %.2fms %s", tostring(eventName), elapsed, payload)
    self:_AppendPerfTraceLine(line)
    if self.liveOutput then
        print(PREFIX .. C_WARN .. line .. C_R)
    end
    self:_Record(self:SliceLabel(self.CAT.MSG, "evt_" .. tostring(eventName)), elapsed)
end

--- Internal continuation (e.g. currency drain slice) — same WN_TRACE_EVT sink.
---@param label string
---@param startTime number
---@param extraDetail string|nil Safe short detail (counts, queue depth)
function Profiler:TraceInternalHandler(label, startTime, extraDetail)
    if not self.enabled or not self.eventTrace or not startTime then return end
    local elapsed = debugprofilestop() - startTime
    local minMs = tonumber(self.eventTraceMinMs) or 12
    if elapsed < minMs then return end
    local line = string.format("WN_TRACE_EVT %s %.2fms %s", tostring(label), elapsed, tostring(extraDetail or ""))
    self:_AppendPerfTraceLine(line)
    if self.liveOutput then
        print(PREFIX .. C_WARN .. line .. C_R)
    end
    self:_Record(self:SliceLabel(self.CAT.MSG, "evt_" .. tostring(label)), elapsed)
end

-- ============================================================================
-- INTERNAL RECORDING
-- ============================================================================

---Record a timing measurement for a label.
---@param label string Operation name
---@param elapsedMs number Elapsed time in milliseconds
function Profiler:_Record(label, elapsedMs)
    if self.gearOnlyRecording and not self:IsGearFocusedSliceLabel(label) then return end
    local e = self.entries[label]
    if not e then
        e = {
            calls = 0,
            totalMs = 0,
            minMs = math.huge,
            maxMs = 0,
            lastMs = 0,
        }
        self.entries[label] = e
    end
    
    e.calls = e.calls + 1
    e.totalMs = e.totalMs + elapsedMs
    e.lastMs = elapsedMs
    if elapsedMs < e.minMs then e.minMs = elapsedMs end
    if elapsedMs > e.maxMs then e.maxMs = elapsedMs end
end

-- ============================================================================
-- FRAME SPIKE DETECTION
-- ============================================================================

---@return number
function Profiler:_SpikeCount()
    return self._spikeCount or 0
end

---Oldest-to-newest spike entries (dense array for display).
---@return table
function Profiler:_GetSpikesChronological()
    local out = {}
    local buf = self.frameSpikes
    local maxS = self.maxSpikes
    local n = self._spikeCount or 0
    if n == 0 or not buf then return out end
    if n < maxS then
        for i = 1, n do
            out[#out + 1] = buf[i]
        end
    else
        local nextSlot = self._spikeNextSlot or 1
        for k = 0, maxS - 1 do
            local idx = ((nextSlot - 1 + k) % maxS) + 1
            out[#out + 1] = buf[idx]
        end
    end
    return out
end

---Enable or disable per-frame time tracking.
---@param enable boolean
function Profiler:SetFrameTracking(enable)
    self.frameTracking = enable
    local quiet = self._suppressFrameTrackingPrint
    
    if enable then
        if not self._frameHandler then
            local frame = CreateFrame("Frame")
            self._frameHandler = frame
        end
        self._frameStart = debugprofilestop()
        self._frameHandler:SetScript("OnUpdate", function()
            local now = debugprofilestop()
            local frameMs = now - self._frameStart
            self._frameStart = now
            
            if self.frameTracking and frameMs > self.spikeThreshold then
                local spike = {
                    timestamp = GetTime(),
                    frameMs = frameMs,
                    date = date("%H:%M:%S"),
                }
                local maxS = self.maxSpikes
                local idx = self._spikeNextSlot or 1
                self.frameSpikes[idx] = spike
                self._spikeNextSlot = (idx % maxS) + 1
                if (self._spikeCount or 0) < maxS then
                    self._spikeCount = (self._spikeCount or 0) + 1
                end
                
                if self.liveOutput then
                    local color = frameMs > 100 and C_BAD or C_WARN
                    print(PREFIX .. color .. "FRAME SPIKE " 
                        .. string.format("%.1fms", frameMs)
                        .. C_R .. "  " .. C_DIM .. spike.date .. C_R)
                end
            end
        end)
        if not quiet then
            print(PREFIX .. C_GOOD .. "Frame spike detection ENABLED" .. C_R
                .. C_DIM .. " (threshold: " .. string.format("%.1fms", self.spikeThreshold) .. ")" .. C_R)
        end
    else
        if self._frameHandler then
            self._frameHandler:SetScript("OnUpdate", nil)
        end
        if not quiet then
            print(PREFIX .. C_DIM .. "Frame spike detection DISABLED" .. C_R)
        end
    end
end

-- ============================================================================
-- DISPLAY / REPORTING
-- ============================================================================

---Print the performance summary table to chat.
function Profiler:PrintSummary()
    if not next(self.entries) then
        print(PREFIX .. C_DIM .. "No profiling data recorded." .. C_R)
        print(PREFIX .. C_DIM .. "Enable with: /wn profiler on" .. C_R)
        return
    end
    
    -- Sort entries by total time descending
    local sorted = {}
    for label, data in pairs(self.entries) do
        sorted[#sorted + 1] = { label = label, data = data }
    end
    table.sort(sorted, function(a, b)
        return a.data.totalMs > b.data.totalMs
    end)
    
    -- Header
    print(" ")
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    print(C_HEADER .. "  Warband Nexus - Performance Profiler" .. C_R)
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    if self.gearOnlyRecording then
        print(PREFIX .. C_DIM .. "Gear-only recording: UI/Pop_* only on last Gear populate; labels containing Gear/gear; |cff00ccff/wn profiler gearonly off|r" .. C_R)
    end
    print(string.format("  %-36s %6s %8s %8s %10s",
        C_DIM .. "Operation" .. C_R,
        C_DIM .. "Calls" .. C_R,
        C_DIM .. "Avg(ms)" .. C_R,
        C_DIM .. "Max(ms)" .. C_R,
        C_DIM .. "Total(ms)" .. C_R))
    print(C_DIM .. "  " .. string.rep("-", 72) .. C_R)
    
    -- Rows
    local grandTotal = 0
    for ei = 1, #sorted do
        local entry = sorted[ei]
        local d = entry.data
        local avgMs = d.calls > 0 and (d.totalMs / d.calls) or 0
        grandTotal = grandTotal + d.totalMs
        
        -- Color code by severity
        local maxColor = d.maxMs > 50 and C_BAD or d.maxMs > 16.67 and C_WARN or C_GOOD
        local avgColor = avgMs > 16.67 and C_BAD or avgMs > 5 and C_WARN or C_GOOD
        local totalColor = d.totalMs > 200 and C_BAD or d.totalMs > 50 and C_WARN or C_GOOD
        
        -- Truncate label for alignment
        local displayLabel = entry.label
        if #displayLabel > 34 then
            displayLabel = displayLabel:sub(1, 31) .. "..."
        end
        
        local line = string.format("  " .. C_LABEL .. "%-34s" .. C_R .. " %6s %8s %8s %10s",
            displayLabel,
            C_VALUE .. d.calls .. C_R,
            avgColor .. string.format("%.2f", avgMs) .. C_R,
            maxColor .. string.format("%.2f", d.maxMs) .. C_R,
            totalColor .. string.format("%.2f", d.totalMs) .. C_R)
        print(line)
        
        -- Show wall-clock time for async entries
        if d.lastWallSec then
            print("  " .. C_DIM .. string.rep(" ", 34) 
                .. "  wall: " .. string.format("%.1fs", d.lastWallSec) .. C_R)
        end
    end
    
    print(C_DIM .. "  " .. string.rep("-", 72) .. C_R)
    local gtColor = grandTotal > 500 and C_BAD or grandTotal > 100 and C_WARN or C_GOOD
    print(string.format("  " .. C_VALUE .. "%-34s" .. C_R .. " %6s %8s %8s %10s",
        "TOTAL",
        "",
        "",
        "",
        gtColor .. string.format("%.2f", grandTotal) .. C_R))
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    
    -- Active timers warning
    if next(self.activeTimers) then
        print(PREFIX .. C_WARN .. "Active timers (not stopped):" .. C_R)
        for label in pairs(self.activeTimers) do
            local elapsed = debugprofilestop() - self.activeTimers[label]
            print("  " .. C_WARN .. "• " .. label .. " (running: " .. string.format("%.2fms", elapsed) .. ")" .. C_R)
        end
    end
    if next(self.asyncTimers) then
        print(PREFIX .. C_WARN .. "Active async timers:" .. C_R)
        for label, entry in pairs(self.asyncTimers) do
            local elapsed = debugprofilestop() - entry.startTime
            local wall = GetTime() - entry.startFrame
            print("  " .. C_WARN .. "• " .. label 
                .. " (CPU: " .. string.format("%.2fms", elapsed) 
                .. ", wall: " .. string.format("%.1fs", wall) .. ")" .. C_R)
        end
    end
    
    print(" ")
end

---Print recent frame spikes.
function Profiler:PrintSpikes()
    local spikes = self:_GetSpikesChronological()
    if #spikes == 0 then
        print(PREFIX .. C_DIM .. "No frame spikes recorded." .. C_R)
        if not self.frameTracking then
            print(PREFIX .. C_DIM .. "Enable with: /wn profiler frames" .. C_R)
        end
        return
    end
    
    print(" ")
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    print(C_HEADER .. "  Recent Frame Spikes (>" .. string.format("%.0f", self.spikeThreshold) .. "ms)" .. C_R)
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    print(string.format("  %-12s %12s %10s",
        C_DIM .. "Time" .. C_R,
        C_DIM .. "Frame(ms)" .. C_R,
        C_DIM .. "FPS" .. C_R))
    print(C_DIM .. "  " .. string.rep("-", 40) .. C_R)
    
    -- Show last 20 spikes
    local startIdx = math.max(1, #spikes - 19)
    for i = startIdx, #spikes do
        local s = spikes[i]
        local fps = 1000 / s.frameMs
        local color = s.frameMs > 100 and C_BAD or s.frameMs > 50 and C_WARN or C_VALUE
        print(string.format("  %-12s %12s %10s",
            C_DIM .. s.date .. C_R,
            color .. string.format("%.1f", s.frameMs) .. C_R,
            color .. string.format("%.0f", fps) .. C_R))
    end
    
    print(C_DIM .. "  " .. string.rep("-", 40) .. C_R)
    local worst = 0
    for i = 1, #spikes do
        local ms = spikes[i].frameMs
        if ms > worst then worst = ms end
    end
    print(string.format("  " .. C_DIM .. "Total spikes: %d  |  Worst: %.1fms" .. C_R,
        #spikes,
        worst))
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    print(" ")
end

---Get array of spike millisecond values (helper for max calculation).
---@return table
function Profiler:_GetSpikeValues()
    local vals = {}
    local spikes = self:_GetSpikesChronological()
    for i = 1, #spikes do
        vals[#vals + 1] = spikes[i].frameMs
    end
    if #vals == 0 then vals[1] = 0 end
    return vals
end

---Reset all profiling data.
function Profiler:Reset()
    wipe(self.entries)
    wipe(self.activeTimers)
    wipe(self.asyncTimers)
    wipe(self.frameSpikes)
    self._spikeNextSlot = 1
    self._spikeCount = 0
    if self._traceLines then
        wipe(self._traceLines)
    end
    if self._traceEdit then
        self._traceEdit:SetText("")
    end
    print(PREFIX .. C_GOOD .. "All profiling data cleared." .. C_R)
end

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================

---Handle /wn profiler subcommands.
---@param addon table WarbandNexus addon instance
---@param subCmd string|nil Subcommand (on/off/reset/frames/spikes/live/threshold)
---@param arg3 string|nil Additional argument
---@param arg4 string|nil Optional 4th token (e.g. min ms for `profiler events on 8`)
function Profiler:HandleCommand(addon, subCmd, arg3, arg4)
    if not subCmd or subCmd == "" then
        self:PrintSummary()
        return
    end
    
    subCmd = subCmd:lower()
    
    if subCmd == "on" or subCmd == "enable" then
        self.enabled = true
        self.liveOutput = true
        self:SetFrameTracking(true)
        print(PREFIX .. C_GOOD .. "Profiling ENABLED" .. C_R .. " (live output + frame spikes; state saved for /reload)")
        self:SavePersistToProfile()
        
    elseif subCmd == "off" or subCmd == "disable" then
        self.enabled = false
        self.liveOutput = false
        self:SetFrameTracking(false)
        print(PREFIX .. C_DIM .. "Profiling DISABLED" .. C_R)
        self:SavePersistToProfile()
        
    elseif subCmd == "reset" or subCmd == "clear" then
        self:Reset()
        
    elseif subCmd == "frames" then
        self.frameTracking = not self.frameTracking
        if self.frameTracking and not self.enabled then
            self.enabled = true
            print(PREFIX .. C_GOOD .. "Profiling auto-enabled." .. C_R)
        end
        self:SetFrameTracking(self.frameTracking)
        self:SavePersistToProfile()
        
    elseif subCmd == "spikes" then
        self:PrintSpikes()
        
    elseif subCmd == "live" then
        self.liveOutput = not self.liveOutput
        if self.liveOutput and not self.enabled then
            self.enabled = true
            print(PREFIX .. C_GOOD .. "Profiling auto-enabled." .. C_R)
        end
        local stateStr = self.liveOutput and (C_GOOD .. "ON") or (C_DIM .. "OFF")
        print(PREFIX .. "Live output: " .. stateStr .. C_R)
        self:SavePersistToProfile()
        
    elseif subCmd == "threshold" then
        local val = (ns.Utilities and ns.Utilities.SafeNumber and ns.Utilities:SafeNumber(arg3, nil)) or nil
        if val and val > 0 then
            self.spikeThreshold = val
            print(PREFIX .. "Spike threshold set to " .. C_VALUE .. string.format("%.1fms", val) .. C_R)
        else
            print(PREFIX .. "Current threshold: " .. C_VALUE .. string.format("%.1fms", self.spikeThreshold) .. C_R)
            print(PREFIX .. C_DIM .. "Usage: /wn profiler threshold <ms>" .. C_R)
        end
        
    elseif subCmd == "status" then
        print(PREFIX .. "Measuring: " .. (self.enabled and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Live output: " .. (self.liveOutput and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Frame tracking: " .. (self.frameTracking and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Event trace (WN_TRACE_EVT): " .. (self.eventTrace and (C_GOOD .. "ON") or (C_DIM .. "OFF")) .. C_R
            .. "  minMs=" .. C_VALUE .. tostring(self.eventTraceMinMs or 12) .. C_R)
        print(PREFIX .. "Dev mode: " .. (self.devMode and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Spike threshold: " .. C_VALUE .. string.format("%.1fms", self.spikeThreshold) .. C_R)
        local entryCount = 0
        for _ in pairs(self.entries) do entryCount = entryCount + 1 end
        print(PREFIX .. "Recorded operations: " .. C_VALUE .. entryCount .. C_R)
        print(PREFIX .. "Recorded spikes: " .. C_VALUE .. tostring(self:_SpikeCount()) .. C_R)
        print(PREFIX .. C_DIM .. "AceDB: profile.profilerPersist (survives /reload)" .. C_R)
        
    elseif subCmd == "dev" then
        self.devMode = not self.devMode
        if not self.devMode then
            if self._devWindow then
                self._devWindow:Hide()
            end
            local p = GetProfilePersistRoot()
            if p then p.devWindowVisible = false end
            print(PREFIX .. C_DIM .. "Profiler dev mode OFF" .. C_R)
        else
            print(PREFIX .. C_GOOD .. "Profiler dev mode ON" .. C_R .. C_DIM .. "  |cff00ccff/wn profiler window|r HUD  |cff00ccff/wn profiler trace|r copy buffer" .. C_R)
        end
        self:SavePersistToProfile()
        
    elseif subCmd == "window" or subCmd == "hud" then
        if not self.devMode then
            print(PREFIX .. C_WARN .. "Turn on dev mode first: |cff00ccff/wn profiler dev|r" .. C_R)
            return
        end
        self:EnsureDevWindow()
        if self._devWindow:IsShown() then
            self._devWindow:Hide()
            local p = GetProfilePersistRoot()
            if p then p.devWindowVisible = false end
            print(PREFIX .. "Dev window hidden." .. C_R)
        else
            self:ApplyDevWindowLayoutFromPersist()
            self._devWindow:Show()
            self:RefreshDevWindowContent()
            local p = GetProfilePersistRoot()
            if p then p.devWindowVisible = true end
            print(PREFIX .. C_GOOD .. "Dev window shown." .. C_R)
        end
        self:SavePersistToProfile()
        
    elseif subCmd == "trace" or subCmd == "tracelog" then
        self:ToggleTraceWindow()
        
    elseif subCmd == "dock" then
        if not self.devMode then
            print(PREFIX .. C_WARN .. "Turn on dev mode first: |cff00ccff/wn profiler dev|r" .. C_R)
            return
        end
        self:EnsureDevWindow()
        self._devDocked = not self._devDocked
        local p = GetProfilePersistRoot()
        if p then p.docked = self._devDocked and true or false end
        self:ApplyDevWindowLayoutFromPersist()
        self:SavePersistToProfile()
        print(PREFIX .. "Dock left: " .. (self._devDocked and (C_GOOD .. "ON") or (C_DIM .. "OFF")) .. C_R)

    elseif subCmd == "gearonly" or subCmd == "gearonlyrecording" then
        local a = (arg3 and tostring(arg3):lower()) or ""
        if a == "on" or a == "1" or a == "true" then
            self.gearOnlyRecording = true
        elseif a == "off" or a == "0" or a == "false" then
            self.gearOnlyRecording = false
        else
            self.gearOnlyRecording = not self.gearOnlyRecording
        end
        local st = self.gearOnlyRecording and (C_GOOD .. "ON") or (C_DIM .. "OFF")
        print(PREFIX .. "Gear-only recording: " .. st .. C_R
            .. C_DIM .. "  UI/Pop_* slices only when Populate runs on Gear; async/deferred labels need \"Gear\" in name." .. C_R)
        self:SavePersistToProfile()

    elseif subCmd == "events" or subCmd == "eventtrace" then
        local a = (arg3 and tostring(arg3):lower()) or ""
        if a == "on" or a == "1" or a == "true" then
            self.eventTrace = true
        elseif a == "off" or a == "0" or a == "false" then
            self.eventTrace = false
        else
            self.eventTrace = not self.eventTrace
        end
        if self.eventTrace and arg4 then
            local m = (ns.Utilities and ns.Utilities.SafeNumber and ns.Utilities:SafeNumber(arg4, nil)) or tonumber(arg4)
            if m and m > 0 then
                self.eventTraceMinMs = m
            end
        end
        if self.eventTrace and not self.enabled then
            self.enabled = true
            print(PREFIX .. C_GOOD .. "Profiling auto-enabled (event trace needs measuring ON)." .. C_R)
        end
        local stEv = self.eventTrace and (C_GOOD .. "ON") or (C_DIM .. "OFF")
        print(PREFIX .. "Event trace (WN_TRACE_EVT): " .. stEv .. C_R
            .. C_DIM .. "  minMs=" .. tostring(self.eventTraceMinMs or 12)
            .. "  |cff00ccff/wn profiler events on 8|r sets threshold to 8ms" .. C_R)
        self:SavePersistToProfile()

    elseif subCmd == "help" then
        print(" ")
        print(C_HEADER .. "Warband Nexus Profiler - Commands" .. C_R)
        print(C_DIM .. string.rep("-", 50) .. C_R)
        print("  " .. C_LABEL .. "/wn profiler" .. C_R .. "           Show performance summary")
        print("  " .. C_LABEL .. "/wn profiler on" .. C_R .. "        Enable profiling (saved; survives /reload)")
        print("  " .. C_LABEL .. "/wn profiler off" .. C_R .. "       Disable profiling")
        print("  " .. C_LABEL .. "/wn profiler reset" .. C_R .. "     Clear all data")
        print("  " .. C_LABEL .. "/wn profiler frames" .. C_R .. "    Toggle frame spike detection")
        print("  " .. C_LABEL .. "/wn profiler spikes" .. C_R .. "    Show recent frame spikes")
        print("  " .. C_LABEL .. "/wn profiler live" .. C_R .. "      Toggle live Start/Stop output")
        print("  " .. C_LABEL .. "/wn profiler threshold <ms>" .. C_R .. "  Set spike threshold")
        print("  " .. C_LABEL .. "/wn profiler status" .. C_R .. "    Show profiler state")
        print("  " .. C_LABEL .. "/wn profiler dev" .. C_R .. "       Toggle dev mode (HUD + layout save)")
        print("  " .. C_LABEL .. "/wn profiler window" .. C_R .. "  Toggle dev summary window")
        print("  " .. C_LABEL .. "/wn profiler trace" .. C_R .. "   Toggle WN_TRACE copy window (needs measuring ON)")
        print("  " .. C_LABEL .. "/wn profiler dock" .. C_R .. "    Toggle dock-left for dev window")
        print("  " .. C_LABEL .. "/wn profiler gearonly" .. C_R .. " on|off  Record only Gear-focused slices (reduces noise)")
        print("  " .. C_LABEL .. "/wn profiler events" .. C_R .. " on|off [minMs]  Log slow Blizzard handlers (WN_TRACE_EVT)")
        print(" ")
    else
        print(PREFIX .. C_WARN .. "Unknown subcommand: " .. tostring(subCmd) .. C_R)
        print(PREFIX .. C_DIM .. "Type /wn profiler help for commands." .. C_R)
    end
end

-- ============================================================================
-- CONVENIENCE: Auto-instrument common patterns
-- ============================================================================

---Create a profiled version of a function (useful for hooking).
---@param label string Operation name
---@param func function Original function
---@return function profiledFunc Wrapped function that records timing
function Profiler:CreateProfiled(label, func)
    local profiler = self
    return function(...)
        if not profiler.enabled then return func(...) end
        return profiler:Wrap(label, func, ...)
    end
end
