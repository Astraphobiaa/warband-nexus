--[[
    Warband Nexus - Reputation Cache Service (v2.1.0 - Direct DB Architecture)
    
    ARCHITECTURE: Direct AceDB - No RAM cache
    
    Previous Problem:
    - RAM cache (self.accountWide, self.characterSpecific) created sync issues
    - wipe() operations affected shared table references
    - Data loss when switching characters
    
    New Architecture:
    - All operations work DIRECTLY on WarbandNexus.db.global.reputationData
    - No intermediate RAM layer
    - AceDB handles persistence automatically
    - Atomic updates prevent data loss
    
    Architecture: Scanner → Processor → DB (Direct)
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
-- STATE (Minimal - No RAM cache)
-- ============================================================================

local ReputationCache = {
    -- Metadata only (no data storage)
    version = "2.1.0",
    lastFullScan = 0,
    lastUpdate = 0,
    
    -- Throttle timers
    fullScanThrottle = nil,
    updateThrottle = nil,
    
    -- UI refresh debounce (for handling multiple rapid updates)
    uiRefreshTimer = nil,
    pendingUIRefresh = false,
    
    -- Reputation gain tracking (for chat notifications)
    previousValues = {},  -- [factionID] = {currentValue, standingID, standingName}
    
    -- Flags
    isInitialized = false,
    isScanning = false,
}

-- Loading state for UI (similar to PlansLoadingState pattern)
ns.ReputationLoadingState = ns.ReputationLoadingState or {
    isLoading = false,
    loadingProgress = 0,
    currentStage = "Preparing...",
}

-- Fire UI refresh events (with optional debounce)
local function ScheduleUIRefresh(immediate)
    if immediate then
        -- Fire immediately (for resetrep, cache clear, etc.)
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
            WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
        end
        return
    end
    
    -- Cancel existing timer
    if ReputationCache.uiRefreshTimer then
        ReputationCache.uiRefreshTimer:Cancel()
    end
    
    -- Mark as pending
    ReputationCache.pendingUIRefresh = true
    
    -- Schedule new refresh (0.5 seconds after last update - for rapid rep gains)
    ReputationCache.uiRefreshTimer = C_Timer.NewTimer(0.5, function()
        if ReputationCache.pendingUIRefresh and WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
            WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
            ReputationCache.pendingUIRefresh = false
        end
    end)
end

-- ============================================================================
-- DB INTERFACE (Direct Access)
-- ============================================================================

---Get direct reference to DB reputation data
---@return table DB table (WarbandNexus.db.global.reputationData)
local function GetDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then
        return nil
    end
    
    -- Ensure structure exists
    if not WarbandNexus.db.global.reputationData then
        WarbandNexus.db.global.reputationData = {
            version = ReputationCache.version,
            lastScan = 0,
            accountWide = {},
            characters = {},
            headers = {},
        }
    end
    
    return WarbandNexus.db.global.reputationData
end

---Migrate old data structure (if needed)
local function MigrateDB()
    local db = GetDB()
    if not db then return end
    
    -- Check version
    if db.version == ReputationCache.version then
        return -- Already up to date
    end
    
    local oldVersion = db.version or "Unknown"
    print("|cffffcc00[Cache Migration]|r Upgrading DB from " .. tostring(oldVersion) .. " to " .. ReputationCache.version)
    
    -- Handle FORCE_REBUILD marker (from /wn resetrep)
    if db.version == "FORCE_REBUILD" then
        print("|cffffcc00[Cache Migration]|r FORCE_REBUILD detected - keeping empty DB")
        db.version = ReputationCache.version
        return
    end
    
    -- Ensure all required fields exist (preserves existing data)
    db.accountWide = db.accountWide or {}
    db.characters = db.characters or {}
    db.headers = db.headers or {}
    db.lastScan = db.lastScan or 0
    
    -- Version-specific migrations
    if oldVersion == "2.0.0" or oldVersion == "2.0" then
        print("|cffffcc00[Cache Migration]|r Migrating from 2.0.0 to 2.1.0...")
        -- No structural changes, just version bump
    end
    
    -- Update version
    db.version = ReputationCache.version
    
    print("|cff00ff00[Cache Migration]|r Migration complete - data preserved")
end

---Initialize cache (validates DB structure, does NOT clear data)
function ReputationCache:Initialize()
    if self.isInitialized then
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[Cache]|r ERROR: Cannot initialize - DB not ready")
        return
    end
    
    -- Migrate old structure if needed
    MigrateDB()
    
    -- Load metadata
    self.lastFullScan = db.lastScan or 0
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Count existing data
    local awCount = 0
    local charCounts = {}
    local currentCharCount = 0
    
    for _ in pairs(db.accountWide) do 
        awCount = awCount + 1
    end
    
    for charKey, charFactions in pairs(db.characters) do
        local count = 0
        for _ in pairs(charFactions) do 
            count = count + 1
        end
        charCounts[charKey] = count
        if charKey == currentCharKey then
            currentCharCount = count
        end
    end
    
    local totalCount = awCount
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
        if dbVersion ~= self.version then
            needsScan = true
            scanReason = string.format("Version mismatch (DB: %s, Current: %s)", tostring(dbVersion), tostring(self.version))
        else
            local age = time() - self.lastFullScan
            local MAX_CACHE_AGE = 3600  -- 1 hour
            if age > MAX_CACHE_AGE then
                needsScan = true
                scanReason = string.format("Cache is old (%d seconds)", age)
            end
        end
    end
    
    if totalCount > 0 then
        print(string.format("|cff00ff00[Reputation]|r Loaded %d factions from DB (%d account-wide)",
            totalCount, awCount))
        for charKey, charCount in pairs(charCounts) do
            local marker = (charKey == currentCharKey) and " (current)" or ""
            print(string.format("|cff00ff00[Reputation]|r   %s: %d factions%s", charKey, charCount, marker))
        end
    end
    
    if needsScan then
        print("|cffffcc00[Cache]|r " .. scanReason .. ", scheduling scan...")
        
        -- Set loading state for UI
        ns.ReputationLoadingState.isLoading = true
        ns.ReputationLoadingState.loadingProgress = 0
        ns.ReputationLoadingState.currentStage = "Initializing..."
        
        -- Fire loading started event to trigger UI refresh
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
        end
        
        C_Timer.After(3, function()
            if ReputationCache then
                ReputationCache:PerformFullScan()
            end
        end)
    else
        -- Fire ready event immediately (data exists and is fresh)
        C_Timer.After(0.1, function()
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
            end
        end)
    end
    
    -- Register event listeners for real-time updates
    self:RegisterEventListeners()
    
    self.isInitialized = true
    print("|cff00ff00[Cache]|r Direct DB architecture initialized")
end

---Register event listeners for real-time reputation updates
function ReputationCache:RegisterEventListeners()
    if not WarbandNexus or not WarbandNexus.RegisterEvent then
        print("|cffff0000[ReputationCache]|r ERROR: WarbandNexus.RegisterEvent not available")
        return
    end
    
    -- PRIMARY: Listen for reputation changes via chat message (most reliable)
    -- This catches ALL reputation gains (quests, kills, world quests, etc.)
    local reputationChatFilter = function(self, event, message, ...)
        -- Snapshot current values before update (for gain detection)
        local snapshotBefore = {}
        local db = GetDB()
        if db then
            local accountWide = db.accountWide or {}
            local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
            local charData = (db.characters or {})[charKey] or {}
            
            -- Snapshot all current values
            for factionID, data in pairs(accountWide) do
                if data.currentValue and data.standingID and data.standingName then
                    snapshotBefore[factionID] = {
                        currentValue = data.currentValue,
                        standingID = data.standingID,
                        standingName = data.standingName,
                    }
                end
            end
            for factionID, data in pairs(charData) do
                if data.currentValue and data.standingID and data.standingName then
                    snapshotBefore[factionID] = {
                        currentValue = data.currentValue,
                        standingID = data.standingID,
                        standingName = data.standingName,
                    }
                end
            end
        end
        
        -- Trigger reputation scan (throttled)
        if ReputationCache.updateThrottle then
            ReputationCache.updateThrottle:Cancel()
        end
        
        ReputationCache.updateThrottle = C_Timer.NewTimer(0.5, function()
            ReputationCache:PerformFullScan()
            
            -- AFTER scan, check for gains and fire notification events
            local db = GetDB()
            if db then
                local accountWide = db.accountWide or {}
                local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
                local charData = (db.characters or {})[charKey] or {}
                
                -- Check account-wide factions
                for factionID, current in pairs(accountWide) do
                    local previous = snapshotBefore[factionID]
                    if previous and current.currentValue and current.currentValue > previous.currentValue then
                        local gainAmount = current.currentValue - previous.currentValue
                        print(string.format("|cffff00ff[DEBUG]|r Reputation gained: %s +%d", current.name, gainAmount))
                        
                        if WarbandNexus and WarbandNexus.SendMessage then
                            print("|cffff00ff[DEBUG]|r Firing WN_REPUTATION_GAINED event")
                            WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                            factionID = factionID,
                            factionName = current.name,
                            gainAmount = gainAmount,
                            currentValue = current.currentValue,
                            maxValue = current.maxValue,
                            standingName = current.standingName,
                            standingColor = current.standingColor,
                            wasStandingUp = (current.standingID > previous.standingID),
                        })
                        end
                    end
                end
                
                -- Check character-specific factions
                for factionID, current in pairs(charData) do
                    local previous = snapshotBefore[factionID]
                    if previous and current.currentValue and current.currentValue > previous.currentValue then
                        local gainAmount = current.currentValue - previous.currentValue
                        print(string.format("|cffff00ff[DEBUG]|r Reputation gained: %s +%d", current.name, gainAmount))
                        
                        if WarbandNexus and WarbandNexus.SendMessage then
                            print("|cffff00ff[DEBUG]|r Firing WN_REPUTATION_GAINED event")
                            WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                            factionID = factionID,
                            factionName = current.name,
                            gainAmount = gainAmount,
                            currentValue = current.currentValue,
                            maxValue = current.maxValue,
                            standingName = current.standingName,
                            standingColor = current.standingColor,
                            wasStandingUp = (current.standingID > previous.standingID),
                        })
                        end
                    end
                end
            end
        end)
        
        -- Return false to allow Blizzard message through (will be filtered by ChatFilter if needed)
        return false
    end
    
    ChatFrame_AddMessageEventFilter("CHAT_MSG_COMBAT_FACTION_CHANGE", reputationChatFilter)
    
    -- SECONDARY: Listen for UPDATE_FACTION (may not fire in TWW)
    WarbandNexus:RegisterEvent("UPDATE_FACTION", function(_, factionIndex)
        -- Snapshot current values before update (for gain detection)
        local snapshotBefore = {}
        local db = GetDB()
        if db then
            local accountWide = db.accountWide or {}
            local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
            local charData = (db.characters or {})[charKey] or {}
            
            -- Snapshot all current values
            for factionID, data in pairs(accountWide) do
                if data.currentValue and data.standingID and data.standingName then
                    snapshotBefore[factionID] = {
                        currentValue = data.currentValue,
                        standingID = data.standingID,
                        standingName = data.standingName,
                    }
                end
            end
            for factionID, data in pairs(charData) do
                if data.currentValue and data.standingID and data.standingName then
                    snapshotBefore[factionID] = {
                        currentValue = data.currentValue,
                        standingID = data.standingID,
                        standingName = data.standingName,
                    }
                end
            end
        end
        
        -- Throttled update (wait 0.5s for multiple updates)
        if ReputationCache.updateThrottle then
            ReputationCache.updateThrottle:Cancel()
        end
        
        ReputationCache.updateThrottle = C_Timer.NewTimer(0.5, function()
            DebugPrint("UPDATE_FACTION event - performing incremental update")
            -- Perform full scan
            ReputationCache:PerformFullScan()
            
            -- AFTER scan, check for gains and fire notification events
            local db = GetDB()
            if db then
                local accountWide = db.accountWide or {}
                local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or ""
                local charData = (db.characters or {})[charKey] or {}
                
                -- Check account-wide factions
                for factionID, current in pairs(accountWide) do
                    local previous = snapshotBefore[factionID]
                    if previous and current.currentValue and current.currentValue > previous.currentValue then
                        local gainAmount = current.currentValue - previous.currentValue
                        print(string.format("|cffff00ff[DEBUG]|r Reputation gained: %s +%d", current.name, gainAmount))
                        
                        if WarbandNexus and WarbandNexus.SendMessage then
                            print("|cffff00ff[DEBUG]|r Firing WN_REPUTATION_GAINED event")
                            WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                            factionID = factionID,
                            factionName = current.name,
                            gainAmount = gainAmount,
                            currentValue = current.currentValue,
                            maxValue = current.maxValue,
                            standingName = current.standingName,
                            standingColor = current.standingColor,
                            wasStandingUp = (current.standingID > previous.standingID),
                        })
                        end
                    end
                end
                
                -- Check character-specific factions
                for factionID, current in pairs(charData) do
                    local previous = snapshotBefore[factionID]
                    if previous and current.currentValue and current.currentValue > previous.currentValue then
                        local gainAmount = current.currentValue - previous.currentValue
                        print(string.format("|cffff00ff[DEBUG]|r Reputation gained: %s +%d", current.name, gainAmount))
                        
                        if WarbandNexus and WarbandNexus.SendMessage then
                            print("|cffff00ff[DEBUG]|r Firing WN_REPUTATION_GAINED event")
                            WarbandNexus:SendMessage("WN_REPUTATION_GAINED", {
                            factionID = factionID,
                            factionName = current.name,
                            gainAmount = gainAmount,
                            currentValue = current.currentValue,
                            maxValue = current.maxValue,
                            standingName = current.standingName,
                            standingColor = current.standingColor,
                            wasStandingUp = (current.standingID > previous.standingID),
                        })
                        end
                    end
                end
            end
        end)
    end)
    
    -- Listen for major faction renown changes
    WarbandNexus:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", function()
        if ReputationCache.updateThrottle then
            ReputationCache.updateThrottle:Cancel()
        end
        
        ReputationCache.updateThrottle = C_Timer.NewTimer(0.5, function()
            DebugPrint("MAJOR_FACTION_RENOWN_LEVEL_CHANGED - performing update")
            ReputationCache:PerformFullScan()
        end)
    end)
    
    -- ALTERNATIVE: Listen for quest completion (often triggers rep gains)
    WarbandNexus:RegisterEvent("QUEST_TURNED_IN", function(_, questID)
        if ReputationCache.updateThrottle then
            ReputationCache.updateThrottle:Cancel()
        end
        
        ReputationCache.updateThrottle = C_Timer.NewTimer(0.5, function()
            ReputationCache:PerformFullScan()
        end)
    end)
    
    print("|cff00ff00[ReputationCache]|r Event listeners registered: CHAT_MSG_COMBAT_FACTION_CHANGE, UPDATE_FACTION, MAJOR_FACTION_RENOWN_LEVEL_CHANGED, QUEST_TURNED_IN")
