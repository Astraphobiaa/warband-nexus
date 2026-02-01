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

-- ============================================================================
-- CACHE INITIALIZATION (Load from DB)
-- ============================================================================

---Initialize reputation cache from DB (load persisted data)
---Called on addon load to restore previous cache
function WarbandNexus:InitializeReputationCache()
    -- Initialize DB structure if needed
    if not self.db.global.reputationCache then
        self.db.global.reputationCache = {
            factions = {},
            version = CACHE_VERSION,
            lastUpdate = 0
        }
        print("|cff9370DB[WN ReputationCache]|r Initialized empty reputation cache in DB")
        reputationCache._needsRefresh = true
        return
    end
    
    -- Load from DB
    local dbCache = self.db.global.reputationCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        print("|cffffcc00[WN ReputationCache]|r Cache version mismatch (DB: " .. tostring(dbCache.version) .. ", Code: " .. CACHE_VERSION .. "), clearing cache")
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
    
    -- Count loaded factions
    local factionCount = 0
    for _ in pairs(reputationCache.factions) do factionCount = factionCount + 1 end
    
    if factionCount > 0 then
        local age = time() - reputationCache.lastUpdate
        print("|cff00ff00[WN ReputationCache]|r Loaded " .. factionCount .. " factions from DB (age: " .. age .. "s)")
        
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
            print("|cffffcc00[WN ReputationCache]|r Cache is stale (>" .. (MAX_CACHE_AGE / 60) .. " minutes), will refresh on next update")
            reputationCache._needsRefresh = true
        elseif not hasFriendship then
            print("|cffffcc00[WN ReputationCache]|r Cache has no Friendship factions, will add them on next update")
            reputationCache._needsRefresh = true
        end
    else
        print("|cff9370DB[WN ReputationCache]|r No cached reputation data, will populate on first update")
        reputationCache._needsRefresh = true
    end
end

---Save reputation cache to DB (persist to SavedVariables)
---@param reason string Optional reason for save (for debugging)
local function SaveReputationCache(reason)
    if not WarbandNexus.db or not WarbandNexus.db.global then
        print("|cffff0000[WN ReputationCache]|r Cannot save: DB not initialized")
        return
    end
    
    reputationCache.lastUpdate = time()
    
    WarbandNexus.db.global.reputationCache = {
        factions = reputationCache.factions,
        version = CACHE_VERSION,
        lastUpdate = reputationCache.lastUpdate
    }
    
    local factionCount = 0
    for _ in pairs(reputationCache.factions) do factionCount = factionCount + 1 end
    
    local reasonStr = reason and (" (" .. reason .. ")") or ""
    print("|cff00ff00[WN ReputationCache]|r Saved " .. factionCount .. " factions to DB" .. reasonStr)
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
        print("|cffffcc00[WN ReputationCache]|r Failed to get data for factionID: " .. tostring(factionID))
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
    local maxIterations = 2000  -- Safety limit (prevents infinite loops if API bugs)
    
    while index <= maxIterations do
        local factionData = C_Reputation.GetFactionDataByIndex(index)
        if not factionData then
            -- Normal exit - reached end of list
            break
        end
        
        if factionData.factionID and factionData.factionID > 0 then
            scannedFactions[factionData.factionID] = true
            
            -- Pass factionData directly (it has currentStanding from GetFactionDataByIndex)
            if UpdateFactionInCache(factionData.factionID, factionData) then
                updatedCount = updatedCount + 1
            end
        end
        
        index = index + 1
    end
    
    -- After loop ends, check if we stopped because of limit or because list ended
    -- If list ended naturally, GetFactionDataByIndex(index) should return nil
    if index > maxIterations then
        -- We hit the limit - check if there's MORE data beyond the limit
        local nextFactionData = C_Reputation.GetFactionDataByIndex(index)
        if nextFactionData then
            -- There IS more data! Limit is too low
            print("|cffff0000[WN ReputationCache]|r WARNING: Scanned " .. (index-1) .. " factions but API still has more data. Increase maxIterations if needed.")
        end
        -- If nextFactionData is nil, we reached the end exactly at the limit (no warning needed)
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
        
        if friendshipFound > 0 then
            print("|cff9370DB[WN ReputationCache]|r Re-cached " .. friendshipFound .. " Friendship factions (had 0 data)")
        end
    end
    
    local elapsed = debugprofilestop() - startTime
    
    if saveToDb and updatedCount > 0 then
        SaveReputationCache("full update")
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
function WarbandNexus:RefreshReputationCache()
    print("|cff9370DB[WN ReputationCache]|r Manual cache refresh requested")
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
    
    print("|cffffcc00[WN ReputationCache]|r Cache cleared")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Register reputation cache events
---NOTE: Event listening is handled by EventManager.lua which calls RefreshReputationCache()
---This function only performs initial cache population
function WarbandNexus:RegisterReputationCacheEvents()
    print("|cff00ff00[WN ReputationCache]|r Service ready (EventManager will trigger updates)")
    
    -- Initial population (delayed to ensure UI is ready)
    C_Timer.After(2, function()
        local factionCount = 0
        for _ in pairs(reputationCache.factions) do factionCount = factionCount + 1 end
        
        -- CRITICAL: Always refresh if cache is stale or missing Friendship factions
        if factionCount == 0 or reputationCache.lastUpdate == 0 or reputationCache._needsRefresh then
            print("|cff9370DB[WN ReputationCache]|r Performing initial cache population/refresh")
            UpdateAllFactions(true, true)  -- saveToDb=true, expandHeaders=true (initial scan only)
            reputationCache._needsRefresh = false
        else
            print("|cff00ff00[WN ReputationCache]|r Cache already populated (" .. factionCount .. " factions)")
        end
    end)
end

print("|cff00ff00[WN ReputationCache]|r Service loaded successfully")
