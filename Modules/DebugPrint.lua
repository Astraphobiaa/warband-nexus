--[[
    DebugPrint.lua - Global debug print helper
    Automatically suppress verbose logging unless debug mode is enabled
]]

local ADDON_NAME, ns = ...

--- Print debug message (only if debug mode enabled)
---@param ... any Messages to print
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end

--- Print message always (even without debug mode)
---@param message string Message to print
local function AlwaysPrint(message)
    print(message)
end

-- Export to namespace
ns.DebugPrint = DebugPrint
ns.AlwaysPrint = AlwaysPrint

return {
    DebugPrint = DebugPrint,
    AlwaysPrint = AlwaysPrint,
}
