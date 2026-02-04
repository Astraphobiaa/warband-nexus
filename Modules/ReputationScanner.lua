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
    
    -- Fetch isAccountWide (separate API call)
    -- Trust the API - do NOT override what Blizzard tells us
    if C_Reputation.IsAccountWideReputation then
        result.isAccountWide = C_Reputation.IsAccountWideReputation(factionID)
    end
    
    -- Fetch Paragon info (if applicable)
    -- IMPORTANT: Paragon can exist for:
    -- 1. Classic factions at Exalted (reaction = 8)
    -- 2. Renown factions at max level (isMajorFaction = true)
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
                    -- Renown faction at max level
                    isParagonActive = true
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
                        currentPlayerHasParagon = currentPlayerHasParagon,  -- NEW: User requirement
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
    
    -- Fetch Renown/Major Faction info (if applicable)
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
            
            -- DEBUG: Log The K'aresh Trust and The Severed Threads API data
        end
    end
    
    -- Add character metadata (v2.1: Per-character storage)
    result._characterKey = ns.Utilities and ns.Utilities:GetCharacterKey() or "Unknown"
    result._characterName = UnitName("player") or "Unknown"
    result._characterRealm = GetRealmName() or "Unknown"
    
    -- DEBUG: Log specific factions WITH FULL API DATA (AFTER all data is collected)
    local debugFactions = {
        ["Darkfuse Solutions"] = true,
        ["The K'aresh Trust"] = true,
        ["The Countess"] = true,
        ["Court of Farondis"] = true,
        ["Steamwheedle Cartel"] = true,
        ["Bilgewater Cartel"] = true,
        ["Blackwater Cartel"] = true,
    }
    
    if false and debugFactions[result.name] then
        print(string.format("|cffff00ff[Scanner FULL API]|r %s (ID:%d):", result.name, factionID))
        print(string.format("  reaction=%d, standing=%d, currentThreshold=%d, nextThreshold=%d",
            result.reaction or 0,
            result.currentStanding or 0,
            result.currentReactionThreshold or 0,
            result.nextReactionThreshold or 0))
        print(string.format("  isHeader=%s, isHeaderWithRep=%s, isChild=%s, isAccountWide=%s",
            tostring(result.isHeader), tostring(result.isHeaderWithRep),
            tostring(result.isChild), tostring(result.isAccountWide)))
        print(string.format("  isMajorFaction=%s, hasRenown=%s, hasFriendship=%s",
            tostring(result.isMajorFaction), tostring(result.renown ~= nil), tostring(result.friendship ~= nil)))
    end
    
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
-- DEBUG HELPERS (For Testing)
-- ============================================================================

---Debug print faction data (for testing)
---@param factionID number
function ReputationScanner:DebugFaction(factionID)
    local data = self:FetchFaction(factionID)
    
    if not data then
        print("|cffff0000[Scanner Debug]|r Faction " .. factionID .. " not found")
        return
    end
    
    print("|cff00ff00[Scanner Debug]|r Faction " .. factionID .. " (" .. data.name .. ")")
    print("  Reaction (Standing): " .. tostring(data.reaction))
    print("  Current Standing: " .. tostring(data.currentStanding))
    print("  Current Threshold: " .. tostring(data.currentReactionThreshold))
    print("  Next Threshold: " .. tostring(data.nextReactionThreshold))
    print("  Is Account Wide: " .. tostring(data.isAccountWide))
    print("  Is Major Faction: " .. tostring(data.isMajorFaction))
    
    if data.paragon then
        print("  |cffff00ff[PARAGON]|r")
        print("    Current: " .. tostring(data.paragon.currentValue))
        print("    Threshold: " .. tostring(data.paragon.threshold))
        print("    Reward Pending: " .. tostring(data.paragon.hasRewardPending))
    end
    
    if data.friendship then
        print("  |cffffcc00[FRIENDSHIP]|r")
        print("    Reaction: " .. tostring(data.friendship.reaction))
        print("    Standing: " .. tostring(data.friendship.standing))
        print("    Max Rep: " .. tostring(data.friendship.maxRep))
        if data.friendshipRanks then
            print("    Level: " .. tostring(data.friendshipRanks.currentLevel) .. "/" .. tostring(data.friendshipRanks.maxLevel))
        end
    end
    
    if data.renown then
        print("  |cff00ffff[RENOWN]|r")
        print("    Level: " .. tostring(data.renown.renownLevel))
        print("    Earned: " .. tostring(data.renown.renownReputationEarned))
        print("    Threshold: " .. tostring(data.renown.renownLevelThreshold))
    end
    
    return data
