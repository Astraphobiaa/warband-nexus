--[[
    Warband Nexus - Daily Quest Manager
    Tracks daily, weekly, world quests, assignments, and zone events for Midnight
    Uses hardcoded quest IDs for reliable weekly tracking + live quest log scanning
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local Utilities = ns.Utilities
local function CmpQuestTitle(a, b)
    return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.title) or "") < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.title) or "")
end

-- AceEvent identity: WN_PLANS_UPDATED → refresh daily-plan presence cache (one handler)
local DailyQuestManagerEvents = {}

--- Rebuild `_hasDailyQuestPlanCache` and `_dailyQuestPlansByCharKey` in one pass over `db.global.plans`
local function SyncDailyQuestPlanIndexes()
    WarbandNexus._hasDailyQuestPlanCache = false
    local idx = WarbandNexus._dailyQuestPlansByCharKey
    if not idx then
        idx = {}
        WarbandNexus._dailyQuestPlansByCharKey = idx
    else
        for k in pairs(idx) do
            idx[k] = nil
        end
    end

    local db = WarbandNexus.db
    if not db or not db.global or not db.global.plans then return end
    local plans = db.global.plans
    local getKey = ns.Utilities and ns.Utilities.GetCharacterKey
    if not getKey then return end

    for i = 1, #plans do
        local p = plans[i]
        if p and p.type == "daily_quests" then
            WarbandNexus._hasDailyQuestPlanCache = true
            local pk = getKey(p.characterName, p.characterRealm)
            if pk and pk ~= "" then
                local arr = idx[pk]
                if not arr then
                    arr = {}
                    idx[pk] = arr
                end
                arr[#arr + 1] = p
            end
        end
    end
end

local function GetDailyQuestPlansForCharKey(charKey)
    if not charKey or charKey == "" then return nil end
    local idx = WarbandNexus._dailyQuestPlansByCharKey
    if not idx then return nil end
    return idx[charKey]
end

--- Resolve daily_quests plan for name+realm; index first, linear fallback (same-frame create before debounced rebuild)
local function FindDailyPlanForCharacter(characterName, characterRealm)
    local db = WarbandNexus.db
    if not db or not db.global or not db.global.plans then return nil end
    local plans = db.global.plans
    local getKey = ns.Utilities and ns.Utilities.GetCharacterKey
    if not getKey then return nil end
    local pk = getKey(characterName, characterRealm)
    local list = GetDailyQuestPlansForCharKey(pk)
    if list then
        for i = 1, #list do
            local plan = list[i]
            if plan and plan.type == "daily_quests"
                and plan.characterName == characterName
                and plan.characterRealm == characterRealm then
                return plan
            end
        end
    end
    for i = 1, #plans do
        local plan = plans[i]
        if plan and plan.type == "daily_quests"
            and plan.characterName == characterName
            and plan.characterRealm == characterRealm then
            return plan
        end
    end
    return nil
end

-- UpdateDailyPlanProgress fires WN_PLANS_UPDATED per plan; coalesce index rebuild to one pass per frame burst
local dailyQuestIndexRebuildScheduled = false
local function RequestDailyQuestIndexRebuild()
    if dailyQuestIndexRebuildScheduled then return end
    dailyQuestIndexRebuildScheduled = true
    C_Timer.After(0, function()
        dailyQuestIndexRebuildScheduled = false
        SyncDailyQuestPlanIndexes()
    end)
end

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
local MIDNIGHT_MAPS_LIST = {}
for mapID in pairs(MIDNIGHT_MAPS) do
    MIDNIGHT_MAP_SET[mapID] = true
    MIDNIGHT_MAPS_LIST[#MIDNIGHT_MAPS_LIST + 1] = mapID
end
ns.MIDNIGHT_MAPS_FOR_SA = MIDNIGHT_MAPS_LIST

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
    { key = "events",          order = 4 },
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

-- When a WQ/daily vanishes from map APIs after turn-in, keep a "ghost" row until this time().
-- timeLeft on quest rows is in MINUTES (C_TaskQuest.GetQuestTimeLeftMinutes).
local function ComputeWQGhostExpiryFromSnapshot(q)
    if not q then return time() + 86400 end
    local tl = type(q.timeLeft) == "number" and q.timeLeft or 0
    if tl > 0 then
        return time() + (tl * 60)
    end
    return time() + 86400
end

local function ShouldDropExpiredWQGhost(q)
    if not q or not q.isComplete then return false end
    if q.wqGhostExpiresAt and type(q.wqGhostExpiresAt) == "number" and q.wqGhostExpiresAt > 0 then
        return time() >= q.wqGhostExpiresAt
    end
    return false
end

--[[
    Merge vanished dynamic quests (WQ/daily/assignment) back into the plan when:
    - API no longer lists them (turned in), but IsQuestFlaggedCompleted says done, OR
    - We already marked isComplete (QUEST_TURNED_IN) and ghost timer not expired.
    Drop ghosts only after wqGhostExpiresAt (remaining WQ window when last seen / at completion).
]]
local function ShouldMergeVanishedDynamic(catKey, oldQ, newIDs)
    if not oldQ or not oldQ.questID or newIDs[oldQ.questID] then
        return false
    end
    if ShouldDropExpiredWQGhost(oldQ) then
        return false
    end
    local done = CheckSingleQuestDone(oldQ.questID)
    if done then
        if not oldQ.isComplete then
            oldQ.isComplete = true
            oldQ.wqGhostExpiresAt = ComputeWQGhostExpiryFromSnapshot(oldQ)
        elseif not oldQ.wqGhostExpiresAt or oldQ.wqGhostExpiresAt <= 0 then
            oldQ.wqGhostExpiresAt = ComputeWQGhostExpiryFromSnapshot(oldQ)
        end
        return true
    end
    if oldQ.isComplete and not oldQ.isLocked then
        if not oldQ.wqGhostExpiresAt or oldQ.wqGhostExpiresAt <= 0 then
            oldQ.wqGhostExpiresAt = ComputeWQGhostExpiryFromSnapshot(oldQ)
        end
        return true
    end
    return false
end

local function SortDynamicQuestCategoryList(list)
    if not list or #list < 2 then return end
    table.sort(list, function(a, b)
        if a.isComplete ~= b.isComplete then
            return not a.isComplete
        end
        local aTime = (type(a.timeLeft) == "number" and a.timeLeft > 0) and a.timeLeft or math.huge
        local bTime = (type(b.timeLeft) == "number" and b.timeLeft > 0) and b.timeLeft or math.huge
        if aTime ~= bTime then return aTime < bTime end
        return CmpQuestTitle(a, b)
    end)
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

local function GetAllObjectiveDetails(questID)
    if not questID or not C_QuestLog or not C_QuestLog.GetQuestObjectives then return nil end
    local ok, objectives = pcall(C_QuestLog.GetQuestObjectives, questID)
    if not ok or type(objectives) ~= "table" or #objectives == 0 then return nil end

    local result = {}
    for i = 1, #objectives do
        local obj = objectives[i]
        if obj and type(obj) == "table" then
            local text = (obj.text and obj.text ~= "" and not IsSecretValue(obj.text)) and obj.text or nil
            result[#result + 1] = {
                text         = text,
                numFulfilled = obj.numFulfilled or 0,
                numRequired  = obj.numRequired or 1,
                finished     = obj.finished or false,
            }
        end
    end
    return #result > 0 and result or nil
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

    -- Title-based detection (before flag checks)
    if lowerTitle ~= "" then
        if lowerTitle:find("special assignment", 1, true) or lowerTitle:find("assignment:", 1, true) then
            return "worldQuests"
        end
        -- Prey hunts (individual contracts from Astalor Bloodsworn)
        if lowerTitle:find("prey:", 1, true) or lowerTitle:find("prey hunt", 1, true) then
            return "weeklyQuests"
        end
        -- WANTED quests (daily repeatable bounty-style, e.g. "WANTED: Toadshade's Petals")
        if lowerTitle:find("wanted:", 1, true) or lowerTitle:find("wanted ", 1, true) then
            return "dailyQuests"
        end
    end

    -- Weekly quests (flag-based)
    if flags.isWeekly or flags.isCalling then
        return "weeklyQuests"
    end

    -- World quests BEFORE generic bounty flag: map pins are often both WQ + bounty;
    -- if we classify as bounty first, WQs disappear from worldQuests and merge logic breaks.
    if flags.isWorldQuest then
        return "worldQuests"
    end

    -- Non-WQ bounties (e.g. Special Assignment-style pins without WQ flag) -> worldQuests
    if flags.isBounty then
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

    -- Campaign quests -> worldQuests
    if flags.isCampaign then
        return "worldQuests"
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

        -- Dynamic (non-hardcoded) weekly/event quests: skip if expired AND incomplete
        -- Hardcoded quests use IsQuestFlaggedCompleted which auto-resets on weekly server reset
        -- C_TaskQuest.GetQuestTimeLeftMinutes returns 0 for hardcoded quests (not task quests)
        if not known and (category == "weeklyQuests" or category == "events") then
            if not isComplete and (not timeLeft or timeLeft <= 0) then
                return
            end
        end
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
    local function IsTaskQuestActive(questID)
        if not C_TaskQuest or not C_TaskQuest.IsActive then return true end
        local ok, active = pcall(C_TaskQuest.IsActive, questID)
        return ok and active == true
    end

    for mapID, zoneName in pairs(MIDNIGHT_MAPS) do
        -- TaskQuest: prefer GetQuestsForPlayerByMapID (returns mapID per quest) to avoid wrong-zone WQs
        local taskPOIs
        if C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID then
            local ok, result = pcall(C_TaskQuest.GetQuestsForPlayerByMapID, mapID)
            if ok and type(result) == "table" then taskPOIs = result end
        end
        if not taskPOIs and C_TaskQuest and C_TaskQuest.GetQuestsOnMap then
            local ok, result = pcall(C_TaskQuest.GetQuestsOnMap, mapID)
            if ok and type(result) == "table" then taskPOIs = result end
        end
        if taskPOIs then
            for j = 1, #taskPOIs do
                local qi = taskPOIs[j]
                local qid = qi and (qi.questID or qi.questId)
                if qid and IsTaskQuestActive(qid) then
                    local questMapID = qi.mapID or qi.mapId
                    if not questMapID or questMapID == mapID then
                        AddQuest(qid, mapID, zoneName, qi)
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

        -- Phase 2b: Locked / prerequisite Special Assignment (GetBountySetInfoForMapID)
        -- MUST run even when GetBountiesForMapID returned other bounties (e.g. world-quest
        -- pins).  Previously we gated this on "no bounties on map", which hid every locked
        -- SA in zones like Harandar that already show WQ bounties — exactly the Midnight case.
        -- lockQuestID is the unlock line (e.g. "Complete 1 world quest in Harandar"), not the
        -- turned-in SA; we avoid AddQuest here because IsQuestDone can be stale across weeks.
        if C_QuestLog and C_QuestLog.GetBountySetInfoForMapID then
            local function TryAddLockedSA(checkMapID, saZone)
                local ok, dispLoc, lockQuestID, bountySetID, isActivitySet = pcall(C_QuestLog.GetBountySetInfoForMapID, checkMapID)
                if not ok or type(lockQuestID) ~= "number" or lockQuestID <= 0 then return end
                if addedIDs[lockQuestID] then return end

                local saTitle = GetQuestTitle(lockQuestID)
                if saTitle == ((ns.L and ns.L["UNKNOWN_QUEST"]) or "Unknown Quest") then
                    saTitle = "Special Assignment"
                end

                local progress = GetQuestProgress(lockQuestID)
                local objectiveText = GetObjectiveText(lockQuestID)

                quests.worldQuests[#quests.worldQuests + 1] = {
                    questID      = lockQuestID,
                    title        = saTitle,
                    isComplete   = false,
                    zone         = saZone,
                    mapID        = checkMapID,
                    timeLeft     = 0,
                    objective    = objectiveText,
                    icon         = "Interface\\Icons\\Achievement_General",
                    description  = objectiveText ~= "" and objectiveText or "Complete World Quests to unlock.",
                    isLocked     = true,
                    progress     = progress,
                }
                addedIDs[lockQuestID] = true
            end

            TryAddLockedSA(mapID, zoneName)

            if C_Map and C_Map.GetMapInfo then
                local mapInfo = C_Map.GetMapInfo(mapID)
                if mapInfo and mapInfo.parentMapID and mapInfo.parentMapID > 0 then
                    local parentZone = MIDNIGHT_MAPS[mapInfo.parentMapID] or zoneName
                    TryAddLockedSA(mapInfo.parentMapID, parentZone)
                end
            end
        end
    end

    -- Discover parent/continent maps for Midnight zones (used by Phase 2c + Phase 3)
    local midnightParentMaps = {}
    if C_Map and C_Map.GetMapInfo then
        for mapID in pairs(MIDNIGHT_MAPS) do
            local ok, mapInfo = pcall(C_Map.GetMapInfo, mapID)
            if ok and mapInfo and type(mapInfo) == "table"
                and mapInfo.parentMapID and mapInfo.parentMapID > 0
                and not MIDNIGHT_MAP_SET[mapInfo.parentMapID] then
                midnightParentMaps[mapInfo.parentMapID] = true
            end
        end
    end

    -- Phase 2c: Continent-level bounty scan for Special Assignments
    -- SAs are often registered on the parent/continent map (Quel'Thalas), not
    -- individual zone maps. Include: title mentions assignment, OR non-WQ bounty
    -- pin (WQ+bounty goes to worldQuests after DetermineQuestCategory order).
    if C_QuestLog and C_QuestLog.GetBountiesForMapID then
        for parentID in pairs(midnightParentMaps) do
            local bok, bounties = pcall(C_QuestLog.GetBountiesForMapID, parentID)
            if bok and type(bounties) == "table" then
                for j = 1, #bounties do
                    local bi = bounties[j]
                    if bi and bi.questID and not addedIDs[bi.questID] then
                        bi.isBounty = true
                        local bTitle = GetQuestTitle(bi.questID, bi)
                        local lt = type(bTitle) == "string" and bTitle:lower() or ""
                        local isWQ = IsWorldQuest(bi.questID)
                        if (not isWQ) or lt:find("assignment", 1, true) then
                            AddQuest(bi.questID, parentID, "Quel'Thalas", bi)
                        end
                    end
                end
            end
        end
    end

    -- Phase 3: Quest log scan (Midnight maps + Prey hunts + Midnight SAs)
    -- SAs in the quest log may have continent-level mapID (parent map), not a zone
    -- mapID, so we also accept SA-titled quests from midnightParentMaps.
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries = C_QuestLog.GetNumQuestLogEntries()
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and info.questID then
                local inMidnight = info.mapID and MIDNIGHT_MAP_SET[info.mapID]
                local inMidnightParent = info.mapID and midnightParentMaps[info.mapID]
                -- Never use info.title raw (may be secret); GetQuestTitle normalizes + fallback
                local title = GetQuestTitle(info.questID, info)
                local lTitle = title:lower()
                local isPrey = lTitle:find("prey:", 1, true) or lTitle:find("prey hunt", 1, true)
                local isMidnightSA = (inMidnight or inMidnightParent)
                    and (lTitle:find("special assignment", 1, true) or lTitle:find("assignment:", 1, true))

                if inMidnight or isPrey or isMidnightSA then
                    local zoneName = info.zoneName or (info.mapID and MIDNIGHT_MAPS[info.mapID]) or ""
                    if (isPrey or isMidnightSA) and zoneName == "" then zoneName = "Quel'Thalas" end
                    AddQuest(info.questID, info.mapID or 0, zoneName, info)
                end
            end
        end
    end

    -- Post-process events: main event isComplete derived from sub-quest completion
    do
        local eventList = quests.events
        if eventList and #eventList > 0 then
            local groupSubs = {}
            local groupMains = {}
            for i = 1, #eventList do
                local q = eventList[i]
                local grp = q.eventGroup
                if grp then
                    if q.isSubQuest then
                        if not groupSubs[grp] then groupSubs[grp] = {} end
                        groupSubs[grp][#groupSubs[grp] + 1] = q
                    else
                        if not groupMains[grp] then groupMains[grp] = {} end
                        groupMains[grp][#groupMains[grp] + 1] = q
                    end
                end
            end
            for grp, mains in pairs(groupMains) do
                local subs = groupSubs[grp]
                if subs and #subs > 0 then
                    local allSubsDone = true
                    for i = 1, #subs do
                        if not subs[i].isComplete then
                            allSubsDone = false
                            break
                        end
                    end
                    for i = 1, #mains do
                        mains[i].isComplete = allSubsDone
                    end
                end
            end
        end
    end

    -- Sort each category
    for _, catInfo in ipairs(QUEST_CATEGORIES) do
        local list = quests[catInfo.key]
        if list then
            if catInfo.key == "events" then
                -- Events: group by eventGroup (main first, subs after), incomplete first, then by title
                local EVENT_ORDER = { soiree = 1, abundance = 2, haranir = 3, stormarion = 4 }
                table.sort(list, function(a, b)
                    local aGroup = EVENT_ORDER[a.eventGroup or ""] or 99
                    local bGroup = EVENT_ORDER[b.eventGroup or ""] or 99
                    if aGroup ~= bGroup then return aGroup < bGroup end
                    local aSub = a.isSubQuest and 1 or 0
                    local bSub = b.isSubQuest and 1 or 0
                    if aSub ~= bSub then return aSub < bSub end
                    if a.isComplete ~= b.isComplete then return not a.isComplete end
                    return CmpQuestTitle(a, b)
                end)
            else
                SortDynamicQuestCategoryList(list)
            end
        end
    end

    -- Debug: dump scan results
    if ns.DebugPrint then
        local a = quests.worldQuests
        ns.DebugPrint("|cff9370DB[DailyQuest]|r ScanMidnightQuests: worldQuests=" .. #a)
        for i = 1, #a do
            ns.DebugPrint("|cff9370DB[DailyQuest]|r   WQ[" .. i .. "] id=" .. a[i].questID
                .. " title=" .. tostring(a[i].title)
                .. " zone=" .. tostring(a[i].zone)
                .. " map=" .. tostring(a[i].mapID)
                .. " done=" .. tostring(a[i].isComplete))
        end
        for parentID in pairs(midnightParentMaps) do
            ns.DebugPrint("|cff9370DB[DailyQuest]|r   midnightParentMap=" .. parentID)
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
        name           = ((ns.L and ns.L["DAILY_TASKS_PREFIX"]) or "Weekly Progress - ") .. characterName,
        iconAtlas      = "questlog-questtypeicon-daily",
        iconIsAtlas    = true,
        createdDate    = time(),
        lastUpdate     = time(),
        quests         = quests,
    }

    self.db.global.plans[#self.db.global.plans + 1] = plan
    self:SendMessage(E.PLANS_UPDATED, {
        action   = "daily_plan_created",
        planID   = planID,
        planType = "daily_quests",
    })

    self:Print("|cff00ff00Created daily quest plan for:|r " .. characterName .. "-" .. characterRealm)
    return plan
end

function WarbandNexus:HasActiveDailyPlan(characterName, characterRealm)
    return FindDailyPlanForCharacter(characterName, characterRealm) ~= nil
end

function WarbandNexus:GetDailyPlan(characterName, characterRealm)
    return FindDailyPlanForCharacter(characterName, characterRealm)
end

function WarbandNexus:UpdateDailyPlanProgress(plan, skipNotifications)
    if not plan or plan.type ~= "daily_quests" then return end

    plan.questTypes = NormalizeQuestTypes(plan.questTypes)
    plan.questTypes.assignments = nil
    if plan.quests then
        plan.quests.assignments = nil
    end

    local oldQuests = plan.quests
    local newQuests = self:ScanMidnightQuests()
    newQuests.assignments = nil

    -- Merge completed quests that vanished from API back into the plan
    -- Dynamic quests (WQ, daily, SA) disappear from API on turn-in
    -- Hardcoded quests (weekly, events) are always re-scanned so no merge needed
    if oldQuests then
        local hasReset = (self.HasWeeklyResetOccurredSince and self:HasWeeklyResetOccurredSince(plan.lastUpdate))

        for _, catKey in ipairs({"worldQuests", "dailyQuests"}) do
            local oldList = oldQuests[catKey]
            local newList = newQuests[catKey] or {}
            if oldList then
                local newIDs = {}
                for i = 1, #newList do
                    local q = newList[i]
                    if q and q.questID then newIDs[q.questID] = true end
                end
                for i = 1, #oldList do
                    local oldQ = oldList[i]
                    if oldQ and oldQ.questID and not newIDs[oldQ.questID] then
                        if ShouldMergeVanishedDynamic(catKey, oldQ, newIDs) then
                            newList[#newList + 1] = oldQ
                            newIDs[oldQ.questID] = true
                        end
                    end
                end
                newQuests[catKey] = newList
            end
            SortDynamicQuestCategoryList(newQuests[catKey])
        end

        -- Weekly/Events: hardcoded quests auto-refresh via Phase 1
        -- Dynamic weekly/events that completed but vanished: preserve until weekly reset
        if not hasReset then
            for _, catKey in ipairs({"weeklyQuests", "events"}) do
                local oldList = oldQuests[catKey]
                local newList = newQuests[catKey]
                if oldList and newList then
                    local newIDs = {}
                    for i = 1, #newList do
                        local q = newList[i]
                        if q and q.questID then newIDs[q.questID] = true end
                    end
                    for i = 1, #oldList do
                        local oldQ = oldList[i]
                        if oldQ and oldQ.questID and not newIDs[oldQ.questID] and oldQ.isComplete then
                            newList[#newList + 1] = oldQ
                        end
                    end
                end
            end
        end
    end

    plan.quests = newQuests
    plan.lastUpdate = time()

    self:SendMessage(E.PLANS_UPDATED, {
        action   = "daily_plan_updated",
        planID   = plan.id,
        planType = "daily_quests",
    })
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

function WarbandNexus:InitializeDailyQuestManager()
    if self._dailyQuestManagerInitialized then
        return
    end
    self._dailyQuestManagerInitialized = true

    -- QUEST_TURNED_IN: dispatched by EventManager's consolidated handler (avoids AceEvent overwrite)
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnDailyQuestUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnDailyQuestLogin")

    SyncDailyQuestPlanIndexes()
    WarbandNexus.RegisterMessage(DailyQuestManagerEvents, E.PLANS_UPDATED, function()
        RequestDailyQuestIndexRebuild()
    end)

    -- Periodic check for weekly reset: when reset occurs, refresh daily plans
    -- (expired weeklies are removed; new week's quests appear)
    if C_Timer and C_Timer.NewTicker then
        self.dailyQuestWeeklyCheckTime = time()
        if self._dailyQuestWeeklyTicker then
            self._dailyQuestWeeklyTicker:Cancel()
            self._dailyQuestWeeklyTicker = nil
        end
        self._dailyQuestWeeklyTicker = C_Timer.NewTicker(60, function()
            if not self.db or not self.db.global then return end
            if ns.Utilities and ns.Utilities.IsModuleEnabled and not ns.Utilities:IsModuleEnabled("plans") then return end
            if not self.db.global.plans then return end
            if not WarbandNexus._hasDailyQuestPlanCache then return end
            if not self.HasWeeklyResetOccurredSince then return end
            if self:HasWeeklyResetOccurredSince(self.dailyQuestWeeklyCheckTime or 0) then
                self.dailyQuestWeeklyCheckTime = time()
                local currentKey = ns.Utilities:GetCharacterKey()
                local dailyList = GetDailyQuestPlansForCharKey(currentKey)
                if dailyList then
                    for i = 1, #dailyList do
                        self:UpdateDailyPlanProgress(dailyList[i], true)
                    end
                end
                if self.SendMessage then
                    self:SendMessage(E.PLANS_UPDATED, { action = "weekly_reset", planType = "daily_quests" })
                end
            end
        end)
    end
end

function WarbandNexus:OnDailyQuestLogin()
    SyncDailyQuestPlanIndexes()
    if not self.db or not self.db.global or not self.db.global.plans then return end
    C_Timer.After(3, function()
        local currentKey = ns.Utilities:GetCharacterKey()
        local dailyList = GetDailyQuestPlansForCharKey(currentKey)
        if dailyList then
            for i = 1, #dailyList do
                self:UpdateDailyPlanProgress(dailyList[i], true)
            end
        end
    end)
end

function WarbandNexus:OnDailyQuestCompleted(event, questID)
    ns.DebugPrint("|cff9370DB[DailyQuest]|r QUEST_TURNED_IN questID=" .. tostring(questID))
    if not self.db or not self.db.global or not self.db.global.plans then return end

    -- Cancel any pending QUEST_LOG_UPDATE rescan and block new ones briefly.
    -- QUEST_LOG_UPDATE fires almost simultaneously with QUEST_TURNED_IN but the
    -- quest-flag API may not reflect completion yet during that window.
    if self.questUpdateTimer then
        self.questUpdateTimer:Cancel()
        self.questUpdateTimer = nil
    end
    self.questTurnInGuard = GetTime()

    local currentKey = ns.Utilities:GetCharacterKey()
    local dailyList = GetDailyQuestPlansForCharKey(currentKey)

    if dailyList then
        for pi = 1, #dailyList do
            local plan = dailyList[pi]
            local completedCategory, completedTitle

            -- Immediately mark the quest complete in current plan data
            -- (WQs/Prey hunts may vanish from the API before the rescan runs)
            if questID and plan.quests and plan.questTypes then
                for category, questList in pairs(plan.quests) do
                    if plan.questTypes[category] and type(questList) == "table" then
                        for i = 1, #questList do
                            if questList[i] and questList[i].questID == questID then
                                local q = questList[i]
                                q.isComplete = true
                                -- Ghost row persists until WQ window expires (timeLeft=min) or 24h fallback
                                q.wqGhostExpiresAt = ComputeWQGhostExpiryFromSnapshot(q)
                                completedCategory = category
                                completedTitle = q.title
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
        self:SendMessage(E.QUEST_PROGRESS_UPDATED, {
            questID = questID,
            reason  = "QUEST_TURNED_IN",
        })
    end
end

function WarbandNexus:OnDailyQuestUpdate()
    ns.DebugPrint("|cff9370DB[DailyQuest]|r QUEST_LOG_UPDATE triggered")
    if not self.db or not self.db.global or not self.db.global.plans then return end

    -- Skip if a quest was just turned in (prevents race where flags aren't set yet)
    if self.questTurnInGuard and (GetTime() - self.questTurnInGuard) < 2 then return end

    if self.questUpdateTimer then return end

    self.questUpdateTimer = C_Timer.NewTimer(1, function()
        self.questUpdateTimer = nil
        local currentKey = ns.Utilities:GetCharacterKey()
        local dailyList = GetDailyQuestPlansForCharKey(currentKey)
        if dailyList then
            for i = 1, #dailyList do
                self:UpdateDailyPlanProgress(dailyList[i], true)
            end
        end

        if self.SendMessage then
            self:SendMessage(E.QUEST_PROGRESS_UPDATED, {
                reason = "QUEST_LOG_UPDATE",
            })
        end
    end)
end

-- ============================================================================
-- CROSS-CHARACTER WEEKLY DASHBOARD AGGREGATOR
-- ============================================================================

---Aggregate weekly/daily completion status across all tracked characters.
---Returns a summary table keyed by charKey, each containing quest/vault/boss status.
---@return table dashboard { [charKey] = { weeklyQuests = {}, vault = {}, worldBoss = bool, delves = {} } }
function WarbandNexus:GetWeeklyDashboard()
    local dashboard = {}
    
    if not self.db or not self.db.global or not self.db.global.characters then
        return dashboard
    end
    
    local pveCache = self.db.global.pveCache
    
    for charKey, charData in pairs(self.db.global.characters) do
        if charData.isTracked then
            local entry = {
                name = charData.name,
                realm = charData.realm,
                classFile = charData.classFile,
                level = charData.level,
                itemLevel = charData.itemLevel,
                heroSpecName = charData.heroSpecName,
                weeklyQuests = {},
                vault = { raids = {}, mythicPlus = {}, world = {} },
                worldBoss = false,
                delves = {},
            }
            
            -- Weekly quest completion (from current character's live scan or DB plans)
            for i = 1, #KNOWN_WEEKLY_QUESTS do
                local q = KNOWN_WEEKLY_QUESTS[i]
                if q.category == "weeklyQuests" then
                    entry.weeklyQuests[q.questID] = {
                        title = q.title,
                        icon = q.icon,
                    }
                end
            end
            
            -- Great Vault progress
            if pveCache and pveCache.greatVault and pveCache.greatVault.activities then
                local vaultData = pveCache.greatVault.activities[charKey]
                if vaultData then
                    entry.vault.raids = vaultData.raids or {}
                    entry.vault.mythicPlus = vaultData.mythicPlus or {}
                    entry.vault.world = vaultData.world or {}
                end
            end
            
            -- World Boss
            if pveCache and pveCache.lockouts and pveCache.lockouts.worldBosses then
                local wb = pveCache.lockouts.worldBosses[charKey]
                if wb then
                    for _ in pairs(wb) do
                        entry.worldBoss = true
                        break
                    end
                end
            end
            
            -- Delves
            if pveCache and pveCache.delves and pveCache.delves.characters then
                entry.delves = pveCache.delves.characters[charKey] or {}
            end
            
            dashboard[charKey] = entry
        end
    end
    
    return dashboard
end
