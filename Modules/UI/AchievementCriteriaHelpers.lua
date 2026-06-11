--[[
    Warband Nexus — Achievement criteria / requirements / progress helpers

    Blizzard surface: GetAchievementNumCriteria, GetAchievementCriteriaInfo (wiki 12.0.1).
    criteriaType + assetID meaning table:
    https://warcraft.wiki.gg/wiki/API_GetAchievementCriteriaInfo

    UI display modes (achievement-level):
      instant       — no criteria rows
      quantity_bar  — aggregate current/required (reqQuantity, quantityString, description)
      checklist     — N of M criteria complete (binary rows)
      timed         — duration/elapsed on at least one criterion

    Per-row handler categories (criteriaType → handler):
      quantity, kill, quest, linked_achievement, reputation, exploration, pvp, spell, guild, meta, generic
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue
local floor = math.floor
local format = string.format
local pcall = pcall
local tonumber = tonumber
local tostring = tostring

local FormatNumber = ns.UI_FormatNumber or function(n) return tostring(floor(n or 0)) end

-- Blizzard criteriaType constants (wiki API_GetAchievementCriteriaInfo)

local CRITERIA_TYPE = {
    MONSTER_KILL = 0,
    WIN_PVP_OBJECTIVES = 1,
    REACH_LEVEL = 5,
    WEAPON_SKILL = 7,
    ACHIEVEMENT = 8,
    COMPLETE_QUESTS_GLOBAL = 9,
    DAILY_QUEST_EVERY_DAY = 10,
    COMPLETE_QUESTS_AREA = 11,
    CURRENCY = 12,
    COMPLETE_DAILY_QUESTS = 14,
    DIE_IN_LOCATION = 16,
    DEFEAT_ENCOUNTER = 20,
    COMPLETE_QUEST = 27,
    SPELL_CAST_ON_YOU = 28,
    CAST_SPELL = 29,
    PVP_OBJECTIVES = 30,
    PVP_KILLS_BG = 31,
    WIN_ARENA_LOCATION = 32,
    SQUASHLING = 34,
    PVP_KILLS_UNDER_INFLUENCE = 35,
    ACQUIRE_ITEM = 36,
    WIN_ARENAS = 37,
    ARENA_RATING_HIGHEST = 38,
    ARENA_RATING = 39,
    EAT_DRINK_ITEM = 41,
    FISHING_LOOT = 42,
    EXPLORATION = 43,
    PVP_RANK = 44,
    BANK_SLOTS = 45,
    EXALTED_FACTION = 46,
    FIVE_EXALTED = 47,
    EQUIP_ITEMS = 49,
    KILL_PLAYER_CLASS = 52,
    KILL_PLAYER_RACE = 53,
    EMOTE_ON_TARGET = 54,
    HEALING = 55,
    AV_WRECKING_BALL = 56,
    HAVE_ITEMS = 57,
    GOLD_FROM_VENDORS = 59,
    GOLD_FROM_QUESTS = 62,
    LOOT_GOLD = 67,
    READ_BOOK = 68,
    WORLD_PVP_KILL = 70,
    FISHING_SCHOOL = 72,
    KILL_MALGANIS_HEROIC = 73,
    EARN_TITLE = 74,
    OBTAIN_MOUNT = 75,
    OBTAIN_BATTLE_PET = 96,
    FISHING = 109,
    CAST_SPELL_ON_TARGET = 110,
    LEARN_COOKING = 112,
    HONORABLE_KILLS = 113,
    GUILD_REPAIR_GOLD = 124,
    GUILD_LEVEL = 125,
    GUILD_CRAFT = 126,
    GUILD_FISH = 127,
    GUILD_BANK_TABS = 128,
    GUILD_ACHIEVEMENT_POINTS = 129,
    RATED_BG_WIN = 130,
    RATED_BG_RATING = 132,
    GUILD_CREST = 133,
}

local DISPLAY_MODE = {
    INSTANT = "instant",
    QUANTITY_BAR = "quantity_bar",
    CHECKLIST = "checklist",
    TIMED = "timed",
}

local HANDLER = {
    QUANTITY = "quantity",
    KILL = "kill",
    QUEST = "quest",
    LINKED_ACHIEVEMENT = "linked_achievement",
    REPUTATION = "reputation",
    EXPLORATION = "exploration",
    PVP = "pvp",
    SPELL = "spell",
    GUILD = "guild",
    META = "meta",
    TIMED = "timed",
    GENERIC = "generic",
}

--- criteriaType → handler key (wiki table on API_GetAchievementCriteriaInfo)
local TYPE_TO_HANDLER = {
    [CRITERIA_TYPE.MONSTER_KILL] = HANDLER.KILL,
    [CRITERIA_TYPE.WIN_PVP_OBJECTIVES] = HANDLER.PVP,
    [CRITERIA_TYPE.REACH_LEVEL] = HANDLER.META,
    [CRITERIA_TYPE.WEAPON_SKILL] = HANDLER.META,
    [CRITERIA_TYPE.ACHIEVEMENT] = HANDLER.LINKED_ACHIEVEMENT,
    [CRITERIA_TYPE.COMPLETE_QUESTS_GLOBAL] = HANDLER.QUEST,
    [CRITERIA_TYPE.DAILY_QUEST_EVERY_DAY] = HANDLER.QUEST,
    [CRITERIA_TYPE.COMPLETE_QUESTS_AREA] = HANDLER.QUEST,
    [CRITERIA_TYPE.CURRENCY] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.COMPLETE_DAILY_QUESTS] = HANDLER.QUEST,
    [CRITERIA_TYPE.DIE_IN_LOCATION] = HANDLER.EXPLORATION,
    [CRITERIA_TYPE.DEFEAT_ENCOUNTER] = HANDLER.KILL,
    [CRITERIA_TYPE.COMPLETE_QUEST] = HANDLER.QUEST,
    [CRITERIA_TYPE.SPELL_CAST_ON_YOU] = HANDLER.SPELL,
    [CRITERIA_TYPE.CAST_SPELL] = HANDLER.SPELL,
    [CRITERIA_TYPE.PVP_OBJECTIVES] = HANDLER.PVP,
    [CRITERIA_TYPE.PVP_KILLS_BG] = HANDLER.PVP,
    [CRITERIA_TYPE.WIN_ARENA_LOCATION] = HANDLER.PVP,
    [CRITERIA_TYPE.SQUASHLING] = HANDLER.SPELL,
    [CRITERIA_TYPE.PVP_KILLS_UNDER_INFLUENCE] = HANDLER.PVP,
    [CRITERIA_TYPE.ACQUIRE_ITEM] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.WIN_ARENAS] = HANDLER.PVP,
    [CRITERIA_TYPE.ARENA_RATING_HIGHEST] = HANDLER.PVP,
    [CRITERIA_TYPE.ARENA_RATING] = HANDLER.PVP,
    [CRITERIA_TYPE.EAT_DRINK_ITEM] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.FISHING_LOOT] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.EXPLORATION] = HANDLER.EXPLORATION,
    [CRITERIA_TYPE.PVP_RANK] = HANDLER.PVP,
    [CRITERIA_TYPE.BANK_SLOTS] = HANDLER.META,
    [CRITERIA_TYPE.EXALTED_FACTION] = HANDLER.REPUTATION,
    [CRITERIA_TYPE.FIVE_EXALTED] = HANDLER.REPUTATION,
    [CRITERIA_TYPE.EQUIP_ITEMS] = HANDLER.META,
    [CRITERIA_TYPE.KILL_PLAYER_CLASS] = HANDLER.PVP,
    [CRITERIA_TYPE.KILL_PLAYER_RACE] = HANDLER.PVP,
    [CRITERIA_TYPE.EMOTE_ON_TARGET] = HANDLER.META,
    [CRITERIA_TYPE.HEALING] = HANDLER.META,
    [CRITERIA_TYPE.AV_WRECKING_BALL] = HANDLER.PVP,
    [CRITERIA_TYPE.HAVE_ITEMS] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.GOLD_FROM_VENDORS] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.GOLD_FROM_QUESTS] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.LOOT_GOLD] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.READ_BOOK] = HANDLER.EXPLORATION,
    [CRITERIA_TYPE.WORLD_PVP_KILL] = HANDLER.PVP,
    [CRITERIA_TYPE.FISHING_SCHOOL] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.KILL_MALGANIS_HEROIC] = HANDLER.KILL,
    [CRITERIA_TYPE.EARN_TITLE] = HANDLER.META,
    [CRITERIA_TYPE.OBTAIN_MOUNT] = HANDLER.META,
    [CRITERIA_TYPE.OBTAIN_BATTLE_PET] = HANDLER.META,
    [CRITERIA_TYPE.FISHING] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.CAST_SPELL_ON_TARGET] = HANDLER.SPELL,
    [CRITERIA_TYPE.LEARN_COOKING] = HANDLER.META,
    [CRITERIA_TYPE.HONORABLE_KILLS] = HANDLER.QUANTITY,
    [CRITERIA_TYPE.GUILD_REPAIR_GOLD] = HANDLER.GUILD,
    [CRITERIA_TYPE.GUILD_LEVEL] = HANDLER.GUILD,
    [CRITERIA_TYPE.GUILD_CRAFT] = HANDLER.GUILD,
    [CRITERIA_TYPE.GUILD_FISH] = HANDLER.GUILD,
    [CRITERIA_TYPE.GUILD_BANK_TABS] = HANDLER.GUILD,
    [CRITERIA_TYPE.GUILD_ACHIEVEMENT_POINTS] = HANDLER.GUILD,
    [CRITERIA_TYPE.RATED_BG_WIN] = HANDLER.PVP,
    [CRITERIA_TYPE.RATED_BG_RATING] = HANDLER.PVP,
    [CRITERIA_TYPE.GUILD_CREST] = HANDLER.GUILD,
}