end

-- ============================================================================
-- GLOBAL DEBUG COMMANDS
-- ============================================================================

---Global debug function: Test scan faction
---Usage: /run WNScannerDebug(2640)
_G.WNScannerDebug = function(factionID)
    if not ns.ReputationScanner then
        print("|cffff0000[Error]|r ReputationScanner not loaded")
        return
    end
    return ns.ReputationScanner:DebugFaction(factionID)
end

---Global debug function: Test scan all factions
---Usage: /run WNScannerDebugAll()
_G.WNScannerDebugAll = function()
    if not ns.ReputationScanner then
        print("|cffff0000[Error]|r ReputationScanner not loaded")
        return
    end
    
    local factions = ns.ReputationScanner:FetchAllFactions()
    print("|cff00ff00[Scanner Debug]|r Found " .. #factions .. " factions")
    
    -- Show summary
    local types = {classic = 0, renown = 0, friendship = 0, paragon = 0}
    for _, data in ipairs(factions) do
        if data.renown then
            types.renown = types.renown + 1
        elseif data.friendship then
            types.friendship = types.friendship + 1
        elseif data.paragon then
            types.paragon = types.paragon + 1
        else
            types.classic = types.classic + 1
        end
    end
    
    print("  Classic: " .. types.classic)
    print("  Renown: " .. types.renown)
    print("  Friendship: " .. types.friendship)
    print("  Paragon: " .. types.paragon)
    
    return factions
end

---Global debug function: Test scan specific factions only (Phase 1 focused test)
---Usage: /run WNScannerTestFactions()
_G.WNScannerTestFactions = function()
    if not ns.ReputationScanner then
        print("|cffff0000[Error]|r ReputationScanner not loaded")
        return
    end
    
    -- Test factions (labels match actual API response)
    local testIDs = {
        2594,  -- Assembly of Deeps (Renown)
        2640,  -- Brann Bronzebeard (Friendship)
        72,    -- Stormwind (Classic)
        2653,  -- The Cartels of Undermine (Header)
        2673,  -- Bilgewater Cartel (Child + Renown)
        2675,  -- Blackwater Cartel (Child)
        169,   -- Steamwheedle Cartel (Header with Rep)
    }
    
    print("|cff00ff00[Scanner Test]|r Fetching " .. #testIDs .. " test factions...")
    
    local results = {}
    for _, factionID in ipairs(testIDs) do
        local data = ns.ReputationScanner:FetchFaction(factionID)
        if data then
            table.insert(results, data)
            
            -- Show brief info with CORRECT priority:
            -- 1. Structure first (Header/Child)
            -- 2. Then type (Renown/Friendship/Paragon/Classic)
            local structureTag = ""
            local typeTag = ""
            
            -- Structure tags (priority 1)
            if data.isHeader then
                structureTag = "|cffffcc00[HEADER]|r"
            elseif data.isChild then
                structureTag = "|cff888888[CHILD]|r"
            end
            
            -- Type tags (priority 2) - only if NOT a pure header
            if not (data.isHeader and not data.isHeaderWithRep) then
                if data.renown then
                    typeTag = "|cff00ffff[RENOWN]|r"
                elseif data.friendship then
                    typeTag = "|cffffcc00[FRIENDSHIP]|r"
                elseif data.paragon then
                    typeTag = "|cffff00ff[PARAGON]|r"
                else
                    typeTag = "|cffffffff[CLASSIC]|r"
                end
            end
            
            -- Combine tags
            local fullTag = structureTag
            if structureTag ~= "" and typeTag ~= "" then
                fullTag = fullTag .. " " .. typeTag
            elseif typeTag ~= "" then
                fullTag = typeTag
            end
            
            print(string.format("  [%d] %s %s", factionID, fullTag, data.name or "Unknown"))
        else
            print(string.format("  [%d] |cffff0000NOT FOUND|r", factionID))
        end
    end
    
    print("|cff00ff00[Scanner Test]|r Complete: " .. #results .. "/" .. #testIDs .. " found")
    
    return results
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

return ReputationScanner
