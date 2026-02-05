--[[
    Warband Nexus - Currency Cache Service (v2.0 - Direct DB Architecture)
    
    ARCHITECTURE: Direct AceDB - No RAM cache (Follows Reputation pattern)
    
    New Architecture:
    - All operations work DIRECTLY on WarbandNexus.db.global.currencyData
    - No intermediate RAM layer
    - AceDB handles persistence automatically
    - Atomic updates prevent data loss
    
    DB Structure:
    {
      version = "2.0.0",
      lastScan = timestamp,
      currencies = {
        [charKey] = {
          [currencyID] = {
            name, quantity, icon, maxQuantity,
            isAccountWide, isAccountTransferable,
            description, quality, _scanTime
          }
        }
      }
    }
    
    Events monitored:
    - CURRENCY_DISPLAY_UPDATE: Standard currency changes
    - PLAYER_MONEY: Gold changes
    
    Architecture: API → DB (Direct) → Event → UI
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import dependencies
local Constants = ns.Constants

-- Debug print helper
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print("|cff00ffff[CurrencyCache]|r", ...)
    end
end

-- ============================================================================
-- STATE (Minimal - No RAM cache)
-- ============================================================================

local CurrencyCache = {
    -- Metadata only (no data storage)
    version = "2.0.0",
    lastFullScan = 0,
    lastUpdate = 0,
    
    -- Throttle timers
    fullScanThrottle = nil,
    updateThrottle = nil,
    
    -- Flags
    isInitialized = false,
    isScanning = false,
}

-- Loading state for UI (similar to ReputationLoadingState pattern)
ns.CurrencyLoadingState = ns.CurrencyLoadingState or {
    isLoading = false,
    loadingProgress = 0,
    currentStage = "Preparing...",
}

-- ============================================================================
-- DB ACCESS (Direct - No RAM cache)
-- ============================================================================

---Get direct reference to currency DB
---@return table|nil DB reference
local function GetDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    
    -- Initialize structure if needed
    if not WarbandNexus.db.global.currencyData then
        WarbandNexus.db.global.currencyData = {
            version = CurrencyCache.version,
            lastScan = 0,
            currencies = {},
            headers = {},  -- Blizzard currency headers structure
        }
    end
    
    return WarbandNexus.db.global.currencyData
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize currency cache (validates DB structure, does NOT clear data)
function WarbandNexus:InitializeCurrencyCache()
    if CurrencyCache.isInitialized then
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[Currency]|r ERROR: Cannot initialize - DB not ready")
        return
    end
    
    -- Load metadata
    CurrencyCache.lastFullScan = db.lastScan or 0
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Count existing data
    local charCounts = {}
    local currentCharCount = 0
    
    for charKey, charCurrencies in pairs(db.currencies) do
        local count = 0
        for _ in pairs(charCurrencies) do
            count = count + 1
        end
        charCounts[charKey] = count
        if charKey == currentCharKey then
            currentCharCount = count
        end
    end
    
    local totalCount = 0
    for _, count in pairs(charCounts) do
        totalCount = totalCount + count
    end
    
    -- Determine if scan is needed
    local needsScan = false
    local scanReason = ""
    
    if totalCount == 0 then
        needsScan = true
        scanReason = "No data in DB"
    elseif currentCharCount == 0 then
        needsScan = true
        scanReason = "Current character (" .. currentCharKey .. ") has no data"
    else
        -- Check for version mismatch
        local dbVersion = db.version
        if dbVersion ~= CurrencyCache.version then
            needsScan = true
            scanReason = string.format("Version mismatch (DB: %s, Current: %s)", tostring(dbVersion), tostring(CurrencyCache.version))
        else
            local age = time() - CurrencyCache.lastFullScan
            local MAX_CACHE_AGE = 3600  -- 1 hour
            if age > MAX_CACHE_AGE then
                needsScan = true
                scanReason = string.format("Cache is old (%d seconds)", age)
            end
        end
    end
    
    if totalCount > 0 then
        DebugPrint(string.format("[Currency] Loaded %d currencies from DB", totalCount))
        for charKey, charCount in pairs(charCounts) do
            local marker = (charKey == currentCharKey) and " (current)" or ""
            DebugPrint(string.format("[Currency]   %s: %d currencies%s", charKey, charCount, marker))
        end
    end
    
    if needsScan then
        DebugPrint("[Currency] " .. scanReason .. ", scheduling scan...")
        
        -- Set loading state for UI
        ns.CurrencyLoadingState.isLoading = true
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Waiting for API..."
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
        end
        
        -- Delay scan to ensure API is ready (especially important for new characters)
        C_Timer.After(5, function()
            if CurrencyCache then
                DebugPrint("[Currency] Starting initial scan...")
                CurrencyCache:PerformFullScan(true)  -- bypass throttle for initial scan
            end
        end)
    else
        -- Fire ready event immediately (data exists and is fresh)
        C_Timer.After(0.1, function()
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_CURRENCY_CACHE_READY")
            end
        end)
    end
    
    -- Register event listeners for real-time updates
    self:RegisterCurrencyCacheEvents()
    
    CurrencyCache.isInitialized = true
    DebugPrint("|cff00ff00[Currency]|r Initialized")
end

-- ============================================================================
-- CURRENCY DATA RETRIEVAL (Direct from API)
-- ============================================================================

---Fetch currency data from WoW API
---@param currencyID number Currency ID
---@return table|nil Currency data or nil if not found
local function FetchCurrencyFromAPI(currencyID)
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
        _scanTime = time(),
    }
    
    return data
end

-- ============================================================================
-- UPDATE OPERATIONS (Direct DB)
-- ============================================================================

---Update a single currency in DB for current character
---@param currencyID number Currency ID to update
---@return boolean success True if updated successfully
local function UpdateSingleCurrency(currencyID)
    if not currencyID or currencyID == 0 then return false end
    
    local db = GetDB()
    if not db then return false end
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey()
    if not charKey then return false end
    
    -- Initialize character entry if needed
    if not db.currencies[charKey] then
        db.currencies[charKey] = {}
    end
    
    -- Snapshot old value for gain detection
    local oldData = db.currencies[charKey][currencyID]
    local oldQuantity = oldData and oldData.quantity or 0
    
    -- Fetch new data from API
    local currencyData = FetchCurrencyFromAPI(currencyID)
    if not currencyData then
        return false
    end
    
    -- Store directly in DB (no RAM cache)
    db.currencies[charKey][currencyID] = currencyData
    
    -- Update metadata
    CurrencyCache.lastUpdate = time()
    db.lastScan = CurrencyCache.lastUpdate
    
    DebugPrint(string.format("Updated currency %s (%d)", currencyData.name, currencyID))
    
    -- Check for gain and fire notification event
    local newQuantity = currencyData.quantity or 0
    if newQuantity > oldQuantity then
        local gainAmount = newQuantity - oldQuantity
        
        print(string.format("|cffff00ff[DEBUG]|r Currency gained: %s +%d", currencyData.name, gainAmount))
        
        -- Fire currency gain event
        if WarbandNexus.SendMessage then
            print("|cffff00ff[DEBUG]|r Firing WN_CURRENCY_GAINED event")
            WarbandNexus:SendMessage("WN_CURRENCY_GAINED", {
                currencyID = currencyID,
                currencyName = currencyData.name,
                gainAmount = gainAmount,
                currentQuantity = newQuantity,
                maxQuantity = currencyData.maxQuantity,
                iconFileID = currencyData.iconFileID,
            })
        end
    end
    
    return true
end

---Perform full scan of all currencies (Direct DB architecture)
function CurrencyCache:PerformFullScan(bypassThrottle)
    if not C_CurrencyInfo then
        print("|cffff0000[Currency]|r ERROR: C_CurrencyInfo not available")
        return
    end
    
    -- Throttle check
    if not bypassThrottle then
        local now = time()
        local timeSinceLastScan = now - self.lastFullScan
        local MIN_SCAN_INTERVAL = 5  -- 5 seconds
        
        if timeSinceLastScan < MIN_SCAN_INTERVAL then
            DebugPrint(string.format("Scan throttled (%.1fs since last scan)", timeSinceLastScan))
            return
        end
    end
    
    if self.isScanning then
        DebugPrint("Scan already in progress, skipping...")
        return
    end
    
    self.isScanning = true
    
    -- Set loading state for UI
    ns.CurrencyLoadingState.isLoading = true
    ns.CurrencyLoadingState.loadingProgress = 0
    ns.CurrencyLoadingState.currentStage = "Fetching currency data..."
    
    -- Trigger UI refresh to show loading state
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
    end
    
    DebugPrint("[Currency] Starting full scan...")
    
    -- Expand all currency categories first
    local listSize = C_CurrencyInfo.GetCurrencyListSize()
    for i = 1, listSize do
        local info = C_CurrencyInfo.GetCurrencyListInfo(i)
        if info and info.isHeader and not info.isHeaderExpanded then
            C_CurrencyInfo.ExpandCurrencyList(i, true)
        end
    end
    
    -- Get currency list size AFTER expansion
    listSize = C_CurrencyInfo.GetCurrencyListSize()
    
    if listSize == 0 then
        print("|cffff0000[Currency]|r Scan returned no data (API not ready?) - retrying in 5 seconds...")
        self.isScanning = false
        
        -- Keep loading state active (don't clear it)
        ns.CurrencyLoadingState.currentStage = "Waiting for API... (retrying)"
        
        -- Trigger UI refresh to show retry message
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
        end
        
        -- Retry after delay
        C_Timer.After(5, function()
            if CurrencyCache then
                DebugPrint("[Currency] Retrying scan...")
                CurrencyCache:PerformFullScan(true)
            end
        end)
        return
    end
    
    -- Update progress
    ns.CurrencyLoadingState.loadingProgress = 20
    ns.CurrencyLoadingState.currentStage = string.format("Processing %d currencies...", listSize)
    
    -- Build header structure and collect currencies
    local currencyDataArray = {}
    local headerStructure = {}
    local currentHeader = nil
    local lastDepth = -1
    
    local maxIterations = 5000  -- Safety limit
    local actualListSize = math.min(listSize, maxIterations)
    local updateInterval = math.max(10, math.floor(actualListSize / 10))
    
    -- First pass: Scan and detect depth by indentation/hierarchy
    local listItems = {}
    for i = 1, actualListSize do
        local listInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
        if listInfo then
            table.insert(listItems, {
                index = i,
                info = listInfo,
                isHeader = listInfo.isHeader or false
            })
        end
    end
    
    -- Second pass: Build structure and collect currencies
    for idx, item in ipairs(listItems) do
        local i = item.index
        local listInfo = item.info
        
        if listInfo.isHeader then
            -- Simple depth detection: assume all headers are root level (depth 0)
            -- We'll build hierarchy later based on spacing/indentation in game
            local depth = 0
            
            -- Create header
            local headerData = {
                name = listInfo.name,
                isExpanded = listInfo.isHeaderExpanded,
                depth = depth,
                currencies = {},
                children = {}
            }
            
            listItems[idx].depth = depth
            listItems[idx].headerData = headerData
            
            -- Add as root header
            table.insert(headerStructure, headerData)
            currentHeader = headerData
            
        else
            -- This is a currency
            local currencyID = nil
            
            -- Method 1: From link (most reliable)
            local currencyLink = C_CurrencyInfo.GetCurrencyListLink(i)
            if currencyLink then
                currencyID = tonumber(currencyLink:match("currency:(%d+)"))
            end
            
            -- Method 2: Fallback to currencyID field
            if not currencyID and listInfo.currencyID then
                currencyID = listInfo.currencyID
            end
            
            if currencyID and currencyID > 0 then
                local currencyData = FetchCurrencyFromAPI(currencyID)
                if currencyData then
                    table.insert(currencyDataArray, currencyData)
                    
                    -- Find parent header (last header before this currency)
                    for j = idx - 1, 1, -1 do
                        if listItems[j].isHeader and listItems[j].headerData then
                            table.insert(listItems[j].headerData.currencies, currencyID)
                            break
                        end
                    end
                end
            end
        end
        
        -- Update progress
        if idx % updateInterval == 0 then
            local progress = 20 + math.floor((idx / #listItems) * 50)  -- 20-70%
            ns.CurrencyLoadingState.loadingProgress = progress
            ns.CurrencyLoadingState.currentStage = string.format("Processing... (%d/%d)", idx, #listItems)
            
            -- Trigger UI refresh to show progress updates
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
            end
        end
    end
    
    -- Note: We're treating all headers as root-level for simplicity
    -- Blizzard's API doesn't provide explicit depth information
    -- The UI will render them sequentially as they appear in the list
    
    -- Save header structure to DB
    local db = GetDB()
    if db then
        db.headers = headerStructure
        DebugPrint(string.format("|cff00ff00[Currency]|r Built header structure with %d root headers", #headerStructure))
    end
    
    -- Update DB
    ns.CurrencyLoadingState.loadingProgress = 70
    ns.CurrencyLoadingState.currentStage = "Saving to database..."
    self:UpdateAll(currencyDataArray)
    
    -- Complete - clear loading state immediately
    ns.CurrencyLoadingState.isLoading = false
    ns.CurrencyLoadingState.loadingProgress = 100
    ns.CurrencyLoadingState.currentStage = "Complete!"
    
    self.isScanning = false
    
    DebugPrint(string.format("|cff00ff00[Currency]|r Scan complete - %d currencies", #currencyDataArray))
    
    -- Fire cache ready event (will trigger UI refresh)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CURRENCY_CACHE_READY")
        WarbandNexus:SendMessage("WN_CURRENCY_UPDATED")
    end
end

---Update all currencies in DB (Direct DB write)
---@param currencyDataArray table Array of currency data
---@return boolean success
function CurrencyCache:UpdateAll(currencyDataArray)
    if not currencyDataArray or #currencyDataArray == 0 then
        DebugPrint("ERROR: No data to update")
        return false
    end
    
    local db = GetDB()
    if not db then
        DebugPrint("ERROR: DB not initialized")
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- CRITICAL: Clear ONLY current character's data (preserve other characters)
    if not db.currencies[currentCharKey] then
        db.currencies[currentCharKey] = {}
    else
        wipe(db.currencies[currentCharKey])
    end
    
    -- Write data to DB
    local currencyCount = 0
    
    for _, data in ipairs(currencyDataArray) do
        if data.currencyID then
            -- Store directly in DB (no RAM cache)
            db.currencies[currentCharKey][data.currencyID] = data
            currencyCount = currencyCount + 1
        end
    end
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    db.lastScan = self.lastFullScan
    db.version = self.version
    
    DebugPrint(string.format("[Currency] Updated: %d currencies (%s)", currencyCount, currentCharKey))
    
    return true
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

-- ============================================================================
-- EVENT HANDLERS (Direct DB)
-- ============================================================================

---Handle CURRENCY_DISPLAY_UPDATE event (incremental update)
---@param currencyType number|nil Currency type/ID
---@param quantity number|nil New quantity
local function OnCurrencyUpdate(currencyType, quantity)
    -- Cancel previous throttle timer
    if CurrencyCache.updateThrottle then
        CurrencyCache.updateThrottle:Cancel()
    end
    
    -- Throttle updates (0.5s)
    CurrencyCache.updateThrottle = C_Timer.NewTimer(0.5, function()
        if currencyType and currencyType > 0 then
            -- Incremental update (single currency)
            DebugPrint("CURRENCY_DISPLAY_UPDATE event - updating currency " .. currencyType)
            
            if UpdateSingleCurrency(currencyType) then
                -- Fire event for UI updates
                if WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage("WN_CURRENCY_UPDATED", currencyType)
                end
            end
        else
            -- Full scan (no specific currency)
            DebugPrint("CURRENCY_DISPLAY_UPDATE event - no currency ID, performing full scan")
            CurrencyCache:PerformFullScan()
        end
        
        CurrencyCache.updateThrottle = nil
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
-- PUBLIC API (Direct DB Access)
-- ============================================================================

---Get currency data for a specific currency (from DB)
---@param currencyID number Currency ID
---@param charKey string|nil Character key (defaults to current character)
---@return table|nil Currency data
function WarbandNexus:GetCurrencyData(currencyID, charKey)
    if not currencyID or currencyID == 0 then return nil end
    
    local db = GetDB()
    if not db then return nil end
    
    -- Use current character if not specified
    if not charKey and ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    if not charKey then return nil end
    
    -- Return from DB
    if db.currencies[charKey] and db.currencies[charKey][currencyID] then
        return db.currencies[charKey][currencyID]
    end
    
    -- Cache miss - fetch live and store it (only for current character)
    if charKey == (ns.Utilities and ns.Utilities:GetCharacterKey()) then
        local currencyData = FetchCurrencyFromAPI(currencyID)
        if currencyData then
            if not db.currencies[charKey] then
                db.currencies[charKey] = {}
            end
            db.currencies[charKey][currencyID] = currencyData
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
    local db = GetDB()
    if not db then return {} end
    
    local result = {}
    local currencyLookup = {}
    
    -- Build currency lookup: [currencyID] = { charKey -> quantity }
    for charKey, currencies in pairs(db.currencies) do
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
            -- Account-wide: calculate total from all characters
            local total = 0
            for _, qty in pairs(data.charQuantities) do
                total = total + qty
            end
            legacy.value = total
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

---Manually trigger currency scan
function WarbandNexus:ScanCurrencies()
    CurrencyCache:PerformFullScan(false)
end

---Clear currency cache for current character
function WarbandNexus:ClearCurrencyCache()
    CurrencyCache:Clear(true)
end

---Clear currency data for current character only
---@param clearDB boolean Also clear SavedVariables
function CurrencyCache:Clear(clearDB)
    DebugPrint("[Currency] Clearing currency data...")
    
    if clearDB then
        local db = GetDB()
        if db then
            -- Get current character key
            local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
            
            -- IMPORTANT: Only clear CURRENT character's currency data
            if db.currencies and db.currencies[currentCharKey] then
                wipe(db.currencies[currentCharKey])
                print("|cff00ff00[Currency]|r Cleared currency data for: " .. currentCharKey)
            else
                print("|cffffcc00[Currency]|r No data to clear for: " .. currentCharKey)
            end
            
            -- Reset scan time for current character only
            db.lastScan = 0
        end
    end
    
    -- Reset metadata
    self.lastFullScan = 0
    self.lastUpdate = 0
    self.isScanning = false
    
    -- Fire events
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CURRENCY_CACHE_CLEARED")
    end
    
    -- Automatically start rescan after clearing
    if clearDB then
        -- Set loading state for UI
        ns.CurrencyLoadingState.isLoading = true
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Preparing..."
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
        end
        
        DebugPrint("[Currency] Starting automatic rescan in 1 second...")
        C_Timer.After(1, function()
            if CurrencyCache then
                CurrencyCache:PerformFullScan(true)  -- bypass throttle since we just cleared
            end
        end)
    else
        -- Clear loading state if not rescanning
        ns.CurrencyLoadingState.isLoading = false
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Preparing..."
    end
end

-- ============================================================================
-- EVENT REGISTRATION
-- ============================================================================

---Register currency cache events
function WarbandNexus:RegisterCurrencyCacheEvents()
    if not self.RegisterEvent then
        DebugPrint("|cffff0000[Currency]|r EventManager not available")
        return
    end
    
    -- PRIMARY: Listen for currency changes via chat message (most reliable)
    local currencyChatFilter = function(self, event, message, ...)
        -- Trigger currency scan (throttled)
        if CurrencyCache.updateThrottle then
            CurrencyCache.updateThrottle:Cancel()
        end
        
        CurrencyCache.updateThrottle = C_Timer.NewTimer(0.5, function()
            CurrencyCache:PerformFullScan()
        end)
        
        -- Return false to allow Blizzard message through (will be filtered by ChatFilter if needed)
        return false
    end
    
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CURRENCY", currencyChatFilter)
    
    -- SECONDARY: Register WoW events (may not fire in TWW)
    self:RegisterEvent("CURRENCY_DISPLAY_UPDATE", function(event, currencyType, quantity)
        OnCurrencyUpdate(currencyType, quantity)
    end)
    
    self:RegisterEvent("PLAYER_MONEY", function(event)
        OnMoneyUpdate()
    end)
    
    DebugPrint("|cff00ff00[CurrencyCache]|r Event listeners registered: CHAT_MSG_CURRENCY, CURRENCY_DISPLAY_UPDATE, PLAYER_MONEY")
end
