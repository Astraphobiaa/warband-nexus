--[[
    Warband Nexus - Reputation Cache Service (v2.0.0 - Phase 2)
    
    Phase 2: Full implementation with Processor
    
    Responsibilities:
    1. DB Interface - Read/write to SavedVariables
    2. RAM Cache - Fast access for UI
    3. Event Firing - Notify listeners on data changes
    4. Throttling - Prevent spam (5s minimum between full scans)
    
    Architecture: Scanner → Processor → Cache → UI
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import dependencies
local Scanner = ns.ReputationScanner
local Processor = ns.ReputationProcessor
local Constants = ns.Constants

-- Debug print helper
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print("|cff00ffff[ReputationCache]|r", ...)
    end
end

-- ============================================================================
-- STATE
-- ============================================================================

local ReputationCache = {
    -- RAM cache for fast UI access (v2.1: Per-character storage)
    accountWide = {},      -- [factionID] = normalizedData (account-wide reputations)
    characterSpecific = {},  -- [characterKey] = { [factionID] = normalizedData }
    headers = {},
    
    -- Metadata
    version = Constants.REPUTATION_CACHE_VERSION or "2.0.0",
    lastFullScan = 0,
    lastUpdate = 0,
    
    -- Throttle timers
    fullScanThrottle = nil,
    updateThrottle = nil,
    
    -- Flags
    isInitialized = false,
    isScanning = false,
}

-- ============================================================================
-- DB INTERFACE
-- ============================================================================

---Initialize cache from SavedVariables
function ReputationCache:Initialize()
    if self.isInitialized then
        return
    end
    
    -- Initialize DB structure (v2.1: Per-character storage)
    if not WarbandNexus.db.global.reputationData then
        WarbandNexus.db.global.reputationData = {
            version = self.version,
            lastScan = 0,
            accountWide = {},    -- Account-wide reputations
            characters = {},     -- Per-character reputations
            headers = {},
        }
    end
    
    local dbCache = WarbandNexus.db.global.reputationData
    
    -- Version check - STRICT: Must match exactly OR be force rebuild marker
    if dbCache.version ~= self.version or dbCache.version == "FORCE_REBUILD" then
        print("|cffffcc00[Cache]|r Version mismatch or force rebuild detected")
        print("|cffffcc00[Cache]|r DB version: " .. tostring(dbCache.version) .. " | Expected: " .. self.version)
        self:Clear(true)  -- Clear DB
        return
    end
    
    -- Load factions from DB to RAM (v2.1: Per-character storage)
    self.accountWide = dbCache.accountWide or {}
    self.characterSpecific = dbCache.characters or {}
    self.headers = dbCache.headers or {}
    self.lastFullScan = dbCache.lastScan or 0
    
    -- Count loaded factions
    local count = 0
    local awCount = 0
    for _ in pairs(self.accountWide) do 
        count = count + 1 
        awCount = awCount + 1
    end
    
    local charCounts = {}
    for charKey, charFactions in pairs(self.characterSpecific) do
        local charCount = 0
        for _ in pairs(charFactions) do 
            count = count + 1
            charCount = charCount + 1
        end
        charCounts[charKey] = charCount
    end
    
    if count > 0 then
        local age = time() - self.lastFullScan
        print(string.format("|cff00ff00[Reputation]|r Cache loaded: %d factions from DB (age: %ds, %d account-wide)",
            count, age, awCount))
        for charKey, charCount in pairs(charCounts) do
            print(string.format("|cff00ff00[Reputation]|r   Character '%s': %d factions", charKey, charCount))
        end
        
        -- Check cache age
        local MAX_CACHE_AGE = 3600  -- 1 hour
        if age > MAX_CACHE_AGE then
            DebugPrint("Cache is stale, will trigger full rescan")
            -- Schedule rescan after 2 seconds (allow UI to load first)
            C_Timer.After(2, function()
                if ReputationCache then
                    ReputationCache:PerformFullScan()
                end
            end)
        end
    else
        DebugPrint("No factions in cache, will trigger full rescan")
        -- Schedule rescan
        C_Timer.After(2, function()
            if ReputationCache then
                ReputationCache:PerformFullScan()
            end
        end)
    end
    
    self.isInitialized = true
    DebugPrint("Initialization complete")
end

---Save cache to SavedVariables (v2.1: Per-character storage)
---@param reason string Optional reason for logging
function ReputationCache:SaveToDB(reason)
    if not WarbandNexus.db or not WarbandNexus.db.global then
        DebugPrint("ERROR: Cannot save - DB not initialized")
        return false
    end
    
    -- CRITICAL FIX: Preserve table reference, don't reassign
    local dbCache = WarbandNexus.db.global.reputationData
    
    if not dbCache then
        -- First time initialization
        WarbandNexus.db.global.reputationData = {
            version = self.version,
            lastScan = self.lastFullScan,
            accountWide = self.accountWide,
            characters = self.characterSpecific,
            headers = self.headers,
        }
    else
        -- Update existing table (preserves AceDB reference)
        dbCache.version = self.version  -- Restore correct version from FORCE_REBUILD
        dbCache.lastScan = self.lastFullScan
        dbCache.accountWide = self.accountWide
        dbCache.characters = self.characterSpecific
        dbCache.headers = self.headers
    end
    
    -- Log summary only on full scan
    if reason and reason:find("full") then
        local awCount = 0
        local charCount = 0
        for _ in pairs(self.accountWide) do awCount = awCount + 1 end
        for _, charFactions in pairs(self.characterSpecific) do
            for _ in pairs(charFactions) do charCount = charCount + 1 end
        end
        print(string.format("|cff00ff00[Reputation]|r DB → %d factions saved (%d account-wide, %d character-specific)",
            awCount + charCount, awCount, charCount))
        
        -- If we were in FORCE_REBUILD state, confirm restoration
        if WarbandNexus.db.global.reputationData.version == self.version then
            print("|cff00ff00[Cache]|r Version restored to " .. self.version)
        end
    end
    
    return true
end

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

---Update single faction in cache (v2.1: Per-character storage)
---@param factionID number
---@param normalizedData table Normalized faction data from Processor
function ReputationCache:UpdateFaction(factionID, normalizedData)
    if not factionID or factionID == 0 then
        DebugPrint("ERROR: Invalid factionID")
        return false
    end
    
    if not normalizedData then
        DebugPrint("ERROR: Missing normalized data for faction " .. factionID)
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Store in RAM cache based on account-wide status
    if normalizedData.isAccountWide then
        self.accountWide[factionID] = normalizedData
    else
        if not self.characterSpecific[currentCharKey] then
            self.characterSpecific[currentCharKey] = {}
        end
        self.characterSpecific[currentCharKey][factionID] = normalizedData
    end
    
    self.lastUpdate = time()
    
    -- Save to DB
    self:SaveToDB("incremental: faction " .. factionID)
    
    -- Fire event
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_UPDATED", factionID)
    end
    
    return true
end

---Update all factions in cache (v2.1: Per-character storage)
---@param normalizedDataArray table Array of normalized faction data from Processor
function ReputationCache:UpdateAll(normalizedDataArray)
    if not normalizedDataArray or #normalizedDataArray == 0 then
        DebugPrint("ERROR: No data to update")
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- CRITICAL FIX: Clear existing character data before updating
    -- This prevents old/stale data from persisting after /wn resetrep
    print(string.format("|cffff00ff[Cache]|r Clearing old data for '%s' before update", currentCharKey))
    if self.characterSpecific[currentCharKey] then
        self.characterSpecific[currentCharKey] = {}
    end
    
    -- Also clear account-wide (full scan should repopulate everything)
    self.accountWide = {}
    
    -- Store factions by category (account-wide vs character-specific)
    local awCount = 0
    local charCount = 0
    
    for _, data in ipairs(normalizedDataArray) do
        if data.factionID then
            -- DEBUG: Log character-based factions
            if not data.isAccountWide then
                if data.factionID == 2658 or data.factionID == 2600 or (data.name and (
                    data.name:find("Cartel") or 
                    data.name:find("Bilgewater") or 
                    data.name:find("Blackwater") or
                    data.name:find("K'aresh") or
                    data.name:find("Severed")
                )) then
                    print(string.format("|cffff00ff[Cache]|r Storing CHAR-SPECIFIC: %s (ID:%d) for %s: standing=%d, current=%d/%d",
                        data.name or "Unknown", data.factionID, currentCharKey,
                        data.standingID or 0, data.currentValue or 0, data.maxValue or 1))
                end
            end
            
            if data.isAccountWide then
                -- Account-wide: Store globally
                self.accountWide[data.factionID] = data
                awCount = awCount + 1
            else
                -- Character-specific: Store per-character
                if not self.characterSpecific[currentCharKey] then
                    self.characterSpecific[currentCharKey] = {}
                end
                self.characterSpecific[currentCharKey][data.factionID] = data
                charCount = charCount + 1
            end
        end
    end
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    
    -- Build headers (for UI grouping)
    self:BuildHeaders()
    
    -- Save to DB
    self:SaveToDB("full scan")
    
    -- Fire event
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
        WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
    end
    
    return true
end

---Build headers from faction data (v2.1: Account-wide + character-specific)
function ReputationCache:BuildHeaders()
    -- Group factions by first parent header (expansion)
    local headerMap = {}
    
    -- Process account-wide factions
    for factionID, data in pairs(self.accountWide) do
        if data.parentHeaders and #data.parentHeaders > 0 then
            local expansionHeader = data.parentHeaders[1]
            
            if not headerMap[expansionHeader] then
                headerMap[expansionHeader] = {
                    name = expansionHeader,
                    factions = {}
                }
            end
            
            table.insert(headerMap[expansionHeader].factions, factionID)
        end
    end
    
    -- Process character-specific factions (from all characters)
    for charKey, charFactions in pairs(self.characterSpecific) do
        for factionID, data in pairs(charFactions) do
            if data.parentHeaders and #data.parentHeaders > 0 then
                local expansionHeader = data.parentHeaders[1]
                
                if not headerMap[expansionHeader] then
                    headerMap[expansionHeader] = {
                        name = expansionHeader,
                        factions = {}
                    }
                end
                
                -- Avoid duplicates (faction might exist from multiple characters)
                local exists = false
                for _, existingID in ipairs(headerMap[expansionHeader].factions) do
                    if existingID == factionID then
                        exists = true
                        break
                    end
                end
                
                if not exists then
                    table.insert(headerMap[expansionHeader].factions, factionID)
                end
            end
        end
    end
    
    -- Convert to array and sort factions within each header by scan index
    self.headers = {}
    for _, headerData in pairs(headerMap) do
        -- Sort factions by scan index (preserves Blizzard API order)
        if headerData.factions and #headerData.factions > 0 then
            -- Create array of {id, scanIndex} for sorting
            local sortableFactions = {}
            for _, factionID in ipairs(headerData.factions) do
                local factionData = self.accountWide[factionID]
                if not factionData then
                    -- Check character-specific
                    for _, charFactions in pairs(self.characterSpecific) do
                        if charFactions[factionID] then
                            factionData = charFactions[factionID]
                            break
                        end
                    end
                end
                
                local scanIndex = (factionData and factionData._scanIndex) or 9999
                table.insert(sortableFactions, {id = factionID, scanIndex = scanIndex})
            end
            
            -- CRITICAL FIX: Sort by _scanIndex (Blizzard API order), NOT alphabetically
            -- This matches the in-game Reputation UI order
            table.sort(sortableFactions, function(a, b)
                return a.scanIndex < b.scanIndex
            end)
            
            -- Replace factions array with sorted IDs
            headerData.factions = {}
            for _, item in ipairs(sortableFactions) do
                table.insert(headerData.factions, item.id)
            end
        end
        
        table.insert(self.headers, headerData)
    end
    
    -- Sort headers by name (expansion order)
    local expansionOrder = {
        ["The War Within"] = 1,
        ["Dragonflight"] = 2,
        ["Shadowlands"] = 3,
        ["Battle for Azeroth"] = 4,
        ["Legion"] = 5,
        ["Warlords of Draenor"] = 6,
        ["Mists of Pandaria"] = 7,
        ["Cataclysm"] = 8,
        ["Wrath of the Lich King"] = 9,
        ["The Burning Crusade"] = 10,
        ["Classic"] = 11,
        ["Guild"] = 12,
        ["Other"] = 99,
    }
    
    table.sort(self.headers, function(a, b)
        local orderA = expansionOrder[a.name] or 99
        local orderB = expansionOrder[b.name] or 99
        return orderA < orderB
    end)
    
    DebugPrint("Built " .. #self.headers .. " headers")
end

---Get single faction from cache (v2.1: Checks both account-wide and current character)
---@param factionID number
---@return table|nil Faction data
function ReputationCache:GetFaction(factionID)
    -- Check account-wide first
    if self.accountWide[factionID] then
        return self.accountWide[factionID]
    end
    
    -- Check current character
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    if self.characterSpecific[currentCharKey] and self.characterSpecific[currentCharKey][factionID] then
        return self.characterSpecific[currentCharKey][factionID]
    end
    
    return nil
end

---Get all factions from cache (v2.1: Returns both account-wide and character-specific)
---@return table Factions structure {accountWide = {}, characters = {}}
function ReputationCache:GetAll()
    return {
        accountWide = self.accountWide,
        characters = self.characterSpecific,
    }
end

---Get headers for UI grouping
---@return table Headers array
function ReputationCache:GetHeaders()
    return self.headers
end

---Clear cache (v2.1: Per-character storage)
---@param clearDB boolean Also clear SavedVariables
function ReputationCache:Clear(clearDB)
    -- CRITICAL: Clear RAM first
    print("|cffff00ff[Cache]|r Clearing RAM cache...")
    self.accountWide = {}
    self.characterSpecific = {}
    self.headers = {}
    self.lastFullScan = 0
    self.lastUpdate = 0
    self.isScanning = false  -- Reset scanning flag
    
    if clearDB and WarbandNexus.db and WarbandNexus.db.global then
        print("|cffff00ff[Cache]|r Clearing SavedVariables DB...")
        
        -- CRITICAL FIX: Use wipe() to preserve AceDB table reference
        -- Do NOT reassign the table or we lose the SavedVariables link
        local dbCache = WarbandNexus.db.global.reputationData
        
        if dbCache then
            -- Wipe all data while preserving table reference
            wipe(dbCache)
            
            -- Set force rebuild marker - this MUST persist until scan completes
            dbCache.version = "FORCE_REBUILD"
            dbCache.lastScan = 0
            dbCache.accountWide = {}
            dbCache.characters = {}
            dbCache.headers = {}
            
            print("|cff00ff00[Cache]|r DB wiped! Version set to FORCE_REBUILD")
            print("|cffffcc00[Cache]|r Data will persist as empty until rescan completes")
        else
            -- DB doesn't exist yet, create with force rebuild marker
            WarbandNexus.db.global.reputationData = {
                version = "FORCE_REBUILD",
                lastScan = 0,
                accountWide = {},
                characters = {},
                headers = {},
            }
            print("|cff00ff00[Cache]|r DB created with FORCE_REBUILD marker")
        end
    end
    
    -- Fire event to notify UI (show loading state)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_CACHE_CLEARED")
    end
end

-- ============================================================================
-- SCAN OPERATIONS
-- ============================================================================

---Perform full scan (throttled)
---@param bypassThrottle boolean Optional: Skip throttle check (used after cache clear)
function ReputationCache:PerformFullScan(bypassThrottle)
    -- Check throttle (skip if bypassed)
    if not bypassThrottle then
        local timeSinceLastScan = time() - self.lastFullScan
        local MIN_SCAN_INTERVAL = 5  -- 5 seconds
        
        if timeSinceLastScan < MIN_SCAN_INTERVAL then
            DebugPrint("Full scan throttled (last scan " .. timeSinceLastScan .. "s ago)")
            return false
        end
    end
    
    -- Check if already scanning
    if self.isScanning then
        DebugPrint("Scan already in progress, skipping")
        return false
    end
    
    self.isScanning = true
    
    -- Step 1: Fetch raw data from API
    local rawFactions = Scanner:FetchAllFactions()
    
    if not rawFactions or #rawFactions == 0 then
        self.isScanning = false
        return false
    end
    
    print(string.format("|cff00ff00[Reputation]|r API → %d factions fetched", #rawFactions))
    
    -- Step 2: Process raw data into normalized format
    if not Processor then
        DebugPrint("ERROR: Processor not loaded")
        self.isScanning = false
        return false
    end
    
    local normalizedFactions = Processor:ProcessBatch(rawFactions)
    
    if not normalizedFactions or #normalizedFactions == 0 then
        DebugPrint("ERROR: Processor returned no data")
        self.isScanning = false
        return false
    end
    
    DebugPrint("Processed " .. #normalizedFactions .. " factions")
    
    -- Step 3: Store normalized data in cache
    self:UpdateAll(normalizedFactions)
    
    self.isScanning = false
    DebugPrint("Full scan complete: " .. #normalizedFactions .. " factions cached")
    
    return true
end

---Perform incremental update (single faction) - Phase 2: API → Processor
---@param factionID number
function ReputationCache:UpdateSingleFaction(factionID)
    if not factionID or factionID == 0 then
        DebugPrint("ERROR: Invalid factionID for incremental update")
        return false
    end
    
    if not Scanner or not Processor then
        DebugPrint("ERROR: Scanner or Processor not loaded")
        return false
    end
    
    -- Step 1: Fetch raw data
    local rawData = Scanner:FetchFaction(factionID)
    
    if not rawData then
        DebugPrint("ERROR: Failed to fetch faction " .. factionID)
        return false
    end
    
    -- Step 2: Process into normalized format
    local normalizedData = Processor:Process(rawData)
    
    if not normalizedData then
        DebugPrint("ERROR: Failed to process faction " .. factionID)
        return false
    end
    
    -- Step 3: Store in cache
    self:UpdateFaction(factionID, normalizedData)
    
    DebugPrint("Incremental update complete for faction " .. factionID .. " (" .. (normalizedData.name or "Unknown") .. ")")
    
    return true
end

-- ============================================================================
-- PUBLIC API (WarbandNexus interface)
-- ============================================================================

---Initialize reputation cache
function WarbandNexus:InitializeReputationCache()
    ReputationCache:Initialize()
end

---Register reputation cache events (stub - events handled by EventManager)
function WarbandNexus:RegisterReputationCacheEvents()
    -- Events are already registered in EventManager.lua:
    -- - UPDATE_FACTION
    -- - MAJOR_FACTION_RENOWN_LEVEL_CHANGED
    -- - MAJOR_FACTION_UNLOCKED
    -- This function exists for compatibility with InitializationService
    DebugPrint("Reputation cache events already registered in EventManager")
end

---Refresh reputation cache (manual or event-triggered)
---@param force boolean Force refresh even if throttled
function WarbandNexus:RefreshReputationCache(force)
    -- Always update cache when event fires (even if tab not visible)
    -- v2.1: Background updates are important for per-character tracking
    ReputationCache:PerformFullScan()
    
    -- Force UI refresh only if on Reputations tab
    if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab == "reputations" then
        -- UI will refresh via WN_REPUTATION_CACHE_READY event
        DebugPrint("RefreshReputationCache: Reputation tab active, UI will refresh")
    else
        DebugPrint("RefreshReputationCache: Cache updated in background (tab not active)")
    end
end

---Update single faction (for incremental updates)
---@param factionID number
---@return boolean success
function WarbandNexus:UpdateReputationFaction(factionID)
    -- Always update cache (even if tab not visible)
    local success = ReputationCache:UpdateSingleFaction(factionID)
    
    if success then
        DebugPrint("UpdateReputationFaction: Updated faction " .. factionID)
    end
    
    return success
end

---Get normalized reputation data for a single faction (v2.1: Per-character)
---@param factionID number
---@return table|nil Normalized faction data
function WarbandNexus:GetReputationData(factionID)
    return ReputationCache:GetFaction(factionID)
end

---Get all normalized reputation data (v2.1: Merges account-wide + all characters)
---@return table Array of normalized faction data with _characterKey metadata
function WarbandNexus:GetAllReputations()
    local result = {}
    
    -- DEBUG: Log what we're returning
    local awCount = 0
    local charCounts = {}
    
    -- Add account-wide reputations
    for factionID, data in pairs(ReputationCache.accountWide) do
        local entry = {}
        for k, v in pairs(data) do
            entry[k] = v
        end
        entry._characterKey = "Account-Wide"
        -- CRITICAL: Ensure isAccountWide is explicitly set to true
        entry.isAccountWide = true
        table.insert(result, entry)
        awCount = awCount + 1
    end
    
    -- Add character-specific reputations (from ALL characters)
    for charKey, charFactions in pairs(ReputationCache.characterSpecific) do
        local count = 0
        for factionID, data in pairs(charFactions) do
            local entry = {}
            for k, v in pairs(data) do
                entry[k] = v
            end
            entry._characterKey = charKey
            -- CRITICAL: Ensure isAccountWide is explicitly set to false
            entry.isAccountWide = false
            table.insert(result, entry)
            count = count + 1
        end
        charCounts[charKey] = count
    end
    
    print(string.format("|cffff00ff[GetAllReputations]|r Returning %d account-wide factions", awCount))
    for charKey, count in pairs(charCounts) do
        print(string.format("|cffff00ff[GetAllReputations]|r Returning %d factions for %s", count, charKey))
    end
    
    return result
end

---Get reputation headers (for hierarchical display)
---@return table Array of {name, factions=[factionID, ...]}
function WarbandNexus:GetReputationHeaders()
    return ReputationCache.headers or {}
end

---Get all reputations grouped by account-wide status (v2.1: Per-character)
---@return table {accountWide = {}, characterSpecific = {}}
function WarbandNexus:GetReputationsByAccountStatus()
    local accountWide = {}
    local characterSpecific = {}
    
    -- Account-wide
    for factionID, data in pairs(ReputationCache.accountWide) do
        table.insert(accountWide, data)
    end
    
    -- Character-specific (all characters)
    for charKey, charFactions in pairs(ReputationCache.characterSpecific) do
        for factionID, data in pairs(charFactions) do
            table.insert(characterSpecific, data)
        end
    end
    
    return {
        accountWide = accountWide,
        characterSpecific = characterSpecific,
    }
end

---Get reputation data for a specific faction
---@param factionID number
---@return table|nil Faction data
function WarbandNexus:GetReputationData(factionID)
    return ReputationCache:GetFaction(factionID)
end

---Get all reputation data
---@return table Factions map
function WarbandNexus:GetAllReputationData()
    return ReputationCache:GetAll()
end

---Get reputation headers (for UI grouping)
---@return table Headers array
function WarbandNexus:GetReputationHeaders()
    return ReputationCache:GetHeaders()
end

---Clear reputation cache
function WarbandNexus:ClearReputationCache()
    ReputationCache:Clear(true)
    self:Print("|cff00ff00Cache cleared!|r")
    DebugPrint("Cache cleared - triggering full rescan")
    
    -- Trigger rescan after 1 second (bypass throttle)
    C_Timer.After(1, function()
        if ReputationCache then
            self:Print("|cffffcc00━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
            self:Print("|cffffcc00   Starting Reputation Scan...   |r")
            self:Print("|cffffcc00━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
            
            local success = ReputationCache:PerformFullScan(true)  -- Bypass throttle
            
            if success then
                self:Print(" ")
                self:Print("|cff00ff00━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
                self:Print("|cff00ff00   ✓ Reputation Scan Complete!   |r")
                self:Print("|cff00ff00━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
                self:Print(" ")
                self:Print("|cffffcc00Now type:|r |cff00ff00/reload|r |cffffcc00to refresh the UI|r")
                self:Print("|cffffcc00Or switch to another tab and back|r")
                
                -- Force UI refresh if on reputation tab
                C_Timer.After(0.5, function()
                    if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab == "reputations" then
                        self:RefreshUI()
                    end
                end)
            else
                self:Print(" ")
                self:Print("|cffff0000━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
                self:Print("|cffff0000   ✗ Reputation Scan Failed!   |r")
                self:Print("|cffff0000━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━|r")
                self:Print("|cffffcc00Enable debug mode: /wn debug|r")
            end
        end
    end)
end

---Abort ongoing operations (called when switching tabs)
function WarbandNexus:AbortReputationOperations()
    -- Cancel any pending scans
    ReputationCache.isScanning = false
    DebugPrint("Operations aborted")
end

-- ============================================================================
-- BACKWARDS COMPATIBILITY (DEPRECATED)
-- ============================================================================

---DEPRECATED: Old InvalidateReputationCache stub
function WarbandNexus:InvalidateReputationCache(playerKey)
    -- NO-OP: Cache version system handles this automatically
end

-- ============================================================================
-- DEBUG HELPERS
-- ============================================================================

---Global debug function: Inspect faction data
---Usage: /dump WNDebugFaction(2640)
_G.WNDebugFaction = function(factionID)
    local data = ReputationCache:GetFaction(factionID)
    
    if not data then
        print("|cffff0000[WN Debug]|r Faction " .. factionID .. " not found in cache")
        print("  Total factions in cache: " .. (ReputationCache.factions and #ReputationCache.factions or 0))
        return nil
    end
    
    print("|cff00ff00[WN Debug]|r Faction " .. factionID .. " (" .. data.name .. "):")
    print("  Type: " .. data.type)
    print("  StandingID: " .. tostring(data.standingID))
    print("  Standing: " .. (data.standing and data.standing.name or "nil"))
    print("  Progress: " .. tostring(data.progress.current) .. "/" .. tostring(data.progress.max) .. " (" .. string.format("%.1f%%", data.progress.percent * 100) .. ")")
    print("  IsAccountWide: " .. tostring(data.isAccountWide))
    print("  IsHeader: " .. tostring(data.isHeader))
    print("  IsHeaderWithRep: " .. tostring(data.isHeaderWithRep))
    
    if data.friendship and data.friendship.enabled then
        print("  Friendship:")
        print("    RankName: " .. tostring(data.friendship.rankName))
        print("    Level: " .. tostring(data.friendship.currentLevel) .. "/" .. tostring(data.friendship.maxLevel))
    end
    
    if data.renown and data.renown.enabled then
        print("  Renown:")
        print("    Level: " .. tostring(data.renown.level) .. "/" .. tostring(data.renown.maxLevel or "?"))
        print("    Progress: " .. tostring(data.renown.reputationEarned) .. "/" .. tostring(data.renown.levelThreshold))
    end
    
    if data.paragon and data.paragon.enabled then
        print("  Paragon:")
        print("    Progress: " .. tostring(data.paragon.current) .. "/" .. tostring(data.paragon.threshold))
        print("    Cycles: " .. tostring(data.paragon.completedCycles))
        print("    Reward Pending: " .. tostring(data.paragon.rewardPending))
    end
    
    return data
end

---Global debug function: Force rescan
---Usage: /run WNRescanReputations()
_G.WNRescanReputations = function()
    print("|cffffcc00[WN]|r Forcing full reputation rescan...")
    if ReputationCache then
        ReputationCache:Clear(false)  -- Clear RAM only
        ReputationCache:PerformFullScan()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

DebugPrint("ReputationCacheService v" .. ReputationCache.version .. " loaded")

-- Export cache for testing
ns.ReputationCache = ReputationCache

return ReputationCache
