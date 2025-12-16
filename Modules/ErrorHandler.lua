--[[
    Warband Nexus - Error Handler Module
    Production-ready error handling and logging
    
    Features:
    - Safe function execution (pcall wrappers)
    - Error logging with stack traces
    - User-friendly error messages
    - Error statistics
    - Debug mode with verbose logging
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- ERROR STORAGE
-- ============================================================================

local errorLog = {}  -- {timestamp, message, stack, count}
local errorStats = {
    total = 0,
    byFunction = {},  -- {functionName = count}
    lastError = nil,
}

local MAX_ERRORS = 50  -- Keep only last 50 errors

-- ============================================================================
-- SAFE FUNCTION EXECUTION
-- ============================================================================

--[[
    Safely execute a function with error handling
    @param func function - Function to execute
    @param context string - Context/name for debugging
    @param ... any - Arguments to pass to function
    @return boolean, any - Success status and result (or error message)
]]
function WarbandNexus:SafeCall(func, context, ...)
    if type(func) ~= "function" then
        self:LogError("SafeCall: Not a function", context or "Unknown")
        return false, "Not a function"
    end
    
    local success, result = pcall(func, ...)
    
    if not success then
        -- Error occurred
        local errorMsg = tostring(result)
        self:LogError(errorMsg, context or "Unknown", debugstack(2))
        
        -- Show user-friendly message (only in debug mode or first occurrence)
        if self.db.profile.debug or not errorStats.byFunction[context] then
            self:Print(string.format("|cffff0000Error in %s:|r %s", context or "addon", errorMsg))
            if self.db.profile.debug then
                self:Print("|cff888888Use /wn errors to see details|r")
            end
        end
        
        return false, errorMsg
    end
    
    return true, result
end

--[[
    Safely execute a function and return nil on error (silent failure)
    @param func function - Function to execute
    @param context string - Context for logging
    @param ... any - Arguments
    @return any - Result or nil
]]
function WarbandNexus:SafeCallSilent(func, context, ...)
    local success, result = self:SafeCall(func, context, ...)
    if success then
        return result
    end
    return nil
end

--[[
    Wrap a function with error handling
    Returns a new function that catches errors
    @param func function - Original function
    @param context string - Context name
    @return function - Wrapped function
]]
function WarbandNexus:WrapFunction(func, context)
    return function(...)
        return self:SafeCall(func, context, ...)
    end
end

-- ============================================================================
-- ERROR LOGGING
-- ============================================================================

--[[
    Log an error with stack trace
    @param message string - Error message
    @param context string - Where the error occurred
    @param stack string - Stack trace (optional)
]]
function WarbandNexus:LogError(message, context, stack)
    errorStats.total = errorStats.total + 1
    errorStats.lastError = time()
    
    -- Update function stats
    if context then
        errorStats.byFunction[context] = (errorStats.byFunction[context] or 0) + 1
    end
    
    -- Check if this is a duplicate error (same message in last 10 errors)
    local isDuplicate = false
    for i = #errorLog, math.max(1, #errorLog - 10), -1 do
        if errorLog[i].message == message and errorLog[i].context == context then
            errorLog[i].count = errorLog[i].count + 1
            errorLog[i].lastSeen = time()
            isDuplicate = true
            break
        end
    end
    
    if not isDuplicate then
        -- Add new error
        table.insert(errorLog, {
            timestamp = time(),
            lastSeen = time(),
            message = message,
            context = context or "Unknown",
            stack = stack or debugstack(3),
            count = 1,
        })
        
        -- Limit log size
        if #errorLog > MAX_ERRORS then
            table.remove(errorLog, 1)
        end
    end
    
    -- Debug output
    if self.db and self.db.profile and self.db.profile.debug then
        print(string.format("|cffff0000[WarbandNexus Error]|r %s: %s", context or "Unknown", message))
    end
end

--[[
    Get error statistics
    @return table - Error stats
]]
function WarbandNexus:GetErrorStats()
    return {
        total = errorStats.total,
        unique = #errorLog,
        lastError = errorStats.lastError,
        byFunction = errorStats.byFunction,
    }
end

--[[
    Get recent errors
    @param count number - Number of errors to retrieve (default 10)
    @return table - Array of error entries
]]
function WarbandNexus:GetRecentErrors(count)
    count = count or 10
    local recent = {}
    
    for i = #errorLog, math.max(1, #errorLog - count + 1), -1 do
        table.insert(recent, errorLog[i])
    end
    
    return recent
end

--[[
    Clear error log
]]
function WarbandNexus:ClearErrorLog()
    errorLog = {}
    errorStats = {
        total = 0,
        byFunction = {},
        lastError = nil,
    }
    self:Print("Error log cleared")
end

-- ============================================================================
-- USER INTERFACE
-- ============================================================================

--[[
    Print error statistics to chat
]]
function WarbandNexus:PrintErrorStats()
    local stats = self:GetErrorStats()
    
    self:Print("===== Error Statistics =====")
    self:Print(string.format("Total Errors: %d (Unique: %d)", stats.total, stats.unique))
    
    if stats.lastError then
        local elapsed = time() - stats.lastError
        local timeStr
        if elapsed < 60 then
            timeStr = string.format("%d seconds ago", elapsed)
        elseif elapsed < 3600 then
            timeStr = string.format("%d minutes ago", math.floor(elapsed / 60))
        else
            timeStr = string.format("%d hours ago", math.floor(elapsed / 3600))
        end
        self:Print(string.format("Last Error: %s", timeStr))
    else
        self:Print("Last Error: None")
    end
    
    -- Top 5 error sources
    if next(stats.byFunction) then
        self:Print("Top Error Sources:")
        local sorted = {}
        for func, count in pairs(stats.byFunction) do
            table.insert(sorted, {func = func, count = count})
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        
        for i = 1, math.min(5, #sorted) do
            self:Print(string.format("  %d. %s (%dx)", i, sorted[i].func, sorted[i].count))
        end
    end
end

--[[
    Print recent errors to chat
    @param count number - Number of errors to show (default 5)
]]
function WarbandNexus:PrintRecentErrors(count)
    count = count or 5
    local errors = self:GetRecentErrors(count)
    
    if #errors == 0 then
        self:Print("No errors recorded")
        return
    end
    
    self:Print(string.format("===== Last %d Errors =====", math.min(count, #errors)))
    
    for i, err in ipairs(errors) do
        local timeStr = date("%H:%M:%S", err.timestamp)
        local countStr = err.count > 1 and string.format(" (x%d)", err.count) or ""
        self:Print(string.format("[%s] %s: %s%s", timeStr, err.context, err.message, countStr))
        
        -- Show stack trace in debug mode
        if self.db.profile.debug and err.stack then
            local stackLines = {strsplit("\n", err.stack)}
            for j = 1, math.min(3, #stackLines) do
                if stackLines[j] and stackLines[j] ~= "" then
                    self:Print("  " .. stackLines[j])
                end
            end
        end
    end
    
    self:Print("Use '/wn errors full' to see all details")
end

--[[
    Show detailed error information
    @param errorIndex number - Error index (1 = most recent)
]]
function WarbandNexus:ShowErrorDetails(errorIndex)
    errorIndex = errorIndex or 1
    local errors = self:GetRecentErrors(50)
    
    if errorIndex < 1 or errorIndex > #errors then
        self:Print(string.format("Error #%d not found (valid range: 1-%d)", errorIndex, #errors))
        return
    end
    
    local err = errors[errorIndex]
    
    self:Print("===== Error Details =====")
    self:Print(string.format("Timestamp: %s", date("%Y-%m-%d %H:%M:%S", err.timestamp)))
    self:Print(string.format("Context: %s", err.context))
    self:Print(string.format("Occurrences: %dx", err.count))
    self:Print(string.format("Message: %s", err.message))
    
    if err.stack then
        self:Print("Stack Trace:")
        local stackLines = {strsplit("\n", err.stack)}
        for i, line in ipairs(stackLines) do
            if line and line ~= "" then
                self:Print("  " .. line)
            end
        end
    end
end

-- ============================================================================
-- SAFE WRAPPERS FOR CRITICAL FUNCTIONS
-- ============================================================================

--[[
    Wrap critical addon functions with error handling
    Called during initialization
]]
function WarbandNexus:WrapCriticalFunctions()
    -- List of functions to wrap
    local criticalFunctions = {
        -- UI Functions
        "PopulateContent",
        "RefreshUI",
        "ToggleMainWindow",
        "ShowMainWindow",
        "CreateMainWindow",
        
        -- Data Functions
        "SaveCurrentCharacterData",
        "UpdateCharacterGold",
        "CollectPvEData",
        
        -- Bank Functions
        "ScanWarbandBank",
        "ScanPersonalBank",
        "OnBankOpened",
        "OnBankClosed",
        
        -- Event Handlers
        "OnBagUpdate",
        "OnMoneyChanged",
        "OnCollectionChanged",
        "OnPvEDataChanged",
    }
    
    -- Wrap each function
    for _, funcName in ipairs(criticalFunctions) do
        if self[funcName] and type(self[funcName]) == "function" then
            local originalFunc = self[funcName]
            self[funcName] = function(...)
                local success, result = self:SafeCall(originalFunc, funcName, ...)
                if success then
                    return result
                end
                return nil
            end
            self:Debug(string.format("Wrapped function: %s", funcName))
        end
    end
end

-- ============================================================================
-- EMERGENCY RECOVERY
-- ============================================================================

--[[
    Attempt to recover from a critical error
    Resets addon to safe state
]]
function WarbandNexus:EmergencyRecovery()
    self:Print("|cffff0000Emergency recovery initiated...|r")
    
    -- Close main window if open
    if self.mainFrame and self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    end
    
    -- Clear UI references
    self.mainFrame = nil
    
    -- Clear caches
    if self.ClearAllCaches then
        self:ClearAllCaches()
    end
    
    -- Re-initialize if possible
    C_Timer.After(1, function()
        if WarbandNexus then
            WarbandNexus:Print("|cff00ff00Recovery complete.|r Try opening the window again (/wn show)")
        end
    end)
end

--[[
    Export error log for bug reporting
    @return string - Formatted error log
]]
function WarbandNexus:ExportErrorLog()
    if #errorLog == 0 then
        return "No errors recorded"
    end
    
    local export = {}
    table.insert(export, "Warband Nexus Error Log")
    table.insert(export, string.format("Version: %s", self.version or "Unknown"))
    table.insert(export, string.format("Generated: %s", date("%Y-%m-%d %H:%M:%S")))
    table.insert(export, "")
    table.insert(export, string.format("Total Errors: %d", errorStats.total))
    table.insert(export, "")
    
    for i, err in ipairs(errorLog) do
        table.insert(export, string.format("--- Error #%d ---", i))
        table.insert(export, string.format("Time: %s", date("%Y-%m-%d %H:%M:%S", err.timestamp)))
        table.insert(export, string.format("Context: %s", err.context))
        table.insert(export, string.format("Count: %dx", err.count))
        table.insert(export, string.format("Message: %s", err.message))
        if err.stack then
            table.insert(export, "Stack:")
            table.insert(export, err.stack)
        end
        table.insert(export, "")
    end
    
    return table.concat(export, "\n")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

--[[
    Initialize error handler
    Called during OnEnable
]]
function WarbandNexus:InitializeErrorHandler()
    -- Wrap critical functions
    self:WrapCriticalFunctions()
    
    -- Register slash commands
    -- (Hidden commands, not shown in help)
    
    self:Debug("Error handler initialized")
end

-- Export for debugging
ns.ErrorLog = errorLog
ns.ErrorStats = errorStats
