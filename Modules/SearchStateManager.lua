--[[
    Warband Nexus - Search State Manager (Service Layer)
    
    Service-Oriented, Event-Driven search state management
    - Manages search queries and state per tab
    - Throttles search updates to prevent performance issues
    - Fires events for UI consumption (no direct UI manipulation)
    - Provides centralized API for all search operations
    
    Architecture: Pure Service Layer (UI-Agnostic)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Ace3 Event System
local AceEvent = LibStub("AceEvent-3.0")

--============================================================================
-- STATE STORAGE
--============================================================================

-- Per-tab search state
-- Structure: {
--   [tabId] = {
--     query = "",           -- Current search query (lowercase)
--     resultCount = 0,      -- Number of results (set by UI after rendering)
--     isEmpty = false,      -- Whether results are empty
--     timestamp = 0,        -- Last update timestamp
--     throttleTimer = nil   -- Active throttle timer
--   }
-- }
local searchStates = {}

--============================================================================
-- CONSTANTS
--============================================================================

local THROTTLE_DELAY = 0.3  -- 300ms throttle (matches existing search boxes)

--============================================================================
-- PRIVATE HELPERS
--============================================================================

-- Flexible validation: accept any non-empty string
-- Supports main tabs (items, currency) and sub-tabs (plans_mount, plans_achievement)
local function ValidateTabId(tabId)
    if not tabId or type(tabId) ~= "string" or tabId == "" then
        print("[SearchStateManager] ERROR: Invalid tab ID:", tostring(tabId))
        return false
    end
    return true
end

local function GetOrCreateState(tabId)
    if not searchStates[tabId] then
        searchStates[tabId] = {
            query = "",
            resultCount = 0,
            isEmpty = false,
            timestamp = GetTime(),
            throttleTimer = nil
        }
    end
    return searchStates[tabId]
end

local function FireStateChangedEvent(tabId)
    local state = searchStates[tabId]
    if not state then return end
    
    -- Fire event for UI consumption
    AceEvent:SendMessage("WN_SEARCH_STATE_CHANGED", {
        tabId = tabId,
        searchText = state.query,
        resultCount = state.resultCount,
        isEmpty = state.isEmpty,
        timestamp = state.timestamp
    })
end

--============================================================================
-- PUBLIC API
--============================================================================

local SearchStateManager = {}

--[[
    Set search query for a tab (throttled)
    @param tabId string - Tab identifier (e.g., "items", "currency")
    @param searchText string - Search query text
]]
function SearchStateManager:SetSearchQuery(tabId, searchText)
    if not ValidateTabId(tabId) then return end
    
    local state = GetOrCreateState(tabId)
    local normalizedQuery = (searchText or ""):lower()
    
    -- Cancel previous throttle timer
    if state.throttleTimer then
        state.throttleTimer:Cancel()
        state.throttleTimer = nil
    end
    
    -- Update query immediately (for instant UI feedback)
    state.query = normalizedQuery
    state.timestamp = GetTime()
    
    -- Fire immediate query update event (for search box display)
    AceEvent:SendMessage("WN_SEARCH_QUERY_UPDATED", {
        tabId = tabId,
        searchText = normalizedQuery
    })
    
    -- Throttle the actual search execution
    state.throttleTimer = C_Timer.NewTimer(THROTTLE_DELAY, function()
        state.throttleTimer = nil
        FireStateChangedEvent(tabId)
    end)
end

--[[
    Get current search state for a tab
    @param tabId string - Tab identifier
    @return table - {query, isEmpty, resultCount, timestamp} or nil if invalid
]]
function SearchStateManager:GetSearchState(tabId)
    if not ValidateTabId(tabId) then return nil end
    
    local state = GetOrCreateState(tabId)
    
    -- Return copy to prevent external modification
    return {
        query = state.query,
        isEmpty = state.isEmpty,
        resultCount = state.resultCount,
        timestamp = state.timestamp
    }
end

--[[
    Update result count after UI has rendered
    Called by Draw functions after rendering is complete
    @param tabId string - Tab identifier
    @param resultCount number - Number of results rendered
]]
function SearchStateManager:UpdateResults(tabId, resultCount)
    if not ValidateTabId(tabId) then return end
    
    local state = GetOrCreateState(tabId)
    state.resultCount = resultCount or 0
    state.isEmpty = state.resultCount == 0
    state.timestamp = GetTime()
    
    -- No event fire here - this is called AFTER rendering
    -- UI already has the results, this just updates internal state
end

--[[
    Clear search for a tab
    @param tabId string - Tab identifier
]]
function SearchStateManager:ClearSearch(tabId)
    if not ValidateTabId(tabId) then return end
    
    local state = GetOrCreateState(tabId)
    
    -- Cancel throttle timer
    if state.throttleTimer then
        state.throttleTimer:Cancel()
        state.throttleTimer = nil
    end
    
    -- Reset state
    state.query = ""
    state.resultCount = 0
    state.isEmpty = false
    state.timestamp = GetTime()
    
    -- Fire event to update UI
    FireStateChangedEvent(tabId)
end

--[[
    Check if a tab has an active search
    @param tabId string - Tab identifier
    @return boolean - True if search query is not empty
]]
function SearchStateManager:HasActiveSearch(tabId)
    if not ValidateTabId(tabId) then return false end
    
    local state = searchStates[tabId]
    return state and state.query ~= ""
end

--[[
    Get search query for a tab (convenience method)
    @param tabId string - Tab identifier
    @return string - Search query (lowercase) or empty string
]]
function SearchStateManager:GetQuery(tabId)
    if not ValidateTabId(tabId) then return "" end
    
    local state = searchStates[tabId]
    return state and state.query or ""
end

--[[
    Debug: Print current state for all tabs
]]
function SearchStateManager:DebugPrintStates()
    print("[SearchStateManager] Current States:")
    for tabId, state in pairs(searchStates) do
        print(string.format("  %s: query='%s', count=%d, empty=%s",
            tabId, state.query, state.resultCount, tostring(state.isEmpty)))
    end
end

--============================================================================
-- INITIALIZATION
--============================================================================

-- Expose to namespace
ns.SearchStateManager = SearchStateManager

-- Debug command
SLASH_WNSEARCHDEBUG1 = "/wnsearchdebug"
SlashCmdList["WNSEARCHDEBUG"] = function()
    SearchStateManager:DebugPrintStates()
end
