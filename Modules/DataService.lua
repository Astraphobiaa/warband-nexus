--[[
    Warband Nexus - Data Service Module
    Centralized data collection, processing, and retrieval
    
    Handles:
    - Character data collection (gold, level, class, etc.)
    - PvE data collection (Great Vault, lockouts, M+)
    - Item data aggregation (bank, bags, storage)
    - Cross-character data queries
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CHARACTER DATA COLLECTION
-- ============================================================================

--[[
    Collect basic profession data
    @return table - Profession data
]]
function WarbandNexus:CollectProfessionData()
    local success, result = pcall(function()
        local professions = {}
        
        -- GetProfessions returns indices for the profession UI
        local prof1, prof2, arch, fish, cook = GetProfessions()
        
        local function getProfData(index)
            if not index then return nil end
            -- name, icon, rank, maxRank, numSpells, spellOffset, skillLine, rankModifier, specializationIndex, specializationOffset
            local name, icon, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
            
            if not name then return nil end
            
            return {
                name = name,
                icon = icon,
                rank = rank,
                maxRank = maxRank,
                skillLine = skillLine,
                index = index
            }
        end

        if prof1 then professions[1] = getProfData(prof1) end
        if prof2 then professions[2] = getProfData(prof2) end
        if cook then professions.cooking = getProfData(cook) end
        if fish then professions.fishing = getProfData(fish) end
        if arch then professions.archaeology = getProfData(arch) end
        
        return professions
    end)
    
    if not success then
        return {}
    end
    
    return result
end

--[[
    Collect detailed expansion data for currently open profession
    Called when TRADE_SKILL_SHOW or related events fire
    @return boolean - Success
]]
function WarbandNexus:UpdateDetailedProfessionData()
    local success, result = pcall(function()
        if not C_TradeSkillUI or not C_TradeSkillUI.IsTradeSkillReady() then
            return false
        end
        
        -- Get information about the currently open profession
        local baseInfo = C_TradeSkillUI.GetBaseProfessionInfo()
        if not baseInfo or not baseInfo.professionID then 
            return false 
        end
        
        -- Get all child profession infos (expansions)
        -- This returns a table of { professionID, professionName, ... }
        local childInfos = C_TradeSkillUI.GetChildProfessionInfos()
        if not childInfos then return false end
        
        -- Identify which profession this belongs to in our storage
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if not self.db.global.characters[key] then return false end
        if not self.db.global.characters[key].professions then 
            self.db.global.characters[key].professions = {} 
        end
        
        local professions = self.db.global.characters[key].professions
        
        -- Find which profession slot matches the open profession
        local targetProf = nil
        
        -- Check primary professions
        for i = 1, 2 do
            if professions[i] and professions[i].skillLine == baseInfo.professionID then
                targetProf = professions[i]
                break
            end
        end
        
        -- Check secondary
        if not targetProf then
            if professions.cooking and professions.cooking.skillLine == baseInfo.professionID then targetProf = professions.cooking end
            if professions.fishing and professions.fishing.skillLine == baseInfo.professionID then targetProf = professions.fishing end
            if professions.archaeology and professions.archaeology.skillLine == baseInfo.professionID then targetProf = professions.archaeology end
        end
        
        -- If we found the matching profession, update its expansion data
        if targetProf then
            targetProf.expansions = {}
            
            for _, child in ipairs(childInfos) do
                -- child contains: professionID, professionName, parentProfessionID, expansionName
                -- We also need the skill level for this specific expansion
                
                -- We can get the info for this specific child ID
                local info = C_TradeSkillUI.GetProfessionInfoBySkillLineID(child.professionID)
                if info then
                    table.insert(targetProf.expansions, {
                        name = child.expansionName or info.professionName, -- Expansion name like "Dragon Isles Alchemy"
                        skillLine = child.professionID,
                        rank = info.skillLevel,
                        maxRank = info.maxSkillLevel,
                    })
                end
            end
            
            -- Sort expansions by ID or something meaningful (usually highest ID = newest)
            table.sort(targetProf.expansions, function(a, b) 
                return a.skillLine > b.skillLine 
            end)
            
            -- Collect specialization data if available
            self:CollectProfessionSpecializationData(targetProf, baseInfo.professionID)
            
            -- Collect recipe data if available
            if self.UpdateProfessionRecipes then
                self:UpdateProfessionRecipes()
            end
            
            -- Invalidate cache so UI refreshes
            if self.InvalidateCharacterCache then
                self:InvalidateCharacterCache()
            end
            
            return true
        end
        
        return false
    end)
    
    if not success then
        return false
    end
    
    return result
end

--[[
    Collect profession specialization and trait data
    @param targetProf table - The profession data to update
    @param professionID number - The profession ID
    @return boolean - Success
]]
function WarbandNexus:CollectProfessionSpecializationData(targetProf, professionID)
    local success, result = pcall(function()
        if not targetProf then return false end
        
        -- Initialize specializations table
        targetProf.specializations = {
            configID = nil,
            specs = {}
        }
        
        -- Try to get config info (TWW/DF professions)
        -- API compatibility check for 11.2.7 and 12.0.0
        local configID = nil
        
        if C_ProfSpecs and C_ProfSpecs.GetConfigIDForSkillLine then
            configID = C_ProfSpecs.GetConfigIDForSkillLine(professionID)
        elseif C_TradeSkillUI and C_TradeSkillUI.GetProfessionSlots then
            -- Fallback method for older API
            local slots = C_TradeSkillUI.GetProfessionSlots(professionID)
            if slots and slots[1] then
                configID = slots[1].configID
            end
        end
        
        if not configID then
            -- No specialization system (classic professions)
            return false
        end
        
        targetProf.specializations.configID = configID
        
        -- Get trait tree info
        if not C_Traits or not C_Traits.GetTreeInfo then
            return false
        end
        
        local treeInfo = C_Traits.GetTreeInfo(configID)
        if not treeInfo then return false end
        
        -- Get all tree nodes
        local treeNodes = C_Traits.GetTreeNodes(configID)
        if not treeNodes then return false end
        
        -- Organize nodes by tab (specialization)
        local specTabs = {}
        
        for _, nodeID in ipairs(treeNodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
            
            if nodeInfo and nodeInfo.ID then
                local tabIndex = nodeInfo.posX and math.floor(nodeInfo.posX / 50) or 1
                
                if not specTabs[tabIndex] then
                    specTabs[tabIndex] = {
                        name = "Specialization " .. tabIndex,
                        nodes = {},
                        knowledgeSpent = 0,
                        knowledgeMax = 0
                    }
                end
                
                -- Get entry info for this node
                local entryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or 
                               (nodeInfo.entryIDs and nodeInfo.entryIDs[1])
                
                local entryInfo = nil
                if entryID and C_Traits.GetEntryInfo then
                    entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                end
                
                -- Get definition info for detailed data
                local definitionInfo = nil
                if entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo then
                    definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                end
                
                -- Get parent nodes (connections)
                local parentNodes = {}
                if nodeInfo.conditionIDs and #nodeInfo.conditionIDs > 0 then
                    for _, condID in ipairs(nodeInfo.conditionIDs) do
                        local condInfo = C_Traits.GetConditionInfo and C_Traits.GetConditionInfo(configID, condID)
                        if condInfo and condInfo.isGate then
                            -- This is a parent node requirement
                            if condInfo.spentAmountRequired then
                                table.insert(parentNodes, {
                                    type = "gate",
                                    amountRequired = condInfo.spentAmountRequired
                                })
                            end
                        end
                    end
                end
                
                -- Store enhanced node data
                local nodeData = {
                    nodeID = nodeID,
                    name = definitionInfo and definitionInfo.overrideName or "Unknown",
                    currentRank = nodeInfo.currentRank or 0,
                    maxRank = nodeInfo.maxRanks or 1,
                    posX = nodeInfo.posX or 0,
                    posY = nodeInfo.posY or 0,
                    type = nodeInfo.type or 0,
                    icon = definitionInfo and definitionInfo.overrideIcon or nil,
                    -- Enhanced data
                    parentNodes = parentNodes,
                    isAvailable = nodeInfo.isAvailable or false,
                    isVisible = nodeInfo.isVisible or false,
                    canPurchaseRank = nodeInfo.canPurchaseRank or false,
                    isChoiceNode = nodeInfo.isChoiceNode or false,
                    -- Tooltip data
                    subTreeID = nodeInfo.subTreeID,
                    entryIDs = nodeInfo.entryIDs or {},
                    activeEntry = nodeInfo.activeEntry
                }
                
                table.insert(specTabs[tabIndex].nodes, nodeData)
                
                -- Calculate spent knowledge
                if nodeData.currentRank > 0 then
                    specTabs[tabIndex].knowledgeSpent = specTabs[tabIndex].knowledgeSpent + nodeData.currentRank
                end
                specTabs[tabIndex].knowledgeMax = specTabs[tabIndex].knowledgeMax + nodeData.maxRank
            end
        end
        
        -- Try to get actual spec names from config
        if C_ProfSpecs and C_ProfSpecs.GetSpecTabIDs then
            local tabIDs = C_ProfSpecs.GetSpecTabIDs(configID)
            if tabIDs then
                for i, tabID in ipairs(tabIDs) do
                    if specTabs[i] and C_ProfSpecs.GetSpecTabInfo then
                        local tabInfo = C_ProfSpecs.GetSpecTabInfo(tabID)
                        if tabInfo and tabInfo.name then
                            specTabs[i].name = tabInfo.name
                            specTabs[i].tabID = tabID
                        end
                    end
                end
            end
        end
        
        -- Store the organized specs
        targetProf.specializations.specs = specTabs
        
        return true
    end)
    
    if not success then
        return false
    end
    
    return result
end

--[[
    Save complete character data
    Called on login/reload and when significant changes occur
    @return boolean - Success status
]]
function WarbandNexus:SaveCurrentCharacterData()
    local name = UnitName("player")
    local realm = GetRealmName()
    
    -- Safety check
    if not name or name == "" or name == "Unknown" then
        return false
    end
    if not realm or realm == "" then
        return false
    end
    
    local key = name .. "-" .. realm
    
    -- Get character info
    local className, classFile, classID = UnitClass("player")
    local level = UnitLevel("player")
    local gold = GetMoney()
    local faction = UnitFactionGroup("player")
    local _, race = UnitRace("player")
    
    -- Validate we have critical info
    if not classFile or not level or level == 0 then
        return false
    end
    
    -- Initialize characters table if needed
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    -- Check if new character
    local isNew = (self.db.global.characters[key] == nil)
    
    -- Collect PvE data (Great Vault, Lockouts, M+)
    local pveData = self:CollectPvEData()
    
    -- Collect Profession data (only if new character or professions don't exist)
    local professionData = nil
    if isNew or not self.db.global.characters[key] or not self.db.global.characters[key].professions then
        professionData = self:CollectProfessionData()
    else
        -- Preserve existing profession data (will be updated by SKILL_LINES_CHANGED event if needed)
        professionData = self.db.global.characters[key].professions
    end
    
    -- Collect Currency data (always collect for current character)
    local currencyData, currencyHeaders = self:CollectCurrencyData()
    
    -- Copy personal bank data to global (for cross-character search and storage browser)
    local personalBank = nil
    if self.db.char.personalBank and self.db.char.personalBank.items then
        personalBank = {}
        for bagIndex, bagData in pairs(self.db.char.personalBank.items) do
            personalBank[bagIndex] = {}
            for slotID, item in pairs(bagData) do
                -- Deep copy all item fields
                personalBank[bagIndex][slotID] = {
                    itemID = item.itemID,
                    itemLink = item.itemLink,
                    stackCount = item.stackCount,
                    quality = item.quality,
                    iconFileID = item.iconFileID,
                    name = item.name,
                    itemLevel = item.itemLevel,
                    itemType = item.itemType,
                    itemSubType = item.itemSubType,
                    classID = item.classID,
                    subclassID = item.subclassID,
                }
            end
        end
    end
    
    -- Store character data
    self.db.global.characters[key] = {
        name = name,
        realm = realm,
        class = className,
        classFile = classFile,
        classID = classID,
        level = level,
        gold = gold,
        faction = faction,
        race = race,
        lastSeen = time(),
        professions = professionData, -- Store Profession data
        pve = pveData,  -- Store PvE data
        currencies = currencyData, -- Store Currency data
        currencyHeaders = currencyHeaders, -- Store Currency headers
        personalBank = personalBank,  -- Store personal bank for search
    }
    
    -- Notify only for new characters
    if isNew then
        self:Print("|cff00ff00" .. name .. "|r registered.")
    end
    
    if self.InvalidateCharacterCache then
        self:InvalidateCharacterCache()
    end
    
    return true
end

--[[
    Update only profession data (lightweight)
]]
function WarbandNexus:UpdateProfessionData()
    local success, err = pcall(function()
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm

        if not self.db.global.characters or not self.db.global.characters[key] then return end

        local professionData = self:CollectProfessionData()

        -- Preserve detailed expansion data
        local oldProfs = self.db.global.characters[key].professions or {}
        for k, v in pairs(professionData) do
            if oldProfs[k] and oldProfs[k].expansions then
                v.expansions = oldProfs[k].expansions
            end
        end

        self.db.global.characters[key].professions = professionData
        self.db.global.characters[key].lastSeen = time()

        -- Invalidate cache so UI refreshes
        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end

    end)
    
    if not success then
    end
end

--[[
    Reset profession data for current character (Debug)
]]
function WarbandNexus:ResetProfessionData()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].professions = nil
        
        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end
        
        if self.RefreshUI then
            self:RefreshUI()
        end
        
        self:Print("Professions reset for " .. key)
    end
end

--[[
    Update only gold for current character (lightweight, called on PLAYER_MONEY)
    @return boolean - Success status
]]
function WarbandNexus:UpdateCharacterGold()
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    if self.db.global.characters and self.db.global.characters[key] then
        self.db.global.characters[key].gold = GetMoney()
        self.db.global.characters[key].lastSeen = time()
        return true
    end
    
    return false
end

--[[
    Get all tracked characters
    @return table - Array of character data sorted by level then name
]]
function WarbandNexus:GetAllCharacters()
    local characters = {}
    
    if not self.db.global.characters then
        return characters
    end
    
    for key, data in pairs(self.db.global.characters) do
        data._key = key  -- Include key for reference
        table.insert(characters, data)
    end
    
    -- Sort by level (highest first), then by name
    table.sort(characters, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then
            return (a.level or 0) > (b.level or 0)
        end
        return (a.name or "") < (b.name or "")
    end)
    
    return characters
end

-- ============================================================================
-- PVE DATA COLLECTION
-- ============================================================================

--[[
    Collect comprehensive PvE data (Great Vault, Lockouts, M+)
    @return table - PvE data structure
]]
function WarbandNexus:CollectPvEData()
    local success, result = pcall(function()
    local pve = {
        greatVault = {},
        lockouts = {},
        mythicPlus = {},
    }
    
    -- ===== GREAT VAULT PROGRESS =====
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        local activities = C_WeeklyRewards.GetActivities()
        if activities then
            for _, activity in ipairs(activities) do
                table.insert(pve.greatVault, {
                    type = activity.type,
                    index = activity.index,
                    progress = activity.progress,
                    threshold = activity.threshold,
                    level = activity.level,
                })
            end
        end
    end
    
    -- ===== CHECK FOR UNCLAIMED VAULT REWARDS =====
    -- This checks if the player has rewards waiting from LAST week (not current progress)
    -- NOTE: This data is only accurate when you're logged in as that character
    -- The indicator will update automatically when you claim vault rewards (via WEEKLY_REWARDS_UPDATE event)
    if C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
        pve.hasUnclaimedRewards = C_WeeklyRewards.HasAvailableRewards()
    else
        pve.hasUnclaimedRewards = false
    end
    
    -- ===== RAID/INSTANCE LOCKOUTS =====
    if GetNumSavedInstances then
        local numSaved = GetNumSavedInstances()
        for i = 1, numSaved do
            local instanceName, lockoutID, resetTime, difficultyID, locked, extended, 
                  instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, 
                  encounterProgress, extendDisabled, instanceID = GetSavedInstanceInfo(i)
            
            if locked or extended then
                table.insert(pve.lockouts, {
                    name = instanceName,
                    id = lockoutID,
                    reset = resetTime,
                    difficultyID = difficultyID,
                    difficultyName = difficultyName,
                    isRaid = isRaid,
                    maxPlayers = maxPlayers,
                    progress = encounterProgress,
                    total = numEncounters,
                    extended = extended,
                })
            end
        end
    end
    
    -- ===== MYTHIC+ DATA =====
    if C_MythicPlus then
        -- Current keystone - scan player's bags for keystone item
        local keystoneMapID, keystoneLevel, keystoneName
        for bagID = 0, NUM_BAG_SLOTS do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots then
                for slotID = 1, numSlots do
                    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
                    if itemInfo and itemInfo.itemID then
                        -- Keystone items have ID 180653 (Mythic Keystone base)
                        -- But actual keystones have different IDs per dungeon
                        local itemName, _, _, _, _, itemType, itemSubType = C_Item.GetItemInfo(itemInfo.itemID)
                        if itemName and itemName:find("Keystone") then
                            -- Get keystone level from item link
                            local itemLink = itemInfo.hyperlink
                            if itemLink then
                                -- Extract level from link (format: [Keystone: Dungeon Name +15])
                                keystoneLevel = itemLink:match("%+(%d+)")
                                if keystoneLevel then
                                    keystoneLevel = tonumber(keystoneLevel)
                                    keystoneName = itemName:match("Keystone:%s*(.+)") or itemName
                                    keystoneMapID = itemInfo.itemID
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if keystoneMapID and keystoneLevel then
            pve.mythicPlus.keystone = {
                mapID = keystoneMapID,
                name = keystoneName,
                level = keystoneLevel,
            }
        end
        
        -- Run history this week
        if C_MythicPlus.GetRunHistory then
            local includeIncomplete = false
            local includePreviousWeeks = false
            local runs = C_MythicPlus.GetRunHistory(includeIncomplete, includePreviousWeeks)
            if runs then
                pve.mythicPlus.runsThisWeek = #runs
                -- Get highest run level for weekly best
                local bestLevel = 0
                for _, run in ipairs(runs) do
                    if run.level and run.level > bestLevel then
                        bestLevel = run.level
                    end
                end
                if bestLevel > 0 then
                    pve.mythicPlus.weeklyBest = bestLevel
                end
            else
                pve.mythicPlus.runsThisWeek = 0
            end
        end
        
        -- ===== MYTHIC+ DUNGEON PROGRESS =====
        if C_ChallengeMode then
            pve.mythicPlus.dungeons = {}
            pve.mythicPlus.overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
            
            -- Get all map scores (returns indexed table with mapChallengeModeID keys)
            local allScores = C_ChallengeMode.GetMapScoreInfo() or {}
            
            -- Create lookup table by mapChallengeModeID
            local scoresByMapID = {}
            for _, scoreData in ipairs(allScores) do
                if scoreData.mapChallengeModeID then
                    scoresByMapID[scoreData.mapChallengeModeID] = scoreData
                end
            end
            
            local mapTable = C_ChallengeMode.GetMapTable()
            if mapTable then
                for _, mapID in ipairs(mapTable) do
                    local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    if name then
                        local bestLevel = 0
                        local bestScore = 0
                        local isCompleted = false
                        
                        -- Lookup score data for this mapID
                        local scoreData = scoresByMapID[mapID]
                        if scoreData then
                            bestLevel = scoreData.level or 0
                            bestScore = scoreData.dungeonScore or 0
                            isCompleted = (scoreData.completedInTime == 1) or false
                        end
                        
                        -- Insert dungeon regardless of completion status
                        table.insert(pve.mythicPlus.dungeons, {
                            mapID = mapID,
                            name = name,
                            texture = texture,
                            bestLevel = bestLevel,
                            score = bestScore,
                            completed = isCompleted,
                        })
                    end
                end
            end
        end
    end
    
    return pve
    end)
    
    if not success then
        return {
            greatVault = {},
            lockouts = {},
            mythicPlus = {},
        }
    end
    
    return result
end

-- ============================================================================
-- ITEM SEARCH & AGGREGATION
-- ============================================================================

--[[
    Perform item search across all characters and banks
    @param searchTerm string - Search query (item name or ID)
    @return table - Array of search results with location info
]]
function WarbandNexus:PerformItemSearch(searchTerm)
    if not searchTerm or searchTerm == "" then
        return {}
    end
    
    local results = {}
    local searchLower = searchTerm:lower()
    local searchID = tonumber(searchTerm)
    
    -- Search Warband Bank
    if self.db.global.warbandBank and self.db.global.warbandBank.items then
        for bagID, bagData in pairs(self.db.global.warbandBank.items) do
            for slotID, item in pairs(bagData) do
                local match = false
                
                -- Match by name
                if item.name and item.name:lower():find(searchLower) then
                    match = true
                end
                
                -- Match by ID
                if searchID and item.itemID == searchID then
                    match = true
                end
                
                if match then
                    table.insert(results, {
                        item = item,
                        location = "Warband Bank",
                        locationDetail = "Tab " .. (bagID - 12), -- Convert bagID to tab number
                        character = nil,
                    })
                end
            end
        end
    end
    
    -- Search Personal Banks (all characters)
    if self.db.global.characters then
        for charKey, charData in pairs(self.db.global.characters) do
            if charData.personalBank then
                for bagID, bagData in pairs(charData.personalBank) do
                    for slotID, item in pairs(bagData) do
                        local match = false
                        
                        -- Match by name
                        if item.name and item.name:lower():find(searchLower) then
                            match = true
                        end
                        
                        -- Match by ID
                        if searchID and item.itemID == searchID then
                            match = true
                        end
                        
                        if match then
                            table.insert(results, {
                                item = item,
                                location = "Personal Bank",
                                locationDetail = charData.name .. " (" .. charData.realm .. ")",
                                character = charData.name,
                            })
                        end
                    end
                end
            end
        end
    end
    
    return results
end

-- ============================================================================
-- CURRENCY DATA
-- ============================================================================

--[[
    Important Currency IDs organized by expansion
]]
-- ============================================================================
-- CURRENCY COLLECTION (Direct from Blizzard API)
-- ============================================================================
-- NOTE: We no longer use a hardcoded currency list.
-- Instead, we collect ALL currencies from C_CurrencyInfo.GetCurrencyListSize()
-- This ensures we always match Blizzard's Currency UI exactly.
-- ============================================================================

--[[
    Collect all currency data for current character
    Collects ALL currencies directly from Blizzard API with their header structure
    @return table, table - currencies data, headers data
]]
function WarbandNexus:CollectCurrencyData()
    local currencies = {}
    local headers = {}
    
    local success, err = pcall(function()
        if not C_CurrencyInfo then
            return
        end
        
        -- FIRST: Expand all currency categories (CRITICAL!)
        for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
            local info = C_CurrencyInfo.GetCurrencyListInfo(i)
            if info and info.isHeader and not info.isHeaderExpanded then
                C_CurrencyInfo.ExpandCurrencyList(i, true)
            end
        end
        
        -- Wait a tiny bit for expansion (not ideal but necessary)
        -- In production, this would be done via event
        
        -- Get currency list size AFTER expansion
        local listSize = C_CurrencyInfo.GetCurrencyListSize()
        
        local currentHeader = nil
        local scannedCount = 0
        local currencyCount = 0
        
        for i = 1, listSize do
            local listInfo = C_CurrencyInfo.GetCurrencyListInfo(i)
            
            if listInfo and listInfo.name and listInfo.name ~= "" then
                scannedCount = scannedCount + 1
                
                if listInfo.isHeader then
                    -- This is a HEADER
                    currentHeader = {
                        name = listInfo.name,
                        index = i,
                        currencies = {}
                    }
                    table.insert(headers, currentHeader)
                else
                    -- This is a CURRENCY entry
                    -- Try multiple methods to get currency ID
                    local currencyID = nil
                    
                    -- Method 1: From link (most reliable if it exists)
                    local currencyLink = C_CurrencyInfo.GetCurrencyListLink(i)
                    if currencyLink then
                        currencyID = tonumber(currencyLink:match("currency:(%d+)"))
                    end
                    
                    -- Method 2: If listInfo has the ID directly (some versions)
                    if not currencyID then
                        currencyID = listInfo.currencyTypesID
                    end
                    
                    -- Method 3: Search by name (fallback, less reliable)
                    if not currencyID and listInfo.name then
                        -- We can't reliably get ID from name, skip this
                    end
                    
                    if currencyID and currencyID > 0 then
                        -- Get FULL currency info using the ID
                        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                        
                        if currencyInfo and currencyInfo.name then
                            currencyCount = currencyCount + 1
                            
                            -- Hidden criteria
                            local nameHidden = currencyInfo.name and 
                                              (currencyInfo.name:find("%(Hidden%)") or 
                                               currencyInfo.name:match("^%d+%.%d+%.%d+"))
                            
                            local isReallyHidden = nameHidden or false
                            
                            -- Store currency data
                            local currencyData = {
                                name = currencyInfo.name,
                                quantity = currencyInfo.quantity or 0,
                                maxQuantity = currencyInfo.maxQuantity or 0,
                                iconFileID = currencyInfo.iconFileID,
                                quality = currencyInfo.quality or 1,
                                useTotalEarnedForMaxQty = currencyInfo.useTotalEarnedForMaxQty,
                                canEarnPerWeek = currencyInfo.canEarnPerWeek,
                                quantityEarnedThisWeek = currencyInfo.quantityEarnedThisWeek or 0,
                                isCapped = (currencyInfo.maxQuantity and currencyInfo.maxQuantity > 0 and
                                           currencyInfo.quantity >= currencyInfo.maxQuantity),
                                isAccountWide = currencyInfo.isAccountWide or false,
                                isAccountTransferable = currencyInfo.isAccountTransferable or false,
                                discovered = currencyInfo.discovered or false,
                                isHidden = isReallyHidden,
                                headerName = currentHeader and currentHeader.name or "Other",
                                listIndex = i,
                            }
                            
                            -- Auto-assign expansion and category based on name patterns
                            local name = currencyData.name:lower()
                            local headerName = currencyData.headerName:lower()
                            
                            -- Expansion detection
                            if name:find("ethereal") or name:find("carved ethereal") or name:find("runed ethereal") or name:find("weathered ethereal") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = "Crest"
                                currencyData.season = "Season 3"  -- Mark as Season 3
                            elseif name:find("undercoin") or name:find("restored coffer") or name:find("coffer key") or name:find("voidsplinter") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = "Currency"
                                currencyData.season = "Season 3"  -- Mark as Season 3
                            elseif name:find("kej") or name:find("resonance") or name:find("valorstone") or name:find("flame%-blessed") or name:find("mereldar") or name:find("hellstone") or name:find("corrupted mementos") or name:find("kaja'cola") or name:find("finery") or name:find("residual memories") or name:find("untethered coin") or name:find("trader's tender") or name:find("bronze celebration") then
                                currencyData.expansion = "The War Within"
                                currencyData.category = name:find("valorstone") and "Upgrade" or "Currency"
                            elseif name:find("drake") or name:find("whelp") or name:find("aspect") or name:find("dragon isles") or name:find("dragonf") then
                                currencyData.expansion = "Dragonflight"
                                currencyData.category = name:find("crest") and "Crest" or "Currency"
                            elseif name:find("soul") or name:find("cinders") or name:find("stygia") or name:find("shadowlands") or name:find("anima") or name:find("infused ruby") or name:find("reservoir anima") or name:find("grateful offering") then
                                currencyData.expansion = "Shadowlands"
                                currencyData.category = "Currency"
                            elseif name:find("war resource") or name:find("seafarer") or name:find("7th legion") or name:find("honorbound") or name:find("polished pet charm") or name:find("prismatic manapearl") or name:find("war supplies") then
                                currencyData.expansion = "Battle for Azeroth"
                                currencyData.category = "Currency"
                            elseif name:find("legion") or name:find("order resource") or name:find("nethershard") or name:find("curious coin") or name:find("legionfall") or name:find("wakening") or name:find("shadowy coin") or name:find("seal of broken fate") then
                                currencyData.expansion = "Legion"
                                currencyData.category = "Currency"
                            elseif name:find("apexis") or name:find("garrison") or name:find("primal spirit") or name:find("oil") or name:find("seal of tempered fate") or name:find("seal of inevitable fate") then
                                currencyData.expansion = "Warlords of Draenor"
                                currencyData.category = "Currency"
                            elseif name:find("timeless") or name:find("warforged") or name:find("bloody coin") or name:find("lesser charm") or name:find("elder charm") or name:find("mogu rune") or name:find("valor point") then
                                currencyData.expansion = "Mists of Pandaria"
                                currencyData.category = "Currency"
                            elseif name:find("mote") or name:find("sidereal") or name:find("essence of corrupted") or name:find("illustrious") or name:find("mark of the world tree") or name:find("tol barad") or name:find("conquest point") then
                                currencyData.expansion = "Cataclysm"
                                currencyData.category = "Currency"
                            elseif name:find("champion's seal") or name:find("emblem") or name:find("stone keeper") or name:find("defiler's") or name:find("wintergrasp") or name:find("shard of") or name:find("frozen orb") then
                                currencyData.expansion = "Wrath of the Lich King"
                                currencyData.category = "Currency"
                            elseif name:find("badge") or name:find("venture coin") or name:find("halaa") or name:find("spirit shard") or name:find("mark of honor hold") or name:find("mark of thrallmar") then
                                currencyData.expansion = "The Burning Crusade"
                                currencyData.category = "Currency"
                            elseif currencyData.isAccountWide then
                                currencyData.expansion = "Account-Wide"
                                currencyData.category = "Currency"
                            else
                                -- Use header name to determine expansion if still unknown
                                if headerName:find("war within") or headerName:find("tww") then
                                    currencyData.expansion = "The War Within"
                                elseif headerName:find("dragonflight") or headerName:find("df") then
                                    currencyData.expansion = "Dragonflight"
                                elseif headerName:find("shadowlands") or headerName:find("sl") then
                                    currencyData.expansion = "Shadowlands"
                                elseif headerName:find("battle for azeroth") or headerName:find("bfa") then
                                    currencyData.expansion = "Battle for Azeroth"
                                elseif headerName:find("legion") then
                                    currencyData.expansion = "Legion"
                                elseif headerName:find("warlords") or headerName:find("wod") then
                                    currencyData.expansion = "Warlords of Draenor"
                                elseif headerName:find("mists of pandaria") or headerName:find("mop") then
                                    currencyData.expansion = "Mists of Pandaria"
                                elseif headerName:find("cataclysm") then
                                    currencyData.expansion = "Cataclysm"
                                elseif headerName:find("wrath") or headerName:find("lich king") or headerName:find("wotlk") then
                                    currencyData.expansion = "Wrath of the Lich King"
                                elseif headerName:find("burning crusade") or headerName:find("tbc") or headerName:find("bc") then
                                    currencyData.expansion = "The Burning Crusade"
                                else
                                    currencyData.expansion = "Other"
                                end
                            end
                            
                            -- Category refinement and special handling
                            if not currencyData.category then
                                if name:find("crest") or name:find("fragment") then
                                    currencyData.category = "Crest"
                                elseif name:find("valorstone") or name:find("upgrade") then
                                    currencyData.category = "Upgrade"
                                elseif name:find("supplies") then
                                    currencyData.category = "Supplies"
                                elseif name:find("research") or name:find("knowledge") or name:find("artisan") then
                                    currencyData.category = "Profession"
                                elseif headerName:find("pvp") or name:find("honor") or name:find("conquest") or name:find("bloody token") or name:find("vicious") then
                                    currencyData.category = "PvP"
                                elseif headerName:find("event") or name:find("timewarped") or name:find("darkmoon") or name:find("love token") or name:find("tricky treat") or name:find("brewfest") or name:find("celebration token") or name:find("prize ticket") or name:find("epicurean") then
                                    currencyData.category = "Event"
                                elseif name:find("trophy") or name:find("tender") then
                                    currencyData.category = "Cosmetic"
                                else
                                    currencyData.category = "Currency"
                                end
                            end
                            
                            -- Special handling for PvP and Event currencies - assign to correct expansion
                            if currencyData.expansion == "Other" then
                                if currencyData.category == "PvP" then
                                    -- PvP currencies go to Account-Wide if account-wide
                                    if currencyData.isAccountWide or name:find("bloody") or name:find("vicious") or name:find("honor") or name:find("conquest") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                elseif currencyData.category == "Event" then
                                    -- Most event currencies are account-wide
                                    if currencyData.isAccountWide or name:find("timewarped") or name:find("darkmoon") or name:find("celebration") or name:find("epicurean") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                elseif currencyData.category == "Cosmetic" then
                                    -- Cosmetic currencies are usually account-wide
                                    if currencyData.isAccountWide or name:find("tender") then
                                        currencyData.expansion = "Account-Wide"
                                    end
                                end
                            end
                            
                            currencies[currencyID] = currencyData
                            
                            -- Add to current header's currency list
                            if currentHeader then
                                table.insert(currentHeader.currencies, currencyID)
                            end
                        end
                    end
                end
            end
        end
    end)
    
    if not success then
        return {}, {}
    end
    
    return currencies, headers
end

--[[
    Update currency data for current character
]]
function WarbandNexus:UpdateCurrencyData()
    local success, err = pcall(function()
        local name = UnitName("player")
        local realm = GetRealmName()
        local key = name .. "-" .. realm
        
        if not self.db.global.characters or not self.db.global.characters[key] then return end
        
        local currencyData, headerData = self:CollectCurrencyData()
        self.db.global.characters[key].currencies = currencyData
        self.db.global.characters[key].currencyHeaders = headerData  -- Store headers too
        self.db.global.characters[key].lastSeen = time()
        
        -- Invalidate cache
        if self.InvalidateCharacterCache then
            self:InvalidateCharacterCache()
        end
    end)
    
    if not success then
    end
end

--[[
    Helper: Count table entries
]]
function WarbandNexus:TableCount(tbl)
    if not tbl then return 0 end
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ============================================================================
-- COLLECTION DATA
-- ============================================================================

--[[
    Get collection statistics for current character
    @return table - Collection stats (mounts, pets, toys, achievements)
]]
function WarbandNexus:GetCollectionStats()
    local success, result = pcall(function()
    local stats = {
        mounts = 0,
        pets = 0,
        toys = 0,
        achievements = 0,
    }
    
    -- Mounts
    if C_MountJournal and C_MountJournal.GetNumMounts then
        stats.mounts = C_MountJournal.GetNumMounts() or 0
    end
    
    -- Pets
    if C_PetJournal and C_PetJournal.GetNumPets then
        stats.pets = C_PetJournal.GetNumPets() or 0
    end
    
    -- Toys
    if C_ToyBox and C_ToyBox.GetNumToys then
        stats.toys = C_ToyBox.GetNumToys() or 0
    end
    
    -- Achievement Points
    if GetTotalAchievementPoints then
        stats.achievements = GetTotalAchievementPoints() or 0
    end
    
    return stats
    end)
    
    if not success then
        return {
            mounts = 0,
            pets = 0,
            toys = 0,
            achievements = 0,
        }
    end
    
    return result
end

--[[
    Export character data for external use (CSV/JSON compatible)
    @param characterKey string - Character key (name-realm)
    @return table - Simplified character data structure
]]
function WarbandNexus:ExportCharacterData(characterKey)
    if not self.db.global.characters or not self.db.global.characters[characterKey] then
        return nil
    end
    
    local char = self.db.global.characters[characterKey]
    
    -- Create simplified export structure
    return {
        name = char.name,
        realm = char.realm,
        class = char.class,
        level = char.level,
        gold = char.gold,
        faction = char.faction,
        race = char.race,
        lastSeen = char.lastSeen,
        pve = {
            greatVaultProgress = #(char.pve and char.pve.greatVault or {}),
            lockoutCount = #(char.pve and char.pve.lockouts or {}),
            mythicPlusWeeklyBest = (char.pve and char.pve.mythicPlus and char.pve.mythicPlus.weeklyBest) or 0,
            mythicPlusRuns = (char.pve and char.pve.mythicPlus and char.pve.mythicPlus.runsThisWeek) or 0,
        },
    }
end

-- ============================================================================
-- DATA VALIDATION & CLEANUP
-- ============================================================================

--[[
    Validate character data integrity
    @param characterKey string - Character key to validate
    @return boolean, string - Valid status and error message if invalid
]]
function WarbandNexus:ValidateCharacterData(characterKey)
    if not self.db.global.characters or not self.db.global.characters[characterKey] then
        return false, "Character not found"
    end
    
    local char = self.db.global.characters[characterKey]
    
    -- Check required fields
    local required = {"name", "realm", "class", "classFile", "level"}
    for _, field in ipairs(required) do
        if not char[field] then
            return false, "Missing required field: " .. field
        end
    end
    
    -- Check data types
    if type(char.level) ~= "number" or char.level < 1 or char.level > 80 then
        return false, "Invalid level: " .. tostring(char.level)
    end
    
    if type(char.gold) ~= "number" or char.gold < 0 then
        return false, "Invalid gold: " .. tostring(char.gold)
    end
    
    return true, nil
end

--[[
    Clean up stale character data (90+ days old)
    @param daysThreshold number - Days of inactivity before cleanup (default 90)
    @return number - Count of characters removed
]]
function WarbandNexus:CleanupStaleCharacters(daysThreshold)
    daysThreshold = daysThreshold or 90
    local currentTime = time()
    local threshold = daysThreshold * 24 * 60 * 60 -- Convert to seconds
    local removed = 0
    
    if not self.db.global.characters then
        return 0
    end
    
    for key, char in pairs(self.db.global.characters) do
        local lastSeen = char.lastSeen or 0
        local age = currentTime - lastSeen
        
        if age > threshold then
            self.db.global.characters[key] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        self:Print(string.format("Cleaned up %d stale character(s)", removed))
    end
    
    return removed
end

-- ============================================================================
-- REPUTATION DATA COLLECTION
-- ============================================================================

--[[
    Collect reputation data and separate account-wide from character-specific
    @return table - Reputation data
]]
function WarbandNexus:CollectReputationData()
    local success, result = pcall(function()
        local characterReps = {}
        local accountReps = {}
        
        -- Get all factions
        local numFactions = GetNumFactions()
        
        for i = 1, numFactions do
            local factionData = C_Reputation.GetFactionDataByIndex(i)
            
            if factionData and factionData.factionID then
                local factionID = factionData.factionID
                local name = factionData.name
                local standing = factionData.reaction -- Standing level (1-8)
                local currentValue = factionData.currentReactionThreshold or 0
                local maxValue = factionData.nextReactionThreshold or 0
                
                -- Check if this is an account-wide reputation
                local isAccountWide = false
                if C_Reputation.IsAccountWideReputation then
                    isAccountWide = C_Reputation.IsAccountWideReputation(factionID)
                end
                
                local repData = {
                    factionID = factionID,
                    name = name,
                    standing = standing,
                    current = currentValue,
                    max = maxValue,
                    isAccountWide = isAccountWide
                }
                
                -- Store in appropriate table
                if isAccountWide then
                    accountReps[factionID] = repData
                else
                    characterReps[factionID] = repData
                end
            end
        end
        
        return {
            character = characterReps,
            account = accountReps
        }
    end)
    
    if not success then
        return {character = {}, account = {}}
    end
    
    return result
end

--[[
    Update reputation data for current character
]]
function WarbandNexus:UpdateReputationData()
    local repData = self:CollectReputationData()
    
    if not repData then
        return
    end
    
    local name = UnitName("player")
    local realm = GetRealmName()
    local key = name .. "-" .. realm
    
    -- Initialize structures
    if not self.db.global.warbandData then
        self.db.global.warbandData = {
            reputations = {},
            bank = {}
        }
    end
    
    if not self.db.global.characters[key] then
        self.db.global.characters[key] = {}
    end
    
    -- Store character-specific reputations
    self.db.global.characters[key].reputations = repData.character
    
    -- Store account-wide reputations (merge with existing)
    for factionID, data in pairs(repData.account) do
        self.db.global.warbandData.reputations[factionID] = data
    end
    
    -- Update timestamp
    self.db.global.characters[key].reputationsUpdated = time()
    
    self:Debug("Updated reputation data: " .. 
        self:GetTableSize(repData.character) .. " character, " ..
        self:GetTableSize(repData.account) .. " account-wide")
end

--[[
    Get all reputations for a character (including account-wide)
    @param charKey string - Character key
    @return table - Combined reputation data
]]
function WarbandNexus:GetCharacterReputations(charKey)
    local result = {}
    
    -- Add character-specific reputations
    if self.db.global.characters[charKey] and self.db.global.characters[charKey].reputations then
        for factionID, data in pairs(self.db.global.characters[charKey].reputations) do
            result[factionID] = data
        end
    end
    
    -- Add account-wide reputations
    if self.db.global.warbandData and self.db.global.warbandData.reputations then
        for factionID, data in pairs(self.db.global.warbandData.reputations) do
            result[factionID] = data
        end
    end
    
    return result
end

--[[
    Get aggregated reputation statistics across all characters
    @return table - Reputation statistics
]]
function WarbandNexus:GetReputationStatistics()
    local stats = {
        totalFactions = 0,
        accountWideFactions = 0,
        characterSpecificFactions = 0,
        maxedFactions = 0, -- Exalted
        byStanding = {}
    }
    
    -- Initialize standing counts
    for i = 1, 8 do
        stats.byStanding[i] = 0
    end
    
    -- Count account-wide reputations
    if self.db.global.warbandData and self.db.global.warbandData.reputations then
        for factionID, data in pairs(self.db.global.warbandData.reputations) do
            stats.accountWideFactions = stats.accountWideFactions + 1
            stats.totalFactions = stats.totalFactions + 1
            
            if data.standing then
                stats.byStanding[data.standing] = (stats.byStanding[data.standing] or 0) + 1
                if data.standing == 8 then -- Exalted
                    stats.maxedFactions = stats.maxedFactions + 1
                end
            end
        end
    end
    
    -- Count unique character-specific reputations
    local uniqueCharReps = {}
    for charKey, charData in pairs(self.db.global.characters or {}) do
        if charData.reputations then
            for factionID, data in pairs(charData.reputations) do
                if not uniqueCharReps[factionID] then
                    uniqueCharReps[factionID] = true
                    stats.characterSpecificFactions = stats.characterSpecificFactions + 1
                    stats.totalFactions = stats.totalFactions + 1
                end
            end
        end
    end
    
    return stats
end