end

-- ============================================================================
-- UPDATE OPERATIONS (Direct DB writes)
-- ============================================================================

---Update single faction (writes directly to DB)
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
    
    local db = GetDB()
    if not db then
        DebugPrint("ERROR: DB not initialized")
        return false
    end
    
    -- Get current character key
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    
    -- Write DIRECTLY to DB (no RAM cache)
    if normalizedData.isAccountWide then
        db.accountWide[factionID] = normalizedData
    else
        if not db.characters[currentCharKey] then
            db.characters[currentCharKey] = {}
        end
        db.characters[currentCharKey][factionID] = normalizedData
    end
    
    self.lastUpdate = time()
    
    -- Schedule UI refresh (debounced)
    ScheduleUIRefresh()
    
    return true
end

---Update all factions (MERGE into DB, preserves other characters' data)
---@param normalizedDataArray table Array of normalized faction data from Processor
function ReputationCache:UpdateAll(normalizedDataArray)
    if not normalizedDataArray or #normalizedDataArray == 0 then
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
    if not db.characters[currentCharKey] then
        db.characters[currentCharKey] = {}
    else
        wipe(db.characters[currentCharKey])
    end
    
    -- MERGE data into DB (account-wide gets updated, not replaced)
    local awCount = 0
    local charCount = 0
    
    for _, data in ipairs(normalizedDataArray) do
        if data.factionID then
            if data.isAccountWide then
                -- Update account-wide faction
                db.accountWide[data.factionID] = data
                awCount = awCount + 1
            else
                -- Add character-specific faction
                db.characters[currentCharKey][data.factionID] = data
                charCount = charCount + 1
            end
        end
    end
    
    -- Update metadata
    self.lastFullScan = time()
    self.lastUpdate = time()
    db.lastScan = self.lastFullScan
    
    -- Build headers
    self:BuildHeaders()
    
    -- Fire UI refresh immediately (full scan always shows results)
    ScheduleUIRefresh(true)
    
    print(string.format("|cff00ff00[Reputation]|r Updated: %d account-wide, %d character-specific (%s)",
        awCount, charCount, currentCharKey))
    
    return true
end

---Build headers from DB data (for UI grouping)
function ReputationCache:BuildHeaders()
    local db = GetDB()
    if not db then return end
    
    -- Group factions by first parent header (expansion)
    local headerMap = {}
    
    -- Process account-wide factions
    for factionID, data in pairs(db.accountWide) do
        if data.parentFactionName and data.parentFactionName ~= "" then
            if not headerMap[data.parentFactionName] then
                headerMap[data.parentFactionName] = {
                    name = data.parentFactionName,
                    factions = {},
                    sortKey = 99999,
                }
            end
            table.insert(headerMap[data.parentFactionName].factions, factionID)
        end
    end
    
    -- Process character-specific factions
    for charKey, charFactions in pairs(db.characters) do
        for factionID, data in pairs(charFactions) do
            if data.parentFactionName and data.parentFactionName ~= "" then
                if not headerMap[data.parentFactionName] then
                    headerMap[data.parentFactionName] = {
                        name = data.parentFactionName,
                        factions = {},
                        sortKey = 99999,
                    }
                end
                -- Don't duplicate factionID if already in list
                local exists = false
                for _, existingID in ipairs(headerMap[data.parentFactionName].factions) do
                    if existingID == factionID then
                        exists = true
                        break
                    end
                end
                if not exists then
                    table.insert(headerMap[data.parentFactionName].factions, factionID)
                end
            end
        end
    end
    
    -- Calculate MinIndex for each header (for sorting)
    for headerName, headerData in pairs(headerMap) do
        local minIndex = 99999
        for _, factionID in ipairs(headerData.factions) do
            -- Check account-wide
            local data = db.accountWide[factionID]
            if not data then
                -- Check character-specific
                for _, charFactions in pairs(db.characters) do
                    data = charFactions[factionID]
                    if data then break end
                end
            end
            
            if data and data._scanIndex and data._scanIndex < minIndex then
                minIndex = data._scanIndex
            end
        end
        headerData.sortKey = minIndex
        
        -- Sort factions within header by scanIndex
        table.sort(headerData.factions, function(a, b)
            local dataA = db.accountWide[a]
            if not dataA then
                for _, charFactions in pairs(db.characters) do
                    dataA = charFactions[a]
                    if dataA then break end
                end
            end
            
            local dataB = db.accountWide[b]
            if not dataB then
                for _, charFactions in pairs(db.characters) do
                    dataB = charFactions[b]
                    if dataB then break end
                end
            end
            
            local indexA = (dataA and dataA._scanIndex) or 99999
            local indexB = (dataB and dataB._scanIndex) or 99999
            return indexA < indexB
        end)
    end
    
    -- Convert to array and sort headers
    local headers = {}
    for _, headerData in pairs(headerMap) do
        table.insert(headers, headerData)
    end
    
    table.sort(headers, function(a, b)
        return a.sortKey < b.sortKey
    end)
    
    -- Save to DB
    db.headers = headers
end

-- ============================================================================
-- READ OPERATIONS (Direct DB reads)
-- ============================================================================

---Get single faction from DB
---@param factionID number
---@return table|nil Normalized faction data
function ReputationCache:GetFaction(factionID)
    local db = GetDB()
    if not db then return nil end
    
    -- Check account-wide first
    if db.accountWide[factionID] then
        return db.accountWide[factionID]
    end
    
    -- Check current character
    local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    if db.characters[currentCharKey] and db.characters[currentCharKey][factionID] then
        return db.characters[currentCharKey][factionID]
    end
    
    return nil
end

---Get all factions from DB (returns structure for internal use)
---@return table Factions structure {accountWide = {}, characters = {}}
function ReputationCache:GetAll()
    local db = GetDB()
    if not db then
        return {accountWide = {}, characters = {}}
    end
    
    return {
        accountWide = db.accountWide,
        characters = db.characters,
    }
end

---Get headers for UI grouping
---@return table Headers array
function ReputationCache:GetHeaders()
    local db = GetDB()
    if not db then return {} end
    
    return db.headers or {}
end

---Clear reputation data for current character only (preserves other characters)
---@param clearDB boolean Also clear SavedVariables (only current character's reputation data)
function ReputationCache:Clear(clearDB)
    print("|cffff00ff[Cache]|r Clearing reputation data...")
    
    if clearDB then
        local db = GetDB()
        if db then
            -- Get current character key
            local currentCharKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
            
            -- IMPORTANT: Only clear CURRENT character's reputation data
            -- Preserve: account-wide data, other characters' data, version, headers
            if db.characters and db.characters[currentCharKey] then
                wipe(db.characters[currentCharKey])
                print("|cff00ff00[Cache]|r Cleared reputation data for: " .. currentCharKey)
            else
                print("|cffffcc00[Cache]|r No data to clear for: " .. currentCharKey)
            end
            
            -- Reset scan time for current character only
            db.lastScan = 0
            
            -- Note: We do NOT clear:
            -- - db.accountWide (shared across all characters)
            -- - db.characters[otherCharKey] (other characters' data)
            -- - db.version (keep version tracking)
            -- - db.headers (will be rebuilt from remaining data)
        end
    end
    
    -- Reset metadata
    self.lastFullScan = 0
    self.lastUpdate = 0
    self.isScanning = false
    
    -- Fire events immediately (cache cleared)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_CACHE_CLEARED")
    end
    ScheduleUIRefresh(true)
    
    -- Automatically start rescan after clearing
    if clearDB then
        -- Set loading state for UI
        ns.ReputationLoadingState.isLoading = true
        ns.ReputationLoadingState.loadingProgress = 0
        ns.ReputationLoadingState.currentStage = "Preparing..."
        
        -- Fire loading started event
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
        end
        
        print("|cffffcc00[Cache]|r Starting automatic rescan in 1 second...")
        C_Timer.After(1, function()
            if ReputationCache then
                ReputationCache:PerformFullScan(true)  -- bypass throttle since we just cleared
            end
        end)
    else
        -- Clear loading state if not rescanning
        ns.ReputationLoadingState.isLoading = false
        ns.ReputationLoadingState.loadingProgress = 0
        ns.ReputationLoadingState.currentStage = "Preparing..."
    end
end

-- ============================================================================
-- SCAN OPERATIONS
-- ============================================================================

---Perform full scan of all reputations
function ReputationCache:PerformFullScan(bypassThrottle)
    if not Scanner or not Processor then
        print("|cffff0000[Cache]|r ERROR: Scanner or Processor not loaded")
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
    ns.ReputationLoadingState.isLoading = true
    ns.ReputationLoadingState.loadingProgress = 0
    ns.ReputationLoadingState.currentStage = "Fetching reputation data..."
    
    -- Trigger UI refresh to show loading state
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
    end
    
    print("|cff9370DB[Reputation]|r Starting full scan...")
    
    -- Scan raw data
    local rawData = Scanner:FetchAllFactions()
    
    if not rawData or #rawData == 0 then
        print("|cffff0000[Reputation]|r Scan returned no data (API not ready?)")
        self.isScanning = false
        
        -- Clear loading state
        ns.ReputationLoadingState.isLoading = false
        
        -- Retry after delay
        C_Timer.After(5, function()
            if ReputationCache then
                ReputationCache:PerformFullScan(true)
            end
        end)
        return
    end
    
    -- Update progress
    ns.ReputationLoadingState.loadingProgress = 33
    ns.ReputationLoadingState.currentStage = string.format("Processing %d factions...", #rawData)
    
    -- Process data
    local normalizedData = {}
    local updateInterval = math.max(10, math.floor(#rawData / 10))  -- Update every 10% or at least every 10 items
    
    for i, raw in ipairs(rawData) do
        local normalized = Processor:Process(raw)
        if normalized then
            table.insert(normalizedData, normalized)
        end
        
        -- Update progress and refresh UI periodically
        if i % updateInterval == 0 then
            local progress = 33 + math.floor((i / #rawData) * 33)  -- 33-66%
            ns.ReputationLoadingState.loadingProgress = progress
            ns.ReputationLoadingState.currentStage = string.format("Processing... (%d/%d)", i, #rawData)
            
            -- Trigger UI refresh to show progress updates
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_REPUTATION_LOADING_STARTED")
            end
        end
    end
    
    -- Update DB
    ns.ReputationLoadingState.loadingProgress = 66
    ns.ReputationLoadingState.currentStage = "Saving to database..."
    self:UpdateAll(normalizedData)
    
    -- Complete - clear loading state immediately
    ns.ReputationLoadingState.isLoading = false
    ns.ReputationLoadingState.loadingProgress = 100
    ns.ReputationLoadingState.currentStage = "Complete!"
    
    self.isScanning = false
    
    print(string.format("|cff00ff00[Reputation]|r Scan complete: %d factions processed", #normalizedData))
    
    -- Fire cache ready event (will trigger UI refresh)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_REPUTATION_CACHE_READY")
        WarbandNexus:SendMessage("WN_REPUTATION_UPDATED")
    end
end

-- ============================================================================
-- PUBLIC API (Attached to WarbandNexus)
-- ============================================================================

---Get all normalized reputation data (ALL characters)
---@return table Array of normalized faction data with _characterKey metadata
function WarbandNexus:GetAllReputations()
    local db = GetDB()
    if not db then return {} end
    
    local result = {}
    
    -- Add account-wide reputations
    for factionID, data in pairs(db.accountWide) do
        local entry = {}
        for k, v in pairs(data) do
            entry[k] = v
        end
        entry._characterKey = "Account-Wide"
        entry.isAccountWide = true
        table.insert(result, entry)
    end
    
    -- Add character-specific reputations (from ALL characters)
    for charKey, charFactions in pairs(db.characters) do
        -- Get character class
        local charClass = "WARRIOR"
        if WarbandNexus.db.global.characters then
            for _, char in pairs(WarbandNexus.db.global.characters) do
                local cKey = (char.name or "") .. "-" .. (char.realm or "")
                if cKey == charKey then
                    charClass = char.class or char.classFile or "WARRIOR"
                    charClass = string.upper(charClass)
                    break
                end
            end
        end
        
        for factionID, data in pairs(charFactions) do
            local entry = {}
            for k, v in pairs(data) do
                entry[k] = v
            end
            entry._characterKey = charKey
            entry._characterClass = charClass
            entry.isAccountWide = false
            table.insert(result, entry)
        end
    end
    
    return result
end

---Get reputation headers (for hierarchical display)
---@return table Array of {name, factions=[factionID, ...]}
function WarbandNexus:GetReputationHeaders()
    return ReputationCache:GetHeaders()
end

---Get single faction by ID
---@param factionID number
---@return table|nil Normalized faction data
function WarbandNexus:GetReputation(factionID)
    return ReputationCache:GetFaction(factionID)
end

---Trigger full reputation scan
function WarbandNexus:ScanReputations()
    ReputationCache:PerformFullScan(false)
end

---Clear reputation cache
function WarbandNexus:ClearReputationCache()
    ReputationCache:Clear(true)
end

-- ============================================================================
-- DEBUG VERIFICATION COMMANDS
-- ============================================================================

---Global debug function: Verify reputation data storage and retrieval
---Usage: /run WNVerifyReputationData(factionID)
_G.WNVerifyReputationData = function(factionID)
    if not factionID then
        print("|cffff0000[RepVerify]|r Usage: /run WNVerifyReputationData(factionID)")
        return
    end
    
    local WarbandNexus = ns.WarbandNexus
    if not WarbandNexus or not WarbandNexus.db then
        print("|cffff0000[RepVerify]|r WarbandNexus not loaded")
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[RepVerify]|r DB not initialized")
        return
    end
    
    -- Get faction name
    local factionName = "Unknown"
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local factionData = C_Reputation.GetFactionDataByID(factionID)
        if factionData then
            factionName = factionData.name or "Unknown"
        end
    end
    
    print("|cff00ff00[RepVerify]|r Faction: " .. factionName .. " (ID:" .. factionID .. ")")
    print("=====================================")
    
    -- Check account-wide storage
    local accountWideData = db.accountWide[factionID]
    if accountWideData then
        print("|cffffcc00[Storage]|r Account-Wide (db.accountWide[" .. factionID .. "])")
        print("  isAccountWide: " .. tostring(accountWideData.isAccountWide))
        print("  Type: " .. (accountWideData.type or "unknown"))
        print("  Standing: " .. (accountWideData.standingName or "unknown"))
        print("  Progress: " .. (accountWideData.currentValue or 0) .. "/" .. (accountWideData.maxValue or 1))
    else
        print("|cff666666[Storage]|r NOT in account-wide storage")
    end
    
    -- Check character-specific storage
    print("")
    print("|cffffcc00[Character Storage]|r")
    local charCount = 0
    local highestChar = nil
    local highestProgress = -1
    
    for charKey, charFactions in pairs(db.characters) do
        local charData = charFactions[factionID]
        if charData then
            charCount = charCount + 1
            print("  " .. charKey .. ":")
            print("    isAccountWide: " .. tostring(charData.isAccountWide))
            print("    Type: " .. (charData.type or "unknown"))
            print("    Standing: " .. (charData.standingName or "unknown"))
            print("    Progress: " .. (charData.currentValue or 0) .. "/" .. (charData.maxValue or 1))
            
            -- Track highest
            local progress = charData.currentValue or 0
            if progress > highestProgress then
                highestProgress = progress
                highestChar = charKey
            end
        end
    end
    
    if charCount == 0 then
        print("  (None)")
    else
        print("")
        print("|cff00ff00[Highest Progress]|r " .. (highestChar or "None"))
    end
    
    -- Check UI data (GetAllReputations)
    print("")
    print("|cffffcc00[UI Data (GetAllReputations)]|r")
    local allReps = WarbandNexus:GetAllReputations()
    local found = false
    for _, rep in ipairs(allReps) do
        if rep.factionID == factionID then
            found = true
            print("  Character: " .. (rep._characterKey or "Unknown"))
            print("  isAccountWide: " .. tostring(rep.isAccountWide))
            print("  Type: " .. (rep.type or "unknown"))
            print("  Standing: " .. (rep.standingName or "unknown"))
            print("  Progress: " .. (rep.currentValue or 0) .. "/" .. (rep.maxValue or 1))
            print("  ---")
        end
    end
    
    if not found then
        print("  (Not found in GetAllReputations)")
    end
    
    print("=====================================")
end

---Global debug function: List all factions in storage
---Usage: /run WNListStoredReputations()
_G.WNListStoredReputations = function()
    local WarbandNexus = ns.WarbandNexus
    if not WarbandNexus or not WarbandNexus.db then
        print("|cffff0000[RepVerify]|r WarbandNexus not loaded")
        return
    end
    
    local db = GetDB()
    if not db then
        print("|cffff0000[RepVerify]|r DB not initialized")
        return
    end
    
    -- Count account-wide
    local awCount = 0
    for _ in pairs(db.accountWide) do
        awCount = awCount + 1
    end
    
    -- Count character-specific
    local charCounts = {}
    local totalChar = 0
    for charKey, charFactions in pairs(db.characters) do
        local count = 0
        for _ in pairs(charFactions) do
            count = count + 1
        end
        charCounts[charKey] = count
        totalChar = totalChar + count
    end
    
    print("|cff00ff00[Stored Reputations]|r")
    print("=====================================")
    print("Account-Wide: " .. awCount .. " factions")
    print("Character-Specific: " .. totalChar .. " factions")
    print("")
    for charKey, count in pairs(charCounts) do
        print("  " .. charKey .. ": " .. count .. " factions")
    end
    print("=====================================")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

ns.ReputationCache = ReputationCache

-- NOTE: Initialize() is called from Core.lua OnEnable() after DB is ready
-- Do NOT call Initialize() here - WarbandNexus.db may not be loaded yet
