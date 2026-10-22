--[[
    Warband Nexus - Profession weekly knowledge (split from ProfessionService.lua, 2026-10-22)
    Midnight weekly knowledge sources (quests, treatise, gathering, catch-up currency), weekly reset
    sanitising and the per-skill-line progress collectors. Loaded after ProfessionService.lua; uses
    ns.ProfessionServiceShared (PS) and publishes its tables / collectors back on PS.
]]

local ADDON_NAME, ns = ...

local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local PS = ns.ProfessionServiceShared

assert(PS and PS.NotifyCollectorUpdate, "ProfessionService_WeeklyKnowledge.lua loaded before ProfessionService.lua - check the TOC")

local ResolveTrackedCharactersTableKey = PS.ResolveTrackedCharactersTableKey
local SafeAPIString = PS.SafeAPIString
local EnsureSkillLineBucket = PS.EnsureSkillLineBucket
local NotifyCollectorUpdate = PS.NotifyCollectorUpdate
local MIDNIGHT_SKILLLINE_TO_PARENT = PS.MIDNIGHT_SKILLLINE_TO_PARENT

-- Midnight weekly profession knowledge (MIDNIGHT_WEEKLY_SOURCES)
-- Detection: QuestProgressComplete() = flagged OR in-log complete OR ready for turn-in
--   OR GetInfo(logIndex).isComplete (quest still in journal).
-- Uniques / treasure: quest IDs match wow-professions.com "Treasure Check Macro" per profession
--   (891xx), plus extra one-time/patch IDs where listed (e.g. 93794 Alchemy).
-- Treatise (95127–95138): hidden weekly "consumed treatise" quests. Verified via WeeklyKnowledge addon.
--   Engineering intentionally uses 95138 (not sequential); 95132 unused.
-- Weekly trainer: 93690 Alch, 93691 BS, {93698,93699} Ench, 93692 Eng, 93693 Insc, 93694 JC,
--   93695 LW, 93696 Tailor. Enchanting has two variants (93698 + 93699) instead of "Services Requested".
-- Gathering (weekly drop caps): Enchanting (95048–95053), Herbalism (81425–81430),
--   Mining (88673–88678), Skinning (88534/88549/88537/88536/88530/88529). Verified via WeeklyKnowledge addon.
-- Source model: hardcoded quest IDs + catch-up currency (API).
local MIDNIGHT_WEEKLY_SOURCES = {
    [2906] = {
        catchUpCurrencyID = 3189,
        uniques = {89115, 89117, 89114, 89116, 89113, 89112, 89111, 89118, 93794},
        treatise = {95127},
        weeklyQuest = {93690}, weeklyQuestLimit = 1,
        treasure = {93528, 93529},
    },
    [2907] = {
        catchUpCurrencyID = 3199,
        uniques = {89177, 89178, 89179, 89180, 89181, 89182, 89183, 89184, 93795},
        treatise = {95128},
        weeklyQuest = {93691}, weeklyQuestLimit = 1,
        treasure = {93530, 93531},
    },
    -- Enchanting weekly: two variants — 93698 and 93699 ("A Ray of Sunlight" / Dawn Crystal turn-in to Dolothos).
    -- Unlike other crafting professions, Enchanting has NO "Services Requested" crafting-order weekly.
    -- Gathering: 5x Swirling Arcane Essence (95048-95052, 1 KP each) + 1x Brimming Mana Shard (95053, 4 KP).
    [2909] = {
        catchUpCurrencyID = 3198,
        uniques = {89100, 89101, 89102, 89103, 89104, 89105, 89106, 89107, 92374, 92186},
        treatise = {95129},
        weeklyQuest = {93698, 93699}, weeklyQuestLimit = 1,
        treasure = {93532, 93533},
        gathering = {95048, 95049, 95050, 95051, 95052, 95053},
    },
    [2910] = {
        catchUpCurrencyID = 3197,
        uniques = {89133, 89134, 89135, 89136, 89137, 89138, 89139, 89140, 93796},
        treatise = {95138},
        weeklyQuest = {93692}, weeklyQuestLimit = 1,
        treasure = {93534, 93535},
    },
    -- Herbalism gathering: 5x Thalassian Phoenix Plume (81425-81429, 1 KP each) + 1x Thalassian Phoenix Tail (81430, 4 KP).
    [2912] = {
        catchUpCurrencyID = 3196,
        uniques = {89162, 89161, 89160, 89159, 89158, 89157, 89156, 89155, 93411, 92174},
        treatise = {95130},
        weeklyQuest = {93700, 93702, 93703, 93704}, weeklyQuestLimit = 1,
        gathering = {81425, 81426, 81427, 81428, 81429, 81430},
    },
    [2913] = {
        catchUpCurrencyID = 3195,
        uniques = {89067, 89068, 89069, 89070, 89071, 89072, 89073, 89074, 93412},
        treatise = {95131},
        weeklyQuest = {93693}, weeklyQuestLimit = 1,
        treasure = {93536, 93537},
    },
    [2914] = {
        catchUpCurrencyID = 3194,
        uniques = {89122, 89123, 89124, 89125, 89126, 89127, 89128, 89129, 93222},
        treatise = {95133},
        weeklyQuest = {93694}, weeklyQuestLimit = 1,
        treasure = {93539, 93538},
    },
    [2915] = {
        catchUpCurrencyID = 3193,
        uniques = {89089, 89090, 89091, 89092, 89093, 89094, 89095, 89096, 92371},
        treatise = {95134},
        weeklyQuest = {93695}, weeklyQuestLimit = 1,
        treasure = {93540, 93541},
    },
    -- Mining gathering: 5x Igneous Rock Specimen (88673-88677, 1 KP each) + 1x Septarian Nodule (88678, 3 KP).
    [2916] = {
        catchUpCurrencyID = 3192,
        uniques = {89144, 89145, 89146, 89147, 89148, 89149, 89150, 89151, 92372, 92187},
        treatise = {95135},
        weeklyQuest = {93705, 93706, 93708, 93709}, weeklyQuestLimit = 1,
        gathering = {88673, 88674, 88675, 88676, 88677, 88678},
    },
    -- Skinning gathering: 5x Fine Void-Tempered Hide (88534/88549/88537/88536/88530, 1 KP each) + 1x Mana-Infused Bone (88529, 3 KP).
    [2917] = {
        catchUpCurrencyID = 3191,
        uniques = {89166, 89167, 89168, 89169, 89170, 89171, 89172, 89173, 92373, 92188},
        treatise = {95136},
        weeklyQuest = {93710, 93711, 93712, 93714}, weeklyQuestLimit = 1,
        gathering = {88534, 88549, 88537, 88536, 88530, 88529},
    },
    [2918] = {
        catchUpCurrencyID = 3190,
        uniques = {89078, 89079, 89080, 89081, 89082, 89083, 89084, 89085, 93201},
        treatise = {95137},
        weeklyQuest = {93696}, weeklyQuestLimit = 1,
        treasure = {93542, 93543},
    },
}