-- Low-level parsing

--- Wiki GetAchievementInfo: id, name, points, completed, month, day, year, description (8th).
local function GetAchievementDescriptionAndPoints(achievementID)
    if not achievementID or not GetAchievementInfo then return nil, nil end
    local ok, _, _, points, _, _, _, _, description = pcall(GetAchievementInfo, achievementID)
    if not ok then return nil, nil end
    if description and (issecretvalue and issecretvalue(description)) then
        description = nil
    end
    if points and (issecretvalue and issecretvalue(points)) then
        points = nil
    end
    return description, tonumber(points)
end

local function GetAchievementDescription(achievementID)
    return GetAchievementDescriptionAndPoints(achievementID)
end

local function ParseDescriptionProgressTarget(achievementID)
    local achDesc = GetAchievementDescription(achievementID)
    if not achDesc or achDesc == "" then
        return nil
    end
    local target = achDesc:match("Harvest%s+(%d+)")
        or achDesc:match("Collect%s+(%d+)")
        or achDesc:match("Loot%s+[^%(]+%((%d+)%)")
        or achDesc:match("(%d+)%s+%S+%s+Lumber")
    return tonumber(target)
end

local function ResolveCriteriaQuantities(quantity, reqQuantity, quantityString)
    local q, rq
    if not (issecretvalue and issecretvalue(quantity)) then
        q = tonumber(quantity)
    end
    if not (issecretvalue and issecretvalue(reqQuantity)) then
        rq = tonumber(reqQuantity)
    end
    if (not rq or rq <= 0) and quantityString
        and not (issecretvalue and issecretvalue(quantityString)) then
        local qs, rs = tostring(quantityString):match("(%d+)%s*/%s*(%d+)")
        if qs and rs then
            q = tonumber(qs)
            rq = tonumber(rs)
        end
    end
    return q, rq
