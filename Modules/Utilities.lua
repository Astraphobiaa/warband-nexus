--[[
    Warband Nexus - Utilities
    Common helper functions to eliminate code duplication
]]

local ADDON_NAME, ns = ...

---@class Utilities
local Utilities = {}
ns.Utilities = Utilities

--============================================================================
-- CHARACTER IDENTIFICATION
--============================================================================

--- Get character key (Name-Realm format)
--- Eliminates 70+ duplicate instances across codebase
---@param name string|nil Player name (defaults to current player)
---@param realm string|nil Realm name (defaults to current realm)
---@return string Character key in "Name-Realm" format
function Utilities:GetCharacterKey(name, realm)
    name = name or UnitName("player")
    realm = realm or GetRealmName()
    local key = name .. "-" .. realm
    -- Debug log (only on first call per session)
    if not self._keyLogged then
        print("|cff9370DB[WN Utilities]|r GetCharacterKey() first call: " .. key)
        self._keyLogged = true
    end
    return key
end

--============================================================================
-- MODULE CHECKS
--============================================================================

--- Check if a module is enabled in settings
--- Eliminates 20+ duplicate checks across codebase
---@param moduleName string Module name (e.g., "pve", "currencies")
---@return boolean Whether the module is enabled
function Utilities:IsModuleEnabled(moduleName)
    local db = ns.WarbandNexus and ns.WarbandNexus.db
    if not db or not db.profile then return false end
    
    local modules = db.profile.modulesEnabled
    if not modules then return false end
    
    return modules[moduleName] == true
end

--============================================================================
-- SAFE TABLE ACCESS
--============================================================================

--- Safely access nested table values without nil errors
---@param tbl table The root table
---@param ... string Keys to traverse
---@return any|nil The value if found, nil otherwise
function Utilities:SafeTableGet(tbl, ...)
    if not tbl then return nil end
    
    local current = tbl
    for i = 1, select("#", ...) do
        local key = select(i, ...)
        if type(current) ~= "table" then return nil end
        current = current[key]
        if current == nil then return nil end
    end
    
    return current
end

--============================================================================
-- VALIDATION
--============================================================================

--- Check if a value is a valid number
---@param value any Value to check
---@return boolean Whether the value is a valid number
function Utilities:IsValidNumber(value)
    return type(value) == "number" and value == value -- NaN check
end

--- Check if a string is empty or nil
---@param str string|nil String to check
---@return boolean Whether the string is empty or nil
function Utilities:IsEmptyString(str)
    return not str or str == "" or str:match("^%s*$") ~= nil
end

--============================================================================
-- EXPORT
--============================================================================

return Utilities
