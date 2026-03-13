--[[
    Warband Nexus - Daily Quest Manager
    Tracks daily, weekly, and world quests across multiple content types
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--[[
    Initialize Daily Quest Manager
    Register event listeners for quest updates
]]
function WarbandNexus:InitializeDailyQuestManager()
    -- Register quest events
    self:RegisterEvent("QUEST_TURNED_IN", "OnDailyQuestCompleted")
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnDailyQuestUpdate")
end

-- Content type map IDs (Midnight-only, per midnight-version-policy.mdc)
local CONTENT_MAPS = {
    midnight = {
        -- Midnight expansion zones (map IDs when available from PTR/Beta)
        -- Expected: Eversong Woods, Zul'Aman, Harandar, Voidstorm, etc.
    }
}

local DEFAULT_QUEST_TYPES = {
    dailyQuests = true,
    worldQuests = true,
    weeklyQuests = true,
    assignments = false,
    contentEvents = true,
}

local function GetSelectedQuestTypes(questTypes)
    if type(questTypes) ~= "table" then
        return {
            dailyQuests = DEFAULT_QUEST_TYPES.dailyQuests,
            worldQuests = DEFAULT_QUEST_TYPES.worldQuests,
            weeklyQuests = DEFAULT_QUEST_TYPES.weeklyQuests,
            assignments = DEFAULT_QUEST_TYPES.assignments,
            contentEvents = DEFAULT_QUEST_TYPES.contentEvents,
        }
    end

    return {
        dailyQuests = (questTypes.dailyQuests ~= false),
        worldQuests = (questTypes.worldQuests ~= false),
        weeklyQuests = (questTypes.weeklyQuests ~= false),
        assignments = (questTypes.assignments == true),
        contentEvents = (questTypes.contentEvents ~= false),
    }
end

local function IsSecretValue(value)
    return value and issecretvalue and issecretvalue(value)
end

local function IsQuestDone(questID)
    if not questID or not C_QuestLog then return false end

    local flaggedDone = false
    if C_QuestLog.IsQuestFlaggedCompleted then
        local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and result == true then
            flaggedDone = true
        end
    end

    local logDone = false
    if C_QuestLog.IsComplete then
        local ok, result = pcall(C_QuestLog.IsComplete, questID)
        if ok and result == true then
            logDone = true
        end
    end

    return flaggedDone or logDone
end

local function BuildMapScanList(contentType)
    local mapList = {}
    local seen = {}

    local function addMap(mapID, zoneName)
        if type(mapID) ~= "number" or mapID <= 0 then return end
        if seen[mapID] then return end
        seen[mapID] = true
        mapList[#mapList + 1] = {
            mapID = mapID,
            zone = zoneName or "",
        }
    end

    local configuredMaps = CONTENT_MAPS[contentType] or CONTENT_MAPS.midnight or {}
    for mapID, zoneName in pairs(configuredMaps) do
        addMap(mapID, zoneName)
    end

    return mapList
end

local function DetermineQuestCategory(questID, questTitle, flags)
    local title = type(questTitle) == "string" and questTitle or ""
    local lowerTitle = ""
    if title ~= "" and not IsSecretValue(title) then
        lowerTitle = title:lower()
    end

    if lowerTitle ~= "" and (lowerTitle:find("assignment", 1, true) or lowerTitle:find("bounty", 1, true)) then
        return "assignments"
    end

    if flags.isWeekly or flags.isCalling or flags.isBounty then
        return "weeklyQuests"
    end

    if flags.isWorldQuest then
        return "worldQuests"
    end

    if flags.isTask or flags.isBonusObjective or flags.isCampaign or flags.timeLeft > 0 then
        return "contentEvents"
    end

    if flags.isDaily then
        return "dailyQuests"
    end

    -- Unknown repeatable/zone activity defaults to content events for better visibility.
    return "contentEvents"
end

--[[
    Scan quest log and world quests for current character
    @param contentType string - "midnight"
    @return table - Categorized quest data
]]
function WarbandNexus:ScanDailyQuests(contentType)
    local quests = {
        dailyQuests = {},      -- Daily repeatable quests (isDaily=true)
        worldQuests = {},      -- World quests (IsWorldQuest=true)
        weeklyQuests = {},     -- Weekly quests (frequency=3 or Calling)
        assignments = {},      -- Special assignments (title contains "Assignment")
        contentEvents = {},    -- Bonus objectives, events, campaign/task style activities
    }

    contentType = contentType or "midnight"
    local mapsToScan = BuildMapScanList(contentType)
    local addedQuestIDs = {}

    local function GetObjectiveText(questID)
        if not C_QuestLog or not C_QuestLog.GetQuestObjectives then
            return ""
        end

        local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
        if not ok or type(objectives) ~= "table" or #objectives == 0 then
            return ""
        end

        for i = 1, #objectives do
            local objective = objectives[i]
            if objective and type(objective) == "table" and objective.text and objective.text ~= "" then
                if not IsSecretValue(objective.text) then
                    return objective.text
                end
            end
        end

        return ""
    end

    local function AddQuest(questID, mapID, zoneName, questInfo)
        if type(questID) ~= "number" or questID <= 0 or addedQuestIDs[questID] then
            return
        end

        local title = nil
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            title = C_QuestLog.GetTitleForQuestID(questID)
        end
        if (not title or title == "") and type(questInfo) == "table" and type(questInfo.title) == "string" then
            title = questInfo.title
        end
        if not title or title == "" or IsSecretValue(title) then
            title = (ns.L and ns.L["UNKNOWN_QUEST"]) or "Unknown Quest"
        end

        local isComplete = IsQuestDone(questID)

        local isWorldQuest = false
        if C_QuestLog and C_QuestLog.IsWorldQuest then
            local ok, result = pcall(C_QuestLog.IsWorldQuest, questID)
            if ok and result == true then
                isWorldQuest = true
            end
        end

        local timeLeft = 0
        if C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes then
            local ok, value = pcall(C_TaskQuest.GetQuestTimeLeftMinutes, questID)
            if ok and type(value) == "number" then
                timeLeft = value
            end
        end

        local isCalling = false
        if C_QuestLog and C_QuestLog.IsQuestCalling then
            local ok, result = pcall(C_QuestLog.IsQuestCalling, questID)
            if ok and result == true then
                isCalling = true
            end
        end

        local frequency = (type(questInfo) == "table" and questInfo.frequency) or nil
        local isWeekly = (frequency == (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly))
        local isDaily = (type(questInfo) == "table" and questInfo.isDaily == true) or (frequency == (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily))
        local isTask = (type(questInfo) == "table" and questInfo.isTask == true) or false
        local isBounty = (type(questInfo) == "table" and questInfo.isBounty == true) or false
        local isCampaign = (type(questInfo) == "table" and questInfo.campaignID and questInfo.campaignID > 0) or false
        local isBonusObjective = (type(questInfo) == "table" and questInfo.isBonusObjective == true) or false

        local category = DetermineQuestCategory(questID, title, {
            isWorldQuest = isWorldQuest,
            isWeekly = isWeekly,
            isDaily = isDaily,
            isTask = isTask,
            isBounty = isBounty,
            isCalling = isCalling,
            isCampaign = isCampaign,
            isBonusObjective = isBonusObjective,
            timeLeft = timeLeft,
        })

        local questData = {
            questID = questID,
            title = title,
            isComplete = isComplete,
            zone = zoneName or "",
            mapID = mapID or 0,
            timeLeft = timeLeft,
            objective = GetObjectiveText(questID),
            x = (type(questInfo) == "table" and questInfo.x) or 0,
            y = (type(questInfo) == "table" and questInfo.y) or 0,
            isDaily = isDaily,
            isWeekly = isWeekly,
            isWorldQuest = isWorldQuest,
            isTask = isTask,
            isBounty = isBounty,
            isCalling = isCalling,
            isCampaign = isCampaign,
            isBonusObjective = isBonusObjective,
            frequency = frequency,
        }

        -- Daily Tasks tab focuses on actionable plans: keep only open quests.
        if not questData.isComplete then
            if not quests[category] then
                category = "contentEvents"
            end
            table.insert(quests[category], questData)
        end

        addedQuestIDs[questID] = true
    end

    for i = 1, #mapsToScan do
        local mapEntry = mapsToScan[i]
        local mapID = mapEntry.mapID
        local zoneName = mapEntry.zone

        if C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
            local ok, taskPOIs = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
            if ok and type(taskPOIs) == "table" then
                for j = 1, #taskPOIs do
                    local questInfo = taskPOIs[j]
                    if questInfo and questInfo.questID then
                        AddQuest(questInfo.questID, mapID, zoneName, questInfo)
                    end
                end
            end
        end

        if C_QuestLog and C_QuestLog.GetQuestsOnMap then
            local ok, mapQuests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
            if ok and type(mapQuests) == "table" then
                for _, questInfo in pairs(mapQuests) do
                    if questInfo and questInfo.questID then
                        AddQuest(questInfo.questID, mapID, zoneName, questInfo)
                    end
                end
            end
        end

        -- Zone bounty quests are generally event/weekly-style objectives.
        if C_QuestLog and C_QuestLog.GetBountiesForMapID then
            local ok, bounties = pcall(C_QuestLog.GetBountiesForMapID, mapID)
            if ok and type(bounties) == "table" then
                for j = 1, #bounties do
                    local bountyInfo = bounties[j]
                    if bountyInfo and bountyInfo.questID then
                        bountyInfo.isBounty = true
                        AddQuest(bountyInfo.questID, mapID, zoneName, bountyInfo)
                    end
                end
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                AddQuest(info.questID, info.mapID or 0, info.zoneName or "", info)
            end
        end
    end

    local function SortCategory(list)
        table.sort(list, function(a, b)
            local aTime = (type(a.timeLeft) == "number" and a.timeLeft > 0) and a.timeLeft or math.huge
            local bTime = (type(b.timeLeft) == "number" and b.timeLeft > 0) and b.timeLeft or math.huge
            if aTime ~= bTime then return aTime < bTime end
            local aTitle = (type(a.title) == "string" and a.title) or ""
            local bTitle = (type(b.title) == "string" and b.title) or ""
            return aTitle < bTitle
        end)
    end

    SortCategory(quests.dailyQuests)
    SortCategory(quests.worldQuests)
    SortCategory(quests.weeklyQuests)
    SortCategory(quests.assignments)
    SortCategory(quests.contentEvents)

    return quests
end

--[[
    Create daily plan for current character
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @param contentType string - "midnight"
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
    local normalizedQuestTypes = GetSelectedQuestTypes(questTypes)
    local quests = self:ScanDailyQuests(contentType)
    
    -- Get character class (if it's the current character)
    local _, currentClass = UnitClass("player")
    local characterClass = nil
    local currentKey = ns.Utilities:GetCharacterKey()
    local questCharKey = ns.Utilities:GetCharacterKey(characterName, characterRealm)
    if questCharKey == currentKey then
        characterClass = currentClass
    end
    
    -- Content names for display (Midnight-only)
    local contentNames = {
        midnight = "Midnight"
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
        questTypes = normalizedQuestTypes,
        name = "Daily Tasks - " .. characterName,
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        createdDate = time(),
        lastUpdate = time(),
        quests = quests
    }
    
    table.insert(self.db.global.plans, plan)
    self:SendMessage("WN_PLANS_UPDATED", {
        action = "daily_plan_created",
        planID = planID,
        planType = "daily_quests",
    })
    
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
    
    -- Normalize quest type flags for backward-compatibility with older saved plans.
    plan.questTypes = GetSelectedQuestTypes(plan.questTypes)

    -- Rescan quests
    local newQuests = self:ScanDailyQuests(plan.contentType)
    
    -- Update plan
    plan.quests = newQuests
    plan.lastUpdate = time()
    self:SendMessage("WN_PLANS_UPDATED", {
        action = "daily_plan_updated",
        planID = plan.id,
        planType = "daily_quests",
    })
end

--[[
    Event handler for quest completion
    Fires custom event for PlansManager to listen
]]
function WarbandNexus:OnDailyQuestCompleted(event, questID)
    ns.DebugPrint("|cff9370DB[DailyQuest]|r [Quest Event] QUEST_TURNED_IN triggered, questID=" .. tostring(questID))
    if not self.db.global.plans then
        return
    end
    
    -- Get current character info
    local currentKey = ns.Utilities:GetCharacterKey()
    
    -- Update daily plans for current character
    for _, plan in ipairs(self.db.global.plans) do
        local planKey = ns.Utilities:GetCharacterKey(plan.characterName, plan.characterRealm)
        if plan.type == "daily_quests" and planKey == currentKey then
            -- Resolve completed quest title/category from existing snapshot before rescan.
            local completedCategory = nil
            local completedTitle = nil
            if questID and plan.quests and plan.questTypes then
                for category, questList in pairs(plan.quests) do
                    if plan.questTypes[category] and type(questList) == "table" then
                        for i = 1, #questList do
                            local quest = questList[i]
                            if quest and quest.questID == questID then
                                completedCategory = category
                                completedTitle = quest.title
                                break
                            end
                        end
                    end
                    if completedCategory then break end
                end
            end

            self:UpdateDailyPlanProgress(plan, true)

            if completedCategory and completedTitle and completedTitle ~= "" then
                self:ShowDailyQuestNotification(plan.characterName, completedCategory, completedTitle)
            end
        end
    end
    
    -- Fire event for PlansManager
    if self.SendMessage then
        self:SendMessage("WARBAND_QUEST_PROGRESS_UPDATED", {
            questID = questID,
            reason = "QUEST_TURNED_IN",
        })
    end
end

--[[
    Event handler for quest log update
    Throttled to prevent spam
]]
function WarbandNexus:OnDailyQuestUpdate()
    ns.DebugPrint("|cff9370DB[DailyQuest]|r [Quest Event] QUEST_LOG_UPDATE triggered")
    if not self.db.global.plans then
        return
    end
    
    -- Throttle rapid updates
    if self.questUpdateTimer then
        return
    end
    
    self.questUpdateTimer = C_Timer.After(1, function()
        self.questUpdateTimer = nil
        
        -- Get current character info
        local currentKey = ns.Utilities:GetCharacterKey()
        
        -- Update daily plans for current character (skip notifications on log update)
        for _, plan in ipairs(self.db.global.plans) do
            local planKey = ns.Utilities:GetCharacterKey(plan.characterName, plan.characterRealm)
            if plan.type == "daily_quests" and planKey == currentKey then
                self:UpdateDailyPlanProgress(plan, true)
            end
        end
        
        -- Fire event for PlansManager
        if self.SendMessage then
            self:SendMessage("WARBAND_QUEST_PROGRESS_UPDATED", {
                reason = "QUEST_LOG_UPDATE",
            })
        end
    end)
end

