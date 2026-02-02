--[[
    Warband Nexus - Scanner Module
    Handles scanning and caching of Warband bank and Personal bank contents
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Local references for performance
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert

-- Minimal logging for operations (disabled)
local function LogOperation(operationName, status, trigger)
    -- Logging disabled
end

-- Scan Guild Bank
function WarbandNexus:ScanGuildBank()
    LogOperation("Guild Bank Scan", "Started", self.currentTrigger or "Manual")
    
    -- Check if guild bank is accessible
    if not self.guildBankIsOpen then
        return false
    end
    
    -- Check if player is in a guild
    if not IsInGuild() then
        return false
    end
    
    -- Get guild name for storage key
    local guildName = GetGuildInfo("player")
    if not guildName then
        return false
    end
    
    -- Initialize guild bank structure in global DB (guild bank is shared across characters)
    if not self.db.global.guildBank then
        self.db.global.guildBank = {}
    end
    
    if not self.db.global.guildBank[guildName] then
        self.db.global.guildBank[guildName] = { 
            tabs = {},
            lastScan = 0,
            scannedBy = UnitName("player")
        }
    end
    
    local guildData = self.db.global.guildBank[guildName]
    
    -- Get number of tabs (player might not have access to all)
    local numTabs = GetNumGuildBankTabs()
    
    if not numTabs or numTabs == 0 then
        return false
    end
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Scan all tabs
    for tabIndex = 1, numTabs do
        -- Check if player has view permission for this tab
        local name, icon, isViewable, canDeposit, numWithdrawals = GetGuildBankTabInfo(tabIndex)
        
        if isViewable then
            if not guildData.tabs[tabIndex] then
                guildData.tabs[tabIndex] = {
                    name = name,
                    icon = icon,
                    items = {}
                }
            else
                -- Update tab info and clear items
                guildData.tabs[tabIndex].name = name
                guildData.tabs[tabIndex].icon = icon
                wipe(guildData.tabs[tabIndex].items)
            end
            
            local tabData = guildData.tabs[tabIndex]
            
            -- Guild bank has 98 slots per tab (14 columns x 7 rows)
            local MAX_GUILDBANK_SLOTS_PER_TAB = 98
            totalSlots = totalSlots + MAX_GUILDBANK_SLOTS_PER_TAB
            
            for slotID = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
                local itemLink = GetGuildBankItemLink(tabIndex, slotID)
                
                if itemLink then
                    local texture, itemCount, locked = GetGuildBankItemInfo(tabIndex, slotID)
                    
                    -- Extract itemID from link
                    local itemID = tonumber(itemLink:match("item:(%d+)"))
                    
                    if itemID then
                        usedSlots = usedSlots + 1
                        totalItems = totalItems + (itemCount or 1)
                        
                        -- Get item info using API wrapper
                        local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                              _, _, itemTexture, _, classID, subclassID = self:API_GetItemInfo(itemID)
                        
                        -- Store item data
                        tabData.items[slotID] = {
                            itemID = itemID,
                            itemLink = itemLink,
                            itemName = itemName or "Unknown",
                            stackCount = itemCount or 1,
                            quality = itemQuality or 0,
                            itemLevel = itemLevel or 0,
                            itemType = itemType or "",
                            itemSubType = itemSubType or "",
                            icon = texture or itemTexture,
                            classID = classID or 0,
                            subclassID = subclassID or 0
                        }
                    end
                end
            end
        end
    end
    
    -- Update metadata
    guildData.lastScan = time()
    guildData.scannedBy = UnitName("player")
    guildData.totalItems = totalItems
    guildData.totalSlots = totalSlots
    guildData.usedSlots = usedSlots
    
    LogOperation("Guild Bank Scan", "Finished", self.currentTrigger or "Manual")
    
    -- Refresh UI
    if self.RefreshUI then
        self:RefreshUI()
    end
    
    return true
end

--[[
    Get all Warband bank items as a flat list
    Groups by item category if requested
    v2: Uses GetWarbandBankV2() with fallback to current session data
]]

--[[
    Get all Guild Bank items as a flat list
]]
function WarbandNexus:GetGuildBankItems(groupByCategory)
    local items = {}
    local guildName = GetGuildInfo("player")
    
    if not guildName or not self.db.global.guildBank or not self.db.global.guildBank[guildName] then
        return items
    end
    
    local guildData = self.db.global.guildBank[guildName]
    
    -- Iterate through all tabs
    for tabIndex, tabData in pairs(guildData.tabs or {}) do
        for slotID, itemData in pairs(tabData.items or {}) do
            -- Copy item data and add metadata
            local item = {}
            for k, v in pairs(itemData) do
                item[k] = v
            end
            item.tabIndex = tabIndex
            item.slotID = slotID
            item.source = "guild"
            item.tabName = tabData.name
            tinsert(items, item)
        end
    end
    
    -- Sort by quality (highest first), then name
    table.sort(items, function(a, b)
        if (a.quality or 0) ~= (b.quality or 0) then
            return (a.quality or 0) > (b.quality or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    
    if groupByCategory then
        return self:GroupItemsByCategory(items)
    end
    
    return items
end

--[[
    Group items by category (classID)
]]
function WarbandNexus:GroupItemsByCategory(items)
    local groups = {}
    local categoryNames = {
        [0] = "Consumables",
        [1] = "Containers",
        [2] = "Weapons",
        [3] = "Gems",
        [4] = "Armor",
        [5] = "Reagents",
        [7] = "Trade Goods",
        [9] = "Recipes",
        [12] = "Quest Items",
        [15] = "Miscellaneous",
        [16] = "Glyphs",
        [17] = "Battle Pets",
        [18] = "WoW Token",
        [19] = "Profession",
    }
    
    for _, item in ipairs(items) do
        local classID = item.classID or 15  -- Default to Miscellaneous
        local categoryName = categoryNames[classID] or "Other"
        
        if not groups[categoryName] then
            groups[categoryName] = {
                name = categoryName,
                classID = classID,
                items = {},
                expanded = true,
            }
        end
        
        tinsert(groups[categoryName].items, item)
    end
    
    -- Convert to array and sort
    local result = {}
    for _, group in pairs(groups) do
        tinsert(result, group)
    end
    
    table.sort(result, function(a, b)
        return a.name < b.name
    end)
    
    return result
end

-- REMOVED: GetTableKeys() - debug helper, only used for debugging

--[[
    Build faction metadata (global, shared across all characters)
    Called once to populate faction information
]]
function WarbandNexus:BuildFactionMetadata()
    if not self.db.global.factionMetadata then
        self.db.global.factionMetadata = {}
    end
    
    local metadata = self.db.global.factionMetadata
    
    -- Check if C_Reputation API is available
    if not C_Reputation or not C_Reputation.GetNumFactions then
        return false
    end
    
    local numFactions = C_Reputation.GetNumFactions()
    if not numFactions or numFactions == 0 then
        return false
    end
    
    -- Expand all headers to get full faction list
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        if factionData and factionData.isHeader and factionData.isCollapsed then
            C_Reputation.ExpandFactionHeader(i)
        end
    end
    
    -- Rescan after expansion
    numFactions = C_Reputation.GetNumFactions()
    
    -- Track header stack for proper nested hierarchy (API-driven)
    local headerStack = {}  -- Stack of current headers for nested structure
    
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        
        if factionData and factionData.name then
            if factionData.isHeader then
                -- This is a header (might be top-level or nested)
                if factionData.isChild then
                    -- Child header: use depth-based logic for siblings vs nesting
                    if #headerStack == 1 then
                        -- First child under top-level parent → append
                        table.insert(headerStack, factionData.name)
                    elseif #headerStack == 2 then
                        -- Already have a child header, this is a sibling → replace
                        headerStack[2] = factionData.name
                    else
                        -- Safety: reset to parent + this child
                        headerStack = {headerStack[1], factionData.name}
                    end
                else
                    -- Top-level header: reset stack
                    headerStack = {factionData.name}
                end
                
                -- If isHeaderWithRep, ALSO store as faction (e.g., Severed Threads)
                if factionData.isHeaderWithRep and factionData.factionID then
                    -- Check if this is a renown faction
                    local isRenown = false
                    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                        local majorData = C_MajorFactions.GetMajorFactionData(factionData.factionID)
                        isRenown = (majorData ~= nil)
                    end
                    
                    -- Get faction icon
                    local iconTexture = nil
                    if C_Reputation.GetFactionDataByID then
                        local detailedData = C_Reputation.GetFactionDataByID(factionData.factionID)
                        if detailedData and detailedData.texture then
                            iconTexture = detailedData.texture
                        end
                    end
                    
                    -- Store as both header AND faction
                    -- parentHeaders = all parents EXCEPT itself
                    local parentHeaders = {}
                    for j = 1, #headerStack - 1 do
                        table.insert(parentHeaders, headerStack[j])
                    end
                    
                    metadata[factionData.factionID] = {
                        name = factionData.name,
                        description = factionData.description or "",
                        iconTexture = iconTexture,
                        isRenown = isRenown,
                        canToggleAtWar = factionData.canToggleAtWar or false,
                        parentHeaders = parentHeaders,  -- API-driven hierarchy
                        isHeader = true,
                        isHeaderWithRep = true,
                    }
                end
            elseif factionData.factionID and not factionData.isHeader then
                -- Regular faction (not a header)
                -- Only build metadata if not exists
                if not metadata[factionData.factionID] then
                    -- Check if this is a renown faction
                    local isRenown = false
                    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                        local majorData = C_MajorFactions.GetMajorFactionData(factionData.factionID)
                        isRenown = (majorData ~= nil)
                    end
                    
                    -- Get faction icon
                    local iconTexture = nil
                    if C_Reputation.GetFactionDataByID then
                        local detailedData = C_Reputation.GetFactionDataByID(factionData.factionID)
                        if detailedData and detailedData.texture then
                            iconTexture = detailedData.texture
                        end
                    end
                    
                    -- Copy current header path
                    local parentHeaders = {}
                    for j = 1, #headerStack do
                        table.insert(parentHeaders, headerStack[j])
                    end
                    
                    metadata[factionData.factionID] = {
                        name = factionData.name,
                        description = factionData.description or "",
                        iconTexture = iconTexture,
                        isRenown = isRenown,
                        canToggleAtWar = factionData.canToggleAtWar or false,
                        parentHeaders = parentHeaders,  -- Full path from API
                        isHeader = false,
                        isHeaderWithRep = false,
                    }
                end
            end
        end
    end
    
    return true
end

--[[
    Scan Reputations (Modern approach with metadata separation)
    Stores only progress data in char.reputations
]]
function WarbandNexus:ScanReputations()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Check if module is enabled
    if not ns.Utilities:IsModuleEnabled("reputations") then
        return
    end
    
    LogOperation("Rep Scan", "Started", self.currentTrigger or "Manual")
    
    -- Get current character key
    local playerKey = ns.Utilities:GetCharacterKey()
    
    -- Initialize character data if needed (v2: no per-character reputations)
    if not self.db.global.characters[playerKey] then
        self.db.global.characters[playerKey] = {}
    end
    
    -- Build metadata first (only adds new factions, doesn't overwrite)
    self:BuildFactionMetadata()
    
    local reputations = {}
    local headers = {}
    
    -- ========================================
    -- PART 1: Scan Classic Reputation System (Modern C_Reputation API)
    -- ========================================
    
    -- Check if C_Reputation API is available
    if not C_Reputation or not C_Reputation.GetNumFactions then
        return false
    end
    
    local numFactions = C_Reputation.GetNumFactions()
    if not numFactions or numFactions == 0 then
        return false
    end
    
    -- Expand all headers to get full faction list
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        if factionData and factionData.isHeader and factionData.isCollapsed then
            C_Reputation.ExpandFactionHeader(i)
        end
    end
    
    -- Rescan after expansion
    numFactions = C_Reputation.GetNumFactions()
    
    local currentHeader = nil
    local currentHeaderFactions = {}
    
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        
        if not factionData or not factionData.name then
            break
        end
        
        -- Handle headers (for non-filtered mode)
        if factionData.isHeader then
            -- Only create new top-level header if NOT isHeaderWithRep
            -- isHeaderWithRep headers (Cartels, Severed) are subfactions under their parent
            if not factionData.isHeaderWithRep then
                -- Save previous header if exists
                if currentHeader then
                    table.insert(headers, {
                        name = currentHeader,
                        index = #headers + 1,
                        isCollapsed = false,
                        factions = currentHeaderFactions,
                    })
                end
                
                -- Start new header
                currentHeader = factionData.name
                currentHeaderFactions = {}
            end
        end
        
        -- Process faction (regular factions OR isHeaderWithRep factions)
        -- Skip pure headers that don't have reputation
        if factionData.factionID and (not factionData.isHeader or factionData.isHeaderWithRep) then
            -- Calculate reputation progress
            local currentValue, maxValue
            local renownLevel, renownMaxLevel = nil, nil
            local isMajorFaction = false
            local isRenownFaction = false
            local rankName = nil  -- New field for Friendship ranks
            
            -- Check Friendship / Paragon-like (Brann, Pacts) - High Priority for TWW
            if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
                local friendInfo = C_GossipInfo.GetFriendshipReputation(factionData.factionID)
                if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
                    isRenownFaction = true
                    isMajorFaction = true
                    
                    -- Get rank information using GetFriendshipReputationRanks API
                    local ranksInfo = C_GossipInfo.GetFriendshipReputationRanks and 
                                      C_GossipInfo.GetFriendshipReputationRanks(factionData.factionID)
                    
                    -- Handle named ranks (e.g. "Mastermind") vs numbered ranks
                    if type(friendInfo.reaction) == "string" then
                        rankName = friendInfo.reaction
                        renownLevel = 1 -- Default numeric value to prevent UI crashes
                    else
                        renownLevel = friendInfo.reaction or 1
                    end
                    
                    -- Try to extract level from text if available (overrides default)
                    if friendInfo.text then
                        local levelMatch = friendInfo.text:match("Level (%d+)")
                        if levelMatch then
                            renownLevel = tonumber(levelMatch)
                        end
                        -- Try to get max level from text if available "Level 3/10"
                        local maxLevelMatch = friendInfo.text:match("Level %d+/(%d+)")
                        if maxLevelMatch then
                            renownMaxLevel = tonumber(maxLevelMatch)
                        end
                    end
                    
                    -- Use GetFriendshipReputationRanks to get max level and current rank
                    if ranksInfo then
                        if ranksInfo.maxLevel and ranksInfo.maxLevel > 0 then
                            renownMaxLevel = ranksInfo.maxLevel
                        end
                        if ranksInfo.currentLevel and ranksInfo.currentLevel > 0 then
                            renownLevel = ranksInfo.currentLevel
                        end
                    end

                    -- Calculate progress within current rank
                    if friendInfo.nextThreshold then
                        currentValue = (friendInfo.standing or 0) - (friendInfo.reactionThreshold or 0)
                        maxValue = (friendInfo.nextThreshold or 0) - (friendInfo.reactionThreshold or 0)
                        
                        -- If we still don't have a max level, default to 0 (unknown)
                        if not renownMaxLevel then
                             renownMaxLevel = 0 
                        end
                    else
                        -- Maxed out
                        currentValue = 1
                        maxValue = 1
                        -- If maxed, set max level to current level so UI knows it's complete
                        if not renownMaxLevel or renownMaxLevel == 0 then
                            renownMaxLevel = renownLevel
                        end
                    end 
                end
            end

            -- Check if this is a Renown faction (if not already handled as Friendship)
            if not isRenownFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionRenownInfo then
                local renownInfo = C_MajorFactions.GetMajorFactionRenownInfo(factionData.factionID)
                if renownInfo then  -- nil = not unlocked for this character
                    isRenownFaction = true
                    isMajorFaction = true
                    -- Try both possible field names (API inconsistency)
                    renownLevel = renownInfo.renownLevel or renownInfo.currentRenownLevel or 0
                    
                    -- TWW 11.2.7: Max level is NOT in renownInfo/majorData
                    -- We need to find max level by checking rewards at each level
                    renownMaxLevel = 0
                    
                    -- Method 1: Check if at maximum
                    if C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionData.factionID) then
                        -- If at maximum, current level IS the max level
                        renownMaxLevel = renownLevel
                        currentValue = 0
                        maxValue = 1
                    else
                        -- Method 2: Find max level by checking rewards (iterate up to find the highest valid level)
                        if C_MajorFactions.GetRenownRewardsForLevel then
                            -- Check up to level 50 (reasonable max for any renown faction)
                            for testLevel = renownLevel, 50 do
                                local rewards = C_MajorFactions.GetRenownRewardsForLevel(factionData.factionID, testLevel)
                                if rewards and #rewards > 0 then
                                    -- This level exists, update max
                                    renownMaxLevel = testLevel
                                else
                                    -- No rewards = this level doesn't exist, previous was max
                                    break
                                end
                            end
                        end
                        
                        -- Not at max - use renownInfo for accurate progress
                        currentValue = renownInfo.renownReputationEarned or 0
                        maxValue = renownInfo.renownLevelThreshold or 1
                    end
                end
            end
            
            -- If not a Renown/Friendship faction, use classic reputation API (same for all factions including subfactions)
            if not isRenownFaction then
                -- Always try to get data from API first (same API for all factions)
                local apiFactionData = C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionData.factionID)
                
                -- Use API data if available, otherwise fall back to index-based data
                local useFactionData = apiFactionData or factionData
                
                -- Check if inactive (but still process to store data)
                local isInactive = false
                if useFactionData.isInactive ~= nil then
                    isInactive = useFactionData.isInactive
                elseif C_Reputation.IsFactionInactive then
                    local success, result = pcall(C_Reputation.IsFactionInactive, factionData.factionID)
                    if success then
                        isInactive = result or false
                    end
                end
                
                -- Calculate reputation values (same logic for all factions)
                if useFactionData.currentReactionThreshold and useFactionData.nextReactionThreshold then
                    -- Standard calculation: current progress within standing
                    currentValue = (useFactionData.currentStanding or 0) - useFactionData.currentReactionThreshold
                    maxValue = useFactionData.nextReactionThreshold - useFactionData.currentReactionThreshold
                elseif useFactionData.currentStanding then
                    -- Fallback: if thresholds missing, use currentStanding
                    currentValue = useFactionData.currentStanding
                    -- Try to get maxValue from reaction thresholds
                    if useFactionData.nextReactionThreshold and useFactionData.currentReactionThreshold then
                        maxValue = useFactionData.nextReactionThreshold - useFactionData.currentReactionThreshold
                    else
                        -- Default maxValue for subfactions (most use 10,000 per standing)
                        maxValue = 10000
                    end
                else
                    -- No standing data: store as 0 but try to get maxValue from API
                    currentValue = 0
                    if apiFactionData and apiFactionData.nextReactionThreshold and apiFactionData.currentReactionThreshold then
                        maxValue = apiFactionData.nextReactionThreshold - apiFactionData.currentReactionThreshold
                    else
                        -- Default maxValue for subfactions
                        maxValue = 10000
                    end
                end
                
                -- Ensure currentValue and maxValue are numbers (not nil)
                currentValue = currentValue or 0
                maxValue = maxValue or 0
            end
            
            -- Store reputation data for ALL factions (including subfactions with 0 currentValue)
            -- All factions use the same reputation API, so all should be stored
            if factionData.factionID then
                -- DEBUG: Check if this is a subfaction before storing
                local metadata = self.db.global.factionMetadata and self.db.global.factionMetadata[factionData.factionID]
                local isSubfaction = false
                if metadata and metadata.parentHeaders then
                    for _, parentName in ipairs(metadata.parentHeaders) do
                        if parentName == "The Cartels of Undermine" then
                            isSubfaction = true
                            break
                        end
                    end
                end
                
                -- Check Paragon
                local paragonValue, paragonThreshold, paragonRewardPending = nil, nil, nil
                if C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionData.factionID) then
                    local pValue, pThreshold, rewardQuestID, hasRewardPending = C_Reputation.GetFactionParagonInfo(factionData.factionID)
                    if pValue and pThreshold then
                        paragonValue = pValue % pThreshold
                        paragonThreshold = pThreshold
                        paragonRewardPending = hasRewardPending or false
                    end
                end
                
                -- Store ONLY progress data (metadata is separate)
                -- For Major Factions: no standingID (Renown doesn't use standings)
                reputations[factionData.factionID] = {
                    standingID = isMajorFaction and nil or factionData.reaction,  -- nil for Renown
                    currentValue = currentValue,
                    maxValue = maxValue,
                    renownLevel = renownLevel,
                    renownMaxLevel = renownMaxLevel,
                    rankName = rankName,  -- NEW: Store named rank if available
                    paragonValue = paragonValue,
                    paragonThreshold = paragonThreshold,
                    paragonRewardPending = paragonRewardPending,
                    isWatched = factionData.isWatched or false,
                    atWarWith = factionData.atWarWith or false,
                    isMajorFaction = isMajorFaction,  -- Flag to prevent duplicate display
                    lastUpdated = time(),
                }
                
                -- Add to current header's factions
                if currentHeader then
                    table.insert(currentHeaderFactions, factionData.factionID)
                end
            end
        end
    end
    
    -- Save last header
    if currentHeader then
        table.insert(headers, {
            name = currentHeader,
            index = #headers + 1,
            isCollapsed = false,
            factions = currentHeaderFactions,
        })
    end
    
    -- v2: Save to global reputation-centric storage
    self.db.global.reputations = self.db.global.reputations or {}
    self.db.global.reputationHeaders = self.db.global.reputationHeaders or {}
    self.db.global.factionMetadata = self.db.global.factionMetadata or {}
    
    -- Update headers (take the latest)
    if headers and next(headers) then
        self.db.global.reputationHeaders = headers
    end
    
    -- Write to reputation-centric storage
    for factionID, repData in pairs(reputations) do
        factionID = tonumber(factionID) or factionID
        
        -- Get metadata from factionMetadata
        local metadata = self.db.global.factionMetadata[factionID]
        
        -- Determine if account-wide by checking API directly
        local isMajorFaction = repData.isMajorFaction or repData.renownLevel ~= nil
        local isAccountWide = nil  -- Will be set from API
        
        -- Check if this is a subfaction before determining isAccountWide
        local isSubfaction = false
        if metadata and metadata.parentHeaders then
            for _, parentName in ipairs(metadata.parentHeaders) do
                if parentName == "The Cartels of Undermine" then
                    isSubfaction = true
                    break
                end
            end
        end
        
        -- PRIORITY 1: Check API for isAccountWide flag
        -- Try Major Faction API first
        if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
            local majorData = C_MajorFactions.GetMajorFactionData(factionID)
            if majorData and majorData.isAccountWide ~= nil then
                isAccountWide = majorData.isAccountWide
            end
        end
        
        -- PRIORITY 2: Try Classic Reputation API
        if isAccountWide == nil and C_Reputation and C_Reputation.GetFactionDataByID then
            local factionData = C_Reputation.GetFactionDataByID(factionID)
            if factionData and factionData.isAccountWide ~= nil then
                isAccountWide = factionData.isAccountWide
            end
        end
        
        -- PRIORITY 3: Default - Major Factions are usually account-wide
        -- FIX: Subfactions are typically character-specific, not account-wide
        if isAccountWide == nil then
            if isSubfaction then
                -- Subfactions are character-specific by default
                isAccountWide = false
            else
                isAccountWide = isMajorFaction
            end
        end
        
        -- Get or create global reputation entry
        if not self.db.global.reputations[factionID] then
            self.db.global.reputations[factionID] = {
                name = (metadata and metadata.name) or ("Faction " .. tostring(factionID)),
                icon = metadata and metadata.icon,
                isMajorFaction = isMajorFaction,
                isRenown = repData.renownLevel ~= nil,
                isAccountWide = isAccountWide,
                header = metadata and metadata.header,
            }
        end
        
        local globalRep = self.db.global.reputations[factionID]
        
        -- Update metadata (ALWAYS update to ensure latest from API)
        if metadata then
            globalRep.name = metadata.name or globalRep.name
            globalRep.icon = metadata.icon or globalRep.icon
            globalRep.header = metadata.header or globalRep.header
        end
        globalRep.isMajorFaction = isMajorFaction
        globalRep.isRenown = repData.renownLevel ~= nil
        globalRep.isAccountWide = isAccountWide  -- ALWAYS update from API
        
        -- Build progress data
        local progressData = {
            standingID = repData.standingID,
            currentValue = repData.currentValue or 0,
            maxValue = repData.maxValue or 0,
            renownLevel = repData.renownLevel,
            renownMaxLevel = repData.renownMaxLevel,
            rankName = repData.rankName,
            paragonValue = repData.paragonValue,
            paragonThreshold = repData.paragonThreshold,
            hasParagonReward = repData.paragonRewardPending,
            isWatched = repData.isWatched,
            atWarWith = repData.atWarWith,
            lastUpdated = time(),
        }
        
        -- Store based on account-wide status
        if isAccountWide then
            globalRep.isAccountWide = true
            globalRep.value = progressData
            globalRep.chars = nil  -- Account-wide doesn't need per-char storage
        else
            globalRep.isAccountWide = false
            globalRep.chars = globalRep.chars or {}
            globalRep.chars[playerKey] = progressData
        end
    end
    
    -- Update timestamp
    self.db.global.reputationLastUpdate = time()
    
    -- Update character lastSeen (but don't store reps per-character anymore)
    if self.db.global.characters[playerKey] then
        self.db.global.characters[playerKey].lastSeen = time()
    end
    
    -- Invalidate cache
    self:InvalidateReputationCache(playerKey)
    
    -- Send update message for UI refresh
    if self.SendMessage then
        self:SendMessage("WARBAND_REPUTATIONS_UPDATED")
    end
    
    LogOperation("Rep Scan", "Finished", self.currentTrigger or "Manual")
    return true
end

-- REMOVED: CategorizeReputation() - deprecated, migration complete