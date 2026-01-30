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

local CACHE_VERSION = "1.0.0"
local UPDATE_THROTTLE = 0.5  -- Throttle rapid reputation changes (0.5s)

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
    else
        print("|cff9370DB[WN ReputationCache]|r No cached reputation data, will populate on first update")
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
            
            local currentValue = friendInfo.standing or 0
            local maxValue = friendInfo.maxRep or 1
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
    elseif factionData.currentReactionThreshold and factionData.nextReactionThreshold then
        -- Fallback: If currentStanding missing, assume we're at threshold (0 progress)
        -- This happens with some factions where API doesn't provide currentStanding
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
        if paragonValue and paragonThreshold then
            -- Paragon uses modulo to get current cycle progress
            data.paragonValue = paragonValue % paragonThreshold
            data.paragonThreshold = paragonThreshold
            data.paragonRewardPending = hasRewardPending or false
            
            -- Override currentValue/maxValue to show paragon progress
            data.currentValue = data.paragonValue
            data.maxValue = data.paragonThreshold
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
local function UpdateAllFactions(saveToDb)
    local updatedCount = 0
    local startTime = debugprofilestop()
    
    -- STEP 1: Scan standard reputation list
    -- CRITICAL: Use GetFactionDataByIndex to iterate (provides currentStanding)
    if not C_Reputation.GetFactionDataByIndex then return end
    
    -- Track all scanned faction IDs to avoid duplicates
    local scannedFactions = {}
    
    local index = 1
    while true do
        local factionData = C_Reputation.GetFactionDataByIndex(index)
        if not factionData then break end
        
        if factionData.factionID and factionData.factionID > 0 then
            scannedFactions[factionData.factionID] = true
            
            -- Pass factionData directly (it has currentStanding from GetFactionDataByIndex)
            if UpdateFactionInCache(factionData.factionID, factionData) then
                updatedCount = updatedCount + 1
            end
        end
        
        index = index + 1
        
        -- Safety: prevent infinite loops
        if index > 1000 then
            print("|cffff0000[WN ReputationCache]|r Safety break at index 1000")
            break
        end
    end
    
    -- STEP 2: Check each scanned faction for Friendship status
    -- Friendship factions sometimes appear in reputation list but with 0 data
    -- We need to query them separately using Friendship API
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendshipFound = 0
        
        for factionID in pairs(scannedFactions) do
            local friendInfo = C_GossipInfo.GetFriendshipReputation(factionID)
            if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
                -- This faction is a Friendship faction - update it again with Friendship data
                local cachedData = reputationCache.factions[factionID]
                if not cachedData or cachedData.currentValue == 0 then
                    -- Re-scan with Friendship API (this will override standard rep data)
                    if UpdateFactionInCache(factionID, nil) then
                        friendshipFound = friendshipFound + 1
                    end
                end
            end
        end
        
        if friendshipFound > 0 then
            print("|cff9370DB[WN ReputationCache]|r Found and updated " .. friendshipFound .. " Friendship factions")
        end
    end
    
    local elapsed = debugprofilestop() - startTime
    print("|cff00ff00[WN ReputationCache]|r Updated " .. updatedCount .. " factions (" .. string.format("%.2f", elapsed) .. "ms)")
    
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
            -- Update specific faction
            local factionData = C_Reputation.GetFactionDataByIndex(factionIndex)
            if factionData and factionData.factionID then
                if UpdateFactionInCache(factionData.factionID) then
                    SaveReputationCache("faction update: " .. (factionData.name or "unknown"))
                    
                    -- Fire event for UI updates (AceEvent)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage("WARBAND_REPUTATIONS_UPDATED")
                        print("|cff00ccff[WN ReputationCache]|r Fired WARBAND_REPUTATIONS_UPDATED event (faction: " .. (factionData.name or "unknown") .. ")")
                    end
                end
            end
        else
            -- Full update (no specific faction index)
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
        SaveReputationCache("renown level changed")
        
        -- Fire event for UI updates (AceEvent)
        if WarbandNexus.SendMessage then
            WarbandNexus:SendMessage("WARBAND_REPUTATIONS_UPDATED")
            print("|cff00ccff[WN ReputationCache]|r Fired WARBAND_REPUTATIONS_UPDATED event (renown)")
        end
        
        print("|cff00ff00[WN ReputationCache]|r Renown level changed for faction: " .. tostring(majorFactionID))
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
    UpdateAllFactions(true)
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
        
        if factionCount == 0 or reputationCache.lastUpdate == 0 then
            print("|cff9370DB[WN ReputationCache]|r Performing initial cache population")
            UpdateAllFactions(true)
        else
            print("|cff00ff00[WN ReputationCache]|r Cache already populated (" .. factionCount .. " factions)")
        end
    end)
end

print("|cff00ff00[WN ReputationCache]|r Service loaded successfully")
