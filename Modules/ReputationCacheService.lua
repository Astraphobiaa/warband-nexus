--[[
    Warband Nexus - Reputation Cache Service
    
    Persistent DB-backed reputation cache with event-driven updates.
    Follows CollectionService pattern for consistency.
    
    Provides:
    1. DB-backed persistent cache (survives /reload)
    2. Event-driven incremental updates (no full API scans)
    3. Support for Classic/Friendship/Paragon/Renown systems
    4. Real-time updates when reputation changes
    5. Optimized C_Reputation API usage
    
    Events monitored:
    - UPDATE_FACTION: Standard reputation changes
    - MAJOR_FACTION_RENOWN_LEVEL_CHANGED: Renown system updates
    
    Cache structure:
    {
      factions = {
        [factionID] = {
          name, standing, currentValue, maxValue,
          isParagon, isMaxed, isMajorFaction,
          renownLevel, renownReputationEarned, renownLevelThreshold
        }
      },
      version = "1.1.1",
      lastUpdate = timestamp
    }
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Debug print helper (only prints if debug mode enabled)
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        print(...)
    end
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local CACHE_VERSION = Constants.REPUTATION_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.REPUTATION_UPDATE

-- ============================================================================
-- REPUTATION CACHE (PERSISTENT IN DB)
-- ============================================================================

local reputationCache = {
    factions = {},
    version = CACHE_VERSION,
    lastUpdate = 0,
}

local updateThrottleTimer = nil
local isAborted = false  -- Flag to abort ongoing operations

-- ============================================================================
-- ABORT PROTOCOL (for tab switches)
-- ============================================================================

---Abort ongoing reputation operations (called when switching away from Reputations tab)
function WarbandNexus:AbortReputationOperations()
    -- Cancel throttle timer if active
    if updateThrottleTimer then
        updateThrottleTimer:Cancel()
        updateThrottleTimer = nil
    end
    
    -- Set abort flag (UpdateAllFactions will check this and log if interrupted)
    isAborted = true
end

-- ============================================================================
-- CACHE INITIALIZATION (Load from DB)
-- ============================================================================

---Initialize reputation cache from DB (load persisted data)
---Called on addon load to restore previous cache
function WarbandNexus:InitializeReputationCache()
    local debugMode = self.db and self.db.profile and self.db.profile.debugMode
    
    -- Initialize DB structure if needed
    if not self.db.global.reputationCache then
        self.db.global.reputationCache = {
            factions = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
        if debugMode then
    DebugPrint("|cff9370DB[WN ReputationCache]|r Initialized empty reputation cache in DB")
        end
        reputationCache._needsRefresh = true
        return
    end
    
    -- Load from DB
    local dbCache = self.db.global.reputationCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        if debugMode then
    DebugPrint("|cffffcc00[WN ReputationCache]|r Cache version mismatch (DB: " .. tostring(dbCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
        end
        self.db.global.reputationCache = {
            factions = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
        reputationCache._needsRefresh = true
        return
    end
    
    -- Load factions cache from DB to RAM
    reputationCache.factions = dbCache.factions or {}
    reputationCache.lastUpdate = dbCache.lastUpdate or 0
    
    -- Count loaded factions (debug mode only)
    if debugMode then
        local factionCount = 0
        for _ in pairs(reputationCache.factions) do factionCount = factionCount + 1 end
        
        if factionCount > 0 then
            local age = time() - reputationCache.lastUpdate
    DebugPrint("|cff00ff00[WN ReputationCache]|r Loaded " .. factionCount .. " factions from DB (age: " .. age .. "s)")
            
            -- CRITICAL: If cache is older than 1 hour OR has no Friendship factions, force refresh
            -- This ensures new Friendship faction support is applied to old caches
            local hasFriendship = false
            for _, faction in pairs(reputationCache.factions) do
                if faction.isFriendship then
                    hasFriendship = true
                    break
                end
            end
            
            local MAX_CACHE_AGE = 3600  -- 1 hour
            if age > MAX_CACHE_AGE then
    DebugPrint("|cffffcc00[WN ReputationCache]|r Cache is stale (>" .. (MAX_CACHE_AGE / 60) .. " minutes), will refresh on next update")
                reputationCache._needsRefresh = true
            elseif not hasFriendship then
    DebugPrint("|cffffcc00[WN ReputationCache]|r Cache has no Friendship factions, will add them on next update")
                reputationCache._needsRefresh = true
            end
        end
    else
        -- Still check for stale cache/missing Friendship data, just don't print
        local factionCount = 0
        for _ in pairs(reputationCache.factions) do factionCount = factionCount + 1 end
        
        if factionCount > 0 then
            local age = time() - reputationCache.lastUpdate
            local MAX_CACHE_AGE = 3600  -- 1 hour
            
            if age > MAX_CACHE_AGE then
                reputationCache._needsRefresh = true
            else
                -- Check for Friendship factions
                local hasFriendship = false
                for _, faction in pairs(reputationCache.factions) do
                    if faction.isFriendship then
                        hasFriendship = true
                        break
                    end
                end
                if not hasFriendship then
                    reputationCache._needsRefresh = true
                end
            end
        end
    end
end

---Save reputation cache to DB (persist to SavedVariables)
---@param reason string Optional reason for save (for debugging)
local function SaveReputationCache(reason)
    if not WarbandNexus.db or not WarbandNexus.db.global then
    DebugPrint("|cffff0000[WN ReputationCache]|r Cannot save: DB not initialized")
        return
    end
    
    reputationCache.lastUpdate = time()
    
    WarbandNexus.db.global.reputationCache = {
        factions = reputationCache.factions,
        version = CACHE_VERSION,
        lastUpdate = reputationCache.lastUpdate
    }
    
    -- Only log for manual/full updates (not incremental)
    if reason and (reason:find("manual") or reason:find("full")) then
        local totalCount = 0
        for _ in pairs(reputationCache.factions) do totalCount = totalCount + 1 end
    DebugPrint("|cff00ff00[WN ReputationCache]|r Saved to DB (total: " .. totalCount .. " factions)")
    end
end

-- ============================================================================
-- REPUTATION DATA RETRIEVAL
-- ============================================================================

---Get reputation data for a specific faction
---@param factionID number Faction ID
---@param indexData table|nil Optional faction data from GetFactionDataByIndex (has currentStanding)
---@return table|nil Faction data or nil if not found
local function GetFactionData(factionID, indexData)
    if not factionID or factionID == 0 then return nil end
    
    -- PRIORITY 1: Check if Friendship faction (special reputation system)
    -- Friendship factions (e.g., Bilgewater Cartel, Darkfuse Solutions) use a different API
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
        
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            -- CRITICAL: Validate friendInfo has required data
            if not friendInfo.name or friendInfo.name == "" then
                -- Invalid Friendship data, skip
                return nil
            end
            
            -- This is a Friendship faction
            local ranksInfo = C_GossipInfo.GetFriendshipReputationRanks and 
                              C_GossipInfo.GetFriendshipReputationRanks(factionID)
            
            -- CRITICAL FIX: Friendship uses NORMALIZED values (current standing within current rank)
            local currentValue = 0
            local maxValue = 1
            
            if friendInfo.standing and friendInfo.nextThreshold then
                -- Calculate progress within current rank
                currentValue = friendInfo.standing
                maxValue = friendInfo.nextThreshold
            elseif friendInfo.maxRep and friendInfo.maxRep > 0 then
                -- Fallback: use maxRep as threshold
                currentValue = friendInfo.standing or 0
                maxValue = friendInfo.maxRep
            end
            
            local currentLevel = 1
            local maxLevel = nil
            
            -- Extract level information
            if ranksInfo then
                currentLevel = ranksInfo.currentLevel or 1
                maxLevel = ranksInfo.maxLevel
            elseif friendInfo.text then
                -- Fallback: extract from text (e.g., "Level 5/8")
                local levelMatch = friendInfo.text:match("Level (%d+)")
                if levelMatch then
                    currentLevel = tonumber(levelMatch)
                end
            end
            
            local data = {
                factionID = factionID,
                name = friendInfo.name or ("Faction " .. tostring(factionID)),
                standing = friendInfo.reaction or 4,  -- Friendship uses reaction field
                currentValue = currentValue,
                maxValue = maxValue,
                isParagon = false,
                isMaxed = false,
                isMajorFaction = true,  -- Friendship factions are treated like major factions
                isHeaderWithRep = false,
                isAccountWide = false,  -- Friendship factions are character-specific
                icon = friendInfo.texture or nil,
                -- Store Friendship-specific data
                renownLevel = currentLevel,
                renownMaxLevel = maxLevel,
                isFriendship = true,  -- Flag to identify Friendship factions
                rankName = friendInfo.reaction,  -- CRITICAL: Use reaction field directly (e.g., "Stranger", "Rank 1", "Max Rank")
            }
            
            return data
        end
    end
    
    -- PRIORITY 2: Standard reputation (Classic/Paragon)
    -- CRITICAL: Merge data from BOTH APIs
    -- GetFactionDataByID: currentReactionThreshold, nextReactionThreshold (thresholds only)
    -- GetFactionDataByIndex: currentStanding (actual rep value) - passed as indexData
    
    local factionData = indexData or (C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionID))
    if not factionData then return nil end
    
    -- CRITICAL: Validate factionData has required fields
    if not factionData.name or factionData.name == "" then
        -- Invalid faction data (header entry or corrupted data)
        return nil
    end
    
    -- CRITICAL FIX: Normalize reputation values using currentStanding
    -- If currentStanding is missing, we cannot normalize properly
    local normalizedCurrent = 0
    local normalizedMax = 0
    
    if factionData.currentStanding and factionData.currentReactionThreshold and factionData.nextReactionThreshold then
        normalizedCurrent = factionData.currentStanding - factionData.currentReactionThreshold
        normalizedMax = factionData.nextReactionThreshold - factionData.currentReactionThreshold
    elseif factionData.currentStanding and factionData.currentStanding > 0 then
        -- CRITICAL FIX: If thresholds are missing or 0 but currentStanding exists, use RAW value
        -- This happens with isHeaderWithRep factions (Cartels, Severed Threads)
        -- They have currentStanding but no thresholds (use custom progression system)
        normalizedCurrent = factionData.currentStanding
        normalizedMax = 10000  -- Default max for header factions (might be overridden by Major Faction data)
    elseif factionData.currentReactionThreshold and factionData.nextReactionThreshold then
        -- Fallback: If currentStanding missing, assume we're at threshold (0 progress)
        normalizedCurrent = 0
        normalizedMax = factionData.nextReactionThreshold - factionData.currentReactionThreshold
    end
    
    local data = {
        factionID = factionID,
        name = factionData.name,
        standing = factionData.reaction,  -- 1-8 (Hated -> Exalted)
        currentValue = normalizedCurrent,  -- FIX: Normalized progress (0-based within standing)
        maxValue = normalizedMax,          -- FIX: Normalized max (standing range, e.g., 6000 for Friendly)
        isParagon = factionData.isParagon or false,
        isMaxed = false,
        isMajorFaction = false,
        isHeaderWithRep = factionData.isHeaderWithRep or false,
        isAccountWide = factionData.isAccountWide or false,
        icon = factionData.icon or nil,  -- Store icon if available
        isFriendship = false,  -- Not a Friendship faction (standard rep)
    }
    
    -- PARAGON SUPPORT (Exalted factions with repeatable rewards)
    if C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID) then
        data.isParagon = true
        local paragonValue, paragonThreshold, rewardQuestID, hasRewardPending = C_Reputation.GetFactionParagonInfo(factionID)
        
        -- CRITICAL FIX: Only override if paragonValue/paragonThreshold are VALID
        -- Some factions (e.g., Bilgewater Cartel ID 2673) incorrectly report as Paragon
        -- but return invalid data (0/10000). Skip override in these cases.
        if paragonValue and paragonThreshold and paragonValue > 0 and paragonThreshold > 0 then
            -- Paragon uses modulo to get current cycle progress
            data.paragonValue = paragonValue % paragonThreshold
            data.paragonThreshold = paragonThreshold
            data.paragonRewardPending = hasRewardPending or false
            
            -- Override currentValue/maxValue to show paragon progress
            data.currentValue = data.paragonValue
            data.maxValue = data.paragonThreshold
        else
            -- Reset isParagon flag if data is invalid
            data.isParagon = false
        end
    end
    
    -- Check if maxed (Exalted with no paragon, or max paragon)
    if data.standing == 8 then -- Exalted
        if not data.isParagon then
            data.isMaxed = true
        elseif data.currentValue >= data.maxValue and data.maxValue > 0 then
            data.isMaxed = true
        end
    end
    
    -- Check for Major Faction (Renown system)
    if C_MajorFactions then
        local majorFactionData = C_MajorFactions.GetMajorFactionData(factionID)
        
        if majorFactionData then
            data.isMajorFaction = true
            data.renownLevel = majorFactionData.renownLevel or 0
            data.renownReputationEarned = majorFactionData.renownReputationEarned or 0
            data.renownLevelThreshold = majorFactionData.renownLevelThreshold or 0
            
            -- For major factions, use renown as progress
            data.currentValue = data.renownReputationEarned
            data.maxValue = data.renownLevelThreshold
        end
    end
    
    return data
end

---Update a single faction in cache (incremental update)
---@param factionID number Faction ID to update
---@param indexData table|nil Optional faction data from GetFactionDataByIndex (has currentStanding)
---@return boolean success True if updated successfully
local function UpdateFactionInCache(factionID, indexData)
    if not factionID or factionID == 0 then return false end
    
    local factionData = GetFactionData(factionID, indexData)
    if not factionData then
        -- Silently skip - might be a header or invalid entry
        return false
    end
    
    -- Store in cache
    reputationCache.factions[factionID] = factionData
    
    return true
end

---Update all visible factions in cache (full refresh, throttled)
---@param saveToDb boolean Whether to save to DB after update
---@param expandHeaders boolean Whether to expand collapsed headers (only on initial scan)
local function UpdateAllFactions(saveToDb, expandHeaders)
    -- Reset abort flag at start
    isAborted = false
    
    local updatedCount = 0
    local startTime = debugprofilestop()
    
    -- STEP 0: Expand all faction headers ONLY on initial scan
    -- This ensures collapsed sections don't prevent data collection
    -- But we DON'T do this on every event (causes FPS drops)
    if expandHeaders and C_Reputation.ExpandAllFactionHeaders then
        C_Reputation.ExpandAllFactionHeaders()
    end
    
    -- STEP 1: Scan standard reputation list
    -- CRITICAL: Use GetFactionDataByIndex to iterate (provides currentStanding)
    if not C_Reputation.GetFactionDataByIndex then return end
    
    -- Track all scanned faction IDs to avoid duplicates
    local scannedFactions = {}
    
    local index = 1
    local maxIterations = 500  -- Realistic limit (no expansion has 500+ factions)
    local consecutiveInvalid = 0  -- Track consecutive invalid entries
    local MAX_CONSECUTIVE_INVALID = 50  -- Stop after 50 consecutive invalid entries
    
    while index <= maxIterations do
        -- Check if operation was aborted (tab switch)
        if isAborted then
    DebugPrint("|cffffcc00[WN ReputationCache]|r Scan STOPPED mid-operation (tab switch detected, " .. updatedCount .. " factions processed)")
            isAborted = false  -- Reset flag
            return
        end
        
        local factionData = C_Reputation.GetFactionDataByIndex(index)
        if not factionData then
            -- Normal exit - reached end of list
            break
        end
        
        -- CRITICAL: Skip invalid faction entries (0 factionID, nil name)
        if factionData.factionID and factionData.factionID > 0 and factionData.name then
            scannedFactions[factionData.factionID] = true
            consecutiveInvalid = 0  -- Reset counter on valid entry
            
            -- Pass factionData directly (it has currentStanding from GetFactionDataByIndex)
            if UpdateFactionInCache(factionData.factionID, factionData) then
                updatedCount = updatedCount + 1
            end
        else
            -- Invalid entry (header or corrupted data)
            consecutiveInvalid = consecutiveInvalid + 1
            
            -- If we hit too many consecutive invalid entries, assume list ended
            if consecutiveInvalid >= MAX_CONSECUTIVE_INVALID then
                break
            end
        end
        
        index = index + 1
    end
    
    -- After loop ends, log warning only if we hit the absolute limit (very unlikely)
    if index > maxIterations then
    DebugPrint("|cffff0000[WN ReputationCache]|r WARNING: Hit max iterations limit (" .. maxIterations .. "). This should never happen.")
    end
    
    -- STEP 2: Check each scanned faction for Friendship status
    -- Friendship factions sometimes appear in reputation list but with 0 data
    -- We need to query them separately using Friendship API
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendshipFound = 0
        
        for factionID in pairs(scannedFactions) do
            local cachedData = reputationCache.factions[factionID]
            
            -- Re-check factions with 0 data or no data
            if not cachedData or (cachedData.currentValue == 0 and cachedData.maxValue == 0) then
                local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
                if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
                    -- This faction is a Friendship faction - update it with Friendship API
                    if UpdateFactionInCache(factionID, nil) then
                        friendshipFound = friendshipFound + 1
                    end
                end
            end
        end
        
        -- Only log if Friendship factions were found
        if friendshipFound > 0 then
    DebugPrint("|cff9370DB[WN ReputationCache]|r Re-cached " .. friendshipFound .. " Friendship factions (had 0 data)")
        end
    end
    
    local elapsed = debugprofilestop() - startTime
    
    if saveToDb and updatedCount > 0 then
        SaveReputationCache("full update")
    end
    
    -- Only log for significant scans (initial/manual)
    if expandHeaders or updatedCount > 100 then
    DebugPrint("|cff9370DB[WN ReputationCache]|r Scanned API: " .. updatedCount .. " factions updated (" .. math.floor(elapsed) .. "ms)")
    end
    
    -- Fire event for UI updates (AceEvent)
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WARBAND_REPUTATIONS_UPDATED")
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

---Handle UPDATE_FACTION event (throttled)
---@param factionIndex number|nil Faction index (may be nil)
local function OnFactionUpdate(factionIndex)
    -- Cancel previous throttle timer
    if updateThrottleTimer then
        updateThrottleTimer:Cancel()
    end
    
    -- Throttle updates (reputation can change rapidly during combat)
    updateThrottleTimer = C_Timer.NewTimer(UPDATE_THROTTLE, function()
        if factionIndex and factionIndex > 0 then
            -- INCREMENTAL UPDATE: Only update the specific faction (fast)
            local factionData = C_Reputation.GetFactionDataByIndex(factionIndex)
            if factionData and factionData.factionID then
                if UpdateFactionInCache(factionData.factionID, factionData) then
                    SaveReputationCache("incremental")
                    
                    -- Fire event for UI updates (AceEvent)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage("WARBAND_REPUTATIONS_UPDATED")
                    end
                end
            end
        else
            -- FULL UPDATE: Only when factionIndex is nil (rare, e.g., on login)
            UpdateAllFactions(true)
        end
        
        updateThrottleTimer = nil
    end)
end

---Handle MAJOR_FACTION_RENOWN_LEVEL_CHANGED event
---@param majorFactionID number Major faction ID
local function OnRenownLevelChanged(majorFactionID)
    if not majorFactionID or majorFactionID == 0 then return end
    
    if UpdateFactionInCache(majorFactionID) then
        SaveReputationCache("renown")
        
        -- Fire event for UI updates (AceEvent)
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WARBAND_REPUTATIONS_UPDATED")
        end
    end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

---Update a single faction in cache (PUBLIC API for incremental updates)
---@param factionID number Faction ID to update
---@return boolean success True if updated successfully
function WarbandNexus:UpdateReputationFaction(factionID)
    if not factionID or factionID == 0 then return false end
    
    -- OPTIMIZATION: Skip if not on Reputations tab (silent)
    if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab ~= "reputations" then
        return false
    end
    
    local success = UpdateFactionInCache(factionID, nil)
    if success then
        SaveReputationCache("incremental: faction " .. tostring(factionID))
        
        -- Fire event for UI updates (AceEvent)
        if self.SendMessage then
            self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
        end
    end
    
    return success
end

---Get reputation data for a specific faction (from cache or live)
---@param factionID number Faction ID
---@return table|nil Faction data
function WarbandNexus:GetReputationData(factionID)
    if not factionID or factionID == 0 then return nil end
    
    -- Return from cache if available
    if reputationCache.factions[factionID] then
        return reputationCache.factions[factionID]
    end
    
    -- Cache miss - fetch live and cache it
    local factionData = GetFactionData(factionID)
    if factionData then
        reputationCache.factions[factionID] = factionData
    end
    
    return factionData
end

---Get all cached reputation data
---@return table Cached factions
function WarbandNexus:GetAllReputationData()
    return reputationCache.factions
end

---Manually refresh reputation cache (useful for UI refresh buttons)
---@param force boolean|nil If true, force full refresh even if cache is recent
function WarbandNexus:RefreshReputationCache(force)
    -- OPTIMIZATION: Skip if not on Reputations tab (unless forced)
    if not force then
        if self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab ~= "reputations" then
            -- Silent skip - user is on different tab, cache will update when they return
            return
        end
    end
    
    -- Check cache age to prevent unnecessary refreshes
    local cacheAge = time() - reputationCache.lastUpdate
    local MIN_REFRESH_INTERVAL = 5  -- Minimum 5 seconds between auto-refreshes
    
    if not force and cacheAge < MIN_REFRESH_INTERVAL then
        -- Cache is fresh enough, skip refresh
        return
    end
    
    UpdateAllFactions(true, false)  -- saveToDb=true, expandHeaders=false (no need to expand on manual refresh)
end

---Clear reputation cache (for testing/debugging)
function WarbandNexus:ClearReputationCache()
    reputationCache.factions = {}
    reputationCache.lastUpdate = 0
    
    if self.db and self.db.global then
        self.db.global.reputationCache = {
            factions = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
    end
    
    DebugPrint("|cffffcc00[WN ReputationCache]|r Cache cleared")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Register reputation cache events
---NOTE: Event listening is handled by EventManager.lua which calls RefreshReputationCache()
---This function only performs initial cache population
function WarbandNexus:RegisterReputationCacheEvents()
    -- Service ready (verbose logging removed)
    
    -- Initial population (delayed to ensure UI is ready)
    C_Timer.After(2, function()
        local factionCount = 0
        for _ in pairs(reputationCache.factions) do factionCount = factionCount + 1 end
        
        -- CRITICAL: Always refresh if cache is stale or missing Friendship factions
        if factionCount == 0 or reputationCache.lastUpdate == 0 or reputationCache._needsRefresh then
    DebugPrint("|cff9370DB[WN ReputationCache]|r Performing initial cache population/refresh")
            UpdateAllFactions(true, true)  -- saveToDb=true, expandHeaders=true (initial scan only)
            reputationCache._needsRefresh = false
        else
            -- Cache already populated (verbose logging removed)
        end
    end)
end

-- ============================================================================
-- REPUTATION DATA BUILDERS (Moved from DataService.lua)
-- ============================================================================

--[[
    Build Friendship reputation data from API response
    @param factionID number - Faction ID
    @param friendInfo table - Response from C_GossipInfo.GetFriendshipReputation()
    @return table - Reputation progress data
]]
function WarbandNexus:BuildFriendshipData(factionID, friendInfo)
    if not friendInfo then return nil end
    
    local ranksInfo = C_GossipInfo.GetFriendshipReputationRanks and 
                      C_GossipInfo.GetFriendshipReputationRanks(factionID)
    
    local renownLevel = 1
    local renownMaxLevel = nil
    local rankName = nil
    local currentValue = friendInfo.standing or 0
    local maxValue = friendInfo.maxRep or 1
    
    -- Handle named ranks (e.g. "Mastermind") vs numbered ranks
    if type(friendInfo.reaction) == "string" then
        rankName = friendInfo.reaction
    else
        renownLevel = friendInfo.reaction or 1
    end
    
    -- Extract level from text if available
    if friendInfo.text then
        local levelMatch = friendInfo.text:match("Level (%d+)")
        if levelMatch then
            renownLevel = tonumber(levelMatch)
        end
        local maxLevelMatch = friendInfo.text:match("Level %d+/(%d+)")
        if maxLevelMatch then
            renownMaxLevel = tonumber(maxLevelMatch)
        end
    end
    
    -- Use GetFriendshipReputationRanks for max level
    if ranksInfo then
        if ranksInfo.maxLevel and ranksInfo.maxLevel > 0 then
            renownMaxLevel = ranksInfo.maxLevel
        end
        if ranksInfo.currentLevel and ranksInfo.currentLevel > 0 then
            renownLevel = ranksInfo.currentLevel
        end
    end
    
    -- Check Paragon
    local paragonValue, paragonThreshold, hasParagonReward = nil, nil, nil
    if C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID) then
        local pValue, pThreshold, _, hasPending = C_Reputation.GetFactionParagonInfo(factionID)
        if pValue and pThreshold then
            paragonValue = pValue % pThreshold
            paragonThreshold = pThreshold
            hasParagonReward = hasPending
        end
    end
    
    return {
        standingID = 8, -- Max standing for friendship
        currentValue = currentValue,
        maxValue = maxValue,
        renownLevel = renownLevel,
        renownMaxLevel = renownMaxLevel,
        rankName = rankName,
        isMajorFaction = true,
        isRenown = true,
        paragonValue = paragonValue,
        paragonThreshold = paragonThreshold,
        hasParagonReward = hasParagonReward,
        lastUpdated = time(),
    }
end

--[[
    Build Renown (Major Faction) reputation data from API response
    @param factionID number - Faction ID
    @param renownInfo table - Response from C_MajorFactions.GetMajorFactionRenownInfo()
    @return table - Reputation progress data
]]
function WarbandNexus:BuildRenownData(factionID, renownInfo)
    if not renownInfo then return nil end
    
    local renownLevel = renownInfo.renownLevel or 1
    local renownMaxLevel = nil
    local currentValue = renownInfo.renownReputationEarned or 0
    local maxValue = renownInfo.renownLevelThreshold or 1
    
    -- Determine max renown level
    if C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionID) then
        renownMaxLevel = renownLevel
        currentValue = 0
        maxValue = 1
    else
        -- Find max level by checking rewards
        if C_MajorFactions.GetRenownRewardsForLevel then
            for testLevel = renownLevel, 50 do
                local rewards = C_MajorFactions.GetRenownRewardsForLevel(factionID, testLevel)
                if rewards and #rewards > 0 then
                    renownMaxLevel = testLevel
                else
                    break
                end
            end
        end
    end
    
    -- Check Paragon
    local paragonValue, paragonThreshold, hasParagonReward = nil, nil, nil
    if C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID) then
        local pValue, pThreshold, _, hasPending = C_Reputation.GetFactionParagonInfo(factionID)
        if pValue and pThreshold then
            paragonValue = pValue % pThreshold
            paragonThreshold = pThreshold
            hasParagonReward = hasPending
        end
    end
    
    return {
        standingID = 8,
        currentValue = currentValue,
        maxValue = maxValue,
        renownLevel = renownLevel,
        renownMaxLevel = renownMaxLevel,
        isMajorFaction = true,
        isRenown = true,
        paragonValue = paragonValue,
        paragonThreshold = paragonThreshold,
        hasParagonReward = hasParagonReward,
        lastUpdated = time(),
    }
end

--[[
    Build Classic reputation data from API response
    @param factionID number - Faction ID
    @param factionData table - Response from C_Reputation.GetFactionDataByID()
    @return table - Reputation progress data
]]
function WarbandNexus:BuildClassicRepData(factionID, factionData)
    if not factionData then return nil end
    
    local standingID = factionData.reaction or 4
    local currentValue = factionData.currentReactionThreshold or 0
    local maxValue = factionData.nextReactionThreshold or 1
    local currentRep = factionData.currentStanding or 0
    
    -- Calculate actual progress within current standing
    if factionData.currentReactionThreshold and factionData.nextReactionThreshold then
        currentValue = currentRep - factionData.currentReactionThreshold
        maxValue = factionData.nextReactionThreshold - factionData.currentReactionThreshold
    end
    
    -- Check Paragon
    local paragonValue, paragonThreshold, hasParagonReward = nil, nil, nil
    if C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID) then
        local pValue, pThreshold, _, hasPending = C_Reputation.GetFactionParagonInfo(factionID)
        if pValue and pThreshold then
            paragonValue = pValue % pThreshold
            paragonThreshold = pThreshold
            hasParagonReward = hasPending
        end
    end
    
    return {
        standingID = standingID,
        currentValue = currentValue,
        maxValue = maxValue,
        atWarWith = factionData.atWarWith,
        isWatched = factionData.isWatched,
        paragonValue = paragonValue,
        paragonThreshold = paragonThreshold,
        hasParagonReward = hasParagonReward,
        lastUpdated = time(),
    }
end

-- Service loaded - verbose logging removed for normal users
