--[[
    Warband Nexus - Currency Cache Service (v3.0 - Lean SV + On-Demand Metadata)
    
    ARCHITECTURE: Direct AceDB + Synchronous FIFO Queue + On-Demand Metadata
    
    SV Format (minimal — only data that can't be fetched from API for offline chars):
    {
      version = "1.0.0",
      lastScan = timestamp,
      currencies = {
        [charKey] = {
          [currencyID] = quantity,   -- just a number!
        }
      },
      headers = { ... },  -- UI grouping structure
    }
    
    Metadata (name, icon, maxQuantity, isAccountWide, description, etc.) is ALWAYS
    fetched on-demand from C_CurrencyInfo.GetCurrencyInfo() and cached in session-only
    RAM (bounded, FIFO eviction). Never persisted to SV.
    
    Data Flow:
    1) CURRENCY_DISPLAY_UPDATE fires → enqueue(currencyID)
    2) DrainCurrencyQueue() processes FIFO (synchronous, immediate)
    3) UpdateSingleCurrency: API → store quantity in DB → gain detection → fire lean event
    4) UI calls GetCurrencyData/GetCurrenciesLegacyFormat → combines SV quantity + RAM metadata
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import dependencies
local Constants = ns.Constants

-- Debug print helper (suppressed unless debugMode + debugVerbose; suppressed when debugTryCounterLoot so loot debug is readable)
local function DebugPrint(...)
    if not (WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode) then return end
    if WarbandNexus.db.profile.debugTryCounterLoot then return end
    if not WarbandNexus.db.profile.debugVerbose then return end
    _G.print("|cff00ffff[CurrencyCache]|r", ...)
end

-- ============================================================================
-- STATE (Minimal - No RAM cache)
-- ============================================================================

local CurrencyCache = {
    -- Metadata only (no data storage)
    version = "1.0.0",
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
    initScanPending = false,  -- True while waiting for the initial 5s delayed scan; suppresses event-driven FullScans
}

-- Loading state for UI (similar to ReputationLoadingState pattern)
ns.CurrencyLoadingState = ns.CurrencyLoadingState or {
    isLoading = false,
    loadingProgress = 0,
    currentStage = "Preparing...",
}

-- ============================================================================
-- SESSION-ONLY METADATA CACHE (never persisted)
-- ============================================================================

local currencyMetadataCache = {}          -- [currencyID] = { name, icon, ... }
local currencyMetadataCacheOrder = {}     -- Circular buffer eviction order
local currencyMetadataCacheHead = 1       -- Circular buffer head index
local CURRENCY_METADATA_CACHE_MAX = 256

-- Whitelist: currency IDs visible in the Currency tab (populated during FullScan)
-- Used to filter out hidden/system currencies from chat notifications.
local visibleCurrencyIDs = {}             -- [currencyID] = true

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
-- ON-DEMAND METADATA RESOLVER (Session RAM only)
-- ============================================================================

