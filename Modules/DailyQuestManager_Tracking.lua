--[[
    Weekly Progress plan tracking: per-category toggles + per-catalog-item selection.
    Loaded before Modules/DailyQuestManager.lua.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Catalog = ns.MidnightQuestCatalog

local DEFAULT_QUEST_TYPES = {
    weeklyQuests = true,
    worldQuests  = true,
    assignments  = true,
    dailyQuests  = true,
    events       = true,
}

local EVENT_MAIN_KEYS = {
    soiree = "event_soiree",
    abundance = "event_abundance",
    haranir = "event_haranir",
    stormarion = "event_stormarion",
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
        assignments  = (questTypes.assignments ~= false),
        dailyQuests  = (questTypes.dailyQuests ~= false),
        events       = (questTypes.events ~= false),
    }
end

--- Build default trackedCatalogKeys: core weekly objectives for enabled categories.
function WarbandNexus:BuildDefaultTrackedCatalogKeys(questTypes)
    local keys = {}
    local normalized = NormalizeQuestTypes(questTypes)
    if Catalog and Catalog.GetCoreWeeklyCatalogKeys then
        local core = Catalog.GetCoreWeeklyCatalogKeys()
        for catKey, enabled in pairs(normalized) do
            if enabled and Catalog.GetSelectableForCategory then
                local rows = Catalog.GetSelectableForCategory(catKey)
                for i = 1, #rows do
                    local row = rows[i]
                    if row and row.catalogKey and core[row.catalogKey] then
                        keys[row.catalogKey] = true
                    end
                end
            end
        end
    end
    if not next(keys) then
        return self:BuildAllAvailableTrackedCatalogKeys(questTypes)
    end
    return keys
end

--- All selectable catalog rows for enabled categories (Track all preset).
function WarbandNexus:BuildAllAvailableTrackedCatalogKeys(questTypes)
    local keys = {}
    local normalized = NormalizeQuestTypes(questTypes)
    if not Catalog or not Catalog.GetSelectableForCategory then
        return keys
    end
    for catKey, enabled in pairs(normalized) do
        if enabled then
            local rows = Catalog.GetSelectableForCategory(catKey)
            for i = 1, #rows do
                local row = rows[i]
                if row and row.catalogKey then
                    keys[row.catalogKey] = true
                end
            end
        end
    end
    return keys
end

function WarbandNexus:NormalizeTrackedCatalogKeys(plan)
    if not plan then return {} end
    plan.questTypes = NormalizeQuestTypes(plan.questTypes)
    local stored = plan.trackedCatalogKeys
    if type(stored) ~= "table" or not next(stored) then
        plan.trackedCatalogKeys = self:BuildDefaultTrackedCatalogKeys(plan.questTypes)
        return plan.trackedCatalogKeys
    end
    local out = {}
    local selectable = {}
    if Catalog and Catalog.GetSelectableForCategory then
        for catKey, enabled in pairs(plan.questTypes) do
            if enabled then
                local rows = Catalog.GetSelectableForCategory(catKey)
                for i = 1, #rows do
                    local row = rows[i]
                    if row and row.catalogKey then
                        selectable[row.catalogKey] = true
                    end
                end
            end
        end
    end
    for key, val in pairs(stored) do
        if val and selectable[key] then
            out[key] = true
        end
    end
    if not next(out) then
        out = self:BuildDefaultTrackedCatalogKeys(plan.questTypes)
    end
    plan.trackedCatalogKeys = out
    return out
end

function WarbandNexus:IsCatalogKeyTracked(plan, catalogKey)
    if not plan or not catalogKey or not plan.questTypes then return false end
    local keys = self:NormalizeTrackedCatalogKeys(plan)
    return keys[catalogKey] == true
end

--- Whether a scanned quest row should appear in Weekly Progress for this plan.
function WarbandNexus:IsWeeklyProgressQuestVisible(plan, quest, categoryKey)
    if not plan or not quest or not categoryKey then return false end
    if not plan.questTypes or not plan.questTypes[categoryKey] then return false end

    local catalogKey = quest.catalogKey
    if not catalogKey and quest.questID and Catalog and Catalog.GetLookup then
        local known = Catalog.GetLookup()[quest.questID]
        catalogKey = known and known.catalogKey
    end

    if quest.isSubQuest and quest.eventGroup then
        local mainKey = EVENT_MAIN_KEYS[quest.eventGroup]
        if mainKey then
            return self:IsCatalogKeyTracked(plan, mainKey)
        end
        return true
    end

    if catalogKey then
        return self:IsCatalogKeyTracked(plan, catalogKey)
    end

    -- Dynamic map / quest-log rows (WQ, daily, assignments): category toggle only.
    return true
end

function WarbandNexus:FilterWeeklyProgressQuestList(plan, categoryKey, questList)
    if not questList or #questList == 0 then return questList end
    if not plan then return questList end
    local out = {}
    for i = 1, #questList do
        local q = questList[i]
        if q and self:IsWeeklyProgressQuestVisible(plan, q, categoryKey) then
            out[#out + 1] = q
        end
    end
    return out
end

ns.DailyQuestManagerTracking = {
    NormalizeQuestTypes = NormalizeQuestTypes,
    DEFAULT_QUEST_TYPES = DEFAULT_QUEST_TYPES,
}