end

local function FormatDurationSeconds(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 0 then seconds = 0 end
    local h = floor(seconds / 3600)
    local m = floor((seconds % 3600) / 60)
    local s = floor(seconds % 60)
    if h > 0 then
        return format("%d:%02d:%02d", h, m, s)
    end
    return format("%d:%02d", m, s)
end

---@param criteriaType number|nil
---@param duration number|nil
---@return string handlerKey
local function ClassifyCriteriaHandler(criteriaType, duration)
    local dur = tonumber(duration)
    if dur and dur > 0 and not (issecretvalue and issecretvalue(duration)) then
        return HANDLER.TIMED
    end
    local t = tonumber(criteriaType)
    if t and TYPE_TO_HANDLER[t] then
        return TYPE_TO_HANDLER[t]
    end
    return HANDLER.GENERIC
end

-- Per-handler helpers

local HandlerApi = {}

function HandlerApi.quantityRowSuffix(row)
    local q, rq = row.quantity, row.reqQuantity
    if (not rq or rq <= 1) and row.descriptionTarget and row.descriptionTarget > 1 then
        rq = row.descriptionTarget
    end
    if not rq or rq <= 1 then return "" end
    if q == nil then q = 0 end
    return format(" (%s / %s)", FormatNumber(q), FormatNumber(rq))
end

function HandlerApi.checklistRowSuffix()
    return ""
end

function HandlerApi.timedRowSuffix(row)
    local dur = tonumber(row.duration)
    local el = tonumber(row.elapsed)
    if not dur or dur <= 0 then return "" end
    if el == nil then el = 0 end
    return format(" (%s / %s)", FormatDurationSeconds(el), FormatDurationSeconds(dur))
end

function HandlerApi.aggregateQuantity(row, acc)
    local q, rq = row.quantity, row.reqQuantity
    if q and q > (acc.maxSeenQuantity or 0) then
        acc.maxSeenQuantity = q
    end
    if rq and rq > 0 then
        acc.hasProgressBased = true
        acc.totalQuantity = (acc.totalQuantity or 0) + (q or 0)
        acc.totalReqQuantity = (acc.totalReqQuantity or 0) + rq
    end
end

function HandlerApi.aggregateChecklist(row, acc)
    if row.hasName then
        acc.namedCriteriaCount = (acc.namedCriteriaCount or 0) + 1
        if row.completed then
            acc.completedCount = (acc.completedCount or 0) + 1
        end
    end
end

function HandlerApi.aggregateTimed(row, acc)
    HandlerApi.aggregateChecklist(row, acc)
    local dur = tonumber(row.duration)
    if dur and dur > 0 then
        acc.hasTimed = true
        acc.timedDuration = dur
        acc.timedElapsed = tonumber(row.elapsed) or 0
    end
end

local ROW_SUFFIX = {
    [HANDLER.QUANTITY] = HandlerApi.quantityRowSuffix,
    [HANDLER.KILL] = HandlerApi.checklistRowSuffix,
    [HANDLER.QUEST] = HandlerApi.checklistRowSuffix,
    [HANDLER.LINKED_ACHIEVEMENT] = HandlerApi.checklistRowSuffix,
    [HANDLER.REPUTATION] = HandlerApi.quantityRowSuffix,
    [HANDLER.EXPLORATION] = HandlerApi.checklistRowSuffix,
    [HANDLER.PVP] = HandlerApi.checklistRowSuffix,
    [HANDLER.SPELL] = HandlerApi.checklistRowSuffix,
    [HANDLER.GUILD] = HandlerApi.quantityRowSuffix,
    [HANDLER.META] = HandlerApi.checklistRowSuffix,
    [HANDLER.TIMED] = HandlerApi.timedRowSuffix,
    [HANDLER.GENERIC] = HandlerApi.checklistRowSuffix,
}

local AGGREGATE = {
    [HANDLER.QUANTITY] = HandlerApi.aggregateQuantity,
    [HANDLER.KILL] = HandlerApi.aggregateChecklist,
    [HANDLER.QUEST] = HandlerApi.aggregateChecklist,
    [HANDLER.LINKED_ACHIEVEMENT] = HandlerApi.aggregateChecklist,
    [HANDLER.REPUTATION] = HandlerApi.aggregateQuantity,
    [HANDLER.EXPLORATION] = HandlerApi.aggregateChecklist,
    [HANDLER.PVP] = HandlerApi.aggregateChecklist,
    [HANDLER.SPELL] = HandlerApi.aggregateChecklist,
    [HANDLER.GUILD] = HandlerApi.aggregateQuantity,
    [HANDLER.META] = HandlerApi.aggregateChecklist,
    [HANDLER.TIMED] = HandlerApi.aggregateTimed,
    [HANDLER.GENERIC] = HandlerApi.aggregateChecklist,
}

-- Fetch & summarize

---@param achievementID number
---@param criteriaIndex number
---@return table|nil row
local function FetchCriterionRow(achievementID, criteriaIndex, descriptionTarget)
    local ok, criteriaName, criteriaType, completed, quantity, reqQuantity, _, _, assetID, quantityString, _, _, duration, elapsed =
        pcall(GetAchievementCriteriaInfo, achievementID, criteriaIndex)
    if not ok then return nil end

    local q, rq = ResolveCriteriaQuantities(quantity, reqQuantity, quantityString)
    local handlerKey = ClassifyCriteriaHandler(criteriaType, duration)
    local hasName = criteriaName and not (issecretvalue and issecretvalue(criteriaName)) and criteriaName ~= ""
    local ct = tonumber(criteriaType)
    local linkedID = nil
    if handlerKey == HANDLER.LINKED_ACHIEVEMENT and assetID and tonumber(assetID) and tonumber(assetID) > 0 then
        linkedID = tonumber(assetID)
    end

    return {
        index = criteriaIndex,
        name = hasName and criteriaName or nil,
        hasName = hasName,
        criteriaType = ct,
        handlerKey = handlerKey,
        completed = completed and true or false,
        quantity = q,
        reqQuantity = rq,
        quantityString = quantityString,
        descriptionTarget = descriptionTarget,
        duration = tonumber(duration),
        elapsed = tonumber(elapsed),
        linkedAchievementID = linkedID,
    }
end

local function ResolveDisplayMode(summary)
    if (summary.rawNumCriteria or 0) <= 0 then
        return DISPLAY_MODE.INSTANT
    end
    if summary.hasTimed and summary.timedDuration and summary.timedDuration > 0 then
        return DISPLAY_MODE.TIMED
    end
    if summary.hasProgressBased and summary.totalReqQuantity and summary.totalReqQuantity > 0 then
        return DISPLAY_MODE.QUANTITY_BAR
    end
    return DISPLAY_MODE.CHECKLIST
end

---@param achievementID number|nil
---@return table|nil summary
local function SummarizeAchievementCriteria(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(achievementID) then return nil end
    if not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then return nil end

    local rawNumCriteria = GetAchievementNumCriteria(achievementID)
    if issecretvalue and issecretvalue(rawNumCriteria) then rawNumCriteria = 0 end
    rawNumCriteria = tonumber(rawNumCriteria) or 0

    local descriptionTarget = ParseDescriptionProgressTarget(achievementID)
    local summary = {
        achievementID = achievementID,
        rawNumCriteria = rawNumCriteria,
        namedCriteriaCount = 0,
        completedCount = 0,
        hasProgressBased = false,
        totalQuantity = 0,
        totalReqQuantity = 0,
        maxSeenQuantity = 0,
        descriptionTarget = descriptionTarget,
        hasTimed = false,
        timedDuration = nil,
        timedElapsed = nil,
        displayMode = DISPLAY_MODE.INSTANT,
        criteria = {},
    }

    if rawNumCriteria <= 0 then
        summary.displayMode = DISPLAY_MODE.INSTANT
        return summary
    end

    local acc = summary
    for criteriaIndex = 1, rawNumCriteria do
        local row = FetchCriterionRow(achievementID, criteriaIndex, descriptionTarget)
        if row then
            summary.criteria[#summary.criteria + 1] = row
            local fn = AGGREGATE[row.handlerKey] or HandlerApi.aggregateChecklist
            fn(row, acc)
        end
    end

    if not summary.hasProgressBased and rawNumCriteria == 1
        and descriptionTarget and descriptionTarget > 1 then
        summary.hasProgressBased = true
        summary.totalQuantity = summary.maxSeenQuantity or 0
        summary.totalReqQuantity = descriptionTarget
    end

    summary.displayMode = ResolveDisplayMode(summary)
    return summary
end

-- Formatting (headers + row suffixes)

local function FormatChecklistProgressHeader(summary)
    local denom = summary.rawNumCriteria or 0
    if denom <= 0 then return "" end
    local pct = floor((summary.completedCount / denom) * 100)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    local achFmt = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
    return format(achFmt, FormatNumber(summary.completedCount), FormatNumber(denom), FormatNumber(pct))
end

local function FormatQuantityProgressHeader(summary)
    local pct = floor((summary.totalQuantity / summary.totalReqQuantity) * 100)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return format("%s / %s (%s%%)", FormatNumber(summary.totalQuantity), FormatNumber(summary.totalReqQuantity), FormatNumber(pct))
end

local function FormatTimedProgressHeader(summary)
    local dur = summary.timedDuration or 0
    local el = summary.timedElapsed or 0
    if dur <= 0 then return FormatChecklistProgressHeader(summary) end
    local pct = floor((el / dur) * 100)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return format("%s / %s (%s%%)", FormatDurationSeconds(el), FormatDurationSeconds(dur), FormatNumber(pct))
end

local HEADER_BY_MODE = {
    [DISPLAY_MODE.QUANTITY_BAR] = FormatQuantityProgressHeader,
    [DISPLAY_MODE.CHECKLIST] = FormatChecklistProgressHeader,
    [DISPLAY_MODE.TIMED] = FormatTimedProgressHeader,
    [DISPLAY_MODE.INSTANT] = function() return "" end,
}

local function FormatAchievementProgressHeader(summary)
    if not summary then return "" end
    local mode = summary.displayMode or ResolveDisplayMode(summary)
    local fn = HEADER_BY_MODE[mode] or FormatChecklistProgressHeader
    return fn(summary)
end

--- Parenthetical for To-Do summary: "(0 / 250 - 0%)" or "(18 of 30 - 60%)".
local function FormatAchievementProgressParenthetical(summary)
    if not summary then return "" end
    local mode = summary.displayMode or ResolveDisplayMode(summary)
    if mode == DISPLAY_MODE.QUANTITY_BAR and summary.totalReqQuantity and summary.totalReqQuantity > 0 then
        local pct = floor((summary.totalQuantity / summary.totalReqQuantity) * 100)
        if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
        return format("(%s / %s - %s%%)", FormatNumber(summary.totalQuantity), FormatNumber(summary.totalReqQuantity), FormatNumber(pct))
    end
    if mode == DISPLAY_MODE.TIMED and summary.timedDuration and summary.timedDuration > 0 then
        local pct = floor(((summary.timedElapsed or 0) / summary.timedDuration) * 100)
        if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
        return format("(%s / %s - %s%%)", FormatDurationSeconds(summary.timedElapsed or 0), FormatDurationSeconds(summary.timedDuration), FormatNumber(pct))
    end
    local denom = summary.rawNumCriteria or 0
    if denom <= 0 then return "" end
    local pct = floor((summary.completedCount / denom) * 100)
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return format("(%s of %s - %s%%)", FormatNumber(summary.completedCount), FormatNumber(denom), FormatNumber(pct))
end

local function NormalizeUiLabel(key, fallback)
    local lab = (ns.L and ns.L[key]) or fallback
    if ns.UI_NormalizeColonLabelSpacing then
        return ns.UI_NormalizeColonLabelSpacing(lab)
    end
    return (lab:gsub("%s*:%s*$", "") .. " : ")
end

local function SanitizeAchievementText(text, maxLen)
    if not text or text == "" or (issecretvalue and issecretvalue(text)) then
        return nil
    end
    text = text:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if maxLen and #text > maxLen then
        text = text:sub(1, maxLen - 3) .. "..."
    end
    return text
end

--- Achievement description for Description: line (API description, then plan text, then first criterion name).
---@param planDescription string|nil
local function GetAchievementDescriptionText(summary, achievementID, planDescription)
    local fromPlan = SanitizeAchievementText(planDescription, 72)
    if fromPlan then return fromPlan end
    local fromApi = SanitizeAchievementText(GetAchievementDescription(achievementID), 72)
    if fromApi then return fromApi end
    if summary and summary.criteria then
        for i = 1, #summary.criteria do
            local row = summary.criteria[i]
            local name = row.hasName and SanitizeAchievementText(row.name, 72)
            if name then return name end
        end
    end
    return nil
end

local function UsesProgressLabelForSummary(summary)
    if not summary then return false end
    local mode = summary.displayMode or ResolveDisplayMode(summary)
    return mode == DISPLAY_MODE.QUANTITY_BAR or mode == DISPLAY_MODE.TIMED
end

--- User-entered custom plan body (stored in source on create; legacy rows may use description/note).
local function GetCustomPlanBodyText(plan)
    if not plan or plan.type ~= "custom" then return nil end
    local customDefault = (ns.L and ns.L["CUSTOM_PLAN_SOURCE"]) or "Custom plan"
    local d = plan.source or plan.description or plan.note or ""
    if type(d) ~= "string" or d == "" or d == "Custom plan" or d == customDefault then
        return nil
    end
    if issecretvalue and issecretvalue(d) then return nil end
    return SanitizeAchievementText(d, 72)
end

--- Summary field rows for To-Do header (Description + Progress or Requirements).
---@return table fields { labelKey, fallback, value, iconMarkup? }[]
local function BuildAchievementTodoSummaryFields(summary, achievementID, planDescription)
    local fields = {}
    local numCriteria = summary and (summary.rawNumCriteria or 0) or 0

    local descText = GetAchievementDescriptionText(summary, achievementID, planDescription)
    if descText then
        fields[#fields + 1] = {
            labelKey = "DESCRIPTION_LABEL",
            fallback = "Description:",
            value = descText,
        }
    end

    if numCriteria <= 0 then
        return fields
    end

    local paren = FormatAchievementProgressParenthetical(summary)
    if paren and paren ~= "" then
        if UsesProgressLabelForSummary(summary) then
            fields[#fields + 1] = {
                labelKey = "PROGRESS_LABEL",
                fallback = "Progress:",
                value = paren,
            }
        else
            fields[#fields + 1] = {
                labelKey = "REQUIREMENTS_LABEL",
                fallback = "Requirements:",
                value = paren,
            }
        end
    end
    return fields
end

local function SummaryFieldsToColoredLines(fields)
    local lines = {}
    if not fields then return lines end
    local P = ns.PLAN_UI_COLORS or {}
    local labCol = P.progressLabel or "|cffffcc00"
    local body = P.incomplete or "|cffffffff"
    for i = 1, #fields do
        local field = fields[i]
        if field and field.value and field.value ~= "" then
            local lab = NormalizeUiLabel(field.labelKey, field.fallback)
            local prefix = field.iconMarkup and (field.iconMarkup .. " ") or ""
            lines[#lines + 1] = prefix .. labCol .. lab .. "|r " .. body .. field.value .. "|r"
        end
    end
    return lines
end

--- To-Do header lines for custom plans (Description: …).
local function BuildCustomPlanTodoSummaryLines(plan)
    local body = GetCustomPlanBodyText(plan)
    if not body then return {} end
    return SummaryFieldsToColoredLines({
        {
            labelKey = "DESCRIPTION_LABEL",
            fallback = "Description:",
            value = body,
        },
    })
end

--- To-Do card summary lines (legacy string form).
local function BuildAchievementTodoSummaryLines(summary, achievementID, planDescription)
    return SummaryFieldsToColoredLines(BuildAchievementTodoSummaryFields(summary, achievementID, planDescription))
end

--- Legacy single-line join (prefer BuildAchievementTodoSummaryLines).
local function FormatAchievementTodoSummaryLine(summary, achievementID, planDescription)
    local parts = BuildAchievementTodoSummaryLines(summary, achievementID, planDescription)
    if #parts == 0 then return "" end
    return table.concat(parts, " ")
end

--- Expand only when multiple criteria rows are worth listing (e.g. 18 of 30). Pure progress bars stay collapsed.
local function ShouldAchievementTodoExpand(summary)
    if not summary or (summary.rawNumCriteria or 0) <= 0 then return false end
    local named = summary.namedCriteriaCount or 0
    local total = summary.rawNumCriteria or 0
    if total <= 1 and named <= 1 then
        return false
    end
    local mode = summary.displayMode or ResolveDisplayMode(summary)
    if mode == DISPLAY_MODE.QUANTITY_BAR or mode == DISPLAY_MODE.TIMED then
        return named > 1
    end
    return total > 1
end

local function FormatAchievementCriteriaQuantitySuffix(quantity, reqQuantity, quantityString, descriptionTarget, handlerKey)
    local row = {
        quantity = nil,
        reqQuantity = nil,
        descriptionTarget = descriptionTarget,
        duration = nil,
        elapsed = nil,
    }
    row.quantity, row.reqQuantity = ResolveCriteriaQuantities(quantity, reqQuantity, quantityString)
    local key = handlerKey or HANDLER.QUANTITY
    local fn = ROW_SUFFIX[key] or HandlerApi.checklistRowSuffix
    return fn(row)
end

local function FormatCriterionRowSuffix(row, summary)
    if not row then return "" end
    row.descriptionTarget = row.descriptionTarget or (summary and summary.descriptionTarget)
    local fn = ROW_SUFFIX[row.handlerKey] or HandlerApi.checklistRowSuffix
    return fn(row)
end

--- Build { text, completed, linkedAchievementID? } for expandable To-Do rows.
---@param achievementID number
---@return table items
---@return table|nil summary
local function BuildAchievementCriteriaListItems(achievementID)
    local summary = SummarizeAchievementCriteria(achievementID)
    local items = {}
    if not summary or not summary.criteria then
        return items, summary
    end
    for i = 1, #summary.criteria do
        local row = summary.criteria[i]
        if row.hasName and row.name then
            local progress = FormatCriterionRowSuffix(row, summary)
            local icon = row.completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
                or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
            local item = {
                text = icon .. " " .. row.name .. progress,
                completed = row.completed,
            }
            if row.linkedAchievementID then
                item.linkedAchievementID = row.linkedAchievementID
            end
            items[#items + 1] = item
        end
    end
    return items, summary
end

-- Public API (ns)

local M = {
    CRITERIA_TYPE = CRITERIA_TYPE,
    DISPLAY_MODE = DISPLAY_MODE,
    HANDLER = HANDLER,
    TYPE_TO_HANDLER = TYPE_TO_HANDLER,
    ClassifyCriteriaHandler = ClassifyCriteriaHandler,
    FetchCriterionRow = FetchCriterionRow,
    SummarizeAchievementCriteria = SummarizeAchievementCriteria,
    FormatAchievementProgressHeader = FormatAchievementProgressHeader,
    FormatAchievementCriteriaQuantitySuffix = FormatAchievementCriteriaQuantitySuffix,
    FormatCriterionRowSuffix = FormatCriterionRowSuffix,
    BuildAchievementCriteriaListItems = BuildAchievementCriteriaListItems,
    ParseDescriptionProgressTarget = ParseDescriptionProgressTarget,
    ResolveCriteriaQuantities = ResolveCriteriaQuantities,
    FormatAchievementProgressParenthetical = FormatAchievementProgressParenthetical,
    GetAchievementTaskLabel = GetAchievementTaskLabel,
    FormatAchievementTodoSummaryLine = FormatAchievementTodoSummaryLine,
    BuildAchievementTodoSummaryLines = BuildAchievementTodoSummaryLines,
    BuildAchievementTodoSummaryFields = BuildAchievementTodoSummaryFields,
    SummaryFieldsToColoredLines = SummaryFieldsToColoredLines,
    ShouldAchievementTodoExpand = ShouldAchievementTodoExpand,
    GetAchievementDescription = GetAchievementDescription,
    GetAchievementDescriptionAndPoints = GetAchievementDescriptionAndPoints,
    GetCustomPlanBodyText = GetCustomPlanBodyText,
    BuildCustomPlanTodoSummaryLines = BuildCustomPlanTodoSummaryLines,
}

ns.AchievementCriteriaHelpers = M

-- Legacy aliases (call sites use ns.UI_*)
ns.UI_SummarizeAchievementCriteria = SummarizeAchievementCriteria
ns.UI_FormatAchievementProgressHeader = FormatAchievementProgressHeader
ns.UI_FormatCriterionRowSuffix = FormatCriterionRowSuffix
ns.UI_BuildAchievementCriteriaListItems = BuildAchievementCriteriaListItems
ns.UI_BuildAchievementTodoSummaryLines = BuildAchievementTodoSummaryLines
ns.UI_ShouldAchievementTodoExpand = ShouldAchievementTodoExpand
ns.UI_GetCustomPlanBodyText = GetCustomPlanBodyText
ns.UI_BuildCustomPlanTodoSummaryLines = BuildCustomPlanTodoSummaryLines