---Resolve currency metadata from WoW API (cached in session RAM, never persisted).
---@param currencyID number
---@return table|nil { name, icon, maxQuantity, isAccountWide, isAccountTransferable, description, quality }
local function ResolveCurrencyMetadata(currencyID)
    if not currencyID or currencyID == 0 then return nil end
    
    -- Check RAM cache first
    local cached = currencyMetadataCache[currencyID]
    if cached then return cached end
    
    -- Fetch from WoW API
    if not C_CurrencyInfo then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info or not info.name then return nil end
    
    local metadata = {
        currencyID = currencyID,
        name = info.name,
        icon = info.iconFileID,
        iconFileID = info.iconFileID,
        maxQuantity = info.maxQuantity or 0,
        isAccountWide = info.isAccountWide or false,
        isAccountTransferable = info.isAccountTransferable or false,
        description = info.description or "",
        quality = info.quality or 1,
    }
    
    -- Circular buffer eviction (O(1) instead of O(n) table.remove)
    if #currencyMetadataCacheOrder >= CURRENCY_METADATA_CACHE_MAX then
        local evictID = currencyMetadataCacheOrder[currencyMetadataCacheHead]
        if evictID then
            currencyMetadataCache[evictID] = nil
        end
        currencyMetadataCacheOrder[currencyMetadataCacheHead] = currencyID
        currencyMetadataCacheHead = (currencyMetadataCacheHead % CURRENCY_METADATA_CACHE_MAX) + 1
    else
        currencyMetadataCacheOrder[#currencyMetadataCacheOrder + 1] = currencyID
    end
    
    currencyMetadataCache[currencyID] = metadata
    
    return metadata
end

---Clear session-only currency metadata cache (call on tab leave, etc.)
function WarbandNexus:ClearCurrencyMetadataCache()
    wipe(currencyMetadataCache)
    wipe(currencyMetadataCacheOrder)
    currencyMetadataCacheHead = 1
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
        return
    end
    
    -- Load metadata
    CurrencyCache.lastFullScan = db.lastScan or 0
    
    -- Get current character key
    local currentCharKey = ns.Utilities:GetCharacterKey()
    
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
    
    -- Currency data loaded from DB
    
    if needsScan then
        -- Set loading state for UI
        ns.CurrencyLoadingState.isLoading = true
        ns.CurrencyLoadingState.loadingProgress = 0
        ns.CurrencyLoadingState.currentStage = "Waiting for API..."
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
        end
        
        -- Suppress event-driven FullScans until the init scan completes
        -- (CURRENCY_DISPLAY_UPDATE fires on login with nil/0 currencyType, triggering redundant scans)
        CurrencyCache.initScanPending = true
        
        -- Delay scan to ensure API is ready. 1.5s is sufficient for C_CurrencyInfo
        -- (available almost immediately after PLAYER_LOGIN). Previous 5s delay caused
        -- currency data to appear late on first login (T+7s instead of T+3.5s).
        C_Timer.After(1.5, function()
            if CurrencyCache then
                CurrencyCache.initScanPending = false
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
    
    -- Pre-warm metadata cache: resolve all known currency IDs from SV in background.
    -- C_CurrencyInfo.GetCurrencyInfo is synchronous (~0.01ms/call), so 200 calls = ~2ms.
    -- Done deferred so it doesn't add to login frame budget.
    C_Timer.After(8, function()
        local db2 = GetDB()
        if db2 and db2.currencies then
            local seen = {}
            for _, charCurrencies in pairs(db2.currencies) do
                for currencyID in pairs(charCurrencies) do
                    if not seen[currencyID] then
                        seen[currencyID] = true
                        ResolveCurrencyMetadata(currencyID)
                    end
                end
            end
        end
    end)
    
    CurrencyCache.isInitialized = true
end

-- ============================================================================
-- CURRENCY DATA RETRIEVAL (Direct from API)
-- ============================================================================

---Fetch live currency info from WoW API (used for scans and event processing).
---Returns a lightweight table with quantity + fields needed for internal logic.
---Metadata (name, icon, etc.) is NOT persisted — see ResolveCurrencyMetadata.
---@param currencyID number Currency ID
---@return table|nil { currencyID, quantity, name, isDiscovered, isAccountWide, isAccountTransferable }
local function FetchCurrencyFromAPI(currencyID)
    if not currencyID or currencyID == 0 then return nil end
    if not C_CurrencyInfo then return nil end
    
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info or not info.name then return nil end
    
    return {
        currencyID = currencyID,
        quantity = info.quantity or 0,
        name = info.name,                                    -- used for gain detection log / notifications
        isDiscovered = info.isDiscovered or false,            -- used for scan filter
        isAccountWide = info.isAccountWide or false,          -- used for notification filter
        isAccountTransferable = info.isAccountTransferable or false,
    }
end

-- ============================================================================
-- UPDATE OPERATIONS (Direct DB)
-- ============================================================================

---Update a single currency in DB for current character.
---SV stores only quantity (number). Metadata comes from ResolveCurrencyMetadata on-demand.
---@param currencyID number Currency ID to update
---@return boolean success True if updated successfully
local function UpdateSingleCurrency(currencyID)
    if not currencyID or currencyID == 0 then return false end
    
    local db = GetDB()
    if not db then return false end
    
    local charKey = ns.Utilities:GetCharacterKey()
    if not charKey then return false end
    
    -- Initialize character entry if needed
    if not db.currencies[charKey] then
        db.currencies[charKey] = {}
    end
    
    -- Snapshot old value for gain detection (SV stores plain number)
    local oldQuantity = db.currencies[charKey][currencyID] or 0
    -- Handle legacy format: if old value is a table, extract quantity
    if type(oldQuantity) == "table" then oldQuantity = oldQuantity.quantity or 0 end
    
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
    
    -- Store ONLY quantity in SV (lean format)
    db.currencies[charKey][currencyID] = newQuantity
    
    -- Update scan timestamp
    CurrencyCache.lastUpdate = time()
    db.lastScan = CurrencyCache.lastUpdate
    
    -- Check for gain and fire lean notification event
    if newQuantity > oldQuantity then
        local gainAmount = newQuantity - oldQuantity
        
        -- Filter: Only notify for currencies visible in the Currency tab.
        -- visibleCurrencyIDs is populated during PerformFullScan from the Blizzard currency list.
        -- This automatically excludes all hidden/system/internal currencies (e.g., "Patch 11.0.0 - Delve...").
        if next(visibleCurrencyIDs) == nil then
            -- FullScan hasn't run yet (first ~5s after login): fallback to isDiscovered check
            if not currencyData.isDiscovered then
                return true  -- DB updated, but no notification
            end
        else
            -- Normal path: whitelist check (O(1) lookup)
            if not visibleCurrencyIDs[currencyID] then
                return true  -- DB updated, but no notification (hidden/system currency)
            end
        end
        
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
    DebugPrint("|cff9370DB[CurrencyCache]|r [Currency Action] FullScan triggered (bypass=" .. tostring(bypassThrottle) .. ")")
    if not C_CurrencyInfo then
        return
    end
    
    -- Suppress event-driven scans while the initial delayed scan is pending
    -- (the init scan at 5s will cover everything; event-driven scans before that are redundant)
    if not bypassThrottle and self.initScanPending then
        DebugPrint("|cff9370DB[CurrencyCache]|r [Currency Action] FullScan SKIPPED (init scan pending)")
        return
    end
    
    -- Throttle check
    if not bypassThrottle then
        local now = time()
        local timeSinceLastScan = now - self.lastFullScan
        local MIN_SCAN_INTERVAL = 5  -- 5 seconds
        
        if timeSinceLastScan < MIN_SCAN_INTERVAL then
            return
        end
    end
    
    if self.isScanning then
        return
    end
    
    -- PERF: Global coordination — if reputation scan is running, defer to avoid
    -- two heavy scans in the same frame causing FPS drops
    if ns._fullScanInProgress then
        DebugPrint("|cff9370DB[CurrencyCache]|r [PERF] Deferring FullScan — another scan in progress")
        C_Timer.After(1.0, function()
            if CurrencyCache then
                CurrencyCache:PerformFullScan(bypassThrottle)
            end
        end)
        return
    end
    
    self.isScanning = true
    ns._fullScanInProgress = true
    
    -- Reset visible currency whitelist (will be rebuilt from the Currency tab list)
    wipe(visibleCurrencyIDs)
    
    -- Set loading state for UI
    ns.CurrencyLoadingState.isLoading = true
    ns.CurrencyLoadingState.loadingProgress = 0
    ns.CurrencyLoadingState.currentStage = "Fetching currency data..."
    
    -- Trigger UI refresh to show loading state
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
    end
    
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
        self.isScanning = false
        ns._fullScanInProgress = false  -- PERF: Release global scan lock
        
        -- Keep loading state active (don't clear it)
        ns.CurrencyLoadingState.currentStage = "Waiting for API... (retrying)"
        
        -- Trigger UI refresh to show retry message
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_CURRENCY_LOADING_STARTED")
        end
        
        -- Retry after delay
        C_Timer.After(5, function()
            if CurrencyCache then
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
                -- Mark as visible (appears in Currency tab → eligible for notifications)
                visibleCurrencyIDs[currencyID] = true
                
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
        
    end
    -- PERF: Progress state updated once (not per-currency) — screen can't redraw mid-loop anyway
    ns.CurrencyLoadingState.loadingProgress = 70
    ns.CurrencyLoadingState.currentStage = string.format("Processed %d currencies", #currencyDataArray)
    
    -- Note: We're treating all headers as root-level for simplicity
    -- Blizzard's API doesn't provide explicit depth information
    -- The UI will render them sequentially as they appear in the list
    
    -- MERGE header structure into DB (accumulate currency IDs across characters)
    -- Different characters may scan at different times; we want the UNION of all currency IDs
    local db = GetDB()
    if db then
        if not db.headers or #db.headers == 0 then
            -- First scan ever: just store
            db.headers = headerStructure
        else
            -- Merge: for each new header, find matching existing header by name
            -- and add any new currency IDs
            local existingByName = {}
            for _, existingHeader in ipairs(db.headers) do
                existingByName[existingHeader.name] = existingHeader
            end
            
            for _, newHeader in ipairs(headerStructure) do
                local existing = existingByName[newHeader.name]
                if existing then
                    -- Merge currency IDs: add any new ones from this scan
                    local existingSet = {}
                    for _, cid in ipairs(existing.currencies or {}) do
                        existingSet[cid] = true
                    end
                    for _, cid in ipairs(newHeader.currencies or {}) do
                        if not existingSet[cid] then
                            table.insert(existing.currencies, cid)
                        end
                    end
                else
                    -- New header not seen before: add it
                    table.insert(db.headers, newHeader)
                end
            end
        end
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
    ns._fullScanInProgress = false  -- PERF: Release global scan lock
    
    -- Fire cache ready event (will trigger UI refresh)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CURRENCY_CACHE_READY")
        WarbandNexus:SendMessage("WN_CURRENCY_UPDATED")
    end
end

---Update all currencies in DB (lean format: only quantity per currency).
---@param currencyDataArray table Array of { currencyID, quantity, ... } from FetchCurrencyFromAPI
---@return boolean success
function CurrencyCache:UpdateAll(currencyDataArray)
    if not currencyDataArray or #currencyDataArray == 0 then
        return false
    end
    
    local db = GetDB()
    if not db then
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities:GetCharacterKey()
    
    -- CRITICAL: Clear ONLY current character's data (preserve other characters)
    if not db.currencies[currentCharKey] then
        db.currencies[currentCharKey] = {}
    else
        wipe(db.currencies[currentCharKey])
    end
    
    -- Write ONLY quantity to SV (lean format)
    local currencyCount = 0
    
    for _, data in ipairs(currencyDataArray) do
        if data.currencyID then
            db.currencies[currentCharKey][data.currencyID] = data.quantity or 0
            currencyCount = currencyCount + 1
        end
    end
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    db.lastScan = self.lastFullScan
    db.version = self.version
    
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

---Get currency data for a specific currency.
---Combines SV quantity (per-char) + on-demand metadata from API.
---@param currencyID number Currency ID
---@param charKey string|nil Character key (defaults to current character)
---@return table|nil { currencyID, quantity, name, icon, iconFileID, maxQuantity, isAccountWide, ... }
function WarbandNexus:GetCurrencyData(currencyID, charKey)
    if not currencyID or currencyID == 0 then return nil end
    
    local db = GetDB()
    if not db then return nil end
    
    -- Use current character if not specified
    if not charKey and ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    if not charKey then return nil end
    
    -- Get quantity from SV
    local quantity = nil
    if db.currencies[charKey] then
        local stored = db.currencies[charKey][currencyID]
        if stored ~= nil then
            -- Handle both lean (number) and legacy (table) format
            if type(stored) == "number" then
                quantity = stored
            elseif type(stored) == "table" then
                quantity = stored.quantity or 0
            end
        end
    end
    
    -- If no data and this is the current character, try to fetch live
    if quantity == nil and charKey == ns.Utilities:GetCharacterKey() then
        local liveData = FetchCurrencyFromAPI(currencyID)
        if liveData then
            quantity = liveData.quantity or 0
            -- Persist quantity to SV
            if not db.currencies[charKey] then
                db.currencies[charKey] = {}
            end
            db.currencies[charKey][currencyID] = quantity
        end
    end
    
    if quantity == nil then return nil end
    
    -- Resolve metadata from API (session RAM cache)
    local metadata = ResolveCurrencyMetadata(currencyID)
    if not metadata then
        -- API not ready yet; return minimal data
        return {
            currencyID = currencyID,
            quantity = quantity,
            name = "Currency #" .. currencyID,
            icon = nil,
            iconFileID = nil,
            maxQuantity = 0,
            isAccountWide = false,
            isAccountTransferable = false,
            description = "",
            quality = 1,
        }
    end
    
    -- Combine: SV quantity + RAM metadata
    return {
        currencyID = currencyID,
        quantity = quantity,
        name = metadata.name,
        icon = metadata.icon,
        iconFileID = metadata.iconFileID,
        maxQuantity = metadata.maxQuantity,
        isAccountWide = metadata.isAccountWide,
        isAccountTransferable = metadata.isAccountTransferable,
        description = metadata.description,
        quality = metadata.quality,
    }
end

---Get all cached currency data for a character (lean format from SV).
---Returns { [currencyID] = quantity } map.
---@param charKey string|nil Character key (defaults to current character)
---@return table { [currencyID] = quantity }
function WarbandNexus:GetAllCurrencyData(charKey)
    if not charKey and ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    if not charKey then return {} end
    
    local db = GetDB()
    if not db or not db.currencies then return {} end
    
    return db.currencies[charKey] or {}
end

---Get all currencies in LEGACY format (for backward compatibility with UI).
---Union of all currency IDs across characters; every tracked char has an entry per currency (0 if missing).
---Combines lean SV quantities + on-demand metadata from API.
---@return table Currency data in legacy format { [currencyID] = { name, icon, value, chars = {...} } }
function WarbandNexus:GetCurrenciesLegacyFormat()
    local db = GetDB()
    if not db then return {} end
    
    -- 1) Collect all tracked character keys (same list as UI/tooltip)
    local trackedCharKeys = {}
    if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters then
        for charKey, charData in pairs(WarbandNexus.db.global.characters) do
            if type(charData) == "table" and charData.isTracked == true then
                trackedCharKeys[charKey] = true
            end
        end
    end
    -- Fallback: if no tracked list, use all charKeys that have currency data
    if not next(trackedCharKeys) and db.currencies then
        for charKey in pairs(db.currencies) do
            trackedCharKeys[charKey] = true
        end
    end
    
    -- 2) Union of all currency IDs (any character has this currency)
    local currencyIDSet = {}
    if db.currencies then
        for _, currencies in pairs(db.currencies) do
            if type(currencies) == "table" then
                for currencyID in pairs(currencies) do
                    currencyIDSet[currencyID] = true
                end
            end
        end
    end
    
    local result = {}
    for currencyID in pairs(currencyIDSet) do
        local metadata = ResolveCurrencyMetadata(currencyID)
        local legacy = {
            name = metadata and metadata.name or ("Currency #" .. currencyID),
            icon = metadata and metadata.icon or nil,
            maxQuantity = metadata and metadata.maxQuantity or 0,
            isAccountWide = metadata and metadata.isAccountWide or false,
            isAccountTransferable = metadata and metadata.isAccountTransferable or false,
        }
        
        -- ALWAYS populate per-character amounts (UI needs this to show current character's value)
        legacy.chars = {}
        local total = 0
        local maxQty = 0
        for charKey in pairs(trackedCharKeys) do
            local currencies = db.currencies and db.currencies[charKey]
            local stored = currencies and currencies[currencyID]
            local qty = 0
            if type(stored) == "number" then qty = stored
            elseif type(stored) == "table" then qty = stored.quantity or 0 end
            legacy.chars[charKey] = qty
            total = total + qty
            if qty > maxQty then maxQty = qty end
        end
        
        -- Warband (account-wide) currencies: one shared pool — same value on all chars. Use max (not sum).
        if legacy.isAccountWide then
            legacy.value = maxQty
        else
            legacy.value = nil
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
    if clearDB then
        local db = GetDB()
        if db then
            -- Get current character key
            local currentCharKey = ns.Utilities:GetCharacterKey()
            
            -- IMPORTANT: Only clear CURRENT character's currency data
            if db.currencies and db.currencies[currentCharKey] then
                wipe(db.currencies[currentCharKey])
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
        return
    end
    
    CurrencyCache.eventsRegistered = true
    
    -- PRIMARY: Listen for currency changes via chat message (backup path)
    -- Non-cancelling debounce: only schedule a full scan if one isn't already pending.
    -- TAINT-SAFE: Filter returns false only (allow message); no Blizzard frame/state modified.
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
    
    self:RegisterEvent("ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED", function()
        ns.DebugPrint("EVENT: ACCOUNT_CHARACTER_CURRENCY_DATA_RECEIVED")
        if CurrencyCache.syncTimer then
            CurrencyCache.syncTimer:Cancel()
            CurrencyCache.syncTimer = nil
        end
        if CurrencyCache.PerformActualSync then
            CurrencyCache:PerformActualSync()
        end
    end)
    
    -- TERTIARY: Hook Warband transfers to update offline character immediately
    -- Since the hook event sometimes triggers before the local client knows the true DB amount 
    -- or if the user hasn't logged into the character yet, we sync ALL known currencies.
    if C_CurrencyInfo and C_CurrencyInfo.RequestCurrencyFromAccountCharacter then
        hooksecurefunc(C_CurrencyInfo, "RequestCurrencyFromAccountCharacter", function(sourceCharacterGUID, currencyID, quantity)
            if not currencyID or not sourceCharacterGUID or not quantity then return end
            
            -- LOCAL PREDICTION: Immediately deduct from our local DB for the source character
            -- The API is heavily delayed/throttled for offline characters.
            local db = GetDB()
            local wDB = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
            if db and db.currencies and wDB and wDB.characters then
                for charKey, charData in pairs(wDB.characters) do
                    -- Match by GUID (or fallback to partial name match if GUID is missing)
                    if charData.guid == sourceCharacterGUID or (not charData.guid and string.find(sourceCharacterGUID, charData.name)) then
                        if db.currencies[charKey] and db.currencies[charKey][currencyID] then
                            local oldQty = db.currencies[charKey][currencyID]
                            local newQty = math.max(0, oldQty - quantity)
                            db.currencies[charKey][currencyID] = newQty
                            
                            -- Mark this currency as recently transferred to protect against stale API overwrites
                            CurrencyCache.recentTransfers = CurrencyCache.recentTransfers or {}
                            CurrencyCache.recentTransfers[charKey] = CurrencyCache.recentTransfers[charKey] or {}
                            CurrencyCache.recentTransfers[charKey][currencyID] = GetTime()
                            
                            ns.DebugPrint(string.format("[WN Hook] Deducted %d of currency %d from %s (%d -> %d)", quantity, currencyID, charKey, oldQty, newQty))
                            
                            if WarbandNexus.SendMessage then
                                WarbandNexus:SendMessage("WN_CURRENCY_UPDATED")
                            end
                        end
                        break
                    end
                end
            end
            
            -- Ask for a server sync for good measure after a delay
            C_Timer.After(1.5, function()
                if CurrencyCache and CurrencyCache.SyncAccountCurrencies then
                    CurrencyCache:SyncAccountCurrencies(currencyID)
                end
            end)
        end)
    end
    
    -- PLAYER_MONEY: owned by Core.lua / EventManager (OnMoneyChanged)
    -- Do NOT register here — prevents duplicate gold processing
    
end

-- ============================================================================
-- ACCOUNT WIDE SYNCHRONIZATION
-- ============================================================================

---Synchronize a specific currency or all known currencies across all characters using the C_CurrencyInfo API.
---This function sets up the asynchronous fetch from the server.
---@param specificCurrencyID number|nil If provided, only this currency will be synced.
function CurrencyCache:SyncAccountCurrencies(specificCurrencyID)
    ns.DebugPrint("SyncAccountCurrencies requesting data from server...")
    
    if not C_CurrencyInfo or not C_CurrencyInfo.RequestCurrencyDataForAccountCharacters then
        return
    end

    -- Save requested ID so the event handler knows what to sync
    CurrencyCache.pendingSyncCurrencyID = specificCurrencyID
    CurrencyCache.isAwaitingAccountCurrencyData = true
    
    -- Ask server for fresh account wide currency data
    C_CurrencyInfo.RequestCurrencyDataForAccountCharacters()
    
    -- Fallback timer: The WoW API silently drops/throttles these requests sometimes without firing the event.
    if CurrencyCache.syncTimer then CurrencyCache.syncTimer:Cancel() end
    CurrencyCache.syncTimer = C_Timer.NewTimer(0.5, function()
        ns.DebugPrint("Fallback timer to PerformActualSync triggered.")
        CurrencyCache.syncTimer = nil
        if CurrencyCache.PerformActualSync then
            CurrencyCache:PerformActualSync(specificCurrencyID, 1)
        end
    end)
end

---Actually performs the update using the fetched data (called from Event).
function CurrencyCache:PerformActualSync(specificCurrencyID, retryCount)
    specificCurrencyID = specificCurrencyID or CurrencyCache.pendingSyncCurrencyID
    retryCount = retryCount or 0
    
    if C_CurrencyInfo.IsAccountCharacterCurrencyDataReady and not C_CurrencyInfo.IsAccountCharacterCurrencyDataReady() then
        if retryCount < 10 then
            ns.DebugPrint("Data not ready. Retrying in 0.5s (Attempt " .. (retryCount + 1) .. ")")
            C_Timer.After(0.5, function()
                if CurrencyCache.PerformActualSync then
                    CurrencyCache:PerformActualSync(specificCurrencyID, retryCount + 1)
                end
            end)
            return
        else
            ns.DebugPrint("Polling timed out after 5 seconds. Aborting sync.")
            CurrencyCache.pendingSyncCurrencyID = nil
            return
        end
    end
    
    -- Clear the pending ID and proceed
    CurrencyCache.pendingSyncCurrencyID = nil
    
    ns.DebugPrint("PerformActualSync triggered.")
    
    if not C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters then
        return
    end
    
    local db = GetDB()
    if not db then
        return
    end
    if not db.currencies then
        return
    end
    
    local wDB = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    if not wDB then
        return
    end
    if not wDB.characters then
        return
    end
    
    -- Collect the currencies to sync
    local currenciesToSync = {}
    if specificCurrencyID then
        currenciesToSync[1] = specificCurrencyID
    else
        -- If no specific ID, sync all known currencies from the DB
        -- (To optimize, we gather a unique list of all currency IDs known to any character)
        local uniqueIDs = {}
        for charKey, charCurrencies in pairs(db.currencies) do
            for cID, _ in pairs(charCurrencies) do
                if not uniqueIDs[cID] then
                    uniqueIDs[cID] = true
                    table.insert(currenciesToSync, cID)
                end
            end
        end
    end
    
    local updatedAny = false
    
    print(string.format("|cff9370DB[WN]|r SyncAccountCurrencies started for %d currencies.", #currenciesToSync))
    
    -- Process each currency
    for _, currencyID in ipairs(currenciesToSync) do
        local accountCharacters = C_CurrencyInfo.FetchCurrencyDataFromAccountCharacters(currencyID)
        
        -- Create a list of characters that the API reported having this currency
        local apiChars = {}
        
        if accountCharacters and type(accountCharacters) == "table" then
            for _, info in ipairs(accountCharacters) do
                if info.characterName and info.quantity then
                    table.insert(apiChars, {
                        name = info.characterName,
                        guid = info.characterGUID,
                        quantity = info.quantity
                    })
                end
            end
        end
        
        -- Now iterate over our TRACKED characters and update their DB entry
        local currentPlayerGUID = UnitGUID("player")
        local currentPlayerKey = UnitName("player") .. "-" .. (GetNormalizedRealmName() or "")
        
        for charKey, charData in pairs(wDB.characters) do
            if charData.isTracked then
                -- SKIP CURRENT LOGIN CHARACTER! Their data is always fresh locally and might not be in the API response.
                local isCurrentPlayer = (charData.guid and charData.guid == currentPlayerGUID) or (charKey == currentPlayerKey)
                
                if not isCurrentPlayer then
                    local newQuantity = 0
                    local dbNameBase = strsplit("-", charData.name)
                    
                    for _, apiChar in ipairs(apiChars) do
                        local isMatch = false
                        -- Strategy 1: Match by GUID (100% accurate)
                        if charData.guid and apiChar.guid and charData.guid == apiChar.guid then
                            isMatch = true
                        else
                            -- Strategy 2: Match by exact API name or API base name
                            local apiNameBase = strsplit("-", apiChar.name)
                            if apiChar.name == charData.name or apiNameBase == dbNameBase then
                                isMatch = true
                                -- Opportunistically save GUID for future comparisons
                                if apiChar.guid and not charData.guid then
                                    charData.guid = apiChar.guid
                                end
                            end
                        end
                        
                        if isMatch then
                            newQuantity = apiChar.quantity
                            break
                        end
                    end
                    
                    -- ONLY update if the quantity differs from what we have
                    local oldQuantity = db.currencies[charKey] and db.currencies[charKey][currencyID] or 0
                    if oldQuantity ~= newQuantity then
                        -- Protection against stale API data: if we recently locally deducted this currency,
                        -- ignore the API update if it is trying to revert the deduction (i.e. API value > local value)
                        local recentlyTransferred = CurrencyCache.recentTransfers and CurrencyCache.recentTransfers[charKey] and CurrencyCache.recentTransfers[charKey][currencyID]
                        local isStaleRevert = recentlyTransferred and (GetTime() - recentlyTransferred < 30) and (newQuantity > oldQuantity)
                        
                        if not isStaleRevert then
                            if not db.currencies[charKey] then db.currencies[charKey] = {} end
                            db.currencies[charKey][currencyID] = newQuantity
                            updatedAny = true
                            ns.DebugPrint(string.format("|cff9370DB[CurrencyCache]|r Sync: Updated %s for %s (%d -> %d)", tostring(currencyID), charKey, oldQuantity, newQuantity))
                        else
                            ns.DebugPrint(string.format("|cff9370DB[CurrencyCache]|r Sync: Ignored stale API data for %s %s (%d -> %d)", charKey, tostring(currencyID), oldQuantity, newQuantity))
                        end
                    end
                end
            end
        end
    end
    
    if updatedAny and WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_CURRENCY_UPDATED")
    end
end

-- Export to namespace for UI and other modules
ns.CurrencyCache = CurrencyCache