local MIDNIGHT_CATCHUP_CURRENCY = {
    [3189] = true, [3199] = true, [3198] = true, [3197] = true, [3196] = true, [3195] = true,
    [3194] = true, [3193] = true, [3192] = true, [3191] = true, [3190] = true,
}

local catchUpCurrencyToSkillLine = {}
for slID, source in pairs(MIDNIGHT_WEEKLY_SOURCES) do
    local cid = source and source.catchUpCurrencyID
    if cid and cid > 0 then
        catchUpCurrencyToSkillLine[cid] = slID
    end
end

local function CharacterHasMidnightSkillLine(charData, skillLineID)
    if not charData or not skillLineID then return false end
    if charData.professionData and charData.professionData.bySkillLine and charData.professionData.bySkillLine[skillLineID] then
        return true
    end
    if charData.professionWeeklyKnowledge and charData.professionWeeklyKnowledge[skillLineID] then
        return true
    end
    if (charData.recipes and charData.recipes[skillLineID])
        or (charData.knowledgeData and charData.knowledgeData[skillLineID])
        or (charData.concentration and charData.concentration[skillLineID]) then
        return true
    end
    if charData.discoveredSkillLines then
        for _, list in pairs(charData.discoveredSkillLines) do
            if type(list) == "table" then
                for i = 1, #list do
                    if list[i] and list[i].id == skillLineID then return true end
                end
            end
        end
    end
    if charData.professionExpansions then
        for _, list in pairs(charData.professionExpansions) do
            if type(list) == "table" then
                for i = 1, #list do
                    if list[i] and list[i].skillLineID == skillLineID then return true end
                end
            end
        end
    end
    local parentSkillLine = MIDNIGHT_SKILLLINE_TO_PARENT[skillLineID]
    if charData.professions and parentSkillLine then
        for _, prof in pairs(charData.professions) do
            if type(prof) == "table" and prof.skillLine == parentSkillLine then
                return true
            end
        end
    end
    if GetProfessions then
        local p1, p2 = GetProfessions()
        local pairsToCheck = { p1, p2 }
        for i = 1, #pairsToCheck do
            local idx = pairsToCheck[i]
            if idx then
                local _, _, _, _, _, _, sl = GetProfessionInfo(idx)
                if sl and sl == parentSkillLine then
                    return true
                end
            end
        end
    end
    return false
