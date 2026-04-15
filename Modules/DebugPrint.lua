--[[
    DebugPrint.lua - Global debug print helper
    Automatically suppress verbose logging unless debug mode is enabled
]]

local ADDON_NAME, ns = ...

local function GetDebugProfile()
    local addon = _G.WarbandNexus
    if not addon or not addon.db or not addon.db.profile then
        return nil
    end
    return addon.db.profile
end

local function IsDebugModeEnabled()
    local profile = GetDebugProfile()
    return profile and profile.debugMode == true or false
end

local function IsDebugVerboseEnabled()
    local profile = GetDebugProfile()
    return profile and profile.debugMode == true and profile.debugVerbose == true or false
end

local function IsTryCounterLootDebugEnabled()
    local profile = GetDebugProfile()
    return profile and profile.debugTryCounterLoot == true or false
end

---Create a module-scoped debug printer with optional policy flags.
---@param prefix string|nil Optional prefix printed before message args
---@param options table|nil { verboseOnly=boolean, suppressWhenTryCounterLoot=boolean }
---@return function printer
local function CreateDebugPrinter(prefix, options)
    options = options or {}
    local verboseOnly = options.verboseOnly == true
    local suppressWhenTryCounterLoot = options.suppressWhenTryCounterLoot == true

    return function(...)
        if suppressWhenTryCounterLoot and IsTryCounterLootDebugEnabled() then return end
        if verboseOnly then
            if not IsDebugVerboseEnabled() then return end
        else
            if not IsDebugModeEnabled() then return end
        end

        if prefix ~= nil then
            _G.print(prefix, ...)
        else
            _G.print(...)
        end
    end
end

--- Print debug message (only if debug mode enabled).
--- Use this as the default logging path.
---@param ... any Messages to print
local function DebugPrint(...)
    if not IsDebugModeEnabled() then return end
    _G.print(...)
end

--- Print debug message (only if debugMode + debugVerbose enabled).
---@param ... any Messages to print
local function DebugVerbosePrint(...)
    if not IsDebugVerboseEnabled() then return end
    _G.print(...)
end

-- Export to namespace
ns.DebugPrint = DebugPrint
ns.DebugVerbosePrint = DebugVerbosePrint
ns.IsDebugModeEnabled = IsDebugModeEnabled
ns.IsDebugVerboseEnabled = IsDebugVerboseEnabled
ns.IsTryCounterLootDebugEnabled = IsTryCounterLootDebugEnabled
ns.CreateDebugPrinter = CreateDebugPrinter

return {
    DebugPrint = DebugPrint,
    DebugVerbosePrint = DebugVerbosePrint,
    IsDebugModeEnabled = IsDebugModeEnabled,
    IsDebugVerboseEnabled = IsDebugVerboseEnabled,
    IsTryCounterLootDebugEnabled = IsTryCounterLootDebugEnabled,
    CreateDebugPrinter = CreateDebugPrinter,
}
