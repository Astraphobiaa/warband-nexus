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

-- Clear logs command
SLASH_WNCLEARLOGS1 = "/wnclear"
SlashCmdList["WNCLEARLOGS"] = function()
    _G.WN_DEBUG_LOGS = {}
    DebugPrint("|cff00ff00[WN Debug]|r Logs cleared")
end

-- Dump logs command
SLASH_WNDUMPLOGS1 = "/wndump"
SlashCmdList["WNDUMPLOGS"] = function()
    if #_G.WN_DEBUG_LOGS == 0 then
        DebugPrint("|cffffcc00[WN Debug]|r No logs to dump")
        return
    end
    
    DebugPrint("|cff00ff00[WN Debug]|r === Debug Logs (" .. #_G.WN_DEBUG_LOGS .. " entries) ===")
    for i, log in ipairs(_G.WN_DEBUG_LOGS) do
        local dataStr = ""
        for k, v in pairs(log.data) do
            dataStr = dataStr .. k .. "=" .. tostring(v) .. " "
        end
        DebugPrint(string.format("[%d] %s | %s | %s | H:%s",
            i,
            log.location,
            log.message,
            dataStr,
            log.hypothesisId))
    end
    DebugPrint("|cff00ff00[WN Debug]|r === End Logs ===")
end

-- Export
ns.DebugLog = DebugLog