end

--- True if the quest counts as "done" for UI: flagged complete, in-log complete, or ready to turn in.
--- Matches DailyQuestManager so weekly profession rows update before the flag bit catches up.
local function QuestProgressComplete(questID)
    if not questID or not C_QuestLog then return false end
    if C_QuestLog.IsQuestFlaggedCompleted then
        local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if ok and done == true then return true end
    end
    if C_QuestLog.IsComplete then
        local ok, done = pcall(C_QuestLog.IsComplete, questID)
        if ok and done == true then return true end
    end
    if C_QuestLog.ReadyForTurnIn then
        local ok, done = pcall(C_QuestLog.ReadyForTurnIn, questID)
        if ok and done == true then return true end
    end
    -- (A QuestInfo.isComplete branch lived here; QuestInfo has no such field (12.1.5 API doc), so it
    -- never fired. C_QuestLog.IsComplete / ReadyForTurnIn above already cover "in log, objectives done".)
    return false
end

local function CountCompletedQuests(questIDs, limit)
    if type(questIDs) ~= "table" or #questIDs == 0 then
        return 0, 0
    end
    local completed = 0
    for i = 1, #questIDs do
        local questID = questIDs[i]
        if questID and QuestProgressComplete(questID) then
            completed = completed + 1
        end
    end
    if limit and limit > 0 then
        return (completed >= limit) and limit or completed, limit
    end
    return completed, #questIDs
end

local function BuildProgressEntry(current, total, source)
    if not total or total <= 0 then
        return { current = 0, total = 0, source = source }
    end
    if not current or current < 0 then current = 0 end
    if current > total then current = total end
    return { current = current, total = total, source = source }
end

local WEEKLY_PROGRESS_KEYS = {
    "firstCraft", "uniques", "treatise", "weeklyQuest", "treasure", "gathering", "catchUp",
}

local RECURRING_WEEKLY_PROGRESS_KEYS = {
    "weeklyQuest", "treatise", "treasure", "gathering",
}

local WEEK_SECONDS = 7 * 86400

local function HasWeeklyResetOccurredForTimestamp(timestamp)
    if ns.ResetService and ns.ResetService.HasWeeklyResetOccurred then
        return ns.ResetService.HasWeeklyResetOccurred(timestamp)
    end
    if not timestamp or timestamp == 0 then return true end
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local ok, secs = pcall(C_DateAndTime.GetSecondsUntilWeeklyReset)
        if ok and type(secs) == "number" and secs > 0 and secs <= WEEK_SECONDS then
            local now = (GetServerTime and GetServerTime()) or time()
            return timestamp < (now + secs - WEEK_SECONDS)
        end
    end
    if WarbandNexus and WarbandNexus.HasWeeklyResetOccurredSince then
        return WarbandNexus:HasWeeklyResetOccurredSince(timestamp)
    end
    return (time() - timestamp) >= WEEK_SECONDS
end

local function SanitizeWeeklyKnowledgeProgress(progress)
    if not progress or type(progress) ~= "table" then return nil end
    local lastUpdate = progress.lastUpdate or 0
    if HasWeeklyResetOccurredForTimestamp(lastUpdate) then
        for i = 1, #RECURRING_WEEKLY_PROGRESS_KEYS do
            local key = RECURRING_WEEKLY_PROGRESS_KEYS[i]
            local entry = progress[key]
            if entry and type(entry) == "table" and (entry.current or 0) > 0 then
                entry.current = 0
            end
        end
    end
    return progress
end

function WarbandNexus:HasWeeklyResetOccurredForTimestamp(timestamp)
    return HasWeeklyResetOccurredForTimestamp(timestamp)
end

function WarbandNexus:SanitizeWeeklyKnowledgeProgress(progress)
    return SanitizeWeeklyKnowledgeProgress(progress)
end

