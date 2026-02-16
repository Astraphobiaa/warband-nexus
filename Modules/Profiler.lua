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
    
    Slash commands:
        /wn profiler          - Show performance summary
        /wn profiler on       - Enable profiling
        /wn profiler off      - Disable profiling
        /wn profiler reset    - Clear all recorded data
        /wn profiler frames   - Toggle frame spike detection
        /wn profiler spikes   - Show recent frame spikes
        /wn profiler live     - Toggle live output (print each Start/Stop)
============================================================================]]

local ADDON_NAME, ns = ...

-- ============================================================================
-- MODULE DEFINITION
-- ============================================================================

local Profiler = {
    enabled = false,
    liveOutput = false,
    frameTracking = false,
    entries = {},       -- { [label] = { calls, totalMs, minMs, maxMs, lastMs } }
    activeTimers = {},  -- { [label] = startTimestamp }
    asyncTimers = {},   -- { [label] = { startTime, frameCount } }
    frameSpikes = {},   -- ring buffer of recent spikes { timestamp, frameMs }
    maxSpikes = 50,     -- max spikes to keep
    spikeThreshold = 33.33, -- ms (below 30fps)
    _frameStart = 0,
    _frameHandler = nil,
}

ns.Profiler = Profiler

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

-- ============================================================================
-- CORE TIMING API
-- ============================================================================

---Start timing a named operation.
---@param label string Unique operation name
function Profiler:Start(label)
    if not self.enabled then return end
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
-- INTERNAL RECORDING
-- ============================================================================

---Record a timing measurement for a label.
---@param label string Operation name
---@param elapsedMs number Elapsed time in milliseconds
function Profiler:_Record(label, elapsedMs)
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

