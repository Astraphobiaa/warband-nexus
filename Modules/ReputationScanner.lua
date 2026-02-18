--[[
    Warband Nexus - Reputation Scanner (Pure API Layer)
    
    Responsibilities:
    - Fetch raw data from WoW API
    - Zero business logic
    - Zero data transformation
    - Pure data collection
    
    Architecture: API → Scanner → Processor → Cache → UI
]]

local ADDON_NAME, ns = ...

-- ============================================================================
-- DEBUG HELPER
-- ============================================================================

local function DebugPrint(...)
    if ns.WarbandNexus and ns.WarbandNexus.db and ns.WarbandNexus.db.profile and ns.WarbandNexus.db.profile.debugMode then
        print("|cff00ff00[RepScanner]|r", ...)
    end
end

-- ============================================================================
-- REPUTATION SCANNER (Pure API Layer)
-- ============================================================================

local ReputationScanner = {}
ns.ReputationScanner = ReputationScanner

-- ============================================================================
-- CORE API: Fetch Single Faction
-- ============================================================================

---Fetch faction data from Blizzard API
---@param factionID number
---@return table|nil Raw API data (unmodified)
--- @param factionID number
--- @param indexDescription string|nil Optional description from GetFactionDataByIndex (avoids O(n) inner lookup)
function ReputationScanner:FetchFaction(factionID, indexDescription)
    if not factionID or type(factionID) ~= "number" or factionID <= 0 then
        return nil
    end
    
    if not C_Reputation or not C_Reputation.GetFactionDataByID then
        return nil
    end
    
    -- Fetch base faction data
    local success, factionData = pcall(C_Reputation.GetFactionDataByID, factionID)
    if not success or not factionData or not factionData.name then
        return nil
    end
    
    -- Use the longer description between GetFactionDataByID and the pre-fetched index description
    local fullDescription = factionData.description or ""
    if indexDescription and indexDescription ~= "" and #indexDescription > #fullDescription then
        fullDescription = indexDescription
    end
    
    -- Create result table with ALL API fields (exact field names from Blizzard)
    local result = {
        -- Base fields from GetFactionDataByID
        factionID = factionData.factionID or factionID,
        name = factionData.name,
        description = fullDescription,
        reaction = factionData.reaction,  -- Standing ID (1-8)
        currentStanding = factionData.currentStanding,
        currentReactionThreshold = factionData.currentReactionThreshold,
        nextReactionThreshold = factionData.nextReactionThreshold,
        isHeader = factionData.isHeader,
        isHeaderWithRep = factionData.isHeaderWithRep,
        isChild = factionData.isChild,
        isCollapsed = factionData.isCollapsed,
        isWatched = factionData.isWatched,
        atWarWith = factionData.atWarWith,
        canToggleAtWar = factionData.canToggleAtWar,
        canSetInactive = factionData.canSetInactive,
        hasBonusRepGain = factionData.hasBonusRepGain,
        
        -- Additional API fields (metadata)
        _scanTime = time(),
        _scanSource = "GetFactionDataByID",
    }
    
    -- Fetch isMajorFaction FIRST (separate API call)
    if C_Reputation.IsMajorFaction then
        result.isMajorFaction = C_Reputation.IsMajorFaction(factionID)
    end
    
    -- Fetch isAccountWide: use BOTH sources (GetFactionDataByID AND IsAccountWideReputation)
    -- Some factions return true from one API but not the other — treat as account-wide if EITHER says true
    local apiAccountWide = false
    if C_Reputation.IsAccountWideReputation then
        apiAccountWide = C_Reputation.IsAccountWideReputation(factionID) or false
    end
    result.isAccountWide = apiAccountWide or (factionData.isAccountWide == true)
    
    -- Fetch Renown/Major Faction info EARLY (needed for paragon max-level check)
    if result.isMajorFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local majorData = C_MajorFactions.GetMajorFactionData(factionID)
        if majorData and majorData.factionID then
            result.renown = {
                factionID = majorData.factionID,
                name = majorData.name,
                renownLevel = majorData.renownLevel,
                renownReputationEarned = majorData.renownReputationEarned,
                renownLevelThreshold = majorData.renownLevelThreshold,
                textureKit = majorData.textureKit,
                celebrationSoundKit = majorData.celebrationSoundKit,
                renownFanfareSoundKitID = majorData.renownFanfareSoundKitID,
                unlockDescription = majorData.unlockDescription,
            }
        end
    end
    
    -- Fetch Paragon info (if applicable)
    -- IMPORTANT: Paragon can exist for:
    -- 1. Classic factions at Exalted (reaction = 8)
    -- 2. Renown factions at max level (isMajorFaction = true, renownLevelThreshold = 0)
    -- 3. Friendship factions at max rank
    if C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID) then
        if C_Reputation.GetFactionParagonInfo then
            local currentValue, threshold, rewardQuestID, hasRewardPending, tooLowLevelForParagon, paragonStorageLevel = 
                C_Reputation.GetFactionParagonInfo(factionID)
            
            -- Also check if paragon is available for current player
            local currentPlayerHasParagon = false
            if C_Reputation.IsFactionParagonForCurrentPlayer then
                currentPlayerHasParagon = C_Reputation.IsFactionParagonForCurrentPlayer(factionID)
            end
            
            -- Check if paragon is ACTIVE
            -- Must have valid values
            if currentValue and threshold and currentValue >= 0 and threshold > 0 then
                local isParagonActive = false
                
                if result.reaction == 8 then
                    -- Classic faction at Exalted
                    isParagonActive = true
                elseif result.isMajorFaction then
                    -- Renown faction: only paragon if THIS PLAYER has actually reached max renown
                    -- IsFactionParagon() is account-wide (true even if alt hasn't maxed renown)
                    -- IsFactionParagonForCurrentPlayer() is character-specific (true only at max)
                    if currentPlayerHasParagon then
                        isParagonActive = true
                    end
                else
                    -- COULD be Friendship paragon - will verify later
                    -- Accept paragon data if API provides it
                    isParagonActive = true
                end
                
                if isParagonActive then
                    result.paragon = {
                        currentValue = currentValue,
                        threshold = threshold,
                        rewardQuestID = rewardQuestID,
                        hasRewardPending = hasRewardPending,
                        tooLowLevelForParagon = tooLowLevelForParagon,
                        paragonStorageLevel = paragonStorageLevel,
                        currentPlayerHasParagon = currentPlayerHasParagon,
                    }
                end
            end
        end
    end
    
    -- Fetch Friendship info (if applicable)
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendshipInfo = C_GossipInfo.GetFriendshipReputation(factionID)
        if friendshipInfo and friendshipInfo.friendshipFactionID and friendshipInfo.friendshipFactionID > 0 then
            result.friendship = {
                friendshipFactionID = friendshipInfo.friendshipFactionID,
                standing = friendshipInfo.standing,
                maxRep = friendshipInfo.maxRep,
                name = friendshipInfo.name,
                text = friendshipInfo.text,
                texture = friendshipInfo.texture,
                reaction = friendshipInfo.reaction,
                reactionThreshold = friendshipInfo.reactionThreshold,
                nextThreshold = friendshipInfo.nextThreshold,
            }
            
            -- Fetch friendship ranks (if available)
            -- CRITICAL FIX: Declare ranksInfo in outer scope so it's accessible below
            local ranksInfo = nil
            if C_GossipInfo.GetFriendshipReputationRanks then
                ranksInfo = C_GossipInfo.GetFriendshipReputationRanks(factionID)
                if ranksInfo then
                    result.friendshipRanks = {
                        currentLevel = ranksInfo.currentLevel,
                        maxLevel = ranksInfo.maxLevel,
                    }
                end
            end
            
            -- IMPORTANT: Check for Friendship Paragon
            -- Friendships work differently from classic/renown:
            -- - When level = maxLevel, paragon progression begins
            -- - Each friendship has its own paragon threshold (not based on standing/maxRep overflow)
            -- - Let Processor handle the actual paragon calculation using reactionThreshold/nextThreshold
            if ranksInfo then
                -- Check if at max level (paragon available)
                local isMaxLevel = ranksInfo.currentLevel >= ranksInfo.maxLevel
                if isMaxLevel then
                    -- Mark as paragon - let Processor calculate the actual progress
                    result.friendshipParagon = {
                        isMaxLevel = true,
                    }
                end
            end
        end
    end
    
    -- NOTE: Renown data already fetched above (before paragon check)
    
    -- Add character metadata (v2.1: Per-character storage)
    result._characterKey = ns.Utilities:GetCharacterKey()
    result._characterName = UnitName("player") or "Unknown"
    result._characterRealm = GetRealmName() or "Unknown"
    
    return result
end

-- ============================================================================
-- BATCH API: Fetch All Factions
-- ============================================================================

---Fetch all factions using GetFactionDataByIndex (synchronous fallback)
---@return table Array of raw faction data
function ReputationScanner:FetchAllFactions()
    -- Synchronous wrapper for backwards compatibility (CommandService etc.)
    local result = {}
    self:FetchAllFactionsAsync(function(factions)
        result = factions
    end, true)  -- immediate=true forces synchronous execution
    return result
end

local FETCH_BUDGET_MS = 4  -- max milliseconds per batch frame

---Fetch all factions asynchronously with time-budgeted batching.
---Calls callback(factions) when complete. Spreads work across frames (max 4ms each).
---@param callback function Called with array of raw faction data when done
---@param immediate boolean|nil If true, run synchronously (no batching)
function ReputationScanner:FetchAllFactionsAsync(callback, immediate)
    if not C_Reputation or not C_Reputation.GetNumFactions or not C_Reputation.GetFactionDataByIndex then
        callback({})
        return
    end
    
    if C_Reputation.ExpandAllFactionHeaders then
        C_Reputation.ExpandAllFactionHeaders()
    end
    
    local numFactions = C_Reputation.GetNumFactions()
    if not numFactions or numFactions == 0 then
        callback({})
        return
    end
    
    local P = ns.Profiler
    if P then P:StartAsync("FetchAllFactions") end
    
    local factions = {}
    local headerStack = {}
    local expansionHeaders = {}
    local scanIdx = 1
    local scanner = self
    local charKey = ns.Utilities:GetCharacterKey()
    local charName = UnitName("player") or "Unknown"
    local charRealm = GetRealmName() or "Unknown"
    
    local function ProcessFaction(index)
        local factionData = C_Reputation.GetFactionDataByIndex(index)
        if not factionData or not factionData.factionID or factionData.factionID <= 0 then
            return
        end
        
        local completeData = scanner:FetchFaction(factionData.factionID, factionData.description)
        if not completeData then return end
        
        completeData._scanIndex = index
        
        if factionData.isHeader ~= nil then completeData.isHeader = factionData.isHeader end
        if factionData.isHeaderWithRep ~= nil then completeData.isHeaderWithRep = factionData.isHeaderWithRep end
        if factionData.isChild ~= nil then completeData.isChild = factionData.isChild end
        if factionData.isAccountWide == true then completeData.isAccountWide = true end
        if factionData.name and factionData.name ~= completeData.name then
            completeData._chatName = factionData.name
        end
        
        if completeData.isHeader and completeData.isHeaderWithRep then
            if #headerStack > 0 then table.remove(headerStack) end
            headerStack[#headerStack + 1] = { factionID = completeData.factionID, name = completeData.name }
            completeData.parentFactionID = nil
            completeData.parentHeaders = {}
            for _, header in ipairs(expansionHeaders) do
                completeData.parentHeaders[#completeData.parentHeaders + 1] = header
            end
        elseif completeData.isHeader and not completeData.isHeaderWithRep then
            if #headerStack > 0 then table.remove(headerStack) end
            expansionHeaders = {completeData.name}
            completeData.parentFactionID = nil
            completeData.parentHeaders = {}
        else
            if completeData.isChild and #headerStack > 0 then
                completeData.parentFactionID = headerStack[#headerStack].factionID
            else
                completeData.parentFactionID = nil
            end
            completeData.parentHeaders = {}
            for _, header in ipairs(expansionHeaders) do
                completeData.parentHeaders[#completeData.parentHeaders + 1] = header
            end
        end
        
        completeData._characterKey = charKey
        completeData._characterName = charName
        completeData._characterRealm = charRealm
        factions[#factions + 1] = completeData
    end
    
    local function ScanBatch()
        local batchStart = debugprofilestop()
        while scanIdx <= numFactions do
            ProcessFaction(scanIdx)
            scanIdx = scanIdx + 1
            if not immediate and debugprofilestop() - batchStart > FETCH_BUDGET_MS then
                C_Timer.After(0, ScanBatch)
                return
            end
        end
        if P then P:StopAsync("FetchAllFactions") end
        callback(factions)
    end
    ScanBatch()
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

return ReputationScanner
