--[[
    Warband Nexus - Daily Quest Manager
    Tracks daily, weekly, and world quests across multiple content types
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Content type map IDs
local CONTENT_MAPS = {
    tww = {
        -- Main zones
        [2248] = "Isle of Dorn",
        [2255] = "Azj-Kahet",
        [2213] = "Hallowfall",
        [2214] = "Ringing Deeps",
        [2339] = "Dornogal",
        [2369] = "The Undermine",
        [2367] = "K'aresh",
        -- Additional zones
        [2375] = "Siren Isle",
        [2601] = "Azj-Kahet (Lower)",
        [2256] = "City of Threads",
        [2216] = "Azj-Kahet (City)"
    },
    df = {
        -- Main zones
        [2022] = "The Waking Shores",
        [2023] = "Ohn'ahran Plains",
        [2024] = "The Azure Span",
        [2025] = "Thaldraszus",
        [2112] = "Valdrakken",
        -- Patch zones
        [2151] = "The Forbidden Reach",
        [2133] = "Zaralek Cavern",
        [2200] = "Emerald Dream"
    },
    sl = {
        -- Main zones
        [1550] = "The Maw",
        [1533] = "Bastion",
        [1565] = "Ardenweald",
        [1536] = "Maldraxxus",
        [1525] = "Revendreth",
        [1543] = "The Maw (Intro)",
        -- Hub
        [1670] = "Oribos",
        -- Patch zones
        [1961] = "Korthia",
        [1970] = "Zereth Mortis",
        [1905] = "Torghast"
    }
}

--[[
    Scan quest log and world quests for current character
    @param contentType string - "tww", "df", or "sl"
    @return table - Categorized quest data
]]
function WarbandNexus:ScanDailyQuests(contentType)
    local quests = {
        dailyQuests = {},
        worldQuests = {},
        weeklyQuests = {},
        specialAssignments = {}
    }
    
    -- Helper function to check if quest already exists
    local function questAlreadyAdded(questID)
        for _, cat in pairs(quests) do
            for _, q in ipairs(cat) do
                if q.questID == questID then
                    return true
                end
            end
        end
        return false
    end
    
    -- Scan maps for AVAILABLE quests (blue/yellow ! on map, not quest log!)
    if not contentType or not CONTENT_MAPS[contentType] then
        return quests
    end
    
    local mapsToScan = CONTENT_MAPS[contentType]
    
    for mapID, zoneName in pairs(mapsToScan) do
        -- Method 1: C_TaskQuest.GetQuestsOnMap - World Quests
        if C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
            local taskPOIs = C_TaskQuest.GetQuestsOnMap(mapID)
            if taskPOIs then
                for _, questInfo in ipairs(taskPOIs) do
                    local questID = questInfo.questID
                    if questID and type(questID) == "number" and not questAlreadyAdded(questID) then
                        local isComplete = C_QuestLog.IsQuestFlaggedCompleted(questID)
                        if not isComplete then
                            local questTitle = C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest"
                            local timeLeft = C_TaskQuest.GetQuestTimeLeftMinutes(questID) or 0
                            local isWorldQuest = C_QuestLog.IsWorldQuest(questID)
                            
                            local questData = {
                                questID = questID,
                                title = questTitle,
                                isComplete = false,
                                zone = zoneName,
                                mapID = mapID,
                                timeLeft = timeLeft,
                                objective = "",
                                x = questInfo.x,
                                y = questInfo.y
                            }
                            
                            if isWorldQuest then
                                table.insert(quests.worldQuests, questData)
                            else
                                table.insert(quests.dailyQuests, questData)
                            end
                            
                            if self.db.profile.debugMode then
                                self:Debug(string.format("[%s] %s: [%d] %s", 
                                    zoneName, isWorldQuest and "WQ" or "Daily", questID, questTitle))
                            end
                        end
                    end
                end
            end
        end
        
        -- Method 2: C_QuestLog.GetQuestsOnMap - Regular quest POIs (yellow !)
        if C_QuestLog and C_QuestLog.GetQuestsOnMap then
            local mapQuests = C_QuestLog.GetQuestsOnMap(mapID)
            if mapQuests then
                for _, questInfo in pairs(mapQuests) do
                    local questID = questInfo.questID
                    if questID and not questAlreadyAdded(questID) then
                        local isComplete = C_QuestLog.IsQuestFlaggedCompleted(questID)
                        if not isComplete then
                            local questTitle = C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest"
                            
                            local questData = {
                                questID = questID,
                                title = questTitle,
                                isComplete = false,
                                zone = zoneName,
                                mapID = mapID,
                                timeLeft = 0,
                                objective = "",
                                x = questInfo.x,
                                y = questInfo.y
                            }
                            
                            table.insert(quests.dailyQuests, questData)
                            
                            if self.db.profile.debugMode then
                                self:Debug(string.format("[%s] Regular: [%d] %s", 
                                    zoneName, questID, questTitle))
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Additional scan: Quest Log for Weekly/Special Assignments
    -- These are typically in the quest log, not on the map
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader then
                local questID = info.questID
                
                -- Skip if already added
                if not questAlreadyAdded(questID) then
                    local isComplete = C_QuestLog.IsComplete(questID)
                    if not isComplete then
                        local questTitle = info.title or C_QuestLog.GetTitleForQuestID(questID) or "Unknown Quest"
                        
                        -- Check for weekly or special assignments
                        local isCalling = C_QuestLog.IsQuestCalling(questID)
                        local isWeekly = info.frequency == Enum.QuestFrequency.Weekly
                        local isSpecialAssignment = questTitle:find("Special Assignment")
                        
                        if isSpecialAssignment then
                            local questData = {
                                questID = questID,
                                title = questTitle,
                                isComplete = false,
                                zone = "",
                                mapID = 0,
                                timeLeft = 0,
                                objective = "",
                                x = 0,
                                y = 0
                            }
                            table.insert(quests.specialAssignments, questData)
                            
                            if self.db.profile.debugMode then
                                self:Debug(string.format("[Quest Log] Special Assignment: [%d] %s", questID, questTitle))
                            end
                        elseif isWeekly or isCalling then
                            local questData = {
                                questID = questID,
                                title = questTitle,
                                isComplete = false,
                                zone = "",
                                mapID = 0,
                                timeLeft = 0,
                                objective = "",
                                x = 0,
                                y = 0
                            }
                            table.insert(quests.weeklyQuests, questData)
                            
                            if self.db.profile.debugMode then
                                self:Debug(string.format("[Quest Log] Weekly: [%d] %s", questID, questTitle))
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Debug logging
    self:Debug(string.format("Daily Quest Scan: %d daily, %d world, %d weekly, %d special", 
        #quests.dailyQuests, #quests.worldQuests, #quests.weeklyQuests, 
        #quests.specialAssignments))
    
    return quests
end

--[[
    Create daily plan for current character
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @param contentType string - "tww", "df", or "sl"
    @param questTypes table - Quest type selections
    @return table - Created plan or nil if failed
]]
function WarbandNexus:CreateDailyPlan(characterName, characterRealm, contentType, questTypes)
    if not characterName or not characterRealm then
        self:Print("|cffff0000Error:|r Character name and realm required")
        return nil
    end
    
    -- Check for existing daily plan for this character
    if self:HasActiveDailyPlan(characterName, characterRealm) then
        self:Print("|cffff0000Error:|r " .. characterName .. "-" .. characterRealm .. " already has an active daily plan")
        return nil
    end
    
    -- Initialize plans table if needed
    if not self.db.global.plans then
        self.db.global.plans = {}
    end
    
    -- Generate unique ID
    local planID = self.db.global.plansNextID or 1
    self.db.global.plansNextID = planID + 1
    
    -- Scan quests
    local quests = self:ScanDailyQuests(contentType)
    
    -- Get character class (if it's the current character)
    local _, currentClass = UnitClass("player")
    local characterClass = nil
    if characterName == UnitName("player") and characterRealm == GetRealmName() then
        characterClass = currentClass
    end
    
    -- Content names for display
    local contentNames = {
        tww = "The War Within",
        df = "Dragonflight",
        sl = "Shadowlands"
    }
    
    -- Create plan structure
    local plan = {
        id = planID,
        type = "daily_quests",
        characterName = characterName,
        characterRealm = characterRealm,
        characterClass = characterClass,
        contentType = contentType,
        contentName = contentNames[contentType] or contentType,
        questTypes = questTypes,
        name = "Daily Tasks - " .. characterName,
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        createdDate = time(),
        lastUpdate = time(),
        quests = quests
    }
    
    table.insert(self.db.global.plans, plan)
    
    self:Print("|cff00ff00Created daily quest plan for:|r " .. characterName .. "-" .. characterRealm)
    
    return plan
end

--[[
    Check if character has an active daily plan
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @return boolean - True if plan exists
]]
function WarbandNexus:HasActiveDailyPlan(characterName, characterRealm)
    if not self.db.global.plans then
        return false
    end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "daily_quests" and 
           plan.characterName == characterName and 
           plan.characterRealm == characterRealm then
            return true
        end
    end
    
    return false
end

--[[
    Get daily plan for a character
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @return table - Plan or nil
]]
function WarbandNexus:GetDailyPlan(characterName, characterRealm)
    if not self.db.global.plans then
        return nil
    end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "daily_quests" and 
           plan.characterName == characterName and 
           plan.characterRealm == characterRealm then
            return plan
        end
    end
    
    return nil
end

--[[
    Update daily plan progress
    @param plan table - Daily plan to update
    @param skipNotifications boolean - If true, don't trigger notifications
]]
function WarbandNexus:UpdateDailyPlanProgress(plan, skipNotifications)
    if not plan or plan.type ~= "daily_quests" then
        return
    end
    
    self:Debug("UpdateDailyPlanProgress called for: " .. (plan.characterName or "Unknown"))
    
    -- Rescan quests
    local newQuests = self:ScanDailyQuests(plan.contentType)
    
    -- Compare and detect completed quests
    local newlyCompleted = {}
    
    for category, questList in pairs(newQuests) do
        if plan.questTypes[category] then
            for _, newQuest in ipairs(questList) do
                if newQuest.isComplete then
                    -- Check if it was incomplete before
                    local wasIncomplete = true
                    if plan.quests[category] then
                        for _, oldQuest in ipairs(plan.quests[category]) do
                            if oldQuest.questID == newQuest.questID and oldQuest.isComplete then
                                wasIncomplete = false
                                break
                            end
                        end
                    end
                    
                    if wasIncomplete then
                        table.insert(newlyCompleted, {
                            category = category,
                            quest = newQuest
                        })
                    end
                end
            end
        end
    end
    
    -- Update plan
    plan.quests = newQuests
    plan.lastUpdate = time()
    
    -- Show notifications
    if not skipNotifications then
        for _, completed in ipairs(newlyCompleted) do
            self:Debug("Daily quest completed: " .. completed.quest.title)
            self:ShowDailyQuestNotification(plan.characterName, completed.category, completed.quest.title)
        end
    end
end

--[[
    Event handler for quest completion
]]
function WarbandNexus:OnDailyQuestCompleted(event, questID)
    if not self.db.global.plans then
        return
    end
    
    -- Get current character info
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- Update daily plans for current character
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "daily_quests" and 
           plan.characterName == currentName and 
           plan.characterRealm == currentRealm then
            self:UpdateDailyPlanProgress(plan)
        end
    end
end

--[[
    Event handler for quest log update
]]
function WarbandNexus:OnDailyQuestUpdate()
    if not self.db.global.plans then
        return
    end
    
    -- Get current character info
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- Update daily plans for current character (skip notifications on log update)
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "daily_quests" and 
           plan.characterName == currentName and 
           plan.characterRealm == currentRealm then
            self:UpdateDailyPlanProgress(plan, true)
        end
    end
end