function WarbandNexus:GetCharacterWeeklyKnowledge(charData, skillLineID)
    if not charData or not skillLineID then return nil end
    local progressData = nil
    if charData.professionData and charData.professionData.bySkillLine and charData.professionData.bySkillLine[skillLineID] then
        progressData = charData.professionData.bySkillLine[skillLineID].weeklyKnowledge
    end
    if not progressData and charData.professionWeeklyKnowledge then
        progressData = charData.professionWeeklyKnowledge[skillLineID]
    end
    if progressData then
        return SanitizeWeeklyKnowledgeProgress(progressData)
    end
    return nil
end

ns.GetCharacterWeeklyKnowledge = function(charData, skillLineID)
    return WarbandNexus:GetCharacterWeeklyKnowledge(charData, skillLineID)
end

local function ProgressEntryEqual(a, b)
    if not a and not b then return true end
    if not a or not b then return false end
    return (tonumber(a.current) or 0) == (tonumber(b.current) or 0)
        and (tonumber(a.total) or 0) == (tonumber(b.total) or 0)
end

local function WeeklyKnowledgeProgressEqual(prev, next)
    if not prev and not next then return true end
    if not prev or not next then return false end
    for i = 1, #WEEKLY_PROGRESS_KEYS do
        if not ProgressEntryEqual(prev[WEEKLY_PROGRESS_KEYS[i]], next[WEEKLY_PROGRESS_KEYS[i]]) then
            return false
        end
    end
    return true
end

local function CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, professionName, expansionName)
    local source = MIDNIGHT_WEEKLY_SOURCES[skillLineID]
    if not source then return false end

    local bucket = EnsureSkillLineBucket(charData, skillLineID, professionName, expansionName or "Midnight")
    if not bucket then return false end

    local recipes = charData.recipes and charData.recipes[skillLineID]
    local firstCraftCurrent = recipes and recipes.firstCraftDoneCount or 0
    local firstCraftTotal = recipes and recipes.firstCraftTotalCount or 0
    -- Legacy fallback: old schema stored "firstCraftCount" against all recipes.
    -- That value mapped to "available first-craft bonus", not done-count.
    if firstCraftTotal <= 0 and recipes and recipes.firstCraftCount and recipes.firstCraftCount > 0 then
        firstCraftCurrent = 0
        firstCraftTotal = recipes.firstCraftCount
    end

    local uniquesCur, uniquesTotal = CountCompletedQuests(source.uniques)
    local treatiseCur, treatiseTotal = CountCompletedQuests(source.treatise)
    local weeklyCur, weeklyTotal = CountCompletedQuests(source.weeklyQuest, source.weeklyQuestLimit or 1)
    local treasureCur, treasureTotal = CountCompletedQuests(source.treasure)
    local gatheringCur, gatheringTotal = CountCompletedQuests(source.gathering)

    local catchUpCurrent, catchUpTotal = 0, 0
    if source.catchUpCurrencyID and source.catchUpCurrencyID > 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, currencyInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, source.catchUpCurrencyID)
        if ok and currencyInfo then
            catchUpCurrent = currencyInfo.quantity or 0
            catchUpTotal = currencyInfo.maxQuantity or 0
        end
    end
    -- Unreadable currency (nil info / 0 cap) keeps the previous catch-up entry.
    if catchUpTotal <= 0 then
        local prevWk = bucket.weeklyKnowledge
        local prevCatchUp = type(prevWk) == "table" and prevWk.catchUp
        if type(prevCatchUp) == "table" and (tonumber(prevCatchUp.total) or 0) > 0 then
            catchUpCurrent = tonumber(prevCatchUp.current) or 0
            catchUpTotal = tonumber(prevCatchUp.total) or 0
        end
    end

    local progress = {
        firstCraft  = BuildProgressEntry(firstCraftCurrent, firstCraftTotal, "api_recipe"),
        uniques     = BuildProgressEntry(uniquesCur, uniquesTotal, "hardcoded_quest"),
        treatise    = BuildProgressEntry(treatiseCur, treatiseTotal, "hardcoded_quest"),
        weeklyQuest = BuildProgressEntry(weeklyCur, weeklyTotal, "hardcoded_quest"),
        treasure    = BuildProgressEntry(treasureCur, treasureTotal, "hardcoded_quest"),
        gathering   = BuildProgressEntry(gatheringCur, gatheringTotal, "hardcoded_quest"),
        catchUp     = BuildProgressEntry(catchUpCurrent, catchUpTotal, "api_currency"),
        lastUpdate = time(),
    }

    -- Quest-flag counters never drop inside one weekly period (uniques never drop at all).
    -- During PLAYER_LOGOUT teardown the client reports every quest as not completed, so the
    -- logout flush used to overwrite real progress with 0 for each character on its own logout.
    -- Same total required: a changed quest list is a new baseline, not a regression.
    local prev = bucket.weeklyKnowledge
        or (charData.professionWeeklyKnowledge and charData.professionWeeklyKnowledge[skillLineID])
    if type(prev) == "table" then
        local prevSameWeek = not HasWeeklyResetOccurredForTimestamp(prev.lastUpdate or 0)
        for i = 0, #RECURRING_WEEKLY_PROGRESS_KEYS do
            local key = (i == 0) and "uniques" or RECURRING_WEEKLY_PROGRESS_KEYS[i]
            local old, new = prev[key], progress[key]
            if (i == 0 or prevSameWeek) and type(old) == "table" and new
                and (tonumber(old.total) or 0) == new.total
                and (tonumber(old.current) or 0) > new.current then
                new.current = tonumber(old.current)
            end
        end
    end

    if WeeklyKnowledgeProgressEqual(bucket.weeklyKnowledge, progress) then
        if bucket.weeklyKnowledge then
            bucket.weeklyKnowledge.lastUpdate = progress.lastUpdate or time()
        end
        if charData.professionWeeklyKnowledge and charData.professionWeeklyKnowledge[skillLineID] then
            charData.professionWeeklyKnowledge[skillLineID].lastUpdate = progress.lastUpdate or time()
        end
        return false
    end

    bucket.weeklyKnowledge = progress

    -- Legacy compatibility mirror
    charData.professionWeeklyKnowledge = charData.professionWeeklyKnowledge or {}
    charData.professionWeeklyKnowledge[skillLineID] = progress
    return true
