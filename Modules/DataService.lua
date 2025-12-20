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
        self:Debug("Error in CollectProfessionData: " .. tostring(result))
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
        if not baseInfo or not baseInfo.professionID then return false end
        
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
            
            self:Debug("Updated detailed profession data for " .. targetProf.name)
            
            -- Invalidate cache so UI refreshes
            if self.InvalidateCharacterCache then
                self:InvalidateCharacterCache()
            end
            
            return true
        end
        
        return false
    end)
    
    if not success then
        self:Debug("Error in UpdateDetailedProfessionData: " .. tostring(result))
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
        personalBank = personalBank,  -- Store personal bank for search
    }
    
    -- Notify only for new characters
    if isNew then
        self:Print("|cff00ff00" .. name .. "|r registered.")
    end
    
    if self.InvalidateCharacterCache then
        self:InvalidateCharacterCache()
    end
    
    self:Debug("Character saved: " .. key)
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

        self:Debug("Professions updated for " .. key)
    end)
    
    if not success then
        self:Debug("Error in UpdateProfessionData: " .. tostring(err))
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
                    -- Debug: Log all activity types we see
                    if self.db and self.db.profile and self.db.profile.debug then
                        self:Debug(string.format("Vault Activity: type=%s, index=%s, progress=%s/%s", 
                            tostring(activity.type), tostring(activity.index),
                            tostring(activity.progress), tostring(activity.threshold)))
                    end
                    
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
        end
        
        return pve
    end)
    
    if not success then
        self:Debug("Error in CollectPvEData: " .. tostring(result))
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
        self:Debug("Error in GetCollectionStats: " .. tostring(result))
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
            self:Debug("Removing stale character: " .. key .. " (last seen " .. math.floor(age / 86400) .. " days ago)")
            self.db.global.characters[key] = nil
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        self:Print(string.format("Cleaned up %d stale character(s)", removed))
    end
    
    return removed
end
