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
function ReputationScanner:FetchFaction(factionID)
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
    
    -- Get description and clean it up
    local fullDescription = factionData.description or ""
    
    -- Try to get full description from Blizzard reputation frame if available
    if C_Reputation and C_Reputation.GetFactionDataByIndex then
        -- Find faction index in the reputation list
        local numFactions = C_Reputation.GetNumFactions()
        for i = 1, numFactions do
            local repData = C_Reputation.GetFactionDataByIndex(i)
            if repData and repData.factionID == factionID then
                if repData.description and repData.description ~= "" and #repData.description > #fullDescription then
                    fullDescription = repData.description
                end
                break
            end
        end
    end
    
    -- NOTE: WoW API often provides truncated descriptions - this is a Blizzard limitation
    -- The API simply doesn't provide full text for many factions
    
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
    result._characterKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    result._characterName = UnitName("player") or "Unknown"
    result._characterRealm = GetRealmName() or "Unknown"
    
    return result
end

-- ============================================================================
-- BATCH API: Fetch All Factions
-- ============================================================================

---Fetch all factions using GetFactionDataByIndex
---@return table Array of raw faction data
function ReputationScanner:FetchAllFactions()
    if not C_Reputation or not C_Reputation.GetNumFactions or not C_Reputation.GetFactionDataByIndex then
        return {}
    end
    
    -- Expand all headers to ensure we get all factions
    if C_Reputation.ExpandAllFactionHeaders then
        C_Reputation.ExpandAllFactionHeaders()
    end
    
    local factions = {}
    local numFactions = C_Reputation.GetNumFactions()
    
    if not numFactions or numFactions == 0 then
        return {}
    end
    
    -- Use a STACK to track nested headers (supports multiple levels)
    local headerStack = {}  -- Stack of {factionID, name} for headers with isHeaderWithRep
    local expansionHeaders = {}  -- Stack of organizational headers (expansion names)
    
    for index = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(index)
        
        if factionData and factionData.factionID and factionData.factionID > 0 then
            -- Use FetchFaction to get complete data (includes paragon, friendship, renown)
            local completeData = self:FetchFaction(factionData.factionID)
            if completeData then
                completeData._scanIndex = index  -- Store index for reference
                
                -- CRITICAL: GetFactionDataByID does NOT return isHeader/isHeaderWithRep.
                -- These flags only come from GetFactionDataByIndex. Merge them.
                if factionData.isHeader ~= nil then
                    completeData.isHeader = factionData.isHeader
                end
                if factionData.isHeaderWithRep ~= nil then
                    completeData.isHeaderWithRep = factionData.isHeaderWithRep
                end
                if factionData.isChild ~= nil then
                    completeData.isChild = factionData.isChild
                end
                
                -- CRITICAL: GetFactionDataByIndex may also have isAccountWide.
                -- Merge it: if ANY source says account-wide, treat as account-wide.
                if factionData.isAccountWide == true then
                    completeData.isAccountWide = true
                end
                
                -- CRITICAL: GetFactionDataByID can return a DIFFERENT name than GetFactionDataByIndex.
                -- Example: Guild faction → ByID returns "Theskilat" (guild name), ByIndex returns "Guild".
                -- Blizzard chat messages use the ByIndex name ("Reputation with Guild increased by X").
                -- Store alternate name so nameToIDLookup can match both.
                if factionData.name and factionData.name ~= completeData.name then
                    completeData._chatName = factionData.name
                end
                
                -- Track parent-child relationships using STACK approach
                -- CRITICAL: Only faction with BOTH isHeader AND isHeaderWithRep can be parent
                
                if completeData.isHeader and completeData.isHeaderWithRep then
                    -- Header WITH rep - this CAN have children
                    -- IMPORTANT: Pop previous headerWithRep before pushing new one
                    -- This ensures only ONE headerWithRep is active at a time (no nesting)
                    if #headerStack > 0 then
                        table.remove(headerStack)
                    end
                    
                    -- Push new parent to stack
                    table.insert(headerStack, {
                        factionID = completeData.factionID,
                        name = completeData.name
                    })
                    completeData.parentFactionID = nil  -- Headers are top-level
                    
                    -- Set expansion headers (from organizational header stack)
                    completeData.parentHeaders = {}
                    for _, header in ipairs(expansionHeaders) do
                        table.insert(completeData.parentHeaders, header)
                    end
                    
                elseif completeData.isHeader and not completeData.isHeaderWithRep then
                    -- Pure organizational header (no rep bar) - this is an EXPANSION header
                    -- Clear parent stack - this ends ALL parent contexts
                    if #headerStack > 0 then
                        table.remove(headerStack)
                    end
                    
                    -- Update expansion header stack
                    expansionHeaders = {completeData.name}  -- Replace with new expansion
                    
                    completeData.parentFactionID = nil  -- Organizational headers are top-level
                    completeData.parentHeaders = {}  -- Expansion headers have no parents
                    
                else
                    -- Regular faction (not a header)
                    -- CRITICAL: Only assign parent if API says this is a child (isChild flag)
                    if completeData.isChild and #headerStack > 0 then
                        -- This faction is explicitly marked as child by Blizzard API
                        local currentParent = headerStack[#headerStack]
                        completeData.parentFactionID = currentParent.factionID
                    else
                        -- Not a child (isChild=false) or no parent context - top-level faction
                        completeData.parentFactionID = nil
                    end
                    
                    -- Set expansion headers (from organizational header stack)
                    completeData.parentHeaders = {}
                    for _, header in ipairs(expansionHeaders) do
                        table.insert(completeData.parentHeaders, header)
                    end
                end
                
                -- Add character metadata (v2.1: Per-character storage)
                completeData._characterKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
                completeData._characterName = UnitName("player") or "Unknown"
                completeData._characterRealm = GetRealmName() or "Unknown"
                
                table.insert(factions, completeData)
            end
        end
    end
    
    return factions
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

return ReputationScanner