---Enable or disable per-frame time tracking.
---@param enable boolean
function Profiler:SetFrameTracking(enable)
    self.frameTracking = enable
    
    if enable and not self._frameHandler then
        local frame = CreateFrame("Frame")
        self._frameStart = debugprofilestop()
        frame:SetScript("OnUpdate", function()
            local now = debugprofilestop()
            local frameMs = now - self._frameStart
            self._frameStart = now
            
            if self.frameTracking and frameMs > self.spikeThreshold then
                local spike = {
                    timestamp = GetTime(),
                    frameMs = frameMs,
                    date = date("%H:%M:%S"),
                }
                local spikes = self.frameSpikes
                spikes[#spikes + 1] = spike
                
                -- Ring buffer trim
                while #spikes > self.maxSpikes do
                    table.remove(spikes, 1)
                end
                
                if self.liveOutput then
                    local color = frameMs > 100 and C_BAD or C_WARN
                    print(PREFIX .. color .. "FRAME SPIKE " 
                        .. string.format("%.1fms", frameMs)
                        .. C_R .. "  " .. C_DIM .. spike.date .. C_R)
                end
            end
        end)
        self._frameHandler = frame
        print(PREFIX .. C_GOOD .. "Frame spike detection ENABLED" .. C_R
            .. C_DIM .. " (threshold: " .. string.format("%.1fms", self.spikeThreshold) .. ")" .. C_R)
    elseif not enable and self._frameHandler then
        self._frameHandler:SetScript("OnUpdate", nil)
        print(PREFIX .. C_DIM .. "Frame spike detection DISABLED" .. C_R)
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
    print(string.format("  %-36s %6s %8s %8s %10s",
        C_DIM .. "Operation" .. C_R,
        C_DIM .. "Calls" .. C_R,
        C_DIM .. "Avg(ms)" .. C_R,
        C_DIM .. "Max(ms)" .. C_R,
        C_DIM .. "Total(ms)" .. C_R))
    print(C_DIM .. "  " .. string.rep("-", 72) .. C_R)
    
    -- Rows
    local grandTotal = 0
    for _, entry in ipairs(sorted) do
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
    local spikes = self.frameSpikes
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
    print(string.format("  " .. C_DIM .. "Total spikes: %d  |  Worst: %.1fms" .. C_R,
        #spikes,
        spikes[1] and math.max(unpack(self:_GetSpikeValues())) or 0))
    print(C_HEADER .. "══════════════════════════════════════════════════════════════════" .. C_R)
    print(" ")
end

---Get array of spike millisecond values (helper for max calculation).
---@return table
function Profiler:_GetSpikeValues()
    local vals = {}
    for _, s in ipairs(self.frameSpikes) do
        vals[#vals + 1] = s.frameMs
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
    print(PREFIX .. C_GOOD .. "All profiling data cleared." .. C_R)
end

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================

---Handle /wn profiler subcommands.
---@param addon table WarbandNexus addon instance
---@param subCmd string|nil Subcommand (on/off/reset/frames/spikes/live/threshold)
---@param arg3 string|nil Additional argument
function Profiler:HandleCommand(addon, subCmd, arg3)
    if not subCmd or subCmd == "" then
        self:PrintSummary()
        return
    end
    
    subCmd = subCmd:lower()
    
    if subCmd == "on" or subCmd == "enable" then
        self.enabled = true
        self.liveOutput = true
        self:SetFrameTracking(true)
        print(PREFIX .. C_GOOD .. "Profiling ENABLED" .. C_R .. " (live output + frame spikes)")
        
    elseif subCmd == "off" or subCmd == "disable" then
        self.enabled = false
        self.liveOutput = false
        self:SetFrameTracking(false)
        print(PREFIX .. C_DIM .. "Profiling DISABLED" .. C_R)
        
    elseif subCmd == "reset" or subCmd == "clear" then
        self:Reset()
        
    elseif subCmd == "frames" then
        self.frameTracking = not self.frameTracking
        if self.frameTracking and not self.enabled then
            self.enabled = true
            print(PREFIX .. C_GOOD .. "Profiling auto-enabled." .. C_R)
        end
        self:SetFrameTracking(self.frameTracking)
        
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
        
    elseif subCmd == "threshold" then
        local val = tonumber(arg3)
        if val and val > 0 then
            self.spikeThreshold = val
            print(PREFIX .. "Spike threshold set to " .. C_VALUE .. string.format("%.1fms", val) .. C_R)
        else
            print(PREFIX .. "Current threshold: " .. C_VALUE .. string.format("%.1fms", self.spikeThreshold) .. C_R)
            print(PREFIX .. C_DIM .. "Usage: /wn profiler threshold <ms>" .. C_R)
        end
        
    elseif subCmd == "status" then
        print(PREFIX .. "Enabled: " .. (self.enabled and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Live output: " .. (self.liveOutput and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Frame tracking: " .. (self.frameTracking and (C_GOOD .. "YES") or (C_DIM .. "NO")) .. C_R)
        print(PREFIX .. "Spike threshold: " .. C_VALUE .. string.format("%.1fms", self.spikeThreshold) .. C_R)
        local entryCount = 0
        for _ in pairs(self.entries) do entryCount = entryCount + 1 end
        print(PREFIX .. "Recorded operations: " .. C_VALUE .. entryCount .. C_R)
        print(PREFIX .. "Recorded spikes: " .. C_VALUE .. #self.frameSpikes .. C_R)
        
    elseif subCmd == "help" then
        print(" ")
        print(C_HEADER .. "Warband Nexus Profiler - Commands" .. C_R)
        print(C_DIM .. string.rep("-", 50) .. C_R)
        print("  " .. C_LABEL .. "/wn profiler" .. C_R .. "           Show performance summary")
        print("  " .. C_LABEL .. "/wn profiler on" .. C_R .. "        Enable profiling")
        print("  " .. C_LABEL .. "/wn profiler off" .. C_R .. "       Disable profiling")
        print("  " .. C_LABEL .. "/wn profiler reset" .. C_R .. "     Clear all data")
        print("  " .. C_LABEL .. "/wn profiler frames" .. C_R .. "    Toggle frame spike detection")
        print("  " .. C_LABEL .. "/wn profiler spikes" .. C_R .. "    Show recent frame spikes")
        print("  " .. C_LABEL .. "/wn profiler live" .. C_R .. "      Toggle live Start/Stop output")
        print("  " .. C_LABEL .. "/wn profiler threshold <ms>" .. C_R .. "  Set spike threshold")
        print("  " .. C_LABEL .. "/wn profiler status" .. C_R .. "    Show profiler state")
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
