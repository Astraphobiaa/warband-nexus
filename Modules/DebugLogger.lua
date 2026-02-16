--[[
    DebugLogger.lua - In-memory debug logger for WoW (io library not available)
]]

local addonName, ns = ...

-- Global debug log storage
_G.WN_DEBUG_LOGS = _G.WN_DEBUG_LOGS or {}

-- Log function
local function DebugLog(location, message, data, hypothesisId)
    table.insert(_G.WN_DEBUG_LOGS, {
        timestamp = GetTime() * 1000,
        location = location,
        message = message,
        data = data or {},
        hypothesisId = hypothesisId or "unknown",
        sessionId = "debug-session",
        runId = "initial"
    })
end

-- Debug commands removed for production build.
-- Use /wn debug to toggle debug mode.

-- Export
ns.DebugLog = DebugLog