end

local function RefreshAllMidnightKnowledgeProgressForCharacter(charData)
    if not charData then return 0 end
    local refreshed = 0
    for skillLineID in pairs(MIDNIGHT_WEEKLY_SOURCES) do
        if CharacterHasMidnightSkillLine(charData, skillLineID)
            and CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, nil, "Midnight") then
            refreshed = refreshed + 1
        end
    end
    return refreshed
end

local function CollectMidnightKnowledgeProgressData()
    if not WarbandNexus or not WarbandNexus.db then return end
    if not C_TradeSkillUI or not C_TradeSkillUI.GetProfessionChildSkillLineID then return end

    local charKey = ResolveTrackedCharactersTableKey()
    if not charKey then return end
    local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
    if not charData then return end

    local slOk, skillLineID = pcall(C_TradeSkillUI.GetProfessionChildSkillLineID)
    if not slOk or not skillLineID or not MIDNIGHT_WEEKLY_SOURCES[skillLineID] then return end

    local professionName, expansionName
    if C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local piOk, profInfo = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, skillLineID)
        if piOk and profInfo then
            professionName = SafeAPIString(profInfo.parentProfessionName) or SafeAPIString(profInfo.professionName)
            expansionName = SafeAPIString(profInfo.professionName)
        end
    end

    if CollectMidnightKnowledgeProgressForSkillLine(charData, skillLineID, professionName, expansionName) then
        NotifyCollectorUpdate("profession", E.PROFESSION_DATA_UPDATED, charKey)
    end
end

-- Read by ProfessionService.lua (recipe summary, currency / quest refresh, logout flush) and _Login.
PS.MIDNIGHT_WEEKLY_SOURCES = MIDNIGHT_WEEKLY_SOURCES
PS.MIDNIGHT_CATCHUP_CURRENCY = MIDNIGHT_CATCHUP_CURRENCY
PS.catchUpCurrencyToSkillLine = catchUpCurrencyToSkillLine
PS.RECURRING_WEEKLY_PROGRESS_KEYS = RECURRING_WEEKLY_PROGRESS_KEYS
PS.HasWeeklyResetOccurredForTimestamp = HasWeeklyResetOccurredForTimestamp
PS.CollectMidnightKnowledgeProgressForSkillLine = CollectMidnightKnowledgeProgressForSkillLine
PS.RefreshAllMidnightKnowledgeProgressForCharacter = RefreshAllMidnightKnowledgeProgressForCharacter
