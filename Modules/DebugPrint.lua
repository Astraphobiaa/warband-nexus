--[[
    DebugPrint.lua - Global debug print helper
    Automatically suppress verbose logging unless debug mode is enabled
]]

local ADDON_NAME, ns = ...

local tconcat = table.concat

--- Route debug text to Profiler trace buffer (not default chat).
---@param line string
local function EmitDebugTraceLine(line)
    if not line or line == "" then return end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine(line)
    end
end

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
    return profile and profile.debugMode == true and profile.debugTryCounterLoot == true or false
end

--- Cache/scan/tooltip tier: debugMode + debugVerbose (Settings → Debug Verbose).
local function IsUserDebugTraceActive()
    return IsDebugVerboseEnabled()
end

--- Module diagnostics tier: verbose OR trace window visible (/wn profiler trace).
local function IsModuleDebugTraceActive()
    if not IsDebugModeEnabled() then return false end
    if IsDebugVerboseEnabled() then return true end
    local P = ns.Profiler
    return P and P.IsUserTraceWindowShown and P:IsUserTraceWindowShown() or false
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
            if not IsUserDebugTraceActive() then return end
        else
            if not IsModuleDebugTraceActive() then return end
        end

        local n = select("#", ...)
        local parts = {}
        for i = 1, n do
            parts[i] = tostring(select(i, ...))
        end
        local body = tconcat(parts, " ")
        if prefix ~= nil then
            EmitDebugTraceLine(tostring(prefix) .. " " .. body)
        else
            EmitDebugTraceLine(body)
        end
    end
end

--- Print debug message (debugMode + debugVerbose — cache/scan tier; trace buffer only).
---@param ... any Messages to print
local function DebugPrint(...)
    if not IsUserDebugTraceActive() then return end
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    EmitDebugTraceLine(tconcat(parts, " "))
end

--- Alias of DebugPrint (verbose cache/scan/tooltip tier).
---@param ... any Messages to print
local function DebugVerbosePrint(...)
    if not IsUserDebugTraceActive() then return end
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    EmitDebugTraceLine(tconcat(parts, " "))
end

--- Print to default chat only when debug mode is enabled (slash feedback, rare UX).
---@param ... any
local function DebugChatPrint(...)
    if not IsDebugModeEnabled() then return end
    local addon = _G.WarbandNexus
    if not addon or not addon.Print then return end
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    addon:Print(tconcat(parts, " "))
end

-- Export to namespace
ns.DebugPrint = DebugPrint
ns.DebugVerbosePrint = DebugVerbosePrint
ns.DebugChatPrint = DebugChatPrint
ns.IsDebugModeEnabled = IsDebugModeEnabled
ns.IsDebugVerboseEnabled = IsDebugVerboseEnabled
ns.IsTryCounterLootDebugEnabled = IsTryCounterLootDebugEnabled
ns.IsUserDebugTraceActive = IsUserDebugTraceActive
ns.IsModuleDebugTraceActive = IsModuleDebugTraceActive
ns.CreateDebugPrinter = CreateDebugPrinter

return {
    DebugPrint = DebugPrint,
    DebugVerbosePrint = DebugVerbosePrint,
    DebugChatPrint = DebugChatPrint,
    IsDebugModeEnabled = IsDebugModeEnabled,
    IsDebugVerboseEnabled = IsDebugVerboseEnabled,
    IsTryCounterLootDebugEnabled = IsTryCounterLootDebugEnabled,
    IsUserDebugTraceActive = IsUserDebugTraceActive,
    IsModuleDebugTraceActive = IsModuleDebugTraceActive,
    CreateDebugPrinter = CreateDebugPrinter,
}
