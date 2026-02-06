--[[
    Warband Nexus - Currency Cache Service (v2.1 - Queue Architecture)
    
    ARCHITECTURE: Direct AceDB + Synchronous FIFO Queue
    
    Data Flow:
    1) CURRENCY_DISPLAY_UPDATE fires → enqueue(currencyID)
    2) DrainCurrencyQueue() processes FIFO (synchronous, immediate)
    3) UpdateSingleCurrency: API → DB write → gain detection → fire lean event
    4) ChatMessageService reads display data from DB (single source of truth)
    
    Queue Benefits:
    - No events lost (old cancel-restart throttle discarded middle events)
    - FIFO order preserved
    - Re-entrancy guard prevents nested processing
    - Same-currency duplicates handled by newQuantity==oldQuantity guard
    
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
    
    -- Queue: FIFO for currency updates (prevents lost events during rapid gains)
    updateQueue = {},       -- {currencyID1, currencyID2, ...}
    isDraining = false,     -- Re-entrancy guard
    
    -- Throttle timers
    fullScanThrottle = nil,
    
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
        DebugPrint("|cffff0000[Currency]|r ERROR: Cannot initialize - DB not ready")
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
        iconFileID = info.iconFileID,
        maxQuantity = info.maxQuantity or 0,
        isAccountWide = info.isAccountWide or false,
        isAccountTransferable = info.isAccountTransferable or false,
        isDiscovered = info.isDiscovered or false,
        isShowInBackpack = info.isShowInBackpack or false,
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
    
    -- OPTIMIZATION: Skip if quantity hasn't changed (avoids unnecessary DB write + log spam)
    local newQuantity = currencyData.quantity or 0
    if newQuantity == oldQuantity then
        return false  -- No change, nothing to update
    end
    
    -- Store directly in DB (no RAM cache)
    db.currencies[charKey][currencyID] = currencyData
    
    -- Update metadata
    CurrencyCache.lastUpdate = time()
    db.lastScan = CurrencyCache.lastUpdate
    
    DebugPrint(string.format("Updated currency %s (%d)", currencyData.name, currencyID))
    
    -- Check for gain and fire lean notification event
    -- DB is already updated above — consumers read from DB
    if newQuantity > oldQuantity then
        local gainAmount = newQuantity - oldQuantity
        
        -- Filter: Skip known internal/tracking currencies
        local currencyName = currencyData.name or ""
        if currencyName:find("Dragon Racing %- Temp Storage") 
            or currencyName:find("Dragon Racing %- Scoreboard")
            or currencyName:find("Race Quest ID") then
            return true  -- DB updated, but no notification
        end
        
        DebugPrint(string.format("Currency gained: %s +%d", currencyData.name, gainAmount))
        
        -- Fire lean event — consumers read display data from DB
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_CURRENCY_GAINED", {
                currencyID = currencyID,
                gainAmount = gainAmount,
            })
        end
    end
    
    return true
end

---Perform full scan of all currencies (Direct DB architecture)
function CurrencyCache:PerformFullScan(bypassThrottle)
    if not C_CurrencyInfo then
        DebugPrint("|cffff0000[Currency]|r ERROR: C_CurrencyInfo not available")
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
        DebugPrint("|cffff0000[Currency]|r Scan returned no data (API not ready?) - retrying in 5 seconds...")
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

-- ============================================================================
-- CURRENCY UPDATE QUEUE (Synchronous FIFO)
-- ============================================================================
-- WoW Lua is single-threaded: no real concurrency.
-- The queue ensures:
--   1) No events are lost (old cancel-restart throttle discarded middle events)
--   2) Each currency is processed in FIFO order with up-to-date API data
--   3) Re-entrancy guard prevents nested processing
--   4) Same-currency duplicates within one drain are auto-handled by
--      the newQuantity == oldQuantity guard in UpdateSingleCurrency
-- ============================================================================

---Drain the currency queue synchronously. Processes all pending items in order.
---Called after every enqueue unless already draining (re-entrancy guard).
local function DrainCurrencyQueue()
    if CurrencyCache.isDraining then return end
    CurrencyCache.isDraining = true
    
    while #CurrencyCache.updateQueue > 0 do
        local currencyID = table.remove(CurrencyCache.updateQueue, 1) -- FIFO pop
        
        if currencyID == 0 then
            -- Marker: full scan requested (no specific currency ID)
            DebugPrint("Queue drain: full scan requested")
            CurrencyCache:PerformFullScan()
        else
            if UpdateSingleCurrency(currencyID) then
                if WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage("WN_CURRENCY_UPDATED", currencyID)
                end
            end
        end
    end
    
    CurrencyCache.isDraining = false
end

---Handle CURRENCY_DISPLAY_UPDATE event (FIFO queue + synchronous drain)
---Every event is enqueued and processed immediately. No events are lost.
---@param currencyType number|nil Currency type/ID
---@param quantity number|nil New quantity
local function OnCurrencyUpdate(currencyType, quantity)
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
        return
    end
    
    if currencyType and currencyType > 0 then
        table.insert(CurrencyCache.updateQueue, currencyType)
    else
        table.insert(CurrencyCache.updateQueue, 0)
    end
    
    -- Drain immediately (re-entrancy guard inside prevents nested calls)
    DrainCurrencyQueue()
end

---Handle PLAYER_MONEY event (gold changes)
local function OnMoneyUpdate()
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
        return
    end
    
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
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
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
                DebugPrint("|cff00ff00[Currency]|r Cleared currency data for: " .. currentCharKey)
            else
                DebugPrint("|cffffcc00[Currency]|r No data to clear for: " .. currentCharKey)
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
    -- Guard: prevent double/triple registration
    if CurrencyCache.eventsRegistered then
        return
    end
    
    if not self.RegisterEvent then
        DebugPrint("|cffff0000[Currency]|r EventManager not available")
        return
    end
    
    CurrencyCache.eventsRegistered = true
    
    -- PRIMARY: Listen for currency changes via chat message (backup path)
    -- Non-cancelling debounce: only schedule a full scan if one isn't already pending.
    -- This ensures rapid messages don't cause repeated scans.
    local chatScanTimer = nil
    local currencyChatFilter = function(self, event, message, ...)
        -- GUARD: Only process if character is tracked
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return false
        end
        
        -- Non-cancelling: only start timer if not already running
        if not chatScanTimer then
            chatScanTimer = C_Timer.NewTimer(0.5, function()
                chatScanTimer = nil
                CurrencyCache:PerformFullScan()
            end)
        end
        
        -- Return false to allow Blizzard message through
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
