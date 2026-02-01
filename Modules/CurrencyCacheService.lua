--[[
    Warband Nexus - Currency Cache Service
    
    Persistent DB-backed currency cache with event-driven updates.
    Follows CollectionService/ReputationCacheService pattern.
    
    Provides:
    1. DB-backed persistent cache (survives /reload)
    2. Event-driven incremental updates (no full API scans)
    3. Per-character currency tracking
    4. Warband-wide currency tracking
    5. Real-time updates when currency changes
    6. Optimized C_CurrencyInfo API usage
    
    Events monitored:
    - CURRENCY_DISPLAY_UPDATE: Standard currency changes
    - PLAYER_MONEY: Gold changes
    
    Cache structure:
    {
      currencies = {
        [charKey] = {
          [currencyID] = {
            name, quantity, icon, maxQuantity,
            isAccountWide, isAccountTransferable,
            description, quality
          }
        }
      },
      warband = {
        [currencyID] = total_quantity  -- Warband-wide totals
      },
      version = "1.0.0",
      lastUpdate = timestamp
    }
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local CACHE_VERSION = Constants.CURRENCY_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.CURRENCY_UPDATE

-- ============================================================================
-- CURRENCY CACHE (PERSISTENT IN DB)
-- ============================================================================

local currencyCache = {
    currencies = {},    -- Per-character currency data
    warband = {},       -- Warband-wide totals
    version = CACHE_VERSION,
    lastUpdate = 0,
}

local updateThrottleTimer = nil

-- ============================================================================
-- CACHE INITIALIZATION (Load from DB)
-- ============================================================================

---Initialize currency cache from DB (load persisted data)
---Called on addon load to restore previous cache
function WarbandNexus:InitializeCurrencyCache()
    -- Initialize DB structure if needed
    if not self.db.global.currencyCache then
        self.db.global.currencyCache = {
            currencies = {},
            warband = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
        print("|cff9370DB[WN CurrencyCache]|r Initialized empty currency cache in DB")
        return
    end
    
    -- Load from DB
    local dbCache = self.db.global.currencyCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        print("|cffffcc00[WN CurrencyCache]|r Cache version mismatch (DB: " .. tostring(dbCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
        self.db.global.currencyCache = {
            currencies = {},
            warband = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
        return
    end
    
    -- Load currencies cache from DB to RAM
    currencyCache.currencies = dbCache.currencies or {}
    currencyCache.warband = dbCache.warband or {}
    currencyCache.lastUpdate = dbCache.lastUpdate or 0
    
    -- Count loaded currencies
    local charCount = 0
    local currencyCount = 0
    for charKey, currencies in pairs(currencyCache.currencies) do
        charCount = charCount + 1
        for _ in pairs(currencies) do
            currencyCount = currencyCount + 1
        end
    end
    
    if currencyCount > 0 then
        local age = time() - currencyCache.lastUpdate
        print("|cff00ff00[WN CurrencyCache]|r Loaded " .. currencyCount .. " currencies across " .. charCount .. " characters from DB (age: " .. age .. "s)")
    else
        print("|cff9370DB[WN CurrencyCache]|r No cached currency data, will populate on first update")
    end
end

---Save currency cache to DB (persist to SavedVariables)
---@param reason string Optional reason for save (for debugging)
---@param incrementalCount number Optional: number of currencies updated (for incremental updates)
local function SaveCurrencyCache(reason, incrementalCount)
    if not WarbandNexus.db or not WarbandNexus.db.global then
        print("|cffff0000[WN CurrencyCache]|r Cannot save: DB not initialized")
        return
    end
    
    currencyCache.lastUpdate = time()
    
    WarbandNexus.db.global.currencyCache = {
        currencies = currencyCache.currencies,
        warband = currencyCache.warband,
        version = CACHE_VERSION,
        lastUpdate = currencyCache.lastUpdate
    }
    
    -- Count total currencies in cache
    local charCount = 0
    local totalCurrencyCount = 0
    for _, currencies in pairs(currencyCache.currencies) do
        charCount = charCount + 1
        for _ in pairs(currencies) do
            totalCurrencyCount = totalCurrencyCount + 1
        end
    end
    
    local reasonStr = reason and (" (" .. reason .. ")") or ""
    
    -- Show different messages for incremental vs full updates
    if incrementalCount and incrementalCount < totalCurrencyCount then
        print("|cff00ff00[WN CurrencyCache]|r Updated " .. incrementalCount .. " currency (total: " .. totalCurrencyCount .. " in cache)" .. reasonStr)
    else
        print("|cff00ff00[WN CurrencyCache]|r Saved " .. totalCurrencyCount .. " currencies (" .. charCount .. " chars) to DB" .. reasonStr)
    end
end

-- ============================================================================
-- CURRENCY DATA RETRIEVAL
-- ============================================================================

---Get currency data for a specific currency
---@param currencyID number Currency ID
---@return table|nil Currency data or nil if not found
local function GetCurrencyData(currencyID)
    if not currencyID or currencyID == 0 then return nil end
    if not C_CurrencyInfo then return nil end
    
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info or not info.name then return nil end
    
    local data = {
        currencyID = currencyID,
        name = info.name,
        quantity = info.quantity or 0,
        icon = info.iconFileID,
        maxQuantity = info.maxQuantity or 0,
        isAccountWide = info.isAccountWide or false,
        isAccountTransferable = info.isAccountTransferable or false,
        description = info.description or "",
        quality = info.quality or 1,
        useTotalEarnedForMaxQty = info.useTotalEarnedForMaxQty or false,
    }
    
    return data
end

---Update a single currency in cache for current character
---@param currencyID number Currency ID to update
---@return boolean success True if updated successfully
local function UpdateCurrencyInCache(currencyID)
    if not currencyID or currencyID == 0 then return false end
    if not ns.Utilities or not ns.Utilities.GetCharacterKey then return false end
    
    local currencyData = GetCurrencyData(currencyID)
    if not currencyData then
        return false
    end
    
    local charKey = ns.Utilities:GetCharacterKey()
    if not charKey then return false end
    
    -- Initialize character cache if needed
    if not currencyCache.currencies[charKey] then
        currencyCache.currencies[charKey] = {}
    end
    
    -- Store in cache
    currencyCache.currencies[charKey][currencyID] = currencyData
    
    -- Update warband total if account-wide
    if currencyData.isAccountWide then
        currencyCache.warband[currencyID] = currencyData.quantity
    end
    
    return true
end

---Update all currencies in cache for current character (full refresh)
---@param saveToDb boolean Whether to save to DB after update
local function UpdateAllCurrencies(saveToDb)
    if not C_CurrencyInfo then
        print("|cffff0000[WN CurrencyCache]|r C_CurrencyInfo not available")
        return
    end
    
    local updatedCount = 0
    local startTime = debugprofilestop()
    
    -- Expand all currency categories first (critical!)
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and info.isHeader and not info.isHeaderExpanded then
            C_CurrencyInfo.ExpandCurrencyList(i, true)
        end
    end
    
    -- Get currency list size AFTER expansion
    local listSize = C_CurrencyInfo.GetCurrencyListSize()
    
    -- Scan all currencies
    local maxIterations = 5000  -- Safety limit (TWW has many currencies)
    local actualListSize = math.min(listSize, maxIterations)
    
    for i = 1, actualListSize do
        local listInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
        
        if listInfo and not listInfo.isHeader then
            -- Get currency ID
            local currencyID = nil
            
            -- Method 1: From link (most reliable)
            local currencyLink = C_CurrencyInfo.GetCurrencyListLink(i)
            if currencyLink then
                currencyID = tonumber(currencyLink:match("currency:(%d+)"))
            end
            
            -- Method 2: Fallback to name lookup (less reliable)
            if not currencyID and listInfo.name then
                -- Try to match by name (fragile, but better than nothing)
                currencyID = listInfo.currencyID or listInfo.currencyTypesID
            end
            
            if currencyID and currencyID > 0 then
                if UpdateCurrencyInCache(currencyID) then
                    updatedCount = updatedCount + 1
                end
            end
        end
    end
    
    -- Warn if we hit safety limit
    if listSize > maxIterations then
        print("|cffff0000[WN CurrencyCache]|r WARNING: Currency list size (" .. listSize .. ") exceeds safety limit (" .. maxIterations .. ")")
    end
    
    local elapsed = debugprofilestop() - startTime
    print("|cffffff00[WN CurrencyCache]|r FULL UPDATE: Scanned " .. updatedCount .. " currencies (" .. string.format("%.2f", elapsed) .. "ms)")
    
    if saveToDb and updatedCount > 0 then
        SaveCurrencyCache("full update")
    end
    
    -- Fire event for UI updates
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WARBAND_CURRENCIES_UPDATED", updatedCount)
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

---Handle CURRENCY_DISPLAY_UPDATE event (throttled)
---@param currencyType number|nil Currency type (may be nil)
---@param quantity number|nil New quantity (may be nil)
local function OnCurrencyUpdate(currencyType, quantity)
    -- Cancel previous throttle timer
    if updateThrottleTimer then
        updateThrottleTimer:Cancel()
    end
    
    -- Throttle updates (currency can change rapidly)
    updateThrottleTimer = C_Timer.NewTimer(UPDATE_THROTTLE, function()
        if currencyType and currencyType > 0 then
            -- Update specific currency (INCREMENTAL)
            print("|cff00ffff[WN CurrencyCache]|r Incremental update for currency " .. currencyType)
            if UpdateCurrencyInCache(currencyType) then
                SaveCurrencyCache("currency update: " .. tostring(currencyType), 1)  -- Pass 1 for incremental count
                
                -- Fire event for UI updates
                if WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage("WARBAND_CURRENCIES_UPDATED", currencyType)
                end
            end
        else
            -- Full update (no specific currency type)
            print("|cffffff00[WN CurrencyCache]|r Full update triggered (no specific currency ID)")
            UpdateAllCurrencies(true)
        end
        
        updateThrottleTimer = nil
    end)
end

---Handle PLAYER_MONEY event (gold changes)
local function OnMoneyUpdate()
    -- Gold is tracked separately, no need to update currency cache
    -- Just fire event for UI updates
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WARBAND_GOLD_UPDATED")
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

---Get currency data for a specific currency (from cache or live)
---@param currencyID number Currency ID
---@param charKey string|nil Character key (defaults to current character)
---@return table|nil Currency data
function WarbandNexus:GetCurrencyData(currencyID, charKey)
    if not currencyID or currencyID == 0 then return nil end
    
    -- Use current character if not specified
    if not charKey and ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    if not charKey then return nil end
    
    -- Return from cache if available
    if currencyCache.currencies[charKey] and currencyCache.currencies[charKey][currencyID] then
        return currencyCache.currencies[charKey][currencyID]
    end
    
    -- Cache miss - fetch live and cache it (only for current character)
    if charKey == (ns.Utilities and ns.Utilities:GetCharacterKey()) then
        local currencyData = GetCurrencyData(currencyID)
        if currencyData then
            if not currencyCache.currencies[charKey] then
                currencyCache.currencies[charKey] = {}
            end
            currencyCache.currencies[charKey][currencyID] = currencyData
        end
        return currencyData
    end
    
    return nil
end

---Get all cached currency data for a character
---@param charKey string|nil Character key (defaults to current character)
---@return table Cached currencies
function WarbandNexus:GetAllCurrencyData(charKey)
    if not charKey and ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    if not charKey then return {} end
    
    return currencyCache.currencies[charKey] or {}
end

---Get warband-wide currency totals
---@return table Warband currency totals
function WarbandNexus:GetWarbandCurrencyTotals()
    return currencyCache.warband
end

---Get all currencies in LEGACY format (for backward compatibility with UI)
---Returns currency data in the old db.global.currencies format
---@return table Currency data in legacy format { [currencyID] = { name, icon, value, chars = {...} } }
function WarbandNexus:GetCurrenciesLegacyFormat()
    local result = {}
    local allCharacterKeys = {}
    
    -- Collect all character keys
    for charKey in pairs(currencyCache.currencies) do
        table.insert(allCharacterKeys, charKey)
    end
    
    -- Build currency lookup: [currencyID] = { charKey -> quantity }
    local currencyLookup = {}
    
    for charKey, currencies in pairs(currencyCache.currencies) do
        for currencyID, currencyData in pairs(currencies) do
            if not currencyLookup[currencyID] then
                currencyLookup[currencyID] = {
                    metadata = currencyData,  -- Store metadata from first occurrence
                    charQuantities = {}
                }
            end
            
            -- Store character quantity
            currencyLookup[currencyID].charQuantities[charKey] = currencyData.quantity or 0
        end
    end
    
    -- Convert to legacy format
    for currencyID, data in pairs(currencyLookup) do
        local metadata = data.metadata
        local legacy = {
            name = metadata.name,
            icon = metadata.icon,
            maxQuantity = metadata.maxQuantity or 0,
            expansion = metadata.expansion or "Other",
            category = metadata.category or "Currency",
            season = metadata.season,
            isAccountWide = metadata.isAccountWide or false,
            isAccountTransferable = metadata.isAccountTransferable or false,
        }
        
        if legacy.isAccountWide then
            -- Account-wide: use warband total
            legacy.value = currencyCache.warband[currencyID] or metadata.quantity or 0
            legacy.chars = nil
        else
            -- Character-specific: use chars table
            legacy.value = nil
            legacy.chars = data.charQuantities
        end
        
        result[currencyID] = legacy
    end
    
    return result
end

---Manually refresh currency cache (useful for UI refresh buttons)
function WarbandNexus:RefreshCurrencyCache()
    print("|cff9370DB[WN CurrencyCache]|r Manual cache refresh requested")
    UpdateAllCurrencies(true)
end

---Clear currency cache (for testing/debugging)
function WarbandNexus:ClearCurrencyCache()
    currencyCache.currencies = {}
    currencyCache.warband = {}
    currencyCache.lastUpdate = 0
    
    if self.db and self.db.global then
        self.db.global.currencyCache = {
            currencies = {},
            warband = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
    end
    
    print("|cffffcc00[WN CurrencyCache]|r Cache cleared")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Register currency cache events
function WarbandNexus:RegisterCurrencyCacheEvents()
    -- Register events via EventManager (AceEvent style)
    -- EventManager is self (WarbandNexus) with AceEvent mixed in
    if self.RegisterEvent then
        self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", function(event, currencyType, quantity)
            -- Use incremental update (only update the changed currency)
            OnCurrencyUpdate(currencyType, quantity)
        end)
        
        self:RegisterEvent("PLAYER_MONEY", function(event)
            -- Money changes don't need currency scan
            OnMoneyUpdate()
        end)
        
        print("|cff00ff00[WN CurrencyCache]|r Event handlers registered (incremental updates enabled)")
    else
        print("|cffff0000[WN CurrencyCache]|r EventManager not available, cannot register events")
    end
    
    -- Initial population (delayed to ensure UI is ready)
    C_Timer.After(2.5, function()
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
        if charKey and (not currencyCache.currencies[charKey] or currencyCache.lastUpdate == 0) then
            print("|cff9370DB[WN CurrencyCache]|r Performing INITIAL cache population (full scan required)")
            UpdateAllCurrencies(true)
        else
            print("|cff00ff00[WN CurrencyCache]|r Cache already populated, skipping initial scan")
        end
    end)
end

print("|cff00ff00[WN CurrencyCache]|r Service loaded successfully")
