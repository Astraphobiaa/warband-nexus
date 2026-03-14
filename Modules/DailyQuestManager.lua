--[[
    Warband Nexus - Daily Quest Manager
    Tracks daily, weekly, world quests, assignments, and zone events for Midnight
    Uses hardcoded quest IDs for reliable weekly tracking + live quest log scanning
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- MIDNIGHT ZONE DATA
-- ============================================================================

local MIDNIGHT_MAPS = {
    [2393] = "Silvermoon",
    [2395] = "Eversong Woods",
    [2424] = "Isle of Quel'Danas",
    [2413] = "Harandar",
    [2437] = "Zul'Aman",
    [2405] = "Voidstorm",
}

local MIDNIGHT_MAP_SET = {}
for mapID in pairs(MIDNIGHT_MAPS) do
    MIDNIGHT_MAP_SET[mapID] = true
end

-- ============================================================================
-- KNOWN QUESTS (hardcoded for reliable tracking via IsQuestFlaggedCompleted)
-- ============================================================================

local KNOWN_WEEKLY_QUESTS = {
    -- =====================================================================
    -- WEEKLY QUESTS (core weekly objectives)
    -- =====================================================================
    { questID = 93942, title = "Spark of Radiance",       category = "weeklyQuests", zone = "Silvermoon",    icon = "Interface\\Icons\\INV_10_Jewelcrafting_Gem3Primal_Fire_Cut_Green",
      description = "Collect a Spark of Radiance for crafting. Pick one weekly event from Lady Liadrin." },
    { questID = 95245, title = "Midnight: World Tour",    category = "weeklyQuests", zone = "Quel'Thalas",   icon = "Interface\\Icons\\INV_Misc_Map_01",
      description = "Complete all 4 zone events this week: Soiree, Abundance, Legends, Stormarion." },
    { questID = 93913, title = "Midnight: World Boss",    category = "weeklyQuests", zone = "Quel'Thalas",   icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
      description = "Defeat the weekly world boss in Quel'Thalas for Champion-level gear." },
    { questID = 81514, title = "Bountiful Delves",        category = "weeklyQuests", zone = "Silvermoon",    icon = "Interface\\Icons\\INV_Misc_Bag_33",
      description = "Complete Tier 8+ Delves for bonus Coffer Keys and gear rewards." },
    { questID = 92600, title = "Cracked Keystone",        category = "weeklyQuests", zone = "Silvermoon",    icon = "Interface\\Icons\\INV_Keystone",
      description = "Complete a Tier 11 Bountiful Delve for a Crested Keystone." },

    -- =====================================================================
    -- CONTENT EVENTS — 4 zone events, each weekly
    -- Main events: counted in card summary (isSubQuest = nil/false)
    -- Sub-quests: shown in detail view only (isSubQuest = true)
    -- =====================================================================

    -- Saltheril's Soiree (Eversong Woods)
    { questID = 93889, title = "Saltheril's Soiree",       category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\INV_Misc_Food_164_Fish_Seadog", eventGroup = "soiree",
      description = "Choose a faction, earn Favor, and defend a Runestone in Eversong Woods." },
    { questID = 89289, title = "Favor of the Court",       category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\INV_Misc_Note_06",              eventGroup = "soiree", isSubQuest = true,
      description = "Pick an ally faction (Blood Knights, Farstriders, Magisters, or Shades) to invite." },
    { questID = 90573, title = "Fortify the Runestones",   category = "events", zone = "Eversong Woods", icon = "Interface\\Icons\\Spell_Arcane_PortalSilvermoon", eventGroup = "soiree", isSubQuest = true, alternateIDs = {90574, 90575, 90576},
      description = "Collect Latent Arcana, charge and defend a Runestone. Faction-specific quest." },

    -- Abundance (Zul'Aman)
    { questID = 93890, title = "Abundance",                category = "events", zone = "Zul'Aman",       icon = "Interface\\Icons\\INV_Misc_Herb_AncientLichen",  eventGroup = "abundance",
      description = "Treasure cave sprint — collect and donate 20,000 points to Dundun's altars." },
    { questID = 89507, title = "Abundant Offerings",       category = "events", zone = "Zul'Aman",       icon = "Interface\\Icons\\INV_Misc_Coin_02",             eventGroup = "abundance", isSubQuest = true,
      description = "Accumulate 20,000 treasure points across multiple Abundance cave runs." },

    -- Legends of the Haranir (Harandar)
    { questID = 93891, title = "Legends of the Haranir",   category = "events", zone = "Harandar",       icon = "Interface\\Icons\\INV_Misc_Book_09",             eventGroup = "haranir",
      description = "Pick 1 of 7 ancient relics and complete its scenario. Warband-wide weekly pick." },
    { questID = 89268, title = "Lost Legends",             category = "events", zone = "Harandar",       icon = "Interface\\Icons\\INV_Misc_Rune_15",             eventGroup = "haranir", isSubQuest = true,
      description = "Select a Hara'ti relic to investigate at the Reliquary of the Zur'ashar." },

    -- Stormarion Assault (Voidstorm)
    { questID = 93892, title = "Stormarion Assault",       category = "events", zone = "Voidstorm",      icon = "Interface\\Icons\\Ability_Warrior_Charge",       eventGroup = "stormarion",
      description = "Tower defense: defend the Singularity Anchor against 3 waves of enemies." },
}

local KNOWN_QUEST_LOOKUP = {}
for i = 1, #KNOWN_WEEKLY_QUESTS do
    local entry = KNOWN_WEEKLY_QUESTS[i]
    KNOWN_QUEST_LOOKUP[entry.questID] = entry
    if entry.alternateIDs then
        for _, altID in ipairs(entry.alternateIDs) do
            KNOWN_QUEST_LOOKUP[altID] = entry
        end
    end
end

-- ============================================================================
-- QUEST CATEGORIES
-- ============================================================================

local QUEST_CATEGORIES = {
    { key = "weeklyQuests",    order = 1 },
    { key = "worldQuests",     order = 2 },
    { key = "dailyQuests",     order = 3 },
    { key = "assignments",     order = 4 },
    { key = "events",          order = 5 },
}

local CATEGORY_DISPLAY = {
    weeklyQuests = {
        name  = function() return (ns.L and ns.L["QUEST_CAT_WEEKLY"]) or "Weekly Quests" end,
        atlas = "questlog-questtypeicon-weekly",
        color = { 0.90, 0.70, 0.20 },
    },
    worldQuests = {
        name  = function() return (ns.L and ns.L["QUEST_CAT_WORLD"]) or "World Quests" end,
        atlas = "worldquest-icon",
        color = { 0.30, 0.80, 1.00 },
    },
    dailyQuests = {
        name  = function() return (ns.L and ns.L["QUEST_CAT_DAILY"]) or "Daily Quests" end,
        atlas = "questlog-questtypeicon-daily",
        color = { 0.40, 0.90, 0.40 },
    },
    assignments = {
        name  = function() return (ns.L and ns.L["QUEST_CAT_ASSIGNMENT"]) or "Assignments" end,
        atlas = "questlog-questtypeicon-important",
        color = { 1.00, 0.50, 0.25 },
    },
    events = {
        name  = function() return (ns.L and ns.L["QUEST_CAT_CONTENT_EVENTS"]) or "Content Events" end,
        atlas = "worldquest-questmarker-epic",
        color = { 0.80, 0.50, 1.00 },
    },
}

ns.QUEST_CATEGORIES = QUEST_CATEGORIES
ns.CATEGORY_DISPLAY = CATEGORY_DISPLAY

-- Default quest type selections for new plans
local DEFAULT_QUEST_TYPES = {
    weeklyQuests = true,
    worldQuests  = true,
    dailyQuests  = true,
    assignments  = true,
    events       = true,
}

local function NormalizeQuestTypes(questTypes)
    if type(questTypes) ~= "table" then
        local result = {}
        for k, v in pairs(DEFAULT_QUEST_TYPES) do result[k] = v end
        return result
    end
    return {
        weeklyQuests = (questTypes.weeklyQuests ~= false),
        worldQuests  = (questTypes.worldQuests ~= false),
        dailyQuests  = (questTypes.dailyQuests ~= false),
        assignments  = (questTypes.assignments ~= false),
        events       = (questTypes.events ~= false),
    }
end

-- ============================================================================
-- QUEST FLAG HELPERS
-- ============================================================================

local function IsSecretValue(value)
    return value and issecretvalue and issecretvalue(value)
end

local function CheckSingleQuestDone(questID)
    if not questID or not C_QuestLog then return false end

    if C_QuestLog.IsQuestFlaggedCompleted then
        local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and result == true then return true end
    end

    if C_QuestLog.IsComplete then
        local ok, result = pcall(C_QuestLog.IsComplete, questID)
        if ok and result == true then return true end
    end

    if C_QuestLog.ReadyForTurnIn then
        local ok, result = pcall(C_QuestLog.ReadyForTurnIn, questID)
        if ok and result == true then return true end
    end

    return false
end

local function IsQuestDone(questID)
    if CheckSingleQuestDone(questID) then return true end

    local known = KNOWN_QUEST_LOOKUP[questID]
    if known and known.alternateIDs then
        for _, altID in ipairs(known.alternateIDs) do
            if CheckSingleQuestDone(altID) then return true end
        end
    end

    return false
end

local function GetQuestProgress(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then
        return nil
    end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" or #objectives == 0 then return nil end

    local totalRequired, totalFulfilled, allFinished = 0, 0, true
    for i = 1, #objectives do
        local obj = objectives[i]
        if obj and type(obj) == "table" then
            totalRequired = totalRequired + (obj.numRequired or 1)
            totalFulfilled = totalFulfilled + (obj.numFulfilled or 0)
            if not obj.finished then allFinished = false end
        end
    end
    return {
        numObjectives   = #objectives,
        totalRequired   = totalRequired,
        totalFulfilled  = totalFulfilled,
        allFinished     = allFinished,
        percent         = totalRequired > 0 and (totalFulfilled / totalRequired) or 0,
    }
end

local function IsWorldQuest(questID)
    if not C_QuestLog or not C_QuestLog.IsWorldQuest then return false end
    local ok, result = pcall(C_QuestLog.IsWorldQuest, questID)
    return ok and result == true
end

local function IsCalling(questID)
    if not C_QuestLog or not C_QuestLog.IsQuestCalling then return false end
    local ok, result = pcall(C_QuestLog.IsQuestCalling, questID)
    return ok and result == true
end

local function GetTimeLeft(questID)
    if not C_TaskQuest or not C_TaskQuest.GetQuestTimeLeftMinutes then return 0 end
    local ok, value = pcall(C_TaskQuest.GetQuestTimeLeftMinutes, questID)
    return (ok and type(value) == "number") and value or 0
end

local function GetQuestTitle(questID, fallbackInfo)
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        title = C_QuestLog.GetTitleForQuestID(questID)
    end
    if (not title or title == "" or IsSecretValue(title)) and type(fallbackInfo) == "table" then
        title = fallbackInfo.title
    end
    if not title or title == "" or IsSecretValue(title) then
        title = (ns.L and ns.L["UNKNOWN_QUEST"]) or "Unknown Quest"
    end
    return title
end

local function GetObjectiveText(questID)
    if not C_QuestLog or not C_QuestLog.GetQuestObjectives then return "" end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" then return "" end
    for i = 1, #objectives do
        local obj = objectives[i]
        if obj and type(obj) == "table" and obj.text and obj.text ~= "" and not IsSecretValue(obj.text) then
            return obj.text
        end
    end
    return ""
end

-- ============================================================================
-- QUEST CATEGORIZATION
-- ============================================================================

local function DetermineQuestCategory(questID, questTitle, flags)
    if KNOWN_QUEST_LOOKUP[questID] then
        return KNOWN_QUEST_LOOKUP[questID].category
    end

    local lowerTitle = ""
    if type(questTitle) == "string" and questTitle ~= "" and not IsSecretValue(questTitle) then
        lowerTitle = questTitle:lower()
    end

    -- Special Assignments (title-based detection)
    if lowerTitle ~= "" then
        if lowerTitle:find("special assignment", 1, true) or lowerTitle:find("assignment:", 1, true) then
            return "assignments"
        end
        -- Prey hunts (individual contracts from Astalor Bloodsworn)
        if lowerTitle:find("prey:", 1, true) or lowerTitle:find("prey hunt", 1, true) then
            return "weeklyQuests"
        end
    end

    -- Weekly quests (flag-based)
    if flags.isWeekly or flags.isCalling then
        return "weeklyQuests"
    end

    -- Bounty quests -> assignments (Midnight uses bounties as special assignments)
    if flags.isBounty then
        return "assignments"
    end

    -- World quests
    if flags.isWorldQuest then
        return "worldQuests"
    end

    -- Daily quests
    if flags.isDaily then
        return "dailyQuests"
    end

    -- Bonus objectives -> events
    if flags.isBonusObjective then
        return "events"
    end

    -- Tasks with time limits -> events
    if flags.isTask and flags.timeLeft > 0 then
        return "events"
    end

    -- Tasks without time (bonus/area quests) -> worldQuests
    if flags.isTask then
        return "worldQuests"
    end

    -- Campaign quests -> assignments
    if flags.isCampaign then
        return "assignments"
    end

    return nil
end

-- ============================================================================
-- QUEST SCANNING
-- ============================================================================

function WarbandNexus:ScanMidnightQuests()
    local quests = {
        weeklyQuests = {},
        worldQuests  = {},
        dailyQuests  = {},
        assignments  = {},
        events       = {},
    }

    local addedIDs = {}

    local function AddQuest(questID, mapID, zoneName, questInfo, forceCategory)
        if type(questID) ~= "number" or questID <= 0 or addedIDs[questID] then
            return
        end

        local title = GetQuestTitle(questID, questInfo)
        local isComplete = IsQuestDone(questID)
        local isWQ = IsWorldQuest(questID)
        local timeLeft = GetTimeLeft(questID)
        local isCQ = IsCalling(questID)

        local frequency = (type(questInfo) == "table" and questInfo.frequency) or nil
        local isWeekly = (frequency == (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly))
        local isDaily = (type(questInfo) == "table" and questInfo.isDaily == true)
            or (frequency == (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily))
        local isTask = (type(questInfo) == "table" and questInfo.isTask == true)
        local isBounty = (type(questInfo) == "table" and questInfo.isBounty == true)
        local isCampaign = (type(questInfo) == "table" and questInfo.campaignID and questInfo.campaignID > 0)
        local isBonusObjective = (type(questInfo) == "table" and questInfo.isBonusObjective == true)

        local category = forceCategory or DetermineQuestCategory(questID, title, {
            isWorldQuest    = isWQ,
            isWeekly        = isWeekly,
            isDaily         = isDaily,
            isTask          = isTask,
            isBounty        = isBounty,
            isCalling       = isCQ,
            isCampaign      = isCampaign,
            isBonusObjective = isBonusObjective,
            timeLeft        = timeLeft,
        })

        if not category or not quests[category] then
            return
        end

        local known = KNOWN_QUEST_LOOKUP[questID]
        local progress = GetQuestProgress(questID)

        local questIcon = known and known.icon or nil
        local questDesc = known and known.description or nil
        local displayTitle = (known and known.title) or title

        -- Prey hunt auto-enrichment (dynamic quests with "Prey:" prefix)
        if not known and title:lower():find("prey:", 1, true) then
            questIcon = questIcon or "Interface\\Icons\\Ability_Hunter_KillCommand"
            questDesc = questDesc or "Prey hunt contract. Defeat enemies to track and fight your target."
        end

        local questData = {
            questID      = questID,
            title        = displayTitle,
            isComplete   = isComplete,
            zone         = (known and known.zone) or zoneName or "",
            mapID        = mapID or 0,
            timeLeft     = timeLeft,
            objective    = GetObjectiveText(questID),
            icon         = questIcon,
            description  = questDesc,
            isDaily      = isDaily,
            isWeekly     = isWeekly,
            isWorldQuest = isWQ,
            progress     = progress,
            eventGroup   = known and known.eventGroup or nil,
            isSubQuest   = known and known.isSubQuest or nil,
        }

        quests[category][#quests[category] + 1] = questData
        addedIDs[questID] = true
    end

    -- Phase 1: Hardcoded weekly quests (always check, even if not in quest log)
    for i = 1, #KNOWN_WEEKLY_QUESTS do
        local kq = KNOWN_WEEKLY_QUESTS[i]
        AddQuest(kq.questID, 0, kq.zone, nil, kq.category)
    end

    -- Phase 2: Map-based scanning (world quests, task quests, bounties)
    for mapID, zoneName in pairs(MIDNIGHT_MAPS) do
        if C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
            local ok, taskPOIs = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
            if ok and type(taskPOIs) == "table" then
                for j = 1, #taskPOIs do
                    local qi = taskPOIs[j]
                    if qi and qi.questID then
                        AddQuest(qi.questID, mapID, zoneName, qi)
                    end
                end
            end
        end

        if C_QuestLog and C_QuestLog.GetQuestsOnMap then
            local ok, mapQuests = pcall(C_QuestLog.GetQuestsOnMap, mapID)
            if ok and type(mapQuests) == "table" then
                for _, qi in pairs(mapQuests) do
                    if qi and qi.questID then
                        AddQuest(qi.questID, mapID, zoneName, qi)
                    end
                end
            end
        end

        if C_QuestLog and C_QuestLog.GetBountiesForMapID then
            local ok, bounties = pcall(C_QuestLog.GetBountiesForMapID, mapID)
            if ok and type(bounties) == "table" then
                for j = 1, #bounties do
                    local bi = bounties[j]
                    if bi and bi.questID then
                        bi.isBounty = true
                        AddQuest(bi.questID, mapID, zoneName, bi)
                    end
                end
            end
        end
    end

    -- Phase 3: Quest log scan (Midnight maps + Prey hunts regardless of map)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local inMidnight = info.mapID and MIDNIGHT_MAP_SET[info.mapID]
                local title = info.title or ""
                local lTitle = title:lower()
                local isPrey = lTitle:find("prey:", 1, true) or lTitle:find("prey hunt", 1, true)
                if inMidnight or isPrey then
                    local zoneName = info.zoneName or (info.mapID and MIDNIGHT_MAPS[info.mapID]) or ""
                    if isPrey and zoneName == "" then zoneName = "Quel'Thalas" end
                    AddQuest(info.questID, info.mapID or 0, zoneName, info)
                end
            end
        end
    end

    -- Sort each category
    for _, catInfo in ipairs(QUEST_CATEGORIES) do
        local list = quests[catInfo.key]
        if list then
            if catInfo.key == "events" then
                -- Events: group by eventGroup (main first, subs after), then incomplete first
                local EVENT_ORDER = { soiree = 1, abundance = 2, haranir = 3, stormarion = 4 }
                table.sort(list, function(a, b)
                    local aGroup = EVENT_ORDER[a.eventGroup or ""] or 99
                    local bGroup = EVENT_ORDER[b.eventGroup or ""] or 99
                    if aGroup ~= bGroup then return aGroup < bGroup end
                    local aSub = a.isSubQuest and 1 or 0
                    local bSub = b.isSubQuest and 1 or 0
                    if aSub ~= bSub then return aSub < bSub end
                    return (a.title or "") < (b.title or "")
                end)
            else
                -- Other categories: incomplete first, time left, alphabetically
                table.sort(list, function(a, b)
                    if a.isComplete ~= b.isComplete then
                        return not a.isComplete
                    end
                    local aTime = (type(a.timeLeft) == "number" and a.timeLeft > 0) and a.timeLeft or math.huge
                    local bTime = (type(b.timeLeft) == "number" and b.timeLeft > 0) and b.timeLeft or math.huge
                    if aTime ~= bTime then return aTime < bTime end
                    return (a.title or "") < (b.title or "")
                end)
            end
        end
    end

    return quests
end

-- ============================================================================
-- PLAN MANAGEMENT
-- ============================================================================

function WarbandNexus:CreateDailyPlan(characterName, characterRealm, questTypes)
    if not characterName or not characterRealm then
        self:Print("|cffff0000Error:|r Character name and realm required")
        return nil
    end

    if self:HasActiveDailyPlan(characterName, characterRealm) then
        self:Print("|cffff0000Error:|r " .. characterName .. "-" .. characterRealm .. " already has an active daily plan")
        return nil
    end

    if not self.db.global.plans then
        self.db.global.plans = {}
    end

    local planID = self.db.global.plansNextID or 1
    self.db.global.plansNextID = planID + 1

    local normalizedTypes = NormalizeQuestTypes(questTypes)
    local quests = self:ScanMidnightQuests()

    local _, currentClass = UnitClass("player")
    local characterClass
    local currentKey = ns.Utilities:GetCharacterKey()
    if ns.Utilities:GetCharacterKey(characterName, characterRealm) == currentKey then
        characterClass = currentClass
    end

    local plan = {
        id             = planID,
        type           = "daily_quests",
        characterName  = characterName,
        characterRealm = characterRealm,
        characterClass = characterClass,
        contentType    = "midnight",
        contentName    = "Midnight",
        questTypes     = normalizedTypes,
        name           = "Daily Tasks - " .. characterName,
        icon           = "Interface\\Icons\\Achievement_Zone_MidnightIsles",
        createdDate    = time(),
        lastUpdate     = time(),
        quests         = quests,
    }

    self.db.global.plans[#self.db.global.plans + 1] = plan
    self:SendMessage("WN_PLANS_UPDATED", {
        action   = "daily_plan_created",
        planID   = planID,
        planType = "daily_quests",
    })

    self:Print("|cff00ff00Created daily quest plan for:|r " .. characterName .. "-" .. characterRealm)
    return plan
end

function WarbandNexus:HasActiveDailyPlan(characterName, characterRealm)
    if not self.db.global.plans then return false end
    for i = 1, #self.db.global.plans do
        local plan = self.db.global.plans[i]
        if plan.type == "daily_quests"
            and plan.characterName == characterName
            and plan.characterRealm == characterRealm then
            return true
        end
    end
    return false
end

function WarbandNexus:GetDailyPlan(characterName, characterRealm)
    if not self.db.global.plans then return nil end
    for i = 1, #self.db.global.plans do
        local plan = self.db.global.plans[i]
        if plan.type == "daily_quests"
            and plan.characterName == characterName
            and plan.characterRealm == characterRealm then
            return plan
        end
    end
    return nil
end

function WarbandNexus:UpdateDailyPlanProgress(plan, skipNotifications)
    if not plan or plan.type ~= "daily_quests" then return end

    plan.questTypes = NormalizeQuestTypes(plan.questTypes)

    local oldQuests = plan.quests
    local newQuests = self:ScanMidnightQuests()

    -- Merge: preserve previously-tracked world quests that disappeared from API
    -- WQs vanish from C_TaskQuest.GetQuestsOnMap on completion; assume gone = done
    if oldQuests and oldQuests.worldQuests then
        local newWQIDs = {}
        for _, q in ipairs(newQuests.worldQuests or {}) do
            newWQIDs[q.questID] = true
        end
        for _, oldQ in ipairs(oldQuests.worldQuests) do
            if not newWQIDs[oldQ.questID] then
                oldQ.isComplete = true
                newQuests.worldQuests[#newQuests.worldQuests + 1] = oldQ
            end
        end
    end

    -- Merge: preserve completed Prey hunts (they leave the quest log after turn-in)
    if oldQuests and oldQuests.weeklyQuests then
        local newWeeklyIDs = {}
        for _, q in ipairs(newQuests.weeklyQuests or {}) do
            newWeeklyIDs[q.questID] = true
        end
        for _, oldQ in ipairs(oldQuests.weeklyQuests) do
            if not newWeeklyIDs[oldQ.questID] and oldQ.isComplete then
                local title = oldQ.title or ""
                local lower = title:lower()
                local isPrey = lower:find("prey:", 1, true) or lower:find("prey hunt", 1, true)
                if isPrey then
                    newQuests.weeklyQuests[#newQuests.weeklyQuests + 1] = oldQ
                end
            end
        end
    end

    plan.quests = newQuests
    plan.lastUpdate = time()

    self:SendMessage("WN_PLANS_UPDATED", {
        action   = "daily_plan_updated",
        planID   = plan.id,
        planType = "daily_quests",
    })
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function WarbandNexus:InitializeDailyQuestManager()
    self:RegisterEvent("QUEST_TURNED_IN", "OnDailyQuestCompleted")
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnDailyQuestUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnDailyQuestLogin")
end

function WarbandNexus:OnDailyQuestLogin()
    if not self.db.global.plans then return end
    C_Timer.After(3, function()
        local currentKey = ns.Utilities:GetCharacterKey()
        for _, plan in ipairs(self.db.global.plans) do
            local planKey = ns.Utilities:GetCharacterKey(plan.characterName, plan.characterRealm)
            if plan.type == "daily_quests" and planKey == currentKey then
                self:UpdateDailyPlanProgress(plan, true)
            end
        end
    end)
end

function WarbandNexus:OnDailyQuestCompleted(event, questID)
    ns.DebugPrint("|cff9370DB[DailyQuest]|r QUEST_TURNED_IN questID=" .. tostring(questID))
    if not self.db.global.plans then return end

    -- Cancel any pending QUEST_LOG_UPDATE rescan and block new ones briefly.
    -- QUEST_LOG_UPDATE fires almost simultaneously with QUEST_TURNED_IN but the
    -- quest-flag API may not reflect completion yet during that window.
    if self.questUpdateTimer then
        self.questUpdateTimer:Cancel()
        self.questUpdateTimer = nil
    end
    self.questTurnInGuard = GetTime()

    local currentKey = ns.Utilities:GetCharacterKey()

    for _, plan in ipairs(self.db.global.plans) do
        local planKey = ns.Utilities:GetCharacterKey(plan.characterName, plan.characterRealm)
        if plan.type == "daily_quests" and planKey == currentKey then
            local completedCategory, completedTitle

            -- Immediately mark the quest complete in current plan data
            -- (WQs/Prey hunts may vanish from the API before the rescan runs)
            if questID and plan.quests and plan.questTypes then
                for category, questList in pairs(plan.quests) do
                    if plan.questTypes[category] and type(questList) == "table" then
                        for i = 1, #questList do
                            if questList[i] and questList[i].questID == questID then
                                questList[i].isComplete = true
                                completedCategory = category
                                completedTitle = questList[i].title
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

    if self.SendMessage then
        self:SendMessage("WARBAND_QUEST_PROGRESS_UPDATED", {
            questID = questID,
            reason  = "QUEST_TURNED_IN",
        })
    end
end

function WarbandNexus:OnDailyQuestUpdate()
    ns.DebugPrint("|cff9370DB[DailyQuest]|r QUEST_LOG_UPDATE triggered")
    if not self.db.global.plans then return end

    -- Skip if a quest was just turned in (prevents race where flags aren't set yet)
    if self.questTurnInGuard and (GetTime() - self.questTurnInGuard) < 2 then return end

    if self.questUpdateTimer then return end

    self.questUpdateTimer = C_Timer.After(1, function()
        self.questUpdateTimer = nil
        local currentKey = ns.Utilities:GetCharacterKey()

        for _, plan in ipairs(self.db.global.plans) do
            local planKey = ns.Utilities:GetCharacterKey(plan.characterName, plan.characterRealm)
            if plan.type == "daily_quests" and planKey == currentKey then
                self:UpdateDailyPlanProgress(plan, true)
            end
        end

        if self.SendMessage then
            self:SendMessage("WARBAND_QUEST_PROGRESS_UPDATED", {
                reason = "QUEST_LOG_UPDATE",
            })
        end
    end)
end
